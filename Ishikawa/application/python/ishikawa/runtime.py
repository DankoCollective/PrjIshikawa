"""Configuration-to-runtime assembly for the Ishikawa Retrieval API."""

from __future__ import annotations

import os
import re
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

from .api_contract import ApiPolicy, ApiSourceReference, validate_api_profile
from .canonical import domain_digest
from .deployment import DeploymentPolicy, PostgreSQLDeployment, validate_deployment_profile
from .document_view import NativePostgresDocumentReader
from .generation_transport import GenerationEndpoint, native_http_exchange
from .http_listener import (
    EventSink,
    ReadinessProbe,
    RetrievalHTTPServer,
    create_retrieval_http_server,
)
from .injection import InjectionPolicy, validate_injection_profile
from .method_profile import RetrievalProfile, validate_retrieval_profile
from .native_adapters import (
    EmbeddingEndpoint,
    EmbeddingExchange,
    GenerationExchange,
    NativeGenerationAdapter,
    NativeQueryEmbeddingAdapter,
    NativeScopeAdapter,
    native_embedding_exchange,
)
from .observability import LoggingPolicy, validate_logging_profile
from .postgres_retrieval import EXPECTED_RETRIEVAL_ROLE, NativePostgresRetrievalAdapter
from .query_resolution import QueryResolutionPolicy, validate_query_resolution_profile
from .query_resolution_transport import NativeQueryResolutionAdapter
from .query_routing import (
    KNOWN_DOCUMENT_ROUTING_IDENTITY,
    NativeKnownDocumentScopeRouter,
)
from .reconstruction import ReconstructionPolicy, validate_reconstruction_profile
from .relationships import RelationshipRegistry, validate_relationship_registry
from .relevance import RelevancePolicy, validate_relevance_profile
from .retrieval_service import (
    RetrievalDependencyUnavailable,
    RetrievalServiceContractError,
    RetrievalServiceExecution,
    RetrievalServicePolicy,
    RetrievalServicePorts,
    orchestrate_chat,
    validate_retrieval_service_profile,
)
from .scope import ScopePolicy, validate_scope_profile
from .sufficiency import SufficiencyPolicy, validate_sufficiency_profile
from .tokenization import (
    NativeGenerationTokenCounter,
    TokenizationEndpoint,
    TokenizationExchange,
    native_tokenization_exchange,
)
from .yaml_loader import load_restricted_yaml


_ENVIRONMENT_NAME = re.compile(r"^[A-Z][A-Z0-9_]{0,63}$")
_DATABASE_NAME = re.compile(r"^[a-z][a-z0-9_]{0,62}$")


class RuntimeConfigurationError(ValueError):
    """Raised when deployment configuration cannot form the qualified runtime."""


def _mapping(value: Any, fields: frozenset[str], label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != fields:
        raise RuntimeConfigurationError(f"{label} fields are invalid")
    return value


def _bounded_integer(value: Any, minimum: int, maximum: int, label: str) -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        raise RuntimeConfigurationError(f"{label} is invalid")
    return value


def _environment_name(value: Any, expected: str, label: str) -> str:
    if not isinstance(value, str) or _ENVIRONMENT_NAME.fullmatch(value) is None or value != expected:
        raise RuntimeConfigurationError(f"{label} is invalid")
    return value


def _health_endpoint_url(value: Any, service_url: str, label: str) -> str:
    if not isinstance(value, str) or value != value.strip():
        raise RuntimeConfigurationError(f"{label} is invalid")
    health = urlsplit(value)
    service = urlsplit(service_url)
    try:
        health_port = health.port
        service_port = service.port
    except ValueError as error:
        raise RuntimeConfigurationError(f"{label} is invalid") from error
    if (
        health.scheme not in {"http", "https"}
        or health.scheme != service.scheme
        or health.hostname != service.hostname
        or health_port is None
        or health_port != service_port
        or health.username is not None
        or health.password is not None
        or health.query
        or health.fragment
        or health.path != "/health"
    ):
        raise RuntimeConfigurationError(f"{label} is invalid")
    return value


@dataclass(frozen=True, slots=True)
class RuntimeDependencyPolicy:
    generation_endpoint: GenerationEndpoint
    tokenization_endpoint: TokenizationEndpoint
    generation_health_endpoint_url: str
    generation_credential_environment: str
    embedding_endpoint: EmbeddingEndpoint
    embedding_health_endpoint_url: str
    embedding_credential_environment: str
    database_name: str
    database_user: str
    database_credential_environment: str
    database_connect_timeout_seconds: int
    digest: str


def validate_runtime_dependencies(value: Any) -> RuntimeDependencyPolicy:
    root = _mapping(
        value,
        frozenset({"schema_version", "gemma", "nomic", "postgresql"}),
        "runtime dependencies",
    )
    if root["schema_version"] != 1 or type(root["schema_version"]) is not int:
        raise RuntimeConfigurationError("runtime dependency version is invalid")
    gemma = _mapping(
        root["gemma"],
        frozenset(
            {
                "chat_endpoint_url",
                "tokenization_endpoint_url",
                "health_endpoint_url",
                "credential_environment",
                "timeout_seconds",
                "maximum_response_bytes",
            }
        ),
        "Gemma dependency",
    )
    nomic = _mapping(
        root["nomic"],
        frozenset(
            {
                "embedding_endpoint_url",
                "health_endpoint_url",
                "credential_environment",
                "timeout_seconds",
                "maximum_response_bytes",
            }
        ),
        "Nomic dependency",
    )
    postgresql = _mapping(
        root["postgresql"],
        frozenset(
            {"database_name", "database_user", "credential_environment", "connect_timeout_seconds"}
        ),
        "PostgreSQL dependency",
    )
    try:
        generation_endpoint = GenerationEndpoint(
            gemma["chat_endpoint_url"],
            _bounded_integer(gemma["timeout_seconds"], 1, 900, "Gemma timeout"),
            _bounded_integer(
                gemma["maximum_response_bytes"], 1024, 16 * 1024 * 1024,
                "Gemma response limit",
            ),
        )
        tokenization_endpoint = TokenizationEndpoint(
            gemma["tokenization_endpoint_url"],
            _bounded_integer(gemma["timeout_seconds"], 1, 300, "Gemma timeout"),
            _bounded_integer(
                gemma["maximum_response_bytes"], 65536, 8 * 1024 * 1024,
                "Gemma response limit",
            ),
        )
        embedding_endpoint = EmbeddingEndpoint(
            nomic["embedding_endpoint_url"],
            _bounded_integer(nomic["timeout_seconds"], 1, 300, "Nomic timeout"),
            _bounded_integer(
                nomic["maximum_response_bytes"], 65536, 4 * 1024 * 1024,
                "Nomic response limit",
            ),
        )
    except Exception as error:
        raise RuntimeConfigurationError("runtime endpoint is invalid") from error
    database_name = postgresql["database_name"]
    database_user = postgresql["database_user"]
    if (
        not isinstance(database_name, str)
        or _DATABASE_NAME.fullmatch(database_name) is None
        or database_name != "rag_catalog"
        or database_user != EXPECTED_RETRIEVAL_ROLE
    ):
        raise RuntimeConfigurationError("PostgreSQL identity is invalid")
    generation_environment = _environment_name(
        gemma["credential_environment"], "ISHIKAWA_GEMMA_API_KEY", "Gemma credential environment"
    )
    embedding_environment = _environment_name(
        nomic["credential_environment"], "ISHIKAWA_NOMIC_API_KEY", "Nomic credential environment"
    )
    database_environment = _environment_name(
        postgresql["credential_environment"],
        "ISHIKAWA_POSTGRESQL_PASSWORD",
        "PostgreSQL credential environment",
    )
    connect_timeout = _bounded_integer(
        postgresql["connect_timeout_seconds"], 1, 60, "PostgreSQL connect timeout"
    )
    generation_health_url = _health_endpoint_url(
        gemma["health_endpoint_url"],
        gemma["chat_endpoint_url"],
        "Gemma health endpoint",
    )
    embedding_health_url = _health_endpoint_url(
        nomic["health_endpoint_url"],
        nomic["embedding_endpoint_url"],
        "Nomic health endpoint",
    )
    canonical = {
        "gemma": dict(gemma),
        "nomic": dict(nomic),
        "postgresql": dict(postgresql),
        "schema_version": 1,
    }
    return RuntimeDependencyPolicy(
        generation_endpoint,
        tokenization_endpoint,
        generation_health_url,
        generation_environment,
        embedding_endpoint,
        embedding_health_url,
        embedding_environment,
        database_name,
        database_user,
        database_environment,
        connect_timeout,
        domain_digest("ishikawa.runtime-dependencies.v1", canonical),
    )


@dataclass(frozen=True, slots=True)
class ProtectedEnvironmentValue:
    name: str
    environment: Mapping[str, str]

    def __post_init__(self) -> None:
        if _ENVIRONMENT_NAME.fullmatch(self.name or "") is None or not isinstance(
            self.environment, Mapping
        ):
            raise RuntimeConfigurationError("protected environment provider is invalid")

    def __call__(self) -> str:
        try:
            value = self.environment[self.name]
        except (KeyError, TypeError) as error:
            raise RetrievalDependencyUnavailable("runtime_credential_unavailable") from error
        if (
            not isinstance(value, str)
            or not value
            or value != value.strip()
            or len(value) > 16384
            or "\x00" in value
            or "\r" in value
            or "\n" in value
        ):
            raise RetrievalDependencyUnavailable("runtime_credential_unavailable")
        return value


DatabaseConnector = Callable[..., Any]


def native_psycopg_connect(**parameters: Any) -> Any:
    try:
        import psycopg
    except ImportError as error:
        raise RetrievalDependencyUnavailable("postgresql_driver_unavailable") from error
    try:
        return psycopg.connect(**parameters)
    except Exception as error:
        raise RetrievalDependencyUnavailable("postgresql_connection_failed") from error


@dataclass(frozen=True, slots=True)
class NativePostgresConnectionFactory:
    deployment: PostgreSQLDeployment
    dependency_policy: RuntimeDependencyPolicy
    password_provider: ProtectedEnvironmentValue
    connector: DatabaseConnector = native_psycopg_connect

    def __post_init__(self) -> None:
        if not callable(self.connector):
            raise RuntimeConfigurationError("PostgreSQL connector is invalid")

    def __call__(self) -> Any:
        try:
            return self.connector(
                host=self.deployment.bind_host,
                port=self.deployment.port,
                dbname=self.dependency_policy.database_name,
                user=self.dependency_policy.database_user,
                password=self.password_provider(),
                connect_timeout=self.dependency_policy.database_connect_timeout_seconds,
                application_name="ishikawa-retrieval-api",
                options="-c default_transaction_read_only=on",
            )
        except RetrievalDependencyUnavailable:
            raise
        except Exception as error:
            raise RetrievalDependencyUnavailable("postgresql_connection_failed") from error


@dataclass(frozen=True, slots=True)
class NativeSourceDisplayNameResolver:
    connection_factory: Callable[[], Any]
    expected_database_role: str = EXPECTED_RETRIEVAL_ROLE

    def __call__(self, reference: ApiSourceReference) -> str:
        if not isinstance(reference, ApiSourceReference):
            raise RetrievalServiceContractError("source reference is invalid")
        connection = None
        try:
            connection = self.connection_factory()
            connection.execute(
                """/* ishikawa.source-name.begin */
                BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY
                """
            )
            boundary = connection.execute(
                """/* ishikawa.source-name.boundary */
                SELECT current_user,
                       current_setting('transaction_read_only'),
                       current_setting('transaction_isolation')
                """
            ).fetchone()
            if boundary != (self.expected_database_role, "on", "repeatable read"):
                raise RetrievalServiceContractError("source resolver database boundary is invalid")
            if reference.citation_id is None:
                rows = connection.execute(
                    """/* ishikawa.source-name.document */
                    SELECT display_name
                    FROM rag_search.active_documents
                    WHERE document_version_id = %s
                    """,
                    (reference.source_id,),
                ).fetchall()
            else:
                rows = connection.execute(
                    """/* ishikawa.source-name.citation */
                    SELECT DISTINCT ad.display_name
                    FROM rag_search.active_documents ad
                    JOIN rag_search.active_citations citation
                      ON citation.document_version_id = ad.document_version_id
                    WHERE ad.document_version_id = %s
                      AND citation.citation_id = %s
                    """,
                    (reference.source_id, reference.citation_id),
                ).fetchall()
            if len(rows) != 1:
                raise RetrievalDependencyUnavailable("source_reference_unavailable")
            name = rows[0][0] if isinstance(rows[0], (tuple, list)) and len(rows[0]) == 1 else None
            if (
                not isinstance(name, str)
                or not name.strip()
                or name != name.strip()
                or len(name) > 512
                or "\x00" in name
            ):
                raise RetrievalServiceContractError("source display name is invalid")
            return name
        except (RetrievalDependencyUnavailable, RetrievalServiceContractError):
            raise
        except Exception as error:
            raise RetrievalDependencyUnavailable("source_reference_lookup_failed") from error
        finally:
            if connection is not None:
                try:
                    connection.rollback()
                except Exception:
                    pass
                try:
                    connection.close()
                except Exception:
                    pass


@dataclass(frozen=True, slots=True)
class RuntimePolicies:
    api: ApiPolicy
    deployment: DeploymentPolicy
    service: RetrievalServicePolicy
    injection: InjectionPolicy
    scope: ScopePolicy
    query_resolution: QueryResolutionPolicy
    retrieval: RetrievalProfile
    reconstruction: ReconstructionPolicy
    relevance: RelevancePolicy
    sufficiency: SufficiencyPolicy
    relationships: RelationshipRegistry
    logging: LoggingPolicy
    dependencies: RuntimeDependencyPolicy
    known_document_routing_identity: str
    digest: str


@dataclass(frozen=True, slots=True)
class ConfiguredRetrievalRuntime:
    policies: RuntimePolicies
    ports: RetrievalServicePorts
    executor: Callable[[Any, str], RetrievalServiceExecution]
    document_reader: NativePostgresDocumentReader
    query_embedder: NativeQueryEmbeddingAdapter

    def create_http_server(
        self,
        *,
        event_sink: EventSink | None = None,
        readiness_probe: ReadinessProbe | None = None,
    ) -> RetrievalHTTPServer:
        return create_retrieval_http_server(
            self.policies.deployment.retrieval,
            self.policies.api,
            self.executor,
            event_sink=event_sink,
            readiness_probe=readiness_probe,
            document_reader=self.document_reader,
        )


def _load(config_root: Path, filename: str, label: str) -> Any:
    path = config_root / filename
    if not path.is_file() or path.is_symlink():
        raise RuntimeConfigurationError(f"{label} is missing or unsafe")
    return load_restricted_yaml(path, label=label)


def assemble_configured_retrieval_runtime(
    config_root: str | Path,
    *,
    environment: Mapping[str, str] = os.environ,
    database_connector: DatabaseConnector = native_psycopg_connect,
    generation_exchange: GenerationExchange = native_http_exchange,
    embedding_exchange: EmbeddingExchange = native_embedding_exchange,
    tokenization_exchange: TokenizationExchange = native_tokenization_exchange,
) -> ConfiguredRetrievalRuntime:
    """Load every accepted profile and wire the concrete runtime without starting it."""

    root = Path(config_root)
    api = validate_api_profile(_load(root, "api_profile.yaml", "API profile"))
    deployment = validate_deployment_profile(
        _load(root, "deployment.yaml", "deployment profile")
    )
    service = validate_retrieval_service_profile(
        _load(root, "retrieval_service_profile.yaml", "retrieval service profile")
    )
    injection = validate_injection_profile(
        _load(root, "injection_profile.yaml", "injection profile")
    )
    scope = validate_scope_profile(_load(root, "scope_profile.yaml", "scope profile"))
    query_resolution = validate_query_resolution_profile(
        _load(root, "query_resolution_profile.yaml", "query-resolution profile")
    )
    retrieval = validate_retrieval_profile(
        _load(root, "method_profile.yaml", "retrieval profile")
    )
    reconstruction = validate_reconstruction_profile(
        _load(root, "reconstruction_profile.yaml", "reconstruction profile")
    )
    relevance = validate_relevance_profile(
        _load(root, "relevance_profile.yaml", "relevance profile")
    )
    sufficiency = validate_sufficiency_profile(
        _load(root, "sufficiency_profile.yaml", "sufficiency profile")
    )
    relationships = validate_relationship_registry(
        _load(root, "relationship_types.yaml", "relationship registry")
    )
    logging = validate_logging_profile(
        _load(root, "logging_profile.yaml", "logging profile")
    )
    dependencies = validate_runtime_dependencies(
        _load(root, "runtime_dependencies.yaml", "runtime dependency profile")
    )
    if (
        service.default_bind_address != deployment.retrieval.bind_host
        or service.default_port != deployment.retrieval.port
        or scope.served_model != query_resolution.served_model
        or scope.served_model != reconstruction.tokenizer_model
    ):
        raise RuntimeConfigurationError("runtime profiles are not coherent")

    gemma_credential = ProtectedEnvironmentValue(
        dependencies.generation_credential_environment, environment
    )
    nomic_credential = ProtectedEnvironmentValue(
        dependencies.embedding_credential_environment, environment
    )
    database_credential = ProtectedEnvironmentValue(
        dependencies.database_credential_environment, environment
    )
    connection_factory = NativePostgresConnectionFactory(
        deployment.postgresql,
        dependencies,
        database_credential,
        database_connector,
    )
    source_resolver = NativeSourceDisplayNameResolver(connection_factory)
    known_document_router = NativeKnownDocumentScopeRouter(connection_factory)
    query_embedder = NativeQueryEmbeddingAdapter(
        dependencies.embedding_endpoint,
        nomic_credential,
        embedding_exchange,
    )
    token_counter = NativeGenerationTokenCounter(
        dependencies.tokenization_endpoint,
        reconstruction.tokenizer_model,
        reconstruction.total_context_tokens,
        gemma_credential,
        tokenization_exchange,
    )
    ports = RetrievalServicePorts(
        NativeScopeAdapter(
            dependencies.generation_endpoint,
            scope,
            gemma_credential,
            source_resolver,
            generation_exchange,
            known_document_router,
        ),
        NativeQueryResolutionAdapter(
            dependencies.generation_endpoint,
            query_resolution,
            gemma_credential,
            source_resolver,
            generation_exchange,
            known_document_router.resolve_query,
        ),
        NativePostgresRetrievalAdapter(
            connection_factory,
            query_embedder,
            token_counter,
            token_counter.count_messages,
            retrieval,
            reconstruction,
            relevance,
            sufficiency,
            relationships,
        ),
        NativeGenerationAdapter(
            dependencies.generation_endpoint,
            reconstruction,
            gemma_credential,
            generation_exchange,
        ),
    )
    policy_digest = domain_digest(
        "ishikawa.configured-retrieval-runtime.v1",
        {
            "api": api.digest,
            "dependencies": dependencies.digest,
            "deployment": deployment.digest,
            "injection": injection.digest,
            "logging": logging.digest,
            "known_document_routing": KNOWN_DOCUMENT_ROUTING_IDENTITY,
            "query_resolution": query_resolution.digest,
            "reconstruction": reconstruction.digest,
            "relationships": relationships.digest,
            "relevance": relevance.digest,
            "retrieval": retrieval.digest,
            "scope": scope.digest,
            "service": service.digest,
            "sufficiency": sufficiency.digest,
        },
    )
    policies = RuntimePolicies(
        api,
        deployment,
        service,
        injection,
        scope,
        query_resolution,
        retrieval,
        reconstruction,
        relevance,
        sufficiency,
        relationships,
        logging,
        dependencies,
        KNOWN_DOCUMENT_ROUTING_IDENTITY,
        policy_digest,
    )

    def execute(request: Any, request_id: str) -> RetrievalServiceExecution:
        return orchestrate_chat(
            request=request,
            request_id=request_id,
            api_policy=api,
            injection_policy=injection,
            service_policy=service,
            ports=ports,
        )

    return ConfiguredRetrievalRuntime(
        policies,
        ports,
        execute,
        NativePostgresDocumentReader(connection_factory),
        query_embedder,
    )

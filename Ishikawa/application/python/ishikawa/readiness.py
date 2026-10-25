"""Concrete fail-closed readiness checks for the Ishikawa Retrieval API.

The probe verifies immutable runtime configuration, protected local storage,
the read-only active PostgreSQL corpus, and the configured Gemma and Nomic
health endpoints. It returns only one boolean to the HTTP boundary; component
details remain internal and contain no credentials, paths, or response bodies.
"""

from __future__ import annotations

import hashlib
import http.client
import os
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path
from threading import Lock
from urllib.parse import urlsplit

from .native_adapters import ValidatedQueryEmbedding
from .runtime import (
    ConfiguredRetrievalRuntime,
    NativePostgresConnectionFactory,
    ProtectedEnvironmentValue,
)


REQUIRED_RUNTIME_CONFIGURATION = (
    "api_profile.yaml",
    "deployment.yaml",
    "injection_profile.yaml",
    "logging_profile.yaml",
    "method_profile.yaml",
    "query_resolution_profile.yaml",
    "reconstruction_profile.yaml",
    "relationship_types.yaml",
    "relevance_profile.yaml",
    "retrieval_service_profile.yaml",
    "runtime_dependencies.yaml",
    "scope_profile.yaml",
    "sufficiency_profile.yaml",
)


class ReadinessContractError(ValueError):
    """Raised when readiness configuration leaves the accepted boundary."""


@dataclass(frozen=True, slots=True)
class HealthEndpoint:
    scheme: str
    host: str
    port: int
    path: str
    timeout_seconds: int
    maximum_response_bytes: int

    @classmethod
    def from_url(
        cls,
        url: str,
        *,
        timeout_seconds: int,
        maximum_response_bytes: int = 65536,
    ) -> "HealthEndpoint":
        if not isinstance(url, str) or url != url.strip():
            raise ReadinessContractError("health endpoint URL is invalid")
        parsed = urlsplit(url)
        try:
            port = parsed.port
        except ValueError as error:
            raise ReadinessContractError("health endpoint URL is invalid") from error
        if (
            parsed.scheme not in {"http", "https"}
            or not parsed.hostname
            or parsed.username is not None
            or parsed.password is not None
            or parsed.query
            or parsed.fragment
            or parsed.path != "/health"
            or port is None
            or not 1 <= port <= 65535
            or type(timeout_seconds) is not int
            or not 1 <= timeout_seconds <= 300
            or type(maximum_response_bytes) is not int
            or not 1024 <= maximum_response_bytes <= 1024 * 1024
        ):
            raise ReadinessContractError("health endpoint URL is invalid")
        return cls(
            parsed.scheme,
            parsed.hostname,
            port,
            "/health",
            timeout_seconds,
            maximum_response_bytes,
        )


@dataclass(frozen=True, slots=True)
class PreparedHealthRequest:
    endpoint: HealthEndpoint
    headers: Mapping[str, str]


@dataclass(frozen=True, slots=True)
class HealthHTTPResponse:
    status: int
    body_size: int


HealthExchange = Callable[[PreparedHealthRequest], HealthHTTPResponse]


def prepare_health_request(endpoint: HealthEndpoint, api_key: str) -> PreparedHealthRequest:
    """Create one bounded authenticated request without placing a key in the URL."""

    if not isinstance(endpoint, HealthEndpoint):
        raise ReadinessContractError("health endpoint is invalid")
    if (
        not isinstance(api_key, str)
        or not api_key
        or api_key != api_key.strip()
        or "\x00" in api_key
        or "\r" in api_key
        or "\n" in api_key
        or len(api_key) > 16384
    ):
        raise ReadinessContractError("health credential is invalid")
    return PreparedHealthRequest(
        endpoint,
        {
            "Accept": "application/json",
            "Authorization": f"Bearer {api_key}",
            "Connection": "close",
        },
    )


def native_health_exchange(request: PreparedHealthRequest) -> HealthHTTPResponse:
    """Perform one standard-library health exchange and retain no response body."""

    if not isinstance(request, PreparedHealthRequest):
        raise ReadinessContractError("prepared health request is invalid")
    endpoint = request.endpoint
    connection_type = (
        http.client.HTTPSConnection
        if endpoint.scheme == "https"
        else http.client.HTTPConnection
    )
    connection = connection_type(
        endpoint.host,
        endpoint.port,
        timeout=endpoint.timeout_seconds,
    )
    try:
        connection.request("GET", endpoint.path, headers=dict(request.headers))
        response = connection.getresponse()
        body = response.read(endpoint.maximum_response_bytes + 1)
        if len(body) > endpoint.maximum_response_bytes:
            raise ReadinessContractError("health response exceeds the accepted size")
        return HealthHTTPResponse(response.status, len(body))
    finally:
        connection.close()


@dataclass(frozen=True, slots=True)
class NativeHealthProbe:
    endpoint: HealthEndpoint
    credential_provider: Callable[[], str]
    exchange: HealthExchange = native_health_exchange

    def __call__(self) -> bool:
        try:
            response = self.exchange(
                prepare_health_request(self.endpoint, self.credential_provider())
            )
            return isinstance(response, HealthHTTPResponse) and response.status == 200
        except Exception:
            return False


class WarmedNomicProbe:
    """Require Nomic health and complete one real query warmup per process."""

    def __init__(
        self,
        health_probe: Callable[[], bool],
        query_embedder: Callable[[str], ValidatedQueryEmbedding],
    ) -> None:
        if not callable(health_probe) or not callable(query_embedder):
            raise ReadinessContractError("Nomic warmup probe is invalid")
        self.health_probe = health_probe
        self.query_embedder = query_embedder
        self._lock = Lock()
        self._warmed = False

    def __call__(self) -> bool:
        try:
            if self.health_probe() is not True:
                return False
            with self._lock:
                if self._warmed:
                    return True
                embedding = self.query_embedder("Ishikawa readiness warmup")
                if not isinstance(embedding, ValidatedQueryEmbedding):
                    return False
                self._warmed = True
                return True
        except Exception:
            return False


@dataclass(frozen=True, slots=True)
class ConfigurationSnapshotProbe:
    entries: tuple[tuple[Path, str], ...]

    def __call__(self) -> bool:
        try:
            for path, expected_digest in self.entries:
                if not path.is_file() or path.is_symlink():
                    return False
                if hashlib.sha256(path.read_bytes()).hexdigest() != expected_digest:
                    return False
            return True
        except OSError:
            return False


@dataclass(frozen=True, slots=True)
class ProtectedStorageProbe:
    directories: tuple[Path, ...]

    def __call__(self) -> bool:
        try:
            return all(
                directory.is_dir()
                and not directory.is_symlink()
                and os.access(directory, os.R_OK | os.W_OK | os.X_OK)
                for directory in self.directories
            )
        except OSError:
            return False


@dataclass(frozen=True, slots=True)
class ActiveCorpusProbe:
    connection_factory: Callable[[], object]

    def __call__(self) -> bool:
        connection = None
        try:
            connection = self.connection_factory()
            result = connection.execute(
                """/* ishikawa.readiness.active-corpus.v1 */
                SELECT
                  current_user::text,
                  current_setting('transaction_read_only')::text,
                  EXISTS (SELECT 1 FROM rag_search.active_chunks LIMIT 1)
                """
            ).fetchone()
            return result == ("rag_retrieval", "on", True)
        except Exception:
            return False
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
class ConfiguredReadinessProbe:
    configuration_probe: Callable[[], bool]
    storage_probe: Callable[[], bool]
    database_probe: Callable[[], bool]
    gemma_probe: Callable[[], bool]
    nomic_probe: Callable[[], bool]

    def inspect(self) -> ReadinessInspection:
        """Inspect every component and return only content-free component states."""

        results = []
        for name, probe in (
            ("configuration", self.configuration_probe),
            ("storage", self.storage_probe),
            ("postgresql", self.database_probe),
            ("gemma", self.gemma_probe),
            ("nomic", self.nomic_probe),
        ):
            try:
                passed = probe() is True
            except Exception:
                passed = False
            results.append((name, passed))
        return ReadinessInspection(tuple(results))

    def __call__(self) -> bool:
        """Require every component without exposing component state over HTTP."""

        return self.inspect().ready

    def inspect_dependencies(self) -> tuple[tuple[str, bool], ...]:
        """Probe only the two model services needed by the local UI indicator."""

        results = []
        for name, probe in (("gemma", self.gemma_probe), ("nomic", self.nomic_probe)):
            try:
                passed = probe() is True
            except Exception:
                passed = False
            results.append((name, passed))
        return tuple(results)


@dataclass(frozen=True, slots=True)
class ReadinessInspection:
    """Content-free readiness result intended for the local operator command."""

    components: tuple[tuple[str, bool], ...]

    def __post_init__(self) -> None:
        expected = ("configuration", "storage", "postgresql", "gemma", "nomic")
        if tuple(name for name, _passed in self.components) != expected or any(
            type(passed) is not bool for _name, passed in self.components
        ):
            raise ReadinessContractError("readiness inspection is invalid")

    @property
    def ready(self) -> bool:
        return all(passed for _name, passed in self.components)

    def marker(self) -> str:
        state = "pass" if self.ready else "blocked"
        component_states = ";".join(
            f"{name}={'pass' if passed else 'blocked'}"
            for name, passed in self.components
        )
        return f"ishikawa_retrieval_api_readiness={state};{component_states}"


def _configuration_snapshot(config_root: Path) -> ConfigurationSnapshotProbe:
    entries = []
    for filename in REQUIRED_RUNTIME_CONFIGURATION:
        path = config_root / filename
        if not path.is_file() or path.is_symlink():
            raise ReadinessContractError("required readiness configuration is unsafe")
        entries.append((path, hashlib.sha256(path.read_bytes()).hexdigest()))
    return ConfigurationSnapshotProbe(tuple(entries))


def assemble_configured_readiness_probe(
    product_root: str | Path,
    runtime: ConfiguredRetrievalRuntime,
    *,
    environment: Mapping[str, str] = os.environ,
    database_connector: Callable[..., object] | None = None,
    health_exchange: HealthExchange = native_health_exchange,
) -> ConfiguredReadinessProbe:
    """Assemble lazy concrete probes without reading credentials or contacting dependencies."""

    if not isinstance(runtime, ConfiguredRetrievalRuntime):
        raise ReadinessContractError("configured runtime is invalid")
    root = Path(product_root).resolve(strict=True)
    config_root = root / "config"
    state_root = root / "state"
    logs_root = state_root / "logs"
    run_root = state_root / "run"
    if not config_root.is_dir() or config_root.is_symlink():
        raise ReadinessContractError("configuration root is unsafe")
    if not state_root.is_dir() or state_root.is_symlink():
        raise ReadinessContractError("state root is unsafe")
    if not logs_root.is_dir() or logs_root.is_symlink():
        raise ReadinessContractError("log root is unsafe")
    if not run_root.is_dir() or run_root.is_symlink():
        raise ReadinessContractError("runtime control root is unsafe")

    dependencies = runtime.policies.dependencies
    database_credential = ProtectedEnvironmentValue(
        dependencies.database_credential_environment,
        environment,
    )
    connection_arguments = (
        runtime.policies.deployment.postgresql,
        dependencies,
        database_credential,
    )
    connection_factory = (
        NativePostgresConnectionFactory(*connection_arguments)
        if database_connector is None
        else NativePostgresConnectionFactory(
            *connection_arguments,
            connector=database_connector,
        )
    )
    gemma_endpoint = HealthEndpoint.from_url(
        dependencies.generation_health_endpoint_url,
        timeout_seconds=dependencies.generation_endpoint.timeout_seconds,
    )
    nomic_endpoint = HealthEndpoint.from_url(
        dependencies.embedding_health_endpoint_url,
        timeout_seconds=dependencies.embedding_endpoint.timeout_seconds,
    )
    return ConfiguredReadinessProbe(
        _configuration_snapshot(config_root),
        ProtectedStorageProbe((state_root, logs_root, run_root)),
        ActiveCorpusProbe(connection_factory),
        NativeHealthProbe(
            gemma_endpoint,
            ProtectedEnvironmentValue(
                dependencies.generation_credential_environment,
                environment,
            ),
            health_exchange,
        ),
        WarmedNomicProbe(
            NativeHealthProbe(
                nomic_endpoint,
                ProtectedEnvironmentValue(
                    dependencies.embedding_credential_environment,
                    environment,
                ),
                health_exchange,
            ),
            runtime.query_embedder,
        ),
    )

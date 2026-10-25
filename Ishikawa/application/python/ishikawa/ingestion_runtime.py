"""Configuration-to-runtime assembly for operator-invoked ingestion."""

from __future__ import annotations

import os
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, TextIO

from .canonical import domain_digest
from .deployment import PostgreSQLDeployment, validate_deployment_profile
from .document_producer import (
    ArtifactRetainer,
    ArtifactStage,
    METHOD_PROFILE_ID,
    NativeDocumentProducer,
)
from .ingestion_command import IngestionCommandPorts, execute_ingestion_command
from .models import IngestionManifest
from .native_adapters import EmbeddingEndpoint, NOMIC_MODEL
from .operator_ingestion import OperatorIngestionPaths, load_operator_configuration
from .relationships import validate_relationship_registry
from .runtime import ProtectedEnvironmentValue, native_psycopg_connect
from .tokenization import TokenizationEndpoint
from .yaml_loader import load_restricted_yaml


EXPECTED_INGESTION_ROLE = "rag_ingest"
_DATABASE_NAME = "rag_catalog"
_NOMIC_ENVIRONMENT = "ISHIKAWA_NOMIC_API_KEY"
_DATABASE_ENVIRONMENT = "ISHIKAWA_POSTGRESQL_INGEST_PASSWORD"


class IngestionRuntimeConfigurationError(ValueError):
    """Stable configuration failure for the ingestion runtime."""


def _mapping(value: Any, fields: frozenset[str], label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != fields:
        raise IngestionRuntimeConfigurationError(f"{label}_fields_invalid")
    return value


def _integer(value: Any, minimum: int, maximum: int, label: str) -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        raise IngestionRuntimeConfigurationError(f"{label}_invalid")
    return value


@dataclass(frozen=True, slots=True)
class IngestionDependencyPolicy:
    """Validated locations and protected-environment names, never secrets."""

    served_model: str
    embedding_endpoint: EmbeddingEndpoint
    tokenization_endpoint: TokenizationEndpoint
    nomic_credential_environment: str
    embedding_batch_size: int
    database_name: str
    database_user: str
    database_credential_environment: str
    database_connect_timeout_seconds: int
    digest: str


def validate_ingestion_dependencies(value: Any) -> IngestionDependencyPolicy:
    root = _mapping(
        value,
        frozenset({"schema_version", "nomic", "postgresql"}),
        "ingestion_dependencies",
    )
    if type(root["schema_version"]) is not int or root["schema_version"] != 1:
        raise IngestionRuntimeConfigurationError("ingestion_dependency_version_invalid")
    nomic = _mapping(
        root["nomic"],
        frozenset(
            {
                "served_model",
                "embedding_endpoint_url",
                "tokenization_endpoint_url",
                "credential_environment",
                "timeout_seconds",
                "maximum_response_bytes",
                "batch_size",
            }
        ),
        "nomic_dependency",
    )
    postgresql = _mapping(
        root["postgresql"],
        frozenset(
            {"database_name", "database_user", "credential_environment", "connect_timeout_seconds"}
        ),
        "postgresql_dependency",
    )
    if (
        nomic["served_model"] != NOMIC_MODEL
        or nomic["credential_environment"] != _NOMIC_ENVIRONMENT
        or postgresql["database_name"] != _DATABASE_NAME
        or postgresql["database_user"] != EXPECTED_INGESTION_ROLE
        or postgresql["credential_environment"] != _DATABASE_ENVIRONMENT
    ):
        raise IngestionRuntimeConfigurationError("ingestion_dependency_identity_invalid")
    timeout = _integer(nomic["timeout_seconds"], 1, 300, "nomic_timeout")
    response_limit = _integer(
        nomic["maximum_response_bytes"], 65536, 4 * 1024 * 1024, "nomic_response_limit"
    )
    batch_size = _integer(nomic["batch_size"], 1, 64, "nomic_batch_size")
    connect_timeout = _integer(
        postgresql["connect_timeout_seconds"], 1, 60, "postgresql_connect_timeout"
    )
    try:
        embedding_endpoint = EmbeddingEndpoint(
            nomic["embedding_endpoint_url"], timeout, response_limit
        )
        tokenization_endpoint = TokenizationEndpoint(
            nomic["tokenization_endpoint_url"], timeout, response_limit
        )
    except Exception as error:
        raise IngestionRuntimeConfigurationError("nomic_endpoint_invalid") from error
    canonical = {
        "nomic": dict(nomic),
        "postgresql": dict(postgresql),
        "schema_version": 1,
    }
    return IngestionDependencyPolicy(
        NOMIC_MODEL,
        embedding_endpoint,
        tokenization_endpoint,
        _NOMIC_ENVIRONMENT,
        batch_size,
        _DATABASE_NAME,
        EXPECTED_INGESTION_ROLE,
        _DATABASE_ENVIRONMENT,
        connect_timeout,
        domain_digest("ishikawa.ingestion-dependencies.v1", canonical),
    )


DatabaseConnector = Callable[..., Any]
ArtifactStageFactory = Callable[
    [IngestionDependencyPolicy, ProtectedEnvironmentValue], ArtifactStage
]


@dataclass(frozen=True, slots=True)
class NativeIngestionConnectionFactory:
    deployment: PostgreSQLDeployment
    dependency_policy: IngestionDependencyPolicy
    password_provider: ProtectedEnvironmentValue
    connector: DatabaseConnector = native_psycopg_connect

    def __post_init__(self) -> None:
        if not callable(self.connector):
            raise IngestionRuntimeConfigurationError("postgresql_connector_invalid")

    def __call__(self) -> Any:
        return self.connector(
            host=self.deployment.bind_host,
            port=self.deployment.port,
            dbname=self.dependency_policy.database_name,
            user=self.dependency_policy.database_user,
            password=self.password_provider(),
            connect_timeout=self.dependency_policy.database_connect_timeout_seconds,
            application_name="ishikawa-ingestion",
            autocommit=True,
        )


@dataclass(frozen=True, slots=True)
class IngestionRuntimePolicy:
    dependencies: IngestionDependencyPolicy
    deployment_digest: str
    registry_digest: str
    relationship_registry_digest: str
    catalog_digest: str
    manifest_digest: str
    method_profile_id: str
    digest: str


@dataclass(frozen=True, slots=True)
class ConfiguredIngestionRuntime:
    """Exact operator paths plus lazy concrete runtime ports."""

    paths: OperatorIngestionPaths
    policy: IngestionRuntimePolicy
    ports: IngestionCommandPorts

    def execute(self, mode: str, *, output: TextIO) -> int:
        if mode not in {"validate-only", "publish"}:
            raise IngestionRuntimeConfigurationError("ingestion_mode_invalid")
        values: Sequence[str] = (
            f"--{mode}",
            "--class-registry", str(self.paths.class_registry),
            "--document-catalog", str(self.paths.document_catalog),
            "--ingestion-manifest", str(self.paths.ingestion_manifest),
            "--source-root", str(self.paths.source_root),
            "--report-root", str(self.paths.report_root),
        )
        return execute_ingestion_command(values, ports=self.ports, output=output)


def _load(root: Path, filename: str, label: str) -> Any:
    path = root / filename
    if not path.is_file() or path.is_symlink():
        raise IngestionRuntimeConfigurationError(f"{label}_missing_or_unsafe")
    return load_restricted_yaml(path, label=label)


def _safe_directory(path: Path, label: str) -> Path:
    if not path.is_absolute() or path.is_symlink() or not path.is_dir():
        raise IngestionRuntimeConfigurationError(f"{label}_unsafe")
    return path.resolve(strict=True)


def assemble_configured_ingestion_runtime(
    paths: OperatorIngestionPaths,
    *,
    runtime_config_root: str | Path,
    work_root: str | Path,
    artifact_stage_factory: ArtifactStageFactory,
    artifact_retainer: ArtifactRetainer,
    environment: Mapping[str, str] = os.environ,
    database_connector: DatabaseConnector = native_psycopg_connect,
) -> ConfiguredIngestionRuntime:
    """Wire validated paths to lazy Psycopg, Nomic, producer, and writer ports."""

    if not isinstance(paths, OperatorIngestionPaths):
        raise IngestionRuntimeConfigurationError("operator_paths_invalid")
    if not callable(artifact_stage_factory) or not callable(artifact_retainer):
        raise IngestionRuntimeConfigurationError("artifact_dependency_invalid")
    config_root = _safe_directory(Path(runtime_config_root), "runtime_config_root")
    producer_work_root = _safe_directory(Path(work_root), "producer_work_root")
    deployment = validate_deployment_profile(
        _load(config_root, "deployment.yaml", "deployment_profile")
    )
    dependencies = validate_ingestion_dependencies(
        _load(config_root, "ingestion_dependencies.yaml", "ingestion_dependencies")
    )
    relationship_registry = validate_relationship_registry(
        _load(config_root, "relationship_types.yaml", "relationship registry")
    )
    registry, catalog, manifest = load_operator_configuration(paths)
    if not isinstance(manifest, IngestionManifest):
        raise IngestionRuntimeConfigurationError("ingestion_manifest_invalid")

    nomic_credential = ProtectedEnvironmentValue(
        dependencies.nomic_credential_environment, environment
    )
    database_credential = ProtectedEnvironmentValue(
        dependencies.database_credential_environment, environment
    )
    artifact_stage = artifact_stage_factory(dependencies, nomic_credential)
    if not callable(artifact_stage):
        raise IngestionRuntimeConfigurationError("artifact_stage_invalid")
    producer = NativeDocumentProducer(
        manifest=manifest,
        work_root=producer_work_root,
        artifact_stage=artifact_stage,
        artifact_retainer=artifact_retainer,
    )
    connection_factory = NativeIngestionConnectionFactory(
        deployment.postgresql,
        dependencies,
        database_credential,
        database_connector,
    )
    runtime_digest = domain_digest(
        "ishikawa.configured-ingestion-runtime.v1",
        {
            "catalog": catalog.digest,
            "dependencies": dependencies.digest,
            "deployment": deployment.digest,
            "manifest": manifest.digest,
            "method_profile": METHOD_PROFILE_ID,
            "relationship_registry": relationship_registry.digest,
            "registry": registry.digest,
        },
    )
    policy = IngestionRuntimePolicy(
        dependencies,
        deployment.digest,
        registry.digest,
        relationship_registry.digest,
        catalog.digest,
        manifest.digest,
        METHOD_PROFILE_ID,
        runtime_digest,
    )
    return ConfiguredIngestionRuntime(
        paths,
        policy,
        IngestionCommandPorts(
            connection_factory,
            producer,
            relationship_registry=relationship_registry,
        ),
    )

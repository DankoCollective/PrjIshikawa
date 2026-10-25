"""Strict deployment configuration for the first Ishikawa vertical slice."""

from __future__ import annotations

import ipaddress
from dataclasses import dataclass
from typing import Any, Mapping

from .canonical import domain_digest


class DeploymentContractError(ValueError):
    """Raised when deployment configuration leaves the qualified boundary."""


def _mapping(value: Any, fields: frozenset[str], label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != fields:
        raise DeploymentContractError(f"{label} fields are invalid")
    return value


def _loopback_ipv4(value: Any, label: str) -> str:
    if not isinstance(value, str) or value != value.strip():
        raise DeploymentContractError(f"{label} is invalid")
    try:
        address = ipaddress.IPv4Address(value)
    except ipaddress.AddressValueError as error:
        raise DeploymentContractError(f"{label} is invalid") from error
    if not address.is_loopback:
        raise DeploymentContractError(f"{label} must remain loopback")
    return str(address)


def _port(value: Any, label: str) -> int:
    if type(value) is not int or not 1 <= value <= 65535:
        raise DeploymentContractError(f"{label} is invalid")
    return value


@dataclass(frozen=True, slots=True)
class WebDeployment:
    bind_host: str
    port: int
    retrieval_base_url: str

    def __post_init__(self) -> None:
        _loopback_ipv4(self.bind_host, "web bind host")
        _port(self.port, "web port")


@dataclass(frozen=True, slots=True)
class RetrievalDeployment:
    bind_host: str
    port: int
    maximum_concurrent_requests: int
    request_read_timeout_seconds: int

    def __post_init__(self) -> None:
        _loopback_ipv4(self.bind_host, "retrieval bind host")
        _port(self.port, "retrieval port")
        if (
            type(self.maximum_concurrent_requests) is not int
            or not 1 <= self.maximum_concurrent_requests <= 64
        ):
            raise DeploymentContractError("retrieval concurrency is invalid")
        if (
            type(self.request_read_timeout_seconds) is not int
            or not 1 <= self.request_read_timeout_seconds <= 300
        ):
            raise DeploymentContractError("retrieval read timeout is invalid")


@dataclass(frozen=True, slots=True)
class PostgreSQLDeployment:
    bind_host: str
    port: int

    def __post_init__(self) -> None:
        _loopback_ipv4(self.bind_host, "PostgreSQL bind host")
        _port(self.port, "PostgreSQL port")


@dataclass(frozen=True, slots=True)
class DeploymentPolicy:
    node_network_mode: str
    web: WebDeployment
    retrieval: RetrievalDeployment
    postgresql: PostgreSQLDeployment
    digest: str


def validate_deployment_profile(value: Any) -> DeploymentPolicy:
    """Validate the complete v1 host topology without accepting extra fields."""

    root = _mapping(
        value,
        frozenset({"schema_version", "runtime", "web", "retrieval", "postgresql"}),
        "deployment profile",
    )
    if type(root["schema_version"]) is not int or root["schema_version"] != 1:
        raise DeploymentContractError("deployment profile version is invalid")
    runtime = _mapping(root["runtime"], frozenset({"node_network_mode"}), "runtime")
    if runtime["node_network_mode"] != "host":
        raise DeploymentContractError("node network mode is invalid")
    web_value = _mapping(
        root["web"], frozenset({"bind_host", "port", "retrieval_base_url"}), "web"
    )
    retrieval_value = _mapping(
        root["retrieval"],
        frozenset(
            {
                "bind_host",
                "port",
                "maximum_concurrent_requests",
                "request_read_timeout_seconds",
            }
        ),
        "retrieval",
    )
    postgresql_value = _mapping(
        root["postgresql"], frozenset({"bind_host", "port"}), "PostgreSQL"
    )
    retrieval = RetrievalDeployment(
        _loopback_ipv4(retrieval_value["bind_host"], "retrieval bind host"),
        _port(retrieval_value["port"], "retrieval port"),
        retrieval_value["maximum_concurrent_requests"],
        retrieval_value["request_read_timeout_seconds"],
    )
    expected_base_url = f"http://{retrieval.bind_host}:{retrieval.port}"
    if web_value["retrieval_base_url"] != expected_base_url:
        raise DeploymentContractError("retrieval base URL does not match the listener")
    web = WebDeployment(
        _loopback_ipv4(web_value["bind_host"], "web bind host"),
        _port(web_value["port"], "web port"),
        expected_base_url,
    )
    postgresql = PostgreSQLDeployment(
        _loopback_ipv4(postgresql_value["bind_host"], "PostgreSQL bind host"),
        _port(postgresql_value["port"], "PostgreSQL port"),
    )
    if len({web.port, retrieval.port, postgresql.port}) != 3:
        raise DeploymentContractError("deployment ports must be distinct")
    canonical = {
        "postgresql": {"bind_host": postgresql.bind_host, "port": postgresql.port},
        "retrieval": {
            "bind_host": retrieval.bind_host,
            "maximum_concurrent_requests": retrieval.maximum_concurrent_requests,
            "port": retrieval.port,
            "request_read_timeout_seconds": retrieval.request_read_timeout_seconds,
        },
        "runtime": {"node_network_mode": "host"},
        "schema_version": 1,
        "web": {
            "bind_host": web.bind_host,
            "port": web.port,
            "retrieval_base_url": web.retrieval_base_url,
        },
    }
    return DeploymentPolicy(
        "host",
        web,
        retrieval,
        postgresql,
        domain_digest("ishikawa.deployment-profile.v1", canonical),
    )

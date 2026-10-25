"""Classified local JSONL logging for the Ishikawa Retrieval API.

Role:
    Validate the logging profile and write bounded operational, diagnostic,
    restricted-content, and audit events to protected local files.

Mental model:
    Callers construct one typed event from allowlisted fields. The active
    profile selects which classifications may be serialized. Verbose access
    exists only as an in-memory, time-bounded activation that disappears at
    restart and can be stopped immediately.

Side effects:
    Appends JSONL records under ``state/logs`` and rotates only the configured
    log files. It never reads environment values, HTTP headers, credentials,
    database values, vectors, arbitrary objects, or raw exceptions.
"""

from __future__ import annotations

import json
import os
import re
import stat
import threading
from collections.abc import Callable, Mapping
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

import fcntl

from .canonical import domain_digest
from .http_listener import ListenerEvent


LOG_PROFILES = ("default", "debug", "verbose")
_BASE_PROFILES = frozenset({"default", "debug"})
_FILENAME = re.compile(r"^[a-z][a-z0-9._-]{0,63}\.jsonl$")
_EVENT_CODE = re.compile(r"^[A-Z][A-Z0-9_]{0,95}$")
_EVENT_WORD = re.compile(r"^[a-z][a-z0-9_-]{0,95}$")
_IDENTITY = re.compile(r"^[0-9a-f]{64}$")
_REASON_CODE = re.compile(r"^[a-z][a-z0-9_-]{0,95}$")
_DIAGNOSTIC_FIELDS = frozenset(
    {
        "candidate_count",
        "lane_counts",
        "rank",
        "retry_state",
        "stage_trace",
        "token_budget",
    }
)
_RESTRICTED_FIELDS = frozenset(
    {
        "answer",
        "conversation_history",
        "excerpts",
        "model_prompt",
        "question",
        "retrieval_query",
    }
)
_PIPELINE_STAGES = frozenset(
    {
        "request-accepted",
        "direct-injection-rejected",
        "direct-injection-passed",
        "scope-clarification",
        "scope-rejected",
        "scope-allowed",
        "query-resolution-response-invalid",
        "query-resolution-transport-failed",
        "query-clarification",
        "query-resolved",
        "retrieval-completed",
        "sufficiency-blocked",
        "indirect-injection-rejected",
        "indirect-injection-passed",
        "sufficiency-passed",
        "generation-response-invalid",
        "generation-transport-failed",
        "generation-retry",
        "generation-completed",
        "response-built",
        "dependency-unavailable",
        "internal-failure",
    }
)
_APPLICATION_OUTCOMES = frozenset(
    {
        "answered",
        "clarification-required",
        "insufficient-evidence",
        "out-of-scope",
        "security-rejected",
        "context-limit",
        "temporarily-unavailable",
        "internal-error",
    }
)
_METRIC_DEFINITIONS = {
    "requests_total": ("counter", "count", ("category", "outcome")),
    "request_duration_milliseconds": (
        "observation",
        "milliseconds",
        ("category", "outcome"),
    ),
    "pipeline_stage_completed_total": ("counter", "count", ("stage",)),
    "pipeline_stage_duration_milliseconds": (
        "observation",
        "milliseconds",
        ("stage",),
    ),
    "retrieval_lane_state_total": ("counter", "count", ("lane", "state")),
    "fused_candidate_count": ("observation", "count", ()),
    "authorized_candidate_count": ("observation", "count", ()),
    "reconstructed_unit_count": ("observation", "count", ()),
    "citation_count": ("observation", "count", ()),
    "context_tokens_used": ("observation", "tokens", ()),
    "context_token_limit": ("observation", "tokens", ()),
    "nomic_query_tokens": ("observation", "tokens", ()),
}


class ObservabilityContractError(ValueError):
    """Raised when logging input leaves the frozen classified boundary."""


def _exact_mapping(value: Any, fields: frozenset[str], label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != fields:
        raise ObservabilityContractError(f"{label} fields are invalid")
    return value


def _bounded_integer(value: Any, minimum: int, maximum: int, label: str) -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        raise ObservabilityContractError(f"{label} is invalid")
    return value


def _log_filename(value: Any, label: str) -> str:
    if not isinstance(value, str) or _FILENAME.fullmatch(value) is None:
        raise ObservabilityContractError(f"{label} is invalid")
    return value


@dataclass(frozen=True, slots=True)
class LoggingPolicy:
    base_profile: str
    operational_filename: str
    metrics_filename: str
    audit_filename: str
    maximum_event_bytes: int
    maximum_file_bytes: int
    retained_file_count: int
    maximum_verbose_seconds: int
    operational_retention_days: int
    metrics_retention_days: int
    audit_retention_days: int
    digest: str


def validate_logging_profile(value: Any) -> LoggingPolicy:
    """Validate one exact v1 logging policy without touching a destination."""

    root = _exact_mapping(
        value,
        frozenset(
            {
                "schema_version",
                "base_profile",
                "operational_filename",
                "metrics_filename",
                "audit_filename",
                "maximum_event_bytes",
                "maximum_file_bytes",
                "retained_file_count",
                "maximum_verbose_seconds",
                "operational_retention_days",
                "metrics_retention_days",
                "audit_retention_days",
            }
        ),
        "logging profile",
    )
    if root["schema_version"] != 1 or type(root["schema_version"]) is not int:
        raise ObservabilityContractError("logging profile version is invalid")
    base_profile = root["base_profile"]
    if base_profile not in _BASE_PROFILES:
        raise ObservabilityContractError("base logging profile is invalid")
    operational_filename = _log_filename(
        root["operational_filename"], "operational log filename"
    )
    metrics_filename = _log_filename(root["metrics_filename"], "metrics filename")
    audit_filename = _log_filename(root["audit_filename"], "audit log filename")
    if len({operational_filename, metrics_filename, audit_filename}) != 3:
        raise ObservabilityContractError("logging destinations must be separate")
    maximum_event_bytes = _bounded_integer(
        root["maximum_event_bytes"], 1024, 1024 * 1024, "maximum event bytes"
    )
    maximum_file_bytes = _bounded_integer(
        root["maximum_file_bytes"],
        maximum_event_bytes,
        1024 * 1024 * 1024,
        "maximum file bytes",
    )
    retained_file_count = _bounded_integer(
        root["retained_file_count"], 1, 100, "retained file count"
    )
    maximum_verbose_seconds = _bounded_integer(
        root["maximum_verbose_seconds"], 60, 86400, "maximum verbose seconds"
    )
    operational_retention_days = _bounded_integer(
        root["operational_retention_days"], 1, 3650, "operational retention days"
    )
    metrics_retention_days = _bounded_integer(
        root["metrics_retention_days"], 1, 3650, "metrics retention days"
    )
    audit_retention_days = _bounded_integer(
        root["audit_retention_days"], 1, 3650, "audit retention days"
    )
    canonical = dict(root)
    return LoggingPolicy(
        base_profile,
        operational_filename,
        metrics_filename,
        audit_filename,
        maximum_event_bytes,
        maximum_file_bytes,
        retained_file_count,
        maximum_verbose_seconds,
        operational_retention_days,
        metrics_retention_days,
        audit_retention_days,
        domain_digest("ishikawa.logging-profile.v1", canonical),
    )


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _utc_timestamp(value: datetime) -> str:
    if not isinstance(value, datetime) or value.tzinfo is None:
        raise ObservabilityContractError("event time is invalid")
    return value.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )


def _safe_json_value(value: Any, *, depth: int = 0) -> Any:
    if depth > 4:
        raise ObservabilityContractError("classified field nesting is invalid")
    if value is None or type(value) in {bool, int}:
        return value
    if isinstance(value, float):
        if not value == value or value in {float("inf"), float("-inf")}:
            raise ObservabilityContractError("classified numeric field is invalid")
        return value
    if isinstance(value, str):
        if len(value) > 65536 or "\x00" in value:
            raise ObservabilityContractError("classified text field is invalid")
        return value
    if isinstance(value, (tuple, list)):
        if len(value) > 256:
            raise ObservabilityContractError("classified list field is invalid")
        return [_safe_json_value(item, depth=depth + 1) for item in value]
    if isinstance(value, Mapping):
        if len(value) > 128:
            raise ObservabilityContractError("classified mapping field is invalid")
        normalized: dict[str, Any] = {}
        for key, item in value.items():
            if not isinstance(key, str) or _EVENT_WORD.fullmatch(key) is None:
                raise ObservabilityContractError("classified mapping key is invalid")
            normalized[key] = _safe_json_value(item, depth=depth + 1)
        return normalized
    raise ObservabilityContractError("classified field type is invalid")


def _classified_fields(
    values: Mapping[str, Any] | None,
    allowed: frozenset[str],
    label: str,
) -> dict[str, Any]:
    if values is None:
        return {}
    if not isinstance(values, Mapping) or not set(values).issubset(allowed):
        raise ObservabilityContractError(f"{label} fields are invalid")
    return {key: _safe_json_value(values[key]) for key in sorted(values)}


@dataclass(frozen=True, slots=True)
class ClassifiedEvent:
    component: str
    stage: str
    event_code: str
    severity: str
    outcome: str
    request_id: str | None = None
    http_status: int | None = None
    duration_ms: int | None = None
    reason_code: str | None = None
    scope: str | None = None
    diagnostic: Mapping[str, Any] | None = None
    restricted: Mapping[str, Any] | None = None

    def validated(self) -> tuple[dict[str, Any], dict[str, Any]]:
        if (
            _EVENT_WORD.fullmatch(self.component or "") is None
            or _EVENT_WORD.fullmatch(self.stage or "") is None
            or _EVENT_CODE.fullmatch(self.event_code or "") is None
            or self.severity not in {"debug", "info", "warning", "error", "critical"}
            or _EVENT_WORD.fullmatch(self.outcome or "") is None
        ):
            raise ObservabilityContractError("event identity is invalid")
        if self.request_id is not None and _IDENTITY.fullmatch(self.request_id) is None:
            raise ObservabilityContractError("event request identity is invalid")
        if self.http_status is not None and (
            type(self.http_status) is not int or not 100 <= self.http_status <= 599
        ):
            raise ObservabilityContractError("event HTTP status is invalid")
        if self.duration_ms is not None and (
            type(self.duration_ms) is not int or not 0 <= self.duration_ms <= 86400000
        ):
            raise ObservabilityContractError("event duration is invalid")
        if self.reason_code is not None and _REASON_CODE.fullmatch(self.reason_code) is None:
            raise ObservabilityContractError("event reason code is invalid")
        if self.scope is not None and self.scope not in {"request", "service"}:
            raise ObservabilityContractError("event scope is invalid")
        return (
            _classified_fields(self.diagnostic, _DIAGNOSTIC_FIELDS, "diagnostic"),
            _classified_fields(self.restricted, _RESTRICTED_FIELDS, "restricted"),
        )


@dataclass(frozen=True, slots=True)
class ContentFreeMetric:
    metric_name: str
    value: int
    request_id: str
    labels: Mapping[str, str]

    def validated(self) -> tuple[str, str, dict[str, str]]:
        definition = _METRIC_DEFINITIONS.get(self.metric_name)
        if definition is None:
            raise ObservabilityContractError("metric name is invalid")
        metric_type, unit, label_names = definition
        if type(self.value) is not int or not 0 <= self.value <= 100000000:
            raise ObservabilityContractError("metric value is invalid")
        if _IDENTITY.fullmatch(self.request_id or "") is None:
            raise ObservabilityContractError("metric request identity is invalid")
        if not isinstance(self.labels, Mapping) or tuple(sorted(self.labels)) != tuple(
            sorted(label_names)
        ):
            raise ObservabilityContractError("metric labels are invalid")
        labels = dict(self.labels)
        if self.metric_name in {"requests_total", "request_duration_milliseconds"}:
            if labels["category"] not in {"application", "health", "transport"}:
                raise ObservabilityContractError("metric category is invalid")
            allowed_outcomes = _APPLICATION_OUTCOMES | {
                "live",
                "ready",
                "not-ready",
                "accepted",
                "rejected",
                "busy",
                "error",
            }
            if labels["outcome"] not in allowed_outcomes:
                raise ObservabilityContractError("metric outcome is invalid")
        elif self.metric_name.startswith("pipeline_stage_"):
            if labels["stage"] not in _PIPELINE_STAGES:
                raise ObservabilityContractError("metric stage is invalid")
        elif self.metric_name == "retrieval_lane_state_total":
            if labels["lane"] not in {"exact", "lexical", "vector"} or labels[
                "state"
            ] not in {"pass", "not_applicable", "failed"}:
                raise ObservabilityContractError("metric lane state is invalid")
        return metric_type, unit, {key: labels[key] for key in sorted(labels)}


@dataclass(frozen=True, slots=True)
class VerboseActivation:
    reason_code: str
    scope: str
    started_utc: datetime
    expires_utc: datetime

    def validate(self, maximum_seconds: int) -> None:
        if _REASON_CODE.fullmatch(self.reason_code or "") is None:
            raise ObservabilityContractError("verbose reason is invalid")
        if self.scope != "service" and _IDENTITY.fullmatch(self.scope or "") is None:
            raise ObservabilityContractError("verbose scope is invalid")
        if self.started_utc.tzinfo is None or self.expires_utc.tzinfo is None:
            raise ObservabilityContractError("verbose interval is invalid")
        duration = (self.expires_utc - self.started_utc).total_seconds()
        if not 0 < duration <= maximum_seconds:
            raise ObservabilityContractError("verbose interval is invalid")


class LogProfileController:
    """Hold one restart-local verbose activation and restore automatically."""

    def __init__(self, policy: LoggingPolicy, clock: Callable[[], datetime] = _utc_now):
        if not isinstance(policy, LoggingPolicy) or not callable(clock):
            raise ObservabilityContractError("logging controller dependency is invalid")
        self.policy = policy
        self.clock = clock
        self._activation: VerboseActivation | None = None
        self._lock = threading.Lock()

    def active_profile(self, request_id: str | None = None) -> str:
        now = self.clock()
        with self._lock:
            activation = self._activation
            if activation is None or now >= activation.expires_utc:
                self._activation = None
                return self.policy.base_profile
            if activation.scope == "service" or activation.scope == request_id:
                return "verbose"
            return self.policy.base_profile

    def control_profile(self) -> str:
        """Report whether any current bounded verbose activation exists."""

        now = self.clock()
        with self._lock:
            activation = self._activation
            if activation is None or now >= activation.expires_utc:
                self._activation = None
                return self.policy.base_profile
            return "verbose"

    def activate(self, activation: VerboseActivation) -> None:
        activation.validate(self.policy.maximum_verbose_seconds)
        now = self.clock()
        if activation.started_utc > now or activation.expires_utc <= now:
            raise ObservabilityContractError("verbose activation is not current")
        with self._lock:
            self._activation = activation

    def emergency_stop(self) -> None:
        with self._lock:
            self._activation = None


class ProtectedJSONLWriter:
    """Append and rotate one mode-0600 JSONL destination without symlinks."""

    def __init__(self, root: Path, filename: str, policy: LoggingPolicy):
        if not isinstance(root, Path) or not root.is_dir() or root.is_symlink():
            raise ObservabilityContractError("log root is unsafe")
        self.root = root.resolve(strict=True)
        self.filename = _log_filename(filename, "log filename")
        self.policy = policy
        self.path = self.root / self.filename
        self._lock = threading.Lock()

    def _require_regular_or_missing(self, path: Path) -> None:
        try:
            metadata = path.lstat()
        except FileNotFoundError:
            return
        if not stat.S_ISREG(metadata.st_mode):
            raise ObservabilityContractError("log destination is unsafe")

    @contextmanager
    def protected_lock(self) -> Iterator[None]:
        """Serialize writers and retention through one protected local lock."""

        lock_path = self.root / f".{self.filename}.lock"
        self._require_regular_or_missing(lock_path)
        flags = os.O_CREAT | os.O_RDWR
        flags |= getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(lock_path, flags, 0o600)
        try:
            metadata = os.fstat(descriptor)
            if not stat.S_ISREG(metadata.st_mode):
                raise ObservabilityContractError("log lock is unsafe")
            os.fchmod(descriptor, 0o600)
            fcntl.flock(descriptor, fcntl.LOCK_EX)
            yield
        finally:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
            os.close(descriptor)

    def _rotate(self) -> None:
        retained = self.policy.retained_file_count
        if retained == 1:
            if self.path.exists():
                self.path.unlink()
            return
        oldest = self.root / f"{self.filename}.{retained - 1}"
        self._require_regular_or_missing(oldest)
        if oldest.exists():
            oldest.unlink()
        for index in range(retained - 2, 0, -1):
            source = self.root / f"{self.filename}.{index}"
            destination = self.root / f"{self.filename}.{index + 1}"
            self._require_regular_or_missing(source)
            if source.exists():
                os.replace(source, destination)
        self._require_regular_or_missing(self.path)
        if self.path.exists():
            os.replace(self.path, self.root / f"{self.filename}.1")

    def append(self, payload: Mapping[str, Any]) -> None:
        encoded = json.dumps(
            payload,
            ensure_ascii=True,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8") + b"\n"
        if len(encoded) > self.policy.maximum_event_bytes:
            raise ObservabilityContractError("structured event exceeds the accepted size")
        with self._lock:
            with self.protected_lock():
                self._require_regular_or_missing(self.path)
                current_size = self.path.stat().st_size if self.path.exists() else 0
                if current_size + len(encoded) > self.policy.maximum_file_bytes:
                    self._rotate()
                flags = os.O_APPEND | os.O_CREAT | os.O_WRONLY
                flags |= getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
                descriptor = os.open(self.path, flags, 0o600)
                try:
                    metadata = os.fstat(descriptor)
                    if not stat.S_ISREG(metadata.st_mode):
                        raise ObservabilityContractError("log destination is unsafe")
                    os.fchmod(descriptor, 0o600)
                    view = memoryview(encoded)
                    while view:
                        written = os.write(descriptor, view)
                        if written < 1:
                            raise OSError("structured event write did not progress")
                        view = view[written:]
                    os.fsync(descriptor)
                finally:
                    os.close(descriptor)


class ClassifiedJSONLLogger:
    """Serialize only classifications allowed by the active profile."""

    def __init__(
        self,
        writer: ProtectedJSONLWriter,
        controller: LogProfileController,
        clock: Callable[[], datetime] = _utc_now,
    ):
        if not isinstance(writer, ProtectedJSONLWriter) or not isinstance(
            controller, LogProfileController
        ) or not callable(clock):
            raise ObservabilityContractError("structured logger dependency is invalid")
        self.writer = writer
        self.controller = controller
        self.clock = clock

    def write(self, event: ClassifiedEvent) -> None:
        if not isinstance(event, ClassifiedEvent):
            raise ObservabilityContractError("classified event is invalid")
        diagnostic, restricted = event.validated()
        profile = self.controller.active_profile(event.request_id)
        classifications = ["operational"]
        payload: dict[str, Any] = {
            "classification": classifications,
            "component": event.component,
            "event_code": event.event_code,
            "outcome": event.outcome,
            "profile": profile,
            "schema": "ishikawa.log-event.v1",
            "severity": event.severity,
            "stage": event.stage,
            "timestamp_utc": _utc_timestamp(self.clock()),
        }
        if event.request_id is not None:
            payload["request_id"] = event.request_id
        if event.http_status is not None:
            payload["http_status"] = event.http_status
        if event.duration_ms is not None:
            payload["duration_ms"] = event.duration_ms
        if event.reason_code is not None:
            payload["reason_code"] = event.reason_code
        if event.scope is not None:
            payload["scope"] = event.scope
        if profile in {"debug", "verbose"} and diagnostic:
            payload["diagnostic"] = diagnostic
            classifications.append("diagnostic")
        if profile == "verbose" and restricted:
            payload["restricted"] = restricted
            classifications.append("restricted-content")
        self.writer.append(payload)


class ContentFreeMetricLogger:
    """Serialize only fixed low-cardinality operational measurements."""

    def __init__(
        self,
        writer: ProtectedJSONLWriter,
        clock: Callable[[], datetime] = _utc_now,
    ):
        if not isinstance(writer, ProtectedJSONLWriter) or not callable(clock):
            raise ObservabilityContractError("metric logger dependency is invalid")
        self.writer = writer
        self.clock = clock

    def write(self, metric: ContentFreeMetric) -> None:
        if not isinstance(metric, ContentFreeMetric):
            raise ObservabilityContractError("metric observation is invalid")
        metric_type, unit, labels = metric.validated()
        self.writer.append(
            {
                "labels": labels,
                "metric_name": metric.metric_name,
                "metric_type": metric_type,
                "request_id": metric.request_id,
                "schema": "ishikawa.metric-event.v1",
                "timestamp_utc": _utc_timestamp(self.clock()),
                "unit": unit,
                "value": metric.value,
            }
        )


def _request_metric_labels(event: ListenerEvent) -> dict[str, str]:
    if event.outcome.startswith("application_"):
        outcome = event.outcome.removeprefix("application_").replace("_", "-")
        if outcome not in _APPLICATION_OUTCOMES:
            raise ObservabilityContractError("application metric outcome is invalid")
        return {"category": "application", "outcome": outcome}
    if event.outcome == "health_live":
        return {"category": "health", "outcome": "live"}
    if event.outcome == "health_ready":
        return {"category": "health", "outcome": "ready"}
    if event.outcome == "health_not_ready":
        return {"category": "health", "outcome": "not-ready"}
    if event.outcome == "http_service_busy":
        return {"category": "transport", "outcome": "busy"}
    if event.http_status < 400:
        return {"category": "transport", "outcome": "accepted"}
    if event.http_status < 500:
        return {"category": "transport", "outcome": "rejected"}
    return {"category": "transport", "outcome": "error"}


class ConfiguredObservability:
    """Own protected operational/audit writers and the listener event adapter."""

    def __init__(
        self,
        policy: LoggingPolicy,
        log_root: Path,
        clock: Callable[[], datetime] = _utc_now,
        *,
        control_root: Path | None = None,
    ):
        if control_root is not None and (
            not isinstance(control_root, Path)
            or not control_root.is_dir()
            or control_root.is_symlink()
        ):
            raise ObservabilityContractError("runtime control root is unsafe")
        self.policy = policy
        self.control_root = (
            None if control_root is None else control_root.resolve(strict=True)
        )
        self.controller = LogProfileController(policy, clock)
        self.operational = ClassifiedJSONLLogger(
            ProtectedJSONLWriter(log_root, policy.operational_filename, policy),
            self.controller,
            clock,
        )
        self.metrics = ContentFreeMetricLogger(
            ProtectedJSONLWriter(log_root, policy.metrics_filename, policy),
            clock,
        )
        audit_policy = LoggingPolicy(
            "default",
            policy.audit_filename,
            policy.metrics_filename,
            policy.operational_filename,
            policy.maximum_event_bytes,
            policy.maximum_file_bytes,
            policy.retained_file_count,
            policy.maximum_verbose_seconds,
            policy.operational_retention_days,
            policy.metrics_retention_days,
            policy.audit_retention_days,
            policy.digest,
        )
        self.audit = ClassifiedJSONLLogger(
            ProtectedJSONLWriter(log_root, policy.audit_filename, audit_policy),
            LogProfileController(audit_policy, clock),
            clock,
        )

    def listener_event(self, event: ListenerEvent) -> None:
        if not isinstance(event, ListenerEvent):
            raise ObservabilityContractError("listener event is invalid")
        self.operational.write(
            ClassifiedEvent(
                component="retrieval-api",
                stage="http-response",
                event_code=(
                    "HTTP_REQUEST_COMPLETED"
                    if event.http_status < 400
                    else "HTTP_REQUEST_REJECTED"
                ),
                severity=("info" if event.http_status < 400 else "warning"),
                outcome=event.outcome.replace("-", "_"),
                request_id=event.request_id,
                http_status=event.http_status,
                duration_ms=event.duration_ms,
                diagnostic={
                    "retry_state": (
                        "grounded_generation_retried"
                        if "generation-retry" in event.stage_trace
                        else "not_retried"
                    ),
                    "stage_trace": event.stage_trace,
                },
            )
        )
        labels = _request_metric_labels(event)
        self.metrics.write(
            ContentFreeMetric("requests_total", 1, event.request_id, labels)
        )
        self.metrics.write(
            ContentFreeMetric(
                "request_duration_milliseconds",
                event.duration_ms,
                event.request_id,
                labels,
            )
        )
        if event.stage_durations_ms:
            if tuple(stage for stage, _duration in event.stage_durations_ms) != event.stage_trace:
                raise ObservabilityContractError("stage metric sequence is invalid")
            for stage, duration_ms in event.stage_durations_ms:
                stage_labels = {"stage": stage}
                self.metrics.write(
                    ContentFreeMetric(
                        "pipeline_stage_completed_total",
                        1,
                        event.request_id,
                        stage_labels,
                    )
                )
                self.metrics.write(
                    ContentFreeMetric(
                        "pipeline_stage_duration_milliseconds",
                        duration_ms,
                        event.request_id,
                        stage_labels,
                    )
                )
        telemetry = event.retrieval_telemetry
        if telemetry is not None:
            for lane, state in telemetry.lane_states:
                self.metrics.write(
                    ContentFreeMetric(
                        "retrieval_lane_state_total",
                        1,
                        event.request_id,
                        {"lane": lane, "state": state},
                    )
                )
            for metric_name, value in (
                ("fused_candidate_count", telemetry.fused_candidate_count),
                ("authorized_candidate_count", telemetry.authorized_candidate_count),
                ("reconstructed_unit_count", telemetry.reconstructed_unit_count),
                ("citation_count", telemetry.citation_count),
                ("context_tokens_used", telemetry.context_tokens_used),
                ("context_token_limit", telemetry.context_token_limit),
                ("nomic_query_tokens", telemetry.nomic_query_tokens),
            ):
                self.metrics.write(
                    ContentFreeMetric(metric_name, value, event.request_id, {})
                )

    def service_event(self, event_code: str, outcome: str, severity: str = "info") -> None:
        """Record one content-free service lifecycle event."""

        self.operational.write(
            ClassifiedEvent(
                component="retrieval-api",
                stage="service-lifecycle",
                event_code=event_code,
                severity=severity,
                outcome=outcome,
            )
        )

    def activate_verbose(self, activation: VerboseActivation) -> None:
        activation.validate(self.policy.maximum_verbose_seconds)
        duration_seconds = int(
            (activation.expires_utc - activation.started_utc).total_seconds()
        )
        self.audit.write(
            ClassifiedEvent(
                component="retrieval-api",
                stage="logging-control",
                event_code="VERBOSE_CAPTURE_ENABLED",
                severity="warning",
                outcome="enabled",
                request_id=(None if activation.scope == "service" else activation.scope),
                duration_ms=duration_seconds * 1000,
                reason_code=activation.reason_code,
                scope=("service" if activation.scope == "service" else "request"),
            )
        )
        self.controller.activate(activation)

    def stop_verbose(self) -> None:
        self.audit.write(
            ClassifiedEvent(
                component="retrieval-api",
                stage="logging-control",
                event_code="VERBOSE_CAPTURE_DISABLED",
                severity="warning",
                outcome="disabled",
            )
        )
        self.controller.emergency_stop()


def assemble_configured_observability(
    product_root: str | Path,
    policy: LoggingPolicy,
    *,
    clock: Callable[[], datetime] = _utc_now,
) -> ConfiguredObservability:
    """Assemble protected local logging from an installed product root."""

    root = Path(product_root).resolve(strict=True)
    log_root = root / "state/logs"
    control_root = root / "state/run"
    if not log_root.is_dir() or log_root.is_symlink():
        raise ObservabilityContractError("log root is unsafe")
    if not control_root.is_dir() or control_root.is_symlink():
        raise ObservabilityContractError("runtime control root is unsafe")
    try:
        os.chmod(log_root, 0o700)
        os.chmod(control_root, 0o700)
    except OSError as error:
        raise ObservabilityContractError(
            "observability directory permissions could not be protected"
        ) from error
    return ConfiguredObservability(
        policy,
        log_root,
        clock,
        control_root=control_root,
    )

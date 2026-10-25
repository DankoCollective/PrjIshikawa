"""Protected retention for Ishikawa local observability files.

Role:
    Delete only expired active or rotated telemetry files named by the
    validated logging policy.

Mental model:
    The installed command records a content-free audit start, locks all three
    telemetry families, validates every candidate, deletes expired files, and
    records completion. Unrelated files and destinations are never touched.

Side effects:
    May delete expired local JSONL telemetry and append audit records. It does
    not contact a database, model, network endpoint, credential, or corpus.
"""

from __future__ import annotations

import os
import stat
from contextlib import ExitStack
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import TextIO

from .observability import (
    ClassifiedEvent,
    ConfiguredObservability,
    LoggingPolicy,
    ObservabilityContractError,
    ProtectedJSONLWriter,
    validate_logging_profile,
)
from .yaml_loader import load_restricted_yaml


@dataclass(frozen=True, slots=True)
class RetentionResult:
    operational_deleted: int
    metrics_deleted: int
    audit_deleted: int

    @property
    def total_deleted(self) -> int:
        return self.operational_deleted + self.metrics_deleted + self.audit_deleted


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _candidate_files(root: Path, filename: str) -> tuple[Path, ...]:
    prefix = f"{filename}."
    candidates: list[Path] = []
    for path in root.iterdir():
        if path.name == filename or (
            path.name.startswith(prefix) and path.name.removeprefix(prefix).isdigit()
        ):
            metadata = path.lstat()
            if not stat.S_ISREG(metadata.st_mode):
                raise ObservabilityContractError("retention candidate is unsafe")
            candidates.append(path)
    return tuple(sorted(candidates, key=lambda item: item.name))


def apply_observability_retention(
    policy: LoggingPolicy,
    log_root: Path,
    now: datetime,
) -> RetentionResult:
    """Delete expired configured telemetry files under all-or-block validation."""

    if (
        not isinstance(policy, LoggingPolicy)
        or not isinstance(log_root, Path)
        or not log_root.is_dir()
        or log_root.is_symlink()
        or not isinstance(now, datetime)
        or now.tzinfo is None
    ):
        raise ObservabilityContractError("retention dependency is invalid")
    resolved_root = log_root.resolve(strict=True)
    families = (
        ("operational", policy.operational_filename, policy.operational_retention_days),
        ("metrics", policy.metrics_filename, policy.metrics_retention_days),
        ("audit", policy.audit_filename, policy.audit_retention_days),
    )
    writers = {
        family: ProtectedJSONLWriter(resolved_root, filename, policy)
        for family, filename, _days in families
    }
    deleted = {"operational": 0, "metrics": 0, "audit": 0}
    with ExitStack() as locks:
        for family in sorted(writers):
            locks.enter_context(writers[family].protected_lock())
        planned: list[tuple[str, Path]] = []
        for family, filename, retention_days in families:
            cutoff = now.astimezone(timezone.utc) - timedelta(days=retention_days)
            cutoff_timestamp = cutoff.timestamp()
            for candidate in _candidate_files(resolved_root, filename):
                if candidate.stat().st_mtime <= cutoff_timestamp:
                    planned.append((family, candidate))
        for family, candidate in planned:
            metadata = candidate.lstat()
            if not stat.S_ISREG(metadata.st_mode):
                raise ObservabilityContractError("retention candidate changed")
            candidate.unlink()
            deleted[family] += 1
    return RetentionResult(deleted["operational"], deleted["metrics"], deleted["audit"])


def execute_observability_retention(
    arguments: list[str],
    *,
    product_root: Path,
    output: TextIO,
    clock=_utc_now,
) -> int:
    """Run the installed retention command from its product root."""

    if arguments not in (["--check-config"], ["--apply"]):
        output.write(
            "Usage: ishikawa-observability-retention --check-config | --apply\n"
        )
        return 2
    try:
        resolved_root = product_root.resolve(strict=True)
        log_root = (resolved_root / "state" / "logs").resolve(strict=True)
        policy = validate_logging_profile(
            load_restricted_yaml(
                resolved_root / "config" / "logging_profile.yaml",
                label="logging profile",
            )
        )
        if arguments == ["--check-config"]:
            output.write(
                "ishikawa_observability_retention=pass;mode=check-config;"
                f"policy_digest={policy.digest};files_deleted=0\n"
            )
            return 0
        observability = ConfiguredObservability(policy, log_root, clock)
        observability.audit.write(
            ClassifiedEvent(
                "retrieval-api",
                "observability-retention",
                "OBSERVABILITY_RETENTION_STARTED",
                "info",
                "started",
            )
        )
        result = apply_observability_retention(policy, log_root, clock())
        observability.audit.write(
            ClassifiedEvent(
                "retrieval-api",
                "observability-retention",
                "OBSERVABILITY_RETENTION_COMPLETED",
                "info",
                "completed",
            )
        )
    except Exception:
        output.write("ishikawa_observability_retention=blocked;reason=retention_failed\n")
        return 1
    output.write(
        "ishikawa_observability_retention=pass;mode=apply;"
        f"operational_deleted={result.operational_deleted};"
        f"metrics_deleted={result.metrics_deleted};"
        f"audit_deleted={result.audit_deleted};"
        f"files_deleted={result.total_deleted}\n"
    )
    return 0

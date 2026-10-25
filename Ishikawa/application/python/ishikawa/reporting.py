"""Protected, content-safe reports for Ishikawa validation plans."""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

from .models import ValidationPlan
from .reasons import REASON_REGISTRY_VERSION, is_registered_reason


def _report_payload(plan: ValidationPlan) -> dict[str, Any]:
    for entry in plan.entries:
        if not is_registered_reason(entry.reason_code):
            raise ValueError(f"unregistered reason code: {entry.reason_code}")
    for issue in plan.issues:
        if not is_registered_reason(issue.reason_code):
            raise ValueError(f"unregistered reason code: {issue.reason_code}")
    return {
        "schema_version": plan.schema_version,
        "reason_registry_version": REASON_REGISTRY_VERSION,
        "validation_id": plan.validation_id,
        "validation_only": plan.validation_only,
        "mutation_performed": plan.mutation_performed,
        "overall_outcome": plan.overall_outcome,
        "registry_digest": plan.registry_digest,
        "catalog_digest": plan.catalog_digest,
        "manifest_digest": plan.manifest_digest,
        "method_profile_id": plan.method_profile_id,
        "action_counts": plan.action_counts(),
        "entries": [entry.protected_dict() for entry in plan.entries],
        "issues": [issue.public_dict() for issue in plan.issues],
        "atomic_publication_eligible": plan.overall_outcome == "PASS",
    }


def _text_report(plan: ValidationPlan) -> str:
    lines = [
        "Ishikawa validation report",
        f"validation_id={plan.validation_id}",
        f"overall_outcome={plan.overall_outcome}",
        f"validation_only={str(plan.validation_only).lower()}",
        f"mutation_performed={str(plan.mutation_performed).lower()}",
        f"registry_digest={plan.registry_digest}",
        f"catalog_digest={plan.catalog_digest}",
        f"manifest_digest={plan.manifest_digest}",
        f"method_profile_id={plan.method_profile_id}",
    ]
    for action, count in plan.action_counts().items():
        lines.append(f"action_count.{action}={count}")
    for entry in plan.entries:
        action = entry.action or "none"
        lines.append(
            "entry="
            f"{entry.manifest_entry_identity};document_key={entry.document_key};"
            f"action={action};outcome={entry.outcome};reason_code={entry.reason_code}"
        )
    for issue in plan.issues:
        lines.append(
            "issue="
            f"document_key={issue.document_key or 'none'};"
            f"outcome={issue.outcome};reason_code={issue.reason_code}"
        )
    lines.append(f"atomic_publication_eligible={str(plan.overall_outcome == 'PASS').lower()}")
    return "\n".join(lines) + "\n"


def _atomic_private_write(path: Path, content: bytes) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as destination:
            destination.write(content)
            destination.flush()
            os.fsync(destination.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def write_protected_reports(
    plan: ValidationPlan, report_root: str | Path
) -> tuple[Path, Path]:
    """Atomically write mode-0600 text and JSON reports in a mode-0700 root."""

    root = Path(report_root)
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if root.is_symlink() or not root.is_dir():
        raise ValueError("report root must be a non-symlink directory")
    os.chmod(root, 0o700)

    text_path = root / f"{plan.validation_id}.txt"
    json_path = root / f"{plan.validation_id}.json"
    payload = _report_payload(plan)
    _atomic_private_write(text_path, _text_report(plan).encode("utf-8"))
    _atomic_private_write(
        json_path,
        (json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8"),
    )
    return text_path, json_path


def render_terminal_summary(plan: ValidationPlan, report_root: str | Path) -> str:
    """Return a bounded summary that never contains source paths or contents."""

    counts = plan.action_counts()
    action_summary = ",".join(f"{name}:{counts[name]}" for name in sorted(counts))
    return "\n".join(
        (
            f"outcome={plan.overall_outcome}",
            f"validation_id={plan.validation_id}",
            f"actions={action_summary}",
            f"entries={len(plan.entries)};issues={len(plan.issues)}",
            f"mutation_performed={str(plan.mutation_performed).lower()}",
            f"reports={Path(report_root) / plan.validation_id}.txt,.json",
        )
    )

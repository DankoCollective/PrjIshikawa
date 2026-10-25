"""Temporary, content-free grounded-generation failure observer.

This module is loaded only when Script 135 places its directory on
``PYTHONPATH``. It activates only for the staged ``ishikawa-retrieval-api``
entrypoint and records stable failure categories and reason codes. It never
records prompts, responses, evidence, credentials, exceptions, or paths.
"""

from __future__ import annotations

import json
import os
import re
import stat
import sys
import threading
from pathlib import Path
from typing import Any


_HEX = re.compile(r"^[0-9a-f]{64}$")
_REASON = re.compile(r"^[A-Z][A-Z0-9_]{0,95}$")
_LOCK = threading.Lock()
_FAILURE_ORDINALS: dict[str, int] = {}


def _activate() -> None:
    if Path(sys.argv[0]).name != "ishikawa-retrieval-api":
        return
    destination_text = os.environ.get("ISHIKAWA_DIAGNOSTIC_FAILURE_LOG", "")
    if not destination_text:
        return
    destination = Path(destination_text)
    if not destination.is_absolute() or destination.is_symlink():
        raise RuntimeError("diagnostic failure log is unsafe")
    metadata = destination.stat()
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid():
        raise RuntimeError("diagnostic failure log is unsafe")

    product_root = Path(sys.argv[0]).resolve(strict=True).parent.parent
    python_root = (product_root / "application" / "python").resolve(strict=True)
    if not python_root.is_dir() or python_root.is_symlink():
        raise RuntimeError("diagnostic product root is unsafe")
    sys.path.insert(0, str(python_root))

    from ishikawa.generation_transport import (  # noqa: PLC0415
        GenerationResponseError,
        GenerationTransportError,
    )
    from ishikawa.native_adapters import NativeGenerationAdapter  # noqa: PLC0415
    from ishikawa.retrieval_service import (  # noqa: PLC0415
        GroundedGenerationRetryableUnavailable,
    )

    original_call = NativeGenerationAdapter.__call__

    def record_failure(turn_id: str, family: str, reason_code: str) -> None:
        if _HEX.fullmatch(turn_id or "") is None:
            raise RuntimeError("diagnostic turn identity is invalid")
        if family not in {"response_validation", "transport", "unclassified"}:
            raise RuntimeError("diagnostic failure family is invalid")
        if _REASON.fullmatch(reason_code or "") is None:
            reason_code = "UNCLASSIFIED_REASON"
        with _LOCK:
            ordinal = _FAILURE_ORDINALS.get(turn_id, 0) + 1
            _FAILURE_ORDINALS[turn_id] = ordinal
            payload: dict[str, Any] = {
                "failure_family": family,
                "failure_ordinal": ordinal,
                "reason_code": reason_code,
                "schema": "ishikawa.generation-failure-diagnostic.v1",
                "turn_id": turn_id,
            }
            encoded = json.dumps(
                payload,
                ensure_ascii=True,
                allow_nan=False,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8") + b"\n"
            flags = os.O_APPEND | os.O_WRONLY
            flags |= getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
            descriptor = os.open(destination, flags)
            try:
                current = os.fstat(descriptor)
                if not stat.S_ISREG(current.st_mode) or current.st_uid != os.getuid():
                    raise RuntimeError("diagnostic failure log changed identity")
                os.write(descriptor, encoded)
                os.fsync(descriptor)
            finally:
                os.close(descriptor)

    def observed_call(self, request, evidence):
        try:
            return original_call(self, request, evidence)
        except GroundedGenerationRetryableUnavailable as error:
            cause = error.__cause__
            if isinstance(cause, GenerationTransportError):
                family = "transport"
                reason_code = cause.reason_code
            elif isinstance(cause, GenerationResponseError):
                family = "response_validation"
                reason_code = cause.reason_code
            else:
                family = "unclassified"
                reason_code = "UNCLASSIFIED_REASON"
            record_failure(request.turn_id, family, reason_code)
            raise

    NativeGenerationAdapter.__call__ = observed_call


_activate()

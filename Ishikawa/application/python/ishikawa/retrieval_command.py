"""Installed foreground command for the native Ishikawa Retrieval API.

The command derives its configuration from the installed product root, never
accepts credentials or path overrides on the command line, and keeps service
lifecycle visible to an external supervisor. Configuration checking assembles
the runtime without reading credentials or contacting dependencies.
"""

from __future__ import annotations

import os
import signal
import threading
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path
from types import FrameType
from typing import Any, TextIO

from .http_listener import ReadinessProbe
from .logging_control import LoggingControlServer
from .observability import ConfiguredObservability, assemble_configured_observability
from .readiness import ConfiguredReadinessProbe, assemble_configured_readiness_probe
from .runtime import ConfiguredRetrievalRuntime, assemble_configured_retrieval_runtime


class RetrievalCommandError(ValueError):
    """Raised when the installed command cannot safely execute."""


RuntimeAssembler = Callable[..., ConfiguredRetrievalRuntime]
ReadinessAssembler = Callable[..., ConfiguredReadinessProbe]
ObservabilityAssembler = Callable[..., ConfiguredObservability]
ServiceRunner = Callable[
    [ConfiguredRetrievalRuntime, ReadinessProbe, ConfiguredObservability, TextIO], int
]


def run_foreground_retrieval_service(
    runtime: ConfiguredRetrievalRuntime,
    readiness_probe: ReadinessProbe,
    observability: ConfiguredObservability,
    output: TextIO,
    *,
    install_signal_handlers: bool = True,
) -> int:
    """Run one server until shutdown while keeping cleanup deterministic."""

    if not isinstance(runtime, ConfiguredRetrievalRuntime):
        raise RetrievalCommandError("configured runtime is invalid")
    if not callable(readiness_probe):
        raise RetrievalCommandError("readiness probe is invalid")
    if not isinstance(observability, ConfiguredObservability):
        raise RetrievalCommandError("configured observability is invalid")
    if observability.control_root is None:
        raise RetrievalCommandError("logging control root is unavailable")
    server = runtime.create_http_server(
        event_sink=observability.listener_event,
        readiness_probe=readiness_probe,
    )
    control_server = LoggingControlServer(
        observability,
        observability.control_root,
    )
    stopped = threading.Event()
    failures: list[str] = []

    def serve() -> None:
        try:
            server.serve_forever(poll_interval=0.2)
        except Exception as error:
            failures.append(type(error).__name__)
        finally:
            stopped.set()

    previous_handlers: dict[int, Any] = {}

    def request_stop(_signal_number: int, _frame: FrameType | None) -> None:
        stopped.set()

    if install_signal_handlers:
        for signal_number in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[signal_number] = signal.getsignal(signal_number)
            signal.signal(signal_number, request_stop)

    service_thread = threading.Thread(
        target=serve,
        name="ishikawa-retrieval-api",
        daemon=False,
    )
    try:
        control_server.start()
        observability.service_event("SERVICE_STARTED", "started")
        service_thread.start()
        bind = runtime.policies.deployment.retrieval
        output.write(
            "ishikawa_retrieval_api=started;"
            f"bind_host={bind.bind_host};port={bind.port}\n"
        )
        output.flush()
        stopped.wait()
        if service_thread.is_alive():
            server.shutdown()
        service_thread.join(timeout=10)
        if service_thread.is_alive():
            output.write("ishikawa_retrieval_api=blocked;reason=shutdown_timeout\n")
            output.flush()
            return 1
    finally:
        server.server_close()
        control_server.stop()
        if install_signal_handlers:
            for signal_number, previous_handler in previous_handlers.items():
                signal.signal(signal_number, previous_handler)

    if failures:
        try:
            observability.service_event("SERVICE_FAILED", "failed", "error")
        except Exception:
            pass
        output.write("ishikawa_retrieval_api=blocked;reason=listener_failure\n")
        output.flush()
        return 1
    if control_server.failed:
        output.write("ishikawa_retrieval_api=blocked;reason=logging_control_failure\n")
        output.flush()
        return 1
    try:
        observability.service_event("SERVICE_STOPPED", "stopped")
    except Exception:
        output.write("ishikawa_retrieval_api=blocked;reason=logging_failure\n")
        output.flush()
        return 1
    output.write("ishikawa_retrieval_api=stopped;cleanup=complete\n")
    output.flush()
    return 0


def execute_installed_retrieval(
    arguments: Sequence[str],
    *,
    product_root: str | Path,
    output: TextIO,
    environment: Mapping[str, str] = os.environ,
    runtime_assembler: RuntimeAssembler = assemble_configured_retrieval_runtime,
    readiness_assembler: ReadinessAssembler = assemble_configured_readiness_probe,
    observability_assembler: ObservabilityAssembler = assemble_configured_observability,
    service_runner: ServiceRunner = run_foreground_retrieval_service,
) -> int:
    """Validate arguments, assemble the installed runtime, and check or serve."""

    if tuple(arguments) == ("--help",) or tuple(arguments) == ("-h",):
        output.write(
            "Usage: ishikawa-retrieval-api "
            "--check-config | --check-readiness | --serve\n"
        )
        return 0
    if tuple(arguments) not in (
        ("--check-config",),
        ("--check-readiness",),
        ("--serve",),
    ):
        output.write("ishikawa_retrieval_api=blocked;reason=arguments_invalid\n")
        return 2
    try:
        root = Path(product_root).resolve(strict=True)
        config_root = root / "config"
        if not config_root.is_dir() or config_root.is_symlink():
            raise RetrievalCommandError("configuration root is unsafe")
        runtime = runtime_assembler(config_root, environment=environment)
        if not isinstance(runtime, ConfiguredRetrievalRuntime):
            raise RetrievalCommandError("runtime assembly result is invalid")
    except Exception:
        output.write("ishikawa_retrieval_api=blocked;reason=configuration_invalid\n")
        return 1

    if tuple(arguments) == ("--check-config",):
        output.write(
            "ishikawa_retrieval_api_configuration=pass;"
            f"policy_digest={runtime.policies.digest};"
            "credential_read=false;dependency_contact=false\n"
        )
        return 0
    try:
        readiness_probe = readiness_assembler(
            root,
            runtime,
            environment=environment,
        )
        if not isinstance(readiness_probe, ConfiguredReadinessProbe):
            raise RetrievalCommandError("readiness assembly result is invalid")
        if tuple(arguments) == ("--check-readiness",):
            inspection = readiness_probe.inspect()
            output.write(f"{inspection.marker()}\n")
            return 0 if inspection.ready else 1
        observability = observability_assembler(root, runtime.policies.logging)
        return service_runner(runtime, readiness_probe, observability, output)
    except Exception:
        output.write("ishikawa_retrieval_api=blocked;reason=service_start_failed\n")
        return 1

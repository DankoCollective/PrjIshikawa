#!/usr/bin/env python3
"""Qualify a temporary two-port SSH transport from an application host."""

from __future__ import annotations

import argparse
import http.client
import json
import os
import platform
import re
import socket
import subprocess
import time
from pathlib import Path
from typing import NoReturn


TARGET = re.compile(r"^[a-z_][a-z0-9_-]{0,31}@[A-Za-z0-9][A-Za-z0-9.-]{0,252}$")
HOST = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$")


class QualificationError(RuntimeError):
    """Stable, content-free qualification failure."""


def fail(reason: str) -> NoReturn:
    raise QualificationError(reason)


def port_is_free(port: int) -> bool:
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(("127.0.0.1", port))
    except OSError:
        return False
    finally:
        probe.close()
    return True


def directly_reachable(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=1.5):
            return True
    except OSError:
        return False


def health_status(port: int) -> int:
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        connection.request("GET", "/health", headers={"Accept": "application/json"})
        response = connection.getresponse()
        response.read(4097)
        return response.status
    except (OSError, http.client.HTTPException):
        return 0
    finally:
        connection.close()


def wait_for_health(process: subprocess.Popen[bytes]) -> tuple[int, int]:
    deadline = time.monotonic() + 20
    last = (0, 0)
    while time.monotonic() < deadline:
        if process.poll() is not None:
            fail("ssh_tunnel_exited_during_startup")
        last = (health_status(8000), health_status(8001))
        if last == (200, 200):
            return last
        time.sleep(0.25)
    fail("tunneled_health_endpoints_unavailable")


def stop_tunnel(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if port_is_free(8000) and port_is_free(8001):
            return
        time.sleep(0.1)
    fail("tunnel_ports_remain_after_shutdown")


def qualify(model_target: str, model_host: str, known_hosts: Path, output: Path) -> None:
    if TARGET.fullmatch(model_target) is None or HOST.fullmatch(model_host) is None:
        fail("model_target_invalid")
    if model_target.rsplit("@", 1)[1] != model_host:
        fail("model_target_host_mismatch")
    if not known_hosts.is_file() or known_hosts.is_symlink():
        fail("known_hosts_missing_or_unsafe")
    if output.exists() or output.is_symlink():
        fail("output_path_exists")
    if not os.environ.get("SSH_AUTH_SOCK"):
        fail("forwarded_ssh_agent_unavailable")
    if not port_is_free(8000) or not port_is_free(8001):
        fail("local_tunnel_port_in_use")

    direct_gemma = directly_reachable(model_host, 8000)
    direct_nomic = directly_reachable(model_host, 8001)
    if direct_gemma or direct_nomic:
        fail("native_model_port_directly_reachable")

    error_path = output.with_suffix(".ssh-error")
    tunnel: subprocess.Popen[bytes] | None = None
    health = (0, 0)
    try:
        with error_path.open("wb") as error_stream:
            tunnel = subprocess.Popen(
                [
                    "ssh",
                    "-F",
                    "/dev/null",
                    "-N",
                    "-o",
                    "BatchMode=yes",
                    "-o",
                    "PasswordAuthentication=no",
                    "-o",
                    "KbdInteractiveAuthentication=no",
                    "-o",
                    "StrictHostKeyChecking=yes",
                    "-o",
                    f"UserKnownHostsFile={known_hosts}",
                    "-o",
                    "CheckHostIP=no",
                    "-o",
                    "ExitOnForwardFailure=yes",
                    "-o",
                    "ForwardAgent=no",
                    "-o",
                    "ServerAliveInterval=10",
                    "-o",
                    "ServerAliveCountMax=2",
                    "-L",
                    "127.0.0.1:8000:127.0.0.1:8000",
                    "-L",
                    "127.0.0.1:8001:127.0.0.1:8001",
                    model_target,
                ],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=error_stream,
                close_fds=True,
            )
            health = wait_for_health(tunnel)
    finally:
        if tunnel is not None:
            stop_tunnel(tunnel)
        try:
            error_path.unlink()
        except FileNotFoundError:
            pass

    document = {
        "api_credentials_read": False,
        "architecture": platform.machine(),
        "direct_native_ports_reachable": {"gemma": direct_gemma, "nomic": direct_nomic},
        "embedding_calls": 0,
        "identity_source": "forwarded_ephemeral_agent",
        "inference_calls": 0,
        "model_host": model_host,
        "organizational_content_used": False,
        "purpose": "application_host_model_transport_qualification",
        "python_version": platform.python_version(),
        "raw_health_bodies_retained": False,
        "schema_version": 1,
        "tokenization_calls": 0,
        "tunnel": {
            "connection_count": 1,
            "gemma_health_status": health[0],
            "gemma_local_endpoint": "127.0.0.1:8000",
            "nomic_health_status": health[1],
            "nomic_local_endpoint": "127.0.0.1:8001",
            "shutdown": "pass",
        },
    }
    output.write_text(json.dumps(document, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    os.chmod(output, 0o600)
    print("direct_native_model_ports=blocked")
    print("ssh_tunnel_connections=1;forwarded_ports=8000,8001")
    print("gemma_health_status=200;nomic_health_status=200")
    print("tunnel_shutdown=pass;ports_after_test=free")
    print("api_credentials_read=false;model_calls=0;organizational_content_used=false")
    print("application_host_model_transport=pass")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-target", required=True)
    parser.add_argument("--model-host", required=True)
    parser.add_argument("--known-hosts", required=True)
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args()
    try:
        qualify(
            arguments.model_target,
            arguments.model_host,
            Path(arguments.known_hosts),
            Path(arguments.output),
        )
    except QualificationError as error:
        print(f"application_host_model_transport=blocked;reason={error}")
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()

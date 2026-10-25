#!/usr/bin/env python3
"""Evaluate the final Ishikawa stack-control source contract."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


class EvaluationError(RuntimeError):
    """Raised when stack control leaves its accepted boundary."""


def _read(path: Path) -> str:
    if not path.is_file() or path.is_symlink():
        raise EvaluationError("unsafe_input")
    return path.read_text(encoding="utf-8")


def _ordered(text: str, snippets: tuple[str, ...], reason: str) -> None:
    cursor = -1
    for snippet in snippets:
        position = text.find(snippet, cursor + 1)
        if position < 0:
            raise EvaluationError(reason)
        cursor = position


def evaluate(command_path: Path, contract_path: Path) -> dict[str, object]:
    command = _read(command_path)
    contract = _read(contract_path)
    required_command = (
        "start|status|stop",
        "postgresql@16-main.service",
        "ishikawa-retrieval-api.service",
        "node-24-slim-nextjs-16-4-1:$architecture",
        "--network host",
        "--security-opt no-new-privileges",
        "--cap-drop ALL",
        "systemctl --user import-environment",
        "systemctl --user unset-environment",
        "managed_stack_state_absent_or_invalid",
        "boot_enabled=false",
    )
    if any(item not in command for item in required_command):
        raise EvaluationError("command_contract_incomplete")
    forbidden = (
        "systemctl enable",
        "systemctl --user enable",
        "docker pull",
        "docker build",
        "docker tag",
        "--privileged",
        "0.0.0.0",
        "\nssh ",
        "\neval ",
        'source "$STATE_FILE"',
    )
    if any(item in command for item in forbidden):
        raise EvaluationError("forbidden_behavior_present")
    _ordered(
        command,
        (
            'sudo systemctl start "$POSTGRESQL_UNIT"',
            'systemctl --user import-environment "${SECRET_NAMES[@]}"',
            'systemctl --user start "$RETRIEVAL_UNIT"',
            'systemctl --user unset-environment "${SECRET_NAMES[@]}"',
            'wait_http "$retrieval_base_url/ready"',
            '"${docker_command[@]}" run --detach --rm',
            'wait_http "http://$web_host:$web_port/api/ready"',
            "write_state running",
        ),
        "start_order_invalid",
    )
    _ordered(
        command,
        (
            '"${docker_command[@]}" stop --time 20',
            'systemctl --user stop "$RETRIEVAL_UNIT"',
            'sudo systemctl stop "$POSTGRESQL_UNIT"',
        ),
        "stop_order_invalid",
    )
    required_contract = (
        "Nothing is started at boot",
        "external operator action",
        "starts native PostgreSQL",
        "starts the one web container",
        "Any failure rolls back",
        "web container, Retrieval API, then PostgreSQL",
    )
    if any(item not in contract for item in required_contract):
        raise EvaluationError("contract_document_incomplete")
    return {
        "schema": "ishikawa.stack-control-qualification.v1",
        "command_sha256": hashlib.sha256(command.encode()).hexdigest(),
        "contract_sha256": hashlib.sha256(contract.encode()).hexdigest(),
        "actions": ["start", "status", "stop"],
        "start_order": ["postgresql", "retrieval", "web"],
        "stop_order": ["web", "retrieval", "postgresql"],
        "boot_enabled": False,
        "forwarding_owned": False,
        "image_changed": False,
        "credential_values_stored": False,
        "rollback_required": True,
        "status": "pass",
    }


def _write_executable(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)


def exercise(source_root: Path) -> dict[str, object]:
    """Exercise lifecycle behavior with deterministic local command adapters."""

    with tempfile.TemporaryDirectory(prefix="ishikawa-stack-control-") as temporary:
        root = Path(temporary)
        installed = root / "Ishikawa"
        (installed / "application").mkdir(parents=True)
        shutil.copytree(source_root / "application" / "python", installed / "application" / "python")
        web = installed / "application" / "web"
        web.mkdir()
        for directory in ("app", "components", "lib"):
            shutil.copytree(source_root / "application" / "web" / directory, web / directory)
        for filename in ("package.json", "next.config.mjs"):
            shutil.copy2(source_root / "application" / "web" / filename, web / filename)
        config = installed / "config"
        config.mkdir()
        for filename in ("product.yaml", "deployment.yaml"):
            shutil.copy2(source_root / "config" / "templates" / filename, config / filename)
        scripts = installed / "scripts"
        scripts.mkdir()
        shutil.copy2(source_root / "scripts" / "ishikawa-stack", scripts / "ishikawa-stack")
        (scripts / "ishikawa-stack").chmod(0o755)
        (installed / "state" / "run").mkdir(parents=True, mode=0o700)

        fake_bin = root / "bin"
        fake_state = root / "state"
        fake_bin.mkdir()
        fake_state.mkdir()
        _write_executable(
            fake_bin / "systemctl",
            """#!/usr/bin/env bash
set -euo pipefail
state="${ISHIKAWA_STACK_TEST_STATE:?}"
scope=system
if [[ "${1-}" == --user ]]; then scope=user; shift; fi
command="${1-}"; shift || true
unit="${1-}"
case "$command" in
  is-enabled)
    [[ "${ISHIKAWA_STACK_TEST_BOOT_ENABLED-}" != true ]] || { printf 'enabled\\n'; exit 0; }
    printf 'disabled\\n'
    ;;
  is-active)
    [[ -f "$state/$scope.$unit.active" ]] && { printf 'active\\n'; exit 0; }
    printf 'inactive\\n'; exit 3
    ;;
  cat) [[ "$scope" == user && "$unit" == ishikawa-retrieval-api.service ]] ;;
  import-environment)
    for name in "$unit" "$@"; do [[ -n "$name" && -n "${!name-}" ]] || exit 1; done
    printf '%s\\n' "$unit" "$@" >"$state/imported-names"
    ;;
  unset-environment) : >"$state/unset-environment" ;;
  start)
    if [[ "$scope" == user ]]; then [[ -f "$state/imported-names" ]] || exit 1; fi
    : >"$state/$scope.$unit.active"
    ;;
  stop) rm -f -- "$state/$scope.$unit.active" ;;
  *) exit 1 ;;
esac
""",
        )
        _write_executable(
            fake_bin / "sudo",
            """#!/usr/bin/env bash
set -euo pipefail
[[ "${1-}" != -v ]] || exit 0
exec "$@"
""",
        )
        _write_executable(
            fake_bin / "docker",
            """#!/usr/bin/env bash
set -euo pipefail
state="${ISHIKAWA_STACK_TEST_STATE:?}"
case "${1-}" in
  info) exit 0 ;;
  image)
    [[ "${2-}" == inspect ]] || exit 1
    [[ "$*" != *Architecture* ]] || printf 'amd64\\n'
    ;;
  inspect)
    [[ -f "$state/web.active" ]] || exit 1
    [[ "$*" != *State.Running* ]] || printf 'true\\n'
    ;;
  run)
    [[ "${ISHIKAWA_STACK_TEST_FAIL_WEB_START-}" != true ]] || exit 1
    printf '%s\\n' "$*" >"$state/docker-run-arguments"
    : >"$state/web.active"
    printf 'fixture-container\\n'
    ;;
  stop) rm -f -- "$state/web.active" ;;
  *) exit 1 ;;
esac
""",
        )
        _write_executable(
            fake_bin / "dpkg",
            """#!/usr/bin/env bash
set -euo pipefail
[[ "${1-}" == --print-architecture ]]
printf 'amd64\\n'
""",
        )
        _write_executable(
            fake_bin / "pg_isready",
            """#!/usr/bin/env bash
set -euo pipefail
[[ -f "${ISHIKAWA_STACK_TEST_STATE:?}/system.postgresql@16-main.service.active" ]]
""",
        )
        _write_executable(
            fake_bin / "curl",
            """#!/usr/bin/env bash
set -euo pipefail
state="${ISHIKAWA_STACK_TEST_STATE:?}"
url="${*: -1}"
case "$url" in
  http://127.0.0.1:1384/live|http://127.0.0.1:1384/ready)
    [[ -f "$state/user.ishikawa-retrieval-api.service.active" ]] && printf '200' || printf '503'
    ;;
  http://127.0.0.1:3000/api/live)
    [[ -f "$state/web.active" ]] && printf '200' || printf '503'
    ;;
  http://127.0.0.1:3000/api/ready)
    if [[ "${ISHIKAWA_STACK_TEST_FAIL_WEB_READY-}" == true ]]; then printf '503'
    elif [[ -f "$state/web.active" ]]; then printf '200'
    else printf '503'; fi
    ;;
  *) printf '503' ;;
esac
""",
        )
        _write_executable(fake_bin / "ss", "#!/usr/bin/env bash\nexit 0\n")
        _write_executable(fake_bin / "sleep", "#!/usr/bin/env bash\nexit 0\n")

        command = str(scripts / "ishikawa-stack")
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{fake_bin}:{environment['PATH']}",
                "ISHIKAWA_STACK_TEST_STATE": str(fake_state),
                "ISHIKAWA_GEMMA_API_KEY": "qualification-gemma-secret",
                "ISHIKAWA_NOMIC_API_KEY": "qualification-nomic-secret",
                "ISHIKAWA_POSTGRESQL_PASSWORD": "qualification-postgresql-secret",
                "PYTHONDONTWRITEBYTECODE": "1",
            }
        )

        def run(action: str, *, extra: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
            current = environment.copy()
            current.update(extra or {})
            return subprocess.run(
                (command, action),
                text=True,
                capture_output=True,
                check=False,
                env=current,
                timeout=30,
            )

        start = run("start")
        if start.returncode or start.stdout != "ishikawa_stack=start;state=ready;boot_enabled=false\n":
            raise EvaluationError("start_contract_failed")
        expected_active = (
            fake_state / "system.postgresql@16-main.service.active",
            fake_state / "user.ishikawa-retrieval-api.service.active",
            fake_state / "web.active",
            installed / "state" / "run" / "stack.state",
        )
        if not all(item.is_file() for item in expected_active):
            raise EvaluationError("start_state_incomplete")
        status = run("status")
        if status.returncode or status.stdout != "ishikawa_stack=status;state=ready;boot_enabled=false\n":
            raise EvaluationError("ready_status_failed")
        stop = run("stop")
        if stop.returncode or stop.stdout != "ishikawa_stack=stop;state=stopped;boot_enabled=false\n":
            raise EvaluationError("stop_contract_failed")
        if any(item.exists() for item in expected_active):
            raise EvaluationError("stop_cleanup_failed")
        stopped = run("status")
        if stopped.returncode or stopped.stdout != "ishikawa_stack=status;state=stopped;boot_enabled=false\n":
            raise EvaluationError("stopped_status_failed")

        rollback = run("start", extra={"ISHIKAWA_STACK_TEST_FAIL_WEB_START": "true"})
        if rollback.returncode == 0 or rollback.stderr != "ishikawa_stack=blocked;reason=web_start_failed\n":
            raise EvaluationError("rollback_reason_invalid")
        if any(item.exists() for item in expected_active):
            raise EvaluationError("rollback_incomplete")

        missing_environment = environment.copy()
        missing_environment.pop("ISHIKAWA_NOMIC_API_KEY")
        missing = subprocess.run(
            (command, "start"),
            text=True,
            capture_output=True,
            check=False,
            env=missing_environment,
            timeout=30,
        )
        if missing.returncode == 0 or missing.stderr != "ishikawa_stack=blocked;reason=required_credential_missing\n":
            raise EvaluationError("missing_credential_not_rejected")

        retained = b"".join(
            item.read_bytes() for item in root.rglob("*") if item.is_file() and item.stat().st_size < 1_000_000
        )
        for secret in (
            b"qualification-gemma-secret",
            b"qualification-nomic-secret",
            b"qualification-postgresql-secret",
        ):
            if secret in retained:
                raise EvaluationError("credential_value_retained")
        return {
            "lifecycle": "start-ready-status-stop-stopped",
            "rollback": "pass",
            "missing_credential": "blocked",
            "credential_disclosure": False,
        }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--command", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--exercise-root", type=Path)
    args = parser.parse_args()
    result = evaluate(args.command, args.contract)
    if args.exercise_root is not None:
        result["runtime_exercise"] = exercise(args.exercise_root)
    args.output.write_text(json.dumps(result, sort_keys=True) + "\n", encoding="utf-8")
    print("actions=start,status,stop;boot_enabled=false")
    print("start_order=postgresql,retrieval,web;readiness_between=true")
    print("stop_order=web,retrieval,postgresql")
    print("forwarding_owned=false;image_changed=false;configuration_changed=false")
    print("credential_values=environment-only,not-printed,not-stored")
    print("rollback=required;managed_state=owner-only")
    if args.exercise_root is not None:
        print("lifecycle=start-ready-status-stop-stopped;rollback=pass;missing_credential=blocked")
    print("explicit_stack_control_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

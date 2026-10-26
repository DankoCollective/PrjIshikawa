#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Exercise Script 07 end to end without contacting EmceeDanko or Docker.
#
# Mental model:
#   Copy the exact wrapper/helper inputs into a private repository, replace only
#   SSH, SCP, host identity, and Docker with deterministic doubles, and prove
#   transfer, native build, return verification, publication, rerun,
#   failure-preservation, and cleanup behavior.
#
# Inputs or prerequisites:
#   Current Script 07, native runtime helper, runtime sources, and decisions.
#
# Outputs:
#   One terminal result; all test state remains under a removed /tmp directory.
#
# Usage:
#   bash ./deployment/tests/native-runtime-build-wrapper.sh

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
test_root="$(mktemp -d /tmp/ishikawa-script-07-test.XXXXXX)"

fail() {
  printf '\nSCRIPT RESULT\nnative_runtime_build_wrapper_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$test_root" == /tmp/ishikawa-script-07-test.* && -d "$test_root" ]] \
    && rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- \
  "$test_root/repo/deployment/scripts" \
  "$test_root/repo/deployment/assets" \
  "$test_root/repo/deployment/runtime-image" \
  "$test_root/repo/docs/decisions" \
  "$test_root/bin" \
  "$test_root/remote-bin" \
  "$test_root/remote-docker-root" \
  "$test_root/reports"
cp -- "$repo_root/deployment/scripts/07_build-node-next-runtime-on-emceedanko.sh" \
  "$test_root/repo/deployment/scripts/"
cp -- "$repo_root/deployment/assets/build-node-next-runtime" \
  "$test_root/repo/deployment/assets/"
cp -- "$repo_root/deployment/runtime-image/"* \
  "$test_root/repo/deployment/runtime-image/"
cp -- "$repo_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md" \
  "$test_root/repo/docs/decisions/"

cat >"$test_root/remote-bin/hostname" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == -s ]] || exit 2
if [[ "${MOCK_REMOTE_HOST_FAIL:-false}" == true ]]; then
  printf 'WrongHost\n'
else
  printf 'EmceeDanko\n'
fi
MOCK
cat >"$test_root/remote-bin/uname" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == -m ]] || exit 2
printf 'x86_64\n'
MOCK
cat >"$test_root/remote-bin/dpkg" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == --print-architecture ]] || exit 2
printf 'amd64\n'
MOCK
cat >"$test_root/remote-bin/nproc" <<'MOCK'
#!/usr/bin/env bash
printf '8\n'
MOCK

cat >"$test_root/remote-bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail

case "${1:-}" in
  info)
    case "$*" in
      *'{{.Architecture}}'*) printf 'amd64\n' ;;
      *'{{.DockerRootDir}}'*) printf '%s\n' "$MOCK_DOCKER_ROOT" ;;
    esac
    ;;
  buildx)
    [[ "${2:-}" == version ]] && exit 0
    [[ "${2:-}" == build ]] || exit 91
    [[ "${MOCK_BUILD_FAIL:-false}" != true ]] || exit 42
    if [[ "${MOCK_BUILD_DELAY:-0}" != 0 ]]; then
      trap 'exit 143' TERM
      sleep "$MOCK_BUILD_DELAY"
    fi
    printf 'mock native image build\n'
    printf 'retained\n' >"$MOCK_IMAGE_MARKER"
    ;;
  image)
    [[ "${2:-}" == inspect ]] || exit 92
    case "$*" in
      *'{{.Architecture}}'*) printf 'amd64\n' ;;
      *'{{.Id}}'*) printf 'sha256:%064d\n' 7 ;;
      *) printf '{}\n' ;;
    esac
    ;;
  run)
    if [[ "$*" == *'--entrypoint sh '* && "$*" == *'runtime_identity=pass'* ]]; then
      printf 'runtime_identity=pass\n'
      exit 0
    fi
    if [[ "$*" == *'--entrypoint sh '* ]]; then
      exit 0
    fi
    if [[ "$*" == *'--entrypoint dpkg-query'* ]]; then
      printf 'libc6\t2.36-9+deb12u13\tamd64\n'
      exit 0
    fi
    if [[ "$*" == *'--entrypoint npm'* ]]; then
      printf '%s\n' '{"dependencies":{"next":{"version":"16.4.3"},"react":{"version":"19.2.9"},"react-dom":{"version":"19.2.9"}}}'
      exit 0
    fi
    if [[ "$*" == *'--entrypoint sha256sum'* ]]; then
      printf '%064d  %s\n' 1 /usr/local/LICENSE
      printf '%064d  %s\n' 2 /usr/local/lib/node_modules/npm/LICENSE
      printf '%064d  %s\n' 3 /opt/yarn-v1.22.22/LICENSE
      exit 0
    fi
    exit 93
    ;;
  history)
    printf 'generic runtime layer\n'
    ;;
  save)
    [[ -n "${2:-}" ]] || exit 94
    archive_root="$(mktemp -d /tmp/mock-runtime-archive.XXXXXX)"
    printf '{"architecture":"amd64","os":"linux","config":{"WorkingDir":"/opt/nextjs","Cmd":["next","--help"]},"rootfs":{"type":"layers","diff_ids":["sha256:%064d"]},"history":[{"created_by":"generic runtime layer"}]}\n' 4 \
      >"$archive_root/config.json"
    printf 'mock compressed layer\n' >"$archive_root/layer"
    layer_hex="$(sha256sum "$archive_root/layer" | awk '{print $1}')"
    config_hex="$(sha256sum "$archive_root/config.json" | awk '{print $1}')"
    mkdir -p "$archive_root/blobs/sha256"
    mv "$archive_root/config.json" "$archive_root/blobs/sha256/$config_hex"
    mv "$archive_root/layer" "$archive_root/blobs/sha256/$layer_hex"
    printf '[{"Config":"blobs/sha256/%s","RepoTags":["node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64"],"Layers":["blobs/sha256/%s"]}]\n' \
      "$config_hex" "$layer_hex" >"$archive_root/manifest.json"
    tar -cf - -C "$archive_root" manifest.json blobs
    rm -rf "$archive_root"
    ;;
  load)
    exit 0
    ;;
  *)
    exit 95
    ;;
esac
MOCK
chmod 0755 "$test_root/remote-bin/"*

# Local helper validation needs Docker only as a named command; --validate-only
# performs no daemon contact.
cp -- "$test_root/remote-bin/docker" "$test_root/bin/docker"

cat >"$test_root/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
for argument in "$@"; do
  [[ "$argument" != -G ]] || { printf 'hostname fake-target\n'; exit 0; }
done
for ((index=1; index <= $#; index++)); do
  [[ "${!index}" != -O ]] || exit 0
  [[ "${!index}" != -Nf ]] || exit 0
done
remote_command="${!#}"
HOME="$ISHIKAWA_FAKE_REMOTE_HOME" \
PATH="$ISHIKAWA_FAKE_REMOTE_BIN:/usr/bin:/bin" \
MOCK_DOCKER_ROOT="$MOCK_DOCKER_ROOT" \
MOCK_IMAGE_MARKER="$MOCK_IMAGE_MARKER" \
MOCK_BUILD_FAIL="${MOCK_BUILD_FAIL:-false}" \
MOCK_BUILD_DELAY="${MOCK_BUILD_DELAY:-0}" \
MOCK_REMOTE_HOST_FAIL="${MOCK_REMOTE_HOST_FAIL:-false}" \
  setsid bash -c "$remote_command" &
remote_pid="$!"
terminate_remote() {
  trap - HUP INT TERM
  kill -TERM -- "-$remote_pid" 2>/dev/null || kill -TERM "$remote_pid" 2>/dev/null || true
  wait "$remote_pid" 2>/dev/null || true
  exit 143
}
trap terminate_remote HUP INT TERM
wait "$remote_pid"
MOCK
chmod 0755 "$test_root/bin/ssh"

cat >"$test_root/bin/scp" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
recursive=false
positionals=()
while (( $# > 0 )); do
  case "$1" in
    -o|-i) shift 2 ;;
    -r) recursive=true; shift ;;
    -*) shift ;;
    *) positionals+=("$1"); shift ;;
  esac
done
(( ${#positionals[@]} >= 2 )) || exit 2
first="${positionals[0]}"
last="${positionals[${#positionals[@]}-1]}"
if [[ "$first" == *:* ]]; then
  source_path="${first#*:}"
  if [[ "$recursive" == true ]]; then
    cp -R -- "$source_path" "$last"
  else
    cp -- "$source_path" "$last"
  fi
  if [[ "${MOCK_RETURN_CORRUPT:-false}" == true ]]; then
    printf 'corrupt\n' >>"$last/node-next-runtime-amd64.tar"
  fi
  if [[ "${MOCK_RETURN_IDENTITY_CORRUPT:-false}" == true ]]; then
    python3 -B - "$last/image-identity.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
record = json.loads(path.read_text(encoding="utf-8"))
record["config_digest"] = "sha256:" + "f" * 64
path.write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
    (
      cd -- "$last"
      while IFS= read -r name; do sha256sum -- "$name"; done < <(
        find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
      ) >SHA256SUMS
    )
  fi
else
  destination="${last#*:}"
  for ((index=0; index < ${#positionals[@]} - 1; index++)); do
    cp -- "${positionals[index]}" "$destination/"
  done
fi
MOCK
chmod 0755 "$test_root/bin/scp"

wrapper="$test_root/repo/deployment/scripts/07_build-node-next-runtime-on-emceedanko.sh"
run_wrapper() {
  local output="$1"
  shift
  PATH="$test_root/bin:$PATH" \
  ISHIKAWA_FAKE_REMOTE_HOME="$test_root/remote-home" \
  ISHIKAWA_FAKE_REMOTE_BIN="$test_root/remote-bin" \
  ISHIKAWA_SCRIPT07_REPORT_ROOT="$test_root/reports" \
  MOCK_DOCKER_ROOT="$test_root/remote-docker-root" \
  MOCK_IMAGE_MARKER="$test_root/image-retained" \
    bash "$wrapper" --run --target FakeEmcee "$@" >"$output" 2>&1
}

validation_output="$(PATH="$test_root/bin:$PATH" bash "$wrapper" --validate-only --target FakeEmcee 2>&1)" \
  || fail validate_only_failed
grep -Fxq 'script_07_node_next_runtime_build=ready' <<<"$validation_output" \
  || fail validate_only_ready_marker_missing
grep -Fq 'target_contact=false;target_mutation=false' <<<"$validation_output" \
  || fail validate_only_contact_contract_missing

run_wrapper "$test_root/first.txt" \
  || { sed -n '1,240p' "$test_root/first.txt" >&2; fail first_native_build_failed; }
grep -Fxq 'script_07_node_next_runtime_build=pass' "$test_root/first.txt" \
  || fail first_pass_marker_missing
handoff="$test_root/repo/local/artifacts/node-next-runtime-current"
[[ -d "$handoff" && ! -L "$handoff" ]] || fail local_handoff_missing
(
  cd -- "$handoff"
  sha256sum --check --strict SHA256SUMS >/dev/null
) || fail local_handoff_checksum_failed
jq -e '
  .npm == "11.19.1"
  and .yarn == "1.22.22"
  and (.config_digest | test("^sha256:[0-9a-f]{64}$"))
  and (.history_sha256 | test("^[0-9a-f]{64}$"))' \
  "$handoff/image-identity.json" >/dev/null || fail returned_identity_incomplete
jq -e '
  any(.components[]; .name == "npm" and .version == "11.19.1")
  and any(.components[]; .name == "yarn" and .version == "1.22.22")' \
  "$handoff/sbom.cdx.json" >/dev/null || fail returned_sbom_incomplete
jq -e '
  (.runtime_tools | length == 3)
  and any(.runtime_tools[]; .name == "node" and .version == "24.22.1")
  and any(.runtime_tools[]; .name == "npm" and .version == "11.19.1")
  and any(.runtime_tools[]; .name == "yarn" and .version == "1.22.22")' \
  "$handoff/licenses.json" >/dev/null || fail returned_license_inventory_incomplete
[[ -f "$test_root/image-retained" ]] || fail remote_image_not_retained
find /tmp -maxdepth 1 -type d -name 'ishikawa-runtime-build-*' -print -quit \
  | grep -q . && fail remote_transfer_not_cleaned_after_success

run_wrapper "$test_root/second.txt" || fail exact_rerun_failed
grep -Fxq 'script_07_node_next_runtime_build=pass' "$test_root/second.txt" \
  || fail rerun_pass_marker_missing
[[ "$(find "$test_root/repo/local/artifacts/superseded" -mindepth 1 -maxdepth 1 -type d | wc -l)" == 1 ]] \
  || fail superseded_handoff_count_invalid

current_manifest_sha256="$(sha256sum -- "$handoff/SHA256SUMS" | awk '{print $1}')"
set +e
MOCK_BUILD_FAIL=true run_wrapper "$test_root/build-failure.txt"
build_failure_status="$?"
set -e
(( build_failure_status != 0 )) || fail nested_build_failure_reported_success
grep -Fq 'reason=image_build_failed' "$test_root/build-failure.txt" \
  || fail nested_build_failure_reason_missing
grep -Fxq 'script_07_node_next_runtime_build=blocked' "$test_root/build-failure.txt" \
  || fail nested_build_failure_result_missing
[[ "$(sha256sum -- "$handoff/SHA256SUMS" | awk '{print $1}')" == "$current_manifest_sha256" ]] \
  || fail nested_build_failure_changed_current
find /tmp -maxdepth 1 -type d -name 'ishikawa-runtime-build-*' -print -quit \
  | grep -q . && fail remote_transfer_not_cleaned_after_build_failure

set +e
MOCK_RETURN_CORRUPT=true run_wrapper "$test_root/corrupt-return.txt"
corrupt_return_status="$?"
set -e
(( corrupt_return_status != 0 )) || fail corrupt_return_reported_success
grep -Fq 'reason=fetched_handoff_checksum_failed' "$test_root/corrupt-return.txt" \
  || fail corrupt_return_reason_missing
[[ "$(sha256sum -- "$handoff/SHA256SUMS" | awk '{print $1}')" == "$current_manifest_sha256" ]] \
  || fail corrupt_return_changed_current
find /tmp -maxdepth 1 -type d -name 'ishikawa-runtime-build-*' -print -quit \
  | grep -q . && fail remote_transfer_not_cleaned_after_corrupt_return

set +e
MOCK_RETURN_IDENTITY_CORRUPT=true run_wrapper "$test_root/corrupt-identity.txt"
corrupt_identity_status="$?"
set -e
(( corrupt_identity_status != 0 )) || fail corrupt_identity_reported_success
grep -Fq 'reason=fetched_identity_invalid' "$test_root/corrupt-identity.txt" \
  || fail corrupt_identity_reason_missing
[[ "$(sha256sum -- "$handoff/SHA256SUMS" | awk '{print $1}')" == "$current_manifest_sha256" ]] \
  || fail corrupt_identity_changed_current
find /tmp -maxdepth 1 -type d -name 'ishikawa-runtime-build-*' -print -quit \
  | grep -q . && fail remote_transfer_not_cleaned_after_corrupt_identity

set +e
MOCK_REMOTE_HOST_FAIL=true run_wrapper "$test_root/host-failure.txt"
host_failure_status="$?"
set -e
(( host_failure_status != 0 )) || fail host_failure_reported_success
grep -Fq 'reason=build_host_mismatch' "$test_root/host-failure.txt" \
  || fail host_failure_reason_missing
[[ "$(sha256sum -- "$handoff/SHA256SUMS" | awk '{print $1}')" == "$current_manifest_sha256" ]] \
  || fail host_failure_changed_current

env \
  PATH="$test_root/bin:$PATH" \
  ISHIKAWA_FAKE_REMOTE_HOME="$test_root/remote-home" \
  ISHIKAWA_FAKE_REMOTE_BIN="$test_root/remote-bin" \
  ISHIKAWA_SCRIPT07_REPORT_ROOT="$test_root/reports" \
  MOCK_DOCKER_ROOT="$test_root/remote-docker-root" \
  MOCK_IMAGE_MARKER="$test_root/image-retained" \
  MOCK_BUILD_DELAY=60 \
  bash "$wrapper" --run --target FakeEmcee >"$test_root/interrupted.txt" 2>&1 &
wrapper_pid="$!"
build_seen=false
for _attempt in {1..100}; do
  if grep -Fq '[BUILD] state=start' "$test_root/interrupted.txt" 2>/dev/null; then
    build_seen=true
    break
  fi
  sleep 0.1
done
[[ "$build_seen" == true ]] \
  || { kill -TERM "$wrapper_pid" 2>/dev/null || true; fail interruption_stage_not_reached; }
kill -TERM "$wrapper_pid"
set +e
wait "$wrapper_pid"
interrupted_status="$?"
set -e
(( interrupted_status == 143 )) || fail interruption_status_invalid
grep -Fq 'reason=signal_termination' "$test_root/interrupted.txt" \
  || fail interruption_reason_missing
grep -Fxq 'script_07_node_next_runtime_build=blocked' "$test_root/interrupted.txt" \
  || fail interruption_result_missing
find /tmp -maxdepth 1 -type d -name 'ishikawa-runtime-build-*' -print -quit \
  | grep -q . && fail remote_transfer_not_cleaned_after_interruption

printf '%s\n' \
  'validate_only=pass;native_build=pass;artifact_return=pass;publication=pass;rerun=pass;supersession=pass' \
  'nested_build_failure=pass;return_checksum_refusal=pass;return_identity_refusal=pass;host_identity_refusal=pass;current_preservation=pass' \
  'signal_propagation=pass;remote_cleanup=pass'
printf '\nSCRIPT RESULT\nnative_runtime_build_wrapper_test=pass\n'

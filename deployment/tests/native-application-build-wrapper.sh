#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Exercise Script 08 end to end with deterministic SSH, Docker, and application
# builder doubles. No real host, Docker daemon, service, database, or network is
# contacted.

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
test_root="$(mktemp -d /tmp/ishikawa-script-08-test.XXXXXX)"

fail() {
  printf '\nSCRIPT RESULT\nnative_application_build_wrapper_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$test_root" == /tmp/ishikawa-script-08-test.* && -d "$test_root" ]] \
    && rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fixture="$test_root/repo"
mkdir -p -- \
  "$fixture/deployment/scripts" "$fixture/deployment/assets" \
  "$fixture/docs/decisions" "$fixture/docs/releases" \
  "$fixture/Ishikawa" "$fixture/local/artifacts/node-next-runtime-current" \
  "$test_root/bin" "$test_root/remote-bin" "$test_root/remote-docker-root" \
  "$test_root/reports"
cp -- "$repo_root/deployment/scripts/08_build-v1.3.1-application-on-emceedanko.sh" \
  "$fixture/deployment/scripts/"
cp -- "$repo_root/deployment/assets/build-v1.3.1-application-on-emceedanko" \
  "$fixture/deployment/assets/"
printf 'fixture application source\n' >"$fixture/Ishikawa/source.txt"
printf 'fixture license\n' >"$fixture/LICENSE"
printf 'fixture release readme\n' >"$fixture/deployment/assets/README-v1.3.1.md"
printf '#!/usr/bin/env bash\nexit 0\n' >"$fixture/deployment/assets/verify-ishikawa-release"
printf 'fixture decisions\n' >"$fixture/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md"
printf 'fixture carry record\n' >"$fixture/docs/releases/ISHIKAWA_ORG_LAB_CARRY_READINESS_CHECKLIST.md"
(cd -- "$fixture" && sha256sum Ishikawa/source.txt >docs/releases/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS)

cat >"$fixture/deployment/scripts/01_build-ishikawa-release.sh" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
mode="${1:-}"
if [[ "$mode" == --validate-only ]]; then
  printf '\nSCRIPT RESULT\nscript_01_build_ishikawa_release=ready\n'
  exit 0
fi
[[ "$mode" == --run ]] || exit 2
if [[ "${MOCK_APPLICATION_BUILD_FAIL:-false}" == true ]]; then
  printf 'FAILURE DETAIL\nstage=next_build\nreason=next_build_failed\ndetail=fixture\noperator_action=fixture\n' >&2
  printf '\nSCRIPT RESULT\nscript_01_build_ishikawa_release=blocked\n' >&2
  exit 41
fi
if [[ "${MOCK_APPLICATION_BUILD_DELAY:-0}" != 0 ]]; then
  trap 'exit 143' TERM
  sleep "$MOCK_APPLICATION_BUILD_DELAY"
fi
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
handoff="$root/local/artifacts/ishikawa-v1.3.1-candidate-current"
work="$(mktemp -d /tmp/mock-ishikawa-app.XXXXXX)"
mkdir -p -- "$handoff" "$work/ishikawa-v1.3.1"
printf '#!/usr/bin/env bash\nprintf "ishikawa_release_verification=pass\\n"\n' \
  >"$work/ishikawa-v1.3.1/verify-ishikawa-release"
chmod 0755 "$work/ishikawa-v1.3.1/verify-ishikawa-release"
tar -czf "$handoff/ishikawa-v1.3.1.tar.gz" -C "$work" ishikawa-v1.3.1
rm -rf -- "$work"
archive_sha="$(sha256sum "$handoff/ishikawa-v1.3.1.tar.gz" | awk '{print $1}')"
(cd -- "$handoff" && sha256sum ishikawa-v1.3.1.tar.gz >ishikawa-v1.3.1.tar.gz.sha256)
printf '%064d  Ishikawa/source.txt\n' 0 >"$handoff/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS"
printf '{"archive_sha256":"%s","coding_standard":"pass","deterministic_archive":true,"fresh_install":"pass","human_ui_validation":"pending_exact_candidate_requalification","release":"Ishikawa v1.3.1 candidate"}\n' \
  "$archive_sha" >"$handoff/release-receipt.json"
printf '{"bomFormat":"CycloneDX"}\n' >"$handoff/application-sbom.cdx.json"
printf '{"application_license":"Apache-2.0"}\n' >"$handoff/application-license.json"
(
  cd -- "$handoff"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
  ) >SHA256SUMS
)
printf '\nSCRIPT RESULT\nscript_01_build_ishikawa_release=pass\n'
MOCK
chmod 0755 \
  "$fixture/deployment/scripts/01_build-ishikawa-release.sh" \
  "$fixture/deployment/assets/build-v1.3.1-application-on-emceedanko" \
  "$fixture/deployment/assets/verify-ishikawa-release"

runtime="$fixture/local/artifacts/node-next-runtime-current"
mkdir -p -- "$test_root/image/blobs/sha256"
printf '%s\n' \
  '{"architecture":"amd64","os":"linux","config":{"WorkingDir":"/opt/nextjs","Cmd":["next","--help"]},"rootfs":{"type":"layers","diff_ids":["sha256:0000000000000000000000000000000000000000000000000000000000000004"]},"history":[{"created_by":"generic runtime layer"}]}' \
  >"$test_root/image/config.json"
config_hex="$(sha256sum "$test_root/image/config.json" | awk '{print $1}')"
history_sha="$(jq -cS .history "$test_root/image/config.json" | sha256sum | awk '{print $1}')"
printf 'mock compressed layer\n' >"$test_root/image/layer"
layer_hex="$(sha256sum "$test_root/image/layer" | awk '{print $1}')"
mv -- "$test_root/image/config.json" "$test_root/image/blobs/sha256/$config_hex"
mv -- "$test_root/image/layer" "$test_root/image/blobs/sha256/$layer_hex"
printf '[{"Config":"blobs/sha256/%s","RepoTags":["node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64"],"Layers":["blobs/sha256/%s"]}]\n' \
  "$config_hex" "$layer_hex" >"$test_root/image/manifest.json"
tar -cf "$runtime/node-next-runtime-amd64.tar" -C "$test_root/image" manifest.json blobs
archive_sha="$(sha256sum "$runtime/node-next-runtime-amd64.tar" | awk '{print $1}')"
(cd -- "$runtime" && sha256sum node-next-runtime-amd64.tar >node-next-runtime-amd64.tar.sha256)
python3 -B - "$runtime/image-identity.json" "$runtime/build-receipt.json" \
  "$archive_sha" "$config_hex" "$history_sha" <<'PY'
import json
import sys
from pathlib import Path
identity_path, receipt_path, archive, config, history = sys.argv[1:]
reference = "node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64"
identity = {
    "application_in_image": False, "archive_sha256": archive,
    "architecture": "amd64", "config_digest": "sha256:" + config,
    "generated_next_in_image": False, "history_sha256": history,
    "image_id": "sha256:" + "0" * 63 + "7", "image_reference": reference,
    "next": "16.4.3", "node": "24.22.1", "npm": "11.19.1",
    "platform": "linux/amd64", "react": "19.2.9", "react_dom": "19.2.9",
    "schema": "node-next-runtime-image.v1", "yarn": "1.22.22",
}
receipt = {key: identity[key] for key in (
    "archive_sha256", "architecture", "config_digest", "generated_next_in_image",
    "history_sha256", "image_id", "image_reference", "platform",
)}
receipt.update({"application_in_image": False, "schema": "node-next-runtime-build-receipt.v1"})
for path, value in ((Path(identity_path), identity), (Path(receipt_path), receipt)):
    path.write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
(
  cd -- "$runtime"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
  ) >SHA256SUMS
)

cat >"$test_root/remote-bin/hostname" <<'MOCK'
#!/usr/bin/env bash
[[ "${1:-}" == -s ]] || exit 2
[[ "${MOCK_REMOTE_HOST_FAIL:-false}" != true ]] && printf 'EmceeDanko\n' || printf 'WrongHost\n'
MOCK
cat >"$test_root/remote-bin/uname" <<'MOCK'
#!/usr/bin/env bash
[[ "${1:-}" == -m ]] || exit 2
printf 'x86_64\n'
MOCK
cat >"$test_root/remote-bin/dpkg" <<'MOCK'
#!/usr/bin/env bash
[[ "${1:-}" == --print-architecture ]] || exit 2
printf 'amd64\n'
MOCK
cat >"$test_root/remote-bin/nproc" <<'MOCK'
#!/usr/bin/env bash
printf '8\n'
MOCK
cat >"$test_root/remote-bin/df" <<'MOCK'
#!/usr/bin/env bash
selected="${!#}"
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf 'mock 20971520 0 10485760 0%% %s\n' "$selected"
MOCK
cat >"$test_root/remote-bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
  info) exit 0 ;;
  image)
    [[ "${2:-}" == inspect ]] || exit 92
    case "$*" in
      *'{{.Id}}'*)
        [[ "${MOCK_REMOTE_IMAGE_FAIL:-false}" != true ]] \
          && printf 'sha256:%064d\n' 7 || printf 'sha256:%064d\n' 8 ;;
      *'{{.Architecture}}'*) printf 'amd64\n' ;;
      *) printf '{}\n' ;;
    esac
    ;;
  *) exit 93 ;;
esac
MOCK
chmod 0755 "$test_root/remote-bin/"*

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
MOCK_APPLICATION_BUILD_FAIL="${MOCK_APPLICATION_BUILD_FAIL:-false}" \
MOCK_APPLICATION_BUILD_DELAY="${MOCK_APPLICATION_BUILD_DELAY:-0}" \
MOCK_REMOTE_HOST_FAIL="${MOCK_REMOTE_HOST_FAIL:-false}" \
MOCK_REMOTE_IMAGE_FAIL="${MOCK_REMOTE_IMAGE_FAIL:-false}" \
  bash -c "$remote_command"
MOCK
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
  [[ "$recursive" == true ]] && cp -R -- "$source_path" "$last" || cp -- "$source_path" "$last"
  if [[ "${MOCK_RETURN_CORRUPT:-false}" == true ]]; then
    printf 'corrupt\n' >>"$last/ishikawa-v1.3.1.tar.gz"
  fi
  if [[ "${MOCK_RETURN_RECEIPT_CORRUPT:-false}" == true ]]; then
    python3 -B - "$last/release-receipt.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
record = json.loads(path.read_text())
record["human_ui_validation"] = "accepted_without_requalification"
path.write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")
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
chmod 0755 "$test_root/bin/"*

wrapper="$fixture/deployment/scripts/08_build-v1.3.1-application-on-emceedanko.sh"
run_wrapper() {
  local output="$1"
  shift
  PATH="$test_root/bin:$PATH" \
  ISHIKAWA_FAKE_REMOTE_HOME="$test_root/remote-home" \
  ISHIKAWA_FAKE_REMOTE_BIN="$test_root/remote-bin" \
  ISHIKAWA_SCRIPT08_REPORT_ROOT="$test_root/reports" \
    bash "$wrapper" --run --target FakeEmcee "$@" >"$output" 2>&1
}

validation_output="$(PATH="$test_root/bin:$PATH" bash "$wrapper" --validate-only --target FakeEmcee 2>&1)" \
  || fail validate_only_failed
grep -Fxq 'script_08_v1_3_1_application_build=ready' <<<"$validation_output" \
  || fail validate_only_marker_missing
grep -Fq 'target_contact=false;target_mutation=false' <<<"$validation_output" \
  || fail validate_only_contact_contract_missing

run_wrapper "$test_root/first.txt" \
  || { sed -n '1,260p' "$test_root/first.txt" >&2; fail first_native_build_failed; }
grep -Fxq 'script_08_v1_3_1_application_build=pass' "$test_root/first.txt" \
  || fail first_pass_marker_missing
handoff="$fixture/local/artifacts/ishikawa-v1.3.1-candidate-current"
[[ -d "$handoff" && ! -L "$handoff" ]] || fail local_handoff_missing
(cd -- "$handoff" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || fail local_handoff_checksum_failed
find /tmp -maxdepth 1 -type d -name 'ishikawa-application-build-20*' -print -quit \
  | grep -q . && fail remote_transfer_not_cleaned_after_success

run_wrapper "$test_root/second.txt" || fail exact_rerun_failed
grep -Fxq 'script_08_v1_3_1_application_build=pass' "$test_root/second.txt" \
  || fail rerun_pass_marker_missing
[[ "$(find "$fixture/local/artifacts/superseded" -mindepth 1 -maxdepth 1 -type d | wc -l)" == 1 ]] \
  || fail superseded_handoff_count_invalid
current_manifest_sha="$(sha256sum "$handoff/SHA256SUMS" | awk '{print $1}')"

set +e
MOCK_APPLICATION_BUILD_FAIL=true run_wrapper "$test_root/build-failure.txt"
build_failure_status="$?"
set -e
(( build_failure_status != 0 )) || fail build_failure_reported_success
grep -Fq 'reason=next_build_failed' "$test_root/build-failure.txt" \
  || fail build_failure_reason_missing
[[ "$(sha256sum "$handoff/SHA256SUMS" | awk '{print $1}')" == "$current_manifest_sha" ]] \
  || fail build_failure_changed_current

set +e
MOCK_REMOTE_IMAGE_FAIL=true run_wrapper "$test_root/image-failure.txt"
image_failure_status="$?"
set -e
(( image_failure_status != 0 )) || fail image_failure_reported_success
grep -Fq 'reason=retained_runtime_image_mismatch' "$test_root/image-failure.txt" \
  || fail image_failure_reason_missing

set +e
MOCK_RETURN_CORRUPT=true run_wrapper "$test_root/corrupt-return.txt"
corrupt_return_status="$?"
set -e
(( corrupt_return_status != 0 )) || fail corrupt_return_reported_success
grep -Fq 'reason=fetched_handoff_checksum_failed' "$test_root/corrupt-return.txt" \
  || fail corrupt_return_reason_missing

set +e
MOCK_RETURN_RECEIPT_CORRUPT=true run_wrapper "$test_root/corrupt-receipt.txt"
corrupt_receipt_status="$?"
set -e
(( corrupt_receipt_status != 0 )) || fail corrupt_receipt_reported_success
grep -Fq 'reason=fetched_release_receipt_invalid' "$test_root/corrupt-receipt.txt" \
  || fail corrupt_receipt_reason_missing

set +e
MOCK_REMOTE_HOST_FAIL=true run_wrapper "$test_root/host-failure.txt"
host_failure_status="$?"
set -e
(( host_failure_status != 0 )) || fail host_failure_reported_success
grep -Fq 'reason=build_host_mismatch' "$test_root/host-failure.txt" \
  || fail host_failure_reason_missing

env \
  PATH="$test_root/bin:$PATH" \
  ISHIKAWA_FAKE_REMOTE_HOME="$test_root/remote-home" \
  ISHIKAWA_FAKE_REMOTE_BIN="$test_root/remote-bin" \
  ISHIKAWA_SCRIPT08_REPORT_ROOT="$test_root/reports" \
  MOCK_APPLICATION_BUILD_DELAY=60 \
  bash "$wrapper" --run --target FakeEmcee >"$test_root/interrupted.txt" 2>&1 &
wrapper_pid="$!"
build_seen=false
for _attempt in {1..150}; do
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
find /tmp -maxdepth 1 -type d -name 'ishikawa-application-build-20*' -print -quit \
  | grep -q . && fail remote_transfer_not_cleaned_after_interruption

printf '%s\n' \
  'validate_only=pass;native_build=pass;artifact_return=pass;publication=pass;rerun=pass;supersession=pass' \
  'nested_build_failure=pass;runtime_image_mismatch=pass;return_checksum_refusal=pass;return_receipt_refusal=pass' \
  'host_identity_refusal=pass;current_preservation=pass;signal_propagation=pass;remote_cleanup=pass'
printf '\nSCRIPT RESULT\nnative_application_build_wrapper_test=pass\n'

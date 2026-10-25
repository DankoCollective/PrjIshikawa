#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Exercise Script 04 end to end without contacting a lab host.
#
# Mental model:
#   Replace only SSH/SCP and bounded target-inspection commands, run the real
#   wrapper and target helper, then prove fresh staging, exact rerun, drift
#   rejection, milestone order, nested failure propagation, and cleanup.
#
# Inputs or prerequisites:
#   Current application/corpus handoffs and a completed Script 04 implementation.
#
# Outputs or artifact lane:
#   Temporary files under /tmp only; no remote contact or repository mutation.
#
# Usage:
#   bash ./deployment/tests/stage-candidate-wrapper.sh

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly wrapper="$repo_root/deployment/scripts/04_stage-v1.3-candidate-on-emceedanko.sh"

fail() {
  printf '\nSCRIPT RESULT\nstage_candidate_wrapper_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

[[ -f "$wrapper" && ! -L "$wrapper" && -r "$wrapper" ]] || fail wrapper_unsafe
bash -n "$wrapper" || fail wrapper_syntax_invalid

test_root="$(mktemp -d /tmp/ishikawa-stage-wrapper-test.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$test_root" == /tmp/ishikawa-stage-wrapper-test.* && -d "$test_root" ]] \
    && rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$test_root/bin" "$test_root/remote-bin" \
  "$test_root/remote-home/Documents/Ishikawa" \
  "$test_root/remote-home/Documents/Ishikawa-before-v1.2" \
  "$test_root/reports"

write_command() {
  local directory="$1" name="$2" body="$3"
  printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n%s\n' "$body" >"$directory/$name"
  chmod 0700 "$directory/$name"
}

write_command "$test_root/remote-bin" hostname "printf 'EmceeDanko\\n'"
write_command "$test_root/remote-bin" dpkg "[[ \"\${1:-}\" == --print-architecture ]] && printf 'amd64\\n'"
write_command "$test_root/remote-bin" uname "[[ \"\${1:-}\" == -m ]] && printf 'x86_64\\n'"
write_command "$test_root/remote-bin" systemctl "[[ \"\${1:-}\" == --user && \"\${2:-}\" == is-active ]] && printf 'active\\n'"
write_command "$test_root/remote-bin" ss "printf 'LISTEN 0 4096 127.0.0.1:1384 0.0.0.0:*\\nLISTEN 0 4096 127.0.0.1:3000 0.0.0.0:*\\n'"

cat >"$test_root/bin/ssh" <<'SH'
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
if [[ "$remote_command" == *'bash ./stage-v1.3-candidate'* \
    && "${ISHIKAWA_FAKE_STAGE_DELAY:-0}" != 0 ]]; then
  trap 'exit 143' TERM
  sleep "$ISHIKAWA_FAKE_STAGE_DELAY"
fi
HOME="$ISHIKAWA_FAKE_REMOTE_HOME" \
PATH="$ISHIKAWA_FAKE_REMOTE_BIN:/usr/bin:/bin" \
  bash -c "$remote_command"
SH
chmod 0700 "$test_root/bin/ssh"

cat >"$test_root/bin/scp" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
positionals=()
while (( $# > 0 )); do
  case "$1" in
    -o|-i) shift 2 ;;
    -*) shift ;;
    *) positionals+=("$1"); shift ;;
  esac
done
(( ${#positionals[@]} >= 2 )) || exit 2
first="${positionals[0]}"
last="${positionals[${#positionals[@]}-1]}"
if [[ "$first" == *:* ]]; then
  cp -- "${first#*:}" "$last"
else
  destination="${last#*:}"
  for ((index=0; index < ${#positionals[@]} - 1; index++)); do
    cp -- "${positionals[index]}" "$destination/"
  done
fi
SH
chmod 0700 "$test_root/bin/scp"

cat >"$test_root/inventory.txt" <<'EOF'
hostname_match=true
active_application_root=present
prior_rollback_root=present
v1_3_candidate_root=absent
unit_retrieval_api_load=loaded;unit_retrieval_api_active=active;unit_retrieval_api_enabled=static
tcp_port_3000_listening=true
tcp_port_1384_listening=true
ishikawa_application_host_inventory=pass
script_02_inventory_emceedanko=pass
EOF

run_wrapper() {
  local output="$1"
  local stage_delay="${2:-0}"
  local replace_unqualified_candidate="${3:-false}"
  local replace_qualification_inputs="${4:-false}"
  local replacement_arguments=()
  [[ "$replace_unqualified_candidate" != true ]] || replacement_arguments+=(--replace-unqualified-candidate)
  [[ "$replace_qualification_inputs" != true ]] || replacement_arguments+=(--replace-qualification-inputs)
  PATH="$test_root/bin:$PATH" \
  ISHIKAWA_FAKE_REMOTE_HOME="$test_root/remote-home" \
  ISHIKAWA_FAKE_REMOTE_BIN="$test_root/remote-bin" \
  ISHIKAWA_SCRIPT04_REPORT_ROOT="$test_root/reports" \
  ISHIKAWA_SCRIPT04_INVENTORY_REPORT="$test_root/inventory.txt" \
  ISHIKAWA_FAKE_STAGE_DELAY="$stage_delay" \
    bash "$wrapper" --run --target FakeEmcee "${replacement_arguments[@]}" >"$output" 2>&1
}

run_wrapper "$test_root/first.txt" || fail fresh_wrapper_run_failed
grep -Fxq 'script_04_stage_v1_3_candidate_on_emceedanko=pass' "$test_root/first.txt" \
  || fail fresh_pass_marker_missing
grep -Fq 'candidate_action=installed_new' "$test_root/first.txt" \
  || fail fresh_action_missing

PYTHONDONTWRITEBYTECODE=1 python3 -B - "$test_root/first.txt" <<'PY' \
  || fail milestone_order_invalid
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
tags = ("[READINESS]", "[AUTHENTICATION]", "[TRANSFER]", "[CANDIDATE]", "[CLEANUP]", "[SUMMARY]")
positions = [text.index(tag) for tag in tags]
if positions != sorted(positions):
    raise SystemExit(1)
PY

run_wrapper "$test_root/second.txt" || fail exact_rerun_failed
grep -Fq 'candidate_action=reused_exact' "$test_root/second.txt" \
  || fail exact_reuse_action_missing
grep -Fq 'corpus_action=reused_exact' "$test_root/second.txt" \
  || fail exact_corpus_reuse_missing

printf 'corrupt\n' >>"$test_root/remote-home/Documents/Ishikawa-v1.3/config/product.yaml"
set +e
run_wrapper "$test_root/third.txt"
third_status="$?"
set -e
(( third_status != 0 )) || fail nested_failure_reported_success
grep -Fq 'reason=existing_candidate_identity_mismatch' "$test_root/third.txt" \
  || fail nested_failure_reason_missing
grep -Fxq 'script_04_stage_v1_3_candidate_on_emceedanko=blocked' "$test_root/third.txt" \
  || fail nested_block_marker_missing
grep -Fq corrupt "$test_root/remote-home/Documents/Ishikawa-v1.3/config/product.yaml" \
  || fail drifted_candidate_mutated
[[ -d "$test_root/remote-home/Documents/Ishikawa" \
    && -d "$test_root/remote-home/Documents/Ishikawa-before-v1.2" ]] \
  || fail accepted_v1_2_state_removed

run_wrapper "$test_root/replacement.txt" 0 true || fail explicit_replacement_failed
grep -Fq 'candidate_action=replaced_unqualified' "$test_root/replacement.txt" \
  || fail explicit_replacement_action_missing
grep -Fq corrupt "$test_root/remote-home/Documents/Ishikawa-v1.3/config/product.yaml" \
  && fail explicit_replacement_retained_drift

printf 'corrupt\n' >>"$test_root/remote-home/Documents/Ishikawa-v1.3-qualification-inputs/qualification-corpus-v3.tar.gz"
run_wrapper "$test_root/input-replacement.txt" 0 false true \
  || fail explicit_qualification_input_replacement_failed
grep -Fq 'corpus_action=replaced_unqualified' "$test_root/input-replacement.txt" \
  || fail explicit_qualification_input_replacement_action_missing

rm -rf -- "$test_root/remote-home/Documents/Ishikawa-v1.3" \
  "$test_root/remote-home/Documents/Ishikawa-v1.3-qualification-inputs"
env \
  PATH="$test_root/bin:$PATH" \
  ISHIKAWA_FAKE_REMOTE_HOME="$test_root/remote-home" \
  ISHIKAWA_FAKE_REMOTE_BIN="$test_root/remote-bin" \
  ISHIKAWA_SCRIPT04_REPORT_ROOT="$test_root/reports" \
  ISHIKAWA_SCRIPT04_INVENTORY_REPORT="$test_root/inventory.txt" \
  ISHIKAWA_FAKE_STAGE_DELAY=60 \
  bash "$wrapper" --run --target FakeEmcee >"$test_root/interrupted.txt" 2>&1 &
wrapper_pid="$!"
candidate_seen=false
for _attempt in {1..100}; do
  if grep -Fq '[CANDIDATE] state=start' "$test_root/interrupted.txt" 2>/dev/null; then
    candidate_seen=true
    break
  fi
  sleep 0.1
done
[[ "$candidate_seen" == true ]] || { kill -TERM "$wrapper_pid" 2>/dev/null || true; fail interruption_stage_not_reached; }
kill -TERM "$wrapper_pid"
set +e
wait "$wrapper_pid"
interrupted_status="$?"
set -e
(( interrupted_status == 143 )) || fail interruption_status_invalid
grep -Fq 'reason=signal_termination' "$test_root/interrupted.txt" \
  || fail interruption_reason_missing
grep -Fxq 'script_04_stage_v1_3_candidate_on_emceedanko=blocked' "$test_root/interrupted.txt" \
  || fail interruption_block_marker_missing
[[ ! -e "$test_root/remote-home/Documents/Ishikawa-v1.3" \
    && ! -e "$test_root/remote-home/Documents/Ishikawa-v1.3-qualification-inputs" ]] \
  || fail interruption_created_candidate_state

printf '%s\n' \
  'wrapper_fresh_stage=pass;wrapper_exact_rerun=pass;wrapper_drift_rejection=pass;wrapper_explicit_unqualified_replacement=pass' \
  'milestone_order=pass;nested_failure_propagation=pass;signal_status=pass;remote_cleanup=pass'
printf '\nSCRIPT RESULT\nstage_candidate_wrapper_test=pass\n'

#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Measure the accepted Script 27 chunk candidates with the authoritative
#   Nomic tokenizer, create their unmodified Nomic embeddings, and return one
#   locally validated protected artifact. The target receives neutral helper
#   names and synthetic inputs only; no repository or decision-list jargon.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/28_qualify_nomic_chunk_embeddings.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Explicitly authorize target qualification.' \
    '  --target USER@HOST         Approved SSH destination.' \
    '  --identity-file PATH       Function-specific SSH private key.' \
    '  --expected-hostname NAME   Exact target hostname.' \
    '  --report-root PATH         Absolute local content-free report directory.' \
    '  --artifact-root PATH       Absolute local protected-artifact directory.' \
    '  --validate-only            Validate all local sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly TARGET_SHELL="$SCRIPT_DIR/qualify-chunk-embeddings"
readonly TARGET_PYTHON="$SCRIPT_DIR/qualify_chunk_embeddings.py"
readonly LOCAL_EVALUATOR="$SCRIPT_DIR/evaluate_chunk_embeddings.py"
readonly EMBEDDING_TESTS="$ISHIKAWA_ROOT/tests/embedding_qualification_checks.py"
readonly CHUNKING_TESTS="$ISHIKAWA_ROOT/tests/chunking_checks.py"
readonly NORMALIZATION_TESTS="$ISHIKAWA_ROOT/tests/normalization_checks.py"
readonly BASE_TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly CHUNK_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/chunking/structural_chunk_candidates_20261019T214924Z.json"
readonly CHUNK_SIDECAR="$CHUNK_ARTIFACT.sha256"
readonly CHUNK_RECEIPT="$REPO_ROOT/local/reports/ishikawa-chunking/chunking_20261019T214924Z_q1twDK.txt"
readonly ACCEPTED_NOMIC_REPORT="$REPO_ROOT/local/reports/embedding-service-verification/embedding_service_verification_20261018T235456Z_LnHgPN.txt"
readonly CHUNK_SHA256='0b351ef579ff134a5fb1fb5f37843d5461a100f1fc2d803e278a9b20d3126548'
readonly CHUNK_SIDECAR_SHA256='8da9758d2203605063cdcd65b3d63eb907783345a7e5fbad4dc38c32994af969'
readonly CHUNK_RECEIPT_SHA256='18dcc83979426951b3bfa308ec3f756cdb4657cde1a21a3ef0d5a1a7f30d6661'
readonly ACCEPTED_NOMIC_REPORT_SHA256='2309ef678501275fcb74b976c30ad110439fc1958af4694a9438b077a106c9bf'
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-embedding-qualification"
readonly DEFAULT_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/embeddings"

target=""
identity_file=""
expected_hostname=""
report_root="$DEFAULT_REPORT_ROOT"
artifact_root="$DEFAULT_ARTIFACT_ROOT"
run_authorized=false
validate_only=false

while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --target) target="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2
  exit 2
}
for destination in "$report_root" "$artifact_root"; do
  [[ "$destination" == /* && ! -L "$destination" ]] || {
    printf 'BLOCKED: local output roots must be absolute and not symlinks.\n' >&2
    exit 2
  }
done
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || {
    printf 'BLOCKED: identity file is unsafe.\n' >&2
    exit 2
  }
fi
for required in awk bash basename cat chmod cp date grep mkdir mktemp python3 rm scp sha256sum ssh stat tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in \
  "$TARGET_SHELL" "$TARGET_PYTHON" "$LOCAL_EVALUATOR" "$EMBEDDING_TESTS" \
  "$CHUNKING_TESTS" "$NORMALIZATION_TESTS" "$BASE_TEST_RUNNER" \
  "$CHUNK_ARTIFACT" "$CHUNK_SIDECAR" "$CHUNK_RECEIPT" "$ACCEPTED_NOMIC_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: required Script 28 input is missing or unsafe.\n' >&2
    exit 2
  }
done

check_sha256() {
  local path="$1" expected="$2" label="$3"
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected" ]] || {
    printf 'BLOCKED: %s checksum mismatch.\n' "$label" >&2
    exit 2
  }
}
check_sha256 "$CHUNK_ARTIFACT" "$CHUNK_SHA256" 'accepted chunk artifact'
check_sha256 "$CHUNK_SIDECAR" "$CHUNK_SIDECAR_SHA256" 'accepted chunk sidecar'
check_sha256 "$CHUNK_RECEIPT" "$CHUNK_RECEIPT_SHA256" 'accepted chunk receipt'
check_sha256 "$ACCEPTED_NOMIC_REPORT" "$ACCEPTED_NOMIC_REPORT_SHA256" 'accepted Nomic report'
(
  cd -- "$(dirname -- "$CHUNK_ARTIFACT")"
  sha256sum -c -- "$(basename -- "$CHUNK_SIDECAR")" >/dev/null
)
grep -Fxq 'script_27_chunking=pass;next_gate=nomic_token_measurement_and_embedding' "$CHUNK_RECEIPT" || {
  printf 'BLOCKED: accepted Script 27 routing fact is absent.\n' >&2
  exit 2
}
for fact in \
  '[embedding-verification] artifacts=pass model_revision=e9b6763023c676ca8431644204f50c2b100d9aab model_sha256=9e7d262b1fe5ea350782829496efa831901b77486bbde1cea54a4c822d010d5c tokenizer_sha256=d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66 pooling=mean_tokens configured_dtype=float32 license=apache-2.0' \
  '[embedding-verification] identity=pass model=nomic-ai/nomic-embed-text-v1.5 advertised_max_model_len=2048' \
  '[embedding-verification] tokenizer_agreement=pass count_mode=with_special_tokens' \
  '[embedding-verification] embedding=pass dimensions=768 finite_vectors=pass cardinality=pass repeat_max_abs_delta=0 batch_max_abs_delta=0 numeric_tolerance=1e-05' \
  'embedding_service_verification_wrapper=pass;local_report=/mnt/g/dankorepos/prj00dankodeux/local/reports/embedding-service-verification/embedding_service_verification_20261018T235456Z_LnHgPN.txt;next_gate=review_local_report'; do
  # The accepted attended SSH receipt preserves carriage returns on target
  # output lines. Match the complete required fact as a fixed substring.
  grep -Fq "$fact" "$ACCEPTED_NOMIC_REPORT" || {
    printf 'BLOCKED: required accepted Nomic fact is absent.\n' >&2
    exit 2
  }
done

bash -n "$TARGET_SHELL" "$BASE_TEST_RUNNER"
python3 -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$TARGET_PYTHON" "$LOCAL_EVALUATOR" "$EMBEDDING_TESTS" "$CHUNKING_TESTS" "$NORMALIZATION_TESTS"
python3 "$TARGET_PYTHON" --self-test
python3 "$LOCAL_EVALUATOR" --self-test
for neutral_source in "$TARGET_SHELL" "$TARGET_PYTHON"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|AgentDanko|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-28.XXXXXX)"
report_path=""
remote_root=""
remote_created=false
master_started=false
ssh_args=()

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}

cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then
      emit 'cleanup_remote_temporary_files=removed'
    else
      emit "cleanup_remote_temporary_files=review_required;exit_code=$cleanup_code"
      status=1
    fi
  else
    emit 'cleanup_remote_temporary_files=not_required'
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-28.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_test_gate() {
  local result_path="$1" expected_count="$2" label="$3"
  shift 3
  set +e
  "$@" >"$result_path" 2>&1
  local status=$?
  set -e
  if (( status != 0 )); then
    cat "$result_path" >&2
    printf 'script_28_embedding=blocked;reason=%s_test_failure\n' "$label" >&2
    exit 1
  fi
  grep -Fq "Ran $expected_count tests" "$result_path" || {
    printf 'script_28_embedding=blocked;reason=%s_test_count_mismatch\n' "$label" >&2
    exit 1
  }
  grep -Fxq 'OK' "$result_path" || {
    printf 'script_28_embedding=blocked;reason=%s_pass_marker_absent\n' "$label" >&2
    exit 1
  }
}

base_result="$work_root/base-tests.txt"
set +e
bash "$BASE_TEST_RUNNER" >"$base_result" 2>&1
base_code=$?
set -e
if (( base_code != 0 )); then
  cat "$base_result" >&2
  printf 'script_28_embedding=blocked;reason=base_regression\n' >&2
  exit 1
fi
grep -Fq 'Ran 64 tests' "$base_result" || { printf 'script_28_embedding=blocked;reason=base_test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$base_result" || { printf 'script_28_embedding=blocked;reason=base_pass_marker_absent\n' >&2; exit 1; }
run_test_gate "$work_root/normalization-tests.txt" 13 normalization \
  env PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 "$NORMALIZATION_TESTS" -v
run_test_gate "$work_root/chunking-tests.txt" 12 chunking \
  env PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 "$CHUNKING_TESTS" -v
run_test_gate "$work_root/embedding-tests.txt" 8 embedding \
  env PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 "$EMBEDDING_TESTS" -v

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
shell_sha256="$(sha256sum "$TARGET_SHELL" | awk '{print $1}')"
qualifier_sha256="$(sha256sum "$TARGET_PYTHON" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$LOCAL_EVALUATOR" | awk '{print $1}')"
tests_sha256="$(sha256sum "$EMBEDDING_TESTS" | awk '{print $1}')"
payload_manifest="$work_root/payload.sha256"
printf '%s  %s\n' \
  "$shell_sha256" 'qualify-chunk-embeddings' \
  "$qualifier_sha256" 'qualify_chunk_embeddings.py' \
  "$CHUNK_SHA256" 'chunk-candidates.json' >"$payload_manifest"
payload_manifest_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_nomic_chunk_embedding_qualification_source' \
    'target_contact=false;model_call=false;retained_artifact=false' \
    "script_sha256=$script_sha256" \
    "target_shell_sha256=$shell_sha256;qualifier_sha256=$qualifier_sha256" \
    "evaluator_sha256=$evaluator_sha256;embedding_tests_sha256=$tests_sha256" \
    "payload_manifest_sha256=$payload_manifest_sha256;payload_members=3" \
    "chunk_candidate_sha256=$CHUNK_SHA256;accepted_nomic_report_sha256=$ACCEPTED_NOMIC_REPORT_SHA256" \
    'base_tests=64;normalization_tests=13;chunking_tests=12;embedding_tests=8;failures=0;errors=0' \
    'script_28_embedding_source=pass'
  exit 0
fi

# Resolve only the nonsecret connection fields used by the already accepted
# embedding-host wrapper. This does not source or execute the values file.
site_values_path="$REPO_ROOT/local/site_values.env"
if [[ -f "$site_values_path" && -z "$target" && -z "$identity_file" && -z "$expected_hostname" ]]; then
  selected_site_values=()
  mapfile -d '' -t selected_site_values < <(python3 -B - "$site_values_path" <<'PY'
import os
import re
import sys

wanted = {
    "LOCAL_RUNTIME_USER", "DANKO_00_SSH_ADDRESS", "DANKO_00_RESERVED_LAN_IP",
    "TARGET_RESERVED_LAN_IP", "DANKO_00_TARGET", "DANKO_00_SSH_KEY",
    "DANKO_00_IDENTITY_FILE", "DANKOSURFACE_TO_00DANKO_IDENTITY_FILE",
    "DANKO_00_EXPECTED_HOSTNAME", "TARGET_STABLE_LAN_NAME",
}
values = {}
assignment = re.compile(r"^([A-Z][A-Z0-9_]*)=(.*)$")
with open(sys.argv[1], "r", encoding="utf-8") as stream:
    for raw_line in stream:
        match = assignment.fullmatch(raw_line.rstrip("\n"))
        if not match or match.group(1) not in wanted:
            continue
        key, value = match.groups()
        if key in values or "\x00" in value or "\r" in value:
            raise SystemExit(1)
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if value.startswith("${HOME}/"):
            value = os.path.join(os.environ["HOME"], value[len("${HOME}/"):])
        elif value.startswith("$HOME/"):
            value = os.path.join(os.environ["HOME"], value[len("$HOME/"):])
        values[key] = value
user = values.get("LOCAL_RUNTIME_USER", "danko")
address = values.get("DANKO_00_SSH_ADDRESS") or values.get("DANKO_00_RESERVED_LAN_IP") or values.get("TARGET_RESERVED_LAN_IP", "")
resolved_target = values.get("DANKO_00_TARGET", "") or (f"{user}@{address}" if address else "")
identity = values.get("DANKO_00_SSH_KEY") or values.get("DANKO_00_IDENTITY_FILE") or values.get("DANKOSURFACE_TO_00DANKO_IDENTITY_FILE", "")
hostname = values.get("DANKO_00_EXPECTED_HOSTNAME") or values.get("TARGET_STABLE_LAN_NAME", "")
for value in (resolved_target, identity, hostname):
    if "\n" in value or "\r" in value:
        raise SystemExit(1)
    sys.stdout.buffer.write(value.encode("utf-8") + b"\0")
PY
  )
  (( ${#selected_site_values[@]} == 3 )) || {
    printf 'BLOCKED: selected site-value parsing failed.\n' >&2
    exit 2
  }
  target="${selected_site_values[0]}"
  identity_file="${selected_site_values[1]}"
  expected_hostname="${selected_site_values[2]}"
fi

[[ "$target" =~ ^[A-Za-z_][A-Za-z0-9_-]*@[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || {
  printf 'BLOCKED: invalid or missing SSH target.\n' >&2
  exit 2
}
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || {
  printf 'BLOCKED: invalid or missing expected hostname.\n' >&2
  exit 2
}
[[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || {
  printf 'BLOCKED: identity file is missing or unsafe.\n' >&2
  exit 2
}

mkdir -p -- "$report_root" "$artifact_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/chunk_embedding_qualification_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/chunk-embedding-qualification-$timestamp-$$"

emit 'purpose=measure_and_qualify_nomic_chunk_embeddings'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;target_shell_sha256=$shell_sha256;qualifier_sha256=$qualifier_sha256"
emit "evaluator_sha256=$evaluator_sha256;embedding_tests_sha256=$tests_sha256"
emit "chunk_candidate_sha256=$CHUNK_SHA256;accepted_nomic_report_sha256=$ACCEPTED_NOMIC_REPORT_SHA256"
emit "payload_manifest_sha256=$payload_manifest_sha256;payload_members=3;synthetic_chunk_candidates=125"
emit 'authorized_actions=stage_verified_synthetic_chunks_measure_tokens_call_loopback_nomic_create_and_fetch_protected_embeddings_restore_initial_service_state_remove_target_temporary_files'
emit 'non_actions=no_package_or_configuration_change_no_database_connection_no_organizational_content_no_credential_transfer_or_retention_no_raw_text_or_vector_logging_no_publication'
emit "selected_target=$target;expected_hostname=$expected_hostname;identity_label=$(basename -- "$identity_file")"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_up_to_once;nomic_api_key_prompt=exactly_once'
emit 'base_tests=64;normalization_tests=13;chunking_tests=12;embedding_tests=8;failures=0;errors=0'

control_path="$work_root/ssh-control"
ssh_args=(
  -i "$identity_file" -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes
  -o ConnectTimeout=10 -o ConnectionAttempts=1
  -o ServerAliveInterval=30 -o ServerAliveCountMax=20
  -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=3600
)

emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" \
  >"$work_root/master.stdout" 2>"$work_root/master.stderr" || {
    emit 'script_28_embedding=blocked;reason=ssh_master_start_failed'
    exit 1
  }
master_started=true
emit 'milestone=authentication;state=pass'

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" hostname \
  >"$work_root/hostname.stdout" 2>"$work_root/hostname.stderr" || {
    emit 'script_28_embedding=blocked;reason=hostname_probe_failed'
    exit 1
  }
[[ "$(tr -d '\r\n' <"$work_root/hostname.stdout")" == "$expected_hostname" ]] || {
  emit 'script_28_embedding=blocked;reason=target_hostname_mismatch'
  exit 1
}
emit "target_hostname=$expected_hostname"

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" \
  >"$work_root/create.stdout" 2>"$work_root/create.stderr" || {
    emit 'script_28_embedding=blocked;reason=remote_temporary_directory_not_created'
    exit 1
  }
remote_created=true

timeout --foreground 180 scp "${ssh_args[@]}" \
  "$TARGET_SHELL" "$TARGET_PYTHON" "$CHUNK_ARTIFACT" "$payload_manifest" \
  "$target:$remote_root/" >"$work_root/scp.stdout" 2>"$work_root/scp.stderr" || {
    emit 'script_28_embedding=blocked;reason=target_payload_copy_failed'
    exit 1
  }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && mv '$(basename -- "$CHUNK_ARTIFACT")' chunk-candidates.json && sha256sum --check --strict payload.sha256" \
  >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || {
    emit 'script_28_embedding=blocked;reason=target_payload_hash_mismatch'
    exit 1
  }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=token_measurement_and_embedding;state=waiting_for_operator_credentials'
set +e
timeout --foreground 3600 ssh -tt "${ssh_args[@]}" "$target" \
  "cd '$remote_root' && umask 077 && sudo -p '[sudo] password for chunk embedding qualification: ' bash ./qualify-chunk-embeddings --input '$remote_root/chunk-candidates.json' --expected-input-sha256 '$CHUNK_SHA256' --output '$remote_root/measured-embeddings.json' > '$remote_root/qualification-result.txt' 2>&1" \
  < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_output_retained=false"

fetched_result="$work_root/qualification-result.txt"
timeout --foreground 120 scp "${ssh_args[@]}" \
  "$target:$remote_root/qualification-result.txt" "$fetched_result" \
  >"$work_root/fetch-result.stdout" 2>"$work_root/fetch-result.stderr" || {
    emit 'script_28_embedding=blocked;reason=result_fetch_failed'
    exit 1
  }
tr -d '\r' <"$fetched_result" >"$work_root/qualification-result.normalized"
fetched_result="$work_root/qualification-result.normalized"
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^\[chunk-embedding\]\ [A-Za-z0-9_.:/=@+,-]+(\ [A-Za-z0-9_.:/=@+,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
pass_markers="$(grep -Fc '[chunk-embedding] result=PASS ' "$fetched_result" || true)"
blocked_markers="$(grep -Fc '[chunk-embedding] result=BLOCKED ' "$fetched_result" || true)"
credential_markers="$(grep -Fxc '[chunk-embedding] credential_source=operator_attended_tty stored_credential_read=false' "$fetched_result" || true)"
cleanup_markers="$(grep -Ec '^\[chunk-embedding\] cleanup=(pass|not_required) ' "$fetched_result" || true)"
emit "pass_markers=$pass_markers;blocked_markers=$blocked_markers;credential_markers=$credential_markers;cleanup_markers=$cleanup_markers"
if (( remote_code != 0 )) || [[ "$output_contract" != pass || "$pass_markers" != 1 || "$blocked_markers" != 0 || "$credential_markers" != 1 || "$cleanup_markers" != 1 ]]; then
  emit 'milestone=token_measurement_and_embedding;state=blocked'
  emit "script_28_embedding=blocked;local_report=$report_path;next_gate=review_content_free_result_before_any_retry"
  exit 1
fi

fetched_artifact="$work_root/measured-embeddings.json"
timeout --foreground 300 scp "${ssh_args[@]}" \
  "$target:$remote_root/measured-embeddings.json" "$fetched_artifact" \
  >"$work_root/fetch-artifact.stdout" 2>"$work_root/fetch-artifact.stderr" || {
    emit 'script_28_embedding=blocked;reason=embedding_artifact_fetch_failed'
    exit 1
  }
emit 'milestone=token_measurement_and_embedding;state=pass'

emit 'milestone=local_embedding_artifact_evaluation;state=start'
evaluation_result="$work_root/evaluation-result.txt"
set +e
python3 "$LOCAL_EVALUATOR" \
  --candidates "$CHUNK_ARTIFACT" \
  --expected-candidate-sha256 "$CHUNK_SHA256" \
  --artifact "$fetched_artifact" \
  --target-result "$fetched_result" >"$evaluation_result"
evaluation_code=$?
set -e
evaluation_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    evaluation_contract=blocked
    continue
  fi
  emit "$line"
done <"$evaluation_result"
evaluation_pass_markers="$(grep -Fxc 'chunk_embedding_evaluation=pass' "$evaluation_result" || true)"
evaluation_blocked_markers="$(grep -Ec '^chunk_embedding_evaluation=blocked;' "$evaluation_result" || true)"
emit "evaluation_exit_code=$evaluation_code;evaluation_output_contract=$evaluation_contract;evaluation_pass_markers=$evaluation_pass_markers;evaluation_blocked_markers=$evaluation_blocked_markers"
if (( evaluation_code != 0 )) || [[ "$evaluation_contract" != pass || "$evaluation_pass_markers" != 1 || "$evaluation_blocked_markers" != 0 ]]; then
  emit 'milestone=local_embedding_artifact_evaluation;state=blocked'
  emit "script_28_embedding=blocked;local_report=$report_path;next_gate=review_content_free_evaluation_before_any_retry"
  exit 1
fi
emit 'milestone=local_embedding_artifact_evaluation;state=pass'

artifact_sha256="$(sha256sum "$fetched_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$fetched_artifact")"
artifact_path="$artifact_root/measured_nomic_chunk_embeddings_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  emit 'script_28_embedding=blocked;reason=local_artifact_path_exists'
  exit 1
}
cp -- "$fetched_artifact" "$artifact_path"
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$artifact_sha256" ]] || {
  emit 'script_28_embedding=blocked;reason=retained_artifact_identity_mismatch'
  exit 1
}
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
emit "accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_artifact=$artifact_path;accepted_checksum=$checksum_path"
emit 'publication_eligible=false;publication_blocker=pipeline_writer_integration_pending'
emit "script_28_embedding=pass;local_report=$report_path;next_gate=connect_measured_embeddings_to_incremental_writer"
exit 0

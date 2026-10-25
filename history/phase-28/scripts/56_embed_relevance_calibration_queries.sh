#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Measure and embed the twelve qualified responsive and nonresponsive
#   synthetic relevance questions through the accepted Nomic service.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/56_embed_relevance_calibration_queries.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Explicitly authorize target qualification.' \
    '  --target USER@HOST         Approved SSH destination.' \
    '  --identity-file PATH       Function-specific SSH private key.' \
    '  --expected-hostname NAME   Exact target hostname.' \
    '  --validate-only            Validate all local sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly TARGET_SHELL="$SCRIPT_DIR/embed-relevance-queries"
readonly TARGET_PYTHON="$SCRIPT_DIR/embed_relevance_queries.py"
readonly COMMON_PYTHON="$SCRIPT_DIR/qualify_chunk_embeddings.py"
readonly LOCAL_EVALUATOR="$SCRIPT_DIR/evaluate_relevance_query_embeddings.py"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly CASES="$REPO_ROOT/local/artifacts/ishikawa/relevance-calibration-input/relevance_cases_v1.json"
readonly ACCEPTED_CASE_REPORT="$REPO_ROOT/local/reports/ishikawa-relevance-case-contract/relevance_case_contract_20261020T040222Z_mTwrP1.txt"
readonly ACCEPTED_NOMIC_REPORT="$REPO_ROOT/local/reports/embedding-service-verification/embedding_service_verification_20261018T235456Z_LnHgPN.txt"
readonly ACCEPTED_QUERY_REPORT="$REPO_ROOT/local/reports/ishikawa-query-embedding/query_embedding_20261019T233832Z_LBSgMJ.txt"
readonly CASES_SHA256='2fa6a20fc77f1faa25d141838b50ad0e95e2467035a0193d7f94451202cd94da'
readonly ACCEPTED_CASE_REPORT_SHA256='5fd84f351a062373dd49894f912d243647fa2a33206d895c73de447822ce8693'
readonly ACCEPTED_NOMIC_REPORT_SHA256='2309ef678501275fcb74b976c30ad110439fc1958af4694a9438b077a106c9bf'
readonly ACCEPTED_QUERY_REPORT_SHA256='3759432883b8413f5eaadd63db63386852c9b6df138bb2b91c07fde4c148518a'
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-relevance-query-embedding"
readonly DEFAULT_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/relevance-query-embeddings"

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
for required in awk bash basename cat chmod cp date env grep mkdir mktemp python3 rm scp sha256sum ssh stat tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in \
  "$TARGET_SHELL" "$TARGET_PYTHON" "$COMMON_PYTHON" "$LOCAL_EVALUATOR" \
  "$TEST_RUNNER" "$CASES" "$ACCEPTED_CASE_REPORT" "$ACCEPTED_NOMIC_REPORT" \
  "$ACCEPTED_QUERY_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: required Script 56 input is missing or unsafe.\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'BLOCKED: %s checksum mismatch.\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$CASES" "$CASES_SHA256" 'qualified relevance cases'
check_sha256 "$ACCEPTED_CASE_REPORT" "$ACCEPTED_CASE_REPORT_SHA256" 'accepted Script 55 report'
check_sha256 "$ACCEPTED_NOMIC_REPORT" "$ACCEPTED_NOMIC_REPORT_SHA256" 'accepted Nomic report'
check_sha256 "$ACCEPTED_QUERY_REPORT" "$ACCEPTED_QUERY_REPORT_SHA256" 'accepted query-embedding report'
for fact in \
  'cases=12;responsive=6;nonresponsive=6;near_domain_nonresponsive=3' \
  'relevance_case_contract_qualification=pass' \
  'script_55_relevance_case_contract=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_CASE_REPORT" || {
    printf 'BLOCKED: required accepted Script 55 fact is absent.\n' >&2
    exit 2
  }
done
grep -Fq '[embedding-verification] embedding=pass dimensions=768 ' "$ACCEPTED_NOMIC_REPORT" || {
  printf 'BLOCKED: accepted Nomic embedding fact is absent.\n' >&2
  exit 2
}
grep -Fxq 'query_embedding_evaluation=pass' "$ACCEPTED_QUERY_REPORT" || {
  printf 'BLOCKED: accepted query-embedding evaluation marker is absent.\n' >&2
  exit 2
}

bash -n "$TARGET_SHELL" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$TARGET_PYTHON" "$COMMON_PYTHON" "$LOCAL_EVALUATOR"
PYTHONPATH="$SCRIPT_DIR" python3 -B "$TARGET_PYTHON" --self-test >/dev/null
python3 -B "$LOCAL_EVALUATOR" --self-test >/dev/null
for neutral_source in "$TARGET_SHELL" "$TARGET_PYTHON" "$COMMON_PYTHON"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|AgentDanko|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-56.XXXXXX)"
report_path=""
remote_root=""
remote_created=false
master_started=false
ssh_args=()
emit() {
  if [[ -n "$report_path" ]]; then printf '%s\n' "$1" | tee -a "$report_path"; else printf '%s\n' "$1"; fi
}
cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then emit 'cleanup_remote_temporary_files=removed'; else emit "cleanup_remote_temporary_files=review_required;exit_code=$cleanup_code"; status=1; fi
  else
    emit 'cleanup_remote_temporary_files=not_required'
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-56.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  cat "$test_result" >&2
  printf 'script_56_relevance_query_embedding=blocked;reason=base_regression\n' >&2
  exit 1
}
grep -Fq 'Ran 195 tests' "$test_result" || {
  printf 'script_56_relevance_query_embedding=blocked;reason=base_test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_56_relevance_query_embedding=blocked;reason=base_pass_marker_absent\n' >&2
  exit 1
}

queries_path="$work_root/relevance-queries.json"
python3 -B - "$CASES" "$queries_path" "$CASES_SHA256" <<'PY'
import hashlib
import json
import os
import sys

source_path, output_path, source_sha256 = sys.argv[1:]
source = json.load(open(source_path, encoding="utf-8"))
canonical = lambda value: json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":")).encode()
def digest(domain, value):
    result = hashlib.sha256()
    result.update(domain.encode("ascii"))
    result.update(b"\x00")
    result.update(canonical(value))
    return result.hexdigest()
records = []
for item in source["cases"]:
    records.append({
        "case_id": item["case_id"],
        "class": item["class"],
        "question": item["question"],
        "question_digest": digest("ishikawa.retrieval-question.v1", {"question": item["question"]}),
    })
artifact = {
    "artifact_kind": "relevance_embedding_queries",
    "cases": records,
    "schema_version": 1,
    "source_case_set_sha256": source_sha256,
}
artifact["query_set_digest"] = digest("ishikawa.relevance-embedding-query-set.v1", artifact)
payload = canonical(artifact)
descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, "wb") as stream:
    stream.write(payload)
PY
queries_sha256="$(sha256sum "$queries_path" | awk '{print $1}')"

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
shell_sha256="$(sha256sum "$TARGET_SHELL" | awk '{print $1}')"
qualifier_sha256="$(sha256sum "$TARGET_PYTHON" | awk '{print $1}')"
common_sha256="$(sha256sum "$COMMON_PYTHON" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$LOCAL_EVALUATOR" | awk '{print $1}')"
payload_manifest="$work_root/payload.sha256"
printf '%s  %s\n' \
  "$shell_sha256" 'embed-relevance-queries' \
  "$qualifier_sha256" 'embed_relevance_queries.py' \
  "$common_sha256" 'qualify_chunk_embeddings.py' \
  "$queries_sha256" 'relevance-queries.json' >"$payload_manifest"
payload_manifest_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_relevance_query_embedding_source' \
    'target_contact=false;model_call=false;database_connection=false;retained_artifact=false' \
    "script_sha256=$script_sha256;target_shell_sha256=$shell_sha256;qualifier_sha256=$qualifier_sha256;common_sha256=$common_sha256" \
    "evaluator_sha256=$evaluator_sha256;payload_manifest_sha256=$payload_manifest_sha256;payload_members=4" \
    "case_set_sha256=$CASES_SHA256;query_input_sha256=$queries_sha256;accepted_case_report_sha256=$ACCEPTED_CASE_REPORT_SHA256" \
    'base_tests=195;queries=12;responsive=6;nonresponsive=6;failures=0;errors=0' \
    'script_56_relevance_query_embedding_source=pass'
  exit 0
fi

# Parse only allowlisted nonsecret connection fields; never source the file.
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
report_path="$(mktemp "$report_root/relevance_query_embedding_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/relevance-query-embedding-$timestamp-$$"
emit 'purpose=embed_qualified_relevance_calibration_queries'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;target_shell_sha256=$shell_sha256;qualifier_sha256=$qualifier_sha256;common_sha256=$common_sha256"
emit "evaluator_sha256=$evaluator_sha256;payload_manifest_sha256=$payload_manifest_sha256"
emit "case_set_sha256=$CASES_SHA256;query_input_sha256=$queries_sha256;accepted_case_report_sha256=$ACCEPTED_CASE_REPORT_SHA256"
emit 'authorized_actions=stage_verified_synthetic_questions_measure_tokens_call_loopback_nomic_create_and_fetch_protected_query_embeddings_restore_initial_service_state_remove_target_temporary_files'
emit 'non_actions=no_package_or_configuration_change_no_database_connection_no_gemma_call_no_credential_transfer_or_retention_no_raw_question_or_vector_logging_no_threshold_selection_no_publication'
emit "selected_target=$target;expected_hostname=$expected_hostname;identity_label=$(basename -- "$identity_file")"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_up_to_once;nomic_api_key_prompt=exactly_once'
emit 'base_tests=195;queries=12;responsive=6;nonresponsive=6;failures=0;errors=0'

control_path="$work_root/ssh-control"
ssh_args=(
  -i "$identity_file" -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes
  -o ConnectTimeout=10 -o ConnectionAttempts=1
  -o ServerAliveInterval=30 -o ServerAliveCountMax=20
  -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=3600
)
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >"$work_root/master.stdout" 2>"$work_root/master.stderr" || {
  emit 'script_56_relevance_query_embedding=blocked;reason=ssh_master_start_failed'
  exit 1
}
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" hostname >"$work_root/hostname.stdout" 2>"$work_root/hostname.stderr" || {
  emit 'script_56_relevance_query_embedding=blocked;reason=hostname_probe_failed'
  exit 1
}
[[ "$(tr -d '\r\n' <"$work_root/hostname.stdout")" == "$expected_hostname" ]] || {
  emit 'script_56_relevance_query_embedding=blocked;reason=target_hostname_mismatch'
  exit 1
}
emit "target_hostname=$expected_hostname"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >"$work_root/create.stdout" 2>"$work_root/create.stderr" || {
    emit 'script_56_relevance_query_embedding=blocked;reason=remote_temporary_directory_not_created'
    exit 1
  }
remote_created=true

timeout --foreground 180 scp "${ssh_args[@]}" \
  "$TARGET_SHELL" "$TARGET_PYTHON" "$COMMON_PYTHON" "$queries_path" "$payload_manifest" \
  "$target:$remote_root/" >"$work_root/scp.stdout" 2>"$work_root/scp.stderr" || {
    emit 'script_56_relevance_query_embedding=blocked;reason=target_payload_copy_failed'
    exit 1
  }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && sha256sum --check --strict payload.sha256" \
  >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || {
    emit 'script_56_relevance_query_embedding=blocked;reason=target_payload_hash_mismatch'
    exit 1
  }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=query_token_measurement_and_embedding;state=waiting_for_operator_credentials'
set +e
timeout --foreground 1800 ssh -tt "${ssh_args[@]}" "$target" \
  "cd '$remote_root' && umask 077 && sudo -p '[sudo] password for relevance embedding qualification: ' bash ./embed-relevance-queries --input '$remote_root/relevance-queries.json' --expected-input-sha256 '$queries_sha256' --output '$remote_root/query-embeddings.json' > '$remote_root/qualification-result.txt' 2>&1" \
  < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_output_retained=false"

fetched_result="$work_root/qualification-result.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/qualification-result.txt" "$fetched_result" >"$work_root/fetch-result.stdout" 2>"$work_root/fetch-result.stderr" || {
  emit 'script_56_relevance_query_embedding=blocked;reason=result_fetch_failed'
  exit 1
}
tr -d '\r' <"$fetched_result" >"$work_root/qualification-result.normalized"
fetched_result="$work_root/qualification-result.normalized"
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^\[relevance-embedding\]\ [A-Za-z0-9_.:/=@+,-]+(\ [A-Za-z0-9_.:/=@+,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
pass_markers="$(grep -Fc '[relevance-embedding] result=PASS ' "$fetched_result" || true)"
blocked_markers="$(grep -Fc '[relevance-embedding] result=BLOCKED ' "$fetched_result" || true)"
credential_markers="$(grep -Fxc '[relevance-embedding] credential_source=operator_attended_tty stored_credential_read=false' "$fetched_result" || true)"
cleanup_markers="$(grep -Ec '^\[relevance-embedding\] cleanup=(pass|not_required) ' "$fetched_result" || true)"
emit "pass_markers=$pass_markers;blocked_markers=$blocked_markers;credential_markers=$credential_markers;cleanup_markers=$cleanup_markers"
if (( remote_code != 0 )) || [[ "$output_contract" != pass || "$pass_markers" != 1 || "$blocked_markers" != 0 || "$credential_markers" != 1 || "$cleanup_markers" != 1 ]]; then
  emit 'milestone=query_token_measurement_and_embedding;state=blocked'
  emit "script_56_relevance_query_embedding=blocked;local_report=$report_path;next_gate=review_content_free_result_before_any_retry"
  exit 1
fi

fetched_artifact="$work_root/query-embeddings.json"
timeout --foreground 300 scp "${ssh_args[@]}" "$target:$remote_root/query-embeddings.json" "$fetched_artifact" >"$work_root/fetch-artifact.stdout" 2>"$work_root/fetch-artifact.stderr" || {
  emit 'script_56_relevance_query_embedding=blocked;reason=query_embedding_artifact_fetch_failed'
  exit 1
}
emit 'milestone=query_token_measurement_and_embedding;state=pass'

emit 'milestone=local_query_embedding_artifact_evaluation;state=start'
evaluation_result="$work_root/evaluation-result.txt"
set +e
python3 -B "$LOCAL_EVALUATOR" \
  --cases "$CASES" --expected-cases-sha256 "$CASES_SHA256" \
  --queries "$queries_path" --artifact "$fetched_artifact" \
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
evaluation_pass_markers="$(grep -Fxc 'relevance_query_embedding_evaluation=pass' "$evaluation_result" || true)"
evaluation_blocked_markers="$(grep -Ec '^relevance_query_embedding_evaluation=blocked;' "$evaluation_result" || true)"
emit "evaluation_exit_code=$evaluation_code;evaluation_output_contract=$evaluation_contract;evaluation_pass_markers=$evaluation_pass_markers;evaluation_blocked_markers=$evaluation_blocked_markers"
if (( evaluation_code != 0 )) || [[ "$evaluation_contract" != pass || "$evaluation_pass_markers" != 1 || "$evaluation_blocked_markers" != 0 ]]; then
  emit 'milestone=local_query_embedding_artifact_evaluation;state=blocked'
  emit "script_56_relevance_query_embedding=blocked;local_report=$report_path;next_gate=review_content_free_evaluation_before_any_retry"
  exit 1
fi
emit 'milestone=local_query_embedding_artifact_evaluation;state=pass'

artifact_sha256="$(sha256sum "$fetched_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$fetched_artifact")"
artifact_path="$artifact_root/measured_nomic_relevance_query_embeddings_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  emit 'script_56_relevance_query_embedding=blocked;reason=local_artifact_path_exists'
  exit 1
}
cp -- "$fetched_artifact" "$artifact_path"
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$artifact_sha256" ]] || {
  emit 'script_56_relevance_query_embedding=blocked;reason=retained_artifact_identity_mismatch'
  exit 1
}
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
emit "accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_artifact=$artifact_path;accepted_checksum=$checksum_path"
emit 'calibration_eligible=true;publication_eligible=false;publication_blocker=relevance_retrieval_observation_pending'
emit "script_56_relevance_query_embedding=pass;local_report=$report_path;next_gate=measure_relevance_signals_in_disposable_database"

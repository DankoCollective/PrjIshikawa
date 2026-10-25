#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Measure deterministic PostgreSQL English-lexeme support across the frozen
#   fused retrieval results without changing ranking or selecting a threshold.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/59_measure_relevance_lexeme_support_on_emceedanko.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options are passed to the underlying disposable measurement:' \
    '  --run                      Authorize the target measurement.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly MEASUREMENT="$SCRIPT_DIR/57_measure_relevance_retrieval_on_emceedanko.sh"
readonly TARGET_RUNNER="$SCRIPT_DIR/measure_relevance_retrieval.py"
readonly LOCAL_EVALUATOR="$SCRIPT_DIR/evaluate_relevance_lexeme_support.py"
readonly CASES="$REPO_ROOT/local/artifacts/ishikawa/relevance-calibration-input/relevance_cases_v1.json"
readonly CASES_SHA256='2fa6a20fc77f1faa25d141838b50ad0e95e2467035a0193d7f94451202cd94da'
readonly ACCEPTED_SCRIPT_58_REPORT="$REPO_ROOT/local/reports/ishikawa-relevance-retrieval-schema-v4-retry/relevance_retrieval_schema_v4_retry_20261020T044625Z_k7cY4X.txt"
readonly ACCEPTED_SCRIPT_58_REPORT_SHA256='e14e3e82ee7c2af8c1cf86a1e55c9f8bd8111e6c7574711f16172c80b397ed61'
readonly ACCEPTED_MEASUREMENT_REPORT="$REPO_ROOT/local/reports/ishikawa-relevance-retrieval-observation/relevance_retrieval_observation_20261020T044605Z_IYZtqG.txt"
readonly ACCEPTED_MEASUREMENT_REPORT_SHA256='db5ca12cfdc027e9d375aa7f4366ff2f1374d9f2272acf94a9dd73c885722c73'
readonly MEASUREMENT_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-relevance-retrieval-observation"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/relevance-retrieval-observations"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-relevance-lexeme-support"

run_mode=false
validate_mode=false
for argument in "$@"; do
  [[ "$argument" == --run ]] && run_mode=true
  [[ "$argument" == --validate-only ]] && validate_mode=true
  [[ "$argument" == --help || "$argument" == -h ]] && { usage; exit 0; }
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2
  exit 2
}
for required in awk bash cat date grep mkdir mktemp python3 rm sed sha256sum stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in \
  "$MEASUREMENT" "$TARGET_RUNNER" "$LOCAL_EVALUATOR" "$CASES" \
  "$ACCEPTED_SCRIPT_58_REPORT" "$ACCEPTED_MEASUREMENT_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 59 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$CASES" | awk '{print $1}')" == "$CASES_SHA256" ]] || {
  printf 'BLOCKED: protected relevance-case identity changed.\n' >&2
  exit 2
}
[[ "$(sha256sum "$ACCEPTED_SCRIPT_58_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_58_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 58 receipt changed.\n' >&2
  exit 2
}
[[ "$(sha256sum "$ACCEPTED_MEASUREMENT_REPORT" | awk '{print $1}')" == "$ACCEPTED_MEASUREMENT_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted relevance-measurement receipt changed.\n' >&2
  exit 2
}
for fact in \
  'script_58_relevance_retrieval_schema_v4_retry=pass;' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'threshold_selected=false;publication_eligible=false'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_58_REPORT" || {
    printf 'BLOCKED: accepted Script 58 fact is absent.\n' >&2
    exit 2
  }
done
for fact in \
  'relevance_retrieval_evaluation=pass' \
  'threshold_selected=false;next_gate=review_relevance_signal_separation' \
  'temporary_database_dropped=true;accepted_database_unchanged=true'; do
  grep -Fq "$fact" "$ACCEPTED_MEASUREMENT_REPORT" || {
    printf 'BLOCKED: accepted retrieval-measurement fact is absent.\n' >&2
    exit 2
  }
done

bash -n "$MEASUREMENT"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$TARGET_RUNNER" "$LOCAL_EVALUATOR"
python3 -B "$LOCAL_EVALUATOR" --self-test >/dev/null

work_root="$(mktemp -d /tmp/ishikawa-script-59.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-59.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

source_result="$work_root/source-validation.txt"
bash "$MEASUREMENT" --validate-only >"$source_result" 2>&1 || {
  cat "$source_result" >&2
  printf 'script_59_relevance_lexeme_support=blocked;reason=measurement_source_validation_failed\n' >&2
  exit 1
}
for fact in \
  'payload_file_count=35' \
  'staged_package_import=pass' \
  'script_57_relevance_retrieval_observation_source=pass'; do
  grep -Fq "$fact" "$source_result" || {
    cat "$source_result" >&2
    printf 'script_59_relevance_lexeme_support=blocked;reason=measurement_source_fact_absent\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
measurement_sha256="$(sha256sum "$MEASUREMENT" | awk '{print $1}')"
runner_sha256="$(sha256sum "$TARGET_RUNNER" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$LOCAL_EVALUATOR" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_postgresql_english_lexeme_support_measurement' \
    'target_contact=false;database_contact=false;model_call=false;retrieval_changed=false;threshold_selected=false' \
    "script_sha256=$script_sha256;measurement_sha256=$measurement_sha256;runner_sha256=$runner_sha256;evaluator_sha256=$evaluator_sha256" \
    "accepted_script_58_report_sha256=$ACCEPTED_SCRIPT_58_REPORT_SHA256;accepted_measurement_report_sha256=$ACCEPTED_MEASUREMENT_REPORT_SHA256" \
    'lexeme_support_measurement=postgresql_english;fused_depths=1,3,5,10,20;model_authority=false' \
    'base_tests=195;adapter_tests=9;evaluator_self_tests=1;failures=0;errors=0' \
    'script_59_relevance_lexeme_support_source=pass'
  exit 0
fi

run_result="$work_root/measurement-output.txt"
set +e
set -o pipefail
bash "$MEASUREMENT" "$@" 2>&1 | tee "$run_result"
measurement_code=$?
set -e
if (( measurement_code != 0 )); then
  printf 'script_59_relevance_lexeme_support=blocked;reason=measurement_failed\n' >&2
  exit 1
fi
[[ "$(grep -Fc 'script_57_relevance_retrieval_observation=pass;' "$run_result" || true)" == 1 ]] || {
  printf 'script_59_relevance_lexeme_support=blocked;reason=measurement_pass_marker_invalid\n' >&2
  exit 1
}
measurement_report="$(sed -n 's/^script_57_relevance_retrieval_observation=pass;local_report=\([^;]*\);next_gate=.*/\1/p' "$run_result")"
artifact_path="$(sed -n 's/^accepted_artifact=\([^;]*\);accepted_checksum=.*/\1/p' "$run_result")"
[[ "$measurement_report" == "$MEASUREMENT_REPORT_ROOT"/* && -f "$measurement_report" && ! -L "$measurement_report" ]] || {
  printf 'script_59_relevance_lexeme_support=blocked;reason=measurement_report_invalid\n' >&2
  exit 1
}
[[ "$artifact_path" == "$ARTIFACT_ROOT"/* && -f "$artifact_path" && ! -L "$artifact_path" ]] || {
  printf 'script_59_relevance_lexeme_support=blocked;reason=measurement_artifact_invalid\n' >&2
  exit 1
}
for fact in \
  'lexeme_support_measurement=postgresql_english;fused_depths=1,3,5,10,20;changes_retrieval_ranking=false;threshold_selected=false;model_authority=false' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'cluster_status=down;postgresql_port_5432=free;postgresql_service_active=inactive;postgresql_service_enabled=disabled' \
  'relevance_retrieval_evaluation=pass' \
  'cleanup_remote_temporary_files=removed' \
  'cleanup_ssh_master_exit_code=0'; do
  grep -Fq "$fact" "$measurement_report" || {
    printf 'script_59_relevance_lexeme_support=blocked;reason=measurement_fact_absent\n' >&2
    exit 1
  }
done

artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
evaluation_result="$work_root/lexeme-evaluation.txt"
set +e
python3 -B "$LOCAL_EVALUATOR" \
  --cases "$CASES" \
  --expected-cases-sha256 "$CASES_SHA256" \
  --observations "$artifact_path" \
  --expected-observations-sha256 "$artifact_sha256" \
  >"$evaluation_result"
evaluation_code=$?
set -e
evaluation_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    evaluation_contract=blocked
  fi
done <"$evaluation_result"
[[ "$evaluation_code" == 0 && "$evaluation_contract" == pass ]] || {
  cat "$evaluation_result" >&2
  printf 'script_59_relevance_lexeme_support=blocked;reason=protected_evaluation_failed\n' >&2
  exit 1
}
[[ "$(grep -Fxc 'relevance_lexeme_support_evaluation=pass' "$evaluation_result" || true)" == 1 ]] || {
  printf 'script_59_relevance_lexeme_support=blocked;reason=evaluation_pass_marker_invalid\n' >&2
  exit 1
}

mkdir -p -- "$REPORT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/relevance_lexeme_support_${timestamp}_XXXXXX.txt")"
measurement_report_sha256="$(sha256sum "$measurement_report" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$artifact_path")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=accept_postgresql_english_lexeme_support_measurement'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;measurement_sha256=$measurement_sha256;runner_sha256=$runner_sha256;evaluator_sha256=$evaluator_sha256"
emit "accepted_script_58_report_sha256=$ACCEPTED_SCRIPT_58_REPORT_SHA256;accepted_measurement_report_sha256=$ACCEPTED_MEASUREMENT_REPORT_SHA256"
emit "measurement_report=$measurement_report;measurement_report_sha256=$measurement_report_sha256"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit 'retrieval_profile_unchanged=true;threshold_selected=false;model_authority=false;publication_eligible=false'
emit 'temporary_database_dropped=true;accepted_database_unchanged=true;postgresql_restored_stopped_disabled=true'
emit "script_59_relevance_lexeme_support=pass;local_report=$report_path;next_gate=review_lexeme_support_separation"

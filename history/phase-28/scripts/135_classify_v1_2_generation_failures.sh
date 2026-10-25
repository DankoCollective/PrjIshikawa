#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Distinguish grounded-generation transport failures from strict model-
#   response validation failures without retaining model or corpus content.
#
# Mental model:
#   Run Script 134's exact five-probe diagnostic under one temporary Python
#   observer. The observer records only attempt number, failure family, and
#   stable reason code. Correlate those records with the content-free probe
#   artifact and retain one checksummed reason-classification artifact.
#
# Inputs or prerequisites:
#   Local PostgreSQL, forwarded Gemma on 127.0.0.1:8000, forwarded Nomic on
#   127.0.0.1:8001, and the same three runtime credentials used by Script 134.
#
# Outputs:
#   One content-free report and artifact. No prompt, response, question,
#   excerpt, credential, vector, exception text, or source content is retained.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/135_classify_v1_2_generation_failures.sh --run

usage() {
  sed -n '3,29p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run            Run five probes and classify each failed generation attempt.' \
    '  --validate-only  Validate bound sources and local helper self-tests only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly SCRIPT_134="$SCRIPT_DIR/134_diagnose_v1_2_r006_dependency_reliability.sh"
readonly PROBE_HELPER="$SCRIPT_DIR/diagnose_t10_generation_reliability.py"
readonly HOOK_DIR="$SCRIPT_DIR/generation_failure_diagnostic_hook"
readonly HOOK="$HOOK_DIR/sitecustomize.py"
readonly CLASSIFIER="$SCRIPT_DIR/classify_generation_failure_reasons.py"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly PROBE_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-t10-reliability-diagnostic"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.2-generation-failure-reasons"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-generation-failure-reasons"

readonly SCRIPT_134_SHA256='f4fadfa0ed1219c04d3e1fcaf404cde8c745bf4af822afe83e56a61d2d607807'
readonly PROBE_HELPER_SHA256='160a3bb0eeae856cdba8cce1467995ac8ce4d18e91e2de1b816405b0024da4f1'
readonly HOOK_SHA256='09a264c3ea55519ef67a97c96630c43f9a62046fb4cace77b8a55a493dd9d29f'
readonly CLASSIFIER_SHA256='e8e38ae31eb7cdbe1fbc34a95d51dedf0f2a5c1fe6fd85223e51eada04d1e4ba'
readonly DECISIONS_SHA256='5eb902509ce604891fb54fee30f447179a8b0c38f6cff480018eceb45dc5c6eb'

run_mode=false
validate_mode=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_mode=true; shift ;;
    --validate-only) validate_mode=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_135_generation_failure_classification=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'script_135_generation_failure_classification=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename chmod date grep install mkdir mktemp mv python3 rm sed sha256sum stat tee tr wc; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_135_generation_failure_classification=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'script_135_generation_failure_classification=blocked;reason=%s_unsafe\n' "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected" ]] || {
    printf 'script_135_generation_failure_classification=blocked;reason=%s_identity_changed\n' "$label" >&2
    exit 2
  }
}

check_file "$SCRIPT_134" "$SCRIPT_134_SHA256" script_134
check_file "$PROBE_HELPER" "$PROBE_HELPER_SHA256" probe_helper
check_file "$HOOK" "$HOOK_SHA256" diagnostic_hook
check_file "$CLASSIFIER" "$CLASSIFIER_SHA256" classifier
check_file "$DECISIONS" "$DECISIONS_SHA256" tuning_decisions
grep -Eq '^\| `T10` \|.*\| FROZEN \|$' "$DECISIONS" || {
  printf 'script_135_generation_failure_classification=blocked;reason=t10_not_frozen\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}" "$SCRIPT_134"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$HOOK" "$CLASSIFIER" "$PROBE_HELPER"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CLASSIFIER" --self-test \
  | grep -Fxq 'generation_failure_reason_classifier_self_test=pass' || {
    printf 'script_135_generation_failure_classification=blocked;reason=classifier_self_test_failed\n' >&2
    exit 2
  }
PYTHONDONTWRITEBYTECODE=1 python3 -B "$PROBE_HELPER" --self-test \
  | grep -Fxq 't10_generation_reliability_diagnostic_self_test=pass' || {
    printf 'script_135_generation_failure_classification=blocked;reason=probe_helper_self_test_failed\n' >&2
    exit 2
  }

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_v1_2_generation_failure_reason_diagnostic' \
    "script_sha256=$script_sha256;script_134_sha256=$SCRIPT_134_SHA256" \
    "hook_sha256=$HOOK_SHA256;classifier_sha256=$CLASSIFIER_SHA256;decision_list_sha256=$DECISIONS_SHA256" \
    'probe_count=5;failure_fields=family_ordinal_reason_code;raw_content_retained=false' \
    'policy_changed=false;application_source_changed=false;package_built=false;model_contact=false' \
    'script_135_generation_failure_classification_source=pass'
  exit 0
fi

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-135.XXXXXX)"
report_path=''
artifact_path=''
checksum_path=''
artifact_created=false
artifact_committed=false

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  unset ISHIKAWA_DIAGNOSTIC_FAILURE_LOG PYTHONPATH
  if [[ "$artifact_created" == true && "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/generation_failure_reasons_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/generation_failure_reasons_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  [[ "$work_root" == /tmp/ishikawa-script-135.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || {
  printf 'script_135_generation_failure_classification=blocked;reason=output_directory_unsafe\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/generation_failure_reasons_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() { emit "script_135_generation_failure_classification=blocked;reason=$1;local_report=$report_path"; exit 1; }
trap 'block interrupted_by_operator' INT
trap 'block terminated_by_signal' TERM

failure_log="$work_root/generation-failures.jsonl"
install -m 0600 /dev/null "$failure_log"
nested_output="$work_root/script-134.stdout"

emit 'purpose=classify_v1_2_grounded_generation_failures'
emit "started_utc=$timestamp;script_sha256=$script_sha256;script_134_sha256=$SCRIPT_134_SHA256"
emit "hook_sha256=$HOOK_SHA256;classifier_sha256=$CLASSIFIER_SHA256"
emit 'authorized_actions=run_script_134_with_temporary_content_free_failure_observer_classify_reason_codes_retain_diagnostic'
emit 'non_actions=no_policy_change_no_application_source_change_no_database_write_no_package_build_no_raw_content_or_secret_retention'
emit 'milestone=script_134_observed_probe;state=start;probes=5'

set +e
PYTHONPATH="$HOOK_DIR" \
ISHIKAWA_DIAGNOSTIC_FAILURE_LOG="$failure_log" \
  bash "$SCRIPT_134" --run 2>&1 | tee "$nested_output"
pipeline_status=("${PIPESTATUS[@]}")
set -e
if (( ${pipeline_status[0]} != 0 || ${pipeline_status[1]} != 0 )); then
  nested_reason="$(sed -nE 's/^script_134_r006_diagnostic=blocked;reason=([A-Za-z0-9_]+).*$/\1/p' "$nested_output" | tail -n 1)"
  [[ -n "$nested_reason" ]] || nested_reason=unclassified_failure
  block "nested_script_134_${nested_reason}"
fi
grep -Eq '^script_134_r006_diagnostic=pass;' "$nested_output" || block nested_script_134_pass_marker_absent
emit 'milestone=script_134_observed_probe;state=pass;probes=5'

probe_artifact="$(sed -nE 's#^accepted_artifact=([^;]+);accepted_artifact_sha256=[0-9a-f]{64};.*#\1#p' "$nested_output" | tail -n 1)"
[[ -n "$probe_artifact" \
    && "$probe_artifact" == "$PROBE_ARTIFACT_ROOT"/r006_reliability_*.json \
    && -f "$probe_artifact" && ! -L "$probe_artifact" ]] || block nested_probe_artifact_invalid
probe_artifact_sha256="$(sha256sum "$probe_artifact" | awk '{print $1}')"

candidate="$work_root/generation-failure-reasons.json"
classifier_output="$work_root/classifier.stdout"
classifier_error="$work_root/classifier.stderr"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CLASSIFIER" \
  --run \
  --probe-artifact "$probe_artifact" \
  --failure-log "$failure_log" \
  --output "$candidate" \
  >"$classifier_output" 2>"$classifier_error" || {
    reason="$(sed -nE 's/^generation_failure_reason_classification=blocked;reason=([A-Za-z0-9_]+)$/\1/p' "$classifier_error" | tail -n 1)"
    [[ -n "$reason" ]] || reason=unclassified_classifier_failure
    block "$reason"
  }
grep -Fxq 'generation_failure_reason_classification=pass' "$classifier_output" \
  || block classifier_pass_marker_absent

summary_line="$(grep -E '^attempt_failures=[0-9]+;transport=[0-9]+;response_validation=[0-9]+;unclassified=[0-9]+$' "$classifier_output")" \
  || block classifier_summary_invalid
interpretation_line="$(grep -E '^failure_interpretation=[a-z_]+;raw_content_retained=false$' "$classifier_output")" \
  || block classifier_interpretation_invalid
emit "nested_probe_artifact_sha256=$probe_artifact_sha256"
emit "$summary_line"
while IFS= read -r line; do
  [[ "$line" =~ ^failure_reason= ]] && emit "$line"
done <"$classifier_output"
emit "$interpretation_line"

validation_output="$work_root/validation.stdout"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CLASSIFIER" --validate-artifact --artifact "$candidate" \
  >"$validation_output" || block artifact_validation_failed
grep -Fxq 'generation_failure_reason_artifact=pass' "$validation_output" \
  || block artifact_validation_marker_absent

artifact_path="$ARTIFACT_ROOT/generation_failure_reasons_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] \
  || block artifact_path_exists
mv -- "$candidate" "$artifact_path"
artifact_created=true
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$artifact_path")"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || block artifact_checksum_failed
artifact_committed=true
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes;checksum=$checksum_path"
emit 'database_write=false;policy_changed=false;application_source_changed=false;package_built=false;raw_content_retained=false;credentials_retained=false'
emit "script_135_generation_failure_classification=pass;next_gate=review_failure_family_before_any_reliability_change;local_report=$report_path"

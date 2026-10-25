#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Prove that the frozen local retrieval-profile configuration exactly matches
#   the accepted Script 37 calibration evidence and application defaults.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/38_freeze_calibrated_retrieval_profile.sh --run

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run             Run the local freeze-validation gate and retain a report.' \
    '  --validate-only   Validate sources and tests without retaining a report.' \
    '  --report-root P   Absolute local content-free report directory.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly PROFILE="$ISHIKAWA_ROOT/config/templates/method_profile.yaml"
readonly VALIDATOR="$ISHIKAWA_ROOT/scripts/validate-method-profile.py"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-retrieval-gap-recalibration/retrieval_gap_recalibration_20261020T003328Z_sV57fU.txt"
readonly ACCEPTED_OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-recalibration/held_out_retrieval_observations_20261020T003328Z.json"
readonly EXPECTED_REPORT_SHA256='60c3daf4fb060cf1a1a89e18d6ba5520ca63c1a55a20397cc926c58b711df97a'
readonly EXPECTED_OBSERVATION_SHA256='8c0fb418d00e629799a425154d0283462c35ddf3b40cdad127d7b43b676dbc43'
readonly EXPECTED_RETRIEVAL_PROFILE_ID='33102734a29ea8170cffcfa7cdff6feae66d4663d09d7bca86c04a6419f77ad7'
readonly EXPECTED_CHUNK_PROFILE_ID='5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0'
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-retrieval-profile-freeze"

run_authorized=false
validate_only=false
report_root="$DEFAULT_REPORT_ROOT"
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2
  exit 2
}
[[ "$report_root" == /* && ! -L "$report_root" ]] || {
  printf 'BLOCKED: report root must be absolute and not a symlink.\n' >&2
  exit 2
}
for required in awk bash cat chmod date grep mkdir mktemp python3 rm sha256sum tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in "$PROFILE" "$VALIDATOR" "$TEST_RUNNER" "$ACCEPTED_REPORT" "$ACCEPTED_OBSERVATION"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 38 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$ACCEPTED_REPORT" | awk '{print $1}')" == "$EXPECTED_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 37 report checksum mismatch.\n' >&2
  exit 2
}
[[ "$(sha256sum "$ACCEPTED_OBSERVATION" | awk '{print $1}')" == "$EXPECTED_OBSERVATION_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 37 observation checksum mismatch.\n' >&2
  exit 2
}
for fact in \
  'cases_passed=6;cases_failed=0;required_citations=13;covered_citations=13' \
  'lexical_or_fallback_observed=true' \
  'profile_promotion_eligible=true' \
  'accepted_database_unchanged=true' \
  'script_37_retrieval_gap_recalibration=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || {
    printf 'BLOCKED: required accepted Script 37 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "$TEST_RUNNER"
python3 -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$VALIDATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-38.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-38.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
test_result="$work_root/tests.txt"
validation_result="$work_root/profile.txt"
bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  cat "$test_result" >&2
  printf 'script_38_retrieval_profile_freeze=blocked;reason=local_regression\n' >&2
  exit 1
}
grep -Fq 'Ran 90 tests' "$test_result" || {
  printf 'script_38_retrieval_profile_freeze=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}

PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 "$VALIDATOR" \
  --profile "$PROFILE" \
  --observation "$ACCEPTED_OBSERVATION" \
  --expected-observation-sha256 "$EXPECTED_OBSERVATION_SHA256" \
  --expected-retrieval-profile-id "$EXPECTED_RETRIEVAL_PROFILE_ID" \
  --expected-chunk-profile-id "$EXPECTED_CHUNK_PROFILE_ID" \
  >"$validation_result"
grep -Fxq 'method_profile_validation=pass' "$validation_result" || {
  printf 'script_38_retrieval_profile_freeze=blocked;reason=profile_validation\n' >&2
  exit 1
}

if [[ "$validate_only" == true ]]; then
  cat "$validation_result"
  printf 'script_38_retrieval_profile_freeze_source=pass;tests=90;retained_report=false\n'
  exit 0
fi

umask 077
mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/retrieval_profile_freeze_${timestamp}_XXXXXX.txt")"
{
  printf 'purpose=freeze_calibrated_retrieval_profile\n'
  printf 'started_utc=%s\n' "$timestamp"
  printf 'authorized_actions=read_accepted_local_evidence_validate_frozen_profile_run_local_tests_write_content_free_local_report\n'
  printf 'non_actions=no_remote_access_no_model_call_no_database_access_no_package_change_no_secret_processing_no_source_document_read\n'
  printf 'local_tests=pass;tests=90\n'
  cat "$validation_result"
  printf 'accepted_script_37_report_sha256=%s\n' "$EXPECTED_REPORT_SHA256"
  printf 'accepted_observation_sha256=%s\n' "$EXPECTED_OBSERVATION_SHA256"
  printf 'calibrated_retrieval_profile=frozen\n'
  printf 'script_38_retrieval_profile_freeze=pass;next_gate=implement_relationship_contract\n'
} | tee "$report_path"
chmod 600 "$report_path"
printf 'local_report=%s\n' "$report_path"

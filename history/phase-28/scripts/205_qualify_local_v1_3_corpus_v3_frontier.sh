#!/usr/bin/env bash
# Qualify the exact local Ishikawa v1.3 candidate and promoted corpus v3 with
# the frozen sixty-question frontier gate before human UI validation.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/205_qualify_local_v1_3_corpus_v3_frontier.sh --validate-only
#   bash ./phase-28-apisachi-tokuli/scripts/205_qualify_local_v1_3_corpus_v3_frontier.sh --run

set -Eeuo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly FRONTIER_CASES="$PHASE_ROOT/reference/ishikawa-v1.3-corpus-v3-frontier-cases.json"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_v1_3_complete_api.py"
readonly INNER_GATE="$SCRIPT_DIR/201_ingest_and_qualify_isolated_synthetic_corpus_v3.sh"
readonly CANDIDATE_GATE="$SCRIPT_DIR/203_promote_corpus_v3_and_assemble_v1_3_frontier_candidate.sh"

readonly CANDIDATE_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.3-frontier-candidate"
readonly PROMOTION_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3-promotion"
readonly ARCHIVE_SHA256='1ed8b578de29dab137fa105a5b4f86b7e74d1d92170a58b185f6b8ef8f9af3c7'
readonly QUALIFICATION_SHA256='254de7ab18c34b7ea61b71b60b7f428d1ef1ed79569d55809413aee1820c5139'
readonly SOURCE_MANIFEST_SHA256='17e3264c94780414597273e49a77d8b527cdd9349f3590f0f1e083f10dc7b9b9'
readonly PROMOTION_SHA256='26c469ec555540d3f55f63c845c4db567d07cd09bdcf089ed78fc240e621bf57'
readonly ARCHIVE="$CANDIDATE_ROOT/ishikawa-v1.3-frontier-candidate-${ARCHIVE_SHA256:0:16}.tar.gz"
readonly QUALIFICATION="$CANDIDATE_ROOT/v1_3_frontier_candidate_qualification_${ARCHIVE_SHA256:0:16}.json"
readonly SOURCE_MANIFEST="$CANDIDATE_ROOT/v1_3_frontier_candidate_source_${ARCHIVE_SHA256:0:16}.sha256"
readonly PROMOTION="$PROMOTION_ROOT/synthetic_corpus_v3_promotion_${PROMOTION_SHA256:0:16}.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-corpus-v3-frontier-promotion"

readonly CANDIDATE_GATE_SHA256='ca0ae4637e86ec7fa9751faaefd654c2d2ff6e6be3684956ad9cde7e14d0e50d'
readonly INNER_GATE_SHA256='6234ca2c88299a0ea265633f187f3db2858051ae7fb3efdc22d20099bda89c23'
readonly EVALUATOR_SHA256='924287b2621df7b757e6e85fae1679d42f2459f19e16e7d1bfdb4a8dc02004d1'
readonly FRONTIER_CASES_SHA256='2ba5f61518ca17b0eaa26f024abe35418b050f9bd8d5b3e1677062c9d7a626a3'
readonly DECISIONS_SHA256='49a77a0c595c8940bd9676137e90dec68d18d3f93a48e95639410111f4e23f4c'
readonly EXPECTED_PACKAGE_MARKER='ishikawa_v1_3_verification=pass;application=frontier_candidate;database_schema=version_5;python_modules=52;operator_documents=11;web_runtime_files=15;retrieval_mrr_at_20=0.895450;exact_generation_boundary=bound;bounded_generation=v13_50;historical_mutation_files=0'

mode="${1:-}"
if [[ "$#" -ne 1 || ( "$mode" != '--validate-only' && "$mode" != '--run' ) ]]; then
  printf '%s\n' \
    'FAILURE DETAIL' \
    'stage=argument_validation' \
    'reason=exactly_one_mode_required' \
    'detail=Script 205 requires exactly one mode: --validate-only or --run.' \
    'operator_action=Rerun Script 205 with exactly one supported mode.' \
    '' 'SCRIPT RESULT' \
    'script_205_local_v1_3_corpus_v3_frontier=blocked' >&2
  exit 2
fi

block_preflight() {
  printf '%s\n' \
    'FAILURE DETAIL' 'stage=preflight' "reason=$1" \
    'detail=A frozen local frontier input or validation contract did not match.' \
    'operator_action=Use the named reason below. If candidate_artifact_missing is reported, run the provided Script 203 command first; otherwise correct the named local prerequisite and rerun Script 205.' \
    '' 'SCRIPT RESULT' \
    'script_205_local_v1_3_corpus_v3_frontier=blocked' >&2
  exit "${2:-1}"
}

for required in awk bash date find grep mkdir mktemp python3 rm sed sha256sum \
  sort tar tee; do
  command -v "$required" >/dev/null 2>&1 \
    || block_preflight "local_command_missing_${required}" 2
done

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || block_preflight "${label}_unsafe"
  [[ "$(sha256sum -- "$path" | awk '{print $1}')" == "$expected" ]] \
    || block_preflight "${label}_identity_changed"
}

check_file "$CANDIDATE_GATE" "$CANDIDATE_GATE_SHA256" candidate_gate
check_file "$INNER_GATE" "$INNER_GATE_SHA256" inner_gate
check_file "$EVALUATOR" "$EVALUATOR_SHA256" evaluator
check_file "$FRONTIER_CASES" "$FRONTIER_CASES_SHA256" frontier_cases
check_file "$DECISIONS" "$DECISIONS_SHA256" decisions
grep -F '| `V13-51` |' "$DECISIONS" | grep -Fq '| FROZEN |' \
  || block_preflight v13_51_not_frozen

bash -n "${BASH_SOURCE[0]}" "$CANDIDATE_GATE" "$INNER_GATE" \
  || block_preflight shell_syntax_invalid
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$EVALUATOR" || block_preflight python_syntax_invalid
case_validation="$(PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --validate-cases --cases "$FRONTIER_CASES" 2>&1)" \
  || block_preflight frontier_case_validation_failed
grep -Eq '^v1_3_complete_api_case_set=pass;cases=60;responsive=60;nonresponsive=0;broad_navigation=0;required_evidence=60;identity=[0-9a-f]{64}$' \
  <<<"$case_validation" || block_preflight frontier_case_contract_invalid

candidate_validation="$({ bash "$CANDIDATE_GATE" --validate-only; } 2>&1)" \
  || {
    printf '%s\n' "$candidate_validation" >&2
    block_preflight candidate_gate_validation_failed
  }
for fact in \
  "candidate_archive_sha256=${ARCHIVE_SHA256};source_manifest_sha256=${SOURCE_MANIFEST_SHA256}" \
  "corpus_promotion_sha256=${PROMOTION_SHA256};qualification_sha256=${QUALIFICATION_SHA256}" \
  'script_203_corpus_v3_promotion_and_frontier_candidate=pass'; do
  grep -Fxq "$fact" <<<"$candidate_validation" \
    || block_preflight candidate_gate_contract_invalid
done

inner_validation="$({ bash "$INNER_GATE" --validate-frontier; } 2>&1)" \
  || {
    printf '%s\n' "$inner_validation" >&2
    block_preflight frontier_gate_validation_failed
  }
for fact in \
  'qualification_profile=frontier_60' \
  'api_cases=60;responsive=60;nonresponsive=0;broad_navigation=0;required_evidence=60' \
  'script_201_isolated_corpus_v3_api_qualification=ready'; do
  grep -Fxq "$fact" <<<"$inner_validation" \
    || block_preflight frontier_gate_contract_invalid
done

script_sha256="$(sha256sum -- "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$mode" == '--validate-only' ]]; then
  printf '%s\n' \
    'purpose=validate_local_v1_3_corpus_v3_sixty_question_frontier_gate' \
    "script_sha256=$script_sha256" \
    "candidate_archive_sha256=$ARCHIVE_SHA256;corpus_promotion_sha256=$PROMOTION_SHA256" \
    'frontier_cases=60;responsive=60;documents=30;required_evidence=60' \
    'next_gate_on_pass=local_human_ui_validation' \
    'database_contact=false;model_contact=false;credential_read=false;service_started=false;emceedanko_contact=false' \
    '' 'SCRIPT RESULT' \
    'script_205_local_v1_3_corpus_v3_frontier=ready'
  exit 0
fi

for retained in "$ARCHIVE" "$QUALIFICATION" "$SOURCE_MANIFEST" "$PROMOTION"; do
  [[ -f "$retained" && ! -L "$retained" && -r "$retained" ]] \
    || block_preflight candidate_artifact_missing
  [[ -f "$retained.sha256" && ! -L "$retained.sha256" ]] \
    || block_preflight candidate_checksum_missing
  (cd -- "$(dirname -- "$retained")" \
    && sha256sum --check --strict "$(basename -- "$retained.sha256")" >/dev/null) \
    || block_preflight candidate_checksum_failed
done
check_file "$ARCHIVE" "$ARCHIVE_SHA256" candidate_archive
check_file "$QUALIFICATION" "$QUALIFICATION_SHA256" candidate_qualification
check_file "$SOURCE_MANIFEST" "$SOURCE_MANIFEST_SHA256" candidate_source_manifest
check_file "$PROMOTION" "$PROMOTION_SHA256" corpus_promotion

work_root="$(mktemp -d /tmp/ishikawa-script-205.XXXXXX)" \
  || block_preflight workspace_creation_failed
report_path=''
failure_reason=''
failure_stage=initialization
emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}
block() {
  failure_reason="$1"
  failure_stage="$2"
  exit "${3:-1}"
}
cleanup() {
  local status="$?" result=pass
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-205.* && -d "$work_root" ]] \
    && rm -rf -- "$work_root"
  if (( status != 0 )) || [[ -n "$failure_reason" ]]; then
    result=blocked
    emit 'FAILURE DETAIL'
    emit "stage=${failure_stage:-unclassified}"
    emit "reason=${failure_reason:-unexpected_exit_${status}}"
    emit 'detail=The exact local candidate or sixty-question frontier qualification failed at the named stage.'
    emit 'operator_action=Use the preceding nested failure detail and retained artifact path to correct the named condition, then rerun Script 205.'
  fi
  [[ -z "$report_path" ]] || emit "local_report=$report_path"
  emit ''
  emit 'SCRIPT RESULT'
  emit "script_205_local_v1_3_corpus_v3_frontier=$result"
  exit "$status"
}
trap cleanup EXIT
trap 'block interrupted signal 130' INT
trap 'block interrupted signal 143' TERM

mkdir -p -- "$REPORT_ROOT" || block report_root_creation_failed initialization
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/local_frontier_${timestamp}_XXXXXX.txt")" \
  || block report_creation_failed initialization

failure_stage=candidate_identity
mkdir -p -- "$work_root/extracted"
tar -xzf "$ARCHIVE" -C "$work_root/extracted" \
  || block candidate_archive_extraction_failed candidate_identity
extracted="$work_root/extracted/ishikawa-v1.3-frontier-candidate"
[[ -d "$extracted" && ! -L "$extracted" ]] \
  || block candidate_archive_layout_invalid candidate_identity
package_marker="$(bash "$extracted/verify-ishikawa-v1.3")" \
  || block candidate_package_verification_failed candidate_identity
[[ "$package_marker" == "$EXPECTED_PACKAGE_MARKER" ]] \
  || block candidate_package_marker_invalid candidate_identity

PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$QUALIFICATION" "$PROMOTION" "$SOURCE_MANIFEST" "$PRODUCT_ROOT" <<'PY' \
  || block candidate_receipt_validation_failed candidate_identity
import hashlib
import json
import pathlib
import re
import sys

qualification = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
promotion = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
manifest_path = pathlib.Path(sys.argv[3])
product_root = pathlib.Path(sys.argv[4])
assert qualification["archive_sha256"] == "1ed8b578de29dab137fa105a5b4f86b7e74d1d92170a58b185f6b8ef8f9af3c7"
assert qualification["body_mrr_at_20"] == 0.895450
assert qualification["bounded_generation"] == "v13_50"
assert qualification["coding_standard_compliant"] is True
assert qualification["deterministic_archive"] is True
assert qualification["fresh_application_install"] is True
assert qualification["generation_optional_group_limit"] == 6
assert qualification["generation_prompt_targets"] == [8192, 12288, 16384]
assert qualification["native_test_count"] == 462
assert qualification["synthetic_corpus_included"] is False
assert promotion["status"] == "promoted"
assert promotion["corpus_identity"] == "synthetic-corpus-v3"
assert promotion["documents"] == 30
assert promotion["pages"] == 150
assert promotion["relationship_pairs"] == 90
assert promotion["retrieval_candidates"] == 943
assert promotion["runtime_flat_file_index"] is False
assert promotion["production_database_changed"] is False

lines = manifest_path.read_text(encoding="utf-8").splitlines()
assert len(lines) == 83
for line in lines:
    match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
    assert match is not None
    expected, relative = match.groups()
    if relative.startswith("application/python/ishikawa/"):
        source = product_root / relative
    elif relative.startswith("application/web/"):
        source = product_root / relative
    elif relative.startswith("config/"):
        source = product_root / "config/templates" / relative.removeprefix("config/")
    else:
        raise AssertionError(relative)
    assert source.is_file() and not source.is_symlink()
    assert hashlib.sha256(source.read_bytes()).hexdigest() == expected
PY
emit 'purpose=qualify_exact_local_v1_3_and_corpus_v3_with_sixty_question_frontier_gate'
emit "started_utc=$timestamp;script_sha256=$script_sha256"
emit "candidate_archive_sha256=$ARCHIVE_SHA256;corpus_promotion_sha256=$PROMOTION_SHA256"
emit 'frontier_cases=60;responsive=60;documents=30;required_evidence=60;human_ui_validation=false'
emit 'non_actions=no_emceedanko_contact_no_org_lab_contact_no_accepted_database_contact_no_black_corpus_access_no_package_change_no_service_install_no_autostart'

failure_stage=frontier_qualification
inner_output="$work_root/frontier-gate.txt"
set +e
bash "$INNER_GATE" --run-frontier 2>&1 \
  | tee "$inner_output" | tee -a "$report_path"
inner_status="${PIPESTATUS[0]}"
set -e
(( inner_status == 0 )) \
  || block inner_frontier_gate_failed frontier_qualification
for fact in \
  'qualification=pass;corpus_v3_database=pass;frontier_60=pass;self_validation=pass' \
  'next_gate=local_human_ui_validation' \
  'script_201_isolated_corpus_v3_api_qualification=pass'; do
  grep -Fxq "$fact" "$inner_output" \
    || block inner_frontier_pass_marker_missing frontier_qualification
done

api_artifact="$(sed -n 's/^api_artifact=//p' "$inner_output" | tail -n 1)"
database_artifact="$(sed -n 's/^database_artifact=//p' "$inner_output" | tail -n 1)"
for artifact in "$api_artifact" "$database_artifact"; do
  [[ "$artifact" == "$REPO_ROOT"/local/artifacts/ishikawa/* \
      && -f "$artifact" && ! -L "$artifact" && -f "$artifact.sha256" ]] \
    || block retained_frontier_artifact_invalid artifact_validation
  (cd -- "$(dirname -- "$artifact")" \
    && sha256sum --check --strict "$(basename -- "$artifact.sha256")" >/dev/null) \
    || block retained_frontier_checksum_failed artifact_validation
done

failure_stage=artifact_validation
frontier_summary="$(PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$api_artifact" "$database_artifact" <<'PY'
import json
import pathlib
import sys

api = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
database = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
summary = api["summary"]
assert api["synthetic_content_only"] is True
assert api["canary"] == {"abort_reason": None, "case_id": "R-001", "passed": True}
assert summary["acceptance_gate"] == "pass"
assert summary["case_count"] == 60
assert summary["contract_valid_count"] == 60
assert summary["expected_status_match_count"] == 60
assert summary["required_evidence_count"] == 60
assert summary["required_evidence_returned_count"] == 60
assert summary["required_evidence_cited_count"] == 60
assert summary["dependency_failure_count"] == 0
assert len(api["cases"]) == 60
assert database["status"] == "pass"
assert database["corpus_identity"] == "synthetic-corpus-v3"
assert database["inventory"]["documents"] == 30
assert database["inventory"]["pages"] == 150
assert database["inventory"]["authoritative_chunks"] == 786
assert database["inventory"]["retrieval_candidates"] == 943
assert database["inventory"]["relationship_pairs"] == 90
print(
    f"cases={summary['case_count']};"
    f"required_returned={summary['required_evidence_returned_count']}/60;"
    f"required_cited={summary['required_evidence_cited_count']}/60;"
    f"dependency_failures={summary['dependency_failure_count']}"
)
PY
)" || block retained_frontier_contract_invalid artifact_validation
emit "frontier_gate=pass;$frontier_summary"
emit "api_artifact=$api_artifact"
emit "database_artifact=$database_artifact"
emit 'promotion=pass;local_frontier=accepted;next_gate=local_human_ui_validation'

#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify and retain the corrected synthetic-corpus-v2 promotion bundle.
#
# Mental model:
#   Promotion of the corpus and optimization of retrieval are independent.
#   Bind the repeatable Script 162 corpus evidence, revalidate the exact files,
#   preserve corpus v1, and assemble the source/configuration/evidence needed for
#   an isolated v2 ingestion. Do not include Script 164 sibling assemblies or
#   any Script 166 optimization finalist in the promotion bundle.
#
# Boundaries:
#   Local read-only validation plus a new content-addressed promotion bundle.
#   No database, model, credential, service, black-corpus, package, accepted-
#   release, retrieval-profile, or corpus-v1 change. No ingestion is performed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/167_qualify_synthetic_corpus_v2_promotion.sh --run

usage() {
  sed -n '3,25p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Qualify and retain the corpus-v2 promotion bundle.' \
    '  --validate-only Validate bound inputs and promotion contracts only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly SCRIPT_162_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-corrected/corrected_synthetic_corpus_v2_20261022T183142Z_FCSzS0.txt"
readonly CANDIDATE="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-corrected/synthetic_corpus_v2_corrected_candidate_20261022T183142Z"
readonly CANDIDATE_SUMS="$CANDIDATE/SHA256SUMS"
readonly V1_MANIFEST="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/manifest.json"
readonly CLASS_REGISTRY="$PRODUCT_ROOT/tests/fixtures/pipeline_writer/document_classes.yaml"
readonly DOCUMENT_CATALOG="$PRODUCT_ROOT/tests/fixtures/pipeline_writer/document_catalog.yaml"
readonly INGESTION_MANIFEST="$PRODUCT_ROOT/tests/fixtures/pipeline_writer/ingestion_manifest.yaml"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-promotion"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-promotion"

readonly DECISIONS_SHA256='f210a94a3b5413efb107fb97a77e5085e9da37bda53348c3006adad7a11c35f9'
readonly SCRIPT_162_REPORT_SHA256='828503831ea649328315cd8dfc5f971e2c30551545f98b9c32a83a83dfbbe290'
readonly CANDIDATE_SUMS_SHA256='e9b32c095b67849defc0e6e9537f9bf3965bce586db58890aadd76329040e0a5'
readonly V1_MANIFEST_SHA256='c00a7a5dc6969ca5c22e0ac4adb5f2d8878439dd0b41adb46ccb079e6f866cfa'
readonly CLASS_REGISTRY_SHA256='6438c0a9e59bea1de0f9010dab2d7ee3de37419f3742666c096e0cca0e7ea32e'
readonly DOCUMENT_CATALOG_SHA256='055f45ad7e7f4647cd8399cba2eb460f83c2c5c72c73b46407407fc98da2e15c'
readonly INGESTION_MANIFEST_SHA256='e8de43bc053b640973753c2ab415d73d517abbaa3ce4238f72e6b3e8638bc180'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'script_167_synthetic_corpus_v2_promotion_qualification=blocked;reason=argument_invalid\n' >&2
      usage >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_167_synthetic_corpus_v2_promotion_qualification=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for command_name in bash cp date find grep mkdir mktemp mv python3 rm sed \
  sha256sum sort tee wc; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'script_167_synthetic_corpus_v2_promotion_qualification=blocked;reason=local_command_missing;command=%s\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'script_167_synthetic_corpus_v2_promotion_qualification=blocked;reason=%s_unsafe\n' "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | sed 's/[[:space:]].*$//')" == "$expected_sha256" ]] || {
    printf 'script_167_synthetic_corpus_v2_promotion_qualification=blocked;reason=%s_identity_changed\n' "$label" >&2
    exit 2
  }
}

check_file "$DECISIONS" "$DECISIONS_SHA256" frozen_decisions
check_file "$SCRIPT_162_REPORT" "$SCRIPT_162_REPORT_SHA256" script_162_report
check_file "$CANDIDATE_SUMS" "$CANDIDATE_SUMS_SHA256" candidate_checksum_manifest
check_file "$V1_MANIFEST" "$V1_MANIFEST_SHA256" accepted_v1_manifest
check_file "$CLASS_REGISTRY" "$CLASS_REGISTRY_SHA256" document_class_registry
check_file "$DOCUMENT_CATALOG" "$DOCUMENT_CATALOG_SHA256" document_catalog
check_file "$INGESTION_MANIFEST" "$INGESTION_MANIFEST_SHA256" ingestion_manifest

for decision in V13-22 V13-24 V13-25 V13-26 V13-27 V13-28 V13-29 V13-30; do
  grep -Fq "| \`$decision\` " "$DECISIONS" || {
    printf 'script_167_synthetic_corpus_v2_promotion_qualification=blocked;reason=decision_not_frozen;decision=%s\n' \
      "$decision" >&2
    exit 1
  }
done

grep -Fq 'script_162_correct_synthetic_corpus_v2=pass;' "$SCRIPT_162_REPORT" || {
  printf 'script_167_synthetic_corpus_v2_promotion_qualification=blocked;reason=script_162_not_clean\n' >&2
  exit 1
}
grep -Fq 'corpus_v1_changed=false;database_contact=false;model_contact=false;' "$SCRIPT_162_REPORT" || {
  printf 'script_167_synthetic_corpus_v2_promotion_qualification=blocked;reason=script_162_boundary_missing\n' >&2
  exit 1
}

(cd "$CANDIDATE" && sha256sum --quiet -c SHA256SUMS) || {
  printf 'script_167_synthetic_corpus_v2_promotion_qualification=blocked;reason=candidate_checksum_verification_failed\n' >&2
  exit 1
}

PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$CANDIDATE" "$V1_MANIFEST" "$DOCUMENT_CATALOG" "$INGESTION_MANIFEST" <<'PY'
import json
import pathlib
import re
import sys

candidate = pathlib.Path(sys.argv[1]).resolve(strict=True)
v1_manifest = pathlib.Path(sys.argv[2]).resolve(strict=True)
catalog_path = pathlib.Path(sys.argv[3]).resolve(strict=True)
ingestion_path = pathlib.Path(sys.argv[4]).resolve(strict=True)

manifest = json.loads((candidate / "manifest.json").read_text(encoding="utf-8"))
source_manifest = json.loads((candidate / "source_manifest.json").read_text(encoding="utf-8"))
truth = json.loads(
    (candidate / "evaluation/header_acceptance_truth.json").read_text(encoding="utf-8")
)
normalized = json.loads(
    (candidate / "qualification/normalized.json").read_text(encoding="utf-8")
)
chunks = json.loads(
    (candidate / "qualification/chunks.json").read_text(encoding="utf-8")
)

assert v1_manifest.is_file()
assert manifest["status"] == "synthetic_corpus_v2_candidate"
assert manifest["schema_version"] == 2
assert manifest["accepted_v1_mutated"] is False
assert manifest["source_corpus_content_used"] is False
assert manifest["document_count"] == 6
assert manifest["page_count"] == 26
assert set(manifest["departments"]) == {
    "Information Technology", "Operations Control", "Records Governance", "Scheduling Office"
}
assert truth["fixture_status"] == "fully_synthetic_no_source_text"
assert truth["accepted_v1_mutated"] is False
assert truth["first_semantic_body_page"] == 1
assert truth["leading_blank_page_policy"] == "removed_from_v2_before_masthead"
assert len(truth["documents"]) == 6
assert sum(item["pages"] for item in truth["documents"]) == 26
assert len(source_manifest["files"]) == 6
assert len({item["doc_id"] for item in source_manifest["files"]}) == 6
assert len({item["filename"] for item in source_manifest["files"]}) == 6
assert all((candidate / "source" / item["filename"]).is_file() for item in source_manifest["files"])
assert len(normalized["documents"]) == 6
assert sum(item["page_count"] for item in normalized["documents"]) == 26
assert all(item["blank_pages"] == [] for item in normalized["documents"])

all_candidates = [
    item
    for document in chunks["documents"]
    for item in document["candidates"]
]
metadata = [item for item in all_candidates if item["projection_kind"] == "document_control_metadata"]
assert chunks["method_profile"]["name"] == "ishikawa-structural-chunk-candidates-v4"
assert len(chunks["documents"]) == 6
assert len(all_candidates) == 139
assert len(metadata) == 6
assert all(item["citation_anchor"]["page_start"] == 1 for item in metadata)
assert all("document_control" in item["retrieval_filters"] for item in all_candidates)
assert all(
    "Document control metadata" not in item["context_text"]
    for item in all_candidates
    if item["projection_kind"] != "document_control_metadata"
)

catalog_text = catalog_path.read_text(encoding="utf-8")
ingestion_text = ingestion_path.read_text(encoding="utf-8")
expected_keys = {
    "form.tst-9001",
    "policy.governance-manual",
    "policy.ops-17-control-2001",
    "policy.ops-17-control-2002",
    "policy.schedule-2003",
    "procedure.incident-reporting",
}
expected_files = {item["filename"] for item in source_manifest["files"]}
assert set(re.findall(r"^\s*(?:-\s*)?document_key:\s*([^\s]+)\s*$", catalog_text, re.M)) == expected_keys
assert set(re.findall(r"^\s*(?:-\s*)?document_key:\s*([^\s]+)\s*$", ingestion_text, re.M)) == expected_keys
assert set(re.findall(r"^\s*(?:-\s*)?source_path:\s*([^\s]+)\s*$", ingestion_text, re.M)) == expected_files

# Experimental representations and scorer truth never enter the ingestion source/config path.
assert not (candidate / "qualification/retrieval-candidate.json").exists()
assert not any("optimization" in path.name for path in candidate.rglob("*"))
print("corpus_v2_promotion_contract=pass;documents=6;pages=26;candidates=139;metadata_candidates=6")
PY

bash -n "${BASH_SOURCE[0]}"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | sed 's/[[:space:]].*$//')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_synthetic_corpus_v2_promotion_qualification' \
    "script_sha256=$script_sha256;decisions_sha256=$DECISIONS_SHA256" \
    "candidate_checksum_manifest_sha256=$CANDIDATE_SUMS_SHA256;accepted_v1_manifest_sha256=$V1_MANIFEST_SHA256" \
    'promotion_basis=generation_extraction_normalization_masthead_metadata_structure_repeatability_safety' \
    'optimization_gate_used=false;retrieval_profile_changed=false;corpus_v1_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_167_synthetic_corpus_v2_promotion_qualification=pass'
  exit 0
fi

report_path=''
work_root=''
artifact_path=''
failure_recorded=false

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}

block() {
  failure_recorded=true
  emit "script_167_synthetic_corpus_v2_promotion_qualification=blocked;reason=$1"
  exit 1
}

cleanup() {
  local initial_status="$?"
  trap - EXIT HUP INT TERM
  set +e
  if (( initial_status != 0 )) && [[ "$failure_recorded" != true ]]; then
    emit "script_167_synthetic_corpus_v2_promotion_qualification=blocked;reason=unexpected_failure;exit_code=$initial_status"
  fi
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-167.* ]]; then
    rm -rf -- "$work_root"
  fi
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    printf 'local_report=%s;local_report_sha256=%s\n' \
      "$report_path" "$(sha256sum "$report_path" | sed 's/[[:space:]].*$//')"
  fi
  exit "$initial_status"
}
trap cleanup EXIT HUP INT TERM

umask 077
mkdir -p -- "$ARTIFACT_ROOT" "$REPORT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/synthetic_corpus_v2_promotion_qualification_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-167.XXXXXX)"
bundle="$work_root/synthetic_corpus_v2_promotion_candidate"
artifact_path="$ARTIFACT_ROOT/synthetic_corpus_v2_promotion_candidate_$timestamp"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" ]] || block artifact_path_exists

emit 'purpose=qualify_synthetic_corpus_v2_for_isolated_promotion'
emit "started_utc=$timestamp;script_sha256=$script_sha256;decisions_sha256=$DECISIONS_SHA256"
emit "script_162_report_sha256=$SCRIPT_162_REPORT_SHA256;candidate_checksum_manifest_sha256=$CANDIDATE_SUMS_SHA256"
emit 'authorized_actions=read_bound_local_corpus_evidence_revalidate_candidate_assemble_immutable_promotion_bundle_write_content_free_report'
emit 'non_actions=no_database_contact_no_ingestion_no_model_contact_no_credential_read_no_service_change_no_black_corpus_access_no_corpus_v1_change_no_package_change_no_accepted_release_change_no_retrieval_profile_change_no_optimization_profile_promotion'

mkdir -p -- "$bundle/source" "$bundle/config" "$bundle/evidence/evaluation-only"
cp -- "$CANDIDATE/source/"*.pdf "$bundle/source/" || block source_copy_failed
cp -- "$CLASS_REGISTRY" "$bundle/config/document_classes.yaml" || block class_registry_copy_failed
cp -- "$DOCUMENT_CATALOG" "$bundle/config/document_catalog.yaml" || block document_catalog_copy_failed
cp -- "$INGESTION_MANIFEST" "$bundle/config/ingestion_manifest.yaml" || block ingestion_manifest_copy_failed
cp -- "$CANDIDATE/manifest.json" "$bundle/evidence/corpus_manifest.json" || block corpus_manifest_copy_failed
cp -- "$CANDIDATE/source_manifest.json" "$bundle/evidence/source_manifest.json" || block source_manifest_copy_failed
cp -- "$CANDIDATE/qualification/normalized.json" "$bundle/evidence/normalized.json" || block normalized_copy_failed
cp -- "$CANDIDATE/qualification/chunks.json" "$bundle/evidence/atomic_chunks.json" || block chunks_copy_failed
cp -- "$CANDIDATE/evaluation/header_acceptance_truth.json" \
  "$bundle/evidence/evaluation-only/header_acceptance_truth.json" || block truth_copy_failed

PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$bundle/promotion-receipt.json" "$timestamp" "$script_sha256" \
  "$DECISIONS_SHA256" "$SCRIPT_162_REPORT_SHA256" "$CANDIDATE_SUMS_SHA256" \
  "$V1_MANIFEST_SHA256" <<'PY'
import json
import pathlib
import sys

output = pathlib.Path(sys.argv[1])
receipt = {
    "schema": "ishikawa.synthetic-corpus-v2-promotion-candidate.v1",
    "created_utc": sys.argv[2],
    "script_sha256": sys.argv[3],
    "decisions_sha256": sys.argv[4],
    "script_162_report_sha256": sys.argv[5],
    "candidate_checksum_manifest_sha256": sys.argv[6],
    "accepted_v1_manifest_sha256": sys.argv[7],
    "corpus_identity": "synthetic-corpus-v2",
    "document_count": 6,
    "page_count": 26,
    "atomic_candidate_count": 139,
    "document_control_metadata_candidate_count": 6,
    "status": "qualified_for_isolated_ingestion",
    "boundaries": {
        "corpus_v1_changed": False,
        "database_contact": False,
        "ingestion_performed": False,
        "optimization_gate_used": False,
        "experimental_sibling_assemblies_included": False,
        "optimization_profile_included": False,
        "retrieval_profile_changed": False,
        "evaluation_truth_in_ingestion_path": False,
    },
    "next_gate": "publish_to_isolated_synthetic_corpus_v2_database",
}
output.write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n", encoding="utf-8")
PY

(cd "$bundle" && find . -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort \
  | while IFS= read -r relative_path; do sha256sum "$relative_path"; done > SHA256SUMS) \
  || block bundle_checksum_generation_failed
(cd "$bundle" && sha256sum --quiet -c SHA256SUMS) || block bundle_checksum_verification_failed

file_count="$(find "$bundle" -type f | wc -l | sed 's/[[:space:]]//g')"
source_count="$(find "$bundle/source" -maxdepth 1 -type f -name '*.pdf' | wc -l | sed 's/[[:space:]]//g')"
[[ "$source_count" == 6 ]] || block promotion_source_inventory_invalid
[[ ! -e "$bundle/evidence/retrieval-candidate.json" ]] || block experimental_retrieval_candidate_included
[[ ! -e "$bundle/config/header_acceptance_truth.json" ]] || block evaluation_truth_in_ingestion_path

mv -- "$bundle" "$artifact_path" || block artifact_promotion_failed

bundle_sums_sha256="$(sha256sum "$artifact_path/SHA256SUMS" | sed 's/[[:space:]].*$//')"
emit 'milestone=promotion_basis;state=pass;generation=true;extraction=true;normalization=true;masthead_metadata=true;structure=true;repeatability=true;safety=true'
emit 'milestone=promotion_bundle;state=pass;documents=6;pages=26;atomic_candidates=139;metadata_candidates=6;experimental_assemblies=0;optimization_profiles=0'
emit "promotion_bundle=$artifact_path;bundle_files=$file_count;bundle_checksum_manifest_sha256=$bundle_sums_sha256"
emit 'promotion_qualification=pass;corpus_v2_promoted=false;next_gate=publish_to_isolated_synthetic_corpus_v2_database'
emit 'optimization_gate_used=false;optimization_deferred_until_corpus_v2_promotion_complete=true'
emit 'database_contact=false;ingestion_performed=false;model_contact=false;corpus_v1_changed=false;retrieval_profile_changed=false'
emit ''
emit 'SCRIPT RESULT'
emit 'script_167_synthetic_corpus_v2_promotion_qualification=pass'


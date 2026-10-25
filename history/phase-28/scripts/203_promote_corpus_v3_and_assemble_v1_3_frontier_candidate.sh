#!/usr/bin/env bash
# Promote the exact qualified synthetic corpus v3 fixture and assemble one
# deterministic Ishikawa v1.3 frontier deployment candidate.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/203_promote_corpus_v3_and_assemble_v1_3_frontier_candidate.sh --validate-only
#   bash ./phase-28-apisachi-tokuli/scripts/203_promote_corpus_v3_and_assemble_v1_3_frontier_candidate.sh --run

set -Eeuo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_PACKAGE="$PRODUCT_ROOT/application/python/ishikawa"
readonly WEB_ROOT="$PRODUCT_ROOT/application/web"
readonly CONFIG_ROOT="$PRODUCT_ROOT/config/templates"
readonly PACKAGING_ROOT="$PRODUCT_ROOT/packaging"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly APPLICATION_README="$PACKAGING_ROOT/README.md"
readonly APPLICATION_INSTALLER="$PACKAGING_ROOT/install-ishikawa"
readonly DATABASE_README="$PACKAGING_ROOT/database/README.md"
readonly DATABASE_INSTALLER="$PACKAGING_ROOT/database/install-schema"
readonly FINAL_SCHEMA="$PACKAGING_ROOT/database/schema.sql"
readonly DEPLOYMENT_README="$PACKAGING_ROOT/deployment/README-v1.3.md"
readonly PACKAGE_VERIFIER="$PACKAGING_ROOT/deployment/verify-ishikawa-v1.3"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly CODING_STANDARD_EVALUATOR="$SCRIPT_DIR/evaluate_consolidated_build_coding_standard.py"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"

readonly SCRIPT_204="$SCRIPT_DIR/204_qualify_v13_50_bounded_generation_latency.sh"
readonly DATABASE_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v13-48-isolated-corpus-v3-api/isolated_corpus_v3_database_20261023T202838Z_TzkQbl.json"
readonly DATABASE_ARTIFACT_CHECKSUM="$DATABASE_ARTIFACT.sha256"
readonly API_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v13-48-isolated-corpus-v3-api/isolated_corpus_v3_api_20261023T202838Z_TzkQbl.json"
readonly API_ARTIFACT_CHECKSUM="$API_ARTIFACT.sha256"
readonly GENERATION_CAPTURE_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v13-48-isolated-corpus-v3-api/generation_capture_20261023T202838Z_TzkQbl"
readonly CORPUS_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3/synthetic_corpus_v3_candidate_20261023T043639Z"
readonly CORPUS_MANIFEST="$CORPUS_ROOT/manifest.json"
readonly CORPUS_SOURCE_MANIFEST="$CORPUS_ROOT/source_manifest.json"
readonly CORPUS_CHECKSUMS="$CORPUS_ROOT/SHA256SUMS"

readonly SCRIPT_204_SHA256='87444fd90c465a10506f48857f18673b37a1da0cc90b6b88731c2d8251015ec9'
readonly DATABASE_ARTIFACT_SHA256='bbc23c034af2f59e447f04d0eeffd91ccd122f87bc6b0cbec180b60cdd63381e'
readonly API_ARTIFACT_SHA256='716cc88fd2f5719fbabafd77c3bdd58d10a75f5915e59dcebc5326730243fb21'
readonly CORPUS_MANIFEST_SHA256='fe863eb642791dfec219aa022ddf9ffcbc4558ab4876bc6ec968f4d64e6d7c3d'
readonly CORPUS_SOURCE_MANIFEST_SHA256='c4798ac1957b0e936cec68a0bfae7fe7d22aa0317fe8107a8d980edefe357f21'
readonly CORPUS_CHECKSUMS_SHA256='3220c5ae7fd16c37086511893c63c4784b9adf10635e40c79332b4a7b4c79fce'
readonly TEST_RUNNER_SHA256='092b2cb8e5254d1ca2b6e71a496bf76743004134848e249d5d7b9f37d9d62eb7'
readonly CODING_STANDARD_EVALUATOR_SHA256='1378200df6072a9b1958b2923ce9bf03005269e5e42977b4caba875edfa2354f'
readonly DEPLOYMENT_README_SHA256='078cfe524fa44641e0a135655d8561f9415e36390c61e6a2973ff4c0961324a6'
readonly PACKAGE_VERIFIER_SHA256='ee6fcc1e63741514903d7953707e6672c49b8fe38d499f56570d3b75841b82e2'
readonly APPLICATION_INSTALLER_SHA256='6d44378cf9f715cb70b38e36312bb7ff0dd805f1d6a6d7ee1703e97961ac3c6b'
readonly DATABASE_INSTALLER_SHA256='9c54a2dce6f7b55f7636c6792befebc0fdd87f0369dfc0b498a8475d677cd2e2'
readonly FINAL_SCHEMA_SHA256='1fdbed2439fb5bfecaef5dd857f380661c298f8459d6cc2319114b78e5a09c5d'
readonly CODING_STANDARD_SHA256='7a773b54db619bcbbd4fbc9c1ec5846d5ad0891e1a0f66de8d94487562989235'
readonly ACCEPTED_RETRIEVAL_PROFILE_ID='7c8f8f37ccce47cde1bdbb6cb43b321be14e54a11c8435e845ab7508c3dc8edb'
readonly ACCEPTED_CHUNK_METHOD_ID='d72a07f81eabc1f521ab1fd54f84289979365c6c71f8e3220a53b1e8c9a1c037'
readonly BUNDLE_NAME='ishikawa-v1.3-frontier-candidate'
readonly OUTPUT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.3-frontier-candidate"
readonly PROMOTION_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3-promotion"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-frontier-candidate"
readonly FORBIDDEN_PATTERN='phase[-_ ]*[0-9]|org[-_ ]*lab|danko|agentdanko|dankorepos|prj[0-9]|codex|opencode|local/artifacts|/mnt/|\.git/|repository|script[[:space:]_-]*[0-9]+'

readonly -a RUNTIME_CONFIGS=(
  api_profile.yaml deployment.yaml document_classes.yaml
  ingestion_dependencies.yaml injection_profile.yaml logging_profile.yaml
  method_profile.yaml product.yaml query_resolution_profile.yaml
  reconstruction_profile.yaml relationship_types.yaml relevance_profile.yaml
  retrieval_service_profile.yaml runtime_dependencies.yaml scope_profile.yaml
  sufficiency_profile.yaml
)
readonly -a PRODUCT_COMMANDS=(
  "$PRODUCT_ROOT/scripts/ishikawa-ingest"
  "$PRODUCT_ROOT/scripts/ishikawa-log-control"
  "$PRODUCT_ROOT/scripts/ishikawa-observability-retention"
  "$PRODUCT_ROOT/scripts/ishikawa-produce-artifacts"
  "$PRODUCT_ROOT/scripts/ishikawa-retrieval-api"
  "$PRODUCT_ROOT/scripts/ishikawa-stack"
)
readonly -a PIPELINE_COMMANDS=(
  "$SCRIPT_DIR/capture-pdf-extraction-observations.py"
  "$SCRIPT_DIR/normalize-pdf-extraction.py"
  "$SCRIPT_DIR/create-structural-chunk-candidates.py"
  "$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
)
readonly -a WEB_FILES=(
  app/api/dependencies/route.js
  app/api/live/route.js
  app/api/ready/route.js
  app/api/v1/chat/route.js
  app/api/v1/document/route.js
  app/globals.css app/layout.js app/page.js
  components/chat-workspace.js components/presentation-markdown.js
  lib/chat-contract.mjs lib/runtime-config.mjs
  next.config.mjs package.json public/theme-init.js
)
readonly -a PRODUCT_DOCS=(
  "$PRODUCT_ROOT/docs/APPLICATION_DEFINITION.md"
  "$PRODUCT_ROOT/docs/APPLICATION_DESIGN.md"
  "$PRODUCT_ROOT/docs/ARCHITECTURE.md"
  "$PRODUCT_ROOT/docs/CHAT_UI.md"
  "$PRODUCT_ROOT/docs/CHUNKING_INGESTION_RETRIEVAL.md"
  "$PRODUCT_ROOT/docs/COMMAND_SHEET.md"
  "$PRODUCT_ROOT/docs/INSTALLED_OPERATOR_INGESTION.md"
  "$PRODUCT_ROOT/docs/OPERATOR_GUIDE.md"
  "$PRODUCT_ROOT/docs/PRODUCT_PRESENTATION_CONFIGURATION.md"
  "$PRODUCT_ROOT/docs/SERVICE_OPERATIONS.md"
  "$PRODUCT_ROOT/docs/STACK_CONTROL.md"
)
readonly -a SYSTEMD_UNITS=(
  "$PACKAGING_ROOT/systemd/ishikawa-observability-retention.service"
  "$PACKAGING_ROOT/systemd/ishikawa-observability-retention.timer"
  "$PACKAGING_ROOT/systemd/ishikawa-retrieval-api.service"
)

mode="${1:-}"
if [[ "$#" -ne 1 || ( "$mode" != '--validate-only' && "$mode" != '--run' ) ]]; then
  printf '%s\n' \
    'FAILURE DETAIL' \
    'stage=argument_validation' \
    'reason=exactly_one_mode_required' \
    'detail=Script 203 requires exactly one mode: --validate-only or --run.' \
    'operator_action=Rerun Script 203 with exactly one supported mode.' \
    '' 'SCRIPT RESULT' \
    'script_203_corpus_v3_promotion_and_frontier_candidate=blocked' >&2
  exit 2
fi

block_preflight() {
  printf '%s\n' \
    'FAILURE DETAIL' 'stage=preflight' "reason=$1" \
    'detail=A required frozen input, qualified artifact, or source contract did not match.' \
    'operator_action=Correct the named prerequisite and rerun this same Script 203 command.' \
    '' 'SCRIPT RESULT' \
    'script_203_corpus_v3_promotion_and_frontier_candidate=blocked' >&2
  exit "${2:-1}"
}

for required in awk bash basename cmp cp date find grep gzip install mkdir \
  mktemp mv python3 rm sed sha256sum sort stat tar tee tr wc; do
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
check_file "$SCRIPT_204" "$SCRIPT_204_SHA256" script_204
check_file "$DATABASE_ARTIFACT" "$DATABASE_ARTIFACT_SHA256" database_artifact
check_file "$API_ARTIFACT" "$API_ARTIFACT_SHA256" api_artifact
check_file "$CORPUS_MANIFEST" "$CORPUS_MANIFEST_SHA256" corpus_manifest
check_file "$CORPUS_SOURCE_MANIFEST" "$CORPUS_SOURCE_MANIFEST_SHA256" corpus_source_manifest
check_file "$CORPUS_CHECKSUMS" "$CORPUS_CHECKSUMS_SHA256" corpus_checksums
check_file "$TEST_RUNNER" "$TEST_RUNNER_SHA256" test_runner
check_file "$CODING_STANDARD_EVALUATOR" "$CODING_STANDARD_EVALUATOR_SHA256" coding_standard_evaluator
check_file "$DEPLOYMENT_README" "$DEPLOYMENT_README_SHA256" deployment_readme
check_file "$PACKAGE_VERIFIER" "$PACKAGE_VERIFIER_SHA256" package_verifier
check_file "$APPLICATION_INSTALLER" "$APPLICATION_INSTALLER_SHA256" application_installer
check_file "$DATABASE_INSTALLER" "$DATABASE_INSTALLER_SHA256" database_installer
check_file "$FINAL_SCHEMA" "$FINAL_SCHEMA_SHA256" final_schema
check_file "$CODING_STANDARD" "$CODING_STANDARD_SHA256" coding_standard

for file in "$DATABASE_ARTIFACT_CHECKSUM" "$API_ARTIFACT_CHECKSUM"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] \
    || block_preflight qualification_checksum_unsafe
  (cd -- "$(dirname -- "$file")" && sha256sum --check --strict "$(basename -- "$file")" >/dev/null) \
    || block_preflight qualification_checksum_failed
done
(cd -- "$CORPUS_ROOT" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block_preflight corpus_internal_checksum_failed

[[ -d "$GENERATION_CAPTURE_ROOT" && ! -L "$GENERATION_CAPTURE_ROOT" ]] \
  || block_preflight generation_capture_root_unsafe
find "$GENERATION_CAPTURE_ROOT" -type l -print -quit | grep -q . \
  && block_preflight generation_capture_symlink_found

for decision in V13-36 V13-47 V13-48 V13-49 V13-50; do
  grep -F "| \`$decision\` |" "$DECISIONS" | grep -Fq '| FROZEN |' \
    || block_preflight "${decision,,}_not_frozen"
done

PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$CORPUS_MANIFEST" "$DATABASE_ARTIFACT" "$API_ARTIFACT" \
  "$GENERATION_CAPTURE_ROOT" <<'PY' \
  || block_preflight qualified_artifact_contract_invalid
import collections
import json
import sys
from pathlib import Path

corpus, database, api = (
    json.loads(Path(name).read_text(encoding="utf-8")) for name in sys.argv[1:4]
)
capture_root = Path(sys.argv[4])
assert corpus["status"] == "synthetic_corpus_v3_candidate"
assert corpus["document_count"] == 30
assert corpus["page_count"] == 150
assert corpus["relationship_count"] == 90
assert corpus["department_count"] >= 10
assert corpus["accepted_v1_mutated"] is False
assert corpus["accepted_v2_mutated"] is False
assert database["status"] == "pass"
assert database["corpus_identity"] == "synthetic-corpus-v3"
assert database["inventory"] == {
    "authoritative_chunks": 786,
    "documents": 30,
    "pages": 150,
    "relationship_pairs": 90,
    "relationship_records": 240,
    "retrieval_candidates": 943,
    "retrieval_scoring_only": 157,
}
assert database["checks"]["runtime_flat_file_index"] is False
assert api["canary"] == {"abort_reason": None, "case_id": "R-001", "passed": True}
assert api["synthetic_content_only"] is True
assert api["summary"]["acceptance_gate"] == "pass"
assert api["summary"]["case_count"] == 13
assert api["summary"]["expected_status_match_count"] == 13
assert api["summary"]["contract_valid_count"] == 13
assert api["summary"]["dependency_failure_count"] == 0
assert api["summary"]["required_evidence_count"] == 6
assert api["summary"]["required_evidence_returned_count"] == 6
assert api["summary"]["required_evidence_cited_count"] == 6
assert len(api["cases"]) == 13
assert all(item["metrics"]["status"] == item["case"]["expected_status"] for item in api["cases"])

targets = collections.Counter()
answered = 0
detail_names = {
    "nomic", "lexical_sql", "vector_sql", "fusion", "reconstruction", "tokenization"
}
for observation in api["cases"]:
    response = observation["response"]
    if response["status"] != "answered":
        continue
    answered += 1
    diagnostics = response["diagnostics"]
    target = diagnostics["prompt_target_tokens"]
    assert target in {8192, 12288, 16384}
    assert response["context_budget"]["tokens_used"] <= target + 2048
    assert set(diagnostics["timings_ms"]["retrieval_detail"]) == detail_names
    assert all(
        isinstance(value, int) and value >= 0
        for value in diagnostics["timings_ms"]["retrieval_detail"].values()
    )
    targets[target] += 1
assert answered == 6

r001 = next(item for item in api["cases"] if item["case"]["case_id"] == "R-001")
r001_payloads = []
for request_path in sorted(capture_root.glob("attempt-*/request-body.json")):
    assert request_path.is_file() and not request_path.is_symlink()
    request = json.loads(request_path.read_text(encoding="utf-8"))
    payload = json.loads(request["messages"][1]["content"])
    if payload["question"] == r001["case"]["question"]:
        r001_payloads.append(payload)
assert r001_payloads
for payload in r001_payloads:
    groups = payload["evidence_groups"]
    assert groups
    identifiers = [group.get("document", {}).get("identifier") for group in groups]
    assert identifiers[0] == "99 TST 2001"
    unique_identifiers = {value for value in identifiers if value is not None}
    item_count_by_identifier = collections.Counter()
    packed_citations = 0
    for group, identifier in zip(groups, identifiers):
        items = group["items"]
        assert items
        packed_citations += len(items)
        item_count_by_identifier[identifier] += len(items)
    assert len(unique_identifiers) <= 6
    assert packed_citations <= 48
    assert item_count_by_identifier["99 TST 2001"] == max(
        item_count_by_identifier.values()
    )
PY

mapfile -t python_sources < <(find "$PYTHON_PACKAGE" -maxdepth 1 -type f -name '*.py' -print | sort)
(( ${#python_sources[@]} == 52 )) || block_preflight python_source_inventory_changed

required_files=(
  "$TEST_RUNNER" "$APPLICATION_README" "$APPLICATION_INSTALLER"
  "$DATABASE_README" "$DATABASE_INSTALLER" "$FINAL_SCHEMA"
  "$DEPLOYMENT_README" "$PACKAGE_VERIFIER" "$CODING_STANDARD"
  "$CODING_STANDARD_EVALUATOR" "$DECISIONS"
  "$PACKAGING_ROOT/document_catalog.yaml"
  "$PACKAGING_ROOT/ingestion_manifest.example.yaml"
  "$CONFIG_ROOT/document_catalog.yaml"
  "${python_sources[@]}" "${PRODUCT_COMMANDS[@]}" "${PIPELINE_COMMANDS[@]}"
  "${PRODUCT_DOCS[@]}" "${SYSTEMD_UNITS[@]}"
)
for name in "${RUNTIME_CONFIGS[@]}"; do required_files+=("$CONFIG_ROOT/$name"); done
for name in "${WEB_FILES[@]}"; do required_files+=("$WEB_ROOT/$name"); done
for file in "${required_files[@]}"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] \
    || block_preflight required_source_unsafe
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER" "$APPLICATION_INSTALLER" \
  "$DATABASE_INSTALLER" "$PACKAGE_VERIFIER" \
  || block_preflight shell_syntax_invalid
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$CODING_STANDARD_EVALUATOR" "${python_sources[@]}" "${PIPELINE_COMMANDS[@]}" \
  "${PRODUCT_COMMANDS[@]:0:5}" \
  || block_preflight python_syntax_invalid

work_root="$(mktemp -d /tmp/ishikawa-script-203.XXXXXX)"
failure_reason=''
failure_stage='initialization'
report_path=''
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
  [[ "$work_root" == /tmp/ishikawa-script-203.* && -d "$work_root" ]] \
    && rm -rf -- "$work_root"
  if (( status != 0 )) || [[ -n "$failure_reason" ]]; then
    result=blocked
    emit 'FAILURE DETAIL'
    emit "stage=${failure_stage:-unclassified}"
    emit "reason=${failure_reason:-unexpected_exit_${status}}"
    emit 'detail=Corpus promotion or frontier-candidate assembly stopped at the named stage.'
    emit 'operator_action=Correct the named reason and rerun this same Script 203 command.'
  fi
  [[ -z "$report_path" ]] || emit "local_report=$report_path"
  emit ''
  emit 'SCRIPT RESULT'
  emit "script_203_corpus_v3_promotion_and_frontier_candidate=$result"
  exit "$status"
}
trap cleanup EXIT
trap 'block interrupted signal 130' INT
trap 'block interrupted signal 143' TERM

script_sha256="$(sha256sum -- "${BASH_SOURCE[0]}" | awk '{print $1}')"
emit 'purpose=promote_exact_synthetic_corpus_v3_and_assemble_v1_3_frontier_candidate'
emit "script_sha256=$script_sha256;script_204_sha256=$SCRIPT_204_SHA256"
emit 'authorized_actions=verify_frozen_local_evidence_promote_synthetic_fixture_run_local_native_tests_assemble_deterministic_candidate_verify_fresh_install_write_local_artifacts'
emit 'non_actions=no_target_contact_no_database_contact_no_model_contact_no_credential_read_no_service_start_no_image_pull_no_black_corpus_access_no_accepted_release_change_no_source_documents_in_package'

failure_stage=native_tests
emit 'milestone=native_tests;state=start'
test_result="$work_root/native-tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 \
  || {
    tail -n 120 "$test_result"
    block native_test_regression native_tests
  }
grep -Fq 'Ran 462 tests' "$test_result" \
  || block native_test_count_mismatch native_tests
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" \
  || block native_test_pass_marker_absent native_tests
emit 'milestone=native_tests;state=pass;tests=462'

assemble_application() {
  local destination="$1" source name destination_name
  install -d -m 0755 -- \
    "$destination/payload/application/python/ishikawa" \
    "$destination/payload/application/web/app/api/dependencies" \
    "$destination/payload/application/web/app/api/live" \
    "$destination/payload/application/web/app/api/ready" \
    "$destination/payload/application/web/app/api/v1/chat" \
    "$destination/payload/application/web/app/api/v1/document" \
    "$destination/payload/application/web/components" \
    "$destination/payload/application/web/lib" \
    "$destination/payload/application/web/public" \
    "$destination/payload/config/examples" \
    "$destination/payload/docs" "$destination/payload/scripts" \
    "$destination/payload/systemd"
  install -m 0644 -- "$APPLICATION_README" "$destination/README.md"
  install -m 0755 -- "$APPLICATION_INSTALLER" "$destination/install-ishikawa"
  for source in "${python_sources[@]}"; do
    install -m 0644 -- "$source" "$destination/payload/application/python/ishikawa/$(basename -- "$source")"
  done
  for name in "${WEB_FILES[@]}"; do
    install -m 0644 -- "$WEB_ROOT/$name" "$destination/payload/application/web/$name"
  done
  for source in "${PRODUCT_COMMANDS[@]}" "${PIPELINE_COMMANDS[@]}"; do
    install -m 0755 -- "$source" "$destination/payload/scripts/$(basename -- "$source")"
  done
  for name in "${RUNTIME_CONFIGS[@]}"; do
    install -m 0644 -- "$CONFIG_ROOT/$name" "$destination/payload/config/$name"
  done
  install -m 0644 -- "$PACKAGING_ROOT/document_catalog.yaml" \
    "$destination/payload/config/document_catalog.yaml"
  install -m 0644 -- "$PACKAGING_ROOT/ingestion_manifest.example.yaml" \
    "$destination/payload/config/examples/ingestion_manifest.yaml"
  install -m 0644 -- "$CONFIG_ROOT/document_catalog.yaml" \
    "$destination/payload/config/examples/document_catalog.yaml"
  for source in "${PRODUCT_DOCS[@]}"; do
    destination_name="$(basename -- "$source")"
    [[ "$destination_name" != INSTALLED_OPERATOR_INGESTION.md ]] \
      || destination_name=OPERATOR_INGESTION.md
    install -m 0644 -- "$source" "$destination/payload/docs/$destination_name"
  done
  for source in "${SYSTEMD_UNITS[@]}"; do
    install -m 0644 -- "$source" "$destination/payload/systemd/$(basename -- "$source")"
  done
  (
    cd -- "$destination"
    while IFS= read -r name; do sha256sum "$name"; done < <(
      find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
    ) >SHA256SUMS
  )
  chmod 0644 "$destination/SHA256SUMS"
}

assemble_database() {
  local destination="$1"
  install -d -m 0755 -- "$destination"
  install -m 0644 -- "$DATABASE_README" "$destination/README.md"
  install -m 0755 -- "$DATABASE_INSTALLER" "$destination/install-schema"
  install -m 0644 -- "$FINAL_SCHEMA" "$destination/schema.sql"
  (
    cd -- "$destination"
    while IFS= read -r name; do sha256sum "$name"; done < <(
      find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
    ) >SHA256SUMS
  )
  chmod 0644 "$destination/SHA256SUMS"
}

assemble_bundle() {
  local destination="$1" bundle="$1/$BUNDLE_NAME"
  install -d -m 0755 -- "$bundle/application" "$bundle/database"
  assemble_application "$bundle/application"
  assemble_database "$bundle/database"
  install -m 0644 -- "$DEPLOYMENT_README" "$bundle/README.md"
  install -m 0755 -- "$PACKAGE_VERIFIER" "$bundle/verify-ishikawa-v1.3"
  (
    cd -- "$bundle"
    while IFS= read -r name; do sha256sum "$name"; done < <(
      find . -type f ! -path './SHA256SUMS' -printf '%P\n' | sort
    ) >SHA256SUMS
  )
  chmod 0644 "$bundle/SHA256SUMS"
}

failure_stage=deterministic_assembly
emit 'milestone=deterministic_assembly;state=start;builds=2'
mkdir -p -- "$work_root/build-a" "$work_root/build-b"
assemble_bundle "$work_root/build-a"
assemble_bundle "$work_root/build-b"
readonly bundle_a="$work_root/build-a/$BUNDLE_NAME"
readonly bundle_b="$work_root/build-b/$BUNDLE_NAME"

expected_verification='ishikawa_v1_3_verification=pass;application=frontier_candidate;database_schema=version_5;python_modules=52;operator_documents=11;web_runtime_files=15;retrieval_mrr_at_20=0.895450;exact_generation_boundary=bound;bounded_generation=v13_50;historical_mutation_files=0'
for bundle in "$bundle_a" "$bundle_b"; do
  bash "$bundle/verify-ishikawa-v1.3" | grep -Fxq "$expected_verification" \
    || block package_verification_failed deterministic_assembly
  find "$bundle" -type l -print -quit | grep -q . \
    && block package_symlink_found deterministic_assembly
  if find "$bundle" -type f \( -name '*.pyc' -o -name '*.pyo' \) -print -quit | grep -q . \
    || find "$bundle" -type d -name __pycache__ -print -quit | grep -q .; then
    block generated_python_file_found deterministic_assembly
  fi
  if find "$bundle" -type f \( -iname '*migration*' -o -iname '*mutation*' -o -iname '*patch*' -o -iname '*repair*' \) -print -quit | grep -q .; then
    block historical_mutation_file_found deterministic_assembly
  fi
  if find "$bundle" -type d ! -perm -005 -print -quit | grep -q . \
    || find "$bundle" -type f ! -perm -004 -print -quit | grep -q .; then
    block nonroot_package_readability_invalid deterministic_assembly
  fi
  grep -ERiq -- "$FORBIDDEN_PATTERN" "$bundle" \
    && block development_jargon_found deterministic_assembly
  grep -ERq -- 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|Authorization:[[:space:]]*Bearer[[:space:]]+[^$]' "$bundle" \
    && block credential_material_found deterministic_assembly
done
cmp -s \
  <(cd -- "$bundle_a" && find . -type f -printf '%P\n' | sort | while IFS= read -r name; do sha256sum "$name"; done) \
  <(cd -- "$bundle_b" && find . -type f -printf '%P\n' | sort | while IFS= read -r name; do sha256sum "$name"; done) \
  || block bundle_not_reproducible deterministic_assembly
emit 'milestone=deterministic_assembly;state=pass;builds=2;identical=true'

failure_stage=coding_standard
coding_standard_result="$work_root/coding-standard.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CODING_STANDARD_EVALUATOR" \
  --bundle-root "$bundle_a" --standard "$CODING_STANDARD" \
  --output "$coding_standard_result" >/dev/null \
  || block coding_standard_noncompliance coding_standard
emit 'milestone=coding_standard;state=pass'

failure_stage=fresh_install
install_root="$work_root/fresh-install/Ishikawa"
bash "$bundle_a/application/install-ishikawa" --install-root "$install_root" \
  >"$work_root/application-install.txt" \
  || block fresh_application_install_failed fresh_install
grep -Fq 'ishikawa_install=pass;' "$work_root/application-install.txt" \
  || block fresh_application_install_marker_absent fresh_install
[[ "$(find "$install_root/application/python/ishikawa" -maxdepth 1 -type f -name '*.py' | awk 'END {print NR+0}')" == 52 ]] \
  || block installed_python_inventory_invalid fresh_install
[[ "$(find "$install_root/docs" -maxdepth 1 -type f -name '*.md' | awk 'END {print NR+0}')" == 11 ]] \
  || block installed_document_inventory_invalid fresh_install
PYTHONDONTWRITEBYTECODE=1 "$install_root/scripts/ishikawa-retrieval-api" --check-config >/dev/null \
  || block installed_retrieval_config_invalid fresh_install
PYTHONDONTWRITEBYTECODE=1 "$install_root/scripts/ishikawa-observability-retention" --check-config >/dev/null \
  || block installed_retention_config_invalid fresh_install
"$install_root/scripts/ishikawa-stack" --help >/dev/null \
  || block installed_stack_command_invalid fresh_install
"$install_root/scripts/ishikawa-ingest" --help >/dev/null \
  || block installed_ingest_command_invalid fresh_install
bash "$bundle_a/database/install-schema" --help >/dev/null \
  || block installed_schema_command_invalid fresh_install
emit 'milestone=fresh_install;state=pass;services_started=false;database_changed=false'

failure_stage=archive_verification
temporary_archive="$work_root/$BUNDLE_NAME.tar.gz"
tar --sort=name --format=posix --pax-option=delete=atime,delete=ctime \
  --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
  -C "$work_root/build-a" -cf - "$BUNDLE_NAME" | gzip -n >"$temporary_archive"
mkdir -p -- "$work_root/extracted"
tar -xzf "$temporary_archive" -C "$work_root/extracted"
readonly extracted_bundle="$work_root/extracted/$BUNDLE_NAME"
bash "$extracted_bundle/verify-ishikawa-v1.3" | grep -Fxq "$expected_verification" \
  || block extracted_package_verification_failed archive_verification

archive_sha256="$(sha256sum -- "$temporary_archive" | awk '{print $1}')"
archive_bytes="$(stat -c '%s' "$temporary_archive")"
package_file_count="$(find "$extracted_bundle" -type f | awk 'END {print NR+0}')"
application_file_count="$(find "$extracted_bundle/application" -type f | awk 'END {print NR+0}')"
database_file_count="$(find "$extracted_bundle/database" -type f | awk 'END {print NR+0}')"
source_manifest="$work_root/source-manifest.sha256"
for source in "${python_sources[@]}"; do
  printf '%s  application/python/ishikawa/%s\n' \
    "$(sha256sum -- "$source" | awk '{print $1}')" "$(basename -- "$source")"
done >"$source_manifest"
for name in "${RUNTIME_CONFIGS[@]}"; do
  printf '%s  config/%s\n' "$(sha256sum -- "$CONFIG_ROOT/$name" | awk '{print $1}')" "$name"
done >>"$source_manifest"
for name in "${WEB_FILES[@]}"; do
  printf '%s  application/web/%s\n' "$(sha256sum -- "$WEB_ROOT/$name" | awk '{print $1}')" "$name"
done >>"$source_manifest"
sort -o "$source_manifest" "$source_manifest"
source_manifest_sha256="$(sha256sum -- "$source_manifest" | awk '{print $1}')"
source_manifest_files="$(wc -l <"$source_manifest" | tr -d ' ')"

qualification="$work_root/qualification.json"
promotion="$work_root/corpus-promotion.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$qualification" "$promotion" "$archive_sha256" "$archive_bytes" \
  "$package_file_count" "$application_file_count" "$database_file_count" \
  "$source_manifest_sha256" "$source_manifest_files" <<'PY'
import json
import sys
from pathlib import Path

(
    qualification_path, promotion_path, archive_sha256, archive_bytes,
    package_files, application_files, database_files, source_manifest_sha256,
    source_manifest_files,
) = sys.argv[1:]
qualification = {
    "application_file_count": int(application_files),
    "archive_bytes": int(archive_bytes),
    "archive_sha256": archive_sha256,
    "body_mrr_at_20": 0.895450,
    "bounded_generation": "v13_50",
    "chunk_method_profile_id": "d72a07f81eabc1f521ab1fd54f84289979365c6c71f8e3220a53b1e8c9a1c037",
    "coding_standard_compliant": True,
    "database_file_count": int(database_files),
    "deterministic_archive": True,
    "exact_generation_boundary": True,
    "fresh_application_install": True,
    "historical_mutation_files": 0,
    "generation_optional_group_limit": 6,
    "generation_prompt_targets": [8192, 12288, 16384],
    "native_test_count": 462,
    "package_file_count": int(package_files),
    "receipt_schema_version": 1,
    "release_name": "Ishikawa v1.3 frontier candidate",
    "repository_references": False,
    "retrieval_profile_id": "7c8f8f37ccce47cde1bdbb6cb43b321be14e54a11c8435e845ab7508c3dc8edb",
    "schema_version": 5,
    "secret_material": False,
    "source_document_count": 0,
    "source_manifest_file_count": int(source_manifest_files),
    "source_manifest_sha256": source_manifest_sha256,
    "synthetic_corpus_included": False,
}
promotion = {
    "api_artifact_sha256": "716cc88fd2f5719fbabafd77c3bdd58d10a75f5915e59dcebc5326730243fb21",
    "body_mrr_at_20": 0.895450,
    "corpus_identity": "synthetic-corpus-v3",
    "corpus_manifest_sha256": "fe863eb642791dfec219aa022ddf9ffcbc4558ab4876bc6ec968f4d64e6d7c3d",
    "database_artifact_sha256": "bbc23c034af2f59e447f04d0eeffd91ccd122f87bc6b0cbec180b60cdd63381e",
    "documents": 30,
    "frontier_synthetic_fixture": True,
    "pages": 150,
    "production_database_changed": False,
    "receipt_schema_version": 1,
    "relationship_pairs": 90,
    "retrieval_candidates": 943,
    "runtime_flat_file_index": False,
    "script_204_sha256": "87444fd90c465a10506f48857f18673b37a1da0cc90b6b88731c2d8251015ec9",
    "source_documents_in_deployment_package": False,
    "status": "promoted",
}
Path(qualification_path).write_text(
    json.dumps(qualification, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
Path(promotion_path).write_text(
    json.dumps(promotion, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
qualification_sha256="$(sha256sum -- "$qualification" | awk '{print $1}')"
promotion_sha256="$(sha256sum -- "$promotion" | awk '{print $1}')"
coding_standard_sha256="$(sha256sum -- "$coding_standard_result" | awk '{print $1}')"
emit "milestone=archive_verification;state=pass;archive_sha256=$archive_sha256;package_files=$package_file_count"

if [[ "$mode" == '--validate-only' ]]; then
  emit 'milestone=retention;state=skipped;mode=validate-only'
  emit "candidate_archive_sha256=$archive_sha256;source_manifest_sha256=$source_manifest_sha256"
  emit "corpus_promotion_sha256=$promotion_sha256;qualification_sha256=$qualification_sha256"
  exit 0
fi

failure_stage=artifact_retention
mkdir -p -- "$OUTPUT_ROOT" "$PROMOTION_ROOT" "$REPORT_ROOT"
archive_name="$BUNDLE_NAME-${archive_sha256:0:16}.tar.gz"
archive_path="$OUTPUT_ROOT/$archive_name"
qualification_path="$OUTPUT_ROOT/v1_3_frontier_candidate_qualification_${archive_sha256:0:16}.json"
coding_standard_path="$OUTPUT_ROOT/v1_3_frontier_candidate_coding_standard_${archive_sha256:0:16}.json"
source_manifest_path="$OUTPUT_ROOT/v1_3_frontier_candidate_source_${archive_sha256:0:16}.sha256"
promotion_path="$PROMOTION_ROOT/synthetic_corpus_v3_promotion_${promotion_sha256:0:16}.json"

retain_exact() {
  local source="$1" destination="$2" conflict_reason="$3" candidate
  [[ ! -L "$destination" ]] || block output_symlink_found artifact_retention
  if [[ -e "$destination" ]]; then
    cmp -s "$source" "$destination" \
      || block "$conflict_reason" artifact_retention
  else
    candidate="$(mktemp "$(dirname -- "$destination")/.ishikawa-v1.3.XXXXXX")"
    cp -- "$source" "$candidate"
    mv -- "$candidate" "$destination"
  fi
}
retain_exact "$temporary_archive" "$archive_path" archive_identity_conflict
retain_exact "$qualification" "$qualification_path" qualification_identity_conflict
retain_exact "$coding_standard_result" "$coding_standard_path" coding_standard_identity_conflict
retain_exact "$source_manifest" "$source_manifest_path" source_manifest_identity_conflict
retain_exact "$promotion" "$promotion_path" corpus_promotion_identity_conflict

for retained in "$archive_path" "$qualification_path" "$coding_standard_path" \
  "$source_manifest_path" "$promotion_path"; do
  checksum="$retained.sha256"
  printf '%s  %s\n' "$(sha256sum -- "$retained" | awk '{print $1}')" \
    "$(basename -- "$retained")" >"$work_root/retained.sha256"
  retain_exact "$work_root/retained.sha256" "$checksum" retained_checksum_identity_conflict
  (cd -- "$(dirname -- "$retained")" && sha256sum --check --strict "$(basename -- "$checksum")" >/dev/null) \
    || block retained_checksum_failure artifact_retention
done

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v1_3_frontier_candidate_${timestamp}_XXXXXX.txt")"
emit 'purpose=retain_promoted_synthetic_corpus_v3_and_v1_3_frontier_candidate'
emit "started_utc=$timestamp;script_sha256=$script_sha256"
emit "script_204_sha256=$SCRIPT_204_SHA256;v13_50=pass;complete_api_cases=13/13"
emit "corpus_promotion=$promotion_path;corpus_promotion_sha256=$promotion_sha256;documents=30;pages=150;relationship_pairs=90;retrieval_candidates=943"
emit "archive=$archive_path;archive_sha256=$archive_sha256;archive_bytes=$archive_bytes"
emit "qualification=$qualification_path;qualification_sha256=$qualification_sha256"
emit "source_manifest=$source_manifest_path;source_manifest_sha256=$source_manifest_sha256;source_files=$source_manifest_files"
emit "coding_standard_receipt=$coding_standard_path;coding_standard_receipt_sha256=$coding_standard_sha256"
emit "package_files=$package_file_count;application_files=$application_file_count;database_files=$database_file_count;python_modules=52;operator_documents=11;web_runtime_files=15"
emit 'native_tests=462;deterministic_archive=true;fresh_application_install=pass;internal_checksums=pass;schema_version=5'
emit 'target_contact=false;database_contact=false;model_contact=false;credential_read=false;service_changed=false;accepted_release_changed=false;source_documents_included=false'
emit 'promotion=pass;frontier_candidate=assembled;next_gate=qualify_fresh_v1_3_frontier_candidate_on_emceedanko'

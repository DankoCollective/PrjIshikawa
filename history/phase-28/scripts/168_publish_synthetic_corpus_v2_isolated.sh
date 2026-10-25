#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Publish the Script 167-qualified synthetic corpus v2 into an isolated local
#   PostgreSQL cluster and prove that the accepted corpus-v1 cluster is intact.
#
# Mental model:
#   Validate the immutable promotion bundle, snapshot corpus v1 read-only,
#   create PostgreSQL cluster 16/ishikawa-v2 on loopback port 5433 with manual
#   start, install the canonical final schema, publish through Ishikawa's real
#   ingestion pipeline, verify v2 metadata and retrieval projections, then
#   compare corpus v1 with its pre-run snapshot. Retrieval optimization remains
#   separate and cannot change this publication.
#
# Inputs or prerequisites:
#   DankoSurface on Ubuntu 24.04 ARM64; one valid Script 167 promotion bundle;
#   existing PostgreSQL 16 and pgvector packages; corpus v1 in cluster 16/main;
#   Nomic forwarded on 127.0.0.1:8001; attended sudo; one Nomic key; and new
#   passwords for the isolated rag_ingest and rag_retrieval roles.
#
# Outputs or artifact lane:
#   A manual-start PostgreSQL cluster named ishikawa-v2 on port 5433, database
#   rag_catalog, six published v2 documents, retained derived artifacts, a
#   content-free publication receipt, and a content-free report. If this script
#   creates the cluster and later fails, it removes only that new cluster.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/168_publish_synthetic_corpus_v2_isolated.sh --run

usage() {
  sed -n '3,30p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                    Create, publish, and verify isolated corpus v2.' \
    '  --validate-only          Validate local source and promotion bundle only.' \
    '  --expected-hostname NAME Exact expected local short hostname.' \
    '  --expected-os-version V  Exact expected Ubuntu major.minor version.' \
    '  --expected-architecture A Exact expected machine architecture.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly APPLICATION_SOURCE_ROOT="$PRODUCT_ROOT/application/python/ishikawa"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly SCRIPT_167="$SCRIPT_DIR/167_qualify_synthetic_corpus_v2_promotion.sh"
readonly INGESTION_RUNNER="$SCRIPT_DIR/run_isolated_synthetic_v2_ingestion.py"
readonly PIPELINE_EXECUTABLE="$SCRIPT_DIR/ishikawa-produce-artifacts"
readonly PIPELINE_CAPTURE="$SCRIPT_DIR/capture-pdf-extraction-observations.py"
readonly PIPELINE_NORMALIZE="$SCRIPT_DIR/normalize-pdf-extraction.py"
readonly PIPELINE_CHUNK="$SCRIPT_DIR/create-structural-chunk-candidates.py"
readonly PIPELINE_EMBED="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly SCHEMA_PATH="$PRODUCT_ROOT/packaging/database/schema.sql"
readonly DEPLOYMENT_TEMPLATE="$PRODUCT_ROOT/config/templates/deployment.yaml"
readonly INGESTION_TEMPLATE="$PRODUCT_ROOT/config/templates/ingestion_dependencies.yaml"
readonly PROMOTION_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-promotion"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-isolated-publication"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-isolated-publication"
readonly ACCEPTED_V1_MANIFEST="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/manifest.json"

readonly SCRIPT_167_SHA256='5e9c830ff7b24e66bb48f741d8ae60a9b864765d3880187074ff0519b30b81a9'
readonly DECISIONS_SHA256='f210a94a3b5413efb107fb97a77e5085e9da37bda53348c3006adad7a11c35f9'
readonly INGESTION_RUNNER_SHA256='147b415d09f76d869d8da75a5ef07f9525fa54d7a6d034ab3d1829ca51687591'
readonly SCHEMA_SHA256='5cfd397152b726aedc97be84d8a06fc8f21cad6e1a11563e5e9dd3a1f026d568'
readonly DEPLOYMENT_TEMPLATE_SHA256='2a5008b70a8ffe615cfcb2ca4b5d5a3687888c362861670a4a79e0de32874cfb'
readonly INGESTION_TEMPLATE_SHA256='1e024911f74e923dc9c2aa8bc0a1efae82f4d739e2be032fd8f067a99481e91f'
readonly PIPELINE_EXECUTABLE_SHA256='0faa5c65fbf8af454040158813308fb239ec70535bd956c3ffbc0523f5904b94'
readonly PIPELINE_CAPTURE_SHA256='a303e63d1a2329ddec39d563b5a7bdddea5bd7d720206544744876171a5371e2'
readonly PIPELINE_NORMALIZE_SHA256='8e9193492c69bee6a31afe3f7606ec2efd528f79d76feb4189d462e6b3c206ea'
readonly PIPELINE_CHUNK_SHA256='2c042acfabe608a5683d212403beac6215d385301562de059dc55bd77ed44a26'
readonly PIPELINE_EMBED_SHA256='8f3c23ca30904dfb48a37f3366fd4b7873769bb92a527479fec5696f7fc456dc'
readonly ACCEPTED_V1_MANIFEST_SHA256='c00a7a5dc6969ca5c22e0ac4adb5f2d8878439dd0b41adb46ccb079e6f866cfa'
readonly APPLICATION_SOURCE_TREE_SHA256='e90c4edb9b704fce0eb4d894728275e84d0f7208a9ea55e8331bf104194ce0cb'
readonly TEST_RUNNER_SHA256='092b2cb8e5254d1ca2b6e71a496bf76743004134848e249d5d7b9f37d9d62eb7'
readonly EXPECTED_APPLICATION_SOURCE_FILES='51'
readonly EXPECTED_NATIVE_TESTS='408'

readonly POSTGRESQL_VERSION='16'
readonly V1_CLUSTER_NAME='main'
readonly V1_PORT='5432'
readonly V2_CLUSTER_NAME='ishikawa-v2'
readonly V2_PORT='5433'
readonly DATABASE_NAME='rag_catalog'
readonly OWNER_ROLE='rag_owner'
readonly INGEST_ROLE='rag_ingest'
readonly RETRIEVAL_ROLE='rag_retrieval'
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'
readonly EXPECTED_V2_IDENTITIES='form.tst-9001|3150feda7f340066d7bc769d88cc8159ad92cd6712b7adb9cb95eec610c7d2a6;policy.governance-manual|44e0f7a2859b288e8d48d63d589b474ef460ae1eed18bf18ffd2296a80601132;policy.ops-17-control-2001|859430d2d4775ba43a29130369ff508d1546ae146f26bd6b69b69b50fa9ed4f7;policy.ops-17-control-2002|3a87ebfb1d5bbfa556a14ca4528600cd306b4c90fe1fb606e7783bdb6ce56245;policy.schedule-2003|9e2fa113b9c77f315f81830e54583a86322522c02b7f272fb11bc50459379b59;procedure.incident-reporting|5214c20d54c79b4f7e41d3f1264c6ed1326f32b7e583477ec7b82c1b58266d8e'

expected_hostname="${ISHIKAWA_V2_EXPECTED_HOSTNAME:-DankoSurface}"
expected_os_version="${ISHIKAWA_V2_EXPECTED_OS_VERSION:-24.04}"
expected_architecture="${ISHIKAWA_V2_EXPECTED_ARCHITECTURE:-aarch64}"
run_authorized=false
validate_only=false

preflight_block() {
  local exit_code="$1" reason="$2"
  shift 2
  printf '\nSCRIPT RESULT\n' >&2
  printf 'reason=%s\n' "$reason" >&2
  local detail
  for detail in "$@"; do
    printf '%s\n' "$detail" >&2
  done
  printf 'script_168_isolated_synthetic_corpus_v2_publication=blocked\n' >&2
  exit "$exit_code"
}

build_retained_artifact_manifest() {
  local artifact_root="$1" manifest_path="$2" expected_count="$3"
  local relative_path expected_digest observed_digest
  local -a relative_paths=()

  [[ "$artifact_root" == /* && -d "$artifact_root" && ! -L "$artifact_root" ]] \
    || return 1
  [[ "$manifest_path" == /* && "$manifest_path" != "$artifact_root"/* ]] \
    || return 1
  [[ "$expected_count" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ -z "$(find "$artifact_root" -type l -print -quit)" ]] || return 1

  mapfile -t relative_paths < <(
    find "$artifact_root" -mindepth 2 -maxdepth 2 -type f -printf '%P\n' \
      | LC_ALL=C sort
  )
  (( ${#relative_paths[@]} == expected_count )) || return 1

  : >"$manifest_path" || return 1
  for relative_path in "${relative_paths[@]}"; do
    [[ "$relative_path" =~ ^([0-9a-f]{2})/([0-9a-f]{64})$ ]] || return 1
    expected_digest="${BASH_REMATCH[2]}"
    [[ "${BASH_REMATCH[1]}" == "${expected_digest:0:2}" ]] || return 1
    observed_digest="$(
      sha256sum "$artifact_root/$relative_path" | sed 's/[[:space:]].*$//'
    )" || return 1
    [[ "$observed_digest" == "$expected_digest" ]] || return 1
    printf '%s  %s\n' "$observed_digest" "$relative_path" \
      >>"$manifest_path" || return 1
  done
}

copy_retained_artifact_set() {
  local source_root="$1" destination_root="$2"
  local expected_digest relative_path observed_digest
  local copied_count=0

  [[ "$source_root" == /* && -d "$source_root" && ! -L "$source_root" ]] \
    || return 1
  [[ "$destination_root" == /* && -d "$destination_root" \
    && ! -L "$destination_root" ]] || return 1
  [[ -f "$source_root/SHA256SUMS" && ! -L "$source_root/SHA256SUMS" ]] \
    || return 1
  [[ -z "$(find "$destination_root" -mindepth 1 -print -quit)" ]] \
    || return 1

  while read -r expected_digest relative_path; do
    [[ "$expected_digest" =~ ^[0-9a-f]{64}$ \
      && "$relative_path" =~ ^([0-9a-f]{2})/([0-9a-f]{64})$ \
      && "${BASH_REMATCH[1]}" == "${expected_digest:0:2}" \
      && "${BASH_REMATCH[2]}" == "$expected_digest" \
      && -f "$source_root/$relative_path" \
      && ! -L "$source_root/$relative_path" ]] || return 1
    mkdir -p -- "$destination_root/${relative_path%/*}" || return 1
    dd if="$source_root/$relative_path" of="$destination_root/$relative_path" \
      bs=1M status=none || return 1
    observed_digest="$(
      sha256sum "$destination_root/$relative_path" | sed 's/[[:space:]].*$//'
    )" || return 1
    [[ "$observed_digest" == "$expected_digest" ]] || return 1
    (( copied_count += 1 ))
  done <"$source_root/SHA256SUMS"

  (( copied_count == 3 )) || return 1
  dd if="$source_root/SHA256SUMS" of="$destination_root/SHA256SUMS" \
    bs=1M status=none || return 1
  (cd -- "$destination_root" && sha256sum --quiet -c SHA256SUMS) \
    || return 1
  [[ "$(find "$destination_root" -type f | wc -l | tr -d '[:space:]')" == 4 \
    && -z "$(find "$destination_root" -type l -print -quit)" ]] \
    || return 1
}

application_source_tree_sha256() {
  (
    cd -- "$APPLICATION_SOURCE_ROOT" || exit 1
    find . -type f -name '*.py' -printf '%P\n' | LC_ALL=C sort \
      | while IFS= read -r relative_path; do
          printf '%s:' "$relative_path"
          sha256sum "$relative_path" | sed 's/[[:space:]].*$//'
        done
  ) | sha256sum | sed 's/[[:space:]].*$//'
}

while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --expected-architecture) expected_architecture="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *)
      usage >&2
      preflight_block 2 argument_invalid
      ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || {
  preflight_block 2 mode_invalid
}
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || {
  preflight_block 2 expected_hostname_invalid
}
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || {
  preflight_block 2 expected_os_version_invalid
}
[[ "$expected_architecture" =~ ^[A-Za-z0-9_-]+$ ]] || {
  preflight_block 2 expected_architecture_invalid
}

for required_command in \
  awk basename bash cp curl date dd find grep hostname kill mkdir mktemp mv pg_createcluster \
  pg_ctlcluster pg_dropcluster pg_isready pg_lsclusters psql python3 readlink \
  rm sed sha256sum sleep sort sudo tee tr uname wc; do
  if [[ "$validate_only" == true && "$required_command" =~ ^(pg_createcluster|pg_ctlcluster|pg_dropcluster|pg_isready|pg_lsclusters|psql|sudo)$ ]]; then
    continue
  fi
  command -v "$required_command" >/dev/null 2>&1 || {
    preflight_block 2 local_command_missing "command=$required_command"
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    preflight_block 2 "${label}_unsafe"
  }
  [[ "$(sha256sum "$path" | sed 's/[[:space:]].*$//')" == "$expected_sha256" ]] || {
    preflight_block 2 "${label}_identity_changed"
  }
}

check_file "$SCRIPT_167" "$SCRIPT_167_SHA256" script_167
check_file "$DECISIONS" "$DECISIONS_SHA256" frozen_decisions
check_file "$INGESTION_RUNNER" "$INGESTION_RUNNER_SHA256" isolated_ingestion_runner
check_file "$SCHEMA_PATH" "$SCHEMA_SHA256" canonical_schema
check_file "$DEPLOYMENT_TEMPLATE" "$DEPLOYMENT_TEMPLATE_SHA256" deployment_template
check_file "$INGESTION_TEMPLATE" "$INGESTION_TEMPLATE_SHA256" ingestion_template
check_file "$PIPELINE_EXECUTABLE" "$PIPELINE_EXECUTABLE_SHA256" pipeline_executable
check_file "$PIPELINE_CAPTURE" "$PIPELINE_CAPTURE_SHA256" pipeline_capture
check_file "$PIPELINE_NORMALIZE" "$PIPELINE_NORMALIZE_SHA256" pipeline_normalize
check_file "$PIPELINE_CHUNK" "$PIPELINE_CHUNK_SHA256" pipeline_chunk
check_file "$PIPELINE_EMBED" "$PIPELINE_EMBED_SHA256" pipeline_embed
check_file "$ACCEPTED_V1_MANIFEST" "$ACCEPTED_V1_MANIFEST_SHA256" accepted_v1_manifest
check_file "$TEST_RUNNER" "$TEST_RUNNER_SHA256" native_test_runner
[[ -x "$PIPELINE_EXECUTABLE" ]] || {
  preflight_block 2 pipeline_executable_not_executable
}
[[ -d "$APPLICATION_SOURCE_ROOT" && ! -L "$APPLICATION_SOURCE_ROOT" \
  && "$(find "$APPLICATION_SOURCE_ROOT" -type f -name '*.py' | wc -l | tr -d '[:space:]')" \
    == "$EXPECTED_APPLICATION_SOURCE_FILES" \
  && "$(application_source_tree_sha256)" == "$APPLICATION_SOURCE_TREE_SHA256" ]] || {
  preflight_block 2 application_source_tree_identity_changed
}

mapfile -t promotion_bundles < <(
  find "$PROMOTION_ROOT" -mindepth 1 -maxdepth 1 -type d \
    -name 'synthetic_corpus_v2_promotion_candidate_*' -print 2>/dev/null \
    | LC_ALL=C sort
)
(( ${#promotion_bundles[@]} >= 1 )) || {
  preflight_block 1 promotion_bundle_missing
}
promotion_bundle="${promotion_bundles[-1]}"
[[ "$promotion_bundle" == "$PROMOTION_ROOT"/synthetic_corpus_v2_promotion_candidate_* \
  && -d "$promotion_bundle" && ! -L "$promotion_bundle" ]] || {
  preflight_block 1 promotion_bundle_unsafe
}
(cd -- "$promotion_bundle" && sha256sum --quiet -c SHA256SUMS) || {
  preflight_block 1 promotion_bundle_checksum_failed
}

promotion_values="$({
  PYTHONDONTWRITEBYTECODE=1 python3 -B - \
    "$promotion_bundle" "$SCRIPT_167_SHA256" "$DECISIONS_SHA256" \
    "$ACCEPTED_V1_MANIFEST_SHA256" <<'PY'
import json
import pathlib
import sys

bundle = pathlib.Path(sys.argv[1]).resolve(strict=True)
receipt = json.loads((bundle / "promotion-receipt.json").read_text(encoding="utf-8"))
assert receipt["schema"] == "ishikawa.synthetic-corpus-v2-promotion-candidate.v1"
assert receipt["script_sha256"] == sys.argv[2]
assert receipt["decisions_sha256"] == sys.argv[3]
assert receipt["accepted_v1_manifest_sha256"] == sys.argv[4]
assert receipt["corpus_identity"] == "synthetic-corpus-v2"
assert receipt["document_count"] == 6
assert receipt["page_count"] == 26
assert receipt["atomic_candidate_count"] == 139
assert receipt["document_control_metadata_candidate_count"] == 6
assert receipt["status"] == "qualified_for_isolated_ingestion"
assert receipt["next_gate"] == "publish_to_isolated_synthetic_corpus_v2_database"
assert receipt["boundaries"] == {
    "corpus_v1_changed": False,
    "database_contact": False,
    "evaluation_truth_in_ingestion_path": False,
    "experimental_sibling_assemblies_included": False,
    "ingestion_performed": False,
    "optimization_gate_used": False,
    "optimization_profile_included": False,
    "retrieval_profile_changed": False,
}
expected = {
    "config/document_catalog.yaml",
    "config/document_classes.yaml",
    "config/ingestion_manifest.yaml",
    "evidence/atomic_chunks.json",
    "evidence/corpus_manifest.json",
    "evidence/evaluation-only/header_acceptance_truth.json",
    "evidence/normalized.json",
    "evidence/source_manifest.json",
    "promotion-receipt.json",
    "source/31_SCH_2003.pdf",
    "source/Form_TST9001.pdf",
    "source/Governance_Manual_2005_Revision_3.pdf",
    "source/OPS_17_CTL_2001.pdf",
    "source/OPS_17_CTL_2002_RevA.pdf",
    "source/SOP_42_IR_2006.pdf",
}
observed = {
    str(path.relative_to(bundle))
    for path in bundle.rglob("*")
    if path.is_file() and path.name != "SHA256SUMS"
}
assert observed == expected
assert not any(path.is_symlink() for path in bundle.rglob("*"))
print(receipt["created_utc"])
print(receipt["candidate_checksum_manifest_sha256"])
chunks = json.loads((bundle / "evidence/atomic_chunks.json").read_text(encoding="utf-8"))
print(chunks["method_profile_id"])
PY
} 2>/dev/null)" || {
  preflight_block 1 promotion_bundle_contract_failed
}
promotion_created_utc="$(sed -n '1p' <<<"$promotion_values")"
promotion_candidate_sha256="$(sed -n '2p' <<<"$promotion_values")"
promoted_method_profile_id="$(sed -n '3p' <<<"$promotion_values")"
[[ "$promotion_created_utc" =~ ^[0-9]{8}T[0-9]{6}Z$ \
  && "$promotion_candidate_sha256" =~ ^[0-9a-f]{64}$ \
  && "$promoted_method_profile_id" =~ ^[0-9a-f]{64}$ ]] || {
  preflight_block 1 promotion_identity_invalid
}

validation_output="$(bash "$SCRIPT_167" --validate-only 2>&1)" || {
  preflight_block 1 current_promotion_source_validation_failed
}
grep -Fxq 'script_167_synthetic_corpus_v2_promotion_qualification=pass' <<<"$validation_output" || {
  preflight_block 1 current_promotion_source_not_clean
}

preflight_root="$(mktemp -d /tmp/ishikawa-script-168-preflight.XXXXXX)"
preflight_chunks="$preflight_root/chunks.json"
promotion_normalized="$promotion_bundle/evidence/normalized.json"
promotion_chunks="$promotion_bundle/evidence/atomic_chunks.json"
promotion_normalized_sha256="$(sha256sum "$promotion_normalized" | sed 's/[[:space:]].*$//')"
if ! PYTHONDONTWRITEBYTECODE=1 python3 -B "$PIPELINE_CHUNK" \
    --input "$promotion_normalized" \
    --expected-input-sha256 "$promotion_normalized_sha256" \
    --output "$preflight_chunks" \
    --python-root "$PRODUCT_ROOT/application/python" \
    >"$preflight_root/chunking.stdout" 2>"$preflight_root/chunking.stderr"; then
  rm -rf -- "$preflight_root"
  preflight_block 1 production_chunking_preflight_failed
fi
preflight_chunks_sha256="$(sha256sum "$preflight_chunks" | sed 's/[[:space:]].*$//')"
promotion_chunks_sha256="$(sha256sum "$promotion_chunks" | sed 's/[[:space:]].*$//')"
manifest_fixture_root="$preflight_root/retained-artifact-fixture"
mkdir -m 0700 -- "$manifest_fixture_root"
for fixture_payload in artifact-one artifact-two artifact-three; do
  fixture_digest="$(printf '%s' "$fixture_payload" | sha256sum | sed 's/[[:space:]].*$//')"
  mkdir -p -- "$manifest_fixture_root/${fixture_digest:0:2}"
  printf '%s' "$fixture_payload" >"$manifest_fixture_root/${fixture_digest:0:2}/$fixture_digest"
done
manifest_fixture_staging="$preflight_root/retained-artifact-fixture.SHA256SUMS"
if ! build_retained_artifact_manifest \
    "$manifest_fixture_root" "$manifest_fixture_staging" 3 \
    || ! mv -- "$manifest_fixture_staging" "$manifest_fixture_root/SHA256SUMS" \
    || ! (cd -- "$manifest_fixture_root" && sha256sum --quiet -c SHA256SUMS) \
    || [[ "$(wc -l <"$manifest_fixture_root/SHA256SUMS" | tr -d '[:space:]')" != 3 ]] \
    || grep -Fq '  SHA256SUMS' "$manifest_fixture_root/SHA256SUMS"; then
  rm -rf -- "$preflight_root"
  preflight_block 1 retained_artifact_manifest_preflight_failed
fi
mkdir -p -- "$ARTIFACT_ROOT"
retained_copy_preflight_path="$(
  mktemp -d "$ARTIFACT_ROOT/.script-168-retained-copy-preflight.XXXXXX"
)" || {
  rm -rf -- "$preflight_root"
  preflight_block 1 retained_artifact_destination_preflight_creation_failed
}
retained_copy_preflight_final="${retained_copy_preflight_path}.final"
[[ ! -e "$retained_copy_preflight_final" \
  && ! -L "$retained_copy_preflight_final" ]] || {
  rm -rf -- "$retained_copy_preflight_path" "$preflight_root"
  preflight_block 1 retained_artifact_destination_preflight_collision
}
if ! copy_retained_artifact_set \
    "$manifest_fixture_root" "$retained_copy_preflight_path" \
    || ! mv -- "$retained_copy_preflight_path" "$retained_copy_preflight_final" \
    || ! (cd -- "$retained_copy_preflight_final" \
      && sha256sum --quiet -c SHA256SUMS); then
  rm -rf -- "$retained_copy_preflight_path" \
    "$retained_copy_preflight_final" "$preflight_root"
  preflight_block 1 retained_artifact_destination_copy_preflight_failed
fi
rm -rf -- "$retained_copy_preflight_final"
rm -rf -- "$preflight_root"
[[ "$preflight_chunks_sha256" == "$promotion_chunks_sha256" ]] || {
  preflight_block 1 production_chunking_preflight_identity_mismatch
}
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$PRODUCT_ROOT/application/python" "$promotion_chunks" <<'PY' || {
import json
import pathlib
import sys

sys.path.insert(0, sys.argv[1])
from ishikawa.chunking import METHOD_PROFILE_ID as chunk_method_profile_id
from ishikawa.document_producer import METHOD_PROFILE_ID as producer_method_profile_id

promoted = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
assert promoted["method_profile_id"] == chunk_method_profile_id
assert producer_method_profile_id == chunk_method_profile_id
PY
  preflight_block 1 production_method_profile_preflight_mismatch
}

bash -n "${BASH_SOURCE[0]}" "$SCRIPT_167"
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$INGESTION_RUNNER" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
compile(source, sys.argv[1], "exec")
PY
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | sed 's/[[:space:]].*$//')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_isolated_synthetic_corpus_v2_publication' \
    "script_sha256=$script_sha256;script_167_sha256=$SCRIPT_167_SHA256;decisions_sha256=$DECISIONS_SHA256" \
    "promotion_created_utc=$promotion_created_utc;promotion_candidate_checksum_manifest_sha256=$promotion_candidate_sha256" \
    'isolation=postgresql_cluster;cluster=16/ishikawa-v2;port=5433;start_policy=manual;database=rag_catalog' \
    'retained_artifact_destination_copy=pass;method=verified_byte_stream_copy' \
    'corpus_v1_changed=false;database_contact=false;model_contact=false;cluster_changed=false;retrieval_profile_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_168_isolated_synthetic_corpus_v2_publication=pass'
  exit 0
fi

report_path=''
work_root=''
receipt_path=''
receipt_checksum_path=''
retained_artifact_path=''
retained_artifact_staging_path=''
cluster_created=false
publication_accepted=false
failure_recorded=false
failure_reason=''
failure_exit_code=''
script_result=''
sudo_keepalive_pid=''
nomic_key=''
ingest_password=''
retrieval_password=''
v1_before=''

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}

block() {
  failure_recorded=true
  failure_reason="$1"
  exit 1
}

refresh_sudo_for_cleanup() {
  sudo -n true >/dev/null 2>&1 && return 0
  printf 'milestone=cleanup_privilege;state=awaiting_attended_sudo\n'
  sudo -v
}

cleanup() {
  local initial_status="$?"
  trap - EXIT HUP INT TERM
  set +e
  unset ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_INGEST_PASSWORD PGPASSWORD
  nomic_key=''
  ingest_password=''
  retrieval_password=''
  if [[ -n "$sudo_keepalive_pid" ]]; then
    kill "$sudo_keepalive_pid" >/dev/null 2>&1
    wait "$sudo_keepalive_pid" >/dev/null 2>&1
  fi
  if (( initial_status != 0 )) && [[ "$cluster_created" == true && "$publication_accepted" != true ]]; then
    if refresh_sudo_for_cleanup; then
      sudo -n pg_ctlcluster --skip-systemctl-redirect \
        "$POSTGRESQL_VERSION" "$V2_CLUSTER_NAME" stop >/dev/null 2>&1 || true
      sudo -n pg_dropcluster "$POSTGRESQL_VERSION" "$V2_CLUSTER_NAME" \
        >/dev/null 2>&1 || true
      if pg_lsclusters --no-header 2>/dev/null \
          | awk -v version="$POSTGRESQL_VERSION" -v name="$V2_CLUSTER_NAME" \
            '$1 == version && $2 == name {found=1} END {exit(found ? 0 : 1)}'; then
        emit 'milestone=failed_candidate_cleanup;state=blocked;isolated_cluster_removed=false'
      else
        emit 'milestone=failed_candidate_cleanup;state=pass;isolated_cluster_removed=true'
      fi
    else
      emit 'milestone=failed_candidate_cleanup;state=blocked;reason=sudo_unavailable'
    fi
  fi
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-168.* ]]; then
    rm -rf -- "$work_root"
  fi
  if (( initial_status != 0 )) \
      && [[ -n "$retained_artifact_path" \
        && "$retained_artifact_path" == "$ARTIFACT_ROOT"/retained-derived-artifacts-* ]]; then
    rm -rf -- "$retained_artifact_path"
  fi
  if (( initial_status != 0 )) \
      && [[ -n "$retained_artifact_staging_path" \
        && "$retained_artifact_staging_path" == "$ARTIFACT_ROOT"/.retained-derived-artifacts-* ]]; then
    rm -rf -- "$retained_artifact_staging_path"
  fi
  if (( initial_status != 0 )); then
    if [[ -n "$receipt_path" \
      && "$receipt_path" == "$ARTIFACT_ROOT"/isolated_synthetic_corpus_v2_publication_*.json ]]; then
      rm -f -- "$receipt_path"
    fi
    if [[ -n "$receipt_checksum_path" \
      && "$receipt_checksum_path" == "$ARTIFACT_ROOT"/isolated_synthetic_corpus_v2_publication_*.json.sha256 ]]; then
      rm -f -- "$receipt_checksum_path"
    fi
  fi
  if (( initial_status != 0 )); then
    script_result='blocked'
    if [[ "$failure_recorded" != true ]]; then
      failure_reason='unexpected_failure'
      failure_exit_code="$initial_status"
    fi
  else
    script_result="${script_result:-pass}"
  fi

  local report_sha256=''
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    {
      printf '\nSCRIPT RESULT\n'
      if [[ "$script_result" == blocked ]]; then
        printf 'reason=%s\n' "$failure_reason"
        if [[ -n "$failure_exit_code" ]]; then
          printf 'exit_code=%s\n' "$failure_exit_code"
        fi
      fi
      printf 'script_168_isolated_synthetic_corpus_v2_publication=%s\n' "$script_result"
    } >>"$report_path"
    report_sha256="$(sha256sum "$report_path" | sed 's/[[:space:]].*$//')"
  fi

  printf '\nSCRIPT RESULT\n'
  if [[ "$script_result" == blocked ]]; then
    printf 'reason=%s\n' "$failure_reason"
    if [[ -n "$failure_exit_code" ]]; then
      printf 'exit_code=%s\n' "$failure_exit_code"
    fi
  fi
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    printf 'report=%s\n' "$report_path"
    printf 'report_sha256=%s\n' "$report_sha256"
  fi
  printf 'script_168_isolated_synthetic_corpus_v2_publication=%s\n' "$script_result"
  exit "$initial_status"
}
trap cleanup EXIT HUP INT TERM

read_secret() {
  local prompt="$1" destination="$2" value
  IFS= read -r -s -p "$prompt: " value
  printf '\n'
  [[ -n "$value" && ${#value} -le 512 && "$value" != *$'\n'* && "$value" != *$'\r'* ]] \
    || block 'credential_input_invalid'
  printf -v "$destination" '%s' "$value"
}

read_confirmed_secret() {
  local label="$1" destination="$2" first second
  read_secret "New $label password" first
  read_secret "Confirm $label password" second
  [[ "$first" == "$second" ]] || block 'password_confirmation_mismatch'
  printf -v "$destination" '%s' "$first"
  first=''
  second=''
}

escape_sql_literal() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf '%s' "$value"
}

database_snapshot() {
  local port="$1"
  local snapshot_raw inventory identities identity_sha256
  snapshot_raw="$(sudo -n -u postgres psql -X -q -A -t -p "$port" \
      -d "$DATABASE_NAME" -v ON_ERROR_STOP=1 \
      -c "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
          SELECT concat_ws('|',
            (SELECT count(*) FROM rag_search.active_documents),
            (SELECT coalesce(sum(page_count), 0) FROM rag_search.active_documents),
            (SELECT count(*) FROM rag_search.active_chunks),
            (SELECT count(*) FROM rag_search.active_citations),
            (SELECT count(*) FROM rag_search.active_embeddings));
          SELECT coalesce(string_agg(identity, ';' ORDER BY identity), '')
          FROM (
            SELECT 'document:' || document_id || ':' || document_version_id || ':' ||
              artifact_set_id || ':' || source_digest || ':' || method_profile_id AS identity
            FROM rag_search.active_documents
            UNION ALL
            SELECT 'chunk:' || chunk_id || ':' || retrieval_text_digest || ':' ||
              method_profile_id AS identity
            FROM rag_search.active_chunks
            UNION ALL
            SELECT 'citation:' || citation_id || ':' || chunk_id || ':' ||
              page_start::text || ':' || page_end::text AS identity
            FROM rag_search.active_citations
            UNION ALL
            SELECT 'embedding:' || embedding_artifact_id || ':' || chunk_id || ':' ||
              embedding_space_id AS identity
            FROM rag_search.active_embeddings
            UNION ALL
            SELECT 'relationship:' || relationship_id || ':' || relationship_type || ':' ||
              source_identity || ':' || target_identity AS identity
            FROM rag_search.active_relationships
          ) AS active_identities;
          ROLLBACK;")" || return 1
  inventory="$(sed -n '1p' <<<"$snapshot_raw")"
  identities="$(sed -n '2p' <<<"$snapshot_raw")"
  [[ "$inventory" =~ ^[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+$ \
    && -n "$identities" ]] || return 1
  identity_sha256="$(printf '%s' "$identities" | sha256sum | sed 's/[[:space:]].*$//')"
  printf '%s|%s\n' "$inventory" "$identity_sha256"
}

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/isolated_synthetic_corpus_v2_publication_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-168.XXXXXX)"
mkdir -m 0700 -- \
  "$work_root/runtime-config" "$work_root/producer-work" \
  "$work_root/operator-reports" "$work_root/retained-artifacts"

emit 'purpose=publish_qualified_synthetic_corpus_v2_to_isolated_postgresql_cluster'
emit "started_utc=$timestamp;script_sha256=$script_sha256;script_167_sha256=$SCRIPT_167_SHA256"
emit "promotion_created_utc=$promotion_created_utc;promotion_candidate_checksum_manifest_sha256=$promotion_candidate_sha256"
emit 'authorized_actions=attended_sudo_create_manual_start_isolated_postgresql_cluster_create_isolated_roles_and_database_install_canonical_schema_call_forwarded_nomic_publish_qualified_synthetic_v2_verify_v1_unchanged_retain_content_free_evidence'
emit 'non_actions=no_corpus_v1_mutation_no_main_cluster_configuration_change_no_gemma_contact_no_black_corpus_access_no_retrieval_optimization_no_retrieval_profile_change_no_application_package_or_release_change_no_service_autostart'
emit 'operator_expectation=sudo_password_may_be_prompted;nomic_key_once;new_isolated_rag_ingest_password_twice;new_isolated_rag_retrieval_password_twice;estimated_duration_minutes=3-10'

actual_hostname="$(hostname -s)"
actual_architecture="$(uname -m)"
actual_os="$(. /etc/os-release && printf '%s|%s' "$ID" "$VERSION_ID")"
[[ "$actual_hostname" == "$expected_hostname" ]] || block 'hostname_mismatch'
[[ "$actual_os" == "ubuntu|$expected_os_version" ]] || block 'os_identity_mismatch'
[[ "$actual_architecture" == "$expected_architecture" ]] || block 'architecture_mismatch'
emit "milestone=local_host_identity;state=pass;hostname=$actual_hostname;os_id=ubuntu;os_version=$expected_os_version;architecture=$actual_architecture"

emit 'milestone=native_tests;state=start'
native_test_output="$work_root/native-tests.txt"
if ! PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" \
    >"$native_test_output" 2>&1; then
  emit "milestone=native_tests;state=blocked;diagnostic_sha256=$(sha256sum "$native_test_output" | sed 's/[[:space:]].*$//');raw_output_retained=false"
  block 'native_test_regression'
fi
grep -Fq "Ran $EXPECTED_NATIVE_TESTS tests" "$native_test_output" \
  || block 'native_test_count_mismatch'
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$native_test_output" \
  || block 'native_test_marker_absent'
emit "milestone=native_tests;state=pass;tests=$EXPECTED_NATIVE_TESTS;application_source_files=$EXPECTED_APPLICATION_SOURCE_FILES;application_source_tree_sha256=$APPLICATION_SOURCE_TREE_SHA256"

nomic_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 5 --max-time 10 "$NOMIC_HEALTH_URL" 2>/dev/null || true)"
[[ "$nomic_status" == 200 ]] || block 'nomic_forwarded_health_unavailable'
emit 'milestone=nomic_forwarded_health;state=pass;http_status=200;inference=false'

emit 'milestone=local_sudo;state=awaiting_attended_authorization'
sudo -v || block 'sudo_authorization_failed'
emit 'milestone=local_sudo;state=pass'
(
  while kill -0 "$$" 2>/dev/null; do
    sudo -n -v >/dev/null 2>&1 || exit 1
    sleep 30
  done
) &
sudo_keepalive_pid="$!"

pg_isready -q -h 127.0.0.1 -p "$V1_PORT" -d "$DATABASE_NAME" -t 10 \
  || block 'corpus_v1_database_unready'
v1_before="$(database_snapshot "$V1_PORT" 2>"$work_root/v1-before.stderr")" \
  || block 'corpus_v1_snapshot_failed'
[[ "$v1_before" =~ ^6\|27\|126\|126\|126\|[0-9a-f]{64}$ ]] \
  || block 'corpus_v1_inventory_unexpected'
emit "milestone=corpus_v1_prepublication_snapshot;state=pass;inventory=${v1_before%|*};identity_sha256=${v1_before##*|}"

if pg_lsclusters --no-header 2>/dev/null \
    | awk -v version="$POSTGRESQL_VERSION" -v name="$V2_CLUSTER_NAME" \
      '$1 == version && $2 == name {found=1} END {exit(found ? 0 : 1)}'; then
  block 'isolated_cluster_already_exists_requires_review'
fi
if pg_lsclusters --no-header 2>/dev/null \
    | awk -v port="$V2_PORT" '$3 == port {found=1} END {exit(found ? 0 : 1)}'; then
  block 'isolated_cluster_port_already_assigned'
fi

sudo -n pg_createcluster \
  --port="$V2_PORT" --start-conf=manual "$POSTGRESQL_VERSION" "$V2_CLUSTER_NAME" \
  >"$work_root/cluster-create.stdout" 2>"$work_root/cluster-create.stderr" \
  || block 'isolated_cluster_creation_failed'
cluster_created=true
cluster_line="$(pg_lsclusters --no-header \
  | awk -v version="$POSTGRESQL_VERSION" -v name="$V2_CLUSTER_NAME" \
    '$1 == version && $2 == name {print; found=1} END {if (!found) exit 1}')" \
  || block 'isolated_cluster_identity_missing'
read -r observed_version observed_name observed_port observed_status _ <<<"$cluster_line"
[[ "$observed_version|$observed_name|$observed_port|$observed_status" \
  == "$POSTGRESQL_VERSION|$V2_CLUSTER_NAME|$V2_PORT|down" ]] \
  || block 'isolated_cluster_initial_state_invalid'
cluster_start_policy="$(
  sudo -n awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    { print $1; exit }
  ' "/etc/postgresql/$POSTGRESQL_VERSION/$V2_CLUSTER_NAME/start.conf"
)" || block 'isolated_cluster_start_policy_read_failed'
[[ "$cluster_start_policy" == manual ]] \
  || block 'isolated_cluster_start_policy_invalid'

sudo -n pg_ctlcluster --skip-systemctl-redirect \
  "$POSTGRESQL_VERSION" "$V2_CLUSTER_NAME" start \
  >"$work_root/cluster-start.stdout" 2>"$work_root/cluster-start.stderr" \
  || block 'isolated_cluster_start_failed'
pg_isready -q -h 127.0.0.1 -p "$V2_PORT" -d postgres -t 10 \
  || block 'isolated_cluster_unready'
emit "milestone=isolated_postgresql_cluster;state=pass;cluster=$POSTGRESQL_VERSION/$V2_CLUSTER_NAME;port=$V2_PORT;start_policy=manual;current_status=online"

read_secret 'Nomic API key' nomic_key
read_confirmed_secret "$INGEST_ROLE" ingest_password
read_confirmed_secret "$RETRIEVAL_ROLE" retrieval_password
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
export ISHIKAWA_POSTGRESQL_INGEST_PASSWORD="$ingest_password"
emit 'milestone=runtime_credentials;state=accepted;credential_values_retained=false'

ingest_password_sql="$(escape_sql_literal "$ingest_password")"
retrieval_password_sql="$(escape_sql_literal "$retrieval_password")"
{
  printf '%s\n' \
    'SET standard_conforming_strings = on;' \
    'BEGIN;' \
    "CREATE ROLE $OWNER_ROLE NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;" \
    "CREATE ROLE $INGEST_ROLE LOGIN PASSWORD '$ingest_password_sql' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;" \
    "CREATE ROLE $RETRIEVAL_ROLE LOGIN PASSWORD '$retrieval_password_sql' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;" \
    'COMMIT;'
} | sudo -n -u postgres psql -X -q -p "$V2_PORT" \
  -v ON_ERROR_STOP=1 -d postgres \
  >"$work_root/role-create.stdout" 2>"$work_root/role-create.stderr" \
  || block 'isolated_application_role_creation_failed'
ingest_password_sql=''
retrieval_password_sql=''

printf 'CREATE DATABASE %s WITH OWNER %s ENCODING '\''UTF8'\'' TEMPLATE template0;\n' \
  "$DATABASE_NAME" "$OWNER_ROLE" \
  | sudo -n -u postgres psql -X -q -p "$V2_PORT" \
      -v ON_ERROR_STOP=1 -d postgres \
      >"$work_root/database-create.stdout" 2>"$work_root/database-create.stderr" \
  || block 'isolated_application_database_creation_failed'

printf '%s\n' \
  "REVOKE ALL ON DATABASE $DATABASE_NAME FROM PUBLIC;" \
  "GRANT CONNECT ON DATABASE $DATABASE_NAME TO $INGEST_ROLE, $RETRIEVAL_ROLE;" \
  "ALTER ROLE $RETRIEVAL_ROLE IN DATABASE $DATABASE_NAME SET default_transaction_read_only = on;" \
  | sudo -n -u postgres psql -X -q -p "$V2_PORT" \
      -v ON_ERROR_STOP=1 -d postgres \
      >"$work_root/database-access.stdout" 2>"$work_root/database-access.stderr" \
  || block 'isolated_database_access_configuration_failed'

printf '%s\n' 'CREATE EXTENSION vector;' \
  'REVOKE CREATE ON SCHEMA public FROM PUBLIC;' \
  | sudo -n -u postgres psql -X -q -p "$V2_PORT" \
      -v ON_ERROR_STOP=1 -d "$DATABASE_NAME" \
      >"$work_root/extensions-create.stdout" 2>"$work_root/extensions-create.stderr" \
  || block 'isolated_database_extension_creation_failed'

sudo -n -u postgres psql -X -q -p "$V2_PORT" \
  -v ON_ERROR_STOP=1 \
  -v "owner_role=$OWNER_ROLE" \
  -v "ingest_role=$INGEST_ROLE" \
  -v "retrieval_role=$RETRIEVAL_ROLE" \
  -v "schema_sha256=$SCHEMA_SHA256" \
  -d "$DATABASE_NAME" <"$SCHEMA_PATH" \
  >"$work_root/schema-install.stdout" 2>"$work_root/schema-install.stderr" \
  || block 'isolated_final_schema_installation_failed'
emit "milestone=isolated_database_schema;state=pass;database=$DATABASE_NAME;schema_version=4;schema_sha256=$SCHEMA_SHA256"

sed "s/port: 5432$/port: $V2_PORT/" "$DEPLOYMENT_TEMPLATE" \
  >"$work_root/runtime-config/deployment.yaml"
cp -- "$INGESTION_TEMPLATE" "$work_root/runtime-config/ingestion_dependencies.yaml"
grep -Fxq "  port: $V2_PORT" "$work_root/runtime-config/deployment.yaml" \
  || block 'isolated_runtime_port_configuration_failed'

runner_arguments=(
  --product-root "$PRODUCT_ROOT"
  --promotion-bundle "$promotion_bundle"
  --runtime-config-root "$work_root/runtime-config"
  --work-root "$work_root/producer-work"
  --report-root "$work_root/operator-reports"
  --artifact-root "$work_root/retained-artifacts"
  --pipeline-executable "$PIPELINE_EXECUTABLE"
)

emit 'milestone=isolated_ingestion_validation;state=start'
validate_output="$work_root/ingestion-validate.stdout"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$INGESTION_RUNNER" \
  --mode validate-only "${runner_arguments[@]}" \
  >"$validate_output" 2>"$work_root/ingestion-validate.stderr" \
  || block 'isolated_ingestion_validation_failed'
grep -Fxq 'outcome=PASS' "$validate_output" \
  || block 'isolated_ingestion_validation_outcome_invalid'
grep -Fxq 'actions=add:6,reprocess:0,retire:0,reuse:0,revise:0' "$validate_output" \
  || block 'isolated_ingestion_validation_plan_invalid'
grep -Fxq 'ishikawa_ingestion=pass;exit_code=0' "$validate_output" \
  || block 'isolated_ingestion_validation_marker_absent'
emit 'milestone=isolated_ingestion_validation;state=pass;documents=6;actions=add:6'

emit 'milestone=isolated_ingestion_publication;state=start'
publish_output="$work_root/ingestion-publish.stdout"
if PYTHONDONTWRITEBYTECODE=1 python3 -B "$INGESTION_RUNNER" \
    --mode publish "${runner_arguments[@]}" \
    >"$publish_output" 2>"$work_root/ingestion-publish.stderr"; then
  publish_exit_code=0
else
  publish_exit_code=$?
fi
if (( publish_exit_code != 0 )); then
  publish_failure_reason="$(sed -nE \
    's/^ishikawa_ingestion=blocked;reason=([a-z][a-z0-9_]{0,255})$/\1/p' \
    "$publish_output" | tail -n 1)"
  [[ -n "$publish_failure_reason" ]] || publish_failure_reason='unclassified_review_required'
  emit "milestone=isolated_ingestion_publication;state=blocked;exit_code=$publish_exit_code;failure_reason=$publish_failure_reason;stdout_sha256=$(sha256sum "$publish_output" | sed 's/[[:space:]].*$//');stderr_sha256=$(sha256sum "$work_root/ingestion-publish.stderr" | sed 's/[[:space:]].*$//');raw_output_retained=false"
  block "isolated_ingestion_publication_$publish_failure_reason"
fi
grep -Fxq 'outcome=PASS' "$publish_output" \
  || block 'isolated_ingestion_publication_outcome_invalid'
grep -Fxq 'actions=add:6,reprocess:0,retire:0,reuse:0,revise:0' "$publish_output" \
  || block 'isolated_ingestion_publication_plan_invalid'
grep -Fxq 'mutation_performed=true' "$publish_output" \
  || block 'isolated_ingestion_publication_not_committed'
grep -Fxq 'ishikawa_ingestion=pass;exit_code=0' "$publish_output" \
  || block 'isolated_ingestion_publication_marker_absent'
emit 'milestone=isolated_ingestion_publication;state=pass;documents=6;actions=add:6'

v2_inventory="$(sudo -n -u postgres psql -X -q -A -t -p "$V2_PORT" \
  -d "$DATABASE_NAME" -v ON_ERROR_STOP=1 \
  -c "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
      SELECT concat_ws('|',
        (SELECT count(*) FROM rag_search.active_documents),
        (SELECT coalesce(sum(page_count), 0) FROM rag_search.active_documents),
        (SELECT count(*) FROM rag_search.active_chunks),
        (SELECT count(*) FROM rag_search.active_citations),
        (SELECT count(*) FROM rag_search.active_embeddings),
        (SELECT count(*) FROM rag_search.active_chunks WHERE projection_kind = 'document_control_metadata'),
        (SELECT count(*) FROM rag_search.active_chunks WHERE retrieval_filters ? 'document_control'),
        (SELECT count(DISTINCT retrieval_filters #>> '{document_control,department_normalized}') FROM rag_search.active_chunks));
      ROLLBACK;" 2>"$work_root/v2-inventory.stderr")" \
  || block 'isolated_published_inventory_query_failed'
[[ "$v2_inventory" == '6|26|139|139|139|6|139|4' ]] \
  || block 'isolated_published_inventory_mismatch'

v2_identities="$(sudo -n -u postgres psql -X -q -A -t -p "$V2_PORT" \
  -d "$DATABASE_NAME" -v ON_ERROR_STOP=1 \
  -c "SELECT string_agg(document_key || '|' || source_digest, ';' ORDER BY document_key) FROM rag_search.active_documents;" \
  2>"$work_root/v2-identities.stderr")" \
  || block 'isolated_published_identity_query_failed'
[[ "$v2_identities" == "$EXPECTED_V2_IDENTITIES" ]] \
  || block 'isolated_published_identity_mismatch'

retained_artifact_values="$({
  PYTHONDONTWRITEBYTECODE=1 python3 -B - \
    "$work_root/retained-artifacts" "$promoted_method_profile_id" \
    "$EXPECTED_V2_IDENTITIES" <<'PY'
import hashlib
import json
import math
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]).resolve(strict=True)
method_profile_id = sys.argv[2]
expected_identities = dict(
    item.split("|", 1) for item in sys.argv[3].split(";")
)
sha256_pattern = re.compile(r"[0-9a-f]{64}")

objects = sorted(path for path in root.glob("*/*") if path.is_file())
assert len(objects) == 3
assert not any(path.is_symlink() for path in root.rglob("*"))
by_digest = {}
for path in objects:
    relative = path.relative_to(root)
    assert len(relative.parts) == 2
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert path.name == digest
    assert relative.parts[0] == digest[:2]
    assert digest not in by_digest
    by_digest[digest] = path

payloads = {
    digest: json.loads(path.read_text(encoding="utf-8"))
    for digest, path in by_digest.items()
}
normalized_matches = [
    (digest, value)
    for digest, value in payloads.items()
    if "normalization_set_digest" in value and "artifact_kind" not in value
]
chunk_matches = [
    (digest, value)
    for digest, value in payloads.items()
    if value.get("artifact_kind") == "non_publishable_structural_chunk_candidates"
]
embedding_matches = [
    (digest, value)
    for digest, value in payloads.items()
    if value.get("artifact_kind") == "measured_nomic_chunk_embeddings"
]
assert len(normalized_matches) == len(chunk_matches) == len(embedding_matches) == 1
normalized_sha256, normalized = normalized_matches[0]
chunk_sha256, chunks = chunk_matches[0]
embedding_sha256, embeddings = embedding_matches[0]

normalized_sources = {
    document["doc_id"]: document["source_sha256"]
    for document in normalized["documents"]
}
chunk_sources = {
    document["document_ref"]: document["source_sha256"]
    for document in chunks["documents"]
}
assert normalized_sources == expected_identities
assert chunk_sources == expected_identities
assert len(normalized["documents"]) == 6
assert sum(document["page_count"] for document in normalized["documents"]) == 26
assert normalized["normalization_set_digest"] == chunks["normalization_set_digest"]
assert chunks["method_profile_id"] == method_profile_id
assert chunks["artifact_kind"] == "non_publishable_structural_chunk_candidates"
assert embeddings["artifact_kind"] == "measured_nomic_chunk_embeddings"
assert embeddings["source_chunk_candidate_sha256"] == chunk_sha256
assert embeddings["source_chunk_candidate_set_digest"] == chunks["chunk_candidate_set_digest"]
assert embeddings["source_method_profile_id"] == method_profile_id
assert embeddings["publication_eligible"] is False
assert embeddings["publication_blocker"] == "retrieval_profile_calibration_pending"

chunk_ids = {
    candidate["chunk_id"]
    for document in chunks["documents"]
    for candidate in document["candidates"]
}
metadata_candidates = [
    candidate
    for document in chunks["documents"]
    for candidate in document["candidates"]
    if candidate["projection_kind"] == "document_control_metadata"
]
assert len(metadata_candidates) == 6
assert all(
    candidate["citation_anchor"]["page_start"] == 1
    and "document_control" in candidate["retrieval_filters"]
    for candidate in metadata_candidates
)
assert all(
    "document_control" in candidate["retrieval_filters"]
    for document in chunks["documents"]
    for candidate in document["candidates"]
)
records = embeddings["records"]
assert len(chunk_ids) == 139
assert len(records) == 139
assert {record["chunk_id"] for record in records} == chunk_ids
embedding_space_id = embeddings["embedding_space_id"]
assert sha256_pattern.fullmatch(embedding_space_id)
assert sha256_pattern.fullmatch(embeddings["embedding_set_digest"])
assert embeddings["embedding_space"]["dimension"] == 768
for record in records:
    assert record["embedding_space_id"] == embedding_space_id
    assert record["vector_dimension"] == 768
    assert len(record["vector"]) == 768
    assert all(isinstance(value, (int, float)) and math.isfinite(value) for value in record["vector"])
    accounting = record["token_accounting"]
    assert accounting["count_mode"] == "with_special_tokens"
    assert 0 < accounting["total_embedding_input_tokens"] <= 2048

print(normalized_sha256)
print(chunk_sha256)
print(embedding_sha256)
print(embedding_space_id)
print(embeddings["embedding_set_digest"])
PY
} 2>/dev/null)" || block 'retained_artifact_semantic_validation_failed'
normalized_artifact_sha256="$(sed -n '1p' <<<"$retained_artifact_values")"
chunk_artifact_sha256="$(sed -n '2p' <<<"$retained_artifact_values")"
embedding_artifact_sha256="$(sed -n '3p' <<<"$retained_artifact_values")"
embedding_space_id="$(sed -n '4p' <<<"$retained_artifact_values")"
embedding_set_digest="$(sed -n '5p' <<<"$retained_artifact_values")"
[[ "$normalized_artifact_sha256" =~ ^[0-9a-f]{64}$ \
  && "$chunk_artifact_sha256" =~ ^[0-9a-f]{64}$ \
  && "$embedding_artifact_sha256" =~ ^[0-9a-f]{64}$ \
  && "$embedding_space_id" =~ ^[0-9a-f]{64}$ \
  && "$embedding_set_digest" =~ ^[0-9a-f]{64}$ ]] \
  || block 'retained_artifact_semantic_identity_invalid'
emit "milestone=retained_artifact_semantics;state=pass;artifacts=3;documents=6;pages=26;chunks=139;metadata_candidates=6;normalized_sha256=$normalized_artifact_sha256;chunks_sha256=$chunk_artifact_sha256;embeddings_sha256=$embedding_artifact_sha256;embedding_space_id=$embedding_space_id"

v2_integrity="$(sudo -n -u postgres psql -X -q -A -t -p "$V2_PORT" \
  -d "$DATABASE_NAME" -v ON_ERROR_STOP=1 \
  -c "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
      SELECT concat_ws('|',
        (SELECT count(*) FROM rag.schema_migrations
          WHERE migration_id = 'ishikawa_consolidated_schema_v4'
            AND schema_version = 4
            AND migration_sha256 = '$SCHEMA_SHA256'),
        (SELECT count(*) FROM rag.ingestion_runs WHERE state = 'succeeded'),
        (SELECT count(*) FROM rag.publication_batches WHERE state = 'published'),
        (SELECT count(*) FROM rag.publication_batch_changes WHERE change_kind = 'add'),
        (SELECT count(*) FROM rag.active_document_versions),
        (SELECT count(*) FROM rag.document_artifact_sets WHERE state = 'validated'),
        (SELECT count(*) FROM rag.embedding_spaces
          WHERE status = 'active' AND embedding_space_id = '$embedding_space_id'
            AND dimension = 768 AND maximum_input_tokens = 2048
            AND vector_transform = 'none' AND distance_metric = 'cosine'),
        (SELECT count(*) FROM rag_private.artifact_manifests),
        (SELECT count(*) FROM rag_private.quarantine_records WHERE resolved_at IS NULL),
        (SELECT count(*) FROM rag_search.active_documents
          WHERE method_profile_id <> '$promoted_method_profile_id'),
        (SELECT count(*) FROM rag_search.active_chunks
          WHERE method_profile_id <> '$promoted_method_profile_id'),
        (SELECT count(*) FROM rag_search.active_embeddings
          WHERE embedding_space_id <> '$embedding_space_id'),
        (SELECT count(*) FROM rag_search.active_chunks ac
          LEFT JOIN (
            SELECT chunk_id, count(*) AS count
            FROM rag_search.active_citations GROUP BY chunk_id
          ) citations USING (chunk_id)
          WHERE coalesce(citations.count, 0) <> 1),
        (SELECT count(*) FROM rag_search.active_chunks ac
          LEFT JOIN (
            SELECT chunk_id, count(*) AS count
            FROM rag_search.active_embeddings GROUP BY chunk_id
          ) embeddings USING (chunk_id)
          WHERE coalesce(embeddings.count, 0) <> 1),
        (SELECT count(*) FROM rag_search.active_citations citation
          JOIN rag_search.active_documents document
            ON document.document_id = citation.document_id
          WHERE citation.page_start < 1
            OR citation.page_end < citation.page_start
            OR citation.page_end > document.page_count),
        (SELECT count(*) FROM (
          SELECT document.document_id
          FROM rag_search.active_documents document
          LEFT JOIN rag_search.active_chunks chunk
            ON chunk.document_id = document.document_id
              AND chunk.projection_kind = 'document_control_metadata'
          GROUP BY document.document_id
          HAVING count(chunk.chunk_id) <> 1
        ) invalid_metadata_inventory),
        (SELECT count(*) FROM rag_search.active_chunks
          WHERE NOT (retrieval_filters ? 'document_control')
            OR nullif(retrieval_filters #>> '{document_control,department_normalized}', '') IS NULL));
      ROLLBACK;" 2>"$work_root/v2-integrity.stderr")" \
  || block 'isolated_database_integrity_query_failed'
[[ "$v2_integrity" == '1|1|1|6|6|6|1|0|0|0|0|0|0|0|0|0|0' ]] \
  || block 'isolated_database_integrity_mismatch'

role_posture="$(sudo -n -u postgres psql -X -q -A -t -p "$V2_PORT" \
  -d postgres -v ON_ERROR_STOP=1 \
  -c "SELECT rolname || '|' || concat_ws('|', rolcanlogin, rolsuper,
        rolcreatedb, rolcreaterole, rolinherit, rolreplication, rolbypassrls)
      FROM pg_roles
      WHERE rolname IN ('$OWNER_ROLE', '$INGEST_ROLE', '$RETRIEVAL_ROLE')
      ORDER BY rolname;" 2>"$work_root/role-posture.stderr")" \
  || block 'isolated_role_posture_query_failed'
[[ "$role_posture" == $'rag_ingest|t|f|f|f|t|f|f\nrag_owner|f|f|f|f|f|f|f\nrag_retrieval|t|f|f|f|t|f|f' ]] \
  || block 'isolated_role_posture_mismatch'

retrieval_posture=''
if ! retrieval_posture="$(PGPASSWORD="$retrieval_password" psql -X -q -A -t \
    -h 127.0.0.1 -p "$V2_PORT" -U "$RETRIEVAL_ROLE" \
    -d "$DATABASE_NAME" -v ON_ERROR_STOP=1 \
    -c "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
        SELECT concat_ws('|', current_user,
          current_setting('default_transaction_read_only'),
          current_setting('transaction_read_only'),
          (SELECT count(*) FROM rag_search.active_documents),
          (SELECT count(*) FROM rag_search.active_chunks),
          (SELECT count(*) FROM rag_search.active_citations),
          (SELECT count(*) FROM rag_search.active_embeddings));
        ROLLBACK;" 2>"$work_root/retrieval-posture.stderr")"; then
  if grep -Fqi 'password authentication failed' "$work_root/retrieval-posture.stderr"; then
    retrieval_connection_reason='authentication_failed'
  elif grep -Eqi 'connection refused|could not connect|no pg_hba.conf entry' \
      "$work_root/retrieval-posture.stderr"; then
    retrieval_connection_reason='transport_rejected'
  elif grep -Fqi 'permission denied' "$work_root/retrieval-posture.stderr"; then
    retrieval_connection_reason='view_permission_denied'
  else
    retrieval_connection_reason='query_failed'
  fi
  emit "milestone=isolated_retrieval_role_connection;state=blocked;reason=$retrieval_connection_reason;diagnostic_sha256=$(sha256sum "$work_root/retrieval-posture.stderr" | sed 's/[[:space:]].*$//');raw_output_retained=false"
  block "isolated_retrieval_role_$retrieval_connection_reason"
fi
[[ "$retrieval_posture" == 'rag_retrieval|on|on|6|139|139|139' ]] \
  || block 'isolated_retrieval_role_posture_mismatch'

retrieval_privileges="$(sudo -n -u postgres psql -X -q -A -t -p "$V2_PORT" \
  -d "$DATABASE_NAME" -v ON_ERROR_STOP=1 \
  -c "SELECT concat_ws('|',
        has_database_privilege('$RETRIEVAL_ROLE', current_database(), 'CONNECT'),
        has_database_privilege('$RETRIEVAL_ROLE', current_database(), 'TEMPORARY'),
        has_schema_privilege('$RETRIEVAL_ROLE', 'rag_search', 'USAGE'),
        has_table_privilege('$RETRIEVAL_ROLE', 'rag_search.active_documents', 'SELECT'),
        has_table_privilege('$RETRIEVAL_ROLE', 'rag_search.active_chunks', 'SELECT'),
        has_table_privilege('$RETRIEVAL_ROLE', 'rag_search.active_citations', 'SELECT'),
        has_table_privilege('$RETRIEVAL_ROLE', 'rag_search.active_embeddings', 'SELECT'),
        has_schema_privilege('$RETRIEVAL_ROLE', 'rag', 'USAGE'),
        has_table_privilege('$RETRIEVAL_ROLE', 'rag.chunks', 'SELECT'),
        has_table_privilege('$RETRIEVAL_ROLE', 'rag.chunks', 'INSERT'),
        has_schema_privilege('$RETRIEVAL_ROLE', 'rag_private', 'USAGE'));" \
  2>"$work_root/retrieval-privileges.stderr")" \
  || block 'isolated_retrieval_privilege_audit_failed'
[[ "$retrieval_privileges" == 't|f|t|t|t|t|t|f|f|f|f' ]] \
  || block 'isolated_retrieval_privilege_posture_mismatch'

cluster_runtime_posture="$(sudo -n -u postgres psql -X -q -A -t -p "$V2_PORT" \
  -d "$DATABASE_NAME" -v ON_ERROR_STOP=1 \
  -c "SELECT current_setting('port') || '|' || current_setting('listen_addresses');" \
  2>"$work_root/cluster-runtime-posture.stderr")" \
  || block 'isolated_cluster_runtime_posture_query_failed'
[[ "$cluster_runtime_posture" == "$V2_PORT|localhost" ]] \
  || block 'isolated_cluster_runtime_posture_mismatch'
cluster_start_policy="$({
  sudo -n awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    { print $1; exit }
  ' "/etc/postgresql/$POSTGRESQL_VERSION/$V2_CLUSTER_NAME/start.conf"
} 2>/dev/null)" || block 'isolated_cluster_start_policy_recheck_failed'
[[ "$cluster_start_policy" == manual ]] \
  || block 'isolated_cluster_start_policy_changed'
emit 'milestone=isolated_database_integrity;state=pass;schema_migrations=1;successful_runs=1;published_batches=1;publication_adds=6;active_versions=6;validated_artifact_sets=6;active_embedding_spaces=1;database_artifact_manifests=0;retained_artifacts=3;unresolved_quarantines=0;chunk_citation_coverage=complete;chunk_embedding_coverage=complete'
emit 'milestone=isolated_security_posture;state=pass;owner_login=false;retrieval_default_read_only=true;retrieval_raw_table_access=false;retrieval_temporary=false;listener=localhost;start_policy=manual'
emit 'milestone=isolated_retrieval_projection;state=pass;documents=6;pages=26;chunks=139;citations=139;embeddings=139;metadata_candidates=6;header_filtered_candidates=139;departments=4'

v1_after="$(database_snapshot "$V1_PORT" 2>"$work_root/v1-after.stderr")" \
  || block 'corpus_v1_postpublication_snapshot_failed'
[[ "$v1_after" == "$v1_before" ]] || block 'corpus_v1_changed'
check_file "$ACCEPTED_V1_MANIFEST" "$ACCEPTED_V1_MANIFEST_SHA256" accepted_v1_manifest
emit "milestone=corpus_v1_postpublication_snapshot;state=pass;unchanged=true;inventory=${v1_after%|*};identity_sha256=${v1_after##*|}"

retained_artifact_manifest_staging="$work_root/retained-artifacts.SHA256SUMS"
build_retained_artifact_manifest \
  "$work_root/retained-artifacts" "$retained_artifact_manifest_staging" 3 \
  || block 'retained_artifact_checksum_generation_failed'
mv -- "$retained_artifact_manifest_staging" \
  "$work_root/retained-artifacts/SHA256SUMS" \
  || block 'retained_artifact_checksum_installation_failed'
(cd -- "$work_root/retained-artifacts" && sha256sum --quiet -c SHA256SUMS) \
  || block 'retained_artifact_checksum_verification_failed'
retained_artifact_checksum_sha256="$(sha256sum "$work_root/retained-artifacts/SHA256SUMS" | sed 's/[[:space:]].*$//')"

receipt_path="$ARTIFACT_ROOT/isolated_synthetic_corpus_v2_publication_${timestamp}.json"
receipt_checksum_path="$receipt_path.sha256"
[[ ! -e "$receipt_path" && ! -L "$receipt_path" \
  && ! -e "$receipt_checksum_path" && ! -L "$receipt_checksum_path" ]] \
  || block 'publication_receipt_path_exists'
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$receipt_path" "$timestamp" "$script_sha256" "$promotion_created_utc" \
  "$promotion_candidate_sha256" "$v1_before" \
  "$retained_artifact_checksum_sha256" "$normalized_artifact_sha256" \
  "$chunk_artifact_sha256" "$embedding_artifact_sha256" \
  "$embedding_space_id" "$embedding_set_digest" "$promoted_method_profile_id" \
  "$APPLICATION_SOURCE_TREE_SHA256" "$TEST_RUNNER_SHA256" <<'PY'
import json
import pathlib
import sys

output = pathlib.Path(sys.argv[1])
v1_parts = sys.argv[6].split("|")
receipt = {
    "schema": "ishikawa.synthetic-corpus-v2-isolated-publication.v1",
    "created_utc": sys.argv[2],
    "script_sha256": sys.argv[3],
    "application_source_tree_sha256": sys.argv[14],
    "native_test_runner_sha256": sys.argv[15],
    "native_tests": 408,
    "promotion_created_utc": sys.argv[4],
    "promotion_candidate_checksum_manifest_sha256": sys.argv[5],
    "postgresql": {
        "version": 16,
        "cluster": "ishikawa-v2",
        "port": 5433,
        "start_policy": "manual",
        "database": "rag_catalog",
    },
    "published": {
        "corpus_identity": "synthetic-corpus-v2",
        "documents": 6,
        "pages": 26,
        "chunks": 139,
        "citations": 139,
        "embeddings": 139,
        "document_control_metadata_candidates": 6,
        "departments": 4,
        "retained_derived_artifacts": 3,
        "retained_artifact_checksum_manifest_sha256": sys.argv[7],
        "normalized_artifact_sha256": sys.argv[8],
        "chunk_artifact_sha256": sys.argv[9],
        "embedding_artifact_sha256": sys.argv[10],
        "embedding_space_id": sys.argv[11],
        "embedding_set_digest": sys.argv[12],
        "method_profile_id": sys.argv[13],
    },
    "corpus_v1": {
        "documents": int(v1_parts[0]),
        "pages": int(v1_parts[1]),
        "chunks": int(v1_parts[2]),
        "citations": int(v1_parts[3]),
        "embeddings": int(v1_parts[4]),
        "identity_sha256": v1_parts[5],
        "unchanged": True,
    },
    "boundaries": {
        "black_corpus_access": False,
        "gemma_contact": False,
        "optimization_gate_used": False,
        "retrieval_profile_changed": False,
        "service_autostart_enabled": False,
    },
    "status": "published_isolated",
    "next_gate": "qualify_isolated_synthetic_corpus_v2_retrieval",
}
output.write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n", encoding="utf-8")
PY
(cd -- "$ARTIFACT_ROOT" && sha256sum "$(basename -- "$receipt_path")" \
  >"$(basename -- "$receipt_checksum_path")")
(cd -- "$ARTIFACT_ROOT" && sha256sum --quiet -c "$(basename -- "$receipt_checksum_path")") \
  || block 'publication_receipt_checksum_failed'
retained_artifact_path="$ARTIFACT_ROOT/retained-derived-artifacts-$timestamp"
[[ ! -e "$retained_artifact_path" && ! -L "$retained_artifact_path" ]] \
  || block 'retained_artifact_path_exists'
retained_artifact_staging_path="$(
  mktemp -d "$ARTIFACT_ROOT/.retained-derived-artifacts-${timestamp}.XXXXXX"
)" || block 'retained_artifact_destination_staging_failed'
copy_retained_artifact_set \
  "$work_root/retained-artifacts" "$retained_artifact_staging_path" \
  || block 'retained_artifact_promotion_failed'
(cd -- "$retained_artifact_staging_path" && sha256sum --quiet -c SHA256SUMS) \
  || block 'promoted_artifact_checksum_verification_failed'
[[ "$(sha256sum "$retained_artifact_staging_path/SHA256SUMS" | sed 's/[[:space:]].*$//')" \
  == "$retained_artifact_checksum_sha256" ]] \
  || block 'promoted_artifact_manifest_identity_mismatch'
[[ "$(find "$retained_artifact_staging_path" -type f | wc -l | tr -d '[:space:]')" == 4 \
  && -z "$(find "$retained_artifact_staging_path" -type l -print -quit)" ]] \
  || block 'promoted_artifact_inventory_invalid'
mv -- "$retained_artifact_staging_path" "$retained_artifact_path" \
  || block 'retained_artifact_finalization_failed'
retained_artifact_staging_path=''
publication_accepted=true

emit "publication_receipt=$receipt_path;publication_receipt_sha256=$(sha256sum "$receipt_path" | sed 's/[[:space:]].*$//')"
emit "retained_artifacts=$retained_artifact_path;retained_artifact_checksum_manifest_sha256=$retained_artifact_checksum_sha256"
emit 'isolated_publication=pass;corpus=synthetic-corpus-v2;cluster=16/ishikawa-v2;port=5433;database=rag_catalog;start_policy=manual'
emit 'corpus_v1_changed=false;optimization_gate_used=false;retrieval_profile_changed=false;gemma_contact=false;black_corpus_access=false'
emit 'next_gate=qualify_isolated_synthetic_corpus_v2_retrieval_before_optimization_return'
script_result='pass'

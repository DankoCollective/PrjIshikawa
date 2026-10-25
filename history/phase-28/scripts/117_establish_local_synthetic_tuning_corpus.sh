#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Establish the six-document synthetic Ishikawa corpus in local PostgreSQL
#   for v1.1 retrieval tuning from the current working source.
#
# Mental model:
#   Bind the proven-empty local baseline and checksum-bound synthetic inputs,
#   create the three application roles and rag_catalog database, install the
#   canonical final schema directly, validate and publish through the real
#   source ingestion path, and verify the read-only retrieval projection.
#
# Inputs or prerequisites:
#   Clean Script 116 evidence, operator-forwarded Nomic on 127.0.0.1:8001,
#   attended sudo, package-network access when the reviewed local native
#   closure is absent, one Nomic key, and new application-role passwords.
#
# Outputs or artifact lane:
#   Exact native dependencies, persistent local roles, final schema, searchable
#   synthetic corpus, retained content-addressed derived artifacts, and a
#   content-free report. A failed run drops objects it created and restores the
#   proven-empty database state; an accepted package upgrade remains installed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/117_establish_local_synthetic_tuning_corpus.sh --run

usage() {
  sed -n '3,28p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                    Establish and verify the local tuning corpus.' \
    '  --validate-only          Validate source and bound inputs without mutation.' \
    '  --expected-hostname NAME Exact expected local short hostname.' \
    '  --expected-os-version V  Exact expected Ubuntu major.minor version.' \
    '  --expected-architecture A Exact expected machine architecture.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly INGESTION_RUNNER="$SCRIPT_DIR/run_local_synthetic_ingestion.py"
readonly DECISION_LIST="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly SCRIPT_116_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-local-database-inventory/local_database_inventory_20261021T153436Z_CIJMtc.txt"
readonly SCRIPT_116_REPORT_SHA256='8b2bc61d304730360c533931c3d0c8a0137e5ab310c299c484e29865401156b1'
readonly POPPLER_SECURITY_REVIEW="$PHASE_ROOT/reference/poppler-utils-ubuntu24.04-arm64-security-review-2026-10-21.md"
readonly POPPLER_SECURITY_REVIEW_SHA256='0354808e733113471e7543c92778e307ab80c466e5da5e30b7a8624a865cfb0b'
readonly NATIVE_DEPENDENCY_REVIEW="$PHASE_ROOT/reference/ishikawa-local-tuning-native-dependency-review-2026-10-21.tsv"
readonly NATIVE_DEPENDENCY_REVIEW_SHA256='846aa8a237e9ce9fb2093fdd61b280a35f2789d1f1655841b35205d94d2523fc'
readonly SCHEMA_PATH="$ISHIKAWA_ROOT/packaging/database/schema.sql"
readonly SCHEMA_SHA256='5cfd397152b726aedc97be84d8a06fc8f21cad6e1a11563e5e9dd3a1f026d568'
readonly DEPLOYMENT_PROFILE="$ISHIKAWA_ROOT/config/templates/deployment.yaml"
readonly DEPLOYMENT_PROFILE_SHA256='2a5008b70a8ffe615cfcb2ca4b5d5a3687888c362861670a4a79e0de32874cfb'
readonly INGESTION_PROFILE="$ISHIKAWA_ROOT/config/templates/ingestion_dependencies.yaml"
readonly INGESTION_PROFILE_SHA256='1e024911f74e923dc9c2aa8bc0a1efae82f4d739e2be032fd8f067a99481e91f'
readonly OPERATOR_ROOT="$ISHIKAWA_ROOT/tests/fixtures/pipeline_writer"
readonly CLASS_REGISTRY="$OPERATOR_ROOT/document_classes.yaml"
readonly CLASS_REGISTRY_SHA256='6438c0a9e59bea1de0f9010dab2d7ee3de37419f3742666c096e0cca0e7ea32e'
readonly DOCUMENT_CATALOG="$OPERATOR_ROOT/document_catalog.yaml"
readonly DOCUMENT_CATALOG_SHA256='055f45ad7e7f4647cd8399cba2eb460f83c2c5c72c73b46407407fc98da2e15c'
readonly INGESTION_MANIFEST="$OPERATOR_ROOT/ingestion_manifest.yaml"
readonly INGESTION_MANIFEST_SHA256='e8de43bc053b640973753c2ab415d73d517abbaa3ce4238f72e6b3e8638bc180'
readonly PIPELINE_EXECUTABLE="$SCRIPT_DIR/ishikawa-produce-artifacts"
readonly PIPELINE_EXECUTABLE_SHA256='0faa5c65fbf8af454040158813308fb239ec70535bd956c3ffbc0523f5904b94'
readonly PIPELINE_CAPTURE="$SCRIPT_DIR/capture-pdf-extraction-observations.py"
readonly PIPELINE_CAPTURE_SHA256='a303e63d1a2329ddec39d563b5a7bdddea5bd7d720206544744876171a5371e2'
readonly PIPELINE_NORMALIZE="$SCRIPT_DIR/normalize-pdf-extraction.py"
readonly PIPELINE_NORMALIZE_SHA256='8e9193492c69bee6a31afe3f7606ec2efd528f79d76feb4189d462e6b3c206ea'
readonly PIPELINE_CHUNK="$SCRIPT_DIR/create-structural-chunk-candidates.py"
readonly PIPELINE_CHUNK_SHA256='2c042acfabe608a5683d212403beac6215d385301562de059dc55bd77ed44a26'
readonly PIPELINE_EMBED="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly PIPELINE_EMBED_SHA256='8f3c23ca30904dfb48a37f3366fd4b7873769bb92a527479fec5696f7fc456dc'
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly SYNTHETIC_MANIFEST="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/manifest.json"
readonly SYNTHETIC_MANIFEST_SHA256='c00a7a5dc6969ca5c22e0ac4adb5f2d8878439dd0b41adb46ccb079e6f866cfa'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-local-tuning-corpus"
readonly ACCEPTED_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-local-tuning-corpus"
readonly NATIVE_DEPENDENCY_CAPTURE_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-local-native-dependencies"
readonly DATABASE_NAME='rag_catalog'
readonly OWNER_ROLE='rag_owner'
readonly INGEST_ROLE='rag_ingest'
readonly RETRIEVAL_ROLE='rag_retrieval'
readonly POPPLER_VERSION='24.02.0-1ubuntu9.10'
readonly NSP_VERSION='2:4.35-1.1build1'
readonly NSS_VERSION='2:3.98-1ubuntu0.2'
readonly OPENJPEG_VERSION='2.5.0-2ubuntu0.5'
readonly UBUNTU_POSTGRESQL_VERSION='16.15-0ubuntu0.24.04.1'
readonly PGDG_POSTGRESQL_VERSION='16.15-1.pgdg24.04+2'
readonly PGVECTOR_PACKAGE_VERSION='0.8.7-1.pgdg24.04+1'
readonly PGVECTOR_EXTENSION_VERSION='0.8.7'
readonly LLVM_VERSION='1:19.1.1-1ubuntu1~24.04.2'
readonly PSYCOPG_PACKAGE_VERSION='3.1.17-2'
readonly PSYCOPG_MODULE_VERSION='3.1.17'
readonly PSYCOPG_SHA256='19f35b5e21532b91969b9924ad58df799e240fd5e6882875c6ff750a5a812831'
readonly PGDG_KEY_URL='https://www.postgresql.org/media/keys/ACCC4CF8.asc'
readonly PGDG_KEY_FINGERPRINT='B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8'
readonly PGDG_REPOSITORY='https://apt.postgresql.org/pub/repos/apt'
readonly PGDG_SUITE='noble-pgdg'
readonly EXPECTED_DOCUMENT_IDENTITIES='form.tst-9001|96a91dab4d748cb5d80ae211bdf4aa435a8d679b0fc7dd3668cfdde066909000;policy.governance-manual|4cef995f8ae67b2184b52ddf59635ea5adf05d8df6e40ac110eff0c04357dd47;policy.ops-17-control-2001|32d3cc0361e4b2a26ea552c1e8e6013c6a1635f036ad759b50d0e29b447b0e79;policy.ops-17-control-2002|1c44ff8c5f1b30046e265b619a08e76a9c1139e15e6eb85164ebcf3655b6b442;policy.schedule-2003|00f4489faa8f15ed50ed3095c476fcdc9dd05852d56daf08bec33f0faafbaa02;procedure.incident-reporting|962f8c6dd5835fc713cea6292ee1f30cb18d0abe6db38efe91f9a4ecea8d5175'

expected_hostname="${ISHIKAWA_TUNING_EXPECTED_HOSTNAME:-DankoSurface}"
expected_os_version="${ISHIKAWA_TUNING_EXPECTED_OS_VERSION:-24.04}"
expected_architecture="${ISHIKAWA_TUNING_EXPECTED_ARCHITECTURE:-aarch64}"
run_authorized=false
validate_only=false

while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --expected-architecture) expected_architecture="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_117_local_tuning_corpus=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_117_local_tuning_corpus=blocked;reason=mode_invalid\n' >&2
  exit 2
}
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || {
  printf 'script_117_local_tuning_corpus=blocked;reason=expected_hostname_invalid\n' >&2
  exit 2
}
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || {
  printf 'script_117_local_tuning_corpus=blocked;reason=expected_os_version_invalid\n' >&2
  exit 2
}
[[ "$expected_architecture" =~ ^[A-Za-z0-9_-]+$ ]] || {
  printf 'script_117_local_tuning_corpus=blocked;reason=expected_architecture_invalid\n' >&2
  exit 2
}

for required in apt-cache apt-get awk bash basename chmod cp curl date dpkg dpkg-deb dpkg-query env find gpg gpgv grep gzip hostname kill mkdir mktemp mv pg_ctlcluster pg_isready pg_lsclusters psql python3 rm sed sha256sum sleep sort stat sudo tail tee tr uname wc; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_117_local_tuning_corpus=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

readonly -a REQUIRED_FILES=(
  "$TEST_RUNNER"
  "$INGESTION_RUNNER"
  "$DECISION_LIST"
  "$SCRIPT_116_REPORT"
  "$POPPLER_SECURITY_REVIEW"
  "$NATIVE_DEPENDENCY_REVIEW"
  "$SCHEMA_PATH"
  "$DEPLOYMENT_PROFILE"
  "$INGESTION_PROFILE"
  "$CLASS_REGISTRY"
  "$DOCUMENT_CATALOG"
  "$INGESTION_MANIFEST"
  "$PIPELINE_EXECUTABLE"
  "$PIPELINE_CAPTURE"
  "$PIPELINE_NORMALIZE"
  "$PIPELINE_CHUNK"
  "$PIPELINE_EMBED"
  "$SYNTHETIC_MANIFEST"
)
for required_file in "${REQUIRED_FILES[@]}"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_117_local_tuning_corpus=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done
[[ -x "$PIPELINE_EXECUTABLE" ]] || {
  printf 'script_117_local_tuning_corpus=blocked;reason=pipeline_executable_invalid\n' >&2
  exit 2
}

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_117_local_tuning_corpus=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_sha256 "$SCRIPT_116_REPORT" "$SCRIPT_116_REPORT_SHA256" script_116_report
check_sha256 "$POPPLER_SECURITY_REVIEW" "$POPPLER_SECURITY_REVIEW_SHA256" poppler_security_review
check_sha256 "$NATIVE_DEPENDENCY_REVIEW" "$NATIVE_DEPENDENCY_REVIEW_SHA256" native_dependency_review
check_sha256 "$SCHEMA_PATH" "$SCHEMA_SHA256" final_schema
check_sha256 "$DEPLOYMENT_PROFILE" "$DEPLOYMENT_PROFILE_SHA256" deployment_profile
check_sha256 "$INGESTION_PROFILE" "$INGESTION_PROFILE_SHA256" ingestion_profile
check_sha256 "$CLASS_REGISTRY" "$CLASS_REGISTRY_SHA256" class_registry
check_sha256 "$DOCUMENT_CATALOG" "$DOCUMENT_CATALOG_SHA256" document_catalog
check_sha256 "$INGESTION_MANIFEST" "$INGESTION_MANIFEST_SHA256" ingestion_manifest
check_sha256 "$PIPELINE_EXECUTABLE" "$PIPELINE_EXECUTABLE_SHA256" pipeline_executable
check_sha256 "$PIPELINE_CAPTURE" "$PIPELINE_CAPTURE_SHA256" pipeline_capture
check_sha256 "$PIPELINE_NORMALIZE" "$PIPELINE_NORMALIZE_SHA256" pipeline_normalize
check_sha256 "$PIPELINE_CHUNK" "$PIPELINE_CHUNK_SHA256" pipeline_chunk
check_sha256 "$PIPELINE_EMBED" "$PIPELINE_EMBED_SHA256" pipeline_embed
check_sha256 "$SYNTHETIC_MANIFEST" "$SYNTHETIC_MANIFEST_SHA256" synthetic_manifest

python3 -B - "$NATIVE_DEPENDENCY_REVIEW" <<'PY'
from __future__ import annotations

import csv
import sys
from pathlib import Path

rows = list(csv.DictReader(Path(sys.argv[1]).open(encoding="utf-8"), delimiter="\t"))
required = {"source_package", "version", "origin", "target", "decision", "finding", "references"}
if not rows or not required.issubset(rows[0]):
    raise SystemExit("native dependency advisory review schema is invalid")
expected = {
    ("postgresql-16", "16.15-0ubuntu0.24.04.1", "ubuntu-noble", "ubuntu24.04-arm64", "accepted_fixed"),
    ("postgresql-16", "16.15-1.pgdg24.04+2", "postgresql-apt-noble-pgdg", "ubuntu24.04-arm64", "accepted_fixed"),
    ("llvm-toolchain-19", "1:19.1.1-1ubuntu1~24.04.2", "ubuntu-noble", "ubuntu24.04-arm64", "accepted_not_applicable"),
    ("psycopg3", "3.1.17-2", "ubuntu-noble", "ubuntu24.04-all", "accepted"),
    ("pgvector", "0.8.7-1.pgdg24.04+1", "postgresql-apt-noble-pgdg", "ubuntu24.04-arm64", "accepted_fixed"),
}
observed = {
    (row["source_package"], row["version"], row["origin"], row["target"], row["decision"])
    for row in rows
}
if observed != expected or len(rows) != len(expected):
    raise SystemExit("native dependency advisory coordinates differ from the accepted set")
for row in rows:
    if not row["finding"].strip() or not row["references"].startswith("https://"):
        raise SystemExit("native dependency advisory evidence is incomplete")
PY

for required_fact in \
  'milestone=application_identity_inventory;state=pass;database_exists=f;owner_role_exists=f;owner_login=f;ingest_role_exists=f;ingest_login=f;retrieval_role_exists=f;retrieval_login=f' \
  'script_116_local_database_inventory=pass;local_state=application_database_and_roles_absent;next_gate=bootstrap_local_roles_database_and_final_schema_then_ingest_synthetic_corpus;'; do
  grep -Fq "$required_fact" "$SCRIPT_116_REPORT" || {
    printf 'script_117_local_tuning_corpus=blocked;reason=script_116_contract_failed\n' >&2
    exit 2
  }
done
grep -Fq '| `T08` |' "$DECISION_LIST" || {
  printf 'script_117_local_tuning_corpus=blocked;reason=tuning_decision_list_incomplete\n' >&2
  exit 2
}

declare -A expected_pdf_sha256=(
  [31_SCH_2003.pdf]='00f4489faa8f15ed50ed3095c476fcdc9dd05852d56daf08bec33f0faafbaa02'
  [Form_TST9001.pdf]='96a91dab4d748cb5d80ae211bdf4aa435a8d679b0fc7dd3668cfdde066909000'
  [Governance_Manual_2005_Revision_3.pdf]='4cef995f8ae67b2184b52ddf59635ea5adf05d8df6e40ac110eff0c04357dd47'
  [OPS_17_CTL_2001.pdf]='32d3cc0361e4b2a26ea552c1e8e6013c6a1635f036ad759b50d0e29b447b0e79'
  [OPS_17_CTL_2002_RevA.pdf]='1c44ff8c5f1b30046e265b619a08e76a9c1139e15e6eb85164ebcf3655b6b442'
  [SOP_42_IR_2006.pdf]='962f8c6dd5835fc713cea6292ee1f30cb18d0abe6db38efe91f9a4ecea8d5175'
)
mapfile -t source_pdfs < <(find "$SOURCE_ROOT" -maxdepth 1 -type f -name '*.pdf' -print | sort)
(( ${#source_pdfs[@]} == 6 )) || {
  printf 'script_117_local_tuning_corpus=blocked;reason=synthetic_pdf_inventory_invalid\n' >&2
  exit 2
}
for source_pdf in "${source_pdfs[@]}"; do
  pdf_name="$(basename -- "$source_pdf")"
  [[ -n "${expected_pdf_sha256[$pdf_name]:-}" ]] || {
    printf 'script_117_local_tuning_corpus=blocked;reason=synthetic_pdf_name_unexpected\n' >&2
    exit 2
  }
  check_sha256 "$source_pdf" "${expected_pdf_sha256[$pdf_name]}" synthetic_pdf
done

apt_candidate() {
  apt-cache policy "$1" | awk '/^[[:space:]]*Candidate:/ && !found {value=$2; found=1} END {print value}'
}
installed_version() {
  local package_record
  package_record="$(dpkg-query -W -f='${Status}|${Version}|${Architecture}\n' "$1" 2>/dev/null || true)"
  awk -F'|' '$1 == "install ok installed" && $3 == "arm64" && !found {value=$2; found=1} END {print value}' \
    <<<"$package_record"
}
installed_package_version() {
  local package_record
  package_record="$(dpkg-query -W -f='${Status}|${Version}\n' "$1" 2>/dev/null || true)"
  awk -F'|' '$1 == "install ok installed" && !found {value=$2; found=1} END {print value}' \
    <<<"$package_record"
}

for package_contract in \
  "libnspr4|$NSP_VERSION" \
  "libnss3|$NSS_VERSION" \
  "libopenjp2-7|$OPENJPEG_VERSION" \
  "libpoppler134|$POPPLER_VERSION" \
  "poppler-utils|$POPPLER_VERSION"; do
  IFS='|' read -r package_name expected_version <<<"$package_contract"
  [[ "$(apt_candidate "$package_name")" == "$expected_version" ]] || {
    printf 'script_117_local_tuning_corpus=blocked;reason=native_package_candidate_changed;package=%s\n' "$package_name" >&2
    exit 2
  }
done
poppler_policy="$(apt-cache policy poppler-utils)"
grep -Fq 'noble-security/main arm64 Packages' <<<"$poppler_policy" || {
    printf 'script_117_local_tuning_corpus=blocked;reason=poppler_security_source_absent\n' >&2
    exit 2
  }

installed_poppler="$(installed_version poppler-utils)"
if [[ -z "$installed_poppler" ]]; then
  [[ ! -e /usr/bin/pdfinfo && ! -e /usr/bin/pdftotext ]] || {
    printf 'script_117_local_tuning_corpus=blocked;reason=unowned_extraction_binary_found\n' >&2
    exit 2
  }
  package_simulation="$(apt-get -s --no-install-recommends install \
    "libnspr4=$NSP_VERSION" \
    "libnss3=$NSS_VERSION" \
    "libopenjp2-7=$OPENJPEG_VERSION" \
    "libpoppler134=$POPPLER_VERSION" \
    "poppler-utils=$POPPLER_VERSION" 2>&1)" || {
    printf 'script_117_local_tuning_corpus=blocked;reason=native_package_simulation_failed\n' >&2
    exit 2
  }
  grep -Fq '0 upgraded, 5 newly installed, 0 to remove' <<<"$package_simulation" || {
    printf 'script_117_local_tuning_corpus=blocked;reason=native_package_closure_changed\n' >&2
    exit 2
  }
  extraction_dependency_action='install_reviewed_native_closure'
else
  [[ "$installed_poppler" == "$POPPLER_VERSION" \
      && -x /usr/bin/pdfinfo && -x /usr/bin/pdftotext ]] || {
    printf 'script_117_local_tuning_corpus=blocked;reason=installed_poppler_contract_mismatch\n' >&2
    exit 2
  }
  extraction_dependency_action='reuse_reviewed_native_installation'
fi

[[ "$(installed_package_version postgresql-16)" == "$UBUNTU_POSTGRESQL_VERSION" \
    || "$(installed_package_version postgresql-16)" == "$PGDG_POSTGRESQL_VERSION" ]] \
  || {
    printf 'script_117_local_tuning_corpus=blocked;reason=installed_postgresql_package_unexpected\n' >&2
    exit 2
  }
[[ "$(apt_candidate libllvm19)" == "$LLVM_VERSION" ]] || {
  printf 'script_117_local_tuning_corpus=blocked;reason=llvm_candidate_changed\n' >&2
  exit 2
}
[[ "$(apt_candidate python3-psycopg)" == "$PSYCOPG_PACKAGE_VERSION" ]] || {
  printf 'script_117_local_tuning_corpus=blocked;reason=psycopg_candidate_changed\n' >&2
  exit 2
}

installed_pgvector="$(installed_package_version postgresql-16-pgvector)"
installed_psycopg="$(installed_package_version python3-psycopg)"
if [[ "$(installed_package_version postgresql-16)" == "$PGDG_POSTGRESQL_VERSION" \
    && "$installed_pgvector" == "$PGVECTOR_PACKAGE_VERSION" \
    && "$(installed_package_version libllvm19)" == "$LLVM_VERSION" \
    && "$installed_psycopg" == "$PSYCOPG_PACKAGE_VERSION" ]]; then
  native_database_dependency_action='reuse_reviewed_native_installation'
else
  [[ -z "$installed_pgvector" || "$installed_pgvector" == '0.6.0-1' \
      || "$installed_pgvector" == "$PGVECTOR_PACKAGE_VERSION" ]] || {
    printf 'script_117_local_tuning_corpus=blocked;reason=installed_pgvector_package_unexpected\n' >&2
    exit 2
  }
  [[ -z "$installed_psycopg" || "$installed_psycopg" == "$PSYCOPG_PACKAGE_VERSION" ]] || {
    printf 'script_117_local_tuning_corpus=blocked;reason=installed_psycopg_package_unexpected\n' >&2
    exit 2
  }
  native_database_dependency_action='install_reviewed_compatible_native_closure'
fi

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(path).read_text(encoding="utf-8"), path, "exec") for path in sys.argv[1:]]' \
  "$INGESTION_RUNNER" "$PIPELINE_EXECUTABLE" "$PIPELINE_CAPTURE" \
  "$PIPELINE_NORMALIZE" "$PIPELINE_CHUNK" "$PIPELINE_EMBED"

pipeline_help="$(mktemp /tmp/ishikawa-script-117-pipeline-help.XXXXXX)"
pipeline_help_cleanup() { rm -f -- "$pipeline_help"; }
trap pipeline_help_cleanup EXIT
PYTHONDONTWRITEBYTECODE=1 "$PIPELINE_EXECUTABLE" --help >"$pipeline_help" 2>&1 || {
  printf 'script_117_local_tuning_corpus=blocked;reason=source_pipeline_layout_invalid\n' >&2
  exit 1
}
grep -Fq 'usage: ishikawa-produce-artifacts' "$pipeline_help" || {
  printf 'script_117_local_tuning_corpus=blocked;reason=source_pipeline_help_contract_invalid\n' >&2
  exit 1
}
rm -f -- "$pipeline_help"
trap - EXIT

test_result="$(mktemp /tmp/ishikawa-script-117-tests.XXXXXX)"
test_cleanup() { rm -f -- "$test_result"; }
trap test_cleanup EXIT
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_117_local_tuning_corpus=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 367 tests' "$test_result" || {
  printf 'script_117_local_tuning_corpus=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_117_local_tuning_corpus=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}
rm -f -- "$test_result"
trap - EXIT

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
ingestion_runner_sha256="$(sha256sum "$INGESTION_RUNNER" | awk '{print $1}')"
decision_list_sha256="$(sha256sum "$DECISION_LIST" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_local_synthetic_tuning_corpus_establishment_source' \
    "script_sha256=$script_sha256;ingestion_runner_sha256=$ingestion_runner_sha256;decision_list_sha256=$decision_list_sha256" \
    "script_116_report_sha256=$SCRIPT_116_REPORT_SHA256;schema_sha256=$SCHEMA_SHA256;synthetic_manifest_sha256=$SYNTHETIC_MANIFEST_SHA256" \
    "poppler_security_review_sha256=$POPPLER_SECURITY_REVIEW_SHA256;poppler_version=$POPPLER_VERSION;native_extraction_dependency_action=$extraction_dependency_action" \
    "native_dependency_review_sha256=$NATIVE_DEPENDENCY_REVIEW_SHA256;native_database_dependency_action=$native_database_dependency_action" \
    "postgresql_target_version=$PGDG_POSTGRESQL_VERSION;pgvector_target_version=$PGVECTOR_PACKAGE_VERSION;psycopg_target_version=$PSYCOPG_PACKAGE_VERSION" \
    'synthetic_documents=6;native_tests=367;failures=0;errors=0' \
    'sudo_used=false;model_contact=false;database_contact=false;database_changed=false;service_changed=false' \
    'script_117_local_tuning_corpus_source=pass'
  exit 0
fi

work_root="$(mktemp -d /tmp/ishikawa-script-117.XXXXXX)"
report_path=''
cluster_started_by_script=false
cluster_stopped_for_dependency_upgrade=false
service_start_policy_created=false
roles_created=false
database_created=false
corpus_accepted=false
nomic_key=''
ingest_password=''
retrieval_password=''
ingest_password_sql=''
retrieval_password_sql=''
sudo_keepalive_pid=''
package_stage_root=''

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}

clear_credentials() {
  nomic_key=''
  ingest_password=''
  retrieval_password=''
  ingest_password_sql=''
  retrieval_password_sql=''
  unset nomic_key ingest_password retrieval_password ingest_password_sql retrieval_password_sql
  unset ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_INGEST_PASSWORD PGPASSWORD
}

cleanup() {
  local status="$?" rollback_code=0 policy_code=0 stop_code=0 restore_code=0
  trap - EXIT INT TERM
  set +e
  if (( status != 0 )) && [[ "$corpus_accepted" != true ]]; then
    if [[ "$database_created" == true ]]; then
      printf 'DROP DATABASE IF EXISTS %s;\n' "$DATABASE_NAME" \
        | sudo -n -u postgres psql -X -q -v ON_ERROR_STOP=1 -d postgres \
          >/dev/null 2>&1 || rollback_code=1
    fi
    if [[ "$roles_created" == true ]]; then
      printf 'DROP ROLE IF EXISTS %s; DROP ROLE IF EXISTS %s; DROP ROLE IF EXISTS %s;\n' \
        "$RETRIEVAL_ROLE" "$INGEST_ROLE" "$OWNER_ROLE" \
        | sudo -n -u postgres psql -X -q -v ON_ERROR_STOP=1 -d postgres \
          >/dev/null 2>&1 || rollback_code=1
    fi
    if [[ "$database_created" == true || "$roles_created" == true ]]; then
      emit "cleanup_created_database_objects=rolled_back;exit_code=$rollback_code"
    else
      emit 'cleanup_created_database_objects=not_required'
    fi
    (( rollback_code == 0 )) || status=1
  fi
  if [[ "$service_start_policy_created" == true ]]; then
    sudo -n rm -f -- /usr/sbin/policy-rc.d >/dev/null 2>&1 || policy_code=$?
    if [[ -e /usr/sbin/policy-rc.d || -L /usr/sbin/policy-rc.d ]]; then
      policy_code=1
    fi
    emit "cleanup_temporary_service_start_policy=removed;exit_code=$policy_code"
    (( policy_code == 0 )) || status=1
    service_start_policy_created=false
  fi
  if [[ "$cluster_stopped_for_dependency_upgrade" == true ]]; then
    if pg_lsclusters --no-header | awk '$1 == 16 && $2 == "main" && $4 == "online" {found=1} END {exit(found ? 0 : 1)}'; then
      restore_code=0
    else
      sudo -n pg_ctlcluster 16 main start >/dev/null 2>&1 || restore_code=$?
    fi
    if (( restore_code == 0 )); then
      pg_isready -q -h 127.0.0.1 -p 5432 -d postgres -t 10 || restore_code=1
    fi
    emit "cleanup_local_cluster=restore_initial_online_verified;exit_code=$restore_code"
    (( restore_code == 0 )) || status=1
    cluster_stopped_for_dependency_upgrade=false
  elif [[ "$cluster_started_by_script" == true && "$corpus_accepted" != true ]]; then
    sudo -n pg_ctlcluster 16 main stop >/dev/null 2>&1 || stop_code=$?
    emit "cleanup_local_cluster=restore_stopped;exit_code=$stop_code"
    (( stop_code == 0 )) || status=1
  elif [[ "$corpus_accepted" == true ]]; then
    emit 'cleanup_local_cluster=left_online_for_tuning;boot_enabled=false'
  else
    emit 'cleanup_local_cluster=not_required'
  fi
  if [[ "$sudo_keepalive_pid" =~ ^[1-9][0-9]*$ ]]; then
    kill "$sudo_keepalive_pid" >/dev/null 2>&1 || true
    wait "$sudo_keepalive_pid" 2>/dev/null || true
  fi
  clear_credentials
  emit 'cleanup_runtime_credentials=cleared'
  [[ -z "$package_stage_root" || ! -d "$package_stage_root" \
      || "$package_stage_root" != /tmp/ishikawa-script-117-packages.* ]] \
    || rm -rf -- "$package_stage_root"
  [[ "$work_root" == /tmp/ishikawa-script-117.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

block() {
  emit "script_117_local_tuning_corpus=blocked;reason=$1"
  exit 1
}

read_secret() {
  local label="$1" output_name="$2" value=''
  printf '%s (input hidden): ' "$label" >/dev/tty
  IFS= read -r -s value </dev/tty || block 'secret_input_failed'
  printf '\n' >/dev/tty
  (( ${#value} >= 1 && ${#value} <= 4096 )) || block 'secret_length_invalid'
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || block 'secret_character_invalid'
  printf -v "$output_name" '%s' "$value"
  value=''
}

read_confirmed_secret() {
  local label="$1" output_name="$2" first='' second=''
  printf 'Enter the password for %s (input hidden): ' "$label" >/dev/tty
  IFS= read -r -s first </dev/tty || block 'secret_input_failed'
  printf '\nConfirm the password for %s (input hidden): ' "$label" >/dev/tty
  IFS= read -r -s second </dev/tty || block 'secret_confirmation_input_failed'
  printf '\n' >/dev/tty
  [[ "$first" == "$second" ]] || block 'secret_confirmation_mismatch'
  (( ${#first} >= 1 && ${#first} <= 4096 )) || block 'secret_length_invalid'
  [[ "$first" != *$'\n'* && "$first" != *$'\r'* ]] || block 'secret_character_invalid'
  printf -v "$output_name" '%s' "$first"
  first=''
  second=''
}

pgdg_server_deb=''
pgvector_deb=''
llvm_deb=''
psycopg_deb=''

bind_native_dependency_capture() {
  local package_path package_name package_version package_architecture
  [[ -d "$NATIVE_DEPENDENCY_CAPTURE_ROOT" \
      && ! -L "$NATIVE_DEPENDENCY_CAPTURE_ROOT" \
      && -f "$NATIVE_DEPENDENCY_CAPTURE_ROOT/SHA256SUMS" \
      && -f "$NATIVE_DEPENDENCY_CAPTURE_ROOT/advisory-review.tsv" ]] \
    || block 'native_dependency_capture_invalid'
  [[ -z "$(find "$NATIVE_DEPENDENCY_CAPTURE_ROOT" -type l -print -quit)" ]] \
    || block 'native_dependency_capture_symlink_found'
  (
    cd "$NATIVE_DEPENDENCY_CAPTURE_ROOT"
    sha256sum -c SHA256SUMS >"$work_root/native-capture-verification.txt" 2>&1
  ) || block 'native_dependency_capture_checksum_failure'
  [[ "$(sha256sum "$NATIVE_DEPENDENCY_CAPTURE_ROOT/advisory-review.tsv" | awk '{print $1}')" \
      == "$NATIVE_DEPENDENCY_REVIEW_SHA256" ]] \
    || block 'native_dependency_capture_review_mismatch'

  while IFS= read -r package_path; do
    package_name="$(dpkg-deb -f "$package_path" Package)"
    package_version="$(dpkg-deb -f "$package_path" Version)"
    package_architecture="$(dpkg-deb -f "$package_path" Architecture)"
    case "$package_name|$package_version|$package_architecture" in
      "postgresql-16|$PGDG_POSTGRESQL_VERSION|arm64") pgdg_server_deb="$package_path" ;;
      "postgresql-16-pgvector|$PGVECTOR_PACKAGE_VERSION|arm64") pgvector_deb="$package_path" ;;
      "libllvm19|$LLVM_VERSION|arm64") llvm_deb="$package_path" ;;
      "python3-psycopg|$PSYCOPG_PACKAGE_VERSION|all") psycopg_deb="$package_path" ;;
      *) block 'native_dependency_capture_package_unexpected' ;;
    esac
  done < <(find "$NATIVE_DEPENDENCY_CAPTURE_ROOT/packages" -maxdepth 1 -type f -name '*.deb' -print | sort)
  [[ -n "$pgdg_server_deb" && -n "$pgvector_deb" && -n "$llvm_deb" && -n "$psycopg_deb" ]] \
    || block 'native_dependency_capture_package_missing'
  [[ "$(find "$NATIVE_DEPENDENCY_CAPTURE_ROOT/packages" -maxdepth 1 -type f -name '*.deb' | awk 'END {print NR+0}')" == 4 ]] \
    || block 'native_dependency_capture_package_count_invalid'
}

capture_native_database_dependencies() {
  local staging_root repository_root key_asc keyring inrelease packages_gz packages_file
  local gpg_home actual_fingerprint packages_metadata packages_sha256 packages_size
  local selected_records package_name package_version package_architecture package_relative
  local package_size package_sha256 downloaded_path apt_metadata apt_filename apt_size apt_sha256
  local apt_download_root apt_downloaded_path

  if [[ -e "$NATIVE_DEPENDENCY_CAPTURE_ROOT" || -L "$NATIVE_DEPENDENCY_CAPTURE_ROOT" ]]; then
    bind_native_dependency_capture
    emit 'milestone=native_dependency_capture;state=pass;action=reuse;packages=4;pre_download_advisory_gate=pass'
    return
  fi

  staging_root="$work_root/native-dependency-capture"
  repository_root="$staging_root/repository-metadata"
  mkdir -p -- "$staging_root/packages" "$repository_root"
  cp -- "$NATIVE_DEPENDENCY_REVIEW" "$staging_root/advisory-review.tsv"
  key_asc="$repository_root/ACCC4CF8.asc"
  keyring="$work_root/ACCC4CF8.gpg"
  inrelease="$repository_root/InRelease"
  packages_gz="$repository_root/Packages.gz"
  packages_file="$work_root/Packages"
  gpg_home="$work_root/gnupg"
  mkdir -m 0700 -- "$gpg_home"

  emit 'milestone=native_dependency_capture;state=start;pre_download_advisory_gate=pass'
  curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 120 --proto '=https' \
    "$PGDG_KEY_URL" --output "$key_asc" \
    || block 'pgdg_key_download_failed'
  actual_fingerprint="$(GNUPGHOME="$gpg_home" gpg --batch --with-colons --import-options show-only --import "$key_asc" 2>/dev/null \
    | awk -F: '$1 == "fpr" {print $10; exit}')"
  [[ "$actual_fingerprint" == "$PGDG_KEY_FINGERPRINT" ]] \
    || block 'pgdg_key_fingerprint_mismatch'
  gpg --batch --yes --dearmor --output "$keyring" "$key_asc" \
    || block 'pgdg_keyring_creation_failed'
  curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 120 --proto '=https' \
    "$PGDG_REPOSITORY/dists/$PGDG_SUITE/InRelease" --output "$inrelease" \
    || block 'pgdg_inrelease_download_failed'
  gpgv --keyring "$keyring" "$inrelease" >"$work_root/inrelease-verification.txt" 2>&1 \
    || block 'pgdg_inrelease_signature_failure'
  packages_metadata="$(awk '$1 ~ /^[0-9a-f]{64}$/ && $3 == "main/binary-arm64/Packages.gz" {print $1, $2; exit}' "$inrelease")"
  [[ -n "$packages_metadata" ]] || block 'pgdg_packages_index_not_signed'
  read -r packages_sha256 packages_size <<<"$packages_metadata"
  curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 120 --proto '=https' \
    "$PGDG_REPOSITORY/dists/$PGDG_SUITE/main/binary-arm64/Packages.gz" --output "$packages_gz" \
    || block 'pgdg_packages_index_download_failed'
  [[ "$(sha256sum "$packages_gz" | awk '{print $1}')" == "$packages_sha256" \
      && "$(wc -c <"$packages_gz" | tr -d ' ')" == "$packages_size" ]] \
    || block 'pgdg_packages_index_checksum_failure'
  gzip -dc -- "$packages_gz" >"$packages_file" \
    || block 'pgdg_packages_index_decompression_failed'

  selected_records="$repository_root/selected-packages.tsv"
  python3 -B - "$packages_file" "$selected_records" \
    "postgresql-16|$PGDG_POSTGRESQL_VERSION|arm64" \
    "postgresql-16-pgvector|$PGVECTOR_PACKAGE_VERSION|arm64" <<'PY'
from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

packages_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
wanted = {tuple(value.split("|", 2)) for value in sys.argv[3:]}
records: list[dict[str, str]] = []
for paragraph in packages_path.read_text(encoding="utf-8", errors="strict").split("\n\n"):
    record: dict[str, str] = {}
    current = ""
    for line in paragraph.splitlines():
        if line.startswith((" ", "\t")) and current:
            record[current] += " " + line.strip()
        elif ": " in line:
            current, value = line.split(": ", 1)
            record[current] = value
    coordinate = (record.get("Package", ""), record.get("Version", ""), record.get("Architecture", ""))
    if coordinate in wanted:
        records.append(record)
if len(records) != len(wanted) or {(
    row["Package"], row["Version"], row["Architecture"]
) for row in records} != wanted:
    raise SystemExit("signed PGDG package records differ from the accepted coordinates")
by_package = {record["Package"]: record for record in records}
server = by_package["postgresql-16"]
vector = by_package["postgresql-16-pgvector"]
if "postgresql-16-jit-llvm (= 19)" not in server.get("Provides", ""):
    raise SystemExit("selected PGDG PostgreSQL server does not provide the accepted JIT-19 contract")
if "postgresql-16-jit-llvm (<< 19)" not in vector.get("Breaks", ""):
    raise SystemExit("selected PGDG pgvector package does not enforce the accepted JIT-19 floor")
columns = ["package", "version", "architecture", "filename", "size", "sha256", "depends", "breaks"]
with output_path.open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=columns, delimiter="\t", lineterminator="\n")
    writer.writeheader()
    for record in sorted(records, key=lambda row: row["Package"]):
        required = {"Filename", "Size", "SHA256", "Depends"}
        if not required.issubset(record):
            raise SystemExit("selected PGDG record lacks signed fields")
        if not re.fullmatch(r"pool/main/p/[A-Za-z0-9._+-]+/[A-Za-z0-9.+~_-]+\.deb", record["Filename"]):
            raise SystemExit("selected PGDG package path is invalid")
        if not re.fullmatch(r"[0-9a-f]{64}", record["SHA256"]) or not record["Size"].isdigit():
            raise SystemExit("selected PGDG package size or digest is invalid")
        writer.writerow({
            "package": record["Package"],
            "version": record["Version"],
            "architecture": record["Architecture"],
            "filename": record["Filename"],
            "size": record["Size"],
            "sha256": record["SHA256"],
            "depends": record["Depends"],
            "breaks": record.get("Breaks", ""),
        })
PY

  while IFS=$'\t' read -r package_name package_version package_architecture package_relative package_size package_sha256 _; do
    [[ "$package_name" != package ]] || continue
    downloaded_path="$staging_root/packages/$(basename -- "$package_relative")"
    curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 180 --proto '=https' \
      "$PGDG_REPOSITORY/$package_relative" --output "$downloaded_path.partial" \
      || block 'pgdg_package_download_failed'
    [[ "$(sha256sum "$downloaded_path.partial" | awk '{print $1}')" == "$package_sha256" \
        && "$(wc -c <"$downloaded_path.partial" | tr -d ' ')" == "$package_size" ]] \
      || block 'pgdg_package_checksum_failure'
    mv -- "$downloaded_path.partial" "$downloaded_path"
    [[ "$(dpkg-deb -f "$downloaded_path" Package)" == "$package_name" \
        && "$(dpkg-deb -f "$downloaded_path" Version)" == "$package_version" \
        && "$(dpkg-deb -f "$downloaded_path" Architecture)" == "$package_architecture" ]] \
      || block 'pgdg_package_control_mismatch'
  done <"$selected_records"

  for apt_coordinate in "libllvm19|$LLVM_VERSION|arm64" "python3-psycopg|$PSYCOPG_PACKAGE_VERSION|all"; do
    IFS='|' read -r package_name package_version package_architecture <<<"$apt_coordinate"
    apt_metadata="$(apt-cache show "$package_name=$package_version")"
    apt_filename="$(awk -F': ' '$1 == "Filename" {print $2; exit}' <<<"$apt_metadata")"
    apt_size="$(awk -F': ' '$1 == "Size" {print $2; exit}' <<<"$apt_metadata")"
    apt_sha256="$(awk -F': ' '$1 == "SHA256" {print $2; exit}' <<<"$apt_metadata")"
    [[ -n "$apt_filename" && "$apt_size" =~ ^[0-9]+$ && "$apt_sha256" =~ ^[0-9a-f]{64}$ ]] \
      || block 'ubuntu_package_metadata_invalid'
    [[ "$package_name" != python3-psycopg || "$apt_sha256" == "$PSYCOPG_SHA256" ]] \
      || block 'psycopg_repository_digest_changed'
    apt_download_root="$work_root/download-$package_name"
    mkdir -- "$apt_download_root"
    (
      cd "$apt_download_root"
      apt-get download "$package_name=$package_version" >download.stdout 2>download.stderr
    ) || block 'ubuntu_package_download_failed'
    apt_downloaded_path="$(find "$apt_download_root" -maxdepth 1 -type f -name '*.deb' -print)"
    [[ -n "$apt_downloaded_path" \
        && "$(find "$apt_download_root" -maxdepth 1 -type f -name '*.deb' | awk 'END {print NR+0}')" == 1 \
        && "$(sha256sum "$apt_downloaded_path" | awk '{print $1}')" == "$apt_sha256" \
        && "$(wc -c <"$apt_downloaded_path" | tr -d ' ')" == "$apt_size" \
        && "$(dpkg-deb -f "$apt_downloaded_path" Package)" == "$package_name" \
        && "$(dpkg-deb -f "$apt_downloaded_path" Version)" == "$package_version" \
        && "$(dpkg-deb -f "$apt_downloaded_path" Architecture)" == "$package_architecture" ]] \
      || block 'ubuntu_package_verification_failed'
    cp -- "$apt_downloaded_path" "$staging_root/packages/$(basename -- "$apt_downloaded_path")"
  done

  {
    printf 'schema=ishikawa-local-native-dependencies/v1\n'
    printf 'target=ubuntu24.04-arm64\n'
    printf 'postgresql_version=%s\n' "$PGDG_POSTGRESQL_VERSION"
    printf 'pgvector_version=%s\n' "$PGVECTOR_PACKAGE_VERSION"
    printf 'llvm_version=%s\n' "$LLVM_VERSION"
    printf 'psycopg_version=%s\n' "$PSYCOPG_PACKAGE_VERSION"
    printf 'advisory_review_sha256=%s\n' "$NATIVE_DEPENDENCY_REVIEW_SHA256"
    printf 'pgdg_key_fingerprint=%s\n' "$PGDG_KEY_FINGERPRINT"
    printf 'pre_download_advisory_gate=pass\n'
  } >"$staging_root/capture.env"
  (
    cd "$staging_root"
    while IFS= read -r relative_path; do
      sha256sum "$relative_path"
    done < <(find . -type f ! -name SHA256SUMS -printf '%P\n' | sort) >SHA256SUMS
    sha256sum -c SHA256SUMS >"$work_root/staged-capture-verification.txt"
  ) || block 'native_dependency_capture_finalization_failed'
  mkdir -p -- "$(dirname -- "$NATIVE_DEPENDENCY_CAPTURE_ROOT")"
  mv -- "$staging_root" "$NATIVE_DEPENDENCY_CAPTURE_ROOT" \
    || block 'native_dependency_capture_retention_failed'
  bind_native_dependency_capture
  emit 'milestone=native_dependency_capture;state=pass;action=create;packages=4;pre_download_advisory_gate=pass'
}

stage_native_database_dependencies() {
  local staging_root source_path staged_path source_sha256
  package_stage_root="$(mktemp -d /tmp/ishikawa-script-117-packages.XXXXXX)"
  chmod 0755 "$package_stage_root"
  staging_root="$package_stage_root"
  for source_path in "$llvm_deb" "$pgdg_server_deb" "$pgvector_deb" "$psycopg_deb"; do
    source_sha256="$(sha256sum "$source_path" | awk '{print $1}')"
    staged_path="$staging_root/$(basename -- "$source_path")"
    cp -- "$source_path" "$staged_path"
    chmod 0644 "$staged_path"
    [[ "$(sha256sum "$staged_path" | awk '{print $1}')" == "$source_sha256" ]] \
      || block 'native_dependency_staging_checksum_failure'
    case "$(dpkg-deb -f "$staged_path" Package)" in
      libllvm19) llvm_deb="$staged_path" ;;
      postgresql-16) pgdg_server_deb="$staged_path" ;;
      postgresql-16-pgvector) pgvector_deb="$staged_path" ;;
      python3-psycopg) psycopg_deb="$staged_path" ;;
      *) block 'native_dependency_staging_package_unexpected' ;;
    esac
  done
  [[ "$(find "$staging_root" -maxdepth 1 -type f -name '*.deb' | awk 'END {print NR+0}')" == 4 ]] \
    || block 'native_dependency_staging_package_count_invalid'
  emit 'milestone=native_dependency_staging;state=pass;filesystem=native_tmp;packages=4'
}

classify_native_package_install_failure() {
  local stdout_path="$1" stderr_path="$2"
  if grep -Eiq 'Could not get lock|Unable to acquire the dpkg frontend lock|is another process using it' \
      "$stdout_path" "$stderr_path"; then
    printf 'package_manager_lock_busy'
  elif grep -Eiq 'unmet dependencies|held broken packages|dependency problems|pkgProblemResolver' \
      "$stdout_path" "$stderr_path"; then
    printf 'dependency_resolution_failed'
  elif grep -Eiq 'Sub-process /usr/bin/dpkg returned an error code|dpkg: error' \
      "$stdout_path" "$stderr_path"; then
    printf 'dpkg_execution_failed'
  elif grep -Eiq 'Failed to fetch|Unable to fetch|File not found|No such file or directory' \
      "$stdout_path" "$stderr_path"; then
    printf 'local_package_acquisition_failed'
  elif grep -Eiq 'No space left on device|not enough free space' \
      "$stdout_path" "$stderr_path"; then
    printf 'insufficient_disk_space'
  elif grep -Eiq 'policy-rc\.d|invoke-rc\.d|systemctl|service' \
      "$stdout_path" "$stderr_path"; then
    printf 'package_service_action_failed'
  else
    printf 'unclassified_review_required'
  fi
}

run_native_package_install_stage() {
  local stage="$1" stdout_path stderr_path exit_code failure_class
  shift
  stdout_path="$work_root/native-database-${stage}-install.stdout"
  stderr_path="$work_root/native-database-${stage}-install.stderr"
  if sudo -n env DEBIAN_FRONTEND=noninteractive apt-get --yes \
      --no-install-recommends \
      -o Dir::Etc::sourcelist=/dev/null \
      -o Dir::Etc::sourceparts=/dev/null \
      -o APT::Get::List-Cleanup=0 \
      -o Acquire::Languages=none \
      -o Acquire::Retries=0 \
      -o Acquire::http::Proxy=http://127.0.0.1:9 \
      -o Acquire::https::Proxy=http://127.0.0.1:9 \
      -o Acquire::ftp::Proxy=ftp://127.0.0.1:9 \
      -o DPkg::Lock::Timeout=60 \
      install "$@" >"$stdout_path" 2>"$stderr_path"; then
    exit_code=0
    failure_class=none
  else
    exit_code=$?
    failure_class="$(classify_native_package_install_failure "$stdout_path" "$stderr_path")"
  fi
  emit "milestone=native_database_${stage}_install;state=$([[ "$exit_code" == 0 ]] && printf pass || printf blocked);exit_code=$exit_code;failure_class=$failure_class;stdout_sha256=$(sha256sum "$stdout_path" | awk '{print $1}');stderr_sha256=$(sha256sum "$stderr_path" | awk '{print $1}');raw_output_retained=false"
  (( exit_code == 0 ))
}

escape_sql_literal() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf '%s' "$value"
}

mkdir -p -- "$REPORT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && ! -e "$ACCEPTED_ARTIFACT_ROOT" ]] \
  || block 'output_lane_not_clean'
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/local_tuning_corpus_${timestamp}_XXXXXX.txt")"
mkdir -m 0700 -- "$work_root/producer-work" "$work_root/operator-reports" "$work_root/artifacts"
emit 'purpose=establish_local_synthetic_corpus_for_ishikawa_v1_1_tuning'
emit "started_utc=$timestamp;local_report=$report_path"
emit "script_sha256=$script_sha256;ingestion_runner_sha256=$ingestion_runner_sha256;decision_list_sha256=$decision_list_sha256"
emit "script_116_report_sha256=$SCRIPT_116_REPORT_SHA256;schema_sha256=$SCHEMA_SHA256;synthetic_manifest_sha256=$SYNTHETIC_MANIFEST_SHA256"
emit "poppler_security_review_sha256=$POPPLER_SECURITY_REVIEW_SHA256;poppler_version=$POPPLER_VERSION;native_extraction_dependency_action=$extraction_dependency_action"
emit "native_dependency_review_sha256=$NATIVE_DEPENDENCY_REVIEW_SHA256;native_database_dependency_action=$native_database_dependency_action"
emit "postgresql_target_version=$PGDG_POSTGRESQL_VERSION;pgvector_target_version=$PGVECTOR_PACKAGE_VERSION;psycopg_target_version=$PSYCOPG_PACKAGE_VERSION"
emit 'authorized_actions=attended_local_sudo_capture_and_install_exact_advisory_reviewed_native_database_dependencies_if_needed_install_exact_reviewed_ubuntu_native_extraction_closure_if_absent_start_existing_postgresql_if_needed_create_application_roles_database_vector_extension_and_final_schema_validate_and_publish_checksum_bound_synthetic_corpus_retain_derived_artifacts_leave_postgresql_online_for_tuning'
emit 'non_actions=no_lab_host_contact_no_gemma_contact_no_database_copy_no_apt_update_no_recommended_package_install_no_deployment_package_build_no_service_enablement_no_firewall_or_forwarding_change_no_secret_argument_output_or_retention'
emit 'operator_expectation=local_sudo_password_may_be_prompted;nomic_key_once;new_rag_ingest_password_twice;new_rag_retrieval_password_twice;estimated_duration_minutes=5-15'

actual_hostname="$(hostname -s)"
actual_architecture="$(uname -m)"
actual_os="$(. /etc/os-release && printf '%s|%s' "$ID" "$VERSION_ID")"
[[ "$actual_hostname" == "$expected_hostname" ]] || block 'hostname_mismatch'
[[ "$actual_os" == "ubuntu|$expected_os_version" ]] || block 'os_identity_mismatch'
[[ "$actual_architecture" == "$expected_architecture" ]] || block 'architecture_mismatch'
emit "milestone=local_host_identity;state=pass;hostname=$actual_hostname;os_id=ubuntu;os_version=$expected_os_version;architecture=$actual_architecture"

nomic_health="$(curl -sS --fail --max-time 10 -o /dev/null -w '%{http_code}' http://127.0.0.1:8001/health 2>"$work_root/nomic-health.stderr")" \
  || block 'nomic_forwarded_health_unavailable'
[[ "$nomic_health" == 200 ]] || block 'nomic_forwarded_health_status_invalid'
emit 'milestone=nomic_forwarded_health;state=pass;http_status=200;inference=false'

emit 'milestone=local_sudo;state=waiting_for_operator_if_prompted'
sudo -v || block 'sudo_authorization_failed'
emit 'milestone=local_sudo;state=pass'
(
  while kill -0 "$$" 2>/dev/null; do
    sudo -n -v >/dev/null 2>&1 || exit 1
    sleep 30
  done
) &
sudo_keepalive_pid=$!

if [[ "$native_database_dependency_action" == install_reviewed_compatible_native_closure ]]; then
  dependency_cluster_line="$(pg_lsclusters --no-header | awk '$1 == 16 && $2 == "main" {print; found=1} END {if (!found) exit 1}')" \
    || block 'postgresql_cluster_missing_before_dependency_install'
  read -r _ _ _ dependency_cluster_status _ <<<"$dependency_cluster_line"
  if [[ "$dependency_cluster_status" == online ]]; then
    sudo -n pg_ctlcluster 16 main stop >"$work_root/dependency-cluster-stop.stdout" 2>"$work_root/dependency-cluster-stop.stderr" \
      || block 'postgresql_stop_before_dependency_install_failed'
    cluster_stopped_for_dependency_upgrade=true
  elif [[ "$dependency_cluster_status" != down ]]; then
    block 'postgresql_cluster_status_invalid_before_dependency_install'
  fi

  capture_native_database_dependencies
  stage_native_database_dependencies
  package_simulation="$(apt-get -s --no-install-recommends --no-download \
    -o Dir::Etc::sourcelist=/dev/null \
    -o Dir::Etc::sourceparts=/dev/null \
    -o APT::Get::List-Cleanup=0 \
    -o Acquire::Languages=none \
    install "$llvm_deb" "$pgdg_server_deb" "$pgvector_deb" "$psycopg_deb" 2>&1)" \
    || block 'native_database_dependency_simulation_failed'
  [[ "$(awk '/^Remv / {count++} END {print count+0}' <<<"$package_simulation")" == 0 ]] \
    || block 'native_database_dependency_simulation_removal_found'
  mapfile -t planned_packages < <(awk '/^Inst / {print $2}' <<<"$package_simulation" | sort -u)
  (( ${#planned_packages[@]} >= 1 && ${#planned_packages[@]} <= 4 )) \
    || block 'native_database_dependency_simulation_count_invalid'
  for planned_package in "${planned_packages[@]}"; do
    case "$planned_package" in
      libllvm19|postgresql-16|postgresql-16-pgvector|python3-psycopg) ;;
      *) block 'native_database_dependency_simulation_package_unexpected' ;;
    esac
  done

  [[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]] \
    || block 'existing_service_start_policy_requires_review'
  printf '%s\n' '#!/bin/sh' '# Temporary Ishikawa Script 117 package-install guard.' 'exit 101' \
    | sudo -n tee /usr/sbin/policy-rc.d >/dev/null \
    || block 'temporary_service_start_policy_creation_failed'
  sudo -n chmod 0755 /usr/sbin/policy-rc.d \
    || block 'temporary_service_start_policy_mode_failed'
  service_start_policy_created=true
  emit 'milestone=temporary_service_start_policy;state=pass;action=created;removal=mandatory'

  run_native_package_install_stage support "$llvm_deb" "$psycopg_deb" \
    || block 'native_database_support_install_failed'
  run_native_package_install_stage server "$pgdg_server_deb" "$pgvector_deb" \
    || block 'native_database_server_install_failed'
  if grep -Eiq 'https?://|ftp://' \
      "$work_root/native-database-support-install.stdout" \
      "$work_root/native-database-support-install.stderr" \
      "$work_root/native-database-server-install.stdout" \
      "$work_root/native-database-server-install.stderr"; then
    block 'unexpected_network_package_source'
  fi
  sudo -n rm -f -- /usr/sbin/policy-rc.d \
    || block 'temporary_service_start_policy_removal_failed'
  [[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]] \
    || block 'temporary_service_start_policy_removal_unverified'
  service_start_policy_created=false
  emit 'milestone=temporary_service_start_policy;state=pass;action=removed'

  if [[ "$cluster_stopped_for_dependency_upgrade" == true ]]; then
    if ! pg_lsclusters --no-header | awk '$1 == 16 && $2 == "main" && $4 == "online" {found=1} END {exit(found ? 0 : 1)}'; then
      sudo -n pg_ctlcluster 16 main start >"$work_root/dependency-cluster-start.stdout" 2>"$work_root/dependency-cluster-start.stderr" \
        || block 'postgresql_restart_after_dependency_install_failed'
    fi
    pg_isready -q -h 127.0.0.1 -p 5432 -d postgres -t 10 \
      || block 'postgresql_unready_after_dependency_install'
    cluster_stopped_for_dependency_upgrade=false
  fi
fi

[[ "$(installed_package_version postgresql-16)" == "$PGDG_POSTGRESQL_VERSION" \
    && "$(installed_package_version postgresql-16-pgvector)" == "$PGVECTOR_PACKAGE_VERSION" \
    && "$(installed_package_version libllvm19)" == "$LLVM_VERSION" \
    && "$(installed_package_version python3-psycopg)" == "$PSYCOPG_PACKAGE_VERSION" ]] \
  || block 'native_database_dependency_verification_failed'
apt_check_stdout="$work_root/native-database-apt-check.stdout"
apt_check_stderr="$work_root/native-database-apt-check.stderr"
sudo -n apt-get check \
  -o Dir::Etc::sourcelist=/dev/null \
  -o Dir::Etc::sourceparts=/dev/null \
  -o APT::Get::List-Cleanup=0 \
  >"$apt_check_stdout" 2>"$apt_check_stderr" \
  || block 'native_database_dependency_consistency_failed'
dpkg_audit="$work_root/native-database-dpkg-audit.txt"
dpkg --audit >"$dpkg_audit" 2>&1 \
  || block 'native_database_dpkg_audit_failed'
[[ ! -s "$dpkg_audit" ]] || block 'native_database_dpkg_state_incomplete'
observed_psycopg_version="$(PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import psycopg; print(psycopg.__version__)' 2>"$work_root/psycopg-import.stderr")" \
  || block 'native_psycopg_import_failed'
[[ "$observed_psycopg_version" == "$PSYCOPG_MODULE_VERSION" ]] \
  || block 'native_psycopg_version_mismatch'
emit "milestone=native_database_dependencies;state=pass;action=$native_database_dependency_action;postgresql_version=$PGDG_POSTGRESQL_VERSION;pgvector_package_version=$PGVECTOR_PACKAGE_VERSION;psycopg_version=$PSYCOPG_MODULE_VERSION;advisory_review=pass;apt_check=pass;dpkg_audit=clean"

if [[ "$extraction_dependency_action" == install_reviewed_native_closure ]]; then
  sudo -n apt-get install -y --no-install-recommends \
    "libnspr4=$NSP_VERSION" \
    "libnss3=$NSS_VERSION" \
    "libopenjp2-7=$OPENJPEG_VERSION" \
    "libpoppler134=$POPPLER_VERSION" \
    "poppler-utils=$POPPLER_VERSION" \
    >"$work_root/native-package-install.stdout" 2>"$work_root/native-package-install.stderr" \
    || block 'native_extraction_dependency_install_failed'
fi
[[ "$(installed_version poppler-utils)" == "$POPPLER_VERSION" \
    && -x /usr/bin/pdfinfo && -x /usr/bin/pdftotext ]] \
  || block 'native_extraction_dependency_verification_failed'
emit "milestone=native_extraction_dependency;state=pass;action=$extraction_dependency_action;package=poppler-utils;version=$POPPLER_VERSION;architecture=arm64;closure_packages=5;advisory_review=pass"

cluster_line="$(pg_lsclusters --no-header | awk '$1 == 16 && $2 == "main" {print; found=1} END {if (!found) exit 1}')" \
  || block 'postgresql_cluster_missing'
read -r cluster_version cluster_name cluster_port cluster_status _ <<<"$cluster_line"
[[ "$cluster_version|$cluster_name|$cluster_port" == '16|main|5432' ]] || block 'postgresql_cluster_identity_mismatch'
if [[ "$cluster_status" == down ]]; then
  sudo -n pg_ctlcluster 16 main start >"$work_root/cluster-start.stdout" 2>"$work_root/cluster-start.stderr" \
    || block 'postgresql_start_failed'
  cluster_started_by_script=true
elif [[ "$cluster_status" != online ]]; then
  block 'postgresql_cluster_status_invalid'
fi
pg_isready -q -h 127.0.0.1 -p 5432 -d postgres -t 10 || block 'postgresql_not_ready'
emit "milestone=local_postgresql_runtime;state=pass;initial_status=$cluster_status;current_status=online;boot_enabled=false"

current_identity="$(sudo -n -u postgres psql -X -q -A -t -d postgres -v ON_ERROR_STOP=1 \
  -c "SELECT concat_ws('|',
      EXISTS (SELECT 1 FROM pg_database WHERE datname = '$DATABASE_NAME'),
      EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$OWNER_ROLE'),
      EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$INGEST_ROLE'),
      EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$RETRIEVAL_ROLE'));" \
  2>"$work_root/identity-preflight.stderr")" || block 'database_identity_preflight_failed'
[[ "$current_identity" == 'f|f|f|f' ]] || block 'database_identity_no_longer_empty'
emit 'milestone=database_identity_preflight;state=pass;database_exists=false;application_roles_exist=false'

read_secret 'Nomic API key' nomic_key
read_confirmed_secret "$INGEST_ROLE" ingest_password
read_confirmed_secret "$RETRIEVAL_ROLE" retrieval_password
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
export ISHIKAWA_POSTGRESQL_INGEST_PASSWORD="$ingest_password"
emit 'milestone=runtime_credentials;state=accepted;credential_values_retained=false'

ingest_password_sql="$(escape_sql_literal "$ingest_password")"
retrieval_password_sql="$(escape_sql_literal "$retrieval_password")"
if ! {
  printf '%s\n' \
    'SET standard_conforming_strings = on;' \
    'BEGIN;' \
    "CREATE ROLE $OWNER_ROLE NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;" \
    "CREATE ROLE $INGEST_ROLE LOGIN PASSWORD '$ingest_password_sql' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;" \
    "CREATE ROLE $RETRIEVAL_ROLE LOGIN PASSWORD '$retrieval_password_sql' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;" \
    'COMMIT;'
} | sudo -n -u postgres psql -X -q -v ON_ERROR_STOP=1 -d postgres \
  >"$work_root/role-create.stdout" 2>"$work_root/role-create.stderr"; then
  block 'application_role_creation_failed'
fi
roles_created=true
ingest_password_sql=''
retrieval_password_sql=''

printf "CREATE DATABASE %s WITH OWNER %s ENCODING 'UTF8' TEMPLATE template0;\n" "$DATABASE_NAME" "$OWNER_ROLE" \
  | sudo -n -u postgres psql -X -q -v ON_ERROR_STOP=1 -d postgres \
    >"$work_root/database-create.stdout" 2>"$work_root/database-create.stderr" \
  || block 'application_database_creation_failed'
database_created=true

printf '%s\n' \
  "REVOKE ALL ON DATABASE $DATABASE_NAME FROM PUBLIC;" \
  "GRANT CONNECT ON DATABASE $DATABASE_NAME TO $INGEST_ROLE, $RETRIEVAL_ROLE;" \
  "ALTER ROLE $RETRIEVAL_ROLE IN DATABASE $DATABASE_NAME SET default_transaction_read_only = on;" \
  | sudo -n -u postgres psql -X -q -v ON_ERROR_STOP=1 -d postgres \
    >"$work_root/database-access.stdout" 2>"$work_root/database-access.stderr" \
  || block 'application_database_access_configuration_failed'

printf '%s\n' 'CREATE EXTENSION vector;' 'REVOKE CREATE ON SCHEMA public FROM PUBLIC;' \
  | sudo -n -u postgres psql -X -q -v ON_ERROR_STOP=1 -d "$DATABASE_NAME" \
    >"$work_root/extension-create.stdout" 2>"$work_root/extension-create.stderr" \
  || block 'vector_extension_creation_failed'

sudo -n -u postgres psql \
  -X -q -v ON_ERROR_STOP=1 \
  -v "owner_role=$OWNER_ROLE" \
  -v "ingest_role=$INGEST_ROLE" \
  -v "retrieval_role=$RETRIEVAL_ROLE" \
  -v "schema_sha256=$SCHEMA_SHA256" \
  -d "$DATABASE_NAME" \
  <"$SCHEMA_PATH" \
  >"$work_root/schema-install.stdout" 2>"$work_root/schema-install.stderr" \
  || block 'final_schema_installation_failed'

schema_contract="$(sudo -n -u postgres psql -X -q -A -t -d "$DATABASE_NAME" -v ON_ERROR_STOP=1 \
  -c "SELECT concat_ws('|',
      (SELECT count(*) FROM rag.schema_migrations),
      (SELECT max(schema_version) FROM rag.schema_migrations),
      (SELECT migration_sha256 FROM rag.schema_migrations WHERE schema_version = 4),
      (SELECT extversion FROM pg_extension WHERE extname = 'vector'));" \
  2>"$work_root/schema-verify.stderr")" || block 'final_schema_verification_failed'
[[ "$schema_contract" == "1|4|$SCHEMA_SHA256|$PGVECTOR_EXTENSION_VERSION" ]] || block 'final_schema_contract_mismatch'
emit "milestone=final_database_schema;state=pass;schema_version=4;schema_sha256=$SCHEMA_SHA256;vector_version=$PGVECTOR_EXTENSION_VERSION;consolidated_baseline_rows=1"

export ISHIKAWA_LOCAL_INGESTION_REPORT_ROOT="$work_root/operator-reports"
export ISHIKAWA_LOCAL_INGESTION_WORK_ROOT="$work_root/producer-work"
export ISHIKAWA_LOCAL_INGESTION_ARTIFACT_ROOT="$work_root/artifacts"

validate_output="$work_root/ingestion-validate.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$INGESTION_RUNNER" --mode validate-only \
  >"$validate_output" 2>"$work_root/ingestion-validate.stderr" \
  || block 'ingestion_validation_failed'
grep -Fxq 'outcome=PASS' "$validate_output" || block 'ingestion_validation_outcome_invalid'
grep -Fxq 'actions=add:6,reprocess:0,retire:0,reuse:0,revise:0' "$validate_output" \
  || block 'ingestion_validation_plan_invalid'
grep -Fxq 'ishikawa_ingestion=pass;exit_code=0' "$validate_output" \
  || block 'ingestion_validation_marker_absent'
emit 'milestone=synthetic_ingestion_validation;state=pass;documents=6;actions=add:6'

publish_output="$work_root/ingestion-publish.txt"
publish_stderr="$work_root/ingestion-publish.stderr"
if PYTHONDONTWRITEBYTECODE=1 python3 -B "$INGESTION_RUNNER" --mode publish \
    >"$publish_output" 2>"$publish_stderr"; then
  publish_exit_code=0
else
  publish_exit_code=$?
fi
if (( publish_exit_code != 0 )); then
  publish_failure_reason="$(sed -nE \
    's/^ishikawa_ingestion=blocked;reason=([a-z][a-z0-9_]{0,255})$/\1/p' \
    "$publish_output" | tail -n 1)"
  [[ -n "$publish_failure_reason" ]] || publish_failure_reason='unclassified_review_required'
  emit "milestone=synthetic_ingestion_publication;state=blocked;exit_code=$publish_exit_code;failure_reason=$publish_failure_reason;stdout_sha256=$(sha256sum "$publish_output" | awk '{print $1}');stderr_sha256=$(sha256sum "$publish_stderr" | awk '{print $1}');raw_output_retained=false"
  block "ingestion_publication_$publish_failure_reason"
fi
grep -Fxq 'outcome=PASS' "$publish_output" || block 'ingestion_publication_outcome_invalid'
grep -Fxq 'actions=add:6,reprocess:0,retire:0,reuse:0,revise:0' "$publish_output" \
  || block 'ingestion_publication_plan_invalid'
grep -Fxq 'mutation_performed=true' "$publish_output" || block 'ingestion_publication_not_committed'
grep -Fxq 'ishikawa_ingestion=pass;exit_code=0' "$publish_output" \
  || block 'ingestion_publication_marker_absent'

export PGPASSWORD="$retrieval_password"
retrieval_inventory="$(psql \
  -X -q -A -t \
  -h 127.0.0.1 -p 5432 \
  -U "$RETRIEVAL_ROLE" -d "$DATABASE_NAME" \
  -v ON_ERROR_STOP=1 \
  -c "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
      SELECT concat_ws('|',
        current_user,
        current_database(),
        (SELECT count(*) FROM rag_search.active_documents),
        (SELECT coalesce(sum(page_count), 0) FROM rag_search.active_documents),
        (SELECT count(*) FROM rag_search.active_chunks),
        (SELECT count(*) FROM rag_search.active_citations),
        (SELECT count(*) FROM rag_search.active_embeddings));
      ROLLBACK;" \
  2>"$work_root/retrieval-inventory.stderr")" || block 'retrieval_role_inventory_failed'
[[ "$retrieval_inventory" == 'rag_retrieval|rag_catalog|6|27|126|126|126' ]] \
  || block 'published_corpus_inventory_mismatch'

observed_identities="$(psql -X -q -A -t \
  -h 127.0.0.1 -p 5432 \
  -U "$RETRIEVAL_ROLE" -d "$DATABASE_NAME" \
  -v ON_ERROR_STOP=1 \
  -c "SELECT string_agg(document_key || '|' || source_digest, ';' ORDER BY document_key) FROM rag_search.active_documents;" \
  2>"$work_root/document-identity.stderr")" || block 'published_corpus_identity_query_failed'
unset PGPASSWORD
[[ "$observed_identities" == "$EXPECTED_DOCUMENT_IDENTITIES" ]] || block 'published_corpus_identity_mismatch'

artifact_file_count="$(find "$work_root/artifacts" -type f | awk 'END {print NR+0}')"
[[ "$artifact_file_count" == 3 ]] || block 'retained_artifact_count_invalid'
mkdir -p -- "$(dirname -- "$ACCEPTED_ARTIFACT_ROOT")"
[[ ! -e "$ACCEPTED_ARTIFACT_ROOT" && ! -L "$ACCEPTED_ARTIFACT_ROOT" ]] \
  || block 'accepted_artifact_path_exists'
mv -- "$work_root/artifacts" "$ACCEPTED_ARTIFACT_ROOT"
corpus_accepted=true
emit "milestone=synthetic_corpus_publication;state=pass;documents=6;pages=27;chunks=126;citations=126;embeddings=126;retained_artifacts=$artifact_file_count"
emit 'database_copy_performed=false;local_ingestion_performed=true;gemma_contact=false;nomic_contact=true;database_changed=true;service_enabled=false;postgresql_runtime=online'
emit 'credential_values_retained=false;raw_document_content_in_report=false;vectors_in_report=false'
emit "script_117_local_tuning_corpus=pass;next_gate=rerun_script_115_local_tuning_preflight;local_report=$report_path"

#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Build and atomically publish the synthetic corpus-v3 qualification transfer.
#
# Mental model:
#   Validate the tracked fixture, assemble it twice, require deterministic
#   archives, and publish the verified corpus independently from the application.
#
# Inputs or prerequisites:
#   The frozen 30-document fixture, its truth metadata, and the 60 frontier cases.
#
# Outputs or artifact lane:
#   local/artifacts/qualification-corpus-v3-current and an ignored local report.
#
# Usage:
#   bash ./deployment/scripts/03_export-qualification-corpus.sh --run

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly fixture_root="$repo_root/qualification/corpus-v3"
readonly frontier_cases="$repo_root/qualification/frontier/frontier-cases.json"
readonly artifact_root="$repo_root/local/artifacts"
readonly report_root="$repo_root/local/reports/qualification-corpus-export"
readonly current_root="$artifact_root/qualification-corpus-v3-current"
readonly bundle_name='qualification-corpus-v3'

mode="${1:-}"
stage='argument_validation'
report_path=''
work_root=''
publication_stage=''

result() { printf '\nSCRIPT RESULT\nscript_03_export_qualification_corpus=%s\n' "$1"; }
block() {
  local reason="$1" detail="$2" action="$3" payload
  local status="${4:-1}"
  trap - ERR
  payload="$(printf '%s\n' 'FAILURE DETAIL' "stage=$stage" "reason=$reason" \
    "detail=$detail" "operator_action=$action")"
  printf '%s\n' "$payload" >&2
  if [[ -n "$report_path" && -f "$report_path" && ! -L "$report_path" ]]; then
    printf '%s\n' "$payload" >>"$report_path"
    result blocked >>"$report_path"
  fi
  result blocked >&2
  exit "$status"
}
cleanup() {
  local status="$?"
  trap - ERR EXIT INT TERM
  [[ -z "$work_root" || "$work_root" != /tmp/qualification-corpus-export.* || ! -d "$work_root" ]] \
    || rm -rf -- "$work_root"
  [[ -z "$publication_stage" || "$publication_stage" != "$artifact_root"/.qualification-corpus-v3-current.* || ! -d "$publication_stage" ]] \
    || rm -rf -- "$publication_stage"
  exit "$status"
}
trap cleanup EXIT
trap 'stage=interrupted; block signal_interrupt "Corpus export was interrupted." "Review the retained report and rerun." 130' INT
trap 'stage=interrupted; block signal_termination "Corpus export received SIGTERM." "Review the retained report and rerun." 143' TERM
unexpected_error() {
  local status="$1" line="$2"
  trap - ERR
  block unexpected_command_failure \
    "An unhandled command failed at Script 03 line ${line} with exit code ${status}." \
    'Review the retained report; correct the complete failing stage before rerunning.' \
    "$status"
}
trap 'unexpected_error "$?" "$LINENO"' ERR

if [[ "$#" -ne 1 || ( "$mode" != --validate-only && "$mode" != --run ) ]]; then
  block exactly_one_supported_mode_required \
    'Use exactly one mode: --validate-only or --run.' \
    'Rerun with one supported mode.'
fi
stage='preflight'
for command_name in awk bash basename cmp cp date diff find grep gzip mkdir mktemp mv python3 rm sha256sum sort tar tee; do
  command -v "$command_name" >/dev/null 2>&1 \
    || block "command_missing_${command_name}" "Required command unavailable: ${command_name}." 'Restore the command and rerun.'
done
for file in "$fixture_root/corpus-truth.json" "$fixture_root/source-manifest.json" \
  "$fixture_root/document-keys.json" "$frontier_cases"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] \
    || block required_file_unsafe "Required corpus input is missing or unsafe: ${file}." 'Restore the tracked fixture and rerun.'
done
[[ -d "$fixture_root/source" && ! -L "$fixture_root/source" ]] \
  || block source_directory_unsafe 'The corpus source directory is missing or unsafe.' 'Restore the tracked fixture and rerun.'
find "$fixture_root" -type l -print -quit | grep -q . \
  && block fixture_symlink_found 'The qualification fixture contains a symbolic link.' 'Replace it with a reviewed regular file.'

if [[ "$mode" == --run ]]; then
  stage='report_setup'
  mkdir -p -- "$report_root" "$artifact_root/superseded"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  report_path="$(mktemp "$report_root/export_qualification_corpus_${timestamp}_XXXXXX.txt")"
  emit() {
    local message="$1" tag="${2:-READINESS}"
    printf '[%s] %s\n' "$tag" "$message" | tee -a "$report_path"
  }
  emit "report_path=$report_path;state=start" READINESS
  emit 'purpose=build_and_publish_independent_qualification_corpus_transfer' READINESS
  emit 'state=start;gate=fixture_contract' READINESS
fi

validate_output="$(PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$fixture_root" "$frontier_cases" validate 2>&1 <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

root, frontier_path, _mode = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
truth = json.loads((root / "corpus-truth.json").read_text(encoding="utf-8"))
sources = json.loads((root / "source-manifest.json").read_text(encoding="utf-8"))
keys = json.loads((root / "document-keys.json").read_text(encoding="utf-8"))
frontier = json.loads(frontier_path.read_text(encoding="utf-8"))
documents = truth.get("documents")
relationships = truth.get("relationships")
source_files = sources.get("files")
expected_ids = [f"SYN-V3-{index:03d}" for index in range(1, 31)]
assert truth.get("corpus_identity") == "synthetic-corpus-v3"
assert isinstance(documents, list) and [item.get("doc_id") for item in documents] == expected_ids
assert sum(item.get("pages", 0) for item in documents) == 150
assert isinstance(relationships, list) and len(relationships) == 90
assert isinstance(source_files, list) and [item.get("doc_id") for item in source_files] == expected_ids
assert list(keys) == expected_ids and len(set(keys.values())) == 30
assert all(re.fullmatch(r"[a-z0-9]+(?:[._-][a-z0-9]+)*", value) for value in keys.values())
assert frontier.get("corpus_identity") == "synthetic-corpus-v3"
assert frontier.get("gate_profile") == "frontier_60"
assert isinstance(frontier.get("cases"), list) and len(frontier["cases"]) == 60
manifest_names = set()
for record in source_files:
    name = record.get("filename")
    path = root / "source" / str(name)
    assert isinstance(name, str) and path.is_file() and not path.is_symlink()
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest == record.get("sha256") and path.stat().st_size == record.get("bytes")
    manifest_names.add(name)
assert manifest_names == {path.name for path in (root / "source").glob("*.pdf")}
print("fixture_validation=pass;documents=30;pages=150;relationships=90;frontier_cases=60")
PY
)" || block fixture_contract_invalid "$validate_output" 'Correct every reported corpus fixture mismatch before export.'
if [[ "$mode" == --run ]]; then
  emit "state=pass;${validate_output}" READINESS
fi

if [[ "$mode" == --validate-only ]]; then
  printf '%s\n' \
    'purpose=validate_independent_qualification_corpus_export' \
    "$validate_output" \
    'application_build_dependency=false;remote_contact=false;database_contact=false;model_contact=false'
  result ready
  exit 0
fi

work_root="$(mktemp -d /tmp/qualification-corpus-export.XXXXXX)"
emit 'authorized_actions=read_tracked_synthetic_fixture_assemble_verify_and_publish_local_transfer' READINESS
emit 'non_actions=no_application_build_no_remote_contact_no_database_contact_no_model_contact_no_service_change' READINESS

assemble() {
  local destination="$1"
  mkdir -p -- "$destination/source"
  cp -- "$fixture_root"/source/*.pdf "$destination/source/"
  cp -- "$fixture_root/corpus-truth.json" "$destination/corpus-truth.json"
  cp -- "$fixture_root/source-manifest.json" "$destination/source-manifest.json"
  cp -- "$fixture_root/document-keys.json" "$destination/document-keys.json"
  cp -- "$frontier_cases" "$destination/frontier-cases.json"
  PYTHONDONTWRITEBYTECODE=1 python3 -B - "$destination" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
receipt = {
    "application_release_dependency": False,
    "configuration_generation": "target_per_ingestion_run",
    "corpus_identity": "synthetic-corpus-v3",
    "document_count": 30,
    "frontier_case_count": 60,
    "generated_configuration": ["document_catalog.yaml", "ingestion_manifest.yaml"],
    "page_count": 150,
    "persistent_flat_file_index": False,
    "purpose": "independent_qualification_corpus_transfer",
    "relationship_count": 90,
    "runtime_source_of_truth": "PostgreSQL after ingestion",
    "schema_version": 1,
}
(root / "transfer.json").write_text(json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
(root / "README.md").write_text(
    "# Qualification corpus v3 transfer\n\n"
    "This checksum-bound synthetic fixture is independent of the Ishikawa application release. "
    "Its source PDFs and checksum-bound identity metadata are inputs to target-side chunking and ingestion. "
    "The document catalog and ingestion manifest are generated anew on the target for every ingestion run. "
    "PostgreSQL is the runtime source of truth; this bundle is not a runtime retrieval index.\n",
    encoding="utf-8",
)
paths = sorted(path for path in root.rglob("*") if path.is_file() and path.name != "SHA256SUMS")
(root / "SHA256SUMS").write_text(
    "".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(root).as_posix()}\n" for path in paths),
    encoding="utf-8",
)
PY
}

stage='deterministic_assembly'
emit 'state=start;builds=2' BUILD
mkdir -p -- "$work_root/a" "$work_root/b"
assemble "$work_root/a/$bundle_name"
assemble "$work_root/b/$bundle_name"
diff -qr "$work_root/a/$bundle_name" "$work_root/b/$bundle_name" >/dev/null \
  || block deterministic_directory_mismatch 'Two corpus assemblies differed.' 'Remove nondeterministic input and rerun.'
for build in a b; do
  (cd -- "$work_root/$build/$bundle_name" && sha256sum --check --strict SHA256SUMS >/dev/null) \
    || block bundle_checksum_failed 'An assembled corpus transfer failed checksum verification.' 'Inspect the fixture and rerun.'
  tar --sort=name --format=posix --mtime='UTC 2026-10-24' --owner=0 --group=0 --numeric-owner \
    --pax-option=delete=atime,delete=ctime -C "$work_root/$build" -cf - "$bundle_name" \
    | gzip -n >"$work_root/$bundle_name-$build.tar.gz"
done
cmp -s "$work_root/$bundle_name-a.tar.gz" "$work_root/$bundle_name-b.tar.gz" \
  || block deterministic_archive_mismatch 'Two corpus archives differed.' 'Remove nondeterministic archive metadata and rerun.'
archive="$work_root/$bundle_name-a.tar.gz"
archive_sha256="$(sha256sum -- "$archive" | awk '{print $1}')"
emit "state=pass;archive_sha256=$archive_sha256" BUILD

stage='publication'
emit 'state=start' PUBLISH
publication_stage="$artifact_root/.qualification-corpus-v3-current.${timestamp}.$$"
mkdir -p -- "$publication_stage"
cp -- "$archive" "$publication_stage/$bundle_name.tar.gz"
(cd -- "$publication_stage" && sha256sum "$bundle_name.tar.gz" >"$bundle_name.tar.gz.sha256")
(cd -- "$publication_stage" && sha256sum --check --strict "$bundle_name.tar.gz.sha256" >/dev/null) \
  || block publication_checksum_failed 'The staged transfer failed checksum verification.' 'Do not publish the transfer.'
backup=''
if [[ -e "$current_root" || -L "$current_root" ]]; then
  [[ -d "$current_root" && ! -L "$current_root" ]] \
    || block current_handoff_unsafe 'The current corpus handoff is not a regular directory.' 'Inspect it before publication.'
  backup="$artifact_root/superseded/qualification-corpus-v3-current-$timestamp"
  [[ ! -e "$backup" && ! -L "$backup" ]] \
    || block backup_exists 'The selected superseded path already exists.' 'Inspect the retained handoffs.'
  mv -- "$current_root" "$backup"
fi
if ! mv -- "$publication_stage" "$current_root"; then
  [[ -z "$backup" ]] || mv -- "$backup" "$current_root"
  block publication_failed 'The transfer could not be atomically published.' 'Inspect local filesystem state and rerun.'
fi
publication_stage=''
(cd -- "$current_root" && sha256sum --check --strict "$bundle_name.tar.gz.sha256" >/dev/null) \
  || block published_checksum_failed 'The published transfer failed verification.' 'Stop and inspect the current handoff.'
emit "state=pass;corpus_current=$current_root" PUBLISH
emit "corpus_archive_sha256=$archive_sha256;application_build_dependency=false;runtime_flat_file_index=false" SUMMARY
emit "local_report=$report_path;next_gate=script_04_side_by_side_candidate_stage" SUMMARY
result pass | tee -a "$report_path"

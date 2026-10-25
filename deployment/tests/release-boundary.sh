#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Prove the v1.3 application and corpus-v3 qualification handoffs are separate.
#
# Mental model:
#   Run both validate-only interfaces, inspect their source-level boundaries,
#   and verify any published corpus handoff without changing it.
#
# Inputs or prerequisites:
#   Tracked deployment scripts and any already-published local handoffs.
#
# Outputs or artifact lane:
#   Terminal-only pass/block result; no target or runtime mutation.
#
# Usage:
#   bash ./deployment/tests/release-boundary.sh

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly release_builder="$repo_root/deployment/scripts/01_build-ishikawa-release.sh"
readonly corpus_exporter="$repo_root/deployment/scripts/03_export-qualification-corpus.sh"
readonly release_verifier="$repo_root/deployment/assets/verify-ishikawa-release"
readonly corpus_handoff="$repo_root/local/artifacts/qualification-corpus-v3-current"
readonly application_handoff="$repo_root/local/artifacts/ishikawa-v1.3-current"
readonly source_manifest="$repo_root/docs/releases/ISHIKAWA_V1_3_SOURCE_SHA256SUMS"
readonly application_archive="$application_handoff/ishikawa-v1.3.tar.gz"

fail() {
  printf '\nSCRIPT RESULT\nrelease_boundary_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

for file in "$release_builder" "$corpus_exporter" "$release_verifier" "$source_manifest"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || fail required_file_unsafe
done
bash -n "$release_builder" "$corpus_exporter" "$release_verifier" \
  || fail shell_syntax_invalid

release_validation="$(bash "$release_builder" --validate-only 2>&1)" \
  || fail release_validation_failed
grep -Fxq 'script_01_build_ishikawa_release=ready' <<<"$release_validation" \
  || fail release_ready_marker_missing
grep -Fq 'source_documents=0;corpus_dependency=false' <<<"$release_validation" \
  || fail release_independence_marker_missing

corpus_validation="$(bash "$corpus_exporter" --validate-only 2>&1)" \
  || fail corpus_validation_failed
grep -Fxq 'script_03_export_qualification_corpus=ready' <<<"$corpus_validation" \
  || fail corpus_ready_marker_missing
grep -Fq 'application_build_dependency=false' <<<"$corpus_validation" \
  || fail corpus_independence_marker_missing

if grep -Eq 'qualification/corpus-v3|corpus_root|ishikawa-corpus|synthetic-corpus-v3-current' "$release_builder"; then
  fail application_builder_contains_corpus_dependency
fi
grep -Fq "readonly application_current=\"\$artifact_root/ishikawa-v1.3-current\"" "$release_builder" \
  || fail application_handoff_name_invalid
grep -Fq "readonly bundle_name='ishikawa-v1.3'" "$release_builder" \
  || fail application_archive_name_invalid
grep -Fq '"release_name": "Ishikawa v1.3"' "$release_builder" \
  || fail application_release_identity_invalid

if [[ -d "$application_handoff" && ! -L "$application_handoff" ]]; then
  application_sidecar="$application_archive.sha256"
  [[ -f "$application_archive" && ! -L "$application_archive" \
      && -f "$application_sidecar" && ! -L "$application_sidecar" ]] \
    || fail application_handoff_incomplete
  (cd -- "$application_handoff" \
    && sha256sum --check --strict "$(basename -- "$application_sidecar")" >/dev/null) \
    || fail application_handoff_checksum_failed
  current_source_manifest_sha256="$(sha256sum -- "$source_manifest" | awk '{print $1}')"
  packaged_source_manifest_sha256="$(
    tar -xOf "$application_archive" ishikawa-v1.3/release.json \
      | python3 -c 'import json, sys; print(json.load(sys.stdin)["source_manifest_sha256"])'
  )" || fail application_release_record_invalid
  [[ "$packaged_source_manifest_sha256" == "$current_source_manifest_sha256" ]] \
    || fail application_handoff_source_identity_stale
  expected_yaml_inventory="$(printf '%s\n' \
    ishikawa-v1.3/application/payload/config/api_profile.yaml \
    ishikawa-v1.3/application/payload/config/deployment.yaml \
    ishikawa-v1.3/application/payload/config/document_catalog.yaml \
    ishikawa-v1.3/application/payload/config/document_classes.yaml \
    ishikawa-v1.3/application/payload/config/examples/document_catalog.yaml \
    ishikawa-v1.3/application/payload/config/examples/ingestion_manifest.yaml \
    ishikawa-v1.3/application/payload/config/ingestion_dependencies.yaml \
    ishikawa-v1.3/application/payload/config/injection_profile.yaml \
    ishikawa-v1.3/application/payload/config/logging_profile.yaml \
    ishikawa-v1.3/application/payload/config/method_profile.yaml \
    ishikawa-v1.3/application/payload/config/product.yaml \
    ishikawa-v1.3/application/payload/config/query_resolution_profile.yaml \
    ishikawa-v1.3/application/payload/config/reconstruction_profile.yaml \
    ishikawa-v1.3/application/payload/config/relationship_types.yaml \
    ishikawa-v1.3/application/payload/config/relevance_profile.yaml \
    ishikawa-v1.3/application/payload/config/retrieval_service_profile.yaml \
    ishikawa-v1.3/application/payload/config/runtime_dependencies.yaml \
    ishikawa-v1.3/application/payload/config/scope_profile.yaml \
    ishikawa-v1.3/application/payload/config/sufficiency_profile.yaml)"
  actual_yaml_inventory="$(tar -tzf "$application_archive" | grep -E '\.yaml$' | sort)"
  [[ "$actual_yaml_inventory" == "$expected_yaml_inventory" ]] \
    || fail application_yaml_inventory_mismatch
fi

if [[ -d "$corpus_handoff" && ! -L "$corpus_handoff" ]]; then
  archive="$corpus_handoff/qualification-corpus-v3.tar.gz"
  sidecar="$archive.sha256"
  [[ -f "$archive" && ! -L "$archive" && -f "$sidecar" && ! -L "$sidecar" ]] \
    || fail corpus_handoff_incomplete
  (cd -- "$corpus_handoff" && sha256sum --check --strict "$(basename -- "$sidecar")" >/dev/null) \
    || fail corpus_handoff_checksum_failed
  tar -tzf "$archive" | grep -Fxq 'qualification-corpus-v3/transfer.json' \
    || fail corpus_transfer_receipt_missing
  if tar -tzf "$archive" | grep -Eq 'qualification-corpus-v3/config/|document_catalog\.yaml|ingestion_manifest\.yaml'; then
    fail corpus_handoff_contains_prebuilt_ingestion_configuration
  fi
  tar -xOf "$archive" qualification-corpus-v3/transfer.json \
    | grep -Fq '"configuration_generation":"target_per_ingestion_run"' \
    || fail corpus_target_configuration_contract_missing
  if tar -tzf "$archive" | grep -Eq '/application/|install-ishikawa|ishikawa-v1\.3'; then
    fail corpus_handoff_contains_application
  fi
fi

printf '%s\n' \
  'release_identity=Ishikawa_v1.3;application_handoff=ishikawa-v1.3-current;corpus_dependency=false' \
  'qualification_transfer=qualification-corpus-v3-current;application_dependency=false;runtime_flat_file_index=false'
printf '\nSCRIPT RESULT\nrelease_boundary_test=pass\n'

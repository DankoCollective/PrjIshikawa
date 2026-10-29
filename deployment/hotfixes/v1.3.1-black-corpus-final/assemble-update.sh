#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Assemble the final update from the audited repository source.
# Mental model:
#   Copy exactly seven reviewed files, bind their accepted input identities and
#   final payload identities in one manifest, bind that manifest and verifier
#   into the operator entry point, then create one deterministic archive.
# Usage:
#   bash ./assemble-update.sh OUTPUT_DIRECTORY

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../../.." && pwd -P)"
readonly source_root="$repo_root/Ishikawa"
readonly output_directory="${1:-}"
readonly update_name='ishikawa-v1.3.1-cumulative-update'
readonly archive_name="$update_name.tar.gz"

fail() {
  printf '\nSCRIPT RESULT\nishikawa_v1_3_1_cumulative_update_assembly=blocked;reason=%s\n' "$1" >&2
  exit 1
}

[[ -n "$output_directory" && "$output_directory" == /* ]] \
  || fail output_directory_invalid
for command_name in awk find install mkdir mktemp python3 sed sha256sum sort tar; do
  command -v "$command_name" >/dev/null 2>&1 || fail required_command_missing
done
[[ -d "$source_root" && ! -L "$source_root" ]] || fail source_root_unsafe
mkdir -p -- "$output_directory"
[[ -d "$output_directory" && ! -L "$output_directory" ]] || fail output_directory_unsafe

workspace="$(mktemp -d /tmp/ishikawa-final-update-assembly.XXXXXX)"
cleanup() {
  local status=$?
  trap - EXIT
  [[ "$workspace" == /tmp/ishikawa-final-update-assembly.* && -d "$workspace" ]] \
    && rm -rf -- "$workspace"
  exit "$status"
}
trap cleanup EXIT

bundle="$workspace/$update_name"
mkdir -p -- "$bundle/payload/scripts" "$bundle/payload/application/python/ishikawa"
install -m 0644 -- "$script_dir/README.md" "$bundle/README.md"
install -m 0644 -- "$script_dir/verify-update.py" "$bundle/verify-update.py"

declare -a rows=(
  'scripts/capture-pdf-extraction-observations.py|0755|2d0cd7552ce76bc5bc4f8a26902b25dab62daf52e58ae2a3bfdffee9e7165356,85d884e319072d3b43c78e02115cdad6e2a0f50f53748c849ab1d3b7a7b58341'
  'application/python/ishikawa/document_control.py|0644|fa596dbcb7a17883076de4ccb0470216e0ec7e8e253f127f5613aac678783b99,2da688f87edf3acdd39214720fe9e42c18259899121e59a95c95cbb93326e9f8'
  'application/python/ishikawa/document_footer.py|0644|113350e53490e6984f4f05289be6f5d2bfb463f172f064ba94eee96db8825c58,58c7fd2ed773e8e68fa0d5c97e32928e2540f473312d0849e9304165c00a7119'
  'application/python/ishikawa/normalization.py|0644|1635eec4bf63b183e9eb6fc12eb0561f38863d055519f0f976ebb24730f6aedd'
  'application/python/ishikawa/artifact_pipeline.py|0644|03825cf81ca9debf7fda49e421429a09ff4f963316603cbbded73222b9463b66'
  'application/python/ishikawa/live_document_stage.py|0644|38fc3efb30fef8c83c5afbc818d0a25ce7af9eda8b439ffa3d1a1a9d08a85232'
  'application/python/ishikawa/installed_ingestion.py|0644|884b02cfcefd22ab5ff48d8f4438037b33e926404401af0f9a170a607ecc4ed8'
)

: >"$bundle/UPDATE_MANIFEST.tsv"
for row in "${rows[@]}"; do
  IFS='|' read -r relative file_mode accepted_values <<<"$row"
  source_file="$source_root/$relative"
  payload_file="$bundle/payload/$relative"
  [[ -f "$source_file" && ! -L "$source_file" ]] || fail source_file_unsafe
  mkdir -p -- "$(dirname -- "$payload_file")"
  install -m "$file_mode" -- "$source_file" "$payload_file"
  final_sha="$(sha256sum -- "$payload_file" | awk '{print $1}')"
  printf '%s\t%s\t%s,%s\t%s\n' \
    "$relative" "$file_mode" "$accepted_values" "$final_sha" "$final_sha" \
    >>"$bundle/UPDATE_MANIFEST.tsv"
done

manifest_sha="$(sha256sum -- "$bundle/UPDATE_MANIFEST.tsv" | awk '{print $1}')"
verifier_sha="$(sha256sum -- "$bundle/verify-update.py" | awk '{print $1}')"
sed -e "s/__MANIFEST_SHA256__/$manifest_sha/" \
    -e "s/__VERIFIER_SHA256__/$verifier_sha/" \
    "$script_dir/apply-update.in" >"$bundle/apply-update"
chmod 0755 "$bundle/apply-update"

(
  cd -- "$bundle"
  while IFS= read -r relative; do
    sha256sum -- "$relative"
  done < <(find . -type f ! -name SHA256SUMS -printf '%P\n' | sort) >SHA256SUMS
  sha256sum --check --strict SHA256SUMS >/dev/null
)

temporary_archive="$workspace/$archive_name"
tar --sort=name --mtime='UTC 2026-10-28' --owner=0 --group=0 --numeric-owner \
  -czf "$temporary_archive" -C "$workspace" \
  "$update_name"
install -m 0644 -- "$temporary_archive" "$output_directory/$archive_name"
(
  cd -- "$output_directory"
  sha256sum -- "$archive_name" >"$archive_name.sha256"
  sha256sum --check --strict "$archive_name.sha256" >/dev/null
)

printf '%s\n' \
  "archive=$output_directory/$archive_name" \
  "archive_sha256=$(sha256sum -- "$output_directory/$archive_name" | awk '{print $1}')"
printf '\nSCRIPT RESULT\nishikawa_v1_3_1_cumulative_update_assembly=pass\n'

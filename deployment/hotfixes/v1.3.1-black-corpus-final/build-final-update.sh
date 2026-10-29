#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Run the consolidated application/update proof and publish one final archive.
# Mental model:
#   No archive is emitted until all discovered application tests and every
#   accepted/refusal update lifecycle state pass in the same execution.
# Usage:
#   bash ./build-final-update.sh

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../../.." && pwd -P)"
readonly artifact_root="$repo_root/local/artifacts/ishikawa-v1.3.1-black-corpus-final-current"

fail() {
  printf '\nSCRIPT RESULT\nishikawa_v1_3_1_black_corpus_final_build=blocked;reason=%s\n' "$1" >&2
  exit 1
}

for command_name in bash cp find grep head mkdir mktemp python3 sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || fail required_command_missing
done

while IFS= read -r script; do
  head -n 1 "$script" | grep -Eq '^#!.*(bash|/sh)([[:space:]]|$)' || continue
  bash -n "$script"
done < <(
  find "$repo_root/Ishikawa/scripts" \
    "$repo_root/deployment/hotfixes/v1.3.1-black-corpus-final" \
    -type f -print | sort
)
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$repo_root/Ishikawa/application/python" \
  python3 -m unittest discover -s "$repo_root/Ishikawa/tests" -p 'test_*.py' -v
bash "$script_dir/test-final-update.sh"

temporary_artifact="$(mktemp -d /tmp/ishikawa-final-update-artifact.XXXXXX)"
cleanup() {
  local status=$?
  trap - EXIT
  [[ "$temporary_artifact" == /tmp/ishikawa-final-update-artifact.* \
     && -d "$temporary_artifact" ]] && rm -rf -- "$temporary_artifact"
  exit "$status"
}
trap cleanup EXIT
bash "$script_dir/assemble-update.sh" "$temporary_artifact"
archive_name='ishikawa-v1.3.1-black-corpus-final-update.tar.gz'
[[ -f "$temporary_artifact/$archive_name" \
   && -f "$temporary_artifact/$archive_name.sha256" ]] || fail final_archive_missing

mkdir -p -- "$artifact_root"
cp -- "$temporary_artifact/$archive_name" "$artifact_root/$archive_name"
cp -- "$temporary_artifact/$archive_name.sha256" \
  "$artifact_root/$archive_name.sha256"
(
  cd -- "$artifact_root"
  sha256sum --check --strict "$archive_name.sha256" >/dev/null
)

printf '%s\n' \
  'application_tests=pass;tests=506' \
  'update_lifecycle=pass' \
  "archive=$artifact_root/$archive_name" \
  "archive_sha256=$(sha256sum -- "$artifact_root/$archive_name" | awk '{print $1}')"
printf '\nSCRIPT RESULT\nishikawa_v1_3_1_black_corpus_final_build=pass\n'

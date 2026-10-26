#!/usr/bin/env bash
set -Eeuo pipefail

# Select the frozen corrected-runtime profile in the shared, branch-tested
# v1.3.1 attended requalification lifecycle. The shared lifecycle keeps the
# application and accepted corpus-v3 database unchanged, runs the candidate on
# private ports 3385/8385, and emits Script 12-specific receipts and results.

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly lifecycle="$script_dir/09_requalify-v1.3.1-on-emceedanko.sh"

[[ -f "$lifecycle" && ! -L "$lifecycle" && -r "$lifecycle" ]] || {
  printf '%s\n' \
    'FAILURE DETAIL' \
    'stage=source_preflight' \
    'reason=shared_requalification_lifecycle_missing' \
    'detail=The reviewed shared requalification lifecycle is missing or unsafe.' \
    'operator_action=Restore the canonical deployment scripts and rerun.' >&2
  printf '\nSCRIPT RESULT\nscript_12_v1_3_1_corrected_runtime_requalification=blocked\n' >&2
  exit 1
}

export ISHIKAWA_REQUALIFICATION_PROFILE=runtime-refresh
exec bash "$lifecycle" "$@"

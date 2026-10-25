#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Freeze the exact accepted Ishikawa v1 package and its observed retrieval
#   baseline as the immutable fallback boundary before v1.1 tuning begins.
#
# Mental model:
#   Reverify the already-accepted v1 package, its release receipt, and the
#   read-only Script 112 baseline. Retain one small checkpoint receipt that
#   names their exact hashes. Do not rebuild, copy, install, or modify v1.
#
# Inputs or prerequisites:
#   Clean accepted Script 109 and Script 112 evidence.
#
# Outputs:
#   One local content-free checkpoint receipt, checksum, and report. The
#   existing deployment archive remains the sole v1 fallback payload.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/113_freeze_ishikawa_v1_fallback_checkpoint.sh --run

usage() {
  sed -n '3,23p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Freeze and retain the v1 fallback checkpoint.' \
    '  --validate-only Validate the same boundary without retaining outputs.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"

readonly V1_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/v1-deployment-package/ishikawa-v1-deployment-package-c848680051786b2b.tar.gz"
readonly V1_ARCHIVE_CHECKSUM="$V1_ARCHIVE.sha256"
readonly V1_RELEASE_RECEIPT="$REPO_ROOT/local/artifacts/ishikawa/v1-release/ishikawa_v1_acceptance_20261021T042530Z.json"
readonly V1_RELEASE_CHECKSUM="$V1_RELEASE_RECEIPT.sha256"
readonly V1_RELEASE_REPORT="$REPO_ROOT/local/reports/ishikawa-v1-release/ishikawa_v1_acceptance_20261021T042530Z_XLvaNG.txt"
readonly BASELINE_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/retrieval-tuning-baseline/retrieval_tuning_baseline_20261021T134742Z.json"
readonly BASELINE_CHECKSUM="$BASELINE_ARTIFACT.sha256"
readonly BASELINE_REPORT="$REPO_ROOT/local/reports/ishikawa-retrieval-tuning-baseline/retrieval_tuning_baseline_20261021T134742Z_zz8Hjr.txt"

readonly V1_ARCHIVE_SHA256='c848680051786b2b3c6ac454b3f007be1632d45215ddf9c8f1d4d04b924845b1'
readonly V1_ARCHIVE_CHECKSUM_SHA256='25313c7065cfa038ba63f51deb29585e763aae0561c672057c28c86c5fe57550'
readonly V1_RELEASE_RECEIPT_SHA256='efb372190d179f3bcf32cec5a7f0d4acc725046ac4e1e253c26d7c4db3dcedf7'
readonly V1_RELEASE_CHECKSUM_SHA256='b342afdd95916c1046af17546ae33e1f1881ae5963c0701fc7dbcfb0bbc3802b'
readonly V1_RELEASE_REPORT_SHA256='c46b415edda072227bcce88f523565160268317e1608a8861e5598203305bf2c'
readonly BASELINE_ARTIFACT_SHA256='caa13083d68a2f02eb0c6deb2851febd5c54cfaf448a14979badffa6b86867dd'
readonly BASELINE_CHECKSUM_SHA256='3522fc4edaeca08b65a58939e20756c756d0fe2f051faa87051cfa50639b12f7'
readonly BASELINE_REPORT_SHA256='d7e00c7c83a793daea15c07ada4be120c154d631153c64e1eb4502c992b96d3e'

readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1-fallback-checkpoint"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1-fallback-checkpoint"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_113_v1_fallback_checkpoint=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_113_v1_fallback_checkpoint=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename chmod date dirname find grep mkdir mktemp python3 rm sed sha256sum stat tar tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_113_v1_fallback_checkpoint=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done

readonly -a INPUTS=(
  "$V1_ARCHIVE" "$V1_ARCHIVE_CHECKSUM"
  "$V1_RELEASE_RECEIPT" "$V1_RELEASE_CHECKSUM" "$V1_RELEASE_REPORT"
  "$BASELINE_ARTIFACT" "$BASELINE_CHECKSUM" "$BASELINE_REPORT"
)
for input in "${INPUTS[@]}"; do
  [[ -f "$input" && ! -L "$input" && -r "$input" ]] || {
    printf 'script_113_v1_fallback_checkpoint=blocked;reason=accepted_input_unsafe\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_113_v1_fallback_checkpoint=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_sha256 "$V1_ARCHIVE" "$V1_ARCHIVE_SHA256" v1_archive
check_sha256 "$V1_ARCHIVE_CHECKSUM" "$V1_ARCHIVE_CHECKSUM_SHA256" v1_archive_checksum
check_sha256 "$V1_RELEASE_RECEIPT" "$V1_RELEASE_RECEIPT_SHA256" v1_release_receipt
check_sha256 "$V1_RELEASE_CHECKSUM" "$V1_RELEASE_CHECKSUM_SHA256" v1_release_checksum
check_sha256 "$V1_RELEASE_REPORT" "$V1_RELEASE_REPORT_SHA256" v1_release_report
check_sha256 "$BASELINE_ARTIFACT" "$BASELINE_ARTIFACT_SHA256" baseline_artifact
check_sha256 "$BASELINE_CHECKSUM" "$BASELINE_CHECKSUM_SHA256" baseline_checksum
check_sha256 "$BASELINE_REPORT" "$BASELINE_REPORT_SHA256" baseline_report

for sidecar in "$V1_ARCHIVE_CHECKSUM" "$V1_RELEASE_CHECKSUM" "$BASELINE_CHECKSUM"; do
  (
    cd -- "$(dirname -- "$sidecar")"
    sha256sum --check --strict "$(basename -- "$sidecar")" >/dev/null
  ) || {
    printf 'script_113_v1_fallback_checkpoint=blocked;reason=accepted_checksum_failed\n' >&2
    exit 2
  }
done

for fact in \
  'package_rebuilt=false;package_duplicated=false;deployment_payload_portable=true;native_prerequisite_packages_included=false' \
  'script_109_v1_acceptance=pass;'; do
  grep -Fq "$fact" "$V1_RELEASE_REPORT" || {
    printf 'script_113_v1_fallback_checkpoint=blocked;reason=v1_release_contract_failed\n' >&2
    exit 2
  }
done
for fact in \
  'non_actions=no_sudo_no_stack_start_or_stop_no_configuration_change_no_database_write_no_service_change_no_package_change_no_port_forwarding_change_no_credential_read' \
  'retrieval_tuning_baseline=pass;cases=13;contract_valid=13;expected_status_matches=10;answered=4;nonanswered=9;sources=20;cited_sources=15;unused_sources=5;required_evidence=13;required_evidence_cited=6;maximum_elapsed_milliseconds=53008;total_elapsed_milliseconds=150225' \
  'milestone=live_baseline_capture;state=pass;runtime_changed=false;database_changed=false;service_changed=false' \
  'script_112_retrieval_tuning_baseline=pass;'; do
  grep -Fq "$fact" "$BASELINE_REPORT" || {
    printf 'script_113_v1_fallback_checkpoint=blocked;reason=baseline_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c '
import json
import pathlib
import sys

release = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
baseline = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
expected_archive = sys.argv[3]
assert release["release_name"] == "Ishikawa v1"
assert release["archive_sha256"] == expected_archive
assert release["host_qualification"] == "pass"
assert release["schema_version"] == 4
assert release["package_file_count"] == 104
assert release["package_rebuilt"] is False
assert baseline["artifact_kind"] == "ishikawa_retrieval_tuning_baseline"
assert baseline["schema_version"] == 1
assert baseline["synthetic_content_only"] is True
assert baseline["raw_synthetic_responses_retained"] is True
assert len(baseline["cases"]) == 13
assert baseline["summary"]["case_count"] == 13
assert baseline["summary"]["contract_valid_count"] == 13
print("release_and_baseline_contract=pass")
' "$V1_RELEASE_RECEIPT" "$BASELINE_ARTIFACT" "$V1_ARCHIVE_SHA256" \
  | grep -Fxq 'release_and_baseline_contract=pass' || {
  printf 'script_113_v1_fallback_checkpoint=blocked;reason=json_contract_failed\n' >&2
  exit 2
}

work_root="$(mktemp -d /tmp/ishikawa-script-113.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-113.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$work_root/extracted"
tar -xzf "$V1_ARCHIVE" -C "$work_root/extracted"
readonly BUNDLE_ROOT="$work_root/extracted/ishikawa-v1-deployment-package"
[[ -d "$BUNDLE_ROOT" && ! -L "$BUNDLE_ROOT" ]] || {
  printf 'script_113_v1_fallback_checkpoint=blocked;reason=bundle_root_invalid\n' >&2
  exit 1
}
bash "$BUNDLE_ROOT/verify-ishikawa-v1" | grep -Fxq \
  'ishikawa_v1_verification=pass;application=final;database_schema=version_4;historical_mutation_files=0' || {
  printf 'script_113_v1_fallback_checkpoint=blocked;reason=package_verification_failed\n' >&2
  exit 1
}
package_file_count="$(find "$BUNDLE_ROOT" -type f | awk 'END {print NR+0}')"
[[ "$package_file_count" == 104 ]] || {
  printf 'script_113_v1_fallback_checkpoint=blocked;reason=package_file_count_changed\n' >&2
  exit 1
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
archive_bytes="$(stat -c '%s' "$V1_ARCHIVE")"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_immutable_ishikawa_v1_fallback_checkpoint' \
    "script_sha256=$script_sha256;v1_archive_sha256=$V1_ARCHIVE_SHA256;v1_archive_bytes=$archive_bytes" \
    "v1_release_receipt_sha256=$V1_RELEASE_RECEIPT_SHA256;baseline_artifact_sha256=$BASELINE_ARTIFACT_SHA256" \
    'release_name=Ishikawa_v1;successor_release=Ishikawa_v1.1;package_files=104;schema_version=4' \
    'package_rebuilt=false;package_duplicated=false;tuning_code_applied=false;fallback_payload_verified=true' \
    'target_contact=false;database_changed=false;service_changed=false;model_contact=false' \
    'script_113_v1_fallback_checkpoint_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || {
  printf 'script_113_v1_fallback_checkpoint=blocked;reason=output_directory_unsafe\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/ishikawa_v1_fallback_checkpoint_${timestamp}.json"
artifact_checksum="$artifact_path.sha256"
report_path="$(mktemp "$REPORT_ROOT/ishikawa_v1_fallback_checkpoint_${timestamp}_XXXXXX.txt")"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$artifact_checksum" && ! -L "$artifact_checksum" ]] || {
  printf 'script_113_v1_fallback_checkpoint=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}

printf '{"baseline_artifact_sha256":"%s","checkpoint_kind":"immutable_fallback","fallback_archive_bytes":%s,"fallback_archive_sha256":"%s","fallback_payload_verified":true,"package_file_count":104,"package_rebuilt":false,"package_duplicated":false,"receipt_schema_version":1,"release_name":"Ishikawa v1","schema_version":4,"successor_release":"Ishikawa v1.1","tuning_code_applied":false,"v1_release_receipt_sha256":"%s"}\n' \
  "$BASELINE_ARTIFACT_SHA256" "$archive_bytes" "$V1_ARCHIVE_SHA256" "$V1_RELEASE_RECEIPT_SHA256" >"$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$artifact_checksum"
chmod 0600 "$artifact_path" "$artifact_checksum" 2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$artifact_checksum")" >/dev/null
) || {
  printf 'script_113_v1_fallback_checkpoint=blocked;reason=checkpoint_checksum_failed\n' >&2
  exit 1
}

{
  printf 'purpose=freeze_immutable_ishikawa_v1_fallback_before_v1_1_tuning\n'
  printf 'started_utc=%s\n' "$timestamp"
  printf 'script_sha256=%s;v1_archive_sha256=%s;v1_archive_bytes=%s\n' "$script_sha256" "$V1_ARCHIVE_SHA256" "$archive_bytes"
  printf 'v1_release_receipt_sha256=%s;v1_release_report_sha256=%s\n' "$V1_RELEASE_RECEIPT_SHA256" "$V1_RELEASE_REPORT_SHA256"
  printf 'baseline_artifact_sha256=%s;baseline_report_sha256=%s;baseline_cases=13\n' "$BASELINE_ARTIFACT_SHA256" "$BASELINE_REPORT_SHA256"
  printf 'release_name=Ishikawa_v1;release_state=immutable;successor_release=Ishikawa_v1.1\n'
  printf 'package_files=104;schema_version=4;fallback_payload_verified=true\n'
  printf 'package_rebuilt=false;package_duplicated=false;tuning_code_applied=false\n'
  printf 'target_contact=false;database_changed=false;service_changed=false;model_contact=false\n'
  printf 'checkpoint_artifact=%s;checkpoint_artifact_sha256=%s;checkpoint_checksum=%s\n' "$artifact_path" "$artifact_sha256" "$artifact_checksum"
  printf 'script_113_v1_fallback_checkpoint=pass;next_gate=implement_isolated_v1_1_query_routing_correction\n'
} | tee "$report_path"
chmod 0600 "$report_path" 2>/dev/null || true

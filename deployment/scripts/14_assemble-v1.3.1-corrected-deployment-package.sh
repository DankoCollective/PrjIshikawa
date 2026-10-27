#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Assemble the corrected Ishikawa v1.3.1 deployment-package candidate.
#
# Mental model:
#   Bind the unchanged application and corrected app-free runtime to completed
#   production qualification, promotion, UI acceptance, and security evidence.
#   Assemble one flat classified carry, verify it independently, and atomically
#   replace only the local non-installable candidate handoff.
#
# Inputs or prerequisites:
#   Exact Script 07/08 handoffs, complete Script 12/13 evidence, the exact
#   corrected Trivy report, and frozen V13-79 through V13-93 decisions.
#
# Outputs or artifact lane:
#   local/artifacts/ishikawa-deployment-v1.3.1-candidate-current/
#   local/reports/ishikawa-deployment-package-assembly/
#   No remote host, corpus, credential, service, listener, database, or boot
#   state is contacted or changed. Stable deployment-ready promotion is later.
#
# Usage:
#   bash ./deployment/scripts/14_assemble-v1.3.1-corrected-deployment-package.sh --validate-only
#   bash ./deployment/scripts/14_assemble-v1.3.1-corrected-deployment-package.sh --run

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly carry_source="$repo_root/deployment/carry"
readonly application_root="$repo_root/local/artifacts/ishikawa-v1.3.1-candidate-current"
readonly runtime_root="$repo_root/local/artifacts/node-next-runtime-current"
readonly qualification_root="$repo_root/local/artifacts/emceedanko-v1.3.1-runtime-requalification-current"
readonly promotion_root="$repo_root/local/artifacts/emceedanko-v1.3.1-corrected-runtime-promotion-current"
readonly security_record="$repo_root/deployment/evidence/ISHIKAWA_V1_3_1_SECURITY_REVIEW.md"
readonly security_scan="$repo_root/local/reports/ishikawa-v1.3.1-security-review/runtime-vulnerabilities-trivy-0.76.1-corrected-20261026.json"
readonly native_inventory="$carry_source/inspect-native-prerequisites"
readonly decision_record="$repo_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md"
readonly artifact_parent="$repo_root/local/artifacts"
readonly artifact_current="$artifact_parent/ishikawa-deployment-v1.3.1-candidate-current"
readonly report_root="$repo_root/local/reports/ishikawa-deployment-package-assembly"
readonly expected_application_sha256='2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69'
readonly expected_runtime_sha256='b92dd71eb155493d7e331e85c92566eee113ed4c8f0eda605c1c3dd951b836e1'
readonly expected_image_id='sha256:6c93bcb5ed22de92420c4de4892eecdd08f1badc8b19e4d6f4488711f8f7a31a'
readonly expected_config_digest='sha256:ccbae1b68ecf82121ce76080793cb7febdf1d6df1653995db02fc2f83233228f'
readonly expected_security_scan_sha256='ce251960fdc20726a73fa49cc4f417761ee90c392592a3a5d7eeb6dae540971c'
readonly capacity_margin_bytes=67108864

mode=''
current_stage='argument_validation'
report_path=''
assembly_stage=''
scan_root=''

usage() { sed -n '5,28p' "${BASH_SOURCE[0]}"; }

result() {
  printf '\nSCRIPT RESULT\nscript_14_ishikawa_v1_3_1_corrected_package_assembly=%s\n' "$1"
}

block() {
  local reason="$1" detail="$2" action="$3" status="${4:-1}" payload
  trap - ERR
  payload="$(printf '%s\n' 'FAILURE DETAIL' "stage=$current_stage" \
    "reason=$reason" "detail=$detail" "operator_action=$action" \
    'cleanup=automatic_on_exit')"
  printf '%s\n' "$payload" >&2
  if [[ -n "$report_path" && -f "$report_path" && ! -L "$report_path" ]]; then
    printf '%s\n' "$payload" >>"$report_path"
    result blocked >>"$report_path"
  fi
  result blocked >&2
  exit "$status"
}

unexpected_error() {
  local status="$1" line="$2"
  block unexpected_command_failure \
    "Unhandled failure at corrected package assembler line $line with status $status." \
    'Review the retained report and correct the reported local condition.' "$status"
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ -n "$assembly_stage" \
      && "$assembly_stage" == "$artifact_parent"/.ishikawa-deployment-v1.3.1-candidate-current.* \
      && -d "$assembly_stage" && ! -L "$assembly_stage" ]]; then
    rm -rf -- "$assembly_stage"
  fi
  if [[ -n "$scan_root" && "$scan_root" == /tmp/ishikawa-carry-scan.* \
      && -d "$scan_root" && ! -L "$scan_root" ]]; then
    rm -rf -- "$scan_root"
  fi
  exit "$status"
}

copy_payload() {
  local source_path="$1" destination_path="$2"
  cp -- "$source_path" "$destination_path" \
    || block payload_copy_failed "Could not copy ${source_path##*/}." \
      'Correct local source readability or artifact storage and rerun.'
  [[ -f "$destination_path" && ! -L "$destination_path" ]] \
    || block copied_payload_invalid "Copied payload is missing or unsafe: ${destination_path##*/}." \
      'Inspect the local artifact filesystem and rerun.'
}

receipt_has_lines() {
  local receipt="$1"
  shift
  local expected_line
  [[ -f "$receipt" && ! -L "$receipt" ]] || return 1
  for expected_line in "$@"; do
    grep -Fxq "$expected_line" "$receipt" || return 1
  done
}

trap cleanup EXIT
trap 'unexpected_error "$?" "$LINENO"' ERR
trap 'current_stage=interrupted; block signal_hangup "Package assembly received SIGHUP." "Review the retained report and rerun." 129' HUP
trap 'current_stage=interrupted; block signal_interrupt "Package assembly was interrupted." "Review the retained report and rerun." 130' INT
trap 'current_stage=interrupted; block signal_termination "Package assembly received SIGTERM." "Review the retained report and rerun." 143' TERM

if [[ $# == 1 && ( "$1" == --help || "$1" == -h ) ]]; then usage; exit 0; fi
[[ $# == 1 && ( "$1" == --validate-only || "$1" == --run ) ]] \
  || { usage >&2; block exactly_one_supported_mode_required \
    'Use exactly one mode: --validate-only or --run.' 'Rerun with one supported mode.' 2; }
mode="$1"

current_stage='source_preflight'
for command_name in awk bash cmp cp date df find grep jq mkdir mktemp mv python3 rm \
  sha256sum sort stat tar tee; do
  command -v "$command_name" >/dev/null 2>&1 \
    || block "command_missing_${command_name}" \
      "Required local command unavailable: $command_name." 'Restore the named command and rerun.'
done
for source_file in README.md SECURITY_REVIEW.md deploy-ishikawa verify-deployment; do
  [[ -f "$carry_source/$source_file" && ! -L "$carry_source/$source_file" \
      && -r "$carry_source/$source_file" ]] \
    || block carry_source_unsafe "Carry source missing or unsafe: $source_file." \
      'Restore the reviewed canonical carry source and rerun.'
done
[[ -f "$native_inventory" && ! -L "$native_inventory" && -r "$native_inventory" ]] \
  || block native_inventory_source_unsafe \
    'The canonical native-prerequisite inventory command is missing or unsafe.' \
    'Restore the reviewed application payload source.'
bash -n "$carry_source/deploy-ishikawa" "$carry_source/verify-deployment" "$native_inventory" \
  || block carry_source_syntax_invalid 'A portable command failed shell parsing.' \
    'Correct the command before assembly.'
for decision in {79..93}; do
  decision_block="$(awk -v header="### V13-${decision} " '
    index($0, header) == 1 {capture=1}
    capture && /^### / && index($0, header) != 1 {exit}
    capture {print}
  ' "$decision_record")"
  [[ "$(grep -Ec '^Status: Frozen([. ]|$)' <<<"$decision_block")" == 1 ]] \
    || block "v13_${decision}_not_frozen" \
      "Required release decision V13-$decision is absent or not frozen." \
      'Reconcile the decision ledger before assembly.'
done

if [[ "$mode" == --validate-only ]]; then
  printf '%s\n' \
    'package_source=pass;decisions=V13-79_through_V13-93_frozen' \
    'primary_payloads=external_application_and_corrected_application_free_amd64_runtime' \
    'publication=candidate_only;stable_handoff=false;target_contact=false'
  result ready
  exit 0
fi

mkdir -p -- "$report_root" \
  || block report_directory_failed 'The package-assembly report directory could not be created.' \
    'Correct local report permissions and rerun.'
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/corrected_package_assembly_${timestamp}_XXXXXX.txt")" \
  || block report_creation_failed 'The package-assembly report could not be created.' \
    'Correct local report permissions and rerun.'
emit() { printf '[%s] %s\n' "$1" "$2" | tee -a "$report_path"; }
emit READINESS 'state=start;remote_contact=false;target_mutation=false;credential_access=false;corpus_access=false'

current_stage='input_verification'
emit INPUTS 'state=start;application=true;corrected_runtime=true;script12=true;script13=true;security=true'
for artifact_directory in "$application_root" "$runtime_root" "$qualification_root" "$promotion_root"; do
  [[ -d "$artifact_directory" && ! -L "$artifact_directory" ]] \
    || block required_handoff_missing "Required verified handoff absent: $artifact_directory." \
      'Restore the exact completed handoff before assembly.'
done
for artifact_directory in "$application_root" "$runtime_root" "$qualification_root" "$promotion_root"; do
  [[ -f "$artifact_directory/SHA256SUMS" && ! -L "$artifact_directory/SHA256SUMS" ]] \
    && (cd -- "$artifact_directory" && sha256sum --check --strict SHA256SUMS >/dev/null) \
    || block handoff_checksum_failed "Checksum verification failed for ${artifact_directory##*/}." \
      'Restore the exact accepted handoff before assembly.'
done

application_sha256="$(sha256sum -- "$application_root/ishikawa-v1.3.1.tar.gz" | awk '{print $1}')"
runtime_sha256="$(sha256sum -- "$runtime_root/node-next-runtime-amd64.tar" | awk '{print $1}')"
[[ "$application_sha256" == "$expected_application_sha256" ]] \
  || block application_identity_mismatch 'The application archive is not the accepted v1.3.1 archive.' \
    'Restore the exact Script 08 handoff.'
jq -e --arg archive "$expected_application_sha256" '
  .release == "Ishikawa v1.3.1 candidate"
  and .archive_sha256 == $archive
  and .coding_standard == "pass"
  and .deterministic_archive == true
  and .fresh_install == "pass"
  and .human_ui_validation == "pending_exact_candidate_requalification"
  and (.source_manifest_sha256 | test("^[0-9a-f]{64}$"))' \
  "$application_root/release-receipt.json" >/dev/null \
  || block application_receipt_invalid 'The source handoff receipt does not bind the exact clean application build.' \
    'Restore the exact Script 08 handoff.'
[[ "$runtime_sha256" == "$expected_runtime_sha256" ]] \
  || block runtime_identity_mismatch 'The runtime archive is not the accepted corrected archive.' \
    'Restore the corrected Script 07 handoff.'
jq -e --arg archive "$expected_runtime_sha256" --arg image "$expected_image_id" \
  --arg config "$expected_config_digest" '
  .schema == "node-next-runtime-image.v3"
  and .archive_sha256 == $archive and .image_id == $image and .config_digest == $config
  and .architecture == "amd64" and .platform == "linux/amd64"
  and .application_in_image == false and .generated_next_in_image == false
  and .runtime_npm == false and .runtime_yarn == false
  and .base_bundled_npm_executed == false and .base_bundled_yarn_executed == false
  and .build_npm == "11.21.1" and .tzdata == "2026e-0+deb12u1"' \
  "$runtime_root/image-identity.json" >/dev/null \
  || block runtime_identity_record_invalid 'The corrected runtime identity record is incomplete or mismatched.' \
    'Restore the exact corrected runtime handoff.'

receipt_has_lines "$qualification_root/qualification-receipt.txt" \
  "application_archive_sha256=$expected_application_sha256" \
  "runtime_archive_sha256=$expected_runtime_sha256" "image_id=$expected_image_id" \
  'production_build_start=pass' 'frontier_cases=60/60' \
  || block script12_qualification_invalid 'Script 12 qualification does not bind the exact payloads.' \
    'Restore complete Script 12 evidence.'
receipt_has_lines "$qualification_root/acceptance-receipt.txt" \
  "application_archive_sha256=$expected_application_sha256" \
  "runtime_archive_sha256=$expected_runtime_sha256" "image_id=$expected_image_id" \
  'human_ui_acceptance=accepted' 'production_build_start=pass' 'frontier_cases=60/60' \
  || block script12_acceptance_invalid 'Script 12 acceptance does not bind the exact payloads.' \
    'Restore complete Script 12 evidence.'
receipt_has_lines "$qualification_root/cleanup-receipt.txt" \
  'mode=cleanup' 'state=pass' 'detail=candidate_removed=true' \
  "image_id=$expected_image_id" \
  || block script12_cleanup_invalid 'Script 12 cleanup evidence is incomplete.' \
    'Restore complete Script 12 evidence.'
receipt_has_lines "$promotion_root/promotion-receipt.txt" \
  'schema=ishikawa.emceedanko-v1.3.1-runtime-promotion.v1' \
  "application_archive_sha256=$expected_application_sha256" \
  "runtime_archive_sha256=$expected_runtime_sha256" "image_id=$expected_image_id" \
  'production_build_start=pass' 'human_ui_acceptance=pending' \
  'application_mutated=false' 'database_mutated=false' 'boot_autostart=false' \
  || block script13_promotion_invalid 'Script 13 promotion evidence is incomplete or mismatched.' \
    'Restore complete Script 13 evidence.'
receipt_has_lines "$promotion_root/acceptance-receipt.txt" \
  'schema=ishikawa.emceedanko-v1.3.1-runtime-promotion-acceptance.v1' \
  "application_archive_sha256=$expected_application_sha256" \
  "runtime_archive_sha256=$expected_runtime_sha256" "image_id=$expected_image_id" \
  'human_ui_acceptance=accepted' 'production_runtime=pass' 'frontier_cases=60/60' \
  'superseded_runtime_image_removed=true' 'previous_runtime_rollback=retired' \
  'application_mutated=false' 'retrieval_api_restarted=false' \
  'postgresql_restarted=false' 'database_mutated=false' 'schema_mutated=false' \
  'corpus_mutated=false' 'boot_autostart=false' \
  || block script13_acceptance_invalid 'Script 13 acceptance omits an exact identity or safety invariant.' \
    'Restore complete Script 13 evidence.'

[[ -f "$security_record" && ! -L "$security_record" \
    && -f "$security_scan" && ! -L "$security_scan" ]] \
  || block security_evidence_missing 'The exact-artifact security evidence is absent or unsafe.' \
    'Restore the reviewed corrected-runtime security evidence.'
[[ "$(sha256sum -- "$security_scan" | awk '{print $1}')" == "$expected_security_scan_sha256" ]] \
  || block security_scan_identity_mismatch 'The corrected raw vulnerability scan identity changed.' \
    'Restore and review the exact scan before assembly.'
jq -e '
  .SchemaVersion == 2 and .ArtifactType == "container_image"
  and .Metadata.OS.Family == "debian" and .Metadata.OS.Name == "12.15"
  and ([.Results[] | select(.Type == "node-pkg") | (.Vulnerabilities // [])[]] | length) == 0
  and ([.Results[] | (.Vulnerabilities // [])[] | select((.FixedVersion // "") != "")] | length) == 0' \
  "$security_scan" >/dev/null \
  || block security_scan_contract_invalid \
    'The exact scan no longer proves zero JavaScript findings and zero available fixed versions.' \
    'Reconcile the scanner output before assembly.'
grep -Fq "$expected_runtime_sha256" "$security_record" \
  && grep -Fq "$expected_image_id" "$security_record" \
  && grep -Fq 'production_promotion_and_acceptance=pass' "$security_record" \
  || block security_review_record_invalid 'The durable security review is stale or mismatched.' \
    'Reconcile the corrected security review before assembly.'

application_bytes="$(stat -Lc %s -- "$application_root/ishikawa-v1.3.1.tar.gz")"
runtime_bytes="$(stat -Lc %s -- "$runtime_root/node-next-runtime-amd64.tar")"
artifact_available="$(df -PB1 "$artifact_parent" | awk 'END {print $4}')"
temporary_available="$(df -PB1 /tmp | awk 'END {print $4}')"
for capacity_value in "$application_bytes" "$runtime_bytes" "$artifact_available" "$temporary_available"; do
  [[ "$capacity_value" =~ ^[0-9]+$ ]] \
    || block capacity_inventory_invalid 'A filesystem capacity value is invalid.' \
      'Correct the local filesystem or inspection tooling.'
done
required_artifact=$(( application_bytes + runtime_bytes + capacity_margin_bytes ))
required_temporary=$(( application_bytes + capacity_margin_bytes ))
(( artifact_available >= required_artifact )) \
  || block insufficient_artifact_capacity \
    "Artifact storage has $artifact_available bytes; $required_artifact are required." \
    'Free artifact storage and rerun.'
(( temporary_available >= required_temporary )) \
  || block insufficient_temporary_capacity \
    "Temporary storage has $temporary_available bytes; $required_temporary are required." \
    'Free temporary storage and rerun.'
emit INPUTS "state=pass;application_sha256=$application_sha256;runtime_sha256=$runtime_sha256;script12=accepted;script13=accepted;security_review=pass"
emit CAPACITY "state=pass;artifact_available_bytes=$artifact_available;artifact_required_bytes=$required_artifact;temporary_available_bytes=$temporary_available;temporary_required_bytes=$required_temporary"

current_stage='assembly'
emit ASSEMBLY 'state=start;primary_payloads=2;stable_handoff=false;release_state=review_pending'
assembly_stage="$artifact_parent/.ishikawa-deployment-v1.3.1-candidate-current.${timestamp}.$$"
mkdir -- "$assembly_stage" \
  || block assembly_stage_creation_failed 'The private assembly stage could not be created.' \
    'Correct local artifact storage and rerun.'
for source_name in README.md SECURITY_REVIEW.md deploy-ishikawa verify-deployment; do
  copy_payload "$carry_source/$source_name" "$assembly_stage/$source_name"
done
copy_payload "$native_inventory" "$assembly_stage/inspect-native-prerequisites"
copy_payload "$application_root/ishikawa-v1.3.1.tar.gz" "$assembly_stage/ishikawa-v1.3.1.tar.gz"
copy_payload "$application_root/ishikawa-v1.3.1.tar.gz.sha256" "$assembly_stage/ishikawa-v1.3.1.tar.gz.sha256"
copy_payload "$application_root/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS" "$assembly_stage/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS"
copy_payload "$application_root/application-sbom.cdx.json" "$assembly_stage/application-sbom.cdx.json"
copy_payload "$application_root/application-license.json" "$assembly_stage/application-license.json"
copy_payload "$runtime_root/node-next-runtime-amd64.tar" "$assembly_stage/node-next-runtime-amd64.tar"
copy_payload "$runtime_root/node-next-runtime-amd64.tar.sha256" "$assembly_stage/node-next-runtime-amd64.tar.sha256"
copy_payload "$runtime_root/image-identity.json" "$assembly_stage/runtime-image-identity.json"
copy_payload "$runtime_root/build-receipt.json" "$assembly_stage/runtime-build-receipt.json"
copy_payload "$runtime_root/sbom.cdx.json" "$assembly_stage/runtime-sbom.cdx.json"
copy_payload "$runtime_root/licenses.json" "$assembly_stage/runtime-licenses.json"
copy_payload "$runtime_root/Dockerfile" "$assembly_stage/runtime-Dockerfile"
copy_payload "$runtime_root/package.json" "$assembly_stage/runtime-package.json"
copy_payload "$runtime_root/package-lock.json" "$assembly_stage/runtime-package-lock.json"
copy_payload "$runtime_root/README.md" "$assembly_stage/RUNTIME_README.md"
copy_payload "$runtime_root/SECURITY.md" "$assembly_stage/RUNTIME_SECURITY.md"
copy_payload "$runtime_root/LICENSES.md" "$assembly_stage/RUNTIME_LICENSES.md"

source_receipt_sha="$(sha256sum -- "$application_root/release-receipt.json" | awk '{print $1}')"
qualification_receipt_sha="$(sha256sum -- "$qualification_root/qualification-receipt.txt" | awk '{print $1}')"
qualification_acceptance_sha="$(sha256sum -- "$qualification_root/acceptance-receipt.txt" | awk '{print $1}')"
promotion_receipt_sha="$(sha256sum -- "$promotion_root/promotion-receipt.txt" | awk '{print $1}')"
promotion_acceptance_sha="$(sha256sum -- "$promotion_root/acceptance-receipt.txt" | awk '{print $1}')"
security_record_sha="$(sha256sum -- "$security_record" | awk '{print $1}')"
source_manifest_sha="$(jq -r '.source_manifest_sha256' "$application_root/release-receipt.json")"
python3 -B - "$assembly_stage/application-release.json" "$application_sha256" \
  "$source_manifest_sha" "$source_receipt_sha" "$qualification_receipt_sha" \
  "$qualification_acceptance_sha" "$promotion_receipt_sha" \
  "$promotion_acceptance_sha" "$security_record_sha" <<'PY' \
  || block application_release_generation_failed 'Could not generate the accepted application record.' \
    'Correct local Python or artifact storage and rerun.'
import json
import sys
from pathlib import Path

(output, application_sha256, source_manifest_sha256, source_receipt_sha256,
 qualification_receipt_sha256, qualification_acceptance_sha256,
 promotion_receipt_sha256, promotion_acceptance_sha256,
 security_review_record_sha256) = sys.argv[1:]
record = {
    "application_archive_sha256": application_sha256,
    "coding_standard": "pass",
    "deterministic_archive": True,
    "fresh_install": "pass",
    "human_ui_validation": "accepted",
    "javascript_test_count": 17,
    "native_test_count": 486,
    "production_runtime": "pass",
    "promotion_acceptance_sha256": promotion_acceptance_sha256,
    "promotion_receipt_sha256": promotion_receipt_sha256,
    "qualification_acceptance_sha256": qualification_acceptance_sha256,
    "qualification_receipt_sha256": qualification_receipt_sha256,
    "release": "Ishikawa v1.3.1",
    "schema": "ishikawa.application-release.v1",
    "security_review_record_sha256": security_review_record_sha256,
    "source_build_receipt_sha256": source_receipt_sha256,
    "source_manifest_sha256": source_manifest_sha256,
}
Path(output).write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY

image_id="$(jq -r '.image_id' "$assembly_stage/runtime-image-identity.json")"
config_digest="$(jq -r '.config_digest' "$assembly_stage/runtime-image-identity.json")"
history_sha="$(jq -r '.history_sha256' "$assembly_stage/runtime-image-identity.json")"
portable_security_sha="$(sha256sum -- "$assembly_stage/SECURITY_REVIEW.md" | awk '{print $1}')"
python3 -B - "$assembly_stage/deployment-package-receipt.json" \
  "$application_sha256" "$runtime_sha256" "$image_id" "$config_digest" \
  "$history_sha" "$portable_security_sha" <<'PY' \
  || block package_receipt_generation_failed 'Could not generate the package review-state receipt.' \
    'Correct local Python or artifact storage and rerun.'
import json
import sys
from pathlib import Path

(output, application_sha256, image_sha256, image_id, config_digest,
 history_sha256, security_review_sha256) = sys.argv[1:]
record = {
    "application_archive_sha256": application_sha256,
    "application_release": "Ishikawa v1.3.1",
    "architecture": "amd64",
    "boot_autostart": False,
    "exact_byte_requalification": "pass",
    "human_ui_validation": "accepted",
    "image_archive_sha256": image_sha256,
    "image_config_digest": config_digest,
    "image_history_sha256": history_sha256,
    "image_id": image_id,
    "image_reference": "node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64",
    "independent_final_review": "pending",
    "platform": "linux/amd64",
    "production_runtime": "pass",
    "release_state": "assembled_pending_target_inventory_and_independent_review",
    "schema": "ishikawa.deployment-package-receipt.v1",
    "security_review": "pass",
    "security_review_sha256": security_review_sha256,
    "stable_handoff": False,
    "target_inventory": "pending",
}
Path(output).write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY

python3 -B - "$assembly_stage" "$assembly_stage/PACKAGE_MANIFEST.json" <<'PY' \
  || block package_manifest_generation_failed 'Could not generate the classified package manifest.' \
    'Correct local Python or artifact storage and rerun.'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
output = Path(sys.argv[2])
purposes = {
    "ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS": ("application source provenance", "release reviewer", "0644"),
    "README.md": ("operator command sheet", "operator", "0644"),
    "RUNTIME_LICENSES.md": ("runtime license boundary", "security reviewer", "0644"),
    "RUNTIME_README.md": ("runtime architecture record", "operator and reviewer", "0644"),
    "RUNTIME_SECURITY.md": ("runtime build-time advisory disposition", "security reviewer", "0644"),
    "SECURITY_REVIEW.md": ("exact-payload security disposition", "security reviewer and operator", "0644"),
    "application-license.json": ("application license identity", "security reviewer", "0644"),
    "application-release.json": ("accepted application identity", "verifier and reviewer", "0644"),
    "application-sbom.cdx.json": ("application software inventory", "security reviewer", "0644"),
    "deployment-package-receipt.json": ("package identity and review state", "verifier and operator", "0644"),
    "deploy-ishikawa": ("consolidated deployment entrypoint", "operator", "0755"),
    "inspect-native-prerequisites": ("read-only destination inventory", "operator", "0755"),
    "ishikawa-v1.3.1.tar.gz": ("external application payload", "deployment entrypoint", "0644"),
    "ishikawa-v1.3.1.tar.gz.sha256": ("application archive checksum", "verifier", "0644"),
    "node-next-runtime-amd64.tar": ("application-free runtime image", "deployment entrypoint", "0644"),
    "node-next-runtime-amd64.tar.sha256": ("runtime archive checksum", "verifier", "0644"),
    "runtime-build-receipt.json": ("runtime build receipt", "verifier and reviewer", "0644"),
    "runtime-Dockerfile": ("runtime reproducibility input", "release reviewer", "0644"),
    "runtime-image-identity.json": ("runtime image identity", "verifier and deployment entrypoint", "0644"),
    "runtime-licenses.json": ("runtime dependency license inventory", "security reviewer", "0644"),
    "runtime-package-lock.json": ("runtime exact dependency lock", "release reviewer", "0644"),
    "runtime-package.json": ("runtime direct dependency declaration", "release reviewer", "0644"),
    "runtime-sbom.cdx.json": ("runtime software inventory", "security reviewer", "0644"),
    "verify-deployment": ("portable complete verifier", "operator", "0755"),
}
records = []
for path in sorted(root.iterdir(), key=lambda item: item.name):
    if not path.is_file() or path == output or path.name == "SHA256SUMS":
        continue
    if path.name not in purposes:
        raise SystemExit(1)
    purpose, consumer, intended_mode = purposes[path.name]
    records.append({
        "consumer": consumer,
        "mode": intended_mode,
        "path": path.name,
        "purpose": purpose,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "size_bytes": path.stat().st_size,
        "type": "file",
    })
record = {
    "control_files": [
        {"consumer": "operator and verifier", "mode": "0644", "path": "PACKAGE_MANIFEST.json", "purpose": "complete classified package inventory", "type": "file"},
        {"consumer": "operator and verifier", "mode": "0644", "path": "SHA256SUMS", "purpose": "complete package checksum inventory", "type": "file"},
    ],
    "files": records,
    "package_file_count": len(records) + 2,
    "payload_file_count": len(records),
    "payload_total_bytes": sum(item["size_bytes"] for item in records),
    "primary_payloads": ["ishikawa-v1.3.1.tar.gz", "node-next-runtime-amd64.tar"],
    "schema": "ishikawa.deployment-package-manifest.v1",
}
output.write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
emit ASSEMBLY "state=pass;application_bytes=$application_bytes;runtime_image_bytes=$runtime_bytes;package_files=26;generated_next_in_package=false"

current_stage='package_verification'
emit VERIFY 'state=start;checksums=true;portable_verifier=true;terminology_scan=true;secret_scan=true'
scan_root="$(mktemp -d /tmp/ishikawa-carry-scan.XXXXXX)" \
  || block scan_workspace_failed 'Could not create the private scan workspace.' \
    'Correct temporary storage and rerun.'
mkdir -- "$scan_root/application"
tar --no-same-owner --no-same-permissions -xzf "$assembly_stage/ishikawa-v1.3.1.tar.gz" \
  -C "$scan_root/application" \
  || block application_scan_extraction_failed 'Could not safely extract the application for final scanning.' \
    'Restore the exact application handoff.'
if grep -R -I -E -n \
    '/mnt/|Prj|phase-|Script[[:space:]]+[0-9]|Codex|EmceeDanko|DankoSurface|local/artifacts|(^|[^[:alnum:]_])agent([^[:alnum:]_]|$)' \
    "$scan_root/application" >/dev/null; then
  block application_language_invalid 'The application contains repository, workstream, or test-host terminology.' \
    'Correct the application payload and rebuild it.'
fi
if grep -R -I -E -n \
    '/mnt/|Prj|phase-|Script[[:space:]]+[0-9]|Codex|EmceeDanko|DankoSurface|local/artifacts|(^|[^[:alnum:]_])agent([^[:alnum:]_]|$)' \
    "$assembly_stage" --exclude='*.tar' --exclude='*.tar.gz' --exclude='*.sha256' \
    --exclude=ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS >/dev/null; then
  block package_language_invalid 'The assembled carry contains non-portable repository or test-host terminology.' \
    'Replace the leaking text with product and operator language.'
fi
if find "$assembly_stage" -type f \( -name '*.key' -o -name '*.pem' -o -name '*.p12' \
    -o -name '*.pfx' -o -name '*.env' \) -print -quit | grep -q .; then
  block prohibited_secret_file_found 'The assembled carry contains a prohibited secret-bearing file type.' \
    'Remove the file and reconcile its approved injection boundary.'
fi
if grep -R -I -E -n -e \
    '-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}' \
    "$assembly_stage" --exclude='*.tar' --exclude='*.tar.gz' >/dev/null; then
  block secret_material_found 'The assembled carry contains a private-key or credential-shaped value.' \
    'Remove the value and rebuild the affected canonical source.'
fi
rm -rf -- "$scan_root"
scan_root=''
(
  cd -- "$assembly_stage"
  while IFS= read -r file_name; do sha256sum -- "$file_name"; done < <(
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\n' | sort
  ) >SHA256SUMS
  sha256sum --check --strict SHA256SUMS >/dev/null
) || block package_checksum_failed 'The assembled package failed its complete checksum manifest.' \
  'Do not publish the candidate.'
bash "$assembly_stage/verify-deployment" >/dev/null \
  || block portable_verification_failed 'The assembled carry failed its portable verifier.' \
    'Correct the reported package boundary before publication.'
emit VERIFY "state=pass;application_sha256=$application_sha256;runtime_sha256=$runtime_sha256;security_review=pass;manifest=pass"

current_stage='publication'
emit PUBLISH 'state=start;destination=candidate_handoff;stable_handoff=false'
mkdir -p -- "$artifact_parent/superseded" \
  || block superseded_directory_failed 'Could not create the superseded-candidate directory.' \
    'Correct artifact storage and rerun.'
backup=''
if [[ -e "$artifact_current" || -L "$artifact_current" ]]; then
  [[ -d "$artifact_current" && ! -L "$artifact_current" ]] \
    || block current_handoff_unsafe 'The existing candidate handoff is not a regular directory.' \
      'Inspect the candidate path before publication.'
  bash "$artifact_current/verify-deployment" >/dev/null \
    || block current_handoff_invalid 'The existing candidate cannot be verified before preservation.' \
      'Inspect the current candidate before replacement.'
  backup="$artifact_parent/superseded/ishikawa-deployment-v1.3.1-candidate-current-${timestamp}-$$"
  [[ ! -e "$backup" && ! -L "$backup" ]] \
    || block superseded_handoff_exists 'The selected preservation path already exists.' \
      'Review the artifact lane and rerun.'
  mv -- "$artifact_current" "$backup" \
    || block prior_candidate_preservation_failed 'Could not preserve the existing verified candidate.' \
      'Inspect the candidate and superseded lanes.'
fi
if ! mv -- "$assembly_stage" "$artifact_current"; then
  [[ -z "$backup" ]] || mv -- "$backup" "$artifact_current" \
    || block prior_candidate_restoration_failed 'Publication failed and the prior candidate could not be restored.' \
      'Stop and inspect both artifact paths.'
  block publication_failed 'The corrected candidate could not be published.' \
    'The prior candidate was restored; correct local storage and rerun.'
fi
assembly_stage=''
bash "$artifact_current/verify-deployment" >/dev/null \
  || block published_candidate_invalid 'The published corrected candidate failed independent verification.' \
    'Stop and inspect the candidate handoff.'
emit PUBLISH "state=pass;candidate_handoff=$artifact_current;stable_handoff=false;installation_allowed=false"
emit SUMMARY "state=pass;report_path=$report_path;cleanup=pass;next_gate=target_inventory_and_independent_review"
result pass | tee -a "$report_path"

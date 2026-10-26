#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Assemble the checksum-bound Ishikawa v1.3.1 deployment package candidate.
#
# Mental model:
#   Verify the frozen release decisions, independent application and runtime
#   handoffs, and exact-byte qualification and promotion-acceptance receipts.
#   Classify every carried file, run the portable verifier from the assembled
#   layout, then atomically replace only the local candidate handoff.
#
# Inputs or prerequisites:
#   - accepted Script 07 and Script 08 handoffs under local/artifacts;
#   - complete Script 09 qualification/acceptance/cleanup evidence; and
#   - complete Script 10 promotion and production-port acceptance evidence.
#
# Outputs or artifact lane:
#   local/artifacts/ishikawa-deployment-v1.3.1-candidate-current/
#   local/reports/ishikawa-deployment-package-assembly/
#   No target, corpus, database, credential, service, listener, or boot state
#   is contacted or changed. Stable deployment-ready promotion is separate.
#
# Usage:
#   bash ./deployment/scripts/11_assemble-ishikawa-v1.3.1-deployment-package.sh --validate-only
#   bash ./deployment/scripts/11_assemble-ishikawa-v1.3.1-deployment-package.sh --run

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly source_root="$repo_root/deployment/carry"
readonly application_root="$repo_root/local/artifacts/ishikawa-v1.3.1-candidate-current"
readonly runtime_root="$repo_root/local/artifacts/node-next-runtime-current"
readonly requalification_root="$repo_root/local/artifacts/emceedanko-v1.3.1-requalification-current"
readonly promotion_root="$repo_root/local/artifacts/emceedanko-v1.3.1-promotion-current"
readonly artifact_parent="$repo_root/local/artifacts"
readonly artifact_current="$artifact_parent/ishikawa-deployment-v1.3.1-candidate-current"
readonly report_root="$repo_root/local/reports/ishikawa-deployment-package-assembly"
readonly decision_record="$repo_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md"
readonly expected_application_sha256='2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69'
readonly expected_runtime_sha256='af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f'
readonly expected_image_id='sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298'
readonly capacity_margin_bytes=67108864

mode=''
current_stage='argument_validation'
stage=''
report_path=''
language_scan_root=''

usage() {
  sed -n '5,31p' "${BASH_SOURCE[0]}"
}

result() {
  printf '\nSCRIPT RESULT\nishikawa_deployment_package_assembly=%s\n' "$1"
}

block() {
  local reason="$1" detail="$2" action="$3" status="${4:-1}" payload
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
  trap - ERR
  block unexpected_command_failure \
    "Unhandled failure at Script 11 line ${line} with status ${status}." \
    'Review the retained report and correct the reported local condition.' \
    "$status"
}

copy_payload_file() {
  local source_path="$1" destination_path="$2"
  cp -- "$source_path" "$destination_path" \
    || block payload_copy_failed \
      "A package file could not be copied: ${source_path##*/}." \
      'Correct local source readability or artifact storage and rerun.'
  [[ -f "$destination_path" && ! -L "$destination_path" ]] \
    || block payload_copy_invalid \
      "A copied package file is missing or unsafe: ${destination_path##*/}." \
      'Inspect the local artifact filesystem and rerun.'
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ -n "$stage" && "$stage" == "$artifact_parent"/.ishikawa-deployment-v1.3.1-candidate-current.* \
      && -d "$stage" && ! -L "$stage" ]]; then
    rm -rf -- "$stage"
  fi
  if [[ -n "$language_scan_root" \
      && "$language_scan_root" == /tmp/ishikawa-deployment-language-scan.* \
      && -d "$language_scan_root" && ! -L "$language_scan_root" ]]; then
    rm -rf -- "$language_scan_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'unexpected_error "$?" "$LINENO"' ERR
trap 'current_stage=interrupted; block signal_hangup "Package assembly received SIGHUP." "Review the retained report and rerun." 129' HUP
trap 'current_stage=interrupted; block signal_interrupt "Package assembly was interrupted." "Review the retained report and rerun." 130' INT
trap 'current_stage=interrupted; block signal_termination "Package assembly received SIGTERM." "Review the retained report and rerun." 143' TERM

if [[ $# == 1 && ( "$1" == --help || "$1" == -h ) ]]; then
  usage
  exit 0
fi
[[ $# == 1 && ( "$1" == --validate-only || "$1" == --run ) ]] \
  || { usage >&2; block exactly_one_supported_mode_required \
    'Use exactly one mode: --validate-only or --run.' \
    'Rerun with one supported mode.' 2; }
mode="$1"

current_stage='source_preflight'
for command_name in awk bash cp date df find grep jq mkdir mktemp mv python3 rm \
  sha256sum sort tar tee; do
  command -v "$command_name" >/dev/null 2>&1 \
    || block "command_missing_${command_name}" \
      "A required local command is unavailable: ${command_name}." \
      'Restore the named command and rerun.'
done
for source_file in README.md deploy-ishikawa verify-deployment; do
  [[ -f "$source_root/$source_file" && ! -L "$source_root/$source_file" \
      && -r "$source_root/$source_file" ]] \
    || block carry_source_unsafe \
      "A carry source is missing or unsafe: ${source_file}." \
      'Restore the reviewed canonical source and rerun.'
done
bash -n "$source_root/deploy-ishikawa" "$source_root/verify-deployment" \
  || block carry_source_syntax_invalid \
    'A portable deployment command failed shell parsing.' \
    'Correct the command before assembly.'
for decision in {79..91}; do
  decision_block="$(awk -v header="### V13-${decision} " '
    index($0, header) == 1 {capture=1}
    capture && /^### / && index($0, header) != 1 {exit}
    capture {print}
  ' "$decision_record")"
  [[ "$(grep -Ec '^Status: Frozen([. ]|$)' <<<"$decision_block")" == 1 ]] \
    || block "v13_${decision}_not_frozen" \
      "Required carry decision V13-${decision} is absent or not frozen." \
      'Reconcile the decision ledger before assembly.'
done

if [[ "$mode" == --validate-only ]]; then
  printf '%s\n' \
    'package_source=pass;decisions=V13-79_through_V13-91_frozen' \
    'primary_payloads=external_application_and_application_free_amd64_runtime_image' \
    'publication=candidate_only;stable_handoff=false;target_contact=false'
  result ready
  exit 0
fi

mkdir -p -- "$report_root" \
  || block report_directory_failed \
    'The local package-assembly report directory could not be created.' \
    'Correct local report permissions and rerun.'
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/package_assembly_${timestamp}_XXXXXX.txt")" \
  || block report_creation_failed \
    'The content-free package-assembly report could not be created.' \
    'Correct local report permissions and rerun.'
emit() { printf '[%s] %s\n' "$1" "$2" | tee -a "$report_path"; }
emit READINESS 'state=start;remote_contact=false;target_mutation=false;credential_access=false;corpus_access=false'

current_stage='input_verification'
emit INPUTS 'state=start;application=true;runtime_image=true;qualification=true;promotion_acceptance=true'
for artifact_directory in "$application_root" "$runtime_root" \
  "$requalification_root" "$promotion_root"; do
  [[ -d "$artifact_directory" && ! -L "$artifact_directory" ]] \
    || block required_handoff_missing \
      "A required verified handoff is absent: ${artifact_directory}." \
      'Build and verify both independent handoffs before carry assembly.'
done
for evidence_directory in "$requalification_root" "$promotion_root"; do
  [[ -f "$evidence_directory/SHA256SUMS" && ! -L "$evidence_directory/SHA256SUMS" ]] \
    && (cd -- "$evidence_directory" && sha256sum --check --strict SHA256SUMS >/dev/null) \
    || block lifecycle_evidence_checksum_failed \
      'A required exact-byte lifecycle evidence set failed its checksum manifest.' \
      'Restore the accepted Script 09 and Script 10 evidence before assembly.'
done
(cd -- "$runtime_root" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block runtime_handoff_checksum_failed \
    'The generic runtime handoff failed its complete checksum manifest.' \
    'Rebuild or restore the verified runtime handoff.'
(cd -- "$application_root" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block application_handoff_checksum_failed \
    'The application handoff failed its archive checksum.' \
    'Rebuild or restore the verified application handoff.'
actual_application_sha256="$(sha256sum -- "$application_root/ishikawa-v1.3.1.tar.gz" | awk '{print $1}')"
actual_runtime_sha256="$(sha256sum -- "$runtime_root/node-next-runtime-amd64.tar" | awk '{print $1}')"
[[ "$actual_application_sha256" == "$expected_application_sha256" ]] \
  || block application_identity_mismatch \
    'The application archive is not the exact qualified and promoted v1.3.1 archive.' \
    'Restore the exact Script 08 application handoff.'
[[ "$actual_runtime_sha256" == "$expected_runtime_sha256" ]] \
  || block runtime_archive_identity_mismatch \
    'The runtime archive is not the exact qualified and promoted AMD64 image archive.' \
    'Restore the exact Script 07 runtime handoff.'
jq -e \
  '.release == "Ishikawa v1.3.1 candidate"
   and .archive_sha256 == "2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69"
   and .coding_standard == "pass"
   and .deterministic_archive == true
   and .fresh_install == "pass"
   and .human_ui_validation == "pending_exact_candidate_requalification"' \
  "$application_root/release-receipt.json" >/dev/null \
  || block application_receipt_invalid \
    'The application handoff receipt does not describe the expected candidate.' \
    'Rebuild the application handoff from the frozen source.'
for receipt_name in qualification-receipt.txt acceptance-receipt.txt cleanup-receipt.txt; do
  [[ -f "$requalification_root/$receipt_name" && ! -L "$requalification_root/$receipt_name" ]] \
    || block requalification_evidence_incomplete \
      'The exact-byte qualification, acceptance, or cleanup receipt is absent.' \
      'Restore the complete Script 09 evidence set.'
done
for expected_line in \
  "application_archive_sha256=$expected_application_sha256" \
  "runtime_archive_sha256=$expected_runtime_sha256" \
  "image_id=$expected_image_id" \
  'production_build_start=pass' \
  'frontier_cases=60/60'; do
  grep -Fxq "$expected_line" "$requalification_root/qualification-receipt.txt" \
    || block requalification_receipt_invalid \
      'The exact-byte qualification receipt does not match the selected payloads.' \
      'Restore the accepted Script 09 qualification evidence.'
done
for expected_line in \
  "application_archive_sha256=$expected_application_sha256" \
  "runtime_archive_sha256=$expected_runtime_sha256" \
  "image_id=$expected_image_id" \
  'human_ui_acceptance=accepted' \
  'production_build_start=pass' \
  'frontier_cases=60/60'; do
  grep -Fxq "$expected_line" "$requalification_root/acceptance-receipt.txt" \
    || block requalification_acceptance_invalid \
      'The exact-byte UI-acceptance receipt does not match the selected payloads.' \
      'Restore the accepted Script 09 acceptance evidence.'
done
grep -Fxq 'state=pass' "$requalification_root/cleanup-receipt.txt" \
  && grep -Fxq "application_archive_sha256=$expected_application_sha256" \
    "$requalification_root/cleanup-receipt.txt" \
  || block requalification_cleanup_invalid \
    'The isolated exact-byte qualification cleanup receipt is incomplete.' \
    'Complete or restore the accepted Script 09 cleanup evidence.'

for receipt_name in promotion-receipt.txt acceptance-receipt.txt; do
  [[ -f "$promotion_root/$receipt_name" && ! -L "$promotion_root/$receipt_name" ]] \
    || block promotion_acceptance_missing \
      'The production-port promotion acceptance receipt has not been recorded.' \
      'Review the promoted UI, then run Script 10 with --accept.'
done
for expected_line in \
  "application_archive_sha256=$expected_application_sha256" \
  "runtime_archive_sha256=$expected_runtime_sha256" \
  "image_id=$expected_image_id" \
  'production_build_start=pass'; do
  grep -Fxq "$expected_line" "$promotion_root/promotion-receipt.txt" \
    || block promotion_receipt_invalid \
      'The production-port promotion receipt does not match the selected payloads.' \
      'Restore the exact Script 10 promotion evidence.'
done
for expected_line in \
  'schema=ishikawa.emceedanko-v1.3.1-promotion-acceptance.v1' \
  "application_archive_sha256=$expected_application_sha256" \
  "runtime_archive_sha256=$expected_runtime_sha256" \
  "image_id=$expected_image_id" \
  'human_ui_acceptance=accepted' \
  'production_runtime=pass' \
  'frontier_cases=60/60' \
  'superseded_v1_3_removed=true' \
  'superseded_image_removed=true' \
  'database_mutated=false' \
  'schema_mutated=false' \
  'corpus_mutated=false' \
  'boot_autostart=false'; do
  grep -Fxq "$expected_line" "$promotion_root/acceptance-receipt.txt" \
    || block promotion_acceptance_invalid \
      'The production-port acceptance receipt omits an exact identity or safety invariant.' \
      'Reconcile and repeat Script 10 acceptance.'
done
jq -e \
  '.schema == "node-next-runtime-image.v1"
   and .architecture == "amd64"
   and .platform == "linux/amd64"
   and .application_in_image == false
   and .generated_next_in_image == false
   and .image_reference == "node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64"
   and .node == "24.22.1"
   and .npm == "11.19.1"
   and .yarn == "1.22.22"
   and .next == "16.4.3"
   and .react == "19.2.9"
   and .react_dom == "19.2.9"
   and .archive_sha256 == "af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f"
   and .image_id == "sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298"
   and (.image_id | test("^sha256:[0-9a-f]{64}$"))
   and (.config_digest | test("^sha256:[0-9a-f]{64}$"))
   and (.history_sha256 | test("^[0-9a-f]{64}$"))' \
  "$runtime_root/image-identity.json" >/dev/null \
  || block runtime_identity_invalid \
    'The runtime handoff does not match the frozen generic Linux AMD64 identity.' \
    'Rebuild the exact generic runtime image.'
python3 -B - "$runtime_root/node-next-runtime-amd64.tar" \
  "$runtime_root/image-identity.json" "$runtime_root/build-receipt.json" \
  "$runtime_root/sbom.cdx.json" "$runtime_root/licenses.json" <<'PY' \
  || block runtime_provenance_invalid \
    'The runtime archive, identity, receipt, SBOM, and license evidence are not mutually bound.' \
    'Rebuild the exact generic runtime image with Script 07.'
import hashlib
import json
import re
import sys
import tarfile
from pathlib import Path

archive_path, identity_path, receipt_path, sbom_path, licenses_path = map(Path, sys.argv[1:])
identity = json.loads(identity_path.read_text(encoding="utf-8"))
receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
sbom = json.loads(sbom_path.read_text(encoding="utf-8"))
licenses = json.loads(licenses_path.read_text(encoding="utf-8"))

def stream_sha256(stream) -> str:
    value = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        value.update(block)
    return value.hexdigest()

with tarfile.open(archive_path, "r:") as archive:
    manifest = json.load(archive.extractfile("manifest.json"))
    if not isinstance(manifest, list) or len(manifest) != 1:
        raise SystemExit(1)
    if manifest[0].get("RepoTags") != ["node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64"]:
        raise SystemExit(1)
    layers = manifest[0].get("Layers")
    if not isinstance(layers, list) or not layers:
        raise SystemExit(1)
    for layer_path in layers:
        layer_match = re.fullmatch(r"blobs/sha256/([0-9a-f]{64})", layer_path or "")
        if layer_match is None:
            raise SystemExit(1)
        layer_member = archive.extractfile(layer_path)
        if layer_member is None or stream_sha256(layer_member) != layer_match.group(1):
            raise SystemExit(1)
    config_path = manifest[0].get("Config")
    if not isinstance(config_path, str):
        raise SystemExit(1)
    match = re.fullmatch(r"blobs/sha256/([0-9a-f]{64})|([0-9a-f]{64})\.json", config_path)
    if match is None:
        raise SystemExit(1)
    config_hex = match.group(1) or match.group(2)
    config_bytes = archive.extractfile(config_path).read()
if hashlib.sha256(config_bytes).hexdigest() != config_hex:
    raise SystemExit(1)
if re.search(r"Ishikawa|Prj|phase-|Script\s+[0-9]|Codex|EmceeDanko|DankoSurface|(?:api[_-]?key|password|secret|token)=", config_bytes.decode("utf-8"), re.IGNORECASE):
    raise SystemExit(1)
config = json.loads(config_bytes)
history = config.get("history")
if not isinstance(history, list) or not history:
    raise SystemExit(1)
history_bytes = (json.dumps(history, sort_keys=True, separators=(",", ":")) + "\n").encode()
config_digest = f"sha256:{config_hex}"
history_digest = hashlib.sha256(history_bytes).hexdigest()
if config.get("architecture") != "amd64" or config.get("os") != "linux":
    raise SystemExit(1)
rootfs = config.get("rootfs", {})
diff_ids = rootfs.get("diff_ids")
if rootfs.get("type") != "layers" or not isinstance(diff_ids, list) or not diff_ids:
    raise SystemExit(1)
if any(re.fullmatch(r"sha256:[0-9a-f]{64}", item or "") is None for item in diff_ids):
    raise SystemExit(1)
if config.get("config", {}).get("WorkingDir") != "/opt/nextjs":
    raise SystemExit(1)
if config.get("config", {}).get("Cmd") != ["next", "--help"]:
    raise SystemExit(1)
if identity.get("config_digest") != config_digest or identity.get("history_sha256") != history_digest:
    raise SystemExit(1)
if receipt.get("schema") != "node-next-runtime-build-receipt.v1":
    raise SystemExit(1)
for field in ("image_id", "image_reference", "archive_sha256", "architecture", "platform", "config_digest", "history_sha256"):
    if receipt.get(field) != identity.get(field):
        raise SystemExit(1)
if receipt.get("sbom_sha256") != hashlib.sha256(sbom_path.read_bytes()).hexdigest():
    raise SystemExit(1)
if receipt.get("licenses_sha256") != hashlib.sha256(licenses_path.read_bytes()).hexdigest():
    raise SystemExit(1)
properties = sbom.get("metadata", {}).get("component", {}).get("properties", [])
if not any(item.get("name") == "oci:image:config-digest" and item.get("value") == config_digest for item in properties):
    raise SystemExit(1)
components = sbom.get("components", [])
expected_components = {("node", "24.22.1", "MIT"), ("npm", "11.19.1", "Artistic-2.0"), ("yarn", "1.22.22", "BSD-2-Clause")}
observed_components = set()
for item in components:
    license_ids = {entry.get("license", {}).get("id") for entry in item.get("licenses", [])}
    for license_id in license_ids:
        observed_components.add((item.get("name"), item.get("version"), license_id))
if not expected_components.issubset(observed_components):
    raise SystemExit(1)
runtime_tools = licenses.get("runtime_tools")
if licenses.get("schema") != "node-runtime-license-inventory.v1" or not isinstance(runtime_tools, list) or len(runtime_tools) != 3:
    raise SystemExit(1)
expected_tools = {("node", "24.22.1", "MIT"), ("npm", "11.19.1", "Artistic-2.0"), ("yarn", "1.22.22", "BSD-2-Clause")}
observed_tools = {(item.get("name"), item.get("version"), item.get("license")) for item in runtime_tools}
if observed_tools != expected_tools:
    raise SystemExit(1)
if any(re.fullmatch(r"[0-9a-f]{64}", item.get("license_sha256", "")) is None for item in runtime_tools):
    raise SystemExit(1)
PY
application_archive_bytes="$(stat -Lc %s -- "$application_root/ishikawa-v1.3.1.tar.gz")"
runtime_archive_bytes="$(stat -Lc %s -- "$runtime_root/node-next-runtime-amd64.tar")"
application_uncompressed_bytes="$(python3 -B - "$application_root/ishikawa-v1.3.1.tar.gz" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1], "r:gz") as archive:
    print(sum(member.size for member in archive.getmembers() if member.isfile()))
PY
)" || block application_archive_inventory_invalid \
  'The application archive size inventory could not be read.' \
  'Restore the exact verified application archive.'
artifact_available_bytes="$(df -PB1 "$artifact_parent" | awk 'END {print $4}')"
temporary_available_bytes="$(df -PB1 /tmp | awk 'END {print $4}')"
for capacity_value in "$application_archive_bytes" "$runtime_archive_bytes" \
  "$application_uncompressed_bytes" "$artifact_available_bytes" \
  "$temporary_available_bytes"; do
  [[ "$capacity_value" =~ ^[0-9]+$ ]] \
    || block capacity_inventory_invalid \
      'A local capacity value was not a non-negative integer.' \
      'Correct the local filesystem or df/stat tooling before assembly.'
done
required_artifact_bytes=$((application_archive_bytes + runtime_archive_bytes + capacity_margin_bytes))
required_temporary_bytes=$((application_uncompressed_bytes + capacity_margin_bytes))
(( artifact_available_bytes >= required_artifact_bytes )) \
  || block insufficient_artifact_capacity \
    "The artifact filesystem has ${artifact_available_bytes} bytes available; ${required_artifact_bytes} are required." \
    'Free space on the artifact filesystem and rerun.'
(( temporary_available_bytes >= required_temporary_bytes )) \
  || block insufficient_temporary_capacity \
    "The temporary filesystem has ${temporary_available_bytes} bytes available; ${required_temporary_bytes} are required." \
    'Free space beneath /tmp and rerun.'
emit INPUTS "state=pass;application_sha256=${actual_application_sha256};runtime_sha256=${actual_runtime_sha256};exact_byte_acceptance=pass;production_port_acceptance=pass"
emit CAPACITY "state=pass;artifact_available_bytes=${artifact_available_bytes};artifact_required_bytes=${required_artifact_bytes};temporary_available_bytes=${temporary_available_bytes};temporary_required_bytes=${required_temporary_bytes}"

current_stage='assembly'
emit ASSEMBLY 'state=start;primary_payloads=2;stable_handoff=false'
stage="$artifact_parent/.ishikawa-deployment-v1.3.1-candidate-current.${timestamp}.$$"
mkdir -- "$stage" \
  || block assembly_stage_creation_failed \
    'The private deployment-package stage could not be created.' \
    'Correct local artifact-directory permissions and rerun.'
copy_payload_file "$source_root/README.md" "$stage/README.md"
copy_payload_file "$source_root/deploy-ishikawa" "$stage/deploy-ishikawa"
copy_payload_file "$source_root/verify-deployment" "$stage/verify-deployment"
copy_payload_file \
  "$repo_root/Ishikawa/packaging/native-prerequisite-inventory/inspect-native-prerequisites" \
  "$stage/inspect-native-prerequisites"
copy_payload_file "$application_root/ishikawa-v1.3.1.tar.gz" \
  "$stage/ishikawa-v1.3.1.tar.gz"
copy_payload_file "$application_root/ishikawa-v1.3.1.tar.gz.sha256" \
  "$stage/ishikawa-v1.3.1.tar.gz.sha256"
copy_payload_file "$application_root/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS" \
  "$stage/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS"
copy_payload_file "$application_root/application-sbom.cdx.json" \
  "$stage/application-sbom.cdx.json"
copy_payload_file "$application_root/application-license.json" \
  "$stage/application-license.json"
copy_payload_file "$runtime_root/node-next-runtime-amd64.tar" \
  "$stage/node-next-runtime-amd64.tar"
copy_payload_file "$runtime_root/node-next-runtime-amd64.tar.sha256" \
  "$stage/node-next-runtime-amd64.tar.sha256"
copy_payload_file "$runtime_root/image-identity.json" \
  "$stage/runtime-image-identity.json"
copy_payload_file "$runtime_root/build-receipt.json" \
  "$stage/runtime-build-receipt.json"
copy_payload_file "$runtime_root/sbom.cdx.json" "$stage/runtime-sbom.cdx.json"
copy_payload_file "$runtime_root/licenses.json" "$stage/runtime-licenses.json"
copy_payload_file "$runtime_root/Dockerfile" "$stage/runtime-Dockerfile"
copy_payload_file "$runtime_root/package.json" "$stage/runtime-package.json"
copy_payload_file "$runtime_root/package-lock.json" \
  "$stage/runtime-package-lock.json"
copy_payload_file "$runtime_root/README.md" "$stage/RUNTIME_README.md"
copy_payload_file "$runtime_root/SECURITY.md" "$stage/RUNTIME_SECURITY.md"
copy_payload_file "$runtime_root/LICENSES.md" "$stage/RUNTIME_LICENSES.md"

application_sha256="$(sha256sum -- "$stage/ishikawa-v1.3.1.tar.gz" | awk '{print $1}')"
image_sha256="$(sha256sum -- "$stage/node-next-runtime-amd64.tar" | awk '{print $1}')"
image_id="$(jq -r '.image_id' "$stage/runtime-image-identity.json")"
config_digest="$(jq -r '.config_digest' "$stage/runtime-image-identity.json")"
history_sha256="$(jq -r '.history_sha256' "$stage/runtime-image-identity.json")"
source_receipt_sha256="$(sha256sum -- "$application_root/release-receipt.json" | awk '{print $1}')"
qualification_receipt_sha256="$(sha256sum -- "$requalification_root/qualification-receipt.txt" | awk '{print $1}')"
qualification_acceptance_sha256="$(sha256sum -- "$requalification_root/acceptance-receipt.txt" | awk '{print $1}')"
promotion_receipt_sha256="$(sha256sum -- "$promotion_root/promotion-receipt.txt" | awk '{print $1}')"
promotion_acceptance_sha256="$(sha256sum -- "$promotion_root/acceptance-receipt.txt" | awk '{print $1}')"
source_manifest_sha256="$(jq -r '.source_manifest_sha256' "$application_root/release-receipt.json")"
python3 -B - "$stage/application-release.json" "$application_sha256" \
  "$source_manifest_sha256" "$source_receipt_sha256" \
  "$qualification_receipt_sha256" "$qualification_acceptance_sha256" \
  "$promotion_receipt_sha256" "$promotion_acceptance_sha256" <<'PY' \
  || block application_release_generation_failed \
    'The final application identity and acceptance record could not be generated.' \
    'Correct local Python or artifact storage and rerun.'
import json
import sys
from pathlib import Path

(output, application_sha256, source_manifest_sha256, source_receipt_sha256,
 qualification_receipt_sha256, qualification_acceptance_sha256,
 promotion_receipt_sha256, promotion_acceptance_sha256) = sys.argv[1:]
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
    "source_build_receipt_sha256": source_receipt_sha256,
    "source_manifest_sha256": source_manifest_sha256,
}
Path(output).write_text(
    json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
python3 -B - "$stage/deployment-package-receipt.json" "$application_sha256" \
  "$image_sha256" "$image_id" "$config_digest" "$history_sha256" <<'PY' \
  || block package_receipt_generation_failed \
    'The deployment-package state receipt could not be generated.' \
    'Correct local Python or artifact storage and rerun.'
import json
import sys
from pathlib import Path

output, application_sha256, image_sha256, image_id, config_digest, history_sha256 = sys.argv[1:]
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
    "release_state": "assembled_pending_security_inventory_and_independent_review",
    "schema": "ishikawa.deployment-package-receipt.v1",
    "security_review": "pending_complete_exact_artifact_review",
    "stable_handoff": False,
    "target_inventory": "pending",
}
Path(output).write_text(
    json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
python3 -B - "$stage" "$stage/PACKAGE_MANIFEST.json" <<'PY' \
  || block package_manifest_generation_failed \
    'The classified deployment-package manifest could not be generated.' \
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
    "RUNTIME_SECURITY.md": ("runtime advisory disposition", "security reviewer", "0644"),
    "application-license.json": ("application license identity", "security reviewer", "0644"),
    "application-release.json": ("final application identity and acceptance binding", "verifier and reviewer", "0644"),
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
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    records.append({
        "consumer": consumer,
        "mode": intended_mode,
        "path": path.name,
        "purpose": purpose,
        "sha256": digest,
        "size_bytes": path.stat().st_size,
        "type": "file",
    })
record = {
    "control_files": [
        {
            "consumer": "operator and verifier",
            "mode": "0644",
            "path": "PACKAGE_MANIFEST.json",
            "purpose": "complete classified package inventory",
            "type": "file",
        },
        {
            "consumer": "operator and verifier",
            "mode": "0644",
            "path": "SHA256SUMS",
            "purpose": "complete package checksum inventory",
            "type": "file",
        },
    ],
    "files": records,
    "package_file_count": len(records) + 2,
    "payload_file_count": len(records),
    "payload_total_bytes": sum(item["size_bytes"] for item in records),
    "primary_payloads": [
        "ishikawa-v1.3.1.tar.gz",
        "node-next-runtime-amd64.tar",
    ],
    "schema": "ishikawa.deployment-package-manifest.v1",
}
output.write_text(
    json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
emit ASSEMBLY "state=pass;application_bytes=$(stat -Lc %s -- "$stage/ishikawa-v1.3.1.tar.gz");runtime_image_bytes=$(stat -Lc %s -- "$stage/node-next-runtime-amd64.tar");generated_next_in_package=false"

current_stage='package_verification'
emit VERIFY 'state=start;checksums=true;portable_verifier=true;terminology_scan=true'
language_scan_root="$(mktemp -d /tmp/ishikawa-deployment-language-scan.XXXXXX)" \
  || block language_scan_workspace_failed \
    'The bounded local terminology-scan directory could not be created.' \
    'Correct temporary-directory permissions and rerun.'
tar --no-same-owner --no-same-permissions -xzf "$stage/ishikawa-v1.3.1.tar.gz" \
  -C "$language_scan_root" \
  || block application_scan_extraction_failed \
    'The application archive could not be extracted for its final terminology scan.' \
    'Restore the exact application handoff.'
if grep -R -I -E -n \
    '/mnt/|Prj|phase-|Script[[:space:]]+[0-9]|Codex|EmceeDanko|DankoSurface|local/artifacts|(^|[^[:alnum:]_])agent([^[:alnum:]_]|$)' \
    "$language_scan_root" >/dev/null; then
  block application_language_invalid \
    'The application archive contains repository, workstream, agent, or test-host terminology.' \
    'Correct the application payload and rebuild the exact release.'
fi
rm -rf -- "$language_scan_root"
language_scan_root=''
if grep -R -I -E -n \
    '/mnt/|Prj|phase-|Script[[:space:]]+[0-9]|Codex|EmceeDanko|DankoSurface|local/artifacts|(^|[^[:alnum:]_])agent([^[:alnum:]_]|$)' \
    "$stage" --exclude='*.tar' --exclude='*.tar.gz' --exclude='*.sha256' \
    --exclude=ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS >/dev/null; then
  block publication_language_invalid \
    'The assembled carry contains repository, workstream, agent, or test-host terminology.' \
    'Replace the leaking text with product and operator language.'
fi
(
  cd -- "$stage"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\n' | sort
  ) >SHA256SUMS
  sha256sum --check --strict SHA256SUMS >/dev/null
) || block carry_checksum_failed \
  'The assembled package failed its complete checksum manifest.' \
  'Do not publish the package candidate.'
bash "$stage/verify-deployment" >/dev/null \
  || block carry_verification_failed \
    'The assembled carry failed its portable verifier.' \
    'Correct the reported boundary before publication.'
emit VERIFY "state=pass;application_sha256=${application_sha256};image_sha256=${image_sha256};package_manifest=pass"

current_stage='publication'
emit PUBLISH 'state=start;destination=candidate_handoff;stable_handoff=false'
mkdir -p -- "$artifact_parent/superseded" \
  || block superseded_directory_failed \
    'The superseded-candidate directory could not be created.' \
    'Correct local artifact-directory permissions and rerun.'
backup=''
if [[ -e "$artifact_current" || -L "$artifact_current" ]]; then
  [[ -d "$artifact_current" && ! -L "$artifact_current" ]] \
    || block current_handoff_unsafe \
      'The candidate handoff exists but is not a regular directory.' \
      'Inspect the local artifact path before publication.'
  backup="$artifact_parent/superseded/ishikawa-deployment-v1.3.1-candidate-current-${timestamp}-$$"
  [[ ! -e "$backup" && ! -L "$backup" ]] \
    || block superseded_handoff_exists \
      'The selected superseded handoff path already exists.' \
      'Review local artifact state and rerun.'
fi
[[ -z "$backup" ]] || mv -- "$artifact_current" "$backup" \
  || block prior_candidate_preservation_failed \
    'The existing verified candidate could not be preserved before replacement.' \
    'Inspect the candidate and superseded directories before retrying.'
if ! mv -- "$stage" "$artifact_current"; then
  [[ -z "$backup" ]] || mv -- "$backup" "$artifact_current" \
    || block prior_candidate_restoration_failed \
      'Publication failed and the prior verified candidate could not be restored.' \
      'Stop and inspect both reported artifact paths before any retry.'
  block publication_failed \
    'The staged carry could not be published.' \
    'Review local filesystem state; the prior candidate was restored.'
fi
stage=''
bash "$artifact_current/verify-deployment" >/dev/null \
  || block published_handoff_verification_failed \
    'The published candidate failed verification.' \
    'Stop and inspect the candidate handoff.'
emit PUBLISH "state=pass;candidate_handoff=${artifact_current};stable_handoff=false"
emit SUMMARY "state=pass;report_path=${report_path};cleanup=pass;next_gate=security_inventory_and_independent_review"
result pass | tee -a "$report_path"

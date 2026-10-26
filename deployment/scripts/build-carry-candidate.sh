#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Assemble and atomically publish the portable deployment candidate from the
#   independently verified application and generic runtime-image handoffs.

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly source_root="$repo_root/deployment/carry"
readonly application_root="$repo_root/local/artifacts/ishikawa-v1.3.1-candidate-current"
readonly runtime_root="$repo_root/local/artifacts/node-next-runtime-current"
readonly artifact_parent="$repo_root/local/artifacts"
readonly artifact_current="$artifact_parent/ishikawa-deployment-v1.3.1-candidate-current"
readonly report_root="$repo_root/local/reports/ishikawa-carry-build"
readonly decision_record="$repo_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md"

mode="${1:-}"
current_stage='argument_validation'
stage=''
report_path=''

result() {
  printf '\nSCRIPT RESULT\nishikawa_carry_candidate_build=%s\n' "$1"
}

block() {
  local reason="$1" detail="$2" action="$3" payload
  payload="$(printf '%s\n' 'FAILURE DETAIL' "stage=$current_stage" \
    "reason=$reason" "detail=$detail" "operator_action=$action")"
  printf '%s\n' "$payload" >&2
  if [[ -n "$report_path" && -f "$report_path" && ! -L "$report_path" ]]; then
    printf '%s\n' "$payload" >>"$report_path"
    result blocked >>"$report_path"
  fi
  result blocked >&2
  exit 1
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ -n "$stage" && "$stage" == "$artifact_parent"/.ishikawa-deployment-v1.3.1-candidate-current.* \
      && -d "$stage" && ! -L "$stage" ]]; then
    rm -rf -- "$stage"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'current_stage=interrupted; block signal_interrupt "Carry assembly was interrupted." "Review the retained report and rerun."' INT
trap 'current_stage=interrupted; block signal_termination "Carry assembly received SIGTERM." "Review the retained report and rerun."' TERM

if [[ $# -ne 1 || ( "$mode" != --validate-only && "$mode" != --run ) ]]; then
  block exactly_one_supported_mode_required \
    'Use exactly one mode: --validate-only or --run.' \
    'Rerun with one supported mode.'
fi

current_stage='source_preflight'
for command_name in awk bash cp date find grep install jq mkdir mktemp mv python3 rm \
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
for decision in {79..90}; do
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
    'carry_source=pass;decisions=V13-79_through_V13-90_frozen' \
    'primary_payloads=external_application_and_application_free_amd64_runtime_image' \
    'publication=candidate_only;final_promotion=false'
  result ready
  exit 0
fi

current_stage='input_verification'
for artifact_directory in "$application_root" "$runtime_root"; do
  [[ -d "$artifact_directory" && ! -L "$artifact_directory" ]] \
    || block required_handoff_missing \
      "A required verified handoff is absent: ${artifact_directory}." \
      'Build and verify both independent handoffs before carry assembly.'
done
(cd -- "$runtime_root" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block runtime_handoff_checksum_failed \
    'The generic runtime handoff failed its complete checksum manifest.' \
    'Rebuild or restore the verified runtime handoff.'
(cd -- "$application_root" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block application_handoff_checksum_failed \
    'The application handoff failed its archive checksum.' \
    'Rebuild or restore the verified application handoff.'
jq -e \
  '.release == "Ishikawa v1.3.1 candidate"
   and .coding_standard == "pass"
   and .deterministic_archive == true
   and .fresh_install == "pass"
   and .human_ui_validation == "pending_exact_candidate_requalification"' \
  "$application_root/release-receipt.json" >/dev/null \
  || block application_receipt_invalid \
    'The application handoff receipt does not describe the expected candidate.' \
    'Rebuild the application handoff from the frozen source.'
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

mkdir -p -- "$artifact_parent" "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/carry_build_${timestamp}_XXXXXX.txt")" \
  || block report_creation_failed \
    'The content-free carry report could not be created.' \
    'Correct local report permissions and rerun.'
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=assemble_portable_ishikawa_v1_3_1_candidate'
emit 'remote_contact=false;target_mutation=false;credential_access=false;corpus_access=false'

current_stage='assembly'
stage="$artifact_parent/.ishikawa-deployment-v1.3.1-candidate-current.${timestamp}.$$"
mkdir -m 0700 -- "$stage"
install -m 0644 -- "$source_root/README.md" "$stage/README.md"
install -m 0755 -- "$source_root/deploy-ishikawa" "$stage/deploy-ishikawa"
install -m 0755 -- "$source_root/verify-deployment" "$stage/verify-deployment"
install -m 0755 -- \
  "$repo_root/Ishikawa/packaging/native-prerequisite-inventory/inspect-native-prerequisites" \
  "$stage/inspect-native-prerequisites"
install -m 0644 -- \
  "$application_root/ishikawa-v1.3.1.tar.gz" \
  "$application_root/ishikawa-v1.3.1.tar.gz.sha256" \
  "$application_root/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS" "$stage/"
install -m 0644 -- "$application_root/release-receipt.json" "$stage/application-release.json"
install -m 0644 -- "$application_root/application-sbom.cdx.json" \
  "$application_root/application-license.json" "$stage/"
install -m 0644 -- \
  "$runtime_root/node-next-runtime-amd64.tar" \
  "$runtime_root/node-next-runtime-amd64.tar.sha256" "$stage/"
install -m 0644 -- "$runtime_root/image-identity.json" "$stage/runtime-image-identity.json"
install -m 0644 -- "$runtime_root/build-receipt.json" "$stage/runtime-build-receipt.json"
install -m 0644 -- "$runtime_root/sbom.cdx.json" "$stage/runtime-sbom.cdx.json"
install -m 0644 -- "$runtime_root/licenses.json" "$stage/runtime-licenses.json"
install -m 0644 -- "$runtime_root/Dockerfile" "$stage/runtime-Dockerfile"
install -m 0644 -- "$runtime_root/package.json" "$stage/runtime-package.json"
install -m 0644 -- "$runtime_root/package-lock.json" "$stage/runtime-package-lock.json"
install -m 0644 -- "$runtime_root/README.md" "$stage/RUNTIME_README.md"
install -m 0644 -- "$runtime_root/SECURITY.md" "$stage/RUNTIME_SECURITY.md"
install -m 0644 -- "$runtime_root/LICENSES.md" "$stage/RUNTIME_LICENSES.md"

application_sha256="$(sha256sum -- "$stage/ishikawa-v1.3.1.tar.gz" | awk '{print $1}')"
image_sha256="$(sha256sum -- "$stage/node-next-runtime-amd64.tar" | awk '{print $1}')"
image_id="$(jq -r '.image_id' "$stage/runtime-image-identity.json")"
config_digest="$(jq -r '.config_digest' "$stage/runtime-image-identity.json")"
history_sha256="$(jq -r '.history_sha256' "$stage/runtime-image-identity.json")"
python3 -B - "$stage/carry-receipt.json" "$application_sha256" "$image_sha256" \
  "$image_id" "$config_digest" "$history_sha256" <<'PY'
import json
import sys
from pathlib import Path

output, application_sha256, image_sha256, image_id, config_digest, history_sha256 = sys.argv[1:]
record = {
    "application_archive_sha256": application_sha256,
    "application_release": "Ishikawa v1.3.1 candidate",
    "architecture": "amd64",
    "boot_autostart": False,
    "image_archive_sha256": image_sha256,
    "image_config_digest": config_digest,
    "image_history_sha256": history_sha256,
    "image_id": image_id,
    "image_reference": "node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64",
    "platform": "linux/amd64",
    "promotion_state": "candidate_pending_exact_byte_requalification",
    "schema": "ishikawa.carry-receipt.v1",
}
Path(output).write_text(
    json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
python3 -B - "$stage" "$stage/carry-inventory.json" <<'PY'
import hashlib
import json
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
output = Path(sys.argv[2])
purposes = {
    "ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS": ("application source provenance", "release reviewer"),
    "README.md": ("operator command sheet", "operator"),
    "RUNTIME_LICENSES.md": ("runtime license boundary", "security reviewer"),
    "RUNTIME_README.md": ("runtime architecture record", "operator and reviewer"),
    "RUNTIME_SECURITY.md": ("runtime advisory disposition", "security reviewer"),
    "application-license.json": ("application license identity", "security reviewer"),
    "application-release.json": ("application build receipt", "verifier and reviewer"),
    "application-sbom.cdx.json": ("application software inventory", "security reviewer"),
    "carry-receipt.json": ("carry identity and promotion state", "verifier and operator"),
    "deploy-ishikawa": ("consolidated deployment entrypoint", "operator"),
    "inspect-native-prerequisites": ("read-only destination inventory", "operator"),
    "ishikawa-v1.3.1.tar.gz": ("external application payload", "deployment entrypoint"),
    "ishikawa-v1.3.1.tar.gz.sha256": ("application archive checksum", "verifier"),
    "node-next-runtime-amd64.tar": ("application-free runtime image", "deployment entrypoint"),
    "node-next-runtime-amd64.tar.sha256": ("runtime archive checksum", "verifier"),
    "runtime-build-receipt.json": ("runtime build receipt", "verifier and reviewer"),
    "runtime-Dockerfile": ("runtime reproducibility input", "release reviewer"),
    "runtime-image-identity.json": ("runtime image identity", "verifier and deployment entrypoint"),
    "runtime-licenses.json": ("runtime dependency license inventory", "security reviewer"),
    "runtime-package-lock.json": ("runtime exact dependency lock", "release reviewer"),
    "runtime-package.json": ("runtime direct dependency declaration", "release reviewer"),
    "runtime-sbom.cdx.json": ("runtime software inventory", "security reviewer"),
    "verify-deployment": ("portable complete verifier", "operator"),
}
records = []
for path in sorted(root.iterdir(), key=lambda item: item.name):
    if not path.is_file() or path == output or path.name == "SHA256SUMS":
        continue
    if path.name not in purposes:
        raise SystemExit(1)
    purpose, consumer = purposes[path.name]
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    records.append({
        "consumer": consumer,
        "mode": format(stat.S_IMODE(path.stat().st_mode), "04o"),
        "path": path.name,
        "purpose": purpose,
        "sha256": digest,
        "size_bytes": path.stat().st_size,
        "type": "file",
    })
record = {
    "control_files": ["carry-inventory.json", "SHA256SUMS"],
    "file_count": len(records),
    "files": records,
    "schema": "ishikawa.carry-inventory.v1",
    "total_bytes": sum(item["size_bytes"] for item in records),
}
output.write_text(
    json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY

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
  'The assembled carry failed its complete checksum manifest.' \
  'Do not publish the candidate.'
bash "$stage/verify-deployment" >/dev/null \
  || block carry_verification_failed \
    'The assembled carry failed its portable verifier.' \
    'Correct the reported boundary before publication.'
emit "carry_verification=pass;application_sha256=${application_sha256};image_sha256=${image_sha256}"

current_stage='publication'
mkdir -p -- "$artifact_parent/superseded"
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
[[ -z "$backup" ]] || mv -- "$artifact_current" "$backup"
if ! mv -- "$stage" "$artifact_current"; then
  [[ -z "$backup" ]] || mv -- "$backup" "$artifact_current"
  block publication_failed \
    'The staged carry could not be published.' \
    'Review local filesystem state; the prior candidate was restored.'
fi
stage=''
bash "$artifact_current/verify-deployment" >/dev/null \
  || block published_handoff_verification_failed \
    'The published candidate failed verification.' \
    'Stop and inspect the candidate handoff.'
emit "publication=pass;candidate_handoff=${artifact_current};final_promotion=false"
result pass | tee -a "$report_path"

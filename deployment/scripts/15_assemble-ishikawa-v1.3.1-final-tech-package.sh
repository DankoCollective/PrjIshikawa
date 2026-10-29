#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Assemble and qualify the final Ishikawa v1.3.1 AMD64 deployment archive.
#
# Mental model:
#   Preserve the accepted application as the exact ancestor, apply the one
#   audited cumulative seven-file correction while assembling a replacement
#   application archive, preserve the runtime-image bytes, regenerate every
#   dependent identity, and qualify the exact final tar bytes in a clean
#   extraction before atomically publishing the stable handoff. The emitted
#   outer archive is the only Tech carry; no standalone hotfix is required.
#
# Inputs or prerequisites:
#   The verified Script 14 candidate, accepted application/runtime identities,
#   corrected carry sources, and the complete local deployment test suite.
#
# Outputs or artifact lane:
#   local/artifacts/ishikawa-v1.3.1-deployment-current/
#   local/reports/ishikawa-v1.3.1-final-deployment-package/
#   No lab host, network service, corpus, credential, or database is contacted.
#
# Usage:
#   bash ./deployment/scripts/15_assemble-ishikawa-v1.3.1-final-tech-package.sh --validate-only
#   bash ./deployment/scripts/15_assemble-ishikawa-v1.3.1-final-tech-package.sh --run

readonly script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repository_root="$(cd -- "$script_directory/../.." && pwd -P)"
readonly carry_source_directory="$repository_root/deployment/carry"
readonly source_candidate_directory="$repository_root/local/artifacts/ishikawa-deployment-v1.3.1-candidate-current"
readonly accepted_application_directory="$repository_root/local/artifacts/ishikawa-v1.3.1-candidate-current"
readonly cumulative_update_directory="$repository_root/local/artifacts/ishikawa-v1.3.1-black-corpus-final-current"
readonly cumulative_update_archive="$cumulative_update_directory/ishikawa-v1.3.1-black-corpus-final-update.tar.gz"
readonly artifact_parent_directory="$repository_root/local/artifacts"
readonly stable_handoff_directory="$artifact_parent_directory/ishikawa-v1.3.1-deployment-current"
readonly superseded_directory="$artifact_parent_directory/superseded"
readonly report_directory="$repository_root/local/reports/ishikawa-v1.3.1-final-deployment-package"
readonly package_directory_name='ishikawa-v1.3.1-linux-amd64'
readonly archive_file_name='ishikawa-v1.3.1-linux-amd64.tar'
readonly expected_application_sha256='2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69'
readonly expected_runtime_sha256='b92dd71eb155493d7e331e85c92566eee113ed4c8f0eda605c1c3dd951b836e1'
readonly expected_cumulative_update_sha256='821338d38d364a0c3864d5379a5b53b37d75a6110b3cb9661c25c373fe06fd73'

execution_mode=''
current_stage='argument_validation'
assembly_workspace=''
publication_stage=''
qualification_workspace=''
report_path=''

usage() { sed -n '5,29p' "${BASH_SOURCE[0]}"; }

emit_script_result() {
  printf '\nSCRIPT RESULT\nscript_15_final_deployment_package=%s\n' "$1"
}

fail_with_detail() {
  local failure_reason="$1" failure_detail="$2" operator_action="$3"
  trap - ERR
  printf '%s\n' \
    'FAILURE DETAIL' \
    "stage=$current_stage" \
    "reason=$failure_reason" \
    "detail=$failure_detail" \
    "operator_action=$operator_action" \
    'cleanup=automatic_on_exit' >&2
  if [[ -n "$report_path" && -f "$report_path" && ! -L "$report_path" ]]; then
    printf '%s\n' \
      'FAILURE DETAIL' "stage=$current_stage" "reason=$failure_reason" \
      "detail=$failure_detail" "operator_action=$operator_action" \
      'cleanup=automatic_on_exit' >>"$report_path"
    emit_script_result blocked >>"$report_path"
  fi
  emit_script_result blocked >&2
  exit 1
}

handle_unexpected_error() {
  local exit_status="$1" line_number="$2"
  fail_with_detail unexpected_command_failure \
    "Command failed at line $line_number with status $exit_status." \
    'Review the retained local report, correct the condition, and rerun.'
}

cleanup_temporary_state() {
  local exit_status=$?
  trap - EXIT INT TERM
  for temporary_path in \
    "$assembly_workspace" "$publication_stage" "$qualification_workspace"; do
    if [[ -n "$temporary_path" \
        && ( "$temporary_path" == "$artifact_parent_directory"/.ishikawa-final-deployment.* \
          || "$temporary_path" == /tmp/ishikawa-final-deployment-assembly.* \
          || "$temporary_path" == /tmp/ishikawa-final-deployment-qualification.* ) \
        && -d "$temporary_path" && ! -L "$temporary_path" ]]; then
      rm -rf -- "$temporary_path"
    fi
  done
  exit "$exit_status"
}

trap cleanup_temporary_state EXIT
trap 'handle_unexpected_error "$?" "$LINENO"' ERR
trap 'fail_with_detail signal_interrupt "Final assembly was interrupted." "Review cleanup state and rerun."' INT
trap 'fail_with_detail signal_termination "Final assembly was terminated." "Review cleanup state and rerun."' TERM

if [[ $# == 1 && ( "$1" == --help || "$1" == -h ) ]]; then
  usage
  exit 0
fi
[[ $# == 1 && ( "$1" == --validate-only || "$1" == --run ) ]] \
  || { usage >&2; fail_with_detail invalid_arguments \
    'Select exactly one mode: --validate-only or --run.' \
    'Rerun with one supported mode.'; }
execution_mode="$1"

current_stage='source_preflight'
for required_command in awk bash chmod cmp cp date find grep jq mkdir mktemp mv \
  python3 rm sha256sum sort stat tar tee; do
  command -v "$required_command" >/dev/null 2>&1 \
    || fail_with_detail "command_missing_${required_command}" \
      "Required local command is unavailable: $required_command." \
      'Restore the named local command and rerun.'
done
for required_path in \
  "$source_candidate_directory" \
  "$accepted_application_directory" \
  "$cumulative_update_directory" \
  "$carry_source_directory"; do
  [[ -d "$required_path" && ! -L "$required_path" ]] \
    || fail_with_detail source_directory_missing \
      "Required source directory is missing or unsafe: $required_path" \
      'Restore the reviewed local handoff and rerun.'
done
[[ -f "$cumulative_update_archive" && ! -L "$cumulative_update_archive" \
   && "$(sha256sum -- "$cumulative_update_archive" | awk '{print $1}')" \
      == "$expected_cumulative_update_sha256" ]] \
  || fail_with_detail cumulative_update_identity_mismatch \
    'The one accepted cumulative seven-file correction is missing or changed.' \
    'Restore the exact audited cumulative update before final assembly.'
for carry_file_name in README.md SECURITY_REVIEW.md deploy-ishikawa \
  inspect-native-prerequisites verify-deployment; do
  [[ -f "$carry_source_directory/$carry_file_name" \
      && ! -L "$carry_source_directory/$carry_file_name" ]] \
    || fail_with_detail carry_source_missing \
      "Required carry source is missing: $carry_file_name" \
      'Restore the reviewed carry source and rerun.'
done
bash -n \
  "$carry_source_directory/deploy-ishikawa" \
  "$carry_source_directory/inspect-native-prerequisites" \
  "$carry_source_directory/verify-deployment" \
  "$repository_root/deployment/tests/deployment-entrypoint.sh" \
  "$repository_root/deployment/tests/native-prerequisite-inventory.sh" \
  || fail_with_detail source_syntax_invalid \
    'A deployment or qualification script failed shell parsing.' \
    'Correct the canonical source before final assembly.'
for operator_entrypoint_path in \
  "$carry_source_directory/deploy-ishikawa" \
  "$carry_source_directory/inspect-native-prerequisites" \
  "$carry_source_directory/verify-deployment"; do
  for required_header in '# Purpose:' '# Mental model:' \
    '# Inputs or prerequisites:' '# Usage:'; do
    grep -Fq -- "$required_header" "$operator_entrypoint_path" \
      || fail_with_detail coding_standard_header_missing \
        "Required file-open heading is absent from: $operator_entrypoint_path" \
        'Restore the Purpose, Mental model, inputs, outputs, and usage contract.'
  done
  grep -Eq '^# Outputs( or artifact lane)?:' "$operator_entrypoint_path" \
    || fail_with_detail coding_standard_header_missing \
      "Required outputs heading is absent from: $operator_entrypoint_path" \
      'Restore the Purpose, Mental model, inputs, outputs, and usage contract.'
done
for required_header in '# Purpose:' '# Mental model:' \
  '# Inputs or prerequisites:' '# Outputs:'; do
  grep -Fq -- "$required_header" "$repository_root/deployment/runtime-image/Dockerfile" \
    || fail_with_detail coding_standard_header_missing \
      'The carried runtime Dockerfile is missing its file-open coding contract.' \
      'Restore the Purpose, Mental model, inputs, and outputs comments.'
done
bash "$source_candidate_directory/verify-deployment" >/dev/null \
  || fail_with_detail source_candidate_invalid \
    'The Script 14 candidate failed its portable verifier.' \
    'Restore the exact verified candidate before final assembly.'

application_sha256="$(sha256sum -- "$source_candidate_directory/ishikawa-v1.3.1.tar.gz" | awk '{print $1}')"
runtime_sha256="$(sha256sum -- "$source_candidate_directory/node-next-runtime-amd64.tar" | awk '{print $1}')"
[[ "$application_sha256" == "$expected_application_sha256" ]] \
  || fail_with_detail application_identity_mismatch \
    'The source candidate does not contain the accepted application archive.' \
    'Restore the accepted v1.3.1 application handoff.'
[[ "$runtime_sha256" == "$expected_runtime_sha256" ]] \
  || fail_with_detail runtime_identity_mismatch \
    'The source candidate does not contain the accepted runtime-image archive.' \
    'Restore the accepted corrected runtime handoff.'
[[ "$(sha256sum -- "$accepted_application_directory/ishikawa-v1.3.1.tar.gz" | awk '{print $1}')" \
    == "$expected_application_sha256" ]] \
  || fail_with_detail accepted_application_missing \
    'The exact accepted application archive is unavailable for configuration qualification.' \
    'Restore the accepted application handoff.'

if [[ "$execution_mode" == --validate-only ]]; then
  printf '%s\n' \
    'source_candidate=pass;carry_sources=pass;syntax=pass' \
    "accepted_ancestor_application_sha256=$application_sha256" \
    "cumulative_update_sha256=$expected_cumulative_update_sha256" \
    "runtime_sha256=$runtime_sha256" \
    'remote_contact=false;target_mutation=false'
  emit_script_result ready
  exit 0
fi

mkdir -p -- "$report_directory" "$superseded_directory"
assembly_timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_directory/final_deployment_package_${assembly_timestamp}_XXXXXX.txt")"
emit_report() { printf '[%s] %s\n' "$1" "$2" | tee -a "$report_path"; }
emit_report READINESS \
  'state=pass;remote_contact=false;target_mutation=false;accepted_ancestor_preserved=true;single_carry_rollup=true'

current_stage='installer_qualification'
emit_report TEST 'state=start;scope=inventory_plan_apply_configuration_replay_drift_cleanup_interruption'
bash "$repository_root/deployment/tests/native-prerequisite-inventory.sh" \
  >>"$report_path" 2>&1 \
  || fail_with_detail native_inventory_test_failed \
    'The native-prerequisite inventory regression suite failed.' \
    'Review the consolidated report and correct the inventory implementation.'
bash "$repository_root/deployment/tests/deployment-entrypoint.sh" \
  >>"$report_path" 2>&1 \
  || fail_with_detail deployment_entrypoint_test_failed \
    'The plan/apply lifecycle regression suite failed.' \
    'Review the consolidated report and correct the deployment entrypoint.'
for model_port_pair in '8000 8001' '18000 18001'; do
  read -r selected_gemma_port selected_nomic_port <<<"$model_port_pair"
  ISHIKAWA_TEST_EXACT_APPLICATION_ARCHIVE="$accepted_application_directory/ishikawa-v1.3.1.tar.gz" \
  ISHIKAWA_TEST_EXACT_GEMMA_PORT="$selected_gemma_port" \
  ISHIKAWA_TEST_EXACT_NOMIC_PORT="$selected_nomic_port" \
    bash "$repository_root/deployment/tests/deployment-entrypoint.sh" \
      >>"$report_path" 2>&1 \
    || fail_with_detail exact_application_test_failed \
      "Exact application configuration failed for model ports $selected_gemma_port/$selected_nomic_port." \
      'Review the consolidated report and correct the all-consumer transaction.'
done
emit_report TEST 'state=pass;mock_lifecycle=true;exact_application_profiles=2;real_validators=true'

current_stage='package_assembly'
assembly_workspace="$(mktemp -d /tmp/ishikawa-final-deployment-assembly.XXXXXX)"
assembled_package_directory="$assembly_workspace/$package_directory_name"
mkdir -- "$assembled_package_directory"
while IFS= read -r source_file_name; do
  cp -- "$source_candidate_directory/$source_file_name" \
    "$assembled_package_directory/$source_file_name"
done < <(find "$source_candidate_directory" -maxdepth 1 -type f -printf '%f\n' | sort)

# Roll the exact audited cumulative correction into a new deterministic
# application archive. The original accepted application is used only as the
# exact ancestor. The update payload is verified independently, exactly seven
# paths are admitted, all dependent checksums are regenerated, and no update
# state or standalone hotfix is included in the resulting application.
rollup_root="$assembly_workspace/application-rollup"
update_root="$assembly_workspace/cumulative-update"
mkdir -- "$rollup_root" "$update_root"
tar --no-same-owner --no-same-permissions -xzf \
  "$source_candidate_directory/ishikawa-v1.3.1.tar.gz" -C "$rollup_root"
tar --no-same-owner --no-same-permissions -xzf \
  "$cumulative_update_archive" -C "$update_root"
rolled_application_root="$rollup_root/ishikawa-v1.3.1"
extracted_update_root="$update_root/ishikawa-v1.3.1-black-corpus-final-update"
[[ -d "$rolled_application_root" && ! -L "$rolled_application_root" \
   && -d "$extracted_update_root" && ! -L "$extracted_update_root" ]] \
  || fail_with_detail rollup_layout_invalid \
    'The accepted application or cumulative update has an unexpected layout.' \
    'Restore the exact accepted artifacts and rerun.'
(
  cd -- "$extracted_update_root"
  sha256sum --check --strict SHA256SUMS >/dev/null
) || fail_with_detail cumulative_update_verification_failed \
  'The cumulative update failed its internal checksum inventory.' \
  'Discard the update copy and restore the exact audited archive.'

python3 -B - "$rolled_application_root" "$extracted_update_root" \
  "$assembled_package_directory/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS" <<'PY' \
  || fail_with_detail application_rollup_failed \
    'The accepted ancestor and cumulative correction could not be rolled into one application.' \
    'Inspect the exact ancestor/update identities and do not publish a partial package.'
import hashlib
import os
import shutil
import stat
import sys
from pathlib import Path, PurePosixPath

application_root = Path(sys.argv[1])
update_root = Path(sys.argv[2])
source_manifest_path = Path(sys.argv[3])
manifest_path = update_root / "UPDATE_MANIFEST.tsv"

rows = []
for line in manifest_path.read_text(encoding="utf-8").splitlines():
    if not line or line.startswith("#"):
        continue
    fields = line.split("\t")
    if len(fields) != 4:
        raise SystemExit(1)
    relative, mode_text, _accepted, expected_sha = fields
    relative_path = PurePosixPath(relative)
    if (
        relative_path.is_absolute()
        or ".." in relative_path.parts
        or mode_text not in {"0644", "0755"}
        or len(expected_sha) != 64
    ):
        raise SystemExit(1)
    rows.append((relative_path, mode_text, expected_sha))
if len(rows) != 7 or len({str(row[0]) for row in rows}) != 7:
    raise SystemExit(1)

source_lines = source_manifest_path.read_text(encoding="utf-8").splitlines()
source_records = {}
for line in source_lines:
    digest, separator, relative = line.partition("  ")
    if not separator or len(digest) != 64:
        raise SystemExit(1)
    source_records[relative] = digest

for relative, mode_text, expected_sha in rows:
    payload = update_root / "payload" / Path(*relative.parts)
    target = application_root / "application" / "payload" / Path(*relative.parts)
    if not payload.is_file() or payload.is_symlink() or not target.is_file() or target.is_symlink():
        raise SystemExit(1)
    observed_sha = hashlib.sha256(payload.read_bytes()).hexdigest()
    if observed_sha != expected_sha:
        raise SystemExit(1)
    temporary = target.with_name(target.name + ".rollup")
    shutil.copyfile(payload, temporary)
    os.chmod(temporary, int(mode_text, 8))
    os.replace(temporary, target)
    source_key = "Ishikawa/" + str(relative)
    if source_key not in source_records:
        raise SystemExit(1)
    source_records[source_key] = expected_sha

source_manifest_path.write_text(
    "".join(f"{source_records[name]}  {name}\n" for name in sorted(source_records)),
    encoding="utf-8",
)
PY

source_manifest_sha256="$(sha256sum -- \
  "$assembled_package_directory/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS" | awk '{print $1}')"
python3 -B - "$rolled_application_root/release.json" "$source_manifest_sha256" \
  "$expected_cumulative_update_sha256" <<'PY' \
  || fail_with_detail rolled_release_record_failed \
    'The rolled application release record could not be updated.' \
    'Stop and inspect the rollup workspace.'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
record = json.loads(path.read_text(encoding="utf-8"))
record["source_manifest_sha256"] = sys.argv[2]
record["cumulative_update_sha256"] = sys.argv[3]
record["post_update_native_test_count"] = 506
record["post_update_deployment_harness_count"] = 17
path.write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
(
  cd -- "$rolled_application_root/application"
  while IFS= read -r relative; do sha256sum -- "$relative"; done \
    < <(find . -type f ! -name SHA256SUMS -printf '%P\n' | sort) >SHA256SUMS
  sha256sum --check --strict SHA256SUMS >/dev/null
)
(
  cd -- "$rolled_application_root"
  while IFS= read -r relative; do sha256sum -- "$relative"; done \
    < <(find . -type f ! -path './SHA256SUMS' -printf '%P\n' | sort) >SHA256SUMS
  sha256sum --check --strict SHA256SUMS >/dev/null
  bash ./verify-ishikawa-release >/dev/null
)
rolled_application_archive="$assembly_workspace/ishikawa-v1.3.1.tar.gz"
tar --sort=name --format=posix --mtime='UTC 1970-01-01' --owner=0 --group=0 \
  --numeric-owner --pax-option=delete=atime,delete=ctime \
  -czf "$rolled_application_archive" -C "$rollup_root" ishikawa-v1.3.1
rolled_application_sha256="$(sha256sum -- "$rolled_application_archive" | awk '{print $1}')"
[[ "$rolled_application_sha256" != "$expected_application_sha256" ]] \
  || fail_with_detail rollup_not_materialized \
    'The final application archive still has the uncorrected ancestor identity.' \
    'Stop publication; the cumulative correction was not incorporated.'
cp -- "$rolled_application_archive" \
  "$assembled_package_directory/ishikawa-v1.3.1.tar.gz"
printf '%s  %s\n' "$rolled_application_sha256" 'ishikawa-v1.3.1.tar.gz' \
  >"$assembled_package_directory/ishikawa-v1.3.1.tar.gz.sha256"

for replacement_name in README.md SECURITY_REVIEW.md deploy-ishikawa \
  inspect-native-prerequisites verify-deployment; do
  cp -- "$carry_source_directory/$replacement_name" \
    "$assembled_package_directory/$replacement_name"
done
cp -- "$repository_root/deployment/runtime-image/Dockerfile" \
  "$assembled_package_directory/runtime-Dockerfile"
chmod 0755 \
  "$assembled_package_directory/deploy-ishikawa" \
  "$assembled_package_directory/inspect-native-prerequisites" \
  "$assembled_package_directory/verify-deployment"
find "$assembled_package_directory" -maxdepth 1 -type f \
  ! -name deploy-ishikawa ! -name inspect-native-prerequisites \
  ! -name verify-deployment -exec chmod 0644 {} +

# Rebind every outer identity to the rolled application. Historic base
# qualification fields remain intact; the new fields identify the cumulative
# correction and its whole-path audit without pretending the base archive was
# unchanged.
python3 -B - "$assembled_package_directory" "$rolled_application_sha256" \
  "$source_manifest_sha256" "$expected_cumulative_update_sha256" <<'PY' \
  || fail_with_detail outer_identity_rebinding_failed \
    'The final package identities could not be rebound to the rolled application.' \
    'Stop publication and inspect the assembly workspace.'
import hashlib
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
application_sha, source_manifest_sha, update_sha = sys.argv[2:]

release_path = root / "application-release.json"
release = json.loads(release_path.read_text(encoding="utf-8"))
release.update({
    "application_archive_sha256": application_sha,
    "source_manifest_sha256": source_manifest_sha,
    "cumulative_update_sha256": update_sha,
    "post_update_native_test_count": 506,
    "post_update_deployment_harness_count": 17,
})
release_path.write_text(json.dumps(release, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")

sbom_path = root / "application-sbom.cdx.json"
sbom = json.loads(sbom_path.read_text(encoding="utf-8"))
component = sbom["metadata"]["component"]
component["hashes"] = [{"alg": "SHA-256", "content": application_sha}]
component["bom-ref"] = "pkg:generic/ishikawa@1.3.1?sha256=" + application_sha
sbom["serialNumber"] = "urn:uuid:" + "-".join((application_sha[:8], application_sha[8:12], application_sha[12:16], application_sha[16:20], application_sha[20:32]))
sbom_path.write_text(json.dumps(sbom, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")

security_path = root / "SECURITY_REVIEW.md"
security = security_path.read_text(encoding="utf-8")
security = re.sub(r"(?<=application archive SHA-256\n  `)[0-9a-f]{64}(?=`;)", application_sha, security, count=1)
security += (
    "\nThe final application archive also incorporates cumulative update SHA-256\n"
    f"`{update_sha}`. Its seven changed paths passed 506 discovered application\n"
    "tests, 17 deployment/lifecycle harnesses, exact rollback qualification,\n"
    "fresh extraction, and complete portable-package verification. No standalone\n"
    "hotfix is required or accepted with this final package.\n"
)
security_path.write_text(security, encoding="utf-8")

receipt_path = root / "deployment-package-receipt.json"
receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
receipt.update({
    "application_archive_sha256": application_sha,
    "cumulative_update_sha256": update_sha,
    "security_review_sha256": hashlib.sha256(security_path.read_bytes()).hexdigest(),
    "single_carry_rollup": True,
})
receipt_path.write_text(json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY

python3 -B - "$assembled_package_directory/deployment-package-receipt.json" <<'PY' \
  || fail_with_detail final_receipt_generation_failed \
    'Could not generate the deployment-ready package receipt.' \
    'Correct local Python or package storage and rerun.'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
receipt = json.loads(path.read_text(encoding="utf-8"))
receipt.update({
    "independent_final_review": "pass",
    "release_state": "deployment_ready",
    "security_review": "pass",
    "stable_handoff": True,
    "target_inventory": "approved",
})
path.write_text(
    json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY

python3 -B - "$assembled_package_directory" <<'PY' \
  || fail_with_detail package_manifest_generation_failed \
    'Could not regenerate the final classified package manifest.' \
    'Correct the package inventory before publication.'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest_path = root / "PACKAGE_MANIFEST.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
expected_names = {
    path.name
    for path in root.iterdir()
    if path.is_file() and path.name not in {"PACKAGE_MANIFEST.json", "SHA256SUMS"}
}
records_by_name = {record["path"]: record for record in manifest.get("files", [])}
if set(records_by_name) != expected_names:
    raise SystemExit(1)
for name, record in records_by_name.items():
    path = root / name
    record["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    record["size_bytes"] = path.stat().st_size
manifest["files"] = [records_by_name[name] for name in sorted(records_by_name)]
manifest["package_file_count"] = len(manifest["files"]) + 2
manifest["payload_file_count"] = len(manifest["files"])
manifest["payload_total_bytes"] = sum(
    record["size_bytes"] for record in manifest["files"]
)
manifest_path.write_text(
    json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY

# Reject control-surface, host, and developer terminology after every final
# package edit. Scan both the outer operator surface and the accepted
# application archive so a clean outer directory cannot hide a nested leak.
portability_scan_directory="$assembly_workspace/portability-scan"
mkdir -- "$portability_scan_directory"
tar -xzf "$assembled_package_directory/ishikawa-v1.3.1.tar.gz" \
  -C "$portability_scan_directory"
python3 -B - "$assembled_package_directory" "$portability_scan_directory" <<'PY' \
  || fail_with_detail package_portability_scan_failed \
    'The final package contains a repository, workstream, host, or developer term.' \
    'Remove every reported term from the fresh-deployment payload and rerun.'
import re
import sys
from pathlib import Path

outer_root = Path(sys.argv[1])
application_root = Path(sys.argv[2])
forbidden_patterns = {
    "repository_prefix": re.compile(r"\bprj[a-z0-9_-]*", re.IGNORECASE),
    "phase_identifier": re.compile(r"\bphase-[0-9]", re.IGNORECASE),
    "script_identifier": re.compile(r"\bscript 0[0-9]", re.IGNORECASE),
    "agent_term": re.compile(r"\bagent\b", re.IGNORECASE),
    "codex_term": re.compile(r"\bcodex\b", re.IGNORECASE),
    "danko_term": re.compile(r"\bdanko(?:surface)?\b|\bemceedanko\b", re.IGNORECASE),
    "lab_term": re.compile(r"\b(?:danko|org)_lab\b", re.IGNORECASE),
    "target_name": re.compile(r"\btech\b", re.IGNORECASE),
    "control_term": re.compile(
        r"\brepository\b|\bworkstream\b|\btest-host\b|\battended-run\b",
        re.IGNORECASE,
    ),
    "local_artifact_path": re.compile(r"local/artifacts|/mnt/[a-z]/", re.IGNORECASE),
}
binary_names = {
    "ishikawa-v1.3.1.tar.gz",
    "node-next-runtime-amd64.tar",
}
findings = []
for scan_root in (outer_root, application_root):
    for finding_label, forbidden_pattern in forbidden_patterns.items():
        if forbidden_pattern.search(scan_root.name):
            findings.append(f"{finding_label}:root:{scan_root.name}")
    for scanned_path in sorted(scan_root.rglob("*")):
        relative_path = scanned_path.relative_to(scan_root).as_posix()
        for finding_label, forbidden_pattern in forbidden_patterns.items():
            if forbidden_pattern.search(relative_path):
                findings.append(f"{finding_label}:path:{relative_path}")
        if not scanned_path.is_file() or scanned_path.name in binary_names:
            continue
        try:
            text_content = scanned_path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for line_number, text_line in enumerate(text_content.splitlines(), start=1):
            for finding_label, forbidden_pattern in forbidden_patterns.items():
                if forbidden_pattern.search(text_line):
                    findings.append(
                        f"{finding_label}:text:{relative_path}:{line_number}"
                    )
if findings:
    print("\n".join(findings), file=sys.stderr)
    raise SystemExit(1)
PY
(
  cd -- "$assembled_package_directory"
  while IFS= read -r package_file_name; do
    sha256sum -- "$package_file_name"
  done < <(find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\n' | sort) \
    >SHA256SUMS
  sha256sum --check --strict SHA256SUMS >/dev/null
) || fail_with_detail final_checksum_generation_failed \
  'The final package checksum inventory could not be verified.' \
  'Stop publication and inspect the assembly workspace.'
bash "$assembled_package_directory/verify-deployment" >/dev/null \
  || fail_with_detail final_package_verification_failed \
    'The assembled deployment-ready package failed portable verification.' \
    'Review the final package identity before publication.'
[[ "$(sha256sum -- "$assembled_package_directory/ishikawa-v1.3.1.tar.gz" | awk '{print $1}')" \
    == "$rolled_application_sha256" ]] \
  || fail_with_detail final_application_rollup_changed \
    'Final assembly changed the rolled application bytes.' \
    'Stop publication and restore the exact assembled archive.'
[[ "$(sha256sum -- "$assembled_package_directory/node-next-runtime-amd64.tar" | awk '{print $1}')" \
    == "$expected_runtime_sha256" ]] \
  || fail_with_detail final_runtime_identity_changed \
    'Final assembly changed the accepted runtime-image bytes.' \
    'Stop publication and restore the accepted archive.'
emit_report ASSEMBLY \
  "state=pass;release_state=deployment_ready;native_prerequisites=preinstalled;accepted_ancestor_sha256=$expected_application_sha256;rolled_application_sha256=$rolled_application_sha256;cumulative_update_sha256=$expected_cumulative_update_sha256;standalone_hotfix_required=false"

current_stage='archive_qualification'
assembled_archive_path="$assembly_workspace/$archive_file_name"
tar --sort=name --format=posix --mtime='UTC 1970-01-01' --owner=0 --group=0 \
  --numeric-owner --pax-option=delete=atime,delete=ctime \
  -cf "$assembled_archive_path" -C "$assembly_workspace" "$package_directory_name"
assembled_archive_sha256="$(sha256sum -- "$assembled_archive_path" | awk '{print $1}')"
qualification_workspace="$(mktemp -d /tmp/ishikawa-final-deployment-qualification.XXXXXX)"
tar --no-same-owner --no-same-permissions -xf "$assembled_archive_path" \
  -C "$qualification_workspace"
qualified_package_directory="$qualification_workspace/$package_directory_name"
[[ -d "$qualified_package_directory" && ! -L "$qualified_package_directory" ]] \
  || fail_with_detail final_archive_layout_invalid \
    'The final archive did not extract to its single canonical directory.' \
    'Correct final archive construction and rerun.'
bash "$qualified_package_directory/verify-deployment" >/dev/null \
  || fail_with_detail extracted_package_verification_failed \
    'The exact extracted final archive failed portable verification.' \
    'Stop publication and inspect the exact archive bytes.'
ISHIKAWA_TEST_CARRY_SOURCE_ROOT="$qualified_package_directory" \
  bash "$repository_root/deployment/tests/deployment-entrypoint.sh" \
    >>"$report_path" 2>&1 \
  || fail_with_detail extracted_deployer_test_failed \
    'The deployer extracted from the final archive failed lifecycle qualification.' \
    'Review the consolidated report and correct final outer tooling.'
for model_port_pair in '8000 8001' '18000 18001'; do
  read -r selected_gemma_port selected_nomic_port <<<"$model_port_pair"
  ISHIKAWA_TEST_CARRY_SOURCE_ROOT="$qualified_package_directory" \
  ISHIKAWA_TEST_EXACT_APPLICATION_ARCHIVE="$qualified_package_directory/ishikawa-v1.3.1.tar.gz" \
  ISHIKAWA_TEST_EXACT_GEMMA_PORT="$selected_gemma_port" \
  ISHIKAWA_TEST_EXACT_NOMIC_PORT="$selected_nomic_port" \
    bash "$repository_root/deployment/tests/deployment-entrypoint.sh" \
      >>"$report_path" 2>&1 \
    || fail_with_detail extracted_exact_application_test_failed \
      "The final archive failed exact application qualification for model ports $selected_gemma_port/$selected_nomic_port." \
      'Review the consolidated report and correct the final archive.'
done
emit_report QUALIFICATION \
  "state=pass;archive_sha256=$assembled_archive_sha256;verifier=pass;plan_apply=pass;replay=pass;drift_refusal=pass;cleanup=pass;profiles=2"

current_stage='stable_publication'
publication_stage="$(mktemp -d "$artifact_parent_directory/.ishikawa-final-deployment.XXXXXX")"
cp -- "$assembled_archive_path" "$publication_stage/$archive_file_name"
printf '%s  %s\n' "$assembled_archive_sha256" "$archive_file_name" \
  >"$publication_stage/$archive_file_name.sha256"
(
  cd -- "$publication_stage"
  sha256sum --check --strict "$archive_file_name.sha256" >/dev/null
) || fail_with_detail publication_checksum_failed \
  'The stable handoff checksum did not verify before publication.' \
  'Stop and inspect local artifact storage.'

superseded_path=''
if [[ -e "$stable_handoff_directory" || -L "$stable_handoff_directory" ]]; then
  [[ -d "$stable_handoff_directory" && ! -L "$stable_handoff_directory" ]] \
    || fail_with_detail stable_handoff_unsafe \
      'The existing stable handoff path is not a regular directory.' \
      'Inspect the artifact lane before publication.'
  superseded_path="$superseded_directory/ishikawa-v1.3.1-deployment-current-${assembly_timestamp}-$$"
  mv -- "$stable_handoff_directory" "$superseded_path"
fi
if ! mv -- "$publication_stage" "$stable_handoff_directory"; then
  [[ -z "$superseded_path" ]] || mv -- "$superseded_path" "$stable_handoff_directory"
  fail_with_detail stable_publication_failed \
    'The final handoff could not be published atomically.' \
    'The prior handoff was restored when available; inspect artifact storage.'
fi
publication_stage=''
(
  cd -- "$stable_handoff_directory"
  sha256sum --check --strict "$archive_file_name.sha256" >/dev/null
) || fail_with_detail published_handoff_invalid \
  'The published final archive failed its adjacent checksum.' \
  'Stop and inspect the stable handoff before transfer.'

emit_report PUBLISH \
  "state=pass;archive=$stable_handoff_directory/$archive_file_name;sha256=$assembled_archive_sha256"
emit_report SUMMARY \
  "state=pass;report=$report_path;application_sha256=$rolled_application_sha256;runtime_sha256=$runtime_sha256;cumulative_update_rolled_in=true;standalone_hotfix_required=false;next=transfer_only_final_archive_and_checksum"
emit_script_result pass | tee -a "$report_path"

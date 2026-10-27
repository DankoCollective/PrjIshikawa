#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Exercise deployment-package assembly and refusal branches with private
#   fixtures only.
#
# Mental model:
#   Create exact-shaped application, corrected image, qualification, promotion,
#   and security fixtures; run the active assembler through success, rerun, supersession,
#   and adjacent refusal paths; then prove no fixture survives cleanup.
#
# Inputs or prerequisites:
#   Local shell, Python, jq, tar, and checksum tools. No target is contacted.
#
# Outputs or artifact lane:
#   Temporary files exist only beneath /tmp and are removed on exit.

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly expected_application_sha256='2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69'
readonly expected_runtime_sha256='b92dd71eb155493d7e331e85c92566eee113ed4c8f0eda605c1c3dd951b836e1'
readonly expected_image_id='sha256:6c93bcb5ed22de92420c4de4892eecdd08f1badc8b19e4d6f4488711f8f7a31a'
readonly expected_config_digest='sha256:ccbae1b68ecf82121ce76080793cb7febdf1d6df1653995db02fc2f83233228f'
readonly expected_scan_sha256='ce251960fdc20726a73fa49cc4f417761ee90c392592a3a5d7eeb6dae540971c'
test_root="$(mktemp -d /tmp/ishikawa-carry-builder.XXXXXX)"
real_df="$(command -v df)"
real_cp="$(command -v cp)"
real_chmod="$(command -v chmod)"
real_python3="$(command -v python3)"

fail() {
  printf '\nSCRIPT RESULT\nishikawa_carry_builder_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$test_root" == /tmp/ishikawa-carry-builder.* && -d "$test_root" ]] \
    && rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$test_root/bin"
cat >"$test_root/bin/df" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${ISHIKAWA_TEST_LOW_CAPACITY:-0}" == 1 ]]; then
  printf '%s\n' \
    'Filesystem 1-blocks Used Available Capacity Mounted on' \
    'fixture 100 99 1 99% /tmp'
  exit 0
fi
exec "${ISHIKAWA_TEST_REAL_DF:?}" "$@"
MOCK
chmod 0755 "$test_root/bin/df"
cat >"$test_root/bin/cp" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${ISHIKAWA_TEST_COPY_FAIL:-0}" != 1 ]] || exit 88
exec "${ISHIKAWA_TEST_REAL_CP:?}" "$@"
MOCK
chmod 0755 "$test_root/bin/cp"
cat >"$test_root/bin/chmod" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${ISHIKAWA_TEST_CHMOD_FAIL:-0}" != 1 ]] || exit 87
exec "${ISHIKAWA_TEST_REAL_CHMOD:?}" "$@"
MOCK
chmod 0755 "$test_root/bin/chmod"
cat >"$test_root/bin/python3" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${ISHIKAWA_TEST_RECORD_GENERATION_FAIL:-0}" == 1 ]]; then
  for argument in "$@"; do
    [[ "$argument" != */application-release.json ]] || exit 89
  done
fi
exec "${ISHIKAWA_TEST_REAL_PYTHON3:?}" "$@"
MOCK
chmod 0755 "$test_root/bin/python3"
export ISHIKAWA_TEST_REAL_DF="$real_df"
export ISHIKAWA_TEST_REAL_CP="$real_cp"
export ISHIKAWA_TEST_REAL_CHMOD="$real_chmod"
export ISHIKAWA_TEST_REAL_PYTHON3="$real_python3"
export PATH="$test_root/bin:$PATH"

fixture="$test_root/repo"
mkdir -p -- \
  "$fixture/deployment/scripts" "$fixture/deployment/carry" \
  "$fixture/docs/decisions" "$fixture/deployment/evidence" \
  "$fixture/local/reports/ishikawa-v1.3.1-security-review" \
  "$fixture/local/artifacts/ishikawa-v1.3.1-candidate-current" \
  "$fixture/local/artifacts/node-next-runtime-current" \
  "$fixture/local/artifacts/emceedanko-v1.3.1-runtime-requalification-current" \
  "$fixture/local/artifacts/emceedanko-v1.3.1-corrected-runtime-promotion-current"
cp -- "$repo_root/deployment/scripts/14_assemble-v1.3.1-corrected-deployment-package.sh" \
  "$fixture/deployment/scripts/"
cp -- "$repo_root/deployment/carry/"* "$fixture/deployment/carry/"
cp -- "$repo_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md" "$fixture/docs/decisions/"

application="$fixture/local/artifacts/ishikawa-v1.3.1-candidate-current"
mkdir -p -- "$test_root/application/ishikawa-v1.3.1"
cat >"$test_root/application/ishikawa-v1.3.1/verify-ishikawa-release" <<'MOCK'
#!/usr/bin/env bash
printf 'ishikawa_release_verification=pass\n'
MOCK
chmod 0755 "$test_root/application/ishikawa-v1.3.1/verify-ishikawa-release"
tar -czf "$application/ishikawa-v1.3.1.tar.gz" -C "$test_root/application" ishikawa-v1.3.1
(cd -- "$application" && sha256sum ishikawa-v1.3.1.tar.gz >ishikawa-v1.3.1.tar.gz.sha256)
printf '%064d  Ishikawa/fixture\n' 0 >"$application/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS"
printf '%s\n' \
  '{"coding_standard":"pass","deterministic_archive":true,"fresh_install":"pass","human_ui_validation":"pending_exact_candidate_requalification","release":"Ishikawa v1.3.1 candidate"}' \
  >"$application/release-receipt.json"
printf '%s\n' \
  '{"bomFormat":"CycloneDX","metadata":{"component":{"name":"Ishikawa","version":"1.3.1"}}}' \
  >"$application/application-sbom.cdx.json"
printf '%s\n' \
  '{"application_license":"Apache-2.0","schema":"ishikawa.application-license.v1"}' \
  >"$application/application-license.json"
(
  cd -- "$application"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
  ) >SHA256SUMS
)

runtime="$fixture/local/artifacts/node-next-runtime-current"
mkdir -p -- "$test_root/image/blobs/sha256"
printf '%s\n' \
  '{"architecture":"amd64","os":"linux","config":{"WorkingDir":"/opt/nextjs","Cmd":["next","--help"]},"rootfs":{"type":"layers","diff_ids":["sha256:0000000000000000000000000000000000000000000000000000000000000004"]},"history":[{"created_by":"generic runtime layer"}]}' \
  >"$test_root/image/config.json"
config_hex="$(sha256sum "$test_root/image/config.json" | awk '{print $1}')"
history_sha="$(jq -cS .history "$test_root/image/config.json" | sha256sum | awk '{print $1}')"
printf 'mock compressed layer\n' >"$test_root/image/layer"
layer_hex="$(sha256sum "$test_root/image/layer" | awk '{print $1}')"
mv -- "$test_root/image/config.json" "$test_root/image/blobs/sha256/$config_hex"
mv -- "$test_root/image/layer" "$test_root/image/blobs/sha256/$layer_hex"
printf '[{"Config":"blobs/sha256/%s","RepoTags":["node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64"],"Layers":["blobs/sha256/%s"]}]\n' \
  "$config_hex" "$layer_hex" >"$test_root/image/manifest.json"
tar -cf "$runtime/node-next-runtime-amd64.tar" -C "$test_root/image" manifest.json blobs
image_sha="$(sha256sum "$runtime/node-next-runtime-amd64.tar" | awk '{print $1}')"
(cd -- "$runtime" && sha256sum node-next-runtime-amd64.tar >node-next-runtime-amd64.tar.sha256)
python3 -B - "$runtime/image-identity.json" "$image_sha" "$config_hex" "$history_sha" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "application_in_image": False,
    "archive_sha256": sys.argv[2],
    "architecture": "amd64",
    "base_bundled_npm_executed": False,
    "base_bundled_yarn_executed": False,
    "build_npm": "11.21.1",
    "build_npm_archive_sha256": "dd77c48eb845f4856c2cdba347cfb52bd877a2655a1ea48ff0c4796e3df9dd7b",
    "config_digest": "sha256:" + sys.argv[3],
    "generated_next_in_image": False,
    "history_sha256": sys.argv[4],
    "image_id": "sha256:" + "0" * 64,
    "image_reference": "node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64",
    "next": "16.4.3",
    "node": "24.22.1",
    "platform": "linux/amd64",
    "react": "19.2.9",
    "react_dom": "19.2.9",
    "runtime_npm": False,
    "runtime_yarn": False,
    "schema": "node-next-runtime-image.v3",
    "tzdata": "2026e-0+deb12u1",
}, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
printf '%s\n' \
  '{"bomFormat":"CycloneDX","specVersion":"1.5","metadata":{"component":{"properties":[{"name":"oci:image:config-digest","value":"sha256:'"$config_hex"'"}]}},"components":[{"name":"node","version":"24.22.1","licenses":[{"license":{"id":"MIT"}}]}]}' \
  >"$runtime/sbom.cdx.json"
printf '%s\n' \
  '{"schema":"node-runtime-license-inventory.v2","build_tools":[{"name":"npm","version":"11.21.1","archive_sha256":"dd77c48eb845f4856c2cdba347cfb52bd877a2655a1ea48ff0c4796e3df9dd7b","base_bundled_copy_executed":false,"retained_in_runtime":false}],"javascript_packages":[],"operating_system_packages":[],"runtime_tools":[{"name":"node","version":"24.22.1","license":"MIT","license_file":"/usr/local/LICENSE","license_sha256":"'"$(printf '%064d' 1)"'"}]}' \
  >"$runtime/licenses.json"
sbom_sha="$(sha256sum "$runtime/sbom.cdx.json" | awk '{print $1}')"
licenses_sha="$(sha256sum "$runtime/licenses.json" | awk '{print $1}')"
python3 -B - "$runtime/build-receipt.json" "$image_sha" "$config_hex" \
  "$history_sha" "$sbom_sha" "$licenses_sha" <<'PY'
import json
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "archive_sha256": sys.argv[2],
    "architecture": "amd64",
    "base_bundled_npm_executed": False,
    "base_bundled_yarn_executed": False,
    "build_npm": "11.21.1",
    "build_npm_archive_sha256": "dd77c48eb845f4856c2cdba347cfb52bd877a2655a1ea48ff0c4796e3df9dd7b",
    "config_digest": "sha256:" + sys.argv[3],
    "history_sha256": sys.argv[4],
    "image_id": "sha256:" + "0" * 64,
    "image_reference": "node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64",
    "platform": "linux/amd64",
    "runtime_npm": False,
    "runtime_yarn": False,
    "sbom_sha256": sys.argv[5],
    "licenses_sha256": sys.argv[6],
    "schema": "node-next-runtime-build-receipt.v3",
    "tzdata": "2026e-0+deb12u1",
}, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
printf 'FROM scratch\n' >"$runtime/Dockerfile"
printf '{"name":"node-next-runtime"}\n' >"$runtime/package.json"
printf '{"lockfileVersion":3}\n' >"$runtime/package-lock.json"
printf 'Generic runtime.\n' >"$runtime/README.md"
printf 'Reviewed security disposition.\n' >"$runtime/SECURITY.md"
printf 'License inventory accompanies this file.\n' >"$runtime/LICENSES.md"
(
  cd -- "$runtime"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
  ) >SHA256SUMS
)

application_sha="$(sha256sum "$application/ishikawa-v1.3.1.tar.gz" | awk '{print $1}')"
fixture_image_id="sha256:$(printf '%064d' 0)"
python3 -B - "$application/release-receipt.json" "$application_sha" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
record = json.loads(path.read_text(encoding="utf-8"))
record["archive_sha256"] = sys.argv[2]
record["source_manifest_sha256"] = "a" * 64
path.write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
(
  cd -- "$application"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
  ) >SHA256SUMS
)
requalification="$fixture/local/artifacts/emceedanko-v1.3.1-runtime-requalification-current"
promotion="$fixture/local/artifacts/emceedanko-v1.3.1-corrected-runtime-promotion-current"
printf '%s\n' \
  'schema=ishikawa.emceedanko-v1.3.1-runtime-qualification.v1' \
  "application_archive_sha256=$application_sha" \
  "runtime_archive_sha256=$image_sha" \
  "image_id=$fixture_image_id" \
  'production_build_start=pass' \
  'frontier_cases=60/60' \
  >"$requalification/qualification-receipt.txt"
printf '%s\n' \
  'schema=ishikawa.emceedanko-v1.3.1-runtime-qualification-acceptance.v1' \
  "application_archive_sha256=$application_sha" \
  "runtime_archive_sha256=$image_sha" \
  "image_id=$fixture_image_id" \
  'human_ui_acceptance=accepted' \
  'production_build_start=pass' \
  'frontier_cases=60/60' \
  >"$requalification/acceptance-receipt.txt"
printf '%s\n' \
  'schema=ishikawa.emceedanko-v1.3.1-runtime-qualification-action.v1' \
  'mode=cleanup' \
  'state=pass' \
  'detail=candidate_removed=true' \
  "image_id=$fixture_image_id" \
  >"$requalification/cleanup-receipt.txt"
(
  cd -- "$requalification"
  sha256sum -- qualification-receipt.txt acceptance-receipt.txt cleanup-receipt.txt >SHA256SUMS
)
printf '%s\n' \
  'schema=ishikawa.emceedanko-v1.3.1-runtime-promotion.v1' \
  "application_archive_sha256=$application_sha" \
  "runtime_archive_sha256=$image_sha" \
  "image_id=$fixture_image_id" \
  'production_build_start=pass' \
  'human_ui_acceptance=pending' \
  'application_mutated=false' \
  'database_mutated=false' \
  'boot_autostart=false' \
  >"$promotion/promotion-receipt.txt"
(
  cd -- "$promotion"
  sha256sum -- promotion-receipt.txt >SHA256SUMS
)

printf '%s\n' \
  '# Ishikawa v1.3.1 security review' \
  "$image_sha" "$fixture_image_id" \
  'production_promotion_and_acceptance=pass' \
  >"$fixture/deployment/evidence/ISHIKAWA_V1_3_1_SECURITY_REVIEW.md"
printf '%s\n' \
  '# Ishikawa v1.3.1 security review' \
  "$application_sha" "$image_sha" "$fixture_image_id" \
  "sha256:$config_hex" \
  >"$fixture/deployment/carry/SECURITY_REVIEW.md"
printf '%s\n' \
  '{"SchemaVersion":2,"ArtifactType":"container_image","Metadata":{"OS":{"Family":"debian","Name":"12.15"}},"Results":[{"Type":"debian","Vulnerabilities":[]},{"Type":"node-pkg","Vulnerabilities":[]}]}' \
  >"$fixture/local/reports/ishikawa-v1.3.1-security-review/runtime-vulnerabilities-trivy-0.76.1-corrected-20261026.json"
fixture_scan_sha="$(sha256sum "$fixture/local/reports/ishikawa-v1.3.1-security-review/runtime-vulnerabilities-trivy-0.76.1-corrected-20261026.json" | awk '{print $1}')"

builder="$fixture/deployment/scripts/14_assemble-v1.3.1-corrected-deployment-package.sh"
sed -i \
  -e "s/$expected_application_sha256/$application_sha/g" \
  -e "s/$expected_runtime_sha256/$image_sha/g" \
  -e "s/$expected_image_id/$fixture_image_id/g" \
  -e "s/$expected_config_digest/sha256:$config_hex/g" \
  -e "s/$expected_scan_sha256/$fixture_scan_sha/g" \
  "$builder"
validation_output="$(bash "$builder" --validate-only 2>&1)" || fail validate_only_failed
grep -Fxq 'script_14_ishikawa_v1_3_1_corrected_package_assembly=ready' <<<"$validation_output" \
  || fail validate_ready_marker_missing

set +e
acceptance_missing_output="$(bash "$builder" --run 2>&1)"
acceptance_missing_status="$?"
set -e
(( acceptance_missing_status != 0 )) || fail missing_promotion_acceptance_reported_success
grep -Fq 'reason=script13_acceptance_invalid' <<<"$acceptance_missing_output" \
  || fail missing_promotion_acceptance_reason_missing
printf '%s\n' \
  'schema=ishikawa.emceedanko-v1.3.1-runtime-promotion-acceptance.v1' \
  "application_archive_sha256=$application_sha" \
  "runtime_archive_sha256=$image_sha" \
  "image_id=$fixture_image_id" \
  'human_ui_acceptance=accepted' \
  'production_runtime=pass' \
  'frontier_cases=60/60' \
  'superseded_runtime_image_removed=true' \
  'previous_runtime_rollback=retired' \
  'application_mutated=false' \
  'retrieval_api_restarted=false' \
  'postgresql_restarted=false' \
  'database_mutated=false' \
  'schema_mutated=false' \
  'corpus_mutated=false' \
  'boot_autostart=false' \
  >"$promotion/acceptance-receipt.txt"
(
  cd -- "$promotion"
  sha256sum -- promotion-receipt.txt acceptance-receipt.txt >SHA256SUMS
)

portable_security="$fixture/deployment/carry/SECURITY_REVIEW.md"
security_record="$fixture/deployment/evidence/ISHIKAWA_V1_3_1_SECURITY_REVIEW.md"
security_scan="$fixture/local/reports/ishikawa-v1.3.1-security-review/runtime-vulnerabilities-trivy-0.76.1-corrected-20261026.json"
cp -- "$portable_security" "$test_root/portable-security.md"
rm -f -- "$portable_security"
set +e
security_source_output="$(bash "$builder" --run 2>&1)"
security_source_status="$?"
set -e
(( security_source_status != 0 )) || fail missing_security_source_reported_success
grep -Fq 'reason=carry_source_unsafe' <<<"$security_source_output" \
  || fail missing_security_source_reason_missing
mv -- "$test_root/portable-security.md" "$portable_security"

cp -- "$security_scan" "$test_root/security-scan.json"
printf '%s\n' altered-scan >"$security_scan"
set +e
security_hash_output="$(bash "$builder" --run 2>&1)"
security_hash_status="$?"
set -e
(( security_hash_status != 0 )) || fail changed_security_scan_reported_success
grep -Fq 'reason=security_scan_identity_mismatch' <<<"$security_hash_output" \
  || fail changed_security_scan_reason_missing
mv -- "$test_root/security-scan.json" "$security_scan"

original_fixture_scan_sha="$fixture_scan_sha"
printf '%s\n' \
  '{"SchemaVersion":2,"ArtifactType":"container_image","Metadata":{"OS":{"Family":"debian","Name":"12.15"}},"Results":[{"Type":"debian","Vulnerabilities":[{"VulnerabilityID":"fixture","FixedVersion":"1"}]},{"Type":"node-pkg","Vulnerabilities":[]}]}' \
  >"$security_scan"
invalid_scan_sha="$(sha256sum "$security_scan" | awk '{print $1}')"
sed -i "s/$original_fixture_scan_sha/$invalid_scan_sha/g" "$builder"
set +e
security_contract_output="$(bash "$builder" --run 2>&1)"
security_contract_status="$?"
set -e
(( security_contract_status != 0 )) || fail invalid_security_contract_reported_success
grep -Fq 'reason=security_scan_contract_invalid' <<<"$security_contract_output" \
  || fail invalid_security_contract_reason_missing
printf '%s\n' \
  '{"SchemaVersion":2,"ArtifactType":"container_image","Metadata":{"OS":{"Family":"debian","Name":"12.15"}},"Results":[{"Type":"debian","Vulnerabilities":[]},{"Type":"node-pkg","Vulnerabilities":[]}]}' \
  >"$security_scan"
fixture_scan_sha="$(sha256sum "$security_scan" | awk '{print $1}')"
sed -i "s/$invalid_scan_sha/$fixture_scan_sha/g" "$builder"

cp -- "$security_record" "$test_root/security-record.md"
sed -i '/production_promotion_and_acceptance=pass/d' "$security_record"
set +e
security_record_output="$(bash "$builder" --run 2>&1)"
security_record_status="$?"
set -e
(( security_record_status != 0 )) || fail stale_security_record_reported_success
grep -Fq 'reason=security_review_record_invalid' <<<"$security_record_output" \
  || fail stale_security_record_reason_missing
mv -- "$test_root/security-record.md" "$security_record"

cp -- "$portable_security" "$test_root/portable-security.md"
printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$portable_security"
set +e
secret_shape_output="$(bash "$builder" --run 2>&1)"
secret_shape_status="$?"
set -e
(( secret_shape_status != 0 )) || fail secret_shape_reported_success
grep -Fq 'reason=secret_material_found' <<<"$secret_shape_output" \
  || fail secret_shape_reason_missing
mv -- "$test_root/portable-security.md" "$portable_security"

set +e
capacity_output="$(ISHIKAWA_TEST_LOW_CAPACITY=1 bash "$builder" --run 2>&1)"
capacity_status="$?"
set -e
(( capacity_status != 0 )) || fail insufficient_capacity_reported_success
grep -Fq 'reason=insufficient_artifact_capacity' <<<"$capacity_output" \
  || fail insufficient_capacity_reason_missing
[[ ! -e "$fixture/local/artifacts/ishikawa-deployment-v1.3.1-candidate-current" ]] \
  || fail insufficient_capacity_published_candidate

set +e
copy_output="$(ISHIKAWA_TEST_COPY_FAIL=1 bash "$builder" --run 2>&1)"
copy_status="$?"
set -e
(( copy_status != 0 )) || fail payload_copy_failure_reported_success
grep -Fq 'reason=payload_copy_failed' <<<"$copy_output" \
  || fail payload_copy_failure_reason_missing
[[ ! -e "$fixture/local/artifacts/ishikawa-deployment-v1.3.1-candidate-current" \
    && -z "$(find "$fixture/local/artifacts" -maxdepth 1 -type d \
      -name '.ishikawa-deployment-v1.3.1-candidate-current.*' -print -quit)" ]] \
  || fail payload_copy_failure_cleanup_incomplete

set +e
record_output="$(ISHIKAWA_TEST_RECORD_GENERATION_FAIL=1 bash "$builder" --run 2>&1)"
record_status="$?"
set -e
(( record_status != 0 )) || fail record_generation_failure_reported_success
grep -Fq 'reason=application_release_generation_failed' <<<"$record_output" \
  || fail record_generation_failure_reason_missing
[[ ! -e "$fixture/local/artifacts/ishikawa-deployment-v1.3.1-candidate-current" \
    && -z "$(find "$fixture/local/artifacts" -maxdepth 1 -type d \
      -name '.ishikawa-deployment-v1.3.1-candidate-current.*' -print -quit)" ]] \
  || fail record_generation_failure_cleanup_incomplete

run_output="$(ISHIKAWA_TEST_CHMOD_FAIL=1 bash "$builder" --run 2>&1)" \
  || { printf '%s\n' "$run_output" >&2; fail success_path_failed; }
grep -Fxq 'script_14_ishikawa_v1_3_1_corrected_package_assembly=pass' <<<"$run_output" \
  || fail success_marker_missing
handoff="$fixture/local/artifacts/ishikawa-deployment-v1.3.1-candidate-current"
bash "$handoff/verify-deployment" >/dev/null || fail published_verification_failed
jq -e \
  '.release == "Ishikawa v1.3.1"
   and .human_ui_validation == "accepted"
   and .production_runtime == "pass"' \
  "$handoff/application-release.json" >/dev/null \
  || fail canonical_application_release_invalid
jq -e \
  '.schema == "ishikawa.deployment-package-manifest.v1"
   and .package_file_count == 26
   and .payload_file_count == 24
   and .primary_payloads == ["ishikawa-v1.3.1.tar.gz", "node-next-runtime-amd64.tar"]' \
  "$handoff/PACKAGE_MANIFEST.json" >/dev/null \
  || fail package_manifest_invalid

second_output="$(bash "$builder" --run 2>&1)" || fail rerun_failed
grep -Fxq 'script_14_ishikawa_v1_3_1_corrected_package_assembly=pass' <<<"$second_output" \
  || fail rerun_marker_missing
[[ "$(find "$fixture/local/artifacts/superseded" -mindepth 1 -maxdepth 1 -type d | wc -l)" == 1 ]] \
  || fail superseded_count_invalid

cp -- "$application/ishikawa-v1.3.1.tar.gz.sha256" "$test_root/application.sha256"
printf '%064d  ishikawa-v1.3.1.tar.gz\n' 0 >"$application/ishikawa-v1.3.1.tar.gz.sha256"
set +e
checksum_output="$(bash "$builder" --run 2>&1)"
checksum_status="$?"
set -e
(( checksum_status != 0 )) || fail checksum_failure_reported_success
grep -Fq 'reason=handoff_checksum_failed' <<<"$checksum_output" \
  || fail checksum_failure_reason_missing
mv -- "$test_root/application.sha256" "$application/ishikawa-v1.3.1.tar.gz.sha256"
(
  cd -- "$application"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
  ) >SHA256SUMS
)

cp -- "$runtime/image-identity.json" "$test_root/provenance-image-identity.json"
cp -- "$runtime/build-receipt.json" "$test_root/provenance-build-receipt.json"
python3 -B - "$runtime/image-identity.json" "$runtime/build-receipt.json" <<'PY'
import json
import sys
from pathlib import Path
for name in sys.argv[1:]:
    path = Path(name)
    record = json.loads(path.read_text(encoding="utf-8"))
    record["history_sha256"] = "f" * 64
    path.write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
(
  cd -- "$runtime"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
  ) >SHA256SUMS
)
set +e
provenance_output="$(bash "$builder" --run 2>&1)"
provenance_status="$?"
set -e
(( provenance_status != 0 )) || fail provenance_failure_reported_success
grep -Fq 'reason=portable_verification_failed' <<<"$provenance_output" \
  || fail provenance_failure_reason_missing
mv -- "$test_root/provenance-image-identity.json" "$runtime/image-identity.json"
mv -- "$test_root/provenance-build-receipt.json" "$runtime/build-receipt.json"
(
  cd -- "$runtime"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
  ) >SHA256SUMS
)

cp -- "$runtime/image-identity.json" "$test_root/image-identity.json"
python3 -B - "$runtime/image-identity.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
record = json.loads(path.read_text(encoding="utf-8"))
record["architecture"] = "arm64"
path.write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
(
  cd -- "$runtime"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
  ) >SHA256SUMS
)
set +e
identity_output="$(bash "$builder" --run 2>&1)"
identity_status="$?"
set -e
(( identity_status != 0 )) || fail identity_failure_reported_success
grep -Fq 'reason=runtime_identity_record_invalid' <<<"$identity_output" \
  || fail identity_failure_reason_missing
mv -- "$test_root/image-identity.json" "$runtime/image-identity.json"
(
  cd -- "$runtime"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
  ) >SHA256SUMS
)

printf ' Codex\n' >>"$fixture/deployment/carry/README.md"
set +e
language_output="$(bash "$builder" --run 2>&1)"
language_status="$?"
set -e
(( language_status != 0 )) || fail language_failure_reported_success
grep -Fq 'reason=package_language_invalid' <<<"$language_output" \
  || fail language_failure_reason_missing

printf '%s\n' \
  'acceptance_gate=pass;security_source_gate=pass;security_hash_gate=pass;security_contract_gate=pass;security_record_gate=pass;secret_scan_gate=pass' \
  'capacity_gate=pass;copy_failure=pass;record_failure=pass;mode_neutral_storage=pass' \
  'success=pass;rerun=pass;supersession=pass;published_verification=pass' \
  'application_release=pass;classified_manifest=pass;checksum_refusal=pass' \
  'provenance_refusal=pass;identity_refusal=pass;terminology_refusal=pass'
printf '\nSCRIPT RESULT\nishikawa_carry_builder_test=pass\n'

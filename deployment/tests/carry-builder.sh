#!/usr/bin/env bash
set -Eeuo pipefail

# Exercise portable carry assembly and refusal branches with private fixtures.

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
test_root="$(mktemp -d /tmp/ishikawa-carry-builder.XXXXXX)"

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

fixture="$test_root/repo"
mkdir -p -- \
  "$fixture/deployment/scripts" "$fixture/deployment/carry" \
  "$fixture/docs/decisions" \
  "$fixture/Ishikawa/packaging/native-prerequisite-inventory" \
  "$fixture/local/artifacts/ishikawa-v1.3.1-candidate-current" \
  "$fixture/local/artifacts/node-next-runtime-current"
cp -- "$repo_root/deployment/scripts/build-carry-candidate.sh" "$fixture/deployment/scripts/"
cp -- "$repo_root/deployment/carry/"* "$fixture/deployment/carry/"
cp -- "$repo_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md" "$fixture/docs/decisions/"
cp -- "$repo_root/Ishikawa/packaging/native-prerequisite-inventory/inspect-native-prerequisites" \
  "$fixture/Ishikawa/packaging/native-prerequisite-inventory/"

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
mkdir -p -- "$test_root/image"
printf '[]\n' >"$test_root/image/manifest.json"
tar -cf "$runtime/node-next-runtime-amd64.tar" -C "$test_root/image" manifest.json
image_sha="$(sha256sum "$runtime/node-next-runtime-amd64.tar" | awk '{print $1}')"
(cd -- "$runtime" && sha256sum node-next-runtime-amd64.tar >node-next-runtime-amd64.tar.sha256)
python3 -B - "$runtime/image-identity.json" "$image_sha" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "application_in_image": False,
    "archive_sha256": sys.argv[2],
    "architecture": "amd64",
    "generated_next_in_image": False,
    "image_id": "sha256:" + "0" * 64,
    "image_reference": "node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64",
    "next": "16.4.3",
    "node": "24.22.1",
    "platform": "linux/amd64",
    "react": "19.2.9",
    "react_dom": "19.2.9",
    "schema": "node-next-runtime-image.v1",
}, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
python3 -B - "$runtime/build-receipt.json" "$image_sha" <<'PY'
import json
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "archive_sha256": sys.argv[2],
    "architecture": "amd64",
    "image_id": "sha256:" + "0" * 64,
    "image_reference": "node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64",
    "platform": "linux/amd64",
    "schema": "node-next-runtime-build-receipt.v1",
}, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
printf '{"bomFormat":"CycloneDX"}\n' >"$runtime/sbom.cdx.json"
printf '{"schema":"node-runtime-license-inventory.v1"}\n' >"$runtime/licenses.json"
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

builder="$fixture/deployment/scripts/build-carry-candidate.sh"
validation_output="$(bash "$builder" --validate-only 2>&1)" || fail validate_only_failed
grep -Fxq 'ishikawa_carry_candidate_build=ready' <<<"$validation_output" \
  || fail validate_ready_marker_missing

run_output="$(bash "$builder" --run 2>&1)" || fail success_path_failed
grep -Fxq 'ishikawa_carry_candidate_build=pass' <<<"$run_output" \
  || fail success_marker_missing
handoff="$fixture/local/artifacts/ishikawa-deployment-v1.3.1-candidate-current"
bash "$handoff/verify-deployment" >/dev/null || fail published_verification_failed

second_output="$(bash "$builder" --run 2>&1)" || fail rerun_failed
grep -Fxq 'ishikawa_carry_candidate_build=pass' <<<"$second_output" \
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
grep -Fq 'reason=application_handoff_checksum_failed' <<<"$checksum_output" \
  || fail checksum_failure_reason_missing
mv -- "$test_root/application.sha256" "$application/ishikawa-v1.3.1.tar.gz.sha256"
(
  cd -- "$application"
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
grep -Fq 'reason=runtime_identity_invalid' <<<"$identity_output" \
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
grep -Fq 'reason=publication_language_invalid' <<<"$language_output" \
  || fail language_failure_reason_missing

printf '%s\n' \
  'success=pass;rerun=pass;supersession=pass;published_verification=pass' \
  'checksum_refusal=pass;identity_refusal=pass;terminology_refusal=pass'
printf '\nSCRIPT RESULT\nishikawa_carry_builder_test=pass\n'

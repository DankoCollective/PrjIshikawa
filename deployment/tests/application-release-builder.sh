#!/usr/bin/env bash
set -Eeuo pipefail

# Exercise the application builder's publication and refusal branches without
# a Docker daemon, network, model, database, credential, or target contact.

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
test_root="$(mktemp -d /tmp/ishikawa-application-builder.XXXXXX)"

fail() {
  printf '\nSCRIPT RESULT\nishikawa_application_builder_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$test_root" == /tmp/ishikawa-application-builder.* && -d "$test_root" ]] \
    && rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fixture="$test_root/repo"
mkdir -p -- "$fixture/deployment/scripts" "$fixture/deployment/assets" \
  "$fixture/docs/decisions" "$fixture/docs/releases" "$fixture/bin"
cp -a -- "$repo_root/Ishikawa" "$fixture/"
cp -- "$repo_root/LICENSE" "$fixture/LICENSE"
cp -- "$repo_root/deployment/scripts/01_build-ishikawa-release.sh" \
  "$fixture/deployment/scripts/"
cp -- "$repo_root/deployment/assets/README-v1.3.1.md" \
  "$repo_root/deployment/assets/verify-ishikawa-release" \
  "$fixture/deployment/assets/"
cp -- "$repo_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md" \
  "$fixture/docs/decisions/"
cp -- "$repo_root/docs/releases/ISHIKAWA_ORG_LAB_CARRY_READINESS_CHECKLIST.md" \
  "$fixture/docs/releases/"

write_source_manifest() {
  (
    cd -- "$fixture"
    while IFS= read -r name; do sha256sum -- "$name"; done < <(
      find Ishikawa -type f ! -path '*/__pycache__/*' ! -name '*.pyc' \
        ! -name '*.pyo' -printf '%p\n' | sort
    )
  ) >"$fixture/docs/releases/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS"
}

write_native_pass() {
  cat >"$fixture/Ishikawa/scripts/run-local-validation-tests.sh" <<'MOCK'
#!/usr/bin/env bash
printf 'Ran 486 tests in 0.001s\n'
printf 'ishikawa_local_validation_tests=PASS\n'
MOCK
  chmod 0755 "$fixture/Ishikawa/scripts/run-local-validation-tests.sh"
}
write_native_pass
write_source_manifest

cat >"$fixture/bin/dpkg" <<'MOCK'
#!/usr/bin/env bash
[[ "${1:-}" == --print-architecture ]] || exit 91
printf 'amd64\n'
MOCK
cat >"$fixture/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == -v ]]; then exit 0; fi
exec "$@"
MOCK
cat >"$fixture/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
  info) exit 0 ;;
  image)
    [[ "${2:-}" == inspect ]] || exit 91
    [[ "${MOCK_IMAGE_MISSING:-false}" != true ]] || exit 1
    case "$*" in
      *'{{.Architecture}}'*) printf 'amd64\n' ;;
      *) printf '{}\n' ;;
    esac
    ;;
  run)
    if [[ "$*" == *'node --test'* ]]; then
      [[ "${MOCK_JAVASCRIPT_FAIL:-false}" != true ]] || exit 42
      printf '%s\n' 'TAP version 13' '# tests 17' '# pass 17' '# fail 0'
      exit 0
    fi
    if [[ "$*" == *'node_modules/.bin/next build'* ]]; then
      [[ "${MOCK_NEXT_BUILD_FAIL:-false}" != true ]] || exit 43
      printf 'mock production build\n'
      exit 0
    fi
    exit 92
    ;;
  *) exit 93 ;;
esac
MOCK
cat >"$fixture/bin/sort" <<'MOCK'
#!/usr/bin/env bash
[[ "${LC_ALL:-}" == C ]] || exit 96
exec /usr/bin/sort "$@"
MOCK
chmod 0755 "$fixture/bin/"*

builder="$fixture/deployment/scripts/01_build-ishikawa-release.sh"
run_builder() {
  PATH="$fixture/bin:$PATH" bash "$builder" "$@" 2>&1
}

validation_output="$(run_builder --validate-only)" || fail validate_only_failed
grep -Fxq 'script_01_build_ishikawa_release=ready' <<<"$validation_output" \
  || fail validate_ready_marker_missing

run_output="$(run_builder --run)" || fail success_path_failed
grep -Fxq 'script_01_build_ishikawa_release=pass' <<<"$run_output" \
  || fail success_marker_missing
handoff="$fixture/local/artifacts/ishikawa-v1.3.1-candidate-current"
[[ -d "$handoff" && ! -L "$handoff" ]] || fail handoff_missing
(cd -- "$handoff" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || fail handoff_checksum_failed
for required in ishikawa-v1.3.1.tar.gz ishikawa-v1.3.1.tar.gz.sha256 \
  ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS application-sbom.cdx.json \
  application-license.json release-receipt.json SHA256SUMS; do
  [[ -f "$handoff/$required" ]] || fail handoff_inventory_incomplete
done
jq -e \
  '.bomFormat == "CycloneDX"
   and .metadata.component.name == "Ishikawa"
   and .metadata.component.version == "1.3.1"' \
  "$handoff/application-sbom.cdx.json" >/dev/null || fail application_sbom_invalid
jq -e \
  '.schema == "ishikawa.application-license.v1"
   and .application_license == "Apache-2.0"' \
  "$handoff/application-license.json" >/dev/null || fail application_license_invalid

mkdir -p -- "$test_root/extracted"
tar -xzf "$handoff/ishikawa-v1.3.1.tar.gz" -C "$test_root/extracted"
[[ -f "$test_root/extracted/ishikawa-v1.3.1/LICENSE" ]] \
  || fail application_license_not_packaged
bash "$test_root/extracted/ishikawa-v1.3.1/verify-ishikawa-release" >/dev/null \
  || fail published_archive_verification_failed

second_output="$(run_builder --run)" || fail rerun_failed
grep -Fxq 'script_01_build_ishikawa_release=pass' <<<"$second_output" \
  || fail rerun_marker_missing
[[ "$(find "$fixture/local/artifacts/superseded" -mindepth 1 -maxdepth 1 -type d | wc -l)" == 1 ]] \
  || fail superseded_count_invalid

printf '\nmanifest drift\n' >>"$fixture/Ishikawa/README.md"
set +e
manifest_output="$(run_builder --run)"
manifest_status="$?"
set -e
(( manifest_status != 0 )) || fail manifest_drift_reported_success
grep -Fq 'reason=source_manifest_mismatch' <<<"$manifest_output" \
  || fail manifest_drift_reason_missing
sed -i '$d' "$fixture/Ishikawa/README.md"
sed -i '$d' "$fixture/Ishikawa/README.md"
write_source_manifest

cat >"$fixture/Ishikawa/scripts/run-local-validation-tests.sh" <<'MOCK'
#!/usr/bin/env bash
printf 'FAILED (failures=1)\n' >&2
exit 1
MOCK
chmod 0755 "$fixture/Ishikawa/scripts/run-local-validation-tests.sh"
write_source_manifest
set +e
native_output="$(run_builder --run)"
native_status="$?"
set -e
(( native_status != 0 )) || fail native_failure_reported_success
grep -Fq 'reason=native_tests_failed' <<<"$native_output" \
  || fail native_failure_reason_missing
write_native_pass
write_source_manifest

set +e
javascript_output="$(MOCK_JAVASCRIPT_FAIL=true run_builder --run)"
javascript_status="$?"
set -e
(( javascript_status != 0 )) || fail javascript_failure_reported_success
grep -Fq 'reason=javascript_tests_failed' <<<"$javascript_output" \
  || fail javascript_failure_reason_missing

set +e
next_output="$(MOCK_NEXT_BUILD_FAIL=true run_builder --run)"
next_status="$?"
set -e
(( next_status != 0 )) || fail next_failure_reported_success
grep -Fq 'reason=next_build_failed' <<<"$next_output" \
  || fail next_failure_reason_missing

printf '\nCodex\n' >>"$fixture/Ishikawa/docs/OPERATOR_GUIDE.md"
write_source_manifest
set +e
language_output="$(run_builder --run)"
language_status="$?"
set -e
(( language_status != 0 )) || fail language_failure_reported_success
grep -Fq 'reason=repository_reference_found' <<<"$language_output" \
  || fail language_failure_reason_missing

printf '%s\n' \
  'success=pass;rerun=pass;supersession=pass;checksums=pass;license=pass;sbom=pass;locale_independence=pass' \
  'manifest_refusal=pass;native_failure=pass;javascript_failure=pass' \
  'next_build_failure=pass;terminology_refusal=pass'
printf '\nSCRIPT RESULT\nishikawa_application_builder_test=pass\n'

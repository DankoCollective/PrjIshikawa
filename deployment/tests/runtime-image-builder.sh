#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Exercise the generic runtime-image builder's publication and failure paths
#   without Docker, network access, or changes to the real artifact lane.
#
# Mental model:
#   Copy the exact build inputs into a private harness, replace Docker with a
#   deterministic executable double, run success/rerun/failure cases, and
#   inspect the builder's standalone result and atomic handoff behavior.
#
# Inputs or prerequisites:
#   Tracked runtime-image source, builder, and frozen decision record.
#
# Outputs:
#   Terminal-only pass/block marker; the private harness is always removed.
#
# Usage:
#   bash ./deployment/tests/runtime-image-builder.sh

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
test_root="$(mktemp -d /tmp/runtime-image-builder-test.XXXXXX)"

fail() {
  printf '\nSCRIPT RESULT\nruntime_image_builder_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$test_root" == /tmp/runtime-image-builder-test.* && -d "$test_root" ]] \
    && rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- \
  "$test_root/repo/deployment/scripts" \
  "$test_root/repo/deployment/runtime-image" \
  "$test_root/repo/docs/decisions" \
  "$test_root/bin"
cp -- "$repo_root/deployment/scripts/build-node-next-runtime.sh" \
  "$test_root/repo/deployment/scripts/"
cp -- "$repo_root/deployment/runtime-image/"* \
  "$test_root/repo/deployment/runtime-image/"
cp -- "$repo_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md" \
  "$test_root/repo/docs/decisions/"

cat >"$test_root/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail

case "${1:-}" in
  info)
    exit 0
    ;;
  buildx)
    [[ "${2:-}" == version ]] && exit 0
    [[ "${2:-}" == build ]] || exit 91
    [[ "${MOCK_BUILD_FAIL:-false}" != true ]] || exit 42
    printf 'mock image build\n'
    ;;
  image)
    [[ "${2:-}" == inspect ]] || exit 92
    case "$*" in
      *'{{.Architecture}}'*) printf 'amd64\n' ;;
      *'org.opencontainers.image.version'*) printf '24.22.1-next16.4.3-react19.2.9\n' ;;
      *'{{.Id}}'*) printf 'sha256:%064d\n' 0 ;;
      *) printf '{}\n' ;;
    esac
    ;;
  run)
    if [[ "$*" == *'--entrypoint node'* ]]; then
      printf 'runtime_identity=pass\n'
      exit 0
    fi
    if [[ "$*" == *'--entrypoint sh'* ]]; then
      [[ "${MOCK_BOUNDARY_FAIL:-false}" != true ]] || exit 43
      exit 0
    fi
    if [[ "$*" == *'--entrypoint dpkg-query'* ]]; then
      printf 'libc6\t2.36-9+deb12u13\tamd64\n'
      exit 0
    fi
    if [[ "$*" == *'--entrypoint npm'* ]]; then
      printf '%s\n' '{"dependencies":{"next":{"version":"16.4.3"},"react":{"version":"19.2.9"},"react-dom":{"version":"19.2.9"}}}'
      exit 0
    fi
    exit 93
    ;;
  history)
    if [[ "${MOCK_HISTORY_JARGON:-false}" == true ]]; then
      printf 'copied from phase-99\n'
    else
      printf 'generic runtime layer\n'
    fi
    ;;
  save)
    shift
    [[ "${1:-}" == --output && -n "${2:-}" ]] || exit 94
    printf 'mock-docker-archive\n' >"$2"
    ;;
  load)
    exit 0
    ;;
  *)
    exit 95
    ;;
esac
MOCK
chmod 0755 "$test_root/bin/docker"

builder="$test_root/repo/deployment/scripts/build-node-next-runtime.sh"
run_builder() {
  PATH="$test_root/bin:$PATH" bash "$builder" "$@" 2>&1
}

validation_output="$(run_builder --validate-only)" || fail validate_only_failed
grep -Fxq 'node_next_runtime_build=ready' <<<"$validation_output" \
  || fail validate_ready_marker_missing

run_output="$(run_builder --run)" || fail success_path_failed
grep -Fxq 'node_next_runtime_build=pass' <<<"$run_output" \
  || fail success_marker_missing
handoff="$test_root/repo/local/artifacts/node-next-runtime-current"
[[ -d "$handoff" && ! -L "$handoff" ]] || fail handoff_missing
(
  cd -- "$handoff"
  sha256sum --check --strict SHA256SUMS >/dev/null
) || fail handoff_checksum_failed
for required_file in \
  node-next-runtime-amd64.tar node-next-runtime-amd64.tar.sha256 \
  image-identity.json build-receipt.json sbom.cdx.json licenses.json Dockerfile package.json \
  package-lock.json README.md SECURITY.md LICENSES.md SHA256SUMS; do
  [[ -f "$handoff/$required_file" && ! -L "$handoff/$required_file" ]] \
    || fail handoff_inventory_incomplete
done
jq -e \
  '.architecture == "amd64"
   and .application_in_image == false
   and .generated_next_in_image == false
   and .next == "16.4.3"
   and .react == "19.2.9"' \
  "$handoff/image-identity.json" >/dev/null || fail identity_record_invalid
jq -e \
  '.bomFormat == "CycloneDX"
   and any(.components[]; .name == "next" and .version == "16.4.3")
   and any(.components[]; .name == "libc6" and .version == "2.36-9+deb12u13")' \
  "$handoff/sbom.cdx.json" >/dev/null || fail combined_sbom_invalid
jq -e \
  '.schema == "node-runtime-license-inventory.v1"
   and any(.javascript_packages[]; .name == "next" and .version == "16.4.3")
   and any(.operating_system_packages[]; .name == "libc6")' \
  "$handoff/licenses.json" >/dev/null || fail combined_license_inventory_invalid
jq -e \
  '.schema == "node-next-runtime-build-receipt.v1"
   and .architecture == "amd64"
   and .application_in_image == false
   and .generated_next_in_image == false' \
  "$handoff/build-receipt.json" >/dev/null || fail build_receipt_invalid

second_output="$(run_builder --run)" || fail rerun_failed
grep -Fxq 'node_next_runtime_build=pass' <<<"$second_output" \
  || fail rerun_pass_marker_missing
[[ "$(find "$test_root/repo/local/artifacts/superseded" -mindepth 1 -maxdepth 1 -type d | wc -l)" == 1 ]] \
  || fail superseded_handoff_count_invalid

set +e
build_failure_output="$(MOCK_BUILD_FAIL=true run_builder --run)"
build_failure_status="$?"
set -e
(( build_failure_status != 0 )) || fail build_failure_reported_success
grep -Fq 'reason=image_build_failed' <<<"$build_failure_output" \
  || fail build_failure_reason_missing
grep -Fxq 'node_next_runtime_build=blocked' <<<"$build_failure_output" \
  || fail build_failure_result_missing
(
  cd -- "$handoff"
  sha256sum --check --strict SHA256SUMS >/dev/null
) || fail build_failure_changed_current

set +e
boundary_failure_output="$(MOCK_BOUNDARY_FAIL=true run_builder --run)"
boundary_failure_status="$?"
set -e
(( boundary_failure_status != 0 )) || fail boundary_failure_reported_success
grep -Fq 'reason=image_boundary_failed' <<<"$boundary_failure_output" \
  || fail boundary_failure_reason_missing

set +e
history_failure_output="$(MOCK_HISTORY_JARGON=true run_builder --run)"
history_failure_status="$?"
set -e
(( history_failure_status != 0 )) || fail history_failure_reported_success
grep -Fq 'reason=image_history_jargon_found' <<<"$history_failure_output" \
  || fail history_failure_reason_missing

printf '%s\n' \
  'success=pass;rerun=pass;supersession=pass;checksums=pass' \
  'build_failure=pass;boundary_failure=pass;jargon_failure=pass'
printf '\nSCRIPT RESULT\nruntime_image_builder_test=pass\n'

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
  "$test_root/repo/deployment/assets" \
  "$test_root/repo/deployment/runtime-image" \
  "$test_root/repo/docs/decisions" \
  "$test_root/bin" \
  "$test_root/docker-root"
cp -- "$repo_root/deployment/assets/build-node-next-runtime" \
  "$test_root/repo/deployment/assets/"
cp -- "$repo_root/deployment/runtime-image/"* \
  "$test_root/repo/deployment/runtime-image/"
cp -- "$repo_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md" \
  "$test_root/repo/docs/decisions/"

cat >"$test_root/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail

case "${1:-}" in
  info)
    case "$*" in
      *'{{.Architecture}}'*) printf '%s\n' "${MOCK_DOCKER_ARCHITECTURE:-amd64}" ;;
      *'{{.DockerRootDir}}'*) printf '%s\n' "$MOCK_DOCKER_ROOT" ;;
    esac
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
    if [[ "$*" == *'--entrypoint sh '* && "$*" == *'runtime_identity=pass'* ]]; then
      printf 'runtime_identity=pass\n'
      exit 0
    fi
    if [[ "$*" == *'--entrypoint sh '* ]]; then
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
    if [[ "$*" == *'--entrypoint sha256sum'* ]]; then
      [[ "${MOCK_RUNTIME_LICENSE_FAIL:-false}" != true ]] || exit 44
      printf '%064d  %s\n' 1 /usr/local/LICENSE
      printf '%064d  %s\n' 2 /usr/local/lib/node_modules/npm/LICENSE
      printf '%064d  %s\n' 3 /opt/yarn-v1.22.22/LICENSE
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
    [[ -n "${2:-}" ]] || exit 94
    archive_root="$(mktemp -d /tmp/mock-runtime-archive.XXXXXX)"
    archive_architecture=amd64
    [[ "${MOCK_ARCHIVE_CONFIG_FAIL:-false}" != true ]] || archive_architecture=arm64
    printf '{"architecture":"%s","os":"linux","config":{"WorkingDir":"/opt/nextjs","Cmd":["next","--help"]},"rootfs":{"type":"layers","diff_ids":["sha256:%064d"]},"history":[{"created_by":"generic runtime layer"}]}\n' \
      "$archive_architecture" 4 \
      >"$archive_root/config.json"
    printf 'mock compressed layer\n' >"$archive_root/layer"
    layer_hex="$(sha256sum "$archive_root/layer" | awk '{print $1}')"
    config_hex="$(sha256sum "$archive_root/config.json" | awk '{print $1}')"
    mkdir -p "$archive_root/blobs/sha256"
    mv "$archive_root/config.json" "$archive_root/blobs/sha256/$config_hex"
    mv "$archive_root/layer" "$archive_root/blobs/sha256/$layer_hex"
    printf '[{"Config":"blobs/sha256/%s","RepoTags":["node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64"],"Layers":["blobs/sha256/%s"]}]\n' \
      "$config_hex" "$layer_hex" >"$archive_root/manifest.json"
    tar -cf - -C "$archive_root" manifest.json blobs
    rm -rf "$archive_root"
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

cat >"$test_root/bin/hostname" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == -s ]] || exit 2
printf 'EmceeDanko\n'
MOCK
cat >"$test_root/bin/uname" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == -m ]] || exit 2
if [[ "${MOCK_NATIVE_ARCH_FAIL:-false}" == true ]]; then
  printf 'aarch64\n'
else
  printf 'x86_64\n'
fi
MOCK
cat >"$test_root/bin/dpkg" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == --print-architecture ]] || exit 2
if [[ "${MOCK_NATIVE_ARCH_FAIL:-false}" == true ]]; then
  printf 'arm64\n'
else
  printf 'amd64\n'
fi
MOCK
cat >"$test_root/bin/nproc" <<'MOCK'
#!/usr/bin/env bash
if [[ "${MOCK_CPU_FAIL:-false}" == true ]]; then
  printf '1\n'
else
  printf '8\n'
fi
MOCK
cat >"$test_root/bin/df" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
selected_path="${!#}"
available=10485760
if [[ "${MOCK_DOCKER_STORAGE_FAIL:-false}" == true \
    && "$selected_path" == "$MOCK_DOCKER_ROOT" ]]; then
  available=1024
fi
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf 'mock 20971520 0 %s 0%% %s\n' "$available" "$selected_path"
MOCK
chmod 0755 "$test_root/bin/hostname" "$test_root/bin/uname" \
  "$test_root/bin/dpkg" "$test_root/bin/nproc" "$test_root/bin/df"

builder="$test_root/repo/deployment/assets/build-node-next-runtime"
run_builder() {
  local selected_mode="${1:-}"
  shift || true
  local target_arguments=()
  if [[ "$selected_mode" == --run ]]; then
    target_arguments=(--expected-hostname EmceeDanko --expected-os-version 24.04)
  fi
  PATH="$test_root/bin:$PATH" MOCK_DOCKER_ROOT="$test_root/docker-root" \
    bash "$builder" "$selected_mode" "${target_arguments[@]}" "$@" 2>&1
}

validation_output="$(run_builder --validate-only)" || fail validate_only_failed
grep -Fxq 'node_next_runtime_build=ready' <<<"$validation_output" \
  || fail validate_ready_marker_missing

run_output="$(run_builder --run)" \
  || { printf '%s\n' "$run_output" >&2; fail success_path_failed; }
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
   and (.config_digest | test("^sha256:[0-9a-f]{64}$"))
   and (.history_sha256 | test("^[0-9a-f]{64}$"))
   and .node == "24.22.1"
   and .npm == "11.19.1"
   and .yarn == "1.22.22"
   and .next == "16.4.3"
   and .react == "19.2.9"' \
  "$handoff/image-identity.json" >/dev/null || fail identity_record_invalid
jq -e \
  '.bomFormat == "CycloneDX"
   and any(.components[]; .name == "node" and .version == "24.22.1")
   and any(.components[]; .name == "npm" and .version == "11.19.1")
   and any(.components[]; .name == "yarn" and .version == "1.22.22")
   and any(.components[]; .name == "next" and .version == "16.4.3")
   and any(.components[]; .name == "libc6" and .version == "2.36-9+deb12u13")
   and any(.metadata.component.properties[]; .name == "oci:image:config-digest")' \
  "$handoff/sbom.cdx.json" >/dev/null || fail combined_sbom_invalid
jq -e \
  '.schema == "node-runtime-license-inventory.v1"
   and (.runtime_tools | length == 3)
   and any(.runtime_tools[]; .name == "node" and .version == "24.22.1" and .license == "MIT")
   and any(.runtime_tools[]; .name == "npm" and .version == "11.19.1" and .license == "Artistic-2.0")
   and any(.runtime_tools[]; .name == "yarn" and .version == "1.22.22" and .license == "BSD-2-Clause")
   and any(.javascript_packages[]; .name == "next" and .version == "16.4.3")
   and any(.operating_system_packages[]; .name == "libc6")' \
  "$handoff/licenses.json" >/dev/null || fail combined_license_inventory_invalid
jq -e \
  '.schema == "node-next-runtime-build-receipt.v1"
   and .architecture == "amd64"
   and .application_in_image == false
   and .generated_next_in_image == false
   and (.config_digest | test("^sha256:[0-9a-f]{64}$"))
   and (.history_sha256 | test("^[0-9a-f]{64}$"))' \
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
archive_config_failure_output="$(MOCK_ARCHIVE_CONFIG_FAIL=true run_builder --run)"
archive_config_failure_status="$?"
set -e
(( archive_config_failure_status != 0 )) || fail archive_config_failure_reported_success
grep -Fq 'reason=image_config_contract_invalid' <<<"$archive_config_failure_output" \
  || fail archive_config_failure_reason_missing

set +e
runtime_license_failure_output="$(MOCK_RUNTIME_LICENSE_FAIL=true run_builder --run)"
runtime_license_failure_status="$?"
set -e
(( runtime_license_failure_status != 0 )) || fail runtime_license_failure_reported_success
grep -Fq 'reason=runtime_tool_license_inventory_failed' <<<"$runtime_license_failure_output" \
  || fail runtime_license_failure_reason_missing

set +e
history_failure_output="$(MOCK_HISTORY_JARGON=true run_builder --run)"
history_failure_status="$?"
set -e
(( history_failure_status != 0 )) || fail history_failure_reported_success
grep -Fq 'reason=image_history_jargon_found' <<<"$history_failure_output" \
  || fail history_failure_reason_missing

set +e
native_architecture_output="$(MOCK_NATIVE_ARCH_FAIL=true run_builder --run)"
native_architecture_status="$?"
set -e
(( native_architecture_status != 0 )) || fail native_architecture_failure_reported_success
grep -Fq 'reason=native_amd64_build_host_required' <<<"$native_architecture_output" \
  || fail native_architecture_failure_reason_missing

set +e
docker_architecture_output="$(MOCK_DOCKER_ARCHITECTURE=arm64 run_builder --run)"
docker_architecture_status="$?"
set -e
(( docker_architecture_status != 0 )) || fail docker_architecture_failure_reported_success
grep -Fq 'reason=docker_native_amd64_unavailable' <<<"$docker_architecture_output" \
  || fail docker_architecture_failure_reason_missing

set +e
cpu_capacity_output="$(MOCK_CPU_FAIL=true run_builder --run)"
cpu_capacity_status="$?"
set -e
(( cpu_capacity_status != 0 )) || fail cpu_capacity_failure_reported_success
grep -Fq 'reason=build_cpu_capacity_insufficient' <<<"$cpu_capacity_output" \
  || fail cpu_capacity_failure_reason_missing

set +e
docker_capacity_output="$(MOCK_DOCKER_STORAGE_FAIL=true run_builder --run)"
docker_capacity_status="$?"
set -e
(( docker_capacity_status != 0 )) || fail docker_capacity_failure_reported_success
grep -Fq 'reason=docker_storage_capacity_insufficient' <<<"$docker_capacity_output" \
  || fail docker_capacity_failure_reason_missing

printf '%s\n' \
  'success=pass;rerun=pass;supersession=pass;checksums=pass' \
  'build_failure=pass;boundary_failure=pass;archive_config_failure=pass;runtime_license_failure=pass;jargon_failure=pass' \
  'native_architecture_failure=pass;docker_architecture_failure=pass' \
  'cpu_capacity_failure=pass;docker_capacity_failure=pass'
printf '\nSCRIPT RESULT\nruntime_image_builder_test=pass\n'

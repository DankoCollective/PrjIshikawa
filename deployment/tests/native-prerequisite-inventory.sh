#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Exercise the portable read-only target inventory and its refusal paths.
#
# Mental model:
#   Run the real inspector against a private operator home while replacing only
#   host-control commands with deterministic read-only doubles. Prove direct
#   and attended-sudo Docker inspection, complete listener/path evidence,
#   package-health handling, and argument refusals without target mutation.
#
# Inputs or prerequisites:
#   Local Ubuntu shell with the inspector's ordinary metadata tools.
#
# Outputs or artifact lane:
#   All fixtures and evidence remain beneath one private /tmp directory and
#   are removed on exit. No remote target is contacted.

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly inspector="$repo_root/deployment/carry/inspect-native-prerequisites"
test_root="$(mktemp -d /tmp/ishikawa-native-inventory-test.XXXXXX)"

fail() {
  printf '\nSCRIPT RESULT\nishikawa_native_prerequisite_inventory_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$test_root" == /tmp/ishikawa-native-inventory-test.* && -d "$test_root" ]] \
    && rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$test_root/bin" "$test_root/home/Documents" "$test_root/protected"

cat >"$test_root/bin/apt-get" <<'MOCK'
#!/usr/bin/env bash
printf 'Reading package lists...\n'
[[ "${MOCK_APT_CHECK_FAIL:-false}" != true ]]
MOCK
cat >"$test_root/bin/docker" <<'MOCK'
#!/usr/bin/env bash
[[ "${MOCK_DOCKER_ACCESS:-true}" == true ]] || exit 1
case "${1:-}" in
  version) printf '27.5.1\n' ;;
  image) exit 1 ;;
  ps)
    [[ "$*" != *'ancestor='* ]] || printf 'fixture-container\n'
    ;;
  *) exit 2 ;;
esac
MOCK
cat >"$test_root/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
[[ "${1:-}" != -v ]] || exit 0
if [[ "${1:-}" == -u ]]; then shift 2; fi
[[ "${1:-}" != -- ]] || shift
exec "$@"
MOCK
cat >"$test_root/bin/ss" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  *':55432'*) printf 'LISTEN 0 1 127.0.0.1:55432 0.0.0.0:*\n' ;;
  *':58000'*) printf 'LISTEN 0 1 127.0.0.1:58000 0.0.0.0:*\n' ;;
  *':58001'*) printf 'LISTEN 0 1 127.0.0.1:58001 0.0.0.0:*\n' ;;
esac
MOCK
cat >"$test_root/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == --user && "${2:-}" == show-environment ]]; then exit 0; fi
case "${1:-}" in
  is-enabled) printf 'disabled\n' ;;
  is-active) printf 'inactive\n' ;;
  *) exit 1 ;;
esac
MOCK
cat >"$test_root/bin/loginctl" <<'MOCK'
#!/usr/bin/env bash
printf 'no\n'
MOCK
cat >"$test_root/bin/pg_lsclusters" <<'MOCK'
#!/usr/bin/env bash
printf '16 main 55432 online postgres /var/lib/postgresql/16/main /var/log/postgresql/postgresql-16-main.log\n'
MOCK
cat >"$test_root/bin/psql" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *'--version'* ]]; then
  printf 'psql (PostgreSQL) 16.15\n'
else
  printf '0|0|1\n'
fi
MOCK
chmod 0755 "$test_root/bin/"*

export PATH="$test_root/bin:$PATH"
export HOME="$test_root/home"
export USER='fixture-operator'
os_version="$(. /etc/os-release; printf '%s' "$VERSION_ID")"
architecture="$(dpkg --print-architecture)"

inventory_arguments=(
  --expected-os-version "$os_version"
  --expected-architecture "$architecture"
  --postgresql-port 55432
  --retrieval-port 51384
  --web-port 53000
  --gemma-port 58000
  --nomic-port 58001
  --protected-source-root "$test_root/protected"
)

default_output="$(bash "$inspector" \
  --expected-os-version "$os_version" \
  --expected-architecture "$architecture" \
  --output-dir "$test_root/defaults" 2>&1)" \
  || fail default_inventory_failed
grep -Fxq 'ishikawa_native_prerequisite_inventory=pass' <<<"$default_output" \
  || fail default_result_missing
grep -Fxq 'retrieval_port=8384' "$test_root/defaults/host-summary.env" \
  || fail default_retrieval_port_invalid
grep -Fxq 'web_port=3384' "$test_root/defaults/host-summary.env" \
  || fail default_web_port_invalid

direct_output="$(bash "$inspector" "${inventory_arguments[@]}" \
  --output-dir "$test_root/direct" 2>&1)" || fail direct_inventory_failed
grep -Fxq 'ishikawa_native_prerequisite_inventory=pass' <<<"$direct_output" \
  || fail direct_result_missing
grep -Fxq 'inventory_schema_version=2' "$test_root/direct/host-summary.env" \
  || fail schema_version_invalid
grep -Fxq 'apt_check_clean=true' "$test_root/direct/host-summary.env" \
  || fail apt_success_misclassified
grep -Fxq 'docker_access_mode=direct' "$test_root/direct/host-summary.env" \
  || fail direct_docker_mode_missing
grep -Fxq 'docker_accessible=true' "$test_root/direct/host-summary.env" \
  || fail direct_docker_access_missing
grep -Fxq 'postgresql_16_main_count=1' "$test_root/direct/host-summary.env" \
  || fail postgresql_cluster_missing
grep -Fxq 'postgresql_selected_port_count=1' "$test_root/direct/host-summary.env" \
  || fail postgresql_port_cluster_missing
grep -Fxq 'listener_gemma_count=1' "$test_root/direct/host-summary.env" \
  || fail gemma_listener_missing
grep -Fxq 'listener_nomic_count=1' "$test_root/direct/host-summary.env" \
  || fail nomic_listener_missing
grep -Fxq 'protected_source_check=pass' "$test_root/direct/host-summary.env" \
  || fail protected_source_check_missing
(cd -- "$test_root/direct" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || fail direct_checksum_failed

sudo_output="$(bash "$inspector" "${inventory_arguments[@]}" --use-sudo-inspection \
  --output-dir "$test_root/sudo" 2>&1)" || fail sudo_inventory_failed
grep -Fq '[INPUT REQUIRED] Attended sudo authorization' <<<"$sudo_output" \
  || fail sudo_prompt_warning_missing
grep -Fxq 'docker_access_mode=sudo' "$test_root/sudo/host-summary.env" \
  || fail sudo_docker_mode_missing
grep -Fxq 'docker_accessible=true' "$test_root/sudo/host-summary.env" \
  || fail sudo_docker_access_missing
grep -Fxq 'postgresql_catalog_checked=true' "$test_root/sudo/host-summary.env" \
  || fail postgresql_catalog_check_missing
grep -Fxq 'rag_role_count=0' "$test_root/sudo/host-summary.env" \
  || fail rag_role_count_invalid
grep -Fxq 'rag_database_count=0' "$test_root/sudo/host-summary.env" \
  || fail rag_database_count_invalid
grep -Fxq 'vector_available_count=1' "$test_root/sudo/host-summary.env" \
  || fail vector_available_count_invalid

export MOCK_APT_CHECK_FAIL=true
bash "$inspector" "${inventory_arguments[@]}" \
  --output-dir "$test_root/apt-failure" >/dev/null \
  || fail apt_failure_inventory_blocked
unset MOCK_APT_CHECK_FAIL
grep -Fxq 'apt_check_clean=false' "$test_root/apt-failure/host-summary.env" \
  || fail apt_failure_not_recorded

export MOCK_DOCKER_ACCESS=false
bash "$inspector" "${inventory_arguments[@]}" \
  --output-dir "$test_root/docker-inaccessible" >/dev/null \
  || fail inaccessible_docker_inventory_blocked
unset MOCK_DOCKER_ACCESS
grep -Fxq 'docker_accessible=false' \
  "$test_root/docker-inaccessible/host-summary.env" \
  || fail inaccessible_docker_not_recorded

set +e
collision_output="$(bash "$inspector" --expected-os-version "$os_version" \
  --expected-architecture "$architecture" --postgresql-port 55432 \
  --retrieval-port 55432 --web-port 53000 --gemma-port 58000 \
  --nomic-port 58001 --output-dir "$test_root/collision" 2>&1)"
collision_status="$?"
relative_output="$(bash "$inspector" "${inventory_arguments[@]:0:12}" \
  --protected-source-root relative/path --output-dir "$test_root/relative" 2>&1)"
relative_status="$?"
set -e
(( collision_status != 0 )) || fail port_collision_reported_success
grep -Fxq 'reason=planned_ports_collide' <<<"$collision_output" \
  || fail port_collision_reason_missing
grep -Fxq 'ishikawa_native_prerequisite_inventory=blocked' <<<"$collision_output" \
  || fail blocked_result_missing
(( relative_status != 0 )) || fail relative_source_reported_success
grep -Fxq 'reason=protected_source_root_invalid' <<<"$relative_output" \
  || fail relative_source_reason_missing

printf '%s\n' \
  'defaults=3384_8384;direct=pass;sudo=pass;complete_host_surface=pass;checksums=pass' \
  'apt_failure_capture=pass;docker_inaccessible_capture=pass' \
  'port_collision_refusal=pass;protected_source_refusal=pass'
printf '\nSCRIPT RESULT\nishikawa_native_prerequisite_inventory_test=pass\n'

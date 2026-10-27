#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CAPTURE="$REPO_ROOT/deployment/carry/capture-native-prerequisites"
TEST_ROOT="$(mktemp -d /tmp/ishikawa-native-package-capture.XXXXXX)"
MOCK_BIN="$TEST_ROOT/bin"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf '\nSCRIPT RESULT\nnative_package_capture_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

mkdir -p "$MOCK_BIN"
printf 'test-keyring\n' > "$TEST_ROOT/ubuntu-archive-keyring.gpg"

cat > "$MOCK_BIN/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (($# > 0)); do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n "$output" ]]
printf 'mock-pgdg-key\n' > "$output"
MOCK

cat > "$MOCK_BIN/gpg" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'fpr:::::::::%s:\n' "${MOCK_PGDG_FINGERPRINT:-B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8}"
MOCK

cat > "$MOCK_BIN/apt-cache" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
action=""
subject=""
for argument in "$@"; do
  case "$argument" in
    policy|show)
      action="$argument"
      ;;
    *=*|python3-psycopg|postgresql-common|postgresql-client-common|libpq5|postgresql-client-16|postgresql-16|postgresql-16-pgvector)
      subject="$argument"
      ;;
  esac
done
if [[ "$action" == show && "${MOCK_PIN_UNAVAILABLE:-false}" == true ]]; then
  exit 100
fi
if [[ "$action" == policy ]]; then
  printf '%s:\n  Installed: (none)\n  Candidate: mock\n' "$subject"
fi
MOCK

cat > "$MOCK_BIN/apt-get" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
action=""
archive_dir=""
for argument in "$@"; do
  case "$argument" in
    update|install)
      action="$argument"
      ;;
    Dir::Cache::archives=*)
      archive_dir="${argument#Dir::Cache::archives=}"
      ;;
  esac
done

if [[ "$action" == update ]]; then
  [[ "${MOCK_APT_UPDATE_FAIL:-false}" != true ]] || exit 100
  printf 'signed metadata update complete\n'
  exit 0
fi

if [[ "$action" == install ]]; then
  [[ "${MOCK_APT_DOWNLOAD_FAIL:-false}" != true ]] || exit 100
  [[ -n "$archive_dir" ]]
  mkdir -p "$archive_dir/partial"
  files=(
    'python3-psycopg_3.3.2-1build1_all.deb'
    'postgresql-common_293.pgdg26.04+1_all.deb'
    'postgresql-client-common_293.pgdg26.04+1_all.deb'
    'libpq5_18.6-1.pgdg26.04+2_amd64.deb'
    'postgresql-client-16_16.15-1.pgdg26.04+2_amd64.deb'
    'postgresql-16_16.15-1.pgdg26.04+2_amd64.deb'
    'postgresql-16-pgvector_0.8.7-1.pgdg26.04+1_amd64.deb'
    'mock-transitive-dependency_1.0_amd64.deb'
  )
  for filename in "${files[@]}"; do
    printf 'mock package %s\n' "$filename" > "$archive_dir/$filename"
  done
  printf 'download-only closure complete\n'
  exit 0
fi

exit 2
MOCK

cat > "$MOCK_BIN/dpkg-deb" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == -f ]]
filename="${2##*/}"
field="$3"
case "$filename" in
  python3-psycopg_*) package=python3-psycopg; version=3.3.2-1build1; arch=all; source=psycopg3 ;;
  postgresql-common_*) package=postgresql-common; version=293.pgdg26.04+1; arch=all; source=postgresql-common ;;
  postgresql-client-common_*) package=postgresql-client-common; version=293.pgdg26.04+1; arch=all; source=postgresql-common ;;
  libpq5_*) package=libpq5; version=18.6-1.pgdg26.04+2; arch=amd64; source=postgresql-18 ;;
  postgresql-client-16_*) package=postgresql-client-16; version=16.15-1.pgdg26.04+2; arch=amd64; source=postgresql-16 ;;
  postgresql-16_*) package=postgresql-16; version=16.15-1.pgdg26.04+2; arch=amd64; source=postgresql-16 ;;
  postgresql-16-pgvector_*) package=postgresql-16-pgvector; version=0.8.7-1.pgdg26.04+1; arch=amd64; source=pgvector ;;
  mock-transitive-dependency_*) package=mock-transitive-dependency; version=1.0; arch=amd64; source=mock-source ;;
  *) exit 2 ;;
esac
case "$field" in
  Package) printf '%s\n' "$package" ;;
  Version) printf '%s\n' "$version" ;;
  Architecture) printf '%s\n' "$arch" ;;
  Source) printf '%s\n' "$source" ;;
  *) exit 2 ;;
esac
MOCK

cat > "$MOCK_BIN/sha256sum" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --check || "${1:-}" == -c ]]; then
  input="$(cat)"
  [[ "${MOCK_HASH_FAIL:-false}" != true ]] || exit 1
  package_path="${input#*  }"
  [[ -f "$package_path" ]]
  exit 0
fi

for package_path in "$@"; do
  filename="${package_path##*/}"
  case "$filename" in
    python3-psycopg_*) hash=e03bef68d5c5456a801309fb330c2814007f265431f2ba97c0a046805731dc53 ;;
    postgresql-common_*) hash=4b830ea730e0de1f6d0c80cee8db3d540185765c933c9ad6537372101f6aae92 ;;
    postgresql-client-common_*) hash=d2ac3e8c35c774fa1e48dd6146b1a5937617496df23f46cf101183dcf51f60c4 ;;
    libpq5_*) hash=a56bfe4843ae432e7338d0139190397db69a343412e489ae637bfb39c2d6fc30 ;;
    postgresql-client-16_*) hash=52fd38615ce65bd9b0442a21e611986e0cc7b87e1143e2464668be17fcb77314 ;;
    postgresql-16_*) hash=029e7af139dafe488a1950531824d61b17d07990879380f459e79b0f15420512 ;;
    postgresql-16-pgvector_*) hash=9a853bba89e2811d0dfeda853ff94ca6d8e84f01a088327ba8b781d99bc083d7 ;;
    *) hash=0000000000000000000000000000000000000000000000000000000000000000 ;;
  esac
  printf '%s  %s\n' "$hash" "$package_path"
done
MOCK

chmod 755 "$MOCK_BIN"/*

run_capture() {
  local output="$1"
  shift
  PATH="$MOCK_BIN:$PATH" \
    ISHIKAWA_UBUNTU_KEYRING="$TEST_ROOT/ubuntu-archive-keyring.gpg" \
    "$@" bash "$CAPTURE" --output "$output"
}

pass_output="$TEST_ROOT/pass"
pass_log="$TEST_ROOT/pass.log"
run_capture "$pass_output" env > "$pass_log" 2>&1 \
  || fail "happy_path_failed"
grep -Fq 'capture-native-prerequisites=pass' "$pass_log" \
  || fail "happy_path_result_missing"
[[ "$(find "$pass_output/debs" -maxdepth 1 -type f -name '*.deb' | wc -l)" -eq 8 ]] \
  || fail "closure_count_wrong"
[[ -f "$pass_output/package-manifest.tsv" && -f "$pass_output/deb-checksums.sha256" ]] \
  || fail "manifest_missing"
[[ -d "$pass_output/repository-metadata/apt-lists" && ! -e "$pass_output/apt-root" ]] \
  || fail "capture_cleanup_wrong"
grep -Fq 'offline_installation_proof=pending' "$pass_output/capture-summary.env" \
  || fail "pending_boundary_missing"

existing_log="$TEST_ROOT/existing.log"
if run_capture "$pass_output" env > "$existing_log" 2>&1; then
  fail "existing_output_was_accepted"
fi
grep -Fq 'reason=output_exists' "$existing_log" \
  || fail "existing_output_reason_wrong"

bad_key_log="$TEST_ROOT/bad-key.log"
if run_capture "$TEST_ROOT/bad-key" env MOCK_PGDG_FINGERPRINT=BAD > "$bad_key_log" 2>&1; then
  fail "bad_key_was_accepted"
fi
grep -Fq 'reason=pgdg_key_mismatch' "$bad_key_log" \
  || fail "bad_key_reason_wrong"

update_log="$TEST_ROOT/update-failure.log"
if run_capture "$TEST_ROOT/update-failure" env MOCK_APT_UPDATE_FAIL=true > "$update_log" 2>&1; then
  fail "repository_failure_was_accepted"
fi
grep -Fq 'reason=repository_update_failed' "$update_log" \
  || fail "repository_failure_reason_wrong"

pin_log="$TEST_ROOT/pin-failure.log"
if run_capture "$TEST_ROOT/pin-failure" env MOCK_PIN_UNAVAILABLE=true > "$pin_log" 2>&1; then
  fail "missing_pin_was_accepted"
fi
grep -Fq 'reason=pinned_package_unavailable' "$pin_log" \
  || fail "missing_pin_reason_wrong"

hash_output="$TEST_ROOT/hash-failure"
hash_log="$TEST_ROOT/hash-failure.log"
if run_capture "$hash_output" env MOCK_HASH_FAIL=true > "$hash_log" 2>&1; then
  fail "bad_hash_was_accepted"
fi
grep -Fq 'reason=direct_package_hash_mismatch' "$hash_log" \
  || fail "bad_hash_reason_wrong"
[[ "$(find "$hash_output/debs" -maxdepth 1 -type f -name '*.deb' | wc -l)" -eq 8 ]] \
  || fail "failed_downloads_not_preserved"

printf 'happy_path=pass;complete_closure=pass;metadata_retention=pass\n'
printf 'existing_output_refusal=pass;signature_refusal=pass;repository_refusal=pass\n'
printf 'missing_pin_refusal=pass;direct_hash_refusal=pass;failure_preservation=pass\n'
printf '\nSCRIPT RESULT\nnative_package_capture_test=pass\n'

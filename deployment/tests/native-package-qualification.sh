#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
QUALIFIER="$REPO_ROOT/deployment/carry/qualify-native-prerequisites"
TEST_ROOT="$(mktemp -d /tmp/ishikawa-native-package-qualification.XXXXXX)"
MOCK_BIN="$TEST_ROOT/bin"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf '\nSCRIPT RESULT\nnative_package_qualification_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
action="${1:-}"
if [[ "$action" == image && "${2:-}" == inspect ]]; then
  [[ "${MOCK_IMAGE_MISSING:-false}" != true ]] || exit 1
  format=""
  while (($# > 0)); do
    if [[ "$1" == --format ]]; then
      format="$2"
      break
    fi
    shift
  done
  case "$format" in
    '{{.Os}}') printf '%s\n' "${MOCK_IMAGE_OS:-linux}" ;;
    '{{.Architecture}}') printf '%s\n' "${MOCK_IMAGE_ARCH:-amd64}" ;;
    '{{.Id}}') printf 'sha256:mock-image\n' ;;
    '{{join .RepoDigests ","}}') printf 'ubuntu@sha256:mock-digest\n' ;;
    '') exit 0 ;;
    *) exit 2 ;;
  esac
  exit 0
fi
if [[ "$action" == run ]]; then
  cat >/dev/null
  [[ "${MOCK_CONTAINER_FAIL:-false}" != true ]] || {
    printf 'mock container failure\n' >&2
    exit 1
  }
  printf '%s\n' \
    '[PSYCOPG] version=3.3.2;state=pass' \
    '[POSTGRESQL] major=16;pgvector=0.8.7;query=pass;state=pass' \
    '[LICENSE] package=python3-psycopg;copyright_sha256=mock' \
    '[LICENSE] state=inventory_pass' \
    '[OFFLINE] state=pass;network=none;source_lists=empty'
  exit 0
fi
exit 2
MOCK

cat > "$MOCK_BIN/sudo" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == -v ]]; then
  exit 0
fi
exec "$@"
MOCK

chmod 755 "$MOCK_BIN"/*

make_shelf() {
  local shelf="$1"
  mkdir -p "$shelf/debs" "$shelf/repository-metadata"
  printf 'mock deb\n' > "$shelf/debs/mock_1.0_amd64.deb"
  cat > "$shelf/capture-summary.env" <<'SUMMARY'
capture_status=downloaded_pending_offline_qualification
target_release=resolute
target_architecture=amd64
postgresql_major=16
captured_package_count=1
SUMMARY
  printf 'B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8\n' \
    > "$shelf/repository-metadata/postgresql-signing-key.fingerprint"
  printf 'filename\tpackage\tversion\tarchitecture\tsource\tbytes\tsha256\n' \
    > "$shelf/package-manifest.tsv"
  printf 'mock_1.0_amd64.deb\tmock\t1.0\tamd64\tmock\t9\tmock\n' \
    >> "$shelf/package-manifest.tsv"
  (
    cd "$shelf"
    sha256sum debs/mock_1.0_amd64.deb > deb-checksums.sha256
    find . -type f ! -name shelf-checksums.sha256 -print0 \
      | sort -z | xargs -0 sha256sum > shelf-checksums.sha256
  )
}

run_qualifier() {
  PATH="$MOCK_BIN:$PATH" bash "$QUALIFIER" "$@"
}

pass_shelf="$TEST_ROOT/pass-shelf"
make_shelf "$pass_shelf"
pass_log="$TEST_ROOT/pass.log"
(
  cd "$pass_shelf"
  run_qualifier
) > "$pass_log" 2>&1 || fail "happy_path_failed"
grep -Fq 'qualify-native-prerequisites=pass' "$pass_log" \
  || fail "happy_result_missing"
summary_path="$(find "$pass_shelf" -maxdepth 2 -type f -name qualification-summary.env -print -quit)"
[[ -n "$summary_path" ]] || fail "qualification_summary_missing"
grep -Fq 'qualification_status=offline_installation_and_operation_pass' "$summary_path" \
  || fail "qualification_summary_wrong"

sudo_shelf="$TEST_ROOT/sudo-shelf"
make_shelf "$sudo_shelf"
sudo_log="$TEST_ROOT/sudo.log"
(
  cd "$sudo_shelf"
  run_qualifier --sudo-docker
) > "$sudo_log" 2>&1 || fail "sudo_docker_path_failed"

bad_checksum_shelf="$TEST_ROOT/bad-checksum-shelf"
make_shelf "$bad_checksum_shelf"
printf 'changed\n' >> "$bad_checksum_shelf/debs/mock_1.0_amd64.deb"
bad_checksum_log="$TEST_ROOT/bad-checksum.log"
if (
  cd "$bad_checksum_shelf"
  run_qualifier
) > "$bad_checksum_log" 2>&1; then
  fail "bad_checksum_was_accepted"
fi
grep -Fq 'reason=deb_checksum_failure' "$bad_checksum_log" \
  || fail "bad_checksum_reason_wrong"

missing_image_shelf="$TEST_ROOT/missing-image-shelf"
make_shelf "$missing_image_shelf"
missing_image_log="$TEST_ROOT/missing-image.log"
if (
  cd "$missing_image_shelf"
  MOCK_IMAGE_MISSING=true run_qualifier
) > "$missing_image_log" 2>&1; then
  fail "missing_image_was_accepted"
fi
grep -Fq 'reason=qualification_image_missing' "$missing_image_log" \
  || fail "missing_image_reason_wrong"

container_failure_shelf="$TEST_ROOT/container-failure-shelf"
make_shelf "$container_failure_shelf"
container_failure_log="$TEST_ROOT/container-failure.log"
if (
  cd "$container_failure_shelf"
  MOCK_CONTAINER_FAIL=true run_qualifier
) > "$container_failure_log" 2>&1; then
  fail "container_failure_was_accepted"
fi
grep -Fq 'reason=offline_qualification_failed' "$container_failure_log" \
  || fail "container_failure_reason_wrong"

printf 'happy_path=pass;sudo_docker=pass;qualification_receipt=pass\n'
printf 'checksum_refusal=pass;missing_image_refusal=pass;container_failure=pass\n'
printf '\nSCRIPT RESULT\nnative_package_qualification_test=pass\n'

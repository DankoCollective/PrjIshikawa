#!/usr/bin/env bash
set -Eeuo pipefail

# Canonical operator-facing Script 21. This checksum-binds and runs the
# disposable local migration-0002 proof. It never contacts or mutates a target.

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly TEST_HELPER="$SCRIPT_DIR/tests/test_ingestion_ownership_migration.sh"
readonly MIGRATION_0001="$PHASE_ROOT/migrations/0001_initial_rag_catalog.sql"
readonly MIGRATION_0002="$PHASE_ROOT/migrations/0002_align_ingestion_ownership.sql"
readonly EXPECTED_HELPER_SHA256=ca9fb1300971c2330f030aba55794a0909448e214b0c74aeb3fe751ad81288c3
readonly EXPECTED_0001_SHA256=3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a
readonly EXPECTED_0002_SHA256=74b08adb8aac9828ac076744fedfd22619751326c911bf17f1fa8690e01345e4

for required in awk bash sha256sum; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: Script 21 requires local command: %s\n' "$required" >&2
    exit 2
  }
done
for source_path in "$TEST_HELPER" "$MIGRATION_0001" "$MIGRATION_0002"; do
  [[ -f "$source_path" && ! -L "$source_path" && -r "$source_path" ]] || {
    printf 'BLOCKED: Script 21 source is missing or unsafe.\n' >&2
    exit 2
  }
done

actual_helper_sha256="$(sha256sum "$TEST_HELPER" | awk '{print $1}')"
actual_0001_sha256="$(sha256sum "$MIGRATION_0001" | awk '{print $1}')"
actual_0002_sha256="$(sha256sum "$MIGRATION_0002" | awk '{print $1}')"
[[ "$actual_helper_sha256" == "$EXPECTED_HELPER_SHA256" ]] || {
  printf 'BLOCKED: Script 21 test-helper checksum mismatch.\n' >&2
  exit 2
}
[[ "$actual_0001_sha256" == "$EXPECTED_0001_SHA256" ]] || {
  printf 'BLOCKED: Script 21 migration 0001 checksum mismatch.\n' >&2
  exit 2
}
[[ "$actual_0002_sha256" == "$EXPECTED_0002_SHA256" ]] || {
  printf 'BLOCKED: Script 21 migration 0002 checksum mismatch.\n' >&2
  exit 2
}

bash -n "$TEST_HELPER"

printf '%s\n' \
  'script=21' \
  'purpose=test_ingestion_ownership_migration_locally' \
  'target_contact=false' \
  'target_mutation=false' \
  "test_helper_sha256=$actual_helper_sha256" \
  "migration_0001_sha256=$actual_0001_sha256" \
  "migration_0002_sha256=$actual_0002_sha256"

bash "$TEST_HELPER"

printf '%s\n' 'script_21_ingestion_ownership_migration_test=pass'

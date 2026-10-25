#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Prove the canonical fresh-install schema is catalog-equivalent to applying
#   the four accepted development schema ancestors to an empty database.
#
# Mental model:
#   Start one throw-away local PostgreSQL cluster, build an ancestor database
#   and a consolidated database from the same clean baseline, normalize their
#   schema-only dumps, compare them byte for byte, and verify ledger posture.
#
# Inputs or prerequisites:
#   PostgreSQL 16 client/server tools, pg_virtualenv, pgvector, the four exact
#   schema ancestors, and the canonical final schema in this repository.
#
# Outputs:
#   One content-free pass or blocked marker. The temporary cluster and both
#   databases are owned and removed automatically by pg_virtualenv.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/tests/test_consolidated_database_schema.sh

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
readonly MIGRATION_ROOT="$PHASE_ROOT/migrations"
readonly FINAL_SCHEMA="$PHASE_ROOT/Ishikawa/packaging/database/schema.sql"
readonly SHA_0001='3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a'
readonly SHA_0002='74b08adb8aac9828ac076744fedfd22619751326c911bf17f1fa8690e01345e4'
readonly SHA_0003='5e833d8ff556c0e6158daf0419b1013235a11e1a94f1f560206ba813e1fc3761'
readonly SHA_0004='5764f6e12a74b18747163c61ef3f314e8dff140a3586b298c62be616a1dc185f'

block() {
  printf 'consolidated_database_schema_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

(( $# == 0 )) || block argument_invalid
for required in awk bash cmp createdb grep mktemp pg_dump pg_virtualenv psql rm sed sha256sum; do
  command -v "$required" >/dev/null 2>&1 || block "command_missing_$required"
done
for required_file in \
  "$MIGRATION_ROOT/0001_initial_rag_catalog.sql" \
  "$MIGRATION_ROOT/0002_align_ingestion_ownership.sql" \
  "$MIGRATION_ROOT/0003_separate_special_token_count.sql" \
  "$MIGRATION_ROOT/0004_preserve_relationship_override_audit.sql" \
  "$FINAL_SCHEMA"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || block required_file_unsafe
done

work_root="$(mktemp -d /tmp/ishikawa-consolidated-schema-test.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-consolidated-schema-test.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_comparison="$work_root/run-comparison"
cat >"$run_comparison" <<'INNER'
#!/usr/bin/env bash
set -Eeuo pipefail

work_root="$1"
phase_root="$2"
final_schema="$3"
sha_0001="$4"
sha_0002="$5"
sha_0003="$6"
sha_0004="$7"

psql --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --dbname=postgres <<'SQL'
CREATE ROLE rag_owner NOLOGIN;
CREATE ROLE rag_ingest NOLOGIN;
CREATE ROLE rag_retrieval NOLOGIN;
SQL
createdb --owner=rag_owner ancestor_catalog
createdb --owner=rag_owner consolidated_catalog
for database in ancestor_catalog consolidated_catalog; do
  psql --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --dbname="$database" \
    --command='CREATE EXTENSION vector;' >/dev/null
done

psql --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --dbname=ancestor_catalog \
  --set=owner_role=rag_owner --set=ingest_role=rag_ingest \
  --set=retrieval_role=rag_retrieval --set="migration_sha256=$sha_0001" \
  --file="$phase_root/migrations/0001_initial_rag_catalog.sql" >/dev/null
psql --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --dbname=ancestor_catalog \
  --set=owner_role=rag_owner --set=ingest_role=rag_ingest \
  --set=retrieval_role=rag_retrieval --set="migration_sha256=$sha_0002" \
  --file="$phase_root/migrations/0002_align_ingestion_ownership.sql" >/dev/null
psql --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --dbname=ancestor_catalog \
  --set=owner_role=rag_owner --set=ingest_role=rag_ingest \
  --set=retrieval_role=rag_retrieval --set="migration_sha256=$sha_0003" \
  --file="$phase_root/migrations/0003_separate_special_token_count.sql" >/dev/null
psql --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --dbname=ancestor_catalog \
  --set=owner_role=rag_owner --set=ingest_role=rag_ingest \
  --set=retrieval_role=rag_retrieval --set="migration_sha256=$sha_0004" \
  --file="$phase_root/migrations/0004_preserve_relationship_override_audit.sql" >/dev/null

schema_sha256="$(sha256sum "$final_schema" | awk '{print $1}')"
psql --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --dbname=consolidated_catalog \
  --set=owner_role=rag_owner --set=ingest_role=rag_ingest \
  --set=retrieval_role=rag_retrieval --set="schema_sha256=$schema_sha256" \
  --file="$final_schema" >/dev/null

normalize_dump() {
  local database="$1" output="$2"
  pg_dump --schema-only --no-owner --dbname="$database" | sed \
    -e '/^\\restrict /d' \
    -e '/^\\unrestrict /d' \
    -e '/^-- Dumped from database version /d' \
    -e '/^-- Dumped by pg_dump version /d' \
    -e '/^-- Started on /d' \
    -e '/^-- Completed on /d' >"$output"
}

normalize_dump ancestor_catalog "$work_root/ancestor.sql"
normalize_dump consolidated_catalog "$work_root/consolidated.sql"
cmp -s "$work_root/ancestor.sql" "$work_root/consolidated.sql" || exit 40

ancestor_ledger="$(psql --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --tuples-only --no-align --dbname=ancestor_catalog --command='SELECT count(*) || '"'|'"' || max(schema_version) FROM rag.schema_migrations;')"
consolidated_ledger="$(psql --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --tuples-only --no-align --dbname=consolidated_catalog --command="SELECT count(*) || '|' || max(schema_version) || '|' || min(migration_id) FROM rag.schema_migrations;")"
[[ "$ancestor_ledger" == '4|4' ]] || exit 41
[[ "$consolidated_ledger" == '1|4|ishikawa_consolidated_schema_v4' ]] || exit 42

for database in ancestor_catalog consolidated_catalog; do
  row_count="$(psql --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --tuples-only --no-align --dbname="$database" --command="SELECT (SELECT count(*) FROM rag.document_classes)+(SELECT count(*) FROM rag.documents)+(SELECT count(*) FROM rag.ingestion_runs)+(SELECT count(*) FROM rag.publication_batches)+(SELECT count(*) FROM rag.document_versions)+(SELECT count(*) FROM rag.document_artifact_sets)+(SELECT count(*) FROM rag.structural_units)+(SELECT count(*) FROM rag.chunks)+(SELECT count(*) FROM rag.chunk_structural_units)+(SELECT count(*) FROM rag.citation_anchors)+(SELECT count(*) FROM rag.embedding_spaces)+(SELECT count(*) FROM rag.chunk_embeddings)+(SELECT count(*) FROM rag.relationship_types)+(SELECT count(*) FROM rag.relationships)+(SELECT count(*) FROM rag.publication_batch_changes)+(SELECT count(*) FROM rag.active_document_versions)+(SELECT count(*) FROM rag_private.artifact_manifests)+(SELECT count(*) FROM rag_private.ingestion_stages)+(SELECT count(*) FROM rag_private.quarantine_records);")"
  [[ "$row_count" == 0 ]] || exit 43
done
INNER

chmod 0700 "$run_comparison"
set +e
pg_virtualenv -v 16 bash "$run_comparison" \
  "$work_root" "$PHASE_ROOT" "$FINAL_SCHEMA" \
  "$SHA_0001" "$SHA_0002" "$SHA_0003" "$SHA_0004" \
  >"$work_root/stdout" 2>"$work_root/stderr"
comparison_status=$?
set -e
if (( comparison_status != 0 )); then
  printf 'comparison_exit_code=%s;stdout_sha256=%s;stderr_sha256=%s;raw_output_retained=false\n' \
    "$comparison_status" \
    "$(sha256sum "$work_root/stdout" | awk '{print $1}')" \
    "$(sha256sum "$work_root/stderr" | awk '{print $1}')" >&2
  block catalog_equivalence_failed
fi

printf 'consolidated_database_schema_test=pass;schema_version=4;catalog_equivalence=exact;ancestor_ledger_rows=4;consolidated_ledger_rows=1\n'

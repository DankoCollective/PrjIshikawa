# Ishikawa incremental writer target integration source ready

Date: 2026-10-19

## Outcome

Numbered Script `24` is source-ready for operator execution against
EmceeDanko. No remote host was contacted during source preparation.

The complete local suite was repeated after the final import-boundary change:

```text
Ran 64 tests
OK
ishikawa_local_validation_tests=PASS
script_23_incremental_ingestion_writer_test=pass
```

The Script `24` local validation contract also passed:

```text
incremental_writer_target_integration_source=pass
target_contact=false;postgresql_connection=false;corpus_mutation=false
payload_file_count=14
```

## Target boundary

The operator-authorized run transfers only checksum-bound Python source, the
accepted `0001` and `0002` schema inputs, and a synthetic integration runner.
The neutral target helper:

- requires the accepted Ubuntu 24.04 AMD64, PostgreSQL 16.15, pgvector 0.8.7,
  Python 3.12, and Psycopg 3.1.17 identities;
- requires the cluster to begin stopped, loopback-only, manual, and
  boot-disabled;
- verifies the exact two-row migration ledger and zero corpus rows in the
  accepted `rag_catalog` database;
- creates only a separate `ishikawa_writer_test` database;
- applies the accepted schema to that disposable database;
- uses synthetic PDF bytes, text, metadata, and embeddings only;
- exercises add, reuse, revise, reprocess, quarantine, successful
  remediation, forced transactional rollback, and retirement;
- proves the final active projection contains only the expected synthetic
  document, chunk, citation, and embedding;
- proves `rag_retrieval` can read active views but cannot read base tables;
- drops the disposable database on both success and failure;
- proves the accepted `rag_catalog` contract is unchanged; and
- stops PostgreSQL and removes all temporary payload and private error files.

It does not install packages, alter service enablement, request an application
credential, read organizational documents, call Nomic or Gemma, or mutate the
accepted application database.

## Source identities

```text
24_test_incremental_writer_on_emceedanko.sh=792aa8a0d2314ee8b500bf1d20df0d9f5b1149b64f831e9e37ba2cb04f35d152
test-incremental-writer-integration=81c49d6557ed85f94543f2405ebaf40d89f4a2097dd3c81ad12eb495c4a88952
test-incremental-writer-integration.py=feb7818c17e1d27d1c67a14da51969bb25c44188d653521c3f3cc949ff5de23d
persistence.py=90e3158393cf8bd04401bde4e1dda8779cfefe8c672cf0c784adbab351b66096
0001_initial_rag_catalog.sql=3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a
0002_align_ingestion_ownership.sql=74b08adb8aac9828ac076744fedfd22619751326c911bf17f1fa8690e01345e4
accepted_migration_receipt=4d5d065a9a941bb11948fdfb24f552b4961602a4b8c9936805e93fe1aa41ffa1
accepted_migration_record=521013c39c88bd8f0733ea251aea38925cdb3791612471af06ef0d63baf4aeff
```

The payload-manifest identity is intentionally generated at execution time
from all 14 exact payload files and is printed by `--validate-only` and the
operator receipt.

## Operator command

From the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/24_test_incremental_writer_on_emceedanko.sh --run
```

Target execution status at publication: `NOT RUN`.

That publication-time status is superseded by
`ishikawa_incremental_writer_target_integration_acceptance_2026-10-19.md`.

After a passing receipt, the next gate is to freeze the consolidated
fresh-install schema and portable-package contract. Fresh installations use
the current schema baseline directly; they do not replay EmceeDanko's
historical `0001` then `0002` development sequence. Future upgrades from an
installed baseline remain versioned migration work.

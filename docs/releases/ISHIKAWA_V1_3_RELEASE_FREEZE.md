# Ishikawa v1.3 Release Freeze

## Release identity

- Release: Ishikawa v1.3
- Freeze date: 2026-10-24
- Origin repository commit: `2af707df7def519bd3d97658060f188ae60f7cc9`
- Origin product path: `phase-28-apisachi-tokuli/Ishikawa`
- Schema: version 5
- Qualification corpus: synthetic v3, 30 documents, 150 pages; separate from
  the application release
- Retrieval MRR@20: 0.895450
- Native regression: 486 tests passed
- Frontier gate: 60/60 passed
- Required evidence returned: 60/60
- Required evidence cited: 60/60
- Human UI validation: operator accepted with minor smoke testing

## Accepted evidence identities

- Frontier artifact SHA-256:
  `1ccb7d59ed67073213051d28cd6142ab445b616e34a6ef7eecb22b174b52d972`
- Frontier report SHA-256:
  `1e7a4a4d93d9e7ceebc5e447dd86c12a436389f8a791e3895c93f90fbfbfbfe4`
- Post-v1.3 roadmap origin SHA-256:
  `8d1265d78cf7ed9d108b10ae3d57aa3ed85a901dc721cec7c81d997ed1b184eb`

Raw frontier requests and responses remain ignored local evidence. The
identities above, sanitized metrics, and product source manifest form the
durable acceptance boundary. The qualification corpus establishes release
quality but is not an application build input or packaged application content.

## Superseded material

Earlier `v1.3-frontier-candidate` archives reporting 460 or 462 native tests are
superseded and must not be deployed. A final archive must be rebuilt from this
repository and pass its fresh-install verifier before publication.

## Deferred work

The post-v1.3 optimization backlog does not amend this release. Org-lab
migration remains deferred until EmceeDanko qualification and human acceptance.

## Historical-baseline disposition — 2026-10-26

The operator subsequently completed and accepted the attended v1.3 UI. The
content-free acceptance receipt is
`deployment/evidence/ISHIKAWA_V1_3_EMCEEDANKO_UI_ACCEPTANCE.md`.

The exact v1.3 archive and evidence remain immutable as the historical
behavioral baseline. They are not silently overwritten or relabeled. The
security dependency refresh and permanent `next build`/`next start` correction
are a separate patch release, Ishikawa v1.3.1, governed by V13-79 through
V13-89. v1.3.1 retains the v1.3 schema, corpus-agnostic product behavior,
retrieval metrics, and qualification expectations, but its changed application
and generic runtime-image bytes require fresh exact-byte qualification and
human acceptance before org-lab promotion.

## Deployment qualification correction

V13-71 preserves `127.0.0.1:1384` as the packaged Retrieval API default and
permits the private side-by-side qualifier to configure `127.0.0.1:1385` in
both relevant profiles. The qualifier now exercises the real packaged
configuration validator, and its hidden credential prompts are emitted before
input begins. This correction does not change retrieval, corpus, schema, UI, or
the frozen frontier acceptance metrics.

V13-73 corrects the schema-v5 identity carried by the application persistence
contract so it equals the checksum of the already frozen packaged schema. The
target qualifier now proves the staged application identity, packaged schema,
and installed migration ledger agree immediately after schema installation,
before any embedding or publication work. The exact boundary passes the full
486-test native suite and a real disposable PostgreSQL 16/pgvector check using
the `rag_ingest` role. This is a release-consistency correction; it changes no
schema structure, corpus, retrieval behavior, UI, or frontier metric.

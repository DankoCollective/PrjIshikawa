# Ishikawa v1.3 Frontier Freeze

## Release identity

- Release: Ishikawa v1.3 frontier
- Freeze date: 2026-10-24
- Origin repository commit: `2af707df7def519bd3d97658060f188ae60f7cc9`
- Origin product path: `phase-28-apisachi-tokuli/Ishikawa`
- Schema: version 5
- Synthetic corpus: v3, 30 documents, 150 pages
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
durable acceptance boundary.

## Superseded material

Earlier `v1.3-frontier-candidate` archives reporting 460 or 462 native tests are
superseded and must not be deployed. A final archive must be rebuilt from this
repository and pass its fresh-install verifier before publication.

## Deferred work

The post-v1.3 optimization backlog does not amend this release. Org-lab
migration remains deferred until EmceeDanko qualification and human acceptance.

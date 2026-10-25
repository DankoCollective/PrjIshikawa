# Ishikawa v1.3 Import Provenance

## Import identity

- Imported UTC date: 2026-10-24
- Origin repository: `Prj00DankoDeux`
- Origin commit: `2af707df7def519bd3d97658060f188ae60f7cc9`
- Origin product path: `phase-28-apisachi-tokuli/Ishikawa`
- Imported product path: `Ishikawa`
- Import method: checksum-bound snapshot; no invented Git history
- Origin bytes deleted or moved: no

## Frozen identities

- Ishikawa source manifest SHA-256:
  `96072ca839af49b239931036fdd6861763dc0d64d433ce29febb239e1d54868c`
- Frontier case-set SHA-256:
  `2ba5f61518ca17b0eaa26f024abe35418b050f9bd8d5b3e1677062c9d7a626a3`
- Corpus v3 origin manifest SHA-256:
  `3220c5ae7fd16c37086511893c63c4784b9adf10635e40c79332b4a7b4c79fce`
- Ordered corpus-PDF digest-list SHA-256:
  `2c08ec56440886eca1a68d37b0a57ccaad36ecbd1c3d3676e334224f8e28c87b`
- Accepted V13-59 qualification artifact SHA-256:
  `1ccb7d59ed67073213051d28cd6142ab445b616e34a6ef7eecb22b174b52d972`
- Accepted V13-59 report SHA-256:
  `1e7a4a4d93d9e7ceebc5e447dd86c12a436389f8a791e3895c93f90fbfbfbfe4`
- Original deferred-optimization note SHA-256:
  `8d1265d78cf7ed9d108b10ae3d57aa3ed85a901dc721cec7c81d997ed1b184eb`

## Qualification facts

- Native tests: 486 passing
- Frontier questions: 60/60 passing
- Retrieval MRR@20: 0.895450
- Synthetic corpus v3: 30 documents, 150 pages
- Local human UI acceptance: passed with minor smoke testing

## Import-only adaptations

- Rebased one reconstruction test from the origin repository's ignored local
  artifact path to an identical tracked fixture within this repository.
- Placed the four accepted extraction, normalization, chunking, and embedding
  commands under the canonical product script directory so the package no
  longer depends on a historical workstream path.
- Normalized tracked text to LF according to `.gitattributes`.

These adaptations change no runtime routing, retrieval, packing, generation,
database, UI, or citation behavior. The complete native suite passed 486 tests
after the fixture rebase.

The raw accepted report and artifact remain ignored local evidence. This record
retains only their identities and reviewed content-free conclusions.

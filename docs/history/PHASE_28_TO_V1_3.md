# Phase 28 to Ishikawa v1.3

Ishikawa began in the Phase 28 Apisachi Tokuli workspace. That work established
the document model, structural chunking, PostgreSQL schema, ingestion pipeline,
exact/lexical/vector retrieval, relationship traversal, bounded evidence
packing, Gemma generation contract, citation proof, reconstructed source views,
and operator-facing web interface.

The development workspace also contains the full experimental and repair trail.
Those materials are retained under `history/phase-28/` and in the origin
repository. They explain how the final posture was learned but are not the
fresh-install or target replay interface.

The v1.3 frontier boundary was reached after synthetic corpus v3 expanded the
fixture to 30 documents and 150 pages, retrieval reached MRR@20 0.895450, the
60-question frontier gate passed with complete required citation coverage, and
the operator accepted the local UI. `docs/releases/ISHIKAWA_V1_3_FRONTIER_FREEZE.md`
records the exact evidence identities.

Beginning with v1.3, this repository owns Ishikawa source, release packaging,
qualification, EmceeDanko deployment, and future planning. The origin repository
remains historical and is not deleted or silently rewritten.

The first-class import also relocated one reconstruction test artifact from the
origin repository's ignored `local/artifacts/` tree into a tracked test fixture
and copied four already-qualified ingestion pipeline commands into the canonical
product script directory. These are self-containment changes only; runtime logic
and accepted behavior are unchanged.

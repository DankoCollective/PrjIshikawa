# Ishikawa v1.3 Repository Sweep

Date: 2026-10-25

## Result

The active local Ishikawa v1.3 repository surface is internally consistent
after the corrections recorded below. The frozen application source manifest,
release archive, native suite, deployment wrapper tests, Python compilation,
shell syntax, and Markdown links pass locally.

The latest retained EmceeDanko Script 05 report is complete and clean. It
records 60/60 frontier cases, both standalone pass markers, v1.2 preservation,
and removal of the disposable PostgreSQL cluster, Retrieval API, credentials,
workspace, transfer, and reserved-port listeners. No remote host was contacted
during this sweep; this conclusion is based on the retained local report and
checksum-bound synthetic-only result.

## Scope reviewed

- repository control surface, decision ledger, release freeze, run order, and
  registries;
- active deployment scripts, helpers, tests, release assets, and checksum
  boundaries;
- the frozen v1.3 source manifest and current release archive;
- installed YAML contracts, ingestion/operator documentation, systemd user
  units, database grants, commands, accounts, listeners, and credential
  boundaries;
- local Markdown links and high-confidence credential patterns; and
- retained local Script 05 reports, result artifacts, and process state.

Binary/PDF payload content was not interpreted as source code. Its applicable
boundary remains manifest identity, checksum verification, and the qualified
ingestion path.

## Drift reconciled

1. Canonicalized V13-69 through V13-73 frozen-status spelling and restored the
   missing Recommendation fields for V13-71 and V13-72.
2. Expanded Script 01's decision preflight through V13-74 and made it require
   exactly one Decision, Recommendation, Reason/Evidence, and canonical frozen
   Status in every release decision block.
3. Added discoverable operator references for the complete YAML contracts,
   catalog/manifest/ingestion procedure, and accounts/services/permissions
   inventory.
4. Corrected one broken historical architecture link.
5. Classified `Ishikawa/README.md` as a retained frozen chronological ledger,
   not the current control authority.
6. Made EmceeDanko attended human UI acceptance an explicit prerequisite to
   assembling the org-lab carry package.

No frozen `Ishikawa/**` application byte was changed by these sweep
corrections. The application modifications already present in the working tree
remain covered by the accepted source manifest and validation results below.

## Validation evidence

- Script 01 static release validation: pass.
- Frozen source checksum manifest: pass.
- Native Python suite: 486 tests, pass.
- Release-boundary deployment tests: pass.
- Candidate stage helper and wrapper tests: pass.
- Candidate qualification helper and wrapper tests: pass, including the
  disposable PostgreSQL lifecycle, schema, Nomic contract, ingestion,
  60-question frontier set, relationship evidence, cleanup, and v1.2
  preservation.
- Shell syntax: 24 scripts, pass.
- Python byte compilation: 106 files, pass.
- Local Markdown links: 146 files, pass after the historical-link correction.
- Current release artifact verification: pass with release `v1.3`, schema
  version `5`, 486 native tests, 17 JavaScript tests, 60 frontier cases, no
  bundled source documents, and boot autostart disabled.
- High-confidence active-tree credential scan: no matches.
- EmceeDanko disposable Script 05 qualification: pass with 486 native tests,
  30 synthetic documents, 60/60 frontier cases, all required evidence returned
  and cited, v1.2 unchanged, accepted database untouched, and cleanup proved.
  The retained local report SHA-256 is
  `854240b564148f38853b183852ca98ac12d38ef3a57bb6ed513116270d7a98c0`.

## Remaining deployment gate

The operator must now perform attended human UI acceptance on EmceeDanko. Only
that accepted outcome authorizes assembly of the unchanged Ishikawa v1.3
archive with a separate org-lab deployment bundle.

The org-lab bundle must carry its reviewed document catalog and ingestion
manifest as separate checksum-verified inputs, then derive corpus-specific
counts and acceptance expectations from that catalog, the ingestion run, and
PostgreSQL. Synthetic corpus-v3 cardinalities are not portable acceptance
constants for the black corpus.

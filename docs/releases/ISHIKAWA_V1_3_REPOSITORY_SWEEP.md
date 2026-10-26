# Ishikawa v1.3 Repository Sweep

Date: 2026-10-25

## Result

The active local Ishikawa v1.3 repository surface is internally consistent
after the corrections recorded below. The frozen application source manifest,
release archive, native suite, deployment lifecycle and wrapper tests, Python
compilation, shell syntax, and Markdown links pass locally.

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
- the consolidated Script 06 preflight, isolated-cluster lifecycle, attended
  service boundary, automatic restoration, acceptance, rollback, reporting,
  and interruption behavior.

Binary/PDF payload content was not interpreted as source code. Its applicable
boundary remains manifest identity, checksum verification, and the qualified
ingestion path.

## Drift reconciled

1. Canonicalized V13-69 through V13-73 frozen-status spelling and restored the
   missing Recommendation fields for V13-71 and V13-72.
2. Expanded Script 01's decision preflight through V13-75 and made it require
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
7. Added one consolidated Script 06 that revalidates the exact Script 01 and
   Script 05 handoffs, creates or reuses an isolated durable v1.3 PostgreSQL
   cluster, reserves UI/API ports `3384`/`8384`, stops v1.2 only at the launch
   boundary, restores v1.2 after any failed launch, and exposes explicit human
   acceptance and rollback actions without changing boot autostart.
8. Reconciled the EmceeDanko `1384` contract after all-party review: Anderson
   is absent from the host, accepted v1.2 owns the port before switchover, and
   the port remains free afterward for automatic or explicit v1.2 rollback.
   Script 06 reports that purpose without an Anderson ownership label.
9. Added the operator-approved V13-76 Script 06 rollback waiver as an explicit
   `--run` flag while retaining the reversible default. The waiver removes the
   v1.2 password, readiness, model-forward, and automatic-restoration gates;
   it does not delete or overwrite either installation or database tree.

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
- Attended Script 06 target lifecycle tests: pass, including preflight
  no-mutation failure, fresh-build cleanup, exact durable reuse, real
  configuration/catalog/manifest validators, failed-launch restoration,
  restoration-failure reporting, explicit rollback waiver with inactive v1.2,
  waived failed-launch cleanup, durable retry, conditional later rollback,
  partial-state preservation, unrelated-PID protection, unsafe-runtime-path
  rejection and preservation, acceptance, rollback, and candidate/v1.2
  preservation.
- Attended Script 06 wrapper tests: pass, including exact evidence and payload
  validation, launch/accept/rollback modes, waiver propagation and mode
  restriction, precise remote-failure propagation, SIGTERM cleanup, one result
  marker, UI address, and operator commands.
- Script 01 decision/release validation through V13-76: pass.
- Script 06 local exact-evidence validation: pass with no target, database,
  service, or credential contact.
- Shell syntax: 27 active scripts, pass.
- Python syntax compilation: 106 files, pass without writing bytecode.
- Local Markdown links: 152 files, pass.
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

The org-lab bundle must carry only content-blind catalog/manifest creation and
validation tooling. Authorized operators create and checksum the protected
catalog and ingestion manifest inside org-lab, then derive corpus-specific
counts and acceptance expectations from those exact inputs, the ingestion run,
and PostgreSQL. Synthetic corpus-v3 cardinalities are not portable acceptance
constants for the black corpus.

## 2026-10-26 carry reconciliation supplement

The remaining-gate paragraph above is historical. The operator completed and
accepted the attended v1.3 UI; the tracked content-free receipt is
`deployment/evidence/ISHIKAWA_V1_3_EMCEEDANKO_UI_ACCEPTANCE.md`.

The accepted v1.3 bytes remain the immutable behavioral baseline. Current
org-lab work is the separately identified v1.3.1 security and production-web
correction under frozen V13-79 through V13-89. Its architecture is the external
application plus a separate application-free generic Linux AMD64 runtime
image. Every permanent start uses read-only source, a bounded ephemeral
`.next`, `next build`, and `next start`; no application or generated `.next`
state is baked into the image.

The protected organizational catalog and ingestion manifest are not carried.
Only content-blind creation/validation tooling and empty metadata structure
travel. Authorized operators create and review the exact catalog and manifest
inside org-lab, and every corpus metric derives from those inputs and the
resulting PostgreSQL state.

Local implementation and command-double branch gates are recorded in
`ISHIKAWA_ORG_LAB_CARRY_READINESS_CHECKLIST.md`. The package remains not
carry-ready until the exact AMD64 image and application are built, security and
license evidence is reviewed, the changed bytes pass EmceeDanko production
qualification and human acceptance, Tech inventory is accepted, independent
review completes, and the stable carry handoff is atomically promoted.

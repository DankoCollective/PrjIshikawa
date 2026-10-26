# Ishikawa Project Runbook

## Required order

1. Work from the repository root and review the control surface.
2. Keep the frozen v1.3 source unchanged while assembling the release.
3. Run local source, native, web, package, fresh-install, and checksum gates.
4. Script 01 publishes the corpus-agnostic application only as
   `local/artifacts/ishikawa-v1.3-current/`.
5. Script 02 runs the operator-attended EmceeDanko inventory before any target
   mutation.
6. Script 03 exports corpus v3 independently as
   `local/artifacts/qualification-corpus-v3-current/`. The corpus export is a
   qualification input and is not an application build dependency. It contains
   source PDFs and checksum-bound identity metadata, but no prebuilt document
   catalog or ingestion manifest.
7. Script 04 stages or checksum-verifies the exact v1.3 application at
   `~/Documents/Ishikawa-v1.3` and the separate qualification input without
   changing the active v1.2 installation, services, ports, or database. When a
   corrected archive must replace an earlier unqualified candidate, invoke
   Script 04 with `--replace-unqualified-candidate`; the helper publishes the
   correction atomically and restores the earlier candidate on failure. When a
   corrected corpus transfer must replace earlier unqualified qualification
   inputs, add `--replace-qualification-inputs`; this never changes an accepted
   database or the active v1.2 installation.
8. Script 05 first proves locally that the exact Script 01 archive accepts the
   reserved private ports. It then re-verifies the exact staged application,
   creates a private target copy, runs all 486 native tests against that private
   installation, creates a disposable PostgreSQL cluster, and proves that the
   accepted v1.2 installation, service, ports, and database remain unchanged.
9. Script 05 creates a new document catalog and ingestion manifest on
   EmceeDanko from the verified corpus-v3 metadata for that disposable run,
   validates both through the shipped application validators, ingests corpus v3
   through the shipped pipeline, runs the complete 60-question frontier gate,
   fetches a synthetic-only result, and proves removal of the temporary API,
   database, credentials, workspace, generated manifests, and transfer.
   Its corpus-v3 inventory gate distinguishes 240 stored relationship records
   from 90 distinct source-document/target-identity relationship pairs; neither
   metric may substitute for the other.
10. Script 06 revalidates the exact application, candidate, corpus-v3 input,
    and Script 05 evidence, then completes all host, model, PostgreSQL 16,
    pgvector, capacity, image, configuration, layout, and port preflights. Its
    default `--run` path also requires v1.2 to remain ready. The explicit
    V13-76 `--waive-v1-2-rollback` path does not require v1.2 readiness, its
    database password, or its separate model forwards; this waiver is valid
    only with `--run`.
11. For a fresh run, Script 06 creates the corpus-v3 catalog and manifest,
    builds schema v5 and ingests corpus v3 in a dedicated durable PostgreSQL
    cluster on private validation port `65438`, and revalidates the complete
    corpus inventory. It never opens or modifies the accepted v1.2 database.
12. Only at the immediate attended launch boundary, Script 06 stops any
    present v1.2 UI, Retrieval API, and host PostgreSQL cluster. It then starts
    the isolated v1.3 cluster on `5432`, the package-local Retrieval API on
    `8384`, and the distinct UI container on `3384`. No v1.3 systemd unit is
    installed or enabled, and all boot autostart remains disabled. On the
    default path, any failed launch stops v1.3 and automatically restores the
    untouched v1.2 PostgreSQL cluster, Retrieval API, and UI. On the explicit
    V13-76 waiver path, a failed launch stops v1.3, preserves both installation
    and database trees, leaves v1.2 stopped, and reports that automatic
    restoration was deliberately waived.
13. Record acceptance with Script 06 `--accept` or restore v1.2 with Script 06
    `--rollback`. Rollback preserves the isolated durable v1.3 cluster for
    review or an exact retry. Assemble the org-lab
    carry package and begin org-lab planning only after the exact EmceeDanko
    application has passed attended human UI acceptance.

## Active commands

- `deployment/scripts/01_build-ishikawa-release.sh`
- `deployment/scripts/02_inventory-emceedanko.sh`
- `deployment/scripts/03_export-qualification-corpus.sh`
- `deployment/scripts/04_stage-v1.3-candidate-on-emceedanko.sh`
- `deployment/scripts/05_qualify-v1.3-on-emceedanko.sh`
- `deployment/scripts/06_attended-v1.3-on-emceedanko.sh`

Script 05 prints a complete `[INPUT REQUIRED]` line before each hidden Gemma
and Nomic API-key input. It does not log or retain either value. A clean Script
05 result authorizes the
attended production-port human UI gate; it does not itself promote v1.3 or stop
v1.2.

Script 06's default `--run` prompts for the Gemma key, Nomic key, accepted
v1.2 retrieval password, and separate v1.3 ingestion/retrieval passwords
through hidden terminal input. `--run --waive-v1-2-rollback` omits the v1.2
password and readiness contact, so it requires only the Gemma and Nomic model
forwards selected for v1.3 plus the two v1.3 database passwords. A passing
launch prints the local UI address, SSH forwarding command, and exact
`--accept` command. The default path prints an unconditional `--rollback`
command; the waiver path prints the same command as conditional recovery and
states that it first requires the v1.2 password and its `8000`/`8001` model
forwards. Script 06 does not promote v1.3 into the canonical v1.2 path and does
not authorize org-lab packaging.

## Evidence rules

Detailed reports stay under ignored `local/reports/`. Only reviewed,
content-free summaries are promoted under `deployment/evidence/` or
`docs/releases/`. Every retained release artifact is checksum-bound.

## Release identity boundary

`Ishikawa v1.3` is the application release. It has no corpus dependency and
contains no source documents. `qualification-corpus-v3` is a separately built,
separately transferred synthetic qualification fixture. Target-side chunking
and ingestion publish that fixture to PostgreSQL; its transfer archive is not a
runtime retrieval index.

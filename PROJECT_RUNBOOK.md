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
    default `--run` path also requires v1.2 to remain ready and proves that a
    fresh disposable v1.2 UI can be recreated from the preserved launcher,
    image, and source tree on temporary port `3394`, then completely removes
    that proof container before any durable v1.3 database work. The explicit
    V13-76 `--waive-v1-2-rollback` path does not require v1.2 readiness, its
    database password, its separate model forwards, or the disposable v1.2
    recreation proof; this waiver is valid only with `--run`. Instead, the
    waiver path starts the durable v1.3 database on private port `65438`, the
    package-local Retrieval API on `8384`, and the exact UI on `3384`, and
    requires the integrated database, corpus-v3, Gemma, Nomic, API, and UI
    readiness chain to pass before issuing any v1.2 stop command.
11. For a fresh run, Script 06 creates the corpus-v3 catalog and manifest,
    builds schema v5 and ingests corpus v3 in a dedicated durable PostgreSQL
    cluster on private validation port `65438`, and revalidates the complete
    corpus inventory. It never opens or modifies the accepted v1.2 database.
12. Only after the applicable pre-switchover proof, Script 06 stops any
    present v1.2 UI, Retrieval API, and host PostgreSQL cluster. On the waiver
    path, the already-proven v1.3 API and UI must remain ready throughout that
    stop; Script 06 then cleanly stops only the proven v1.3 stack, changes its
    PostgreSQL profile from private validation port `65438` to required runtime
    port `5432`, and relaunches v1.3 on `5432`/`8384`/`3384` for human
    validation. On the default path it starts that final v1.3 arrangement
    directly after the reversible switchover. No v1.3 systemd unit is
    installed or enabled, and all boot autostart remains disabled. The v1.3 UI
    runs as the numeric deployment-account UID/GID with `HOME=/tmp`, exact
    source mounted read-only, and generated `.next` state isolated in a
    bounded disposable tmpfs; Script 06 proves that exact runtime before
    stopping v1.2. On the
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
14. After acceptance, use
    `docs/releases/ISHIKAWA_ORG_LAB_CARRY_READINESS_CHECKLIST.md` to freeze the
    remaining release/runtime decisions, consolidate the canonical final
    package, and prove the small-footprint, portable-name, advisory, license,
    reproducibility, installed-layout, target-inventory, and carry gates. Do
    not publish or carry while any mandatory checklist item remains open.
15. Run Script 07 to transfer the checksum-bound generic-image sources to the
    native Ubuntu 24.04 AMD64 EmceeDanko Docker host, build and verify the
    application-free Linux AMD64 runtime-image handoff there, and return it to
    the local artifact lane. Script 08 then transfers the checksum-bound
    external application source and revised Script 01 to the same native host,
    proves the retained Script 07 image ID, runs every application build gate,
    and returns only the verified deterministic application handoff. Keep the
    two handoffs separate.
16. Run the complete native suite plus the runtime-image, production-stack,
    application-boundary, carry-builder, and portable-deployment branch
    harnesses. A mocked branch test supports failure coverage but does not
    replace a real AMD64 image build or production UI qualification.
17. Run Script 09 `--run` to repeat every affected exact-byte gate on
    EmceeDanko with the v1.3.1 application and generic image. Script 09
    verifies the exact Script 07/08 identities, installs v1.3.1 only at
    `~/Documents/Ishikawa-v1.3.1-qualification`, reuses the accepted corpus-v3
    database read-only on port `5432`, and starts only a package-local
    candidate Retrieval API on `8385` and production UI on `3385`. It requires
    the accepted v1.3 API/UI on `8384`/`3384` to remain ready, runs all 60
    synthetic frontier cases, removes the first production container and its
    bounded `.next` tmpfs, and performs a fresh second `next build`/`next
    start` before attended review. Record human UI acceptance with Script 09
    `--accept`, then remove only the isolated candidate with Script 09
    `--cleanup`. Do not alter the accepted v1.3 evidence or treat it as
    acceptance of v1.3.1.
18. Assemble only the candidate carry directory with
    `build-carry-candidate.sh`. Promote to the stable
    `local/artifacts/ishikawa-deployment-current/` handoff only after exact-byte
    requalification, target-independent security and license review, complete
    checklist closure, and independent final review.
19. On Tech, run the portable verifier and read-only inventory before any
    mutation. Install through the consolidated `deploy-ishikawa` entrypoint,
    create the protected catalog and manifest inside org-lab, and derive every
    corpus metric from that exact protected run.

## Active commands

- `deployment/scripts/01_build-ishikawa-release.sh`
- `deployment/scripts/02_inventory-emceedanko.sh`
- `deployment/scripts/03_export-qualification-corpus.sh`
- `deployment/scripts/04_stage-v1.3-candidate-on-emceedanko.sh`
- `deployment/scripts/05_qualify-v1.3-on-emceedanko.sh`
- `deployment/scripts/06_attended-v1.3-on-emceedanko.sh`
- `deployment/scripts/07_build-node-next-runtime-on-emceedanko.sh`
- `deployment/scripts/08_build-v1.3.1-application-on-emceedanko.sh`
- `deployment/scripts/09_requalify-v1.3.1-on-emceedanko.sh`
- `deployment/scripts/build-carry-candidate.sh`
- `deployment/carry/verify-deployment`
- `deployment/carry/deploy-ishikawa`

Script 05 prints a complete `[INPUT REQUIRED]` line before each hidden Gemma
and Nomic API-key input. It does not log or retain either value. A clean Script
05 result authorizes the
attended production-port human UI gate; it does not itself promote v1.3 or stop
v1.2.

Script 06's default `--run` prompts for the Gemma key, Nomic key, accepted
v1.2 retrieval password, and separate v1.3 ingestion/retrieval passwords
through hidden terminal input. `--run --waive-v1-2-rollback` omits the v1.2
password, readiness contact, and disposable recreation proof, so it requires
only the Gemma and Nomic model forwards selected for v1.3 plus the two v1.3
database passwords. A passing
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

The accepted v1.3 bytes remain the historical behavioral baseline. The
security and permanent-production-runtime correction is `Ishikawa v1.3.1`.
Its application archive remains external to, and separately checksum-bound
from, the generic Linux AMD64 Node/Next runtime-image archive. Neither local
candidate handoff becomes the stable org-lab carry until the v1.3.1 exact-byte
requalification and promotion gates pass.

Script 09's `--run` mode prompts at the target for the Gemma key, Nomic key,
and existing v1.3 retrieval-role password. It does not request an ingestion
password because its database access is read-only and it does not recreate or
modify corpus v3. A passing run leaves the exact candidate on ports
`3385`/`8385` for attended review and prints the `--accept` and `--cleanup`
commands. The accepted v1.3 runtime remains on `3384`/`8384` throughout.
Script 09 defaults to the frozen v1.3 Gemma/Nomic forward ports
`18000`/`18001`; create those loopback listeners on EmceeDanko, not on the
wrapper host.

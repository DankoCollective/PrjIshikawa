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
18. After Script 09 cleanup, run Script 10 `--run` to promote the exact
    accepted v1.3.1 application and generic image on EmceeDanko. Script 10
    stages and proves v1.3.1 while v1.3 stays ready, stops v1.3 only at the
    switch boundary, moves the stopped corpus-v3 PostgreSQL state unchanged
    into `~/Documents/Ishikawa-v1.3.1`, and starts the package-local Retrieval
    API and production UI on `8384`/`3384`. A failed launch automatically
    restores v1.3. Record the promoted UI decision with Script 10 `--accept`,
    or use Script 10 `--rollback` before acceptance. Acceptance retires the
    superseded v1.3 application root and old runtime image only after removing
    exact named Ishikawa containers and stopped containers that still use that
    exact old image, then proving no running unknown consumer remains. A
    running unknown consumer blocks with its name, running state, and image
    identity. Boot autostart stays disabled; v1.2 files and database remain
    historical and non-operational.
19. After Script 10 acceptance, assemble only the candidate deployment-package
    directory with Script 11
    `11_assemble-ishikawa-v1.3.1-deployment-package.sh`. Script 11 requires the
    complete Script 09 and Script 10 lifecycle receipts, creates the canonical
    final application-release record and classified package manifest, and
    refuses stable promotion. Promote to the stable
    `local/artifacts/ishikawa-deployment-current/` handoff only after exact-byte
    requalification, target-independent security and license review, complete
    checklist closure, and independent final review.
    Candidate storage may be mode-neutral (for example, a Windows-backed
    transfer directory): `PACKAGE_MANIFEST.json` records the required Unix
    modes, the portable verifier validates that classification, and the Tech
    installer materializes those modes on the native target filesystem.
20. On Tech, run the portable verifier and read-only inventory before any
    mutation. Install through the consolidated `deploy-ishikawa` entrypoint,
    create the protected catalog and manifest inside org-lab, and derive every
    corpus metric from that exact protected run.
21. V13-92 supersedes only the v1.3.1 runtime-image handoff. After corrected
    Script 07 and unchanged-application Script 08 pass, run Script 12 `--run`.
    Script 12 binds application archive
    `2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69`
    to corrected runtime archive
    `b92dd71eb155493d7e331e85c92566eee113ed4c8f0eda605c1c3dd951b836e1`
    and image
    `sha256:6c93bcb5ed22de92420c4de4892eecdd08f1badc8b19e4d6f4488711f8f7a31a`.
    It leaves accepted v1.3.1 on `3384`/`8384`/`5432` untouched, installs the
    isolated candidate at
    `~/Documents/Ishikawa-v1.3.1-runtime-qualification`, reuses corpus v3
    read-only, and proves all 60 frontier cases plus two fresh production
    build/start containers on `3385`/`8385`. Record human acceptance with
    Script 12 `--accept`, then remove only that candidate with `--cleanup`.
22. Do not rerun the original Script 10 promotion or Script 11 assembly after
    V13-92: both remain deliberately pinned to the superseded image and refuse
    the corrected handoff. After the complete Script 12 lifecycle, run Script
    13 `--run`. Script 13 verifies the exact accepted application, installed
    web path set and bytes, current production receipt, both runtime images,
    all Script 12 receipts, ports, readiness, and disabled boot posture before
    service mutation. The run carries both checksum-bound runtime archives and,
    if either recreatable Docker image is absent, loads the previous archive
    first and the corrected archive last so the canonical tag remains on the
    corrected image. It then removes only the production web container and
    recreates it on `3384` with the corrected image. It does not replace or
    restart the application, Retrieval API, PostgreSQL, or corpus. A failed
    switch or interrupted run automatically recreates the previous production
    web runtime. Record human acceptance with Script 13 `--accept`, which
    refuses unknown superseded-image consumers before removing the old image;
    or use Script 13 `--rollback` before acceptance.
23. After Script 13 acceptance, run Script 14 `--run`. It binds the unchanged
    application, corrected image, complete Script 12/13 lifecycle receipts,
    exact corrected-image scan, durable and portable security dispositions,
    SBOM/license records, and frozen V13-79 through V13-93 decisions. It
    independently verifies the resulting 26-file package, preserves the
    verified Script 11 candidate under `local/artifacts/superseded/`, and
    atomically publishes only the corrected candidate at
    `local/artifacts/ishikawa-deployment-v1.3.1-candidate-current/`. The
    candidate remains non-installable until Tech inventory and independent
    final review authorize stable publication.
24. After the accepted read-only Tech inventory proves that PostgreSQL 16,
    pgvector, Psycopg, and related native prerequisites are missing, follow
    `docs/operations/ISHIKAWA_ORG_LAB_NATIVE_PACKAGE_METHOD.md`. Capture the
    Ubuntu 26.04 AMD64 closure on the approved internet-connected work laptop
    with isolated target-specific APT metadata. Do not use the work laptop's
    normal release metadata, install the packages there, or contact Tech during
    capture and qualification.

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
- `deployment/scripts/10_promote-v1.3.1-on-emceedanko.sh`
- `deployment/scripts/11_assemble-ishikawa-v1.3.1-deployment-package.sh`
- `deployment/scripts/12_requalify-v1.3.1-corrected-runtime-on-emceedanko.sh`
- `deployment/scripts/13_promote-v1.3.1-corrected-runtime-on-emceedanko.sh`
- `deployment/scripts/14_assemble-v1.3.1-corrected-deployment-package.sh`
- `deployment/carry/verify-deployment`
- `deployment/carry/deploy-ishikawa`
- `deployment/carry/capture-native-prerequisites`

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
`18000`/`18001`. The operator owns the direct EmceeDanko-to-00Danko SSH
tunnel outside Script 09; use the canonical four-service mapping in
`local/pf/Port_Forwarding.md`, even though Ishikawa consumes only Gemma and
Nomic. Do not originate that model tunnel on the Script 09 wrapper host.
Script 09 preflights its local report and evidence publication lanes before
target work. Acceptance or cleanup may recover the exact content-free
qualification receipt from the still-durable target candidate when a prior
local publication failed; target runtime state and protected output are not
recovered through that path.

Script 10 requires the complete checksum-bound Script 09 qualification,
acceptance, and cleanup evidence before target contact. Its `--run` mode
prompts at the target for the Gemma key, Nomic key, and existing v1.3
retrieval-role password. It performs no schema, corpus, or role mutation. It
moves the stopped durable state rather than copying or rebuilding it, launches
the exact v1.3.1 runtime on `5432`/`8384`/`3384`, and leaves v1.3 available as
an automatic and explicit pre-acceptance rollback source. Script 10 `--accept`
is non-secret and finalizes retirement; `--rollback` requires the same three
runtime secrets. The direct EmceeDanko model tunnel remains operator-managed.

Script 12 uses the same reviewed side-by-side lifecycle with a distinct
corrected-runtime profile, candidate root, container name, receipt schemas,
artifact lane, and standalone result. Its `--run` mode has the same three
hidden inputs and requires the operator-managed Gemma/Nomic forwards on
EmceeDanko ports `18000`/`18001`. A passing run leaves only the isolated
corrected-runtime candidate on `3385`/`8385`; accepted v1.3.1 and its database
remain unchanged until a later promotion step.

Script 13 is the corrected-runtime production promotion. It requires no model
or database secret because the accepted Retrieval API and PostgreSQL process
remain running. Only the exact production web container is replaced. Its
`--run` action transfers and verifies both exact image archives, restores a
missing recreatable image before the switch, and retains the previous image
for automatic or explicit rollback. `--accept` retires that image only after
proving it has no container consumer.

Script 14 is local corrected-carry assembly. It contacts no target, reads no
credential or corpus, and mutates no service, listener, database, or boot
state. Its output is deliberately a review-pending candidate, not the stable
deployment handoff. Run the portable verifier from the resulting directory
before the separate Tech inventory and independent-review gates.

The carried deploy entrypoint's inventory action verifies the complete package
before invoking the read-only inspector. Supply all five selected ports and
use its attended-sudo inventory option when the installing operator needs
sudo for Docker and an already-online PostgreSQL catalog. The inspector never
starts PostgreSQL. It records package/runtime availability, apt/dpkg health,
capacity, paths, user units, user-manager/lingering posture, Docker
image/container facts, PostgreSQL clusters and clean-target counts, all five
listener counts, and an optional protected-source-root usability result
without retaining the hostname, account, protected path, or document names.

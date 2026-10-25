# Ishikawa Project Runbook

## Required order

1. Work from the repository root and review the control surface.
2. Keep the frozen v1.3 source unchanged while assembling the release.
3. Run local source, native, web, package, fresh-install, and checksum gates.
4. Publish only qualified application and corpus bundles to their stable
   `-current` handoff directories.
5. Run the operator-attended EmceeDanko inventory before any target mutation.
6. Qualify the exact carried bundles in a disposable target installation and
   disposable PostgreSQL database.
7. Ingest corpus v3 through the shipped pipeline and run the complete
   60-question frontier gate on the target.
8. Prove disposable cleanup, then install v1.3 without overwriting the accepted
   prior installation.
9. Keep boot autostart disabled and start Ishikawa only for attended human UI
   verification.
10. Record acceptance or execute the proved rollback. Begin org-lab planning
    only after EmceeDanko acceptance.

## Active commands

- `deployment/scripts/build-ishikawa-release.sh`
- `deployment/scripts/inventory-emceedanko.sh`
- Later target qualification, deployment, acceptance, and rollback commands
  must use product/action names and must not require historical Phase 28 repair
  scripts.

## Evidence rules

Detailed reports stay under ignored `local/reports/`. Only reviewed,
content-free summaries are promoted under `deployment/evidence/` or
`docs/releases/`. Every retained release artifact is checksum-bound.

# Application Host Inventory Pass

## Result

Accepted the operator-executed read-only application-host inventory as a
passing Danko `linux/amd64` host and native-package baseline. This is inventory
evidence only. It does not claim Docker image readiness, application
installation, extraction quality, database readiness, or service readiness.

## Evidence

- Local ignored report:
  `local/reports/application-host-inventory/application_host_inventory_20261019T014205Z_hQirh3.txt`
- Report SHA-256:
  `a02fd0767b5db8e9584abfd8e720bb6dd039552fa45e301001191f795e60f69b`
- Report size: `3,786` bytes and `74` lines.
- Wrapper result: `pass`.
- Target mutation: none.
- Target files created: none; the neutral helper was streamed over SSH.
- Credential handling: operator-entered SSH passphrase only; no credential was
  read, copied, printed, or retained by the script.

## Accepted Facts

- Exact expected-hostname check passed.
- Ubuntu `24.04.5 LTS`, kernel `7.0.0-34-generic`, `x86_64`/`amd64`.
- Python `3.12.3`; the functional `venv` check passed even though the
  `python3-venv` metapackage was not installed. Host pip was unavailable.
- Poppler `24.02.0` was installed through Ubuntu package
  `24.02.0-1ubuntu9.10`; both `pdftotext` and `pdfinfo` were present.
- Docker CE and CLI `29.9.1`, containerd `2.4.2`, Buildx package `0.38.0`, and
  Compose plugin package `5.6.0` were installed.
- The unprivileged SSH session could not query the Docker daemon. No sudo
  prompt was attempted, so runtime versions and allowlisted image identities
  remain unverified.
- The PostgreSQL client, PostgreSQL common package, and host psycopg2 package
  were absent. The operator subsequently selected native host Python and
  native PostgreSQL/pgvector, so these absences define the next native-package
  qualification gate rather than a container-image requirement.
- TCP port `3000` was occupied; ports `1384` and `5432` were not listening.
- Capacity reported approximately `419 GiB` available on the home filesystem.

## Disposition

The bounded attended-sudo container-runtime inventory was subsequently run and
accepted for the sole selected application container: the existing
Node/Next.js image. The later three-image capture is historical and shall not
be transferred or loaded.

Next, use an operator-executed read-only inventory to identify the native
PostgreSQL/pgvector packages and remaining native Python dependencies. The org
target shall use the same neutral inventory approach through an
operator-executed wrapper and an operator-controlled temporary report
location. Target-specific package versions must be recorded separately.

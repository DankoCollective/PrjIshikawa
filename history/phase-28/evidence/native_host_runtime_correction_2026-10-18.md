# Native Host Runtime Correction

## Decision Correction

The operator clarified the intended first-slice runtime boundary:

- the existing Node 24/Next.js 16.4.1 image is the only application container;
- Next.js source remains on the host and is bind-mounted into that unchanged
  image;
- the retrieval API and one-shot corpus commands run with native host Python;
- PostgreSQL and pgvector are installed and run natively on the host; and
- no Python or PostgreSQL/pgvector image is a deployment input.

The earlier phrase “application and database live on the host” had been
incorrectly interpreted as host-mounted source and data executed by additional
containers. This record corrects that interpretation. It reopens only the
runtime portions of `D23` and `G20`; all unrelated frozen decisions remain
unchanged.

## Existing Evidence

The accepted EmceeDanko inventory already establishes:

- Ubuntu `24.04.5` on `linux/amd64`;
- native Python `3.12.3`;
- a functioning Python `venv` capability;
- distribution-provided PyYAML `6.0.1`;
- distribution-provided Poppler `24.02.0`; and
- the accepted AMD64 Node/Next.js developer image already present locally.

The inventory also establishes that host pip, `python3-psycopg2`, the
PostgreSQL client, and PostgreSQL common packages were absent at inventory
time. PostgreSQL server and pgvector native-package availability were not yet
fully inventoried. These are native-package qualification gaps, not reasons to
introduce more containers.

## Disposition of Script 04

Script `04` produced a technically valid archive containing Node, Python, and
PostgreSQL/pgvector images. That archive is not selected for deployment. Do
not transfer it, load it, or use it as an installation input. It remains in
the ignored local artifact tree pending an explicit operator deletion
decision; this correction does not authorize deletion.

## Accepted Configurable Runtime Transport

The browser surface remains on `127.0.0.1:3000`, and native retrieval remains
on `127.0.0.1:1384`. A normally bridged Node container cannot reach a host
service that listens only on host loopback. The operator accepted running the
sole Node container with configurable host networking, explicitly binding
Next.js through configurable values that default to `127.0.0.1:3000`, and
configuring the native retrieval URL with a default of
`http://127.0.0.1:1384`. Native retrieval separately defaults to
`127.0.0.1:1384`. This preserves loopback-only access without exposing another
host interface.

That acceptance recloses `G20` and the runtime portion of `D23`.
Target-native dependency inventory and qualification remain implementation
evidence, not open architecture decisions.

The first PostgreSQL implementation gate is the neutral read-only native
package inventory defined in `../docs/NATIVE_POSTGRESQL_CAPTURE_PLAN.md`. It
does not install, initialize, configure, or start PostgreSQL.

## Non-Actions

- Codex did not contact EmceeDanko or org-lab.
- No package was installed or removed.
- No service or container was started, stopped, or changed.
- No archive or image was transferred, loaded, or deleted.
- No credential, private content, or remote output was captured.

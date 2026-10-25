# Native PostgreSQL Cluster Initialization Source Ready — 2026-10-19

## Disposition

Script `15` and its neutral target helper are source-ready and bound to the
accepted Script `14` installation receipt.

Source identities:

- `15_initialize_native_postgresql_cluster.sh`
  - SHA-256: `ae52b26ab6370061d9373f6655f0accc5010e5b3595667e0b91db7363b38575f`
- `initialize-native-database-cluster`
  - SHA-256: `b8c1a4eef6e33698ab39252efb7ddba43a12a9f0072d20658459722c3c1fa2be`
  - bytes: `11661`

The guarded initialization:

- requires explicit `--initialize` authorization;
- re-verifies the exact nine package tuples and runtime versions;
- requires zero existing clusters, free port `5432`, disabled automatic
  cluster creation, and an inactive/boot-disabled PostgreSQL service;
- initializes only PostgreSQL `16/main` in the distribution-managed
  `/var/lib/postgresql/16/main` data directory;
- selects UTF-8, enables data-page checksums, uses peer authentication for
  local socket access, and SCRAM-SHA-256 for loopback host access;
- binds PostgreSQL configuration to `127.0.0.1:5432`;
- canonicalizes the dotted IPv4 value as a quoted PostgreSQL string and
  requires the server binary to parse the complete configuration;
- sets the cluster to manual start, leaves it stopped, and keeps the service
  disabled at boot;
- validates cluster identity, ownership/mode, authentication rules,
  checksums, listener absence, and service state; and
- does not access a package network, change packages, start PostgreSQL, or
  create an application database, role, schema, extension, credential, or
  secret.

Local validation passed:

```text
native_postgresql_cluster_initialization_source=pass
target_contact=false
database_cluster_initialization=false
```

Operator command:

```bash
bash ./phase-28-apisachi-tokuli/scripts/15_initialize_native_postgresql_cluster.sh --initialize
```


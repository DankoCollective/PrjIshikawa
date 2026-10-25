# Compatible Native PostgreSQL Package Installation Source Ready — 2026-10-19

## Disposition

Script `12` and its neutral target helper are source-ready for the explicitly
authorized offline installation of the package set accepted by Script `11`.

Source identities:

- `12_install_compatible_native_postgresql_packages.sh`
  - SHA-256: `7310bbd892af34fe3497d30078d0c48ac57d2568d0cac9bc7208e0df95b0420e`
- `install-compatible-native-database-packages`
  - SHA-256: `4cfe41ddcd93e15d4babed2289174599e164baa9e323aa746b3f1fba8933bcc4`
  - bytes: `15879`

The wrapper binds:

- the accepted Script `11` report and its exact SHA-256;
- the accepted compatible bundle and its exact SHA-256;
- the exact Ubuntu `24.04` AMD64 host identity;
- an explicit `--install` authorization argument.

## Guarded behavior

The target helper:

1. re-verifies the bundle, internal checksums, package coordinates, license
   rows, advisory rows, JIT compatibility, and target state;
2. simulates the exact install with package sources disabled;
3. installs only the eight absent local `.deb` packages while reusing the
   exact installed `libllvm19`;
4. installs support packages first, then disables automatic cluster creation
   before installing the PostgreSQL server and pgvector;
5. blocks service start during package configuration;
6. leaves PostgreSQL stopped and disabled at boot;
7. proves that no cluster or data directory was created and port `5432`
   remains free;
8. validates PostgreSQL, `psql`, pgvector, Psycopg, and all nine exact package
   versions;
9. returns a bounded receipt and removes the temporary target payload.

It does not initialize a database, create schemas or roles, acquire a package
from the network, or read application content or secrets.

## Local validation

Both scripts passed `bash -n`, the target helper passed the neutral-language
check, and the wrapper passed its no-contact validation:

```text
compatible_native_postgresql_package_installation_source=pass
target_contact=false
package_install=false
```

## Operator command

Run from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/12_install_compatible_native_postgresql_packages.sh --install
```

The operator may receive the SSH-key prompt and a separate sudo-password
prompt. Review the returned receipt before database initialization.


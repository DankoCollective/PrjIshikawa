# Container Runtime Inventory Pass

## Result

Accepted the operator-executed, attended-sudo container-runtime inventory as a
passing read-only Docker and allowlisted-image baseline for the Danko
`linux/amd64` application host. This proves the existing runtime facts; it does
not claim that missing runtime images have been selected or acquired, or that
the application has been implemented.

## Evidence

- Local ignored report:
  `local/reports/container-runtime-inventory/container_runtime_inventory_20261019T014658Z_Cp464S.txt`
- Report SHA-256:
  `a83c486a065237b85f7687b5a7cbadaa062987ddae2f216d232eea99b24d13c8`
- Report size: `2,861` bytes and `57` lines.
- Wrapper result: `pass`.
- Exact expected-hostname check: pass.
- Remote temporary files: removed by the wrapper.
- SSH master cleanup: pass.
- Container mutation: none.
- Network access: none.
- Credential handling: operator entered the SSH and sudo credentials; neither
  value was read, copied, printed, or retained by the wrapper.

## Accepted Facts

- Docker client and server: `29.9.1`.
- Docker Compose: `5.6.0`.
- Docker Buildx: `0.38.0`.
- Docker architecture/OS: `x86_64`, Ubuntu `24.04.5 LTS`.
- Storage/cgroup drivers: `overlayfs` and `systemd`.
- Docker filesystem capacity: approximately `419 GiB` available.
- One container was running, and it was the only recorded container.
- Two unique local image identities, one Docker volume, and three Docker
  networks existed.
- One container published port `3000`; none published `1384` or `5432`.
- The required Node 24/Next.js 16.4.1 AMD64 runtime image was present as
  `node-24-slim-nextjs-16-4-1:amd64`, architecture `amd64`, image identity
  `sha256:368f4381b61bf90ad27aa5a9dd4c10e1de0b4b4666006911e1b6cb4aafcfb8a6`.
- No allowlisted Python `3.12-slim` or `3.13-slim` runtime image was present.
- No allowlisted pgvector PostgreSQL 16, 17, or 18 image was present.

## Wrapper Correction

The accepted run required blind sudo-password entry because Script `03`
redirected its attended SSH terminal while excluding prompt output from the
report. The password was not captured, and the inventory result is valid. The
wrapper was corrected after the run to attach that step directly to
`/dev/tty`, making future prompts visible while still retaining no prompt
output.

## Target-Version Boundary

EmceeDanko is Ubuntu `24.04.5`. The operator states that org-lab Tech is Ubuntu
`26`. This does not change the frozen host-source/OCI architecture, but Ubuntu
package versions and availability shall be inventoried and selected
independently on Tech. Noble package versions are not assumed to apply there.
The reusable Script `02` now accepts an expected Ubuntu major or major/minor
version and still records the exact target `VERSION_ID`.

## Disposition

Select and capture exact `linux/amd64` generic Python and
PostgreSQL/pgvector runtime images next. Do not replace or rebuild the accepted
Node/Next.js image. Port `3000` ownership must be handled explicitly before
starting the new web application; no existing container is stopped by this
inventory decision.

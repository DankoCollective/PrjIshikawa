# Application Runtime Image Capture Pass — Not Selected for Deployment

## Result

Accepted Script `04` as a technically valid `linux/amd64` runtime-image
capture. The capture reused the already cached
Python and PostgreSQL/pgvector images without registry contact, preserved the
accepted Node/Next.js image, and produced one checksum-bound Docker archive.
The operator subsequently clarified that Python and PostgreSQL/pgvector must
run natively on the host. Therefore this combined archive is historical
evidence only: it is not an installation input and shall not be transferred or
loaded.

## Evidence

- Operator report:
  `local/reports/application-runtime-images/capture_application_runtime_images_20261019T022055Z_FpH6uz.txt`
- Report SHA-256:
  `0a03fbf5f5e897b8f8bc6dd0d0b90074cd03b672bcab08acfd3aa7ffdc863867`
- Report size: `2,849` bytes and `32` lines.
- Accepted Script `04` SHA-256:
  `1940bc31fe7992aff4ff75032bdb9e7712a0170a4335752b932d0e60d9cbbf69`
- Artifact directory:
  `local/artifacts/application-runtime-images/application-runtime-images-linux-amd64-20261019T022055Z/`
- Docker archive:
  `application-runtime-images-linux-amd64.tar`
- Archive size: `378,607,104` bytes.
- Archive SHA-256:
  `44688a19b5bfdf0ab9fc274db52c434b0df82348d24aaa611de7ad4191842a52`
- `SHA256SUMS` validation: both the Docker archive and
  `runtime-image-manifest.txt` passed.
- Top-level artifact symlinks: none.

## Accepted Runtime Identities

### Node/Next.js

- Reference: `node-24-slim-nextjs-16-4-1:amd64`.
- Platform: `linux/amd64`.
- Platform image ID:
  `sha256:368f4381b61bf90ad27aa5a9dd4c10e1de0b4b4666006911e1b6cb4aafcfb8a6`.
- The platform image ID exactly matches the previously accepted EmceeDanko
  inventory.
- Archive config digest:
  `sha256:c8a9630b569f700fd14f51a1a79dff42b15517a0c7ec9f4d73226ec26f6ef393`.

### Python

- Reference: `python:3.12.15-slim-trixie`.
- Runtime version: `3.12.15`.
- Platform: `linux/amd64`.
- Platform image ID:
  `sha256:2b4f19dae3a777dfc3b76730bda1e82e1f66ab2a2686fa93ca78edbfb4f04ffe`.
- Repository digest:
  `python@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1`.
- Archive config digest:
  `sha256:df18428df8a0f9189c84e7424d214b4c50092af1f9dca5842a00c41c39bda316`.

### PostgreSQL/pgvector

- Reference: `pgvector/pgvector:0.8.7-pg17-bookworm`.
- PostgreSQL runtime: `17.11-1.pgdg12+2`.
- pgvector extension: `0.8.7`.
- Platform: `linux/amd64`.
- Platform image ID:
  `sha256:cd4ccfdaf62cbfeb5c6ee19ef0dd663406d4ed740c320b324d016a90e85385b3`.
- Repository digest:
  `pgvector/pgvector@sha256:ac08538c6f8b9904c33c8224c5e5706dbe760aca29db1d096972b4052c22a75d`.
- Archive config digest:
  `sha256:151aa1c2e849e7828ed8aef2183ae15f692cbe887d2f28921d8b44b26e154d7e`.

## Scope and Non-Actions

- The accepted run performed no registry contact because both newly selected
  images were already cached by the earlier acquisition attempt.
- No SSH, SCP, or remote-system contact occurred.
- No image was built or altered.
- No container was run, started, or stopped.
- No application source, corpus, database state, backup, or secret is in the
  archive.
- The earlier blocked Script `04` attempts produced no promoted artifact.
  Their platform-selection and identity-layer checks were corrected before
  this accepted run; they are not alternate captures.

## Disposition

Do not transfer or load this archive. The accepted Node/Next.js image already
exists on EmceeDanko. Python and PostgreSQL/pgvector now follow the native-host
path under reopened `G20` and `D23`. The archive remains in the ignored local
artifact tree until the operator explicitly decides whether to delete it.

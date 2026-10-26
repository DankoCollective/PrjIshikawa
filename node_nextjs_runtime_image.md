# Generic Node/Next Runtime Image

## Role

This record defines the application-free Linux AMD64 runtime image consumed by
Ishikawa v1.3.1. The canonical build inputs are under
`deployment/runtime-image/`; the application remains an external archive and
is never copied into the image.

## Exact identity

| Item | Value |
| --- | --- |
| Image reference | `node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64` |
| Platform | `linux/amd64` |
| Node.js | `24.22.1` |
| npm | `11.19.1` |
| Next.js | `16.4.3` |
| React | `19.2.9` |
| React DOM | `19.2.9` |
| Base | `node:24.22.1-bookworm-slim` |
| AMD64 base manifest | `sha256:2dd9a4f758e173b65fee15388f7706af6fb01ef50cf7a2c0538711d67a6981ae` |
| Work directory | `/opt/nextjs` |

The exact transitive npm graph and integrity values are in
`deployment/runtime-image/package-lock.json`. The Dockerfile, lock, advisory
disposition, license boundary, SBOM, image ID, archive checksum, and build
receipt travel with the separate runtime-image handoff.

## Image boundary

The image contains the reviewed Node/Next/React dependency layer. It contains
no Ishikawa source, application configuration, corpus, credentials, database
state, target-host state, or generated `.next` output. It has no product
entrypoint; its default command only displays Next.js help.

Build and validate the source contract with:

```bash
bash ./deployment/scripts/build-node-next-runtime.sh --validate-only
```

Build, verify, export, and publish the local handoff with:

```bash
bash ./deployment/scripts/build-node-next-runtime.sh --run
```

The run builds only Linux AMD64 and publishes
`local/artifacts/node-next-runtime-current/`. It does not contact a deployment
target or access application credentials, databases, model endpoints, or
corpus content.

## Runtime contract

The installed application stack must:

1. verify the exact image reference, AMD64 architecture, version label, image
   ID, and direct dependency versions before mutation;
2. run the container as the installing operator's numeric UID/GID;
3. mount only the external application directories and files, all read-only;
4. use a read-only container root, no new privileges, and no Linux
   capabilities;
5. provide one bounded writable tmpfs at `/opt/nextjs/.next`, with home and
   temporary subdirectories inside that same tmpfs;
6. run `next build`, require `.next/BUILD_ID` and `.next/server`, and emit
   bounded progress while the build is quiet;
7. `exec next start` in the same container and require application liveness
   and readiness; and
8. stop and remove the container so all generated build state disappears.

`next dev` is not permitted in the permanent runtime. A deliberate local
development command may use it outside this production lifecycle.

## Offline deployment

Tech verifies the checksum-bound Docker archive and identity record, then uses
`docker load`. Tech does not rebuild the image, contact a registry, or download
npm dependencies. The application archive and runtime-image archive remain
separate primary payloads; neither is nested inside the other.

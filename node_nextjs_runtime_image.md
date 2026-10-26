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
| Build-only npm | `11.21.1`, checksum-pinned, absent from runtime |
| Base-bundled npm/Yarn | Not executed; absent from runtime |
| Next.js | `16.4.3` |
| React | `19.2.9` |
| React DOM | `19.2.9` |
| Base | `node:24.22.1-bookworm-slim` |
| AMD64 base manifest | `sha256:2dd9a4f758e173b65fee15388f7706af6fb01ef50cf7a2c0538711d67a6981ae` |
| Work directory | `/opt/nextjs` |

The fixed npm build archive is pinned to SHA-256
`dd77c48eb845f4856c2cdba347cfb52bd877a2655a1ea48ff0c4796e3df9dd7b`.
The exact transitive npm graph and integrity values are in
`deployment/runtime-image/package-lock.json`. The Dockerfile, lock, advisory
disposition, license boundary, SBOM, image ID, archive checksum, and build
receipt travel with the separate runtime-image handoff.

## Image boundary

The image contains the reviewed Node/Next/React dependency layer. It contains
no Ishikawa source, application configuration, corpus, credentials, database
state, target-host state, or generated `.next` output. It has no product
entrypoint; its default command only displays Next.js help.

Validate the native-build source contract without target contact with:

```bash
bash ./deployment/scripts/07_build-node-next-runtime-on-emceedanko.sh --validate-only
```

Build natively on EmceeDanko, verify both transfer directions, and publish the
returned local handoff with:

```bash
bash ./deployment/scripts/07_build-node-next-runtime-on-emceedanko.sh --run
```

Script 07 contacts only the frozen Ubuntu 24.04 AMD64 EmceeDanko build host,
executes the unnumbered `deployment/assets/build-node-next-runtime` helper,
and publishes `local/artifacts/node-next-runtime-current/`. It transfers no
application and accesses no application credential, database, model endpoint,
or corpus content. The exact image remains loaded on EmceeDanko for v1.3.1
qualification; the private transfer directory is removed.

Allow approximately 3-10 minutes. The operator may receive one SSH-key
passphrase prompt and one EmceeDanko `sudo` password prompt. EmceeDanko must
provide native AMD64 kernel, Debian-package, and Docker architecture; Ubuntu
24.04; Docker with buildx; at least two logical CPUs, 4 GiB available memory,
1 GiB available under `/tmp`, 2 GiB build-workspace capacity, and 5 GiB Docker
storage capacity; and build-time HTTPS access to the pinned Docker Hub base
and the checksum-pinned npm archive and lock objects. The script does not need Gemma, Nomic, PostgreSQL,
application ports, application credentials, application source, or corpus
input.

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

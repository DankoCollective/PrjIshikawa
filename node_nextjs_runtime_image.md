# Node 24 and Next.js 16.4.1 Runtime Image

## Purpose

This document defines the reusable, product-neutral container image used to
develop, test, build, and run a host-resident Next.js application. It provides
the identity, runtime contract, source-mount model, verification procedure,
and adoption boundaries needed by an agent or human operator.

This is a runtime definition, not an image archive and not permission to pull,
rebuild, retag, transfer, or deploy an image. Follow
`LAB_RUN_PATH_STANDARD.md` and the repository package-capture rules for those
operations.

## Image Contract

| Property | Defined value |
|---|---|
| Repository name | `node-24-slim-nextjs-16-4-1` |
| Architecture tags | `amd64`, `arm64` |
| Platform | Linux |
| Node.js | `24.22.0` |
| Next.js | `16.4.1` |
| React | `19.2.0` |
| React DOM | `19.2.0` |
| Yarn environment | `1.22.22` |
| Working directory | `/opt/nextjs` |
| Exposed container port | `3000/tcp` |
| Entrypoint | `docker-entrypoint.sh` |
| Default command | `npm run dev` |
| Telemetry | `NEXT_TELEMETRY_DISABLED=1` |
| Application source in image | None; source is supplied by bind mounts |

Select the architecture tag explicitly. Never substitute `latest`:

```bash
architecture="$(dpkg --print-architecture)"
case "$architecture" in
  amd64|arm64) ;;
  *) printf 'unsupported architecture: %s\n' "$architecture" >&2; exit 2 ;;
esac
image="node-24-slim-nextjs-16-4-1:${architecture}"
```

## Recorded Identity and Provenance

The accepted AMD64 image has these recorded identities:

- reference: `node-24-slim-nextjs-16-4-1:amd64`;
- platform: `linux/amd64`;
- Docker image ID:
  `sha256:368f4381b61bf90ad27aa5a9dd4c10e1de0b4b4666006911e1b6cb4aafcfb8a6`;
- OCI archive config digest:
  `sha256:c8a9630b569f700fd14f51a1a79dff42b15517a0c7ec9f4d73226ec26f6ef393`.

The ARM64 tag has been exercised on the ARM64 development host, but its exact
image ID is not frozen in this shared definition. Before an ARM64 carry,
deployment, or release claim, capture its `docker image inspect` identity and
the SHA-256 of the dedicated exported archive in repository evidence.

This is a locally built image and has no authoritative registry digest. A
matching tag alone does not prove matching bytes. Verify the image ID on every
target, or transfer a dedicated checksum-bound Docker archive and verify it
before loading. A historical multi-image archive is not an accepted deployment
input for this image.

## Observed Build Content

The image follows the official Node 24 slim, Debian Bookworm lineage. Its
reviewed OCI history shows:

1. Node.js `24.22.0` and Yarn `1.22.22` from the upstream Node image process.
2. `/opt/nextjs` selected as the working directory.
3. An npm project initialized in that directory.
4. Exact installations of `next@16.4.1`, `react@19.2.0`, and
   `react-dom@19.2.0`.
5. `/opt/nextjs/node_modules/.bin` prepended to `PATH`.
6. Next.js telemetry disabled.
7. Port `3000/tcp` exposed and `npm run dev` selected as the default command.

The reviewed repositories do not retain the original Dockerfile or a dedicated
single-image build archive. This history describes the observed image; it is
not a byte-reproducible build recipe. A successor image must retain its
Dockerfile, exact base identity, lockfile, advisory record, build report,
per-platform identities, and checksum-bound exports.

The image does not declare a non-root `USER`, a Docker `HEALTHCHECK`,
application source, application configuration, or application secrets. Those
boundaries belong to the application and its launch tooling.

## Application Compatibility Contract

An application is compatible only when all of the following are true:

- it is a Next.js application compatible with Next.js `16.4.1`;
- it is compatible with React and React DOM `19.2.0` and Node.js `24.22.0`;
- it needs no npm package absent from the image's installed `node_modules`,
  unless a separately reviewed mechanism supplies that package;
- its `package.json` declares the same exact direct runtime versions;
- its scripts expose the commands required by the selected workflow, normally
  `dev`, `build`, `start`, and `test`;
- it can operate with source files bind-mounted under `/opt/nextjs`;
- it treats `.next` and other generated output as disposable container state;
- it receives configuration through named environment variables or mounted,
  validated configuration rather than environment-specific image content.

Mounting another `package.json` does not install its dependencies. If a port
requires additional packages, do not run `npm install` interactively in the
container or rely on undeclared transitive dependencies. Either change the
application to fit the frozen dependency contract or qualify a separately
named successor image through the dependency, advisory, build, and
multi-architecture gates.

Use by another application is not automatic security acceptance. Perform a
fresh affectedness review for Node.js, Next.js, React, React DOM, Yarn, the
Debian base, and the application's complete dependency graph before promotion.

## Host-Mounted Source Layout

The established model keeps source on the host and mounts only the surfaces
needed by the command:

| Host application path | Container path | Normal mode |
|---|---|---|
| `app/` | `/opt/nextjs/app` | read-only |
| `components/` | `/opt/nextjs/components` | read-only |
| `lib/` | `/opt/nextjs/lib` | read-only |
| `public/` | `/opt/nextjs/public` | read-only |
| `tests/` | `/opt/nextjs/tests` | read-only, test runs only |
| `package.json` | `/opt/nextjs/package.json` | read-only |
| `next.config.mjs` | `/opt/nextjs/next.config.mjs` | read-only |

Mount only paths the application and command need. Additional source roots
must be explicit and normally read-only. Never mount the repository root,
credentials, a home directory, the Docker socket, or unrelated host state.

The bind mounts replace image paths while leaving
`/opt/nextjs/node_modules` available. Next.js writes `.next` in the writable
container layer; removing the container removes that generated state.

## Required Preflight

Use Docker directly when the operator already has access. If attended `sudo`
is required, the operator-facing wrapper must announce the prompt first.

```bash
docker image inspect "$image" >/dev/null
image_architecture="$(docker image inspect "$image" --format '{{.Architecture}}')"
test "$image_architecture" = "$architecture"

docker run --rm --network none "$image" node -e '
const expected = {
  node: "v24.22.0",
  next: "16.4.1",
  react: "19.2.0",
  reactDom: "19.2.0",
};
const observed = {
  node: process.version,
  next: require("next/package.json").version,
  react: require("react/package.json").version,
  reactDom: require("react-dom/package.json").version,
};
if (JSON.stringify(observed) !== JSON.stringify(expected)) {
  console.error({expected, observed});
  process.exit(1);
}
console.log(observed);
'
```

Before launch, also verify the host port is free, configuration is valid,
required upstream services are ready, the mounted source is the accepted
candidate, and cleanup targets only the intended container.

## Test and Build Pattern

Tests and builds that do not need external services must disable networking.
The invoking wrapper should construct explicit read-only mounts from the table
above and run one of these commands:

```bash
docker run --rm --network none "${web_mounts[@]}" \
  "$image" node --test --test-reporter=tap

docker run --rm --network none "${web_mounts[@]}" \
  "$image" npm run build
```

`web_mounts` is illustrative shell-array notation, not literal standalone
input. A real wrapper must validate every host source path before constructing
the array. Pass required build variables by name; never pass the complete host
environment.

The build proves compilation but does not preserve `.next` after the
container exits. The established attended runtime uses `next dev`. A
production-mode `next start` workflow requires a separately tested
build-output persistence or same-container build/start design.

An attended launcher may invoke the image-provided `next dev` executable
directly when it first proves that `next --version` matches the frozen image
contract. This bypasses only npm's run-script wrapper; it does not change the
image, framework version, working directory, source mounts, generated `.next`
state, or application command. Keep any accepted rollback runtime on its
previous launch path unless that runtime is separately requalified.

When the hardened container cannot create generated `.next` state in the
image working directory, the attended launcher may mount only
`/opt/nextjs/.next` as a bounded, disposable tmpfs. Keep the application
source mounts read-only, retain `no-new-privileges` and capability removal,
and prove liveness, the home route, and required static assets before stopping
an accepted runtime. The tmpfs must disappear with the exact container and
must never contain source, credentials, database state, or retained evidence.

If exact staged source is intentionally private to the deployment account
(for example, regular files mode `0600` and directories mode `0700`), a
capability-stripped image-default root process cannot rely on discretionary
access-control bypasses to read the bind mounts. The attended launcher may run
the v1.3 web process as the numeric UID and primary GID of that deployment
account and set `HOME=/tmp`. This preserves the exact source bytes and modes,
keeps every source mount read-only, and allows only generated `.next` state in
the bounded tmpfs. Prove the exact identity and source-import behavior before
switchover; do not solve this boundary by changing candidate modes.

Where automatic rollback is promised, also start and remove a separately
named disposable container from the preserved rollback launcher, image, and
source tree on a temporary loopback port before stopping the accepted runtime.
The proof must cover liveness, readiness, the home route, required static
assets, and complete cleanup. A running old container proves current service,
not that it can be recreated after it is stopped.

## Runtime Pattern

The established attended runtime uses a unique container name, approved
networking, explicit read-only source mounts, only named environment variables,
and these Docker hardening controls:

```bash
docker run --detach --rm \
  --name "$WEB_CONTAINER" \
  --network host \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  --env "PRODUCT_DISPLAY_NAME=$PRODUCT_DISPLAY_NAME" \
  --env "BACKEND_BASE_URL=$BACKEND_BASE_URL" \
  "${web_mounts[@]}" \
  "$image" npm run dev -- --hostname "$WEB_HOST" --port "$WEB_PORT"
```

The variable names are generic examples. Each application must define and
validate its exact configuration contract. Prefer loopback binding. If host
networking is unnecessary, publish only the required loopback port. Do not
infer readiness from a running container; poll application-defined liveness
and readiness endpoints and retain bounded logs on failure.

Because the image does not set `USER`, it runs as the image default unless the
launcher supplies a user. `no-new-privileges` and capability removal are
required existing hardening, but do not substitute for a qualified non-root
design. A change to `--user`, a read-only root filesystem, tmpfs placement, or
production-mode startup must be tested as a runtime change.

## Porting and Adoption Checklist

Before declaring another application operational on this image:

1. Freeze the framework migration and source-layout decision.
2. Inventory every current runtime and development dependency.
3. Prove the image contains every retained dependency at the accepted version,
   or qualify a successor image.
4. Convert the application to a valid Next.js server/client boundary without
   moving server secrets or privileged operations into browser code.
5. Define exact scripts and configuration variables.
6. Add native unit tests, containerized JavaScript tests, a network-disabled
   build, liveness, readiness, upstream-failure, cleanup, and rerun coverage.
7. Prove the architecture tag and image identity on every build and target
   host.
8. Review current licenses and advisories for the complete dependency graph.
9. Keep boot autostart disabled until separately approved.
10. Record human UI acceptance after automated qualification passes.

The image standardizes a runtime. It does not waive application-specific
architecture, security, package, service, or acceptance decisions.

## Change Control

Any change to Node.js, Next.js, React, React DOM, the base OS, image tag,
default command, working directory, installed dependencies, architecture,
user, network model, or source-mount contract creates a new runtime candidate.
Do not mutate an accepted tag in place. Use a new unambiguous name, retain the
build definition and lock data, perform advisory and license review, qualify
every supported architecture, export dedicated checksum-bound bytes, and
promote only after repository acceptance gates pass.

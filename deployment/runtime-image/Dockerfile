# syntax=docker/dockerfile:1

# Purpose:
#   Build one reusable Linux AMD64 Node.js/Next.js runtime image without
#   embedding Ishikawa application source or generated web state.
#
# Mental model:
#   Resolve the exact production JavaScript dependency set in a temporary
#   assembly stage, remove package-manager and cache bytes, then flatten the
#   resulting filesystem into one scratch-based runtime layer. The deployed
#   application is mounted separately and creates temporary build state at
#   startup.
#
# Inputs or prerequisites:
#   The pinned Node.js base image, package.json, package-lock.json, and the
#   checksum-bound npm build-tool archive.
#
# Outputs:
#   An application-free runtime image containing Node.js, Next.js, React, and
#   the exact production dependency tree. npm, Yarn, Corepack, pnpm, source,
#   credentials, and generated application state are absent.

FROM --platform=linux/amd64 node:24.22.1-bookworm-slim@sha256:2dd9a4f758e173b65fee15388f7706af6fb01ef50cf7a2c0538711d67a6981ae AS assemble

ENV NEXT_TELEMETRY_DISABLED=1 \
    NODE_ENV=production

WORKDIR /opt/nextjs

COPY package.json package-lock.json ./
ADD --checksum=sha256:dd77c48eb845f4856c2cdba347cfb52bd877a2655a1ea48ff0c4796e3df9dd7b \
    https://registry.npmjs.org/npm/-/npm-11.21.1.tgz /tmp/npm-11.21.1.tgz

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends tzdata=2026e-0+deb12u1 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/npm-11.21.1 \
    && tar -xzf /tmp/npm-11.21.1.tgz -C /opt/npm-11.21.1 --strip-components=1 \
    && rm -rf /usr/local/lib/node_modules/npm \
      /usr/local/lib/node_modules/corepack /opt/yarn-v1.22.22 \
    && rm -f /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/yarn \
      /usr/local/bin/yarnpkg /usr/local/bin/corepack /usr/local/bin/pnpm \
      /usr/local/bin/pnpx \
    && hash -r \
    && ! command -v npm >/dev/null 2>&1 \
    && ! command -v npx >/dev/null 2>&1 \
    && ! command -v yarn >/dev/null 2>&1 \
    && ! command -v yarnpkg >/dev/null 2>&1 \
    && ! command -v corepack >/dev/null 2>&1 \
    && ! command -v pnpm >/dev/null 2>&1 \
    && ! command -v pnpx >/dev/null 2>&1 \
    && test "$(node /opt/npm-11.21.1/bin/npm-cli.js --version)" = "11.21.1" \
    && node /opt/npm-11.21.1/bin/npm-cli.js ci --omit=dev --no-audit --no-fund \
    && test -f /usr/local/LICENSE \
    && node --input-type=module -e \
      'import next from "next/package.json" with {type:"json"}; import react from "react/package.json" with {type:"json"}; import reactDom from "react-dom/package.json" with {type:"json"}; const expected={node:"v24.22.1",next:"16.4.3",react:"19.2.9",reactDom:"19.2.9"}; const actual={node:process.version,next:next.version,react:react.version,reactDom:reactDom.version}; if(JSON.stringify(actual)!==JSON.stringify(expected)){throw new Error(`runtime identity mismatch: ${JSON.stringify(actual)}`)}' \
    && node /opt/npm-11.21.1/bin/npm-cli.js cache clean --force \
    && rm -rf /root/.npm /opt/npm-11.21.1 /tmp/npm-11.21.1.tgz \
    && hash -r \
    && ! command -v npm >/dev/null 2>&1 \
    && ! command -v npx >/dev/null 2>&1 \
    && ! command -v yarn >/dev/null 2>&1 \
    && ! command -v yarnpkg >/dev/null 2>&1 \
    && ! command -v corepack >/dev/null 2>&1 \
    && ! command -v pnpm >/dev/null 2>&1 \
    && ! command -v pnpx >/dev/null 2>&1 \
    && test ! -e /usr/local/lib/node_modules/npm \
    && test ! -e /opt/npm-11.21.1 \
    && test ! -e /opt/yarn-v1.22.22

# Flatten the assembled filesystem so removed package-manager bytes are not
# retained in an inaccessible lower image layer.
FROM scratch
COPY --from=assemble / /

LABEL org.opencontainers.image.title="Node Next Runtime" \
      org.opencontainers.image.version="24.22.1-next16.4.3-react19.2.9" \
      org.opencontainers.image.description="Application-free Node.js and Next.js runtime"

ENV NEXT_TELEMETRY_DISABLED=1 \
    NODE_ENV=production

WORKDIR /opt/nextjs

EXPOSE 3000/tcp

CMD ["next", "--help"]

# syntax=docker/dockerfile:1
FROM --platform=linux/amd64 node:24.22.1-bookworm-slim@sha256:2dd9a4f758e173b65fee15388f7706af6fb01ef50cf7a2c0538711d67a6981ae

LABEL org.opencontainers.image.title="Node Next Runtime" \
      org.opencontainers.image.version="24.22.1-next16.4.3-react19.2.9" \
      org.opencontainers.image.description="Application-free Node.js and Next.js runtime"

ENV NEXT_TELEMETRY_DISABLED=1 \
    NODE_ENV=production

WORKDIR /opt/nextjs

COPY package.json package-lock.json ./

RUN npm ci --omit=dev --no-audit --no-fund \
    && test "$(npm --version)" = "11.19.1" \
    && test "$(yarn --version)" = "1.22.22" \
    && test -f /usr/local/LICENSE \
    && test -f /usr/local/lib/node_modules/npm/LICENSE \
    && test -f /opt/yarn-v1.22.22/LICENSE \
    && node --input-type=module -e \
      'import next from "next/package.json" with {type:"json"}; import react from "react/package.json" with {type:"json"}; import reactDom from "react-dom/package.json" with {type:"json"}; const expected={node:"v24.22.1",next:"16.4.3",react:"19.2.9",reactDom:"19.2.9"}; const actual={node:process.version,next:next.version,react:react.version,reactDom:reactDom.version}; if(JSON.stringify(actual)!==JSON.stringify(expected)){throw new Error(`runtime identity mismatch: ${JSON.stringify(actual)}`)}' \
    && npm cache clean --force \
    && find /root/.npm -mindepth 1 -delete

EXPOSE 3000/tcp

CMD ["next", "--help"]

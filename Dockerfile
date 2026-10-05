# syntax=docker/dockerfile:1.7
ARG NODE_IMAGE=node:22-alpine
ARG NPM_REGISTRY=https://registry.npmjs.org/

FROM ${NODE_IMAGE} AS base
WORKDIR /app

FROM base AS builder
ARG NPM_REGISTRY
RUN apk add --no-cache python3 make g++ linux-headers

COPY package.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm install --registry="${NPM_REGISTRY}" --fetch-retries=5 --fetch-retry-factor=2 --fetch-retry-mintimeout=10000 --fetch-retry-maxtimeout=120000 --fetch-timeout=300000

COPY . ./
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build
RUN node scripts/copy-standalone-assets.mjs

FROM ${NODE_IMAGE} AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=20128
ENV HOSTNAME=0.0.0.0
ENV NEXT_TELEMETRY_DISABLED=1
ENV DATA_DIR=/app/data

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/custom-server.js ./custom-server.js
COPY --from=builder /app/brand.json ./brand.json
COPY --from=builder /app/open-sse ./open-sse
COPY --from=builder /app/src/mitm ./src/mitm
COPY --from=builder /app/node_modules/node-forge ./node_modules/node-forge
COPY --from=builder /app/node_modules/next ./node_modules/next
COPY --from=builder /app/node_modules/sql.js ./node_modules/sql.js
COPY --from=builder /app/node_modules/node-machine-id ./node_modules/node-machine-id

# Unikraft: no su-exec, direct USER. chown owned files (no-op on read-only layer).
RUN mkdir -p /app/data && \
    mkdir -p /app/data-home && \
    ln -sf /app/data-home /root/.flagshiprouter 2>/dev/null || true && \
    addgroup -S node 2>/dev/null || true && \
    adduser -S node -G node 2>/dev/null || true && \
    chown -R node:node /app/data /app/data-home /app/public /app/.next /app/custom-server.js /app/brand.json /app/open-sse /app/src /app/node_modules

USER node
EXPOSE 20128
CMD ["node", "custom-server.js"]

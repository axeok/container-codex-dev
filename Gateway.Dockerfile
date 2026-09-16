# syntax=docker/dockerfile:1.7

ARG NODE_VERSION=24-bookworm-slim
ARG CODEX_GATEWAY_REVISION=8514266735669d37ccc0c9398fb3856c63e7f907

FROM node:${NODE_VERSION} AS source
ARG CODEX_GATEWAY_REVISION
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /source
COPY gateway-dockview-community.patch /tmp/gateway-dockview-community.patch
RUN git init \
    && git remote add origin https://github.com/yunhaoli24/codex-gateway.git \
    && git fetch --depth 1 origin "${CODEX_GATEWAY_REVISION}" \
    && git checkout --detach FETCH_HEAD \
    && git apply /tmp/gateway-dockview-community.patch \
    && rm -rf .git \
    && sed -i 's/defaultLocale: "zh"/defaultLocale: "en"/' nuxt.config.ts \
    && grep -q 'defaultLocale: "en"' nuxt.config.ts

FROM node:${NODE_VERSION} AS base
ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable
WORKDIR /app

FROM base AS deps
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 make g++ \
    && rm -rf /var/lib/apt/lists/*
COPY --from=source /source/package.json /source/pnpm-lock.yaml /source/pnpm-workspace.yaml /source/turbo.json ./
COPY --from=source /source/patches ./patches
COPY --from=source /source/packages ./packages
RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store \
    pnpm install --frozen-lockfile

FROM deps AS build
COPY --from=source /source/i18n ./i18n
COPY --from=source /source/components.json /source/nuxt.config.ts /source/tailwind.config.ts /source/tsconfig.json ./
COPY --from=source /source/public ./public
COPY --from=source /source/scripts ./scripts
COPY --from=source /source/shared ./shared
COPY --from=source /source/server ./server
COPY --from=source /source/app ./app
RUN pnpm exec nuxt build

FROM node:${NODE_VERSION} AS runner
ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tini \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/.output ./.output
COPY --from=build /app/scripts ./scripts
EXPOSE 3000
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "--expose-gc", "--max-old-space-size=512", ".output/server/index.mjs"]

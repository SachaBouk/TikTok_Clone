# syntax=docker/dockerfile:1
# Image du backoffice (ADR-004, ADR-015) : sortie « standalone » de Next.js, serveur Node autonome.
# Contexte : racine du monorepo.
#   docker build -f apps/backoffice/Dockerfile -t tiktok-clone-backoffice .
# Configuration à l'exécution : API_URL (l'API vue depuis le conteneur), POSTHOG_PROJECT_URL.
ARG NODE_IMAGE=node:22-alpine
ARG TURBO_VERSION=2.11.3

FROM ${NODE_IMAGE} AS base
RUN corepack enable
WORKDIR /repo

FROM base AS pruner
ARG TURBO_VERSION
RUN npm install -g turbo@${TURBO_VERSION}
COPY . .
RUN turbo prune backoffice --docker

FROM base AS builder
COPY --from=pruner /repo/out/json/ .
RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store pnpm install --frozen-lockfile --store-dir /pnpm/store
COPY --from=pruner /repo/out/full/ .
# Configuration TypeScript commune, que turbo prune ne reprend pas.
COPY tsconfig.base.json ./
ENV NEXT_TELEMETRY_DISABLED=1
# NEXT_OUTPUT=standalone : next.config.ts produit un serveur autonome (.next/standalone) avec les seules
# dépendances utilisées. `--env-mode=loose` : Turborepo transmet la variable à `next build`.
RUN NEXT_OUTPUT=standalone pnpm turbo run build --filter=backoffice --env-mode=loose

FROM ${NODE_IMAGE} AS runner
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3001 HOSTNAME=0.0.0.0
WORKDIR /repo
# Le serveur autonome reprend l'arborescence du monorepo (apps/backoffice/server.js) ; les fichiers statiques
# ne sont pas copiés par Next, on les ajoute.
COPY --from=builder /repo/apps/backoffice/.next/standalone ./
COPY --from=builder /repo/apps/backoffice/.next/static apps/backoffice/.next/static
USER node
EXPOSE 3001
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s CMD wget -qO- http://127.0.0.1:${PORT}/login >/dev/null || exit 1
CMD ["node", "apps/backoffice/server.js"]

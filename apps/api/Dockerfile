# syntax=docker/dockerfile:1
# Image de l'API (ADR-015 : tout est dockerisé, indépendant de l'hébergeur). Contexte : racine du monorepo.
#   docker build -f apps/api/Dockerfile -t tiktok-clone-api .
#   docker build -f apps/api/Dockerfile --target migrate -t tiktok-clone-api-migrate .   (prisma migrate deploy)
# Configuration par variables d'environnement (voir .env.example), jamais par un fichier .env dans l'image.
ARG NODE_IMAGE=node:22-alpine
ARG TURBO_VERSION=2.11.3

FROM ${NODE_IMAGE} AS base
RUN corepack enable
WORKDIR /repo

# Sous-ensemble du monorepo dont l'API dépend (turbo prune) : package.json et lockfile d'abord, pour que
# l'installation des dépendances reste en cache tant qu'ils ne changent pas.
FROM base AS pruner
ARG TURBO_VERSION
RUN npm install -g turbo@${TURBO_VERSION}
COPY . .
RUN turbo prune api --docker

FROM base AS builder
COPY --from=pruner /repo/out/json/ .
RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store pnpm install --frozen-lockfile --store-dir /pnpm/store
COPY --from=pruner /repo/out/full/ .
# Configuration TypeScript commune, que turbo prune ne reprend pas.
COPY tsconfig.base.json ./
# Génère le client Prisma, compile @repo/shared puis l'API.
RUN pnpm turbo run build --filter=api

# Migrations (prisma migrate deploy) : à lancer avant l'API, avec DATABASE_URL. Garde les dépendances de
# développement (CLI Prisma), absentes de l'image finale.
FROM builder AS migrate
WORKDIR /repo/apps/api
CMD ["pnpm", "exec", "prisma", "migrate", "deploy"]

FROM base AS prod-deps
COPY --from=pruner /repo/out/json/ .
RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store pnpm install --frozen-lockfile --prod --store-dir /pnpm/store

# Image finale : dépendances de production et code compilé, sans sources ni outils de build.
FROM ${NODE_IMAGE} AS runner
ENV NODE_ENV=production
WORKDIR /repo
COPY --from=prod-deps /repo ./
COPY --from=builder /repo/packages/shared/dist packages/shared/dist
COPY --from=builder /repo/apps/api/dist apps/api/dist
WORKDIR /repo/apps/api
USER node
EXPOSE 3000
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s CMD wget -qO- http://127.0.0.1:${PORT:-3000}/health >/dev/null || exit 1
CMD ["node", "dist/main.js"]

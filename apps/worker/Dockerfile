# syntax=docker/dockerfile:1
# Image du worker de transcodage (ADR-008, ADR-015). Contexte : racine du monorepo.
#   docker build -f apps/worker/Dockerfile -t tiktok-clone-worker .
# Il ne lui faut que Redis et le stockage objet (jamais PostgreSQL) ; FFmpeg est installé dans l'image.
ARG NODE_IMAGE=node:22-alpine
ARG TURBO_VERSION=2.11.3

FROM ${NODE_IMAGE} AS base
RUN corepack enable
WORKDIR /repo

FROM base AS pruner
ARG TURBO_VERSION
RUN npm install -g turbo@${TURBO_VERSION}
COPY . .
RUN turbo prune worker --docker

FROM base AS builder
COPY --from=pruner /repo/out/json/ .
RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store pnpm install --frozen-lockfile --store-dir /pnpm/store
COPY --from=pruner /repo/out/full/ .
# Configuration TypeScript commune, que turbo prune ne reprend pas.
COPY tsconfig.base.json ./
RUN pnpm turbo run build --filter=worker

FROM base AS prod-deps
COPY --from=pruner /repo/out/json/ .
RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store pnpm install --frozen-lockfile --prod --store-dir /pnpm/store

FROM ${NODE_IMAGE} AS runner
# FFmpeg et ffprobe de la distribution (H.264 libx264 et AAC compris).
RUN apk add --no-cache ffmpeg
ENV NODE_ENV=production
WORKDIR /repo
COPY --from=prod-deps /repo ./
COPY --from=builder /repo/packages/shared/dist packages/shared/dist
COPY --from=builder /repo/apps/worker/dist apps/worker/dist
WORKDIR /repo/apps/worker
# Dossiers temporaires du transcodage dans /tmp, accessible à l'utilisateur node.
USER node
CMD ["node", "dist/main.js"]

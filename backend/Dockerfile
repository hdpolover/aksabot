# ── Stage 1: Build ─────────────────────────────────────
FROM node:22-alpine AS builder

WORKDIR /app

# Install dependencies first (cache layer)
COPY package.json package-lock.json ./
RUN npm ci

# Copy source and build
COPY tsconfig.json tsconfig.build.json nest-cli.json ./
COPY src/ src/
RUN npm run build

# Prune dev dependencies
RUN npm prune --production

# ── Stage 2: Production ───────────────────────────────
FROM node:22-alpine

WORKDIR /app

# Create non-root user
RUN addgroup -S aksabot && adduser -S aksabot -G aksabot

# Copy built app + production deps from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./
COPY entrypoint.sh ./

# Own files by app user
RUN chown -R aksabot:aksabot /app

USER aksabot

EXPOSE 4280

ENTRYPOINT ["./entrypoint.sh"]
CMD ["node", "dist/main.js"]

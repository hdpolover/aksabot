# ── Stage 1: Build ─────────────────────────────────────
# node:22-slim (Debian) — required for onnxruntime-node which links against glibc.
# node:22-alpine uses musl and cannot load libonnxruntime.so.1.
FROM node:22-slim AS builder

WORKDIR /app

COPY package.json package-lock.json ./

# Skip postinstall scripts during npm ci — onnxruntime-node's postinstall downloads
# a binary from GitHub which can fail on flaky network. We run it separately with retry.
RUN npm ci --ignore-scripts

# Retry onnxruntime-node binary download up to 5 times with backoff
RUN for i in 1 2 3 4 5; do \
      node ./node_modules/onnxruntime-node/script/install.js && break; \
      echo "onnxruntime install attempt $i failed, retrying in ${i}0s..."; \
      sleep $((i * 10)); \
    done

# Run remaining postinstall scripts (sharp, etc.)
RUN npm rebuild

COPY tsconfig.json tsconfig.build.json nest-cli.json ./
COPY src/ src/
RUN npm run build

RUN npm prune --production

# ── Stage 2: Production ───────────────────────────────
FROM node:22-slim

WORKDIR /app

RUN groupadd -r aksabot && useradd -r -g aksabot aksabot

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./
COPY entrypoint.sh ./
# ONNX models for face recognition (buffalo_l — not committed, must be present at build time)
COPY models/ ./models/

RUN chown -R aksabot:aksabot /app

USER aksabot

EXPOSE 4280

ENTRYPOINT ["./entrypoint.sh"]
CMD ["node", "dist/main.js"]

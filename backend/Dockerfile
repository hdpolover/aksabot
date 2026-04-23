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

# ── Stage 2: Models ───────────────────────────────────
# Download buffalo_l ONNX models from InsightFace GitHub releases.
# Separate stage so Docker caches them — won't re-download on code changes.
FROM debian:12-slim AS models

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /models

# buffalo_l.zip (~275MB): det_10g.onnx (16MB) + w600k_r50.onnx (166MB)
RUN for i in 1 2 3 4 5; do \
      curl -fL --retry 3 --retry-delay 5 \
        "https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip" \
        -o buffalo_l.zip && break; \
      echo "Download attempt $i failed, retrying..."; sleep $((i * 10)); \
    done \
    && unzip -j buffalo_l.zip det_10g.onnx w600k_r50.onnx -d . \
    && rm buffalo_l.zip \
    && ls -lh *.onnx

# ── Stage 3: Production ───────────────────────────────
FROM node:22-slim

WORKDIR /app

RUN groupadd -r aksabot && useradd -r -g aksabot aksabot \
    && apt-get update && apt-get install -y --no-install-recommends wget \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./
COPY entrypoint.sh ./
COPY --from=models /models/det_10g.onnx  ./models/buffalo_l/det_10g.onnx
COPY --from=models /models/w600k_r50.onnx ./models/buffalo_l/w600k_r50.onnx

RUN chown -R aksabot:aksabot /app

USER aksabot

EXPOSE 4280

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD wget -qO- http://localhost:4280/ || exit 1

ENTRYPOINT ["./entrypoint.sh"]
CMD ["node", "dist/main.js"]

#!/bin/sh
set -e

# Decode Google Cloud service account JSON from base64 env var
if [ -n "$GCLOUD_SA_BASE64" ]; then
  echo "$GCLOUD_SA_BASE64" | base64 -d > /tmp/gcloud-sa.json
  echo "[entrypoint] Google Cloud credentials written to /tmp/gcloud-sa.json"
fi

exec "$@"

#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:?VERSION is required}"
COMPOSE_FILE="${COMPOSE_FILE:-compose.yaml}"

for command in docker cosign; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "required command not found: $command" >&2
    exit 1
  fi
done

verified_ref="$(VERSION="$VERSION" PULL=1 bash scripts/verify-release.sh | tail -n1)"
if [[ ! "$verified_ref" =~ ^ghcr\.io/ploos-as/glowing-bear@sha256:[0-9a-f]{64}$ ]]; then
  echo "verification did not return an immutable Glowing Bear image ref" >&2
  exit 1
fi

export GLOWING_BEAR_IMAGE="$verified_ref"

echo "Deploying verified image with Compose: $GLOWING_BEAR_IMAGE"
docker compose -f "$COMPOSE_FILE" config >/dev/null
docker compose -f "$COMPOSE_FILE" up -d --no-build

echo "Verified Compose deployment started: $GLOWING_BEAR_IMAGE"

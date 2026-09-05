#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:?VERSION is required}"
OUTPUT="${OUTPUT:-glowing-bear.verified.container}"
TEMPLATE="${TEMPLATE:-quadlet/glowing-bear.container}"

for command in docker cosign; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "required command not found: $command" >&2
    exit 1
  fi
done

verified_ref="$(VERSION="$VERSION" PULL=0 bash scripts/verify-release.sh | tail -n1)"
if [[ ! "$verified_ref" =~ ^ghcr\.io/ploos-as/glowing-bear@sha256:[0-9a-f]{64}$ ]]; then
  echo "verification did not return an immutable Glowing Bear image ref" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Quadlet template not found: $TEMPLATE" >&2
  exit 1
fi

awk -v image="$verified_ref" '
  /^Image=/ { print "Image=" image; next }
  { print }
' "$TEMPLATE" > "$OUTPUT"

if ! grep -Eq '^Image=ghcr\.io/ploos-as/glowing-bear@sha256:[0-9a-f]{64}$' "$OUTPUT"; then
  echo "rendered Quadlet does not contain the verified immutable image ref" >&2
  exit 1
fi

echo "Rendered verified Quadlet: $OUTPUT"
echo "Immutable image: $verified_ref"

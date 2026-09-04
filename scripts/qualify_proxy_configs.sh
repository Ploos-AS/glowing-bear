#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "Validating Compose files"
docker compose -f deploy/caddy/compose.yaml config >/dev/null
docker compose -f deploy/nginx/compose.yaml config >/dev/null

echo "Validating Caddy configuration"
docker run --rm \
  -e SITE_ADDRESS=localhost \
  -e WEECHAT_RELAY_UPSTREAM=127.0.0.1:9001 \
  -v "$repo_root/deploy/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
  caddy:2.10-alpine \
  caddy validate --config /etc/caddy/Caddyfile

echo "Validating nginx configuration"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$tmpdir/privkey.pem" \
  -out "$tmpdir/fullchain.pem" \
  -days 1 \
  -subj '/CN=localhost' >/dev/null 2>&1

docker run --rm \
  --add-host glowing-bear:127.0.0.1 \
  --add-host host.docker.internal:127.0.0.1 \
  -v "$repo_root/deploy/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
  -v "$tmpdir:/etc/nginx/certs:ro" \
  nginx:1.27-alpine \
  nginx -t

echo "M0.4 reverse proxy configuration qualification passed"

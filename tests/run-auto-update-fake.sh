#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

project_dir="$tmp_dir/project"
mkdir -p "$project_dir/custom" "$project_dir/data"

cat > "$project_dir/docker-compose.yml" <<'YAML'
services:
  uptime-kuma:
    image: louislam/uptime-kuma:2
    volumes:
      - ./custom/favicon.ico:/app/custom/favicon.ico:ro
      - ./custom/patch-favicon.sh:/app/custom/patch-favicon.sh:ro
    entrypoint: ["/usr/bin/dumb-init", "--", "/bin/sh", "/app/custom/patch-favicon.sh"]
    command: ["node", "server/server.js"]
YAML

printf 'fake ico\n' > "$project_dir/custom/favicon.ico"
printf '#!/bin/sh\n' > "$project_dir/custom/patch-favicon.sh"
printf 'fake data\n' > "$project_dir/data/kuma.db"

export FAKE_DOCKER_STATE="$tmp_dir/docker-state"
export FAKE_DOCKER_LOG="$tmp_dir/docker.log"
printf 'old\n' > "$FAKE_DOCKER_STATE"
touch "$FAKE_DOCKER_LOG"
chmod +x "$repo_root/tests/fake-bin/docker"

PATH="$repo_root/tests/fake-bin:$PATH" \
PROJECT_DIR="$project_dir" \
BACKUP_ROOT="$project_dir/backups/auto-update" \
BACKUP_DATA_DIR=1 \
BACKUP_SQL=1 \
DB_SERVICE=db \
BACKUP_RETENTION_DAYS=-1 \
LOCK_DIR="$tmp_dir/update.lock" \
STARTUP_WAIT_SECONDS=0 \
sh "$repo_root/auto-update/uptime-kuma-auto-update.sh"

grep -q 'docker compose pull uptime-kuma' "$FAKE_DOCKER_LOG"
grep -q 'docker compose up -d uptime-kuma' "$FAKE_DOCKER_LOG"
grep -q 'docker compose exec -T uptime-kuma' "$FAKE_DOCKER_LOG"

backup_count="$(find "$project_dir/backups/auto-update" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
test "$backup_count" = "1"

test -f "$project_dir/backups/auto-update"/*/docker-compose.yml
test -f "$project_dir/backups/auto-update"/*/custom/favicon.ico
test -f "$project_dir/backups/auto-update"/*/data/kuma.db
grep -q 'fake mariadb dump' "$project_dir/backups/auto-update"/*/database.sql

echo "fake auto-update test passed"

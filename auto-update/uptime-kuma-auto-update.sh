#!/bin/sh
set -eu

PROJECT_DIR="${PROJECT_DIR:-/www/server/uptime-kuma}"
KUMA_SERVICE="${KUMA_SERVICE:-uptime-kuma}"
KUMA_IMAGE="${KUMA_IMAGE:-louislam/uptime-kuma:latest}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
COMPOSE_COMMAND="${COMPOSE_COMMAND:-docker compose}"
BACKUP_ROOT="${BACKUP_ROOT:-$PROJECT_DIR/backups/auto-update}"
BACKUP_DATA_DIR="${BACKUP_DATA_DIR:-0}"
DATA_DIR="${DATA_DIR:-data}"
BACKUP_SQL="${BACKUP_SQL:-0}"
DB_DUMP_COMMAND="${DB_DUMP_COMMAND:-}"
STARTUP_WAIT_SECONDS="${STARTUP_WAIT_SECONDS:-15}"
LOG_TAIL="${LOG_TAIL:-200}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
AUTO_ROLLBACK="${AUTO_ROLLBACK:-1}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-}"
WEBHOOK_URL="${WEBHOOK_URL:-}"
LOCK_DIR="${LOCK_DIR:-/tmp/uptime-kuma-auto-update.lock}"
FORCE_UPDATE="${FORCE_UPDATE:-0}"
DRY_RUN=0

usage() {
    cat <<'EOF'
Usage: uptime-kuma-auto-update.sh [options]

Options:
  --dry-run              Print the resolved workflow without touching Docker.
  --force                Recreate the Kuma container even if the image id did not change.
  --project-dir PATH     Override PROJECT_DIR.
  --service NAME         Override KUMA_SERVICE.
  --image IMAGE          Override KUMA_IMAGE.
  -h, --help             Show this help.

Configuration is usually supplied by /etc/uptime-kuma-auto-update.env through
the systemd unit, or by exporting environment variables before running.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --force)
            FORCE_UPDATE=1
            ;;
        --project-dir)
            shift
            PROJECT_DIR="${1:?missing value for --project-dir}"
            ;;
        --service)
            shift
            KUMA_SERVICE="${1:?missing value for --service}"
            ;;
        --image)
            shift
            KUMA_IMAGE="${1:?missing value for --image}"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

notify() {
    status="$1"
    message="$2"

    [ -n "$WEBHOOK_URL" ] || return 0

    if [ "$DRY_RUN" = "1" ]; then
        log "dry-run: would notify $status: $message"
        return 0
    fi

    command -v curl >/dev/null 2>&1 || return 0

    escaped_message=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')
    curl -fsS -m 10 \
        -H 'Content-Type: application/json' \
        -d "{\"status\":\"$status\",\"message\":\"$escaped_message\"}" \
        "$WEBHOOK_URL" >/dev/null 2>&1 || true
}

die() {
    log "ERROR: $*"
    notify "failure" "$*"
    exit 1
}

run_compose() {
    if [ "$DRY_RUN" = "1" ]; then
        log "dry-run: $COMPOSE_COMMAND $*"
        return 0
    fi

    # shellcheck disable=SC2086
    $COMPOSE_COMMAND "$@"
}

compose_capture() {
    # shellcheck disable=SC2086
    $COMPOSE_COMMAND "$@"
}

docker_capture() {
    "$DOCKER_BIN" "$@"
}

running_container_image_id() {
    container_id=$(compose_capture ps -q "$KUMA_SERVICE" 2>/dev/null | head -n 1 || true)
    [ -n "$container_id" ] || return 0

    docker_capture inspect --format '{{.Image}}' "$container_id" 2>/dev/null || true
}

safe_mkdir_lock() {
    if [ "$DRY_RUN" = "1" ]; then
        log "dry-run: would acquire lock $LOCK_DIR"
        return 0
    fi

    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        die "another update run is already active: $LOCK_DIR"
    fi

    trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM
}

print_dry_run_plan() {
    log "dry-run configuration:"
    log "  PROJECT_DIR=$PROJECT_DIR"
    log "  KUMA_SERVICE=$KUMA_SERVICE"
    log "  KUMA_IMAGE=$KUMA_IMAGE"
    log "  BACKUP_ROOT=$BACKUP_ROOT"
    log "  BACKUP_DATA_DIR=$BACKUP_DATA_DIR"
    log "  BACKUP_SQL=$BACKUP_SQL"
    log "  AUTO_ROLLBACK=$AUTO_ROLLBACK"
    log "workflow:"
    log "  inspect current image id"
    log "  pull $KUMA_SERVICE"
    log "  compare $KUMA_IMAGE image id"
    log "  create backup only when an update is detected or --force is used"
    log "  run docker compose up -d $KUMA_SERVICE"
    log "  verify running service, patch markers, logs, and optional healthcheck"
}

preflight() {
    [ -d "$PROJECT_DIR" ] || die "project directory not found: $PROJECT_DIR"
    cd "$PROJECT_DIR"

    command -v "$DOCKER_BIN" >/dev/null 2>&1 || die "docker command not found: $DOCKER_BIN"
    docker_capture version >/dev/null 2>&1 || die "docker is not available"

    compose_config=$(compose_capture config 2>/dev/null) || die "docker compose config failed"

    printf '%s\n' "$compose_config" | grep -Fq "$KUMA_SERVICE" || die "compose service not found: $KUMA_SERVICE"
    printf '%s\n' "$compose_config" | grep -Fq "image: $KUMA_IMAGE" || die "compose config does not use expected image: $KUMA_IMAGE"
    printf '%s\n' "$compose_config" | grep -Fq 'patch-favicon.sh' || die "compose config does not include patch-favicon.sh mount or entrypoint"
    printf '%s\n' "$compose_config" | grep -Fq 'favicon.ico' || die "compose config does not include favicon.ico mount"

    [ -f custom/favicon.ico ] || die "missing custom/favicon.ico"
    [ -f custom/patch-favicon.sh ] || die "missing custom/patch-favicon.sh"
}

image_id() {
    docker_capture image inspect --format '{{.Id}}' "$KUMA_IMAGE" 2>/dev/null || true
}

primary_compose_file() {
    for file in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        if [ -f "$file" ]; then
            printf '%s\n' "$file"
            return 0
        fi
    done

    return 1
}

backup_project() {
    stamp="$1"
    backup_dir="$BACKUP_ROOT/$stamp"

    mkdir -p "$backup_dir"

    copied_compose=0
    for file in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        if [ -f "$file" ]; then
            cp -a "$file" "$backup_dir/"
            copied_compose=1
        fi
    done

    [ "$copied_compose" = "1" ] || die "no compose file found to back up"

    if [ -d custom ]; then
        cp -a custom "$backup_dir/custom"
    fi

    if [ "$BACKUP_DATA_DIR" = "1" ]; then
        [ -d "$DATA_DIR" ] || die "BACKUP_DATA_DIR=1 but data directory not found: $DATA_DIR"
        cp -a "$DATA_DIR" "$backup_dir/data"
    fi

    if [ "$BACKUP_SQL" = "1" ]; then
        [ -n "$DB_DUMP_COMMAND" ] || die "BACKUP_SQL=1 but DB_DUMP_COMMAND is empty"
        sh -c "$DB_DUMP_COMMAND" > "$backup_dir/database.sql"
    fi

    printf '%s\n' "$backup_dir"
}

prune_backups() {
    [ "$BACKUP_RETENTION_DAYS" -ge 0 ] 2>/dev/null || return 0
    [ -d "$BACKUP_ROOT" ] || return 0

    case "$BACKUP_ROOT" in
        ""|"/"|"$PROJECT_DIR")
            log "skip backup pruning because BACKUP_ROOT is not specific enough: $BACKUP_ROOT"
            return 0
            ;;
    esac

    case "$BACKUP_ROOT" in
        */backups|*/backups/*|*/backup|*/backup/*|/var/backups/*)
            ;;
        *)
            log "skip backup pruning because BACKUP_ROOT is outside an obvious backup directory: $BACKUP_ROOT"
            return 0
            ;;
    esac

    find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +"$BACKUP_RETENTION_DAYS" -exec rm -rf {} +
}

write_rollback_override() {
    backup_dir="$1"
    rollback_image="$2"
    override_file="$backup_dir/rollback.compose.yml"

    cat > "$override_file" <<EOF
services:
  $KUMA_SERVICE:
    image: $rollback_image
EOF

    printf '%s\n' "$override_file"
}

rollback_to_previous_image() {
    rollback_image="$1"
    backup_dir="$2"

    [ "$AUTO_ROLLBACK" = "1" ] || return 1
    [ -n "$rollback_image" ] || return 1
    [ -n "$backup_dir" ] || return 1

    compose_file=$(primary_compose_file || true)
    [ -n "$compose_file" ] || return 1

    override_file=$(write_rollback_override "$backup_dir" "$rollback_image")
    log "rolling back $KUMA_SERVICE with $override_file"

    # shellcheck disable=SC2086
    $COMPOSE_COMMAND -f "$compose_file" -f "$override_file" up -d "$KUMA_SERVICE"
}

verify_update() {
    sleep "$STARTUP_WAIT_SECONDS"

    running_services=$(compose_capture ps --status running --services 2>/dev/null || true)
    printf '%s\n' "$running_services" | grep -Fxq "$KUMA_SERVICE" || return 1

    logs=$(compose_capture logs --no-color --tail="$LOG_TAIL" "$KUMA_SERVICE" 2>/dev/null || true)
    if printf '%s\n' "$logs" | grep -Eq 'Unable to patch|status_page\.js favicon renderer|status-page manifest icon'; then
        printf '%s\n' "$logs" >&2
        return 1
    fi

    verify_cmd='grep -q "Codex favicon render patch START" /app/server/model/status_page.js && grep -q "Codex favicon manifest patch START" /app/server/routers/status-page-router.js && grep -q "status-favicon-lock" /app/dist/index.html'
    compose_capture exec -T "$KUMA_SERVICE" sh -lc "$verify_cmd" >/dev/null 2>&1 || return 1

    if [ -n "$HEALTHCHECK_URL" ]; then
        command -v curl >/dev/null 2>&1 || return 1
        curl -fsS -m 15 "$HEALTHCHECK_URL" >/dev/null || return 1
    fi
}

main() {
    if [ "$DRY_RUN" = "1" ]; then
        print_dry_run_plan
        exit 0
    fi

    safe_mkdir_lock
    preflight

    stamp=$(date '+%Y-%m-%d-%H%M%S')
    before_id=$(image_id)
    rollback_source_id="$before_id"
    if [ -z "$rollback_source_id" ]; then
        rollback_source_id=$(running_container_image_id)
    fi
    rollback_image=""

    log "pulling image for $KUMA_SERVICE"
    run_compose pull "$KUMA_SERVICE"

    after_id=$(image_id)
    if [ "$FORCE_UPDATE" != "1" ] && [ -n "$before_id" ] && [ "$before_id" = "$after_id" ]; then
        log "no new image for $KUMA_IMAGE"
        notify "noop" "No new Uptime Kuma image for $KUMA_IMAGE"
        prune_backups
        exit 0
    fi

    if [ -n "$rollback_source_id" ]; then
        rollback_image="uptime-kuma-auto-update-rollback:$stamp"
        docker_capture tag "$rollback_source_id" "$rollback_image"
    fi

    backup_dir=$(backup_project "$stamp")
    log "backup written to $backup_dir"

    log "recreating $KUMA_SERVICE"
    run_compose up -d "$KUMA_SERVICE"

    if verify_update; then
        log "update verified"
        notify "success" "Uptime Kuma update verified for $KUMA_IMAGE"
        prune_backups
        exit 0
    fi

    log "update verification failed"
    if rollback_to_previous_image "$rollback_image" "$backup_dir"; then
        notify "failure" "Uptime Kuma update failed; rolled back to $rollback_image"
        die "update failed; rollback command was executed"
    fi

    die "update failed and automatic rollback was not available"
}

main "$@"

# Automatic updates

The auto updater is intentionally conservative:

- It tracks the configured Docker image, defaulting to `louislam/uptime-kuma:latest`.
- It runs `docker compose pull uptime-kuma`.
- It recreates the Kuma container only when the pulled image id changed, unless `--force` is used.
- It backs up Compose files and `custom/` before recreating the container.
- It verifies the container is running and that the favicon patch markers were injected.
- If verification fails, it tries to roll back to the previous local image tag.

## Install

Copy the files to the server:

```bash
sudo install -m 0755 auto-update/uptime-kuma-auto-update.sh /usr/local/sbin/uptime-kuma-auto-update.sh
sudo install -m 0644 auto-update/uptime-kuma-auto-update.service /etc/systemd/system/uptime-kuma-auto-update.service
sudo install -m 0644 auto-update/uptime-kuma-auto-update.timer /etc/systemd/system/uptime-kuma-auto-update.timer
sudo install -m 0600 auto-update/uptime-kuma-auto-update.env.example /etc/uptime-kuma-auto-update.env
```

Edit `/etc/uptime-kuma-auto-update.env`:

```bash
sudoedit /etc/uptime-kuma-auto-update.env
```

For the current Compose layout, the important values are usually:

```env
PROJECT_DIR=/www/server/uptime-kuma
KUMA_SERVICE=uptime-kuma
KUMA_IMAGE=louislam/uptime-kuma:latest
BACKUP_ROOT=/www/server/uptime-kuma/backups/auto-update
BACKUP_DATA_DIR=0
BACKUP_SQL=0
AUTO_ROLLBACK=1
```

If Kuma uses SQLite in `./data`, set:

```env
BACKUP_DATA_DIR=1
DATA_DIR=data
```

If Kuma uses MariaDB / MySQL, keep `BACKUP_DATA_DIR=0` and configure a database dump command instead. Keep the env file mode `0600` if it contains a password.

```env
BACKUP_SQL=1
DB_DUMP_COMMAND='docker compose exec -T uptime-kuma-db mariadb-dump -u <user> -p<password> <database>'
```

## Test before enabling the timer

Run a local dry run first. It prints the workflow without touching Docker:

```bash
sudo /usr/local/sbin/uptime-kuma-auto-update.sh --dry-run
```

Then run one real update check manually:

```bash
sudo systemctl daemon-reload
sudo systemctl start uptime-kuma-auto-update.service
sudo journalctl -u uptime-kuma-auto-update.service -n 120 --no-pager
```

If there is no new image, the log should say `no new image`. If there is a new image, the log should show backup, recreate, and `update verified`.

## Enable weekly checks

```bash
sudo systemctl enable --now uptime-kuma-auto-update.timer
systemctl list-timers uptime-kuma-auto-update.timer
```

The timer runs weekly on Sunday around 04:20 with a randomized 30 minute delay.

## Manual force run

Use `--force` only when you want to recreate the Kuma container even if the image id did not change:

```bash
sudo /usr/local/sbin/uptime-kuma-auto-update.sh --force
```

## What counts as success

After an update, the script checks:

- `docker compose ps --status running --services` contains the Kuma service.
- Kuma logs do not contain the patch failure messages.
- The running container contains `Codex favicon render patch START`.
- The running container contains `Codex favicon manifest patch START`.
- `/app/dist/index.html` contains `status-favicon-lock`.
- `HEALTHCHECK_URL` returns success, if configured.

## Failure behavior

If Uptime Kuma changes its internal files and `patch-favicon.sh` can no longer patch them, verification fails. With `AUTO_ROLLBACK=1`, the updater tags the old local image before pulling, writes a temporary `rollback.compose.yml` into the backup directory, and starts Kuma with that previous image.

The rollback keeps the service available, but it is still a signal that `patch-favicon.sh` needs to be adjusted for the new Uptime Kuma version.

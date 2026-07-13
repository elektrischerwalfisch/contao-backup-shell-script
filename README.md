# Contao Backup Shell Script

Contao file + database backups for shared hosting with retention cleanup, error notifications, and optional PHP trigger execution; can be automated with a cronjob.

Developed for shared hosting, tested on all-inkl and IONOS.

> **Key characteristic**
> This tool runs fully server-side and independently from Contao internals.
> It does not require a Contao extension, theme integration, or admin access.
> It also works on shared hosting without SSH by using the PHP trigger.

---

## Quickstart

1. Clone the repository (or upload the project files) and open the project folder.
2. Create `scripts/.env-contao-backup` from `scripts/env-contao-backup.example`.
   - Ensure file permissions allow writing the file during setup, then set it to 600 for secure read/write access by the owner only.
3. Edit `scripts/.env-contao-backup` and set at least:
   - `PROJECT_ROOT`
   - `BACKUP_FOLDER`
   - email settings (`SMTP_*`, `EMAIL_FROM`, `EMAIL_TO`) if notifications are required
4. Run one test backup and check log output.
   - With SSH: run `scripts/contao-backup.sh`.
   - Without SSH: execute `trigger/contao-backup.php` via URL.
   - In both cases, verify the result in `backup.log`.
5. Review [Trigger Security](#trigger-security-current-limitations-and-todo) before exposing the trigger via URL.
6. Automate via cron (shell cron if SSH is available, otherwise URL cron via trigger).

---

## Project Structure

```text
contao-backup-shell-script/
├── README.md
├── scripts/
│   ├── contao-backup.sh
│   └── env-contao-backup.example
└── trigger/
    └── contao-backup.php
```

- `scripts/` must not be publicly reachable via web.
- `trigger/` may be web-reachable for URL-based cron.

---

## Core Configuration

Main variables in `scripts/.env-contao-backup`:

- `PROJECT_ROOT`: absolute path to Contao project root
- `BACKUP_FOLDER`: absolute path where backups are stored
- `MAX_BACKUPS`: number of backup folders to keep
- `EXCLUDES`: space-separated paths to exclude from file archive (default: `var/cache var/log vendor node_modules`)
- `CONTAO_VERSION`: `"5"` for Contao 5.x (default) or `"4"` for Contao 4.x
- `DATABASE_CONFIG_FILE`: Contao 4.x database config path (default: `config/parameters.yml`)
- `ENABLE_COMPRESSION`: `1` for compressed output (`files.tar.gz` + `contao-database-YYYY-MM-DD.sql.gz`), `0` for uncompressed output
- `USE_NICE_FOR_TAR`: apply `nice` for tar command (`1` or `0`)
- `SEND_EMAIL_ON_ERROR`: `1` or `0`
- `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`
- `EMAIL_FROM`, `EMAIL_TO`, `EMAIL_SUBJECT_DEFAULT`

Database credentials are read automatically:

- **Contao 5.x**: from `.env.local` (`DATABASE_URL`)
- **Contao 4.x**: from `config/parameters.yml`, `.yaml`, or `.php`

Security note:

- `.env-contao-backup` contains credentials. Keep permissions at `600`.
- Database credentials in `DATABASE_URL` must not contain URL-encoding special characters (`@`, `:`, `/`, `%`, etc.).

---

## PHP Trigger

`trigger/contao-backup.php` is useful when SSH execution is not available.

Config options in the file:

- `$shellScriptPath`: default `../scripts/contao-backup.sh`
- `$executionMode`:
  - `sync`: waits for completion (works well on all-inkl)
  - `background`: starts detached process (recommended on IONOS for large backups)
- `$debugMode`:
  - `false` (default): minimal HTTP output
  - `true`: verbose HTTP output for troubleshooting

By default, the trigger returns minimal HTTP messages only. Full diagnostics are written to `BACKUP_FOLDER/backup.log`.

---

## Trigger Security (Current Limitations and TODO)

Static `.htaccess` IP allowlists for shared-hosting cronjobs are unreliable because cronjob source IPs can change.

Current policy:

- keep trigger exposure minimal
- keep `$debugMode = false` in production (minimal HTTP responses only)
- use `backup.log` for diagnostics, not the HTTP response body
- monitor access via logs
- do not treat static IP allowlists as primary protection

TODO:

- implement a stable trigger authentication mechanism that does not rely on fixed source IPs
- document the final approach in this README

---

## Minimal Troubleshooting

- **No DB backup generated**
  - Contao 5.x: check `.env.local` and `DATABASE_URL`
  - Contao 4.x: check `CONTAO_VERSION="4"` and `DATABASE_CONFIG_FILE`
  - Check `backup.log` + `mysqldump` error output
- **Mail not sent**
  - Verify `SMTP_*` values
  - Confirm `curl` or `sendmail` availability
- **Permission errors**
  - Ensure read/write access to `PROJECT_ROOT` and `BACKUP_FOLDER`
  - Keep `.env-contao-backup` at permissions `600`
  - Never expose `scripts/` via web URL
- **Backups too large**
  - Use `EXCLUDES` for cache, logs, vendor, and other non-essential folders
- **Timeouts on shared hosting**
  - Set `$executionMode = 'background'` in the PHP trigger
  - Consider `ENABLE_COMPRESSION=0` and `USE_NICE_FOR_TAR=1`
- **Trigger returns only `Error` with no details**
  - Check `BACKUP_FOLDER/backup.log` for the full error log
  - If you need more detail in the HTTP response (e.g. without log access), set `$debugMode = true` in `trigger/contao-backup.php` temporarily
  - Set `$debugMode` back to `false` when done (required for production/cron)

---

## License

MIT License.

# Contao Backup Shell Script

## Overview
This script automates Contao backup creation by:
1. Creating a compressed tar archive of the Contao project files (excluding cache, logs, vendor, etc.).
2. Creating a compressed MySQL database backup.
3. Managing backup retention with automatic cleanup.
4. Sending email alerts in case of errors.

Perfect for developers and sysadmins who want a simple, configurable, and efficient way to back up Contao sites (supports both Contao 4.x and 5.x).

**Developed for**: Shared hosting environments  
**Tested on**: all-inkl.com, IONOS (other shared hosting providers may work but are untested)

---

## File Structure

```
contao-backup-shell-script/
├── README.md                    # This file
├── LICENSE                      # MIT License
├── .gitignore                   # Git ignore rules
├── scripts/                     # Shell script directory (not publicly accessible)
│   ├── contao-backup.sh        # Main backup script
│   └── env-contao-backup.example # Configuration template
└── trigger/                     # PHP trigger directory (publicly accessible via URL)
    ├── contao-backup.php       # PHP trigger script
    └── .htaccess.example       # Access restrictions template (IP-based)
```

### Directory Purpose

- **`scripts/`**: Contains the main shell script and configuration files. This directory should **not** be publicly accessible via web URL to protect the backup script and sensitive configuration.
- **`trigger/`**: Contains PHP scripts that can be called via URL to execute the backup script. This directory is publicly accessible but should be protected via `.htaccess` to restrict access to authorized IP addresses (e.g., the cronjob server IP).

---

## Features
- **File Backup**: Automatically creates a compressed tar archive of the Contao project files.
- **Smart Exclusions**: Automatically excludes cache, logs, vendor, and node_modules folders.
- **Database Dump**: Creates a compressed MySQL database dump (`.sql.gz`).
- **Multi-Version Support**: Supports both Contao 4.x (parameters.yaml/php) and Contao 5.x (.env.local) configuration files.
- **Retention Policy**: Keeps a fixed number of backups (`MAX_BACKUPS`), deleting old backups automatically.
- **Logging**: Logs all processes (successes and errors) to a log file.
- **Email Notifications**: Sends error reports in case of failures.

---

## Requirements
1. **Tools Needed**:
   - `mysqldump`: To create MySQL database dumps.
   - `tar` and `gzip`: For creating compressed file archives.
   - `curl`: For SMTP email notifications (recommended for shared hosting).
   - `sendmail`: Optional fallback for email notifications.
2. **Permissions**: The user running the script must have read/write access to the directories.
3. **Contao Version**: Supports Contao 4.x and Contao 5.x.

---

## Installation and Setup

1. Clone the repository or download the files:
   ```bash
   git clone https://github.com/your-repo/contao-backup-shell-script.git
   cd contao-backup-shell-script
   ```

2. Configure the backup settings:
   The script uses an external configuration file `.env-contao-backup` in the `scripts/` directory.
   
   **Option A**: Copy the example file and edit it:
   ```bash
   cp scripts/env-contao-backup.example scripts/.env-contao-backup
   nano scripts/.env-contao-backup
   ```
   
   **Option B**: On first run, the script will automatically create this file with placeholder values. Edit it:
   ```bash
   nano scripts/.env-contao-backup
   ```
   
   **Important variables to configure:**
   - `PROJECT_ROOT`: Path to your Contao project root (use absolute paths!)
   - `BACKUP_FOLDER`: Path to store backups (use absolute paths!)
   - `CONTAO_VERSION`: Set to `"4"` for Contao 4.x or `"5"` for Contao 5.x (default: `"5"`)
   - Email settings: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `EMAIL_FROM`, `EMAIL_TO`
   
   For a complete list of all configuration variables, see the [Configuration Variables](#configuration-variables) section below.

3. Make the script executable:
   ```bash
   chmod +x scripts/contao-backup.sh
   ```

4. Test the script:
   
   **Option A: Direct execution via Terminal (if SSH access is available)**
   ```bash
   ./scripts/contao-backup.sh
   ```
   Check the `backup.log` file in the backup folder for results.
   
   **Option B: Execution via PHP trigger (if no SSH access)**
   - The shell script can be executed via the PHP trigger script (`trigger/contao-backup.php`)
   - The PHP script will automatically set execute permissions and run the backup script
   - **Important**: Only expose the `trigger/` directory via URL, never the `scripts/` directory
   - Example URL: `https://yourdomain.com/cronjobs/contao-backup-shell-script/trigger/contao-backup.php`
   - Access the URL via browser or configure it as a URL-based cronjob in your hosting panel
   - **Configuration**: Edit `trigger/contao-backup.php` to configure:
     - Script path (default: `../scripts/contao-backup.sh`)
     - Execution mode: `'sync'` (default, for all-inkl) or `'background'` (for IONOS to avoid timeouts)

5. Secure the PHP trigger (recommended):
   
   To protect the PHP trigger script from unauthorized access, add a `.htaccess` file in the `trigger/` directory that restricts access to specific IP addresses (e.g., the IP of your cronjob server):
   
   **Option A**: Copy the example file and edit it:
   ```bash
   cp trigger/.htaccess.example trigger/.htaccess
   nano trigger/.htaccess
   ```
   
   **Option B**: Create the file manually with the following content:
   ```apache
   # Block all access by default
   Order Deny,Allow
   Deny from all
   
   # Allow access only for specific IPs (replace with your actual cronjob server IP)
   # Example: Allow from 85.13.130.203
   Allow from YOUR_CRONJOB_SERVER_IP
   ```
   
   **Note**: For Apache 2.4+, use `Require` syntax instead:
   ```apache
   # Require ip YOUR_CRONJOB_SERVER_IP
   # Example: Require ip 85.13.130.203
   Require ip YOUR_CRONJOB_SERVER_IP
   ```
   
   **Important**: Replace `YOUR_CRONJOB_SERVER_IP` with the actual IP address of your cronjob server. You can find this IP in your hosting panel's cronjob settings or by checking the server logs.

6. (Optional) Add a cronjob for automation:
   
   **Option A: Shell-based cronjob (if SSH access is available)**
   ```bash
   crontab -e
   ```
   Add the following line to schedule backups (e.g., daily at midnight):
   ```
   0 0 * * * /full/path/to/scripts/contao-backup.sh
   ```
   
   **Option B: URL-based cronjob (via hosting panel)**
   - Configure a URL-based cronjob in your hosting panel
   - **Important**: Use only the `trigger/` directory URL, never the `scripts/` directory
   - Example: `https://yourdomain.com/cronjobs/contao-backup-shell-script/trigger/contao-backup.php`
   - The `.htaccess` file will protect the trigger from unauthorized access

---

## Configuration Variables

All configuration is done via the `.env-contao-backup` file in the `scripts/` directory. The script will automatically create this file with placeholder values on first run if it doesn't exist.

| **Variable**        | **Description**                                                                 |
|----------------------|---------------------------------------------------------------------------------|
| `PROJECT_ROOT`      | Path to the Contao project root on your server (e.g., `/var/www/html/contao`). Use absolute paths! |
| `BACKUP_FOLDER`     | Path to the folder where backups will be stored. Use absolute paths! |
| `LOG_FILE`          | Optional: Path to the log file. Defaults to `$BACKUP_FOLDER/backup.log` if not specified. |
| `MAX_BACKUPS`       | Maximum number of backups to keep (older backups will be deleted automatically). Default: 8 |
| `EXCLUDES`          | Space-separated list of paths to exclude from the tar archive (relative to PROJECT_ROOT). Default: `var/cache var/log vendor node_modules` |
| `CONTAO_VERSION`    | Contao version: `"4"` for Contao 4.x or `"5"` for Contao 5.x. Default: `"5"` (Contao 5.x) |
| `DATABASE_CONFIG_FILE` | Database configuration file path for Contao 4.x (only used if `CONTAO_VERSION="4"`). Can be relative to `PROJECT_ROOT` or absolute path. Default: `"config/parameters.yml"` |
| `ENABLE_COMPRESSION` | Set to `1` to enable compression (default, recommended for all-inkl.com) or `0` to disable (recommended for IONOS to avoid timeout issues). Default: `1` |
| `USE_NICE_FOR_TAR`  | Set to `1` to use `nice` for tar command (reduces priority, helps on IONOS) or `0` to disable. Default: `0` |
| `SEND_EMAIL_ON_ERROR`| Set to `1` to enable email notifications on errors. Default: 1 |
| `EMAIL_SUBJECT_DEFAULT`| Subject line for error notification emails. |
| `SMTP_HOST`         | SMTP server hostname (e.g., `mail.yourdomain.tld`). |
| `SMTP_PORT`         | SMTP server port (typically `587` for STARTTLS or `465` for implicit TLS). |
| `SMTP_USER`         | SMTP username for authentication. |
| `SMTP_PASS`         | SMTP password for authentication. |
| `EMAIL_FROM`        | Email address to send notifications from. |
| `EMAIL_TO`          | Email address to send error reports to when the backup fails. |

**Security Note**: The `.env-contao-backup` file contains sensitive credentials and should be excluded from version control via `.gitignore`. Keep the file permissions set to `600` (read/write for owner only).

---

## PHP Trigger Script Configuration

The PHP trigger script (`trigger/contao-backup.php`) can be configured to work in different environments. Edit the configuration section at the top of the file:

### Configuration Options

| **Option** | **Description** | **Default** |
|------------|-----------------|-------------|
| `$shellScriptPath` | Path to the shell script (relative to PHP file). Change if your script is in a different location. | `../scripts/contao-backup.sh` |
| `$executionMode` | Execution mode: `'sync'` (waits for completion) or `'background'` (runs in background). | `'sync'` |

### Recommended Configurations

**For all-inkl.com:**
```php
$executionMode = 'sync'; // Wait for completion, get full output
```

**For IONOS:**
```php
$executionMode = 'background'; // Run in background to avoid timeout issues
```

### Execution Modes

- **`'sync'`** (Synchronous): 
  - Waits for script completion
  - Returns full output
  - Works well on all-inkl.com
  - May timeout on IONOS for large backups

- **`'background'`** (Background):
  - Runs script in background (detached from PHP process)
  - Returns PID immediately
  - Recommended for IONOS to avoid timeout issues
  - Check `BACKUP_FOLDER/backup.log` for progress
  - Falls back to sync mode if background execution fails

---

## Script Workflow

### Step-by-Step Actions
1. Create a timestamped backup folder inside `BACKUP_FOLDER`.
2. Create a compressed tar archive of the Contao project files (`files.tar.gz`):
   - Automatically excludes cache, logs, vendor, and node_modules folders (configurable via `EXCLUDES`).
3. Create a compressed MySQL dump (`contao-database-YYYY-MM-DD.sql.gz`):
   - Automatically detects Contao version (4.x or 5.x).
   - Extracts credentials from Contao configuration files:
     - **Contao 5.x**: `.env.local` (DATABASE_URL format)
     - **Contao 4.x**: `config/parameters.yaml` or `config/parameters.php`
4. Maintain up to `MAX_BACKUPS` by deleting the oldest backups.
5. Log all actions and errors into `backup.log`.
6. If the backup fails:
   - Log the specific error(s).
   - Send an email with a summary of the issues.

---

## Contao Version Support

The script supports both Contao 4.x and 5.x. By default, it assumes Contao 5.x. You can explicitly specify the version using the `CONTAO_VERSION` variable in `.env-contao-backup`.

### Contao 5.x (Default)
- **Default behavior**: If `CONTAO_VERSION` is not set, the script defaults to Contao 5.x
- **Configuration file**: `.env.local` in the project root
- **Database credentials**: Extracted from the `DATABASE_URL` environment variable:
  ```
  DATABASE_URL=mysql://user:password@host:port/database
  ```
- **Important**: Database credentials must NOT contain special characters that require URL encoding (such as `@`, `:`, `/`, `%`, `#`, `&`, `+`, etc.). Use only alphanumeric characters, underscores, and hyphens.

### Contao 4.x
- **Configuration**: Set `CONTAO_VERSION="4"` in `.env-contao-backup`
- **Database config file**: 
  - **Default**: `config/parameters.yml` (if `DATABASE_CONFIG_FILE` is not specified)
  - **Custom**: Set `DATABASE_CONFIG_FILE` to specify a different path (relative to `PROJECT_ROOT` or absolute path)
- **Supported formats**:
  - `config/parameters.yml`: YAML format
  - `config/parameters.yaml`: YAML format
  - `config/parameters.php`: PHP array format
- **Example configuration**:
  ```bash
  CONTAO_VERSION="4"
  DATABASE_CONFIG_FILE="config/parameters.yml"  # Optional, defaults to this
  ```

---

## Example Log Output

A successful backup will generate log entries like this:
```plaintext
2025-08-29 15:30:01 - Starting backup for 2025-08-29...
2025-08-29 15:30:01 - Project root: /path/to/contao
2025-08-29 15:30:01 - Backup target folder: /path/to/backups/2025-08-29
2025-08-29 15:30:15 - Database credentials loaded from: /path/to/contao/.env.local
2025-08-29 15:30:20 - Project files successfully backed up: /path/to/backups/2025-08-29/files.tar.gz (Size: 150M)
2025-08-29 15:30:25 - Database successfully backed up: /path/to/backups/2025-08-29/contao-database-2025-08-29.sql.gz (Size: 5M)
2025-08-29 15:30:30 - Deleted oldest backup: 2025-08-20 to maintain a maximum of 8 backups.
2025-08-29 15:30:35 - Backup completed successfully for 2025-08-29.
```

If errors occur, the corresponding log entries will include:
```plaintext
2025-08-29 15:30:15 - ERROR: Contao database backup FAILED!
```

Additionally, in case of errors, an email will be sent to the configured email address.

Here's an example email:

**Subject**:  
`Contao Backup Error Report for www.mywebsite.de`

**Body**:
```plaintext
The backup of your Contao-Website failed with the following error(s):

Host: server.example.com
Timestamp: 2025-08-29

Errors in this run:

2025-08-29 15:30:15 - ERROR: Contao database backup FAILED!

Please investigate the issue for resolution.
```

---

## Troubleshooting

### Common Issues & Fixes

1. **Empty or Incorrect Database Credentials**
   - **Contao 5.x**: Ensure `.env.local` exists in the project root and contains a valid `DATABASE_URL`:
     ```
     DATABASE_URL=mysql://user:password@host:port/database
     ```
     - **Important**: Database credentials must NOT contain special characters that require URL encoding.
   - **Contao 4.x**: Ensure `config/parameters.yaml` or `config/parameters.php` exists and contains database configuration:
     - YAML format: `database_user: username`
     - PHP format: `'database_user' => 'username'`
   - Check file permissions: The script must be able to read the configuration files.

2. **Cannot Send Emails**
   - **Primary method (recommended)**: Configure SMTP settings in `.env-contao-backup`:
     - Set `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, and `SMTP_PASS`
     - This method works on all shared hosting providers (all-inkl.com, IONOS, etc.)
     - Uses `curl` for SMTP communication (supports STARTTLS on port 587)
   - **Fallback method**: If SMTP is not configured, the script will try to use `sendmail`:
     ```bash
     sudo apt install sendmail
     ```
   - Ensure your server is properly configured to send emails.

3. **Permission Errors**
   - Ensure the user running the script has read/write permissions for `PROJECT_ROOT` and `BACKUP_FOLDER`.
   - If you don't have SSH access, use the PHP trigger file (`trigger/contao-backup.php`) which will set execute permissions automatically.
   - The config file `.env-contao-backup` should have permissions `600` (read/write for owner only).
   - **Security**: Never expose the `scripts/` directory via web URL. Only the `trigger/` directory should be accessible via URL, and it should be protected with `.htaccess` to restrict access to authorized IP addresses.

4. **Backup File Too Large**
   - Adjust the `EXCLUDES` variable in `.env-contao-backup` to exclude more folders:
     ```
     EXCLUDES="var/cache var/log vendor node_modules public/bundles"
     ```
   - Common folders to exclude: `var/cache`, `var/log`, `vendor`, `node_modules`, `public/bundles`

5. **Contao Version Not Detected**
   - Ensure the `PROJECT_ROOT` path points to the Contao project root (where `composer.json` is located).
   - For Contao 5.x: Check that `.env.local` exists in the project root.
   - For Contao 4.x: Check that `config/parameters.yaml` or `config/parameters.php` exists.

---

## License

This project is licensed under the **MIT License**. You are free to use, modify, and redistribute the code, but no warranty is provided for its functionality or suitability for specific purposes.


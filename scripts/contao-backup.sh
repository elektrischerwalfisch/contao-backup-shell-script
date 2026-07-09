#!/bin/bash

# ============================================================================
# Contao Backup Shell Script (Universal)
# ============================================================================
# Script Name:    contao-backup.sh
# Version:        0.1.0
# Description:    Automates the backup of Contao (4.x and 5.x) project files 
#                 and database with logging and error reporting.
# Developed for:  Shared hosting environments
# Tested on:      all-inkl.com, IONOS (other shared hosting providers may 
#                 work but are untested)
# Author:         elektrischerwalfisch
# Author URL:     https://www.elektrischerwalfisch.de/
# License:        MIT License
# ============================================================================
#
# IMPORTANT: Database Credential Requirements
# This script automatically extracts database credentials from Contao configuration files.
# For the script to work correctly, database credentials must NOT contain special characters
# that require URL encoding (such as @, :, /, %, #, &, +, etc.).
# Use only alphanumeric characters, underscores, and hyphens in:
# - Database username
# - Database password  
# - Database hostname
# - Database name

# Load configuration from external file
# This allows keeping project-specific paths and credentials out of version control
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.env-contao-backup"

# Load config file if it exists
if [ -f "$CONFIG_FILE" ]; then
  # Source the config file (this will set all variables)
  if ! source "$CONFIG_FILE"; then
    echo "ERROR: Failed to load configuration file: $CONFIG_FILE" >&2
    exit 1
  fi
else
  # Auto-generate config file with all variables if it doesn't exist
  cat > "$CONFIG_FILE" <<'EOF'
# Contao Backup Configuration File
# This file contains project-specific settings and should NOT be committed to version control.
# Keep this file secure (chmod 600) and update the values below.

# Contao and backup paths (use absolute paths!)
PROJECT_ROOT="/path/to/contao"
BACKUP_FOLDER="/path/to/contao-backups"
# LOG_FILE will be set automatically to $BACKUP_FOLDER/backup.log if not specified
# You can override it with an absolute path if needed
# LOG_FILE="/custom/path/to/backup.log"
MAX_BACKUPS=8                         # Maximum number of backups to keep

# Excluded files/folders for the file archive (relative to PROJECT_ROOT)
# Modify this list to adjust which paths are excluded from the tar archive
# Note: This is a space-separated list in the config file
EXCLUDES="var/cache var/log vendor node_modules"

# Contao version (default: "5" for Contao 5.x)
# Set to "4" for Contao 4.x or "5" for Contao 5.x
# If not specified, defaults to "5" (Contao 5.x)
# CONTAO_VERSION="5"

# Database configuration file path for Contao 4.x (optional)
# Only used if CONTAO_VERSION is set to "4"
# Can be relative to PROJECT_ROOT or absolute path
# Default: "config/parameters.yml" (if not specified)
# Examples:
# DATABASE_CONFIG_FILE="config/parameters.yml"
# DATABASE_CONFIG_FILE="/absolute/path/to/config/parameters.yml"
# DATABASE_CONFIG_FILE="config/parameters.yaml"
# DATABASE_CONFIG_FILE="config/parameters.php"

# Compression settings (for IONOS and other hosts with timeout issues, set to 0)
# 1 = enabled (default, recommended for all-inkl.com)
# 0 = disabled (recommended for IONOS to avoid timeout issues)
ENABLE_COMPRESSION=1

# Use nice for tar command (reduces priority, helps on IONOS)
# 1 = enabled (recommended for IONOS)
# 0 = disabled (default)
USE_NICE_FOR_TAR=0

# Email notification settings
SEND_EMAIL_ON_ERROR=1                 # Set to 1 to enable email notification on errors
EMAIL_SUBJECT_DEFAULT="Contao Backup Error Report for www.mywebsite.de"

# SMTP settings for shared hosting
SMTP_HOST="mail.yourdomain.tld"
SMTP_PORT="587"
SMTP_USER="backup@yourdomain.tld"
SMTP_PASS="your_password"

# Email addresses
EMAIL_FROM="backup@yourdomain.tld"
EMAIL_TO="info@yourdomain.tld"
EOF
  chmod 600 "$CONFIG_FILE" 2>/dev/null || true
  echo "WARNING: Configuration file $CONFIG_FILE was missing and has been created with placeholder values." >&2
  echo "Please edit $CONFIG_FILE and update all paths and credentials before running the backup." >&2
fi

# Set default values (used if config file doesn't define a variable)
PROJECT_ROOT="${PROJECT_ROOT:-/path/to/contao}"
BACKUP_FOLDER="${BACKUP_FOLDER:-/path/to/contao-backups}"
MAX_BACKUPS="${MAX_BACKUPS:-8}"
SEND_EMAIL_ON_ERROR="${SEND_EMAIL_ON_ERROR:-1}"
EMAIL_SUBJECT_DEFAULT="${EMAIL_SUBJECT_DEFAULT:-Contao Backup Error Report}"

# Excludes (default: same as in config template)
# If EXCLUDES is not set in config file, default excludes will be used
# If EXCLUDES is set to empty string (EXCLUDES="") in config, no excludes will be used
EXCLUDES="${EXCLUDES:-var/cache var/log vendor node_modules}"

# Compression settings (default: enabled for all-inkl compatibility)
ENABLE_COMPRESSION="${ENABLE_COMPRESSION:-1}"
USE_NICE_FOR_TAR="${USE_NICE_FOR_TAR:-0}"

# Contao version and database config (default: Contao 5)
CONTAO_VERSION="${CONTAO_VERSION:-5}"
# For Contao 4.x, set default database config file if not specified
if [ "$CONTAO_VERSION" = "4" ] && [ -z "$DATABASE_CONFIG_FILE" ]; then
  DATABASE_CONFIG_FILE="config/parameters.yml"
fi
DATABASE_CONFIG_FILE="${DATABASE_CONFIG_FILE:-}"

# Set LOG_FILE after BACKUP_FOLDER is loaded (expand variables if needed)
LOG_FILE="${LOG_FILE:-$BACKUP_FOLDER/backup.log}"

# Load email settings early (needed for error handling)
EMAIL_TO="${EMAIL_TO:-info@mydomain.de}"
EMAIL_SUBJECT_DEFAULT="${EMAIL_SUBJECT_DEFAULT:-Contao Backup Error Report}"
EMAIL_SUBJECT="${EMAIL_SUBJECT:-$EMAIL_SUBJECT_DEFAULT}"
EMAIL_FROM="${EMAIL_FROM:-backup@mydomain.de}"

# SMTP settings (with defaults)
SMTP_HOST="${SMTP_HOST:-mail.yourdomain.tld}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-backup@mydomain.de}"
SMTP_PASS="${SMTP_PASS:-your_password}"

# Initialize error tracking early (before validation)
TIMESTAMP=$(date +"%Y-%m-%d")
RUN_ERROR_FILE="/tmp/backup_errors_$$.log"
SENDMAIL_BIN="$(command -v sendmail || true)"

# Parse EXCLUDES from config (space-separated string to array)
# EXCLUDES already has default value set above (if not set in config)
# Convert to array (will be empty array if EXCLUDES is empty string)
if [ -n "$EXCLUDES" ]; then
  EXCLUDES_ARRAY=($EXCLUDES)
else
  EXCLUDES_ARRAY=()
fi

# Simple early error handler (works before LOG_FILE is available)
early_error_exit() {
  local error_msg="$1"
  local now_ts="$(date +'%Y-%m-%d %H:%M:%S')"
  
  # Output error
  echo "ERROR: $error_msg" >&2
  
  # Try to send email if enabled
  if [ "$SEND_EMAIL_ON_ERROR" -eq 1 ]; then
    EMAIL_BODY_FILE="/tmp/backup_error_email_early.txt"
    echo "To: $EMAIL_TO" > "$EMAIL_BODY_FILE"
    echo "From: $EMAIL_FROM" >> "$EMAIL_BODY_FILE"
    echo "Subject: $EMAIL_SUBJECT" >> "$EMAIL_BODY_FILE"
    echo "" >> "$EMAIL_BODY_FILE"
    echo "The backup of your Contao-Website failed with the following error:" >> "$EMAIL_BODY_FILE"
    echo "" >> "$EMAIL_BODY_FILE"
    echo "Host: $(hostname)" >> "$EMAIL_BODY_FILE"
    echo "Timestamp: $now_ts" >> "$EMAIL_BODY_FILE"
    echo "" >> "$EMAIL_BODY_FILE"
    echo "Error: $error_msg" >> "$EMAIL_BODY_FILE"
    echo "" >> "$EMAIL_BODY_FILE"
    echo "Please investigate the issue for resolution." >> "$EMAIL_BODY_FILE"
    
    # Try SMTP via curl
    if command -v curl >/dev/null 2>&1 && [ -n "$SMTP_HOST" ] && [ -n "$SMTP_USER" ] && [ -n "$SMTP_PASS" ] && [ "$SMTP_HOST" != "mail.yourdomain.tld" ]; then
      local smtp_msg_file="/tmp/backup_error_smtp_early.txt"
      local body_content=$(grep -A 1000 "^$" "$EMAIL_BODY_FILE" | tail -n +2)
      printf "Subject: $EMAIL_SUBJECT\r\nFrom: $EMAIL_FROM\r\nTo: $EMAIL_TO\r\n\r\n$body_content\r\n" > "$smtp_msg_file"
      curl -s --url "smtp://$SMTP_HOST:$SMTP_PORT" --ssl-reqd \
        --mail-from "$EMAIL_FROM" \
        --mail-rcpt "$EMAIL_TO" \
        --user "$SMTP_USER:$SMTP_PASS" \
        --upload-file "$smtp_msg_file" >/dev/null 2>&1
      rm -f "$smtp_msg_file"
    elif [ -n "$SENDMAIL_BIN" ] && [ -x "$SENDMAIL_BIN" ]; then
      "$SENDMAIL_BIN" -t -i -f "$EMAIL_FROM" < "$EMAIL_BODY_FILE" >/dev/null 2>&1
    fi
    rm -f "$EMAIL_BODY_FILE"
  fi
  
  exit 1
}

# Validate that critical variables are set (not using placeholder values)
if [ "$PROJECT_ROOT" = "/path/to/contao" ] || [ -z "$PROJECT_ROOT" ]; then
  early_error_exit "PROJECT_ROOT is not configured. Please set it in: $CONFIG_FILE"
fi

if [ "$BACKUP_FOLDER" = "/path/to/contao-backups" ] || [ -z "$BACKUP_FOLDER" ]; then
  early_error_exit "BACKUP_FOLDER is not configured. Please set it in: $CONFIG_FILE"
fi

# Validate that paths are absolute (start with /)
if [ "${PROJECT_ROOT#/}" = "$PROJECT_ROOT" ]; then
  early_error_exit "PROJECT_ROOT must be an absolute path (starting with /), got: $PROJECT_ROOT"
fi

if [ "${BACKUP_FOLDER#/}" = "$BACKUP_FOLDER" ]; then
  early_error_exit "BACKUP_FOLDER must be an absolute path (starting with /), got: $BACKUP_FOLDER"
fi

# Validate critical paths exist
if [ ! -d "$PROJECT_ROOT" ]; then
  early_error_exit "Contao project folder does not exist: $PROJECT_ROOT"
fi

# Database backup settings (using mysqldump like WordPress script)
# Will be extracted from Contao configuration after functions are defined

# Define logging function (used throughout the script)
log_message() {
  local message="$1"
  local now_ts="$(date +'%Y-%m-%d %H:%M:%S')"
  
  # If running interactively (terminal), also output to terminal
  if [ -t 1 ]; then
    echo "$now_ts - $message"
  fi
  
  # Ensure log directory exists before writing
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || {
    echo "ERROR: Cannot create log directory: $(dirname "$LOG_FILE")" >&2
    return 1
  }
  
  # Write to main log file
  echo "$now_ts - $message" >> "$LOG_FILE" 2>/dev/null || {
    echo "ERROR: Cannot write to log file: $LOG_FILE" >&2
  }
  
  # If this is an ERROR line, also record it in the per-run error file
  if [[ "$message" == ERROR:* ]] && [ -n "$RUN_ERROR_FILE" ]; then
    echo "$now_ts - $message" >> "$RUN_ERROR_FILE"
  fi
}

# Function to send an email in case of error
send_email_if_error() {
  if [ "$SEND_EMAIL_ON_ERROR" -eq 1 ]; then
    EMAIL_BODY_FILE="/tmp/backup_error_email.txt"

    # Write the required email content (for sendmail/SMTP)
    echo "To: $EMAIL_TO" > "$EMAIL_BODY_FILE"
    echo "From: $EMAIL_FROM" >> "$EMAIL_BODY_FILE"
    echo "Subject: $EMAIL_SUBJECT" >> "$EMAIL_BODY_FILE"
    echo "" >> "$EMAIL_BODY_FILE"  # Empty line separates headers from the body
    echo "The backup of your Contao-Website failed with the following error(s):" >> "$EMAIL_BODY_FILE"
    echo "" >> "$EMAIL_BODY_FILE"

    # Add short context (without sensitive paths)
    echo "Host: $(hostname)" >> "$EMAIL_BODY_FILE"
    echo "Timestamp: $TIMESTAMP" >> "$EMAIL_BODY_FILE"
    echo "" >> "$EMAIL_BODY_FILE"
    echo "Errors in this run:" >> "$EMAIL_BODY_FILE"
    echo "" >> "$EMAIL_BODY_FILE"

    # Append only this run's ERROR messages if available; otherwise, fall back to last 20 ERRORs from log
    if [ -n "$RUN_ERROR_FILE" ] && [ -s "$RUN_ERROR_FILE" ]; then
      cat "$RUN_ERROR_FILE" >> "$EMAIL_BODY_FILE"
    else
      grep "ERROR:" "$LOG_FILE" 2>/dev/null | tail -n 20 >> "$EMAIL_BODY_FILE"
    fi
    echo "" >> "$EMAIL_BODY_FILE"
    echo "Please investigate the issue for resolution." >> "$EMAIL_BODY_FILE"

    # Try SMTP via curl first (works on all-inkl), then sendmail
    if command -v curl >/dev/null 2>&1 && [ -n "$SMTP_HOST" ] && [ -n "$SMTP_USER" ] && [ -n "$SMTP_PASS" ] && [ "$SMTP_HOST" != "mail.yourdomain.tld" ]; then
      log_message "Attempting to send error email via SMTP (curl)..."
      # Create message file for curl (strip headers from body for SMTP)
      local smtp_msg_file="/tmp/backup_error_smtp.txt"
      local body_content=$(grep -A 1000 "^$" "$EMAIL_BODY_FILE" | tail -n +2)
      printf "Subject: $EMAIL_SUBJECT\r\nFrom: $EMAIL_FROM\r\nTo: $EMAIL_TO\r\n\r\n$body_content\r\n" > "$smtp_msg_file"
      
      curl -s --url "smtp://$SMTP_HOST:$SMTP_PORT" --ssl-reqd \
        --mail-from "$EMAIL_FROM" \
        --mail-rcpt "$EMAIL_TO" \
        --user "$SMTP_USER:$SMTP_PASS" \
        --upload-file "$smtp_msg_file" >/dev/null 2>&1
      SEND_STATUS=$?
      rm -f "$smtp_msg_file"
      
      if [ $SEND_STATUS -ne 0 ]; then
        log_message "ERROR: SMTP (curl) failed with status $SEND_STATUS"
      else
        log_message "Sent error email via SMTP (curl)."
      fi
    elif [ -n "$SENDMAIL_BIN" ] && [ -x "$SENDMAIL_BIN" ]; then
      log_message "SMTP not configured; attempting to send error email via sendmail..."
      "$SENDMAIL_BIN" -t -i -f "$EMAIL_FROM" < "$EMAIL_BODY_FILE"
      SEND_STATUS=$?
      if [ $SEND_STATUS -ne 0 ]; then
        log_message "ERROR: sendmail failed with status $SEND_STATUS"
      else
        log_message "Sent error email via sendmail."
      fi
    else
      log_message "ERROR: No available method to send error email (SMTP not configured and sendmail missing)."
    fi

    # Clean up temporary email body file
    rm -f "$EMAIL_BODY_FILE"
  fi
}

# Extract database credentials from Contao configuration
# Support both Contao 4.x (config/parameters.*) and Contao 5.x (.env*)
# Uses CONTAO_VERSION variable (default: "5") and optional DATABASE_CONFIG_FILE for Contao 4.x

CONFIG_FILE=""
DB_HOST=""
DB_NAME=""
DB_USER=""
DB_PASS=""

# Use CONTAO_VERSION (default: "5")
if [ "$CONTAO_VERSION" = "5" ]; then
    # Contao 5.x - use .env.local
    if [ -f "$PROJECT_ROOT/.env.local" ]; then
      CONFIG_FILE="$PROJECT_ROOT/.env.local"
      DATABASE_URL=$(grep -E "^DATABASE_URL=" "$CONFIG_FILE" | sed 's/DATABASE_URL=//')
      
      if [ -n "$DATABASE_URL" ]; then
        # Parse DATABASE_URL format: mysql://user:password@host:port/database
        # IMPORTANT: Database credentials must NOT contain special characters that require URL encoding
        # (such as @, :, /, %, etc.). Use only alphanumeric characters, underscores, and hyphens.
        DB_USER=$(echo "$DATABASE_URL" | sed 's/mysql:\/\/\([^:]*\):.*/\1/')
        DB_PASS=$(echo "$DATABASE_URL" | sed 's/mysql:\/\/\([^:]*\):\([^@]*\)@.*/\2/')
        DB_HOST=$(echo "$DATABASE_URL" | sed 's/mysql:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([^\/]*\)\/.*/\3/')
        DB_NAME=$(echo "$DATABASE_URL" | sed 's/mysql:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([^\/]*\)\/\([^?]*\).*/\5/')
      fi
    fi
  elif [ "$CONTAO_VERSION" = "4" ]; then
    # Contao 4.x - use DATABASE_CONFIG_FILE (defaults to "config/parameters.yml" if not specified)
    # Resolve database config file path: if relative, make it relative to PROJECT_ROOT; if absolute, use as-is
    if [ "${DATABASE_CONFIG_FILE#/}" = "$DATABASE_CONFIG_FILE" ]; then
      # Relative path
      CONFIG_FILE="$PROJECT_ROOT/$DATABASE_CONFIG_FILE"
    else
      # Absolute path
      CONFIG_FILE="$DATABASE_CONFIG_FILE"
    fi
    
    if [ -f "$CONFIG_FILE" ]; then
      # Extract credentials based on file type
      if [[ "$CONFIG_FILE" == *.yml ]] || [[ "$CONFIG_FILE" == *.yaml ]]; then
        # YAML format - support both flat and nested structures
        DB_HOST=$(grep -E "^\s*database_host:" "$CONFIG_FILE" | head -n 1 | sed 's/.*database_host:\s*//' | sed "s/^['\"]//" | sed "s/['\"]$//" | tr -d ' ')
        DB_NAME=$(grep -E "^\s*database_name:" "$CONFIG_FILE" | head -n 1 | sed 's/.*database_name:\s*//' | sed "s/^['\"]//" | sed "s/['\"]$//" | tr -d ' ')
        DB_USER=$(grep -E "^\s*database_user:" "$CONFIG_FILE" | head -n 1 | sed 's/.*database_user:\s*//' | sed "s/^['\"]//" | sed "s/['\"]$//" | tr -d ' ')
        DB_PASS=$(grep -E "^\s*database_password:" "$CONFIG_FILE" | head -n 1 | sed 's/.*database_password:\s*//' | sed "s/^['\"]//" | sed "s/['\"]$//" | tr -d ' ')
      elif [[ "$CONFIG_FILE" == *.php ]]; then
        # PHP format
        DB_HOST=$(grep -E "'database_host'" "$CONFIG_FILE" | sed "s/.*'database_host'\s*=>\s*'\([^']*\)'.*/\1/")
        DB_NAME=$(grep -E "'database_name'" "$CONFIG_FILE" | sed "s/.*'database_name'\s*=>\s*'\([^']*\)'.*/\1/")
        DB_USER=$(grep -E "'database_user'" "$CONFIG_FILE" | sed "s/.*'database_user'\s*=>\s*'\([^']*\)'.*/\1/")
        DB_PASS=$(grep -E "'database_password'" "$CONFIG_FILE" | sed "s/.*'database_password'\s*=>\s*'\([^']*\)'.*/\1/")
      fi
    fi
  fi

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  # Validate that we got the credentials
  if [ -z "$DB_HOST" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ]; then
    log_message "ERROR: Could not extract database credentials from $CONFIG_FILE"
    send_email_if_error
    exit 1
  fi
  
  # Log which method was used
  log_message "Using Contao version: $CONTAO_VERSION"
  if [ "$CONTAO_VERSION" = "4" ]; then
    log_message "Using database config file: $DATABASE_CONFIG_FILE"
  fi
  
  log_message "Database credentials loaded from: $CONFIG_FILE"
  log_message "Database connection configured successfully"
else
  log_message "ERROR: No Contao configuration file found."
  if [ "$CONTAO_VERSION" = "5" ]; then
    log_message "  Tried: $PROJECT_ROOT/.env.local (Contao 5.x)"
  elif [ "$CONTAO_VERSION" = "4" ]; then
    if [ "${DATABASE_CONFIG_FILE#/}" = "$DATABASE_CONFIG_FILE" ]; then
      # Relative path
      log_message "  Tried: $PROJECT_ROOT/$DATABASE_CONFIG_FILE (Contao 4.x)"
    else
      # Absolute path
      log_message "  Tried: $DATABASE_CONFIG_FILE (Contao 4.x)"
    fi
  fi
  send_email_if_error
  exit 1
fi

# Create target backup folder
BACKUP_TARGET="$BACKUP_FOLDER/$TIMESTAMP"
mkdir -p "$BACKUP_TARGET" || { 
  log_message "ERROR: Failed to create backup folder: $BACKUP_TARGET"; 
  send_email_if_error; 
  exit 1; 
}

# Start logging
log_message "Starting backup for $TIMESTAMP..."
log_message "Project root: $PROJECT_ROOT"
log_message "Backup target folder: $BACKUP_TARGET"
log_message "Compression: $([ "$ENABLE_COMPRESSION" -eq 1 ] && echo 'enabled' || echo 'disabled')"

# Log basic environment info (without sensitive details)
log_message "Backup environment initialized"

# Step 1: Create tar archive of the project files (with excludes)
# Determine archive filename based on compression setting
if [ "$ENABLE_COMPRESSION" -eq 1 ]; then
  FILES_ARCHIVE="$BACKUP_TARGET/files.tar.gz"
  TAR_COMPRESS_FLAG="z"
else
  FILES_ARCHIVE="$BACKUP_TARGET/files.tar"
  TAR_COMPRESS_FLAG=""
fi

# Build tar exclude flags from EXCLUDES_ARRAY
TAR_EXCLUDES=""
for path in "${EXCLUDES_ARRAY[@]}"; do
  TAR_EXCLUDES+=" --exclude=${path}"
done

log_message "Starting file backup (this may take a while for large projects)..."
log_message "Archive target: $FILES_ARCHIVE"
log_message "Excluding paths: ${EXCLUDES_ARRAY[*]}"

# Change working directory to PROJECT_ROOT to avoid path issues (better for IONOS)
cd "$PROJECT_ROOT" || {
  log_message "ERROR: Cannot change to project root: $PROJECT_ROOT"
  send_email_if_error
  exit 1
}

log_message "Changed to project root: $PROJECT_ROOT"
log_message "Starting tar command..."

# Build tar command with optional nice and compression
TAR_CMD="tar"
if [ "$USE_NICE_FOR_TAR" -eq 1 ] && command -v nice >/dev/null 2>&1; then
  TAR_CMD="nice -n 19 tar"
  log_message "Using nice for tar command (reduced priority)"
fi

# Create tar archive with appropriate compression
log_message "Creating tar archive..."
TAR_OUTPUT=$($TAR_CMD -c${TAR_COMPRESS_FLAG}f "$FILES_ARCHIVE" $TAR_EXCLUDES --warning=no-file-ignored . 2>&1)
TAR_EXIT_CODE=$?

if [ $TAR_EXIT_CODE -eq 0 ]; then
  log_message "Tar archive created successfully."
else
  log_message "Tar command failed with exit code: $TAR_EXIT_CODE"
  if [ -n "$TAR_OUTPUT" ]; then
    log_message "Tar error output: $TAR_OUTPUT"
  fi
fi

# Return to script directory
cd "$SCRIPT_DIR" || true

if [ $TAR_EXIT_CODE -eq 0 ]; then
  # Verify the archive was created and is not empty
  if [ ! -f "$FILES_ARCHIVE" ]; then
    log_message "ERROR: Archive file was not created: $FILES_ARCHIVE"
    send_email_if_error
    exit 1
  fi
  
  # Get file size using stat (more reliable in shared hosting)
  FILES_SIZE_BYTES=$(stat -c %s "$FILES_ARCHIVE" 2>/dev/null || echo "0")
  FILES_SIZE=$(echo "$FILES_SIZE_BYTES" | awk '{if($1>1024*1024*1024) printf "%.1fG", $1/1024/1024/1024; else if($1>1024*1024) printf "%.1fM", $1/1024/1024; else if($1>1024) printf "%.1fK", $1/1024; else printf "%dB", $1}' || echo "unknown")
  
  # Check if archive seems too small (less than 100MB might indicate incomplete backup)
  if [ "$FILES_SIZE_BYTES" -lt 104857600 ] && [ "$FILES_SIZE_BYTES" -gt 0 ]; then
    log_message "WARNING: Archive size seems unusually small: $FILES_SIZE ($FILES_SIZE_BYTES bytes)"
    log_message "This might indicate an incomplete backup. Please verify manually."
  fi
  
  log_message "Project files successfully backed up: $FILES_ARCHIVE (Size: $FILES_SIZE)"
  
  # Log tar output if there were any warnings (but not errors, since exit code was 0)
  if [ -n "$TAR_OUTPUT" ]; then
    log_message "Tar output: $TAR_OUTPUT"
  fi
else
  log_message "ERROR: Project files backup FAILED! (tar exit code: $TAR_EXIT_CODE)"
  if [ -n "$TAR_OUTPUT" ]; then
    log_message "Tar error output: $TAR_OUTPUT"
  fi
  send_email_if_error
  exit 1
fi

# Step 2: Create a database backup using mysqldump
log_message "Creating database backup using mysqldump..."

# Determine database backup filename based on compression setting
if [ "$ENABLE_COMPRESSION" -eq 1 ]; then
  DB_BACKUP_FILE="$BACKUP_TARGET/contao-database-$TIMESTAMP.sql.gz"
else
  DB_BACKUP_FILE="$BACKUP_TARGET/contao-database-$TIMESTAMP.sql"
fi

# Create database backup using mysqldump
# --no-tablespaces is required for shared hosting (IONOS, all-inkl, etc.)
# Capture stderr separately to capture any error messages
MYSQLDUMP_ERR_FILE="$BACKUP_TARGET/mysqldump_error.log"

if [ "$ENABLE_COMPRESSION" -eq 1 ]; then
  # Compressed backup
  mysqldump -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" --no-tablespaces "$DB_NAME" 2> "$MYSQLDUMP_ERR_FILE" | gzip > "$DB_BACKUP_FILE"
  MYSQLDUMP_EXIT_CODE=${PIPESTATUS[0]}
else
  # Uncompressed backup
  mysqldump -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" --no-tablespaces "$DB_NAME" > "$DB_BACKUP_FILE" 2> "$MYSQLDUMP_ERR_FILE"
  MYSQLDUMP_EXIT_CODE=$?
fi

if [ $MYSQLDUMP_EXIT_CODE -eq 0 ]; then
  # Verify the backup file was created and is not empty
  if [ ! -f "$DB_BACKUP_FILE" ]; then
    log_message "ERROR: Database backup file was not created: $DB_BACKUP_FILE"
    send_email_if_error
    exit 1
  fi
  
  # Get file size
  DB_SIZE_BYTES=$(stat -c %s "$DB_BACKUP_FILE" 2>/dev/null || echo "0")
  DB_SIZE=$(echo "$DB_SIZE_BYTES" | awk '{if($1>1024*1024*1024) printf "%.1fG", $1/1024/1024/1024; else if($1>1024*1024) printf "%.1fM", $1/1024/1024; else if($1>1024) printf "%.1fK", $1/1024; else printf "%dB", $1}' || echo "unknown")
  
  # Check if backup seems too small (less than 1KB might indicate an error)
  if [ "$DB_SIZE_BYTES" -lt 1024 ] && [ "$DB_SIZE_BYTES" -gt 0 ]; then
    log_message "WARNING: Database backup size seems unusually small: $DB_SIZE ($DB_SIZE_BYTES bytes)"
    log_message "This might indicate an incomplete backup. Please verify manually."
  fi
  
  log_message "Database successfully backed up: $DB_BACKUP_FILE (Size: $DB_SIZE)"
  
  # Clean up error file if backup was successful
  rm -f "$MYSQLDUMP_ERR_FILE" 2>/dev/null || true
else
  log_message "ERROR: Contao database backup FAILED! (mysqldump exit code: $MYSQLDUMP_EXIT_CODE)"
  # Log error output if available
  if [ -f "$MYSQLDUMP_ERR_FILE" ] && [ -s "$MYSQLDUMP_ERR_FILE" ]; then
    log_message "mysqldump error output:"
    while IFS= read -r line; do
      log_message "  $line"
    done < "$MYSQLDUMP_ERR_FILE"
  fi
  # Also check if partial file was created and log its content if small
  if [ -f "$DB_BACKUP_FILE" ]; then
    DB_SIZE_BYTES=$(stat -c %s "$DB_BACKUP_FILE" 2>/dev/null || echo "0")
    if [ "$DB_SIZE_BYTES" -lt 10240 ]; then
      log_message "Partial backup file content (first 20 lines):"
      head -n 20 "$DB_BACKUP_FILE" 2>/dev/null | while IFS= read -r line; do
        log_message "  $line"
      done || true
    fi
  fi
  # Clean up error file
  rm -f "$MYSQLDUMP_ERR_FILE" 2>/dev/null || true
  send_email_if_error
  exit 1
fi

# Step 3: Ensure a maximum of MAX_BACKUPS in the backup folder
# Count backup directories using shell globbing (more reliable in cron environment)
BACKUPS_COUNT=0
for backup_dir in "$BACKUP_FOLDER"/*; do
  if [ -d "$backup_dir" ]; then
    BACKUPS_COUNT=$((BACKUPS_COUNT + 1))
  fi
done

if [ "$BACKUPS_COUNT" -gt "$MAX_BACKUPS" ]; then
  # Find oldest backup directory by modification time
  OLDEST_BACKUP=""
  OLDEST_TIME=9999999999
  for backup_dir in "$BACKUP_FOLDER"/*; do
    if [ -d "$backup_dir" ]; then
      dir_time=$(stat -c %Y "$backup_dir" 2>/dev/null || echo "0")
      if [ "$dir_time" -lt "$OLDEST_TIME" ]; then
        OLDEST_TIME="$dir_time"
        OLDEST_BACKUP="$(basename "$backup_dir")"
      fi
    fi
  done
  
  if [ -n "$OLDEST_BACKUP" ] && rm -rf "$BACKUP_FOLDER/$OLDEST_BACKUP"; then
    log_message "Deleted oldest backup: $OLDEST_BACKUP to maintain a maximum of $MAX_BACKUPS backups."
  else
    log_message "ERROR: Failed to delete oldest backup: $OLDEST_BACKUP"
    send_email_if_error
    exit 1
  fi
fi

# Finish logging
log_message "Backup completed successfully for $TIMESTAMP."
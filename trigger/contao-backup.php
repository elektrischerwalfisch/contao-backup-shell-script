<?php
/**
 * Contao Backup Trigger Script
 *
 * PHP script that sets execute permissions on the backup script and runs it.
 * Use this if you don't have SSH access to set chmod +x on the shell script.
 *
 * HOW TO USE:
 * 1. Configure the settings below (script path, execution mode)
 * 2. Call this script via URL with a cronjob or via browser
 *
 * SECURITY:
 * - See README section "Trigger Security (Current Limitations and TODO)".
 */

// ============================================================================
// CONFIGURATION
// ============================================================================

// Shell script path (relative to this PHP file's directory)
// Default: ../scripts/contao-backup.sh (standard structure)
// Change this if your script is in a different location
$shellScriptPath = __DIR__ . "/../scripts/contao-backup.sh";

// Execution mode: 'sync' or 'background'
// - 'sync': Waits for script completion (default, works on all-inkl)
// - 'background': Runs script in background (recommended for IONOS to avoid timeouts)
$executionMode = 'sync'; // Change to 'background' for IONOS

// SECURITY: In production/cron, $debugMode MUST stay false (minimal HTTP output).
// Use true only for initial setup or troubleshooting; details are in backup.log.
$debugMode = false;

// Minimal HTTP responses (used when $debugMode is false)
$minimalMessageStarted = "Process started\n";
$minimalMessageFinished = "Process finished\n";
$minimalMessageError = "Error\n";

// ============================================================================
// OUTPUT HELPERS
// ============================================================================

function triggerRespondSuccess(string $minimalMessage, bool $debugMode, ?string $verboseMessage = null): void
{
    echo ($debugMode && $verboseMessage !== null) ? $verboseMessage : $minimalMessage;
}

function triggerRespondError(int $httpCode, string $minimalMessage, bool $debugMode, ?string $verboseMessage = null): void
{
    http_response_code($httpCode);
    echo ($debugMode && $verboseMessage !== null) ? $verboseMessage : $minimalMessage;
    exit(1);
}

// ============================================================================
// SCRIPT VALIDATION
// ============================================================================

// Use realpath() to get absolute canonical path (important for PHP exec())
$shellScript = realpath($shellScriptPath);

// Check if script exists
if (!$shellScript || !file_exists($shellScript)) {
    $verboseMessage = "ERROR: Script file not found: $shellScriptPath";
    if ($shellScript) {
        $verboseMessage .= " (resolved to: $shellScript)";
    }
    triggerRespondError(500, $minimalMessageError, $debugMode, $verboseMessage);
}

// Try to set execute permissions (won't work if PHP doesn't have write access)
// If this fails silently, it's usually fine - the script might already be executable
chmod($shellScript, 0755);

// Common troubleshooting hints for trigger errors.
$errorHint = "Hint: Check scripts/.env-contao-backup and verify paths, database config, and required tools are configured.\n";
$logHint = "See BACKUP_FOLDER/backup.log for detailed diagnostics.\n";

// ============================================================================
// EXECUTE SCRIPT
// ============================================================================

if ($executionMode === 'background') {
    // Background execution (recommended for IONOS to avoid timeout issues)
    // Using setsid + nohup to completely detach from PHP process
    $scriptDir = dirname($shellScript);
    $command = "cd " . escapeshellarg($scriptDir) . " && setsid nohup bash -l -c " . escapeshellarg($shellScript . " 2>&1") . " > /dev/null 2>&1 < /dev/null & echo \$!";
    exec($command, $output, $returnCode);
    
    if (!empty($output) && is_numeric(trim($output[0]))) {
        $pid = trim($output[0]);
        $verboseMessage = "SUCCESS: Backup script started in background (PID: $pid).\n\n"
            . "The backup is now running. Check BACKUP_FOLDER/backup.log for progress.\n";
        triggerRespondSuccess($minimalMessageStarted, $debugMode, $verboseMessage);
    } else {
        $verboseMessage = "ERROR: Could not start backup in background.\n"
            . "Please check if setsid is available on your system.\n"
            . "If background execution is not available, change \$executionMode to 'sync' in the configuration.\n"
            . $errorHint
            . $logHint;
        triggerRespondError(500, $minimalMessageError, $debugMode, $verboseMessage);
    }
} else {
    // Synchronous execution (default, works on all-inkl)
    // Execute the shell script in a login shell environment (like SSH would)
    // This ensures environment variables and PATH are loaded correctly
    exec("bash -l -c " . escapeshellarg($shellScript) . " 2>&1", $output, $returnCode);
    
    // Return results
    if ($returnCode === 0) {
        $verboseMessage = "SUCCESS: Backup script completed successfully.\n\n"
            . "Output:\n"
            . implode("\n", $output);
        triggerRespondSuccess($minimalMessageFinished, $debugMode, $verboseMessage);
    } else {
        $verboseMessage = "ERROR: Backup script failed with exit code $returnCode.\n\n"
            . $errorHint
            . $logHint . "\n"
            . "Output:\n"
            . implode("\n", $output);
        triggerRespondError(500, $minimalMessageError, $debugMode, $verboseMessage);
    }
}




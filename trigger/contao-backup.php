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
 * - Restrict access via .htaccess to authorized IP addresses (recommended)
 */

// ============================================================================
// CONFIGURATION
// ============================================================================

// Shell script path (relative to this PHP file's directory)
// Default: ../scripts/contao-backup.sh (standard structure)
// Change this if your script is in a different location
$shellScriptPath = __DIR__ . "/../scripts/contao-backup.sh";

// Execution mode: 'sync' or 'background'
// - 'sync': Waits for script completion, returns full output (default, works on all-inkl)
// - 'background': Runs script in background, returns PID (recommended for IONOS to avoid timeouts)
$executionMode = 'sync'; // Change to 'background' for IONOS

// ============================================================================
// SCRIPT VALIDATION
// ============================================================================

// Use realpath() to get absolute canonical path (important for PHP exec())
$shellScript = realpath($shellScriptPath);

// Check if script exists
if (!$shellScript || !file_exists($shellScript)) {
    http_response_code(500);
    echo "ERROR: Script file not found: $shellScriptPath";
    if ($shellScript) {
        echo " (resolved to: $shellScript)";
    }
    exit(1);
}

// Try to set execute permissions (won't work if PHP doesn't have write access)
// If this fails silently, it's usually fine - the script might already be executable
chmod($shellScript, 0755);

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
        echo "SUCCESS: Backup script started in background (PID: $pid).\n\n";
        echo "The backup is now running. Check BACKUP_FOLDER/backup.log for progress.\n";
    } else {
        http_response_code(500);
        echo "ERROR: Could not start backup in background.\n";
        echo "Please check if setsid is available on your system.\n";
        echo "If background execution is not available, change \$executionMode to 'sync' in the configuration.\n";
    }
} else {
    // Synchronous execution (default, works on all-inkl)
    // Execute the shell script in a login shell environment (like SSH would)
    // This ensures environment variables and PATH are loaded correctly
    exec("bash -l -c " . escapeshellarg($shellScript) . " 2>&1", $output, $returnCode);
    
    // Return results
    if ($returnCode === 0) {
        echo "SUCCESS: Backup script completed successfully.\n\n";
        echo "Output:\n";
        echo implode("\n", $output);
    } else {
        http_response_code(500);
        echo "ERROR: Backup script failed with exit code $returnCode.\n\n";
        echo "Output:\n";
        echo implode("\n", $output);
    }
}




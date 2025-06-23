#!/bin/bash
# System Maintenance Tasks Script
# Cleans temporary files, rotates logs, updates package lists, and verifies backups

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$BASE_DIR/config/maintenance_config.json"
LOG_FILE="$BASE_DIR/logs/maintenance.log"
TEMP_DIRS=("/tmp" "/var/tmp" "/var/cache/apt/archives" "/home/cbwinslow/.cache")
LOG_DIRS=("/var/log" "/home/cbwinslow/.local/share/logs")
BACKUP_DIRS=("/home/cbwinslow/backups" "/var/backups")

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # Parse JSON config if it exists
        log "INFO" "Loading configuration from $CONFIG_FILE"
        
        # Extract values from JSON using jq if available, otherwise use defaults
        if command -v jq &> /dev/null; then
            CLEANUP_TEMP_FILES=$(jq -r '.cleanup_temp_files // true' "$CONFIG_FILE")
            ROTATE_LOGS=$(jq -r '.rotate_logs // true' "$CONFIG_FILE")
            UPDATE_PACKAGES=$(jq -r '.update_packages // true' "$CONFIG_FILE")
            VERIFY_BACKUPS=$(jq -r '.verify_backups // true' "$CONFIG_FILE")
            TEMP_FILE_AGE_DAYS=$(jq -r '.temp_file_age_days // 7' "$CONFIG_FILE")
            LOG_RETENTION_DAYS=$(jq -r '.log_retention_days // 30' "$CONFIG_FILE")
            NOTIFICATION_EMAIL=$(jq -r '.notification_email // ""' "$CONFIG_FILE")
        else
            log "WARN" "jq not available, using default configuration"
            set_defaults
        fi
    else
        log "INFO" "Configuration file not found, using defaults"
        set_defaults
        create_default_config
    fi
}

# Set default configuration values
set_defaults() {
    CLEANUP_TEMP_FILES=true
    ROTATE_LOGS=true
    UPDATE_PACKAGES=true
    VERIFY_BACKUPS=true
    TEMP_FILE_AGE_DAYS=7
    LOG_RETENTION_DAYS=30
    NOTIFICATION_EMAIL=""
}

# Create default configuration file
create_default_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << EOF
{
  "cleanup_temp_files": true,
  "rotate_logs": true,
  "update_packages": true,
  "verify_backups": true,
  "temp_file_age_days": 7,
  "log_retention_days": 30,
  "notification_email": "",
  "temp_dirs": [
    "/tmp",
    "/var/tmp",
    "/var/cache/apt/archives",
    "/home/cbwinslow/.cache"
  ],
  "log_dirs": [
    "/var/log",
    "/home/cbwinslow/.local/share/logs"
  ],
  "backup_dirs": [
    "/home/cbwinslow/backups",
    "/var/backups"
  ],
  "exclude_patterns": [
    "*.lock",
    "*.pid",
    "currently-*"
  ]
}
EOF
    log "INFO" "Created default configuration file: $CONFIG_FILE"
}

# Check if running as root for system-level operations
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        log "INFO" "Running with root privileges - full system maintenance enabled"
        SYSTEM_MAINTENANCE=true
    else
        log "INFO" "Running as user - limited to user-level maintenance"
        SYSTEM_MAINTENANCE=false
    fi
}

# Clean temporary files
cleanup_temp_files() {
    if [[ "$CLEANUP_TEMP_FILES" != "true" ]]; then
        log "INFO" "Temporary file cleanup disabled"
        return 0
    fi
    
    log "INFO" "Starting temporary file cleanup"
    local files_removed=0
    local space_freed=0
    
    for temp_dir in "${TEMP_DIRS[@]}"; do
        if [[ ! -d "$temp_dir" ]]; then
            log "WARN" "Temporary directory $temp_dir does not exist"
            continue
        fi
        
        log "INFO" "Cleaning temporary files in $temp_dir"
        
        # Find and remove files older than specified days
        if [[ -w "$temp_dir" ]]; then
            # Calculate space before cleanup
            local space_before
            space_before=$(du -sb "$temp_dir" 2>/dev/null | cut -f1 || echo 0)
            
            # Find and count files to be removed
            local file_count
            file_count=$(find "$temp_dir" -type f -mtime +${TEMP_FILE_AGE_DAYS} 2>/dev/null | wc -l || echo 0)
            
            # Remove old temporary files
            find "$temp_dir" -type f -mtime +${TEMP_FILE_AGE_DAYS} -delete 2>/dev/null || true
            
            # Remove empty directories
            find "$temp_dir" -type d -empty -delete 2>/dev/null || true
            
            # Calculate space after cleanup
            local space_after
            space_after=$(du -sb "$temp_dir" 2>/dev/null | cut -f1 || echo 0)
            
            local freed=$((space_before - space_after))
            files_removed=$((files_removed + file_count))
            space_freed=$((space_freed + freed))
            
            log "INFO" "Removed $file_count files from $temp_dir, freed $(( freed / 1024 / 1024 )) MB"
        else
            log "WARN" "No write permission for $temp_dir"
        fi
    done
    
    # Clean package cache if we have permission
    if command -v apt &> /dev/null && [[ "$SYSTEM_MAINTENANCE" = true ]]; then
        log "INFO" "Cleaning package cache"
        apt-get clean 2>/dev/null || log "WARN" "Failed to clean package cache"
    fi
    
    log "INFO" "Temporary file cleanup completed: $files_removed files removed, $(( space_freed / 1024 / 1024 )) MB freed"
}

# Rotate logs
rotate_logs() {
    if [[ "$ROTATE_LOGS" != "true" ]]; then
        log "INFO" "Log rotation disabled"
        return 0
    fi
    
    log "INFO" "Starting log rotation"
    
    # Use logrotate if available and running as root
    if command -v logrotate &> /dev/null && [[ "$SYSTEM_MAINTENANCE" = true ]]; then
        log "INFO" "Running system logrotate"
        logrotate -f /etc/logrotate.conf 2>&1 | tee -a "$LOG_FILE" || log "WARN" "Logrotate failed"
    fi
    
    # Manual log rotation for user logs
    for log_dir in "${LOG_DIRS[@]}"; do
        if [[ ! -d "$log_dir" ]]; then
            continue
        fi
        
        log "INFO" "Processing logs in $log_dir"
        
        # Find large log files (>100MB) and rotate them
        find "$log_dir" -name "*.log" -size +100M -type f 2>/dev/null | while read -r logfile; do
            if [[ -w "$logfile" ]]; then
                log "INFO" "Rotating large log file: $logfile"
                mv "$logfile" "${logfile}.$(date +%Y%m%d_%H%M%S)"
                touch "$logfile"
                
                # Compress rotated log
                gzip "${logfile}.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            fi
        done
        
        # Remove old compressed logs
        find "$log_dir" -name "*.log.*.gz" -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true
    done
    
    log "INFO" "Log rotation completed"
}

# Update package lists
update_packages() {
    if [[ "$UPDATE_PACKAGES" != "true" ]]; then
        log "INFO" "Package update disabled"
        return 0
    fi
    
    log "INFO" "Starting package list update"
    
    # Update package database
    if command -v apt &> /dev/null; then
        if [[ "$SYSTEM_MAINTENANCE" = true ]]; then
            log "INFO" "Updating APT package lists"
            apt update 2>&1 | tee -a "$LOG_FILE" || log "ERROR" "Failed to update package lists"
            
            # Check for available upgrades
            local upgrades
            upgrades=$(apt list --upgradable 2>/dev/null | wc -l)
            log "INFO" "Available package upgrades: $((upgrades - 1))"
        else
            log "INFO" "Skipping system package update (requires root)"
        fi
    fi
    
    # Update snap packages if available
    if command -v snap &> /dev/null; then
        log "INFO" "Refreshing snap packages"
        snap refresh 2>&1 | tee -a "$LOG_FILE" || log "WARN" "Failed to refresh snap packages"
    fi
    
    # Update flatpak packages if available
    if command -v flatpak &> /dev/null; then
        log "INFO" "Updating flatpak packages"
        flatpak update -y 2>&1 | tee -a "$LOG_FILE" || log "WARN" "Failed to update flatpak packages"
    fi
    
    log "INFO" "Package update completed"
}

# Verify backups
verify_backups() {
    if [[ "$VERIFY_BACKUPS" != "true" ]]; then
        log "INFO" "Backup verification disabled"
        return 0
    fi
    
    log "INFO" "Starting backup verification"
    local backup_status="OK"
    local total_backups=0
    local valid_backups=0
    
    for backup_dir in "${BACKUP_DIRS[@]}"; do
        if [[ ! -d "$backup_dir" ]]; then
            log "WARN" "Backup directory $backup_dir does not exist"
            continue
        fi
        
        log "INFO" "Verifying backups in $backup_dir"
        
        # Check for recent backups (within last 7 days)
        local recent_backups
        recent_backups=$(find "$backup_dir" -type f -mtime -7 2>/dev/null | wc -l)
        total_backups=$((total_backups + recent_backups))
        
        if [[ $recent_backups -eq 0 ]]; then
            log "WARN" "No recent backups found in $backup_dir"
            backup_status="WARNING"
        else
            log "INFO" "Found $recent_backups recent backup(s) in $backup_dir"
        fi
        
        # Verify backup integrity (for common formats)
        find "$backup_dir" -name "*.tar.gz" -o -name "*.tar.bz2" -o -name "*.zip" -mtime -7 2>/dev/null | while read -r backup_file; do
            case "$backup_file" in
                *.tar.gz)
                    if tar -tzf "$backup_file" >/dev/null 2>&1; then
                        log "INFO" "Backup integrity OK: $backup_file"
                        valid_backups=$((valid_backups + 1))
                    else
                        log "ERROR" "Backup integrity FAILED: $backup_file"
                        backup_status="ERROR"
                    fi
                    ;;
                *.tar.bz2)
                    if tar -tjf "$backup_file" >/dev/null 2>&1; then
                        log "INFO" "Backup integrity OK: $backup_file"
                        valid_backups=$((valid_backups + 1))
                    else
                        log "ERROR" "Backup integrity FAILED: $backup_file"
                        backup_status="ERROR"
                    fi
                    ;;
                *.zip)
                    if unzip -t "$backup_file" >/dev/null 2>&1; then
                        log "INFO" "Backup integrity OK: $backup_file"
                        valid_backups=$((valid_backups + 1))
                    else
                        log "ERROR" "Backup integrity FAILED: $backup_file"
                        backup_status="ERROR"
                    fi
                    ;;
            esac
        done
    done
    
    log "INFO" "Backup verification completed: $backup_status ($valid_backups/$total_backups backups verified)"
    
    # Alert if no backups found
    if [[ $total_backups -eq 0 ]]; then
        log "ERROR" "No recent backups found in any backup directory!"
        backup_status="CRITICAL"
    fi
    
    echo "$backup_status" > "$BASE_DIR/logs/backup_status.txt"
}

# Generate maintenance report
generate_report() {
    local report_file="$BASE_DIR/reports/maintenance_report_$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$(dirname "$report_file")"
    
    log "INFO" "Generating maintenance report: $report_file"
    
    cat > "$report_file" << EOF
System Maintenance Report
Generated: $(date)
Host: $(hostname)
User: $(whoami)

=== MAINTENANCE SUMMARY ===
Temporary File Cleanup: $([ "$CLEANUP_TEMP_FILES" = true ] && echo "ENABLED" || echo "DISABLED")
Log Rotation: $([ "$ROTATE_LOGS" = true ] && echo "ENABLED" || echo "DISABLED")
Package Updates: $([ "$UPDATE_PACKAGES" = true ] && echo "ENABLED" || echo "DISABLED")
Backup Verification: $([ "$VERIFY_BACKUPS" = true ] && echo "ENABLED" || echo "DISABLED")

=== SYSTEM INFORMATION ===
Disk Usage:
$(df -h | head -n 1)
$(df -h | grep -E "^/dev|^tmpfs" | head -n 5)

Memory Usage:
$(free -h)

Load Average:
$(uptime)

=== MAINTENANCE LOG (Last 50 lines) ===
$(tail -n 50 "$LOG_FILE")

EOF
    
    log "INFO" "Maintenance report generated: $report_file"
}

# Send notification email if configured
send_notification() {
    if [[ -z "$NOTIFICATION_EMAIL" ]]; then
        return 0
    fi
    
    local subject="System Maintenance Completed - $(hostname)"
    local report_file="$BASE_DIR/reports/maintenance_report_$(date +%Y%m%d)*.txt"
    
    if command -v mail &> /dev/null; then
        log "INFO" "Sending notification email to $NOTIFICATION_EMAIL"
        echo "System maintenance completed successfully on $(hostname) at $(date)" | \
            mail -s "$subject" "$NOTIFICATION_EMAIL" 2>&1 | tee -a "$LOG_FILE" || \
            log "WARN" "Failed to send notification email"
    else
        log "WARN" "Mail command not available, skipping email notification"
    fi
}

# Main maintenance function
run_maintenance() {
    log "INFO" "Starting system maintenance"
    local start_time=$(date +%s)
    
    # Check system privileges
    check_privileges
    
    # Run maintenance tasks
    cleanup_temp_files
    rotate_logs
    update_packages
    verify_backups
    
    # Generate report
    generate_report
    
    # Send notification
    send_notification
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "INFO" "System maintenance completed in ${duration} seconds"
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

System Maintenance Script
Performs automated system maintenance tasks including:
- Temporary file cleanup
- Log rotation
- Package list updates
- Backup verification

OPTIONS:
    --help              Show this help message
    --config-only       Create configuration file and exit
    --dry-run          Show what would be done without making changes
    --cleanup-only     Run only temporary file cleanup
    --logs-only        Run only log rotation
    --packages-only    Run only package updates
    --backups-only     Run only backup verification

EXAMPLES:
    $0                 Run all maintenance tasks
    $0 --dry-run       Show what would be done
    $0 --cleanup-only  Run only file cleanup
    
Configuration file: $CONFIG_FILE
Log file: $LOG_FILE
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_usage
                exit 0
                ;;
            --config-only)
                load_config
                create_default_config
                exit 0
                ;;
            --dry-run)
                log "INFO" "DRY RUN MODE - No changes will be made"
                # Override functions to just log what would be done
                cleanup_temp_files() { log "INFO" "DRY RUN: Would clean temporary files"; }
                rotate_logs() { log "INFO" "DRY RUN: Would rotate logs"; }
                update_packages() { log "INFO" "DRY RUN: Would update packages"; }
                verify_backups() { log "INFO" "DRY RUN: Would verify backups"; }
                ;;
            --cleanup-only)
                ROTATE_LOGS=false
                UPDATE_PACKAGES=false
                VERIFY_BACKUPS=false
                ;;
            --logs-only)
                CLEANUP_TEMP_FILES=false
                UPDATE_PACKAGES=false
                VERIFY_BACKUPS=false
                ;;
            --packages-only)
                CLEANUP_TEMP_FILES=false
                ROTATE_LOGS=false
                VERIFY_BACKUPS=false
                ;;
            --backups-only)
                CLEANUP_TEMP_FILES=false
                ROTATE_LOGS=false
                UPDATE_PACKAGES=false
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
        shift
    done
}

# Main script execution
main() {
    # Parse command line arguments
    parse_args "$@"
    
    # Load configuration
    load_config
    
    # Create lock file to prevent concurrent execution
    local lock_file="/tmp/maintenance_tasks.lock"
    if [[ -f "$lock_file" ]]; then
        local pid=$(cat "$lock_file")
        if kill -0 "$pid" 2>/dev/null; then
            log "ERROR" "Another maintenance process is already running (PID: $pid)"
            exit 1
        else
            log "WARN" "Removing stale lock file"
            rm -f "$lock_file"
        fi
    fi
    
    # Create lock file
    echo $$ > "$lock_file"
    
    # Set up cleanup trap
    trap 'rm -f "$lock_file"; log "INFO" "Maintenance script terminated"' EXIT INT TERM
    
    # Run maintenance
    run_maintenance
    
    # Remove lock file
    rm -f "$lock_file"
    
    log "INFO" "Maintenance script completed successfully"
}

# Run main function with all arguments
main "$@"


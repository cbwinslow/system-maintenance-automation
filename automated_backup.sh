#!/bin/bash

# automated_backup.sh
# Automated backup script using LVM storage for comprehensive data protection
# Author: System Maintenance Automation
# Created: $(date)

set -euo pipefail

# Configuration
BACKUP_BASE="/mnt/storage/backups"
LOG_FILE="$HOME/system-maintenance-automation/logs/backup_$(date +%Y%m%d_%H%M%S).log"
CONFIG_FILE="$HOME/system-maintenance-automation/backup_config.conf"

# Default retention periods (days)
DAILY_RETENTION=7
WEEKLY_RETENTION=30
MONTHLY_RETENTION=365

# Email notification (if configured)
EMAIL_NOTIFY=${EMAIL_NOTIFY:-""}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
    log "INFO: $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    log "WARN: $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log "ERROR: $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
    log "SECTION: $1"
}

# Load configuration if exists
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        print_status "Configuration loaded from $CONFIG_FILE"
    else
        print_warning "No configuration file found, using defaults"
    fi
}

# Create default configuration
create_default_config() {
    cat > "$CONFIG_FILE" << EOF
# Automated Backup Configuration
# Generated: $(date)

# Retention periods (in days)
DAILY_RETENTION=7
WEEKLY_RETENTION=30
MONTHLY_RETENTION=365

# Email notification (leave empty to disable)
EMAIL_NOTIFY=""

# Backup sources (space-separated)
HOME_DIRS=".bashrc .zshrc .gitconfig .ssh .dotfiles"
PROJECT_DIRS="/mnt/storage/projects"
CONFIG_DIRS="/etc/fstab /etc/hosts /etc/hostname"

# Exclude patterns for rsync (one per line, will be converted to --exclude)
EXCLUDE_PATTERNS="
.cache
.tmp
*.tmp
.git/objects
node_modules
__pycache__
.venv
venv
.DS_Store
Thumbs.db
"

# Database backup settings
DB_BACKUP_ENABLED=true
POSTGRES_DBS="cbwinslow"  # Space-separated list
EOF

    print_status "Default configuration created at $CONFIG_FILE"
}

# Determine backup type based on day
get_backup_type() {
    local day_of_month=$(date +%d)
    local day_of_week=$(date +%u)  # 1-7, Monday is 1
    
    if [[ "$day_of_month" == "01" ]]; then
        echo "monthly"
    elif [[ "$day_of_week" == "7" ]]; then  # Sunday
        echo "weekly"
    else
        echo "daily"
    fi
}

# Create backup directory structure
create_backup_structure() {
    local backup_type="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    case "$backup_type" in
        "daily")
            backup_dir="$BACKUP_BASE/home/daily/$timestamp"
            ;;
        "weekly")
            backup_dir="$BACKUP_BASE/home/weekly/$timestamp"
            ;;
        "monthly")
            backup_dir="$BACKUP_BASE/home/monthly/$timestamp"
            ;;
        *)
            backup_dir="$BACKUP_BASE/home/daily/$timestamp"
            ;;
    esac
    
    mkdir -p "$backup_dir"
    echo "$backup_dir"
}

# Build rsync exclude options
build_exclude_options() {
    local exclude_opts=""
    while IFS= read -r pattern; do
        [[ -n "$pattern" ]] && exclude_opts="$exclude_opts --exclude=$pattern"
    done <<< "$EXCLUDE_PATTERNS"
    echo "$exclude_opts"
}

# Backup home directory files
backup_home() {
    local backup_dir="$1"
    local home_backup_dir="$backup_dir/home"
    
    print_header "BACKING UP HOME DIRECTORY"
    
    mkdir -p "$home_backup_dir"
    
    # Build exclude options
    local exclude_opts=$(build_exclude_options)
    
    # Backup specified home directories/files
    for item in $HOME_DIRS; do
        local source_path="$HOME/$item"
        if [[ -e "$source_path" ]]; then
            print_status "Backing up $source_path"
            rsync -av $exclude_opts "$source_path" "$home_backup_dir/" 2>&1 | tee -a "$LOG_FILE"
        else
            print_warning "Source path $source_path does not exist, skipping"
        fi
    done
    
    # Create a manifest of what was backed up
    echo "Home backup manifest - $(date)" > "$home_backup_dir/MANIFEST.txt"
    echo "Backup directory: $home_backup_dir" >> "$home_backup_dir/MANIFEST.txt"
    echo "Items backed up:" >> "$home_backup_dir/MANIFEST.txt"
    find "$home_backup_dir" -type f | head -50 >> "$home_backup_dir/MANIFEST.txt"
    
    print_status "Home backup completed to $home_backup_dir"
}

# Backup system configurations
backup_configs() {
    local backup_dir="$1"
    local config_backup_dir="$backup_dir/configs"
    
    print_header "BACKING UP SYSTEM CONFIGURATIONS"
    
    mkdir -p "$config_backup_dir"
    
    # System configuration files
    for config_file in $CONFIG_DIRS; do
        if [[ -e "$config_file" ]]; then
            print_status "Backing up $config_file"
            sudo cp -r "$config_file" "$config_backup_dir/" 2>/dev/null || print_warning "Failed to backup $config_file"
        fi
    done
    
    # LVM configuration
    sudo vgdisplay > "$config_backup_dir/lvm_vgdisplay.txt" 2>/dev/null || true
    sudo lvdisplay > "$config_backup_dir/lvm_lvdisplay.txt" 2>/dev/null || true
    sudo pvdisplay > "$config_backup_dir/lvm_pvdisplay.txt" 2>/dev/null || true
    
    # Disk layout
    lsblk > "$config_backup_dir/lsblk.txt"
    df -h > "$config_backup_dir/df.txt"
    mount > "$config_backup_dir/mount.txt"
    
    # Package lists
    dpkg -l > "$config_backup_dir/dpkg_packages.txt" 2>/dev/null || true
    snap list > "$config_backup_dir/snap_packages.txt" 2>/dev/null || true
    if command -v conda &> /dev/null; then
        conda list > "$config_backup_dir/conda_packages.txt" 2>/dev/null || true
    fi
    
    print_status "System configuration backup completed to $config_backup_dir"
}

# Backup databases
backup_databases() {
    local backup_dir="$1"
    local db_backup_dir="$backup_dir/databases"
    
    print_header "BACKING UP DATABASES"
    
    if [[ "$DB_BACKUP_ENABLED" != "true" ]]; then
        print_warning "Database backup disabled in configuration"
        return
    fi
    
    mkdir -p "$db_backup_dir"
    
    # PostgreSQL databases
    if command -v pg_dump &> /dev/null && [[ -n "$POSTGRES_DBS" ]]; then
        for db in $POSTGRES_DBS; do
            print_status "Backing up PostgreSQL database: $db"
            local dump_file="$db_backup_dir/postgres_${db}_$(date +%Y%m%d_%H%M%S).sql"
            pg_dump -U cbwinslow "$db" > "$dump_file" 2>&1 || print_warning "Failed to backup database $db"
            
            # Compress the dump
            if [[ -f "$dump_file" ]]; then
                gzip "$dump_file"
                print_status "Database $db backed up and compressed: ${dump_file}.gz"
            fi
        done
    else
        print_warning "PostgreSQL not found or no databases configured"
    fi
    
    print_status "Database backup completed to $db_backup_dir"
}

# Backup project metadata
backup_project_metadata() {
    local backup_dir="$1"
    local project_backup_dir="$backup_dir/project_metadata"
    
    print_header "BACKING UP PROJECT METADATA"
    
    mkdir -p "$project_backup_dir"
    
    # Backup important project files (README, configs, etc.)
    if [[ -d "$PROJECT_DIRS" ]]; then
        find "$PROJECT_DIRS" -name "README*" -o -name "*.md" -o -name "package.json" -o -name "requirements.txt" -o -name "Cargo.toml" -o -name "pom.xml" | while read -r file; do
            local rel_path=$(realpath --relative-to="$PROJECT_DIRS" "$file")
            local dest_dir=$(dirname "$project_backup_dir/$rel_path")
            mkdir -p "$dest_dir"
            cp "$file" "$dest_dir/" 2>/dev/null || print_warning "Failed to backup $file"
        done
        
        print_status "Project metadata backup completed to $project_backup_dir"
    else
        print_warning "Project directory $PROJECT_DIRS not found"
    fi
}

# Clean old backups based on retention policy
cleanup_old_backups() {
    print_header "CLEANING UP OLD BACKUPS"
    
    # Clean daily backups
    local daily_dir="$BACKUP_BASE/home/daily"
    if [[ -d "$daily_dir" ]]; then
        find "$daily_dir" -maxdepth 1 -type d -mtime +$DAILY_RETENTION -exec rm -rf {} \; 2>/dev/null || true
        local daily_count=$(find "$daily_dir" -maxdepth 1 -type d | wc -l)
        print_status "Daily backups: $daily_count remaining after cleanup"
    fi
    
    # Clean weekly backups
    local weekly_dir="$BACKUP_BASE/home/weekly"
    if [[ -d "$weekly_dir" ]]; then
        find "$weekly_dir" -maxdepth 1 -type d -mtime +$WEEKLY_RETENTION -exec rm -rf {} \; 2>/dev/null || true
        local weekly_count=$(find "$weekly_dir" -maxdepth 1 -type d | wc -l)
        print_status "Weekly backups: $weekly_count remaining after cleanup"
    fi
    
    # Clean monthly backups
    local monthly_dir="$BACKUP_BASE/home/monthly"
    if [[ -d "$monthly_dir" ]]; then
        find "$monthly_dir" -maxdepth 1 -type d -mtime +$MONTHLY_RETENTION -exec rm -rf {} \; 2>/dev/null || true
        local monthly_count=$(find "$monthly_dir" -maxdepth 1 -type d | wc -l)
        print_status "Monthly backups: $monthly_count remaining after cleanup"
    fi
}

# Generate backup report
generate_backup_report() {
    local backup_dir="$1"
    local backup_type="$2"
    
    local report_file="$backup_dir/BACKUP_REPORT.txt"
    
    {
        echo "Automated Backup Report"
        echo "======================="
        echo "Backup Type: $backup_type"
        echo "Timestamp: $(date)"
        echo "Backup Directory: $backup_dir"
        echo ""
        
        echo "BACKUP CONTENTS:"
        du -sh "$backup_dir"/* 2>/dev/null || echo "No contents found"
        echo ""
        
        echo "STORAGE USAGE:"
        df -h "$BACKUP_BASE"
        echo ""
        
        echo "BACKUP VERIFICATION:"
        if [[ -d "$backup_dir/home" ]]; then
            echo "✓ Home backup completed"
        fi
        if [[ -d "$backup_dir/configs" ]]; then
            echo "✓ Configuration backup completed"
        fi
        if [[ -d "$backup_dir/databases" ]]; then
            echo "✓ Database backup completed"
        fi
        if [[ -d "$backup_dir/project_metadata" ]]; then
            echo "✓ Project metadata backup completed"
        fi
        echo ""
        
        echo "LOG LOCATION:"
        echo "$LOG_FILE"
        
    } > "$report_file"
    
    print_status "Backup report generated: $report_file"
    
    # Display summary
    cat "$report_file"
}

# Send email notification if configured
send_notification() {
    local backup_dir="$1"
    local backup_type="$2"
    
    if [[ -n "$EMAIL_NOTIFY" ]] && command -v mail &> /dev/null; then
        local subject="Backup Completed: $backup_type - $(hostname)"
        local report_file="$backup_dir/BACKUP_REPORT.txt"
        
        if [[ -f "$report_file" ]]; then
            mail -s "$subject" "$EMAIL_NOTIFY" < "$report_file"
            print_status "Email notification sent to $EMAIL_NOTIFY"
        fi
    fi
}

# Main backup execution
main() {
    print_header "AUTOMATED BACKUP STARTING"
    
    # Create logs directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Load configuration
    load_config
    
    # Create default config if it doesn't exist
    [[ ! -f "$CONFIG_FILE" ]] && create_default_config && load_config
    
    # Determine backup type
    local backup_type=$(get_backup_type)
    print_status "Backup type determined: $backup_type"
    
    # Create backup directory
    local backup_dir=$(create_backup_structure "$backup_type")
    print_status "Backup directory created: $backup_dir"
    
    # Perform backups
    backup_home "$backup_dir"
    backup_configs "$backup_dir"
    backup_databases "$backup_dir"
    backup_project_metadata "$backup_dir"
    
    # Generate report
    generate_backup_report "$backup_dir" "$backup_type"
    
    # Cleanup old backups
    cleanup_old_backups
    
    # Send notification
    send_notification "$backup_dir" "$backup_type"
    
    print_header "BACKUP COMPLETED SUCCESSFULLY"
    print_status "Backup location: $backup_dir"
    print_status "Log file: $LOG_FILE"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi


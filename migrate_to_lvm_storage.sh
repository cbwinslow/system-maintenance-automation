#!/bin/bash

# migrate_to_lvm_storage.sh
# Comprehensive data migration script for new LVM storage volumes
# Author: System Maintenance Automation
# Created: $(date)

set -euo pipefail

# Configuration
LOG_FILE="$HOME/system-maintenance-automation/logs/lvm_migration_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=${1:-"false"}
FORCE=${2:-"false"}

# Storage paths
PROJECTS_STORAGE="/mnt/storage/projects"
MEDIA_STORAGE="/mnt/storage/media" 
BACKUPS_STORAGE="/mnt/storage/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Print colored output
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

# Safety checks
check_prerequisites() {
    print_header "CHECKING PREREQUISITES"
    
    # Check if storage volumes are mounted
    if ! mountpoint -q "$PROJECTS_STORAGE"; then
        print_error "Projects storage not mounted at $PROJECTS_STORAGE"
        exit 1
    fi
    
    if ! mountpoint -q "$MEDIA_STORAGE"; then
        print_error "Media storage not mounted at $MEDIA_STORAGE"
        exit 1
    fi
    
    if ! mountpoint -q "$BACKUPS_STORAGE"; then
        print_error "Backups storage not mounted at $BACKUPS_STORAGE"
        exit 1
    fi
    
    print_status "All storage volumes are properly mounted"
    
    # Check available space
    projects_avail=$(df "$PROJECTS_STORAGE" | tail -1 | awk '{print $4}')
    media_avail=$(df "$MEDIA_STORAGE" | tail -1 | awk '{print $4}')
    backups_avail=$(df "$BACKUPS_STORAGE" | tail -1 | awk '{print $4}')
    
    print_status "Available space - Projects: ${projects_avail}KB, Media: ${media_avail}KB, Backups: ${backups_avail}KB"
}

# Calculate directory sizes
calculate_sizes() {
    print_header "CALCULATING DATA SIZES"
    
    # Major project directories (in KB) - clean up any whitespace/newlines
    projects_size=$(du -s /home/cbwinslow/Projects 2>/dev/null | cut -f1 | tr -d '\n' || echo "0")
    dev_size=$(du -s /home/cbwinslow/dev 2>/dev/null | cut -f1 | tr -d '\n' || echo "0")
    cascade_size=$(du -s /home/cbwinslow/CascadeProjects 2>/dev/null | cut -f1 | tr -d '\n' || echo "0")
    devops_size=$(du -s /home/cbwinslow/devops-testing 2>/dev/null | cut -f1 | tr -d '\n' || echo "0")
    
    # Media directories (in KB)
    music_size=$(du -s /home/cbwinslow/Music 2>/dev/null | cut -f1 | tr -d '\n' || echo "0")
    videos_size=$(du -s /home/cbwinslow/Videos 2>/dev/null | cut -f1 | tr -d '\n' || echo "0")
    pictures_size=$(du -s /home/cbwinslow/Pictures 2>/dev/null | cut -f1 | tr -d '\n' || echo "0")
    
    # Downloads (can be large)
    downloads_size=$(du -s /home/cbwinslow/Downloads 2>/dev/null | cut -f1 | tr -d '\n' || echo "0")
    
    # Ensure all variables are numeric (fallback to 0 if not)
    projects_size=${projects_size//[^0-9]/0}
    dev_size=${dev_size//[^0-9]/0}
    cascade_size=${cascade_size//[^0-9]/0}
    devops_size=${devops_size//[^0-9]/0}
    music_size=${music_size//[^0-9]/0}
    videos_size=${videos_size//[^0-9]/0}
    pictures_size=${pictures_size//[^0-9]/0}
    downloads_size=${downloads_size//[^0-9]/0}
    
    print_status "Project directories:"
    print_status "  Projects: $((projects_size / 1024))MB"
    print_status "  dev: $((dev_size / 1024))MB" 
    print_status "  CascadeProjects: $((cascade_size / 1024))MB"
    print_status "  devops-testing: $((devops_size / 1024))MB"
    
    print_status "Media directories:"
    print_status "  Music: $((music_size / 1024))MB"
    print_status "  Videos: $((videos_size / 1024))MB"
    print_status "  Pictures: $((pictures_size / 1024))MB"
    
    print_status "Downloads: $((downloads_size / 1024))MB"
}

# Create organized directory structure
create_directory_structure() {
    print_header "CREATING DIRECTORY STRUCTURE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would create directory structure"
        return
    fi
    
    # Projects structure
    mkdir -p "$PROJECTS_STORAGE"/{active,archive,personal,work,experiments}
    mkdir -p "$PROJECTS_STORAGE"/active/{web,mobile,desktop,ai-ml,devops}
    
    # Media structure  
    mkdir -p "$MEDIA_STORAGE"/{music,videos,pictures,documents,downloads}
    mkdir -p "$MEDIA_STORAGE"/pictures/{screenshots,wallpapers,personal,work}
    
    # Backups structure
    mkdir -p "$BACKUPS_STORAGE"/{system,home,projects,databases,configs}
    mkdir -p "$BACKUPS_STORAGE"/home/{daily,weekly,monthly}
    
    print_status "Directory structure created successfully"
}

# Migrate projects
migrate_projects() {
    print_header "MIGRATING PROJECT DIRECTORIES"
    
    # Major project directories to migrate
    declare -A project_dirs=(
        ["/home/cbwinslow/Projects"]="$PROJECTS_STORAGE/active/personal"
        ["/home/cbwinslow/dev"]="$PROJECTS_STORAGE/active"
        ["/home/cbwinslow/CascadeProjects"]="$PROJECTS_STORAGE/active/work"
        ["/home/cbwinslow/devops-testing"]="$PROJECTS_STORAGE/active/devops"
    )
    
    for source_dir in "${!project_dirs[@]}"; do
        dest_dir="${project_dirs[$source_dir]}"
        
        if [[ -d "$source_dir" ]]; then
            dir_size=$(du -sh "$source_dir" | cut -f1)
            print_status "Migrating $source_dir ($dir_size) to $dest_dir"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                print_warning "DRY RUN: Would migrate $source_dir to $dest_dir"
            else
                # Create parent directory if it doesn't exist
                mkdir -p "$dest_dir"
                
                # Use rsync for safe migration with progress
                rsync -av --progress "$source_dir/" "$dest_dir/$(basename "$source_dir")/" 2>&1 | tee -a "$LOG_FILE"
                
                # Verify migration
                if rsync -av --dry-run --checksum "$source_dir/" "$dest_dir/$(basename "$source_dir")/" | grep -q "^[^/]"; then
                    print_error "Migration verification failed for $source_dir"
                else
                    print_status "Migration verified successfully for $source_dir"
                    
                    # Create symlink for backward compatibility
                    if [[ "$FORCE" == "true" ]]; then
                        rm -rf "$source_dir"
                        ln -s "$dest_dir/$(basename "$source_dir")" "$source_dir"
                        print_status "Created symlink: $source_dir -> $dest_dir/$(basename "$source_dir")"
                    fi
                fi
            fi
        else
            print_warning "Source directory $source_dir does not exist, skipping"
        fi
    done
}

# Migrate media files
migrate_media() {
    print_header "MIGRATING MEDIA DIRECTORIES"
    
    declare -A media_dirs=(
        ["/home/cbwinslow/Music"]="$MEDIA_STORAGE/music"
        ["/home/cbwinslow/Videos"]="$MEDIA_STORAGE/videos" 
        ["/home/cbwinslow/Pictures"]="$MEDIA_STORAGE/pictures/personal"
        ["/home/cbwinslow/Downloads"]="$MEDIA_STORAGE/downloads"
    )
    
    for source_dir in "${!media_dirs[@]}"; do
        dest_dir="${media_dirs[$source_dir]}"
        
        if [[ -d "$source_dir" ]]; then
            dir_size=$(du -sh "$source_dir" 2>/dev/null | cut -f1 || echo "0")
            print_status "Migrating $source_dir ($dir_size) to $dest_dir"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                print_warning "DRY RUN: Would migrate $source_dir to $dest_dir"
            else
                mkdir -p "$(dirname "$dest_dir")"
                
                # For Downloads, be more selective - only migrate certain file types
                if [[ "$source_dir" == "/home/cbwinslow/Downloads" ]]; then
                    mkdir -p "$dest_dir"
                    # Migrate archives, installers, and large files
                    find "$source_dir" -type f \( -name "*.zip" -o -name "*.tar.gz" -o -name "*.deb" -o -name "*.rpm" -o -name "*.iso" -o -size +100M \) -exec rsync -av {} "$dest_dir/" \; 2>&1 | tee -a "$LOG_FILE"
                else
                    rsync -av --progress "$source_dir/" "$dest_dir/" 2>&1 | tee -a "$LOG_FILE"
                    
                    # Create symlink for backward compatibility
                    if [[ "$FORCE" == "true" ]]; then
                        rm -rf "$source_dir"
                        ln -s "$dest_dir" "$source_dir"
                        print_status "Created symlink: $source_dir -> $dest_dir"
                    fi
                fi
            fi
        else
            print_warning "Source directory $source_dir does not exist, skipping"
        fi
    done
}

# Create initial backups
create_initial_backups() {
    print_header "CREATING INITIAL SYSTEM BACKUPS"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would create initial backups"
        return
    fi
    
    # Backup important configuration files
    config_backup_dir="$BACKUPS_STORAGE/configs/$(date +%Y%m%d)"
    mkdir -p "$config_backup_dir"
    
    # System configs
    sudo cp -r /etc/fstab /etc/hosts /etc/hostname /etc/resolv.conf "$config_backup_dir/" 2>/dev/null || true
    
    # User configs
    cp -r ~/.bashrc ~/.zshrc ~/.gitconfig ~/.ssh/config "$config_backup_dir/" 2>/dev/null || true
    
    # Docker configs if they exist
    [[ -d ~/.docker ]] && cp -r ~/.docker "$config_backup_dir/" 2>/dev/null || true
    
    print_status "Configuration backups created in $config_backup_dir"
    
    # Create a home directory backup (selective)
    home_backup_dir="$BACKUPS_STORAGE/home/$(date +%Y%m%d)"
    mkdir -p "$home_backup_dir"
    
    # Backup important home directories (excluding large media/project dirs we just moved)
    rsync -av --exclude="Projects" --exclude="dev" --exclude="CascadeProjects" \
              --exclude="Downloads" --exclude="Music" --exclude="Videos" \
              --exclude="Pictures" --exclude=".cache" --exclude="snap" \
              --exclude="anaconda3" --exclude="quantum_env" \
              /home/cbwinslow/ "$home_backup_dir/" 2>&1 | tee -a "$LOG_FILE"
    
    print_status "Selective home backup created in $home_backup_dir"
}

# Generate migration report
generate_report() {
    print_header "GENERATING MIGRATION REPORT"
    
    report_file="$HOME/system-maintenance-automation/logs/lvm_migration_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "LVM Storage Migration Report"
        echo "Generated: $(date)"
        echo "========================================="
        echo ""
        
        echo "STORAGE USAGE AFTER MIGRATION:"
        df -h | grep storage
        echo ""
        
        echo "DIRECTORY STRUCTURE:"
        echo "Projects Storage:"
        find "$PROJECTS_STORAGE" -maxdepth 2 -type d 2>/dev/null || echo "Not accessible"
        echo ""
        echo "Media Storage:"
        find "$MEDIA_STORAGE" -maxdepth 2 -type d 2>/dev/null || echo "Not accessible"
        echo ""
        echo "Backups Storage:"
        find "$BACKUPS_STORAGE" -maxdepth 2 -type d 2>/dev/null || echo "Not accessible"
        echo ""
        
        echo "SYMBOLIC LINKS CREATED:"
        find /home/cbwinslow -maxdepth 1 -type l 2>/dev/null || echo "None found"
        echo ""
        
        echo "MIGRATION LOG LOCATION:"
        echo "$LOG_FILE"
        
    } > "$report_file"
    
    print_status "Migration report saved to: $report_file"
    cat "$report_file"
}

# Main execution
main() {
    print_header "LVM STORAGE MIGRATION STARTING"
    
    # Create logs directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "Migration started with DRY_RUN=$DRY_RUN, FORCE=$FORCE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "RUNNING IN DRY RUN MODE - NO ACTUAL CHANGES WILL BE MADE"
    fi
    
    if [[ "$FORCE" == "true" ]]; then
        print_warning "RUNNING IN FORCE MODE - WILL REPLACE ORIGINAL DIRS WITH SYMLINKS"
    fi
    
    # Execute migration steps
    check_prerequisites
    calculate_sizes
    create_directory_structure
    migrate_projects
    migrate_media
    create_initial_backups
    generate_report
    
    print_header "MIGRATION COMPLETED SUCCESSFULLY"
    print_status "Check the report and logs for details"
    print_status "Log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "false" && "$FORCE" == "false" ]]; then
        print_warning "Original directories are preserved. Run with 'force' parameter to replace with symlinks."
        print_status "Example: ./migrate_to_lvm_storage.sh false force"
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi


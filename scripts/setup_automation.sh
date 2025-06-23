#!/bin/bash
# System Maintenance Automation Setup Script
# Configures cron jobs, maintenance windows, logging rotation, and email alerts

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
AUTOMATION_CONFIG="$BASE_DIR/config/automation_config.json"
LOG_FILE="$BASE_DIR/logs/automation_setup.log"
CRON_BACKUP_DIR="$BASE_DIR/config/cron_backup"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$CRON_BACKUP_DIR"

# Logging function
log() {
    local level="$1"
    shift
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

# Print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_status "$YELLOW" "WARNING: Running as root. Some operations will have system-wide effects."
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Load or create automation configuration
load_automation_config() {
    if [[ ! -f "$AUTOMATION_CONFIG" ]]; then
        log "INFO" "Creating default automation configuration"
        mkdir -p "$(dirname "$AUTOMATION_CONFIG")"
        
        cat > "$AUTOMATION_CONFIG" << 'EOF'
{
  "monitoring": {
    "enabled": true,
    "interval_minutes": 5,
    "cron_schedule": "*/5 * * * *"
  },
  "maintenance": {
    "enabled": true,
    "daily_time": "02:00",
    "weekly_day": "sunday",
    "weekly_time": "03:00",
    "monthly_day": 1,
    "monthly_time": "04:00"
  },
  "reporting": {
    "enabled": true,
    "daily_time": "06:00",
    "weekly_time": "07:00",
    "monthly_time": "08:00"
  },
  "log_rotation": {
    "enabled": true,
    "max_size_mb": 100,
    "max_age_days": 30,
    "compress": true
  },
  "email_alerts": {
    "enabled": false,
    "smtp_server": "localhost",
    "smtp_port": 587,
    "username": "",
    "password": "",
    "from_email": "system@localhost",
    "to_emails": ["admin@localhost"],
    "alert_types": ["critical", "warning"]
  },
  "maintenance_windows": {
    "prefer_low_usage": true,
    "allowed_hours": [1, 2, 3, 4, 5],
    "blocked_days": [],
    "emergency_override": true
  },
  "backup": {
    "config_backup": true,
    "log_backup": true,
    "report_backup": true,
    "retention_days": 90
  }
}
EOF
        print_status "$GREEN" "Created automation configuration: $AUTOMATION_CONFIG"
    fi
    
    # Load configuration
    if command -v jq &> /dev/null; then
        MONITORING_ENABLED=$(jq -r '.monitoring.enabled' "$AUTOMATION_CONFIG")
        MONITORING_INTERVAL=$(jq -r '.monitoring.cron_schedule' "$AUTOMATION_CONFIG")
        MAINTENANCE_ENABLED=$(jq -r '.maintenance.enabled' "$AUTOMATION_CONFIG")
        DAILY_TIME=$(jq -r '.maintenance.daily_time' "$AUTOMATION_CONFIG")
        WEEKLY_TIME=$(jq -r '.maintenance.weekly_time' "$AUTOMATION_CONFIG")
        WEEKLY_DAY=$(jq -r '.maintenance.weekly_day' "$AUTOMATION_CONFIG")
        MONTHLY_TIME=$(jq -r '.maintenance.monthly_time' "$AUTOMATION_CONFIG")
        MONTHLY_DAY=$(jq -r '.maintenance.monthly_day' "$AUTOMATION_CONFIG")
        REPORTING_ENABLED=$(jq -r '.reporting.enabled' "$AUTOMATION_CONFIG")
        DAILY_REPORT_TIME=$(jq -r '.reporting.daily_time' "$AUTOMATION_CONFIG")
        WEEKLY_REPORT_TIME=$(jq -r '.reporting.weekly_time' "$AUTOMATION_CONFIG")
        MONTHLY_REPORT_TIME=$(jq -r '.reporting.monthly_time' "$AUTOMATION_CONFIG")
    else
        print_status "$YELLOW" "jq not available, using default values"
        MONITORING_ENABLED="true"
        MONITORING_INTERVAL="*/5 * * * *"
        MAINTENANCE_ENABLED="true"
        DAILY_TIME="02:00"
        WEEKLY_TIME="03:00"
        WEEKLY_DAY="sunday"
        MONTHLY_TIME="04:00"
        MONTHLY_DAY="1"
        REPORTING_ENABLED="true"
        DAILY_REPORT_TIME="06:00"
        WEEKLY_REPORT_TIME="07:00"
        MONTHLY_REPORT_TIME="08:00"
    fi
}

# Backup current crontab
backup_crontab() {
    log "INFO" "Backing up current crontab"
    local backup_file="$CRON_BACKUP_DIR/crontab_backup_$(date +%Y%m%d_%H%M%S).txt"
    
    if crontab -l > "$backup_file" 2>/dev/null; then
        print_status "$GREEN" "Crontab backed up to: $backup_file"
    else
        log "WARN" "No existing crontab to backup"
        touch "$backup_file"
    fi
}

# Convert day name to number for cron
get_day_number() {
    case "${1,,}" in
        sunday|sun) echo "0" ;;
        monday|mon) echo "1" ;;
        tuesday|tue) echo "2" ;;
        wednesday|wed) echo "3" ;;
        thursday|thu) echo "4" ;;
        friday|fri) echo "5" ;;
        saturday|sat) echo "6" ;;
        *) echo "0" ;;
    esac
}

# Setup system monitoring cron job
setup_monitoring_cron() {
    if [[ "$MONITORING_ENABLED" != "true" ]]; then
        log "INFO" "System monitoring disabled in configuration"
        return 0
    fi
    
    log "INFO" "Setting up system monitoring cron job"
    
    local monitor_script="$SCRIPT_DIR/monitor_system.py"
    local cron_entry="$MONITORING_INTERVAL cd $BASE_DIR && /usr/bin/python3 $monitor_script --daemon >> $BASE_DIR/logs/monitor_cron.log 2>&1"
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "$monitor_script" || true; echo "$cron_entry") | crontab -
    
    print_status "$GREEN" "System monitoring scheduled: $MONITORING_INTERVAL"
}

# Setup maintenance cron jobs
setup_maintenance_cron() {
    if [[ "$MAINTENANCE_ENABLED" != "true" ]]; then
        log "INFO" "Maintenance tasks disabled in configuration"
        return 0
    fi
    
    log "INFO" "Setting up maintenance cron jobs"
    
    local maintenance_script="$SCRIPT_DIR/maintenance_tasks.sh"
    
    # Parse time for daily maintenance
    local daily_hour="${DAILY_TIME%:*}"
    local daily_minute="${DAILY_TIME#*:}"
    local daily_cron="$daily_minute $daily_hour * * * cd $BASE_DIR && $maintenance_script >> $BASE_DIR/logs/maintenance_cron.log 2>&1"
    
    # Parse time for weekly maintenance
    local weekly_hour="${WEEKLY_TIME%:*}"
    local weekly_minute="${WEEKLY_TIME#*:}"
    local weekly_day_num=$(get_day_number "$WEEKLY_DAY")
    local weekly_cron="$weekly_minute $weekly_hour * * $weekly_day_num cd $BASE_DIR && $maintenance_script >> $BASE_DIR/logs/maintenance_cron.log 2>&1"
    
    # Parse time for monthly maintenance
    local monthly_hour="${MONTHLY_TIME%:*}"
    local monthly_minute="${MONTHLY_TIME#*:}"
    local monthly_cron="$monthly_minute $monthly_hour $MONTHLY_DAY * * cd $BASE_DIR && $maintenance_script >> $BASE_DIR/logs/maintenance_cron.log 2>&1"
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "$maintenance_script" || true; 
     echo "# Daily maintenance"; echo "$daily_cron";
     echo "# Weekly maintenance"; echo "$weekly_cron";
     echo "# Monthly maintenance"; echo "$monthly_cron") | crontab -
    
    print_status "$GREEN" "Maintenance tasks scheduled:"
    print_status "$GREEN" "  Daily: $DAILY_TIME"
    print_status "$GREEN" "  Weekly: $WEEKLY_DAY at $WEEKLY_TIME"
    print_status "$GREEN" "  Monthly: Day $MONTHLY_DAY at $MONTHLY_TIME"
}

# Setup reporting cron jobs
setup_reporting_cron() {
    if [[ "$REPORTING_ENABLED" != "true" ]]; then
        log "INFO" "Reporting disabled in configuration"
        return 0
    fi
    
    log "INFO" "Setting up reporting cron jobs"
    
    local report_script="$SCRIPT_DIR/generate_reports.py"
    
    # Daily reports
    local daily_hour="${DAILY_REPORT_TIME%:*}"
    local daily_minute="${DAILY_REPORT_TIME#*:}"
    local daily_cron="$daily_minute $daily_hour * * * cd $BASE_DIR && /usr/bin/python3 $report_script --type daily >> $BASE_DIR/logs/reports_cron.log 2>&1"
    
    # Weekly reports (Mondays)
    local weekly_hour="${WEEKLY_REPORT_TIME%:*}"
    local weekly_minute="${WEEKLY_REPORT_TIME#*:}"
    local weekly_cron="$weekly_minute $weekly_hour * * 1 cd $BASE_DIR && /usr/bin/python3 $report_script --type weekly >> $BASE_DIR/logs/reports_cron.log 2>&1"
    
    # Monthly reports (1st of month)
    local monthly_hour="${MONTHLY_REPORT_TIME%:*}"
    local monthly_minute="${MONTHLY_REPORT_TIME#*:}"
    local monthly_cron="$monthly_minute $monthly_hour 1 * * cd $BASE_DIR && /usr/bin/python3 $report_script --type monthly >> $BASE_DIR/logs/reports_cron.log 2>&1"
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "$report_script" || true; 
     echo "# Daily reports"; echo "$daily_cron";
     echo "# Weekly reports"; echo "$weekly_cron";
     echo "# Monthly reports"; echo "$monthly_cron") | crontab -
    
    print_status "$GREEN" "Reporting scheduled:"
    print_status "$GREEN" "  Daily: $DAILY_REPORT_TIME"
    print_status "$GREEN" "  Weekly: Mondays at $WEEKLY_REPORT_TIME"
    print_status "$GREEN" "  Monthly: 1st at $MONTHLY_REPORT_TIME"
}

# Setup log rotation
setup_log_rotation() {
    log "INFO" "Setting up log rotation"
    
    local logrotate_config="$BASE_DIR/config/system-maintenance-logrotate"
    
    cat > "$logrotate_config" << EOF
# Log rotation for system maintenance automation
$BASE_DIR/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 $(whoami) $(id -gn)
    postrotate
        # Optional: restart services if needed
    endscript
}

# Rotate database files if they get too large
$BASE_DIR/logs/*.db {
    weekly
    missingok
    rotate 4
    compress
    delaycompress
    notifempty
    size 100M
    copytruncate
}
EOF
    
    # Add system-wide logrotate if running as root
    if [[ $EUID -eq 0 ]]; then
        ln -sf "$logrotate_config" /etc/logrotate.d/system-maintenance
        print_status "$GREEN" "System-wide log rotation configured"
    else
        # Setup user cron for log rotation
        local logrotate_cron="0 2 * * * /usr/sbin/logrotate $logrotate_config --state $BASE_DIR/logs/logrotate.state >> $BASE_DIR/logs/logrotate.log 2>&1"
        (crontab -l 2>/dev/null | grep -v "logrotate.*system-maintenance" || true; echo "$logrotate_cron") | crontab -
        print_status "$GREEN" "User-level log rotation configured"
    fi
}

# Setup email alerts configuration
setup_email_alerts() {
    local email_config_file="$BASE_DIR/config/email_config.json"
    
    if [[ ! -f "$email_config_file" ]]; then
        log "INFO" "Creating email configuration template"
        
        cat > "$email_config_file" << 'EOF'
{
  "enabled": false,
  "smtp_server": "smtp.gmail.com",
  "smtp_port": 587,
  "use_tls": true,
  "username": "your-email@gmail.com",
  "password": "your-app-password",
  "from_email": "system-monitor@localhost",
  "to_emails": [
    "admin@localhost"
  ],
  "alert_levels": ["critical", "warning"],
  "subject_prefix": "[SYSTEM-ALERT]",
  "rate_limit": {
    "max_emails_per_hour": 10,
    "cooldown_minutes": 15
  }
}
EOF
        print_status "$YELLOW" "Email configuration template created: $email_config_file"
        print_status "$YELLOW" "Please edit this file to configure email alerts"
    fi
}

# Create systemd service (if systemd is available)
setup_systemd_service() {
    if ! command -v systemctl &> /dev/null; then
        log "INFO" "systemd not available, skipping service setup"
        return 0
    fi
    
    log "INFO" "Setting up systemd service"
    
    local service_file="$BASE_DIR/config/system-maintenance.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=System Maintenance Automation
After=network.target

[Service]
Type=oneshot
User=$(whoami)
Group=$(id -gn)
WorkingDirectory=$BASE_DIR
ExecStart=$SCRIPT_DIR/maintenance_tasks.sh
StandardOutput=append:$BASE_DIR/logs/systemd.log
StandardError=append:$BASE_DIR/logs/systemd.log

[Install]
WantedBy=multi-user.target
EOF
    
    # Create timer file
    local timer_file="$BASE_DIR/config/system-maintenance.timer"
    
    cat > "$timer_file" << EOF
[Unit]
Description=Run system maintenance daily
Requires=system-maintenance.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    if [[ $EUID -eq 0 ]]; then
        # Install system-wide
        cp "$service_file" /etc/systemd/system/
        cp "$timer_file" /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable system-maintenance.timer
        print_status "$GREEN" "systemd service and timer installed"
    else
        print_status "$YELLOW" "systemd service files created in $BASE_DIR/config/"
        print_status "$YELLOW" "Run as root to install system-wide"
    fi
}

# Install Python dependencies
install_python_dependencies() {
    log "INFO" "Checking Python dependencies"
    
    local requirements_file="$BASE_DIR/requirements.txt"
    
    if [[ ! -f "$requirements_file" ]]; then
        cat > "$requirements_file" << 'EOF'
psutil>=5.8.0
pandas>=1.3.0
matplotlib>=3.3.0
seaborn>=0.11.0
sqlite3
EOF
    fi
    
    # Check if pip is available
    if command -v pip3 &> /dev/null; then
        print_status "$BLUE" "Installing Python dependencies..."
        pip3 install --user -r "$requirements_file" || {
            print_status "$YELLOW" "Warning: Failed to install some Python dependencies"
            print_status "$YELLOW" "You may need to install them manually"
        }
    else
        print_status "$YELLOW" "pip3 not available. Please install Python dependencies manually:"
        cat "$requirements_file"
    fi
}

# Create startup script
create_startup_script() {
    local startup_script="$BASE_DIR/start_monitoring.sh"
    
    cat > "$startup_script" << EOF
#!/bin/bash
# System Maintenance Automation Startup Script
# Run this script to start all monitoring and maintenance tasks

BASE_DIR="$BASE_DIR"

echo "Starting System Maintenance Automation..."

# Run initial system check
echo "Running initial system monitoring..."
\$BASE_DIR/scripts/monitor_system.py

# Generate initial report
echo "Generating initial report..."
\$BASE_DIR/scripts/generate_reports.py --type daily

echo "System Maintenance Automation started successfully!"
echo "Check logs in: \$BASE_DIR/logs/"
echo "Check reports in: \$BASE_DIR/reports/"
EOF
    
    chmod +x "$startup_script"
    print_status "$GREEN" "Startup script created: $startup_script"
}

# Verify installation
verify_installation() {
    log "INFO" "Verifying installation"
    
    local errors=0
    
    # Check scripts
    local scripts=("monitor_system.py" "maintenance_tasks.sh" "generate_reports.py")
    for script in "${scripts[@]}"; do
        if [[ -f "$SCRIPT_DIR/$script" ]]; then
            if [[ -x "$SCRIPT_DIR/$script" ]]; then
                print_status "$GREEN" "✓ $script is executable"
            else
                print_status "$RED" "✗ $script is not executable"
                chmod +x "$SCRIPT_DIR/$script"
                print_status "$GREEN" "✓ Fixed permissions for $script"
            fi
        else
            print_status "$RED" "✗ $script not found"
            ((errors++))
        fi
    done
    
    # Check directories
    local dirs=("logs" "reports" "config")
    for dir in "${dirs[@]}"; do
        if [[ -d "$BASE_DIR/$dir" ]]; then
            print_status "$GREEN" "✓ Directory $dir exists"
        else
            print_status "$RED" "✗ Directory $dir missing"
            mkdir -p "$BASE_DIR/$dir"
            print_status "$GREEN" "✓ Created directory $dir"
        fi
    done
    
    # Check crontab
    if crontab -l | grep -q "monitor_system.py\|maintenance_tasks.sh\|generate_reports.py"; then
        print_status "$GREEN" "✓ Cron jobs are configured"
    else
        print_status "$YELLOW" "⚠ No cron jobs found (may not be configured yet)"
    fi
    
    # Test Python dependencies
    if python3 -c "import psutil, pandas, matplotlib, sqlite3" 2>/dev/null; then
        print_status "$GREEN" "✓ Python dependencies available"
    else
        print_status "$YELLOW" "⚠ Some Python dependencies missing"
    fi
    
    return $errors
}

# Show current configuration
show_configuration() {
    print_status "$BLUE" "=== CURRENT CONFIGURATION ==="
    
    if [[ -f "$AUTOMATION_CONFIG" ]]; then
        if command -v jq &> /dev/null; then
            echo "Monitoring: $(jq -r '.monitoring.enabled' "$AUTOMATION_CONFIG")"
            echo "Maintenance: $(jq -r '.maintenance.enabled' "$AUTOMATION_CONFIG")"
            echo "Reporting: $(jq -r '.reporting.enabled' "$AUTOMATION_CONFIG")"
            echo "Daily maintenance: $(jq -r '.maintenance.daily_time' "$AUTOMATION_CONFIG")"
            echo "Weekly maintenance: $(jq -r '.maintenance.weekly_day' "$AUTOMATION_CONFIG") at $(jq -r '.maintenance.weekly_time' "$AUTOMATION_CONFIG")"
        else
            print_status "$YELLOW" "Install jq to see detailed configuration"
        fi
    fi
    
    echo
    print_status "$BLUE" "=== CURRENT CRON JOBS ==="
    crontab -l 2>/dev/null | grep -E "(monitor_system|maintenance_tasks|generate_reports)" || echo "No automation cron jobs found"
    
    echo
}

# Main setup function
main_setup() {
    print_status "$BLUE" "=== SYSTEM MAINTENANCE AUTOMATION SETUP ==="
    echo
    
    # Check prerequisites
    check_root
    
    # Load configuration
    load_automation_config
    
    # Show current configuration
    show_configuration
    
    # Ask for confirmation
    echo
    read -p "Proceed with automation setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "$YELLOW" "Setup cancelled"
        exit 0
    fi
    
    # Backup existing crontab
    backup_crontab
    
    # Install dependencies
    install_python_dependencies
    
    # Setup components
    setup_monitoring_cron
    setup_maintenance_cron
    setup_reporting_cron
    setup_log_rotation
    setup_email_alerts
    setup_systemd_service
    
    # Create utility scripts
    create_startup_script
    
    # Make scripts executable
    chmod +x "$SCRIPT_DIR"/*.py 2>/dev/null || true
    chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
    
    # Verify installation
    echo
    print_status "$BLUE" "=== VERIFICATION ==="
    if verify_installation; then
        print_status "$GREEN" "Setup completed successfully!"
    else
        print_status "$YELLOW" "Setup completed with some issues"
    fi
    
    echo
    print_status "$BLUE" "=== NEXT STEPS ==="
    echo "1. Review configuration files in: $BASE_DIR/config/"
    echo "2. Test the monitoring: $SCRIPT_DIR/monitor_system.py"
    echo "3. Test maintenance: $SCRIPT_DIR/maintenance_tasks.sh --dry-run"
    echo "4. Generate test report: $SCRIPT_DIR/generate_reports.py"
    echo "5. Configure email alerts in: $BASE_DIR/config/email_config.json"
    echo "6. Monitor logs in: $BASE_DIR/logs/"
    echo
}

# Command line interface
case "${1:-setup}" in
    setup)
        main_setup
        ;;
    verify)
        verify_installation
        ;;
    show-config)
        show_configuration
        ;;
    remove)
        print_status "$YELLOW" "Removing automation cron jobs..."
        crontab -l 2>/dev/null | grep -v -E "(monitor_system|maintenance_tasks|generate_reports)" | crontab -
        print_status "$GREEN" "Cron jobs removed"
        ;;
    help|--help|-h)
        cat << EOF
Usage: $0 [COMMAND]

Commands:
    setup       Setup automation framework (default)
    verify      Verify installation
    show-config Show current configuration
    remove      Remove cron jobs
    help        Show this help

Configuration file: $AUTOMATION_CONFIG
Log file: $LOG_FILE
EOF
        ;;
    *)
        print_status "$RED" "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac


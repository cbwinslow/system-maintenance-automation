# System Maintenance Automation Framework

A comprehensive automation framework for system monitoring, maintenance, and reporting. This system provides automated disk cleanup, system health monitoring, trend analysis, and detailed reporting capabilities.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Components](#components)
- [Automation Setup](#automation-setup)
- [Monitoring and Alerts](#monitoring-and-alerts)
- [Reports](#reports)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## Overview

The System Maintenance Automation Framework consists of four main components:

1. **System Monitoring** (`monitor_system.py`) - Tracks disk usage, inode usage, filesystem health, and system metrics
2. **Maintenance Tasks** (`maintenance_tasks.sh`) - Automated cleanup, log rotation, package updates, and backup verification
3. **Report Generation** (`generate_reports.py`) - Creates daily, weekly, and monthly reports with trend analysis
4. **Automation Framework** (`setup_automation.sh`) - Configures cron jobs, maintenance windows, and email alerts

## Features

### System Monitoring
- **Disk Usage Tracking**: Monitor disk usage trends across multiple filesystems
- **Inode Monitoring**: Track inode usage to prevent filesystem exhaustion
- **Filesystem Health Checks**: Automated filesystem integrity verification
- **System Metrics**: CPU, memory, and load average monitoring
- **Threshold Alerts**: Configurable thresholds with email notifications
- **Historical Data**: SQLite database for trend analysis

### Maintenance Tasks
- **Temporary File Cleanup**: Automated removal of old temporary files
- **Log Rotation**: Smart log rotation with compression
- **Package Management**: Automated package list updates
- **Backup Verification**: Integrity checks for backup files
- **Maintenance Windows**: Configurable maintenance schedules
- **Safety Features**: Dry-run mode and lock file protection

### Reporting System
- **Daily Reports**: 24-hour system health summaries
- **Weekly Reports**: 7-day trend analysis and maintenance effectiveness
- **Monthly Reports**: Comprehensive 30-day analysis with recommendations
- **Visual Charts**: Automated generation of trend charts and graphs
- **Cleanup Effectiveness**: Analysis of maintenance task performance
- **Actionable Recommendations**: Data-driven suggestions for system optimization

### Automation Framework
- **Cron Job Management**: Automated scheduling configuration
- **Email Alerts**: SMTP-based notification system
- **Log Rotation**: Automated log management
- **Systemd Integration**: Optional systemd service and timer setup
- **Configuration Management**: JSON-based configuration system

## Installation

### Prerequisites

- Python 3.6 or higher
- Bash shell
- SQLite3
- Required Python packages: `psutil`, `pandas`, `matplotlib`, `seaborn`

### Quick Install

1. Clone or download the system maintenance automation framework:
```bash
# If you haven't already, navigate to the system-maintenance-automation directory
cd ~/system-maintenance-automation
```

2. Run the setup automation script:
```bash
./scripts/setup_automation.sh
```

3. Install Python dependencies:
```bash
pip3 install --user psutil pandas matplotlib seaborn
```

### Manual Installation

1. Create the directory structure:
```bash
mkdir -p ~/system-maintenance-automation/{scripts,logs,reports,config}
```

2. Copy all scripts to the `scripts` directory
3. Make scripts executable:
```bash
chmod +x scripts/*.py scripts/*.sh
```

4. Install Python dependencies:
```bash
pip3 install --user psutil pandas matplotlib seaborn
```

## Configuration

### Main Configuration Files

#### `config/monitor_config.json`
Controls system monitoring behavior:
```json
{
  "disk_usage_threshold": 85,
  "inode_usage_threshold": 85,
  "email_alerts": {
    "enabled": false,
    "smtp_server": "localhost",
    "smtp_port": 587,
    "from_email": "system@localhost",
    "to_emails": ["admin@localhost"]
  },
  "monitored_paths": ["/", "/home", "/var", "/tmp"],
  "check_interval": 300,
  "retention_days": 30
}
```

#### `config/maintenance_config.json`
Controls maintenance task behavior:
```json
{
  "cleanup_temp_files": true,
  "rotate_logs": true,
  "update_packages": true,
  "verify_backups": true,
  "temp_file_age_days": 7,
  "log_retention_days": 30,
  "notification_email": "",
  "temp_dirs": ["/tmp", "/var/tmp", "/var/cache/apt/archives", "/home/cbwinslow/.cache"],
  "log_dirs": ["/var/log", "/home/cbwinslow/.local/share/logs"],
  "backup_dirs": ["/home/cbwinslow/backups", "/var/backups"]
}
```

#### `config/automation_config.json`
Controls automation scheduling:
```json
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
  }
}
```

## Usage

### Running Components Individually

#### System Monitoring
```bash
# Run a single monitoring cycle
./scripts/monitor_system.py

# Run in daemon mode (for cron)
./scripts/monitor_system.py --daemon
```

#### Maintenance Tasks
```bash
# Run all maintenance tasks
./scripts/maintenance_tasks.sh

# Dry run (show what would be done)
./scripts/maintenance_tasks.sh --dry-run

# Run specific tasks only
./scripts/maintenance_tasks.sh --cleanup-only
./scripts/maintenance_tasks.sh --logs-only
./scripts/maintenance_tasks.sh --packages-only
./scripts/maintenance_tasks.sh --backups-only
```

#### Report Generation
```bash
# Generate daily report
./scripts/generate_reports.py --type daily

# Generate weekly report
./scripts/generate_reports.py --type weekly

# Generate monthly report
./scripts/generate_reports.py --type monthly

# Generate all reports
./scripts/generate_reports.py --type all
```

### Automation Management

#### Setup Automation
```bash
# Initial setup
./scripts/setup_automation.sh setup

# Verify installation
./scripts/setup_automation.sh verify

# Show current configuration
./scripts/setup_automation.sh show-config

# Remove automation
./scripts/setup_automation.sh remove
```

#### Quick Start
```bash
# Start monitoring immediately
./start_monitoring.sh
```

## Components

### 1. System Monitor (`monitor_system.py`)

**Purpose**: Continuous system health monitoring and alerting

**Key Features**:
- Disk usage tracking with configurable thresholds
- Inode usage monitoring
- Filesystem health checks using read-only fsck operations
- System metrics collection (CPU, memory, load average)
- SQLite database storage for historical data
- Email alerting for threshold violations
- Automatic data retention management

**Database Schema**:
- `disk_usage`: Historical disk usage data
- `inode_usage`: Historical inode usage data
- `system_health`: CPU, memory, and load metrics
- `filesystem_health`: Filesystem status and error counts
- `alerts`: Alert history with resolution tracking

### 2. Maintenance Tasks (`maintenance_tasks.sh`)

**Purpose**: Automated system maintenance and cleanup

**Key Features**:
- Temporary file cleanup with age-based criteria
- Log rotation for large files with compression
- Package list updates (APT, Snap, Flatpak)
- Backup verification with integrity testing
- Privilege detection for system vs. user operations
- Lock file protection against concurrent execution
- Comprehensive logging and reporting

**Safety Features**:
- Dry-run mode for testing
- Lock file prevention of concurrent runs
- Configurable exclusion patterns
- Backup verification before cleanup
- Error handling and rollback capabilities

### 3. Report Generator (`generate_reports.py`)

**Purpose**: Automated report generation with trend analysis

**Key Features**:
- Daily system health summaries
- Weekly maintenance effectiveness analysis
- Monthly comprehensive reports with recommendations
- Automated chart generation using matplotlib/seaborn
- Trend analysis across multiple time periods
- Cleanup effectiveness tracking
- Actionable recommendations based on data patterns

**Report Types**:
- **Daily**: 24-hour summary with recent alerts
- **Weekly**: 7-day trends with maintenance effectiveness
- **Monthly**: 30-day comprehensive analysis with capacity planning

### 4. Automation Framework (`setup_automation.sh`)

**Purpose**: Complete automation setup and configuration

**Key Features**:
- Automated cron job configuration
- Systemd service and timer setup
- Log rotation configuration
- Email alert configuration
- Dependency installation
- Installation verification
- Configuration backup and restore

## Automation Setup

### Cron Job Scheduling

The automation framework sets up the following cron jobs:

```bash
# System monitoring every 5 minutes
*/5 * * * * cd /home/cbwinslow/system-maintenance-automation && /usr/bin/python3 scripts/monitor_system.py --daemon

# Daily maintenance at 2:00 AM
0 2 * * * cd /home/cbwinslow/system-maintenance-automation && scripts/maintenance_tasks.sh

# Weekly maintenance on Sunday at 3:00 AM
0 3 * * 0 cd /home/cbwinslow/system-maintenance-automation && scripts/maintenance_tasks.sh

# Monthly maintenance on the 1st at 4:00 AM
0 4 1 * * cd /home/cbwinslow/system-maintenance-automation && scripts/maintenance_tasks.sh

# Daily reports at 6:00 AM
0 6 * * * cd /home/cbwinslow/system-maintenance-automation && /usr/bin/python3 scripts/generate_reports.py --type daily

# Weekly reports on Monday at 7:00 AM
0 7 * * 1 cd /home/cbwinslow/system-maintenance-automation && /usr/bin/python3 scripts/generate_reports.py --type weekly

# Monthly reports on the 1st at 8:00 AM
0 8 1 * * cd /home/cbwinslow/system-maintenance-automation && /usr/bin/python3 scripts/generate_reports.py --type monthly
```

### Log Rotation

Automated log rotation is configured with:
- Daily rotation for log files
- 30-day retention period
- Compression for rotated logs
- Size-based rotation for database files

## Monitoring and Alerts

### Threshold Configuration

Default thresholds can be configured in `config/monitor_config.json`:

- **Disk Usage Warning**: 85%
- **Disk Usage Critical**: 95%
- **Inode Usage Warning**: 85%
- **Inode Usage Critical**: 95%

### Email Alerts

Configure email alerts in `config/email_config.json`:

```json
{
  "enabled": true,
  "smtp_server": "smtp.gmail.com",
  "smtp_port": 587,
  "use_tls": true,
  "username": "your-email@gmail.com",
  "password": "your-app-password",
  "from_email": "system-monitor@yourdomain.com",
  "to_emails": ["admin@yourdomain.com"],
  "alert_levels": ["critical", "warning"]
}
```

### Alert Types

- **Disk Usage**: Triggered when disk usage exceeds thresholds
- **Inode Usage**: Triggered when inode usage exceeds thresholds
- **Filesystem Errors**: Triggered when filesystem errors are detected
- **System Health**: Triggered for extreme CPU/memory usage (configurable)

## Reports

### Report Structure

Reports are organized in the following directory structure:
```
reports/
├── daily/
│   └── 2024-01-15/
│       ├── daily_report.txt
│       └── charts/
│           ├── system_health.png
│           └── disk_usage.png
├── weekly/
│   └── 2024-W03/
│       ├── weekly_report.txt
│       └── charts/
└── monthly/
    └── 2024-01/
        ├── monthly_report.txt
        └── charts/
```

### Report Content

#### Daily Reports
- Executive summary of last 24 hours
- Cleanup effectiveness analysis
- System health trends (7-day context)
- Recent alerts and their status
- Actionable recommendations

#### Weekly Reports
- Weekly cleanup summary
- System trends (30-day context)
- Alert analysis by severity and type
- Most frequent issues
- Weekly recommendations

#### Monthly Reports
- Monthly statistics and metrics
- Long-term trend analysis (90-day context)
- Cleanup effectiveness rating
- Capacity planning recommendations
- Alert pattern analysis
- Monthly optimization suggestions

### Chart Generation

Automated charts include:
- System health trends (CPU, memory, load average)
- Disk usage trends by filesystem
- Alert frequency over time
- Cleanup effectiveness metrics

## Troubleshooting

### Common Issues

#### 1. Python Dependencies Missing
```bash
# Install required packages
pip3 install --user psutil pandas matplotlib seaborn

# Verify installation
python3 -c "import psutil, pandas, matplotlib, seaborn; print('All dependencies available')"
```

#### 2. Permission Issues
```bash
# Make scripts executable
chmod +x scripts/*.py scripts/*.sh

# Check file permissions
ls -la scripts/
```

#### 3. Cron Jobs Not Running
```bash
# Check cron service
systemctl status cron

# View cron logs
grep CRON /var/log/syslog

# Test cron jobs manually
./scripts/monitor_system.py --daemon
```

#### 4. Email Alerts Not Working
```bash
# Test email configuration
python3 -c "
import smtplib
from email.mime.text import MimeText
# Test SMTP connection
"

# Check email logs
tail -f logs/monitor.log | grep -i email
```

#### 5. Database Issues
```bash
# Check database file
ls -la logs/system_metrics.db

# Verify database integrity
sqlite3 logs/system_metrics.db ".schema"
```

### Log Files

Monitor these log files for troubleshooting:

- `logs/monitor.log` - System monitoring activities
- `logs/maintenance.log` - Maintenance task execution
- `logs/reports.log` - Report generation activities
- `logs/automation_setup.log` - Automation setup and configuration
- `logs/*_cron.log` - Cron job execution logs

### Verification Commands

```bash
# Verify all components
./scripts/setup_automation.sh verify

# Test individual components
./scripts/monitor_system.py
./scripts/maintenance_tasks.sh --dry-run
./scripts/generate_reports.py --type daily

# Check configuration
./scripts/setup_automation.sh show-config
```

## Advanced Configuration

### Custom Monitoring Paths

Edit `config/monitor_config.json` to add custom paths:

```json
{
  "monitored_paths": ["/", "/home", "/var", "/tmp", "/opt", "/usr/local"]
}
```

### Custom Cleanup Directories

Edit `config/maintenance_config.json` to add custom cleanup directories:

```json
{
  "temp_dirs": [
    "/tmp",
    "/var/tmp",
    "/var/cache/apt/archives",
    "/home/cbwinslow/.cache",
    "/home/cbwinslow/.local/share/Trash"
  ]
}
```

### Maintenance Windows

Configure specific maintenance windows in `config/automation_config.json`:

```json
{
  "maintenance_windows": {
    "prefer_low_usage": true,
    "allowed_hours": [1, 2, 3, 4, 5],
    "blocked_days": ["saturday"],
    "emergency_override": true
  }
}
```

## Security Considerations

### File Permissions
- Scripts are set to 755 (executable by owner, readable by all)
- Configuration files are set to 644 (readable/writable by owner, readable by group/others)
- Log files are created with 644 permissions
- Database files are created with 644 permissions

### Network Security
- Email authentication uses encrypted connections (TLS)
- SMTP credentials should be stored securely
- Consider using application-specific passwords for email accounts

### System Access
- Scripts detect privilege level and adjust operations accordingly
- System-level operations require root privileges
- User-level operations work with standard user permissions

## Contributing

### Development Guidelines

1. **Code Style**: Follow existing bash and Python conventions
2. **Error Handling**: Include comprehensive error handling and logging
3. **Configuration**: Use JSON configuration files for settings
4. **Documentation**: Update README and inline documentation
5. **Testing**: Include dry-run modes and verification steps

### Adding New Features

1. **Monitoring**: Add new metrics to `monitor_system.py`
2. **Maintenance**: Add new tasks to `maintenance_tasks.sh`
3. **Reporting**: Extend report generation in `generate_reports.py`
4. **Automation**: Update setup scripts as needed

### Testing

```bash
# Test all components
./scripts/setup_automation.sh verify

# Dry run maintenance
./scripts/maintenance_tasks.sh --dry-run

# Generate test reports
./scripts/generate_reports.py --type all

# Check configurations
./scripts/setup_automation.sh show-config
```

## License

This project is provided as-is for educational and operational purposes. Feel free to modify and adapt to your specific needs.

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review log files for error messages
3. Verify configuration files
4. Test individual components manually
5. Check system requirements and dependencies

---

**Note**: This system is designed to be safe and non-destructive by default. Always test in a non-production environment first and use dry-run modes when available.


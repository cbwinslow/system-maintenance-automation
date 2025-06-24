# LVM Storage and Backup - Quick Reference Guide

## 🗄️ **LVM Storage Locations**

### Project Storage (`/mnt/storage/projects/`)
```bash
# Original → New LVM Location
~/CascadeProjects  → /mnt/storage/projects/active/work/CascadeProjects
~/Projects         → /mnt/storage/projects/active/personal/Projects  
~/devops-testing   → /mnt/storage/projects/active/devops/devops-testing
```

### Convenience Symlinks (Easy Access)
```bash
~/CascadeProjects_LVM  → Points to migrated CascadeProjects
~/Projects_LVM         → Points to migrated Projects
~/devops-testing_LVM   → Points to migrated devops-testing
```

### Directory Structure
```
/mnt/storage/
├── projects/           # 150GB - Your development projects
│   ├── active/
│   │   ├── work/       # Work-related projects
│   │   ├── personal/   # Personal projects
│   │   └── devops/     # DevOps and testing projects
│   ├── archive/        # Archived projects
│   └── experiments/    # Experimental projects
├── media/              # 200GB - Media files
│   ├── pictures/
│   ├── music/
│   ├── videos/
│   └── documents/
└── backups/            # 100GB - Automated backups
    ├── system/
    ├── home/
    ├── projects/
    └── databases/
```

## 💾 **Backup System**

### Automated Schedule
- **Daily Backups**: 1:00 AM (automated via cron)
- **Backup Location**: `/mnt/storage/backups/`
- **Log File**: `/home/cbwinslow/system-maintenance-automation/logs/backup_cron.log`

### Manual Backup Commands
```bash
# Run backup manually
/home/cbwinslow/system-maintenance-automation/automated_backup.sh

# Run backup with test configuration
/home/cbwinslow/system-maintenance-automation/automated_backup.sh --test-config

# Check backup logs
tail -f /home/cbwinslow/system-maintenance-automation/logs/backup_cron.log
```

### Backup Configuration
- **Config File**: `/home/cbwinslow/system-maintenance-automation/backup_config.conf`
- **Features**: Incremental backups, retention policies, email notifications

## 📊 **Storage Monitoring**

### Check Storage Usage
```bash
# LVM storage status
df -h /mnt/storage/*

# Detailed LVM information
sudo lvs
sudo vgs
sudo pvs

# LVM storage utilization summary
lsblk /dev/sdb
```

### Current Utilization
```
Projects: 33GB used / 147GB available (24% full)
Media:    3.3MB used / 196GB available (1% full)
Backups:  2.1MB used / 98GB available (1% full)
```

## 🔧 **Management Commands**

### LVM Management
```bash
# Extend logical volume (if needed)
sudo lvextend -L +50G /dev/storage_vg/projects_lv
sudo resize2fs /dev/storage_vg/projects_lv

# Create LVM snapshot for backup
sudo lvcreate -L 10G -s -n projects_snapshot /dev/storage_vg/projects_lv
```

### Backup Management
```bash
# View backup history
ls -la /mnt/storage/backups/home/daily/

# Edit backup configuration
nano /home/cbwinslow/system-maintenance-automation/backup_config.conf

# Test backup script
/home/cbwinslow/system-maintenance-automation/automated_backup.sh --dry-run
```

## 🚨 **Troubleshooting**

### Common Issues
1. **Mount Issues**: Check `/etc/fstab` and remount with `sudo mount -a`
2. **Permission Problems**: Fix with `sudo chown -R cbwinslow:cbwinslow /mnt/storage/`
3. **Backup Failures**: Check logs in `/home/cbwinslow/system-maintenance-automation/logs/`

### Recovery Commands
```bash
# Remount LVM volumes
sudo mount -a

# Check filesystem integrity
sudo fsck /dev/storage_vg/projects_lv

# Activate LVM volume group
sudo vgchange -ay storage_vg
```

## 📁 **File Access Examples**

### Using New LVM Locations
```bash
# Navigate to projects
cd /mnt/storage/projects/active/work/CascadeProjects
cd /mnt/storage/projects/active/personal/Projects

# Using convenience symlinks
cd ~/CascadeProjects_LVM
cd ~/Projects_LVM
```

### Development Workflow
```bash
# Your existing commands work with symlinks
cd ~/Projects_LVM/your-project
git status
code .

# Or use full LVM paths
cd /mnt/storage/projects/active/personal/Projects/your-project
```

## 📅 **Scheduled Tasks**
- **1:00 AM**: Daily LVM backups
- **2:00 AM**: System maintenance tasks
- **3:00 AM**: Weekly maintenance (Sundays)
- **6:00 AM**: Daily reports generation

## 🔐 **Security Notes**
- All original directories preserved during migration
- Automated backups include encryption options (configurable)
- File permissions and ownership maintained
- Complete audit trail in logs

---

**Setup completed**: June 23, 2025  
**Next review**: Schedule monthly storage utilization review  
**Documentation**: See `LVM_MIGRATION_COMPLETION_REPORT.md` for full details


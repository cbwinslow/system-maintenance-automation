#!/usr/bin/env python3
"""
System Monitoring Script
Tracks disk usage trends, inode usage, filesystem health, and alerts on thresholds
"""

import os
import sys
import json
import sqlite3
import smtplib
import subprocess
import psutil
import logging
from datetime import datetime, timedelta
from pathlib import Path
from email.mime.text import MimeText
from email.mime.multipart import MimeMultipart
from typing import Dict, List, Tuple, Optional

# Configuration
CONFIG_FILE = "/home/cbwinslow/system-maintenance-automation/config/monitor_config.json"
DB_FILE = "/home/cbwinslow/system-maintenance-automation/logs/system_metrics.db"
LOG_FILE = "/home/cbwinslow/system-maintenance-automation/logs/monitor.log"

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class SystemMonitor:
    def __init__(self, config_file: str = CONFIG_FILE):
        """Initialize the system monitor with configuration."""
        self.config = self.load_config(config_file)
        self.db_path = DB_FILE
        self.init_database()
    
    def load_config(self, config_file: str) -> Dict:
        """Load configuration from JSON file."""
        default_config = {
            "disk_usage_threshold": 85,  # Percentage
            "inode_usage_threshold": 85,  # Percentage
            "email_alerts": {
                "enabled": False,
                "smtp_server": "localhost",
                "smtp_port": 587,
                "from_email": "system@localhost",
                "to_emails": ["admin@localhost"],
                "password": ""
            },
            "monitored_paths": ["/", "/home", "/var", "/tmp"],
            "check_interval": 300,  # seconds
            "retention_days": 30
        }
        
        try:
            if os.path.exists(config_file):
                with open(config_file, 'r') as f:
                    config = json.load(f)
                # Merge with defaults
                for key, value in default_config.items():
                    if key not in config:
                        config[key] = value
                return config
            else:
                # Create default config file
                os.makedirs(os.path.dirname(config_file), exist_ok=True)
                with open(config_file, 'w') as f:
                    json.dump(default_config, f, indent=2)
                return default_config
        except Exception as e:
            logger.error(f"Error loading config: {e}")
            return default_config
    
    def init_database(self):
        """Initialize SQLite database for storing metrics."""
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            # Disk usage table
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS disk_usage (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                    path TEXT NOT NULL,
                    total_gb REAL,
                    used_gb REAL,
                    free_gb REAL,
                    usage_percent REAL
                )
            ''')
            
            # Inode usage table
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS inode_usage (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                    path TEXT NOT NULL,
                    total_inodes INTEGER,
                    used_inodes INTEGER,
                    free_inodes INTEGER,
                    usage_percent REAL
                )
            ''')
            
            # System health table
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS system_health (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                    cpu_percent REAL,
                    memory_percent REAL,
                    load_avg_1 REAL,
                    load_avg_5 REAL,
                    load_avg_15 REAL
                )
            ''')
            
            # Filesystem health table
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS filesystem_health (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                    path TEXT NOT NULL,
                    filesystem TEXT,
                    status TEXT,
                    errors INTEGER DEFAULT 0
                )
            ''')
            
            # Alerts table
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS alerts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                    alert_type TEXT NOT NULL,
                    severity TEXT NOT NULL,
                    message TEXT NOT NULL,
                    resolved BOOLEAN DEFAULT FALSE
                )
            ''')
            
            conn.commit()
    
    def get_disk_usage(self, path: str) -> Dict:
        """Get disk usage statistics for a given path."""
        try:
            usage = psutil.disk_usage(path)
            return {
                'path': path,
                'total_gb': round(usage.total / (1024**3), 2),
                'used_gb': round(usage.used / (1024**3), 2),
                'free_gb': round(usage.free / (1024**3), 2),
                'usage_percent': round((usage.used / usage.total) * 100, 2)
            }
        except Exception as e:
            logger.error(f"Error getting disk usage for {path}: {e}")
            return None
    
    def get_inode_usage(self, path: str) -> Dict:
        """Get inode usage statistics for a given path."""
        try:
            result = subprocess.run(['df', '-i', path], capture_output=True, text=True)
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                if len(lines) >= 2:
                    parts = lines[1].split()
                    if len(parts) >= 6:
                        total_inodes = int(parts[1])
                        used_inodes = int(parts[2])
                        free_inodes = int(parts[3])
                        usage_percent = round((used_inodes / total_inodes) * 100, 2) if total_inodes > 0 else 0
                        
                        return {
                            'path': path,
                            'total_inodes': total_inodes,
                            'used_inodes': used_inodes,
                            'free_inodes': free_inodes,
                            'usage_percent': usage_percent
                        }
        except Exception as e:
            logger.error(f"Error getting inode usage for {path}: {e}")
        return None
    
    def check_filesystem_health(self, path: str) -> Dict:
        """Check filesystem health using fsck (read-only)."""
        try:
            # Get filesystem type
            result = subprocess.run(['df', '-T', path], capture_output=True, text=True)
            filesystem = 'unknown'
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                if len(lines) >= 2:
                    parts = lines[1].split()
                    if len(parts) >= 2:
                        filesystem = parts[1]
            
            # Perform read-only filesystem check
            errors = 0
            status = 'healthy'
            
            if filesystem in ['ext2', 'ext3', 'ext4']:
                # Use tune2fs to check for errors (read-only)
                result = subprocess.run(['tune2fs', '-l', path], capture_output=True, text=True)
                if result.returncode == 0:
                    for line in result.stdout.split('\n'):
                        if 'Filesystem errors:' in line:
                            errors = int(line.split(':')[1].strip())
                            if errors > 0:
                                status = 'errors_detected'
                            break
            
            return {
                'path': path,
                'filesystem': filesystem,
                'status': status,
                'errors': errors
            }
        except Exception as e:
            logger.error(f"Error checking filesystem health for {path}: {e}")
            return {
                'path': path,
                'filesystem': 'unknown',
                'status': 'check_failed',
                'errors': -1
            }
    
    def get_system_health(self) -> Dict:
        """Get overall system health metrics."""
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            load_avg = os.getloadavg()
            
            return {
                'cpu_percent': round(cpu_percent, 2),
                'memory_percent': round(memory.percent, 2),
                'load_avg_1': round(load_avg[0], 2),
                'load_avg_5': round(load_avg[1], 2),
                'load_avg_15': round(load_avg[2], 2)
            }
        except Exception as e:
            logger.error(f"Error getting system health: {e}")
            return None
    
    def store_metrics(self, disk_data: List[Dict], inode_data: List[Dict], 
                     system_data: Dict, filesystem_data: List[Dict]):
        """Store collected metrics in the database."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            # Store disk usage data
            for data in disk_data:
                if data:
                    cursor.execute('''
                        INSERT INTO disk_usage (path, total_gb, used_gb, free_gb, usage_percent)
                        VALUES (?, ?, ?, ?, ?)
                    ''', (data['path'], data['total_gb'], data['used_gb'], 
                          data['free_gb'], data['usage_percent']))
            
            # Store inode usage data
            for data in inode_data:
                if data:
                    cursor.execute('''
                        INSERT INTO inode_usage (path, total_inodes, used_inodes, free_inodes, usage_percent)
                        VALUES (?, ?, ?, ?, ?)
                    ''', (data['path'], data['total_inodes'], data['used_inodes'],
                          data['free_inodes'], data['usage_percent']))
            
            # Store system health data
            if system_data:
                cursor.execute('''
                    INSERT INTO system_health (cpu_percent, memory_percent, load_avg_1, load_avg_5, load_avg_15)
                    VALUES (?, ?, ?, ?, ?)
                ''', (system_data['cpu_percent'], system_data['memory_percent'],
                      system_data['load_avg_1'], system_data['load_avg_5'], system_data['load_avg_15']))
            
            # Store filesystem health data
            for data in filesystem_data:
                if data:
                    cursor.execute('''
                        INSERT INTO filesystem_health (path, filesystem, status, errors)
                        VALUES (?, ?, ?, ?)
                    ''', (data['path'], data['filesystem'], data['status'], data['errors']))
            
            conn.commit()
    
    def check_thresholds_and_alert(self, disk_data: List[Dict], inode_data: List[Dict]):
        """Check thresholds and generate alerts if necessary."""
        alerts = []
        
        # Check disk usage thresholds
        for data in disk_data:
            if data and data['usage_percent'] > self.config['disk_usage_threshold']:
                alert = {
                    'alert_type': 'disk_usage',
                    'severity': 'critical' if data['usage_percent'] > 95 else 'warning',
                    'message': f"Disk usage on {data['path']} is {data['usage_percent']}% (threshold: {self.config['disk_usage_threshold']}%)"
                }
                alerts.append(alert)
        
        # Check inode usage thresholds
        for data in inode_data:
            if data and data['usage_percent'] > self.config['inode_usage_threshold']:
                alert = {
                    'alert_type': 'inode_usage',
                    'severity': 'critical' if data['usage_percent'] > 95 else 'warning',
                    'message': f"Inode usage on {data['path']} is {data['usage_percent']}% (threshold: {self.config['inode_usage_threshold']}%)"
                }
                alerts.append(alert)
        
        # Store and send alerts
        if alerts:
            self.store_alerts(alerts)
            if self.config['email_alerts']['enabled']:
                self.send_email_alerts(alerts)
    
    def store_alerts(self, alerts: List[Dict]):
        """Store alerts in the database."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            for alert in alerts:
                cursor.execute('''
                    INSERT INTO alerts (alert_type, severity, message)
                    VALUES (?, ?, ?)
                ''', (alert['alert_type'], alert['severity'], alert['message']))
            conn.commit()
    
    def send_email_alerts(self, alerts: List[Dict]):
        """Send email alerts."""
        try:
            email_config = self.config['email_alerts']
            
            # Create message
            msg = MimeMultipart()
            msg['From'] = email_config['from_email']
            msg['To'] = ', '.join(email_config['to_emails'])
            msg['Subject'] = f"System Alert - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            
            # Create email body
            body = "System Monitoring Alerts:\n\n"
            for alert in alerts:
                body += f"[{alert['severity'].upper()}] {alert['alert_type']}: {alert['message']}\n"
            
            msg.attach(MimeText(body, 'plain'))
            
            # Send email
            server = smtplib.SMTP(email_config['smtp_server'], email_config['smtp_port'])
            if email_config['password']:
                server.starttls()
                server.login(email_config['from_email'], email_config['password'])
            
            server.send_message(msg)
            server.quit()
            
            logger.info(f"Email alerts sent to {email_config['to_emails']}")
        except Exception as e:
            logger.error(f"Error sending email alerts: {e}")
    
    def cleanup_old_data(self):
        """Clean up old data based on retention policy."""
        retention_date = datetime.now() - timedelta(days=self.config['retention_days'])
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            tables = ['disk_usage', 'inode_usage', 'system_health', 'filesystem_health']
            for table in tables:
                cursor.execute(f'DELETE FROM {table} WHERE timestamp < ?', (retention_date,))
            
            # Keep alerts for longer (90 days)
            alert_retention_date = datetime.now() - timedelta(days=90)
            cursor.execute('DELETE FROM alerts WHERE timestamp < ?', (alert_retention_date,))
            
            conn.commit()
            logger.info(f"Cleaned up data older than {self.config['retention_days']} days")
    
    def run_monitoring_cycle(self):
        """Run a complete monitoring cycle."""
        logger.info("Starting monitoring cycle")
        
        try:
            # Collect disk usage data
            disk_data = []
            for path in self.config['monitored_paths']:
                if os.path.exists(path):
                    data = self.get_disk_usage(path)
                    if data:
                        disk_data.append(data)
            
            # Collect inode usage data
            inode_data = []
            for path in self.config['monitored_paths']:
                if os.path.exists(path):
                    data = self.get_inode_usage(path)
                    if data:
                        inode_data.append(data)
            
            # Collect system health data
            system_data = self.get_system_health()
            
            # Collect filesystem health data
            filesystem_data = []
            for path in self.config['monitored_paths']:
                if os.path.exists(path):
                    data = self.check_filesystem_health(path)
                    if data:
                        filesystem_data.append(data)
            
            # Store metrics
            self.store_metrics(disk_data, inode_data, system_data, filesystem_data)
            
            # Check thresholds and alert
            self.check_thresholds_and_alert(disk_data, inode_data)
            
            # Cleanup old data
            self.cleanup_old_data()
            
            logger.info("Monitoring cycle completed successfully")
            
        except Exception as e:
            logger.error(f"Error in monitoring cycle: {e}")
            raise

def main():
    """Main function."""
    if len(sys.argv) > 1 and sys.argv[1] == '--daemon':
        # Run as daemon (for cron)
        monitor = SystemMonitor()
        monitor.run_monitoring_cycle()
    else:
        # Interactive mode
        monitor = SystemMonitor()
        print("System Monitor - Running single cycle...")
        monitor.run_monitoring_cycle()
        print("Monitoring cycle completed. Check logs for details.")

if __name__ == "__main__":
    main()


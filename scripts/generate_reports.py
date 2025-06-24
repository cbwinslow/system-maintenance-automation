#!/home/cbwinslow/system-maintenance-automation/venv/bin/python
"""
Report Generation System
Tracks cleanup effectiveness, monitors system health, generates trend analysis, and creates monthly summaries
"""

import os
import sys
import json
import sqlite3
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend
import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns
from datetime import datetime, timedelta
from pathlib import Path
import logging
from typing import Dict, List, Tuple, Optional
import argparse

# Configuration
BASE_DIR = Path(__file__).parent.parent
CONFIG_FILE = BASE_DIR / "config" / "report_config.json"
DB_FILE = BASE_DIR / "logs" / "system_metrics.db"
LOG_FILE = BASE_DIR / "logs" / "reports.log"
REPORTS_DIR = BASE_DIR / "reports"

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

# Set style for matplotlib
plt.style.use('seaborn-v0_8')
sns.set_palette("husl")

class ReportGenerator:
    def __init__(self, config_file: str = None):
        """Initialize the report generator with configuration."""
        self.config_file = config_file or CONFIG_FILE
        self.config = self.load_config()
        self.db_path = DB_FILE
        self.reports_dir = REPORTS_DIR
        self.reports_dir.mkdir(exist_ok=True)
    
    def load_config(self) -> Dict:
        """Load configuration from JSON file."""
        default_config = {
            "report_types": ["daily", "weekly", "monthly"],
            "include_charts": True,
            "chart_format": "png",
            "retention_days": 90,
            "email_reports": {
                "enabled": False,
                "recipients": ["admin@localhost"],
                "smtp_server": "localhost",
                "smtp_port": 587,
                "username": "",
                "password": ""
            },
            "thresholds": {
                "disk_usage_warning": 80,
                "disk_usage_critical": 90,
                "memory_usage_warning": 80,
                "memory_usage_critical": 90,
                "load_average_warning": 2.0,
                "load_average_critical": 4.0
            }
        }
        
        try:
            if self.config_file.exists():
                with open(self.config_file, 'r') as f:
                    config = json.load(f)
                # Merge with defaults
                for key, value in default_config.items():
                    if key not in config:
                        config[key] = value
                return config
            else:
                # Create default config file
                self.config_file.parent.mkdir(exist_ok=True)
                with open(self.config_file, 'w') as f:
                    json.dump(default_config, f, indent=2)
                return default_config
        except Exception as e:
            logger.error(f"Error loading config: {e}")
            return default_config
    
    def get_db_connection(self) -> sqlite3.Connection:
        """Get database connection."""
        if not self.db_path.exists():
            raise FileNotFoundError(f"Database file not found: {self.db_path}")
        return sqlite3.connect(self.db_path)
    
    def get_disk_usage_data(self, days: int = 30) -> pd.DataFrame:
        """Get disk usage data from database."""
        query = """
        SELECT timestamp, path, total_gb, used_gb, free_gb, usage_percent
        FROM disk_usage
        WHERE timestamp >= datetime('now', '-{} days')
        ORDER BY timestamp
        """.format(days)
        
        with self.get_db_connection() as conn:
            df = pd.read_sql_query(query, conn)
            if not df.empty:
                df['timestamp'] = pd.to_datetime(df['timestamp'])
            return df
    
    def get_system_health_data(self, days: int = 30) -> pd.DataFrame:
        """Get system health data from database."""
        query = """
        SELECT timestamp, cpu_percent, memory_percent, load_avg_1, load_avg_5, load_avg_15
        FROM system_health
        WHERE timestamp >= datetime('now', '-{} days')
        ORDER BY timestamp
        """.format(days)
        
        with self.get_db_connection() as conn:
            df = pd.read_sql_query(query, conn)
            if not df.empty:
                df['timestamp'] = pd.to_datetime(df['timestamp'])
            return df
    
    def get_alerts_data(self, days: int = 30) -> pd.DataFrame:
        """Get alerts data from database."""
        query = """
        SELECT timestamp, alert_type, severity, message, resolved
        FROM alerts
        WHERE timestamp >= datetime('now', '-{} days')
        ORDER BY timestamp DESC
        """.format(days)
        
        with self.get_db_connection() as conn:
            df = pd.read_sql_query(query, conn)
            if not df.empty:
                df['timestamp'] = pd.to_datetime(df['timestamp'])
            return df
    
    def analyze_cleanup_effectiveness(self, days: int = 30) -> Dict:
        """Analyze the effectiveness of cleanup operations."""
        logger.info(f"Analyzing cleanup effectiveness for the last {days} days")
        
        # Get disk usage trends
        disk_data = self.get_disk_usage_data(days)
        
        if disk_data.empty:
            return {"status": "no_data", "message": "No disk usage data available"}
        
        analysis = {}
        
        # Analyze each monitored path
        for path in disk_data['path'].unique():
            path_data = disk_data[disk_data['path'] == path].sort_values('timestamp')
            
            if len(path_data) < 2:
                continue
            
            # Calculate trend
            initial_usage = path_data.iloc[0]['usage_percent']
            final_usage = path_data.iloc[-1]['usage_percent']
            trend = final_usage - initial_usage
            
            # Calculate average daily change
            days_span = (path_data.iloc[-1]['timestamp'] - path_data.iloc[0]['timestamp']).days
            avg_daily_change = trend / max(days_span, 1)
            
            # Detect cleanup events (significant drops in usage)
            path_data['usage_diff'] = path_data['usage_percent'].diff()
            cleanup_events = len(path_data[path_data['usage_diff'] < -1])  # Drops > 1%
            
            analysis[path] = {
                "initial_usage": round(initial_usage, 2),
                "final_usage": round(final_usage, 2),
                "trend": round(trend, 2),
                "avg_daily_change": round(avg_daily_change, 3),
                "cleanup_events": cleanup_events,
                "effectiveness": "good" if trend < 0 else "poor" if trend > 5 else "stable"
            }
        
        return analysis
    
    def generate_trend_analysis(self, days: int = 30) -> Dict:
        """Generate trend analysis for system metrics."""
        logger.info(f"Generating trend analysis for the last {days} days")
        
        health_data = self.get_system_health_data(days)
        disk_data = self.get_disk_usage_data(days)
        
        trends = {}
        
        if not health_data.empty:
            # CPU trend
            cpu_trend = health_data['cpu_percent'].diff().mean()
            trends['cpu'] = {
                "current_avg": round(health_data['cpu_percent'].tail(7).mean(), 2),
                "trend": "increasing" if cpu_trend > 0.1 else "decreasing" if cpu_trend < -0.1 else "stable",
                "max_value": round(health_data['cpu_percent'].max(), 2),
                "min_value": round(health_data['cpu_percent'].min(), 2)
            }
            
            # Memory trend
            memory_trend = health_data['memory_percent'].diff().mean()
            trends['memory'] = {
                "current_avg": round(health_data['memory_percent'].tail(7).mean(), 2),
                "trend": "increasing" if memory_trend > 0.1 else "decreasing" if memory_trend < -0.1 else "stable",
                "max_value": round(health_data['memory_percent'].max(), 2),
                "min_value": round(health_data['memory_percent'].min(), 2)
            }
            
            # Load average trend
            load_trend = health_data['load_avg_1'].diff().mean()
            trends['load_average'] = {
                "current_avg": round(health_data['load_avg_1'].tail(7).mean(), 2),
                "trend": "increasing" if load_trend > 0.1 else "decreasing" if load_trend < -0.1 else "stable",
                "max_value": round(health_data['load_avg_1'].max(), 2),
                "min_value": round(health_data['load_avg_1'].min(), 2)
            }
        
        if not disk_data.empty:
            # Disk usage trends by path
            trends['disk_usage'] = {}
            for path in disk_data['path'].unique():
                path_data = disk_data[disk_data['path'] == path].sort_values('timestamp')
                if len(path_data) > 1:
                    usage_trend = path_data['usage_percent'].diff().mean()
                    trends['disk_usage'][path] = {
                        "current_usage": round(path_data['usage_percent'].iloc[-1], 2),
                        "trend": "increasing" if usage_trend > 0.1 else "decreasing" if usage_trend < -0.1 else "stable",
                        "max_usage": round(path_data['usage_percent'].max(), 2),
                        "min_usage": round(path_data['usage_percent'].min(), 2)
                    }
        
        return trends
    
    def create_charts(self, output_dir: Path, days: int = 30):
        """Create visualization charts."""
        if not self.config.get('include_charts', True):
            return
        
        logger.info("Creating visualization charts")
        charts_dir = output_dir / "charts"
        charts_dir.mkdir(exist_ok=True)
        
        # Get data
        health_data = self.get_system_health_data(days)
        disk_data = self.get_disk_usage_data(days)
        
        # Create system health chart
        if not health_data.empty:
            fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(15, 10))
            fig.suptitle('System Health Trends', fontsize=16)
            
            # CPU Usage
            ax1.plot(health_data['timestamp'], health_data['cpu_percent'])
            ax1.set_title('CPU Usage (%)')
            ax1.set_ylabel('Percentage')
            ax1.tick_params(axis='x', rotation=45)
            
            # Memory Usage
            ax2.plot(health_data['timestamp'], health_data['memory_percent'], color='orange')
            ax2.set_title('Memory Usage (%)')
            ax2.set_ylabel('Percentage')
            ax2.tick_params(axis='x', rotation=45)
            
            # Load Average
            ax3.plot(health_data['timestamp'], health_data['load_avg_1'], label='1 min')
            ax3.plot(health_data['timestamp'], health_data['load_avg_5'], label='5 min')
            ax3.plot(health_data['timestamp'], health_data['load_avg_15'], label='15 min')
            ax3.set_title('Load Average')
            ax3.set_ylabel('Load')
            ax3.legend()
            ax3.tick_params(axis='x', rotation=45)
            
            # Combined overview
            ax4.plot(health_data['timestamp'], health_data['cpu_percent'], label='CPU %')
            ax4.plot(health_data['timestamp'], health_data['memory_percent'], label='Memory %')
            ax4.set_title('System Overview')
            ax4.set_ylabel('Percentage')
            ax4.legend()
            ax4.tick_params(axis='x', rotation=45)
            
            plt.tight_layout()
            plt.savefig(charts_dir / f"system_health.{self.config.get('chart_format', 'png')}", 
                       dpi=300, bbox_inches='tight')
            plt.close()
        
        # Create disk usage chart
        if not disk_data.empty:
            fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 10))
            fig.suptitle('Disk Usage Trends', fontsize=16)
            
            # Usage percentage over time
            for path in disk_data['path'].unique():
                path_data = disk_data[disk_data['path'] == path]
                ax1.plot(path_data['timestamp'], path_data['usage_percent'], label=path, marker='o')
            
            ax1.set_title('Disk Usage Percentage Over Time')
            ax1.set_ylabel('Usage Percentage')
            ax1.legend()
            ax1.tick_params(axis='x', rotation=45)
            
            # Current disk usage by path
            latest_data = disk_data.groupby('path').last().reset_index()
            ax2.bar(latest_data['path'], latest_data['usage_percent'])
            ax2.set_title('Current Disk Usage by Path')
            ax2.set_ylabel('Usage Percentage')
            ax2.tick_params(axis='x', rotation=45)
            
            # Add warning/critical thresholds
            warning_threshold = self.config['thresholds']['disk_usage_warning']
            critical_threshold = self.config['thresholds']['disk_usage_critical']
            ax1.axhline(y=warning_threshold, color='orange', linestyle='--', label='Warning')
            ax1.axhline(y=critical_threshold, color='red', linestyle='--', label='Critical')
            ax2.axhline(y=warning_threshold, color='orange', linestyle='--', label='Warning')
            ax2.axhline(y=critical_threshold, color='red', linestyle='--', label='Critical')
            
            plt.tight_layout()
            plt.savefig(charts_dir / f"disk_usage.{self.config.get('chart_format', 'png')}", 
                       dpi=300, bbox_inches='tight')
            plt.close()
    
    def generate_daily_report(self) -> str:
        """Generate daily system report."""
        logger.info("Generating daily report")
        
        report_date = datetime.now().strftime('%Y-%m-%d')
        output_dir = self.reports_dir / "daily" / report_date
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Get data for last 24 hours
        cleanup_analysis = self.analyze_cleanup_effectiveness(1)
        trends = self.generate_trend_analysis(7)  # 7-day trends for context
        alerts = self.get_alerts_data(1)
        
        # Create charts
        self.create_charts(output_dir, 7)
        
        # Generate report content
        report_file = output_dir / "daily_report.txt"
        with open(report_file, 'w') as f:
            f.write(f"Daily System Report - {report_date}\n")
            f.write("=" * 50 + "\n\n")
            
            f.write("EXECUTIVE SUMMARY\n")
            f.write("-" * 20 + "\n")
            f.write(f"Report generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"Data period: Last 24 hours\n\n")
            
            # Cleanup effectiveness
            f.write("CLEANUP EFFECTIVENESS\n")
            f.write("-" * 25 + "\n")
            if cleanup_analysis.get('status') == 'no_data':
                f.write("No cleanup data available for analysis.\n\n")
            else:
                for path, data in cleanup_analysis.items():
                    f.write(f"Path: {path}\n")
                    f.write(f"  Current usage: {data['final_usage']}%\n")
                    f.write(f"  Daily change: {data['avg_daily_change']}%\n")
                    f.write(f"  Effectiveness: {data['effectiveness']}\n")
                    f.write(f"  Cleanup events: {data['cleanup_events']}\n\n")
            
            # System health trends
            f.write("SYSTEM HEALTH TRENDS (7-day)\n")
            f.write("-" * 30 + "\n")
            if 'cpu' in trends:
                f.write(f"CPU: {trends['cpu']['current_avg']}% avg, trend: {trends['cpu']['trend']}\n")
            if 'memory' in trends:
                f.write(f"Memory: {trends['memory']['current_avg']}% avg, trend: {trends['memory']['trend']}\n")
            if 'load_average' in trends:
                f.write(f"Load: {trends['load_average']['current_avg']} avg, trend: {trends['load_average']['trend']}\n")
            f.write("\n")
            
            # Recent alerts
            f.write("RECENT ALERTS (24h)\n")
            f.write("-" * 20 + "\n")
            if alerts.empty:
                f.write("No alerts in the last 24 hours.\n\n")
            else:
                for _, alert in alerts.iterrows():
                    f.write(f"[{alert['severity'].upper()}] {alert['alert_type']}: {alert['message']}\n")
                    f.write(f"  Time: {alert['timestamp']}\n")
                    f.write(f"  Resolved: {'Yes' if alert['resolved'] else 'No'}\n\n")
            
            # Recommendations
            f.write("RECOMMENDATIONS\n")
            f.write("-" * 15 + "\n")
            recommendations = self.generate_recommendations(trends, alerts)
            for rec in recommendations:
                f.write(f"• {rec}\n")
        
        logger.info(f"Daily report generated: {report_file}")
        return str(report_file)
    
    def generate_weekly_report(self) -> str:
        """Generate weekly system report."""
        logger.info("Generating weekly report")
        
        # Get the start of this week (Monday)
        today = datetime.now()
        monday = today - timedelta(days=today.weekday())
        week_str = monday.strftime('%Y-W%U')
        
        output_dir = self.reports_dir / "weekly" / week_str
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Get data for last 7 days
        cleanup_analysis = self.analyze_cleanup_effectiveness(7)
        trends = self.generate_trend_analysis(30)  # 30-day trends for context
        alerts = self.get_alerts_data(7)
        
        # Create charts
        self.create_charts(output_dir, 30)
        
        # Generate report content
        report_file = output_dir / "weekly_report.txt"
        with open(report_file, 'w') as f:
            f.write(f"Weekly System Report - {week_str}\n")
            f.write("=" * 50 + "\n\n")
            
            f.write("EXECUTIVE SUMMARY\n")
            f.write("-" * 20 + "\n")
            f.write(f"Report generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"Week period: {monday.strftime('%Y-%m-%d')} to {today.strftime('%Y-%m-%d')}\n\n")
            
            # Weekly cleanup summary
            f.write("WEEKLY CLEANUP SUMMARY\n")
            f.write("-" * 25 + "\n")
            if cleanup_analysis.get('status') == 'no_data':
                f.write("No cleanup data available for analysis.\n\n")
            else:
                total_cleanup_events = sum(data.get('cleanup_events', 0) for data in cleanup_analysis.values())
                f.write(f"Total cleanup events: {total_cleanup_events}\n")
                
                for path, data in cleanup_analysis.items():
                    f.write(f"\nPath: {path}\n")
                    f.write(f"  Weekly change: {data['trend']}%\n")
                    f.write(f"  Average daily change: {data['avg_daily_change']}%\n")
                    f.write(f"  Effectiveness rating: {data['effectiveness']}\n")
                    f.write(f"  Cleanup events: {data['cleanup_events']}\n")
            
            # System trends
            f.write("\nSYSTEM TRENDS (30-day)\n")
            f.write("-" * 25 + "\n")
            self.write_trend_summary(f, trends)
            
            # Weekly alerts summary
            f.write("\nWEEKLY ALERTS SUMMARY\n")
            f.write("-" * 25 + "\n")
            if alerts.empty:
                f.write("No alerts this week.\n")
            else:
                alert_counts = alerts['severity'].value_counts()
                f.write("Alert counts by severity:\n")
                for severity, count in alert_counts.items():
                    f.write(f"  {severity}: {count}\n")
                
                f.write("\nMost recent alerts:\n")
                for _, alert in alerts.head(10).iterrows():
                    f.write(f"  [{alert['severity'].upper()}] {alert['alert_type']}: {alert['timestamp'].strftime('%m-%d %H:%M')}\n")
        
        logger.info(f"Weekly report generated: {report_file}")
        return str(report_file)
    
    def generate_monthly_report(self) -> str:
        """Generate monthly system summary report."""
        logger.info("Generating monthly report")
        
        # Get current month
        today = datetime.now()
        month_str = today.strftime('%Y-%m')
        
        output_dir = self.reports_dir / "monthly" / month_str
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Get data for last 30 days
        cleanup_analysis = self.analyze_cleanup_effectiveness(30)
        trends = self.generate_trend_analysis(90)  # 90-day trends for context
        alerts = self.get_alerts_data(30)
        
        # Create charts
        self.create_charts(output_dir, 90)
        
        # Generate detailed statistics
        stats = self.generate_monthly_statistics()
        
        # Generate report content
        report_file = output_dir / "monthly_report.txt"
        with open(report_file, 'w') as f:
            f.write(f"Monthly System Report - {month_str}\n")
            f.write("=" * 50 + "\n\n")
            
            f.write("EXECUTIVE SUMMARY\n")
            f.write("-" * 20 + "\n")
            f.write(f"Report generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"Month: {today.strftime('%B %Y')}\n\n")
            
            # Monthly statistics
            f.write("MONTHLY STATISTICS\n")
            f.write("-" * 20 + "\n")
            for key, value in stats.items():
                f.write(f"{key}: {value}\n")
            f.write("\n")
            
            # Cleanup effectiveness over the month
            f.write("MONTHLY CLEANUP ANALYSIS\n")
            f.write("-" * 28 + "\n")
            if cleanup_analysis.get('status') == 'no_data':
                f.write("No cleanup data available for analysis.\n\n")
            else:
                # Overall effectiveness rating
                effectiveness_scores = [data.get('effectiveness', 'unknown') for data in cleanup_analysis.values()]
                good_count = effectiveness_scores.count('good')
                total_paths = len(effectiveness_scores)
                overall_rating = "Excellent" if good_count == total_paths else "Good" if good_count > total_paths/2 else "Needs Improvement"
                
                f.write(f"Overall cleanup effectiveness: {overall_rating}\n")
                f.write(f"Paths with good effectiveness: {good_count}/{total_paths}\n\n")
                
                for path, data in cleanup_analysis.items():
                    f.write(f"Path: {path}\n")
                    f.write(f"  Month start usage: {data['initial_usage']}%\n")
                    f.write(f"  Current usage: {data['final_usage']}%\n")
                    f.write(f"  Monthly change: {data['trend']}%\n")
                    f.write(f"  Total cleanup events: {data['cleanup_events']}\n")
                    f.write(f"  Effectiveness: {data['effectiveness']}\n\n")
            
            # Long-term trends
            f.write("LONG-TERM TRENDS (90-day)\n")
            f.write("-" * 28 + "\n")
            self.write_trend_summary(f, trends)
            
            # Monthly alerts analysis
            f.write("\nMONTHLY ALERTS ANALYSIS\n")
            f.write("-" * 27 + "\n")
            if alerts.empty:
                f.write("No alerts this month.\n")
            else:
                # Alert statistics
                total_alerts = len(alerts)
                critical_alerts = len(alerts[alerts['severity'] == 'critical'])
                warning_alerts = len(alerts[alerts['severity'] == 'warning'])
                
                f.write(f"Total alerts: {total_alerts}\n")
                f.write(f"Critical alerts: {critical_alerts}\n")
                f.write(f"Warning alerts: {warning_alerts}\n\n")
                
                # Alert types
                alert_types = alerts['alert_type'].value_counts()
                f.write("Alerts by type:\n")
                for alert_type, count in alert_types.items():
                    f.write(f"  {alert_type}: {count}\n")
            
            # Recommendations for next month
            f.write("\nRECOMMENDATIONS FOR NEXT MONTH\n")
            f.write("-" * 35 + "\n")
            recommendations = self.generate_monthly_recommendations(cleanup_analysis, trends, alerts)
            for rec in recommendations:
                f.write(f"• {rec}\n")
        
        logger.info(f"Monthly report generated: {report_file}")
        return str(report_file)
    
    def generate_monthly_statistics(self) -> Dict:
        """Generate detailed monthly statistics."""
        stats = {}
        
        try:
            with self.get_db_connection() as conn:
                # System uptime data points
                cursor = conn.cursor()
                cursor.execute("SELECT COUNT(*) FROM system_health WHERE timestamp >= datetime('now', '-30 days')")
                stats['Data points collected'] = cursor.fetchone()[0]
                
                # Average system metrics
                cursor.execute("""
                    SELECT AVG(cpu_percent), AVG(memory_percent), AVG(load_avg_1)
                    FROM system_health 
                    WHERE timestamp >= datetime('now', '-30 days')
                """)
                avg_cpu, avg_memory, avg_load = cursor.fetchone()
                if avg_cpu:
                    stats['Average CPU usage'] = f"{avg_cpu:.1f}%"
                    stats['Average memory usage'] = f"{avg_memory:.1f}%"
                    stats['Average load'] = f"{avg_load:.2f}"
                
                # Peak usage
                cursor.execute("""
                    SELECT MAX(cpu_percent), MAX(memory_percent), MAX(load_avg_1)
                    FROM system_health 
                    WHERE timestamp >= datetime('now', '-30 days')
                """)
                max_cpu, max_memory, max_load = cursor.fetchone()
                if max_cpu:
                    stats['Peak CPU usage'] = f"{max_cpu:.1f}%"
                    stats['Peak memory usage'] = f"{max_memory:.1f}%"
                    stats['Peak load'] = f"{max_load:.2f}"
                
                # Total alerts
                cursor.execute("SELECT COUNT(*) FROM alerts WHERE timestamp >= datetime('now', '-30 days')")
                stats['Total alerts'] = cursor.fetchone()[0]
                
        except Exception as e:
            logger.error(f"Error generating monthly statistics: {e}")
            stats['Error'] = "Unable to generate statistics"
        
        return stats
    
    def write_trend_summary(self, f, trends: Dict):
        """Write trend summary to file."""
        if 'cpu' in trends:
            f.write(f"CPU usage: {trends['cpu']['current_avg']}% (trend: {trends['cpu']['trend']})\n")
            f.write(f"  Range: {trends['cpu']['min_value']}% - {trends['cpu']['max_value']}%\n")
        
        if 'memory' in trends:
            f.write(f"Memory usage: {trends['memory']['current_avg']}% (trend: {trends['memory']['trend']})\n")
            f.write(f"  Range: {trends['memory']['min_value']}% - {trends['memory']['max_value']}%\n")
        
        if 'load_average' in trends:
            f.write(f"Load average: {trends['load_average']['current_avg']} (trend: {trends['load_average']['trend']})\n")
            f.write(f"  Range: {trends['load_average']['min_value']} - {trends['load_average']['max_value']}\n")
        
        if 'disk_usage' in trends:
            f.write("Disk usage trends:\n")
            for path, data in trends['disk_usage'].items():
                f.write(f"  {path}: {data['current_usage']}% (trend: {data['trend']})\n")
    
    def generate_recommendations(self, trends: Dict, alerts: pd.DataFrame) -> List[str]:
        """Generate actionable recommendations."""
        recommendations = []
        
        # Check trends for concerning patterns
        if 'cpu' in trends and trends['cpu']['trend'] == 'increasing':
            recommendations.append("Monitor CPU usage - increasing trend detected")
        
        if 'memory' in trends and trends['memory']['trend'] == 'increasing':
            recommendations.append("Monitor memory usage - increasing trend detected")
        
        if 'disk_usage' in trends:
            for path, data in trends['disk_usage'].items():
                if data['current_usage'] > 80:
                    recommendations.append(f"Consider cleanup for {path} - usage at {data['current_usage']}%")
                elif data['trend'] == 'increasing':
                    recommendations.append(f"Monitor {path} - disk usage increasing")
        
        # Check for repeated alerts
        if not alerts.empty:
            frequent_alerts = alerts['alert_type'].value_counts()
            for alert_type, count in frequent_alerts.items():
                if count > 3:
                    recommendations.append(f"Address recurring {alert_type} alerts ({count} occurrences)")
        
        if not recommendations:
            recommendations.append("System appears healthy - continue regular monitoring")
        
        return recommendations
    
    def generate_monthly_recommendations(self, cleanup_analysis: Dict, trends: Dict, alerts: pd.DataFrame) -> List[str]:
        """Generate monthly recommendations."""
        recommendations = []
        
        # Cleanup recommendations
        if cleanup_analysis.get('status') != 'no_data':
            poor_paths = [path for path, data in cleanup_analysis.items() 
                         if data.get('effectiveness') == 'poor']
            if poor_paths:
                recommendations.append(f"Improve cleanup strategies for: {', '.join(poor_paths)}")
        
        # Capacity planning
        if 'disk_usage' in trends:
            high_usage_paths = [path for path, data in trends['disk_usage'].items() 
                               if data['current_usage'] > 75]
            if high_usage_paths:
                recommendations.append(f"Plan capacity expansion for: {', '.join(high_usage_paths)}")
        
        # Alert pattern analysis
        if not alerts.empty:
            critical_count = len(alerts[alerts['severity'] == 'critical'])
            if critical_count > 10:
                recommendations.append("Review and tune alert thresholds - too many critical alerts")
        
        # System optimization
        if 'cpu' in trends and trends['cpu']['current_avg'] > 70:
            recommendations.append("Consider CPU optimization or upgrade")
        
        if 'memory' in trends and trends['memory']['current_avg'] > 80:
            recommendations.append("Consider memory upgrade or optimization")
        
        if not recommendations:
            recommendations.append("System performance is stable - maintain current practices")
        
        return recommendations

def main():
    """Main function with command line interface."""
    parser = argparse.ArgumentParser(description='Generate system maintenance reports')
    parser.add_argument('--type', choices=['daily', 'weekly', 'monthly', 'all'], 
                       default='daily', help='Type of report to generate')
    parser.add_argument('--config', help='Configuration file path')
    parser.add_argument('--output-dir', help='Output directory for reports')
    
    args = parser.parse_args()
    
    # Create report generator
    config_file = args.config if args.config else None
    generator = ReportGenerator(config_file)
    
    # Override output directory if specified
    if args.output_dir:
        generator.reports_dir = Path(args.output_dir)
        generator.reports_dir.mkdir(exist_ok=True)
    
    try:
        if args.type == 'daily':
            report_file = generator.generate_daily_report()
            print(f"Daily report generated: {report_file}")
        
        elif args.type == 'weekly':
            report_file = generator.generate_weekly_report()
            print(f"Weekly report generated: {report_file}")
        
        elif args.type == 'monthly':
            report_file = generator.generate_monthly_report()
            print(f"Monthly report generated: {report_file}")
        
        elif args.type == 'all':
            daily_report = generator.generate_daily_report()
            weekly_report = generator.generate_weekly_report()
            monthly_report = generator.generate_monthly_report()
            print(f"All reports generated:")
            print(f"  Daily: {daily_report}")
            print(f"  Weekly: {weekly_report}")
            print(f"  Monthly: {monthly_report}")
    
    except Exception as e:
        logger.error(f"Error generating report: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()


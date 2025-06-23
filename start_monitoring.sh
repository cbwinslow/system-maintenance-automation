#!/bin/bash
# System Maintenance Automation Startup Script
# Run this script to start all monitoring and maintenance tasks

BASE_DIR="/home/cbwinslow/system-maintenance-automation"

echo "Starting System Maintenance Automation..."

# Run initial system check
echo "Running initial system monitoring..."
$BASE_DIR/scripts/monitor_system.py

# Generate initial report
echo "Generating initial report..."
$BASE_DIR/scripts/generate_reports.py --type daily

echo "System Maintenance Automation started successfully!"
echo "Check logs in: $BASE_DIR/logs/"
echo "Check reports in: $BASE_DIR/reports/"

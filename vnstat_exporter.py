#!/usr/bin/env python3
"""
VNStat Prometheus Exporter
-------------------------

This exporter collects network traffic statistics from vnstat and exports them in Prometheus format.

Usage:
    python3 vnstat_exporter.py [--port PORT] [--interval INTERVAL] [--billing-day DAY]

Options:
    --port        Port to expose metrics on (default: 9469)
    --interval    Update interval in seconds (default: 60)
    --billing-day Day of month when billing cycle resets (default: 1, range: 1-28)

Metrics Exported:
    vnstat_traffic_5min          - Traffic in the last 5 minutes
    vnstat_traffic_hourly        - Hourly network traffic
    vnstat_traffic_daily         - Daily network traffic
    vnstat_traffic_monthly       - Monthly network traffic (natural month)
    vnstat_traffic_yearly        - Yearly network traffic
    vnstat_traffic_total         - Total network traffic
    vnstat_traffic_billing_cycle - Traffic in current billing cycle (respects --billing-day)

Labels:
    interface - Network interface name (e.g., eth0)
    direction - Traffic direction (rx for received, tx for transmitted)
"""

import subprocess
import json
from prometheus_client import start_http_server, Gauge
import time
import argparse
import logging
import logging.handlers
import sys
import daemon
from datetime import date, timedelta

# Set up logging
logger = logging.getLogger('vnstat_exporter')
logger.setLevel(logging.INFO)

# Add syslog handler
try:
    syslog_handler = logging.handlers.SysLogHandler(address='/dev/log')
    syslog_formatter = logging.Formatter('%(name)s: %(message)s')
    syslog_handler.setFormatter(syslog_formatter)
    logger.addHandler(syslog_handler)
except Exception:
    pass  # /dev/log 在容器内可能不存在

# Add journal handler (stdout/stderr)
stream_handler = logging.StreamHandler(sys.stdout)
stream_formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
stream_handler.setFormatter(stream_formatter)
logger.addHandler(stream_handler)

# Define all Prometheus metrics
TRAFFIC_5MIN = Gauge('vnstat_traffic_5min', 'Traffic in the last 5 minutes', ['interface', 'direction'])
TRAFFIC_HOURLY = Gauge('vnstat_traffic_hourly', 'Hourly network traffic', ['interface', 'direction'])
TRAFFIC_DAILY = Gauge('vnstat_traffic_daily', 'Daily network traffic', ['interface', 'direction'])
TRAFFIC_MONTHLY = Gauge('vnstat_traffic_monthly', 'Monthly network traffic', ['interface', 'direction'])
TRAFFIC_YEARLY = Gauge('vnstat_traffic_yearly', 'Yearly network traffic', ['interface', 'direction'])
TRAFFIC_TOTAL = Gauge('vnstat_traffic_total', 'Total network traffic', ['interface', 'direction'])
TRAFFIC_BILLING = Gauge('vnstat_traffic_billing_cycle', 'Traffic in current billing cycle', ['interface', 'direction'])


def get_billing_cycle_start(billing_day: int) -> date:
    """根据计费日计算当前计费周期的起始日期"""
    today = date.today()
    if today.day >= billing_day:
        return today.replace(day=billing_day)
    else:
        # 上个月的计费日
        first_of_month = today.replace(day=1)
        last_month = first_of_month - timedelta(days=1)
        # 防止计费日超过上个月最大天数
        billing_day_clamped = min(billing_day, last_month.day)
        return last_month.replace(day=billing_day_clamped)


def get_vnstat_data(interface=None):
    """Get network traffic data from vnstat in JSON format"""
    cmd = ['vnstat', '--json']
    if interface:
        cmd.extend(['-i', interface])

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        logger.error(f"Error running vnstat: {e}")
        return None
    except json.JSONDecodeError as e:
        logger.error(f"Error parsing vnstat output: {e}")
        return None


def update_metrics():
    """Update Prometheus metrics with current vnstat data"""
    data = get_vnstat_data()
    if not data:
        return

    billing_start = get_billing_cycle_start(args.billing_day)

    for interface in data.get('interfaces', []):
        iface_name = interface.get('name')
        traffic = interface.get('traffic', {})

        # 5 分钟
        fiveminute = traffic.get('fiveminute', [])
        if fiveminute:
            latest = fiveminute[-1]
            TRAFFIC_5MIN.labels(interface=iface_name, direction='rx').set(latest.get('rx', 0))
            TRAFFIC_5MIN.labels(interface=iface_name, direction='tx').set(latest.get('tx', 0))

        # 小时
        hours = traffic.get('hour', [])
        if hours:
            latest = hours[-1]
            TRAFFIC_HOURLY.labels(interface=iface_name, direction='rx').set(latest.get('rx', 0))
            TRAFFIC_HOURLY.labels(interface=iface_name, direction='tx').set(latest.get('tx', 0))

        # 日
        days = traffic.get('day', [])
        if days:
            latest = days[-1]
            TRAFFIC_DAILY.labels(interface=iface_name, direction='rx').set(latest.get('rx', 0))
            TRAFFIC_DAILY.labels(interface=iface_name, direction='tx').set(latest.get('tx', 0))

        # 自然月
        months = traffic.get('month', [])
        if months:
            latest = months[-1]
            TRAFFIC_MONTHLY.labels(interface=iface_name, direction='rx').set(latest.get('rx', 0))
            TRAFFIC_MONTHLY.labels(interface=iface_name, direction='tx').set(latest.get('tx', 0))

        # 年
        years = traffic.get('year', [])
        if years:
            latest = years[-1]
            TRAFFIC_YEARLY.labels(interface=iface_name, direction='rx').set(latest.get('rx', 0))
            TRAFFIC_YEARLY.labels(interface=iface_name, direction='tx').set(latest.get('tx', 0))

        # 总计
        total = traffic.get('total', {})
        TRAFFIC_TOTAL.labels(interface=iface_name, direction='rx').set(total.get('rx', 0))
        TRAFFIC_TOTAL.labels(interface=iface_name, direction='tx').set(total.get('tx', 0))

        # 计费周期累计（从 billing_start 到今天的日流量加总）
        billing_rx = 0
        billing_tx = 0
        for day_entry in days:
            d = day_entry.get('date', {})
            try:
                entry_date = date(d['year'], d['month'], d['day'])
            except (KeyError, ValueError):
                continue
            if entry_date >= billing_start:
                billing_rx += day_entry.get('rx', 0)
                billing_tx += day_entry.get('tx', 0)

        TRAFFIC_BILLING.labels(interface=iface_name, direction='rx').set(billing_rx)
        TRAFFIC_BILLING.labels(interface=iface_name, direction='tx').set(billing_tx)


class vnstat_metrics:
    def __init__(self):
        try:
            start_http_server(args.port)
            logger.info(f"Metrics server started on port {args.port}")
            logger.info(f"Billing cycle starts on day {args.billing_day} of each month")
        except Exception as e:
            logger.error(f"Failed to start metrics server: {e}")
            sys.exit(1)

    def run(self):
        while True:
            try:
                logger.info("Processing vnstat data...")
                update_metrics()
            except Exception as e:
                logger.error(f"Error updating metrics: {e}")
            time.sleep(args.interval)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='VNStat Prometheus Exporter')
    parser.add_argument('--port', type=int, default=9469,
                        help='Port to expose metrics on (default: 9469)')
    parser.add_argument('--interval', type=int, default=60,
                        help='Metrics update interval in seconds (default: 60)')
    parser.add_argument('--billing-day', type=int, default=1,
                        help='Day of month when billing cycle resets (default: 1, range: 1-28)')
    parser.add_argument('--daemon', action='store_true',
                        help='Daemonize app on non-systemd systems')
    args = parser.parse_args()

    if not 1 <= args.billing_day <= 28:
        logger.error("--billing-day must be between 1 and 28")
        sys.exit(1)

    logger.info(f"Starting VNStat exporter on port {args.port}")
    logger.info(f"Update interval: {args.interval} seconds")

    logger.info("Testing vnstat access...")
    if get_vnstat_data():
        logger.info("Successfully called vnstat")
    else:
        logger.error("Failed to call vnstat")
        sys.exit(1)

    if args.daemon:
        logger.setLevel(logging.WARNING)
        logger.removeHandler(stream_handler)
        with daemon.DaemonContext():
            vnstat_metrics().run()
    else:
        vnstat_metrics().run()

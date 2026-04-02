#!/usr/bin/env python3
"""
VNStat Prometheus Exporter
--------------------------

将 vnstat 网络流量统计数据导出为 Prometheus 格式指标。

用法：
    python3 vnstat_exporter.py [--port PORT] [--interval INTERVAL] [--billing-day DAY] [--vnstat-url URL]

参数：
    --port          指标监听端口（默认：9469）
    --interval      数据更新间隔，单位秒（默认：60）
    --billing-day   计费周期重置日，每月第几天（默认：1，范围：1-28）
    --vnstat-url    vergoh/vnstat 容器的 HTTP 地址，例如 http://localhost:8685
                    不指定时使用本地 vnstat 命令行（需宿主机已安装 vnstat）

数据来源（二选一）：
    1. HTTP 模式（推荐）：对接 vergoh/vnstat 官方容器的 /json.cgi 接口
       兼容 vnstat 2.x JSON 格式
    2. 命令行模式：直接调用宿主机的 vnstat --json 命令
       兼容 vnstat 1.x 和 2.x

导出指标：
    vnstat_traffic_5min          - 最近5分钟流量（仅 vnstat 2.x 支持）
    vnstat_traffic_hourly        - 当前小时流量
    vnstat_traffic_daily         - 当日流量（含 date label）
    vnstat_traffic_monthly       - 当月流量（自然月）
    vnstat_traffic_yearly        - 当年流量
    vnstat_traffic_total         - 历史总流量
    vnstat_traffic_billing_cycle - 当前计费周期流量（按 --billing-day 计算）
    vnstat_traffic_top_daily     - 历史单日流量峰值
    vnstat_billing_day           - 计费周期重置日（数值）
    vnstat_db_updated_timestamp  - vnstat 数据库最后更新时间戳
    vnstat_db_created_timestamp  - vnstat 数据库创建时间戳

标签：
    interface - 网卡名称（如 eth0）
    direction - 流量方向（rx：下行，tx：上行）
"""

import subprocess
import json
from prometheus_client import start_http_server, Gauge
import time
import argparse
import logging
import sys
import os
import signal
from datetime import date, timedelta

# Set up logging
logger = logging.getLogger('vnstat_exporter')
logger.setLevel(logging.INFO)

stream_handler = logging.StreamHandler(sys.stdout)
stream_formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
stream_handler.setFormatter(stream_formatter)
logger.addHandler(stream_handler)

# Define all Prometheus metrics
TRAFFIC_5MIN = Gauge('vnstat_traffic_5min', 'Traffic in the last 5 minutes', ['interface', 'direction'])
TRAFFIC_HOURLY = Gauge('vnstat_traffic_hourly', 'Hourly network traffic', ['interface', 'direction'])
TRAFFIC_DAILY = Gauge('vnstat_traffic_daily', 'Daily network traffic', ['interface', 'direction', 'date'])
TRAFFIC_MONTHLY = Gauge('vnstat_traffic_monthly', 'Monthly network traffic', ['interface', 'direction'])
TRAFFIC_YEARLY = Gauge('vnstat_traffic_yearly', 'Yearly network traffic', ['interface', 'direction'])
TRAFFIC_TOTAL = Gauge('vnstat_traffic_total', 'Total network traffic', ['interface', 'direction'])
TRAFFIC_BILLING = Gauge('vnstat_traffic_billing_cycle', 'Traffic in current billing cycle', ['interface', 'direction'])
BILLING_DAY = Gauge('vnstat_billing_day', 'Billing cycle reset day of month', [])
TRAFFIC_LIMIT = Gauge('vnstat_traffic_limit_bytes', 'Traffic limit in bytes for billing cycle (0 = unlimited)', [])
TRAFFIC_TOP_DAILY = Gauge('vnstat_traffic_top_daily', 'Top daily traffic record', ['interface', 'direction'])
DB_UPDATED = Gauge('vnstat_db_updated_timestamp', 'Timestamp of last vnstat database update', ['interface'])
DB_CREATED = Gauge('vnstat_db_created_timestamp', 'Timestamp of vnstat database creation', ['interface'])


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
    """Get network traffic data from vnstat in JSON format.
    支持两种模式：
    1. HTTP 模式：从 vergoh/vnstat 容器的 /json.cgi 接口读取（推荐）
    2. 命令行模式：直接调用本地 vnstat 命令
    """
    if args.vnstat_url:
        url = args.vnstat_url.rstrip('/')
        if interface:
            url = f"{url}/json.cgi?iface={interface}"
        else:
            url = f"{url}/json.cgi"
        try:
            import urllib.request
            with urllib.request.urlopen(url, timeout=10) as resp:
                return json.loads(resp.read().decode('utf-8'))
        except Exception as e:
            logger.error(f"Error fetching vnstat data from {url}: {e}")
            return None

    cmd = ['vnstat', '--json']
    if interface:
        cmd.extend(['-i', interface])

    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, check=True)
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        logger.error(f"Error running vnstat: {e}, stderr: {e.stderr.strip()}")
        return None
    except json.JSONDecodeError as e:
        logger.error(f"Error parsing vnstat output: {e}")
        return None


def update_metrics():
    """Update Prometheus metrics with current vnstat data"""
    data = get_vnstat_data()
    if not data:
        return

    billing_start = get_billing_cycle_start(args.billing_day) if args.billing_day > 0 else None
    BILLING_DAY.set(args.billing_day)
    TRAFFIC_LIMIT.set(args.traffic_limit * 1024 * 1024 * 1024)

    for interface in data.get('interfaces', []):
        iface_name = interface.get('name') or interface.get('id')
        traffic = interface.get('traffic', {})

        # 5 分钟（vnstat 2.x: fiveminute，1.x 不支持）
        fiveminute = traffic.get('fiveminute') or traffic.get('fiveminutes', [])
        if fiveminute:
            latest = fiveminute[-1]
            TRAFFIC_5MIN.labels(interface=iface_name, direction='rx').set(latest.get('rx', 0))
            TRAFFIC_5MIN.labels(interface=iface_name, direction='tx').set(latest.get('tx', 0))

        # 小时（2.x: hour，1.x: hours）
        hours = traffic.get('hour') or traffic.get('hours', [])
        if hours:
            latest = hours[-1]
            TRAFFIC_HOURLY.labels(interface=iface_name, direction='rx').set(latest.get('rx', 0))
            TRAFFIC_HOURLY.labels(interface=iface_name, direction='tx').set(latest.get('tx', 0))

        # 日（2.x: day，1.x: days）
        days = traffic.get('day') or traffic.get('days', [])
        if days:
            latest = days[-1]
            d = latest.get('date', {})
            date_str = f"{d.get('year', 0)}-{d.get('month', 0):02d}-{d.get('day', 0):02d}"
            TRAFFIC_DAILY.labels(interface=iface_name, direction='rx', date=date_str).set(latest.get('rx', 0))
            TRAFFIC_DAILY.labels(interface=iface_name, direction='tx', date=date_str).set(latest.get('tx', 0))

        # 自然月（2.x: month，1.x: months）
        months = traffic.get('month') or traffic.get('months', [])
        if months:
            latest = months[-1]
            TRAFFIC_MONTHLY.labels(interface=iface_name, direction='rx').set(latest.get('rx', 0))
            TRAFFIC_MONTHLY.labels(interface=iface_name, direction='tx').set(latest.get('tx', 0))

        # 年（2.x: year，1.x: years）
        years = traffic.get('year') or traffic.get('years', [])
        if years:
            latest = years[-1]
            TRAFFIC_YEARLY.labels(interface=iface_name, direction='rx').set(latest.get('rx', 0))
            TRAFFIC_YEARLY.labels(interface=iface_name, direction='tx').set(latest.get('tx', 0))

        # 总计
        total = traffic.get('total', {})
        TRAFFIC_TOTAL.labels(interface=iface_name, direction='rx').set(total.get('rx', 0))
        TRAFFIC_TOTAL.labels(interface=iface_name, direction='tx').set(total.get('tx', 0))

        # 计费周期累计（从 billing_start 到今天的日流量加总）
        if billing_start is not None:
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

        # 历史单日峰值
        tops = traffic.get('top', [])
        if tops:
            max_rx = max((t.get('rx', 0) for t in tops), default=0)
            max_tx = max((t.get('tx', 0) for t in tops), default=0)
            TRAFFIC_TOP_DAILY.labels(interface=iface_name, direction='rx').set(max_rx)
            TRAFFIC_TOP_DAILY.labels(interface=iface_name, direction='tx').set(max_tx)

        # 数据库更新时间
        updated_ts = interface.get('updated', {}).get('timestamp')
        if updated_ts:
            DB_UPDATED.labels(interface=iface_name).set(updated_ts)

        created_ts = interface.get('created', {}).get('timestamp')
        if created_ts:
            DB_CREATED.labels(interface=iface_name).set(created_ts)


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
    parser.add_argument('--port', type=int, default=19469,
                        help='Port to expose metrics on (default: 19469)')
    parser.add_argument('--interval', type=int, default=60,
                        help='Metrics update interval in seconds (default: 60)')
    parser.add_argument('--billing-day', type=int, default=0,
                        help='计费周期重置日，每月第几天（0 或不设置表示不启用计费周期统计，范围：1-28）')
    parser.add_argument('--traffic-limit', type=float, default=0,
                        help='计费周期流量限额，单位 GB（0 表示不限制）')
    parser.add_argument('--vnstat-url', type=str, default=None,
                        help='URL of vergoh/vnstat HTTP server, e.g. http://localhost:8685 (default: use local vnstat command)')
    parser.add_argument('--daemon', action='store_true',
                        help='Daemonize app on non-systemd systems')
    args = parser.parse_args()

    if not 0 <= args.billing_day <= 28:
        logger.error("--billing-day 必须在 0-28 之间（0 表示不启用计费周期）")
        sys.exit(1)

    data_source = f"HTTP ({args.vnstat_url})" if args.vnstat_url else "本地 vnstat 命令"
    billing_reset = f"每月 {args.billing_day} 日" if args.billing_day > 0 else "未启用"
    traffic_limit = f"{args.traffic_limit} GB" if args.traffic_limit > 0 else "不限制"

    logger.info("=" * 50)
    logger.info("  VNStat Prometheus Exporter 启动")
    logger.info("=" * 50)
    logger.info(f"  监听端口    : {args.port}")
    logger.info(f"  更新间隔    : {args.interval} 秒")
    logger.info(f"  计费重置日  : {billing_reset}")
    logger.info(f"  流量限额    : {traffic_limit}")
    logger.info(f"  数据来源    : {data_source}")
    logger.info("=" * 50)

    logger.info("正在测试 vnstat 数据源连接...")
    if get_vnstat_data():
        logger.info("vnstat 数据源连接成功")
    else:
        logger.warning("vnstat 数据源连接失败，将持续重试...")

    if args.daemon:
        # 用标准库实现守护进程，避免 python-daemon 依赖
        pid = os.fork()
        if pid > 0:
            sys.exit(0)
        os.setsid()
        pid = os.fork()
        if pid > 0:
            sys.exit(0)
        sys.stdout.flush()
        sys.stderr.flush()
        with open(os.devnull, 'r') as f:
            os.dup2(f.fileno(), sys.stdin.fileno())
        with open(os.devnull, 'a+') as f:
            os.dup2(f.fileno(), sys.stdout.fileno())
            os.dup2(f.fileno(), sys.stderr.fileno())
        logger.setLevel(logging.WARNING)
        logger.removeHandler(stream_handler)
        vnstat_metrics().run()
    else:
        vnstat_metrics().run()

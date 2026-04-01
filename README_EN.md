# vnstat Prometheus Exporter

Based on [joaomnmoreira/vnstat-exporter](https://github.com/joaomnmoreira/vnstat-exporter) and [rosco-pc/vnstat_exporter](https://github.com/rosco-pc/vnstat_exporter), with additional modifications. Grafana dashboard reference: [Dashboard #22548](https://grafana.com/grafana/dashboards/22548).

[中文版](README.md)

## Changes

- Added `--billing-day` parameter to support custom billing cycle start day (1-28), adapting to different ISP billing cycles
- Added `vnstat_traffic_billing_cycle` metric to accumulate traffic by billing cycle (instead of calendar month)
- Added `--daemon` parameter to run as a daemon process on systems without systemd
- Reduced log output frequency in daemon mode
- Fixed startup error caused by missing `/dev/log` in container environments
- Replaced `print()` calls with `logger.error()`

## Exposed Metrics

| Metric | Description |
|--------|-------------|
| `vnstat_traffic_5min` | Traffic in the last 5 minutes |
| `vnstat_traffic_hourly` | Hourly traffic |
| `vnstat_traffic_daily` | Daily traffic |
| `vnstat_traffic_monthly` | Calendar month traffic |
| `vnstat_traffic_yearly` | Yearly traffic |
| `vnstat_traffic_total` | Total cumulative traffic |
| `vnstat_traffic_billing_cycle` | Cumulative traffic in the current billing cycle |

All metrics include `interface` (network interface name) and `direction` (`rx`/`tx`) labels.

## Dependencies

```
pip install -r requirements.txt
```

Required packages: `prometheus-client`, `python-daemon`

## Docker Deployment (Recommended)

```yaml
services:
  vnstat-exporter:
    image: adsryen/vnstat_exporter:latest
    container_name: vnstat-exporter
    restart: always
    ports:
      - "19209:9469"
    volumes:
      - /var/lib/vnstat:/var/lib/vnstat:ro
      - /etc/localtime:/etc/localtime:ro
    command: ["--port", "9469", "--interval", "60", "--billing-day", "28"]
```

Set `--billing-day` to your server's actual billing start day.

## Running Directly

```bash
# Show help
python3 vnstat_exporter.py --help

# Default startup (billing cycle starts on the 1st of each month)
python3 vnstat_exporter.py

# Custom port, interval, and billing day
python3 vnstat_exporter.py --port 9469 --interval 60 --billing-day 28

# Daemon mode
python3 vnstat_exporter.py --billing-day 28 --daemon
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--port` | 9469 | Listening port |
| `--interval` | 60 | Collection interval (seconds) |
| `--billing-day` | 1 | Billing cycle start day of month (1-28) |
| `--daemon` | - | Run as a daemon process |

## Prometheus Configuration

```yaml
scrape_configs:
  - job_name: "vnstat"
    static_configs:
      - targets: ["your-server-ip:19209"]
        labels:
          instance: your-server-ip
          remark: your-isp-name
```

## Prerequisites

- vnstat must be installed and running on the host: `systemctl enable vnstat --now`
- For custom billing cycles, edit `/etc/vnstat.conf` and set `MonthRotate 28` (should match `--billing-day`)

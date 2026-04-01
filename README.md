# vnstat Prometheus Exporter

基于 [joaomnmoreira/vnstat-exporter](https://github.com/joaomnmoreira/vnstat-exporter) 与[rosco-pc/vnstat_exporter](https://github.com/rosco-pc/vnstat_exporter)修改，Grafana 面板参考 [Dashboard #22548](https://grafana.com/grafana/dashboards/22548)。

[English Version](README_EN.md)

## 主要改动

- 新增 `--billing-day` 参数，支持自定义计费周期起始日（1-28），适配不同服务商的账单周期
- 新增 `vnstat_traffic_billing_cycle` 指标，按计费周期累计流量（而非自然月）
- 新增 `--daemon` 参数，支持在无 systemd 的系统上以守护进程方式运行
- 守护进程模式下减少日志输出频率
- 修复容器环境下 `/dev/log` 不存在导致启动报错的问题
- 将 `print()` 统一改为 `logger.error()`

## 暴露的指标

| 指标名 | 说明 |
|--------|------|
| `vnstat_traffic_5min` | 最近 5 分钟流量 |
| `vnstat_traffic_hourly` | 小时流量 |
| `vnstat_traffic_daily` | 日流量 |
| `vnstat_traffic_monthly` | 自然月流量 |
| `vnstat_traffic_yearly` | 年流量 |
| `vnstat_traffic_total` | 累计总流量 |
| `vnstat_traffic_billing_cycle` | 当前计费周期内的累计流量 |

所有指标均带有 `interface`（网卡名）和 `direction`（`rx`/`tx`）标签。

## 依赖

```
pip install -r requirements.txt
```

依赖项：`prometheus-client`、`python-daemon`

## Docker 部署（推荐）

```yaml
services:
  vnstat-exporter:
    image: adsryen/vnstat_exporter:latest
    container_name: vnstat-exporter
    restart: always
    ports:
      - "9469:9469"
    volumes:
      - /var/lib/vnstat:/var/lib/vnstat:ro
      - /etc/localtime:/etc/localtime:ro
    command: ["--port", "9469", "--interval", "60", "--billing-day", "28"]
```

`--billing-day` 改为你的服务器实际计费日即可。

## 直接运行

```bash
# 查看帮助
python3 vnstat_exporter.py --help

# 默认启动（每月1日为计费周期起始）
python3 vnstat_exporter.py

# 自定义端口、采集间隔、计费日
python3 vnstat_exporter.py --port 9469 --interval 60 --billing-day 28

# 守护进程模式
python3 vnstat_exporter.py --billing-day 28 --daemon
```

## 参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--port` | 9469 | 监听端口 |
| `--interval` | 60 | 采集间隔（秒） |
| `--billing-day` | 1 | 每月计费周期起始日（1-28） |
| `--daemon` | - | 以守护进程方式运行 |

## Prometheus 配置

```yaml
scrape_configs:
  - job_name: "vnstat"
    static_configs:
      - targets: ["your-server-ip:19209"]
        labels:
          instance: your-server-ip
          remark: 服务商名称
```

## 前置条件

- 宿主机已安装并运行 vnstat 服务：`systemctl enable vnstat --now`
- 如需自定义计费周期，编辑 `/etc/vnstat.conf` 设置 `MonthRotate 28`（与 `--billing-day` 保持一致）

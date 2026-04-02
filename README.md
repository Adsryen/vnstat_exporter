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

## 部署方式

exporter 支持三种部署场景，核心区别在于 vnstat 数据的获取方式：

| 场景 | vnstat | exporter | 是否需要 `--vnstat-url` |
|------|--------|----------|------------------------|
| 全容器 | vergoh/vnstat 容器 | Docker | 需要（容器间 HTTP 通信） |
| 全二进制 | 宿主机 vnstatd | 宿主机二进制 | 不需要 |
| 混合 | 宿主机 vnstatd | Docker | 不需要（挂载 `/var/lib/vnstat`） |

不带 `--vnstat-url` 时，exporter 直接调用本地 `vnstat --json` 命令读取数据。

## Docker 部署

### 混合模式（宿主机 vnstat + Docker exporter，推荐）

```yaml
services:
  vnstat-exporter:
    image: adsryen/vnstat_exporter:latest
    container_name: vnstat-exporter
    restart: always
    ports:
      - "19469:9469"
    volumes:
      - /var/lib/vnstat:/var/lib/vnstat:ro
      - /etc/localtime:/etc/localtime:ro
    command: ["--port", "9469", "--interval", "60", "--billing-day", "28"]
```

### 全容器模式（vnstat 也跑在容器里）

```yaml
services:
  vnstat:
    image: vergoh/vnstat:latest
    container_name: vnstat
    network_mode: host
    volumes:
      - /var/lib/vnstat:/var/lib/vnstat

  vnstat-exporter:
    image: adsryen/vnstat_exporter:latest
    container_name: vnstat-exporter
    restart: always
    ports:
      - "19469:9469"
    volumes:
      - /etc/localtime:/etc/localtime:ro
    command: ["--port", "9469", "--interval", "60", "--billing-day", "28", "--vnstat-url", "http://vnstat:8685"]
```

`--billing-day` 改为你的服务器实际计费日即可。

## 二进制部署

### 安装

从 [Releases](../../releases) 下载对应架构的二进制文件：

```bash
sudo cp vnstat_exporter-linux-amd64 /usr/local/bin/vnstat_exporter
sudo chmod +x /usr/local/bin/vnstat_exporter
```

### systemd service

```bash
sudo cp vnstat_exporter.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vnstat_exporter
```

service 默认配置（`ExecStart` 不带 `--vnstat-url`，直接调用本地 `vnstat` 命令）：

```ini
ExecStart=/usr/local/bin/vnstat_exporter --port 19469 --interval 60 --billing-day 1
```

### 直接运行 Python 脚本

```bash
# 查看帮助
python3 vnstat_exporter.py --help

# 默认启动（每月1日为计费周期起始）
python3 vnstat_exporter.py

# 自定义端口、采集间隔、计费日
python3 vnstat_exporter.py --port 19469 --interval 60 --billing-day 28

# 守护进程模式
python3 vnstat_exporter.py --billing-day 28 --daemon
```

## 参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--port` | 19469 | 监听端口 |
| `--interval` | 60 | 采集间隔（秒） |
| `--billing-day` | 1 | 每月计费周期起始日（1-28） |
| `--vnstat-url` | - | vnstat HTTP API 地址，仅全容器模式需要 |
| `--daemon` | - | 以守护进程方式运行 |

## Prometheus 配置

```yaml
scrape_configs:
  - job_name: "vnstat"
    static_configs:
      - targets: ["your-server-ip:19469"]
        labels:
          instance: your-server-ip
          remark: 服务商名称
```

## 前置条件

- 宿主机已安装并运行 vnstat 服务：`systemctl enable vnstat --now`
- 如需自定义计费周期，编辑 `/etc/vnstat.conf` 设置 `MonthRotate 28`（与 `--billing-day` 保持一致）

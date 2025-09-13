# vnstat export for Prometheus

Based on: https://github.com/joaomnmoreira/vnstat-exporter and https://grafana.com/grafana/dashboards/22548

Changes
 * Add --daemon option to run the script as a deamon for those systems whithout systemd
 * When started in daemon mode, limit the messages send to the log (the original is very chatty, one message every interval)
 * move all print() to log.error()
 * When started without daemon mode it will behave like the original script

## requirements
 * python-daemon
 * promethuse-client

Depending on your OS you either install a package or setup a _venv_ and run
```
pip install -r requirements.txt
```
## Installation
If you have not down so yet instal and setup [prometheus](https://prometheus.io/docs/prometheus/latest/installation/) and [grafana](https://grafana.com/docs/grafana/latest/setup-grafana/)

copy the script

(optional) change the owner & group to a priviliged user (I used `_vnstat`, the user defined for running vnstat as a service)

copy the script to a sensible place on your system, e.g. `/usr/local/bin`

start the script, either
 * manually vnstat_export ..
    ```
     ./vnstat_exporter --help                                                                                                                          
    usage: vnstat_exporter [-h] [--port PORT] [--interval INTERVAL] [--daemon]
    
    VNStat Prometheus Exporter
    
    options:
      -h, --help           show this help message and exit
      --port PORT          Port to expose metrics on (default: 9469)
      --interval INTERVAL  Metrics update interval in seconds (default: 60)
      --daemon             Daemonize app on non-systemd systems
    ```
 * Or through a service
   * systemd service can be found [here]()
   * openbsd service (included in this repo  `doas rcctl start vnstat_exporter`
 
Add the vnstat exporter to your prometheus configuration

```
scrape_configs:
  ...
  # vnstat exporter
  - job_name: "vnstat"
    static_configs:
      - targets: ["sfp:9469"] 

```
and restart/reload prometheus

load the grafana dashboard above to your grafana instance

change reular expression in the `interface` variable to reflect the interfaces you're monitoting with vnstat

and Bob's your uncle

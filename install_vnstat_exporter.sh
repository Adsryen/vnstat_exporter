#!/bin/sh

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

GITHUB_REPO="Adsryen/vnstat_exporter"
DEFAULT_VERSION="v1.0.4"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="vnstat_exporter"
SERVICE_FILE="/etc/systemd/system/vnstat_exporter.service"
DEFAULT_PROXY="https://gh.we-together.club"

# 帮助信息
usage() {
    echo -e "${CYAN}用法: $0 [命令] [选项]${NC}"
    echo ""
    echo -e "命令:"
    echo -e "  install     安装 vnstat_exporter（默认）"
    echo -e "  uninstall   卸载 vnstat_exporter"
    echo ""
    echo -e "选项:"
    echo -e "  -h, --help  显示帮助信息"
    exit 0
}

# 自动检测 CPU 架构
detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)        ARCH_NAME="amd64" ;;
        aarch64|arm64) ARCH_NAME="arm64" ;;
        *)
            echo -e "${RED}不支持的架构: $ARCH${NC}"
            exit 1
            ;;
    esac
    echo -e "${CYAN}检测到系统架构: $ARCH -> $ARCH_NAME${NC}"
}

do_install() {
    detect_arch

    FILE="${BINARY_NAME}-linux-${ARCH_NAME}"

    # 检测是否已安装
    if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        echo -e "${YELLOW}检测到已安装 ${INSTALL_DIR}/${BINARY_NAME}${NC}"
        printf "${CYAN}是否卸载后重新安装？(y/n)：${NC}"
        read -r reinstall
        if [ "$reinstall" != "y" ]; then
            echo -e "${RED}安装已取消。${NC}"
            exit 0
        fi
        do_uninstall_silent
        echo -e "${GREEN}旧版本已卸载，继续安装...${NC}"
    fi

    # 优先使用本地已有文件
    if [ -f "$FILE" ]; then
        echo -e "${GREEN}找到本地文件 $FILE，跳过下载。${NC}"
    else
        # 询问是否使用代理（影响 API 和文件下载）
        printf "${CYAN}是否使用 GitHub 代理？(y/n)：${NC}"
        read -r use_proxy
        PROXY_URL=""
        if [ "$use_proxy" = "y" ]; then
            printf "${CYAN}请输入代理地址，直接回车使用默认 ${DEFAULT_PROXY}：${NC}"
            read -r input_proxy
            PROXY_URL="${input_proxy:-$DEFAULT_PROXY}"
            echo -e "${GREEN}使用代理: $PROXY_URL${NC}"
        fi

        # 获取最新版本号
        echo -e "${GREEN}获取最新版本信息...${NC}"
        API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
        LATEST_TAG=$(wget -qO- "$API_URL" | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')

        if [ -z "$LATEST_TAG" ]; then
            echo -e "${YELLOW}无法获取最新版本，使用默认版本 ${DEFAULT_VERSION}${NC}"
            LATEST_TAG="$DEFAULT_VERSION"
        fi
        echo -e "${GREEN}版本: $LATEST_TAG${NC}"

        BASE_URL="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_TAG}"
        if [ -n "$PROXY_URL" ]; then
            DOWNLOAD_URL="${PROXY_URL}/${BASE_URL}/${FILE}"
        else
            DOWNLOAD_URL="${BASE_URL}/${FILE}"
        fi

        echo -e "${YELLOW}开始下载 $FILE...${NC}"
        if wget -O "$FILE" "$DOWNLOAD_URL"; then
            echo -e "${GREEN}成功下载 $FILE${NC}"
        else
            echo -e "${RED}下载失败，URL：$DOWNLOAD_URL${NC}"
            exit 1
        fi
    fi

    # 安装二进制
    sudo install -m 755 "$FILE" "${INSTALL_DIR}/${BINARY_NAME}"
    echo -e "${GREEN}已安装到 ${INSTALL_DIR}/${BINARY_NAME}${NC}"

    # 配置端口，默认 19469
    printf "${CYAN}请输入 vnstat_exporter 服务端口（默认 19469）：${NC}"
    read -r exporter_port
    exporter_port="${exporter_port:-19469}"
    echo -e "${GREEN}服务端口: $exporter_port${NC}"

    # 配置采集间隔，默认 60
    printf "${CYAN}请输入数据采集间隔秒数（默认 60）：${NC}"
    read -r exporter_interval
    exporter_interval="${exporter_interval:-60}"
    echo -e "${GREEN}采集间隔: ${exporter_interval}s${NC}"

    # 配置 vnstat HTTP URL（可选）
    printf "${CYAN}请输入 vnstat HTTP 地址（直接回车跳过，使用本地 vnstat 命令）：${NC}"
    read -r vnstat_url

    # 配置计费日（可选）
    printf "${CYAN}请输入计费周期重置日 1-28（直接回车跳过，默认 0 不启用）：${NC}"
    read -r billing_day
    billing_day="${billing_day:-0}"

    # 构建 ExecStart 参数
    EXEC_START="${INSTALL_DIR}/${BINARY_NAME} --port=${exporter_port} --interval=${exporter_interval} --billing-day=${billing_day}"
    if [ -n "$vnstat_url" ]; then
        EXEC_START="${EXEC_START} --vnstat-url=${vnstat_url}"
    fi

    # 创建 systemd 服务
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=vnstat Prometheus Exporter
Documentation=https://github.com/${GITHUB_REPO}
After=network.target vnstat.service

[Service]
Type=simple
ExecStart=${EXEC_START}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl start vnstat_exporter
    sudo systemctl enable vnstat_exporter

    if sudo systemctl is-active --quiet vnstat_exporter; then
        echo -e "${GREEN}vnstat_exporter 已成功启动！监听端口: $exporter_port${NC}"
    else
        echo -e "${RED}vnstat_exporter 启动失败，详细状态：${NC}"
        sudo systemctl status vnstat_exporter
        exit 1
    fi
}

# 静默卸载（供重装时调用）
do_uninstall_silent() {
    if sudo systemctl is-active --quiet vnstat_exporter 2>/dev/null; then
        sudo systemctl stop vnstat_exporter
    fi
    if sudo systemctl is-enabled --quiet vnstat_exporter 2>/dev/null; then
        sudo systemctl disable vnstat_exporter
    fi
    [ -f "$SERVICE_FILE" ] && sudo rm -f "$SERVICE_FILE"
    [ -f "${INSTALL_DIR}/${BINARY_NAME}" ] && sudo rm -f "${INSTALL_DIR}/${BINARY_NAME}"
    sudo systemctl daemon-reload
}

do_uninstall() {
    echo -e "${YELLOW}开始卸载 vnstat_exporter...${NC}"
    do_uninstall_silent
    echo -e "${GREEN}vnstat_exporter 已成功卸载。${NC}"
}

# 解析参数
COMMAND="install"
for arg in "$@"; do
    case "$arg" in
        install)   COMMAND="install" ;;
        uninstall) COMMAND="uninstall" ;;
        -h|--help) usage ;;
        *)
            echo -e "${RED}未知参数: $arg${NC}"
            usage
            ;;
    esac
done

case "$COMMAND" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
esac

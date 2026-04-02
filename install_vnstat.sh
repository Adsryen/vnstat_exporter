#!/bin/sh

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

VNSTAT_VERSION="2.13"
DEFAULT_PROXY="https://gh.we-together.club"
FILE="vnstat-${VNSTAT_VERSION}.tar.gz"
BASE_URL="https://github.com/vergoh/vnstat/releases/download/v${VNSTAT_VERSION}"
URL="${BASE_URL}/${FILE}"
INSTALL_PREFIX="/usr/local"
SERVICE_FILE="/etc/systemd/system/vnstat.service"

# 帮助信息
usage() {
    echo -e "${CYAN}用法: $0 [命令] [选项]${NC}"
    echo ""
    echo -e "命令:"
    echo -e "  install     安装 vnstat（默认）"
    echo -e "  uninstall   卸载 vnstat"
    echo ""
    echo -e "选项:"
    echo -e "  -h, --help  显示帮助信息"
    exit 0
}

# 检测发行版
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_ID_LIKE="$ID_LIKE"
    else
        echo -e "${RED}无法识别操作系统${NC}"
        exit 1
    fi

    case "$OS_ID" in
        ubuntu|debian)
            PKG_MANAGER="apt"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            PKG_MANAGER="yum"
            # Rocky/RHEL 8+ 用 dnf
            command -v dnf >/dev/null 2>&1 && PKG_MANAGER="dnf"
            ;;
        *)
            # 通过 ID_LIKE 兜底
            case "$OS_ID_LIKE" in
                *debian*) PKG_MANAGER="apt" ;;
                *rhel*|*fedora*) PKG_MANAGER="yum"; command -v dnf >/dev/null 2>&1 && PKG_MANAGER="dnf" ;;
                *)
                    echo -e "${RED}不支持的发行版: $OS_ID${NC}"
                    exit 1
                    ;;
            esac
            ;;
    esac
    echo -e "${CYAN}检测到系统: $OS_ID，包管理器: $PKG_MANAGER${NC}"
}

# 安装编译依赖
install_deps() {
    echo -e "${GREEN}安装编译依赖...${NC}"
    case "$PKG_MANAGER" in
        apt)
            sudo apt-get update -y
            sudo apt-get install -y gcc make libsqlite3-dev wget
            ;;
        yum|dnf)
            sudo $PKG_MANAGER install -y gcc make sqlite-devel wget
            # RHEL/Rocky 需要 EPEL 或 powertools，sqlite-devel 一般在 base 里
            ;;
    esac
}

do_install() {
    detect_os

    # 检测是否已安装 vnstat
    if command -v vnstat >/dev/null 2>&1; then
        INSTALLED_VER=$(vnstat --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
        echo -e "${YELLOW}检测到已安装 vnstat ${INSTALLED_VER}，目标版本 ${VNSTAT_VERSION}${NC}"
        printf "${CYAN}是否卸载后重新安装？(y/n)：${NC}"
        read -r reinstall
        if [ "$reinstall" != "y" ]; then
            echo -e "${RED}安装已取消。${NC}"
            exit 0
        fi
        echo -e "${YELLOW}正在卸载旧版本...${NC}"
        do_uninstall_silent
        echo -e "${GREEN}旧版本已卸载，继续安装...${NC}"
    fi

    install_deps

    echo -e "${GREEN}开始安装 vnstat v${VNSTAT_VERSION}...${NC}"

    # 下载
    if [ ! -f "$FILE" ]; then
        echo -e "${YELLOW}文件 $FILE 未找到，开始下载...${NC}"
        printf "${CYAN}是否使用 GitHub 代理下载？(y/n)：${NC}"
        read -r yn
        if [ "$yn" = "y" ]; then
            printf "${CYAN}请输入代理地址，直接回车使用默认 ${DEFAULT_PROXY}：${NC}"
            read -r PROXY_URL
            if [ -z "$PROXY_URL" ]; then
                PROXY_URL="$DEFAULT_PROXY"
            fi
            URL="${PROXY_URL}/${BASE_URL}/${FILE}"
        fi
        if wget -O "$FILE" "$URL"; then
            echo -e "${GREEN}成功下载 $FILE${NC}"
        else
            echo -e "${RED}下载失败，请检查网络或 URL：$URL${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}找到文件 $FILE，继续安装...${NC}"
    fi

    # 解压编译安装
    SRCDIR="vnstat-${VNSTAT_VERSION}"
    tar xf "$FILE"
    cd "$SRCDIR"

    ./configure --prefix="$INSTALL_PREFIX" --sysconfdir=/etc
    make
    sudo make install

    cd ..
    rm -rf "$SRCDIR"

    # 初始化配置（如果不存在）
    if [ ! -f /etc/vnstat.conf ]; then
        sudo cp "${INSTALL_PREFIX}/share/doc/vnstat/examples/vnstat.conf" /etc/vnstat.conf 2>/dev/null || true
    fi

    # 创建数据目录
    sudo mkdir -p /var/lib/vnstat
    sudo chown -R root:root /var/lib/vnstat 2>/dev/null || true

    # 创建 systemd 服务
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=vnStat network traffic monitor
After=network.target

[Service]
Type=forking
PIDFile=/var/run/vnstat/vnstat.pid
ExecStart=${INSTALL_PREFIX}/sbin/vnstatd -d
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl start vnstat
    sudo systemctl enable vnstat

    if sudo systemctl is-active --quiet vnstat; then
        echo -e "${GREEN}vnstat v${VNSTAT_VERSION} 安装成功并已启动！${NC}"
        echo -e "${CYAN}使用 'vnstat -i <网卡>' 查看流量统计${NC}"
    else
        echo -e "${RED}vnstat 服务启动失败，详细状态：${NC}"
        sudo systemctl status vnstat
        exit 1
    fi
}

# 静默卸载（不询问数据，供重装时调用）
do_uninstall_silent() {
    if sudo systemctl is-active --quiet vnstat 2>/dev/null; then
        sudo systemctl stop vnstat
    fi
    if sudo systemctl is-enabled --quiet vnstat 2>/dev/null; then
        sudo systemctl disable vnstat
    fi
    [ -f "$SERVICE_FILE" ] && sudo rm -f "$SERVICE_FILE"
    sudo rm -f "${INSTALL_PREFIX}/bin/vnstat"
    sudo rm -f "${INSTALL_PREFIX}/sbin/vnstatd"
    sudo rm -f "${INSTALL_PREFIX}/bin/vnstati" 2>/dev/null || true
    sudo systemctl daemon-reload
}

do_uninstall() {
    detect_os
    echo -e "${YELLOW}开始卸载 vnstat...${NC}"
    do_uninstall_silent

    # 询问是否删除数据
    printf "${RED}是否同时删除 vnstat 流量数据库 /var/lib/vnstat？(y/n)：${NC}"
    read -r del_data
    if [ "$del_data" = "y" ]; then
        sudo rm -rf /var/lib/vnstat
        echo -e "${GREEN}已删除流量数据库${NC}"
    fi

    echo -e "${GREEN}vnstat 已成功卸载。${NC}"
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

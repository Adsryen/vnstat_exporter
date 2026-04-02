#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
IMAGE_NAME="adsryen/vnstat_exporter:latest"

build_docker() {
    echo ">>> 构建 Docker 镜像 ${IMAGE_NAME} ..."
    docker build --no-cache -t "${IMAGE_NAME}" "${SCRIPT_DIR}"
    echo ">>> 推送镜像 ${IMAGE_NAME} ..."
    docker push "${IMAGE_NAME}"
    echo ">>> Docker 镜像构建完成"
}

build_binary() {
    echo ">>> 用 PyInstaller 打包二进制..."
    cd "${SCRIPT_DIR}"

    # 检查 pyinstaller
    if ! command -v pyinstaller &>/dev/null; then
        echo ">>> 安装 PyInstaller..."
        pip3 install pyinstaller prometheus-client
    fi

    pyinstaller --onefile --name vnstat_exporter vnstat_exporter.py
    echo ">>> 二进制输出: ${SCRIPT_DIR}/dist/vnstat_exporter"
}

build_binary_compat() {
    echo ">>> 在 CentOS 7 容器内打包兼容旧 glibc 的二进制（适用于 GLIBC < 2.38 的系统）..."
    cd "${SCRIPT_DIR}"

    docker run --rm \
        -v "${SCRIPT_DIR}:/build" \
        centos:7 \
        bash -c "
            set -e
            # 安装 Python3 和依赖
            yum install -y epel-release
            yum install -y python3 python3-pip
            pip3 install pyinstaller prometheus-client

            cd /build
            pyinstaller --onefile --name vnstat_exporter vnstat_exporter.py
            echo '>>> 打包完成'
        "
    echo ">>> 兼容二进制输出: ${SCRIPT_DIR}/dist/vnstat_exporter"
}

show_help() {
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  docker          构建并推送 Docker 镜像（默认）"
    echo "  binary          用 PyInstaller 打包本地二进制"
    echo "  binary-compat   在 CentOS 7 容器内打包，兼容旧 glibc（< 2.38）的系统"
    echo "  all             同时执行 docker 和 binary"
    echo "  -h              显示帮助"
}

case "${1:-docker}" in
    docker)         build_docker ;;
    binary)         build_binary ;;
    binary-compat)  build_binary_compat ;;
    all)            build_docker; build_binary ;;
    -h|--help)      show_help ;;
    *)
        echo "未知命令: $1"
        show_help
        exit 1
        ;;
esac

#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
IMAGE_NAME="adsryen/vnstat_exporter:latest"
VNSTAT_VERSION="1.15"
TARBALL="vnstat-${VNSTAT_VERSION}.tar.gz"

echo ">>> 检查 ${TARBALL} ..."
if [ ! -f "${SCRIPT_DIR}/${TARBALL}" ]; then
    echo ">>> 下载 vnstat ${VNSTAT_VERSION} ..."
    wget -q "https://humdi.net/vnstat/${TARBALL}" -O "${SCRIPT_DIR}/${TARBALL}"
    echo ">>> 下载完成"
else
    echo ">>> 已存在，跳过下载"
fi

echo ">>> 构建镜像 ${IMAGE_NAME} ..."
docker build --no-cache -t "${IMAGE_NAME}" "${SCRIPT_DIR}"

echo ">>> 推送镜像 ${IMAGE_NAME} ..."
docker push "${IMAGE_NAME}"

echo ">>> 完成"

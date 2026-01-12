#!/bin/bash
echo "=== 开始卸载 Docker 环境 ==="
systemctl stop docker
systemctl disable docker
rm -f /etc/systemd/system/docker.service
systemctl daemon-reload

# 删除二进制
rm -f /usr/bin/docker* /usr/bin/containerd* /usr/bin/runc /usr/bin/ctr

# 提示数据删除
echo "二进制文件已删除。"
echo "注意：镜像和容器数据位于 /var/lib/docker，脚本未删除该目录以防误删数据。"
echo "如需彻底清除，请执行: rm -rf /var/lib/docker"

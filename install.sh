#!/bin/bash

# =================================================================
# 脚本名称: Docker 离线全栈部署脚本
# 支持架构: x86_64, aarch64
# 支持系统: Ubuntu, CentOS, Kylin V10
# =================================================================

# --- 配置变量 ---
WORK_DIR=$(cd "$(dirname "$0")"; pwd)
INSTALL_BIN="/usr/bin"
SERVICE_FILE="/etc/systemd/system/docker.service"

# --- 辅助函数 ---
log_info() { echo -e "\033[32m[INFO] $1\033[0m"; }
log_warn() { echo -e "\033[33m[WARN] $1\033[0m"; }
log_err()  { echo -e "\033[31m[ERROR] $1\033[0m"; }

# 1. 权限检查
if [[ $EUID -ne 0 ]]; then
   log_err "必须以 root 权限运行此脚本"
   exit 1
fi

sudo apt-get install -y iptables

# 2. 架构检测与路径选择
ARCH=$(uname -m)
log_info "当前系统架构: $ARCH"

if [[ "$ARCH" == "x86_64" ]]; then
    PKG_DIR="$WORK_DIR/pkgs/x86_64"
elif [[ "$ARCH" == "aarch64" ]]; then
    PKG_DIR="$WORK_DIR/pkgs/aarch64"
else
    log_err "不支持的架构: $ARCH"
    exit 1
fi

DOCKER_TGZ=$(find "$PKG_DIR" -name "docker-*.tgz" | head -n 1)
COMPOSE_BIN="$PKG_DIR/docker-compose-linux-${ARCH}"

if [[ ! -f "$DOCKER_TGZ" ]]; then
    log_err "未在 $PKG_DIR 找到 Docker 安装包"
    exit 1
fi

log_info "DOCKER_TGZ: ${DOCKER_TGZ}"
log_info "COMPOSE_BIN: ${COMPOSE_BIN}"

# 3. 清理旧环境
log_info "正在清理旧版本..."
systemctl stop docker >/dev/null 2>&1
rm -f $INSTALL_BIN/docker* $INSTALL_BIN/containerd* $INSTALL_BIN/runc $INSTALL_BIN/ctr

# 4. 安装二进制文件
log_info "解压并安装 Docker 二进制文件..."
tar -zxvf "$DOCKER_TGZ" -C "$WORK_DIR" >/dev/null
if [ $? -ne 0 ]; then
    log_err "解压失败"
    exit 1
fi

# 移动文件
cp "$WORK_DIR/docker/"* "$INSTALL_BIN/"
chmod +x $INSTALL_BIN/docker*
rm -rf "$WORK_DIR/docker" # 清理临时目录

# 安装 Docker Compose
if [[ -f "$COMPOSE_BIN" ]]; then
    log_info "安装 Docker Compose..."
    cp "$COMPOSE_BIN" "$INSTALL_BIN/docker-compose"
    chmod +x "$INSTALL_BIN/docker-compose"
fi

# 5. 配置 Systemd 服务 (兼容 SELinux)
log_info "配置 Systemd 服务..."
cat > $SERVICE_FILE <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
# 关键配置: 禁用 SELinux 支持以防报错，使用 overlay2 驱动
ExecStart=/usr/bin/dockerd --selinux-enabled=false --storage-driver=overlay2
ExecReload=/bin/kill -s HUP \$MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
EOF

chmod +x $SERVICE_FILE

# 6. 启动 Docker
log_info "启动 Docker 服务..."
systemctl daemon-reload
systemctl enable docker
systemctl start docker

# 等待 Docker 守护进程完全启动
log_info "等待 Docker 守护进程就绪..."
TIMEOUT=30
while ! docker info >/dev/null 2>&1; do
    TIMEOUT=$(($TIMEOUT - 1))
    if [ $TIMEOUT -le 0 ]; then
        log_err "Docker 启动超时，请检查 systemctl status docker"
        exit 1
    fi
    sleep 1
done
log_info "Docker 启动成功！"

log_info "=== 部署全部完成 ==="
docker version

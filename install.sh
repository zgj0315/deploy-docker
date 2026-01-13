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
CONFIG_DIR="/etc/docker"
DAEMON_JSON="${CONFIG_DIR}/daemon.json"

log_info() {
    echo -e "\033[32m[INFO]\033[0m $(date '+%Y-%m-%d %H:%M:%S') $*"
}

log_warn() {
    echo -e "\033[33m[WARN]\033[0m $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_error() {
    echo -e "\033[31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
    exit 1
}

# 权限检查
if [[ $EUID -ne 0 ]]; then
   log_error "必须以 root 权限运行此脚本"
fi

# 架构检测与路径选择
ARCH=$(uname -m)
log_info "当前系统架构: $ARCH"

if [[ "$ARCH" == "x86_64" ]]; then
    PKG_DIR="${WORK_DIR}/pkgs/x86_64"
elif [[ "$ARCH" == "aarch64" ]]; then
    PKG_DIR="${WORK_DIR}/pkgs/aarch64"
else
    log_error "不支持的架构: $ARCH"
fi

DOCKER_TGZ=$(find "$PKG_DIR" -name "docker-*.tgz" | head -n 1)
COMPOSE_BIN="${PKG_DIR}/docker-compose-linux-${ARCH}"

if [[ ! -f "$DOCKER_TGZ" ]]; then
    log_error "未在 ${PKG_DIR} 找到 Docker 安装包"
fi

log_info "DOCKER_TGZ: ${DOCKER_TGZ}"
log_info "COMPOSE_BIN: ${COMPOSE_BIN}"

# 清理旧环境
log_info "正在清理旧版本..."
systemctl stop docker >/dev/null 2>&1
systemctl disable docker >/dev/null 2>&1

# 防止 Text file busy，先移除旧文件
log_info "Clean old binaries in ${INSTALL_BIN}"
rm -f "${INSTALL_BIN}"/docker* "${INSTALL_BIN}"/containerd* "${INSTALL_BIN}"/runc "${INSTALL_BIN}"/ctr

log_info "Clean ${SERVICE_FILE}"
rm -f "$SERVICE_FILE"

# 安装二进制文件
log_info "解压并安装 Docker 二进制文件..."
tar -zxvf "$DOCKER_TGZ" -C "$WORK_DIR" >/dev/null
if [ $? -ne 0 ]; then
    log_error "解压失败"
fi

# 使用 install 命令安装，自动设置权限 755
log_info "安装二进制文件到 ${INSTALL_BIN}..."
install -m 755 "${WORK_DIR}"/docker/* "${INSTALL_BIN}/"
rm -rf "${WORK_DIR}/docker"

# 安装 Docker Compose
if [[ -f "$COMPOSE_BIN" ]]; then
    log_info "安装 Docker Compose..."
    # [修复] 修正引号，将源文件和目标路径分开
    install -m 755 "${COMPOSE_BIN}" "${INSTALL_BIN}/docker-compose"
else
    log_error "未找到 Docker Compose 二进制文件"
fi

# 创建 Docker 组
if ! getent group docker > /dev/null; then
    log_info "创建 docker 用户组..."
    groupadd docker
fi

# 获取调用 sudo 的原始用户，并加入 docker 组
if [ -n "$SUDO_USER" ]; then
    log_info "检测到 sudo 用户: $SUDO_USER"
    usermod -aG docker "$SUDO_USER"
    log_info "已将用户 $SUDO_USER 加入 docker 组"
else
    log_warn "无法检测到 sudo 用户 (可能是直接以 root 登录)。"
    log_warn "请手动执行: usermod -aG docker <your-username>"
fi

# 配置 daemon.json
log_info "生成生产环境配置 daemon.json..."
mkdir -p "$CONFIG_DIR"
cat > "$DAEMON_JSON" <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65535,
      "Soft": 65535
    }
  }
}
EOF

# 配置 Systemd 服务
log_info "配置 Systemd 服务..."
cat > $SERVICE_FILE <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
# 使用标准启动命令，参数由 daemon.json 接管
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP \$MAINPID
TimeoutSec=0
RestartSec=2
Restart=always

# 生产环境性能调优
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE_FILE"

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
        log_error "Docker 启动超时，请检查 systemctl status docker"
    fi
    sleep 1
done

log_info "=== 部署全部完成 ==="
docker info | grep "Cgroup Driver"
docker info | grep "Storage Driver"
docker version

log_info "注意：用户组更改生效需要重新登录。"
log_info "请执行命令 'newgrp docker' 或 退出终端重新连接 以便立即使用 docker 命令。"

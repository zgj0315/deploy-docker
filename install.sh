#!/bin/bash

# =================================================================
# 脚本名称: Docker 离线全栈部署脚本
# 支持架构: x86_64, aarch64
# 支持系统: Ubuntu, CentOS, Kylin V10
# =================================================================

set -eE

# --- 配置变量 ---
WORK_DIR=$(cd "$(dirname "$0")"; pwd)
INSTALL_BIN="/usr/bin"
SERVICE_FILE="/etc/systemd/system/docker.service"
DOCKER_DATA_DIR="/var/lib/docker"
LOG_FILE="/var/log/docker-install-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR=""
INSTALL_STATE="none"

# --- 辅助函数 ---
log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo -e "\033[32m${msg}\033[0m" | tee -a "$LOG_FILE"
}

log_warn() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1"
    echo -e "\033[33m${msg}\033[0m" | tee -a "$LOG_FILE"
}

log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "\033[31m${msg}\033[0m" | tee -a "$LOG_FILE"
}

# --- 日志初始化 ---
setup_logging() {
    touch "$LOG_FILE" 2>/dev/null || {
        LOG_FILE="/tmp/docker-install-$(date +%Y%m%d-%H%M%S).log"
        touch "$LOG_FILE"
    }
    log_info "日志文件: $LOG_FILE"
}

# --- 操作系统检测 ---
detect_os() {
    local os_type=""

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu) os_type="ubuntu" ;;
            centos|rhel) os_type="centos" ;;
            kylin) os_type="kylin" ;;
        esac
    fi

    [[ -z "$os_type" ]] && [[ -f /etc/kylin-release ]] && os_type="kylin"
    [[ -z "$os_type" ]] && [[ -f /etc/redhat-release ]] && os_type="centos"

    if [[ -z "$os_type" ]]; then
        local uname_output=$(uname -a)
        [[ "$uname_output" =~ [Kk]ylin ]] && os_type="kylin"
    fi

    echo "$os_type"
}

# --- 安装前检查 ---
preflight_checks() {
    log_info "执行安装前检查..."

    # 检查内核版本
    local kernel_version=$(uname -r | cut -d. -f1,2)
    local kernel_major=$(echo "$kernel_version" | cut -d. -f1)
    local kernel_minor=$(echo "$kernel_version" | cut -d. -f2)

    if [[ $kernel_major -lt 3 ]] || [[ $kernel_major -eq 3 && $kernel_minor -lt 10 ]]; then
        log_err "内核版本过低: $(uname -r)，需要至少 3.10"
        return 1
    fi
    log_info "内核版本检查通过: $(uname -r)"

    # 检查磁盘空间
    local available_space=$(df -BG "$DOCKER_DATA_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || echo "0")
    if [[ -z "$available_space" ]]; then
        available_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    fi

    if [[ $available_space -lt 10 ]]; then
        log_warn "磁盘空间不足 10GB (当前: ${available_space}GB)，可能影响 Docker 运行"
    else
        log_info "磁盘空间检查通过: ${available_space}GB 可用"
    fi

    # 检查 systemd
    if ! command -v systemctl &> /dev/null; then
        log_err "未找到 systemctl，需要 systemd 支持"
        return 1
    fi
    log_info "systemd 检查通过"

    # 检查 Docker 是否已运行
    if systemctl is-active docker &>/dev/null; then
        log_warn "Docker 服务正在运行，将被停止并重新安装"
    fi

    # 检查架构与安装包匹配
    if [[ ! -f "$DOCKER_TGZ" ]]; then
        log_err "未找到 Docker 安装包: $DOCKER_TGZ"
        return 1
    fi
    log_info "Docker 安装包检查通过: $DOCKER_TGZ"

    log_info "所有安装前检查通过"
    return 0
}

# --- 备份现有安装 ---
backup_existing() {
    log_info "备份现有 Docker 安装..."

    BACKUP_DIR="/tmp/docker-backup-$(date +%s)"
    mkdir -p "$BACKUP_DIR"

    local backed_up=false

    # 备份二进制文件
    for bin in docker dockerd docker-init docker-proxy containerd containerd-shim containerd-shim-runc-v2 runc ctr; do
        if [[ -f "$INSTALL_BIN/$bin" ]]; then
            cp "$INSTALL_BIN/$bin" "$BACKUP_DIR/" 2>/dev/null && backed_up=true
        fi
    done

    # 备份服务文件
    if [[ -f "$SERVICE_FILE" ]]; then
        cp "$SERVICE_FILE" "$BACKUP_DIR/" && backed_up=true
    fi

    if [[ "$backed_up" == "true" ]]; then
        log_info "备份已保存到: $BACKUP_DIR"
        INSTALL_STATE="backup_created"
    else
        log_info "未发现现有安装，无需备份"
        rmdir "$BACKUP_DIR" 2>/dev/null || true
        BACKUP_DIR=""
    fi

    return 0
}

# --- 回滚函数 ---
rollback() {
    local exit_code=$?
    log_err "安装失败 (退出码: $exit_code)，开始回滚..."

    case "$INSTALL_STATE" in
        service_started|service_configured)
            log_info "停止 Docker 服务..."
            systemctl stop docker 2>/dev/null || true
            systemctl disable docker 2>/dev/null || true
            ;&
        binaries_installed)
            log_info "删除已安装的二进制文件..."
            rm -f $INSTALL_BIN/docker* $INSTALL_BIN/containerd* $INSTALL_BIN/runc $INSTALL_BIN/ctr 2>/dev/null || true
            rm -f "$SERVICE_FILE" 2>/dev/null || true
            systemctl daemon-reload 2>/dev/null || true
            ;&
        backup_created)
            if [[ -n "$BACKUP_DIR" ]] && [[ -d "$BACKUP_DIR" ]]; then
                log_info "恢复备份文件..."
                cp "$BACKUP_DIR"/* "$INSTALL_BIN/" 2>/dev/null || true
                if [[ -f "$BACKUP_DIR/docker.service" ]]; then
                    cp "$BACKUP_DIR/docker.service" "$SERVICE_FILE"
                    systemctl daemon-reload
                    systemctl start docker 2>/dev/null || true
                fi
                log_info "已恢复到之前的状态"
            fi
            ;;
    esac

    log_err "回滚完成，请查看日志: $LOG_FILE"
    exit $exit_code
}

# --- 配置 daemon.json ---
configure_daemon() {
    local os_type=$1
    local daemon_config="/etc/docker/daemon.json"

    log_info "配置 Docker daemon..."

    mkdir -p /etc/docker

    # 检测存储驱动支持
    local storage_driver="overlay2"
    if [[ "$os_type" == "centos" ]]; then
        local kernel_version=$(uname -r | cut -d. -f1,2)
        local kernel_major=$(echo "$kernel_version" | cut -d. -f1)
        if [[ $kernel_major -lt 4 ]]; then
            log_warn "内核版本 < 4.0，使用 devicemapper 存储驱动"
            storage_driver="devicemapper"
        fi
    fi

    # 创建 daemon.json
    cat > "$daemon_config" <<EOF
{
  "storage-driver": "$storage_driver",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF

    log_info "Docker daemon 配置完成: $daemon_config"
    log_info "存储驱动: $storage_driver"
}

# --- 等待 Docker 启动 ---
wait_for_docker() {
    log_info "等待 Docker 守护进程就绪..."
    local timeout=60
    local count=0

    while [[ $count -lt $timeout ]]; do
        # 检查 systemd 服务状态
        if systemctl is-active docker &>/dev/null; then
            # 检查 containerd 进程
            if pgrep -x containerd &>/dev/null; then
                # 检查 Docker socket
                if [[ -S /var/run/docker.sock ]]; then
                    # 验证 docker info
                    if docker info &>/dev/null; then
                        log_info "Docker 启动成功！"
                        return 0
                    fi
                fi
            fi
        fi

        sleep 1
        count=$((count + 1))
    done

    log_err "Docker 启动超时，请检查: systemctl status docker"
    return 1
}

# --- 主流程 ---
main() {
    # 设置错误处理
    trap rollback ERR

    # 初始化日志
    setup_logging

    log_info "=== 开始 Docker 离线安装 ==="

    # 1. 权限检查
    if [[ $EUID -ne 0 ]]; then
        log_err "必须以 root 权限运行此脚本"
        exit 1
    fi

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

    DOCKER_TGZ=$(find "$PKG_DIR" -name "docker-*.tgz" 2>/dev/null | head -n 1)
    COMPOSE_BIN="$PKG_DIR/docker-compose-linux-${ARCH}"

    log_info "安装包目录: $PKG_DIR"
    log_info "Docker 安装包: $DOCKER_TGZ"
    log_info "Compose 二进制: $COMPOSE_BIN"

    # 3. 检测操作系统
    OS_TYPE=$(detect_os)
    if [[ -z "$OS_TYPE" ]]; then
        log_err "无法检测操作系统类型"
        exit 1
    fi
    log_info "检测到操作系统: $OS_TYPE"

    # 4. 安装前检查
    if ! preflight_checks; then
        log_err "安装前检查失败"
        exit 1
    fi

    # 5. 备份现有安装
    backup_existing

    # 6. 清理旧环境
    log_info "正在清理旧版本..."
    systemctl stop docker &>/dev/null || true
    rm -f $INSTALL_BIN/docker* $INSTALL_BIN/containerd* $INSTALL_BIN/runc $INSTALL_BIN/ctr

    # 7. 安装二进制文件
    log_info "解压并安装 Docker 二进制文件..."
    tar -zxf "$DOCKER_TGZ" -C "$WORK_DIR"
    if [[ $? -ne 0 ]]; then
        log_err "解压失败"
        exit 1
    fi

    cp "$WORK_DIR/docker/"* "$INSTALL_BIN/"
    chmod +x $INSTALL_BIN/docker* $INSTALL_BIN/containerd* $INSTALL_BIN/runc $INSTALL_BIN/ctr
    rm -rf "$WORK_DIR/docker"

    INSTALL_STATE="binaries_installed"
    log_info "二进制文件安装完成"

    # 8. 安装 Docker Compose
    if [[ -f "$COMPOSE_BIN" ]]; then
        log_info "安装 Docker Compose..."
        cp "$COMPOSE_BIN" "$INSTALL_BIN/docker-compose"
        chmod +x "$INSTALL_BIN/docker-compose"
    else
        log_warn "未找到 Docker Compose: $COMPOSE_BIN"
    fi

    # 9. 配置 daemon.json
    configure_daemon "$OS_TYPE"

    # 10. 配置 Systemd 服务
    log_info "配置 Systemd 服务..."
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
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

    chmod 644 $SERVICE_FILE
    INSTALL_STATE="service_configured"
    log_info "Systemd 服务配置完成"

    # 11. 启动 Docker
    log_info "启动 Docker 服务..."
    systemctl daemon-reload
    systemctl enable docker
    systemctl start docker

    INSTALL_STATE="service_started"

    # 12. 等待 Docker 启动
    if ! wait_for_docker; then
        log_err "Docker 启动失败"
        exit 1
    fi

    # 13. 显示版本信息
    log_info "=== Docker 安装完成 ==="
    docker version | tee -a "$LOG_FILE"
    docker-compose --version 2>/dev/null | tee -a "$LOG_FILE" || log_warn "Docker Compose 未安装"

    log_info "日志文件: $LOG_FILE"

    # 14. 运行验证脚本
    if [[ -f "$WORK_DIR/validate.sh" ]]; then
        log_info "运行安装验证..."
        bash "$WORK_DIR/validate.sh"
    fi

    # 清理备份（安装成功）
    if [[ -n "$BACKUP_DIR" ]] && [[ -d "$BACKUP_DIR" ]]; then
        rm -rf "$BACKUP_DIR"
        log_info "已清理备份文件"
    fi
}

main "$@"

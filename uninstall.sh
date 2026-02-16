#!/bin/bash

# =================================================================
# 脚本名称: Docker 卸载脚本
# 功能: 完全卸载 Docker 环境，支持备份和清理
# =================================================================

set -e

# --- 配置变量 ---
INSTALL_BIN="/usr/bin"
SERVICE_FILE="/etc/systemd/system/docker.service"
DOCKER_DATA_DIR="/var/lib/docker"
DOCKER_CONFIG_DIR="/etc/docker"

# --- 日志函数 ---
log_info() { echo -e "\033[32m[INFO] $1\033[0m"; }
log_warn() { echo -e "\033[33m[WARN] $1\033[0m"; }
log_err()  { echo -e "\033[31m[ERROR] $1\033[0m"; }

# --- 权限检查 ---
if [[ $EUID -ne 0 ]]; then
   log_err "必须以 root 权限运行此脚本"
   exit 1
fi

# --- 确认卸载 ---
confirm_uninstall() {
    log_warn "=== Docker 卸载确认 ==="
    echo "此操作将："
    echo "  1. 停止并删除 Docker 服务"
    echo "  2. 删除所有 Docker 二进制文件"
    echo "  3. 可选：删除 Docker 数据目录（镜像、容器、卷等）"
    echo ""

    read -p "确认卸载 Docker？(yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "取消卸载"
        exit 0
    fi
}

# --- 备份数据 ---
backup_data() {
    if [[ ! -d "$DOCKER_DATA_DIR" ]]; then
        log_info "Docker 数据目录不存在，无需备份"
        return 0
    fi

    local data_size=$(du -sh "$DOCKER_DATA_DIR" 2>/dev/null | awk '{print $1}')
    log_info "Docker 数据目录大小: $data_size"

    read -p "是否备份 Docker 数据目录？(yes/no): " backup_choice
    if [[ "$backup_choice" == "yes" ]]; then
        local backup_file="/tmp/docker-data-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
        log_info "正在备份到: $backup_file"
        log_warn "这可能需要一些时间..."

        if tar -czf "$backup_file" -C / "var/lib/docker" 2>/dev/null; then
            log_info "备份完成: $backup_file"
        else
            log_err "备份失败"
            read -p "是否继续卸载？(yes/no): " continue_choice
            if [[ "$continue_choice" != "yes" ]]; then
                exit 1
            fi
        fi
    fi
}

# --- 停止服务 ---
stop_services() {
    log_info "=== 停止 Docker 服务 ==="

    if systemctl is-active docker &>/dev/null; then
        log_info "停止 Docker 服务..."
        systemctl stop docker
    else
        log_info "Docker 服务未运行"
    fi

    if systemctl is-enabled docker &>/dev/null; then
        log_info "禁用 Docker 服务..."
        systemctl disable docker
    fi

    # 停止所有 Docker 相关进程
    log_info "停止 Docker 相关进程..."
    pkill -9 dockerd 2>/dev/null || true
    pkill -9 containerd 2>/dev/null || true
    pkill -9 docker-proxy 2>/dev/null || true

    sleep 2
}

# --- 清理网络 ---
cleanup_network() {
    log_info "=== 清理 Docker 网络 ==="

    # 删除 Docker 创建的网络接口
    for iface in $(ip link show | grep docker | awk -F: '{print $2}' | tr -d ' '); do
        log_info "删除网络接口: $iface"
        ip link delete "$iface" 2>/dev/null || true
    done

    # 清理 iptables 规则
    log_info "清理 iptables 规则..."
    iptables -t nat -F DOCKER 2>/dev/null || true
    iptables -t filter -F DOCKER 2>/dev/null || true
    iptables -t nat -X DOCKER 2>/dev/null || true
    iptables -t filter -X DOCKER 2>/dev/null || true
    iptables -t filter -F DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
    iptables -t filter -F DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
    iptables -t filter -X DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
    iptables -t filter -X DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
    iptables -t filter -F DOCKER-USER 2>/dev/null || true
    iptables -t filter -X DOCKER-USER 2>/dev/null || true

    log_info "网络清理完成"
}

# --- 删除二进制文件 ---
remove_binaries() {
    log_info "=== 删除 Docker 二进制文件 ==="

    local binaries=(
        "docker"
        "dockerd"
        "docker-init"
        "docker-proxy"
        "docker-compose"
        "containerd"
        "containerd-shim"
        "containerd-shim-runc-v1"
        "containerd-shim-runc-v2"
        "runc"
        "ctr"
    )

    for bin in "${binaries[@]}"; do
        if [[ -f "$INSTALL_BIN/$bin" ]]; then
            log_info "删除: $INSTALL_BIN/$bin"
            rm -f "$INSTALL_BIN/$bin"
        fi
    done

    log_info "二进制文件删除完成"
}

# --- 删除服务文件 ---
remove_service() {
    log_info "=== 删除 Systemd 服务 ==="

    if [[ -f "$SERVICE_FILE" ]]; then
        log_info "删除: $SERVICE_FILE"
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    else
        log_info "服务文件不存在"
    fi
}

# --- 删除配置和数据 ---
remove_data() {
    log_info "=== 清理配置和数据 ==="

    read -p "是否删除 Docker 数据目录 $DOCKER_DATA_DIR？(yes/no): " delete_data
    if [[ "$delete_data" == "yes" ]]; then
        if [[ -d "$DOCKER_DATA_DIR" ]]; then
            log_warn "正在删除 Docker 数据目录（包括所有镜像、容器、卷）..."
            rm -rf "$DOCKER_DATA_DIR"
            log_info "数据目录已删除"
        else
            log_info "数据目录不存在"
        fi
    else
        log_info "保留数据目录: $DOCKER_DATA_DIR"
    fi

    # 删除配置目录
    if [[ -d "$DOCKER_CONFIG_DIR" ]]; then
        log_info "删除配置目录: $DOCKER_CONFIG_DIR"
        rm -rf "$DOCKER_CONFIG_DIR"
    fi

    # 删除日志文件
    log_info "清理日志文件..."
    rm -f /var/log/docker-install-*.log 2>/dev/null || true
}

# --- 删除用户组 ---
remove_group() {
    log_info "=== 清理 Docker 用户组 ==="

    if getent group docker &>/dev/null; then
        read -p "是否删除 docker 用户组？(yes/no): " delete_group
        if [[ "$delete_group" == "yes" ]]; then
            log_info "删除 docker 用户组..."
            groupdel docker 2>/dev/null || log_warn "删除用户组失败"
        else
            log_info "保留 docker 用户组"
        fi
    else
        log_info "docker 用户组不存在"
    fi
}

# --- 主流程 ---
main() {
    log_info "=== Docker 卸载脚本 ==="
    echo ""

    # 确认卸载
    confirm_uninstall
    echo ""

    # 备份数据
    backup_data
    echo ""

    # 停止服务
    stop_services
    echo ""

    # 清理网络
    cleanup_network
    echo ""

    # 删除二进制文件
    remove_binaries
    echo ""

    # 删除服务文件
    remove_service
    echo ""

    # 删除配置和数据
    remove_data
    echo ""

    # 删除用户组
    remove_group
    echo ""

    log_info "=== Docker 卸载完成 ==="
    log_info "如需重新安装，请运行 install.sh"
}

main "$@"

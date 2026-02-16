#!/bin/bash

set -e

# =================================================================
# 脚本名称: Docker 安装包下载脚本
# 功能: 下载 Docker 和 Docker Compose 离线安装包
# 支持架构: x86_64, aarch64
# =================================================================

# --- 配置变量 ---
DOCKER_VERSION="29.2.1"
COMPOSE_VERSION="v5.0.2"
WORK_DIR=$(cd "$(dirname "$0")"; pwd)

# --- 日志函数 ---
log_info() { echo -e "\033[32m[INFO] $1\033[0m"; }
log_warn() { echo -e "\033[33m[WARN] $1\033[0m"; }
log_err()  { echo -e "\033[31m[ERROR] $1\033[0m"; }

# --- 下载函数（支持断点续传和进度显示） ---
download_file() {
    local url=$1
    local output=$2
    local max_retries=3

    log_info "下载: $(basename "$output")"

    for ((i=1; i<=max_retries; i++)); do
        if curl -C - -SL --progress-bar "$url" -o "$output"; then
            log_info "下载成功: $(basename "$output")"
            return 0
        fi

        if [[ $i -lt $max_retries ]]; then
            log_warn "下载失败，5秒后重试 ($i/$max_retries)..."
            sleep 5
        fi
    done

    log_err "下载失败: $url"
    return 1
}

# --- 验证文件大小 ---
validate_file_size() {
    local file=$1
    local min_size_mb=$2

    if [[ ! -f "$file" ]]; then
        log_err "文件不存在: $file"
        return 1
    fi

    local size_mb=$(du -m "$file" | cut -f1)
    if [[ $size_mb -lt $min_size_mb ]]; then
        log_err "文件大小异常: $(basename "$file") ($size_mb MB < $min_size_mb MB)"
        rm -f "$file"
        return 1
    fi

    log_info "文件大小验证通过: $(basename "$file") ($size_mb MB)"
    return 0
}

# --- 检查磁盘空间 ---
check_disk_space() {
    local target_dir=$1
    local required_gb=$2

    # 使用 df -k 获取 KB 单位的可用空间（跨平台兼容）
    local available_kb=$(df -k "$target_dir" 2>/dev/null | awk 'NR==2 {print $4}')

    if [[ -z "$available_kb" ]]; then
        log_warn "无法检测磁盘空间，跳过检查"
        return 0
    fi

    # 转换为 GB（1GB = 1048576 KB）
    local available_gb=$((available_kb / 1048576))

    if [[ $available_gb -lt $required_gb ]]; then
        log_err "磁盘空间不足: 需要 ${required_gb}GB，可用 ${available_gb}GB"
        return 1
    fi

    log_info "磁盘空间检查通过: ${available_gb}GB 可用"
    return 0
}

# --- 主流程 ---
main() {
    log_info "=== 开始下载 Docker 安装包 ==="
    log_info "Docker 版本: $DOCKER_VERSION"
    log_info "Docker Compose 版本: $COMPOSE_VERSION"

    # 检查磁盘空间（至少需要 1GB）
    if ! check_disk_space "$WORK_DIR" 1; then
        exit 1
    fi

    # 创建目录
    mkdir -p "$WORK_DIR/pkgs/aarch64"
    mkdir -p "$WORK_DIR/pkgs/x86_64"

    local failed_downloads=()

    # 下载 aarch64 包
    log_info "--- 下载 aarch64 架构安装包 ---"

    if ! download_file \
        "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-aarch64" \
        "$WORK_DIR/pkgs/aarch64/docker-compose-linux-aarch64"; then
        failed_downloads+=("docker-compose-linux-aarch64")
    fi

    if ! download_file \
        "https://download.docker.com/linux/static/stable/aarch64/docker-${DOCKER_VERSION}.tgz" \
        "$WORK_DIR/pkgs/aarch64/docker-${DOCKER_VERSION}.tgz"; then
        failed_downloads+=("docker-${DOCKER_VERSION}.tgz (aarch64)")
    fi

    # 下载 x86_64 包
    log_info "--- 下载 x86_64 架构安装包 ---"

    if ! download_file \
        "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
        "$WORK_DIR/pkgs/x86_64/docker-compose-linux-x86_64"; then
        failed_downloads+=("docker-compose-linux-x86_64")
    fi

    if ! download_file \
        "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" \
        "$WORK_DIR/pkgs/x86_64/docker-${DOCKER_VERSION}.tgz"; then
        failed_downloads+=("docker-${DOCKER_VERSION}.tgz (x86_64)")
    fi

    # 验证文件
    log_info "--- 验证下载文件 ---"

    local validation_failed=false

    if ! validate_file_size "$WORK_DIR/pkgs/aarch64/docker-compose-linux-aarch64" 25; then
        validation_failed=true
    fi

    if ! validate_file_size "$WORK_DIR/pkgs/aarch64/docker-${DOCKER_VERSION}.tgz" 60; then
        validation_failed=true
    fi

    if ! validate_file_size "$WORK_DIR/pkgs/x86_64/docker-compose-linux-x86_64" 25; then
        validation_failed=true
    fi

    if ! validate_file_size "$WORK_DIR/pkgs/x86_64/docker-${DOCKER_VERSION}.tgz" 70; then
        validation_failed=true
    fi

    # 报告结果
    if [[ ${#failed_downloads[@]} -gt 0 ]]; then
        log_err "以下文件下载失败: ${failed_downloads[*]}"
        exit 1
    fi

    if [[ "$validation_failed" == "true" ]]; then
        log_err "文件验证失败，请重新运行脚本"
        exit 1
    fi

    log_info "=== 所有文件下载完成 ==="
    log_info "--- aarch64 文件列表 ---"
    ls -lh "$WORK_DIR/pkgs/aarch64/"
    log_info "--- x86_64 文件列表 ---"
    ls -lh "$WORK_DIR/pkgs/x86_64/"
}

main "$@"

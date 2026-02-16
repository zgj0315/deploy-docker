#!/bin/bash

set -e

# =================================================================
# 脚本名称: Docker 离线部署包打包脚本
# 功能: 创建包含所有架构的完整部署包
# 输出: dist/deploy-docker-{version}.tar.gz
# =================================================================

# --- 配置变量 ---
WORK_DIR=$(cd "$(dirname "$0")"; pwd)
DIST_DIR="$WORK_DIR/dist"

# 从 download_pkg.sh 读取版本号
DOCKER_VERSION=$(grep '^DOCKER_VERSION=' "$WORK_DIR/download_pkg.sh" | cut -d'"' -f2)
COMPOSE_VERSION=$(grep '^COMPOSE_VERSION=' "$WORK_DIR/download_pkg.sh" | cut -d'"' -f2)

# 输出文件名
OUTPUT_FILE="deploy-docker-${DOCKER_VERSION}.tar.gz"

# --- 日志函数 ---
log_info() { echo -e "\033[32m[INFO] $1\033[0m"; }
log_warn() { echo -e "\033[33m[WARN] $1\033[0m"; }
log_err()  { echo -e "\033[31m[ERROR] $1\033[0m"; }

# --- 文件验证函数 ---
validate_file() {
    local file=$1
    local min_size_mb=$2
    local description=$3

    # 检查文件是否存在
    if [[ ! -f "$file" ]]; then
        log_err "缺少必需文件: $description"
        return 1
    fi

    # 检查文件大小
    local size_mb=$(du -m "$file" | cut -f1)
    if [[ $size_mb -lt $min_size_mb ]]; then
        log_err "文件大小异常: $description ($size_mb MB < $min_size_mb MB)"
        return 1
    fi

    log_info "✓ $description ($size_mb MB)"
    return 0
}

# --- 验证所有必需文件 ---
validate_all_files() {
    log_info "=== 验证打包文件 ==="

    local validation_failed=false

    # 验证脚本文件
    for script in install.sh pre-install.sh validate.sh uninstall.sh download_pkg.sh; do
        if ! validate_file "$WORK_DIR/$script" 0 "脚本: $script"; then
            validation_failed=true
        fi
    done

    # 验证文档
    if ! validate_file "$WORK_DIR/README.md" 0 "文档: README.md"; then
        validation_failed=true
    fi

    # 验证 x86_64 包
    if ! validate_file "$WORK_DIR/pkgs/x86_64/docker-${DOCKER_VERSION}.tgz" 70 "x86_64: docker-${DOCKER_VERSION}.tgz"; then
        validation_failed=true
    fi
    if ! validate_file "$WORK_DIR/pkgs/x86_64/docker-compose-linux-x86_64" 25 "x86_64: docker-compose"; then
        validation_failed=true
    fi

    # 验证 aarch64 包
    if ! validate_file "$WORK_DIR/pkgs/aarch64/docker-${DOCKER_VERSION}.tgz" 60 "aarch64: docker-${DOCKER_VERSION}.tgz"; then
        validation_failed=true
    fi
    if ! validate_file "$WORK_DIR/pkgs/aarch64/docker-compose-linux-aarch64" 25 "aarch64: docker-compose"; then
        validation_failed=true
    fi

    if [[ "$validation_failed" == "true" ]]; then
        log_err "文件验证失败，请先运行 ./download_pkg.sh 下载所有必需文件"
        return 1
    fi

    log_info "所有文件验证通过"
    return 0
}

# --- 创建打包 ---
create_package() {
    log_info "=== 开始创建部署包 ==="

    # 创建 dist 目录
    mkdir -p "$DIST_DIR"

    # 创建临时目录
    local temp_dir=$(mktemp -d)
    local pkg_dir="$temp_dir/deploy-docker"
    mkdir -p "$pkg_dir"

    # 复制文件到临时目录
    log_info "复制文件到临时目录..."

    # 复制脚本
    cp "$WORK_DIR"/*.sh "$pkg_dir/"

    # 复制文档
    cp "$WORK_DIR/README.md" "$pkg_dir/"

    # 复制安装包目录
    cp -r "$WORK_DIR/pkgs" "$pkg_dir/"

    # 设置脚本可执行权限
    chmod +x "$pkg_dir"/*.sh

    # 创建 tar.gz
    log_info "创建压缩包: $OUTPUT_FILE"
    cd "$temp_dir"
    tar czf "$DIST_DIR/$OUTPUT_FILE" deploy-docker/

    # 清理临时目录
    rm -rf "$temp_dir"

    # 显示结果
    local pkg_size=$(du -h "$DIST_DIR/$OUTPUT_FILE" | cut -f1)
    log_info "=== 打包完成 ==="
    log_info "输出文件: $DIST_DIR/$OUTPUT_FILE"
    log_info "文件大小: $pkg_size"
    log_info "Docker 版本: $DOCKER_VERSION"
    log_info "Docker Compose 版本: $COMPOSE_VERSION"
}

# --- 主流程 ---
main() {
    log_info "=== Docker 离线部署包打包工具 ==="
    log_info "工作目录: $WORK_DIR"
    log_info "输出目录: $DIST_DIR"

    # 验证文件
    if ! validate_all_files; then
        exit 1
    fi

    # 创建打包
    if ! create_package; then
        log_err "打包失败"
        exit 1
    fi

    # 显示使用说明
    log_info ""
    log_info "=== 使用说明 ==="
    log_info "1. 将 $OUTPUT_FILE 传输到目标服务器"
    log_info "2. 解压: tar xzf $OUTPUT_FILE"
    log_info "3. 进入目录: cd deploy-docker"
    log_info "4. 安装依赖: sudo ./pre-install.sh"
    log_info "5. 安装 Docker: sudo ./install.sh"
    log_info "6. 验证安装: sudo ./validate.sh"
}

main "$@"

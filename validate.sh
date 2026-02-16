#!/bin/bash

# =================================================================
# 脚本名称: Docker 安装验证脚本
# 功能: 验证 Docker 环境是否正确安装和配置
# =================================================================

set -e

# --- 配置变量 ---
INSTALL_BIN="/usr/bin"
DOCKER_SOCKET="/var/run/docker.sock"
DOCKER_DATA_DIR="/var/lib/docker"

# 验证结果统计
PASSED=0
FAILED=0
WARNINGS=0

# --- 日志函数 ---
log_info() { echo -e "\033[32m[INFO] $1\033[0m"; }
log_warn() { echo -e "\033[33m[WARN] $1\033[0m"; }
log_err()  { echo -e "\033[31m[ERROR] $1\033[0m"; }
log_pass() { echo -e "\033[32m[✓] $1\033[0m"; PASSED=$((PASSED + 1)); }
log_fail() { echo -e "\033[31m[✗] $1\033[0m"; FAILED=$((FAILED + 1)); }

# --- 验证二进制文件 ---
validate_binaries() {
    log_info "=== 验证二进制文件 ==="

    local binaries=("docker" "dockerd" "containerd" "runc" "ctr")
    local optional_binaries=("docker-compose" "docker-init" "docker-proxy")

    for bin in "${binaries[@]}"; do
        if [[ -x "$INSTALL_BIN/$bin" ]]; then
            local version=$($INSTALL_BIN/$bin --version 2>/dev/null | head -n 1 || echo "未知版本")
            log_pass "$bin 存在且可执行: $version"
        else
            log_fail "$bin 不存在或不可执行"
        fi
    done

    for bin in "${optional_binaries[@]}"; do
        if [[ -x "$INSTALL_BIN/$bin" ]]; then
            local version=$($INSTALL_BIN/$bin --version 2>/dev/null | head -n 1 || echo "未知版本")
            log_pass "$bin 存在: $version"
        else
            log_warn "$bin 未安装（可选组件）"
            WARNINGS=$((WARNINGS + 1))
        fi
    done

    return 0
}

# --- 验证服务状态 ---
validate_service() {
    log_info "=== 验证服务状态 ==="

    # 检查服务是否激活
    if systemctl is-active docker &>/dev/null; then
        log_pass "Docker 服务正在运行"
    else
        log_fail "Docker 服务未运行"
        return 1
    fi

    # 检查服务是否启用
    if systemctl is-enabled docker &>/dev/null; then
        log_pass "Docker 服务已设置为开机自启"
    else
        log_warn "Docker 服务未设置为开机自启"
        WARNINGS=$((WARNINGS + 1))
    fi

    # 检查 Docker socket
    if [[ -S "$DOCKER_SOCKET" ]]; then
        log_pass "Docker socket 存在: $DOCKER_SOCKET"
    else
        log_fail "Docker socket 不存在: $DOCKER_SOCKET"
        return 1
    fi

    # 检查 containerd 进程
    if pgrep -x containerd &>/dev/null; then
        log_pass "containerd 进程正在运行"
    else
        log_fail "containerd 进程未运行"
        return 1
    fi

    # 检查 dockerd 进程
    if pgrep -x dockerd &>/dev/null; then
        log_pass "dockerd 进程正在运行"
    else
        log_fail "dockerd 进程未运行"
        return 1
    fi

    return 0
}

# --- 验证功能 ---
validate_functional() {
    log_info "=== 验证 Docker 功能 ==="

    # 执行 docker info
    if docker info &>/dev/null; then
        log_pass "docker info 执行成功"

        # 获取存储驱动
        local storage_driver=$(docker info 2>/dev/null | grep "Storage Driver" | awk '{print $3}')
        if [[ -n "$storage_driver" ]]; then
            log_pass "存储驱动: $storage_driver"
        else
            log_warn "无法获取存储驱动信息"
            WARNINGS=$((WARNINGS + 1))
        fi

        # 获取 Docker 根目录
        local docker_root=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $4}')
        if [[ -n "$docker_root" ]]; then
            log_pass "Docker 根目录: $docker_root"
        fi
    else
        log_fail "docker info 执行失败"
        return 1
    fi

    # 检查网络
    if docker network ls &>/dev/null; then
        log_pass "docker network 命令可用"

        if docker network ls | grep -q bridge; then
            log_pass "bridge 网络存在"
        else
            log_warn "bridge 网络不存在"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        log_fail "docker network 命令失败"
    fi

    # 尝试运行测试容器（仅在有镜像时）
    local image_count=$(docker images -q 2>/dev/null | wc -l)
    if [[ $image_count -gt 0 ]]; then
        log_info "检测到 $image_count 个镜像，尝试运行测试容器..."

        # 检查是否有 busybox 或 hello-world 镜像
        if docker images | grep -qE "busybox|hello-world"; then
            local test_image=$(docker images | grep -E "busybox|hello-world" | head -n 1 | awk '{print $1":"$2}')
            log_info "使用镜像: $test_image"

            if docker run --rm "$test_image" echo "Docker 容器测试成功" &>/dev/null; then
                log_pass "容器运行测试通过"
            else
                log_warn "容器运行测试失败"
                WARNINGS=$((WARNINGS + 1))
            fi
        else
            log_warn "未找到测试镜像（busybox/hello-world），跳过容器测试"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        log_warn "未检测到镜像，跳过容器测试（离线环境正常）"
        WARNINGS=$((WARNINGS + 1))
    fi

    return 0
}

# --- 验证资源 ---
validate_resources() {
    log_info "=== 验证系统资源 ==="

    # 检查磁盘空间
    if [[ -d "$DOCKER_DATA_DIR" ]]; then
        local available_space=$(df -BG "$DOCKER_DATA_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
        if [[ -n "$available_space" ]]; then
            if [[ $available_space -ge 10 ]]; then
                log_pass "磁盘空间充足: ${available_space}GB 可用"
            elif [[ $available_space -ge 5 ]]; then
                log_warn "磁盘空间较少: ${available_space}GB 可用（建议至少 10GB）"
                WARNINGS=$((WARNINGS + 1))
            else
                log_fail "磁盘空间不足: ${available_space}GB 可用（需要至少 5GB）"
            fi
        fi
    else
        log_warn "Docker 数据目录不存在: $DOCKER_DATA_DIR"
        WARNINGS=$((WARNINGS + 1))
    fi

    # 检查内核版本
    local kernel_version=$(uname -r)
    log_pass "内核版本: $kernel_version"

    # 检查 cgroup
    if [[ -d /sys/fs/cgroup ]]; then
        log_pass "cgroup 文件系统可用"
    else
        log_warn "cgroup 文件系统不可用"
        WARNINGS=$((WARNINGS + 1))
    fi

    return 0
}

# --- 生成报告 ---
generate_report() {
    echo ""
    log_info "=== 验证报告 ==="
    echo "通过: $PASSED"
    echo "失败: $FAILED"
    echo "警告: $WARNINGS"
    echo ""

    if [[ $FAILED -eq 0 ]]; then
        if [[ $WARNINGS -eq 0 ]]; then
            log_pass "所有验证通过！Docker 环境完全正常"
            return 0
        else
            log_warn "验证通过，但有 $WARNINGS 个警告"
            return 2
        fi
    else
        log_fail "验证失败，有 $FAILED 个关键错误"
        log_err "请检查日志并修复问题"
        return 1
    fi
}

# --- 主流程 ---
main() {
    log_info "=== 开始 Docker 安装验证 ==="
    echo ""

    # 权限检查
    if [[ $EUID -ne 0 ]]; then
        log_err "必须以 root 权限运行此脚本"
        exit 1
    fi

    # 执行验证
    validate_binaries
    echo ""

    validate_service
    echo ""

    validate_functional
    echo ""

    validate_resources
    echo ""

    # 生成报告
    generate_report
    exit $?
}

main "$@"

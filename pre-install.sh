#!/bin/bash

# =================================================================
# 脚本名称: Docker 依赖预安装脚本
# 功能: 检测操作系统并安装必要的依赖包
# 支持系统: Ubuntu, CentOS/RHEL, Kylin V10
# =================================================================

set -e

# --- 日志函数 ---
log_info() { echo -e "\033[32m[INFO] $1\033[0m"; }
log_warn() { echo -e "\033[33m[WARN] $1\033[0m"; }
log_err()  { echo -e "\033[31m[ERROR] $1\033[0m"; }

# --- 权限检查 ---
if [[ $EUID -ne 0 ]]; then
   log_err "必须以 root 权限运行此脚本"
   exit 1
fi

# --- 操作系统检测 ---
detect_os() {
    local os_type=""

    # 优先检查 /etc/os-release
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu)
                os_type="ubuntu"
                ;;
            centos|rhel)
                os_type="centos"
                ;;
            kylin)
                os_type="kylin"
                ;;
            *)
                log_warn "未识别的 OS ID: $ID，尝试其他检测方法"
                ;;
        esac
    fi

    # 回退检测 Kylin
    if [[ -z "$os_type" ]] && [[ -f /etc/kylin-release ]]; then
        os_type="kylin"
    fi

    # 回退检测 CentOS/RHEL
    if [[ -z "$os_type" ]] && [[ -f /etc/redhat-release ]]; then
        os_type="centos"
    fi

    # 通过 uname 检测 Kylin
    if [[ -z "$os_type" ]]; then
        local uname_output=$(uname -a)
        if [[ "$uname_output" =~ [Kk]ylin ]]; then
            os_type="kylin"
        fi
    fi

    if [[ -z "$os_type" ]]; then
        log_err "无法检测操作系统类型"
        return 1
    fi

    echo "$os_type"
    return 0
}

# --- 获取包管理器 ---
get_package_manager() {
    local os_type=$1
    local pkg_mgr=""

    case "$os_type" in
        ubuntu|kylin)
            pkg_mgr="apt-get"
            ;;
        centos)
            # 自动检测 dnf 或 yum
            if command -v dnf &> /dev/null; then
                pkg_mgr="dnf"
            elif command -v yum &> /dev/null; then
                pkg_mgr="yum"
            else
                log_err "未找到 yum 或 dnf 包管理器"
                return 1
            fi
            ;;
        *)
            log_err "不支持的操作系统: $os_type"
            return 1
            ;;
    esac

    echo "$pkg_mgr"
    return 0
}

# --- 获取依赖包列表 ---
get_dependencies() {
    local os_type=$1
    local deps=""

    case "$os_type" in
        ubuntu)
            deps="iptables ca-certificates curl gnupg lsb-release"
            ;;
        centos)
            deps="iptables device-mapper-persistent-data lvm2 yum-utils"
            ;;
        kylin)
            deps="iptables ca-certificates curl"
            ;;
        *)
            log_err "不支持的操作系统: $os_type"
            return 1
            ;;
    esac

    echo "$deps"
    return 0
}

# --- 安装单个包（带重试） ---
install_package() {
    local pkg_mgr=$1
    local package=$2
    local max_retries=3
    local retry_delay=5

    for ((i=1; i<=max_retries; i++)); do
        log_info "安装 $package (尝试 $i/$max_retries)..."

        if [[ "$pkg_mgr" == "apt-get" ]]; then
            if DEBIAN_FRONTEND=noninteractive $pkg_mgr install -y "$package" 2>&1; then
                return 0
            fi
        else
            if $pkg_mgr install -y "$package" 2>&1; then
                return 0
            fi
        fi

        if [[ $i -lt $max_retries ]]; then
            log_warn "$package 安装失败，${retry_delay}秒后重试..."
            sleep $retry_delay
        fi
    done

    log_err "$package 安装失败，已重试 $max_retries 次"
    return 1
}

# --- 验证包是否已安装 ---
validate_package() {
    local os_type=$1
    local package=$2

    case "$os_type" in
        ubuntu|kylin)
            if dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
                return 0
            fi
            ;;
        centos)
            if rpm -q "$package" &>/dev/null; then
                return 0
            fi
            ;;
    esac

    return 1
}

# --- 安装依赖 ---
install_dependencies() {
    local os_type=$1
    local pkg_mgr=$2
    local dependencies=$3

    log_info "更新包管理器缓存..."
    if [[ "$pkg_mgr" == "apt-get" ]]; then
        DEBIAN_FRONTEND=noninteractive $pkg_mgr update -y || log_warn "更新缓存失败，继续安装"
    else
        $pkg_mgr makecache || log_warn "更新缓存失败，继续安装"
    fi

    local failed_packages=()

    for package in $dependencies; do
        if validate_package "$os_type" "$package"; then
            log_info "$package 已安装，跳过"
            continue
        fi

        if ! install_package "$pkg_mgr" "$package"; then
            failed_packages+=("$package")
        fi
    done

    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_err "以下包安装失败: ${failed_packages[*]}"
        return 1
    fi

    return 0
}

# --- 验证所有依赖 ---
validate_dependencies() {
    local os_type=$1
    local dependencies=$2

    log_info "验证依赖包安装..."
    local missing_packages=()

    for package in $dependencies; do
        if ! validate_package "$os_type" "$package"; then
            missing_packages+=("$package")
        fi
    done

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log_err "以下包未正确安装: ${missing_packages[*]}"
        return 1
    fi

    log_info "所有依赖包验证通过"
    return 0
}

# --- 主流程 ---
main() {
    log_info "=== 开始安装 Docker 依赖 ==="

    # 检测操作系统
    log_info "检测操作系统..."
    OS_TYPE=$(detect_os)
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    log_info "检测到操作系统: $OS_TYPE"

    # 获取包管理器
    PKG_MGR=$(get_package_manager "$OS_TYPE")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    log_info "使用包管理器: $PKG_MGR"

    # 获取依赖列表
    DEPENDENCIES=$(get_dependencies "$OS_TYPE")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    log_info "需要安装的依赖: $DEPENDENCIES"

    # 安装依赖
    if ! install_dependencies "$OS_TYPE" "$PKG_MGR" "$DEPENDENCIES"; then
        log_err "依赖安装失败"
        exit 1
    fi

    # 验证依赖
    if ! validate_dependencies "$OS_TYPE" "$DEPENDENCIES"; then
        log_err "依赖验证失败"
        exit 1
    fi

    log_info "=== Docker 依赖安装完成 ==="
}

main "$@"

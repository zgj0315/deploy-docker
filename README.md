# Docker 离线部署工具

完整的 Docker 离线安装、验证和卸载解决方案，支持多种 Linux 发行版。

## 支持的系统

- **Ubuntu** 18.04+
- **CentOS/RHEL** 7.x, 8.x
- **Kylin V10**

## 支持的架构

- x86_64 (amd64)
- aarch64 (arm64)

## 系统要求

- Linux 内核版本 ≥ 3.10
- systemd 支持
- 至少 10GB 可用磁盘空间（推荐）
- root 权限

## 目录结构

```
deploy-docker/
├── install.sh          # 主安装脚本
├── pre-install.sh      # 依赖预安装脚本
├── validate.sh         # 安装验证脚本
├── uninstall.sh        # 卸载脚本
├── pkgs/
│   ├── x86_64/
│   │   ├── docker-*.tgz
│   │   └── docker-compose-linux-x86_64
│   └── aarch64/
│       ├── docker-*.tgz
│       └── docker-compose-linux-aarch64
└── README.md
```

## 快速开始

### 1. 安装依赖

首先运行依赖预安装脚本（需要网络连接）：

```bash
sudo ./pre-install.sh
```

此脚本会：
- 自动检测操作系统类型
- 选择合适的包管理器（apt-get/yum/dnf）
- 安装必要的系统依赖
- 验证依赖安装成功

### 2. 安装 Docker

运行主安装脚本（离线安装）：

```bash
sudo ./install.sh
```

安装过程包括：
- 系统架构检测
- 安装前检查（内核版本、磁盘空间、systemd）
- 备份现有 Docker 安装
- 安装 Docker 二进制文件
- 配置 systemd 服务
- 自动启动并验证 Docker

### 3. 验证安装

安装完成后会自动运行验证，也可以手动执行：

```bash
sudo ./validate.sh
```

验证内容：
- 二进制文件完整性
- 服务运行状态
- Docker 功能测试
- 系统资源检查

## 详细说明

### pre-install.sh - 依赖预安装

**功能特性：**
- 多系统自动检测（Ubuntu/CentOS/Kylin）
- 智能包管理器选择
- 失败重试机制（每个包重试 3 次）
- 安装后验证

**依赖包列表：**

| 系统 | 依赖包 |
|------|--------|
| Ubuntu | iptables, ca-certificates, curl, gnupg, lsb-release |
| CentOS/RHEL | iptables, device-mapper-persistent-data, lvm2, yum-utils |
| Kylin V10 | iptables, ca-certificates, curl |

### install.sh - 主安装脚本

**功能特性：**
- 详细日志记录（保存到 `/var/log/docker-install-*.log`）
- 安装前系统检查
- 自动备份现有安装
- 失败自动回滚
- 操作系统特定配置
- 增强的启动验证（60秒超时）

**安装状态跟踪：**
```
none → backup_created → binaries_installed →
service_configured → service_started
```

**存储驱动选择：**
- Ubuntu/Kylin: overlay2
- CentOS/RHEL (内核 ≥ 4.0): overlay2
- CentOS/RHEL (内核 < 4.0): devicemapper

**日志配置：**
- 日志驱动: json-file
- 单文件最大: 100MB
- 保留文件数: 3

### validate.sh - 验证脚本

**验证项目：**

1. **二进制验证**
   - 检查所有必需二进制文件
   - 验证版本信息
   - 检查可执行权限

2. **服务验证**
   - systemd 服务状态
   - 开机自启配置
   - Docker socket 存在性
   - containerd/dockerd 进程

3. **功能验证**
   - `docker info` 执行
   - 存储驱动配置
   - 网络功能
   - 容器运行测试（如有镜像）

4. **资源验证**
   - 磁盘空间
   - 内核版本
   - cgroup 支持

**退出码：**
- 0: 所有验证通过
- 1: 有关键错误
- 2: 通过但有警告

### uninstall.sh - 卸载脚本

**功能特性：**
- 交互式确认
- 可选数据备份
- 完整清理（网络、iptables、进程）
- 用户组管理

**卸载步骤：**
1. 确认卸载意图
2. 可选备份数据目录
3. 停止所有服务和进程
4. 清理网络接口和 iptables 规则
5. 删除二进制文件
6. 删除 systemd 服务
7. 可选删除数据目录
8. 可选删除 docker 用户组

## 使用示例

### 完整安装流程

```bash
# 1. 安装依赖（需要网络）
sudo ./pre-install.sh

# 2. 离线安装 Docker
sudo ./install.sh

# 3. 验证安装
sudo ./validate.sh

# 4. 测试 Docker
sudo docker run hello-world
```

### 查看安装日志

```bash
# 查看最新日志
sudo tail -f /var/log/docker-install-*.log

# 查看所有日志
sudo ls -lh /var/log/docker-install-*.log
```

### 卸载 Docker

```bash
sudo ./uninstall.sh
```

按提示选择：
- 是否备份数据
- 是否删除数据目录
- 是否删除用户组

## 故障排查

### 问题：安装失败并自动回滚

**解决方法：**
1. 查看日志文件：`/var/log/docker-install-*.log`
2. 检查错误信息
3. 修复问题后重新运行 `install.sh`

### 问题：Docker 启动超时

**可能原因：**
- 内核版本过低
- 存储驱动不兼容
- SELinux 阻止

**解决方法：**
```bash
# 检查服务状态
sudo systemctl status docker

# 查看详细日志
sudo journalctl -xeu docker

# 检查内核版本
uname -r

# 临时禁用 SELinux（CentOS/RHEL）
sudo setenforce 0
```

### 问题：验证脚本报告警告

**常见警告：**
- 磁盘空间不足：清理磁盘或扩容
- 未找到测试镜像：正常（离线环境）
- Docker Compose 未安装：检查安装包是否存在

### 问题：CentOS 7 上 overlay2 不可用

**解决方法：**
脚本会自动检测并使用 devicemapper。如需手动配置：

```bash
# 编辑 /etc/docker/daemon.json
{
  "storage-driver": "devicemapper"
}

# 重启 Docker
sudo systemctl restart docker
```

### 问题：权限被拒绝

**解决方法：**
```bash
# 所有脚本必须以 root 运行
sudo ./install.sh

# 或切换到 root 用户
sudo su -
./install.sh
```

## 离线安装包准备

如需准备离线安装包：

### 1. 下载 Docker 二进制包

访问 [Docker 官方下载页](https://download.docker.com/linux/static/stable/)：

```bash
# x86_64
wget https://download.docker.com/linux/static/stable/x86_64/docker-24.0.7.tgz

# aarch64
wget https://download.docker.com/linux/static/stable/aarch64/docker-24.0.7.tgz
```

### 2. 下载 Docker Compose

访问 [Docker Compose Releases](https://github.com/docker/compose/releases)：

```bash
# x86_64
wget https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-linux-x86_64

# aarch64
wget https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-linux-aarch64
```

### 3. 组织目录结构

```bash
mkdir -p pkgs/x86_64 pkgs/aarch64

# 放置文件
mv docker-24.0.7.tgz pkgs/x86_64/
mv docker-compose-linux-x86_64 pkgs/x86_64/
mv docker-*-aarch64.tgz pkgs/aarch64/
mv docker-compose-linux-aarch64 pkgs/aarch64/
```

## 高级配置

### 自定义 Docker 配置

编辑 `/etc/docker/daemon.json`（安装后）：

```json
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "registry-mirrors": ["https://your-mirror.com"],
  "insecure-registries": ["your-registry:5000"]
}
```

重启 Docker：
```bash
sudo systemctl restart docker
```

### 配置非 root 用户使用 Docker

```bash
# 创建 docker 组（如不存在）
sudo groupadd docker

# 添加用户到 docker 组
sudo usermod -aG docker $USER

# 重新登录或运行
newgrp docker

# 测试
docker ps
```

## 技术细节

### 回滚机制

安装失败时自动执行：
1. 停止并禁用 Docker 服务
2. 删除新安装的二进制文件
3. 恢复备份的文件
4. 重启原有 Docker 服务（如有）

### 日志格式

```
[2026-02-16 10:30:45] [INFO] 消息内容
[2026-02-16 10:30:46] [WARN] 警告内容
[2026-02-16 10:30:47] [ERROR] 错误内容
```

### 启动验证流程

1. 检查 systemd 服务状态
2. 验证 containerd 进程运行
3. 确认 Docker socket 存在
4. 执行 `docker info` 验证功能

## 许可证

本项目仅用于 Docker 的离线部署，Docker 本身遵循其官方许可证。

## 贡献

欢迎提交 Issue 和 Pull Request。

## 更新日志

### v2.0.0 (2026-02-16)
- 新增多系统支持（Ubuntu/CentOS/Kylin）
- 新增详细日志记录
- 新增安装前检查
- 新增备份和回滚机制
- 新增安装验证脚本
- 增强卸载脚本功能
- 改进错误处理

### v1.0.0
- 基础 Docker 离线安装功能

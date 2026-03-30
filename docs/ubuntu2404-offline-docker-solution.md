# Ubuntu 24.04 Docker 离线部署方案

## 1. 目标

在一台可联网的制品机上生成一个离线安装包，交付到 Ubuntu 24.04 生产服务器后，在无外网条件下完成 Docker Engine 部署、启动和校验。

## 2. 设计原则

- 目标系统固定为 Ubuntu 24.04，避免一个安装包兼容过多发行版导致复杂度失控。
- 优先使用 `deb` 包离线安装，而不是直接散拷贝二进制。
- 安装过程不依赖公网仓库，不执行在线 `apt update`。
- 安装包需要包含版本清单、校验文件、安装脚本、卸载脚本、回滚说明。
- 区分“Docker 运行时安装”和“业务模块部署”两个阶段，便于复用。

## 3. 推荐交付物

建议最终交付一个压缩包，例如：

```text
docker-offline-bundle/
├── manifest/
│   ├── VERSION
│   ├── packages.txt
│   └── sha256sum.txt
├── packages/
│   ├── containerd.io_<ver>_<arch>.deb
│   ├── docker-ce_<ver>_<arch>.deb
│   ├── docker-ce-cli_<ver>_<arch>.deb
│   ├── docker-buildx-plugin_<ver>_<arch>.deb
│   ├── docker-compose-plugin_<ver>_<arch>.deb
│   ├── pigz_<ver>_<arch>.deb
│   ├── iptables_<ver>_<arch>.deb
│   └── ...
├── config/
│   ├── daemon.json
│   └── docker.service.d/
│       └── override.conf
├── scripts/
│   ├── install.sh
│   ├── uninstall.sh
│   └── verify.sh
└── docs/
    ├── README.md
    ├── rollback.md
    └── checklists.md
```

## 4. 总体流程

### 4.1 联网制品机构建

1. 准备一台与生产环境同架构的 Ubuntu 24.04 主机。
2. 配置 Docker 官方 APT 源。
3. 下载目标版本的 Docker 相关 `deb` 包及依赖包。
4. 生成 `sha256` 校验文件和版本清单。
5. 打包为统一交付物。

### 4.2 生产机离线安装

1. 上传安装包到目标机器。
2. 执行校验脚本，确认包完整性。
3. 安装依赖包和 Docker Engine。
4. 写入 `daemon.json` 和 systemd 配置。
5. 启动并校验 Docker 服务。
6. 业务模块按自身脚本完成镜像导入。

## 5. 为什么推荐 `deb` 离线安装

相较于直接复制 `dockerd`、`docker`、`containerd` 二进制，`deb` 包方式更适合生产环境：

- 依赖关系更清晰，便于版本锁定。
- 升级、卸载、审计更标准。
- 与 Ubuntu 24.04 的 systemd、iptables、containerd 配置更一致。
- 后续做补丁升级时复用方式一致。

直接拷贝二进制可以作为兜底方案，但不建议作为主交付方案。

## 6. 安装包内容设计

### 6.1 必选软件包

核心包通常包括：

- `containerd.io`
- `docker-ce`
- `docker-ce-cli`
- `docker-buildx-plugin`
- `docker-compose-plugin`

### 6.2 常见依赖

依赖包不要在生产机现装，建议随包交付。常见包括：

- `iptables`
- `iproute2`
- `pigz`
- `xz-utils`
- `ca-certificates`
- `uidmap`

实际依赖以制品机构建时通过 `apt-rdepends` 或 `apt-cache depends` 解析结果为准。

## 7. 脚本职责划分

### 7.1 `install.sh`

负责：

- root 权限检查
- 操作系统检查，只允许 Ubuntu 24.04
- CPU 架构检查，只允许 `amd64` 或 `arm64`
- 文件完整性校验
- 使用 `dpkg -i` 安装全部 `deb`
- 缺失依赖时改用 `apt install ./packages/*.deb`
- 创建 `/etc/docker/daemon.json`
- 执行 `systemctl daemon-reload`
- `enable` 并 `start` Docker
- 输出 `docker version` 和 `docker info`

### 7.2 `verify.sh`

负责：

- `sha256sum -c manifest/sha256sum.txt`
- 检查 `systemctl is-active docker`
- 检查 `docker info`
- 检查 `docker run --rm hello-world` 或内部最小镜像

生产环境如果不能运行公开镜像，建议换成随包提供的内部测试镜像。

### 7.3 `uninstall.sh`

负责：

- 停止 Docker 服务
- 卸载 Docker 相关包
- 清理 `/etc/docker`
- 默认不删除 `/var/lib/docker`

不要在卸载脚本里直接删除数据目录，避免误删生产数据。

## 8. Ubuntu 24.04 关键配置建议

### 8.1 `daemon.json`

建议提供一个可审计的默认模板：

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "exec-opts": [
    "native.cgroupdriver=systemd"
  ],
  "storage-driver": "overlay2",
  "data-root": "/var/lib/docker"
}
```

如生产环境需要代理、私有仓库或 insecure registry，再按环境覆盖。

### 8.2 systemd

Ubuntu 24.04 默认采用 systemd，建议通过 drop-in 文件管理额外参数，不直接改主 service 文件。

例如：

```ini
[Service]
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
TasksMax=infinity
```

### 8.3 防火墙与转发

Docker 依赖 `iptables`/`nftables` 兼容层，安装前需要确认：

- 内核模块已具备
- `net.ipv4.ip_forward=1`
- 若存在安全基线，确认 FORWARD 策略不会拦截容器网络

建议安装脚本只检查并提示，不自动改过多网络策略，避免影响生产主机现有规则。

## 9. 联网制品机构建方案

建议单独提供一个“构建离线包”的脚本，在联网机器执行。

核心步骤：

1. 固定 Docker 版本和架构。
2. 清理并创建输出目录。
3. 下载 `deb` 包和依赖。
4. 生成 `packages.txt`、`sha256sum.txt`。
5. 打成 `tar.gz` 或 `tar.zst`。

可采用如下思路：

```bash
apt-get download docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
apt-cache depends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

如果希望依赖收集更完整，建议使用：

- `apt-rdepends`
- 或本地临时 APT 仓库工具，例如 `apt-ftparchive`

## 10. 两种可选交付模式

### 模式 A: 简单离线包

特点：

- 目录中直接放所有 `deb`
- 用 `dpkg -i packages/*.deb` 安装
- 实现简单，适合单机或小规模交付

适用：

- 生产节点数量不多
- 版本更新频率低

### 模式 B: 本地离线 APT 仓库

特点：

- 安装包中内置一个本地仓库目录
- 生产机通过 `file://` 源安装
- 更适合后续升级和批量维护

适用：

- 节点较多
- 后续还要持续发补丁包
- 需要更标准的软件包管理方式

如果当前目标是“尽快可用”，建议先落地模式 A；如果目标是“长期批量运维”，建议直接做模式 B。

## 11. 推荐实施路线

建议分三阶段推进：

### 阶段 1: 最小可用版

- 只支持 Ubuntu 24.04
- 只支持一种架构
- 交付 `deb + install.sh + verify.sh`
- 不包含业务镜像

目标是先验证 Docker Engine 可稳定离线安装。

### 阶段 2: 完整生产版

- 增加校验、回滚、卸载
- 增加 `daemon.json` 模板化
- 增加日志与错误码

### 阶段 3: 运维化版本

- 升级为本地离线 APT 仓库
- 增加版本锁定和升级脚本
- 增加批量部署文档

## 12. 风险与控制点

### 12.1 版本漂移

风险：

- 制品机构建的包版本与生产验证版本不一致。

控制：

- 清单中固化精确版本。
- 构建完成后生成 `VERSION` 和 `packages.txt`。

### 12.2 架构不匹配

风险：

- 在 `arm64` 机器上误装 `amd64` 包。

控制：

- 安装前强制比对 `dpkg --print-architecture`。

### 12.3 依赖缺失

风险：

- `dpkg -i` 后存在未满足依赖。

控制：

- 制品机构建阶段必须做依赖闭包下载。
- 交付前在一台断网 Ubuntu 24.04 虚机完整演练。

### 12.4 网络策略冲突

风险：

- Docker 修改 iptables 后影响现网业务。

控制：

- 先在测试环境验证。
- 把网络相关配置作为可选项，而不是默认强改。

## 13. 验收标准

交付方案至少满足以下验收项：

- 断网 Ubuntu 24.04 主机可成功安装 Docker
- `systemctl status docker` 正常
- `docker version` 正常
- 能正常承接业务模块后续镜像导入
- 支持卸载且不误删业务数据
- 具备版本清单和文件完整性校验

## 14. 结论

这个需求最稳妥的实现方式是：

- 用一台联网 Ubuntu 24.04 制品机生成 Docker 离线安装包
- 安装包以 `deb` 包为核心，而不是二进制散装复制
- 生产机通过脚本完成校验、安装、配置、启动、验证
- 后续按规模决定是否演进为离线 APT 仓库

如果要立即开始实施，建议先做“模式 A + 阶段 1”，最快可以形成一个可在断网服务器验证的 MVP。

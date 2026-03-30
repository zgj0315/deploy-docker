# deploy-docker

Ubuntu 24.04 Docker 离线部署脚手架。

## 目录

```text
.
├── config/
│   ├── daemon.json
│   └── docker.service.d/
│       └── override.conf
├── docs/
│   ├── checklists.md
│   ├── rollback.md
│   └── ubuntu2404-offline-docker-solution.md
├── manifest/
│   ├── VERSION
│   └── packages.txt
└── scripts/
    ├── build-offline-bundle.sh
    ├── install.sh
    ├── prepare-build-host.sh
    ├── uninstall.sh
    └── verify.sh
```

## 使用方式

初始化全新制品机：

```bash
sudo bash scripts/prepare-build-host.sh
```

联网制品机构建离线包：

```bash
bash scripts/build-offline-bundle.sh
```

断网生产机安装：

```bash
sudo bash scripts/install.sh
```

执行安装校验：

```bash
bash scripts/verify.sh
```

卸载 Docker：

```bash
bash scripts/uninstall.sh
```

## 说明

- 目标系统固定为 Ubuntu 24.04。
- 默认支持 `amd64` 和 `arm64`。
- 脚手架优先采用 `deb` 包离线安装。
- 全新制品机先执行 `scripts/prepare-build-host.sh`，再执行 `scripts/build-offline-bundle.sh`。
- 如果系统后台正在执行 `unattended-upgrades`，`scripts/prepare-build-host.sh` 会等待 APT 锁释放后继续。
- 安装脚本会把执行 `sudo` 的登录用户加入 `docker` 组，重新登录后可直接执行 `docker`。
- 业务镜像导入由业务模块部署脚本负责，不在本仓库实现。

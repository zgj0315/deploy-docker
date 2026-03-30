# deploy-docker

Ubuntu 24.04 Docker 离线部署脚手架。

## 目标

- 在联网 Ubuntu 24.04 制品机上生成 Docker 离线安装包
- 在断网 Ubuntu 24.04 服务器上完成 Docker 安装和校验
- 仅负责 Docker 运行时，不处理业务镜像导入

## 目录

```text
config/
manifest/
scripts/
README.md
```

## 使用

```bash
sudo bash scripts/prepare-build-host.sh
bash scripts/build-offline-bundle.sh
sudo bash scripts/install.sh
bash scripts/verify.sh
bash scripts/uninstall.sh
```

## 中国大陆环境建议

`scripts/build-offline-bundle.sh` 的主要耗时通常不在打包本身，而在 APT 下载。中国大陆环境下，慢点通常有两个：

- `scripts/prepare-build-host.sh` 默认使用 Docker 官方 APT 源 `https://download.docker.com/linux/ubuntu`
- `scripts/build-offline-bundle.sh` 默认每次都要重新检查并下载离线包

可以按下面方式优化：

```bash
sudo DOCKER_APT_BASE_URL=https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
  bash scripts/prepare-build-host.sh

APT_CACHE_DIR="$PWD/dist/apt-cache" bash scripts/build-offline-bundle.sh
```

说明：

- `DOCKER_APT_BASE_URL` 用于切换 Docker APT 镜像，默认仍是官方源
- `APT_CACHE_DIR` 用于复用已下载的 `.deb` 包；第二次构建会明显更快
- Ubuntu 系统源本身也建议切换到国内镜像，否则 `apt-get update` 和依赖下载仍可能很慢

## 脚本

- `scripts/prepare-build-host.sh`
  初始化全新制品机，安装依赖并配置 Docker 官方 APT 源。
- `scripts/build-offline-bundle.sh`
  下载 Docker 及依赖的 `deb` 包，生成离线安装包到 `dist/`。
- `scripts/install.sh`
  在断网服务器安装 Docker，写入配置并启动服务。
- `scripts/verify.sh`
  校验 Docker 服务和命令可用性。
- `scripts/uninstall.sh`
  卸载 Docker，默认保留 `/var/lib/docker` 数据。

## 约束

- 仅支持 Ubuntu 24.04
- 支持 `amd64` 和 `arm64`
- 业务镜像导入由业务模块脚本负责
- 安装后需重新登录或执行 `newgrp docker` 才能免 `sudo` 使用 `docker`

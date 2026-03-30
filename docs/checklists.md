# 检查清单

## 制品机构建前

- Ubuntu 24.04
- 已执行 `sudo bash scripts/prepare-build-host.sh`

## 生产机安装前

- Ubuntu 24.04
- root 权限
- 已上传完整离线包
- 确认 `/var/lib/docker` 可用空间充足
- 确认主机网络策略允许 Docker 修改相关 iptables 规则

## 安装后验证

- `systemctl is-active docker` 为 `active`
- `docker version` 返回正常
- `docker info` 返回正常
- 业务模块可正常承接后续镜像导入

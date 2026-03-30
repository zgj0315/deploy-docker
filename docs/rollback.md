# 回滚说明

## 回滚范围

本脚手架默认只回滚 Docker 软件和配置，不自动删除业务数据目录。

## 快速回滚

```bash
bash scripts/uninstall.sh
```

## 手工检查项

- 检查 `/etc/docker/daemon.json` 是否已清理
- 检查 `/etc/systemd/system/docker.service.d/override.conf` 是否已清理
- 检查 `systemctl status docker` 是否已停止
- 如需清理数据，再评估是否删除 `/var/lib/docker`

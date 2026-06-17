# Update and rollback

## Restart

普通重启不会让补丁失效。每次容器启动时，`entrypoint` 都会先执行 `patch-favicon.sh`，再启动 `node server/server.js`。

```bash
cd /www/server/uptime-kuma
docker compose restart uptime-kuma
docker compose logs --tail=120 uptime-kuma
```

## Update the Uptime Kuma image

当前项目更新时，保留原有 `docker-compose.yml`，确认这几项还在：

- `./custom/favicon.ico:/app/custom/favicon.ico:ro`
- `./custom/patch-favicon.sh:/app/custom/patch-favicon.sh:ro`
- `entrypoint: ["/usr/bin/dumb-init", "--", "/bin/sh", "/app/custom/patch-favicon.sh"]`
- `command: ["node", "server/server.js"]`

然后执行：

```bash
cd /www/server/uptime-kuma
docker compose pull uptime-kuma
docker compose up -d uptime-kuma
docker compose logs --tail=120 uptime-kuma
```

如果 `docker compose logs` 没有出现 `Unable to patch ...`，说明补丁已经重新套到了新镜像上。

## Why failures are visible

脚本会匹配 Uptime Kuma 当前版本里的 favicon 渲染代码和 manifest 图标代码。如果上游版本大改了这些文件，脚本会退出非零状态，让容器启动失败并给出错误。这样比静默失败更安全，因为你会立刻知道需要调整补丁。

## Rollback

如需临时回退：

1. 从 `docker-compose.yml` 删除 `custom/favicon.ico` 和 `custom/patch-favicon.sh` 两个挂载。
2. 删除自定义 `entrypoint` 和 `command`，恢复到你原本的启动方式。
3. 重启服务：

```bash
docker compose up -d uptime-kuma
```

状态页 Custom CSS 和自定义页尾可以在 Uptime Kuma 后台单独删除，不影响容器启动。

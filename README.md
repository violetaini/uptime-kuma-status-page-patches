# Uptime Kuma status page patches

这个仓库记录一个 Uptime Kuma 状态页在启用 Cloudflare Tunnel 后做过的补丁方式。

## 解决的问题

启用 Cloudflare Tunnel / Cloudflare 访问保护后，浏览器在无痕窗口里访问 `/favicon.ico` 可能被 Cloudflare 拦截，导致状态页角标丢失。Uptime Kuma 状态页还会在运行时用 Favico/状态徽标改写 favicon，所以只改 nginx 或只上传图标不够稳定。

当前方案把 favicon 变成页面内联的 `data:image/x-icon;base64,...`，并在页面运行时持续校正 `<link rel="icon">`。这样浏览器首屏 HTML、manifest 和运行时 head 都使用同一个 ICO 数据，不再依赖单独请求 `/favicon.ico`。

同时保留了两类页面增强：

- 状态页页尾的一言重新拉取 `https://v1.hitokoto.cn/?encode=json`，并写入自定义页尾元素。
- 状态页标题 `Chitanda No Status` 和旁边头像通过自定义 CSS 放大，并给头像加了类似主页头像的轻微浮动、光环和呼吸动效。

## 文件说明

- `patch-favicon.sh`：挂到 Uptime Kuma 容器里的启动补丁脚本。容器每次启动都会执行。
- `compose.example.yml`：只展示和补丁有关的 Docker Compose 写法，数据库、端口和已有 volume 按你自己的项目保留。
- `status-page-custom.css`：粘贴到 Uptime Kuma 状态页「Custom CSS」里的样式。
- `auto-update/`：保守自动追新脚本、systemd service/timer 和 env 示例。
- `nginx/favicon-location.conf`：可选 nginx 兜底片段，给 `/favicon.ico` 直接返回本地图标。
- `docs/auto-update.md`：自动更新部署、测试、定时器和失败回滚说明。
- `docs/update-and-rollback.md`：更新、重启和回滚方式。
- `docs/verification.md`：上线后如何确认 favicon 和一言没有再失效。

## 安装方式

假设 Uptime Kuma 项目目录是 `/www/server/uptime-kuma`：

```bash
cd /www/server/uptime-kuma
mkdir -p custom
cp /path/to/your/favicon.ico custom/favicon.ico
cp /path/to/patch-favicon.sh custom/patch-favicon.sh
chmod 755 custom/patch-favicon.sh
```

在 `docker-compose.yml` 的 `uptime-kuma` 服务中保留你原来的配置，只新增或确认下面几项：

```yaml
services:
  uptime-kuma:
    image: louislam/uptime-kuma:latest
    volumes:
      - ./custom/favicon.ico:/app/custom/favicon.ico:ro
      - ./custom/patch-favicon.sh:/app/custom/patch-favicon.sh:ro
    entrypoint: ["/usr/bin/dumb-init", "--", "/bin/sh", "/app/custom/patch-favicon.sh"]
    command: ["node", "server/server.js"]
```

如果你的服务还有数据库、端口、`/app/data`、网络等配置，不要删除，只把上面的补丁项合并进去。

然后重启 Kuma：

```bash
docker compose up -d uptime-kuma
docker compose logs --tail=120 uptime-kuma
```

## 状态页 CSS

打开 Uptime Kuma 后台，进入对应 Status Page 的设置，把 `status-page-custom.css` 追加到 Custom CSS。CSS 只依赖 Uptime Kuma 当前状态页里的 `h1.title-flex`、`.logo-wrapper` 和 `.logo` 结构。

## 一言页尾

在状态页自定义页尾里保留两个元素：

```html
<span id="status-yiyan-text">愿你历经山河，仍觉人间值得。</span>
<span id="status-yiyan-source"></span>
```

`patch-favicon.sh` 会把一言加载器注入到 Uptime Kuma 的 `index.html`，页面加载后自动填充这两个元素。请求失败时会保留 fallback 文案。

## 如何更新 Uptime Kuma

更新前先确认项目目录和容器名。下面示例假设项目目录是 `/www/server/uptime-kuma`，服务名是 `uptime-kuma`：

```bash
cd /www/server/uptime-kuma
docker compose ps
docker compose config | grep -E 'image:|patch-favicon|favicon.ico|entrypoint|command'
```

确认输出里仍然能看到：

- `image: louislam/uptime-kuma:latest`
- `./custom/favicon.ico:/app/custom/favicon.ico:ro`
- `./custom/patch-favicon.sh:/app/custom/patch-favicon.sh:ro`
- `/app/custom/patch-favicon.sh`
- `node server/server.js`

更新前建议先备份 Compose 文件、补丁文件和 Kuma 数据：

```bash
cd /www/server/uptime-kuma
stamp="$(date +%F-%H%M%S)"
mkdir -p "backups/$stamp"
cp docker-compose.yml "backups/$stamp/docker-compose.yml"
cp -a custom "backups/$stamp/custom"
```

如果你使用的是默认 SQLite 数据目录，再备份 `/app/data` 对应的本地目录：

```bash
cp -a data "backups/$stamp/data"
```

如果你使用的是 MariaDB / MySQL 部署，更新前先按自己的数据库账号做一次 dump。不要把数据库密码写进仓库：

```bash
docker compose exec -T db sh -lc 'mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' > "backups/$stamp/uptime-kuma.sql"
```

如果要自动追最新稳定镜像，Compose 里的 `image` 也要是 `louislam/uptime-kuma:latest`。否则 `docker compose pull uptime-kuma` 只会继续拉原来的 tag。

确认备份后拉取新镜像并重建 Kuma 容器：

```bash
cd /www/server/uptime-kuma
docker compose pull uptime-kuma
docker compose up -d uptime-kuma
docker compose logs --tail=120 uptime-kuma
```

日志里没有 `Unable to patch ...`，并且 Kuma 能正常启动，就说明补丁已经重新套到新镜像上。随后用浏览器无痕窗口打开状态页，再按 `docs/verification.md` 做 favicon 和一言检查。

如果更新后容器起不来，先看日志：

```bash
docker compose logs --tail=200 uptime-kuma
```

如果日志里出现 `Unable to patch status_page.js favicon renderer` 或 `Unable to patch status-page manifest icon`，说明 Uptime Kuma 新版本改了内部文件结构，需要调整 `patch-favicon.sh`。临时恢复服务时，可以先回滚到更新前备份的 Compose/数据，或临时移除补丁挂载和自定义 `entrypoint` 后启动原版 Kuma。

## 自动追新

仓库里提供了一个保守自动更新器，适合用 systemd timer 每周检查一次新镜像。它不会盲目替换容器，而是按下面流程执行：

1. 检查 Compose 里仍然存在 `favicon.ico`、`patch-favicon.sh` 和自定义 `entrypoint`。
2. 记录当前 `louislam/uptime-kuma:latest` 镜像 id。
3. 执行 `docker compose pull uptime-kuma`。
4. 只有镜像 id 变化时才备份并重建容器。
5. 更新后检查容器运行状态、补丁 marker、Kuma 日志和可选健康检查地址。
6. 如果验证失败，尝试用更新前的本地镜像 tag 自动回滚。

安装方式：

```bash
sudo install -m 0755 auto-update/uptime-kuma-auto-update.sh /usr/local/sbin/uptime-kuma-auto-update.sh
sudo install -m 0644 auto-update/uptime-kuma-auto-update.service /etc/systemd/system/uptime-kuma-auto-update.service
sudo install -m 0644 auto-update/uptime-kuma-auto-update.timer /etc/systemd/system/uptime-kuma-auto-update.timer
sudo install -m 0600 auto-update/uptime-kuma-auto-update.env.example /etc/uptime-kuma-auto-update.env
sudoedit /etc/uptime-kuma-auto-update.env
```

上线前先 dry-run，再手动跑一次 service：

```bash
sudo /usr/local/sbin/uptime-kuma-auto-update.sh --dry-run
sudo systemctl daemon-reload
sudo systemctl start uptime-kuma-auto-update.service
sudo journalctl -u uptime-kuma-auto-update.service -n 120 --no-pager
```

确认无误后启用定时器：

```bash
sudo systemctl enable --now uptime-kuma-auto-update.timer
systemctl list-timers uptime-kuma-auto-update.timer
```

完整配置见 `docs/auto-update.md`。

## 更新后补丁会不会失效

正常重启不会失效。只要 Docker Compose 里还保留 `custom/favicon.ico`、`custom/patch-favicon.sh` 这两个挂载，以及自定义 `entrypoint`，容器每次启动都会重新给 Uptime Kuma 当前镜像打补丁。

如果 Uptime Kuma 以后大改了内部文件结构，脚本找不到预期代码时会让容器启动失败并打印明确错误，例如 `Unable to patch status_page.js favicon renderer`。这是故意的，避免静默上线一个角标再次失效的版本。

## nginx 兜底

主修复不依赖 `/favicon.ico`，因为 favicon 已内联进 HTML 和 manifest。nginx 片段只是给直接访问 `/favicon.ico` 的客户端一个稳定返回，适合放在 catch-all rewrite/proxy 规则之前。

见 `nginx/favicon-location.conf`。

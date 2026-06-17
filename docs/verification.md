# Verification

## Browser check

用 Chrome 无痕窗口打开公开状态页，然后在 DevTools Console 里检查：

```js
document.querySelector("link[rel~='icon']")?.href.startsWith("data:image/x-icon;base64,")
```

返回 `true` 表示页面当前 favicon 已经不是普通 `/favicon.ico` 请求。

也可以继续检查一言元素：

```js
document.getElementById("status-yiyan-text")?.textContent.trim().length > 0
```

返回 `true` 表示页尾元素已被填充。

## Network check

直接请求 `/favicon.ico` 应该仍然返回 ICO，作为兜底：

```bash
curl -I https://status.example.com/favicon.ico
```

期望看到类似：

```text
HTTP/2 200
content-type: image/x-icon
cache-control: public, max-age=300, must-revalidate
```

如果站点经过 Cloudflare，浏览器标签页仍应优先使用 HTML 里的内联 icon，所以即使 `/favicon.ico` 被挑战页影响，标签页角标也不应该再消失。

## Container check

进入容器确认启动补丁已写入：

```bash
docker compose exec uptime-kuma sh -lc 'grep -R "Codex favicon" -n /app/server/model/status_page.js /app/server/routers/status-page-router.js && grep -n "status-favicon-lock" /app/dist/index.html'
```

正常情况下会看到：

- `Codex favicon render patch START`
- `Codex favicon manifest patch START`
- `status-favicon-lock`

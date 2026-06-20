#!/bin/sh
set -eu

favicon_source="/app/custom/favicon.ico"
favicon_target="/app/dist/favicon.ico"
index_file="/app/dist/index.html"
status_page_model="/app/server/model/status_page.js"
status_page_router="/app/server/routers/status-page-router.js"

if [ -f "$favicon_source" ]; then
    cp "$favicon_source" "$favicon_target"
fi

if [ -f "$status_page_model" ]; then
    node - "$status_page_model" <<'NODE'
const fs = require("fs");

const modelPath = process.argv[2];
const faviconPath = "/app/custom/favicon.ico";

if (!fs.existsSync(faviconPath)) {
    process.exit(0);
}

const faviconDataUrl = "data:image/x-icon;base64," + fs.readFileSync(faviconPath).toString("base64");
let js = fs.readFileSync(modelPath, "utf8");

const patchStart = "        // Codex favicon render patch START\n";
const patchEnd = "        // Codex favicon render patch END\n";
const renderPatch = `${patchStart}        const codexFaviconHref = ${JSON.stringify(faviconDataUrl)};\n        $("link[rel=icon]").attr("href", codexFaviconHref).attr("type", "image/x-icon");\n        $("link[rel=apple-touch-icon]").remove();\n${patchEnd}`;

const existingPatchPattern = /        \/\/ Codex favicon render patch START\n[\s\S]*?        \/\/ Codex favicon render patch END\n/;
const kumaIconPattern = /        if \(statusPage\.icon\) {\n            \$\("link\[rel=icon\]"\)\.attr\("href", statusPage\.icon\)\.removeAttr\("type"\);\n\n            \$\("link\[rel=apple-touch-icon\]"\)\.remove\(\);\n        }\n/;

if (existingPatchPattern.test(js)) {
    js = js.replace(existingPatchPattern, renderPatch);
} else if (kumaIconPattern.test(js)) {
    js = js.replace(kumaIconPattern, renderPatch);
} else {
    console.error("Unable to patch status_page.js favicon renderer");
    process.exit(1);
}

fs.writeFileSync(modelPath, js);
NODE
fi

if [ -f "$status_page_router" ]; then
    node - "$status_page_router" <<'NODE'
const fs = require("fs");

const routerPath = process.argv[2];
const faviconPath = "/app/custom/favicon.ico";

if (!fs.existsSync(faviconPath)) {
    process.exit(0);
}

const faviconDataUrl = "data:image/x-icon;base64," + fs.readFileSync(faviconPath).toString("base64");
let js = fs.readFileSync(routerPath, "utf8");

const patchStart = "            // Codex favicon manifest patch START\n";
const patchEnd = "            // Codex favicon manifest patch END\n";
const manifestPatch = `${patchStart}            icons: [\n                {\n                    src: ${JSON.stringify(faviconDataUrl)},\n                    sizes: "32x32",\n                    type: "image/x-icon",\n                },\n            ],\n${patchEnd}`;

const existingPatchPattern = /            \/\/ Codex favicon manifest patch START\n[\s\S]*?            \/\/ Codex favicon manifest patch END\n/;
const kumaManifestPattern = /            icons: \[\n                {\n                    src: statusPage\.icon,\n                    sizes: "128x128",\n                    type: "image\/png",\n                },\n            \],\n/;

if (existingPatchPattern.test(js)) {
    js = js.replace(existingPatchPattern, manifestPatch);
} else if (kumaManifestPattern.test(js)) {
    js = js.replace(kumaManifestPattern, manifestPatch);
} else {
    console.error("Unable to patch status-page manifest icon");
    process.exit(1);
}

fs.writeFileSync(routerPath, js);
NODE
fi

if [ -f "$index_file" ]; then
    node - "$index_file" <<'NODE'
const fs = require("fs");
const zlib = require("zlib");

const indexPath = process.argv[2];
const faviconPath = "/app/custom/favicon.ico";
let html = fs.readFileSync(indexPath, "utf8");
const faviconDataUrl = fs.existsSync(faviconPath)
    ? "data:image/x-icon;base64," + fs.readFileSync(faviconPath).toString("base64")
    : "/favicon.ico";
const faviconLink = `    <link rel="icon" type="image/x-icon" href="${faviconDataUrl}" />`;
const writeAsset = (filePath, content) => {
    const buffer = Buffer.from(content);
    fs.writeFileSync(filePath, content);
    fs.writeFileSync(`${filePath}.br`, zlib.brotliCompressSync(buffer));
    fs.writeFileSync(`${filePath}.gz`, zlib.gzipSync(buffer));
};
const faviconScript = `    <script id="status-favicon-lock">
        (() => {
            const faviconHref = ${JSON.stringify(faviconDataUrl)};
            let observer;

            const ensureFavicon = () => {
                if (observer) {
                    observer.disconnect();
                }

                let icon = document.querySelector("link[rel~='icon']");

                if (!icon) {
                    icon = document.createElement("link");
                    icon.rel = "icon";
                    document.head.appendChild(icon);
                }

                if (icon.getAttribute("type") !== "image/x-icon") {
                    icon.setAttribute("type", "image/x-icon");
                }

                if (icon.getAttribute("href") !== faviconHref) {
                    icon.setAttribute("href", faviconHref);
                }

                if (observer && document.head) {
                    observer.observe(document.head, {
                        childList: true,
                        subtree: true,
                        attributes: true,
                        attributeFilter: ["href", "rel", "type"],
                    });
                }
            };

            let scheduled = false;
            const scheduleFaviconCheck = () => {
                if (scheduled) {
                    return;
                }

                scheduled = true;
                window.setTimeout(() => {
                    scheduled = false;
                    ensureFavicon();
                }, 0);
            };

            observer = new MutationObserver(scheduleFaviconCheck);

            ensureFavicon();
            if (document.head) {
                observer.observe(document.head, {
                    childList: true,
                    subtree: true,
                    attributes: true,
                    attributeFilter: ["href", "rel", "type"],
                });
            }

            window.addEventListener("pageshow", ensureFavicon);
            window.setInterval(ensureFavicon, 3000);
        })();
    </script>`;
const yiyanScript = `    <script id="status-yiyan-loader">
        (() => {
            const endpoint = "https://v1.hitokoto.cn/?encode=json";
            const fallbackText = "愿你历经山河，仍觉人间值得。";

            const applyYiyan = (data = {}) => {
                const textEl = document.getElementById("status-yiyan-text");
                const sourceEl = document.getElementById("status-yiyan-source");

                if (!textEl) {
                    return false;
                }

                const text = typeof data.hitokoto === "string" && data.hitokoto.trim()
                    ? data.hitokoto.trim()
                    : fallbackText;
                const source = [data.from_who, data.from].filter(Boolean).join(" - ");

                textEl.textContent = text;

                if (sourceEl) {
                    sourceEl.textContent = source ? "「" + source + "」" : "";
                }

                return true;
            };

            const waitForFooter = (attempts = 0) => {
                if (applyYiyan(window.__statusYiyanData || {}) || attempts >= 80) {
                    return;
                }

                window.setTimeout(() => waitForFooter(attempts + 1), 250);
            };

            fetch(endpoint, { cache: "no-store" })
                .then((response) => response.ok ? response.json() : Promise.reject(new Error("bad response")))
                .then((data) => {
                    window.__statusYiyanData = data;
                    waitForFooter();
                })
                .catch(() => {
                    window.__statusYiyanData = {};
                    waitForFooter();
                });

            if (document.readyState === "loading") {
                document.addEventListener("DOMContentLoaded", () => waitForFooter(), { once: true });
            } else {
                waitForFooter();
            }
        })();
    </script>`;
const settingsNavScript = `    <script id="status-settings-navigation-fix">
        (() => {
            const handler = (event) => {
                const anchor = event.target instanceof Element
                    ? event.target.closest('.dropdown-profile-pic a[href="/settings/general"]')
                    : null;

                if (!anchor) {
                    return;
                }

                event.preventDefault();
                event.stopImmediatePropagation();
                window.location.assign(anchor.href);
            };

            document.addEventListener("click", handler, true);
        })();
    </script>`;
const adminShortcutScript = `    <script id="status-admin-shortcut-loader">
        (() => {
            const shortcutId = "status-admin-shortcut";
            const shortcutHref = "/dashboard";
            const shortcutLabel = "前往后台面板";
            let observer;

            const removeShortcut = () => {
                const existing = document.getElementById(shortcutId);

                if (existing) {
                    existing.remove();
                }
            };

            const ensureShortcut = () => {
                if (!location.pathname.startsWith("/status/")) {
                    removeShortcut();
                    return false;
                }

                const footer = document.querySelector("footer");

                if (!footer) {
                    return false;
                }

                let shortcut = document.getElementById(shortcutId);

                if (!shortcut) {
                    shortcut = document.createElement("div");
                    shortcut.id = shortcutId;
                    shortcut.className = "status-admin-shortcut";
                    shortcut.style.display = "flex";
                    shortcut.style.justifyContent = "flex-end";
                    shortcut.style.marginTop = "0.5rem";
                    shortcut.style.fontSize = "0.95rem";

                    const link = document.createElement("a");
                    link.href = shortcutHref;
                    link.textContent = shortcutLabel;
                    link.className = "text-decoration-none fw-semibold";
                    link.style.color = "var(--bs-primary)";

                    shortcut.appendChild(link);
                    footer.appendChild(shortcut);
                } else if (shortcut.parentElement !== footer) {
                    footer.appendChild(shortcut);
                }

                return true;
            };

            let scheduled = false;
            const scheduleEnsureShortcut = () => {
                if (scheduled) {
                    return;
                }

                scheduled = true;
                window.setTimeout(() => {
                    scheduled = false;
                    ensureShortcut();
                }, 0);
            };

            const watchTarget = () => {
                if (!observer && document.body) {
                    observer = new MutationObserver(scheduleEnsureShortcut);
                    observer.observe(document.body, {
                        childList: true,
                        subtree: true,
                        attributes: true,
                        attributeFilter: ["class", "style", "href"],
                    });
                }
            };

            ensureShortcut();
            watchTarget();

            if (document.readyState === "loading") {
                document.addEventListener("DOMContentLoaded", () => {
                    watchTarget();
                    ensureShortcut();
                }, { once: true });
            }

            window.addEventListener("pageshow", ensureShortcut);
            window.setInterval(ensureShortcut, 3000);
        })();
    </script>`;

if (/<link\b[^>]*\brel=["']icon["'][^>]*>/i.test(html)) {
    html = html.replace(/^[ \t]*<link\b[^>]*\brel=["']icon["'][^>]*>\s*$/im, faviconLink);
} else if (/<\/head>/i.test(html)) {
    html = html.replace(/<\/head>/i, `${faviconLink}\n</head>`);
}

html = html.replace(/^[ \t]*<script\b[^>]*\bid=["']status-yiyan-loader["'][\s\S]*?<\/script>\s*$/im, "");
html = html.replace(/^[ \t]*<script\b[^>]*\bid=["']status-favicon-lock["'][\s\S]*?<\/script>\s*$/im, "");
html = html.replace(/^[ \t]*<script\b[^>]*\bid=["']status-settings-navigation-fix["'][\s\S]*?<\/script>\s*$/im, "");
html = html.replace(/^[ \t]*<script\b[^>]*\bid=["']status-admin-shortcut-loader["'][\s\S]*?<\/script>\s*$/im, "");

if (/<\/body>/i.test(html)) {
    html = html.replace(/<\/body>/i, `${faviconScript}\n${yiyanScript}\n${settingsNavScript}\n${adminShortcutScript}\n</body>`);
} else {
    html += `\n${faviconScript}\n${yiyanScript}\n${settingsNavScript}\n${adminShortcutScript}\n`;
}

writeAsset(indexPath, html);
NODE
fi

asset_dir="/app/dist/assets"
if [ -d "$asset_dir" ]; then
    node - "$asset_dir" "$index_file" <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const assetDir = process.argv[2];
const indexPath = process.argv[3];
const faviconPath = "/app/custom/favicon.ico";

if (!fs.existsSync(faviconPath)) {
    process.exit(0);
}

const faviconDataUrl = "data:image/x-icon;base64," + fs.readFileSync(faviconPath).toString("base64");
const originalIconPattern = /icon\(([$A-Z_a-z][$\w]*)\)\{return \1===(["'])\/icon\.svg\2\?\1:([$A-Z_a-z][$\w]*)\(\)\+\1\}/g;
const patchedNeedle = `==="/favicon.ico"?${JSON.stringify(faviconDataUrl)}:`;
const settingsPattern = /currentPage\(\)\{let t=E\(\)\.path.split\("\/"\),e=t\[t\.length-1\];return!e\|\|e==="settings"\?null:e\}/;
const settingsPatch = 'currentPage(){const path=this.$route?.path||"";const pathSplit=path.split("/");const pathEnd=pathSplit[pathSplit.length-1];return!pathEnd||pathEnd==="settings"?null:pathEnd}';
const socketPattern = /socket\s*=\s*io\(url\)\s*;/;
const socketPatch = 'socket = io(url, { transports: ["polling"], upgrade: false, reconnectionAttempts: 3, timeout: 20000 });';
const writeAsset = (filePath, content) => {
    const buffer = Buffer.from(content);
    fs.writeFileSync(filePath, content);
    fs.writeFileSync(`${filePath}.br`, zlib.brotliCompressSync(buffer));
    fs.writeFileSync(`${filePath}.gz`, zlib.gzipSync(buffer));
};

let patchedCount = 0;
let existingCount = 0;
const patchedAssets = [];

const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

for (const name of fs.readdirSync(assetDir)) {
    if (!name.endsWith(".js")) {
        continue;
    }

    if (/-codex-[0-9a-f]{12}\.js$/.test(name)) {
        continue;
    }

    const file = path.join(assetDir, name);
    let js = fs.readFileSync(file, "utf8");
    const hadPatch = js.includes(patchedNeedle) || js.includes(settingsPatch) || js.includes(socketPatch);
    let changed = false;

    js = js.replace(originalIconPattern, (match, iconArg, quote, baseUrlFn) => {
        changed = true;
        return `icon(${iconArg}){return ${iconArg}==="/favicon.ico"?${JSON.stringify(faviconDataUrl)}:${iconArg}==="/icon.svg"?${iconArg}:${baseUrlFn}()+${iconArg}}`;
    });

    const settingsUpdated = js.replace(settingsPattern, settingsPatch);
    if (settingsUpdated !== js) {
        js = settingsUpdated;
        changed = true;
    }

    const socketUpdated = js.replace(socketPattern, socketPatch);
    if (socketUpdated !== js) {
        js = socketUpdated;
        changed = true;
    }

    if (changed) {
        writeAsset(file, js);
        patchedCount += 1;
    }

    if (changed || hadPatch) {
        existingCount += 1;
        patchedAssets.push({
            name,
            content: js,
        });
    }
}

if (patchedCount === 0 && existingCount === 0) {
    console.error("Unable to patch manage page favicon preview");
    process.exit(1);
}

if (patchedAssets.length > 0 && fs.existsSync(indexPath)) {
    let html = fs.readFileSync(indexPath, "utf8");
    let rewrites = 0;
    const keepGeneratedAssets = new Set();

    for (const asset of patchedAssets) {
        const hash = crypto.createHash("sha256").update(asset.content).digest("hex").slice(0, 12);
        const generatedName = asset.name.startsWith("index-")
            ? `index-codex-${hash}.js`
            : asset.name.replace(/\.js$/, `-codex-${hash}.js`);
        const generatedPath = path.join(assetDir, generatedName);

        if (!fs.existsSync(generatedPath) || fs.readFileSync(generatedPath, "utf8") !== asset.content) {
            writeAsset(generatedPath, asset.content);
        }

        keepGeneratedAssets.add(generatedName);

        const before = html;
        if (asset.name.startsWith("index-")) {
            html = html.replace(/assets\/index-(?:codex-[0-9a-f]{12}|[^"'<>]+)\.js/g, `assets/${generatedName}`);
        } else {
            html = html.replace(new RegExp(escapeRegExp(`assets/${asset.name}`), "g"), `assets/${generatedName}`);
        }

        if (html !== before) {
            rewrites += 1;
        }
    }

    for (const name of fs.readdirSync(assetDir)) {
        if (/-codex-[0-9a-f]{12}\.js$/.test(name) && !keepGeneratedAssets.has(name)) {
            const file = path.join(assetDir, name);
            if (fs.existsSync(file)) {
                fs.unlinkSync(file);
            }
            for (const suffix of [".br", ".gz"]) {
                const sidecar = `${file}${suffix}`;
                if (fs.existsSync(sidecar)) {
                    fs.unlinkSync(sidecar);
                }
            }
        }
    }

    if (rewrites > 0) {
        writeAsset(indexPath, html);
    }
}
NODE
fi

exec "$@"

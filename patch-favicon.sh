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

const indexPath = process.argv[2];
const faviconPath = "/app/custom/favicon.ico";
let html = fs.readFileSync(indexPath, "utf8");
const faviconDataUrl = fs.existsSync(faviconPath)
    ? "data:image/x-icon;base64," + fs.readFileSync(faviconPath).toString("base64")
    : "/favicon.ico";
const faviconLink = `    <link rel="icon" type="image/x-icon" href="${faviconDataUrl}" />`;
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

if (/<link\b[^>]*\brel=["']icon["'][^>]*>/i.test(html)) {
    html = html.replace(/^[ \t]*<link\b[^>]*\brel=["']icon["'][^>]*>\s*$/im, faviconLink);
} else if (/<\/head>/i.test(html)) {
    html = html.replace(/<\/head>/i, `${faviconLink}\n</head>`);
}

html = html.replace(/^[ \t]*<script\b[^>]*\bid=["']status-yiyan-loader["'][\s\S]*?<\/script>\s*$/im, "");
html = html.replace(/^[ \t]*<script\b[^>]*\bid=["']status-favicon-lock["'][\s\S]*?<\/script>\s*$/im, "");

if (/<\/body>/i.test(html)) {
    html = html.replace(/<\/body>/i, `${faviconScript}\n${yiyanScript}\n</body>`);
} else {
    html += `\n${faviconScript}\n${yiyanScript}\n`;
}

fs.writeFileSync(indexPath, html);
NODE
fi

exec "$@"

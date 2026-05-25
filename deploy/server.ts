import { serve } from "bun";
import { existsSync } from "node:fs";
import { extname, join } from "node:path";

const port = Number(process.env.PORT || 8080);
const backendRoot = join(import.meta.dir, "..", "backend");
const webRoot = join(import.meta.dir, "web");
const python = Bun.spawn({
  cmd: [
    join(backendRoot, ".venv", "bin", "uvicorn"),
    "app.main:app",
    "--host",
    "127.0.0.1",
    "--port",
    "18080",
  ],
  cwd: backendRoot,
  env: {
    ...process.env,
    PORT: "18080",
  },
  stdout: "inherit",
  stderr: "inherit",
});

process.on("SIGTERM", () => python.kill());
process.on("SIGINT", () => python.kill());

const types: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".wasm": "application/wasm",
  ".wav": "audio/wav",
  ".otf": "font/otf",
  ".ttf": "font/ttf",
  ".frag": "text/plain; charset=utf-8",
};

const apiPrefixes = [
  "/healthz",
  "/auth/",
  "/sync/",
  "/roadmap/",
  "/axes/",
  "/coach/",
  "/tools/",
  "/onboarding",
];

function isApi(pathname: string) {
  return apiPrefixes.some((prefix) => pathname === prefix.replace(/\/$/, "") || pathname.startsWith(prefix));
}

function webPath(pathname: string) {
  return pathname === "/" ? "/index.html" : pathname;
}

serve({
  port,
  hostname: "0.0.0.0",
  async fetch(request) {
    const url = new URL(request.url);
    if (isApi(url.pathname)) {
      const upstream = new URL(request.url);
      upstream.protocol = "http:";
      upstream.hostname = "127.0.0.1";
      upstream.port = "18080";
      return fetch(upstream, request);
    }

    const targetPath = join(webRoot, webPath(decodeURIComponent(url.pathname)));
    const target = existsSync(targetPath) ? targetPath : join(webRoot, "index.html");
    const headers = new Headers({
      "Content-Type": types[extname(target)] || "application/octet-stream",
      "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    });
    if (url.pathname.endsWith("/flutter_bootstrap.js") || url.pathname === "/flutter_bootstrap.js") {
      const text = await Bun.file(target).text();
      return new Response(text.replaceAll('mainJsPath":"main.dart.js', 'mainJsPath":"main.dart.zo.js'), { headers });
    }
    return new Response(Bun.file(target), { headers });
  },
});

console.log(`Noetica full stack listening on ${port}`);
console.log(`Noetica web root: ${webRoot}`);
console.log(`Noetica main.dart.js exists: ${existsSync(join(webRoot, "main.dart.js"))}`);

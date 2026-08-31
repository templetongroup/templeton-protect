import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { applyFix } from "./fix.ts";
import { scanAiInstallations } from "./scan.ts";
import type { FixAction } from "./finding.ts";

// The window's back end. Local only.
//
// ⚠️ BOUND TO 127.0.0.1, NEVER 0.0.0.0. This process can change file
// permissions and delete files; a listener on every interface would hand that to
// anything on the same network. There is no configuration option to widen it.
//
// ⚠️ AND A LOCAL PORT IS NOT PRIVATE. Any page in any browser on this Mac can
// POST to localhost, so /api/fix checks Origin and requires a token minted at
// startup — the page gets it because it is served by this process, and a
// drive-by page in another tab does not.

const HERE = dirname(fileURLToPath(import.meta.url));
const UI = join(HERE, "..", "ui");
const TOKEN = crypto.randomUUID();

function send(res: import("node:http").ServerResponse, code: number, body: string, type: string): void {
  res.writeHead(code, {
    "Content-Type": type,
    // Nothing here should ever be framed or cached.
    "X-Frame-Options": "DENY",
    "Cache-Control": "no-store",
  });
  res.end(body);
}

export function startServer(port = 7717): Promise<string> {
  return new Promise((resolve) => {
    const server = createServer(async (req, res) => {
      const url = new URL(req.url ?? "/", `http://127.0.0.1:${port}`);

      if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
        const html = readFileSync(join(UI, "index.html"), "utf8").replace("__TOKEN__", TOKEN);
        return send(res, 200, html, "text/html; charset=utf-8");
      }

      if (req.method === "GET" && url.pathname === "/api/scan") {
        const result = scanAiInstallations(homedir());
        return send(res, 200, JSON.stringify(result), "application/json");
      }

      if (req.method === "POST" && url.pathname === "/api/fix") {
        // ⚠️ BOTH CHECKS, NOT EITHER. The token stops a page that never loaded
        // ours; the Origin check stops one that scraped it out of a screenshot.
        const origin = req.headers.origin;
        if (origin && origin !== `http://127.0.0.1:${port}` && origin !== `http://localhost:${port}`) {
          return send(res, 403, JSON.stringify({ ok: false, message: "Refused." }), "application/json");
        }
        let raw = "";
        for await (const chunk of req) raw += chunk;
        let body: { token?: string; fix?: FixAction };
        try {
          body = JSON.parse(raw);
        } catch {
          return send(res, 400, JSON.stringify({ ok: false, message: "Bad request." }), "application/json");
        }
        if (body.token !== TOKEN) {
          return send(res, 403, JSON.stringify({ ok: false, message: "Refused." }), "application/json");
        }
        if (!body.fix) {
          return send(res, 400, JSON.stringify({ ok: false, message: "Nothing to fix." }), "application/json");
        }
        const outcome = applyFix(body.fix, homedir());
        return send(res, 200, JSON.stringify(outcome), "application/json");
      }

      send(res, 404, "Not found", "text/plain");
    });
    server.listen(port, "127.0.0.1", () => resolve(`http://127.0.0.1:${port}`));
  });
}

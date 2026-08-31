import { startServer } from "./server.ts";
import { spawn } from "node:child_process";

// Opening the window.
//
// ⚠️ THE PORT IS FIXED SO A SECOND LAUNCH FINDS THE FIRST. Two copies of a tool
// that changes file permissions is not a state worth being in; if the port is
// busy, that is almost certainly us already running and the browser is pointed
// at it instead of starting a rival.
const PORT = 7717;

const url = await startServer(PORT).catch(() => `http://127.0.0.1:${PORT}`);
console.log(`\n  Templeton Protect is running at ${url}`);
console.log("  Press Control-C to stop.\n");
if (!process.argv.includes("--no-open")) spawn("open", [url], { stdio: "ignore", detached: true }).unref();

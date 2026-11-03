// Drives the Web build (python tools/web.py) in headless Chromium. Run from games/konbini-empire:
//   node tools/shot.mjs [--size 1600x900] step...
// Steps run in order:
//   eval:<GDScript>   body of func run(main), main being the main.gd node; prints what it returns
//   wait:<seconds>    key:<Playwright key name>    click:<x>,<y>    shot:<file.png>
// The page's console (Godot's prints, errors and warnings) is echoed.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { execSync } from "node:child_process";
import { extname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  ({ chromium } = await import(pathToFileURL(join(execSync("npm root -g").toString().trim(), "playwright", "index.mjs")).href));
}

const dir = resolve("build/web");
const types = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm", ".png": "image/png" };
const server = createServer(async (req, res) => {
  const file = join(dir, new URL(req.url, "http://x").pathname);
  try {
    res.writeHead(200, { "Content-Type": types[extname(file)] ?? "application/octet-stream" }).end(await readFile(file));
  } catch {
    res.writeHead(404).end();
  }
}).listen(0);

const steps = process.argv.slice(2);
let [width, height] = [1600, 900];
if (steps[0] === "--size") [width, height] = steps.splice(0, 2)[1].split("x").map(Number);

const browser = await chromium.launch({ args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--mute-audio"] });
const page = await browser.newPage({ viewport: { width, height } });
page.on("console", (m) => console.log(`[${m.type()}] ${m.text()}`));
page.on("pageerror", (e) => console.log("[pageerror]", e.message));
await page.goto(`http://localhost:${server.address().port}/index.html?dev`);
await page.waitForFunction(() => window.konbiniEval, null, { timeout: 300000 });
for (const s of steps) {
  const op = s.slice(0, s.indexOf(":")), arg = s.slice(s.indexOf(":") + 1);
  if (op === "eval") console.log("=>", await page.evaluate((c) => (window.konbiniEval(c), window.konbiniResult), arg));
  else if (op === "wait") await page.waitForTimeout(parseFloat(arg) * 1000);
  else if (op === "key") await page.keyboard.press(arg);
  else if (op === "click") await page.mouse.click(...arg.split(",").map(Number));
  else if (op === "shot") await page.screenshot({ path: arg }).then(() => console.log("saved", arg));
  else throw new Error("unknown step " + s);
}
await browser.close();
server.close();

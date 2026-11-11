// Screenshots of the built website for checking the layout, in slices.
//
// Drives Microsoft Edge (headless) over the DevTools Protocol with Node's
// built-in WebSocket: loads the page, scrolls through it so the scroll
// animations run, then saves the page in viewport-height slices.
//
// Usage: node website/tools/shoot_site.mjs [url] [outDir]
//   e.g. node website/tools/shoot_site.mjs http://localhost:5700/ build/site-shots

import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const PORT = 9400 + Math.floor(Math.random() * 500);
const [url = 'http://localhost:5700/', outDir = 'build/site-shots', only] = process.argv.slice(2);

const VIEWS = [
  { name: 'desktop-dark', width: 1280, height: 860, scale: 1, mobile: false, scheme: 'dark' },
  { name: 'desktop-light', width: 1280, height: 860, scale: 1, mobile: false, scheme: 'light' },
  { name: 'phone-dark', width: 390, height: 844, scale: 1, mobile: true, scheme: 'dark' },
  { name: 'phone-light', width: 390, height: 844, scale: 1, mobile: true, scheme: 'light' },
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function devtools() {
  for (let i = 0; i < 80; i++) {
    try { if ((await fetch(`http://127.0.0.1:${PORT}/json/version`)).ok) return; } catch {}
    await sleep(250);
  }
  throw new Error('Edge DevTools did not start');
}

function connect(wsUrl) {
  const ws = new WebSocket(wsUrl);
  let id = 0;
  const pending = new Map();
  ws.addEventListener('message', (e) => {
    const msg = JSON.parse(e.data);
    if (msg.id && pending.has(msg.id)) {
      const p = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? p.reject(new Error(msg.error.message)) : p.resolve(msg.result);
    }
  });
  const send = (method, params = {}) => new Promise((res, rej) => {
    const n = ++id;
    pending.set(n, { resolve: res, reject: rej });
    ws.send(JSON.stringify({ id: n, method, params }));
  });
  return new Promise((res, rej) => {
    ws.addEventListener('open', () => res({ send, close: () => ws.close() }));
    ws.addEventListener('error', rej);
  });
}

async function evaluate(cdp, expression) {
  const r = await cdp.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  return r.result.value;
}

const PROFILE_NAME = `edge-site-profile-${Date.now()}`;

// Edge starts helper processes of its own, and they are not children of
// the one started here, so closing that one leaves them running. This ends
// every Edge process that was started with this run's profile folder.
function closeEdge(edge) {
  try { edge.kill(); } catch {}
  try {
    spawnSync('powershell', ['-NoProfile', '-Command',
      `Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object { $_.CommandLine -like '*${PROFILE_NAME}*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }`,
    ], { stdio: 'ignore' });
  } catch {}
}

async function main() {
  const out = resolve(outDir);
  mkdirSync(out, { recursive: true });
  const edge = spawn(EDGE, [
    '--headless=new', `--remote-debugging-port=${PORT}`,
    `--user-data-dir=${resolve('build', PROFILE_NAME)}`,
    '--hide-scrollbars', '--no-first-run', '--disable-gpu', '--disable-extensions',
    '--disable-background-networking', 'about:blank',
  ], { stdio: 'ignore' });
  // If the browser hangs, give up instead of waiting for ever.
  const watchdog = setTimeout(() => {
    console.error('Gave up after 150 seconds: the browser stopped answering.');
    closeEdge(edge);
    process.exit(2);
  }, 150_000);
  try {
    await devtools();
    for (const v of VIEWS) {
      if (only && !v.name.startsWith(only)) continue;
      const target = await (await fetch(`http://127.0.0.1:${PORT}/json/new?about:blank`, { method: 'PUT' })).json();
      const cdp = await connect(target.webSocketDebuggerUrl);
      await cdp.send('Page.enable');
      await cdp.send('Runtime.enable');
      await cdp.send('Emulation.setDeviceMetricsOverride', {
        width: v.width, height: v.height, deviceScaleFactor: v.scale, mobile: v.mobile,
      });
      await cdp.send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: v.scheme }] });
      await cdp.send('Page.navigate', { url });
      await sleep(2500);
      const errors = await evaluate(cdp, 'JSON.stringify(window.__errors || [])');
      // Scroll through so every scroll animation runs, then back to the top.
      const height = await evaluate(cdp, 'document.documentElement.scrollHeight');
      for (let y = 0; y < height; y += Math.round(v.height * 0.6)) {
        await evaluate(cdp, `window.scrollTo(0, ${y})`);
        await sleep(160);
      }
      await sleep(900);
      const overflow = await evaluate(cdp, 'document.documentElement.scrollWidth - window.innerWidth');
      const total = await evaluate(cdp, 'document.documentElement.scrollHeight');
      let n = 0;
      for (let y = 0; y < total; y += v.height) {
        await evaluate(cdp, `window.scrollTo(0, ${y})`);
        await sleep(450);
        const { data } = await cdp.send('Page.captureScreenshot', { format: 'png' });
        writeFileSync(join(out, `${v.name}-${String(++n).padStart(2, '0')}.png`), Buffer.from(data, 'base64'));
      }
      console.log(`${v.name}: ${n} slices, page ${total}px, horizontal overflow ${overflow}px, errors ${errors}`);
      cdp.close();
      await fetch(`http://127.0.0.1:${PORT}/json/close/${target.id}`);
    }
  } finally {
    clearTimeout(watchdog);
    closeEdge(edge);
  }
}

main().catch((e) => { console.error(e); process.exit(1); });

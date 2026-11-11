// Capture phone-sized screenshots of the app's web build for the website.
//
// Drives Microsoft Edge in headless mode over the Chrome DevTools Protocol,
// using only Node's built-in fetch and WebSocket (Node 22+). No packages.
//
// Usage (from the project root, with the web build served, e.g. on 5601):
//   node website/tools/capture_screens.mjs http://localhost:5601 website/src/assets/screens
//
// Each shot opens the app fresh in a phone viewport, optionally taps through
// the app, waits for the map to draw, and saves a WebP.

import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
// A random port, so a leftover Edge from an earlier run cannot answer instead.
const PORT = 9400 + Math.floor(Math.random() * 500);
const VIEW = { width: 390, height: 844, deviceScaleFactor: 2, mobile: true };

const [base = 'http://localhost:5601', outDir = 'website/src/assets/screens', only] = process.argv.slice(2);

// Taps are in CSS pixels of the 390 x 844 viewport.
const SHOTS = [
  { name: 'map-light', scheme: 'light', wait: 18000 },
  { name: 'map-dark', scheme: 'dark', wait: 18000 },
  { name: 'schedule', scheme: 'light', wait: 14000, taps: [[140, 786, 4000]] },
  { name: 'stops', scheme: 'dark', wait: 9000, taps: [[234, 786, 4000]] },
  { name: 'profile', scheme: 'light', wait: 9000, taps: [[328, 786, 4000]] },
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitForDevtools() {
  for (let i = 0; i < 60; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${PORT}/json/version`);
      if (r.ok) return;
    } catch {}
    await sleep(250);
  }
  throw new Error('Edge DevTools did not start');
}

function connect(url) {
  const ws = new WebSocket(url);
  let id = 0;
  const pending = new Map();
  ws.addEventListener('message', (e) => {
    const msg = JSON.parse(e.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve: ok, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? reject(new Error(msg.error.message)) : ok(msg.result);
    }
  });
  const send = (method, params = {}) =>
    new Promise((ok, reject) => {
      const n = ++id;
      pending.set(n, { resolve: ok, reject });
      ws.send(JSON.stringify({ id: n, method, params }));
    });
  return new Promise((ok, reject) => {
    ws.addEventListener('open', () => ok({ send, close: () => ws.close() }));
    ws.addEventListener('error', reject);
  });
}

async function tap(cdp, x, y) {
  for (const type of ['mousePressed', 'mouseReleased']) {
    await cdp.send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
    await sleep(60);
  }
}

async function main() {
  const out = resolve(outDir);
  mkdirSync(out, { recursive: true });
  // Keep Edge's throwaway profile off drive C:, which is nearly full.
  // A fresh folder each run: Edge can keep the last one locked for a while.
  const profile = resolve('build', `edge-cdp-profile-${Date.now()}`);
  const edge = spawn(EDGE, [
    '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
    '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--hide-scrollbars',
    '--no-first-run', '--window-size=390,844', 'about:blank',
  ], { stdio: 'ignore' });

  try {
    await waitForDevtools();
    for (const shot of SHOTS) {
      if (only && shot.name !== only) continue;
      const target = await (await fetch(`http://127.0.0.1:${PORT}/json/new?about:blank`, { method: 'PUT' })).json();
      const cdp = await connect(target.webSocketDebuggerUrl);
      await cdp.send('Page.enable');
      await cdp.send('Emulation.setDeviceMetricsOverride', VIEW);
      await cdp.send('Emulation.setTouchEmulationEnabled', { enabled: false });
      await cdp.send('Emulation.setEmulatedMedia', {
        features: [{ name: 'prefers-color-scheme', value: shot.scheme }],
      });
      await cdp.send('Page.navigate', { url: base });
      await sleep(shot.wait);
      for (const [x, y, after] of shot.taps ?? []) {
        await tap(cdp, x, y);
        await sleep(after);
      }
      const { data } = await cdp.send('Page.captureScreenshot', { format: 'webp', quality: 86 });
      const file = join(out, `${shot.name}.webp`);
      writeFileSync(file, Buffer.from(data, 'base64'));
      console.log(`${shot.name}.webp  ${(Buffer.from(data, 'base64').length / 1024).toFixed(0)} KB`);
      cdp.close();
      await fetch(`http://127.0.0.1:${PORT}/json/close/${target.id}`);
    }
  } finally {
    edge.kill();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

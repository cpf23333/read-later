#!/usr/bin/env node
/**
 * 从已连接的 Android 设备上的 Chromium 浏览器导入已打开标签页。
 *
 * 依赖：Node 24+（内置 WebSocket）、adb；不需要 npm install。
 *
 * 用法：
 *   node tools/import-tabs/import.mjs \
 *     --server http://192.168.1.10:3000 \
 *     --api-key <API_KEY>
 *
 * 网络 ADB 示例：
 *   adb connect 192.168.1.20:5555
 *   node tools/import-tabs/import.mjs --device 192.168.1.20:5555 ...
 *
 * 默认只导入 URL/标题。加 --with-screenshots 会通过 CDP 对每个标签页截一张图，
 * 上传到服务端后作为链接的 screenshot。注意：这不是 Chrome 标签页切换器的
 * 原生缩略图；工具不会激活/切换标签页，后台标签页截图失败时直接跳过。
 */

import { execFileSync } from 'node:child_process';

const DEFAULT_SERVER = process.env.READLATER_SERVER || '';
const DEFAULT_API_KEY = process.env.READLATER_API_KEY || '';

function parseArgs(argv) {
  const args = {
    server: DEFAULT_SERVER,
    apiKey: DEFAULT_API_KEY,
    adb: process.env.ADB || 'adb',
    device: '',
    socket: '',
    port: 9222,
    withScreenshots: false,
    concurrency: 3,
    batchSize: 5000,
    dryRun: false,
    timeoutMs: 15000,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = () => {
      const value = argv[++i];
      if (!value) throw new Error(`Missing value for ${arg}`);
      return value;
    };
    switch (arg) {
      case '--server':
        args.server = next();
        break;
      case '--api-key':
        args.apiKey = next();
        break;
      case '--adb':
        args.adb = next();
        break;
      case '--device':
        args.device = next();
        break;
      case '--socket':
        args.socket = next();
        break;
      case '--port':
        args.port = Number.parseInt(next(), 10);
        break;
      case '--with-screenshots':
        args.withScreenshots = true;
        break;
      case '--concurrency':
        args.concurrency = Math.max(
          1,
          Math.min(8, Number.parseInt(next(), 10))
        );
        break;
      case '--batch-size':
        args.batchSize = Math.max(
          1,
          Math.min(5000, Number.parseInt(next(), 10))
        );
        break;
      case '--dry-run':
        args.dryRun = true;
        break;
      case '--timeout':
        args.timeoutMs = Number.parseInt(next(), 10);
        break;
      case '--help':
      case '-h':
        printHelp();
        process.exit(0);
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }
  if (!args.server) throw new Error('Missing --server (or READLATER_SERVER)');
  if (!args.apiKey) throw new Error('Missing --api-key (or READLATER_API_KEY)');
  args.server = args.server.replace(/\/+$/, '');
  return args;
}

function printHelp() {
  console.log(`Usage: node tools/import-tabs/import.mjs --server <url> --api-key <key> [options]

Options:
  --device <serial>        adb device serial (default: first device)
  --socket <name>          devtools socket name (default: auto-discover)
  --port <port>            local forward port (default: 9222)
  --with-screenshots       capture one CDP screenshot per tab and upload it
  --concurrency <n>        screenshot workers (1-8, default: 3)
  --batch-size <n>         import batch size, max 5000 (default: 5000)
  --dry-run                only print tabs, do not upload
  --timeout <ms>           CDP/request timeout (default: 15000)
  --adb <path>             adb executable (default: adb or $ADB)

Environment:
  READLATER_SERVER, READLATER_API_KEY`);
}

function adb(args, opts = {}) {
  return execFileSync(opts.adb || 'adb', args, {
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
    timeout: opts.timeoutMs || 30000,
  });
}

function discoverDevice(adbPath, requested) {
  const output = adb([...deviceArgs(requested), 'devices'], { adb: adbPath });
  const devices = output
    .split(/\r?\n/)
    .slice(1)
    .map((line) => line.trim().split(/\s+/))
    .filter((parts) => parts.length >= 2 && parts[1] === 'device')
    .map((parts) => parts[0]);
  if (devices.length === 0) {
    throw new Error('No online adb device. Run `adb devices` / `adb connect`.');
  }
  return devices[0];
}

function deviceArgs(device) {
  return device ? ['-s', device] : [];
}

function discoverSocket(adbPath, device) {
  const output = adb([...deviceArgs(device), 'shell', 'cat', '/proc/net/unix'], {
    adb: adbPath,
  });
  const names = Array.from(output.matchAll(/@([^\s]+devtools_remote[^\s]*)/g)).map(
    (m) => m[1]
  );
  if (names.length === 0) {
    throw new Error(
      'No Chrome/Chromium devtools socket found. Open Chrome and make sure USB debugging is enabled.'
    );
  }
  const preferred = [
    'chrome_devtools_remote',
    'brave_devtools_remote',
    'edge_devtools_remote',
    'chromium_devtools_remote',
  ];
  for (const wanted of preferred) {
    const found = names.find((name) => name.includes(wanted));
    if (found) return found;
  }
  return names[0];
}

async function fetchJson(url, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) throw new Error(`HTTP ${response.status} for ${url}`);
    return await response.json();
  } finally {
    clearTimeout(timer);
  }
}

function waitForDevtools(port, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  const url = `http://127.0.0.1:${port}/json/list`;
  return (async () => {
    while (Date.now() < deadline) {
      try {
        return await fetchJson(url, 2000);
      } catch {
        await new Promise((resolve) => setTimeout(resolve, 300));
      }
    }
    throw new Error(`Devtools endpoint not ready: ${url}`);
  })();
}

function cdpScreenshot(wsUrl, timeoutMs) {
  return new Promise((resolve, reject) => {
    if (!wsUrl) {
      reject(new Error('tab has no webSocketDebuggerUrl'));
      return;
    }
    const ws = new WebSocket(wsUrl);
    let nextId = 1;
    let done = false;
    const timer = setTimeout(() => finish(null, new Error('CDP screenshot timeout')), timeoutMs);

    function finish(value, error) {
      if (done) return;
      done = true;
      clearTimeout(timer);
      try {
        ws.close();
      } catch {
        // ignore
      }
      if (error) reject(error);
      else resolve(value);
    }

    ws.onopen = () => {
      ws.send(JSON.stringify({ id: nextId++, method: 'Page.enable' }));
    };
    ws.onerror = () => finish(null, new Error('CDP WebSocket error'));
    ws.onmessage = (event) => {
      let message;
      try {
        message = JSON.parse(event.data);
      } catch {
        return;
      }
      if (message.id === 1) {
        ws.send(
          JSON.stringify({
            id: nextId++,
            method: 'Page.captureScreenshot',
            params: { format: 'png', fromSurface: true },
          })
        );
      } else if (message.id === 2) {
        if (message.error) {
          finish(null, new Error(message.error.message || 'captureScreenshot failed'));
        } else {
          finish(message.result?.data || null);
        }
      }
    };
  });
}

async function uploadScreenshot(server, apiKey, base64, timeoutMs) {
  const response = await fetch(`${server}/api/upload`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      image: `data:image/png;base64,${base64}`,
      filename: 'tab-preview.png',
      purpose: 'screenshot',
    }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const body = await response.json().catch(() => null);
  if (!response.ok || !body?.success || !body.data?.url) {
    throw new Error(`Upload failed: HTTP ${response.status}`);
  }
  return body.data.url;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const device = discoverDevice(args.adb, args.device);
  const socket = args.socket || discoverSocket(args.adb, device);
  console.log(`device: ${device}`);
  console.log(`devtools socket: ${socket}`);

  adb([...deviceArgs(device), 'forward', `tcp:${args.port}`, `localabstract:${socket}`], {
    adb: args.adb,
  });

  try {
    const targets = await waitForDevtools(args.port, args.timeoutMs);
    const tabs = (Array.isArray(targets) ? targets : []).filter(
      (tab) =>
        tab &&
        tab.type === 'page' &&
        typeof tab.url === 'string' &&
        !tab.url.startsWith('chrome://') &&
        !tab.url.startsWith('devtools://')
    );
    console.log(`found ${tabs.length} tabs`);
    for (const tab of tabs) {
      console.log(`- ${tab.title || '(no title)'}`);
      console.log(`  ${tab.url}`);
      if (tab.favIconUrl) console.log(`  favicon: ${tab.favIconUrl}`);
    }
    if (tabs.length === 0 || args.dryRun) return;

    const links = tabs.map((tab) => ({ url: tab.url, title: tab.title || '' }));

    // 只对后台标签页做 CDP 截图，不激活/切换标签页。
    // 并发受限，标签页很多时避免同时压垮浏览器。
    if (args.withScreenshots) {
      let nextIndex = 0;
      let screenshotDone = 0;
      const worker = async () => {
        while (true) {
          const index = nextIndex++;
          if (index >= tabs.length) return;
          const tab = tabs[index];
          const link = links[index];
          const current = ++screenshotDone;
          const progress = `[截图 ${current}/${tabs.length}]`;
          try {
            const base64 = await cdpScreenshot(
              tab.webSocketDebuggerUrl,
              args.timeoutMs
            );
            if (base64) {
              link.screenshot = await uploadScreenshot(
                args.server,
                args.apiKey,
                base64,
                args.timeoutMs
              );
              console.log(`  ${progress} ${link.screenshot}  ${tab.url}`);
            } else {
              console.warn(`  ${progress} empty, skipped: ${tab.url}`);
            }
          } catch (error) {
            console.warn(`  ${progress} failed: ${error.message}  ${tab.url}`);
          }
        }
      };
      const workers = Math.min(args.concurrency, tabs.length);
      await Promise.all(Array.from({ length: workers }, worker));
    }

    // 服务端单次最多 5000 条；超过时由客户端分批导入。
    let imported = 0;
    let failed = 0;
    const totalBatches = Math.ceil(links.length / args.batchSize);
    for (let start = 0; start < links.length; start += args.batchSize) {
      const batch = links.slice(start, start + args.batchSize);
      const batchNo = Math.floor(start / args.batchSize) + 1;
      console.log(`[导入 ${batchNo}/${totalBatches}] ${batch.length} 条...`);
      const response = await fetch(`${args.server}/api/import`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${args.apiKey}`,
        },
        body: JSON.stringify({ links: batch, mode: 'merge' }),
        signal: AbortSignal.timeout(args.timeoutMs),
      });
      const body = await response.json().catch(() => null);
      if (!response.ok || !body?.success) {
        failed += batch.length;
        console.warn(
          `batch ${batchNo} failed: HTTP ${response.status} ${JSON.stringify(body)}`
        );
        continue;
      }
      imported += body.data.imported || 0;
      failed += body.data.failed || 0;
      console.log(
        `batch ${batchNo}: imported ${body.data.imported}, failed ${body.data.failed}, total ${body.data.total}`
      );
    }
    console.log(`imported: ${imported}, failed: ${failed}, total: ${links.length}`);
  } finally {
    try {
      adb([...deviceArgs(device), 'forward', '--remove', `tcp:${args.port}`], {
        adb: args.adb,
      });
    } catch {
      // best effort
    }
  }
}

main().catch((error) => {
  console.error(`error: ${error.message}`);
  process.exit(1);
});

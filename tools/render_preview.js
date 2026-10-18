// renders every .svg in a folder to .png with headless Chromium
// usage: node render_preview.js <folder>
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

(async () => {
  const dir = process.argv[2];
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.svg')).sort()) {
    const svg = fs.readFileSync(path.join(dir, file), 'utf8');
    const m = svg.match(/width="(\d+)" height="(\d+)"/);
    const w = parseInt(m[1], 10), h = parseInt(m[2], 10);
    await page.setViewportSize({ width: w, height: h });
    await page.setContent(`<html><body style="margin:0;background:#000">${svg}</body></html>`);
    await page.screenshot({ path: path.join(dir, file.replace(/\.svg$/, '.png')), clip: { x: 0, y: 0, width: w, height: h } });
    console.log('rendered', file);
  }
  await browser.close();
})();

const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1536, height: 960 }, deviceScaleFactor: 1 });
  await page.goto('https://spargo-app.web.app/business-register?refresh=6041', { waitUntil: 'networkidle', timeout: 120000 });
  await page.screenshot({ path: 'C:/Users/kara/npaartsts/tst/spargo/artifacts/business-register-after.png', fullPage: true });
  await browser.close();
})();

const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({
    viewport: { width: 1366, height: 768 },
    deviceScaleFactor: 1,
  });
  await page.goto('https://spargo-app.web.app/business-register?refresh=768', {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await page.screenshot({
    path: 'C:/Users/kara/npaartsts/tst/spargo/artifacts/business-register-1366x768.png',
    fullPage: true,
  });
  await browser.close();
})();

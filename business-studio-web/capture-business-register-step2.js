const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({
    viewport: { width: 1536, height: 960 },
    deviceScaleFactor: 1,
  });

  await page.goto('https://spargo-app.web.app/business-register?step=2', {
    waitUntil: 'networkidle',
    timeout: 120000,
  });

  await page.locator('.auth-segment button').nth(1).click();
  await page.getByPlaceholder('Business-Name oder Business + Stadt').fill('Friseur Berlin');
  await page.getByRole('button', { name: 'Suchen' }).click();
  await page.waitForTimeout(2200);
  await page.locator('.search-result').first().click();
  await page.getByRole('button', { name: /Weiter zu Schritt 2/i }).click();
  await page.waitForTimeout(900);

  await page.screenshot({
    path: 'C:/Users/kara/npaartsts/tst/spargo/artifacts/business-register-step2.png',
    fullPage: true,
  });

  await browser.close();
})();

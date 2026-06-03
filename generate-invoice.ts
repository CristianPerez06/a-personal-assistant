const { chromium } = require("playwright");

(async () => {
  const browser = await chromium.launch({
    headless: false,
  });
  const context = await browser.newContext();
  await page.goto("https://invoice-generator.com/");
  await page.getByRole("textbox").nth(1).click();
  await page.getByRole("textbox").nth(1).fill("0625");
  await page.getByRole("textbox", { name: "Who is this from?" }).click();
  await page
    .getByRole("textbox", { name: "Who is this from?" })
    .fill("REPLACE_WITH_FROM_NAME\n• REPLACE_WITH_FROM_ID");
  await page.getByRole("textbox", { name: "Who is this to?" }).click();
  await page
    .getByRole("textbox", { name: "Who is this to?" })
    .fill("• REPLACE_WITH_TO_NAME\n• REPLACE_WITH_TO_ID");
  await page.locator("#dp1780489539178").click();
  await page.locator("#dp1780489539178").fill("REPLACE_WITH_DATE");
  await page.getByRole("complementary").click();
  await page.locator("#dp1780489539179").click();
  await page.locator("#dp1780489539179").fill("REPLACE_WITH_DATE");
  await page
    .getByRole("textbox", { name: "Description of item/service..." })
    .click();
  await page
    .getByRole("textbox", { name: "Description of item/service..." })
    .fill("REPLACE_WITH_DESCRIPTION");
  await page.getByRole("spinbutton").nth(1).click();
  await page
    .getByRole("textbox", { name: "Description of item/service..." })
    .press("ControlOrMeta+a");
  await page.getByRole("spinbutton").nth(1).click();
  await page.getByRole("spinbutton").nth(1).click();
  await page.getByRole("spinbutton").nth(1).fill("REPLACE_WITH_QUANTITY");
  await page.getByRole("spinbutton").nth(1).press("Tab");
  await page.getByRole("spinbutton").first().fill("REPLACE_WITH_PRICE");
  await page.getByRole("textbox", { name: "Notes - any relevant" }).click();
  await page
    .getByRole("textbox", { name: "Notes - any relevant" })
    .fill("REPLACE_WITH_NOTES");
  const page1Promise = page.waitForEvent("popup");
  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: " Download" }).click();
  const page1 = await page1Promise;
  const download = await downloadPromise;
  await page1.close();
  await page.goto("https://invoice-generator.com/thanks?invoice=1");
  await page.close();
  const page = await context.newPage();
  await page.goto("chrome://new-tab-page/");
  await page.close();

  // ---------------------
  await context.close();
  await browser.close();
})();

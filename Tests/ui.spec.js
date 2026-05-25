const { test, expect } = require('@playwright/test');

const BASE_URL = 'http://localhost:17863';

test.describe('FlickFix UI', () => {

    test.beforeEach(async ({ page }) => {
        await page.goto(BASE_URL);
    });

    // ---- Page Load ----
    test('Page title is FlickFix', async ({ page }) => {
        await expect(page).toHaveTitle('FlickFix');
    });

    test('Header displays FlickFix', async ({ page }) => {
        const header = page.locator('h1');
        await expect(header).toHaveText('FlickFix');
    });

    test('Status badge shows Idle on load', async ({ page }) => {
        const badge = page.locator('#statusBadge');
        await expect(badge).toHaveText('Idle');
    });

    // ---- Settings Panel ----
    test('Library Root input is visible', async ({ page }) => {
        await expect(page.locator('#rootPath')).toBeVisible();
    });

    test('Browse button is visible', async ({ page }) => {
        await expect(page.locator('#browseRoot')).toBeVisible();
    });

    test('Workers slider is visible', async ({ page }) => {
        await expect(page.locator('#workerCount')).toBeVisible();
    });

    // ---- Operation Mode ----
    test('Scan & Repair radio is present', async ({ page }) => {
        await expect(page.locator('input[value="Full"]')).toBeVisible();
    });

    test('Compression radio is present', async ({ page }) => {
        await expect(page.locator('input[value="SmartCompression"]')).toBeVisible();
    });

    test('Selecting Compression shows Smart Compression panel', async ({ page }) => {
        await page.locator('input[value="SmartCompression"]').click();
        await expect(page.locator('#smartOptions')).toBeVisible();
    });

	test('Selecting Scan hides Smart Compression panel', async ({ page }) => {
        await page.locator('input[value="SmartCompression"]').click();
        await page.locator('input[value="ScanOnly"]').click();
        await expect(page.locator('#smartOptions')).toHaveClass(/hidden/);
    });

    // ---- CRF Slider ----
    test('CRF slider default value is 22', async ({ page }) => {
        await page.locator('input[value="SmartCompression"]').click();
        const value = await page.locator('#crfSlider').inputValue();
        expect(value).toBe('22');
    });

    test('CRF value label updates when slider moves', async ({ page }) => {
        await page.locator('input[value="SmartCompression"]').click();
        await page.locator('#crfSlider').fill('25');
        await page.locator('#crfSlider').dispatchEvent('input');
        await expect(page.locator('#crfValue')).toHaveText('25');
    });

    // ---- Buttons ----
    test('Start button is visible', async ({ page }) => {
        await expect(page.locator('#startBtn')).toBeVisible();
    });

    test('Cancel button is visible', async ({ page }) => {
        await expect(page.locator('#cancelBtn')).toBeVisible();
    });

    test('Start button shows error when no root path set', async ({ page }) => {
        await page.locator('#rootPath').fill('');
        await page.locator('#startBtn').click();
        await expect(page.locator('#errorModal')).toBeVisible();
    });

    // ---- Log Buttons ----
    test('Human Log button is visible', async ({ page }) => {
        await expect(page.locator('#humanLogBtn')).toBeVisible();
    });

    test('Machine Log button is visible', async ({ page }) => {
        await expect(page.locator('#machineLogBtn')).toBeVisible();
    });

});
const { test, expect } = require('@playwright/test');

const BASE_URL = 'http://localhost:17863';

// ================================================================
// HELPERS
// ================================================================

async function resetConfig(page) {
    await page.request.get(`${BASE_URL}/config/save?root=&repaired=&mode=Full&scanAll=false&accurateMode=false`);
    await page.goto(BASE_URL);
    await page.waitForFunction(() => {
        const desc = document.getElementById('scanModeDesc');
        return desc && desc.textContent.includes('fast results');
    });
}

async function selectMode(page, mode) {
    await page.locator(`input[value="${mode}"]`).click();
}

// ================================================================
// SUITE 1: Page Load
// ================================================================
test.describe('Page Load', () => {

    test.beforeEach(async ({ page }) => { await resetConfig(page); });

    test('Page title is FlickFix', async ({ page }) => {
        await expect(page).toHaveTitle('FlickFix');
    });

    test('Header displays FlickFix', async ({ page }) => {
        await expect(page.locator('h1')).toHaveText('FlickFix');
    });

    test('Status badge is visible and shows a valid state', async ({ page }) => {
        const badge = page.locator('#statusBadge');
        await expect(badge).toBeVisible();
        const text = await badge.textContent();
        expect(['Idle', 'Running', 'Completed']).toContain(text.trim());
    });

    test('Console element is visible', async ({ page }) => {
        await expect(page.locator('#consoleOutput')).toBeVisible();
    });

    test('Scan & Repair is selected after config reset', async ({ page }) => {
        await expect(page.locator('input[value="Full"]')).toBeChecked();
    });

    test('Smart Compression panel is hidden after config reset', async ({ page }) => {
        await expect(page.locator('#smartOptions')).toHaveClass(/hidden/);
    });

    test('All four operation mode radios are present', async ({ page }) => {
        await expect(page.locator('input[value="Full"]')).toBeVisible();
        await expect(page.locator('input[value="ScanOnly"]')).toBeVisible();
        await expect(page.locator('input[value="RepairOnly"]')).toBeVisible();
        await expect(page.locator('input[value="SmartCompression"]')).toBeVisible();
    });

});

// ================================================================
// SUITE 2: Settings Panel
// ================================================================
test.describe('Settings Panel', () => {

    test.beforeEach(async ({ page }) => { await resetConfig(page); });

    test('Library Root input is visible and enabled', async ({ page }) => {
        await expect(page.locator('#rootPath')).toBeVisible();
        await expect(page.locator('#rootPath')).toBeEnabled();
    });

    test('Library Root Browse button is visible and enabled', async ({ page }) => {
        await expect(page.locator('#browseRoot')).toBeVisible();
        await expect(page.locator('#browseRoot')).toBeEnabled();
    });

    test('Repaired Output input is visible and enabled', async ({ page }) => {
        await expect(page.locator('#repairedPath')).toBeVisible();
        await expect(page.locator('#repairedPath')).toBeEnabled();
    });

    test('Repaired Output Browse button is visible and enabled', async ({ page }) => {
        await expect(page.locator('#browseRepaired')).toBeVisible();
        await expect(page.locator('#browseRepaired')).toBeEnabled();
    });

    test('Workers slider is visible and enabled', async ({ page }) => {
        await expect(page.locator('#workerCount')).toBeVisible();
        await expect(page.locator('#workerCount')).toBeEnabled();
    });

    test('Workers value label updates when slider moves', async ({ page }) => {
        await page.locator('#workerCount').fill('6');
        await page.locator('#workerCount').dispatchEvent('input');
        await expect(page.locator('#workerValue')).toHaveText('6');
    });

    test('Workers description shows Less CPU intensive at value 1', async ({ page }) => {
        await page.locator('#workerCount').fill('1');
        await page.locator('#workerCount').dispatchEvent('input');
        await expect(page.locator('#workerDesc')).toContainText('Less CPU intensive');
    });

	test('Workers description does NOT show Recommended when not at 4', async ({ page }) => {
        await page.locator('#workerCount').fill('1');
        await page.locator('#workerCount').dispatchEvent('input');
        await expect(page.locator('#workerDesc')).not.toHaveText('Recommended — balance of speed and CPU resources');
    });

    test('Workers description shows More CPU intensive at value 8', async ({ page }) => {
        await page.locator('#workerCount').fill('8');
        await page.locator('#workerCount').dispatchEvent('input');
        await expect(page.locator('#workerDesc')).toContainText('More CPU intensive');
    });

    test('Scan mode toggle shows Quick description when unchecked', async ({ page }) => {
        await page.locator('#scanAllEpisodes').uncheck();
        await expect(page.locator('#scanModeDesc')).toContainText('fast results');
    });

	test('Scan mode description changes when toggled to Full', async ({ page }) => {
        const before = await page.locator('#scanModeDesc').textContent();
        await page.locator('#scanAllEpisodes').evaluate(el => el.click());
        const after = await page.locator('#scanModeDesc').textContent();
        expect(before).not.toBe(after);
    });

    test('Scan mode description changes back when toggled to Quick', async ({ page }) => {
        await page.locator('#scanAllEpisodes').evaluate(el => el.click());
        const before = await page.locator('#scanModeDesc').textContent();
        await page.locator('#scanAllEpisodes').evaluate(el => el.click());
        const after = await page.locator('#scanModeDesc').textContent();
        expect(before).not.toBe(after);
    });

});

// ================================================================
// SUITE 3: Mode — Scan & Repair
// ================================================================
test.describe('Mode: Scan & Repair', () => {

    test.beforeEach(async ({ page }) => {
        await resetConfig(page);
        await selectMode(page, 'Full');
    });

    test('Library Root is enabled', async ({ page }) => {
        await expect(page.locator('#rootPath')).toBeEnabled();
    });

    test('Library Root Browse is enabled', async ({ page }) => {
        await expect(page.locator('#browseRoot')).toBeEnabled();
    });

    test('Repaired Output is enabled', async ({ page }) => {
        await expect(page.locator('#repairedPath')).toBeEnabled();
    });

    test('Repaired Output Browse is enabled', async ({ page }) => {
        await expect(page.locator('#browseRepaired')).toBeEnabled();
    });

    test('Workers slider is enabled', async ({ page }) => {
        await expect(page.locator('#workerCount')).toBeEnabled();
    });

    test('Scan toggle is enabled', async ({ page }) => {
        await expect(page.locator('#scanAllEpisodes')).toBeEnabled();
    });

    test('Start button is enabled', async ({ page }) => {
        await expect(page.locator('#startBtn')).toBeEnabled();
    });

    test('Smart Compression panel is hidden', async ({ page }) => {
        await expect(page.locator('#smartOptions')).toHaveClass(/hidden/);
    });

    test('Start with no root path shows error modal', async ({ page }) => {
        await page.locator('#rootPath').fill('');
        await page.locator('#startBtn').click();
        await expect(page.locator('#errorModal')).toBeVisible();
    });

    test('Start with no repaired path shows error modal', async ({ page }) => {
        await page.locator('#rootPath').fill('C:\\FakePath');
        await page.locator('#repairedPath').fill('');
        await page.locator('#startBtn').click();
        await expect(page.locator('#errorModal')).toBeVisible();
    });

    test('Start with both paths blank shows error mentioning Library Root first', async ({ page }) => {
        await page.locator('#rootPath').fill('');
        await page.locator('#repairedPath').fill('');
        await page.locator('#startBtn').click();
        await expect(page.locator('#errorModal')).toBeVisible();
        await expect(page.locator('#errorMessage')).toContainText('Library Root');
    });

    test('All mode radios are still selectable', async ({ page }) => {
        for (const mode of ['ScanOnly', 'RepairOnly', 'SmartCompression', 'Full']) {
            await page.locator(`input[value="${mode}"]`).click();
            await expect(page.locator(`input[value="${mode}"]`)).toBeChecked();
        }
    });

});

// ================================================================
// SUITE 4: Mode — Scan Only
// ================================================================
test.describe('Mode: Scan Only', () => {

    test.beforeEach(async ({ page }) => {
        await resetConfig(page);
        await selectMode(page, 'ScanOnly');
    });

    test('Library Root is enabled', async ({ page }) => {
        await expect(page.locator('#rootPath')).toBeEnabled();
    });

    test('Library Root Browse is enabled', async ({ page }) => {
        await expect(page.locator('#browseRoot')).toBeEnabled();
    });

    test('Repaired Output is disabled', async ({ page }) => {
        await expect(page.locator('#repairedPath')).toBeDisabled();
    });

    test('Repaired Output Browse is disabled', async ({ page }) => {
        await expect(page.locator('#browseRepaired')).toBeDisabled();
    });

    test('Workers slider is enabled', async ({ page }) => {
        await expect(page.locator('#workerCount')).toBeEnabled();
    });

    test('Scan toggle is enabled', async ({ page }) => {
        await expect(page.locator('#scanAllEpisodes')).toBeEnabled();
    });

    test('Smart Compression panel is hidden', async ({ page }) => {
        await expect(page.locator('#smartOptions')).toHaveClass(/hidden/);
    });

    test('Start with no root path shows error modal', async ({ page }) => {
        await page.locator('#rootPath').fill('');
        await page.locator('#startBtn').click();
        await expect(page.locator('#errorModal')).toBeVisible();
    });

    test('Start with no repaired path proceeds without error modal', async ({ page }) => {
        await page.locator('#rootPath').fill('C:\\FakePath');
        await page.locator('#startBtn').click();
        await expect(page.locator('#errorModal')).toBeHidden();
    });

    test('Start with both paths blank shows error mentioning Library Root', async ({ page }) => {
        await page.locator('#rootPath').fill('');
        await page.locator('#startBtn').click();
        await expect(page.locator('#errorModal')).toBeVisible();
        await expect(page.locator('#errorMessage')).toContainText('Library Root');
    });

});

// ================================================================
// SUITE 5: Mode — Repair Only
// ================================================================
test.describe('Mode: Repair Only', () => {

    test.beforeEach(async ({ page }) => {
        await resetConfig(page);
        await selectMode(page, 'RepairOnly');
    });

    test('Library Root is disabled', async ({ page }) => {
        await expect(page.locator('#rootPath')).toBeDisabled();
    });

    test('Library Root Browse is disabled', async ({ page }) => {
        await expect(page.locator('#browseRoot')).toBeDisabled();
    });

    test('Repaired Output is enabled', async ({ page }) => {
        await expect(page.locator('#repairedPath')).toBeEnabled();
    });

    test('Repaired Output Browse is enabled', async ({ page }) => {
        await expect(page.locator('#browseRepaired')).toBeEnabled();
    });

    test('Workers slider is enabled', async ({ page }) => {
        await expect(page.locator('#workerCount')).toBeEnabled();
    });

    test('Smart Compression panel is hidden', async ({ page }) => {
        await expect(page.locator('#smartOptions')).toHaveClass(/hidden/);
    });

    test('Start with no repaired path shows error modal', async ({ page }) => {
        await page.locator('#repairedPath').fill('');
        await page.locator('#startBtn').click();
        await expect(page.locator('#errorModal')).toBeVisible();
    });

    test('Start with repaired path and no root path proceeds without error modal', async ({ page }) => {
        await page.locator('#repairedPath').fill('C:\\FakePath');
        await page.locator('#startBtn').click();
        await expect(page.locator('#errorModal')).toBeHidden();
    });

    test('Start with both paths blank shows error mentioning Repaired Output', async ({ page }) => {
        await page.locator('#repairedPath').fill('');
        await page.locator('#startBtn').click();
        await expect(page.locator('#errorModal')).toBeVisible();
        await expect(page.locator('#errorMessage')).toContainText('Repaired Output');
    });

});

// ================================================================
// SUITE 6: Mode — Smart Compression
// ================================================================
test.describe('Mode: Smart Compression', () => {

    test.beforeEach(async ({ page }) => {
        await resetConfig(page);
        await selectMode(page, 'SmartCompression');
    });

    test('Smart Compression panel is visible', async ({ page }) => {
        await expect(page.locator('#smartOptions')).not.toHaveClass(/hidden/);
    });

    test('Library Root is enabled', async ({ page }) => {
        await expect(page.locator('#rootPath')).toBeEnabled();
    });

    test('Library Root Browse is enabled', async ({ page }) => {
        await expect(page.locator('#browseRoot')).toBeEnabled();
    });

    test('Repaired Output is disabled', async ({ page }) => {
        await expect(page.locator('#repairedPath')).toBeDisabled();
    });

    test('Repaired Output Browse is disabled', async ({ page }) => {
        await expect(page.locator('#browseRepaired')).toBeDisabled();
    });

    test('Workers slider is enabled', async ({ page }) => {
        await expect(page.locator('#workerCount')).toBeEnabled();
    });

    test('Scan toggle is enabled', async ({ page }) => {
        await expect(page.locator('#scanAllEpisodes')).toBeEnabled();
    });

    test('CRF slider is visible and enabled', async ({ page }) => {
        await expect(page.locator('#crfSlider')).toBeVisible();
        await expect(page.locator('#crfSlider')).toBeEnabled();
    });

    test('CRF value label updates when slider moves', async ({ page }) => {
        await page.locator('#crfSlider').fill('25');
        await page.locator('#crfSlider').dispatchEvent('input');
        await expect(page.locator('#crfValue')).toHaveText('25');
    });

    test('CRF description shows Near lossless at value 18', async ({ page }) => {
        await page.locator('#crfSlider').fill('18');
        await page.locator('#crfSlider').dispatchEvent('input');
        await expect(page.locator('#crfDesc')).toContainText('Near lossless');
    });

    test('CRF description shows Recommended at value 22', async ({ page }) => {
        await page.locator('#crfSlider').fill('22');
        await page.locator('#crfSlider').dispatchEvent('input');
        await expect(page.locator('#crfDesc')).toContainText('Recommended');
    });

    test('CRF description shows Low quality at value 28', async ({ page }) => {
        await page.locator('#crfSlider').fill('28');
        await page.locator('#crfSlider').dispatchEvent('input');
        await expect(page.locator('#crfDesc')).toContainText('Low quality');
    });

	test('Accurate mode toggle is attached and enabled', async ({ page }) => {
        await expect(page.locator('#accurateMode')).toBeAttached();
        await expect(page.locator('#accurateMode')).toBeEnabled();
    });

	test('Accurate mode description changes when toggled on', async ({ page }) => {
        await page.locator('#accurateMode').evaluate(el => { el.checked = false; el.dispatchEvent(new Event('change')); });
        await expect(page.locator('#smartMethodDesc')).toHaveText('Quick results across your entire library');
        await page.locator('#accurateMode').evaluate(el => { el.checked = true; el.dispatchEvent(new Event('change')); });
        await expect(page.locator('#smartMethodDesc')).not.toHaveText('Quick results across your entire library');
    });

    test('Accurate mode description changes when toggled off', async ({ page }) => {
        await page.locator('#accurateMode').evaluate(el => { el.checked = true; el.dispatchEvent(new Event('change')); });
        await expect(page.locator('#smartMethodDesc')).not.toHaveText('Quick results across your entire library');
        await page.locator('#accurateMode').evaluate(el => { el.checked = false; el.dispatchEvent(new Event('change')); });
        await expect(page.locator('#smartMethodDesc')).toHaveText('Quick results across your entire library');
    });
	
    test('Review button is visible', async ({ page }) => {
        await expect(page.locator('#reviewBtn')).toBeVisible();
    });

	test('Review button has disabled-ui class when no SmartProbe log data exists', async ({ page }) => {
        await expect(page.locator('#reviewBtn')).toHaveClass(/disabled-ui/);
    });

    test('Start with no root path shows error modal', async ({ page }) => {
        await page.locator('#rootPath').fill('');
        await page.locator('#startBtn').click();
        await expect(page.locator('#errorModal')).toBeVisible();
    });

    test('Start with both paths blank shows error mentioning Library Root', async ({ page }) => {
        await page.locator('#rootPath').fill('');
        await page.locator('#startBtn').click();
        await expect(page.locator('#errorModal')).toBeVisible();
        await expect(page.locator('#errorMessage')).toContainText('Library Root');
    });

});

// ================================================================
// SUITE 7: Mode Switching
// ================================================================
test.describe('Mode Switching', () => {

    test.beforeEach(async ({ page }) => { await resetConfig(page); });

    test('All mode radios are always selectable', async ({ page }) => {
        for (const mode of ['Full', 'ScanOnly', 'RepairOnly', 'SmartCompression']) {
            await page.locator(`input[value="${mode}"]`).click();
            await expect(page.locator(`input[value="${mode}"]`)).toBeChecked();
        }
    });

    test('Switching from Repair Only back to Full re-enables Library Root', async ({ page }) => {
        await selectMode(page, 'RepairOnly');
        await selectMode(page, 'Full');
        await expect(page.locator('#rootPath')).toBeEnabled();
    });

    test('Switching from Compression back to Full re-enables Repaired Output', async ({ page }) => {
        await selectMode(page, 'SmartCompression');
        await selectMode(page, 'Full');
        await expect(page.locator('#repairedPath')).toBeEnabled();
    });

    test('Switching away from Compression hides Smart Compression panel', async ({ page }) => {
        await selectMode(page, 'SmartCompression');
        await selectMode(page, 'ScanOnly');
        await expect(page.locator('#smartOptions')).toHaveClass(/hidden/);
    });

});

// ================================================================
// SUITE 8: Error Modal
// ================================================================
test.describe('Error Modal', () => {

    test.beforeEach(async ({ page }) => { await resetConfig(page); });

    test('Error modal is hidden on load', async ({ page }) => {
        await expect(page.locator('#errorModal')).toHaveClass(/hidden/);
    });

    test('Error modal OK button closes it', async ({ page }) => {
        await page.locator('#rootPath').fill('');
        await page.locator('#startBtn').click();
        await page.locator('#errorOk').click();
        await expect(page.locator('#errorModal')).toHaveClass(/hidden/);
    });

	test('Error message contains text when shown', async ({ page }) => {
        await page.locator('#rootPath').fill('');
        await page.locator('#startBtn').click();
        await expect(page.locator('#errorModal')).toBeVisible();
        await expect(page.locator('#errorMessage')).not.toBeEmpty();
    });

});

// ================================================================
// SUITE 9: Log Panel
// ================================================================
test.describe('Log Panel', () => {

    test.beforeEach(async ({ page }) => { await resetConfig(page); });

    test('Log pane is closed by default', async ({ page }) => {
        await expect(page.locator('#logPane')).not.toHaveClass(/open/);
    });

    test('Human Log button opens log pane', async ({ page }) => {
        await page.locator('#humanLogBtn').click();
        await expect(page.locator('#logPane')).toHaveClass(/open/);
    });

    test('Clicking Human Log again closes log pane', async ({ page }) => {
        await page.locator('#humanLogBtn').click();
        await page.locator('#humanLogBtn').click();
        await expect(page.locator('#logPane')).not.toHaveClass(/open/);
    });

    test('Machine Log button opens log pane', async ({ page }) => {
        await page.locator('#machineLogBtn').click();
        await expect(page.locator('#logPane')).toHaveClass(/open/);
    });

    test('Clicking Machine Log again closes log pane', async ({ page }) => {
        await page.locator('#machineLogBtn').click();
        await page.locator('#machineLogBtn').click();
        await expect(page.locator('#logPane')).not.toHaveClass(/open/);
    });

    test('Human and Machine Log cannot both be active simultaneously', async ({ page }) => {
        await page.locator('#humanLogBtn').click();
        await page.locator('#machineLogBtn').click();
        const humanActive   = await page.locator('#humanLogBtn').evaluate(el => el.classList.contains('active'));
        const machineActive = await page.locator('#machineLogBtn').evaluate(el => el.classList.contains('active'));
        expect(humanActive && machineActive).toBe(false);
    });

    test('Human Log button gets active class when clicked', async ({ page }) => {
        await page.locator('#humanLogBtn').click();
        await expect(page.locator('#humanLogBtn')).toHaveClass(/active/);
    });

    test('Machine Log button gets active class when clicked', async ({ page }) => {
        await page.locator('#machineLogBtn').click();
        await expect(page.locator('#machineLogBtn')).toHaveClass(/active/);
    });

    test('Clicking Machine Log removes Human Log active class', async ({ page }) => {
        await page.locator('#humanLogBtn').click();
        await page.locator('#machineLogBtn').click();
        const humanActive = await page.locator('#humanLogBtn').evaluate(el => el.classList.contains('active'));
        expect(humanActive).toBe(false);
    });

    test('Log filter input accepts text when log is open', async ({ page }) => {
        await page.locator('#humanLogBtn').click();
        await page.locator('#logFilterInput').fill('test search');
        await expect(page.locator('#logFilterInput')).toHaveValue('test search');
    });

    test('Log filter clear button empties input', async ({ page }) => {
        await page.locator('#humanLogBtn').click();
        await page.locator('#logFilterInput').fill('test search');
        await page.locator('#logFilterClear').click();
        await expect(page.locator('#logFilterInput')).toHaveValue('');
    });

    test('Clear Logs button shows confirm modal', async ({ page }) => {
        await page.locator('#humanLogBtn').click();
        await page.locator('#clearLogsBtn').click();
        await expect(page.locator('#confirmModal')).toBeVisible();
    });

    test('Confirm modal Cancel button closes it', async ({ page }) => {
        await page.locator('#humanLogBtn').click();
        await page.locator('#clearLogsBtn').click();
        await page.locator('#confirmNo').click();
        await expect(page.locator('#confirmModal')).toHaveClass(/hidden/);
    });

    test('Confirm modal OK button closes it', async ({ page }) => {
        await page.locator('#humanLogBtn').click();
        await page.locator('#clearLogsBtn').click();
        await page.locator('#confirmYes').click();
        await expect(page.locator('#confirmModal')).toHaveClass(/hidden/);
    });

});

// ================================================================
// SUITE 10: Compression Modal Structure
// ================================================================
test.describe('Compression Modal Structure', () => {

    test.beforeEach(async ({ page }) => { await resetConfig(page); });

    test('Compression modal is hidden on load', async ({ page }) => {
        await expect(page.locator('#compressionModal')).toHaveClass(/hidden/);
    });

    test('Compression output path input is present', async ({ page }) => {
        await expect(page.locator('#compressionOutputPath')).toBeAttached();
    });

    test('Compression Browse button is present', async ({ page }) => {
        await expect(page.locator('#compressionBrowse')).toBeAttached();
    });

    test('Compression worker slider defaults to 2', async ({ page }) => {
        await expect(page.locator('#compressWorkerCount')).toHaveValue('2');
    });

	test('Compression worker description changes away from Recommended when not at 2', async ({ page }) => {
        await page.locator('#compressWorkerCount').fill('1', { force: true });
        await page.locator('#compressWorkerCount').dispatchEvent('input');
        await expect(page.locator('#compressWorkerDesc')).not.toHaveText('Recommended — balance of speed and CPU resources');
    });

    test('Compression worker value label updates when slider moves away from 2', async ({ page }) => {
        await page.locator('#compressWorkerCount').fill('4', { force: true });
        await page.locator('#compressWorkerCount').dispatchEvent('input');
        await expect(page.locator('#compressWorkerValue')).toHaveText('4');
    });

    test('Compression worker description is not blank at value 1', async ({ page }) => {
        await page.locator('#compressWorkerCount').fill('1', { force: true });
        await page.locator('#compressWorkerCount').dispatchEvent('input');
        await expect(page.locator('#compressWorkerDesc')).not.toBeEmpty();
    });

    test('Compression worker description is not blank at value 4', async ({ page }) => {
        await page.locator('#compressWorkerCount').fill('4', { force: true });
        await page.locator('#compressWorkerCount').dispatchEvent('input');
        await expect(page.locator('#compressWorkerDesc')).not.toBeEmpty();
    });

    test('Compression tree Size column header is present', async ({ page }) => {
        await expect(page.locator('.tree-th-size')).toBeAttached();
    });

    test('Compression tree Verdict column header is present', async ({ page }) => {
        await expect(page.locator('.tree-th-verdict')).toBeAttached();
    });

    test('Compression close button is present', async ({ page }) => {
        await expect(page.locator('#compressionClose')).toBeAttached();
    });

    test('Compression start button is present', async ({ page }) => {
        await expect(page.locator('#compressionStart')).toBeAttached();
    });

});

// ================================================================
// SUITE 11: API Endpoints
// Verifies all server endpoints respond correctly
// ================================================================
test.describe('API Endpoints', () => {

    test('/logs/total returns ok and total count', async ({ page }) => {
        const res = await page.request.get(`${BASE_URL}/logs/total`);
        const json = await res.json();
        expect(json.ok).toBe(true);
        expect(typeof json.total).toBe('number');
    });

    test('/logs/slice returns ok, entries array, and total', async ({ page }) => {
        const res = await page.request.get(`${BASE_URL}/logs/slice?start=0&end=10`);
        const json = await res.json();
        expect(json.ok).toBe(true);
        expect(Array.isArray(json.entries)).toBe(true);
        expect(typeof json.total).toBe('number');
    });

    test('/logs/slice with no data returns empty entries', async ({ page }) => {
        // Clear logs first
        await page.request.get(`${BASE_URL}/logs/clear`);
        const res = await page.request.get(`${BASE_URL}/logs/slice?start=0&end=10`);
        const json = await res.json();
        expect(json.ok).toBe(true);
        expect(json.entries.length).toBe(0);
    });

    test('/logs/search returns ok and entries array', async ({ page }) => {
        const res = await page.request.get(`${BASE_URL}/logs/search?q=test&max=10`);
        const json = await res.json();
        expect(json.ok).toBe(true);
        expect(Array.isArray(json.entries)).toBe(true);
        expect(typeof json.total).toBe('number');
    });

    test('/logs/search with empty query returns empty entries', async ({ page }) => {
        const res = await page.request.get(`${BASE_URL}/logs/search?q=&max=10`);
        const json = await res.json();
        expect(json.ok).toBe(true);
        expect(json.entries.length).toBe(0);
    });

    test('/logs/clear returns ok', async ({ page }) => {
        const res = await page.request.get(`${BASE_URL}/logs/clear`);
        const json = await res.json();
        expect(json.ok).toBe(true);
    });

    test('/logs/total returns 0 after clear', async ({ page }) => {
        await page.request.get(`${BASE_URL}/logs/clear`);
        const res = await page.request.get(`${BASE_URL}/logs/total`);
        const json = await res.json();
        expect(json.ok).toBe(true);
        expect(json.total).toBe(0);
    });

    test('/status returns a valid status string', async ({ page }) => {
        const res = await page.request.get(`${BASE_URL}/status`);
        const json = await res.json();
        expect(['idle', 'running', 'completed', 'error']).toContain(json.status);
    });

    test('/status-all returns status and logTotal', async ({ page }) => {
        const res = await page.request.get(`${BASE_URL}/status-all`);
        const json = await res.json();
        expect(typeof json.logTotal).toBe('number');
        // status can be null when idle, so just check it exists
        expect('status' in json).toBe(true);
        expect('logTotal' in json).toBe(true);
    });

    test('/status-console returns a status field', async ({ page }) => {
        const res = await page.request.get(`${BASE_URL}/status-console`);
        const json = await res.json();
        expect('status' in json).toBe(true);
    });

    test('/config returns ok and config object', async ({ page }) => {
        const res = await page.request.get(`${BASE_URL}/config`);
        const json = await res.json();
        expect(json.ok).toBe(true);
        expect(json.config).toBeDefined();
        expect(typeof json.config.RootPath).toBe('string');
    });

});

// ================================================================
// SUITE 12: Search Filter Behavior
// Tests server-side search and client filter interactions
// ================================================================
test.describe('Search Filter', () => {

    test.beforeEach(async ({ page }) => { await resetConfig(page); });

    test('Search filter input is present when log is open', async ({ page }) => {
        await page.locator('#machineLogBtn').click();
        await expect(page.locator('#logFilterInput')).toBeVisible();
    });

    test('Typing in filter updates the input value', async ({ page }) => {
        await page.locator('#machineLogBtn').click();
        await page.locator('#logFilterInput').fill('test query');
        await expect(page.locator('#logFilterInput')).toHaveValue('test query');
    });

    test('Clear button resets filter input', async ({ page }) => {
        await page.locator('#machineLogBtn').click();
        await page.locator('#logFilterInput').fill('something');
        await page.locator('#logFilterClear').click();
        await expect(page.locator('#logFilterInput')).toHaveValue('');
    });

    test('Filter with no matches shows appropriate message', async ({ page }) => {
        await page.request.get(`${BASE_URL}/logs/clear`);
        await page.locator('#machineLogBtn').click();
        await page.locator('#logFilterInput').fill('zzz_nonexistent_query_zzz');
        await page.locator('#logFilterInput').dispatchEvent('input');
        // Wait for debounce + server response
        await page.waitForTimeout(500);
        const text = await page.locator('#logContent').textContent();
        expect(text.length).toBeGreaterThan(0);
    });

    test('Search with backslash in query does not crash', async ({ page }) => {
        await page.locator('#machineLogBtn').click();
        await page.locator('#logFilterInput').fill('Shows\\Test');
        await page.locator('#logFilterInput').dispatchEvent('input');
        await page.waitForTimeout(500);
        // Should not throw — page should still be responsive
        await expect(page.locator('#logFilterInput')).toBeVisible();
    });

});

// ================================================================
// SUITE 13: Log Panel — Mode Integrity
// Ensures switching between human/machine mode renders correctly
// ================================================================
test.describe('Log Mode Integrity', () => {

    test.beforeEach(async ({ page }) => { await resetConfig(page); });

    test('Machine log button sets machine-log class on content', async ({ page }) => {
        await page.locator('#machineLogBtn').click();
        const hasMachineClass = await page.locator('#logContent').evaluate(
            el => el.classList.contains('machine-log')
        );
        expect(hasMachineClass).toBe(true);
    });

    test('Human log button removes machine-log class from content', async ({ page }) => {
        await page.locator('#machineLogBtn').click();
        await page.locator('#humanLogBtn').click();
        const hasMachineClass = await page.locator('#logContent').evaluate(
            el => el.classList.contains('machine-log')
        );
        expect(hasMachineClass).toBe(false);
    });

    test('Switching from human to machine does not show human-formatted content', async ({ page }) => {
        await page.locator('#humanLogBtn').click();
        await page.waitForTimeout(300);
        await page.locator('#machineLogBtn').click();
        await page.waitForTimeout(300);
        const hasMachineClass = await page.locator('#logContent').evaluate(
            el => el.classList.contains('machine-log')
        );
        expect(hasMachineClass).toBe(true);
    });

    test('Closing and reopening log pane resets machine-log class', async ({ page }) => {
        await page.locator('#machineLogBtn').click();
        await page.locator('#machineLogBtn').click(); // close
        const hasMachineClass = await page.locator('#logContent').evaluate(
            el => el.classList.contains('machine-log')
        );
        expect(hasMachineClass).toBe(false);
    });

    test('Resume scroll button is hidden when log opens', async ({ page }) => {
        await page.locator('#machineLogBtn').click();
        await expect(page.locator('#resumeScrollBtn')).toHaveClass(/hidden/);
    });

});

// ================================================================
// SUITE 14: Console Updates
// Verifies the console area receives and displays status data
// ================================================================
test.describe('Console', () => {

    test.beforeEach(async ({ page }) => { await resetConfig(page); });

    test('Console output element is visible on load', async ({ page }) => {
        await expect(page.locator('#consoleOutput')).toBeVisible();
    });

    test('/status-all endpoint responds within 2 seconds', async ({ page }) => {
        const start = Date.now();
        const res = await page.request.get(`${BASE_URL}/status-all`);
        const elapsed = Date.now() - start;
        expect(res.ok()).toBe(true);
        expect(elapsed).toBeLessThan(2000);
    });

    test('/status-console endpoint responds within 2 seconds', async ({ page }) => {
        const start = Date.now();
        const res = await page.request.get(`${BASE_URL}/status-console`);
        const elapsed = Date.now() - start;
        expect(res.ok()).toBe(true);
        expect(elapsed).toBeLessThan(2000);
    });

    test('/logs/total responds within 1 second', async ({ page }) => {
        const start = Date.now();
        const res = await page.request.get(`${BASE_URL}/logs/total`);
        const elapsed = Date.now() - start;
        expect(res.ok()).toBe(true);
        expect(elapsed).toBeLessThan(1000);
    });

    test('/logs/slice responds within 2 seconds for 200 entries', async ({ page }) => {
        const start = Date.now();
        const res = await page.request.get(`${BASE_URL}/logs/slice?start=0&end=200`);
        const elapsed = Date.now() - start;
        expect(res.ok()).toBe(true);
        expect(elapsed).toBeLessThan(2000);
    });

});

// ================================================================
// SUITE 15: Log Data Round-Trip
// Writes test entries, verifies they appear via endpoints
// ================================================================
test.describe('Log Data Round-Trip', () => {

    test('Clear then total returns 0', async ({ page }) => {
        await page.request.get(`${BASE_URL}/logs/clear`);
        const res = await page.request.get(`${BASE_URL}/logs/total`);
        const json = await res.json();
        expect(json.total).toBe(0);
    });

    test('Slice from empty log returns empty entries', async ({ page }) => {
        await page.request.get(`${BASE_URL}/logs/clear`);
        const res = await page.request.get(`${BASE_URL}/logs/slice?start=0&end=100`);
        const json = await res.json();
        expect(json.entries.length).toBe(0);
        expect(json.total).toBe(0);
    });

    test('Slice with start >= total returns clamped result', async ({ page }) => {
        await page.request.get(`${BASE_URL}/logs/clear`);
        const res = await page.request.get(`${BASE_URL}/logs/slice?start=9999&end=10000`);
        const json = await res.json();
        expect(json.ok).toBe(true);
    });

    test('Search max parameter limits results', async ({ page }) => {
        const res = await page.request.get(`${BASE_URL}/logs/search?q=a&max=1`);
        const json = await res.json();
        expect(json.ok).toBe(true);
        expect(json.entries.length).toBeLessThanOrEqual(1);
    });

    test('Status-all logTotal matches logs/total count', async ({ page }) => {
        const [allRes, totalRes] = await Promise.all([
            page.request.get(`${BASE_URL}/status-all`),
            page.request.get(`${BASE_URL}/logs/total`)
        ]);
        const allJson = await allRes.json();
        const totalJson = await totalRes.json();
        expect(allJson.logTotal).toBe(totalJson.total);
    });

});
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
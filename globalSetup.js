// globalSetup.js
// Runs once before all Playwright tests
// Resets config to a known clean state so tests are deterministic

const BASE_URL = 'http://localhost:17863';

module.exports = async function globalSetup() {
    const fetch = (...args) => import('node-fetch').then(({ default: f }) => f(...args)).catch(() => {
        // node-fetch not available, use built-in fetch (Node 18+)
        return global.fetch(...args);
    });

    try {
        await globalThis.fetch(`${BASE_URL}/config/save?root=&repaired=&mode=Full&scanAll=false&accurateMode=false`);
        console.log('  Config reset to clean state for testing');
    } catch (e) {
        console.warn('  Warning: Could not reset config. Tests may be affected by saved state.');
    }
};
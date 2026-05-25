const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
    testDir: './Tests',
    timeout: 10000,
    use: {
        baseURL: 'http://localhost:17863',
        headless: true,
    },
});
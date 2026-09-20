const { chromium } = require('playwright-core');
const fs = require('fs');
const os = require('os');
const path = require('path');

const BASE = process.env.SHOT_BASE || 'http://127.0.0.1:9999';
const SCHEME = process.argv[2] || 'light';
const OUT = process.env.SHOT_OUT || `shots/${SCHEME}`;
const MASK = JSON.parse(process.env.SHOT_MASK || '{}');
const LOG = process.env.SHOT_LOG || '';
const WIDTH = 1366;
fs.mkdirSync(OUT, { recursive: true });

const sleep = ms => new Promise(r => setTimeout(r, ms));

function chromePath() {
    const root = path.join(os.homedir(), '.cache/ms-playwright');
    const dir = fs.readdirSync(root).filter(d => /^chromium-\d+$/.test(d)).sort().pop();
    return path.join(root, dir, 'chrome-linux64/chrome');
}

/* Replace throwaway paths and the real hostname with generic ones. */
async function mask(page) {
    await page.evaluate(map => {
        const pairs = Object.entries(map).sort((a, b) => b[0].length - a[0].length);
        const fix = s => pairs.reduce((v, [from, to]) => v.split(from).join(to), s);
        const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        for (let n = w.nextNode(); n; n = w.nextNode()) n.nodeValue = fix(n.nodeValue);
        for (const el of document.querySelectorAll('input, textarea')) el.value = fix(el.value);
    }, MASK);
}

async function shot(page, name, cap = 1400) {
    await mask(page);
    await page.addStyleTag({ content: '[class*="right-side-tab"] { display: none !important }' });
    await sleep(300);
    const height = await page.evaluate(() => document.documentElement.scrollHeight);
    await page.screenshot({
        path: `${OUT}/${name}.png`, fullPage: true,
        clip: { x: 0, y: 0, width: WIDTH, height: Math.min(height, cap) },
    });
    console.log(`${OUT}/${name}.png`);
}

/* Authentic loads pages in place; the header title changing is the signal. */
async function open(page, action, title) {
    await action();
    await page.waitForFunction(
        t => document.querySelector('[data-main_title]')?.textContent.trim() === t, title, { timeout: 20000 });
    await page.waitForSelector('.ui_links_row');
    await sleep(700);
}

const nav = (page, label) => () => page.locator('.ui_links_row').getByRole('link', { name: label, exact: true }).click();

let page;
(async () => {
    const browser = await chromium.launch({ executablePath: chromePath() });
    const ctx = await browser.newContext({ viewport: { width: WIDTH, height: 850 }, deviceScaleFactor: 2, colorScheme: SCHEME });
    page = await ctx.newPage();
    if (process.env.SHOT_DEBUG) {
        page.on('console', m => console.error(`console.${m.type()}: ${m.text()}`));
        page.on('response', r => { if (r.status() >= 400) console.error(`${r.status()} ${r.url()}`); });
        page.on('requestfailed', r => console.error(`failed ${r.url()} ${r.failure()?.errorText}`));
    }

    await page.goto(`${BASE}/`, { waitUntil: 'networkidle' });
    await page.fill('input[name=user]', 'root');
    await page.fill('input[name=pass]', 'shots');
    await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle' }), page.keyboard.press('Enter')]);
    await sleep(1000);

    await open(page, async () => {
        await page.click('a[data-has-sub-link][href="#net"]');
        await page.click('a[href="/minsec/"]');
    }, 'Minsec Intrusion Prevention');
    await shot(page, '01-dashboard');

    await open(page, nav(page, 'Bans'), 'Active Bans');
    await shot(page, '02-bans', 1700);

    await open(page, nav(page, 'Filters'), 'Filters');
    await shot(page, '03-filters');

    await open(page, () => page.locator('tr', { hasText: 'sshd' }).first().getByRole('link', { name: 'Edit policy' }).click(), 'Filter Policy: sshd');
    await shot(page, '04-filter-policy');

    if (LOG) {
        await page.fill('input[name=log_file]', LOG);
        await open(page, () => page.click('button[value=test]'), 'Filter Test: sshd');
        await shot(page, '05-filter-test');
    }

    await open(page, nav(page, 'Configuration'), 'Structured Configuration');
    await shot(page, '06-config');

    await open(page, nav(page, 'Raw TOML'), 'Raw Configuration Files');
    await shot(page, '07-files');

    await open(page, () => page.locator('tr', { hasText: /\/minsec\.toml$/m }).first().getByRole('link', { name: 'Edit' }).click(), 'Edit main configuration');
    await shot(page, '08-file-edit');

    await open(page, nav(page, 'Events'), 'Event History');
    await shot(page, '09-events', 1700);

    await open(page, nav(page, 'Nftables'), 'Minsec Nftables Objects');
    await shot(page, '10-nftables', 1700);

    await browser.close();
})().catch(async e => {
    console.error(e.message);
    if (page) {
        await page.screenshot({ path: `${OUT}/failure.png` }).catch(() => {});
        console.error(await page.evaluate(() => document.body.innerText.slice(0, 3000)).catch(() => ''));
    }
    process.exit(1);
});

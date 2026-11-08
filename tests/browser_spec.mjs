// Real page in Chromium with the real feather-theme files. Browser evidence only, not in-game acceptance.
// PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs BROWSER_EXECUTABLE=/path/to/chrome node tests/browser_spec.mjs [screenshot-dir]
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const resource = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const theme = path.resolve(resource, '../../[feather]/feather-theme');
const shots = process.argv[2];
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2' };

const server = createServer(async (request, response) => {
  const file = request.url === '/' ? 'index.html' : request.url.slice(1);
  if (!['index.html', 'style.css', 'app.js'].includes(file)) { response.writeHead(404); response.end(); return; }
  response.setHeader('Content-Type', types[path.extname(file)]);
  response.end(await readFile(path.join(resource, 'web', file)));
});
await new Promise((resolve) => { server.listen(0, '127.0.0.1', resolve); });

const texts = {
  search: 'Caută model sau număr', filter_all: 'Toate', filter_stored: 'Parcate', filter_out: 'Scoase',
  section_nearby: 'Parchează lângă tine', section_vehicles: 'Vehiculele tale', engine: 'Motor', body: 'Caroserie', fuel: 'Combustibil',
  close: 'Închide', no_vehicles: 'Nu ai vehicule de acest tip.', no_match: 'Niciun vehicul nu se potrivește.',
};
const retrieve = [{ id: 'retrieve', label: 'Scoate vehiculul' }];
const items = [
  { id: 'adder', name: 'Adder', plate: 'LS12 ABC', status: 'În apropiere', tone: 'ok', group: 'out', nearby: true, actions: [{ id: 'park', label: 'Parchează vehiculul' }] },
  { id: 't20', name: 'T20', plate: 'LS56 FEU', status: 'Parcat · Burton — Garaj', tone: 'ok', group: 'stored', condition: { engine: 90, body: 45, fuel: 18 }, actions: retrieve },
  { id: 'sultan', name: 'Sultan RS', plate: 'LS77 ȚĂȘ', status: 'Parcat · Pillbox — Garaj', tone: 'ok', group: 'stored', condition: { engine: 100, body: 100, fuel: 76 }, actions: retrieve },
  { id: 'zentorno', name: 'Zentorno', plate: 'LS99 XYZ', status: 'Cheia nu e la tine', tone: 'warn', group: 'out', reason: 'Așteptarea s-a încheiat. Plătești și vehiculul revine în garaj.',
    actions: [{ id: 'rekey', method: 'cash', label: 'Plătește $2500 numerar' }, { id: 'rekey', method: 'bank', label: 'Plătește $2500 cu cardul' }] },
  { id: 'blista', name: 'Blista', plate: 'LS11 AAA', status: 'Scos', tone: 'muted', group: 'out', reason: 'Vehiculul e scos. Îl găsești după blipul de pe hartă.', actions: [] },
];
for (let index = 0; index < 12; index += 1) {
  items.push({ id: `car${index}`, name: `Vehicul lung cu nume foarte foarte lung ${index}`, plate: `LS${10 + index} BBB`, status: 'Parcat · San Andreas — Garaj', tone: 'ok', group: 'stored', condition: { engine: 70, body: 70, fuel: 70 }, actions: retrieve });
}

const browser = await chromium.launch({
  headless: true, executablePath: process.env.BROWSER_EXECUTABLE || undefined, args: ['--no-sandbox', '--disable-dev-shm-usage'],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const errors = [];
const posts = [];
let answer = { ok: true, closed: true };
let release = null;
let checks = 0;
const check = (value, label) => { assert(value, label); checks += 1; };
page.on('pageerror', (error) => errors.push(error.message));
await page.addInitScript(() => { window.GetParentResourceName = () => 'h4nr-garages'; });
await page.route(/^https:\/\/cfx-nui-feather-theme\//, async (route) => {
  const url = new URL(route.request().url());
  await route.fulfill({ body: await readFile(theme + url.pathname), contentType: types[path.extname(url.pathname)] });
});
await page.route(/^https:\/\/h4nr-garages\//, async (route) => {
  const name = new URL(route.request().url()).pathname.slice(1);
  posts.push({ name, body: JSON.parse(route.request().postData() || '{}') });
  if (name === 'action' && release) await release;
  await route.fulfill({ contentType: 'application/json', headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify(name === 'action' ? answer : { ok: true }) });
});
const send = (message) => page.evaluate((data) => { window.postMessage(data, '*'); return new Promise((resolve) => { setTimeout(resolve, 20); }); }, message);
const open = async (list = items) => {
  await send({ action: 'open', session: 1, label: 'Pillbox — Garaj', kind: 'Garaj', texts });
  await send({ action: 'view', session: 1, items: list });
};
const names = () => page.locator('.row .name').allInnerTexts();
const selectedName = () => page.locator('.row.selected .name').innerText();
const last = (name) => posts.filter((post) => post.name === name).at(-1);
const fits = (selector) => page.locator(selector).first().evaluate((element) => element.scrollWidth <= element.clientWidth + 1);
const shot = async (name) => { if (shots) await page.screenshot({ path: path.join(shots, `${name}.png`) }); };

try {
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.waitForFunction(() => document.fonts.status === 'loaded');
  check(last('ready'), 'the page says it is ready');
  check(await page.locator('#app').isHidden(), 'hidden until opened');
  const transparent = await page.evaluate(() => [getComputedStyle(document.documentElement).backgroundColor, getComputedStyle(document.body).backgroundColor]);
  check(transparent.every((color) => color === 'rgba(0, 0, 0, 0)'), 'the page around the panel is transparent');

  await open();
  check(await page.locator('#garage-name').innerText() === 'PILLBOX — GARAJ', 'garage name in the header');
  check(await page.evaluate(() => document.activeElement.id) === 'search', 'search has focus');
  check((await names())[0] === 'Adder' && await selectedName() === 'Adder', 'a nearby vehicle comes first and is selected');
  check(await page.locator('.section').first().innerText() === 'PARCHEAZĂ LÂNGĂ TINE', 'nearby section heading');
  check(await page.locator('.primary').innerText() === 'PARCHEAZĂ VEHICULUL', 'the button follows the selection');
  check(await page.evaluate(() => ['Barlow', 'Chakra Petch'].every((font) => document.fonts.check(`14px "${font}"`, 'ȚĂȘ'))), 'fonts cover Romanian diacritics');
  const box = await page.locator('#app').boundingBox();
  check(box.x + box.width <= 1280 && box.y >= 0 && box.y + box.height <= 720, 'the panel fits 720p');
  check(box.x > 640, 'the game stays visible beside the panel');
  check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'no horizontal page scroll');
  check(await page.locator('#list').evaluate((element) => element.scrollHeight > element.clientHeight), 'a long list scrolls inside the panel');
  await shot('default-720');

  // Selection and buttons.
  await page.locator('.row', { hasText: 'T20' }).click();
  check(await page.locator('.primary').innerText() === 'SCOATE VEHICULUL', 'selecting a stored car offers retrieval');
  check(await page.locator('.row.selected .bar').count() === 3, 'condition bars are shown');
  check(await page.locator('.row.selected .bar.warn').count() === 1 && await page.locator('.row.selected .bar.danger').count() === 1, 'low values use warning and danger');
  await page.locator('.row', { hasText: 'Zentorno' }).click();
  check(await page.locator('.primary, .secondary').count() === 2, 'recovery offers both payments');
  check((await page.locator('#reason').innerText()).startsWith('Așteptarea'), 'recovery explains itself');
  await shot('rekey-720');
  await page.locator('.row', { hasText: 'Blista' }).click();
  check(await page.locator('.primary').count() === 0 && (await page.locator('#reason').innerText()).includes('blip'), 'nothing to do says why');
  await page.locator('.row', { hasText: 'Zentorno' }).click();
  await page.locator('.secondary').click();
  await page.waitForFunction(() => document.querySelector('#notice').hidden === false || document.querySelector('.primary:not(:disabled)'));
  assert.deepEqual(last('action').body, { session: 1, assetId: 'zentorno', id: 'rekey', method: 'bank' });
  checks += 1;

  // A truck comes out alone unless a trailer is ticked.
  const tow = [{ id: 'retrieve', label: 'Scoate vehiculul' }, { id: 'retrieve', method: 'tr1', towing: true, label: 'Cu remorca Tanker (TR1)' }, { id: 'retrieve', method: 'tr2', towing: true, label: 'Cu remorca Trflat (TR2)' }];
  const truckList = [{ id: 'hauler', name: 'Hauler', plate: 'TIR 1', status: 'Parcat', tone: 'ok', group: 'stored', actions: tow }];
  await open(truckList);
  check(await page.locator('.tow input').count() === 2 && await page.locator('.primary, .secondary').count() === 1, 'trailers are checkboxes beside one button');
  check(await page.locator('.tow input:checked').count() === 0, 'nothing is ticked at first');
  await shot('trailer-720');
  await page.locator('.primary').click();
  await page.waitForFunction(() => document.querySelector('.primary:not(:disabled)'));
  assert.deepEqual(last('action').body, { session: 1, assetId: 'hauler', id: 'retrieve' });
  await page.locator('.tow input').nth(0).check();
  await page.locator('.tow input').nth(1).check();
  check(await page.locator('.tow input:checked').count() === 1, 'one trailer at a time');
  await page.locator('.primary').click();
  await page.waitForFunction(() => document.querySelector('.primary:not(:disabled)'));
  assert.deepEqual(last('action').body, { session: 1, assetId: 'hauler', id: 'retrieve', method: 'tr2' });
  await page.locator('.tow input').nth(1).uncheck();
  await page.locator('.primary').click();
  await page.waitForFunction(() => document.querySelector('.primary:not(:disabled)'));
  assert.deepEqual(last('action').body, { session: 1, assetId: 'hauler', id: 'retrieve' });
  checks += 3;
  await open();
  await page.locator('.row', { hasText: 'Zentorno' }).click();

  // Search and filters.
  await page.fill('#search', 'ls56');
  check((await names()).join() === 'T20' && await selectedName() === 'T20', 'search by plate moves the selection');
  await page.fill('#search', 'nimic');
  check(await page.locator('.empty').innerText() === texts.no_match && await page.locator('.primary').count() === 0, 'no match offers no action');
  await page.fill('#search', '');
  await page.locator('.filter').nth(2).click();
  check(await page.locator('.filter').nth(2).innerText() === 'Scoase 3', 'filters show counts');
  check((await names()).length === 3 && (await names()).includes('Blista') && !(await names()).includes('T20'), 'filter narrows the list');
  await page.locator('.filter').nth(1).click();
  check(!(await names()).includes('Adder'), 'stored filter hides cars that are out');
  await page.locator('.filter').nth(0).click();
  await send({ action: 'view', session: 1, items: [] });
  check(await page.locator('.empty').innerText() === texts.no_vehicles, 'no vehicles of the type');
  await send({ action: 'view', session: 9, items });
  check(await page.locator('.empty').innerText() === texts.no_vehicles, 'a view of another session is ignored');

  // Slots and premium offers.
  check(await page.locator('#slots').isHidden(), 'no slot strip without slots');
  await send({ action: 'open', session: 1, label: 'Pillbox — Garaj', kind: 'Garaj', texts: { ...texts, slots_premium: 'Premium', slot_confirm: 'Confirmă plata' } });
  const slots = {
    meters: [{ label: 'Scoase', used: 3, limit: 3 }, { label: 'Locuri în garaj', used: 4, limit: 5 }],
    offers: [{ id: 'out', label: '+1 loc scos · 500 Tokens' }, { id: 'owned', label: '+1 loc în garaj · 300 Tokens' }],
  };
  await send({ action: 'view', session: 1, items, slots });
  check(await page.locator('#slots').isVisible(), 'the slot strip is shown');
  check((await page.locator('.meter em').allInnerTexts()).join() === '3/3,4/5', 'meters show used and limit');
  check(await page.locator('.meter.full').count() === 1, 'a full meter is marked');
  check(await fits('.offer span') && await fits('.meter'), 'offers and meters fit');
  const slotPosts = posts.filter((post) => post.name === 'slot').length;
  await page.locator('.offer').first().click();
  check((await page.locator('.offer').first().innerText()).includes('Confirmă plata'), 'the first click asks for confirmation');
  check(posts.filter((post) => post.name === 'slot').length === slotPosts, 'nothing is bought on the first click');
  await shot('slots-720');
  await page.locator('.offer').first().click();
  await page.waitForFunction(() => document.querySelector('.offer:not(:disabled)'));
  assert.deepEqual(last('slot').body, { session: 1, id: 'out' });
  checks += 1;
  check(!(await page.locator('.offer').first().innerText()).includes('Confirmă'), 'the confirmation is cleared after paying');
  await page.locator('.offer').nth(1).click();
  await page.locator('.row', { hasText: 'T20' }).click();
  check(!(await page.locator('.offer').nth(1).innerText()).includes('Confirmă'), 'selecting a car cancels a pending confirmation');

  // Keyboard.
  await open();
  check(await page.locator('#slots').isHidden(), 'a new panel starts without slots');
  await page.keyboard.press('ArrowDown');
  check(await selectedName() !== 'Adder', 'arrow down moves the selection');
  await page.keyboard.press('ArrowUp');
  check(await selectedName() === 'Adder', 'arrow up moves it back');
  await page.keyboard.press('ArrowUp');
  check(await selectedName() === 'Adder', 'selection stops at the top');
  await page.click('#search');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelector('.primary:not(:disabled)'));
  check(last('action').body.id === 'park', 'enter in search runs the main action');

  // A running action, then a refusal shown in the panel.
  let finish;
  release = new Promise((resolve) => { finish = resolve; });
  answer = { ok: false, message: 'Locul de scoatere este ocupat.' };
  await page.locator('.row', { hasText: 'T20' }).click();
  await page.locator('.primary').click();
  await page.waitForFunction(() => document.querySelector('.primary').disabled);
  const before = posts.length;
  await page.locator('.primary').click({ force: true });
  check(posts.length === before, 'a running action cannot be sent twice');
  finish();
  release = null;
  await page.waitForFunction(() => document.querySelector('#notice').hidden === false);
  check(await page.locator('#notice').innerText() === answer.message && !(await page.locator('#notice').evaluate((element) => element.classList.contains('success'))), 'a refusal is shown in the panel');
  await shot('refused-720');
  await page.locator('.row', { hasText: 'Sultan' }).click();
  check(await page.locator('#notice').isHidden(), 'choosing another car clears the notice');

  // Live accents, per the shared standard.
  for (const [name, accent] of [['dark', '#5b21b6'], ['bright', '#f6e05e']]) {
    await page.evaluate((value) => window.FeatherTheme.apply({ palette: { accent: value } }), accent);
    await page.waitForTimeout(250); // the button's colour transition
    const paint = await page.locator('.primary').evaluate((element) => {
      const style = getComputedStyle(element);
      return { background: style.backgroundColor, color: style.color };
    });
    const [r, g, b] = accent.slice(1).match(/../g).map((part) => parseInt(part, 16));
    check(paint.background === `rgb(${r}, ${g}, ${b})`, `${name} accent reaches the main button`);
    check(paint.color === (name === 'bright' ? 'rgb(6, 16, 31)' : 'rgb(255, 255, 255)'), `${name} accent keeps its label readable`);
    await shot(`accent-${name}`);
  }
  await page.evaluate(() => window.FeatherTheme.apply({}));

  // Other sizes.
  await page.setViewportSize({ width: 1920, height: 1080 });
  check(await fits('.panel'), 'fits 1080p');
  await shot('default-1080');
  await page.setViewportSize({ width: 480, height: 640 });
  const narrow = await page.locator('#app').boundingBox();
  check(narrow.x >= 16 && narrow.x + narrow.width <= 464, 'narrow layout keeps its gutters');
  check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'narrow layout has no horizontal scroll');
  await page.setViewportSize({ width: 1280, height: 720 });

  // Closing.
  posts.length = 0;
  await page.keyboard.press('Escape');
  check(last('close'), 'escape asks to close');
  await page.click('#close');
  check(posts.filter((post) => post.name === 'close').length === 2, 'the button asks to close');
  await send({ action: 'close' });
  check(await page.locator('#app').isHidden(), 'close hides the page');
  check(await page.evaluate(() => document.activeElement === document.body), 'focus is released');
  posts.length = 0;
  await page.keyboard.press('Escape');
  check(!last('close'), 'a closed page sends nothing');
  assert.deepEqual(errors, []);
  console.log(`browser_spec: ${checks} checks passed`);
} finally {
  await browser.close();
  server.close();
}

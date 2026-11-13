const test = require('node:test');
const assert = require('node:assert/strict');
const { mount, daysEndingToday, count, chart } = require('../dashboard.js');

function clientWith(handler) {
  const calls = [];
  return { calls, from(table) {
    const call = { table, filters: [] }; calls.push(call);
    const q = { select(columns, options) { call.columns = columns; call.options = options; return q; },
      eq(...args) { call.filters.push(['eq', ...args]); return q; },
      or(...args) { call.filters.push(['or', ...args]); return q; },
      gte(...args) { call.filters.push(['gte', ...args]); return q; },
      lt(...args) { call.filters.push(['lt', ...args]); return q; },
      then(resolve, reject) { return Promise.resolve().then(() => handler(call)).then(resolve, reject); } };
    return q;
  } };
}
function container() { return { isConnected: true, innerHTML: '', querySelector() { return { addEventListener: (name, fn) => { this.retry = fn; } }; } }; }
const now = () => new Date('2026-11-13T12:00:00Z');

test('uses exact head counts and proper per-day ranges, renders readable bars', async () => {
  const client = clientWith(call => ({ count: call.table === 'orders' ? 1201 : 8, error: null }));
  const el = container(); await mount({ container: el, client, now });
  assert.equal(client.calls.length, 16);
  assert.equal(client.calls.filter(c => c.filters.some(f => f[0] === 'eq' && f[2] === 'pending')).length, 1);
  assert.ok(client.calls.some(c => c.filters.some(f => f[0] === 'or' && f[1].includes('status.is.null'))));
  assert.ok(client.calls.every(c => c.columns === 'id' && c.options.count === 'exact' && c.options.head));
  assert.match(el.innerHTML, /1,201/); assert.match(el.innerHTML, /Orders by status/); assert.match(el.innerHTML, /aria-hidden="true"/);
  assert.doesNotMatch(el.innerHTML, /Delivered revenue/);
  const dates = client.calls.filter(c => c.filters.some(f => f[0] === 'gte'));
  assert.equal(dates.length, 7); assert.ok(dates.every(c => c.filters.some(f => f[0] === 'lt')));
});

test('empty counts are explicit and failures never become zeros', async () => {
  const el = container(); await mount({ container: el, client: clientWith(() => ({ count: 0, error: null })), now });
  assert.match(el.innerHTML, /No orders yet/); assert.match(el.innerHTML, /No orders were placed/);
  const err = container(); await mount({ container: err, client: clientWith(() => ({ count: null, error: { message: 'no access' } })), now });
  assert.match(err.innerHTML, /Unavailable/); assert.match(err.innerHTML, /could not be loaded/); assert.match(err.innerHTML, /Try again/); assert.doesNotMatch(err.innerHTML, /No orders yet/);
});

test('partial failures affect only their section and retry is wired', async () => {
  const client = clientWith(c => c.table === 'products' ? { error: {} } : { count: 2 });
  const el = container(); await mount({ container: el, client, now });
  assert.match(el.innerHTML, /Products<\/p><strong>Unavailable/); assert.match(el.innerHTML, /chart-list/); assert.equal(typeof el.retry, 'function');
});

test('retry actually reloads and replaces an error with real results', async () => {
  let failed = true;
  const client = clientWith(() => failed ? {error:{message:'offline'}} : {count:3});
  const el = container(); await mount({ container: el, client, now });
  assert.match(el.innerHTML, /Try again/);
  failed = false; await el.retry();
  assert.equal(client.calls.length, 32);
  assert.doesNotMatch(el.innerHTML, /Unavailable|Try again/);
  assert.match(el.innerHTML, /<strong>3<\/strong>/);
});

test('navigation and sign-out prevent a late response rendering', async () => {
  const el = container(); await mount({ container: el, client: clientWith(() => ({ count: 2 })), now, isActive: () => false });
  assert.match(el.innerHTML, /Loading/); assert.doesNotMatch(el.innerHTML, /business at a glance/);
  el.isConnected = false; await mount({ container: el, client: clientWith(() => ({ count: 2 })), now }); assert.match(el.innerHTML, /Loading/);
});

test('count rejects null, errors and thrown exceptions', async () => {
  for (const handler of [() => ({ count: null }), () => ({ count: 0, error: {} }), () => { throw Error('network'); }]) await assert.rejects(count(clientWith(handler), 'orders'));
});

test('days use consecutive local midnights in DST and non-DST timezones', () => {
  const { spawnSync } = require('node:child_process');
  for (const [tz, month, day, expectedHours] of [
    ['America/New_York', 2, 11, 23],
    ['America/New_York', 10, 4, 25],
    ['Africa/Kampala', 2, 11, 24],
  ]) {
    const script = `const { daysEndingToday } = require(${JSON.stringify(require.resolve('../dashboard.js'))});
      console.log(JSON.stringify(daysEndingToday(new Date(2026, ${month}, ${day}, 12))));`;
    const child = spawnSync(process.execPath, ['-e', script], { env: { ...process.env, TZ: tz }, encoding: 'utf8' });
    assert.equal(child.status, 0, child.stderr);
    const days = JSON.parse(child.stdout);
    assert.equal(days.length, 7);
    for (let i = 0; i < 6; i++) assert.equal(days[i].end, days[i + 1].start);
    assert.ok(days.some(d => new Date(d.end) - new Date(d.start) === expectedHours * 3600000), `${tz}: expected a ${expectedHours}-hour day`);
  }
});

test('chart escapes labels and marks visual bars decorative', () => {
  const html = chart([{ label: '<script>', value: 3 }, { label: 'Zero', value: 0 }]);
  assert.match(html, /&lt;script&gt;/); assert.doesNotMatch(html, /<script>/); assert.match(html, /width:0.00%/); assert.match(html, /aria-hidden/);
});

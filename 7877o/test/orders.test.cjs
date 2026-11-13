const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync(require.resolve('../app_part3.js'), 'utf8');
function setup(rows, result = {data: {id: 'abc123', status: 'confirmed'}, error: null}) {
  const calls = [], alerts = [], refreshed = [], select = {dataset: {o:'abc123'}, value:'confirmed', disabled:false};
  const sb = {from(table) {
    calls.push(['from', table]);
    return { select(columns) { calls.push(['select', columns]); return {order: async () => ({data:rows, error:null})}; },
      update(changes) { calls.push(['update', changes]); return {eq(field, id) {calls.push(['eq', field, id]); return {select(columns) { calls.push(['update-select',columns]); return {maybeSingle: async () => result}; }};}}; }
    };
  }};
  const context = {sb, STATUSES: ['pending','confirmed','processing','delivered','cancelled'],
    esc: s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])),
    ugx: n => 'UGX ' + Number(n || 0).toLocaleString('en-US'),
    countPending: async () => refreshed.push('count'), page:'orders', go: (...a) => refreshed.push(a.join(':')), alert: msg => alerts.push(msg)};
  vm.createContext(context); vm.runInContext(source, context);
  const view = {innerHTML:'', textContent:'', querySelectorAll: () => [select]};
  return {context, calls, alerts, refreshed, view, select};
}
const base = {id:'abc123-456', customer_name:'Jane', total:100000, items:[{qty:1,name:'Bag'}], created_at:'2026-11-01T08:00:00Z', status:'pending'};

test('legacy schema: wildcard query and working status update with no delivery fields', async () => {
  const x = setup([base]); x.select.dataset.o=base.id;
  await x.context.orders(x.view);
  assert.equal(x.calls[1][1], '*');
  assert.doesNotMatch(x.view.innerHTML, /Delivery fee|Preferred delivery|Grand total/);
  assert.match(x.view.innerHTML, /aria-label="Order status/);
  await x.select.onchange();
  assert.equal(JSON.stringify(x.calls.find(c => c[0] === 'update')[1]), JSON.stringify({status:'confirmed'}));
  assert.deepEqual(x.calls.find(c => c[0] === 'eq'), ['eq','id',base.id]);
  assert.deepEqual(x.refreshed, ['count','orders:true']);
});

test('migration data shows preference and accepted fee and total, not unaccepted totals', async () => {
  const x = setup([]), detail = x.context.orderDeliveryDetails;
  const html = detail({...base, preferred_delivery_date:'2026-12-01', delivery_fee_status:'accepted', delivery_fee:10000});
  assert.match(html, /2026-12-01 \(not confirmed\)/); assert.match(html, /Accepted by customer/);
  assert.match(html, /Accepted delivery fee: UGX 10,000/); assert.match(html, /Grand total \(items \+ accepted delivery\): UGX 110,000/);
  for (const state of ['offered','declined','awaiting_quote']) assert.doesNotMatch(detail({...base, delivery_fee_status:state, delivery_fee: 10000}), /Grand total|Accepted delivery fee/);
  assert.match(detail({...base, delivery_fee_status:'accepted', delivery_fee:null}), /Accepted delivery fee: Unavailable.*Grand total.*Unavailable/);
  assert.match(detail({...base, delivery_fee_status:'accepted', delivery_fee:0}), /UGX 0/);
  assert.match(detail({preferred_delivery_date:null}), /Not specified/);
  assert.match(detail({preferred_delivery_date:'<img src=x>'}), /&lt;img/);
  assert.match(detail({delivery_fee_status:'<script>'}), /Unknown/);
});

test('failed or missing update restores status and reports error', async () => {
  for (const result of [{data:null,error:{message:'denied'}},{data:null,error:null}]) {
    const x = setup([base],result); x.select.dataset.o=base.id; await x.context.orders(x.view); await x.select.onchange();
    assert.equal(x.select.value,'pending'); assert.equal(x.select.disabled,false); assert.match(x.alerts[0],/Could not update order/); assert.deepEqual(x.refreshed,[]);
  }
});

test('customer controlled order item quantity and name are escaped', async () => {
  const x = setup([{...base, items:[{qty:'<img>',name:'<script>'}]}]); await x.context.orders(x.view);
  assert.doesNotMatch(x.view.innerHTML, /<img>|<script>/); assert.match(x.view.innerHTML, /&lt;img&gt;/);
});

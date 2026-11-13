// select('*') deliberately supports installations that have not applied delivery migrations.
function orderDeliveryDetails(o) {
  const has = key => Object.prototype.hasOwnProperty.call(o, key);
  let html = '';
  if (has('preferred_delivery_date')) {
    html += `<div class="small">Preferred delivery date: ${o.preferred_delivery_date ? esc(o.preferred_delivery_date) + ' (not confirmed)' : 'Not specified'}</div>`;
  }
  if (!has('delivery_fee_status')) return html;
  const states = { awaiting_quote: 'Awaiting quote', offered: 'Offered — awaiting customer response', accepted: 'Accepted by customer', declined: 'Declined by customer' };
  const state = Object.prototype.hasOwnProperty.call(states, o.delivery_fee_status) ? states[o.delivery_fee_status] : 'Unknown';
  html += `<div class="small">Delivery fee status: ${state}</div>`;
  if (o.delivery_fee_status === 'accepted') {
    const amount = x => x !== null && x !== undefined && x !== '' && Number.isSafeInteger(Number(x)) && Number(x) >= 0 ? Number(x) : null;
    const fee = amount(o.delivery_fee), subtotal = amount(o.total);
    const total = fee !== null && subtotal !== null && Number.isSafeInteger(fee + subtotal) ? fee + subtotal : null;
    html += `<div class="small">Accepted delivery fee: ${fee === null ? 'Unavailable' : ugx(fee)} · Grand total (items + accepted delivery): ${total === null ? 'Unavailable' : ugx(total)}</div>`;
  }
  return html;
}

async function orders(v) {
  const { data, error } = await sb.from('orders').select('*').order('created_at', { ascending: false });
  if (error) { v.textContent = 'Could not load orders: ' + error.message; return; }
  if (!data?.length) { v.innerHTML = '<p class="muted">No orders yet.</p>'; return; }
  v.innerHTML = `<div class="list">${data.map(o => `
    <div class="card">
      <div class="row"><b class="grow">#${esc(String(o.id).slice(0, 6).toUpperCase())} · ${esc(o.customer_name)}</b><span class="gold">${Object.prototype.hasOwnProperty.call(o, 'delivery_fee_status') ? 'Item subtotal: ' : ''}${ugx(o.total)}</span></div>
      <div class="small" style="margin:6px 0">${(o.items || []).map(i => `${esc(i.qty)} x ${esc(i.name)}`).join(', ')}</div>
      <div class="small">Phone: ${esc(o.phone)} · ${esc(o.address)} · ${esc(o.payment_method)}${o.note ? ' · Note: ' + esc(o.note) : ''}</div>
      <div class="small">${new Date(o.created_at).toLocaleString()}</div>
      ${orderDeliveryDetails(o)}
      <select aria-label="Order status for ${esc(String(o.id).slice(0, 6))}" data-o="${esc(o.id)}" style="margin-top:8px;max-width:200px">${STATUSES.includes(o.status) ? '' : `<option value="" selected disabled>Unknown status</option>`}${STATUSES.map(s => `<option ${s === o.status ? 'selected' : ''}>${s}</option>`).join('')}</select>
    </div>`).join('')}</div>`;
  v.querySelectorAll('[data-o]').forEach(s => s.onchange = async () => {
    const previous = data.find(o => String(o.id) === s.dataset.o)?.status;
    s.disabled = true;
    const { data: updated, error } = await sb.from('orders').update({ status: s.value }).eq('id', s.dataset.o).select('id,status').maybeSingle();
    s.disabled = false;
    if (error || !updated) { s.value = previous; alert('Could not update order: ' + (error?.message || 'No order was updated.')); }
    else { await countPending(); if (page === 'orders') go('orders', true); }
  });
}

/* ---------- messages ---------- */
let names = {};
async function messages(v) {
  const { data: profs } = await sb.from('profiles').select('id,full_name');
  if (page !== 'messages' || !v.isConnected) return;
  names = Object.fromEntries((profs || []).map(p => [p.id, p.full_name || 'Customer']));
  v.innerHTML = `<div class="msgs"><div class="threads" id="threads"></div>
    <div class="card chat"><div class="bubbles" id="bubbles"><p class="muted">Select a conversation.</p></div>
    <div class="composer" id="composer" hidden><input id="msgIn" placeholder="Type a reply"><button class="btn" id="send">Send</button></div></div></div>`;
  $('#send').onclick = send;
  $('#msgIn').addEventListener('keydown', e => { if (e.key === 'Enter') send(); });
  refreshChat();
}

async function refreshChat() {
  if (!$('#threads')) return;
  const { data } = await sb.from('messages').select('*').order('created_at', { ascending: true });
  if (page !== 'messages' || !$('#threads')) return;
  const by = {};
  (data || []).forEach(m => (by[m.customer_id] ||= []).push(m));
  const ids = Object.keys(by).sort((a, b) => by[b].at(-1).created_at.localeCompare(by[a].at(-1).created_at));
  $('#threads').innerHTML = ids.length ? ids.map(id => `<div class="th ${id === chatWith ? 'on' : ''}" data-c="${esc(id)}"><b>${esc(names[id] || 'Customer')}</b><div class="small">${esc(by[id].at(-1).body.slice(0, 40))}</div></div>`).join('') : '<p class="muted">No conversations yet.</p>';
  $('#threads').querySelectorAll('[data-c]').forEach(t => t.onclick = () => { chatWith = t.dataset.c; refreshChat(); });
  if (chatWith) {
    $('#composer').hidden = false;
    const b = $('#bubbles');
    b.innerHTML = (by[chatWith] || []).map(m => `<div class="b ${m.is_admin ? 'me' : ''}">${esc(m.body)}</div>`).join('');
    b.scrollTop = b.scrollHeight;
  }
}

async function send() {
  const t = $('#msgIn').value.trim();
  if (!t || !chatWith) return;
  const input = $('#msgIn');
  const recipient = chatWith;
  const { error } = await sb.from('messages').insert({ customer_id: recipient, sender_id: me.id, is_admin: true, body: t });
  if (error) { alert('Message was not sent: ' + error.message); return; }
  if (input.isConnected && input.value.trim() === t && chatWith === recipient) input.value = '';
}

/* ---------- feedback ---------- */
async function feedback(v) {
  const [f, p] = await Promise.all([sb.from('feedback').select('*').order('created_at', { ascending: false }), sb.from('projects').select('id,title')]);
  const titles = Object.fromEntries((p.data || []).map(x => [x.id, x.title]));
  if (f.error) { v.textContent = 'Could not load feedback: ' + f.error.message; return; }
  if (!f.data?.length) { v.innerHTML = '<p class="muted">No feedback yet.</p>'; return; }
  v.innerHTML = `<div class="list">${f.data.map(x => `
    <div class="card row"><div class="grow"><b>${esc(titles[x.project_id] || 'Project')}</b> <span class="gold">${'\u2605'.repeat(x.rating || 0)}</span>
    <div class="small">${esc(x.customer_name)}: ${esc(x.comment)}</div></div>
    <button class="btn ghost" data-f="${esc(x.id)}">Delete</button></div>`).join('')}</div>`;
  v.querySelectorAll('[data-f]').forEach(b => b.onclick = async () => {
    if (!confirm('Delete this feedback?')) return;
    const { data, error } = await sb.from('feedback').delete().eq('id', b.dataset.f).select('id').maybeSingle();
    if (error || !data) alert('Could not delete feedback: ' + (error?.message || 'No feedback was deleted.'));
    else go('feedback', true);
  });
}

/* ---------- customers ---------- */
function waLink(phone) {
  let d = String(phone || '').replace(/\D/g, '');
  if (d.startsWith('0')) d = '256' + d.slice(1);
  return d ? 'https://wa.me/' + d : '';
}

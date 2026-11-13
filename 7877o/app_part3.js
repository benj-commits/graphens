async function orders(v) {
  const { data, error } = await sb.from('orders').select('*').order('created_at', { ascending: false });
  if (error) { v.textContent = 'Could not load orders: ' + error.message; return; }
  if (!data?.length) { v.innerHTML = '<p class="muted">No orders yet.</p>'; return; }
  v.innerHTML = `<div class="list">${data.map(o => `
    <div class="card">
      <div class="row"><b class="grow">#${o.id.slice(0, 6).toUpperCase()} · ${esc(o.customer_name)}</b><span class="gold">${ugx(o.total)}</span></div>
      <div class="small" style="margin:6px 0">${(o.items || []).map(i => `${i.qty} x ${esc(i.name)}`).join(', ')}</div>
      <div class="small">Phone: ${esc(o.phone)} · ${esc(o.address)} · ${esc(o.payment_method)}${o.note ? ' · Note: ' + esc(o.note) : ''}</div>
      <div class="small">${new Date(o.created_at).toLocaleString()}</div>
      <select data-o="${o.id}" style="margin-top:8px;max-width:200px">${STATUSES.map(s => `<option ${s === o.status ? 'selected' : ''}>${s}</option>`).join('')}</select>
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
  $('#threads').innerHTML = ids.length ? ids.map(id => `<div class="th ${id === chatWith ? 'on' : ''}" data-c="${id}"><b>${esc(names[id] || 'Customer')}</b><div class="small">${esc(by[id].at(-1).body.slice(0, 40))}</div></div>`).join('') : '<p class="muted">No conversations yet.</p>';
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
  $('#msgIn').value = '';
  await sb.from('messages').insert({ customer_id: chatWith, sender_id: me.id, is_admin: true, body: t });
}

/* ---------- feedback ---------- */
async function feedback(v) {
  const [f, p] = await Promise.all([sb.from('feedback').select('*').order('created_at', { ascending: false }), sb.from('projects').select('id,title')]);
  const titles = Object.fromEntries((p.data || []).map(x => [x.id, x.title]));
  if (!f.data?.length) { v.innerHTML = '<p class="muted">No feedback yet.</p>'; return; }
  v.innerHTML = `<div class="list">${f.data.map(x => `
    <div class="card row"><div class="grow"><b>${esc(titles[x.project_id] || 'Project')}</b> <span class="gold">${'\u2605'.repeat(x.rating || 0)}</span>
    <div class="small">${esc(x.customer_name)}: ${esc(x.comment)}</div></div>
    <button class="btn ghost" data-f="${x.id}">Delete</button></div>`).join('')}</div>`;
  v.querySelectorAll('[data-f]').forEach(b => b.onclick = async () => { await sb.from('feedback').delete().eq('id', b.dataset.f); go('feedback', true); });
}

/* ---------- customers ---------- */
function waLink(phone) {
  let d = String(phone || '').replace(/\D/g, '');
  if (d.startsWith('0')) d = '256' + d.slice(1);
  return d ? 'https://wa.me/' + d : '';
}

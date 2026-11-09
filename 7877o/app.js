const sb = supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE);
const $ = s => document.querySelector(s);
const ugx = n => 'UGX ' + Number(n || 0).toLocaleString();
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const STATUSES = ['pending', 'confirmed', 'processing', 'delivered', 'cancelled'];
const CATS = ['Lady Bags', 'Handbags', 'Cases', 'Wallets & More', 'Other'];

const CRUD = {
  products: { title: 'Products', one: 'product', name: 'name', price: 'price', fields: [
    ['name', 'Name', 'text'], ['category', 'Category', 'select', CATS], ['price', 'Price (UGX)', 'number'],
    ['stock', 'Stock quantity', 'number'], ['description', 'Description', 'textarea'], ['active', 'Visible in app', 'bool']] },
  projects: { title: 'Projects', one: 'project', name: 'title', price: 'price_from', fields: [
    ['title', 'Project title', 'text'], ['category', 'Category', 'text'], ['price_from', 'Price from (UGX)', 'number'],
    ['status', 'Status', 'select', ['Open', 'In progress', 'Completed']], ['description', 'Description', 'textarea'], ['active', 'Visible in app', 'bool']] },
};
const PAGES = ['dashboard', 'products', 'projects', 'orders', 'messages', 'customers', 'feedback', 'activity', 'settings'];
const LABEL = { dashboard: 'Dashboard', products: 'Products', projects: 'Projects', orders: 'Orders', messages: 'Messages', customers: 'Customers', feedback: 'Feedback', activity: 'Activity', settings: 'Settings' };

let recovering = location.hash.includes('type=recovery');
let me = null, page = 'dashboard', chatWith = null, pendingOrders = 0;

/* ---------- auth ---------- */
const FORMS = ['loginForm', 'mfaForm', 'newPassForm'];
const showForm = id => FORMS.forEach(f => $('#' + f).hidden = f !== id);

sb.auth.onAuthStateChange(ev => {
  if (ev === 'PASSWORD_RECOVERY') { recovering = true; $('#app').hidden = true; $('#login').hidden = false; showForm('newPassForm'); }
});

$('#loginForm').addEventListener('submit', async e => {
  e.preventDefault();
  $('#loginErr').textContent = '';
  const { error } = await sb.auth.signInWithPassword({ email: $('#email').value.trim(), password: $('#pass').value });
  if (error) $('#loginErr').textContent = 'Wrong email or password.';
  else boot();
});

$('#forgot').onclick = async () => {
  const email = $('#email').value.trim();
  if (!email) { $('#loginErr').textContent = 'Enter your email first.'; return; }
  await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname });
  $('#loginErr').textContent = 'If that email belongs to an admin, a reset link is on its way.';
};

$('#newPassForm').addEventListener('submit', async e => {
  e.preventDefault();
  const { error } = await sb.auth.updateUser({ password: $('#np').value });
  if (error) $('#npErr').textContent = error.message;
  else { await sb.auth.signOut(); location.href = location.pathname; }
});

$('#mfaForm').addEventListener('submit', async e => {
  e.preventDefault();
  const { data: f } = await sb.auth.mfa.listFactors();
  const { error } = await sb.auth.mfa.challengeAndVerify({ factorId: f.totp[0].id, code: $('#mfaCode').value.trim() });
  if (error) $('#mfaErr').textContent = 'That code did not work. Try again.';
  else boot();
});

$('#logout').onclick = async () => { await sb.auth.signOut(); location.reload(); };

let idleTimer;
function resetIdle() { clearTimeout(idleTimer); idleTimer = setTimeout(async () => { await sb.auth.signOut(); location.reload(); }, 30 * 60 * 1000); }
['click', 'keydown', 'mousemove', 'touchstart'].forEach(ev => document.addEventListener(ev, () => { if (me) resetIdle(); }));

async function boot() {
  if (recovering) return;
  const { data: { session } } = await sb.auth.getSession();
  if (!session) { showForm('loginForm'); return; }
  const { data: aal } = await sb.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aal.nextLevel === 'aal2' && aal.currentLevel !== 'aal2') { $('#login').hidden = false; showForm('mfaForm'); return; }
  const { data: prof } = await sb.from('profiles').select('role').eq('id', session.user.id).maybeSingle();
  if (prof?.role !== 'admin') {
    await sb.auth.signOut();
    showForm('loginForm');
    $('#loginErr').textContent = 'This account is not an admin.';
    return;
  }
  me = session.user;
  resetIdle();
  $('#login').hidden = true;
  $('#app').hidden = false;
  buildNav();
  go('dashboard');
  sb.channel('live').on('postgres_changes', { event: '*', schema: 'public' }, onChange).subscribe();
}

function buildNav() {
  $('#nav').innerHTML = PAGES.map(p => `<button data-p="${p}">${LABEL[p]}${p === 'orders' && pendingOrders ? `<span class="dot">${pendingOrders}</span>` : ''}</button>`).join('');
  $('#nav').querySelectorAll('button').forEach(b => { b.onclick = () => go(b.dataset.p); b.classList.toggle('on', b.dataset.p === page); });
}

async function countPending() {
  const { count } = await sb.from('orders').select('id', { count: 'exact', head: true }).eq('status', 'pending');
  pendingOrders = count || 0;
  buildNav();
}

function onChange(p) {
  if (p.table === 'orders') countPending();
  if (p.table === 'messages' && page === 'messages') return refreshChat();
  const map = { products: 'products', projects: 'projects', orders: 'orders', feedback: 'feedback' };
  if (map[p.table] === page || (page === 'dashboard')) go(page, true);
}

async function go(p, silent) {
  page = p;
  chatWith = p === 'messages' ? chatWith : null;
  buildNav();
  if (!silent) countPending();
  $('#title').textContent = LABEL[p];
  $('#actions').innerHTML = '';
  const v = $('#view');
  if (p === 'dashboard') return dashboard(v);
  if (CRUD[p]) return crud(v, p);
  if (p === 'orders') return orders(v);
  if (p === 'messages') return messages(v);
  if (p === 'customers') return customers(v);
  if (p === 'feedback') return feedback(v);
  if (p === 'activity') return activity(v);
  if (p === 'settings') return settings(v);
}

/* ---------- dashboard ---------- */
async function dashboard(v) {
  const [o, pr, pj, fb] = await Promise.all([
    sb.from('orders').select('status,total'), sb.from('products').select('id'), sb.from('projects').select('id'), sb.from('feedback').select('rating')]);
  const orders = o.data || [];
  const rev = orders.filter(x => x.status === 'delivered').reduce((s, x) => s + Number(x.total), 0);
  const avg = fb.data?.length ? (fb.data.reduce((s, x) => s + x.rating, 0) / fb.data.length).toFixed(1) : '-';
  const m = [['Pending orders', orders.filter(x => x.status === 'pending').length], ['All orders', orders.length],
    ['Delivered revenue', ugx(rev)], ['Products', pr.data?.length || 0], ['Projects', pj.data?.length || 0], ['Average rating', avg]];
  v.innerHTML = `<div class="grid">${m.map(x => `<div class="card metric"><small>${x[0]}</small><b>${x[1]}</b></div>`).join('')}</div>`;
}

/* ---------- products + projects ---------- */
async function crud(v, t) {
  const c = CRUD[t];
  $('#actions').innerHTML = `<button class="btn gold" id="add">+ Add ${c.one}</button>`;
  $('#add').onclick = () => editor(t, null);
  const { data } = await sb.from(t).select('*').order('created_at', { ascending: false });
  if (!data?.length) { v.innerHTML = `<p class="muted">No ${c.one}s yet. Click "Add ${c.one}".</p>`; return; }
  v.innerHTML = `<div class="list">${data.map(r => `
    <div class="card row">
      <img class="thumb" src="${esc(r.images?.[0] || '')}" alt="">
      <div class="grow"><b>${esc(r[c.name])}</b><br><span class="gold">${ugx(r[c.price])}</span>
        ${r.stock !== undefined ? `<span class="small"> · stock ${r.stock}</span>` : ''}
        <span class="tag ${r.active ? '' : 'off'}">${r.active ? 'Visible' : 'Hidden'}</span></div>
      <button class="btn ghost" data-e="${r.id}">Edit</button>
      <button class="btn ghost" data-d="${r.id}">Delete</button>
    </div>`).join('')}</div>`;
  v.querySelectorAll('[data-e]').forEach(b => b.onclick = () => editor(t, data.find(r => r.id === b.dataset.e)));
  v.querySelectorAll('[data-d]').forEach(b => b.onclick = async () => {
    if (confirm(`Delete this ${c.one}?`)) { await sb.from(t).delete().eq('id', b.dataset.d); go(t, true); }
  });
}

function editor(t, row) {
  const c = CRUD[t];
  let keep = [...(row?.images || [])];
  const f = $('#dlgForm');
  const fieldHtml = c.fields.map(([k, l, type, opts]) => {
    const val = row?.[k];
    if (type === 'bool') return `<label><span><input type="checkbox" name="${k}" style="width:auto" ${(val ?? true) ? 'checked' : ''}> ${l}</span></label>`;
    if (type === 'select') return `<label>${l}<select name="${k}">${opts.map(o => `<option ${o === val ? 'selected' : ''}>${esc(o)}</option>`).join('')}</select></label>`;
    if (type === 'textarea') return `<label>${l}<textarea name="${k}">${esc(val)}</textarea></label>`;
    return `<label>${l}<input name="${k}" type="${type}" value="${esc(val)}"></label>`;
  }).join('');
  f.innerHTML = `<h3 style="margin:0">${row ? 'Edit' : 'New'} ${c.one}</h3>
    <div class="imgs" id="imgs"></div>
    <label>Photos<input type="file" id="files" accept="image/*" multiple></label>
    ${fieldHtml}
    <p class="err" id="eErr"></p>
    <div class="row" style="justify-content:flex-end"><button type="button" class="btn ghost" id="cancel">Cancel</button><button type="button" class="btn" id="save">Save</button></div>`;
  const drawImgs = () => {
    $('#imgs').innerHTML = keep.map((u, i) => `<div class="im"><img src="${esc(u)}" alt=""><button type="button" class="x" data-i="${i}">x</button></div>`).join('');
    $('#imgs').querySelectorAll('.x').forEach(b => b.onclick = () => { keep.splice(+b.dataset.i, 1); drawImgs(); });
  };
  drawImgs();
  $('#cancel').onclick = () => $('#dlg').close();
  $('#save').onclick = async () => {
    const btn = $('#save'); btn.disabled = true; btn.textContent = 'Saving...';
    try {
      const data = { images: keep };
      c.fields.forEach(([k, , type]) => {
        const el = f.elements[k];
        data[k] = type === 'bool' ? el.checked : type === 'number' ? Number(el.value) || 0 : el.value.trim();
      });
      for (const file of $('#files').files) {
        const path = `${Date.now()}_${file.name.replace(/\s+/g, '_')}`;
        const { error } = await sb.storage.from('media').upload(path, file, { contentType: file.type });
        if (error) throw error;
        data.images.push(sb.storage.from('media').getPublicUrl(path).data.publicUrl);
      }
      const { error } = row ? await sb.from(t).update(data).eq('id', row.id) : await sb.from(t).insert(data);
      if (error) throw error;
      $('#dlg').close();
      go(t, true);
    } catch (e) {
      $('#eErr').textContent = e.message || String(e);
      btn.disabled = false; btn.textContent = 'Save';
    }
  };
  $('#dlg').showModal();
}

/* ---------- orders ---------- */
async function orders(v) {
  const { data } = await sb.from('orders').select('*').order('created_at', { ascending: false });
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
    await sb.from('orders').update({ status: s.value }).eq('id', s.dataset.o);
    countPending();
  });
}

/* ---------- messages ---------- */
let names = {};
async function messages(v) {
  const { data: profs } = await sb.from('profiles').select('id,full_name');
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
async function customers(v) {
  const [p, o] = await Promise.all([
    sb.from('profiles').select('*').eq('role', 'customer').order('created_at', { ascending: false }),
    sb.from('orders').select('user_id,total')]);
  const stats = {};
  (o.data || []).forEach(x => { const s = stats[x.user_id] || (stats[x.user_id] = { n: 0, t: 0 }); s.n++; s.t += Number(x.total); });
  if (!p.data?.length) { v.innerHTML = '<p class="muted">No customers yet. They appear when someone registers in the app.</p>'; return; }
  v.innerHTML = `<div class="list">${p.data.map(c => `<div class="card row">
    <div class="grow"><b>${esc(c.full_name || 'Customer')}</b><div class="small">${esc(c.phone || 'no phone')} · ${stats[c.id]?.n || 0} orders · ${ugx(stats[c.id]?.t || 0)}</div></div>
    <button class="btn ghost" data-m="${c.id}">Message</button>
    ${waLink(c.phone) ? `<a class="btn ghost" style="text-decoration:none" target="_blank" rel="noopener" href="${waLink(c.phone)}">WhatsApp</a>` : ''}</div>`).join('')}</div>`;
  v.querySelectorAll('[data-m]').forEach(b => b.onclick = () => { chatWith = b.dataset.m; go('messages'); });
}

/* ---------- activity log ---------- */
async function activity(v) {
  const [l, p] = await Promise.all([sb.from('audit_log').select('*').order('created_at', { ascending: false }).limit(100), sb.from('profiles').select('id,full_name')]);
  const who = Object.fromEntries((p.data || []).map(x => [x.id, x.full_name || 'Admin']));
  if (!l.data?.length) { v.innerHTML = '<p class="muted">No activity yet.</p>'; return; }
  const verb = { INSERT: 'added', UPDATE: 'changed', DELETE: 'deleted' };
  v.innerHTML = `<div class="list">${l.data.map(x => `<div class="card"><b>${esc(who[x.user_id] || 'Admin')}</b> ${verb[x.action] || x.action} ${esc(x.table_name.replace(/s$/, ''))} <b>${esc(x.label || '')}</b><div class="small">${new Date(x.created_at).toLocaleString()}</div></div>`).join('')}</div>`;
}

/* ---------- settings: 2FA + password ---------- */
async function settings(v) {
  const { data: f } = await sb.auth.mfa.listFactors();
  const on = f.totp.length > 0;
  v.innerHTML = `<div class="list" style="max-width:480px">
    <div class="card"><b>Two-factor authentication</b>
      <p class="small">${on ? 'On. A code from your authenticator app is needed at every sign-in.' : 'Off. Turn it on so a stolen password is not enough to get in.'}</p>
      <div id="mfaBox">${on ? '<button class="btn ghost" id="mfaOff">Turn off</button>' : '<button class="btn gold" id="mfaOn">Set up with an authenticator app</button>'}</div></div>
    <div class="card"><b>Change password</b>
      <div style="display:grid;gap:8px;margin-top:8px"><input id="pw1" type="password" placeholder="New password (10+ characters)"><button class="btn" id="pwSave">Update password</button><p class="small" id="pwMsg"></p></div></div></div>`;
  $('#pwSave').onclick = async () => {
    const pw = $('#pw1').value;
    if (pw.length < 10) { $('#pwMsg').textContent = 'Use at least 10 characters.'; return; }
    const { error } = await sb.auth.updateUser({ password: pw });
    $('#pwMsg').textContent = error ? error.message : 'Password updated.';
    if (!error) $('#pw1').value = '';
  };
  if (on) $('#mfaOff').onclick = async () => {
    if (!confirm('Turn off two-factor authentication?')) return;
    const { error } = await sb.auth.mfa.unenroll({ factorId: f.totp[0].id });
    if (error) alert(error.message); else { await sb.auth.refreshSession(); settings(v); }
  };
  else $('#mfaOn').onclick = async () => {
    const { data: all } = await sb.auth.mfa.listFactors();
    for (const x of (all.all || []).filter(x => x.status === 'unverified')) await sb.auth.mfa.unenroll({ factorId: x.id });
    const { data, error } = await sb.auth.mfa.enroll({ factorType: 'totp', friendlyName: 'Graphen admin ' + Date.now() });
    if (error) { alert(error.message); return; }
    $('#mfaBox').innerHTML = `<p class="small">Scan with Google Authenticator, Microsoft Authenticator or Authy.</p>
      <img src="${data.totp.qr_code}" width="180" alt="QR code">
      <p class="small">Or type this key: <code>${esc(data.totp.secret)}</code></p>
      <input id="mfaVer" inputmode="numeric" maxlength="6" placeholder="6-digit code">
      <button class="btn" id="mfaGo" style="margin-top:8px">Turn on</button><p class="err" id="mfaE"></p>`;
    $('#mfaGo').onclick = async () => {
      const { error } = await sb.auth.mfa.challengeAndVerify({ factorId: data.id, code: $('#mfaVer').value.trim() });
      if (error) $('#mfaE').textContent = 'Wrong code. Try again.';
      else { await sb.auth.refreshSession(); settings(v); }
    };
  };
}

boot();

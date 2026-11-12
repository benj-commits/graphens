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
  vouchers: { title: 'Vouchers', one: 'voucher', name: 'code', price: 'value', fields: [
    ['code', 'Code', 'text'], ['value', 'Voucher value (UGX)', 'number'], ['expiry_date', 'Expiry date', 'date'], ['usage_limit', 'Usage limit', 'number'], ['active', 'Active', 'bool']] },
};
const PAGES = ['dashboard', 'products', 'projects', 'orders', 'deliveryFees', 'vouchers', 'messages', 'customers', 'feedback', 'activity', 'settings'];
const LABEL = { dashboard: 'Dashboard', products: 'Products', projects: 'Projects', orders: 'Orders', deliveryFees: 'Delivery fees', vouchers: 'Vouchers', messages: 'Messages', customers: 'Customers', feedback: 'Feedback', activity: 'Activity', settings: 'Settings' };

let recovering = location.hash.includes('type=recovery');
let me = null, page = 'dashboard', chatWith = null, pendingOrders = 0, idleTimer, authEpoch = 0, liveChannel = null;

/* ---------- auth ---------- */
const FORMS = ['loginForm', 'mfaForm', 'newPassForm'];
const showForm = id => FORMS.forEach(f => $('#' + f).hidden = f !== id);

sb.auth.onAuthStateChange(ev => {
  if (ev === 'PASSWORD_RECOVERY') { recovering = true; $('#app').hidden = true; $('#login').hidden = false; showForm('newPassForm'); }
  if (ev === 'SIGNED_OUT') { authEpoch++; me = null; if (liveChannel) { sb.removeChannel(liveChannel); liveChannel = null; } clearTimeout(idleTimer); $('#app').hidden = true; $('#login').hidden = false; showForm('loginForm'); }
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
  const { data: f, error: factorError } = await sb.auth.mfa.listFactors();
  const factor = f?.totp?.find(x => x.status === 'verified');
  if (factorError || !factor) { $('#mfaErr').textContent = 'Unable to load your authenticator. Try again.'; return; }
  const { error } = await sb.auth.mfa.challengeAndVerify({ factorId: factor.id, code: $('#mfaCode').value.trim() });
  if (error) $('#mfaErr').textContent = 'That code did not work. Try again.';
  else boot();
});

$('#logout').onclick = async () => { await sb.auth.signOut(); location.reload(); };

function resetIdle() { clearTimeout(idleTimer); idleTimer = setTimeout(async () => { await sb.auth.signOut(); location.reload(); }, 30 * 60 * 1000); }
['click', 'keydown', 'mousemove', 'touchstart'].forEach(ev => document.addEventListener(ev, () => { if (me) resetIdle(); }));

async function boot() {
  if (recovering || me) return;
  const bootEpoch = authEpoch;
  const { data: { session } } = await sb.auth.getSession();
  if (!session) { showForm('loginForm'); return; }
  const { data: aal, error: aalError } = await sb.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aalError || !aal) { $('#loginErr').textContent = 'Unable to verify sign-in security. Please try again.'; showForm('loginForm'); return; }
  if (aal.nextLevel === 'aal2' && aal.currentLevel !== 'aal2') { $('#login').hidden = false; showForm('mfaForm'); return; }
  const { data: verified, error: userError } = await sb.auth.getUser();
  if (userError || !verified?.user || verified.user.id !== session.user.id) {
    await sb.auth.signOut(); showForm('loginForm'); $('#loginErr').textContent = 'Unable to verify your session. Please sign in again.'; return;
  }
  const { data: prof, error: profileError } = await sb.from('profiles').select('role').eq('id', verified.user.id).maybeSingle();
  if (profileError || prof?.role !== 'admin') {
    await sb.auth.signOut();
    showForm('loginForm');
    $('#loginErr').textContent = profileError ? 'Unable to verify admin access.' : 'This account is not an admin.';
    return;
  }
  if (bootEpoch !== authEpoch || recovering || me) return;
  me = verified.user;
  resetIdle();
  $('#login').hidden = true;
  $('#app').hidden = false;
  buildNav();
  go('dashboard');
  liveChannel = sb.channel('live').on('postgres_changes', { event: '*', schema: 'public' }, onChange).subscribe();
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
  if (!me) return;
  const host = $('#view');
  const v = document.createElement('div');
  host.replaceChildren(v);
  if (p === 'deliveryFees') {
    if (!window.GraphensDeliveryFeeAdmin?.mount) { v.textContent = 'Delivery fee screen could not be loaded.'; return; }
    try { window.GraphensDeliveryFeeAdmin.mount({ container: v, client: sb }); }
    catch (e) { v.textContent = 'Delivery fee screen could not be opened: ' + (e.message || String(e)); }
    return;
  }
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

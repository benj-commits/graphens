const sb = supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE);
const $ = s => document.querySelector(s);
const ugx = n => 'UGX ' + Number(n || 0).toLocaleString();
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const safeImageUrl = value => { if (!value) return ''; try { const u = new URL(value, location.href); return ['http:', 'https:'].includes(u.protocol) ? u.href : ''; } catch { return ''; } };
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
// Vouchers and delivery-fee controls are intentionally hidden until their
// backend schema and RPCs have been deployed and verified independently.
const PAGES = ['dashboard', 'products', 'projects', 'orders', 'messages', 'customers', 'feedback', 'activity', 'settings'];
const LABEL = { dashboard: 'Dashboard', products: 'Products', projects: 'Projects', orders: 'Orders', deliveryFees: 'Delivery fees', vouchers: 'Vouchers', messages: 'Messages', customers: 'Customers', feedback: 'Feedback', activity: 'Activity', settings: 'Settings' };

let recovering = location.hash.includes('type=recovery');
let me = null, page = 'dashboard', chatWith = null, pendingOrders = 0, idleTimer, authEpoch = 0, liveChannel = null;

/* ---------- auth ---------- */
const FORMS = ['loginForm', 'mfaForm', 'newPassForm'];
const showForm = id => FORMS.forEach(f => $('#' + f).hidden = f !== id);

sb.auth.onAuthStateChange(ev => {
  if (ev === 'PASSWORD_RECOVERY') { recovering = true; $('#app').hidden = true; $('#login').hidden = false; showForm('newPassForm'); }
  if (ev === 'SIGNED_OUT') { authEpoch++; me = null; pendingOrders = 0; if (liveChannel) { sb.removeChannel(liveChannel); liveChannel = null; } clearTimeout(idleTimer); $('#app').hidden = true; $('#view').replaceChildren(); $('#actions').replaceChildren(); $('#nav').replaceChildren(); if ($('#dlg').open) $('#dlg').close(); $('#dlgForm').replaceChildren(); $('#syncStatus').style.display = 'none'; $('#pass').value = ''; $('#login').hidden = false; showForm('loginForm'); }
});

$('#loginForm').addEventListener('submit', async e => {
  e.preventDefault();
  const button = e.currentTarget.querySelector('button[type="submit"]');
  button.disabled = true;
  $('#loginErr').textContent = '';
  try {
    const { error } = await sb.auth.signInWithPassword({ email: $('#email').value.trim(), password: $('#pass').value });
    if (error) { $('#loginErr').textContent = error.status === 400 ? 'Wrong email or password.' : 'Sign-in failed. Check your connection and try again.'; return; }
    $('#pass').value = '';
    await boot();
  } catch (error) {
    $('#loginErr').textContent = 'Sign-in could not be completed. Check your connection and try again.';
  } finally { button.disabled = false; }
});

$('#forgot').onclick = async () => {
  const email = $('#email').value.trim();
  if (!email) { $('#loginErr').textContent = 'Enter your email first.'; return; }
  $('#forgot').disabled = true;
  try {
    const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname });
    if (error) throw error;
    $('#loginErr').textContent = 'If that email belongs to an admin, a reset link is on its way.';
  } catch (error) {
    $('#loginErr').textContent = 'Could not request a reset link. Check your connection and try again.';
  } finally { $('#forgot').disabled = false; }
};

$('#newPassForm').addEventListener('submit', async e => {
  e.preventDefault();
  try {
    const { error } = await sb.auth.updateUser({ password: $('#np').value });
    if (error) { $('#npErr').textContent = error.message; return; }
  } catch (error) { $('#npErr').textContent = 'Could not confirm the password was updated. Check your connection before trying again.'; return; }
  try {
    const { error } = await sb.auth.signOut();
    if (error) throw error;
    location.href = location.pathname;
  } catch (error) { $('#npErr').textContent = 'Password updated, but sign-out failed. Please sign out and sign in again.'; }
});

$('#mfaForm').addEventListener('submit', async e => {
  e.preventDefault();
  try {
    const { data: f, error: factorError } = await sb.auth.mfa.listFactors();
    const factor = f?.totp?.find(x => x.status === 'verified');
    if (factorError || !factor) { $('#mfaErr').textContent = 'Unable to load your authenticator. Check your connection and try again.'; return; }
    const { error } = await sb.auth.mfa.challengeAndVerify({ factorId: factor.id, code: $('#mfaCode').value.trim() });
    if (error) $('#mfaErr').textContent = 'Could not verify the code. Check the code and your connection, then try again.';
    else await boot();
  } catch (error) { $('#mfaErr').textContent = 'Could not verify the code. Check your connection and try again.'; }
});

$('#logout').onclick = async () => { await sb.auth.signOut(); location.reload(); };

function resetIdle() { clearTimeout(idleTimer); idleTimer = setTimeout(async () => { await sb.auth.signOut(); location.reload(); }, 30 * 60 * 1000); }
['click', 'keydown', 'mousemove', 'touchstart'].forEach(ev => document.addEventListener(ev, () => { if (me) resetIdle(); }));

async function boot() {
  if (recovering || me) return;
  const bootEpoch = authEpoch;
  try {
  const { data, error: sessionError } = await sb.auth.getSession();
  if (sessionError) throw sessionError;
  const session = data?.session;
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
  } catch (error) {
    if (bootEpoch !== authEpoch || recovering || me) return;
    $('#login').hidden = false; showForm('loginForm');
    $('#loginErr').textContent = 'Unable to complete sign-in. Check your connection and try again.';
  }
}

function buildNav() {
  $('#nav').innerHTML = PAGES.map(p => `<button data-p="${p}">${LABEL[p]}${p === 'orders' && pendingOrders ? `<span class="dot">${pendingOrders}</span>` : ''}</button>`).join('');
  $('#nav').querySelectorAll('button').forEach(b => { b.onclick = () => go(b.dataset.p); b.classList.toggle('on', b.dataset.p === page); });
}

async function countPending() {
  const epoch = authEpoch;
  const { count, error } = await sb.from('orders').select('id', { count: 'exact', head: true }).eq('status', 'pending');
  if (!me || epoch !== authEpoch || error || !Number.isSafeInteger(count) || count < 0) return;
  pendingOrders = count;
  buildNav();
}

function onChange(p) {
  if (p.table === 'orders') countPending();
  if (p.table === 'messages' && page === 'messages') return refreshChat();
  const map = { products: 'products', projects: 'projects', orders: 'orders', feedback: 'feedback' };
  if (map[p.table] === page || (page === 'dashboard')) go(page, true);
}

async function go(p, silent) {
  if (!PAGES.includes(p)) return;
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
  const epoch = authEpoch;
  if (!window.GraphensDashboard) { v.textContent = 'Dashboard could not be loaded.'; return; }
  return window.GraphensDashboard.mount({ container: v, client: sb, isActive: () => !!me && page === 'dashboard' && epoch === authEpoch && !recovering });
}

/* ---------- products + projects ---------- */

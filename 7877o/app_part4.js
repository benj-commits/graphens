async function customers(v) {
  const [p, o] = await Promise.all([
    sb.from('profiles').select('*').eq('role', 'customer').order('created_at', { ascending: false }),
    sb.from('orders').select('user_id,total')]);
  if (p.error || o.error) { v.textContent = 'Could not load customer information. Try again.'; return; }
  const stats = {};
  (o.data || []).forEach(x => { const s = stats[x.user_id] || (stats[x.user_id] = { n: 0, t: 0 }); s.n++; s.t += Number(x.total); });
  if (!p.data?.length) { v.innerHTML = '<p class="muted">No customers yet. They appear when someone registers in the app.</p>'; return; }
  v.innerHTML = `<div class="list">${p.data.map(c => `<div class="card row">
    <div class="grow"><b>${esc(c.full_name || 'Customer')}</b><div class="small">${esc(c.phone || 'no phone')} · ${stats[c.id]?.n || 0} orders · ${ugx(stats[c.id]?.t || 0)}</div></div>
    <button class="btn ghost" data-m="${esc(c.id)}">Message</button>
    ${waLink(c.phone) ? `<a class="btn ghost" style="text-decoration:none" target="_blank" rel="noopener" href="${waLink(c.phone)}">WhatsApp</a>` : ''}</div>`).join('')}</div>`;
  v.querySelectorAll('[data-m]').forEach(b => b.onclick = () => { chatWith = b.dataset.m; go('messages'); });
}

/* ---------- activity log ---------- */
async function activity(v) {
  const [l, p] = await Promise.all([sb.from('audit_log').select('*').order('created_at', { ascending: false }).limit(100), sb.from('profiles').select('id,full_name')]);
  if (l.error || p.error) { v.textContent = 'Could not load activity. Try again.'; return; }
  const who = Object.fromEntries((p.data || []).map(x => [x.id, x.full_name || 'Admin']));
  if (!l.data?.length) { v.innerHTML = '<p class="muted">No activity yet.</p>'; return; }
  const verb = { INSERT: 'added', UPDATE: 'changed', DELETE: 'deleted' };
  v.innerHTML = `<div class="list">${l.data.map(x => `<div class="card"><b>${esc(who[x.user_id] || 'Admin')}</b> ${esc(verb[x.action] || x.action)} ${esc(x.table_name.replace(/s$/, ''))} <b>${esc(x.label || '')}</b><div class="small">${new Date(x.created_at).toLocaleString()}</div></div>`).join('')}</div>`;
}

/* ---------- settings: 2FA + password ---------- */
async function settings(v) {
  const { data: f, error: factorError } = await sb.auth.mfa.listFactors();
  if (factorError || !f) { v.textContent = 'Could not load security settings: ' + (factorError?.message || 'Unknown error'); return; }
  const on = (f.totp || []).some(x => x.status === 'verified');
  if (page !== 'settings' || !v.isConnected) return;
  v.innerHTML = `<div class="list" style="max-width:560px">
    <div class="card"><b>Two-factor authentication</b>
      <p class="small">${on ? 'On. A code from your authenticator app is needed at every sign-in.' : 'Off. Turn it on so a stolen password is not enough to get in.'}</p>
      <div id="mfaBox">${on ? '<button class="btn ghost" id="mfaOff">Turn off</button>' : '<button class="btn gold" id="mfaOn">Set up with an authenticator app</button>'}</div></div>
    <div class="card"><b>Change password</b>
      <div style="display:grid;gap:8px;margin-top:8px"><input id="pw1" type="password" placeholder="New password (10+ characters)"><button class="btn" id="pwSave">Update password</button><p id="pwMsg" class="small"></p></div>
    </div>
  </div>`;

  $('#pwSave').onclick = async () => {
    const pw = $('#pw1').value;
    if (pw.length < 10) { $('#pwMsg').textContent = 'Use at least 10 characters.'; return; }
    const { error } = await sb.auth.updateUser({ password: pw });
    $('#pwMsg').textContent = error ? error.message : 'Password updated.';
    if (!error) $('#pw1').value = '';
  };

  if (on) $('#mfaOff').onclick = async () => {
    if (!confirm('Turn off two-factor authentication?')) return;
    const { error } = await sb.auth.mfa.unenroll({ factorId: f.totp.find(x => x.status === 'verified').id });
    if (error) alert(error.message); else { await sb.auth.refreshSession(); settings(v); }
  };
  else $('#mfaOn').onclick = async () => {
    const { data: all } = await sb.auth.mfa.listFactors();
    for (const x of (all.all || []).filter(x => x.status === 'unverified')) await sb.auth.mfa.unenroll({ factorId: x.id });
    const { data, error } = await sb.auth.mfa.enroll({ factorType: 'totp', friendlyName: 'Graphen admin ' + Date.now() });
    if (error) { alert(error.message); return; }
    $('#mfaBox').innerHTML = `<p class="small">Scan with Google Authenticator, Microsoft Authenticator or Authy.</p>
      <img src="${esc(data.totp.qr_code)}" width="180" alt="QR code">
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

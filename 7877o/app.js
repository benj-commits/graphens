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

async function settings(v) {
  const { data: f } = await sb.auth.mfa.listFactors();
  const on = f.totp.length > 0;
  const { data: loc } = await sb.from('profiles').select('phone, full_name').limit(1).maybeSingle();
  v.innerHTML = `<div class="list" style="max-width:560px">
    <div class="card"><b>Business location</b>
      <div style="display:grid;gap:8px;margin-top:8px">
        <input id="bizAddress" placeholder="Business address" value="${esc(loc?.address ?? '')}">
        <input id="bizCoords" placeholder="Latitude, Longitude" value="${esc(loc?.coordinates ?? '')}">
        <button class="btn" id="saveBiz">Save business location</button>
      </div>
    </div>
    <div class="card"><b>Two-factor authentication</b>
      <p class="small">${on ? 'On. A code from your authenticator app is needed at every sign-in.' : 'Off. Turn it on so a stolen password is not enough to get in.'}</p>
      <div id="mfaBox">${on ? '<button class="btn ghost" id="mfaOff">Turn off</button>' : '<button class="btn gold" id="mfaOn">Set up with an authenticator app</button>'}</div></div>
    <div class="card"><b>Change password</b>
      <div style="display:grid;gap:8px;margin-top:8px"><input id="pw1" type="password" placeholder="New password (10+ characters)"><button class="btn" id="pwSave">Update password</button><p id="pwMsg" class="small"></p></div>
    </div>
  </div>`;

  $('#saveBiz').onclick = async () => {
    const address = $('#bizAddress').value.trim();
    const coords = $('#bizCoords').value.trim();
    await sb.from('profiles').update({ address, coordinates: coords }).eq('id', me.id);
    alert('Business location saved.');
  };

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

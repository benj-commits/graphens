async function crud(v, t) {
  const c = CRUD[t];
  $('#actions').innerHTML = `<button class="btn gold" id="add">+ Add ${c.one}</button>`;
  $('#add').onclick = () => editor(t, null);
  const { data, error } = await sb.from(t).select('*').order('created_at', { ascending: false });
  if (error) { v.textContent = 'Could not load ' + c.title.toLowerCase() + ': ' + error.message; return; }
  if (!data?.length) { v.innerHTML = `<p class="muted">No ${c.one}s yet. Click "Add ${c.one}".</p>`; return; }
  v.innerHTML = `<div class="list">${data.map(r => `
    <div class="card row">
      ${t === 'vouchers' ? '' : `<img class="thumb" src="${esc(safeImageUrl(r.images?.[0] || ''))}" alt="">`}
      <div class="grow"><b>${esc(r[c.name])}</b><br><span class="gold">${ugx(r[c.price])}</span>
        ${r.stock !== undefined ? `<span class="small"> · stock ${esc(r.stock)}</span>` : ''}
        <span class="tag ${r.active ? '' : 'off'}">${r.active ? 'Visible' : 'Hidden'}</span></div>
      <button class="btn ghost" data-e="${esc(r.id)}">Edit</button>
      <button class="btn ghost" data-d="${esc(r.id)}">Delete</button>
    </div>`).join('')}</div>`;
  v.querySelectorAll('[data-e]').forEach(b => b.onclick = () => editor(t, data.find(r => r.id === b.dataset.e)));
  v.querySelectorAll('[data-d]').forEach(b => b.onclick = async () => {
    if (confirm(`Delete this ${c.one}?`)) { const { data: deleted, error } = await sb.from(t).delete().eq('id', b.dataset.d).select('id').maybeSingle(); if (error || !deleted) alert('Could not delete: ' + (error?.message || 'No record was deleted.')); else go(t, true); }
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
    ${t === 'vouchers' ? '' : `<div class="imgs" id="imgs"></div>
    <label>Photos<input type="file" id="files" accept="image/*" multiple></label>`}
    ${fieldHtml}
    <p class="err" id="eErr"></p>
    <div class="row" style="justify-content:flex-end"><button type="button" class="btn ghost" id="cancel">Cancel</button><button type="button" class="btn" id="save">Save</button></div>`;
  const drawImgs = () => {
    $('#imgs').innerHTML = keep.map((u, i) => `<div class="im"><img src="${esc(safeImageUrl(u))}" alt=""><button type="button" class="x" data-i="${i}">x</button></div>`).join('');
    $('#imgs').querySelectorAll('.x').forEach(b => b.onclick = () => { keep.splice(+b.dataset.i, 1); drawImgs(); });
  };
  if (t !== 'vouchers') drawImgs();
  $('#cancel').onclick = () => $('#dlg').close();
  $('#save').onclick = async () => {
    const btn = $('#save'); btn.disabled = true; btn.textContent = 'Saving...';
    try {
      const data = t === 'vouchers' ? {} : { images: keep };
      c.fields.forEach(([k, , type]) => {
        const el = f.elements[k];
        data[k] = type === 'bool' ? el.checked : type === 'number' ? Number(el.value) || 0 : el.value.trim();
      });
      for (const file of (t === 'vouchers' ? [] : $('#files').files)) {
        const path = `${Date.now()}_${file.name.replace(/\s+/g, '_')}`;
        const { error } = await sb.storage.from('media').upload(path, file, { contentType: file.type });
        if (error) throw error;
        data.images.push(sb.storage.from('media').getPublicUrl(path).data.publicUrl);
      }
      const result = row ? await sb.from(t).update(data).eq('id', row.id).select('id').maybeSingle() : await sb.from(t).insert(data).select('id').maybeSingle();
      if (result.error || !result.data) throw result.error || new Error('No record was saved.');
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

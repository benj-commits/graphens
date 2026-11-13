const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const code = fs.readFileSync(require.resolve('../app_part2.js'), 'utf8');
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

function setup({original = 10, input = '10', current = 10, error = null, kind = 'products', isNew = false} = {}) {
  const calls = [], db = { id:'p', stock:current, name:'old', active:true }, f = {innerHTML:'',elements:{stock:{value:input},name:{value:'new'},active:{checked:false}}};
  let closed = false, refreshed = false;
  const nodes = {dlgForm:f,imgs:{innerHTML:'',querySelectorAll:()=>[]},files:{files:[]},cancel:{},save:{},eErr:{textContent:''},dlg:{showModal(){},close(){closed=true}},actions:{},add:{}};
  function writer(data, method) {
    const filters = [];
    const chain = {eq(k,v){filters.push(['eq',k,v]);return this},is(k,v){filters.push(['is',k,v]);return this},select(){return this},async maybeSingle(){
      calls.push({method,data:JSON.parse(JSON.stringify(data)),filters});
      if(error) return {data:null,error:{message:error}};
      if(method==='update' && !filters.every(([,k,v])=>db[k]===v)) return {data:null,error:null};
      Object.assign(db,data); return {data:{id:'p'},error:null};
    }}; return chain;
  }
  const sb = {from(){return {update:d=>writer(d,'update'),insert:d=>writer(d,'insert'),select(){return {order:async()=>({data:[db]})}},delete(){throw Error('unexpected deletion')}}}};
  const fields=[['name','Name','text'],['stock','Stock','number'],['active','Visible in app','bool']];
  const ctx = {CRUD:{products:{title:'Products',one:'product',name:'name',price:'price',fields},projects:{title:'Projects',one:'project',name:'name',price:'price',fields:[]}},$:s=>nodes[s.slice(1)],esc,safeImageUrl:x=>x,ugx:()=>'',sb,go(){refreshed=true},confirm(){throw Error('unexpected confirmation')},alert(){}};
  vm.createContext(ctx); vm.runInContext(code,ctx);
  const row = isNew ? null : {id:'p',stock:original,name:'old',active:true,images:[]};
  return {ctx,nodes,f,calls,db,row,closed:()=>closed,refreshed:()=>refreshed,kind};
}

test('unchanged stock is omitted even when concurrent order changes stock', async()=>{
  const s=setup({original:10,input:'10',current:8}); s.ctx.editor('products',s.row); await s.nodes.save.onclick();
  assert.equal(s.db.stock,8); assert.equal(s.db.name,'new'); assert.equal(s.db.active,false);
  assert.equal(Object.hasOwn(s.calls[0].data,'stock'),false); assert.deepEqual(s.calls[0].filters,[['eq','id','p']]); assert.ok(s.closed());
});

test('changed stock uses atomic original-stock condition and rejects stale write', async()=>{
  for (const current of [10,8]) {
    const s=setup({original:10,input:'15',current}); s.ctx.editor('products',s.row); await s.nodes.save.onclick();
    assert.deepEqual(s.calls[0].filters,[['eq','id','p'],['eq','stock',10]]); assert.equal(s.calls[0].data.stock,15);
    if(current===8) {assert.equal(s.db.stock,8); assert.equal(s.db.name,'old'); assert.match(s.nodes.eErr.textContent,/Stock may have changed/); assert.equal(s.nodes.save.disabled,false); assert.equal(s.closed(),false);}
    else {assert.equal(s.db.stock,15); assert.ok(s.closed()); assert.ok(s.refreshed());}
  }
});

test('null original stock remains null unless changed; changed null is conditionally matched', async()=>{
  let s=setup({original:null,input:'',current:4}); s.ctx.editor('products',s.row); await s.nodes.save.onclick(); assert.equal(s.db.stock,4); assert.equal(Object.hasOwn(s.calls[0].data,'stock'),false);
  s=setup({original:null,input:'0',current:null}); s.ctx.editor('products',s.row); await s.nodes.save.onclick(); assert.deepEqual(s.calls[0].filters,[['eq','id','p'],['is','stock',null]]); assert.equal(s.db.stock,0);
  s=setup({original:null,input:'0',current:4}); s.ctx.editor('products',s.row); await s.nodes.save.onclick(); assert.equal(s.db.stock,4); assert.match(s.nodes.eErr.textContent,/Stock may have changed/);
});

test('invalid stock and missing baseline fail closed; inserts retain stock', async()=>{
  for(const input of ['', '-1', '1.5', '2147483648']) {const s=setup({input});s.ctx.editor('products',s.row);await s.nodes.save.onclick();assert.equal(s.calls.length,0);assert.match(s.nodes.eErr.textContent,/Stock must/)}
  let s=setup(); delete s.row.stock; s.ctx.editor('products',s.row); await s.nodes.save.onclick(); assert.equal(s.calls.length,0); assert.match(s.nodes.eErr.textContent,/Original stock is unavailable/);
  s=setup({isNew:true,input:'5'}); s.ctx.editor('products',null); await s.nodes.save.onclick(); assert.equal(s.calls[0].method,'insert'); assert.equal(s.calls[0].data.stock,5);
});

test('database errors show without closing editor', async()=>{const s=setup({input:'11',error:'permission denied'});s.ctx.editor('products',s.row);await s.nodes.save.onclick();assert.match(s.nodes.eErr.textContent,/permission denied/);assert.equal(s.closed(),false)});

test('product list offers hiding but never attaches delete; projects retain delete', async()=>{
  for(const kind of ['products','projects']) {
    const s=setup({kind}); const fakeDelete={dataset:{d:'p'}}; const v={innerHTML:'',querySelectorAll(sel){return sel==='[data-d]'?[fakeDelete]:[]}};
    await s.ctx.crud(v,kind);
    if(kind==='products') {assert.doesNotMatch(v.innerHTML,/data-d=/);assert.match(v.innerHTML,/uncheck Visible in app/);assert.equal(fakeDelete.onclick,undefined)}
    else {assert.match(v.innerHTML,/data-d=/);assert.equal(typeof fakeDelete.onclick,'function')}
  }
});

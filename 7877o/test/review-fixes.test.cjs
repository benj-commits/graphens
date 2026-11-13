const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const read = name => fs.readFileSync(require.resolve('../' + name), 'utf8');
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

test('editor preserves unknown and null select values unless deliberately changed', async () => {
  for (const [kind, value, change] of [['products',' Vintage & <Rare> ',null], ['projects','ongoing',null], ['projects',null,null], ['projects','ongoing','Completed']]) {
    let payload;
    const f = {innerHTML:'', elements:{choice:{value: change ?? value ?? ''}}};
    const nodes = {dlgForm:f, imgs:{innerHTML:'',querySelectorAll:()=>[]}, files:{files:[]}, cancel:{}, save:{}, eErr:{}, dlg:{showModal(){},close(){}}};
    const sb = {from:()=>({update(data){payload=data; const chain={eq(){return chain},select(){return chain},async maybeSingle(){return {data:{id:'1'}}}};return chain}})};
    const ctx = {CRUD:{products:{one:'product',fields:[['choice','Category','select',['Lady Bags','Other']]]},projects:{one:'project',fields:[['choice','Status','select',['Open','Completed']]]}}, $:s=>nodes[s.slice(1)], esc, safeImageUrl:x=>x, sb, go(){}};
    vm.createContext(ctx); vm.runInContext(read('app_part2.js'),ctx);
    ctx.editor(kind,{id:'1', choice:value, images:[]});
    assert.match(f.innerHTML, /selected/);
    if (value != null) assert.ok(f.innerHTML.includes(esc(value)));
    await nodes.save.onclick();
    if (change) assert.equal(payload.choice,change); else assert.equal(Object.hasOwn(payload,'choice'),false);
  }
});

test('messages refresh after successful insert and show errors without clearing drafts', async () => {
  for (const mode of ['ok','insert-error','insert-throw','refresh-error','refresh-throw']) {
    let inserts=0, reads=0; const alerts=[];
    const nodes={threads:{innerHTML:'old',querySelectorAll:()=>[]},bubbles:{innerHTML:'',scrollHeight:1},composer:{hidden:true},chatErr:{textContent:''},msgIn:{value:'Hello',isConnected:true},send:{disabled:false}};
    const sb={from(){return {async insert(){inserts++; if(mode==='insert-throw') throw Error('offline'); return {error:mode==='insert-error'?{message:'denied'}:null}},select(){return {async order(){reads++; if(mode==='refresh-throw') throw Error('offline'); if(mode==='refresh-error') return {error:{message:'offline'}}; return {data:[{customer_id:'c',body:'Hello',is_admin:true,created_at:'2026-01-01'}]}}}}}}};
    const ctx={sb,$:s=>nodes[s.slice(1)],page:'messages',chatWith:'c',me:{id:'admin'},esc,alert:x=>alerts.push(x)};
    vm.createContext(ctx); vm.runInContext(read('app_part3.js'),ctx); await ctx.send();
    assert.equal(inserts,1); assert.equal(nodes.send.disabled,false);
    if(mode.startsWith('insert')) {assert.equal(nodes.msgIn.value,'Hello'); assert.match(alerts[0],/Check the conversation before retrying/); assert.equal(reads,0)}
    else {assert.equal(nodes.msgIn.value,''); assert.equal(reads,1); if(mode==='ok') assert.match(nodes.bubbles.innerHTML,/Hello/); else {assert.match(nodes.chatErr.textContent,/Message sent, but messages could not be refreshed/); assert.equal(nodes.threads.innerHTML,'old'); assert.deepEqual(alerts,[])}}
  }
});

test('terminal orders cannot be reopened and stale status uses atomic compare', async () => {
  for (const status of ['cancelled','delivered','unknown']) {
    let updates=0; const control={dataset:{o:'1'},value:'pending',disabled:false};
    const ctx={sb:{from:()=>({select:()=>({order:async()=>({data:[{id:'1',status,items:[],created_at:'2026-01-01'}]})}), update(){updates++}})}, STATUSES:['pending','confirmed','processing','delivered','cancelled'],esc,ugx:()=>'',alert(){},page:'orders',go(){},countPending:async()=>{}};
    vm.createContext(ctx); vm.runInContext(read('app_part3.js'),ctx);
    const v={innerHTML:'',querySelectorAll:()=>[control]}; await ctx.orders(v);
    assert.match(v.innerHTML, /<select[^>]*disabled/); await control.onchange(); assert.equal(updates,0); assert.equal(control.value,status);
  }
});

test('password reset and MFA handle returned and thrown errors', async () => {
  const nodes={};
  for(const id of ['app','login','loginForm','mfaForm','newPassForm','email','pass','forgot','logout','dlg','dlgForm','view','actions','nav','syncStatus','title','loginErr','mfaErr','mfaCode','np','npErr']) nodes[id]={value:'',style:{},handlers:{},addEventListener(e,f){this.handlers[e]=f},replaceChildren(){},querySelectorAll(){return []},close(){}};
  nodes.email.value='a@example.test';
  const auth={onAuthStateChange(){},resetPasswordForEmail:async()=>({error:{message:'down'}}),mfa:{listFactors:async()=>{throw Error('offline')}},updateUser:async()=>{throw Error('offline')}};
  const ctx={supabase:{createClient:()=>({auth})},SUPABASE_URL:'test',SUPABASE_PUBLISHABLE:'test',document:{querySelector:s=>nodes[s.slice(1)],addEventListener(){}},location:{hash:'',origin:'https://example.test',pathname:'/'},URL,setTimeout,clearTimeout}; ctx.window=ctx;
  vm.createContext(ctx); vm.runInContext(read('app.js'),ctx);
  await nodes.forgot.onclick(); assert.match(nodes.loginErr.textContent,/Could not request/); assert.equal(nodes.forgot.disabled,false);
  auth.resetPasswordForEmail=async()=>{throw Error('offline')}; await nodes.forgot.onclick(); assert.match(nodes.loginErr.textContent,/Could not request/);
  auth.resetPasswordForEmail=async()=>({error:null}); await nodes.forgot.onclick(); assert.match(nodes.loginErr.textContent,/If that email/);
  await nodes.mfaForm.handlers.submit({preventDefault(){}}); assert.match(nodes.mfaErr.textContent,/connection/);
  auth.mfa.listFactors=async()=>({data:{totp:[{id:'x',status:'verified'}]}}); auth.mfa.challengeAndVerify=async()=>({error:{message:'network'}});
  await nodes.mfaForm.handlers.submit({preventDefault(){}}); assert.match(nodes.mfaErr.textContent,/connection/);
  await nodes.newPassForm.handlers.submit({preventDefault(){}}); assert.match(nodes.npErr.textContent,/Could not confirm/);
});

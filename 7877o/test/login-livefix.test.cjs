const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');

function setup({role='admin', aal='aal1', failure=false}={}) {
  const nodes = {};
  for (const id of ['app','login','loginForm','mfaForm','newPassForm','email','pass','forgot','logout','dlg','dlgForm','view','actions','nav','syncStatus','title','loginErr','mfaErr','mfaCode']) {
    nodes[id] = {hidden:false, value:'', innerHTML:'', textContent:'', style:{}, handlers:{}, open:false,
      addEventListener(event, fn){this.handlers[event]=fn;}, replaceChildren(){this.innerHTML='';}, close(){this.open=false;}, querySelectorAll(){return [];}};
  }
  const button={disabled:false}; nodes.loginForm.querySelector=()=>button;
  nodes.email.value='admin@example.test'; nodes.pass.value='password';
  let signedOut=false, signIns=0;
  const sb = {auth:{
    onAuthStateChange(){},
    async signInWithPassword(){signIns++; if(failure) throw Error('offline'); return {error:null};},
    async getSession(){return {data:{session:{user:{id:'1'}}}, error:null};},
    mfa:{async getAuthenticatorAssuranceLevel(){return {data:aal==='mfa'?{currentLevel:'aal1',nextLevel:'aal2'}:{currentLevel:'aal1',nextLevel:'aal1'},error:null};}},
    async getUser(){return {data:{user:{id:'1'}},error:null};},
    async signOut(){signedOut=true;},
  }, from(){return {select(){return {eq(){return {async maybeSingle(){return {data:{role},error:null};}}}}}}},
  channel(){return {on(){return this},subscribe(){return this}}}};
  const ctx = {supabase:{createClient:()=>sb}, SUPABASE_URL:'example', SUPABASE_PUBLISHABLE:'test',
    document:{querySelector(s){return nodes[s.slice(1)];}, addEventListener(){}},
    location:{hash:'',href:'https://example.test/admin/',reload(){}}, URL, setTimeout, clearTimeout, console};
  ctx.window=ctx; vm.createContext(ctx); vm.runInContext(fs.readFileSync(require.resolve('../app.js'),'utf8'),ctx);
  vm.runInContext('window.originalGo=go;resetIdle=()=>{};buildNav=()=>{};go=()=>{}',ctx);
  return {ctx,nodes,button, signIns:()=>signIns,signedOut:()=>signedOut};
}
async function submit(x){await x.nodes.loginForm.handlers.submit({preventDefault(){},currentTarget:x.nodes.loginForm});}
test('admin login verifies session and profile before showing the app',async()=>{
  const x=setup(); await submit(x); assert.equal(x.signIns(),1); assert.equal(x.nodes.app.hidden,false); assert.equal(x.nodes.login.hidden,true); assert.equal(x.nodes.pass.value,''); assert.equal(x.button.disabled,false);
});
test('non-admin is signed out and cannot enter',async()=>{
  const x=setup({role:'customer'}); await submit(x); assert.equal(x.signedOut(),true); assert.match(x.nodes.loginErr.textContent,/not an admin/); assert.notEqual(x.nodes.login.hidden,true);
});
test('MFA is required before app is opened',async()=>{
  const x=setup({aal:'mfa'}); x.nodes.app.hidden=true; await submit(x); assert.equal(x.nodes.mfaForm.hidden,false); assert.equal(x.nodes.app.hidden,true);
});
test('network errors are visible and the button can be retried',async()=>{
  const x=setup({failure:true}); await submit(x); assert.match(x.nodes.loginErr.textContent,/connection/); assert.equal(x.button.disabled,false);
});
test('unsupported pages are excluded from navigation and blocked directly',async()=>{
  const x=setup(); assert.equal(vm.runInContext("PAGES.includes('vouchers') || PAGES.includes('deliveryFees')",x.ctx),false);
  vm.runInContext("page='dashboard'",x.ctx); await vm.runInContext("window.originalGo('vouchers')",x.ctx); assert.equal(vm.runInContext('page',x.ctx),'dashboard');
});

test('image URLs reject unsafe protocols and preserve safe web URLs',()=>{
  const x=setup();
  assert.equal(vm.runInContext("safeImageUrl('javascript:alert(1)')",x.ctx),'');
  assert.equal(vm.runInContext("safeImageUrl('data:text/html,evil')",x.ctx),'');
  assert.equal(vm.runInContext("safeImageUrl('')",x.ctx),'');
  assert.equal(vm.runInContext("safeImageUrl('https://example.test/image.png')",x.ctx),'https://example.test/image.png');
});

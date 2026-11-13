const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
function setup() {
  const nodes = {};
  for (const id of ['app','login','loginForm','mfaForm','newPassForm','email','pass','forgot','logout','dlg','dlgForm','view','actions','nav','syncStatus','title']) {
    nodes[id] = {hidden:false, value:'', innerHTML:'sensitive', textContent:'', style:{}, open:false,
      addEventListener(){}, replaceChildren(){this.innerHTML='';}, close(){this.open=false;}, querySelectorAll(){return [];}};
  }
  let authCallback, countResolve, subCallback;
  const removed=[];
  const sb = {auth:{onAuthStateChange(cb){authCallback=cb;}}, removeChannel(ch){removed.push(ch);},
    from(){return {select(){return {eq(){return new Promise(r => {countResolve=r;});}};}};},
    channel(){return {subscribe(cb){subCallback=cb; return this;}};}};
  const context = {supabase:{createClient:()=>sb}, SUPABASE_URL:'example', SUPABASE_PUBLISHABLE:'test',
    document:{querySelector(s){return nodes[s.slice(1)];}, addEventListener(){}},
    location:{hash:'',reload(){}}, setTimeout, clearTimeout, console};
  context.window=context;
  vm.createContext(context); vm.runInContext(fs.readFileSync(require.resolve('../app.js'),'utf8'),context);
  vm.runInContext(fs.readFileSync(require.resolve('../realtime_sync.js'),'utf8'),context);
  return {context,nodes,sb,removed, authCallback, resolveCount: x=>countResolve(x), subscribed:()=>subCallback};
}
test('sign-out clears sensitive UI and late navbar counts cannot repopulate it', async () => {
  const x=setup(); vm.runInContext("me={id:'admin'}; liveChannel={};",x.context);
  x.nodes.dlg.open=true; x.nodes.pass.value='secret';
  const pending=vm.runInContext('countPending()',x.context);
  x.authCallback('SIGNED_OUT');
  assert.equal(x.nodes.app.hidden,true); assert.equal(x.nodes.login.hidden,false);
  for (const id of ['view','actions','nav','dlgForm']) assert.equal(x.nodes[id].innerHTML,'');
  assert.equal(x.nodes.dlg.open,false); assert.equal(x.nodes.pass.value,'');
  assert.equal(x.nodes.syncStatus.style.display,'none'); assert.equal(x.removed.length,1);
  x.resolveCount({count:7,error:null}); await pending;
  assert.equal(x.nodes.nav.innerHTML,'');
});
test('realtime ignores signed-out callbacks', () => {
  const x=setup(); vm.runInContext("me={id:'admin'}",x.context);
  const channel=x.sb.channel('live'); channel.subscribe(); const callback=x.subscribed();
  callback('SUBSCRIBED'); assert.equal(x.nodes.syncStatus.style.display,'block');
  x.authCallback('SIGNED_OUT'); callback('CLOSED');
  assert.equal(x.nodes.syncStatus.style.display,'none');
  x.context.onChange({table:'orders'});
});

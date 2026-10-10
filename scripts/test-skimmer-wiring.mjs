import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'
function session(config={}){
 const results=[],events={},elements={};const ctx=new Proxy({},{get:()=>()=>{}})
 const element=id=>elements[id]??={style:{},textContent:'',addEventListener(){},getContext:()=>ctx};
 const parent={postMessage:r=>results.push(r)},window={devicePixelRatio:1,addEventListener:(k,f)=>(events[k]??=[]).push(f)};
 const box={window,parent,document:{getElementById:element},requestAnimationFrame(){},console};vm.createContext(box)
 let script=fs.readFileSync('src/minigames/shearSkimmer.html','utf8').match(/<script>([\s\S]*?)<\/script>/)[1];script=script.replace(/\}\)\(\);\s*$/, 'globalThis.api={state:()=>S,cut,stripClick,move,press,release,hold,feed,update,finish,draw,hud,current,pad,endPoint};})();');vm.runInContext(script,box)
 for(const f of events.message)f({source:parent,data:{action:'skimmer:open',id:'test',config}})
 return {api:box.api,results,events};
}
function prepare(t){const a=t.api,s=a.state(),end=a.endPoint();a.move(350,end.y);a.press();assert.equal(s.stage,'strip');a.move(end.x,end.y);assert.ok(s.snapped);while(s.strip<s.stripTarget-s.d.stripTol)a.press();a.move(end.x+30,end.y);assert.ok(s.snapped,'small movement stays seated');a.move(end.x+s.d.snapRelease+1,end.y);assert.equal(s.stage,'place');a.move(end.x,end.y);a.press();const p=a.pad();a.move(p.x,p.y);a.release();assert.equal(s.stage,'solder');assert.equal(s.wireEnd.x,p.x)}
for(const level of ['easy','medium','hard'])for(const solderMode of ['heat_feed','trace','steady'])for(const drift of [false,true]){
 const t=session({level,solderMode,drift}),a=t.api,s=a.state();
 for(let wire=0;wire<s.d.wires;wire++){
  prepare(t);let cooling=false;
  for(let i=0;i<4000&&s.index===wire;i++){
   const p=a.pad();let x=p.x,y=p.y;
   if(solderMode==='trace'){const sector=s.trace.findIndex(v=>v<1),angle=(Math.max(0,sector)+.5)*Math.PI/4;x+=Math.cos(angle)*15;y+=Math.sin(angle)*15}
   a.move(x-s.offset.x,y-s.offset.y);
   if(s.heat>=s.d.heatHigh-3)cooling=true;if(s.heat<=s.d.heatLow+3)cooling=false;
   a.hold(!cooling);a.feed(solderMode==='heat_feed'&&s.heat>=s.d.heatLow+1);a.update(.02);
  }
  assert.equal(s.index,wire+1,`${level} ${solderMode} drift=${drift}`);a.draw();a.hud();
 }
 assert.equal(t.results.length,1);assert.equal(t.results[0].success,true);a.finish(false);assert.equal(t.results.length,1)
}
let t=session({wires:1,mistakes:4}),a=t.api,s=a.state();a.cut((a.current()+1)%6);assert.equal(s.errors,1);
a.cut(a.current());a.move(370,a.endPoint().y);a.press();a.move(450,a.endPoint().y);assert.equal(s.errors,2);assert.equal(s.stage,'strip');
t=session();prepare(t);a=t.api;s=a.state();const p=a.pad();a.move(p.x,p.y);a.hold(true);a.feed(true);a.update(.02);assert.equal(s.errors,1);assert.equal(s.joint,0,'cold joint');
a.feed(false);a.hold(true);a.update(10);assert.equal(s.errors,2,'overheat');
t=session({solderMode:'trace',drift:false});prepare(t);a=t.api;s=a.state();a.move(a.pad().x+15,a.pad().y);s.heat=60;a.hold(true);for(let i=0;i<10;i++){s.heat=60;a.update(.03)}assert.ok(s.joint<=.125,'one trace sector cannot complete');
t=session({drift:true});prepare(t);a=t.api;s=a.state();a.move(a.pad().x,a.pad().y);a.hold(true);a.update(.2);assert.ok(Math.hypot(s.offset.x,s.offset.y)>0);for(const f of t.events.blur)f();assert.equal(s.holding,false);assert.equal(s.feeding,false);
t=session({drift:false});prepare(t);a=t.api;s=a.state();a.hold(true);a.update(.2);assert.equal(s.offset.x,0);assert.equal(s.offset.y,0);
t=session();a=t.api;s=a.state();a.cut(a.current());a.move(370,a.endPoint().y);while(s.strip<s.stripTarget-s.d.stripTol)a.press();a.move(450,a.endPoint().y);a.move(370,a.endPoint().y);a.press();a.move(480,200);a.release();assert.equal(s.stage,'place');assert.equal(s.wireEnd.x,480,'release position retained');
a.move(480,200);a.press();const wrong=(s.terminals.indexOf(a.current())+1)%6;a.move(560,137+wrong*38);a.release();assert.equal(s.errors,1);assert.equal(s.stage,'place');
t=session({time:15});t.api.update(16);assert.equal(t.results[0].reason,'time');
t=session();for(const f of t.events.keydown)f({key:'Escape'});assert.equal(t.results[0].reason,'cancel');
t=session({solderMode:'invalid',wires:999,drift:'true',snapRelease:1});s=t.api.state();assert.equal(s.d.solderMode,'heat_feed');assert.equal(s.d.drift,false);assert.equal(s.order.length,6);assert.equal(s.d.snapRelease,25);
console.log('Wiring: 18 difficulty/mode/drift combinations, physical tools, snapping, placement, cold joints, trace coverage, drift, overheat, blur, cancel and timeout passed.')

import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'
const themes=fs.readFileSync('src/minigames/shearThemes.js','utf8')
function session(kind,config){
  const results=[],events={},els={},elementEvents={};const gradient={addColorStop(){}}
  const ctx=new Proxy({}, {get:(_,k)=>k.startsWith('create')?()=>gradient:()=>{}})
  const element=id=>els[id]??={style:{setProperty(){}},value:35,hidden:false,addEventListener(k,f){((elementEvents[id]??={})[k]??=[]).push(f)},getContext:()=>ctx,replaceChildren(){},getBoundingClientRect:()=>({left:0,width:800,height:440})}
  const parent={postMessage:r=>results.push(r)},window={devicePixelRatio:1,addEventListener:(k,f)=>(events[k]??=[]).push(f)}
  const box={window,parent,document:{getElementById:element,createElement:()=>({})},performance:{now:()=>1000},requestAnimationFrame(){},setTimeout(){},console}
  vm.createContext(box)
  let script=fs.readFileSync(`src/minigames/${kind==='drill'?'shearDrill':'shearGrinder'}.html`,'utf8').replace('/* SHEAR_THEME_RENDERER */',themes).match(/<script>([\s\S]*?)<\/script>/)[1]
  script=script.replace(/\}\)\(\);\s*$/,`globalThis.api={state:()=>S,update,finish,draw${kind==='drill'?',useOil':''}};})();`)
  vm.runInContext(script,box)
  for(const f of events.message)f({source:parent,data:{action:kind+':open',id:'test',config}})
  return {api:box.api,results,events,elementEvents,els,parent}
}
for(const theme of ['padlock','camlock']){
  let t=session('drill',{level:'easy',theme,pins:999,oil:999});assert.equal(t.api.state().pins.length,10);assert.equal(t.api.state().oil,20);t.api.draw()
  t.api.state().heat=99;t.api.useOil();assert.equal(t.api.state().oil,19);assert.equal(t.api.state().oilUsed,1)
  t.api.state().turning=true;t.api.state().turn=4.59;t.api.update(.02);assert.equal(t.results[0].success,true);t.api.finish(false,'cancel');assert.equal(t.results.length,1)
  t=session('drill',{level:'easy',theme});t.api.state().time=.01;t.api.update(.02);assert.equal(t.results[0].reason,'time')
  t=session('drill',{level:'easy',theme});t.api.state().stress=100;t.api.state().run=true;t.els.pressure.value=100;t.api.update(.02);assert.equal(t.results[0].reason,'snap')
}
for(const target of ['shackle','bolts']){
  let t=session('grinder',{target,cuts:99,feed:80,time:300,heatRate:1,wearRate:1,wob:0,drift:0,angleDrift:0});const s=t.api.state();assert.equal(s.targets.length,target==='bolts'?8:2)
  t.api.draw();t.els.pressure.value=50;
  for(let i=0;i<s.targets.length;i++){s.x=s.targets[i].x;s.run=true;for(let k=0;k<100&&s.index===i;k++)t.api.update(.05)}
  assert.equal(s.index,s.targets.length);assert.equal(s.turning,true);t.api.update(1.3);assert.equal(t.results[0].success,true)
  t.api.finish(false,'cancel');assert.equal(t.results.length,1)
  t=session('grinder',{target});t.api.state().time=.001;t.api.update(.05);assert.equal(t.results[0].reason,'time')
  t=session('grinder',{target});t.api.state().heat=100;t.api.state().run=true;t.api.update(.01);assert.equal(t.results[0].reason,'heat')
}
// Load changes actual position/angle, and releasing does not magically recenter the disc.
let t=session('grinder',{target:'bolts',cuts:1,heatRate:1,wearRate:1,wob:0});let s=t.api.state();s.x=400;s.forcePhase=0;s.run=true;t.els.pressure.value=80;
let peakAngle=0;for(let i=0;i<60;i++){t.api.update(.05);peakAngle=Math.max(peakAngle,Math.abs(s.angle))}
assert.ok(Math.abs(s.x-400)>s.d.tol);assert.ok(peakAngle>s.d.angleTol);
const displaced=s.x;s.run=false;for(let i=0;i<80;i++)t.api.update(.05);assert.ok(Math.abs(s.x-400)>s.d.tol);assert.ok(Math.abs(s.x-displaced)<15)
// A tilted disc cannot cut, wears faster, and can be corrected with Q.
t=session('grinder',{target:'bolts',cuts:1,heatRate:1,wob:0,drift:0,angleDrift:0});s=t.api.state();s.x=400;s.angle=30;s.run=true;t.els.pressure.value=50;t.api.update(.1);
assert.equal(s.targets[0].cut,0);assert.ok(s.wear>0);
for(const f of t.events.keydown)f({key:'q',preventDefault(){}});
for(let i=0;i<12;i++)t.api.update(.05);
for(const f of t.events.keyup)f({key:'q'});
assert.ok(Math.abs(s.angle)<s.d.angleTol);assert.ok(s.targets[0].cut>0);
function driftAt(p){const t=session('grinder',{target:'bolts',cuts:1,heatRate:1,wearRate:1,wob:0,angleDrift:0});const s=t.api.state();s.x=400;s.forcePhase=0;s.run=true;t.els.pressure.value=p;for(let i=0;i<20;i++)t.api.update(.05);return Math.abs(s.x-400)}
assert.ok(driftAt(80)>driftAt(20)*2);
// Mouse up raises the handle; reverse movement levels it, without anchoring loaded position.
t=session('grinder',{target:'bolts'});s=t.api.state();s.x=410;s.run=true;
for(const f of t.elementEvents.cv.pointermove)f({clientX:400,movementX:0,movementY:-40});
assert.equal(s.angle,10);assert.equal(s.x,410);
for(const f of t.elementEvents.cv.pointermove)f({clientX:400,movementX:12,movementY:40});
assert.equal(s.angle,0);assert.equal(s.x,422);
t=session('grinder',{target:'bolts',mouseTilt:0});s=t.api.state();
for(const f of t.elementEvents.cv.pointermove)f({clientX:400,movementX:0,movementY:-200});assert.equal(s.angle,0);
// Default medium games remain completable by correcting both axes and cooling between bursts.
for(const target of ['shackle','bolts']){
  t=session('grinder',{target,cuts:target==='bolts'?4:1,time:120});s=t.api.state();t.els.pressure.value=50;let cooling=false;
  for(let i=0;i<2400&&s.running&&!s.turning;i++){
    const mark=s.targets[s.index];
    for(const key of ['a','d','q','e'])for(const f of t.events.keyup)f({key});
    const press=key=>{for(const f of t.events.keydown)f({key,preventDefault(){}})};
    if(s.x<mark.x-2)press('d');else if(s.x>mark.x+2)press('a');
    if(s.angle>1)press('q');else if(s.angle<-1)press('e');
    if(s.heat>70)cooling=true;if(s.heat<35)cooling=false;
    s.run=!cooling;t.api.update(.05);
  }
  assert.equal(s.turning,true,`${target} medium failed: ${JSON.stringify(t.results)}`);t.api.update(1.3);assert.equal(t.results[0].success,true);
}
console.log('Grinder load skills: persistent displacement, pressure-dependent drift, angle binding/wear and keyboard correction passed.')
console.log('Drill/grinder: both themes, config bounds, oil, cutting, complete unlock sequence, stress, heat, timeout and duplicate results passed.')

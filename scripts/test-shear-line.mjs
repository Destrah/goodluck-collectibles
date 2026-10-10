import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'
const html=fs.readFileSync('src/minigames/shearLine.html','utf8').replace('/* SHEAR_THEME_RENDERER */',fs.readFileSync('src/minigames/shearThemes.js','utf8'))
const events={},results=[],elements={}
const gradient={addColorStop(){}}
const ctx=new Proxy({measureText:()=>({width:10})},{get:(o,k)=>o[k]??(k.startsWith('create')?()=>gradient:()=>{}),set:(o,k,v)=>(o[k]=v,true)})
function element(id){return elements[id]??=( {style:{},value:0,hidden:false,className:'',textContent:'',addEventListener(){},getContext:()=>ctx,replaceChildren(){},append(){},getBoundingClientRect:()=>({left:0,width:800})})}
const parent={postMessage:r=>results.push(r)}
const window={devicePixelRatio:1,addEventListener:(k,f)=>(events[k]??=[]).push(f),focus(){}}
const sandbox={window,parent,document:{getElementById:element,createElement:()=>element(Math.random())},performance:{now:()=>1000},requestAnimationFrame(){},setTimeout(){},console}
vm.createContext(sandbox)
let script=html.match(/<script>([\s\S]*?)<\/script>/)[1]
script=script.replace(/\}\)\(\);\s*$/,`globalThis.test={state:()=>S,update,endLift,setTension,startLift,binding,finish};})();`)
vm.runInContext(script,sandbox)
const api=sandbox.test
function open(config){for(const f of events.message)f({source:parent,data:{action:'lockpick:open',id:'test',config}})}
open({level:'easy',pins:4,time:50,tol:6,showBand:true})
let state=api.state();assert.equal(state.pins.length,4);assert.equal(state.d.spools,0)
const windowBefore={lo:state.lo,hi:state.hi,base:state.base}
api.setTension((state.lo+state.hi)/2);state.sel=api.binding();const pin=state.pins[state.sel];pin.lift=pin.target;state.lifting=true;api.endLift();assert.equal(pin.set,true)
assert.equal(state.base,windowBefore.base);api.update(1)
assert.equal(state.lo,windowBefore.lo);assert.equal(state.hi,windowBefore.hi)
state.sel=api.binding();const spool=state.pins[state.sel];spool.spool=true;spool.lift=spool.target;state.lifting=true;api.endLift();assert.equal(spool.caught,true);assert.equal(spool.set,false)
state.counterLift=.3;state.lifting=true;api.endLift();assert.equal(spool.set,true)
api.finish(false,'cancel');api.finish(true);assert.equal(results.length,1);assert.equal(results[0].reason,'cancel')
// New isolated iframe session: timeout, snap, turn completion, config clamps.
function fresh(config){vm.runInContext(script,sandbox);open(config);return sandbox.test}
let next=fresh({level:'hard',pins:999,spools:999,band:0});assert.equal(next.state().pins.length,10);assert.equal(next.state().d.spools,9);assert.equal(next.state().d.band,4)
next.state().time=.01;next.update(.02);assert.equal(results.at(-1).reason,'time')
next=fresh({level:'medium'});next.state().strain=100;next.setTension(100);next.update(.02);assert.equal(results.at(-1).broke,true)
next=fresh({level:'easy'});next.state().turning=true;next.state().turn=4.59;next.update(.1);assert.equal(results.at(-1).success,true)
assert.ok(!html.includes('fetch('));assert.ok(!html.includes('fonts.googleapis.com'))
console.log('Shear Line: fixed tension across time/pin sets, pin/spool setting, timeout, snap, turn success, duplicate finish and config bounds passed.')

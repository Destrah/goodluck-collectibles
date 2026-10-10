import assert from 'node:assert/strict'
import fs from 'node:fs'
import {createRequire} from 'node:module'
const require=createRequire(import.meta.url)
const {chromium}=require(process.env.PLAYWRIGHT_PATH || 'C:/Users/troyr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright')
const themes=fs.readFileSync('src/minigames/shearThemes.js','utf8')
const fit=fs.readFileSync('src/minigames/shearFit.js','utf8')
const prepare=doc=>doc.replace('/* SHEAR_THEME_RENDERER */',themes).replace('/* SHEAR_FIT_LAYOUT */',fit)
const html=prepare(fs.readFileSync('src/minigames/shearLine.html','utf8'))
const browser=await chromium.launch({channel:'chrome',headless:true})
try {
  const page=await browser.newPage({viewport:{width:1000,height:900}})
  const errors=[];page.on('pageerror',e=>errors.push(String(e)))
  await page.setContent('<iframe id="game" sandbox="allow-scripts" style="width:880px;height:740px;border:0"></iframe>')
  await page.evaluate(html=>{window.results=[];window.addEventListener('message',e=>{if(e.data?.type==='metacomic:shearResult')results.push(e.data)});document.querySelector('iframe').srcdoc=html},html)
  const game=page.frameLocator('#game')
  await game.locator('#overlay').waitFor({state:'visible'})
  assert.equal(await game.locator('#timeTxt').textContent(),'--')
  await page.evaluate(()=>document.querySelector('iframe').contentWindow.postMessage({action:'lockpick:open',id:'browser',config:{level:'medium',time:50}},'*'))
  await game.locator('#overlay').waitFor({state:'hidden'})
  await game.locator('#timeTxt').filter({hasText:/[0-9]/}).waitFor()
  assert.equal(await game.locator('#band').isVisible(),false)
  assert.equal(await game.locator('#overlay').evaluate(e=>getComputedStyle(e).display),'none')
  await game.locator('#cv').click()
  await page.keyboard.press('Escape')
  await page.waitForFunction(()=>window.results.length===1)
  assert.equal(await page.evaluate(()=>results[0].reason),'cancel')
  await game.locator('#overlay').waitFor({state:'visible'})
  assert.equal(errors.length,0,errors.join('\n'))
  for(const [kind,file] of [['lockpick','shearLine.html'],['drill','shearDrill.html'],['grinder','shearGrinder.html'],['skimmer','shearSkimmer.html']]){
    for(const theme of kind==='skimmer'?['wiring']:kind==='grinder'?['shackle','bolts']:['padlock','camlock']){
      let doc=prepare(fs.readFileSync('src/minigames/'+file,'utf8'))
      if(['lockpick','drill'].includes(kind))doc=doc.replace('resize();', 'window.testSequence=turn=>{S.turning=true;S.turn=turn;draw();};resize();')
      if(kind==='skimmer')doc=doc.replace('resize();','window.wiringState=()=>S;resize();')
      await page.evaluate(doc=>{results=[];document.querySelector('iframe').srcdoc=doc},doc)
      await game.locator('#cv').waitFor()
      await page.evaluate(({kind,theme})=>document.querySelector('iframe').contentWindow.postMessage({action:kind+':open',id:'theme',config:{level:'easy',time:50,theme,target:theme}},'*'),{kind,theme})
      await page.waitForTimeout(150)
      if(['lockpick','drill'].includes(kind))await game.locator('#overlay').waitFor({state:'hidden'})
      const frame=page.frames().find(frame=>frame.parentFrame())
      for(const [width,height] of [[880,740],[640,380],[360,460]]){
        await page.locator('iframe').evaluate((el,{width,height})=>{el.style.width=width+'px';el.style.height=height+'px'},{width,height})
        await page.waitForTimeout(80)
        const layout=await frame.evaluate(()=>{const r=document.querySelector('.wrap').getBoundingClientRect();return {right:r.right,bottom:r.bottom,left:r.left,top:r.top,width:innerWidth,height:innerHeight,scrollWidth:document.documentElement.scrollWidth,scrollHeight:document.documentElement.scrollHeight}})
        assert.ok(layout.right<=layout.width+1 && layout.bottom<=layout.height+1 && layout.left>=-1 && layout.top>=-1,JSON.stringify(layout))
        assert.ok(layout.scrollWidth<=layout.width+1 && layout.scrollHeight<=layout.height+1,JSON.stringify(layout))
      }
      await page.locator('iframe').evaluate(el=>{el.style.width='880px';el.style.height='740px'})
      await page.waitForTimeout(80)
      await page.screenshot({path:`.tmp-shear-${kind}-${theme}.png`})
      if(['lockpick','drill'].includes(kind)){
        for(const turn of [1.8,2.5,3.6]){
          await frame.evaluate(turn=>window.testSequence(turn),turn)
          await page.waitForTimeout(100)
          await page.screenshot({path:`.tmp-shear-${kind}-${theme}-turn-${turn}.png`})
        }
      }
      await game.locator('#cv').click();await page.keyboard.press('Escape')
      await page.waitForFunction(()=>results.length===1)
      assert.equal(await page.evaluate(()=>results[0].reason),'cancel')
      if(kind==='skimmer'){
        await page.evaluate(doc=>{results=[];document.querySelector('iframe').srcdoc=doc},doc)
        await game.locator('#cv').waitFor()
        await page.evaluate(()=>document.querySelector('iframe').contentWindow.postMessage({action:'skimmer:open',id:'play',config:{level:'easy',wires:1,time:100}},'*'))
        const playing=page.frames().find(f=>f.parentFrame())
        await playing.waitForFunction(()=>window.wiringState?.()?.running)
        const plan=await playing.evaluate(()=>{const s=window.wiringState();return {wire:s.order[0],target:s.stripTarget,tol:s.d.stripTol,step:s.d.stripClick,terminal:s.terminals.indexOf(s.order[0])}})
        const point=async(x,y)=>{const r=await game.locator('#cv').boundingBox();return {x:r.x+x*r.width/800,y:r.y+y*r.height/440}}
        const move=async(x,y)=>{const p=await point(x,y);await page.mouse.move(p.x,p.y)}
        const click=async(x,y)=>{const p=await point(x,y);await page.mouse.click(p.x,p.y)}
        const y=137+plan.wire*38,py=137+plan.terminal*38;
        await click(350,y);assert.equal(await playing.evaluate(()=>wiringState().stage),'strip')
        await move(370,y);
        for(let depth=0;depth<plan.target-plan.tol;depth+=plan.step)await click(370,y)
        await move(450,y);assert.equal(await playing.evaluate(()=>wiringState().stage),'place')
        await move(370,y);await page.mouse.down();await move(560,py);await page.mouse.up();
        assert.equal(await playing.evaluate(()=>wiringState().stage),'solder')
        await move(560,py);await page.mouse.down();
        await playing.waitForFunction(()=>wiringState().heat>=wiringState().d.heatLow+1)
        await page.keyboard.down('f');await page.waitForFunction(()=>results.length===1);await page.keyboard.up('f');await page.mouse.up();
        assert.equal(await page.evaluate(()=>results[0].success),true)
      }
    }
  }
  assert.equal(errors.length,0,errors.join('\n'))
  console.log('Browser check passed: waiting timer, hidden running overlay/tension hint, visible result and Escape cancellation.')
} finally {await browser.close()}

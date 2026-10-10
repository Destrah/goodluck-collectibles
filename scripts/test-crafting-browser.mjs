import assert from 'node:assert/strict'
import {createRequire} from 'node:module'
const require=createRequire(import.meta.url)
const {chromium}=require('C:/Users/troyr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright')
const browser=await chromium.launch({channel:'chrome',headless:true})
try{
 const page=await browser.newPage({viewport:{width:1280,height:1080}}),errors=[]
 page.on('pageerror',e=>errors.push(String(e)))
 await page.goto('http://localhost:5180/scripts/crafting-browser-fixture.html')
 await page.waitForFunction(()=>typeof playCraft==='function')
 // Set filtering, broad identity coverage, and all configured prints participate.
 await page.evaluate(async()=>{
  const {loadCraftingPrints}=await import('/src/minigames/craftingPrints.js')
  const {defaultCards}=await import('/src/cardData.js')
  const cards=Array.from({length:100},(_,i)=>({...defaultCards[0],id:`set-card-${i}`,title:`Set Card ${i}`}))
  const sets=[{id:'large',name:'Large set',cardIds:cards.slice(0,90).map(c=>c.id)},{id:'small',name:'Small set',cardIds:cards.slice(90).map(c=>c.id)}]
  const large=await loadCraftingPrints('large',sets,cards),small=await loadCraftingPrints('small',sets,cards)
  if(new Set(large.cards.map(c=>c.id)).size!==90||new Set(small.cards.map(c=>c.id)).size!==10)throw Error('Selected set leaked or identities truncated')
  if(new Set(large.cards.map(c=>c.variantId)).size<2)throw Error('Variants omitted')
  let rejected=false;try{await loadCraftingPrints('missing',sets,cards)}catch{rejected=true}if(!rejected)throw Error('Unknown set fell back')
 })
 // First check the actual React/NUI renderer, not a thumbnail-only test surface.
 await page.evaluate(async()=>{
  const {defaultCards,resolveCardVariant}=await import('/src/cardData.js')
  const cards=Array.from({length:100},(_,i)=>{const c=resolveCardVariant({...defaultCards[0],id:`identity-${i}`,title:`Identity ${i}`},defaultCards[0].variants[0]);return {...c,baseCardId:c.id,id:c.variantId,subjectLayers:[{id:'mask',mode:'foil-electric',image:'data:image/svg+xml,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><circle cx="32" cy="32" r="24" fill="white"/></svg>'),maskSource:'alpha',maskOnly:true,strength:60}]}})
  window.playCraft({id:'react-craft',game:'crafting',cards,cols:5,rows:3,cutter:'bench',time:900,flawChance:0})
 })
 await page.locator('#craft-batch .sheet .trading-card').first().waitFor()
 assert.equal(await page.locator('#craft-batch .sheet .trading-card').count(),15)
 const printCell=await page.locator('#craft-batch .sheet .cell').first().evaluate(el=>({width:el.clientWidth,height:el.clientHeight}));assert(Math.abs(printCell.height/printCell.width-322/230)<.015,'Print sheet cells distort card proportions')
 assert.equal(await page.locator('#craft-batch .sheet').evaluate(el=>new Set([...el.querySelectorAll('[data-print]')].map(c=>c.dataset.print)).size),15,'Shared print IDs collapsed distinct cards')
 const edgeColours=await page.locator('#craft-batch .sheet').evaluate(el=>({stock:getComputedStyle(el).backgroundColor,cards:[...el.querySelectorAll('.trading-card')].map(card=>getComputedStyle(card).borderTopColor)}))
 assert(edgeColours.cards.every(colour=>colour===edgeColours.stock),'Printed borders and gutters differ')
 assert.equal(await page.locator('#craft-batch').evaluate(el=>el.scrollHeight>el.clientHeight+1),false)
 // Drag print stock hard beyond all four edges; its entire sheet stays on the table.
 async function drag(rect,dx,dy){await page.mouse.move(rect.x+rect.width/2,rect.y+rect.height/2);await page.mouse.down();await page.mouse.move(rect.x+rect.width/2+dx,rect.y+rect.height/2+dy,{steps:5});await page.mouse.up()}
 for(const [dx,dy]of [[2000,0],[-2000,0],[0,2000],[0,-2000]]){await drag(await page.locator('#craft-batch .sheet').boundingBox(),dx,dy);const a=await page.locator('#craft-batch .field').boundingBox(),b=await page.locator('#craft-batch .sheet').boundingBox();assert(b.x>=a.x-2&&b.y>=a.y-2&&b.x+b.width<=a.x+a.width+2&&b.y+b.height<=a.y+a.height+2)}
 await page.screenshot({path:'.tmp-crafting-runtime-print.png'})
 // Keep the exact effect/canvas DOM alive through both strip cuts and repeated rotation.
 const rw=page.locator('#craft-batch')
 await rw.getByRole('button',{name:'Rotate left · Q',exact:true}).click({clickCount:3})
 const rs=await rw.locator('.sheet').boundingBox(),rr=await rw.locator('.registration').boundingBox();await drag(rs,rr.x-rs.x,rr.y-rs.y)
 await page.waitForFunction(()=>document.querySelectorAll('#craft-batch .sheet .elemental-mask-fx').length===15)
 await page.evaluate(()=>{window.originalFaces=[...document.querySelectorAll('#craft-batch .sheet [data-face]')].map(el=>({key:el.dataset.face,card:el.querySelector('.trading-card'),mask:el.querySelector('.subject-effect-layer'),canvas:el.querySelector('canvas')}))})
 await rw.getByRole('button',{name:'Print · Enter',exact:true}).click();await rw.getByRole('button',{name:'Accept inspected sheet'}).click()
 async function assertStable(){assert(await page.evaluate(()=>originalFaces.every(face=>{const el=document.querySelector(`#craft-batch [data-face="${face.key}"]`);return el?.querySelector('.trading-card')===face.card&&el?.querySelector('.subject-effect-layer')===face.mask&&el?.querySelector('canvas')===face.canvas&&face.canvas?.width>0})), 'Card mask/canvas remounted or vanished')}
 await assertStable()
 for(const id of [0,5]){const p=rw.locator('.work-piece').filter({has:page.locator(`[data-cut-card="${id}"]`)}),a=await p.locator('.cell').nth(0).boundingBox(),b=await p.locator('.cell').nth(5).boundingBox(),blade=await rw.locator('.blade-grip').boundingBox();await drag(blade,0,(a.y+a.height+b.y)/2-blade.y-blade.height/2);await rw.getByRole('button',{name:'Cut · Space',exact:true}).click();await page.waitForTimeout(240);await assertStable()}
 assert.equal(await rw.locator('.work-piece').count(),3)
 for(const id of [0,5,10]){await rw.locator(`[data-cut-card="${id}"]`).click();for(let i=0;i<4;i++){await rw.getByRole('button',{name:'Rotate right · R',exact:true}).click();await assertStable()}}
 await page.screenshot({path:'.tmp-crafting-stable-masks.png'})

 await page.keyboard.press('Escape');await page.locator('#craft-batch').waitFor({state:'hidden'})
 await page.waitForFunction(()=>window.reactOutcome?.success===false)
 await page.evaluate(()=>stopCraft())
 // Random labels keep the complete sheet stock, rather than choosing a one-card preview.
 await page.evaluate(async()=>{
  const {mountCraftWorkbench}=await import('/src/minigames/craftWorkbench.js')
  document.body.innerHTML='<div id="craft-batch" class="cw-runtime"><div class="shop"></div></div>'
  const cards=Array.from({length:20},(_,i)=>({id:`varied-${i}`,title:`Varied ${i}`,accent:'#22d3ee',layout:'classic'}))
  cards.push({id:'decoy1',title:'Decoy 1',accent:'#ff0000',layout:'classic'},{id:'decoy2',title:'Decoy 2',accent:'#00ff00',layout:'classic'})
  const random=Math.random;Math.random=()=>0
  try{window.disposeLabelTest=mountCraftWorkbench(document.querySelector('#craft-batch'),{cols:5,rows:3,cutter:'bench',time:900,flawChance:0,cards},()=>{})}finally{Math.random=random}
 })
 assert((await page.locator('#craft-batch .hint').textContent()).includes('Requested: Sheet C'))
 await page.locator('#craft-batch [data-job="2"]').click()
 assert.equal(await page.locator('#craft-batch .sheet').evaluate(el=>new Set([...el.querySelectorAll('[data-print]')].map(c=>c.dataset.print)).size),15,'Random label selected a decoy pool')
 await page.evaluate(()=>disposeLabelTest())
 // Exercise the same engine directly to inspect its completion report and disposal.
 for(const kind of ['bench','industrial']){
  await page.evaluate(async kind=>{
   const {mountCraftWorkbench}=await import('/src/minigames/craftWorkbench.js')
   document.body.innerHTML='<div class="mg-card mg-crafting-card"><div id="craft-batch" class="cw-runtime"><div class="shop"></div></div></div>'
   window.outcomes=[];window.disposeCraft=mountCraftWorkbench(document.querySelector('#craft-batch'),{cutter:kind,cols:5,rows:3,flawChance:0,time:900,cards:[{title:'Teal',accent:'#22d3ee',layout:'classic'},{title:'Teal second',accent:'#22d3ee',layout:'classic'}]},(success,details)=>outcomes.push({success,details}))
  },kind)
  const w=page.locator('#craft-batch'),field=w.locator('.field')
  await w.getByRole('button',{name:'Rotate left · Q',exact:true}).click({clickCount:3})
  const sheet=await w.locator('.sheet').boundingBox(),reg=await w.locator('.registration').boundingBox();await drag(sheet,reg.x-sheet.x,reg.y-sheet.y)
  await w.getByRole('button',{name:'Print · Enter',exact:true}).click();await w.getByRole('button',{name:'Accept inspected sheet'}).waitFor();await w.getByRole('button',{name:'Accept inspected sheet'}).click()
  async function cycle(){if(kind==='industrial'){await w.getByRole('button',{name:'Clamp · C',exact:true}).click();await w.getByRole('button',{name:'Cut · Q + E',exact:true}).click()}else await w.getByRole('button',{name:'Cut · Space',exact:true}).click();await page.waitForTimeout(740)}
  async function aim(a,b,p){const box=await field.boundingBox(),y=(a.y+a.height+b.y)/2;if(kind==='industrial')await drag(await p.boundingBox(),0,box.y+box.height*.39-y);else{const blade=await w.locator('.blade-grip').boundingBox();await drag(blade,0,y-blade.y-blade.height/2)}}
  let p=w.locator('.work-piece').first();await aim(await p.locator('.cell').nth(0).boundingBox(),await p.locator('.cell').nth(5).boundingBox(),p);await cycle()
  p=w.locator('.work-piece').filter({has:page.locator('[data-cut-card="5"]')});await aim(await p.locator('.cell').nth(0).boundingBox(),await p.locator('.cell').nth(5).boundingBox(),p);await cycle();assert.equal(await w.locator('.work-piece').count(),3)
  const box=await field.boundingBox(),line=box.y+box.height*.39
  for(const row of [2,1,0]){const p=w.locator('.work-piece').filter({has:page.locator(`[data-cut-card="${row*5}"]`)});await p.locator('.cell').first().click();await w.getByRole('button',{name:'Rotate right · R',exact:true}).click();const b=await p.boundingBox();await drag(b,box.x+box.width*(.2+row*.3)-b.x-b.width/2,box.y+box.height*.5-b.y-b.height/2)}
  if(kind==='bench'){const b=await w.locator('.blade-grip').boundingBox();await drag(b,0,line-b.y-b.height/2)}
  for(let step=0;step<4;step++){for(let row=0;row<3;row++){const p=w.locator('.work-piece').filter({has:page.locator(`[data-cut-card="${row*5+step}"]`)}),a=await p.locator('.cell').nth(0).boundingBox(),b=await p.locator('.cell').nth(1).boundingBox();await drag(await p.boundingBox(),0,line-(a.y+a.height+b.y)/2)}await cycle()}
  assert.equal(await w.locator('.work-piece.single').count(),15,await w.locator('.status').textContent())
  // Boundary enforcement includes rotated cut pieces.
  const single=await w.locator('.work-piece.single').first().boundingBox();assert(Math.abs(single.width/single.height-322/230)<.015,'Rotated cut card retains stock margin');await drag(single,-2000,-2000);const bounded=await w.locator('.work-piece.single').first().boundingBox();assert(bounded.x>=box.x-1&&bounded.y>=box.y-1)
  await w.getByRole('button',{name:'Grab an empty pack',exact:true}).click()
  assert.equal(await w.locator('.bench-empty>.back').isVisible(),false)
  assert.equal(await w.locator('.foil-inside').count(),2)
  assert.equal(await w.locator('.foil-outside').count(),2)
  await page.screenshot({path:`.tmp-crafting-${kind}-wrapper.png`})
  for(let pack=0;pack<3;pack++){
   if(pack)await w.getByRole('button',{name:'Grab empty pack',exact:true}).click()
   let b=await w.locator('.bench-empty').boundingBox();await drag(b,box.x+box.width*.82-b.x-b.width/2,box.y+box.height*.72-b.y-b.height/2)
   for(let i=0;i<5;i++){const b=await w.locator('.work-piece.single .cell').first().boundingBox(),t=await w.locator('.bench-empty').boundingBox();await drag(b,t.x+t.width/2-b.x-b.width/2,t.y+t.height/2-b.y-b.height/2)}
   assert((await w.locator('.bench-count').textContent()).includes('5 / 5'))
   await w.getByRole('button',{name:'Fold & place pack'}).click();if(pack===0){await page.waitForTimeout(350);await page.screenshot({path:`.tmp-crafting-${kind}-fold.png`})}await page.waitForTimeout(1300)
   b=await w.locator(`[data-pack="${pack}"]`).boundingBox();await drag(b,box.x+box.width*.12-b.x-b.width/2,box.y+box.height*(.18+pack*.29)-b.y-b.height/2)
  }
  await w.getByRole('button',{name:'Grab sealer',exact:true}).click()
  for(let pack=0;pack<3;pack++){const b=await w.locator('.bench-tool').boundingBox(),p=await w.locator(`[data-pack="${pack}"]`).boundingBox();await drag(b,p.x+p.width/2-b.x-b.width/2,p.y+p.height/2-b.y-b.height/2);await page.keyboard.down(' ');await page.waitForTimeout(650);assert.equal(await w.locator('.bench-tool').evaluate(el=>el.classList.contains('ready')),false);const fill=await w.locator('.bench-tool').evaluate(el=>parseFloat(el.style.getPropertyValue('--heat-fill')));assert(fill>30&&fill<80,'Heater fill does not follow hold duration');await page.waitForTimeout(700);assert.equal(await w.locator('.bench-tool').evaluate(el=>el.classList.contains('ready')),true);assert.equal(await w.locator('.bench-tool').evaluate(el=>el.style.getPropertyValue('--heat-fill')),'100%');await page.keyboard.up(' ');await page.waitForTimeout(1250)}
  const result=await page.evaluate(()=>outcomes);assert.equal(result.length,1);assert.equal(result[0].success,true);assert.equal(result[0].details.cuts,14);assert.equal(result[0].details.errors,0);assert.equal(result[0].details.packs,3)
  await page.evaluate(()=>disposeCraft())
 }
 // Draft production has an independent set picker, without changing the recipe's output.
 await page.goto('http://localhost:5180/scripts/crafting-browser-fixture.html')
 await page.waitForFunction(()=>typeof showCraftAdmin==='function')
 await page.evaluate(async()=>{
  const {defaultCards}=await import('/src/cardData.js')
  const cards=defaultCards.slice(0,4)
  showCraftAdmin([{id:'base',name:'Base Set',cardIds:[cards[0].id]},{id:'chosen',name:'Chosen Set',cardIds:cards.slice(1).map(c=>c.id)}],cards)
 })
 await page.getByLabel('Print, inspect, cut, fold and seal instead of a progress bar').check()
 await page.getByLabel('Test production card set').selectOption('chosen')
 await page.getByRole('button',{name:'Test draft production · no rewards'}).click()
 await page.locator('#craft-batch .summary').waitFor()
 assert((await page.locator('#craft-batch .summary').textContent()).includes('Chosen Set'))
 await page.keyboard.press('Escape')
 await page.locator('#craft-batch').waitFor({state:'detached'})
 assert.equal(errors.length,0,errors.join('\n'));console.log('Runtime card rendering, sheet/piece boundaries, silver lining and printed wing faces, both full 15-card workflows, exact completion metrics, Escape, and teardown passed.')
}finally{await browser.close()}

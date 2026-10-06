import { createServer } from '../node_modules/vite/dist/node/index.js'
import { chromium } from 'file:///C:/Users/troyr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs'
import { mkdir } from 'node:fs/promises'
import { resolve } from 'node:path'
const server = await createServer({server:{host:'127.0.0.1',port:5179,strictPort:true}})
await server.listen()
let browser
try {
  browser = await chromium.launch({headless:true,channel:'msedge',args:['--enable-unsafe-swiftshader']})
  const page = await browser.newPage({viewport:{width:800,height:500},deviceScaleFactor:1})
  page.on('pageerror',err => console.error('PAGE ERROR:',err.message))
  await page.goto('http://127.0.0.1:5179/.readme-capture/index.html')
  await page.waitForFunction(() => window.demoReady)
  const demos = process.argv.slice(2).length ? process.argv.slice(2) : ['coin-opening','plushie-opening','case-opening','container-viewing','collectible-viewing','card-viewing','pack-opening']
  for (const name of demos) {
    await page.reload();await page.waitForFunction(() => window.demoReady)
    await page.evaluate(name => window.showDemo(name),name)
    const dir=resolve('.readme-capture/frames',name);await mkdir(dir,{recursive:true})
    console.log('Capturing',name)
    if (['coin-opening','plushie-opening','case-opening','container-viewing'].includes(name)) {
      for (let i=0;i<80;i++) {
        await page.evaluate(({t,reveal}) => window.seekDemo(t,reveal),{t:i*.1,reveal:i===58 && name!=='case-opening' && name!=='container-viewing'})
        await page.screenshot({path:resolve(dir,`${String(i).padStart(3,'0')}.png`)})
      }
    } else {
      await page.waitForTimeout(name==='pack-opening'?100:1800)
      let flipped=false
      for (let i=0;i<90;i++) {
        const started=Date.now()
        if (name==='pack-opening') {
          const flip=page.getByRole('button',{name:/Flip all/})
          if (!flipped && await flip.isEnabled().catch(()=>false)) {await flip.click({timeout:1000}).catch(()=>{});flipped=true}
        } else {
          const stages = name==='card-viewing' ? page.locator('.collectible-rotation-stage') : page.locator('.collectible-3d-canvas')
          if (i===8) {
            const box=await stages.first().boundingBox();await page.mouse.move(box.x+box.width*.35,box.y+box.height*.5);await page.mouse.down()
          }
          if (i>=8 && i<=63) {
            const box=await stages.first().boundingBox();await page.mouse.move(box.x+box.width*.35+(i-8)*8,box.y+box.height*.5+Math.sin(i*.1)*25)
          }
          if (i===64) await page.mouse.up()
          if (name==='collectible-viewing' && i%10===0) await page.getByRole('button',{name:'Rotate right'}).nth(1).click()
          if (i===80) await page.getByRole('button',{name:'Reset view'}).first().click()
        }
        await page.screenshot({path:resolve(dir,`${String(i).padStart(3,'0')}.png`)})
        await page.waitForTimeout(Math.max(0,100-(Date.now()-started)))
      }
    }
    console.log('Done',name)
  }
} finally {await browser?.close();await server.close()}

import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import http from 'node:http'
import {createRequire} from 'node:module'
const require=createRequire(import.meta.url)
const {chromium}=require('C:/Users/troyr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright')
const root=path.resolve('dist')
const server=http.createServer((req,res)=>{const file=path.resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!file.startsWith(root+path.sep)&&file!==root){res.writeHead(403).end();return}const target=file===root?path.join(root,'index.html'):file;try{res.setHeader('Content-Type',target.endsWith('.js')?'text/javascript':target.endsWith('.css')?'text/css':target.endsWith('.html')?'text/html':'application/octet-stream');res.end(fs.readFileSync(target))}catch{res.writeHead(404).end()}})
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve))
const browser=await chromium.launch({channel:'chrome',headless:true,timeout:20000})
try{
 const page=await browser.newPage({viewport:{width:1440,height:1000}})
 page.setDefaultTimeout(8000)
 const errors=[];page.on('pageerror',e=>errors.push(String(e)))
 await page.goto(`http://127.0.0.1:${server.address().port}/`)
 await page.getByRole('button',{name:'Minigames',exact:true}).click()
 await page.locator('.mgt-preset').filter({hasText:'skimmer_medium'}).waitFor()
 assert.equal(await page.locator('.mgt-preset').filter({hasText:'wires_'}).count(),0)
 for(const level of ['easy','medium','hard']){
  await page.locator('.mgt-preset').filter({hasText:`skimmer_${level}`}).getByRole('button',{name:'Test',exact:true}).click()
  const frame=page.frameLocator('iframe')
  await frame.locator('#overlay').waitFor({state:'hidden'})
  await frame.locator('#cv').waitFor({state:'visible'})
  await frame.locator('#cv').click({position:{x:8,y:8}})
  await page.keyboard.press('Escape')
  await page.locator('iframe').waitFor({state:'detached'})
 }
 assert.deepEqual(errors,[])
 console.log('Standalone menu: all three skimmer presets render and cancel; obsolete presets absent; no JavaScript errors.')
}finally{await browser.close();server.closeAllConnections();await new Promise(resolve=>server.close(resolve))}

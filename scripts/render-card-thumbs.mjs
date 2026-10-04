/**
 * Renders every card print in fivem/data/catalog.json to a PNG, for inventory icons that look like the real card.
 *
 *   npm run cards:thumbs                                   -> public/img/cards + fivem/img/cards (+ index.json)
 *   npm run cards:thumbs -- --ox "C:/server/resources/[ox]/ox_inventory/web/images"
 *                                                          -> also copies them into ox_inventory as rushcard_<name>.png
 *   options: --skip-build (reuse the last render build), --catalog <file>
 *
 * Needs the dev dependency playwright-core. It drives Microsoft Edge (installed on every Windows 10/11 PC) or Chrome,
 * so no extra browser download is needed. Run it again whenever you add or change cards, then `npm run build:fivem`.
 */
import { readFile, writeFile, mkdir, copyFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { createServer } from 'node:http'
import { resolve, extname, join } from 'node:path'
import { spawnSync } from 'node:child_process'

const root = process.cwd()
const args = process.argv.slice(2)
const arg = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined }
const catalogFile = resolve(root, arg('--catalog') || 'fivem/data/catalog.json')
const oxDir = arg('--ox')
const buildDir = resolve(root, '.card-thumbs-build')
const outDirs = [resolve(root, 'public/img/cards'), resolve(root, 'fivem/img/cards')]
const STORAGE_KEY = 'rush-tradingcards-react-v3' // src/runtime/storage/standalone.js

export const thumbName = key => key.replace(/::/g, '__').replace(/[^a-zA-Z0-9_-]+/g, '-').toLowerCase()

const catalog = JSON.parse(await readFile(catalogFile, 'utf8'))
console.log(`Catalog: ${catalog.length} cards from ${catalogFile}`)

// 1) standalone build of the app (separate folder, so dist/ and fivem/web are untouched)
if (!args.includes('--skip-build') || !existsSync(join(buildDir, 'index.html'))) {
  const npx = process.platform === 'win32' ? 'npx.cmd' : 'npx'
  const r = spawnSync(npx, ['vite', 'build', '--outDir', buildDir, '--emptyOutDir'], { stdio: 'inherit', shell: process.platform === 'win32' })
  if (r.status !== 0) process.exit(r.status || 1)
}

// 2) tiny static server for the build (+ public/img for card art)
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.json': 'application/json', '.glb': 'model/gltf-binary' }
const server = createServer(async (req, res) => {
  const path = decodeURIComponent(new URL(req.url, 'http://x').pathname)
  for (const base of [buildDir, resolve(root, 'public')]) {
    const file = join(base, path === '/' ? 'index.html' : path)
    if (file.startsWith(base) && existsSync(file) && !file.endsWith('/')) {
      try {
        res.writeHead(200, { 'Content-Type': types[extname(file).toLowerCase()] || 'application/octet-stream' })
        res.end(await readFile(file))
        return
      } catch { /* directory: fall through */ }
    }
  }
  res.writeHead(200, { 'Content-Type': 'text/html' })
  res.end(await readFile(join(buildDir, 'index.html')))
})
await new Promise(r => server.listen(0, '127.0.0.1', r))
const url = `http://127.0.0.1:${server.address().port}/`

// 3) browser: Edge, then Chrome, then a Playwright-installed Chromium
let pw
try { pw = await import('playwright-core') } catch { pw = await import('playwright') }
let browser
for (const channel of ['msedge', 'chrome', undefined]) {
  try { browser = await pw.chromium.launch(channel ? { channel } : {}); console.log(`Browser: ${channel || 'chromium'}`); break } catch { /* try next */ }
}
if (!browser) { console.error('No Edge / Chrome found. Install Chrome, or run: npx playwright install chromium'); process.exit(1) }

const page = await browser.newPage({ viewport: { width: 1400, height: 1000 }, deviceScaleFactor: 1 }) // 230x322 icons: plenty for inventory slots
await page.addInitScript(([key, cards]) => { try { localStorage.setItem(key, JSON.stringify(cards)) } catch {} }, [STORAGE_KEY, catalog])
await page.goto(url)
await page.getByRole('button', { name: 'Print collection' }).click()
await page.addStyleTag({ content: 'html,body,#root,.app-shell,.gallery-grid,.gallery-item{background:transparent!important;box-shadow:none!important} .trading-card{transition:none!important}' })
await page.waitForSelector('[data-print-key]')

for (const dir of outDirs) await mkdir(dir, { recursive: true })
if (oxDir) await mkdir(oxDir, { recursive: true })

const index = {}
const items = page.locator('[data-print-key]')
const total = await items.count()
for (let i = 0; i < total; i++) {
  const item = items.nth(i)
  const key = await item.getAttribute('data-print-key')
  await item.scrollIntoViewIfNeeded()
  const card = item.locator('.trading-card')
  await card.waitFor()
  await page.mouse.move(0, 0)
  await card.evaluate(el => Promise.all([...el.querySelectorAll('img')].map(img => img.complete ? null : new Promise(r => { img.onload = img.onerror = r }))))
  await page.waitForTimeout(150)
  const name = thumbName(key)
  const png = await card.screenshot({ omitBackground: true, animations: 'disabled' })
  for (const dir of outDirs) await writeFile(join(dir, `${name}.png`), png)
  if (oxDir) await writeFile(join(oxDir, `rushcard_${name}.png`), png)
  index[key] = name
  process.stdout.write(`\r${i + 1}/${total} ${key}`.padEnd(70))
}
for (const dir of outDirs) await writeFile(join(dir, 'index.json'), JSON.stringify(index, null, 1))
console.log(`\nWrote ${total} card thumbnails to public/img/cards and fivem/img/cards${oxDir ? ` and ${oxDir}` : ''}.`)

await browser.close()
server.close()

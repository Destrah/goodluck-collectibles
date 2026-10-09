/**
 * Three.js shipping crate reveal (FiveM shipping_crate item), lazy-loaded like Container3D.
 *
 * createCrateScene(canvas, { animation: 'lid'|'panels'|'pry'|'straps'|'random', items, serial, label, onReveal })
 *   -> { animation, play() => Promise, skip(), dispose() }
 *
 * items: [{ label, type, kind, collectible, outer, count }] as the server gave them. Each item rises out of the crate
 * and lands in a row in front of it; onReveal(index) fires as each one lands.
 */
import * as THREE from 'three'
import { buildBoosterBox, loadBoxArt } from './BoosterBox3D.js'
import { normalizeLook } from './container3dOptions'

export const CRATE_ANIMATIONS = ['lid', 'panels', 'pry', 'straps']

const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v))
const lerp = (a, b, k) => a + (b - a) * k
const ss = (a, b, t) => { const k = clamp((t - a) / (b - a)); return k * k * (3 - 2 * k) }
const outBack = (k, c = 1.7) => 1 + (c + 1) * Math.pow(k - 1, 3) + c * Math.pow(k - 1, 2)
const outBounce = k => {
  const n = 7.5625, d = 2.75
  if (k < 1 / d) return n * k * k
  if (k < 2 / d) return n * (k -= 1.5 / d) * k + 0.75
  if (k < 2.5 / d) return n * (k -= 2.25 / d) * k + 0.9375
  return n * (k -= 2.625 / d) * k + 0.984375
}

// crate size (metres-ish): width x height x depth
const W = 1.7, H = 1.0, D = 1.05, T = 0.06
// when the crate is open (seconds), per animation
const OPEN_AT = { lid: 2.3, panels: 2.5, pry: 2.9, straps: 2.6 }
const ITEM_FLIGHT = 1.1, ITEM_STAGGER = 0.38

/* ------------------------------------------------------------------ textures */

const makeCanvas = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h; return [c, c.getContext('2d')] }
const texture = canvas => { const t = new THREE.CanvasTexture(canvas); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4; return t }

function woodTexture(w, h, { boards = 4, vertical = false, stencil, sub } = {}) {
  const [c, g] = makeCanvas(w, h)
  const along = vertical ? h : w, across = vertical ? w : h
  const size = across / boards
  for (let i = 0; i < boards; i++) {
    const tone = 0.85 + Math.random() * 0.25
    g.fillStyle = `rgb(${Math.round(150 * tone)},${Math.round(104 * tone)},${Math.round(58 * tone)})`
    if (vertical) g.fillRect(i * size, 0, size, along); else g.fillRect(0, i * size, along, size)
    g.strokeStyle = 'rgba(70,40,15,0.35)'; g.lineWidth = 1.2
    for (let k = 0; k < 9; k++) { // grain
      const o = i * size + Math.random() * size
      g.beginPath()
      for (let p = 0; p <= along; p += along / 12) {
        const q = o + Math.sin(p / (40 + k * 7) + k) * 3
        if (vertical) g.lineTo(q, p); else g.lineTo(p, q)
      }
      g.stroke()
    }
    g.fillStyle = 'rgba(30,15,5,0.75)' // gap between boards
    if (vertical) g.fillRect(i * size, 0, 3, along); else g.fillRect(0, i * size, along, 3)
    g.fillStyle = '#3b3b40' // nail heads
    for (const p of [along * 0.06, along * 0.94]) {
      g.beginPath()
      if (vertical) g.arc(i * size + size / 2, p, 4, 0, Math.PI * 2); else g.arc(p, i * size + size / 2, 4, 0, Math.PI * 2)
      g.fill()
    }
  }
  if (stencil) {
    g.save(); g.translate(w / 2, h / 2); g.rotate(-0.02)
    g.font = `bold ${Math.round(h * 0.2)}px Impact, "Arial Black", sans-serif`; g.textAlign = 'center'; g.textBaseline = 'middle'
    g.fillStyle = 'rgba(25,20,18,0.78)'; g.fillText(stencil, 0, sub ? -h * 0.07 : 0)
    if (sub) { g.font = `bold ${Math.round(h * 0.09)}px "Courier New", monospace`; g.fillText(sub, 0, h * 0.16) }
    g.restore()
  }
  return texture(c)
}

const ITEM_STYLE = {
  box: { colors: ['#c41fa8', '#4a0f63'], text: 'BOOSTER BOX', size: [0.5, 0.22, 0.41] }, // prop_boosterbox_01 proportions
  pack: { colors: ['#ff2bd6', '#1b1030'], text: 'BOOSTER', size: [0.22, 0.34, 0.04] },
  plushie: { colors: ['#ff8fcf', '#8a2a6a'], text: 'PLUSHIE', size: [0.48, 0.52, 0.42] },
  plushieCase: { colors: ['#b0814f', '#5a3a1c'], text: 'PLUSHIE CASE', size: [0.72, 0.52, 0.52] },
  coin: { colors: ['#ffd23c', '#7a4f00'], text: 'COINS', size: [0.38, 0.42, 0.38], bag: true },
  coinCase: { colors: ['#b0814f', '#5a3a1c'], text: 'COIN BAG BOX', size: [0.72, 0.5, 0.52] },
  item: { colors: ['#4df3ff', '#0e3140'], text: '', size: [0.32, 0.22, 0.22] },
}
export function itemStyleKey(item = {}) {
  if (item.type === 'sealed') return item.kind === 'box' ? 'box' : 'pack'
  if (item.type === 'container' && item.collectible === 'plushie') return item.outer ? 'plushieCase' : 'plushie'
  if (item.type === 'container' && item.collectible === 'challenge_coin') return item.outer ? 'coinCase' : 'coin'
  return 'item'
}

function labelTexture(style, label) {
  const [c, g] = makeCanvas(256, 256)
  const grad = g.createLinearGradient(0, 0, 256, 256)
  grad.addColorStop(0, style.colors[0]); grad.addColorStop(1, style.colors[1])
  g.fillStyle = grad; g.fillRect(0, 0, 256, 256)
  g.strokeStyle = 'rgba(255,255,255,0.35)'; g.lineWidth = 8; g.strokeRect(10, 10, 236, 236)
  g.fillStyle = '#fff'; g.textAlign = 'center'; g.textBaseline = 'middle'
  g.font = 'bold 30px Impact, "Arial Black", sans-serif'
  const words = (style.text || label || '').split(' ')
  words.forEach((word, i) => g.fillText(word, 128, 128 + (i - (words.length - 1) / 2) * 36))
  return texture(c)
}

/* ------------------------------------------------------------------ scene */

export async function createCrateScene(canvas, options = {}) {
  const items = Array.isArray(options.items) ? options.items : []
  const animation = CRATE_ANIMATIONS.includes(options.animation) ? options.animation : CRATE_ANIMATIONS[Math.floor(Math.random() * CRATE_ANIMATIONS.length)]
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true })
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2))
  renderer.outputColorSpace = THREE.SRGBColorSpace
  renderer.shadowMap.enabled = true
  const scene = new THREE.Scene()
  const camera = new THREE.PerspectiveCamera(38, 1, 0.1, 50)
  const disposables = []
  const keep = thing => { disposables.push(thing); return thing }

  scene.add(new THREE.HemisphereLight(0xfff4e0, 0x2a2030, 1.1))
  const sun = new THREE.DirectionalLight(0xffffff, 2.2)
  sun.position.set(2.5, 5, 3.5); sun.castShadow = true; sun.shadow.mapSize.set(1024, 1024)
  scene.add(sun)
  const glow = new THREE.PointLight(0xffc870, 0, 6)
  glow.position.set(0, H * 0.8, 0)
  scene.add(glow)

  const floor = new THREE.Mesh(keep(new THREE.CircleGeometry(6, 48)), keep(new THREE.ShadowMaterial({ opacity: 0.35 })))
  floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true
  scene.add(floor)

  /* crate: each panel is a group pivoting on the edge it swings or hinges around */
  const crate = new THREE.Group()
  scene.add(crate)
  const panelMat = (w, h, opts) => keep(new THREE.MeshStandardMaterial({ map: keep(woodTexture(w, h, opts)), roughness: 0.85 }))
  const serial = String(options.serial || '')
  const sideMat = panelMat(512, 300, { boards: 4, stencil: 'META COMICS', sub: serial ? `FRAGILE · ${serial}` : 'FRAGILE · THIS SIDE UP' })
  const endMat = panelMat(320, 300, { boards: 4, vertical: true, stencil: '▲▲' })
  const topMat = panelMat(512, 320, { boards: 5, stencil: options.label ? String(options.label).toUpperCase().slice(0, 22) : 'SHIPPING CRATE' })
  const plain = panelMat(256, 256, { boards: 4 })
  const steel = keep(new THREE.MeshStandardMaterial({ color: 0x3d4148, metalness: 0.85, roughness: 0.35 }))
  const inside = keep(new THREE.MeshStandardMaterial({ color: 0x3a2412, roughness: 1 }))

  const slab = (w, h, d, mat) => {
    const geo = keep(new THREE.BoxGeometry(w, h, d))
    const mesh = new THREE.Mesh(geo, [plain, plain, plain, plain, mat, inside])
    mesh.castShadow = true; mesh.receiveShadow = true
    return mesh
  }
  // pivot at the bottom edge of each wall so 'panels' can let them fall outward
  const wall = (w, mat, x, z, rotY) => {
    const pivot = new THREE.Group()
    pivot.position.set(x, 0, z); pivot.rotation.y = rotY
    const mesh = slab(w, H, T, mat); mesh.position.set(0, H / 2, 0)
    pivot.add(mesh); crate.add(pivot)
    return pivot
  }
  const front = wall(W, sideMat, 0, D / 2 - T / 2, 0)
  const back = wall(W, sideMat, 0, -D / 2 + T / 2, Math.PI)
  const left = wall(D - T * 2, endMat, -W / 2 + T / 2, 0, -Math.PI / 2)
  const right = wall(D - T * 2, endMat, W / 2 - T / 2, 0, Math.PI / 2)
  const walls = [front, back, left, right]
  const base = slab(W, T, D, plain); base.position.y = T / 2; crate.add(base)

  // lid hinged at the back edge ('pry' swings it open there)
  const lidPivot = new THREE.Group()
  lidPivot.position.set(0, H, -D / 2)
  const lid = new THREE.Mesh(keep(new THREE.BoxGeometry(W + 0.04, T, D + 0.04)), [plain, plain, topMat, inside, plain, plain])
  lid.position.set(0, T / 2, D / 2); lid.castShadow = true
  lidPivot.add(lid); crate.add(lidPivot)

  // steel corner brackets ride on the walls
  for (const pivot of walls) {
    for (const side of [-1, 1]) {
      const w = pivot === left || pivot === right ? D - T * 2 : W
      const bracket = new THREE.Mesh(keep(new THREE.BoxGeometry(0.12, H * 0.98, 0.012)), steel)
      bracket.position.set(side * (w / 2 - 0.06), H / 2, T / 2 + 0.006)
      pivot.add(bracket)
    }
  }
  // two steel straps over the lid ('straps' snaps them)
  const straps = [-0.45, 0.45].map(x => {
    const group = new THREE.Group()
    const top = new THREE.Mesh(keep(new THREE.BoxGeometry(0.07, 0.012, D + 0.1)), steel); top.position.y = H + T + 0.006
    const f = new THREE.Mesh(keep(new THREE.BoxGeometry(0.07, H + T, 0.012)), steel); f.position.set(0, (H + T) / 2, D / 2 + 0.05)
    const b = f.clone(); b.position.z = -D / 2 - 0.05
    group.add(top, f, b); group.position.x = x
    crate.add(group)
    return group
  })
  const crowbar = new THREE.Group()
  const bar = new THREE.Mesh(keep(new THREE.CylinderGeometry(0.018, 0.018, 0.9, 10)), keep(new THREE.MeshStandardMaterial({ color: 0xb3141b, metalness: 0.6, roughness: 0.4 })))
  bar.rotation.z = Math.PI / 2; bar.position.x = 0.45
  crowbar.add(bar); crowbar.visible = false
  scene.add(crowbar)

  /* the contents, hidden inside until they fly out. Booster boxes are the in-game box (prop_boosterbox_01); plushie
     boxes, coin bags and their cases are the same 3D models their own openings use (Container3D.js) */
  const boxArt = items.some(item => itemStyleKey(item) === 'box') ? await loadBoxArt(keep).catch(() => null) : null
  let models = null
  if (items.some(item => item.type === 'container')) {
    try { models = keep(await (await import('./Container3D.js')).createContainerModels()) } catch (error) { console.warn('Shipping crate: container models unavailable', error) }
  }
  const modelCache = new Map()
  const containerModel = item => {
    if (!models) return null
    const kind = item.outer ? 'case' : item.containerKind === 'bag' || (!item.containerKind && item.collectible === 'challenge_coin') ? 'bag' : 'box'
    const style = normalizeLook(kind, item.look).style
    const innerLabel = item.innerLabel || (item.collectible === 'challenge_coin' ? 'Coin Bag' : 'Plushie Box')
    const cacheKey = [kind, style, innerLabel, item.caseCount || ''].join(':')
    if (!modelCache.has(cacheKey)) modelCache.set(cacheKey, models.build(kind === 'bag' ? 'bag' : 'box', style, { count: item.caseCount, innerLabel }).root)
    return modelCache.get(cacheKey).clone(true)
  }
  // centre a model on the origin and scale it into the item's slot (glow planes and other effects don't count)
  const fitted = (model, [w, h, d]) => {
    model.updateMatrixWorld(true)
    const bounds = new THREE.Box3()
    model.traverse(o => { if (o.isMesh && o.visible && !o.material?.isShaderMaterial && !(o.material?.transparent && o.material.opacity < 0.5)) bounds.expandByObject(o) })
    const size = bounds.getSize(new THREE.Vector3()), centre = bounds.getCenter(new THREE.Vector3())
    const scale = Math.min(w / Math.max(size.x, 1e-3), h / Math.max(size.y, 1e-3), d / Math.max(size.z, 1e-3))
    model.scale.multiplyScalar(scale); model.position.sub(centre.multiplyScalar(scale))
    const group = new THREE.Group(); group.add(model)
    group.traverse(o => { if (o.isMesh && !o.material?.isShaderMaterial) o.castShadow = true })
    return { group, height: size.y * scale }
  }
  const landing = (i, n) => {
    const spread = Math.min(2.6, 0.62 * (n - 1))
    const x = n === 1 ? 0 : lerp(-spread / 2, spread / 2, i / (n - 1))
    return new THREE.Vector3(x, 0, D / 2 + 0.75 + Math.abs(x) * -0.12)
  }
  const itemMeshes = items.map((item, i) => {
    const style = ITEM_STYLE[itemStyleKey(item)]
    const [w, , d] = style.size
    let h = style.size[1], mesh
    const model = itemStyleKey(item) === 'box' ? buildBoosterBox(boxArt, keep).root : item.type === 'container' ? containerModel(item) : null
    if (model) {
      const fit = fitted(model, style.size)
      mesh = fit.group; h = fit.height
    } else {
      const mat = keep(new THREE.MeshStandardMaterial({ map: keep(labelTexture(style, item.label)), roughness: 0.5, metalness: 0.05 }))
      const geo = keep(style.bag ? new THREE.SphereGeometry(w / 2, 24, 16) : new THREE.BoxGeometry(w, h, d))
      mesh = new THREE.Mesh(geo, mat)
      if (style.bag) mesh.scale.set(1, h / w * 1.2, 1)
      mesh.castShadow = true
    }
    mesh.userData = { from: new THREE.Vector3((i % 3 - 1) * 0.35, H * 0.35, (Math.floor(i / 3) % 2 ? -0.15 : 0.15)), to: landing(i, items.length).setY(h / 2), height: h, spin: (i % 2 ? 1 : -1) * Math.PI * 2 }
    mesh.position.copy(mesh.userData.from); mesh.visible = false
    scene.add(mesh)
    return mesh
  })

  /* dust / splinters burst when it opens */
  const DUST = 160
  const dustGeo = keep(new THREE.BufferGeometry())
  const dustPos = new Float32Array(DUST * 3), dustVel = []
  for (let i = 0; i < DUST; i++) dustVel.push(new THREE.Vector3((Math.random() - 0.5) * 2.4, Math.random() * 2.2 + 0.4, (Math.random() - 0.5) * 2.4))
  dustGeo.setAttribute('position', new THREE.BufferAttribute(dustPos, 3))
  const dustMat = keep(new THREE.PointsMaterial({ color: 0xd9b98a, size: 0.035, transparent: true, opacity: 0 }))
  scene.add(new THREE.Points(dustGeo, dustMat))

  const openAt = OPEN_AT[animation]
  const total = openAt + 0.3 + items.length * ITEM_STAGGER + ITEM_FLIGHT + 0.6
  let start = 0, frame = 0, finished, done = false, disposed = false
  const revealed = new Set()

  function pose(t) {
    // drop in and settle
    const drop = clamp(t / 0.7)
    crate.position.y = (1 - outBounce(drop)) * 1.8
    crate.rotation.y = lerp(-0.5, -0.18, ss(0, 1.2, t))
    // shakes while it is being worked open
    const shake = t > 0.8 && t < openAt ? Math.sin(t * 55) * 0.012 * ss(0.8, openAt, t) : 0
    crate.position.x = shake

    lidPivot.rotation.set(0, 0, 0); lid.position.set(0, T / 2, D / 2); lid.rotation.set(0, 0, 0)
    walls.forEach(w => { w.rotation.x = 0 })
    straps.forEach(s => { s.visible = true; s.position.y = 0; s.rotation.set(0, 0, 0) })
    crowbar.visible = false

    if (animation === 'lid') { // lid pops, lifts and flips away behind the crate
      const k = ss(openAt - 0.9, openAt + 0.5, t)
      lid.position.y = T / 2 + Math.sin(k * Math.PI) * 1.0 - ss(0.5, 1, k) * (H - 0.02)
      lid.position.z = D / 2 - k * 2.0
      lid.rotation.x = -Math.sin(k * Math.PI) * 0.9 - k * 0.05
      straps.forEach(s => { s.visible = false })
    } else if (animation === 'panels') { // the four walls fall outward like a flower, lid jumps up and away
      const k = ss(openAt - 0.5, openAt + 0.6, t)
      walls.forEach((w, i) => { w.rotation.x = outBounce(clamp(ss(openAt - 0.5 + i * 0.07, openAt + 0.6 + i * 0.07, t))) * (Math.PI / 2) * 0.98 })
      lid.position.y = T / 2 + Math.sin(k * Math.PI) * 1.1 - ss(0.5, 1, k) * (H - 0.02)
      lid.position.x = -k * 2.4; lid.rotation.z = Math.sin(k * Math.PI) * 1.1
      straps.forEach(s => { s.visible = false })
    } else if (animation === 'pry') { // a crowbar wedges under the front edge; the lid creaks open on its back hinge
      crowbar.visible = t > 0.8 && t < openAt + 0.6
      const wedge = ss(0.8, 1.4, t), lever = ss(1.5, openAt, t)
      crowbar.position.set(0.15, H + 0.02, D / 2 + lerp(0.5, 0.06, wedge))
      crowbar.rotation.set(0, Math.PI / 2, lerp(0.15, -0.55, lever) + Math.sin(t * 20) * 0.02 * lever)
      const creak = Math.min(lever * 0.18, 0.18) + ss(openAt - 0.15, openAt + 0.5, t) * 1.75
      lidPivot.rotation.x = -creak
      straps.forEach(s => { s.visible = false })
    } else { // straps: each strap snaps and whips off, then the lid slides off sideways
      straps.forEach((s, i) => {
        const k = ss(1.0 + i * 0.45, 1.5 + i * 0.45, t)
        s.position.y = k * 1.4; s.position.z = k * (i ? -1 : 1) * 0.6; s.rotation.x = k * (i ? 3 : -3)
        s.visible = k < 0.98
      })
      const k = ss(openAt - 0.4, openAt + 0.5, t)
      lid.position.x = -outBack(k) * 2.2; lid.position.y = T / 2 + Math.sin(k * Math.PI) * 0.2 - ss(0.45, 1, k) * (H - 0.02)
      lid.rotation.z = Math.sin(k * Math.PI) * 0.5
    }

    glow.intensity = ss(openAt - 0.2, openAt + 0.4, t) * 3.2
    const dustK = clamp((t - openAt + 0.15) / 1.6)
    dustMat.opacity = dustK > 0 && dustK < 1 ? (1 - dustK) * 0.9 : 0
    for (let i = 0; i < DUST; i++) {
      const v = dustVel[i]
      dustPos[i * 3] = v.x * dustK; dustPos[i * 3 + 1] = H + v.y * dustK - 2.2 * dustK * dustK; dustPos[i * 3 + 2] = v.z * dustK
    }
    dustGeo.attributes.position.needsUpdate = true

    itemMeshes.forEach((mesh, i) => {
      const begin = openAt + 0.3 + i * ITEM_STAGGER
      const k = clamp((t - begin) / ITEM_FLIGHT)
      mesh.visible = t >= begin
      const { from, to, spin } = mesh.userData
      const e = ss(0, 1, k)
      mesh.position.set(lerp(from.x, to.x, e), lerp(from.y, to.y, e) + Math.sin(k * Math.PI) * 1.3, lerp(from.z, to.z, e))
      mesh.rotation.set(Math.sin(k * Math.PI) * 0.4, lerp(spin, 0, e), 0)
      if (k >= 1 && !revealed.has(i)) { revealed.add(i); options.onReveal?.(i) }
    })

    // camera eases from a wide shot down to the row of contents
    const c = ss(openAt, total - 0.4, t)
    const wide = camera.aspect > 1.3 ? 0.45 : 0 // leave room for the contents list on the right
    camera.position.set(Math.sin(t * 0.15) * 0.3 + wide, lerp(2.4, 2.3, c), lerp(4.8, 5.4 + items.length * 0.12, c))
    camera.lookAt(wide, lerp(0.55, 0.3, c), lerp(0, 0.7, c))
  }

  function resize() {
    const w = canvas.clientWidth || canvas.width, h = canvas.clientHeight || canvas.height
    renderer.setSize(w, h, false)
    camera.aspect = w / Math.max(1, h); camera.updateProjectionMatrix()
  }
  const observer = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(resize) : null
  observer?.observe(canvas)
  resize()

  function tick(now) {
    if (disposed) return
    if (!start) start = now
    const t = done ? total : (now - start) / 1000
    pose(t)
    renderer.render(scene, camera)
    if (t >= total && !done) { done = true; finished?.() }
    frame = requestAnimationFrame(tick)
  }
  pose(0); renderer.render(scene, camera)

  return {
    animation,
    play() {
      return new Promise(resolve => { finished = resolve; start = 0; frame = requestAnimationFrame(tick) })
    },
    skip() { done = true; pose(total); itemMeshes.forEach((_, i) => { if (!revealed.has(i)) { revealed.add(i); options.onReveal?.(i) } }); finished?.() },
    dispose() {
      disposed = true
      cancelAnimationFrame(frame)
      observer?.disconnect()
      for (const thing of disposables) thing.dispose?.()
      for (const mat of disposables) if (mat.map) mat.map.dispose?.()
      renderer.dispose()
    },
  }
}

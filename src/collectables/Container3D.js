/**
 * Real-time Three.js coin bags and plushie boxes, lazy-loaded like the card pack's PeelTear3D.
 *
 * createContainerScene(canvas, { kind: 'bag'|'box', style, animation, items, preview, onPhase, onPick, onReveal, onLayout })
 *   -> { play() => Promise, reveal(index), revealAll(), dispose() }
 *
 * The collectibles physically come out of the container, land in front of it as glowing silhouettes and are
 * revealed in 3D when clicked (onPick reports clicks; the host decides whether to reveal or inspect).
 * preview: true renders the sealed container idling on a turntable for the lab.
 */
import * as THREE from 'three'
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js'
import { resolveAsset } from '../runtime/assets'

const MAGENTA = '#ff2bd6', YELLOW = '#ffd23c', CYAN = '#4df3ff'
const PACK_ART = '/img/meta_pack.png'

const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v))
const lerp = (a, b, k) => a + (b - a) * k
const ss = (a, b, t) => { const k = clamp((t - a) / (b - a)); return k * k * (3 - 2 * k) }
const inOut = k => (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2)
const outCubic = k => 1 - Math.pow(1 - k, 3)
const outBack = (k, c = 1.7) => 1 + (c + 1) * Math.pow(k - 1, 3) + c * Math.pow(k - 1, 2)
const outBounce = k => {
  const n = 7.5625, d = 2.75
  if (k < 1 / d) return n * k * k
  if (k < 2 / d) return n * (k -= 1.5 / d) * k + 0.75
  if (k < 2.5 / d) return n * (k -= 2.25 / d) * k + 0.9375
  return n * (k -= 2.625 / d) * k + 0.984375
}
const v3 = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z)

// Timelines (seconds). emerge = first item leaves the container; each item flies for `flight`, `stagger` apart.
const TIMELINES = {
  float: { drop: 0.65, charge: [0.65, 1.5], open: [1.5, 2.6], emerge: 2.45, flight: 1.55, stagger: 0.3, peek: true },
  pour: { drop: 0.65, charge: [0.65, 1.45], open: [1.45, 2.05], tip: [1.95, 2.85], emerge: 2.7, flight: 1.35, stagger: 0.13 },
  pop: { drop: 0.65, charge: [0.65, 2.0], open: [2.0, 2.25], emerge: 2.08, flight: 1.45, stagger: 0.09 },
  lift: { drop: 0.65, charge: [0.65, 1.5], open: [1.5, 2.5], emerge: 2.3, flight: 1.55, stagger: 0.3, peek: true },
  unfold: { drop: 0.65, charge: [0.65, 1.45], open: [1.45, 2.55], emerge: 2.5, flight: 1.05, stagger: 0.2 },
  burst: { drop: 0.65, charge: [0.65, 2.0], open: [2.0, 2.35], emerge: 2.02, flight: 1.5, stagger: 0.12 },
}
const REVEAL_TIME = 0.9

/* ------------------------------------------------------------------ canvas helpers */

const makeCanvas = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h; return [c, c.getContext('2d')] }
const speckle = (g, w, h, count, color, size = 1.4) => {
  g.fillStyle = color
  for (let i = 0; i < count; i++) g.fillRect(Math.random() * w, Math.random() * h, size * (0.4 + Math.random()), size * (0.4 + Math.random()))
}
const roundRect = (g, x, y, w, h, r) => { g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r); g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath() }
const text = (g, value, x, y, size, { fill = '#fff', stroke, strokeWidth = 0, font = 'Impact, "Arial Black", sans-serif', weight = '', align = 'center', glow, glowBlur = 0 } = {}) => {
  g.save()
  g.font = `${weight} ${size}px ${font}`.trim(); g.textAlign = align; g.textBaseline = 'middle'
  if (glow) { g.shadowColor = glow; g.shadowBlur = glowBlur }
  if (stroke) { g.lineJoin = 'round'; g.strokeStyle = stroke; g.lineWidth = strokeWidth; g.strokeText(value, x, y) }
  g.fillStyle = fill; g.fillText(value, x, y)
  g.restore()
}
const brand = (g, x, y, size, { meta = YELLOW, comics = MAGENTA, stroke = '#120518' } = {}) => {
  text(g, 'META', x, y - size * 0.55, size, { fill: meta, stroke, strokeWidth: size * 0.16 })
  text(g, 'COMICS', x, y + size * 0.5, size, { fill: comics, stroke, strokeWidth: size * 0.16 })
}
// The booster pack's yellow comic-burst border and magenta field, so boxes read as the same product line.
const comicPanel = (g, w, h, { base = '#c41fa8', deep = '#4a0f63' } = {}) => {
  const bg = g.createRadialGradient(w * 0.5, h * 0.45, 0, w * 0.5, h * 0.5, Math.max(w, h) * 0.75)
  bg.addColorStop(0, base); bg.addColorStop(1, deep)
  g.fillStyle = bg; g.fillRect(0, 0, w, h)
  g.save(); g.globalAlpha = 0.16; g.fillStyle = '#ffffff'
  for (let y = 0; y < h; y += 14) for (let x = (y / 14) % 2 ? 7 : 0; x < w; x += 14) { g.beginPath(); g.arc(x, y, 2.6 * (0.4 + y / h), 0, Math.PI * 2); g.fill() }
  g.restore()
  g.save(); g.globalAlpha = 0.18; g.strokeStyle = YELLOW; g.lineWidth = 3
  for (let a = 0; a < Math.PI * 2; a += Math.PI / 18) { g.beginPath(); g.moveTo(w / 2, h / 2); g.lineTo(w / 2 + Math.cos(a) * w, h / 2 + Math.sin(a) * h); g.stroke() }
  g.restore()
  const edge = Math.min(w, h) * 0.06
  g.fillStyle = YELLOW
  for (const [x0, y0, dx, dy, len] of [[0, 0, 1, 0, w], [0, h, 1, 0, w], [0, 0, 0, 1, h], [w, 0, 0, 1, h]]) {
    g.beginPath(); g.moveTo(x0, y0)
    for (let s = 0; s <= len; s += edge) {
      const inward = (s / edge) % 2 ? edge * 0.9 : edge * 0.35
      const px = x0 + dx * s + (dy ? (x0 === 0 ? inward : -inward) : 0)
      const py = y0 + dy * s + (dx ? (y0 === 0 ? inward : -inward) : 0)
      g.lineTo(px, py)
    }
    g.lineTo(x0 + dx * len, y0 + dy * len); g.closePath(); g.fill()
  }
}
// planked wood (crates, chests): horizontal boards with grain, optional dark gaps between them
const woodPanel = (g, w, h, { boards = 4, base = '#8a5a2e', gaps = true, vertical = false } = {}) => {
  g.save()
  if (vertical) { g.translate(w, 0); g.rotate(Math.PI / 2); [w, h] = [h, w] }
  const bh = h / boards
  for (let b = 0; b < boards; b++) {
    const tone = 0.85 + ((b * 37) % 7) / 25
    g.fillStyle = base; g.fillRect(0, b * bh, w, bh)
    g.fillStyle = `rgba(${tone > 1 ? 255 : 0},${tone > 1 ? 220 : 0},${tone > 1 ? 170 : 0},${Math.abs(1 - tone) * 0.6})`; g.fillRect(0, b * bh, w, bh)
    for (let n = 0; n < 14; n++) {
      g.strokeStyle = `rgba(40,20,6,${0.12 + (n % 3) * 0.06})`; g.lineWidth = 1 + (n % 2)
      const y0 = b * bh + bh * ((n * 0.071 + b * 0.13) % 1)
      g.beginPath(); g.moveTo(0, y0)
      for (let x = 0; x <= w; x += w / 12) g.lineTo(x, y0 + Math.sin(x * 0.02 + n + b) * bh * 0.05)
      g.stroke()
    }
    if (gaps) { g.fillStyle = 'rgba(15,8,2,.85)'; g.fillRect(0, b * bh, w, Math.max(2, bh * 0.05)) }
    g.fillStyle = 'rgba(30,18,8,.9)'
    for (const x of [w * 0.04, w * 0.96]) { g.beginPath(); g.arc(x, b * bh + bh / 2, Math.max(2, bh * 0.05), 0, Math.PI * 2); g.fill() }
  }
  g.restore()
}
const drawPackCrop = (g, img, x, y, w, h) => {
  if (!img) return
  // the booster artwork: hero silhouette and "META COMICS" wordmark, cropped from the centre of the pack image
  const sx = img.width * 0.25, sy = img.height * 0.06, sw = img.width * 0.5, sh = img.height * 0.62
  g.drawImage(img, sx, sy, sw, sh, x, y, w, h)
}
const questionMark = (g, x, y, size, { fill = '#ffd76a', glow = '#ff9d1f', stroke } = {}) =>
  text(g, '?', x, y, size, { fill, glow, glowBlur: size * 0.25, font: 'Georgia, "Times New Roman", serif', weight: 'bold', stroke, strokeWidth: size * 0.06 })

// Outer outlines of a pixel mask (Moore-neighbour tracing), as smoothed point lists.
function traceOutlines(mask, S, minLength = 40) {
  const inside = (x, y) => x >= 0 && y >= 0 && x < S && y < S && mask[y * S + x] === 1
  const DIRS = [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]] // clockwise (y down)
  const visited = new Uint8Array(S * S)
  const outlines = []
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    if (!inside(x, y) || inside(x - 1, y) || visited[y * S + x]) continue
    const points = []
    let cx = x, cy = y, back = 4, guard = S * S
    do {
      points.push([cx, cy]); visited[cy * S + cx] = 1
      let moved = false
      for (let k = 1; k <= 8; k++) {
        const d = (back + k) % 8, nx = cx + DIRS[d][0], ny = cy + DIRS[d][1]
        if (!inside(nx, ny)) continue
        const prev = DIRS[(back + k - 1) % 8], bx = cx + prev[0] - nx, by = cy + prev[1] - ny
        back = DIRS.findIndex(([dx, dy]) => dx === bx && dy === by)
        if (back < 0) back = 4
        cx = nx; cy = ny; moved = true
        break
      }
      if (!moved) break
    } while ((cx !== x || cy !== y) && --guard > 0)
    if (points.length < minLength) continue
    // smooth (moving average) so stitches follow a clean curve rather than the pixel staircase
    const n = points.length, w = 4
    outlines.push(points.map((_, i) => {
      let sx = 0, sy = 0
      for (let k = -w; k <= w; k++) { const q = points[(i + k + n) % n]; sx += q[0]; sy += q[1] }
      return [sx / (2 * w + 1), sy / (2 * w + 1)]
    }))
  }
  return outlines
}

// Plushie fabric colour: re-hue the artwork while keeping its shading.
function tintCanvas(canvas, color, strength) {
  if (!color || !(strength > 0)) return canvas
  const [solid, sg] = makeCanvas(canvas.width, canvas.height)
  sg.drawImage(canvas, 0, 0); sg.globalCompositeOperation = 'source-atop'; sg.fillStyle = color; sg.fillRect(0, 0, canvas.width, canvas.height)
  const g = canvas.getContext('2d')
  g.save(); g.globalAlpha = Math.min(1, strength); g.globalCompositeOperation = 'color'; g.drawImage(solid, 0, 0); g.restore()
  g.save(); g.globalCompositeOperation = 'destination-in'; g.drawImage(solid, 0, 0); g.restore() // keep the original outline
  return canvas
}

// Seam stitching drawn as thread right on the outline: the outline is where the front and back halves meet,
// and both halves draw the same stitches there, so they read as one seam sewn across the join.
function stitchCanvas(canvas, outlines, mask, S, { color = '#f3e6cf', pattern = 'running', width = 2.2 } = {}) {
  if (pattern === 'none' || !outlines.length) return canvas
  const g = canvas.getContext('2d')
  const unit = S / 320
  const inside = (x, y) => { const ix = Math.round(x), iy = Math.round(y); return ix >= 0 && iy >= 0 && ix < S && iy < S && mask[iy * S + ix] === 1 }
  const thread = (draw, lineWidth) => {
    g.save(); g.lineCap = 'round'; g.lineJoin = 'round'
    g.strokeStyle = 'rgba(0,0,0,.35)'; g.lineWidth = lineWidth * unit + 1.2; g.translate(0.8, 1); draw(); g.translate(-0.8, -1) // shadow under the thread
    g.strokeStyle = color; g.lineWidth = lineWidth * unit; draw()
    g.strokeStyle = 'rgba(255,255,255,.28)'; g.lineWidth = Math.max(0.6, lineWidth * unit * 0.35); g.translate(-0.4, -0.5); draw() // sheen
    g.restore()
  }
  for (const outline of outlines) {
    // resample along the curve and work out the inward normal at each step
    const step = 3.5 * unit, pts = []
    let carry = 0
    for (let i = 0; i < outline.length; i++) {
      const a = outline[i], b = outline[(i + 1) % outline.length]
      const len = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1e-6
      for (let t = carry; t < len; t += step) pts.push([a[0] + (b[0] - a[0]) * t / len, a[1] + (b[1] - a[1]) * t / len])
      carry = (carry - len) % step; if (carry < 0) carry += step
    }
    if (pts.length < 6) continue
    const at = (i, offset) => {
      const n = pts.length, p = pts[(i + n) % n], q = pts[(i + 1) % n], o = pts[(i - 1 + n) % n]
      let nx = -(q[1] - o[1]), ny = q[0] - o[0]; const l = Math.hypot(nx, ny) || 1; nx /= l; ny /= l
      if (!inside(p[0] + nx * 4 * unit, p[1] + ny * 4 * unit)) { nx = -nx; ny = -ny }
      return [p[0] + nx * offset * unit, p[1] + ny * offset * unit]
    }
    const seg = (a, b) => { g.moveTo(a[0], a[1]); g.lineTo(b[0], b[1]) }
    const n = pts.length
    if (pattern === 'running' || pattern === 'double') {
      const rows = pattern === 'double' ? [1.6, 5] : [1.8]
      thread(() => { g.beginPath(); for (const off of rows) for (let i = 0; i < n - 2; i += 3) seg(at(i, off), at(i + 2, off)); g.stroke() }, width)
    } else if (pattern === 'cross') {
      thread(() => { g.beginPath(); for (let i = 0; i < n - 2; i += 3) { seg(at(i, 0.4), at(i + 2, 4.6)); seg(at(i, 4.6), at(i + 2, 0.4)) } g.stroke() }, width * 0.9)
    } else if (pattern === 'zigzag') {
      thread(() => { g.beginPath(); for (let i = 0; i < n; i += 2) { const p = at(i, (i / 2) % 2 ? 0.5 : 4.2); i ? g.lineTo(p[0], p[1]) : g.moveTo(p[0], p[1]) } g.closePath(); g.stroke() }, width)
    } else if (pattern === 'blanket') {
      thread(() => { g.beginPath(); for (let i = 0; i < n; i++) { const p = at(i, 4.5); i ? g.lineTo(p[0], p[1]) : g.moveTo(p[0], p[1]) } g.closePath(); for (let i = 0; i < n; i += 3) seg(at(i, 0.3), at(i, 4.5)); g.stroke() }, width * 0.9)
    }
  }
  return canvas
}

const loadImage = async src => {
  if (!src) return null
  try {
    const state = await resolveAsset(src)
    if (state.status === 'error') return null
    const url = state.url || src
    return await new Promise(resolve => { const img = new Image(); img.crossOrigin = 'anonymous'; img.onload = () => resolve(img); img.onerror = () => resolve(null); img.src = url })
  } catch { return null }
}

/* ------------------------------------------------------------------ shaders (shared look with the card pack) */

const SIMPLE_VERT = `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`
const GLOW_FRAG = `uniform vec3 uCol; uniform float uI; uniform float uSoft; varying vec2 vUv;
void main(){ vec2 p = vUv * 2.0 - 1.0; float r = length(p); float g = exp(-r * r * uSoft) * (1.0 - smoothstep(0.85, 1.0, r)); gl_FragColor = vec4(uCol * g * uI, 1.0); }`
const RAYS_FRAG = `uniform float uI, uTime; uniform vec3 uCol; varying vec2 vUv;
void main(){
  vec2 p = vec2((vUv.x - 0.5) * 6.0, vUv.y * 7.0);
  float a = atan(p.x, p.y), r = length(p);
  float cone = smoothstep(0.78, 0.18, abs(a));
  float s = 0.5 + 0.5 * sin(a * 23.0 + uTime * 0.6) * sin(a * 37.0 - uTime * 0.45);
  s += 0.9 * pow(max(0.0, sin(a * 11.0 + 1.3 + uTime * 0.25)), 14.0);
  float I = uI * (cone * s * exp(-r * 0.42) * 0.8 + exp(-abs(a) * 6.0) * exp(-r * 0.9) * 1.1) * smoothstep(0.0, 0.12, r) * smoothstep(1.0, 0.7, vUv.y);
  gl_FragColor = vec4(uCol * I, 1.0);
}`
const SPARK_VERT = `attribute float aLife; attribute float aSize; attribute vec3 aCol; varying float vLife; varying vec3 vCol;
void main(){ vLife = aLife; vCol = aCol; vec4 mv = modelViewMatrix * vec4(position, 1.0); gl_PointSize = aSize * (300.0 / -mv.z) * step(0.001, aLife); gl_Position = projectionMatrix * mv; }`
const SPARK_FRAG = `varying float vLife; varying vec3 vCol;
void main(){ vec2 p = gl_PointCoord * 2.0 - 1.0; float d = length(p); float star = max(exp(-d * d * 6.0), 0.6 * exp(-abs(p.x * p.y) * 60.0) * (1.0 - d));
  gl_FragColor = vec4(vCol * star * vLife * 1.6, 1.0); }`
const ADDITIVE = { blending: THREE.CustomBlending, blendEquation: THREE.AddEquation, blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor, blendSrcAlpha: THREE.ZeroFactor, blendDstAlpha: THREE.OneFactor }

/* ------------------------------------------------------------------ scene */

// Inventory icon of a coin / plushie print: the real 3D model at a slight angle on a transparent background.
export async function renderCollectibleIcon(item, size = 100, format = 'webp') {
  const canvas = document.createElement('canvas')
  const coin = item.collectableType === 'challenge_coin'
  const viewer = await createContainerScene(canvas, { viewer: true, items: [item], size: size * 2, maxPixelRatio: 1, fill: coin ? 1.02 : 1.06 })
  try {
    return viewer.still(coin ? 0.14 : 0.06, coin ? -0.42 : -0.3, rendered => {
      const out = document.createElement('canvas'); out.width = out.height = size
      const g = out.getContext('2d'); g.imageSmoothingQuality = 'high'; g.drawImage(rendered, 0, 0, size, size)
      return out.toDataURL(format === 'png' ? 'image/png' : 'image/webp', 0.92)
    })
  } finally { viewer.dispose() }
}

export async function createContainerScene(canvas, options = {}) {
  const opts = { kind: 'bag', style: 'velvet', animation: 'float', items: [], preview: false, maxPixelRatio: 1.75, ...options }
  const kind = opts.kind === 'bag' || opts.kind === 'case' ? opts.kind : 'box'
  const anim = TIMELINES[opts.animation] ? opts.animation : kind === 'bag' ? 'float' : 'lift'
  const TL = TIMELINES[anim]
  const owned = []
  const miniCache = new Map() // inner design -> shared model for the sealed containers in a case
  const own = o => { owned.push(o); return o }

  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true })
  renderer.setClearColor(0x000000, 0)
  renderer.outputColorSpace = THREE.SRGBColorSpace
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 1.15
  renderer.shadowMap.enabled = true
  renderer.shadowMap.type = THREE.PCFShadowMap

  const scene = new THREE.Scene()
  const pmrem = new THREE.PMREMGenerator(renderer)
  const roomEnv = new RoomEnvironment()
  scene.environment = own(pmrem.fromScene(roomEnv, 0.04).texture)
  roomEnv.traverse?.(child => { child.geometry?.dispose?.(); child.material?.dispose?.() })
  pmrem.dispose()
  scene.environmentIntensity = 0.55

  const camera = new THREE.PerspectiveCamera(32, 16 / 9, 0.1, 80)

  const tex = (c, srgb = true) => { const t = own(new THREE.CanvasTexture(c)); if (srgb) t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; return t }
  const mat = m => own(m)
  const geo = g => own(g)
  const glowMaterial = (color, soft = 3) => mat(new THREE.ShaderMaterial({ uniforms: { uCol: { value: new THREE.Color(color) }, uI: { value: 0 }, uSoft: { value: soft } }, vertexShader: SIMPLE_VERT, fragmentShader: GLOW_FRAG, transparent: true, depthWrite: false, ...ADDITIVE }))
  const shadowCasting = root => root.traverse(o => { if (o.isMesh && !o.material.isShaderMaterial && !(o.material.transparent && o.material.opacity < 1)) o.castShadow = true })

  // lights: warm spot from above like the reference photo, magenta rim, cyan fill
  scene.add(new THREE.HemisphereLight(0x9a8cff, 0x1a0c22, 0.3))
  const key = new THREE.SpotLight(0xffe0b0, 120, 0, 0.42, 0.65, 2)
  key.position.set(1.6, 7.5, 4.2); key.target.position.set(0, 0.8, 0.4)
  key.castShadow = true; key.shadow.mapSize.set(1024, 1024); key.shadow.bias = -0.0004; key.shadow.radius = 6
  scene.add(key, key.target)
  const rim = new THREE.DirectionalLight(0xff4bd8, 1.6); rim.position.set(-3.5, 2.5, -3); scene.add(rim)
  const fill = new THREE.DirectionalLight(0x5cf0ff, 0.55); fill.position.set(4, 1.5, 3); scene.add(fill)
  const inner = new THREE.PointLight(0xffb347, 0, 4.5, 1.6); scene.add(inner)

  const floor = new THREE.Mesh(geo(new THREE.PlaneGeometry(40, 40)), mat(new THREE.ShadowMaterial({ opacity: 0.55, depthWrite: false })))
  floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true; scene.add(floor)
  const floorGlow = new THREE.Mesh(geo(new THREE.PlaneGeometry(1, 1)), glowMaterial(kind === 'bag' ? '#ff9a2a' : MAGENTA, 3.2))
  floorGlow.rotation.x = -Math.PI / 2; floorGlow.position.y = 0.005; floorGlow.scale.setScalar(4.4); scene.add(floorGlow)

  const packArt = await loadImage(PACK_ART)
  const container = opts.viewer ? null : kind === 'bag' ? buildBag(opts.style) : buildBox(opts.style)
  if (container) { scene.add(container.root); shadowCasting(container.root) }

  /* -------------------------------- sparkles */
  const SPARKS = 480
  const sparkGeo = geo(new THREE.BufferGeometry())
  const sp = { pos: new Float32Array(SPARKS * 3), vel: new Float32Array(SPARKS * 3), life: new Float32Array(SPARKS), size: new Float32Array(SPARKS), col: new Float32Array(SPARKS * 3), decay: new Float32Array(SPARKS), next: 0 }
  sparkGeo.setAttribute('position', new THREE.BufferAttribute(sp.pos, 3))
  sparkGeo.setAttribute('aLife', new THREE.BufferAttribute(sp.life, 1))
  sparkGeo.setAttribute('aSize', new THREE.BufferAttribute(sp.size, 1))
  sparkGeo.setAttribute('aCol', new THREE.BufferAttribute(sp.col, 3))
  const sparks = new THREE.Points(sparkGeo, mat(new THREE.ShaderMaterial({ vertexShader: SPARK_VERT, fragmentShader: SPARK_FRAG, transparent: true, depthWrite: false, ...ADDITIVE })))
  sparks.frustumCulled = false; sparks.renderOrder = 10; scene.add(sparks)
  const palette = [new THREE.Color(YELLOW), new THREE.Color(MAGENTA), new THREE.Color(CYAN), new THREE.Color('#ffffff')]
  const emit = (origin, count, { speed = 1.6, up = 1.2, spread = 1, colors = palette, size = 0.12, decay = 1.1 } = {}) => {
    for (let n = 0; n < count; n++) {
      const i = sp.next = (sp.next + 1) % SPARKS
      sp.pos.set([origin.x, origin.y, origin.z], i * 3)
      const a = Math.random() * Math.PI * 2, s = speed * (0.35 + Math.random())
      sp.vel.set([Math.cos(a) * s * spread, up * (0.4 + Math.random()) * speed, Math.sin(a) * s * spread], i * 3)
      sp.life[i] = 1; sp.decay[i] = decay * (0.7 + Math.random() * 0.6); sp.size[i] = size * (0.5 + Math.random())
      const c = colors[(Math.random() * colors.length) | 0]; sp.col.set([c.r, c.g, c.b], i * 3)
    }
  }
  const stepSparks = dt => {
    for (let i = 0; i < SPARKS; i++) {
      if (sp.life[i] <= 0) continue
      sp.vel[i * 3 + 1] -= 2.2 * dt
      for (let k = 0; k < 3; k++) { sp.vel[i * 3 + k] *= 1 - 0.9 * dt; sp.pos[i * 3 + k] += sp.vel[i * 3 + k] * dt }
      sp.life[i] = Math.max(0, sp.life[i] - sp.decay[i] * dt)
    }
    for (const name of ['position', 'aLife']) sparkGeo.attributes[name].needsUpdate = true
    sparkGeo.attributes.aSize.needsUpdate = true; sparkGeo.attributes.aCol.needsUpdate = true
  }

  /* -------------------------------- items */
  // an outer case shows at most 24 of its sealed containers flying out; the rest are delivered all the same
  const shownItems = opts.preview ? [] : kind === 'case' ? opts.items.slice(0, 24) : opts.items
  const items = await Promise.all(shownItems.map((item, index) => buildItem(item, index)))
  const layout = layoutSlots(items)
  items.forEach((it, i) => { it.slot = layout.slots[i]; scene.add(it.root); it.root.visible = false })
  const questionTex = (() => { const [c, g] = makeCanvas(128, 128); questionMark(g, 64, 70, 104, { fill: '#ffe08a', glow: '#ff8a00' }); return tex(c) })()
  items.forEach(it => {
    it.mark = new THREE.Sprite(mat(new THREE.SpriteMaterial({ map: questionTex, transparent: true, depthWrite: false, opacity: 0 })))
    it.mark.scale.setScalar(0.42); it.mark.renderOrder = 9; scene.add(it.mark)
  })
  if (opts.viewer) return startViewer()

  /* ================================================================ viewer */

  // Interactive inspect view: drag to turn, hover tilts toward the pointer and a light follows it so
  // metal, foil and iridescent finishes react; turning the model sweeps the reflections across it.
  function it_coin(it) { return !!it?.coin }
  function startViewer() {
    floor.visible = false; floorGlow.visible = false; key.castShadow = false
    // calmer lighting for close-up inspection; fabric gets less than polished metal
    key.intensity = it_coin(items[0]) ? 85 : 55; rim.intensity = it_coin(items[0]) ? 1.2 : 0.7; scene.environmentIntensity = it_coin(items[0]) ? 0.95 : 0.32; renderer.toneMappingExposure = it_coin(items[0]) ? 1.05 : 0.95
    const it = items[0]
    if (!it) throw new Error('Nothing to show')
    for (const swap of it.swaps) swap.mesh.material = swap.real
    it.glow.visible = false; it.mark.visible = false
    const tilt = new THREE.Group(), spin = new THREE.Group(); scene.add(tilt); tilt.add(spin); spin.add(it.root)
    it.root.visible = true
    it.root.position.set(0, it.coin ? 0 : -it.height / 2, 0)
    const pointerLight = new THREE.PointLight(0xffffff, 0, 8, 1.4); scene.add(pointerLight)
    const state = { x: 0, y: 0, tx: 0, ty: 0, nx: 0, ny: 0, inside: false, hover: 0, drag: null }
    const fit = () => {
      const w = opts.size || canvas.clientWidth || 1, h = opts.size || canvas.clientHeight || 1
      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, opts.maxPixelRatio)); renderer.setSize(w, h, false)
      camera.aspect = w / h; camera.fov = 30; camera.updateProjectionMatrix()
      const size = (it.coin ? 0.95 : Math.max(it.height, 1.0)) * (opts.fill || 1.18)
      const d = size / 2 / Math.tan(THREE.MathUtils.degToRad(15)) / Math.min(1, camera.aspect)
      camera.position.set(0, 0, d); camera.lookAt(0, 0, 0)
    }
    fit()
    const ro = typeof ResizeObserver === 'function' ? new ResizeObserver(fit) : null
    ro?.observe(canvas)
    const track = event => { const rect = canvas.getBoundingClientRect(); state.nx = clamp(((event.clientX - rect.left) / rect.width) * 2 - 1, -1, 1); state.ny = clamp(((event.clientY - rect.top) / rect.height) * 2 - 1, -1, 1) }
    const down = event => { if (event.button !== 0) return; event.preventDefault(); canvas.setPointerCapture?.(event.pointerId); state.drag = { px: event.clientX, py: event.clientY, x: state.tx, y: state.ty }; track(event) }
    const move = event => {
      track(event); state.inside = event.pointerType !== 'touch' || !!state.drag
      if (state.drag) { state.ty = state.drag.y + (event.clientX - state.drag.px) * 0.011; state.tx = state.drag.x + (event.clientY - state.drag.py) * 0.008 }
    }
    const up = () => { state.drag = null }
    const leave = () => { state.inside = false }
    canvas.addEventListener('pointerdown', down); canvas.addEventListener('pointermove', move); canvas.addEventListener('pointerup', up); canvas.addEventListener('pointercancel', up); canvas.addEventListener('pointerleave', leave)
    canvas.style.touchAction = 'none'; canvas.style.cursor = 'grab'
    const glitter = (it.item.finish === 'glitter')
    let raf = 0, last = performance.now(), disposed = false, t = 0
    const frame = now => {
      if (disposed) return
      const dt = Math.min(0.1, (now - last) / 1000); last = now; t += dt
      const ease = 1 - Math.pow(0.0001, dt)
      state.x += (state.tx - state.x) * ease; state.y += (state.ty - state.y) * ease
      state.hover += ((state.inside && !state.drag ? 1 : 0) - state.hover) * Math.min(1, dt * 8)
      spin.rotation.set(state.x, state.y, 0)
      tilt.rotation.set(state.ny * 0.22 * state.hover, state.nx * 0.32 * state.hover, 0)
      const lit = state.inside || state.drag ? 1 : 0
      pointerLight.position.set(state.nx * 1.8, -state.ny * 1.8, camera.position.z * 0.55)
      pointerLight.intensity += (lit * (it.coin ? 4.5 : 1.6) - pointerLight.intensity) * Math.min(1, dt * 6)
      if (glitter && lit && Math.random() < 0.35) {
        const p = v3((Math.random() - 0.5) * 0.7, (Math.random() - 0.5) * (it.coin ? 0.7 : it.height * 0.8), 0.2).applyMatrix4(spin.matrixWorld)
        emit(p, 1, { speed: 0.15, up: 0.1, spread: 0.3, size: 0.06, decay: 2.4, colors: [new THREE.Color('#ffffff'), new THREE.Color(YELLOW)] })
      }
      stepSparks(dt)
      canvas.style.cursor = state.drag ? 'grabbing' : 'grab'
      renderer.render(scene, camera)
      raf = requestAnimationFrame(frame)
    }
    raf = requestAnimationFrame(frame)
    return {
      // rotate by a step (radians) or jump to an absolute orientation
      turn: (dx = 0, dy = 0) => { state.tx += dx; state.ty += dy },
      // render one frame at a fixed angle and hand it back (inventory icons); read in the same task as the render
      still: (x, y, draw) => {
        state.x = state.tx = x; state.y = state.ty = y; state.hover = 0
        spin.rotation.set(x, y, 0); tilt.rotation.set(0, 0, 0)
        // a soft light from upper front, like a product shot, so metal faces read in the icon
        pointerLight.position.set(0.7, 0.9, camera.position.z * 0.6); pointerLight.intensity = it.coin ? 7 : 1.5
        renderer.render(scene, camera)
        return draw(canvas)
      },
      reset: () => { state.tx = 0; state.ty = 0 },
      dispose: () => {
        if (disposed) return
        disposed = true; cancelAnimationFrame(raf); ro?.disconnect()
        canvas.removeEventListener('pointerdown', down); canvas.removeEventListener('pointermove', move); canvas.removeEventListener('pointerup', up); canvas.removeEventListener('pointercancel', up); canvas.removeEventListener('pointerleave', leave)
        scene.traverse(o => { if (o.isMesh && o.geometry && !owned.includes(o.geometry)) o.geometry.dispose() })
        owned.forEach(o => o.dispose?.()); renderer.dispose(); renderer.forceContextLoss?.()
      },
    }
  }

  /* ================================================================ builders */

  function buildBag(style) {
    const LOOK = {
      velvet: { lining: '#141018', cord: '#2b2731', bead: '#141217', beadCap: '#d7a640', ruffle: 0.13, pleat: 0.09 },
      satin: { lining: '#ffcf4a', cord: CYAN, bead: YELLOW, beadCap: '#ffffff', ruffle: 0.12, pleat: 0.08 },
      leather: { lining: '#3d2716', cord: '#3a2312', bead: '#7a5230', beadCap: '#c9a46a', ruffle: 0.05, pleat: 0.05 },
    }[style] || {}
    const SEG = 84, RINGS = 64, TOP0 = 1.98
    const closedKeys = [[0, 0], [0.05, 0.42], [0.22, 0.7], [0.6, 0.8], [0.98, 0.72], [1.25, 0.48], [1.42, 0.2], [1.55, 0.27], [1.75, 0.42], [1.98, 0.54]]
    const openKeys = [[0, 0], [0.05, 0.42], [0.22, 0.74], [0.6, 0.85], [0.98, 0.84], [1.2, 0.76], [1.33, 0.68], [1.42, 0.76], [1.52, 0.9], [1.62, 1.02]]

    // body texture: 1536 x 512 wraps the full circumference; u = 0.5 faces the camera
    const W = 1536, H = 512
    const cy = y => H - (y / TOP0) * H
    const [bc, bg] = makeCanvas(W, H)
    const [ec, eg] = makeCanvas(W, H)
    const [nc, ng] = makeCanvas(512, 256)
    eg.fillStyle = '#000'; eg.fillRect(0, 0, W, H)
    ng.fillStyle = '#808080'; ng.fillRect(0, 0, 512, 256)
    if (style === 'satin') {
      const grad = bg.createLinearGradient(0, 0, W, 0)
      for (let s = 0; s <= 1; s += 1 / 24) grad.addColorStop(s, (Math.round(s * 24) % 2) ? '#b4168f' : '#d42aa9')
      bg.fillStyle = grad; bg.fillRect(0, 0, W, H)
      bg.save(); bg.globalAlpha = 0.18; bg.fillStyle = '#fff'
      for (let i = 0; i < 90; i++) { bg.beginPath(); const x = Math.random() * W, y = Math.random() * H; bg.arc(x, y, 3 + Math.random() * 5, 0, Math.PI * 2); bg.fill() }
      bg.restore()
      bg.save(); roundRect(bg, W / 2 - 128, cy(1.28), 256, 270, 18); bg.fillStyle = '#fff'; bg.fill(); bg.clip()
      roundRect(bg, W / 2 - 118, cy(1.28) + 10, 236, 250, 12); bg.clip(); drawPackCrop(bg, packArt, W / 2 - 118, cy(1.28) + 10, 236, 250); bg.restore()
      text(bg, 'CHALLENGE COINS', W / 2, cy(0.28), 26, { fill: YELLOW, stroke: '#3a0634', strokeWidth: 6 })
      speckle(ng, 512, 256, 1400, '#9a9a9a', 2)
    } else if (style === 'leather') {
      bg.fillStyle = '#6a3d20'; bg.fillRect(0, 0, W, H)
      for (let i = 0; i < 160; i++) { bg.fillStyle = `rgba(${30 + Math.random() * 40},${15 + Math.random() * 20},5,${0.08 + Math.random() * 0.12})`; bg.beginPath(); bg.ellipse(Math.random() * W, Math.random() * H, 20 + Math.random() * 80, 10 + Math.random() * 40, Math.random() * 3, 0, Math.PI * 2); bg.fill() }
      speckle(bg, W, H, 9000, 'rgba(20,8,2,.35)', 2)
      bg.strokeStyle = '#e6c48c'; bg.lineWidth = 3; bg.setLineDash([10, 9])
      for (const u of [0.125, 0.375, 0.625, 0.875]) { bg.beginPath(); bg.moveTo(u * W, cy(0.08)); bg.lineTo(u * W, cy(1.3)); bg.stroke() }
      bg.setLineDash([])
      bg.save(); bg.strokeStyle = '#d9b26a'; bg.lineWidth = 5; bg.beginPath(); bg.ellipse(W / 2, cy(0.78), 150, 150, 0, 0, Math.PI * 2); bg.stroke()
      bg.setLineDash([8, 7]); bg.lineWidth = 2.5; bg.beginPath(); bg.ellipse(W / 2, cy(0.78), 136, 136, 0, 0, Math.PI * 2); bg.stroke(); bg.restore()
      text(bg, 'META COMICS', W / 2, cy(1.03), 40, { fill: '#e8c46c', stroke: '#3b210d', strokeWidth: 5 })
      questionMark(bg, W / 2, cy(0.64), 140, { fill: '#e8c46c', glow: 'rgba(0,0,0,0)', stroke: '#3b210d' })
      text(bg, 'CHALLENGE COINS', W / 2, cy(0.36), 22, { fill: '#e8c46c' })
      questionMark(eg, W / 2, cy(0.64), 140, { fill: '#5a3a08', glow: 'rgba(0,0,0,0)' })
      for (let i = 0; i < 2200; i++) { ng.fillStyle = Math.random() > 0.5 ? '#9a9a9a' : '#5a5a5a'; ng.fillRect(Math.random() * 512, Math.random() * 256, 3, 3) }
      ng.save(); ng.scale(512 / W, 256 / H); text(ng, 'META COMICS', W / 2, cy(1.03), 40, { fill: '#d0d0d0' }); questionMark(ng, W / 2, cy(0.64), 140, { fill: '#e0e0e0', glow: 'rgba(0,0,0,0)' }); ng.restore()
    } else {
      bg.fillStyle = '#1a171d'; bg.fillRect(0, 0, W, H)
      speckle(bg, W, H, 26000, 'rgba(120,108,140,.10)', 1.6)
      speckle(bg, W, H, 18000, 'rgba(0,0,0,.25)', 1.6)
      bg.save(); roundRect(bg, W / 2 - 112, cy(1.24), 224, 78, 8); bg.fillStyle = '#0a080c'; bg.fill()
      const border = bg.createLinearGradient(W / 2 - 112, 0, W / 2 + 112, 0); border.addColorStop(0, MAGENTA); border.addColorStop(0.5, YELLOW); border.addColorStop(1, CYAN)
      bg.strokeStyle = border; bg.lineWidth = 3; bg.setLineDash([9, 6]); bg.stroke(); bg.restore()
      brand(bg, W / 2, cy(1.24) + 39, 27)
      text(bg, 'CHALLENGE COINS', W / 2, cy(0.94), 17, { fill: CYAN, weight: 'bold', font: 'Arial, sans-serif' })
      questionMark(bg, W / 2, cy(0.6), 150, { fill: '#ffd76a', glow: '#ff9d1f' })
      questionMark(eg, W / 2, cy(0.6), 150, { fill: '#ffb238', glow: '#ff7a00' })
      brand(eg, W / 2, cy(1.24) + 39, 27, { meta: '#3a2a00', comics: '#3a0030', stroke: '#000' })
      speckle(ng, 512, 256, 9000, '#a8a8a8', 1.5)
    }
    const map = tex(bc), emissiveMap = tex(ec), bumpMap = tex(nc, false)
    bumpMap.wrapS = bumpMap.wrapT = THREE.RepeatWrapping; bumpMap.repeat.set(style === 'leather' ? 1 : 4, style === 'leather' ? 1 : 2)

    const body = {
      velvet: { roughness: 0.96, sheen: 0.85, sheenRoughness: 0.45, sheenColor: new THREE.Color('#3b3346'), bumpScale: 0.5, emissiveIntensity: 1.6 },
      satin: { roughness: 0.3, sheen: 0.9, sheenRoughness: 0.25, sheenColor: new THREE.Color('#ffb0ec'), clearcoat: 0.55, clearcoatRoughness: 0.2, bumpScale: 0.15, emissiveIntensity: 0 },
      leather: { roughness: 0.58, clearcoat: 0.2, clearcoatRoughness: 0.5, bumpScale: 1.6, emissiveIntensity: 0.25 },
    }[style] || {}
    const outerMat = mat(new THREE.MeshPhysicalMaterial({ map, emissiveMap, emissive: 0xffffff, bumpMap, ...body }))
    const [lc, lg] = makeCanvas(16, 256)
    const lgrad = lg.createLinearGradient(0, 256, 0, 0); lgrad.addColorStop(0, '#ffe7a0'); lgrad.addColorStop(0.45, '#d0801c'); lgrad.addColorStop(0.75, '#2a1406'); lgrad.addColorStop(1, '#000')
    lg.fillStyle = lgrad; lg.fillRect(0, 0, 16, 256)
    const innerMat = mat(new THREE.MeshStandardMaterial({ color: LOOK.lining, roughness: 0.9, side: THREE.BackSide, emissive: 0xffffff, emissiveMap: tex(lc), emissiveIntensity: 0 }))

    const bagGeo = geo(new THREE.BufferGeometry())
    const count = (SEG + 1) * (RINGS + 1)
    const positions = new Float32Array(count * 3), uvs = new Float32Array(count * 2), index = []
    for (let j = 0; j <= RINGS; j++) for (let i = 0; i <= SEG; i++) { const k = j * (SEG + 1) + i; uvs[k * 2] = i / SEG; uvs[k * 2 + 1] = j / RINGS }
    for (let j = 0; j < RINGS; j++) for (let i = 0; i < SEG; i++) {
      const a = j * (SEG + 1) + i, b = a + 1, c = a + SEG + 1, d = c + 1
      index.push(a, b, d, a, d, c)
    }
    bagGeo.setIndex(index)
    bagGeo.setAttribute('position', new THREE.BufferAttribute(positions, 3))
    bagGeo.setAttribute('uv', new THREE.BufferAttribute(uvs, 2))
    const outer = new THREE.Mesh(bagGeo, outerMat)
    const lining = new THREE.Mesh(bagGeo, innerMat)

    const root = new THREE.Group()     // drop / wobble / move back
    const pivot = new THREE.Group()    // tipping over (pour)
    const bag = new THREE.Group()
    root.add(pivot); pivot.add(bag); bag.add(outer, lining)

    // monotone cubic interpolation through the profile keypoints
    const radiusAt = (keys, y) => {
      if (y <= keys[0][0]) return keys[0][1]
      for (let n = 0; n < keys.length - 1; n++) {
        const [y0, r0] = keys[n], [y1, r1] = keys[n + 1]
        if (y > y1) continue
        const m0 = n > 0 ? (r1 - keys[n - 1][1]) / (y1 - keys[n - 1][0]) : (r1 - r0) / (y1 - y0)
        const m1 = n + 2 < keys.length ? (keys[n + 2][1] - r0) / (keys[n + 2][0] - y0) : (r1 - r0) / (y1 - y0)
        const h = y1 - y0, s = (y - y0) / h
        const h00 = 2 * s ** 3 - 3 * s ** 2 + 1, h10 = s ** 3 - 2 * s ** 2 + s, h01 = -2 * s ** 3 + 3 * s ** 2, h11 = s ** 3 - s ** 2
        return Math.max(0, h00 * r0 + h10 * h * m0 + h01 * r1 + h11 * h * m1)
      }
      return keys[keys.length - 1][1]
    }

    const cordMat = mat(new THREE.MeshPhysicalMaterial({ color: LOOK.cord, roughness: style === 'satin' ? 0.3 : 0.62, sheen: 0.35, sheenColor: new THREE.Color(style === 'satin' ? '#ffffff' : '#4a4452'), clearcoat: style === 'satin' ? 0.5 : 0 }))
    const beadMat = mat(new THREE.MeshPhysicalMaterial({ color: LOOK.bead, roughness: 0.25, clearcoat: 1, metalness: style === 'satin' ? 0.8 : 0.1 }))
    const capMat = mat(new THREE.MeshStandardMaterial({ color: LOOK.beadCap, metalness: 0.95, roughness: 0.25 }))
    const loopMesh = new THREE.Mesh(undefined, cordMat), strands = [new THREE.Mesh(undefined, cordMat), new THREE.Mesh(undefined, cordMat)]
    const beads = [0, 1].map(() => {
      const g = new THREE.Group()
      const b = new THREE.Mesh(geo(new THREE.SphereGeometry(0.062, 20, 16)), beadMat); b.scale.set(1, 1.25, 1)
      const cap = new THREE.Mesh(geo(new THREE.CylinderGeometry(0.03, 0.045, 0.035, 16)), capMat); cap.position.y = 0.08
      const tassel = new THREE.Mesh(geo(new THREE.ConeGeometry(0.05, 0.16, 12, 1, true)), cordMat); tassel.position.y = -0.14; tassel.rotation.x = Math.PI
      g.add(b, cap, tassel); return g
    })
    bag.add(loopMesh, ...strands, ...beads)
    const grommets = style === 'leather' ? Array.from({ length: 12 }, () => { const m = new THREE.Mesh(geo(new THREE.TorusGeometry(0.035, 0.012, 8, 18)), capMat); bag.add(m); return m }) : []

    const mouthGlow = new THREE.Mesh(geo(new THREE.PlaneGeometry(1, 1)), glowMaterial('#ffd27a', 2.6))
    mouthGlow.rotation.x = -Math.PI / 2; mouthGlow.renderOrder = 5; bag.add(mouthGlow)
    const rays = new THREE.Mesh(geo(new THREE.PlaneGeometry(4.2, 4.8)), mat(new THREE.ShaderMaterial({ uniforms: { uI: { value: 0 }, uTime: { value: 0 }, uCol: { value: new THREE.Color('#ffe2a8') } }, vertexShader: SIMPLE_VERT, fragmentShader: RAYS_FRAG, transparent: true, depthWrite: false, side: THREE.DoubleSide, ...ADDITIVE })))
    const rays2 = rays.clone(); rays2.rotation.y = Math.PI / 2
    const raysGroup = new THREE.Group(); raysGroup.add(rays, rays2); raysGroup.renderOrder = 6; bag.add(raysGroup)
    const mouth = new THREE.Object3D(); bag.add(mouth)

    let lastOpen = -1, lastCordKey = ''
    const state = { neckY: 1.38, neckR: 0.2, top: TOP0 }
    const shape = (open, t) => {
      const keys = closedKeys.map(([y, r], n) => [lerp(y, openKeys[n][0], open), lerp(r, openKeys[n][1], open)])
      const top = keys[keys.length - 1][0]
      const neckY = lerp(1.42, 1.33, open), neckR = lerp(0.2, 0.68, open)
      Object.assign(state, { neckY, neckR, top })
      if (Math.abs(open - lastOpen) > 1e-4) {
        lastOpen = open
        for (let j = 0; j <= RINGS; j++) {
          const y = top * j / RINGS
          const r0 = radiusAt(keys, y)
          const ruffle = ss(neckY, top, y)
          const pleat = Math.exp(-(((y - neckY) / 0.34) ** 2)) * (1 - 0.75 * open)
          for (let i = 0; i <= SEG; i++) {
            const phi = -Math.PI + Math.PI * 2 * i / SEG
            const r = r0 * (1 + 0.03 * Math.sin(phi * 3 + 1.3) * Math.sin(y * 3.1)
              + pleat * LOOK.pleat * Math.sin(phi * 16)
              + ruffle * LOOK.ruffle * (1 - open * 0.5) * Math.sin(phi * 7 + 0.6 * Math.sin(phi * 3)))
            const yy = y + ruffle * 0.06 * (1 - open * 0.4) * Math.sin(phi * 7 + 1)
            const k = (j * (SEG + 1) + i) * 3
            positions[k] = Math.sin(phi) * r; positions[k + 1] = yy; positions[k + 2] = Math.cos(phi) * r
          }
        }
        bagGeo.attributes.position.needsUpdate = true
        bagGeo.computeVertexNormals()
        bagGeo.computeBoundingSphere()
      }
      // drawstring: a loop through the neck plus two strands that shorten as the pouch loosens
      const cordKey = open.toFixed(3)
      if (cordKey !== lastCordKey) {
        lastCordKey = cordKey
        const loopR = neckR + 0.035
        const loopPts = Array.from({ length: 48 }, (_, n) => { const a = n / 48 * Math.PI * 2; const w = 1 + 0.06 * (1 - open) * Math.sin(a * 16); return v3(Math.sin(a) * loopR * w, neckY + 0.015 * Math.sin(a * 5), Math.cos(a) * loopR * w) })
        loopMesh.geometry?.dispose(); loopMesh.geometry = new THREE.TubeGeometry(new THREE.CatmullRomCurve3(loopPts, true), 96, 0.024, 8, true)
        const length = lerp(0.95, 0.32, open)
        strands.forEach((strand, side) => {
          const sign = side ? 1 : -1
          const pts = []
          for (let n = 0; n <= 7; n++) {
            const k = n / 7, y = neckY - length * k
            const phi = sign * (0.32 + 0.3 * k)
            const r = (n === 0 ? loopR : radiusAt(keys, Math.max(0.1, y)) + 0.05 + 0.03 * k)
            pts.push(v3(Math.sin(phi) * r, y, Math.cos(phi) * r))
          }
          strand.geometry?.dispose(); strand.geometry = new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 40, 0.02, 8, false)
          const end = pts[pts.length - 1]
          beads[side].position.set(end.x, end.y - 0.07, end.z)
        })
        grommets.forEach((g, n) => { const a = n / grommets.length * Math.PI * 2; g.position.set(Math.sin(a) * (neckR + 0.01), neckY + 0.05, Math.cos(a) * (neckR + 0.01)); g.lookAt(0, neckY + 0.05, 0) })
      }
      mouth.position.set(0, neckY + 0.05, 0)
      mouthGlow.position.set(0, neckY - 0.02, 0); mouthGlow.scale.setScalar(neckR * 2.6)
      raysGroup.position.set(0, neckY + 2.35, 0)
    }
    shape(0, 0)

    const update = (t, open, glow) => {
      shape(open, t)
      innerMat.emissiveIntensity = open * 0.75 * glow
      mouthGlow.material.uniforms.uI.value = open * 0.85 * glow
      for (const r of [rays, rays2]) { r.material.uniforms.uI.value = open * 0.75 * glow; r.material.uniforms.uTime.value = t }
      outerMat.emissiveIntensity = (body.emissiveIntensity || 0) * (0.75 + 0.25 * Math.sin(t * 2.4)) * (1 - 0.6 * open)
    }
    return { root, pivot, bag, mouth, update, state, height: 2.0, light: () => v3(0, state.neckY - 0.25, 0).applyMatrix4(bag.matrixWorld) }
  }

  function buildBox(style) {
    const dims = { window: [1.3, 1.75, 0.9], cube: [1.45, 1.45, 1.45], gift: [1.55, 1.12, 1.55], display: [2.7, 1.15, 1.75], chest: [2.5, 1.25, 1.55], crate: [2.5, 1.4, 1.65] }[style] || [1.4, 1.4, 1.4]
    const wooden = style === 'chest' || style === 'crate'
    const info = opts.caseInfo || {}
    const innerName = String(info.innerLabel || 'container').toUpperCase()
    const countLine = `${info.count || ''} SEALED ${info.count === 1 ? innerName : /(X|S|CH|SH)$/.test(innerName) ? innerName + 'ES' : innerName + 'S'}`.trim()
    const [W, H, D] = dims
    const TH = wooden ? 0.07 : 0.03
    const kraft = style === 'chest' ? mat(new THREE.MeshPhysicalMaterial({ color: '#5a0d2c', roughness: 0.95, sheen: 1, sheenColor: new THREE.Color('#ff5fa8'), sheenRoughness: 0.4 }))
      : style === 'crate' ? mat(new THREE.MeshStandardMaterial({ color: '#a8743f', roughness: 0.9 }))
      : mat(new THREE.MeshStandardMaterial({ color: '#b98c5c', roughness: 0.92 }))
    const edge = mat(new THREE.MeshStandardMaterial({ color: wooden ? '#5c3818' : '#e0c093', roughness: 0.85 }))
    const gold = mat(new THREE.MeshStandardMaterial({ color: '#d9a93c', metalness: 0.95, roughness: 0.28 }))
    const darkWood = mat(new THREE.MeshStandardMaterial({ color: '#4a2c12', roughness: 0.8 }))
    const printMat = (c, extra = {}) => mat(new THREE.MeshPhysicalMaterial({ map: tex(c), roughness: 0.38, clearcoat: 0.45, clearcoatRoughness: 0.3, ...extra }))
    const face = (w, h, draw) => { const scale = 512 / Math.max(w, h); const [c, g] = makeCanvas(Math.round(w * scale), Math.round(h * scale)); draw(g, c.width, c.height); return c }

    // ---------------- prints
    const sidePrint = (w, h, variant) => face(w, h, (g, cw, ch) => {
      if (style === 'gift') {
        g.fillStyle = '#b51896'; g.fillRect(0, 0, cw, ch)
        g.save(); g.globalAlpha = 0.85
        for (let y = 20; y < ch; y += 64) for (let x = (y / 64) % 2 ? 46 : 14; x < cw; x += 64) { questionMark(g, x, y, 30, { fill: (x + y) % 3 ? YELLOW : CYAN, glow: 'rgba(0,0,0,0)' }) }
        g.restore()
        const rw = cw * 0.16; g.fillStyle = YELLOW; g.fillRect(cw / 2 - rw / 2, 0, rw, ch)
        g.fillStyle = 'rgba(0,0,0,.18)'; g.fillRect(cw / 2 - rw / 2, 0, 5, ch); g.fillRect(cw / 2 + rw / 2 - 5, 0, 5, ch)
        return
      }
      if (style === 'crate') {
        woodPanel(g, cw, ch, { boards: variant === 'lid' ? 1 : 5, base: '#9a6533' })
        if (variant === 'front' || variant === 'back') {
          g.save(); g.globalAlpha = 0.82
          text(g, 'META COMICS', cw / 2, ch * 0.36, ch * 0.2, { fill: '#1b0d05', font: 'Impact, "Arial Black", sans-serif' })
          text(g, countLine, cw / 2, ch * 0.58, ch * 0.075, { fill: '#1b0d05', font: 'Arial, sans-serif', weight: 'bold' })
          text(g, '★ FRAGILE · COLLECTIBLES ★', cw / 2, ch * 0.75, ch * 0.06, { fill: '#7a1010', font: 'Arial, sans-serif', weight: 'bold' })
          g.restore()
        } else if (variant === 'side') { g.save(); g.globalAlpha = 0.75; questionMark(g, cw / 2, ch * 0.52, ch * 0.55, { fill: '#1b0d05', glow: 'rgba(0,0,0,0)' }); g.restore() }
        return
      }
      if (style === 'chest') {
        woodPanel(g, cw, ch, { boards: 3, base: '#6b3a1c', gaps: false })
        g.fillStyle = '#c99532'; for (const x of [cw * 0.14, cw * 0.86]) g.fillRect(x - cw * 0.025, 0, cw * 0.05, ch)
        if (variant === 'front') {
          g.save(); roundRect(g, cw * 0.39, ch * 0.18, cw * 0.22, ch * 0.5, cw * 0.02); g.fillStyle = '#d9a93c'; g.fill(); g.strokeStyle = '#7a5410'; g.lineWidth = 4; g.stroke(); g.restore()
          questionMark(g, cw / 2, ch * 0.42, ch * 0.32, { fill: '#5a3a08', glow: 'rgba(0,0,0,0)' })
          brand(g, cw / 2, ch * 0.83, ch * 0.08, { meta: '#ffd23c', comics: '#ffd23c', stroke: '#2a1404' })
        }
        return
      }
      comicPanel(g, cw, ch)
      if (style === 'display') {
        if (variant === 'front') {
          drawPackCrop(g, packArt, cw * 0.06, ch * 0.08, cw * 0.24, ch * 0.84)
          brand(g, cw * 0.62, ch * 0.32, ch * 0.16)
          text(g, countLine, cw * 0.62, ch * 0.68, ch * 0.085, { fill: YELLOW, stroke: '#2b0430', strokeWidth: ch * 0.02 })
          text(g, 'COLLECTOR DISPLAY', cw * 0.62, ch * 0.84, ch * 0.06, { fill: CYAN, stroke: '#2b0430', strokeWidth: ch * 0.015 })
        } else if (variant === 'lid') { brand(g, cw * 0.3, ch * 0.5, ch * 0.18); text(g, countLine, cw * 0.7, ch * 0.5, ch * 0.09, { fill: YELLOW, stroke: '#2b0430', strokeWidth: ch * 0.02 }) }
        else questionMark(g, cw / 2, ch * 0.55, ch * 0.6, { fill: CYAN, glow: '#0aa', stroke: '#1d0630' })
        return
      }
      if (variant === 'front' && style === 'cube') {
        drawPackCrop(g, packArt, cw * 0.18, ch * 0.08, cw * 0.64, ch * 0.62)
        text(g, 'MYSTERY PLUSHIE', cw / 2, ch * 0.82, cw * 0.085, { fill: YELLOW, stroke: '#2b0430', strokeWidth: cw * 0.018 })
      } else if (variant === 'front' && style === 'window') {
        g.fillStyle = 'rgba(10,4,16,.55)'; g.fillRect(0, 0, cw, ch * 0.2)
        brand(g, cw / 2, ch * 0.1, ch * 0.05)
        text(g, 'COLLECTOR PLUSHIE', cw / 2, ch * 0.92, cw * 0.075, { fill: YELLOW, stroke: '#2b0430', strokeWidth: cw * 0.016 })
        // window cut-out (made transparent below)
      } else {
        questionMark(g, cw / 2, ch * 0.56, ch * 0.5, { fill: CYAN, glow: '#0aa', stroke: '#1d0630' })
        brand(g, cw / 2, ch * 0.16, ch * 0.065)
      }
    })
    const cutWindow = c => {
      const g = c.getContext('2d'); g.save(); g.globalCompositeOperation = 'destination-out'
      roundRect(g, c.width * 0.12, c.height * 0.24, c.width * 0.76, c.height * 0.6, c.width * 0.06); g.fill(); g.restore()
      g.save(); g.strokeStyle = YELLOW; g.lineWidth = c.width * 0.02; roundRect(g, c.width * 0.12, c.height * 0.24, c.width * 0.76, c.height * 0.6, c.width * 0.06); g.stroke(); g.restore()
      return c
    }

    const root = new THREE.Group(), pivot = new THREE.Group(), box = new THREE.Group()
    root.add(pivot); pivot.add(box)
    const panel = (w, h, outsideMat, insideMat = kraft) => {
      const g = geo(new THREE.BoxGeometry(w, h, TH)); g.translate(0, h / 2, 0)
      return new THREE.Mesh(g, [edge, edge, edge, edge, outsideMat, insideMat])
    }
    const walls = {}
    const frontCanvas = sidePrint(W, H, 'front')
    const windowed = style === 'window'
    if (windowed) cutWindow(frontCanvas)
    const frontMat = printMat(frontCanvas, windowed ? { transparent: true, alphaTest: 0.5 } : {})
    const frontInside = windowed ? mat(new THREE.MeshStandardMaterial({ color: '#b98c5c', roughness: 0.92, alphaMap: frontMat.map, alphaTest: 0.5, transparent: true })) : kraft
    const wallDefs = [
      ['front', W, frontMat, frontInside, [0, 0, D / 2 - TH / 2], 0],
      ['back', W, printMat(sidePrint(W, H, 'back')), kraft, [0, 0, -D / 2 + TH / 2], Math.PI],
      ['left', D, printMat(sidePrint(D, H, 'side')), kraft, [-W / 2 + TH / 2, 0, 0], -Math.PI / 2],
      ['right', D, printMat(sidePrint(D, H, 'side')), kraft, [W / 2 - TH / 2, 0, 0], Math.PI / 2],
    ]
    for (const [name, w, outside, insideMat, p, ry] of wallDefs) {
      const hinge = new THREE.Group(); hinge.position.set(...p)
      const m = panel(w, H, outside, insideMat); m.rotation.y = ry
      hinge.add(m); box.add(hinge); walls[name] = hinge
    }
    const bottom = new THREE.Mesh(geo(new THREE.BoxGeometry(W, TH, D)), kraft); bottom.position.y = TH / 2; box.add(bottom)
    if (windowed) {
      const plastic = new THREE.Mesh(geo(new THREE.PlaneGeometry(W * 0.78, H * 0.62)), mat(new THREE.MeshPhysicalMaterial({ color: '#ffffff', transparent: true, opacity: 0.16, roughness: 0.04, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.05, depthWrite: false })))
      plastic.position.set(0, H * 0.46, -0.04); walls.front.add(plastic)
      const header = face(W * 0.9, 0.36, (g, cw, ch) => { comicPanel(g, cw, ch, { base: '#7a1a8f', deep: '#2b0a3c' }); text(g, 'META COMICS', cw / 2, ch * 0.62, ch * 0.42, { fill: YELLOW, stroke: '#16031d', strokeWidth: 8 }) })
      const hg = header.getContext('2d'); hg.save(); hg.globalCompositeOperation = 'destination-out'; hg.beginPath(); hg.ellipse(header.width / 2, header.height * 0.2, header.width * 0.07, header.height * 0.1, 0, 0, Math.PI * 2); hg.fill(); hg.restore()
      const hang = panel(W * 0.9, 0.36, printMat(header, { transparent: true, alphaTest: 0.5 }))
      hang.position.set(0, H, 0); hang.rotation.y = Math.PI; walls.back.add(hang)
    }

    // ---------------- top pieces
    const tops = []
    const topPrint = (w, d, variant) => printMat(face(w, d, (g, cw, ch) => {
      if (style === 'gift') { g.fillStyle = '#b51896'; g.fillRect(0, 0, cw, ch); drawPackCrop(g, packArt, cw * 0.2, ch * 0.1, cw * 0.6, ch * 0.8); return }
      comicPanel(g, cw, ch)
      if (variant === 'q') questionMark(g, cw / 2, ch / 2, Math.min(cw, ch) * 0.7, { fill: YELLOW, glow: '#ff9d1f', stroke: '#1d0630' })
      else brand(g, cw / 2, ch / 2, Math.min(cw, ch) * 0.2)
    }))
    if (style === 'chest') {
      // domed lid hinged at the back, with gold bands
      const hinge = new THREE.Group(); hinge.position.set(0, H, -TH / 2)
      const R = D / 2
      const dome = geo(new THREE.CylinderGeometry(R, R, W, 32, 1, false, 0, Math.PI)); dome.rotateZ(Math.PI / 2); dome.scale(1, 0.55, 1); dome.translate(0, 0, R - TH / 2)
      const lidCanvas = face(W, D * 1.6, (g, cw, ch) => { woodPanel(g, cw, ch, { boards: 4, base: "#6b3a1c", gaps: false, vertical: true }) })
      const woodLid = printMat(lidCanvas, { clearcoat: 0.2, roughness: 0.6, side: THREE.DoubleSide })
      const lidMesh = new THREE.Mesh(dome, [woodLid, darkWood, darkWood])
      hinge.add(lidMesh)
      for (const x of [-W * 0.36, W * 0.36]) {
        const band = geo(new THREE.TorusGeometry(R, 0.03, 8, 32, Math.PI)); band.rotateY(Math.PI / 2); band.scale(1, 0.55, 1); band.translate(x, 0, R - TH / 2)
        hinge.add(new THREE.Mesh(band, gold))
      }
      const latch = new THREE.Mesh(geo(new THREE.BoxGeometry(0.22, 0.2, 0.04)), gold); latch.position.set(0, -0.06, D - TH + 0.01); hinge.add(latch)
      walls.back.add(hinge)
      tops.push({ node: hinge, open: k => { hinge.rotation.x = -1.95 * outBack(k, 1.1) } })
    } else if (style === 'crate') {
      // loose lid boards that pop off one by one
      const boards = 4, bw = D / boards
      for (let b = 0; b < boards; b++) {
        const plank = new THREE.Group(); plank.position.set(0, H + 0.035, -D / 2 + bw * (b + 0.5))
        const m = new THREE.Mesh(geo(new THREE.BoxGeometry(W + 0.08, 0.07, bw - 0.02)), [edge, edge, printMat(sidePrint(W, bw, 'lid')), darkWood, edge, edge])
        plank.add(m); box.add(plank)
        const side = b % 2 ? 1 : -1, z0 = plank.position.z
        tops.push({ node: plank, direct: true, open: k => {
          const q = clamp(k * 1.6 - (boards - 1 - b) * 0.18)
          plank.position.set(side * 2.2 * ss(0.2, 1, q), H + 0.035 + 1.6 * Math.sin(q * Math.PI * 0.9) * (1 - ss(0.7, 1, q) * 0.6) - 1.2 * ss(0.75, 1, q), z0 + 0.6 * q)
          plank.rotation.set(0.8 * q, 0, side * -2.6 * q)
        } })
      }
      for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
        const post = new THREE.Mesh(geo(new THREE.BoxGeometry(0.12, H + 0.04, 0.12)), darkWood); post.position.set(x * (W / 2 + 0.02), H / 2, z * (D / 2 + 0.02))
        walls[z > 0 ? 'front' : 'back'].add(post); post.position.set(x * (W / 2 + 0.02), H / 2, z > 0 ? 0.05 : -0.05)
      }
    } else if (style === 'window' || style === 'display') {
      const hinge = new THREE.Group(); hinge.position.set(0, H, -TH / 2)
      const lidGeo = geo(new THREE.BoxGeometry(W, TH, D)); lidGeo.translate(0, TH / 2, D / 2)
      const lid = new THREE.Mesh(lidGeo, [edge, edge, style === 'display' ? printMat(sidePrint(W, D, 'lid')) : topPrint(W, D, 'brand'), kraft, edge, edge])
      const tabGeo = geo(new THREE.BoxGeometry(W * 0.96, 0.22, TH)); tabGeo.translate(0, -0.11, 0)
      const tab = new THREE.Mesh(tabGeo, kraft); tab.position.set(0, 0, D - TH)
      hinge.add(lid, tab); walls.back.add(hinge)
      tops.push({ node: hinge, open: k => { hinge.rotation.x = -2.05 * k; tab.rotation.x = 0.9 * k } })
    } else if (style === 'cube') {
      const flap = (w, d, wall, pos, axis, sign, lift, variant) => {
        const hinge = new THREE.Group(); hinge.position.set(...pos); hinge.position.y += lift
        const g = geo(new THREE.BoxGeometry(w, TH, d))
        if (axis === 'x') g.translate(0, TH / 2, -sign * d / 2); else g.translate(-sign * w / 2, TH / 2, 0)
        hinge.add(new THREE.Mesh(g, [edge, edge, topPrint(w, d, variant), kraft, edge, edge])); walls[wall].add(hinge)
        return { node: hinge, open: k => { if (axis === 'x') hinge.rotation.x = sign * 2.35 * k; else hinge.rotation.z = -sign * 2.35 * k } }
      }
      // outer flaps (front/back) open first, then the side flaps
      tops.push(flap(W, D / 2 - TH / 2, 'front', [0, H, TH / 2], 'x', 1, TH, 'q'), flap(W, D / 2 - TH / 2, 'back', [0, H, -TH / 2], 'x', -1, TH, 'brand'))
      tops.push(flap(W / 2 - TH / 2, D, 'left', [-TH / 2, H, 0], 'z', -1, 0, 'q'), flap(W / 2 - TH / 2, D, 'right', [TH / 2, H, 0], 'z', 1, 0, 'q'))
    } else {
      const lid = new THREE.Group(); lid.position.y = H - 0.22
      const LW = W + 0.07, LD = D + 0.07, LH = 0.3
      const lidTop = new THREE.Mesh(geo(new THREE.BoxGeometry(LW, TH, LD)), [edge, edge, topPrint(LW, LD, 'pack'), kraft, edge, edge]); lidTop.position.y = LH
      lid.add(lidTop)
      const skirt = (w, x, z, ry) => { const m = panel(w, LH, printMat(sidePrint(w, LH * 3, 'skirt'))); m.position.set(x, 0, z); m.rotation.y = ry; lid.add(m) }
      skirt(LW, 0, LD / 2, 0); skirt(LW, 0, -LD / 2, Math.PI); skirt(LD, -LW / 2, 0, -Math.PI / 2); skirt(LD, LW / 2, 0, Math.PI / 2)
      const ribbonMat = mat(new THREE.MeshPhysicalMaterial({ color: YELLOW, roughness: 0.25, sheen: 1, sheenColor: new THREE.Color('#fff4c0'), clearcoat: 0.6 }))
      for (const [w, d] of [[LW + 0.01, 0.22], [0.22, LD + 0.01]]) { const r = new THREE.Mesh(geo(new THREE.BoxGeometry(w, 0.02, d)), ribbonMat); r.position.y = LH + 0.02; lid.add(r) }
      for (const side of [-1, 1]) {
        const loop = new THREE.Mesh(geo(new THREE.TorusGeometry(0.2, 0.06, 14, 32)), ribbonMat)
        loop.scale.set(1.2, 0.75, 0.5); loop.position.set(side * 0.2, LH + 0.15, 0); loop.rotation.set(0, 0, side * 0.35); lid.add(loop)
      }
      const knot = new THREE.Mesh(geo(new THREE.SphereGeometry(0.09, 18, 14)), ribbonMat); knot.position.y = LH + 0.1; lid.add(knot)
      box.add(lid)
      tops.push({ node: lid, open: k => { lid.position.set(-0.9 * ss(0.35, 1, k), H - 0.22 + 1.2 * Math.sin(Math.min(k, 0.7) / 0.7 * Math.PI / 2) - 1.4 * ss(0.6, 1, k), -1.1 * ss(0.3, 1, k)); lid.rotation.set(-0.5 * k, 0.6 * k, 0.9 * ss(0.4, 1, k)) } })
    }

    const glow = new THREE.Mesh(geo(new THREE.PlaneGeometry(1, 1)), glowMaterial('#ff9bf0', 3.2))
    glow.rotation.x = -Math.PI / 2; glow.position.y = H + 0.01; glow.scale.set(W * 1.4, D * 1.4, 1); glow.renderOrder = 5; box.add(glow)
    const rays = new THREE.Mesh(geo(new THREE.PlaneGeometry(4.2, 4.8)), mat(new THREE.ShaderMaterial({ uniforms: { uI: { value: 0 }, uTime: { value: 0 }, uCol: { value: new THREE.Color('#ffd8fb') } }, vertexShader: SIMPLE_VERT, fragmentShader: RAYS_FRAG, transparent: true, depthWrite: false, side: THREE.DoubleSide, ...ADDITIVE })))
    const rays2 = rays.clone(); rays2.rotation.y = Math.PI / 2
    const raysGroup = new THREE.Group(); raysGroup.add(rays, rays2); raysGroup.position.y = H + 2.35; box.add(raysGroup)
    const mouth = new THREE.Object3D(); mouth.position.set(0, H * 0.4, 0); box.add(mouth)

    const update = (t, open, glowK, unfold = 0) => {
      tops.forEach((top, n) => top.open(top.direct ? clamp(open) : clamp(open * (tops.length > 2 ? 1.6 : 1) - (tops.length > 2 ? (n < 2 ? 0 : 0.6) : 0))))
      if (unfold > 0) {
        walls.front.rotation.x = 1.57 * ss(0, 0.8, unfold); walls.back.rotation.x = -1.57 * ss(0.1, 0.9, unfold)
        walls.left.rotation.z = 1.57 * ss(0.15, 0.95, unfold); walls.right.rotation.z = -1.57 * ss(0.2, 1, unfold)
      }
      glow.material.uniforms.uI.value = open * 0.55 * glowK * (1 - unfold)
      for (const r of [rays, rays2]) { r.material.uniforms.uI.value = open * 0.7 * glowK * (1 - unfold); r.material.uniforms.uTime.value = t }
    }
    if (style === 'chest') {
      for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) { const cap = new THREE.Mesh(geo(new THREE.BoxGeometry(0.14, H, 0.14)), gold); cap.position.set(x * W / 2, H / 2, z * D / 2); box.add(cap) }
    }
    return { root, pivot, bag: box, mouth, update, height: H + (style === 'window' ? 0.36 : style === 'chest' ? D * 0.3 : 0.1), state: { neckY: H }, light: () => v3(0, H * 0.55, 0).applyMatrix4(box.matrixWorld), H, W, D }
  }

  // one shared model per inner design; every sealed container in the case is a clone of it
  function buildMini(item, index) {
    const snapshot = item.containerSnapshot || {}
    const innerKind = snapshot.kind === 'bag' ? 'bag' : 'box'
    const innerStyle = snapshot.look?.style || (innerKind === 'bag' ? 'velvet' : 'window')
    const key = innerKind + ':' + innerStyle
    if (!miniCache.has(key)) {
      const proto = innerKind === 'bag' ? buildBag(innerStyle) : buildBox(innerStyle)
      proto.update(0, 0, 0)
      shadowCasting(proto.root)
      miniCache.set(key, proto)
    }
    const proto = miniCache.get(key)
    const scale = innerKind === 'bag' ? 0.36 : 0.42
    const root = new THREE.Group(), body = proto.root.clone(true)
    body.scale.setScalar(scale); root.add(body)
    const glow = new THREE.Mesh(geo(new THREE.PlaneGeometry(1, 1)), glowMaterial(MAGENTA, 2.4)); glow.visible = false; scene.add(glow)
    return { item, index, coin: false, mini: true, root, body, mats: [], swaps: [], glow, height: proto.height * scale, revealed: true, revealAt: -1, hover: 0, hoverTarget: 0, landed: false }
  }

  async function buildItem(item, index) {
    if (item.containerSnapshot) return buildMini(item, index)
    const coin = item.collectableType === 'challenge_coin' || (!item.collectableType && kind === 'bag')
    const accent = new THREE.Color(item.accent || '#c9a34d')
    const [front, back] = await Promise.all([loadImage(item.image), loadImage(item.backImage)])
    const root = new THREE.Group(), body = new THREE.Group(); root.add(body)
    const mats = []
    const track = m => { mats.push({ m }); return m }
    let height
    const finish = item.finish || 'none', finishK = clamp((item.finishStrength ?? 60) / 100)
    // Lab "finish" options carried into 3D: rainbow = iridescent film, metallic = polished, glitter = sparkly clearcoat
    const finishProps = base => ({
      ...base,
      ...(finish === 'rainbow' ? { iridescence: finishK, iridescenceIOR: 1.6, iridescenceThicknessRange: [180, 620] } : {}),
      ...(finish === 'metallic' ? { roughness: Math.max(0.08, (base.roughness ?? 0.4) * (1 - 0.7 * finishK)), metalness: Math.max(base.metalness ?? 0, 0.6 * finishK) } : {}),
      ...(finish === 'glitter' ? { clearcoat: finishK, clearcoatRoughness: 0.08, sheen: Math.max(base.sheen ?? 0, finishK), sheenColor: new THREE.Color('#ffffff') } : {}),
    })
    if (coin) {
      const R = 0.42, T = 0.075
      const [rimImg, edgeImg] = await Promise.all([loadImage(item.rimImage), loadImage(item.edgeImage)])
      const cover = (g, img, x, y, w, h) => { const k = Math.max(w / img.width, h / img.height); g.drawImage(img, x + (w - img.width * k) / 2, y + (h - img.height * k) / 2, img.width * k, img.height * k) }
      const faceTex = (img, isBack) => {
        const S = 512, [c, g] = makeCanvas(S, S), mid = S / 2
        const metal = g.createRadialGradient(S * 0.36, S * 0.3, 0, mid, mid, S * 0.6)
        metal.addColorStop(0, '#fff6d6'); metal.addColorStop(0.45, `#${accent.getHexString()}`); metal.addColorStop(1, '#2a1c06')
        g.fillStyle = metal; g.fillRect(0, 0, S, S)
        if (rimImg) {
          // custom rim artwork fills the ring around the face
          g.save(); g.beginPath(); g.arc(mid, mid, S * 0.5, 0, Math.PI * 2); g.arc(mid, mid, S * 0.4, 0, Math.PI * 2, true); g.clip('evenodd'); cover(g, rimImg, 0, 0, S, S)
          const shade = g.createRadialGradient(mid, mid, S * 0.4, mid, mid, S * 0.5); shade.addColorStop(0, 'rgba(0,0,0,.35)'); shade.addColorStop(0.5, 'rgba(255,255,255,.12)'); shade.addColorStop(1, 'rgba(0,0,0,.4)')
          g.fillStyle = shade; g.fillRect(0, 0, S, S); g.restore()
        }
        g.save(); g.beginPath(); g.arc(mid, mid, S * 0.4, 0, Math.PI * 2); g.clip()
        if (img) {
          const fx = clamp(Number(isBack ? 50 : item.imagePositionX ?? 50), 0, 100) / 100, fy = clamp(Number(isBack ? 50 : item.imagePositionY ?? 50), 0, 100) / 100
          const zoom = clamp(Number(isBack ? 100 : item.imageZoom ?? 100), 100, 220) / 100, box = S * 0.8
          const k = Math.max(box / img.width, box / img.height) * zoom, w = img.width * k, h = img.height * k
          g.drawImage(img, mid - box / 2 + (box - w) * fx, mid - box / 2 + (box - h) * fy, w, h)
          const v = g.createRadialGradient(mid, mid, S * 0.28, mid, mid, S * 0.4); v.addColorStop(0, 'rgba(0,0,0,0)'); v.addColorStop(1, 'rgba(0,0,0,.45)'); g.fillStyle = v; g.fillRect(0, 0, S, S)
        } else {
          const ink = 'rgba(40,24,4,.75)', hi = 'rgba(255,244,210,.55)'
          const star = (dx, dy, color) => { g.save(); g.translate(mid + dx, mid + dy); g.beginPath(); for (let n = 0; n < 10; n++) { const r = n % 2 ? S * 0.09 : S * 0.22, a = -Math.PI / 2 + n * Math.PI / 5; g.lineTo(Math.cos(a) * r, Math.sin(a) * r) } g.closePath(); g.fillStyle = color; g.fill(); g.restore() }
          if (isBack) { text(g, 'MC', mid + 3, mid + 4, S * 0.26, { fill: hi }); text(g, 'MC', mid, mid, S * 0.26, { fill: ink }) }
          else { star(3, 4, hi); star(0, 0, ink); text(g, (item.title || '').slice(0, 16).toUpperCase(), mid, mid + S * 0.29, S * 0.045, { fill: ink, font: 'Arial, sans-serif', weight: 'bold' }) }
        }
        g.restore()
        g.lineWidth = S * 0.012; g.strokeStyle = 'rgba(40,24,4,.6)'; g.beginPath(); g.arc(mid, mid, S * 0.405, 0, Math.PI * 2); g.stroke()
        if (!rimImg) {
          const runes = ['ᚠ', 'ᚢ', 'ᚦ', 'ᚨ', 'ᚱ', 'ᚲ', 'ᚷ', 'ᚹ', 'ᚺ', 'ᚾ', 'ᛁ', 'ᛃ', 'ᛇ', 'ᛈ', 'ᛉ', 'ᛊ', 'ᛏ', 'ᛒ', 'ᛖ', 'ᛗ', 'ᛚ', 'ᛜ', 'ᛞ', 'ᛟ']
          g.save(); g.translate(mid, mid)
          runes.forEach((rune, n) => { g.save(); g.rotate(n / runes.length * Math.PI * 2); text(g, rune, 0, -S * 0.445, S * 0.05, { fill: 'rgba(40,24,4,.8)', font: '"Segoe UI Historic", "Noto Sans Runic", serif' }); g.restore() })
          g.restore()
        }
        g.lineWidth = S * 0.02; g.strokeStyle = 'rgba(255,240,200,.55)'; g.beginPath(); g.arc(mid, mid, S * 0.485, 0, Math.PI * 2); g.stroke()
        // the cylinder caps map u down the coin and v across it; a quarter turn puts the artwork upright
        const t = tex(c); t.center.set(0.5, 0.5); t.rotation = Math.PI / 2; return t
      }
      // edge: custom artwork wrapped round the rim, or a minted pattern
      const [ec, eg] = makeCanvas(1024, 32)
      const edgeStyle = item.edgeStyle || 'reeded'
      eg.fillStyle = `#${accent.getHexString()}`; eg.fillRect(0, 0, 1024, 32)
      if (edgeImg) {
        const tile = Math.max(8, 32 * edgeImg.width / edgeImg.height)
        for (let x = 0; x < 1024; x += tile) eg.drawImage(edgeImg, x, 0, tile, 32)
      } else if (edgeStyle === 'reeded') {
        for (let x = 0; x < 1024; x += 6) { eg.fillStyle = 'rgba(0,0,0,.35)'; eg.fillRect(x, 0, 2, 32); eg.fillStyle = 'rgba(255,255,255,.25)'; eg.fillRect(x + 2, 0, 1, 32) }
      } else if (edgeStyle === 'rope') {
        eg.strokeStyle = 'rgba(0,0,0,.4)'; eg.lineWidth = 3
        for (let x = -32; x < 1056; x += 10) { eg.beginPath(); eg.moveTo(x, 32); eg.lineTo(x + 18, 0); eg.stroke() }
      } else if (edgeStyle === 'studded') {
        for (let x = 8; x < 1024; x += 16) { const gr = eg.createRadialGradient(x - 2, 14, 0, x, 16, 6); gr.addColorStop(0, 'rgba(255,255,255,.7)'); gr.addColorStop(1, 'rgba(0,0,0,.35)'); eg.fillStyle = gr; eg.beginPath(); eg.arc(x, 16, 5, 0, Math.PI * 2); eg.fill() }
      } else if (edgeStyle === 'lettered') {
        const label = ` ${(item.title || 'META COMICS').toUpperCase()} ✦ META COMICS ✦`
        eg.font = 'bold 18px Arial, sans-serif'
        const step = Math.max(40, eg.measureText(label).width)
        for (let x = 0; x < 1024; x += step) text(eg, label, x, 17, 18, { fill: 'rgba(40,24,4,.75)', font: 'Arial, sans-serif', weight: 'bold', align: 'left' })
      }
      const edgeTex = tex(ec); edgeTex.wrapS = THREE.RepeatWrapping
      const imageFace = !!front
      const faceMat = map => track(mat(new THREE.MeshPhysicalMaterial(finishProps({ map, bumpMap: map, bumpScale: 1.4, metalness: imageFace ? 0.35 : 0.78, roughness: imageFace ? 0.4 : 0.34 }))))
      const g = geo(new THREE.CylinderGeometry(R, R, T, 96, 1)); g.rotateX(Math.PI / 2)
      const sideMat = track(mat(new THREE.MeshPhysicalMaterial(finishProps({ map: edgeTex, bumpMap: edgeTex, bumpScale: 1, metalness: edgeImg ? 0.5 : 0.95, roughness: 0.28 }))))
      body.add(new THREE.Mesh(g, [sideMat, faceMat(faceTex(front, false)), faceMat(faceTex(back, true))]))
      height = R * 2
    } else {
      // plushie: a closed, puffy shape. The artwork's outline is blurred into a height field, and the visible
      // edge is cut exactly where that height reaches zero, so the front and back halves meet with no gap.
      const S = 320, P = 1.3, PAD = 0.1
      const trimCache = new Map()
      const trim = img => {
        if (trimCache.has(img)) return trimCache.get(img)
        let box = [0, 0, img.width, img.height]
        try {
          const k = Math.min(1, 400 / Math.max(img.width, img.height)), w = Math.max(1, Math.round(img.width * k)), h = Math.max(1, Math.round(img.height * k))
          const [, tg] = makeCanvas(w, h); tg.drawImage(img, 0, 0, w, h)
          const data = tg.getImageData(0, 0, w, h).data
          let x0 = w, y0 = h, x1 = -1, y1 = -1
          for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (data[(y * w + x) * 4 + 3] > 40) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y }
          if (x1 >= x0 && y1 >= y0) box = [x0 / k, y0 / k, (x1 - x0 + 1) / k, (y1 - y0 + 1) / k]
        } catch { /* cross-origin artwork: draw it whole */ }
        trimCache.set(img, box); return box
      }
      const drawArt = (ctx, img, mirror) => {
        ctx.save(); if (mirror) { ctx.translate(S, 0); ctx.scale(-1, 1) }
        const room = S * (1 - PAD * 2)
        if (img) { const [sx, sy, sw, sh] = trim(img); const k = Math.min(room / sw, room / sh); ctx.drawImage(img, sx, sy, sw, sh, (S - sw * k) / 2, (S - sh * k) / 2, sw * k, sh * k) }
        else { ctx.font = `${S * 0.66}px "Segoe UI Emoji", "Apple Color Emoji", "Noto Color Emoji", sans-serif`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText('🧸', S / 2, S * 0.54) }
        ctx.restore()
      }
      // colour layer: the art, with its edge colours smeared outward so the cut never shows a transparent fringe
      const paint = (img, mirror) => {
        const [c, g] = makeCanvas(S, S)
        const [ac] = makeCanvas(S, S); drawArt(ac.getContext('2d'), img, mirror)
        for (const r of [6, 4, 2]) for (let a = 0; a < 8; a++) g.drawImage(ac, Math.round(Math.cos(a * Math.PI / 4) * r), Math.round(Math.sin(a * Math.PI / 4) * r))
        g.drawImage(ac, 0, 0)
        return c
      }
      const frontArt = paint(front, false)
      let mask = null, inside = null, outside = null, maxD = 1, lowest = S - 1, topmost = 0
      // chamfer (3-4) distance from every pixel where `on` is true to the nearest pixel where it is false
      const chamfer = on => {
        const d = new Float32Array(S * S)
        for (let n = 0; n < S * S; n++) d[n] = on(n) ? 1e9 : 0
        const at = (x, y) => (x < 0 || y < 0 || x >= S || y >= S) ? 0 : d[y * S + x]
        for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) { const n = y * S + x; if (d[n]) d[n] = Math.min(d[n], at(x - 1, y) + 3, at(x, y - 1) + 3, at(x - 1, y - 1) + 4, at(x + 1, y - 1) + 4) }
        for (let y = S - 1; y >= 0; y--) for (let x = S - 1; x >= 0; x--) { const n = y * S + x; if (d[n]) d[n] = Math.min(d[n], at(x + 1, y) + 3, at(x, y + 1) + 3, at(x + 1, y + 1) + 4, at(x - 1, y + 1) + 4) }
        for (let n = 0; n < S * S; n++) d[n] = Math.min(d[n] / 3, S)
        return d
      }
      try {
        // outline: lightly smoothed alpha, thresholded
        const [ac] = makeCanvas(S, S); drawArt(ac.getContext('2d'), front, false)
        const [, sg] = makeCanvas(S, S); sg.filter = 'blur(1.5px)'; sg.drawImage(ac, 0, 0)
        const raw = sg.getImageData(0, 0, S, S).data
        mask = new Uint8Array(S * S)
        for (let n = 0; n < S * S; n++) mask[n] = raw[n * 4 + 3] > 110 ? 1 : 0
        // distance inside the outline drives how far the stuffing puffs out; the outside distance lets the
        // outline vertices be placed exactly on the edge
        inside = chamfer(n => mask[n] === 1)
        outside = chamfer(n => mask[n] === 0)
        for (let n = 0; n < S * S; n++) if (inside[n] > maxD) maxD = inside[n]
        // soften the medial ridges of the inside distance (min keeps the edge itself at zero)
        const enc = new Uint8ClampedArray(S * S * 4)
        for (let n = 0; n < S * S; n++) enc[n * 4 + 3] = Math.round(inside[n] / maxD * 255)
        const [ec2, eg2] = makeCanvas(S, S); eg2.putImageData(new ImageData(enc, S, S), 0, 0)
        const [, bg] = makeCanvas(S, S); bg.filter = `blur(${Math.round(S * 0.035)}px)`; bg.drawImage(ec2, 0, 0)
        const soft = bg.getImageData(0, 0, S, S).data
        for (let n = 0; n < S * S; n++) inside[n] = Math.min(inside[n], soft[n * 4 + 3] / 255 * maxD)
        outer: for (let y = S - 1; y >= 0; y--) for (let x = 0; x < S; x++) if (mask[y * S + x]) { lowest = y; break outer }
        outer2: for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) if (mask[y * S + x]) { topmost = y; break outer2 }
      } catch { mask = null }
      const SEGS = 200
      const plane = geo(new THREE.PlaneGeometry(P, P, SEGS, SEGS))
      if (mask) {
        // One closed body: both halves share this grid, triangles outside the outline are dropped and the
        // outline vertices are moved onto the edge with zero depth, so front and back meet exactly.
        const pos = plane.attributes.position, uv = plane.attributes.uv
        const bilinear = (field, u, v) => {
          const x = clamp(u * (S - 1), 0, S - 1), y = clamp((1 - v) * (S - 1), 0, S - 1)
          const x0 = Math.floor(x), y0 = Math.floor(y), x1 = Math.min(S - 1, x0 + 1), y1 = Math.min(S - 1, y0 + 1), fx = x - x0, fy = y - y0
          return lerp(lerp(field[y0 * S + x0], field[y0 * S + x1], fx), lerp(field[y1 * S + x0], field[y1 * S + x1], fx), fy)
        }
        const N = SEGS + 1
        const signed = new Float32Array(N * N)
        for (let n = 0; n < N * N; n++) signed[n] = bilinear(inside, uv.getX(n), uv.getY(n)) - bilinear(outside, uv.getX(n), uv.getY(n)) - 0.5
        const zMax = (maxD / (S - 1)) * P * 0.62 // thickest point ~60% of the half-width: round, not a slab
        const moved = new Float32Array(N * N * 2)
        for (let n = 0; n < N * N; n++) {
          const s = signed[n]
          if (s > 0) { pos.setZ(n, zMax * Math.sqrt(Math.min(1, s / maxD))); continue }
          pos.setZ(n, 0)
          // outside vertex next to the body: slide it onto the zero crossing towards its inside neighbours
          const gx = n % N, gy = Math.floor(n / N)
          let sx = 0, sy = 0, su = 0, sv = 0, count = 0
          for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            const nx = gx + dx, ny = gy + dy
            if (nx < 0 || ny < 0 || nx >= N || ny >= N) continue
            const m = ny * N + nx
            if (signed[m] <= 0) continue
            const t = s / (s - signed[m])
            sx += lerp(pos.getX(n), pos.getX(m), t); sy += lerp(pos.getY(n), pos.getY(m), t)
            su += lerp(uv.getX(n), uv.getX(m), t); sv += lerp(uv.getY(n), uv.getY(m), t); count++
          }
          if (count) { moved[n * 2] = 1; pos.setXY(n, sx / count, sy / count); uv.setXY(n, su / count, sv / count) }
        }
        const keep = []
        const index = plane.index.array
        for (let k = 0; k < index.length; k += 3) {
          const a = index[k], b = index[k + 1], c = index[k + 2]
          if (signed[a] > 0 || signed[b] > 0 || signed[c] > 0) keep.push(a, b, c)
        }
        plane.setIndex(keep)
        plane.computeVertexNormals()
      }
      // print look: fabric tint, then seam stitching along the outline (both halves share the same uv)
      const outlines = mask ? traceOutlines(mask, S) : []
      const look = { color: item.stitchColor || '#f3e6cf', pattern: item.stitchPattern || 'running', width: Number(item.stitchWidth) || 2.2 }
      tintCanvas(frontArt, item.tint, clamp((item.tintStrength ?? 0) / 100))
      // colour reaches a few pixels past the outline (paint() smears it outward), so the edge never samples black
      const frontTex = tex(frontArt)
      const backArt = paint(back || front, !!back)
      // no back artwork: the back is the front's colours softened (no face showing through), a little darker
      if (!back) { const [cc] = makeCanvas(S, S); cc.getContext('2d').drawImage(backArt, 0, 0); const g2 = backArt.getContext('2d'); g2.clearRect(0, 0, S, S); g2.filter = `blur(${Math.round(S * 0.045)}px)`; g2.drawImage(cc, 0, 0); g2.drawImage(cc, 0, 0); g2.filter = 'none'; g2.globalCompositeOperation = 'source-atop'; g2.fillStyle = 'rgba(0,0,0,.16)'; g2.fillRect(0, 0, S, S) }
      tintCanvas(backArt, item.tint, clamp((item.tintStrength ?? 0) / 100))
      const backTex = tex(backArt)
      // fabric: matte with a soft fuzz sheen (kept low so lights never wash the colours out)
      const plush = map => track(mat(new THREE.MeshPhysicalMaterial(finishProps({ map, roughness: 0.92, sheen: 0.28, sheenRoughness: 0.8, sheenColor: accent.clone().lerp(new THREE.Color('#ffffff'), 0.5), envMapIntensity: 0.6 }))))
      const frontMesh = new THREE.Mesh(plane, plush(frontTex))
      const backMesh = new THREE.Mesh(plane, plush(backTex)); backMesh.scale.set(1, 1, -1)
      const holder = new THREE.Group(); holder.add(frontMesh, backMesh)
      // The seam: its own thin welt running round the very edge where the two halves meet (z = 0), in the
      // fabric's edge colour, with the stitch pattern wrapped along it - so there is one row of stitching.
      if (mask && look.pattern !== 'none') {
        let edge = [200, 160, 120]
        try {
          const data = frontArt.getContext('2d').getImageData(0, 0, S, S).data
          let rr = 0, gg = 0, bb = 0, n = 0
          for (const outline of outlines) for (let k = 0; k < outline.length; k += 3) {
            const x = Math.round(outline[k][0]), y = Math.round(outline[k][1]), o = (y * S + x) * 4
            if (data[o + 3] > 100) { rr += data[o]; gg += data[o + 1]; bb += data[o + 2]; n++ }
          }
          if (n) edge = [rr / n, gg / n, bb / n].map(v => Math.round(v * 0.85))
        } catch { /* tainted canvas: keep the default fabric colour */ }
        const radius = 0.012 * P
        for (const outline of outlines) {
          const pts = []
          for (let k = 0; k < outline.length; k += 2) pts.push(v3((outline[k][0] / (S - 1) - 0.5) * P, (0.5 - outline[k][1] / (S - 1)) * P, 0))
          if (pts.length < 8) continue
          const curve = new THREE.CatmullRomCurve3(pts, true, 'centripetal')
          const length = curve.getLength()
          const [sc, sg] = makeCanvas(128, 32)
          sg.fillStyle = `rgb(${edge.join(',')})`; sg.fillRect(0, 0, 128, 32)
          // stitches across the welt: v runs round the tube, so the thread sits across its outer side
          const thread = (draw, w) => { sg.save(); sg.lineCap = 'round'; sg.strokeStyle = 'rgba(0,0,0,.35)'; sg.lineWidth = w + 2; sg.translate(1, 1); draw(); sg.translate(-1, -1); sg.strokeStyle = look.color; sg.lineWidth = w; draw(); sg.restore() }
          const w = 2 + look.width * 1.4
          const line = (x0, y0, x1, y1) => { sg.moveTo(x0, y0); sg.lineTo(x1, y1) }
          if (look.pattern === 'cross') thread(() => { sg.beginPath(); line(10, 6, 54, 26); line(10, 26, 54, 6); line(74, 6, 118, 26); line(74, 26, 118, 6); sg.stroke() }, w * 0.8)
          else if (look.pattern === 'zigzag') thread(() => { sg.beginPath(); sg.moveTo(0, 8); sg.lineTo(32, 24); sg.lineTo(64, 8); sg.lineTo(96, 24); sg.lineTo(128, 8); sg.stroke() }, w * 0.8)
          else if (look.pattern === 'blanket') thread(() => { sg.beginPath(); line(0, 9, 128, 9); for (const x of [16, 48, 80, 112]) line(x, 9, x, 27); sg.stroke() }, w * 0.7)
          else if (look.pattern === 'double') thread(() => { sg.beginPath(); line(8, 11, 56, 11); line(72, 11, 120, 11); line(8, 21, 56, 21); line(72, 21, 120, 21); sg.stroke() }, w * 0.7)
          else thread(() => { sg.beginPath(); line(10, 16, 54, 16); line(74, 16, 118, 16); sg.stroke() }, w)
          const stitchTex = tex(sc); stitchTex.wrapS = THREE.RepeatWrapping; stitchTex.wrapT = THREE.RepeatWrapping
          stitchTex.repeat.set(Math.max(4, Math.round(length / (0.055 * P))), 1)
          // the tube's v wraps round its circumference; rotate so the stitch row faces outward (front and back
          // halves each see half of it)
          stitchTex.offset.set(0, 0.25)
          const tube = geo(new THREE.TubeGeometry(curve, Math.min(900, pts.length * 2), radius, 10, true))
          const seam = new THREE.Mesh(tube, track(mat(new THREE.MeshPhysicalMaterial({ map: stitchTex, roughness: 0.75, sheen: 0.4, sheenColor: new THREE.Color('#ffffff') }))))
          holder.add(seam)
        }
      }
      holder.position.y = P * (lowest / (S - 1) - 0.5) // feet on the floor
      body.add(holder)
      height = P * ((lowest - topmost) / (S - 1))
    }
    const glow = new THREE.Mesh(geo(new THREE.PlaneGeometry(1, 1)), glowMaterial(`#${accent.clone().lerp(new THREE.Color(MAGENTA), 0.4).getHexString()}`, 2.4))
    glow.renderOrder = 4; scene.add(glow)
    shadowCasting(body)
    const swaps = []
    body.traverse(o => {
      if (!o.isMesh) return
      const real = o.material
      const sil = Array.isArray(real) ? real.map(m => mat(new THREE.MeshBasicMaterial({ color: 0x050307, map: m.alphaTest ? m.map : null, alphaTest: m.alphaTest || 0 }))) : mat(new THREE.MeshBasicMaterial({ color: 0x050307, map: real.alphaTest ? real.map : null, alphaTest: real.alphaTest || 0 }))
      swaps.push({ mesh: o, real, sil }); o.material = sil
    })
    return { item, index, coin, root, body, mats, swaps, glow, height, revealed: false, revealAt: -1, hover: 0, hoverTarget: 0, landed: false }
  }

  function layoutSlots(list) {
    const n = Math.max(1, list.length)
    const coinRow = list[0]?.coin === true
    const cols = Math.min(n, n <= 5 ? n : Math.ceil(n / Math.ceil(n / 6)))
    const rows = Math.ceil(n / cols)
    const spacing = list[0]?.mini ? 0.95 : coinRow ? 1.05 : 1.55
    const scale = Math.min(1, 6.2 / (cols * spacing))
    const slots = list.map((it, i) => {
      const r = Math.floor(i / cols), inRow = Math.min(cols, n - r * cols), c = i - r * cols
      const x = (c - (inRow - 1) / 2) * spacing * scale
      const z = 1.75 - r * 1.05 * scale
      return { pos: v3(x, it.coin ? 0.82 : 0, z), scale }
    })
    return { slots, rows, width: cols * spacing * scale }
  }

  /* ================================================================ animation */

  let dist = 6.4
  const camState = { pos: v3(), look: v3() }
  const finalCam = () => {
    const rows = layout.rows
    const halfW = layout.width / 2 + 0.6
    const fit = halfW / Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2) / camera.aspect
    const d = Math.max(kind === 'bag' ? 5.2 : 6.6, fit + 1.6)
    const tall = items.length ? Math.max(...items.map(it => it.coin ? 1.2 : it.height * it.slot.scale)) : 1.2
    return { pos: v3(0, 1.4 + tall * 0.6 + rows * 0.45, 1.6 + d), look: v3(0, items.some(it => it.coin) ? 1.0 : tall * 0.55, 0.9 - rows * 0.2) }
  }
  const pose = (t, dt) => {
    const c = container
    const dropK = clamp(t / TL.drop)
    const drop = opts.preview ? 0 : (1 - outBounce(dropK)) * 2.2
    const charge = ss(TL.charge[0], TL.charge[1], t) * (1 - ss(TL.open[0], TL.open[0] + 0.2, t))
    const intense = anim === 'pop' || anim === 'burst' ? 2.2 : 1
    const wob = opts.preview ? 0 : charge * intense
    const open = opts.preview ? 0 : anim === 'pop' || anim === 'burst' ? outBack(clamp((t - TL.open[0]) / (TL.open[1] - TL.open[0])), 2.2) : inOut(clamp((t - TL.open[0]) / (TL.open[1] - TL.open[0])))
    const openC = clamp(open, 0, 1.15)
    const emergeEnd = TL.emerge + TL.flight + TL.stagger * Math.max(0, items.length - 1)
    const away = opts.preview ? 0 : ss(TL.emerge + 0.3, TL.emerge + 1.4, t)

    c.root.position.set(0, drop, -2.4 * away * (anim === 'unfold' ? 0.35 : 1))
    c.root.scale.setScalar(1 - 0.16 * away)
    c.bag.rotation.z = Math.sin(t * 19) * 0.05 * wob + Math.sin(t * 7) * 0.02 * wob
    c.bag.rotation.x = Math.sin(t * 13) * 0.03 * wob + (anim === 'float' ? 0.3 * ss(TL.open[0], TL.open[1], t) * (1 - away) : 0)
    c.bag.position.y = Math.abs(Math.sin(t * 9.5)) * 0.07 * wob
    const squash = 1 + Math.sin(t * 19) * 0.025 * wob
    c.bag.scale.set(squash, 2 - squash, squash)
    if (opts.preview) c.bag.rotation.y = Math.sin(t * 0.5) * 0.55
    else c.bag.rotation.y = 0

    if (anim === 'pour') {
      const tip = inOut(clamp((t - TL.tip[0]) / (TL.tip[1] - TL.tip[0])))
      c.pivot.position.set(0.72, 0, 0); c.bag.position.x = -0.72
      c.pivot.rotation.z = -1.42 * tip; c.pivot.rotation.y = -0.45 * tip
      c.pivot.position.y = 0.55 * Math.sin(tip * Math.PI) * 0.3
      c.root.position.x = -1.1 * tip
    }
    const unfold = anim === 'unfold' ? ss(TL.open[0] + 0.2, TL.open[1], t) : 0
    const burst = anim === 'burst' ? ss(TL.open[0], TL.open[1], t) : 0
    if (kind === 'bag') c.update(t, Math.min(1, openC), 1 - 0.55 * ss(emergeEnd, emergeEnd + 1, t))
    else c.update(t, anim === 'unfold' ? ss(TL.open[0], TL.open[0] + 0.25, t) : burst ? clamp(openC * 1.4) : Math.min(1, openC), 1 - 0.55 * ss(emergeEnd, emergeEnd + 1, t), unfold)
    c.root.updateMatrixWorld(true)

    // light from inside the container while it is open
    const lightPos = c.light()
    inner.position.copy(lightPos)
    inner.intensity = opts.preview ? 0 : 3.2 * Math.min(1, openC) * (1 - 0.7 * ss(emergeEnd, emergeEnd + 1, t))
    floorGlow.material.uniforms.uI.value = opts.preview ? 0.22 : 0.22 + 0.4 * Math.min(1, openC) * (1 - 0.5 * away)
    floorGlow.position.set(c.root.position.x, 0.005, c.root.position.z)

    // sparkles drifting out of the opening
    if (!opts.preview && t > TL.open[0] && t < emergeEnd && Math.random() < 0.7) emit(c.mouth.getWorldPosition(v3()), 2, { speed: 0.7, up: 1.6, spread: 0.6, size: 0.1 })

    // camera
    const base = { pos: v3(0, 1.75, dist), look: v3(0, 0.95, 0) }
    const peek = TL.peek ? { pos: v3(0, 4.3, 6.0), look: v3(0, 1.55, 0) } : anim === 'pop' || anim === 'burst' ? { pos: v3(0, 2.7, dist * 1.3), look: v3(0, 1.7, 0) } : { pos: v3(0, 2.2, dist * 0.95), look: v3(0, 0.95, 0) }
    const fin = finalCam()
    const toPeek = opts.preview ? 0 : inOut(ss(TL.open[0] - 0.2, TL.open[1], t))
    const toFinal = opts.preview ? 0 : inOut(ss(TL.emerge + (TL.peek ? 0.55 : 0.1), TL.emerge + TL.flight * (TL.peek ? 1.25 : 0.9), t))
    camState.pos.copy(base.pos).lerp(peek.pos, toPeek).lerp(fin.pos, toFinal)
    camState.look.copy(base.look).lerp(peek.look, toPeek).lerp(fin.look, toFinal)
    const shake = (anim === 'burst' || anim === 'pop') ? 0.03 * Math.exp(-Math.max(0, t - TL.open[0]) * 6) * (t > TL.open[0] ? 1 : 0) : 0
    camera.position.set(camState.pos.x + Math.sin(t * 90) * shake, camState.pos.y + Math.cos(t * 83) * shake, camState.pos.z)
    camera.lookAt(camState.look)

    // collectibles
    const mouthPos = c.mouth.getWorldPosition(v3())
    const mouthDir = v3(0, 1, 0).applyQuaternion(c.bag.getWorldQuaternion(new THREE.Quaternion()))
    items.forEach((it, i) => poseItem(it, i, t, dt, mouthPos, mouthDir))
  }

  const poseItem = (it, i, t, dt, mouthPos, mouthDir) => {
    const start = TL.emerge + i * TL.stagger
    const k = clamp((t - start) / TL.flight)
    const E = it.slot.pos, sc = it.slot.scale
    const insideVisible = kind === 'box' && opts.style === 'window' && t < start
    it.root.visible = t >= start || insideVisible
    const body = it.body
    let px, py, pz, rx = 0, ry = 0, rz = 0, s = 1
    if (t < start) {
      // waiting inside: visible through the window box's plastic
      const W = container.W || 1
      px = (i - (items.length - 1) / 2) * Math.min(0.5, W * 0.6 / Math.max(1, items.length)); py = 0.04; pz = 0
      s = 0.7
      it.root.position.set(px, py, pz).applyMatrix4(container.bag.matrixWorld)
      it.root.scale.setScalar(s * sc * container.root.scale.x)
      it.root.rotation.set(0, 0, 0)
      it.glow.material.uniforms.uI.value = 0; it.mark.material.opacity = 0
      applyReveal(it, 0, 0)
      return
    }
    const S = mouthPos
    if (anim === 'float' || anim === 'lift') {
      const A = v3(E.x * 0.25, (kind === 'bag' ? 2.95 : container.H + 1.0) + 0.14 * (i % 3), 0.25)
      if (k < 0.5) { const q = outCubic(k / 0.5); px = lerp(S.x, A.x, q); py = lerp(S.y, A.y, q); pz = lerp(S.z, A.z, q) }
      else { const q = inOut((k - 0.5) / 0.5); px = lerp(A.x, E.x, q); py = lerp(A.y, E.y, q) + Math.sin(q * Math.PI) * 0.3; pz = lerp(A.z, E.z, q) }
      ry = (1 - outCubic(k)) * Math.PI * (it.coin ? 7 : 2); rx = (1 - k) * 0.5
      s = lerp(0.5, 1, ss(0, 0.4, k))
    } else if (anim === 'pour') {
      const M = S.clone().addScaledVector(mouthDir, 0.85).add(v3(0, 0.15, 0.2))
      const L = v3(E.x, it.coin ? 0.42 : 0, E.z)
      if (k < 0.5) {
        const q = Math.pow(k / 0.5, 1.3)
        const a = S.clone().lerp(M, q), b = M.clone().lerp(L, q); const p = a.lerp(b, q)
        px = p.x; py = p.y; pz = p.z; rz = -k * 9; rx = k * 6
      } else if (k < 0.78) {
        const q = (k - 0.5) / 0.28
        px = L.x; pz = L.z; py = L.y + Math.abs(Math.sin(q * Math.PI * 2)) * 0.32 * (1 - q); rz = -4.5 - q * 2; rx = 3
      } else {
        const q = inOut((k - 0.78) / 0.22)
        px = L.x; pz = L.z; py = lerp(L.y, E.y, q); rz = lerp(-6.5, -Math.PI * 2, q); rx = lerp(3, Math.PI * 2, q)
      }
    } else if (anim === 'unfold') {
      const B = container.mouth.getWorldPosition(v3()); B.y = 0
      const q = inOut(k)
      px = lerp(B.x, E.x, q); pz = lerp(B.z, E.z, q); py = lerp(it.coin ? 0.45 : 0, E.y, q) + Math.sin(q * Math.PI) * 0.9
      ry = (1 - q) * Math.PI * 2
    } else {
      // pop / burst: fountain out of the opening
      const apex = (kind === 'bag' ? 3.9 : 4.3) + 0.3 * ((i * 7) % 3) / 2
      const q = k < 0.86 ? k / 0.86 : 1
      px = lerp(S.x, E.x, q); pz = lerp(S.z, E.z, q)
      const h = apex - Math.max(S.y, E.y)
      py = lerp(S.y, E.y, q) + 4 * h * q * (1 - q)
      if (k >= 0.86) py = E.y + Math.abs(Math.sin((k - 0.86) / 0.14 * Math.PI)) * 0.18 * (1 - (k - 0.86) / 0.14)
      if (it.coin) rx = (1 - outCubic(k)) * Math.PI * 10; else { rz = (1 - outCubic(k)) * Math.PI * 3; ry = (1 - k) * 2 }
      s = lerp(0.6, 1, ss(0, 0.3, k))
    }
    if (k >= 1 && !it.landed) { it.landed = true; opts.onPhase?.('land', i); emit(v3(E.x, Math.max(0.05, E.y - (it.coin ? 0.4 : 0)), E.z), 14, { speed: 0.9, up: 0.6, spread: 1.2, size: 0.08, decay: 1.6 }) }

    // idle once landed: silhouettes bob, revealed ones turn slowly to show off their depth
    const idle = ss(start + TL.flight, start + TL.flight + 0.6, t)
    it.hover += (it.hoverTarget - it.hover) * Math.min(1, dt * 10)
    const bob = it.coin ? Math.sin(t * 1.7 + i) * 0.05 : 0
    const revealK = it.revealAt >= 0 ? clamp((t - it.revealAt) / REVEAL_TIME) : 0
    const hop = it.revealAt >= 0 && !it.coin ? Math.sin(revealK * Math.PI) * 0.45 : 0
    const turn = it.revealed || it.revealAt >= 0 ? Math.sin(t * 0.6 + i) * 0.45 : Math.sin(t * 0.8 + i) * 0.22
    const spin = it.coin ? outCubic(revealK) * Math.PI * 4 : outCubic(revealK) * Math.PI * 2
    it.root.position.set(px, py + idle * (bob + it.hover * 0.1) + hop, pz)
    it.root.rotation.set(rx, ry + idle * turn + spin, rz)
    const squash = !it.coin && it.revealAt >= 0 ? 1 + Math.sin(revealK * Math.PI * 2) * 0.08 * (1 - revealK) : 1
    it.root.scale.set(s * sc * (1 + it.hover * 0.07) * (2 - squash), s * sc * (1 + it.hover * 0.07) * squash, s * sc * (1 + it.hover * 0.07) * (2 - squash))

    if (it.mini) { it.glow.visible = false; it.mark.material.opacity = 0; return }
    const flash = it.revealAt >= 0 ? Math.sin(clamp(revealK / 0.6) * Math.PI) : 0
    applyReveal(it, ss(0.12, 0.6, revealK), flash)
    const center = v3(px, py + (it.coin ? 0 : it.height * 0.5 * sc) + hop, pz)
    it.glow.position.copy(center).addScaledVector(camera.getWorldDirection(v3()), 0.6)
    it.glow.quaternion.copy(camera.quaternion)
    it.glow.scale.setScalar((it.coin ? 1.7 : 2.3) * sc * (1 + flash * 0.8))
    it.glow.material.uniforms.uI.value = (1 - ss(0.2, 0.7, revealK)) * (0.45 + 0.55 * it.hover) * idle + flash * 1.6 + (it.revealed ? 0.18 : 0) * idle
    it.mark.position.copy(center).add(v3(0, (it.coin ? 0.62 : it.height * 0.62) * sc, 0))
    it.mark.material.opacity = idle * (1 - ss(0, 0.25, revealK)) * (0.75 + 0.25 * Math.sin(t * 3 + i))
    if (revealK >= 1 && !it.revealed) { it.revealed = true; opts.onReveal?.(i) }
  }

  // the swap happens under the reveal flash, then the real materials glow down to normal
  const applyReveal = (it, s, flash) => {
    const real = s > 0.02
    for (const swap of it.swaps) swap.mesh.material = real ? swap.real : swap.sil
    for (const { m } of it.mats) m.emissive?.setScalar(flash * 0.7 * (1 - s * 0.5))
  }

  /* ================================================================ loop / interaction */

  const resize = () => {
    const w = canvas.clientWidth || 1, h = canvas.clientHeight || 1
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, opts.maxPixelRatio))
    renderer.setSize(w, h, false)
    camera.aspect = w / h
    camera.fov = w / h < 1 ? 40 : 32
    camera.updateProjectionMatrix()
    const fitH = (container.height + 0.9) / 2 / Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2)
    const fitW = 2.2 / Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2) / camera.aspect
    dist = Math.max(fitH, fitW) + 0.4
    if (settled) opts.onLayout?.(labelPositions())
  }
  let settled = false
  const labelPositions = () => items.map(it => {
    const p = it.slot.pos.clone(); p.y = it.coin ? p.y - 0.5 * it.slot.scale : -0.05
    p.project(camera)
    return { x: (p.x + 1) / 2 * canvas.clientWidth, y: (1 - p.y) / 2 * canvas.clientHeight }
  })
  resize()
  const ro = typeof ResizeObserver === 'function' ? new ResizeObserver(resize) : null
  ro?.observe(canvas)

  const raycaster = new THREE.Raycaster(), ndc = new THREE.Vector2()
  const pick = event => {
    const rect = canvas.getBoundingClientRect()
    ndc.set(((event.clientX - rect.left) / rect.width) * 2 - 1, -((event.clientY - rect.top) / rect.height) * 2 + 1)
    raycaster.setFromCamera(ndc, camera)
    const hit = raycaster.intersectObjects(items.filter(it => it.landed).map(it => it.root), true)[0]
    return hit ? items.find(it => { let o = hit.object; while (o) { if (o === it.root) return true; o = o.parent } return false }) : null
  }
  const onMove = event => {
    if (!settled) return
    const hit = pick(event)
    items.forEach(it => { it.hoverTarget = it === hit ? 1 : 0 })
    canvas.style.cursor = hit ? (hit.revealed ? 'zoom-in' : 'pointer') : ''
  }
  const onLeave = () => { items.forEach(it => { it.hoverTarget = 0 }); canvas.style.cursor = '' }
  const onClick = event => { if (!settled) return; const hit = pick(event); if (hit) opts.onPick?.(hit.index, hit.revealed) }
  if (!opts.preview) { canvas.addEventListener('pointermove', onMove); canvas.addEventListener('pointerleave', onLeave); canvas.addEventListener('click', onClick) }

  const reduce = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches
  let raf = 0, disposed = false, t0 = performance.now(), last = t0, clock = 0, playing = !!opts.preview
  const phases = [[TL.charge[0], 'charge'], [TL.open[0], 'open'], [TL.emerge, 'emerge']]
  let nextPhase = 0
  const settleAt = TL.emerge + TL.flight + TL.stagger * Math.max(0, items.length - 1) + 0.15
  let resolveSettled
  const settledPromise = new Promise(resolve => { resolveSettled = resolve })
  const frame = now => {
    if (disposed) return
    const dt = Math.min(0.25, (now - last) / 1000); last = now
    if (playing) clock = reduce && !opts.preview && clock < settleAt ? settleAt : clock + dt
    while (!opts.preview && playing && nextPhase < phases.length && clock >= phases[nextPhase][0]) opts.onPhase?.(phases[nextPhase++][1])
    if (!opts.preview && playing && !settled && clock >= settleAt) { settled = true; opts.onPhase?.('settled'); opts.onLayout?.(labelPositions()); resolveSettled() }
    pose(clock, dt); stepSparks(dt)
    renderer.render(scene, camera)
    raf = requestAnimationFrame(frame)
  }
  pose(0, 0); renderer.render(scene, camera)
  raf = requestAnimationFrame(frame)

  const reveal = index => {
    const it = items[index]
    if (!it || it.revealAt >= 0 || !settled) return
    it.revealAt = clock
    const c = it.root.position.clone(); if (!it.coin) c.y += it.height * 0.5 * it.slot.scale
    emit(c, 70, { speed: 2.2, up: 1.4, spread: 1.4, size: 0.13, decay: 1.2 })
  }
  return {
    play: () => { playing = true; t0 = performance.now(); return settledPromise },
    reveal,
    revealAll: () => items.forEach((it, n) => setTimeout(() => reveal(n), n * 160)),
    // jump to a moment of the timeline (paused) — for previews and tests
    seek: t => { playing = false; clock = t; if (!opts.preview && t >= settleAt) settled = true; pose(t, 1 / 60); renderer.render(scene, camera) },
    labelPositions,
    dispose: () => {
      if (disposed) return
      disposed = true
      cancelAnimationFrame(raf)
      ro?.disconnect()
      canvas.removeEventListener('pointermove', onMove); canvas.removeEventListener('pointerleave', onLeave); canvas.removeEventListener('click', onClick)
      scene.traverse(o => { if (o.isMesh && o.geometry && !owned.includes(o.geometry)) o.geometry.dispose() })
      owned.forEach(o => o.dispose?.())
      renderer.dispose()
      renderer.forceContextLoss?.()
    },
  }
}

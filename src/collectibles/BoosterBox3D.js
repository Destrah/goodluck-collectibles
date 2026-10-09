/**
 * The booster box in three.js (the same model as stream/prop_boosterbox_01.ydr), lazy-loaded like Container3D.
 *
 * buildBoosterBox(art, keep) -> { root, lid, inside, size }
 *   The in-game mesh rebuilt from the .ydr: same 24 vertices and UVs, artwork in /img/meta_booster_box.jpg (the
 *   texture embedded in the .ydr). Y up, 1 unit = 1 metre, origin at the bottom centre, the window art on top.
 *   The top is a separate lid hinged on its back edge so the box can open. `keep` collects disposables.
 *
 * createBoosterBoxScene(canvas, { packs, onPhase }) -> { play() => Promise, skip(), dispose() }
 *   Opening of a booster box item: the box drops in, the cellophane tears off, the lid swings open and the packs
 *   rise out and line up in front of it, lit and framed like the Container3D openings (transparent canvas).
 *   packs: number or Promise of the number of packs (the server's answer);
 *   the sealed box waits, rattling, until it arrives. onPhase('drop' | 'tear' | 'open' | 'emerge' | 'land' | 'done').
 */
import * as THREE from 'three'
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js'
import { resolveAsset } from '../runtime/assets'

export const BOX_ART = '/img/meta_booster_box.jpg'
const PACK_ART = '/img/meta_pack.png'
const PACK_BACK_ART = '/img/meta_pack_back.svg'

// prop_boosterbox_01.ydr vertex buffer (game coordinates, z up): position, normal, uv. The uvs wrap: v is negative.
const YDR_VERTS = [
  [-0.097, -0.0797, -0.0417, -1, 0, 0, 0.9898, -0.7665], [-0.097, -0.0797, -0.0417, 0, 0, -1, 0.4395, -0.0985],
  [-0.097, -0.0797, -0.0417, 0, -1, 0, 0.4803, -0.2749], [0.097, -0.0797, -0.0417, 1, 0, 0, 0.4776, -0.5277],
  [0.097, -0.0797, -0.0417, 0, 0, -1, 0.0241, -0.0998], [0.097, -0.0797, -0.0417, 0, -1, 0, 0.9846, -0.2749],
  [-0.097, 0.0797, -0.0417, 0, 1, 0, 0.9868, -0.0313], [-0.097, 0.0797, -0.0417, 0, 0, -1, 0.4483, -0.4191],
  [-0.097, 0.0797, -0.0417, -1, 0, 0, 0.4778, -0.7665], [0.097, 0.0797, -0.0417, 1, 0, 0, 0.989, -0.5277],
  [0.097, 0.0797, -0.0417, 0, 1, 0, 0.4748, -0.0313], [0.097, 0.0797, -0.0417, 0, 0, -1, 0.0225, -0.4217],
  [-0.097, -0.0797, 0.0417, 0, 0, 1, 0.0278, -0.5856], [-0.097, -0.0797, 0.0417, -1, 0, 0, 0.9898, -0.9789],
  [-0.097, -0.0797, 0.0417, 0, -1, 0, 0.4803, -0.4958], [0.097, -0.0797, 0.0417, 1, 0, 0, 0.4776, -0.7411],
  [0.097, -0.0797, 0.0417, 0, 0, 1, 0.4463, -0.5856], [0.097, -0.0797, 0.0417, 0, -1, 0, 0.9846, -0.4958],
  [-0.097, 0.0797, 0.0417, -1, 0, 0, 0.4778, -0.9789], [-0.097, 0.0797, 0.0417, 0, 1, 0, 0.9868, -0.2538],
  [-0.097, 0.0797, 0.0417, 0, 0, 1, 0.0278, -0.9718], [0.097, 0.0797, 0.0417, 1, 0, 0, 0.989, -0.7411],
  [0.097, 0.0797, 0.0417, 0, 1, 0, 0.4748, -0.2493], [0.097, 0.0797, 0.0417, 0, 0, 1, 0.4463, -0.9718],
]
const YDR_INDICES = [11, 4, 1, 1, 7, 11, 23, 20, 12, 12, 16, 23, 17, 14, 2, 2, 5, 17, 21, 15, 3, 3, 9, 21, 19, 22, 10, 10, 6, 19, 13, 18, 8, 8, 0, 13]
const HX = 0.097, HY = 0.0797, HZ = 0.0417
export const BOX_SIZE = { width: HX * 2, height: HZ * 2, depth: HY * 2 }

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

export const loadImage = async src => {
  if (!src) return null
  try {
    const state = await resolveAsset(src)
    if (state.status === 'error') return null
    const url = state.url || src
    return await new Promise(resolve => { const img = new Image(); img.crossOrigin = 'anonymous'; img.onload = () => resolve(img); img.onerror = () => resolve(null); img.src = url })
  } catch { return null }
}
const imageTexture = (img, keep) => {
  if (!img) return null
  const t = keep(new THREE.Texture(img)); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; t.needsUpdate = true
  return t
}
// the pack artwork has transparent margins: crop it to the opaque part so it fills the pack's face
const croppedTexture = (img, keep) => {
  if (!img) return null
  const c = document.createElement('canvas'); c.width = img.naturalWidth || img.width; c.height = img.naturalHeight || img.height
  const g = c.getContext('2d'); g.drawImage(img, 0, 0)
  let x0 = c.width, y0 = c.height, x1 = -1, y1 = -1
  try {
    const { data } = g.getImageData(0, 0, c.width, c.height)
    for (let y = 0; y < c.height; y += 2) for (let x = 0; x < c.width; x += 2) {
      if (data[(y * c.width + x) * 4 + 3] > 40) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y }
    }
  } catch { return imageTexture(img, keep) } // tainted canvas: use it as it is
  if (x1 < 0) return imageTexture(img, keep)
  const out = document.createElement('canvas'); out.width = x1 - x0 + 1; out.height = y1 - y0 + 1
  out.getContext('2d').drawImage(c, x0, y0, out.width, out.height, 0, 0, out.width, out.height)
  const t = keep(new THREE.CanvasTexture(out)); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8
  return t
}
export const loadBoxArt = async keep => imageTexture(await loadImage(BOX_ART), keep)

// game (x, y, z) -> three (x, z + HZ, -y): z up becomes y up with the base on the floor; the game's +y side is the back
function ydrGeometry(lidOnly) {
  const pos = [], nor = [], uv = [], index = []
  const map = new Map()
  for (let i = 0; i < YDR_INDICES.length; i += 3) {
    const tri = YDR_INDICES.slice(i, i + 3)
    if ((YDR_VERTS[tri[0]][5] === 1) !== lidOnly) continue // the lid is the face pointing up (game +z)
    for (const v of tri) {
      if (!map.has(v)) {
        const [x, y, z, nx, ny, nz, u, w] = YDR_VERTS[v]
        map.set(v, pos.length / 3)
        pos.push(x, z + HZ, -y); nor.push(nx, nz, -ny); uv.push(u, -w) // image y = 1 + v; three flips textures, so v' = -v
      }
      index.push(map.get(v))
    }
  }
  const geo = new THREE.BufferGeometry()
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3))
  geo.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3))
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2))
  geo.setIndex(index)
  return geo
}

export function buildBoosterBox(art, keep = o => o) {
  const print = keep(new THREE.MeshPhysicalMaterial({ map: art, color: art ? '#ffffff' : '#c41fa8', roughness: 0.42, clearcoat: 0.5, clearcoatRoughness: 0.3 }))
  const cardboard = keep(new THREE.MeshStandardMaterial({ color: '#4a1a5c', roughness: 0.9 })) // printed inside of the lid
  const root = new THREE.Group()
  const body = new THREE.Mesh(keep(ydrGeometry(false)), print)
  root.add(body)
  // inside walls, only seen once the lid is open (the outside faces are one-sided)
  const inside = new THREE.Mesh(keep(new THREE.BoxGeometry(HX * 2 - 0.002, HZ * 2 - 0.002, HY * 2 - 0.002)),
    keep(new THREE.MeshStandardMaterial({ color: '#3a0f4a', roughness: 0.9, side: THREE.BackSide })))
  inside.position.y = HZ
  root.add(inside)
  // lid hinged on the back top edge
  const lid = new THREE.Group()
  lid.position.set(0, HZ * 2, -HY)
  const top = new THREE.Mesh(keep(ydrGeometry(true)), print)
  top.position.set(0, -HZ * 2, HY)
  const under = new THREE.Mesh(keep(new THREE.PlaneGeometry(HX * 2, HY * 2)), cardboard)
  under.rotation.x = Math.PI / 2; under.position.set(0, -0.0005, HY)
  lid.add(top, under)
  root.add(lid)
  root.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true } })
  inside.castShadow = false
  return { root, lid, inside, size: BOX_SIZE }
}

/* ------------------------------------------------------------------ opening scene */

const PACK_W = 0.064, PACK_H = 0.104, PACK_D = 0.005
const MAX_SHOWN = 12
const DROP = 0.6, TEAR = [1.05, 1.75], OPEN = [1.75, 2.45], EMERGE = 2.35, FLIGHT = 0.95, STAGGER = 0.11
// The box is modelled at its real size; the stage scales it up to the size of Container3D's coin bags and plushie
// boxes so the opening shares their look: lights, magenta floor glow, sparkles, full-screen transparent canvas.
const S = 7
const MAGENTA = '#ff2bd6', YELLOW = '#ffd23c', CYAN = '#4df3ff'
const SIMPLE_VERT = `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`
const GLOW_FRAG = `uniform vec3 uCol; uniform float uI; uniform float uSoft; varying vec2 vUv;
void main(){ vec2 p = vUv * 2.0 - 1.0; float r = length(p); float g = exp(-r * r * uSoft) * (1.0 - smoothstep(0.85, 1.0, r)); gl_FragColor = vec4(uCol * g * uI, 1.0); }`
const SPARK_VERT = `attribute float aLife; attribute float aSize; attribute vec3 aCol; varying float vLife; varying vec3 vCol;
void main(){ vLife = aLife; vCol = aCol; vec4 mv = modelViewMatrix * vec4(position, 1.0); gl_PointSize = aSize * (300.0 / -mv.z) * step(0.001, aLife); gl_Position = projectionMatrix * mv; }`
const SPARK_FRAG = `varying float vLife; varying vec3 vCol;
void main(){ vec2 p = gl_PointCoord * 2.0 - 1.0; float d = length(p); float star = max(exp(-d * d * 6.0), 0.6 * exp(-abs(p.x * p.y) * 60.0) * (1.0 - d));
  gl_FragColor = vec4(vCol * star * vLife * 1.6, 1.0); }`
const ADDITIVE = { blending: THREE.CustomBlending, blendEquation: THREE.AddEquation, blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor, blendSrcAlpha: THREE.ZeroFactor, blendDstAlpha: THREE.OneFactor }

// options.frame(w, h) -> { width, height }: frame the scene like a centre stage on a bigger (full-screen) canvas, as
// Container3D does in FiveM. onPhase('drop' | 'tear' | 'open' | 'emerge' | 'land' (index) | 'done').
export async function createBoosterBoxScene(canvas, options = {}) {
  const owned = []
  const keep = o => { owned.push(o); return o }
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true })
  renderer.setClearColor(0x000000, 0)
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75))
  renderer.outputColorSpace = THREE.SRGBColorSpace
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 1.15
  renderer.shadowMap.enabled = true
  renderer.shadowMap.type = THREE.PCFShadowMap

  const scene = new THREE.Scene()
  const pmrem = new THREE.PMREMGenerator(renderer)
  const roomEnv = new RoomEnvironment()
  scene.environment = keep(pmrem.fromScene(roomEnv, 0.04).texture)
  roomEnv.traverse?.(child => { child.geometry?.dispose?.(); child.material?.dispose?.() })
  pmrem.dispose()
  scene.environmentIntensity = 0.55

  const camera = new THREE.PerspectiveCamera(32, 16 / 9, 0.05, 80)
  const glowMaterial = (color, soft = 3) => keep(new THREE.ShaderMaterial({ uniforms: { uCol: { value: new THREE.Color(color) }, uI: { value: 0 }, uSoft: { value: soft } }, vertexShader: SIMPLE_VERT, fragmentShader: GLOW_FRAG, transparent: true, depthWrite: false, ...ADDITIVE }))

  // Container3D's lights: warm spot from above, magenta rim, cyan fill
  scene.add(new THREE.HemisphereLight(0x9a8cff, 0x1a0c22, 0.3))
  const key = new THREE.SpotLight(0xffe0b0, 120, 0, 0.42, 0.65, 2)
  key.position.set(1.6, 7.5, 4.2); key.target.position.set(0, 0.3, 0.5)
  key.castShadow = true; key.shadow.mapSize.set(1024, 1024); key.shadow.bias = -0.0004; key.shadow.radius = 6
  scene.add(key, key.target)
  const rim = new THREE.DirectionalLight(0xff4bd8, 1.6); rim.position.set(-3.5, 2.5, -3); scene.add(rim)
  const fill = new THREE.DirectionalLight(0x5cf0ff, 0.55); fill.position.set(4, 1.5, 3); scene.add(fill)
  const inner = new THREE.PointLight(0xffb347, 0, 3.2, 1.6); inner.position.set(0, HZ * 2 * S + 0.25, 0); scene.add(inner)

  const floor = new THREE.Mesh(keep(new THREE.PlaneGeometry(40, 40)), keep(new THREE.ShadowMaterial({ opacity: 0.55, depthWrite: false })))
  floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true; scene.add(floor)
  const floorGlow = new THREE.Mesh(keep(new THREE.PlaneGeometry(1, 1)), glowMaterial(MAGENTA, 3.2))
  floorGlow.rotation.x = -Math.PI / 2; floorGlow.position.y = 0.005; floorGlow.scale.setScalar(4.4); scene.add(floorGlow)

  const stage = new THREE.Group()
  stage.scale.setScalar(S)
  scene.add(stage)

  const [boxImg, packImg, packBackImg] = await Promise.all([loadImage(BOX_ART), loadImage(PACK_ART), loadImage(PACK_BACK_ART)])
  const box = buildBoosterBox(imageTexture(boxImg, keep), keep)
  stage.add(box.root)

  // cellophane wrap, torn off before the lid opens
  const wrapMat = keep(new THREE.MeshPhysicalMaterial({ color: '#ffffff', transparent: true, opacity: 0.16, roughness: 0.08, metalness: 0, clearcoat: 1, depthWrite: false }))
  const wrap = new THREE.Mesh(keep(new THREE.BoxGeometry(HX * 2 + 0.006, HZ * 2 + 0.006, HY * 2 + 0.006)), wrapMat)
  wrap.position.y = HZ
  box.root.add(wrap)

  /* sparkles (world space, like Container3D) */
  const SPARKS = 360
  const sparkGeo = keep(new THREE.BufferGeometry())
  const sp = { pos: new Float32Array(SPARKS * 3), vel: new Float32Array(SPARKS * 3), life: new Float32Array(SPARKS), size: new Float32Array(SPARKS), col: new Float32Array(SPARKS * 3), decay: new Float32Array(SPARKS), next: 0 }
  sparkGeo.setAttribute('position', new THREE.BufferAttribute(sp.pos, 3))
  sparkGeo.setAttribute('aLife', new THREE.BufferAttribute(sp.life, 1))
  sparkGeo.setAttribute('aSize', new THREE.BufferAttribute(sp.size, 1))
  sparkGeo.setAttribute('aCol', new THREE.BufferAttribute(sp.col, 3))
  const sparks = new THREE.Points(sparkGeo, keep(new THREE.ShaderMaterial({ vertexShader: SPARK_VERT, fragmentShader: SPARK_FRAG, transparent: true, depthWrite: false, ...ADDITIVE })))
  sparks.frustumCulled = false; sparks.renderOrder = 10; scene.add(sparks)
  const palette = [new THREE.Color(YELLOW), new THREE.Color(MAGENTA), new THREE.Color(CYAN), new THREE.Color('#ffffff')]
  const shine = [new THREE.Color('#ffffff'), new THREE.Color(CYAN)]
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
    for (const name of ['position', 'aLife', 'aSize', 'aCol']) sparkGeo.attributes[name].needsUpdate = true
  }
  const worldOf = (object, local = new THREE.Vector3()) => object.localToWorld(local.clone())

  /* packs: standing in a row inside the box, then rising out to a fan in front of it */
  const packFront = keep(new THREE.MeshPhysicalMaterial({ map: croppedTexture(packImg, keep), color: packImg ? '#ffffff' : '#ff2bd6', roughness: 0.3, metalness: 0.35, clearcoat: 0.8 }))
  const packBack = keep(new THREE.MeshPhysicalMaterial({ map: croppedTexture(packBackImg, keep), color: packBackImg ? '#ffffff' : '#4a0f63', roughness: 0.35, metalness: 0.3, clearcoat: 0.6 }))
  const packEdge = keep(new THREE.MeshStandardMaterial({ color: '#c41fa8', roughness: 0.4, metalness: 0.4 }))
  const packGeo = keep(new THREE.BoxGeometry(PACK_W, PACK_H, PACK_D))
  let packs = [], emergeEnd = Infinity, total = Infinity, pending = typeof options.packs?.then === 'function', failed = false
  const layoutPacks = count => {
    const shown = Math.max(0, Math.min(MAX_SHOWN, Math.floor(count)))
    const rows = shown > 6 ? 2 : 1, perRow = Math.ceil(shown / rows)
    packs = Array.from({ length: shown }, (_, i) => {
      const mesh = new THREE.Mesh(packGeo, [packEdge, packEdge, packEdge, packEdge, packFront, packBack])
      mesh.castShadow = true
      const row = Math.floor(i / perRow), col = i % perRow, inRow = row ? shown - perRow : Math.min(perRow, shown)
      const gap = PACK_W + 0.012
      // inside: upright, faces to the front, in two slanted rows behind each other
      const from = new THREE.Vector3((col - (inRow - 1) / 2) * 0.012 * (rows === 1 ? 1 : 0.6), HZ * 2 - PACK_H / 2 + 0.012, lerp(-HY + 0.02, HY - 0.02, shown > 1 ? i / (shown - 1) : 0.5))
      const to = new THREE.Vector3((col - (inRow - 1) / 2) * gap, PACK_H / 2 + 0.002, HY + 0.09 + (rows === 2 ? (row === 0 ? 0 : 0.11) : 0.02))
      mesh.userData = { from, to, spin: (i % 2 ? 1 : -1) * Math.PI * 2, tilt: -0.18, landed: false }
      mesh.position.copy(from); mesh.visible = false
      stage.add(mesh)
      return mesh
    })
    emergeEnd = EMERGE + STAGGER * Math.max(0, packs.length - 1) + FLIGHT
    total = emergeEnd + 0.6
  }
  if (!pending) layoutPacks(Number(options.packs) || 12)
  else options.packs.then(count => { layoutPacks(Number(count) || 12); pending = false }, () => { failed = true; pending = false })

  const phase = new Set()
  let effects = true // no sparkles while skipping to the end
  const fire = (name, index) => {
    if (index === undefined ? phase.has(name) : false) return
    if (index === undefined) phase.add(name)
    if (effects) {
      if (name === 'tear') emit(worldOf(box.root, new THREE.Vector3(0, HZ * 2, 0)), 34, { speed: 0.9, up: 0.9, spread: 1.2, colors: shine, size: 0.08, decay: 1.4 })
      if (name === 'open') emit(worldOf(box.root, new THREE.Vector3(0, HZ * 2, 0)), 90, { speed: 1.4, up: 1.5, spread: 0.8 })
      if (name === 'land') emit(worldOf(packs[index], new THREE.Vector3(0, -PACK_H / 2, 0)), 8, { speed: 0.5, up: 0.5, size: 0.07, decay: 1.6 })
    }
    options.onPhase?.(name, index, !effects) // third argument: reached by skipping (no sound)
  }

  function pose(t) {
    // drop in and settle, slight turn toward the camera
    const drop = clamp(t / DROP)
    box.root.position.y = (1 - outBounce(drop)) * 0.35
    box.root.rotation.y = lerp(-0.55, -0.12, ss(0, 1.4, t))
    if (t >= DROP * 0.36) fire('drop') // first touch of the bounce
    const rattle = t > DROP && t < TEAR[1] ? Math.sin(t * 48) * 0.004 * (pending ? 1 : 1 - ss(TEAR[0], TEAR[1], t)) : 0
    box.root.position.x = rattle; box.root.rotation.z = rattle * 2

    // cellophane: splits, puffs out and flies off up and to the side
    const tear = ss(TEAR[0], TEAR[1], t)
    if (t >= TEAR[0]) fire('tear')
    wrap.visible = tear < 0.98
    wrap.scale.setScalar(1 + tear * 0.35)
    wrap.position.set(-tear * 0.35, HZ + tear * 0.22, tear * 0.05)
    wrap.rotation.set(tear * 0.6, 0, tear * 1.2)
    wrapMat.opacity = 0.16 * (1 - tear) + (tear > 0 && tear < 0.5 ? 0.12 * Math.sin(tear * Math.PI * 2) : 0)

    // lid swings back on its hinge with a small overshoot; warm light spills out
    const open = ss(OPEN[0], OPEN[1], t)
    if (t >= OPEN[0]) fire('open')
    box.lid.rotation.x = -outBack(open, 1.2) * Math.PI * 0.62
    const away = ss(emergeEnd, total, t)
    inner.intensity = open * 9 * (1 - 0.5 * away)
    floorGlow.material.uniforms.uI.value = 0.22 + 0.4 * open * (1 - 0.5 * away)

    // packs: visible inside once the lid lifts, then each rises out and lands in the fan
    packs.forEach((mesh, i) => {
      const begin = EMERGE + i * STAGGER
      const k = clamp((t - begin) / FLIGHT)
      mesh.visible = open > 0.3
      const { from, to, spin, tilt } = mesh.userData
      const e = ss(0, 1, k)
      // the packs ride with the box until they leave it
      const base = new THREE.Vector3().copy(from).applyAxisAngle(new THREE.Vector3(0, 1, 0), box.root.rotation.y)
      mesh.position.set(lerp(base.x + box.root.position.x, to.x, e), lerp(base.y + box.root.position.y, to.y, e) + Math.sin(k * Math.PI) * 0.16, lerp(base.z, to.z, e))
      mesh.rotation.set(lerp(0, tilt, e) + Math.sin(k * Math.PI) * 0.35, lerp(box.root.rotation.y, 0, e) + Math.sin(k * Math.PI) * spin * 0.08, 0)
      if (k >= 1 && !mesh.userData.landed) { mesh.userData.landed = true; fire('land', i) }
    })
    if (packs.length && t >= EMERGE) fire('emerge')

    // camera (box units, scaled with the stage): close on the sealed box, then back out to frame the packs
    const c = ss(OPEN[0], emergeEnd === Infinity ? OPEN[1] + 1 : emergeEnd, t)
    const rows = packs.length > 6 ? 2 : 1
    const span = Math.max(BOX_SIZE.width, Math.min(6, packs.length) * (PACK_W + 0.012))
    const lookY = lerp(0.05, 0.04, c), lookZ = lerp(0, 0.08 + rows * 0.03, c), near = 0.82 // a bit closer than the panel version
    camera.position.set(Math.sin(t * 0.25) * 0.03 * S, (lookY + (lerp(0.32, 0.42 + rows * 0.05, c) - lookY) * near) * S, (lookZ + (lerp(0.62, 0.5 + span * 0.85 + rows * 0.06, c) - lookZ) * near) * S)
    camera.lookAt(0, lookY * S, lookZ * S)
  }

  function resize() {
    const w = canvas.clientWidth || canvas.width || 1, h = canvas.clientHeight || canvas.height || 1
    const region = options.frame?.(w, h)
    const fw = region ? Math.max(1, Math.min(w, region.width)) : w, fh = region ? Math.max(1, Math.min(h, region.height)) : h
    renderer.setSize(w, h, false)
    camera.aspect = fw / fh
    camera.fov = camera.aspect < 1 ? 42 : 32
    if (region) camera.setViewOffset(fw, fh, -(w - fw) / 2, -(h - fh) / 2, w, h)
    else camera.clearViewOffset()
    camera.updateProjectionMatrix()
  }
  const observer = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(resize) : null
  observer?.observe(canvas)
  resize()

  let clock = 0, last = 0, frame = 0, finished, done = false, disposed = false
  function tick(now) {
    if (disposed) return
    const dt = last ? Math.min(0.1, (now - last) / 1000) : 0
    last = now
    // the sealed box keeps rattling until the server says how many packs are in it
    if (!(pending && clock + dt > TEAR[0] - 0.05)) clock += dt
    if (failed && !done) { done = true; finished?.(false) }
    const t = done ? Math.max(clock, total) : clock
    pose(t)
    stepSparks(dt)
    renderer.render(scene, camera)
    if (t >= total && !done) { done = true; fire('done'); finished?.(true) }
    frame = requestAnimationFrame(tick)
  }
  effects = false; pose(0); effects = true
  renderer.render(scene, camera)

  return {
    play() { return new Promise(resolve => { finished = resolve; last = 0; frame = requestAnimationFrame(tick) }) },
    skip() { if (pending || done) return; effects = false; clock = total; pose(total); effects = true },
    dispose() {
      disposed = true
      cancelAnimationFrame(frame)
      observer?.disconnect()
      owned.forEach(o => o.dispose?.())
      renderer.dispose(); renderer.forceContextLoss?.()
    },
  }
}

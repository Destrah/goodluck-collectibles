/**
 * "Back peel" tear style — a real-time Three.js pack, lazy-loaded so the other tear styles never pull in three.
 *
 * Timing is modelled on the spd_H.gif reference: the pack spins round to its back, the camera pushes in on the
 * back seam, the seam splits and the back sheet peels outward and away (the front sheet stays intact, so you
 * look at its silver inside), light pours out and the face-down stack slides up between the sheets.
 *
 * createPeelScene(canvas, opts) -> { play({ speed, onPhase, isDead }) => Promise<rect|null>, dispose() }
 *   play() resolves when the stack is clear of the pack, with the top card's rectangle in canvas CSS pixels,
 *   so PackOpenScene can drop its DOM cards exactly on top and hand over to the normal fan-out.
 */
import * as THREE from 'three'

// packFill: pack height as a fraction of the canvas height at the start, so the 3D pack matches the CSS tear styles
const DEFAULTS = { front: '/img/pack_open_front.jpg', back: '/img/pack_open_back.jpg', cardBack: '/img/Cards_Back.jpg', maxPixelRatio: 1.5, packFill: 0.72 }

// timeline in seconds at 1x
export const PEEL_T = { spinA: 0.25, spinB: 2.05, pushB: 2.55, seamA: 3.5, seamB: 3.85, peelB: 4.95, riseB: 6.6 }
const T = PEEL_T
const PHASE_AT = [
  [0, 'front'], [T.spinA, 'tilt'], [T.spinA + 0.15, 'flip-start'], [1.15, 'flip-half'], [T.spinB, 'back'],
  [T.seamA, 'seam-tension'], [T.seamB, 'tear-start'], [T.seamB + 0.3, 'tear-mid'], [T.seamB + 0.6, 'tear-open'], [T.peelB, 'cards-pull'],
]

// pack geometry (local space): front sheet at z=0 facing +z, back sheet at z=-GAP facing -z
const PH = 2, PW = PH * 480 / 840, YS = 0.1, GAP = 0.024
const CW = PW * 0.84, CH = CW * 322 / 230
const CARD_Y0 = 0.76 - CH / 2           // resting inside: top of the stack just under the crimp
const CARD_Y1 = 1.0 + CH / 2 + 0.12     // bottom edge just clear of the top crimp

const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v))
const lerp = (a, b, k) => a + (b - a) * k
const ss = (a, b, t) => { const k = clamp((t - a) / (b - a)); return k * k * (3 - 2 * k) }
const inOut = k => (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2)
const outBack = k => { const c = 1.3; return 1 + (c + 1) * Math.pow(k - 1, 3) + c * Math.pow(k - 1, 2) }

const NOISE = `
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p){ vec2 i = floor(p), f = fract(p); vec2 u = f*f*(3.0-2.0*f);
  return mix(mix(hash(i), hash(i+vec2(1,0)), u.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), u.x), u.y); }`

const PACK_VERT = `
varying vec2 vUv; varying vec3 vN; varying vec3 vV;
void main(){ vUv = uv; vN = normalize(normalMatrix * normal);
  vec4 mv = modelViewMatrix * vec4(position, 1.0); vV = mv.xyz; gl_Position = projectionMatrix * mv; }`

// uSheet 0 = front sheet (outside is the +z side), 1 = back sheet (outside is the -z side); the inside of both is silver foil
const PACK_FRAG = `
uniform sampler2D uFront, uBack; uniform float uSheet, uSeam, uOpacity, uHaloI, uSheen, uGlow;
varying vec2 vUv; varying vec3 vN; varying vec3 vV;
${NOISE}
void main(){
  vec2 uv = vUv;
  float teeth = abs(fract(uv.x * 24.0) - 0.5) * 2.0;
  float cr = 0.03;
  if (uv.y > 1.0 - cr * (0.3 + 0.7 * teeth) || uv.y < cr * (0.3 + 0.7 * teeth)) discard;
  float side = 0.006 + 0.006 * noise(vec2(uv.y * 38.0, 3.0));
  if (uv.x < side || uv.x > 1.0 - side) discard;
  if (uSeam > 0.0) {
    float j = abs(fract(uv.y * 34.0 + noise(uv * vec2(4.0, 70.0)) * 0.8) - 0.5) * 2.0;
    if (abs(uv.x - 0.5) < uSeam * (0.003 + 0.016 * j)) discard;
  }
  bool fr = gl_FrontFacing;
  bool outside = uSheet < 0.5 ? fr : !fr;
  vec3 N = normalize(vN) * (fr ? 1.0 : -1.0);
  vec3 V = normalize(-vV), L = normalize(vec3(-0.45, 0.55, 0.85));
  vec3 col;
  if (outside) {
    col = uSheet < 0.5 ? texture2D(uFront, uv).rgb : texture2D(uBack, vec2(1.0 - uv.x, uv.y)).rgb;
    vec2 q = uv * vec2(10.0, 22.0); float e = 0.05;
    float n0 = noise(q), nx = noise(q + vec2(e, 0.0)), ny = noise(q + vec2(0.0, e));
    N = normalize(N + vec3(n0 - nx, n0 - ny, 0.0) * 5.0);
    float diff = max(dot(N, L), 0.0);
    float spec = pow(max(dot(reflect(-L, N), V), 0.0), 28.0);
    float fres = pow(1.0 - max(dot(N, V), 0.0), 3.0);
    col = col * (0.62 + 0.5 * diff) + spec * (0.35 + uSheen) + fres * uHaloI * vec3(1.0, 0.75, 0.95) * 0.9;
  } else {
    vec2 q = uv * vec2(5.0, 9.0); float e = 0.06;
    float n0 = noise(q) + 0.25 * noise(q * 3.1);
    float nx = noise(q + vec2(e, 0.0)) + 0.25 * noise((q + vec2(e, 0.0)) * 3.1);
    float ny = noise(q + vec2(0.0, e)) + 0.25 * noise((q + vec2(0.0, e)) * 3.1);
    N = normalize(N + vec3(n0 - nx, n0 - ny, 0.0) * 6.0);
    vec3 R = reflect(-V, N);
    float env = 0.1 + 0.55 * pow(clamp(R.y * 0.5 + 0.5, 0.0, 1.0), 3.0);
    env += 0.7 * smoothstep(0.42, 0.9, noise(R.xy * 2.2 + vec2(3.1, 7.4))) + 0.25 * noise(R.xy * 6.0);
    float spec = pow(max(dot(reflect(-L, N), V), 0.0), 40.0);
    vec3 silver = vec3(0.74, 0.76, 0.82) * (0.92 + 0.08 * sin(uv.x * 220.0 + noise(uv * vec2(3.0, 40.0)) * 4.0));
    col = silver * env * (1.0 + 0.6 * uGlow) + spec * 0.9 + uGlow * vec3(1.0, 0.86, 0.97) * 0.18 * smoothstep(0.55, 1.0, uv.y);
  }
  gl_FragColor = vec4(col, uOpacity);
}`

// pure additive light: adds colour but never alpha, so it brightens the page behind the transparent canvas
const ADDITIVE = { blending: THREE.CustomBlending, blendEquation: THREE.AddEquation, blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor, blendSrcAlpha: THREE.ZeroFactor, blendDstAlpha: THREE.OneFactor }

const SIMPLE_VERT = `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`
const GLOW_FRAG = `
uniform vec3 uCol; uniform float uI; uniform float uSoft; varying vec2 vUv;
void main(){ vec2 p = vUv * 2.0 - 1.0; float r = length(p);
  float g = exp(-r * r * uSoft) * (1.0 - smoothstep(0.85, 1.0, r));
  gl_FragColor = vec4(uCol * g * uI, 1.0); }`
const RAYS_FRAG = `
uniform float uI, uTime; uniform vec3 uCol; varying vec2 vUv;
void main(){
  vec2 p = vec2((vUv.x - 0.5) * 6.0, vUv.y * 7.0);
  float a = atan(p.x, p.y), r = length(p);
  float cone = smoothstep(0.78, 0.18, abs(a));
  float s = 0.5 + 0.5 * sin(a * 23.0 + uTime * 0.6) * sin(a * 37.0 - uTime * 0.45);
  s += 0.9 * pow(max(0.0, sin(a * 11.0 + 1.3 + uTime * 0.25)), 14.0);
  float fall = exp(-r * 0.42);
  float core = exp(-abs(a) * 6.0) * exp(-r * 0.9);
  float I = uI * (cone * s * fall * 0.8 + core * 1.1) * smoothstep(0.0, 0.12, r) * smoothstep(1.0, 0.7, vUv.y);
  gl_FragColor = vec4(uCol * I, 1.0);
}`
const CARD_FRAG = `
uniform sampler2D uMap; uniform float uBright, uOpacity; varying vec2 vUv;
void main(){
  vec2 s = vec2(${CW.toFixed(4)}, ${CH.toFixed(4)});
  vec2 p = (vUv - 0.5) * s; float rad = s.x * 0.07;
  vec2 d = abs(p) - (s * 0.5 - rad);
  if (length(max(d, 0.0)) - rad > 0.0) discard;
  vec2 uv = gl_FrontFacing ? vUv : vec2(1.0 - vUv.x, vUv.y);
  gl_FragColor = vec4(texture2D(uMap, uv).rgb * uBright, uOpacity);
}`

export async function createPeelScene(canvas, options = {}) {
  const opts = { ...DEFAULTS, ...options }
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true }) // premultiplied, so additive light stays see-through
  renderer.outputColorSpace = THREE.LinearSRGBColorSpace
  renderer.setClearColor(0x000000, 0)
  const scene = new THREE.Scene()
  const camera = new THREE.PerspectiveCamera(30, 16 / 9, 0.1, 60)
  const owned = [] // geometries / materials / textures to dispose

  const loader = new THREE.TextureLoader()
  const loadTex = src => new Promise((res, rej) => loader.load(src, t => { t.anisotropy = 4; owned.push(t); res(t) }, undefined, rej))
  const [front, back, cardBack] = await Promise.all([loadTex(opts.front), loadTex(opts.back), loadTex(opts.cardBack)])

  const mesh = (geo, mat, order) => { owned.push(geo, mat); const m = new THREE.Mesh(geo, mat); m.renderOrder = order; return m }
  const packMat = sheet => new THREE.ShaderMaterial({
    uniforms: { uFront: { value: front }, uBack: { value: back }, uSheet: { value: sheet }, uSeam: { value: 0 }, uOpacity: { value: 1 }, uHaloI: { value: 0 }, uSheen: { value: 0 }, uGlow: { value: 0 } },
    vertexShader: PACK_VERT, fragmentShader: PACK_FRAG, side: THREE.DoubleSide, transparent: true,
  })
  const glowMat = (col, soft, extra = {}) => new THREE.ShaderMaterial({
    uniforms: { uCol: { value: new THREE.Color(...col) }, uI: { value: 0 }, uSoft: { value: soft } },
    vertexShader: SIMPLE_VERT, fragmentShader: GLOW_FRAG, transparent: true, ...ADDITIVE, depthWrite: false, ...extra,
  })
  const sheetGeo = (y0, y1, segX, segY) => {
    const g = new THREE.PlaneGeometry(PW, y1 - y0, segX, segY)
    const p = g.attributes.position, u = g.attributes.uv
    for (let i = 0; i < p.count; i++) { const y = p.getY(i) + (y0 + y1) / 2; p.setY(i, y); u.setXY(i, p.getX(i) / PW + 0.5, (y + 1) / 2) }
    return g
  }

  const group = new THREE.Group(); scene.add(group)
  const halo = mesh(new THREE.PlaneGeometry(5.2, 5.2), glowMat([1.0, 0.82, 0.96], 9), 0) // tight falloff so it fades well inside the canvas
  halo.position.z = -0.8; scene.add(halo)

  const frontMat = packMat(0), backMat = packMat(1)
  group.add(mesh(sheetGeo(-1, 1, 10, 16), frontMat, 1))
  const backBody = mesh(sheetGeo(-1, YS, 10, 12), backMat, 3); backBody.position.z = -GAP; group.add(backBody)

  const flapMats = [], flapBase = [], flaps = []
  for (const side of [-1, 1]) {
    const g = new THREE.PlaneGeometry(PW / 2, 1 - YS, 10, 14)
    const pos = g.attributes.position, uv = g.attributes.uv
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i) + side * PW / 4, y = pos.getY(i) + (1 + YS) / 2
      pos.setXYZ(i, x, y, -GAP); uv.setXY(i, x / PW + 0.5, (y + 1) / 2)
    }
    const m = packMat(1)
    flapMats.push(m); flapBase.push(Float32Array.from(pos.array))
    const f = mesh(g, m, 4); flaps.push(f); group.add(f)
  }

  const rays = mesh(new THREE.PlaneGeometry(6, 7), new THREE.ShaderMaterial({
    uniforms: { uI: { value: 0 }, uTime: { value: 0 }, uCol: { value: new THREE.Color(1.0, 0.9, 0.98) } },
    vertexShader: SIMPLE_VERT, fragmentShader: RAYS_FRAG, transparent: true, ...ADDITIVE, depthWrite: false, side: THREE.DoubleSide }), 1.5)
  rays.position.set(0, 0.92 + 3.5, -GAP / 2); group.add(rays)
  const inner = mesh(new THREE.PlaneGeometry(PW * 1.1, 0.7), glowMat([1, 0.95, 1], 2.2, { side: THREE.DoubleSide }), 2.5)
  inner.position.set(0, 0.98, -GAP * 0.85); group.add(inner)

  const cards = []
  for (let i = 0; i < 5; i++) {
    const c = mesh(new THREE.PlaneGeometry(CW, CH), new THREE.ShaderMaterial({
      uniforms: { uMap: { value: cardBack }, uBright: { value: 1 }, uOpacity: { value: 1 } },
      vertexShader: SIMPLE_VERT, fragmentShader: CARD_FRAG, transparent: true, side: THREE.DoubleSide }), 2)
    cards.push(c); group.add(c)
  }

  // peel a back flap outward (to its side) and away from the pack (toward the camera, local -z)
  const deformFlap = (f, base, side, p, t) => {
    const pos = f.geometry.attributes.position
    const px = side * PW / 2
    for (let i = 0; i < pos.count; i++) {
      const x0 = base[i * 3], y0 = base[i * 3 + 1]
      const u = Math.abs(x0) / (PW / 2), v = (y0 - YS) / (1 - YS)
      const w = Math.pow(v, 1.1) * (1.05 - 0.5 * u)
      const rx = x0 - px, ry = y0 - YS
      const az = -side * p * 0.5 * w
      const nx = rx * Math.cos(az) - ry * Math.sin(az), ny = rx * Math.sin(az) + ry * Math.cos(az)
      const ay = p * 1.15 * w
      const lift = Math.abs(nx) * Math.sin(ay) + p * 0.2 * w * w + p * 0.02 * Math.sin(v * 9 + u * 5 + t * 2) * w
      pos.setXYZ(i, px + nx * Math.cos(ay), YS + ny, -GAP - lift)
    }
    pos.needsUpdate = true
    f.geometry.computeVertexNormals()
  }

  let dist0 = 4.85 // camera distance at which the pack fills opts.packFill of the view height (set in resize)
  const reduce = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches
  const pose = t => {
    const spin = inOut(clamp((t - T.spinA) / (T.spinB - T.spinA)))
    const yaw = spin * Math.PI * 3 + 0.05 * Math.sin(t * 1.4) // 1.5 turns: lands on the back
    const edge = Math.abs(Math.sin(yaw))
    const push = inOut(clamp((t - T.spinB) / (T.pushB - T.spinB)))
    const tension = ss(T.seamA, T.seamB, t)
    const p = outBack(clamp((t - T.seamB) / 1.0))
    const rise = clamp((t - T.peelB) / (T.riseB - T.peelB))
    const slide = inOut(clamp(rise / 0.62))           // straight up between the sheets
    const away = inOut(clamp((rise - 0.55) / 0.45))   // then toward the camera once clear
    const shake = reduce ? 0 : (0.006 * tension * (1 - p) * Math.sin(t * 70) + 0.012 * Math.exp(-Math.max(0, t - T.seamB) * 7) * Math.sin(t * 95) * (t > T.seamB ? 1 : 0))

    const dropY = -1.5 * ss(0.45, 1, rise)
    const cardWorldY = dropY + lerp(CARD_Y0, CARD_Y1, slide) + 0.35 * away
    const cy = lerp(lerp(0, 0.7, push), cardWorldY, inOut(clamp(rise * 1.1)))
    const cz = lerp(lerp(dist0, dist0 * 0.69, push) - 0.07 * ss(T.pushB, T.seamA, t), dist0 * 0.9, inOut(rise))
    camera.position.set(shake, cy + shake * 0.6, cz)
    camera.lookAt(0, cy, 0)

    group.rotation.y = yaw * (1 - push) + Math.PI * push + 0.03 * Math.sin(t * 0.9) * push * (1 - rise)
    group.rotation.x = 0.04 * Math.sin(t * 1.1) * (1 - rise)
    group.position.y = dropY

    const packFade = 1 - ss(T.riseB - 0.5, T.riseB - 0.05, t)
    const open = ss(T.seamB - 0.05, T.seamB + 0.55, t)
    for (const m of [frontMat, backMat, ...flapMats]) {
      m.uniforms.uOpacity.value = packFade
      m.uniforms.uHaloI.value = (0.25 + 0.9 * edge) * (1 - push * 0.7)
      m.uniforms.uSheen.value = 0.35 * Math.pow(edge, 2)
      m.uniforms.uGlow.value = open * (1 - 0.6 * ss(T.peelB, T.riseB, t))
    }
    for (const m of flapMats) m.uniforms.uSeam.value = Math.max(0.25 * tension, ss(T.seamB - 0.05, T.seamB + 0.12, t))
    flaps.forEach((f, k) => deformFlap(f, flapBase[k], k === 0 ? -1 : 1, Math.max(0, p), t))

    halo.material.uniforms.uI.value = (0.55 + 0.9 * edge) * (1 - 0.75 * push) + 0.25 * open * (1 - rise)
    halo.position.y = camera.position.y
    rays.material.uniforms.uI.value = open * (1 - ss(T.peelB + 0.4, T.riseB - 0.2, t)) * (1 + 0.06 * Math.sin(t * 13))
    rays.material.uniforms.uTime.value = t
    inner.material.uniforms.uI.value = open * 0.4 * (1 - 0.7 * ss(T.peelB + 0.3, T.riseB, t))

    cards.forEach((c, i) => {
      const lag = clamp(slide * 1.06 - i * 0.015)
      const y = lerp(CARD_Y0, CARD_Y1, inOut(lag)) + 0.35 * away - i * 0.006 * (1 - away)
      c.position.set((i - 2) * 0.01 * (1 - slide), y, -0.004 - i * 0.003 - 0.6 * away) // between the sheets until clear
      c.rotation.z = (i - 2) * 0.01 * (1 - slide)
      c.material.uniforms.uBright.value = 1 + 0.7 * open * (1 - ss(T.peelB + 0.5, T.riseB - 0.1, t))
    })
  }

  const resize = () => {
    const w = canvas.clientWidth || 1, h = canvas.clientHeight || 1
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, opts.maxPixelRatio))
    renderer.setSize(w, h, false)
    camera.aspect = w / h
    camera.fov = w / h < 1 ? 38 : 30
    // keep the pack centred on the stage even when the canvas is larger than the stage (full-screen layer)
    const off = opts.centerOffset
    if (off && (off.x || off.y)) camera.setViewOffset(w, h, -off.x, -off.y, w, h)
    else camera.clearViewOffset()
    camera.updateProjectionMatrix()
    // pack is 2 units tall: on screen it is 2 / (2 * d * tan(fov/2)) of the view height
    // the shader cuts the crimp teeth inside the outline (tooth tips sit ~1% in at top and bottom), the CSS packs print them in the image,
    // so frame the 3D pack slightly larger to make the visible packs match
    dist0 = 1 / ((Math.max(0.2, opts.packFill) / 0.982) * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2))
  }
  resize()
  const ro = typeof ResizeObserver === 'function' ? new ResizeObserver(resize) : null
  ro?.observe(canvas)

  // the top (nearest) card, projected to canvas CSS pixels
  const topCardRect = () => {
    const c = cards[cards.length - 1]; c.updateMatrixWorld(true)
    const w = canvas.clientWidth, h = canvas.clientHeight
    const pts = [[-CW / 2, -CH / 2], [CW / 2, CH / 2]].map(([x, y]) => new THREE.Vector3(x, y, 0).applyMatrix4(c.matrixWorld).project(camera))
    const xs = pts.map(p => (p.x + 1) / 2 * w), ys = pts.map(p => (1 - p.y) / 2 * h)
    return { x: Math.min(...xs), y: Math.min(...ys), w: Math.abs(xs[1] - xs[0]), h: Math.abs(ys[1] - ys[0]) }
  }

  let raf = 0, disposed = false
  pose(0); renderer.render(scene, camera)

  const play = ({ speed = 1, onPhase, isDead = () => false } = {}) => new Promise(resolve => {
    const t0 = performance.now()
    let next = 0
    const tick = () => {
      if (disposed || isDead()) { resolve(null); return }
      const t = ((performance.now() - t0) / 1000) * speed
      while (next < PHASE_AT.length && t >= PHASE_AT[next][0]) onPhase?.(PHASE_AT[next++][1])
      if (t >= T.riseB) {
        pose(T.riseB); renderer.render(scene, camera)
        resolve(topCardRect())
        return
      }
      pose(t); renderer.render(scene, camera)
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
  })

  const dispose = () => {
    if (disposed) return
    disposed = true
    cancelAnimationFrame(raf)
    ro?.disconnect()
    owned.forEach(o => o.dispose?.())
    renderer.dispose()
    renderer.forceContextLoss?.()
  }

  return { play, dispose, seek: t => { pose(t); renderer.render(scene, camera) } }
}

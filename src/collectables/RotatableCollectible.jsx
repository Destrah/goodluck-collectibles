import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import CollectableView from './CollectableView'
import { inspectorInputs } from './inspectorRevision.js'
import { queueInspectorBuild } from './inspectorLifecycle.js'

const clamp = (n, min, max) => Math.min(Math.max(n, min), max)
const rad = deg => deg * Math.PI / 180

// Lets the inspector push light/pointer positions into a TradingCard without re-rendering it every frame.
function createLightDriver() {
  const listeners = new Set()
  return { subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn) }, emit(light) { listeners.forEach(fn => fn(light)) } }
}

const OBJECT_TYPES = new Set(['challenge_coin', 'plushie'])
const EDGE_LAYERS = [-2.25, -1.5, -0.75, 0, 0.75, 1.5, 2.25]

// Coins and plushies are inspected as real 3D models (same models as the openings); cards keep their
// DOM foil/mask effects and get a physical edge. Falls back to the CSS view when WebGL is unavailable.
export default function RotatableCollectible(props) {
  const [webgl, setWebgl] = useState(true)
  if (OBJECT_TYPES.has(props.item?.collectableType) && webgl) return <ObjectInspector3D item={props.item} onFail={() => setWebgl(false)} />
  return <FlatInspector {...props} />
}

function ObjectInspector3D({ item, onFail }) {
  const host = useRef(null)
  const api = useRef(null)
  const buildQueue = useRef(Promise.resolve())
  const failed = useRef(onFail)
  failed.current = onFail
  const inputs = inspectorInputs(item)
  useEffect(() => {
    let dead = false, created = null
    const canvas = document.createElement('canvas'); canvas.className = 'collectible-3d-canvas'; canvas.setAttribute('aria-label', item.title || 'Collectible')
    host.current.appendChild(canvas)
    // Finish/dispose an outstanding build before allocating another WebGL context.
    // Intermediate edits can be skipped while remote artwork is still loading.
    buildQueue.current = queueInspectorBuild(buildQueue.current, {
      isCurrent: () => !dead,
      build: async () => {
        const { createContainerScene } = await import('./Container3D.js')
        if (dead) return null
        try {
          return await createContainerScene(canvas, { viewer: true, items: [item] })
        } catch (error) {
          // A failed constructor may allocate a context without returning a disposer.
          const context = canvas.getContext('webgl2') || canvas.getContext('webgl')
          context?.getExtension('WEBGL_lose_context')?.loseContext()
          throw error
        }
      },
      publish: result => { created = result; api.current = result },
      onError: error => {
        console.warn('[collectibles] 3D inspector unavailable, using flat view', error)
        failed.current()
      },
    })
    return () => { dead = true; created?.dispose(); api.current = null; canvas.remove() }
  }, inputs)
  const turn = (dx, dy) => api.current?.turn(dx, dy)
  return <div className="collectible-inspector">
    <div ref={host} className="collectible-3d-stage" />
    <div className="collectible-inspect-controls"><button onClick={() => turn(0, Math.PI)}>Flip</button><button onClick={() => turn(0, -Math.PI / 4)} aria-label="Rotate left">↶</button><button onClick={() => turn(0, Math.PI / 4)} aria-label="Rotate right">↷</button><button onClick={() => api.current?.reset()}>Reset view</button></div>
    <small>Drag to rotate · hover to catch the light</small>
  </div>
}

function FlatInspector({ item, size = 'viewer' }) {
  const [rotation, setRotation] = useState({ x: 0, y: 0 })
  const [tracking, setTracking] = useState(false)
  const drag = useRef(null)
  const live = useRef(rotation)
  const pointer = useRef({ nx: 0, ny: 0, inside: false })
  const shell = useRef(null)
  const front = useRef(null)
  const back = useRef(null)
  const frame = useRef(0)
  const driver = useMemo(createLightDriver, [])

  // Hover tilt is applied in screen space, outside the collectible's own rotation, so it always leans
  // toward the pointer. Finish/foil light is mapped into each face's local space, so a flipped or
  // upside-down collectible still lights up under the cursor, and turning it sweeps the light across.
  const paint = () => {
    frame.current = 0
    const el = shell.current
    if (!el) return
    const { nx, ny, inside } = pointer.current
    const { x, y } = live.current
    const dragging = !!drag.current
    const hovering = inside && !dragging
    const tiltX = hovering ? -ny * 10 : 0
    const tiltY = hovering ? nx * 14 : 0
    el.style.transform = `rotateX(${tiltX}deg) rotateY(${tiltY}deg) rotateX(${x}deg) rotateY(${y}deg)`
    const facing = Math.cos(rad(y)) >= 0 ? 1 : -1
    const upright = Math.cos(rad(x)) >= 0 ? 1 : -1
    const lit = inside || dragging
    const sweepX = Math.sin(rad(y) * 2) * 30
    const sweepY = Math.sin(rad(x) * 2) * 30
    const localX = clamp(50 + (inside ? nx * 50 : 0) * facing + sweepX, 0, 100)
    const localY = clamp(50 + (inside ? ny * 50 : 0) * upright - sweepY, 0, 100)
    const glint = Math.abs(Math.sin(rad(y) * 2 + rad(x))) * .6 + (inside ? Math.hypot(nx, ny) * .4 : 0)
    const faces = [[front.current, localX], [back.current, 100 - localX]]
    for (const [face, mx] of faces) {
      if (!face) continue
      face.style.setProperty('--mx', `${mx}%`)
      face.style.setProperty('--my', `${localY}%`)
      face.style.setProperty('--hover-active', lit ? 1 : 0)
      face.style.setProperty('--glint', glint.toFixed(3))
    }
    el.dataset.lit = lit ? '1' : '0'
    driver.emit({ x: facing > 0 ? localX : 100 - localX, y: localY, active: lit && facing > 0 })
  }
  const schedule = () => { if (!frame.current) frame.current = requestAnimationFrame(paint) }
  useLayoutEffect(() => { live.current = rotation; paint() }, [rotation])
  useEffect(() => () => cancelAnimationFrame(frame.current), [])

  const track = event => {
    const rect = event.currentTarget.getBoundingClientRect()
    pointer.current = { nx: clamp(((event.clientX - rect.left) / rect.width) * 2 - 1, -1, 1), ny: clamp(((event.clientY - rect.top) / rect.height) * 2 - 1, -1, 1), inside: true }
  }
  const move = event => {
    if (event.pointerType !== 'touch' || drag.current) track(event)
    if (drag.current) live.current = { x: drag.current.x - (event.clientY - drag.current.py) * .4, y: drag.current.y + (event.clientX - drag.current.px) * .6 }
    schedule()
  }
  const endDrag = () => { if (!drag.current) return; drag.current = null; setRotation(live.current) }
  const leave = () => { pointer.current = { ...pointer.current, inside: false }; setTracking(false); schedule() }

  return <div className="collectible-inspector">
    <div className="collectible-rotation-stage"
      onPointerEnter={event => { if (event.pointerType !== 'touch') { setTracking(true); track(event); schedule() } }}
      onPointerDown={event => { if (event.button !== 0) return; event.preventDefault(); event.currentTarget.setPointerCapture(event.pointerId); drag.current = { px:event.clientX, py:event.clientY, ...live.current }; setTracking(true); track(event); schedule() }}
      onPointerMove={move}
      onPointerUp={endDrag}
      onPointerCancel={endDrag}
      onPointerLeave={leave}>
      <div ref={shell} className={`collectible-rotation ${tracking ? 'dragging' : ''}`}>
        <div ref={front} className="collectible-inspect-face"><CollectableView item={item} size={size} interactive={false} driver={driver} /></div>
        <div ref={back} className="collectible-inspect-face collectible-inspect-back"><CollectableView item={item} size={size} interactive={false} back /></div>
        {!OBJECT_TYPES.has(item?.collectableType) && EDGE_LAYERS.map(z => <i key={z} className="collectible-card-edge" style={{ transform: `translateZ(${z}px)` }} aria-hidden="true" />)}
        {!OBJECT_TYPES.has(item?.collectableType) && <span className="collectible-card-sides" aria-hidden="true"><i className="side-left" /><i className="side-right" /><i className="side-top" /><i className="side-bottom" /></span>}
      </div>
    </div>
    <div className="collectible-inspect-controls"><button onClick={() => setRotation(current => ({ ...current, y:current.y+180 }))}>Flip</button><button onClick={() => setRotation(current => ({ ...current, y:current.y-45 }))} aria-label="Rotate left">↶</button><button onClick={() => setRotation(current => ({ ...current, y:current.y+45 }))} aria-label="Rotate right">↷</button><button onClick={() => setRotation({x:0,y:0})}>Reset view</button></div>
    <small>Drag to rotate · Flip to view the other side</small>
  </div>
}

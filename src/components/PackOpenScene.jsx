import React, { useEffect, useLayoutEffect, useRef, useState } from 'react'
import '../styles/packOpen.css'

const FRONT = '/img/pack_open_front.jpg'
const BACK = '/img/pack_open_back.jpg'
const CARD_BACK = '/img/Cards_Back.jpg'
const RATIO = 240 / 420 // pack width / height
const CARD_W = 340 // native width of a .pull-inner in the reveal row (full-size card layout: readable, sharp text)
export const PITCH = 364 // native card pitch in the reveal row (340 card + 24 gap)
const U = CARD_W / 230 // fan offsets below were designed for a 230px card
const EASE = 'cubic-bezier(.22,1,.36,1)'

/* ------------------------------------------------------------------ options */
export const TEAR_INFO = {
  // 'seam' is no longer offered in the menu; it stays as the automatic fallback for 'peel' when WebGL is unavailable
  seam: { label: 'Centre rip', short: 'Flip, then split down the seam', detail: 'The pack flips to its back, a crack runs down the centre seam, the foil peels apart in a V and a beam of light shoots out.' },
  top: { label: 'Top tear-off', short: 'Stays upright, foil strip rips off', detail: 'The pack stays upright, the top foil strip tears off in a jagged line and the stack slides straight up out of the opening.' },
  peel: { label: 'Back peel (3D)', short: 'Spin to the back, peel the seam open', detail: 'A 3D foil pack spins round to its back, the camera pushes in on the seam, the back peels outward to show the silver inside, light pours out and the face-down stack slides out the top.' },
}
export const FAN_INFO = {
  line: { label: 'Straight line', short: 'Burst out, settle into a neat row' },
  arc: { label: 'Hand fan', short: 'Fan out like a hand of cards' },
  wave: { label: 'Wave', short: 'Slide out one by one in a rolling wave' },
  deal: { label: 'Dealt', short: 'Flicked onto the table one at a time' },
}
export const RANDOM_INFO = { label: 'Random', short: 'A different combination every pack' }
// rough duration of one opening at 1x (seconds), used for the speed read-out
export const BASE_SECONDS = { seam: 6.5, top: 4.5, peel: 8 }
export const TEAR_KEYS = ['peel', 'top'] // tears offered to players (and picked from by Random)

export const pickRandom = (list) => list[Math.floor(Math.random() * list.length)]
export const resolveTear = value => (value === 'random' ? pickRandom(TEAR_KEYS) : (TEAR_KEYS.includes(value) ? value : 'peel'))
export const resolveFan = value => (value === 'random' ? pickRandom(['line', 'arc', 'wave', 'deal']) : (FAN_INFO[value] ? value : 'line'))

/**
 * Final resting pose of card i, in native card pixels (230x322 card), relative to the straight row.
 * The animation ends exactly on this pose and the real, clickable cards are placed with the same numbers.
 */
export function fanPose(fan, i, count = 5) {
  const d = i - (count - 1) / 2
  switch (fan) {
    case 'arc': return { dx: -50 * d * U, dy: d * d * 12 * U, r: d * 7 }
    case 'wave': return { dx: 0, dy: -Math.sin((i / Math.max(1, count - 1)) * Math.PI * 2) * 22 * U, r: d * 2 }
    case 'deal': { const J = [[-2.5, 4], [1.8, -3], [-1, 5], [2.2, -4], [-2, 3]]; const j = J[i % J.length]; return { dx: 0, dy: j[1] * U, r: j[0] } }
    default: return { dx: 0, dy: 0, r: 0 }
  }
}
export const fanVars = (fan, i, count = 5) => {
  const p = fanPose(fan, i, count)
  return { '--dx': `${p.dx}px`, '--dy': `${p.dy}px`, '--dr': `${p.r}deg` }
}

// interlocking jagged foil edge (centre seam)
const zig = side => Array.from({ length: 25 }, (_, i) => `${(side ? 0 : 100) + (i % 2 ? (side ? 9 : -9) : 0)}% ${(i / 24) * 100}%`)
const CLIP_L = `polygon(0 0,100% 0,${zig(0).slice(1).join(',')},0 100%)`
const CLIP_R = `polygon(${zig(1).join(',')},100% 100%,100% 0)`
// jagged tear line across the top (top tear-off)
const TEETH = Array.from({ length: 21 }, (_, i) => `${i * 5}% ${i % 2 ? 9.6 : 8}%`)
const CLIP_STRIP = `polygon(0 0,100% 0,${[...TEETH].reverse().join(',')})`
const CLIP_DBASE = `polygon(${TEETH.join(',')},100% 100%,0 100%)`

/** Pack height for a stage box. Every tear style starts with the pack at exactly this size (the 3D peel included). */
export const PACK_FILL = 0.72, PACK_MAX = 420
export const packHeightFor = h => Math.min(h * PACK_FILL, PACK_MAX)

/** Final card width for a stage box. Shared by the animation and the reveal row so they match exactly. */
export function cardWidthFor(w, h, count = 5) {
  const ph = Math.min(h * 0.78, 560)
  return Math.min(CARD_W, (w - 40) / (count * 1.07), ph * 0.64)
}

/**
 * One persistent stage. The animation plays inside it and the reveal row (children) is placed
 * in the exact same spot, scaled to the same card size, so the animated cards simply become the real ones.
 */
export function PackStage({ children, count = 5 }) {
  const ref = useRef(null)
  const [k, setK] = useState(1)
  useLayoutEffect(() => {
    const measure = () => {
      const r = ref.current.getBoundingClientRect()
      setK(cardWidthFor(r.width, r.height, count) / CARD_W)
    }
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(ref.current)
    return () => ro.disconnect()
  }, [count])
  return (
    <div className="pk-stage" ref={ref} style={{ '--pk-k': k }}>
      <div className="pk-glow" />
      <div className="pk-floor" />
      {children}
    </div>
  )
}

/** The reveal row, centred in the stage and scaled to the animated card size. */
export function PackTable({ children }) {
  return <div className="pk-table">{children}</div>
}

/**
 * Runs the pack opening and calls onDone() when the face-down cards sit in their final pose.
 *   tear  'peel' | 'top' | 'seam'         how the pack is opened ('peel' = lazy-loaded Three.js scene; 'seam' = its no-WebGL fallback)
 *   fan   'line' | 'arc' | 'wave' | 'deal'  how the cards come out and where they rest
 *   speed 1 .. max                        1 = original pace (slowest), higher = faster
 * Keep it mounted briefly after onDone and set `handoff` so it can fade out under the real cards.
 * onPhase(name): front, tilt, flip-start, back, seam-tension, tear-start, tear-mid, tear-open, cards-pull, fan, settle
 */
export default function PackOpenScene({ tear = 'seam', fan = 'line', speed = 1, count = 5, handoff = false, onPhase, onDone }) {
  const root = useRef(null)
  const cb = useRef({ onPhase, onDone })
  cb.current = { onPhase, onDone }

  useEffect(() => {
    const T = tear === 'top'
    const k = 1 / Math.max(1, Number(speed) || 1)
    let dead = false
    const timers = []
    const disposers = []
    const q = s => root.current.querySelector(s)
    const wait = ms => new Promise(r => timers.push(setTimeout(r, ms * k)))
    const go = (el, frames, o = {}) => {
      if (dead) return Promise.resolve()
      const a = el.animate(frames, { fill: 'forwards', ...o, duration: (o.duration || 0) * k, delay: (o.delay || 0) * k })
      return a.finished.catch(() => {})
    }
    const phase = n => !dead && cb.current.onPhase?.(n)

    // ---- sizing ----
    const r = root.current.getBoundingClientRect()
    const ph = packHeightFor(r.height)
    const pw = ph * RATIO
    const cw = cardWidthFor(r.width, r.height, count)
    const kk = cw / CARD_W
    const st = root.current.style
    st.setProperty('--pk-ph', ph + 'px'); st.setProperty('--pk-pw', pw + 'px')
    st.setProperty('--pk-front', `url(${FRONT})`); st.setProperty('--pk-back', `url(${BACK})`); st.setProperty('--pk-cardback', `url(${CARD_BACK})`)

    // cards start hidden inside the pack, then scale up to the final reveal-row size
    const pcw = pw * (T ? 0.84 : 0.8), pch = (pcw * 461) / 330, top0 = ph * (T ? 0.04 : 0.14)
    const s = cw / pcw
    const cards = [...root.current.querySelectorAll('.pk-card')]
    cards.forEach(c => { c.style.width = pcw + 'px'; c.style.height = pch + 'px'; c.style.left = (pw - pcw) / 2 + 'px'; c.style.top = top0 + 'px' })
    // Top tear-off: the stack slides out above the pack, so sit the pack a little lower to keep the cards on stage
    const rigTop = (r.height - ph) / 2
    const lift = T ? Math.max(0, Math.min(rigTop - 10, 10 - (rigTop + top0 - pch * 0.5))) : 0
    const toCenterY = ph / 2 - (top0 + pch / 2) - lift // moves a card centre to the stage centre
    const mid = (count - 1) / 2
    const finalT = i => {
      const p = fanPose(fan, i, count)
      return `translate(${((i - mid) * PITCH + p.dx) * kk}px,${toCenterY + p.dy * kk}px) rotate(${p.r}deg) scale(${s})`
    }
    const rig = q('.pk-rig'), idle = q('.pk-idle'), cardsEl = q('.pk-cards')
    rig.style.top = lift + 'px'
    const fadePack = els => els.map(e => go(e, [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateY(260px) rotate(8deg)' }], { duration: 700, easing: 'ease-in' }))

    // ---------------- tear styles: both end with the face-down stack pulled out of the pack ----------------
    const seamTear = async () => {
      const torn = q('.pk-torn'), L = q('.pk-flap--l'), R = q('.pk-flap--r'), base = q('.pk-base'), beam = q('.pk-beam'), seam = q('.pk-seam')
      const rise = -ph * 0.42
      phase('front'); phase('tilt')
      idle.style.animation = 'none'
      await go(rig, [{ transform: 'rotate(0) scale(1)' }, { transform: 'rotate(-3deg) scale(1.05)' }], { duration: 300, easing: 'ease-out' })
      if (dead) return
      phase('flip-start')
      go(q('.pk-swoosh'), [{ opacity: 0, transform: 'scale(.6) rotate(-20deg)' }, { opacity: 1, offset: .4 }, { opacity: 0, transform: 'scale(1.25) rotate(25deg)' }], { duration: 900 })
      await go(rig, [{ transform: 'rotate(-3deg) scale(1.05) rotateY(0)' }, { transform: 'rotate(0) scale(1.14) rotateY(90deg)', offset: .5 }, { transform: 'rotate(0) scale(1) rotateY(180deg)' }], { duration: 1000, easing: 'ease-in-out' })
      if (dead) return
      rig.getAnimations().forEach(a => a.cancel()); rig.style.transform = ''
      torn.style.display = 'block'; idle.style.display = 'none'; cardsEl.style.visibility = 'visible'
      phase('back'); await wait(260)
      phase('seam-tension')
      go(rig, [{ transform: 'translateX(0)' }, { transform: 'translateX(-3px)' }, { transform: 'translateX(3px)' }, { transform: 'translateX(-2px)' }, { transform: 'translateX(0)' }], { duration: 380 })
      go(seam, [{ opacity: 1, transform: 'scaleY(0)' }, { opacity: 1, transform: 'scaleY(1)' }], { duration: 420, easing: 'ease-in' })
      await wait(430)
      phase('tear-start')
      go(seam, [{ opacity: 1 }, { opacity: 0 }], { duration: 300 })
      go(beam, [{ opacity: 0, transform: 'translate(-50%,-70%) scaleY(0)' }, { opacity: 1, transform: 'translate(-50%,-70%) scaleY(1)' }], { duration: 500 })
      timers.push(setTimeout(() => phase('tear-mid'), 300 * k), setTimeout(() => phase('tear-open'), 620 * k))
      go(L, [{ transform: 'rotate(0)' }, { transform: 'rotate(-30deg) rotateY(25deg)' }], { duration: 900, easing: EASE })
      await go(R, [{ transform: 'rotate(0)' }, { transform: 'rotate(30deg) rotateY(-25deg)' }], { duration: 900, easing: EASE })
      if (dead) return null
      phase('cards-pull')
      const stackT = i => `translate(${(i - 2) * pw * 0.03}px,${rise - i * 6}px) scale(1)`
      await Promise.all(cards.map((c, i) => go(c, [{ transform: 'translate(0,0) scale(1)' }, { transform: stackT(i) }], { duration: 900, delay: i * 90, easing: EASE })))
      go(beam, [{ opacity: 1 }, { opacity: 0 }], { duration: 600 })
      const away = Promise.all(fadePack([L, R, base]))
      await wait(220)
      return { stackT, away, rise }
    }

    const topTear = async () => {
      const dpack = q('.pk-dpack'), strip = q('.pk-dstrip')
      const rise = -pch * 0.5
      cardsEl.style.visibility = 'visible'
      phase('front'); phase('tilt')
      idle.style.animation = 'none'
      await go(rig, [{ transform: 'scale(1)' }, { transform: 'scale(1.05) rotate(-2deg)' }], { duration: 350, easing: 'ease-out' })
      if (dead) return null
      phase('seam-tension')
      await go(rig, [{ transform: 'scale(1.05) rotate(-2deg)' }, { transform: 'scale(1.05) translateX(-3px)' }, { transform: 'scale(1.05) translateX(3px)' }, { transform: 'scale(1.02) translateX(-2px)' }, { transform: 'scale(1) rotate(0)' }], { duration: 360 })
      rig.getAnimations().forEach(a => a.cancel()); rig.style.transform = ''
      if (dead) return null
      dpack.style.display = 'block'; idle.style.display = 'none'
      phase('tear-start')
      timers.push(setTimeout(() => phase('tear-mid'), 180 * k), setTimeout(() => phase('tear-open'), 380 * k))
      go(q('.pk-spark'), [{ opacity: 0, transform: 'translate(-50%,-50%) scale(.3)' }, { opacity: 1, offset: .3 }, { opacity: 0, transform: 'translate(-50%,-50%) scale(1.6)' }], { duration: 600 })
      await go(strip, [{ transform: 'none', opacity: 1 }, { transform: `translate(${pw * 0.55}px,${-ph * 0.22}px) rotate(24deg)`, opacity: 0 }], { duration: 650, easing: 'cubic-bezier(.4,0,.2,1)' })
      if (dead) return null
      phase('cards-pull')
      const stackT = i => `translate(${(i - 2) * pw * 0.012}px,${rise - i * 3}px) scale(1)`
      await Promise.all(cards.map((c, i) => go(c, [{ transform: `translate(${(i - 2) * pw * 0.012}px,${-i * 3}px) scale(1)` }, { transform: stackT(i) }], { duration: 850, delay: (count - 1 - i) * 55, easing: EASE })))
      cardsEl.style.zIndex = 5
      const away = go(dpack, [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateY(240px)' }], { duration: 750, delay: 260, easing: 'ease-in' })
      return { stackT, away, rise }
    }

    // 3D back peel: the Three.js scene runs the whole opening, then the DOM cards take over on the exact spot
    // where the 3D stack ended, so every fan-out style works unchanged. Falls back to the centre rip without WebGL.
    const peelTear = async () => {
      const canvas = q('.pk-gl')
      let peel
      try {
        const { createPeelScene } = await import('./PeelTear3D.js')
        if (dead) return null
        // the 3D layer spans the full window width and reaches 60% of the stage height above and below it,
        // so the pack is never cut off by the stage edges; the camera is shifted so the pack sits on the stage centre
        const sr = root.current.getBoundingClientRect(), vw = window.innerWidth
        const bandTop = -sr.height * 0.6, bandH = sr.height * 2.2
        Object.assign(canvas.style, { left: `${-sr.left}px`, top: `${bandTop}px`, right: 'auto', bottom: 'auto', width: `${vw}px`, height: `${bandH}px` })
        canvas.classList.add('pk-gl--full')
        const centerOffset = { x: sr.left + sr.width / 2 - vw / 2, y: 0 }
        peel = await createPeelScene(canvas, { front: FRONT, back: BACK, cardBack: CARD_BACK, packFill: ph / bandH, centerOffset })
      } catch (error) {
        console.warn('Back peel needs WebGL; using the centre rip instead.', error)
        root.current?.classList.remove('pk-scene--p')
        return dead ? null : seamTear()
      }
      if (dead) { peel.dispose(); return null }
      disposers.push(peel.dispose)
      idle.style.animation = 'none'
      const rect = await peel.play({ speed: 1 / k, onPhase: phase, isDead: () => dead })
      if (dead || !rect) return null
      // drop the DOM stack exactly on the projected 3D stack
      const rr = root.current.getBoundingClientRect(), cr = cards[0].getBoundingClientRect(), gr = canvas.getBoundingClientRect()
      const bx = cr.left - rr.left + cr.width / 2, by = cr.top - rr.top + cr.height / 2
      // rect is in canvas pixels; convert to the scene's own coordinates
      const dx = rect.x + rect.w / 2 + (gr.left - rr.left) - bx, dy = rect.y + rect.h / 2 + (gr.top - rr.top) - by, sc = rect.w / pcw
      const stackT = i => `translate(${dx + (i - mid) * 0.6}px,${dy - (count - 1 - i) * 0.8}px) scale(${sc})`
      cards.forEach((c, i) => { c.style.transform = stackT(i) })
      cardsEl.style.zIndex = 5
      cardsEl.style.visibility = 'visible'
      const away = go(canvas, [{ opacity: 1 }, { opacity: 0 }], { duration: 450, easing: 'ease-out' }).then(() => peel.dispose())
      return { stackT, away, rise: dy }
    }

    // ---------------- fan-out styles: stack -> final pose ----------------
    const fanOut = async ({ stackT, rise }) => {
      phase('fan')
      const sgn = i => (i % 2 ? -1 : 1)
      const run = {
        // burst out wide, then settle into a straight row
        line: () => cards.map((c, i) => { const d = i - mid; return go(c, [
          { transform: stackT(i) },
          { transform: `translate(${d * PITCH * kk * 0.8}px,${rise * 0.5 + toCenterY * 0.5 + d * d * 9}px) rotate(${d * 9}deg) scale(${s * 0.95})`, offset: 0.55 },
          { transform: finalT(i) }], { duration: 1100, delay: i * 60, easing: EASE }) }),
        // lift the whole stack, spread the angles like a hand of cards, then lower into the arc
        arc: () => cards.map((c, i) => { const d = i - mid; return go(c, [
          { transform: stackT(i) },
          { transform: `translate(${d * 34 * U * kk}px,${rise * 0.9 + toCenterY * 0.4}px) rotate(${d * 17}deg) scale(${s * 0.98})`, offset: 0.45 },
          { transform: finalT(i) }], { duration: 1250, delay: i * 40, easing: EASE }) }),
        // each card slides out in turn and rolls into the wave
        wave: () => cards.map((c, i) => go(c, [
          { transform: stackT(i) },
          { transform: `translate(${(i - mid) * PITCH * kk * 0.55}px,${toCenterY - 90 * U * kk}px) rotate(${sgn(i) * 6}deg) scale(${s * 1.06})`, offset: 0.5 },
          { transform: finalT(i) }], { duration: 1000, delay: i * 130, easing: EASE })),
        // flicked out one at a time: lift off the stack, glide to the spot with a slight tilt, settle (no spinning)
        deal: () => cards.map((c, i) => { const p = fanPose('deal', i, count); const fx = ((i - mid) * PITCH + p.dx) * kk; return go(c, [
          { transform: stackT(i) },
          { transform: `translate(${fx * 0.7}px,${toCenterY + p.dy * kk - 46 * U * kk}px) rotate(${p.r + sgn(i) * 9}deg) scale(${s * 1.07})`, offset: 0.55 },
          { transform: finalT(i) }], { duration: 850, delay: i * 170, easing: EASE }) }),
      }
      await Promise.all((run[fan] || run.line)())
    }

    ;(async () => {
      const result = await (tear === 'peel' ? peelTear() : T ? topTear() : seamTear())
      if (dead || !result) return
      await fanOut(result)
      await result.away
      if (dead) return
      phase('settle'); await wait(200)
      if (!dead) cb.current.onDone?.()
    })()

    return () => { dead = true; timers.forEach(clearTimeout); disposers.forEach(fn => fn()) }
  }, [tear, fan, speed, count])

  return (
    <div className={`pk-scene pk-scene--${tear === 'top' ? 'd' : tear === 'peel' ? 'p' : 'c'} ${handoff ? 'pk-scene--out' : ''}`} ref={root} aria-hidden="true">
      {tear === 'peel' && <canvas className="pk-gl" />}
      <div className="pk-rig">
        <div className="pk-cards">{Array.from({ length: count }, (_, i) => <div className="pk-card" key={i} />)}</div>
        <div className="pk-idle">
          <div className="pk-face pk-face--front" />
          <div className="pk-face pk-face--back" />
          <div className="pk-shine" />
        </div>
        <div className="pk-swoosh" />
        <div className="pk-torn">
          <div className="pk-beam" />
          <div className="pk-flap pk-flap--l"><i style={{ clipPath: CLIP_L }} /></div>
          <div className="pk-flap pk-flap--r"><i style={{ clipPath: CLIP_R }} /></div>
          <div className="pk-base" />
          <div className="pk-seam" />
        </div>
        <div className="pk-dpack">
          <div className="pk-dbase" style={{ clipPath: CLIP_DBASE }} />
          <div className="pk-dstrip" style={{ clipPath: CLIP_STRIP }} />
          <div className="pk-spark" />
        </div>
      </div>
    </div>
  )
}

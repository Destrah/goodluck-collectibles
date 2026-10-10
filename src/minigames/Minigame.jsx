import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import './minigame.css'
import ShearLineLockpick from './ShearLineLockpick.jsx'
import CraftingMinigame from './CraftingMinigame.jsx'

// Built-in skill checks for FiveM (client/minigames.lua, Config.Minigames type 'builtin'). Each game calls
// onResult(true | false) once. Escape gives up (fails).
//   lockpick { pins, tol, band, time, showBand, drift, shift, spools }   skimmer { wires, time, mistakes }
//   keypad { length, show, time, rounds }            sequence { keys, perKey, rounds }
//   simon { start, length, show, time }              grid { size, cells, rounds, show, time, mistakes }
//   safe { numbers, tolerance, speed, time, mistakes }   reaction { grid, targets, life, traps, misses }
//   order { count, time, shuffle, mistakes }         circle { zones, zone, speed, time, mistakes, reverse }

function useCountdown(seconds, onTimeout, running = true) {
  const [left, setLeft] = useState(seconds)
  const end = useRef(0)
  useEffect(() => { end.current = performance.now() + seconds * 1000; setLeft(seconds) }, [seconds])
  useEffect(() => {
    if (!running) return
    const timer = setInterval(() => {
      const remaining = Math.max(0, (end.current - performance.now()) / 1000)
      setLeft(remaining)
      if (remaining <= 0) { clearInterval(timer); onTimeout() }
    }, 100)
    return () => clearInterval(timer)
  }, [running, onTimeout])
  return [left, extra => { end.current = performance.now() + extra * 1000 }]
}

function Timer({ left, total }) {
  return <div className="mg-timer"><i style={{ width: `${Math.max(0, Math.min(100, (left / total) * 100))}%` }} className={left / total < 0.25 ? 'low' : ''} /></div>
}
function Lives({ used, max }) {
  if (max == null) return null
  return <div className="mg-lives">{Array.from({ length: max + 1 }, (_, i) => <span key={i} className={i < max + 1 - used ? 'on' : ''} />)}</div>
}

/* keypad: memorise the code, then type it */
function Keypad({ config, done }) {
  const length = Math.min(12, Math.max(3, Number(config.length) || 6))
  const rounds = Math.max(1, Number(config.rounds) || 1)
  const show = Math.max(0.5, Number(config.show) || 3)
  const total = Math.max(4, Number(config.time) || 12)
  const makeCode = () => Array.from({ length }, () => Math.floor(Math.random() * 10)).join('')
  const [round, setRound] = useState(0)
  const [code, setCode] = useState(makeCode)
  const [typed, setTyped] = useState('')
  const [showing, setShowing] = useState(true)
  const timeout = useCallback(() => done(false), [done])
  const [left, restart] = useCountdown(total, timeout, !showing)

  useEffect(() => { setShowing(true); const timer = setTimeout(() => { setShowing(false); restart(total) }, show * 1000); return () => clearTimeout(timer) }, [code]) // eslint-disable-line react-hooks/exhaustive-deps
  const press = useCallback(digit => {
    if (showing) return
    const next = typed + digit
    if (code[next.length - 1] !== digit) return done(false)
    if (next.length < length) return setTyped(next)
    if (round + 1 >= rounds) return done(true)
    setRound(round + 1); setTyped(''); setCode(makeCode())
  }, [showing, typed, code, length, round, rounds, done]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    const onKey = event => { if (/^[0-9]$/.test(event.key)) press(event.key) }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [press])
  return (
    <div className="mg-game">
      <h3>Enter the access code</h3>
      <p>{showing ? 'Memorise the code…' : `Type it in (round ${round + 1} of ${rounds}).`}</p>
      <div className="mg-code">{Array.from({ length }, (_, i) => <span key={i}>{showing ? code[i] : typed[i] ? typed[i] : ''}</span>)}</div>
      <div className="mg-keypad">{['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'].map(digit => <button key={digit} disabled={showing} onClick={() => press(digit)}>{digit}</button>)}</div>
      {!showing && <Timer left={left} total={total} />}
    </div>
  )
}

/* sequence: press the shown key before it runs out */
const SEQ_KEYS = [['w', 'W', '▲'], ['a', 'A', '◀'], ['s', 'S', '▼'], ['d', 'D', '▶']]
const ARROWS = { ArrowUp: 'w', ArrowLeft: 'a', ArrowDown: 's', ArrowRight: 'd' }
function Sequence({ config, done }) {
  const keys = Math.max(3, Number(config.keys) || 8)
  const rounds = Math.max(1, Number(config.rounds) || 1)
  const perKey = Math.max(0.3, Number(config.perKey) || 1.2)
  const pick = () => SEQ_KEYS[Math.floor(Math.random() * SEQ_KEYS.length)]
  const [index, setIndex] = useState(0)
  const [current, setCurrent] = useState(pick)
  const timeout = useCallback(() => done(false), [done])
  const [left, restart] = useCountdown(perKey, timeout)
  const press = useCallback(key => {
    if (key !== current[0]) return done(false)
    if (index + 1 >= keys * rounds) return done(true)
    setIndex(index + 1); setCurrent(pick()); restart(perKey)
  }, [current, index, keys, rounds, perKey, done]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    const onKey = event => {
      const key = ARROWS[event.key] || event.key.toLowerCase()
      if (['w', 'a', 's', 'd'].includes(key)) { event.preventDefault(); press(key) }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [press])
  return (
    <div className="mg-game">
      <h3>Keep the drill steady</h3>
      <p>Press the key shown (WASD or arrows). {index + 1} / {keys * rounds}</p>
      <div className="mg-seq" key={index}><kbd>{current[1]}</kbd><span>{current[2]}</span></div>
      <div className="mg-seq-buttons">{SEQ_KEYS.map(([key, label, arrow]) => <button key={key} onClick={() => press(key)}>{arrow} {label}</button>)}</div>
      <Timer left={left} total={perKey} />
    </div>
  )
}



/* simon: watch the pads light up, then repeat the sequence; it grows by one each round */
const SIMON = [['#e5484d', '1'], ['#3e9bff', '2'], ['#ffd23c', '3'], ['#30c46e', '4']]
function Simon({ config, done }) {
  const start = Math.max(1, Number(config.start) || 3)
  const length = Math.max(start, Number(config.length) || 7)
  const show = Math.max(0.15, Number(config.show) || 0.5)
  const total = Math.max(2, Number(config.time) || 8)
  const [sequence, setSequence] = useState(() => Array.from({ length: start }, () => Math.floor(Math.random() * 4)))
  const [lit, setLit] = useState(null)
  const [showing, setShowing] = useState(true)
  const [input, setInput] = useState(0)
  const timeout = useCallback(() => done(false), [done])
  const [left, restart] = useCountdown(total, timeout, !showing)

  useEffect(() => {
    setShowing(true); setInput(0)
    const timers = []
    sequence.forEach((pad, i) => {
      timers.push(setTimeout(() => setLit(pad), 500 + i * show * 1400))
      timers.push(setTimeout(() => setLit(null), 500 + i * show * 1400 + show * 1000))
    })
    timers.push(setTimeout(() => { setShowing(false); restart(total) }, 500 + sequence.length * show * 1400))
    return () => timers.forEach(clearTimeout)
  }, [sequence]) // eslint-disable-line react-hooks/exhaustive-deps

  const press = useCallback(pad => {
    if (showing) return
    setLit(pad); setTimeout(() => setLit(current => (current === pad ? null : current)), 160)
    if (sequence[input] !== pad) return done(false)
    if (input + 1 < sequence.length) return setInput(input + 1)
    if (sequence.length >= length) return done(true)
    setTimeout(() => setSequence([...sequence, Math.floor(Math.random() * 4)]), 350)
    setShowing(true)
  }, [showing, sequence, input, length, done])
  useEffect(() => {
    const onKey = event => { const pad = ['1', '2', '3', '4'].indexOf(event.key); if (pad >= 0) press(pad) }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [press])
  return (
    <div className="mg-game">
      <h3>Copy the signal</h3>
      <p>{showing ? 'Watch the pads…' : `Repeat it: ${input} / ${sequence.length}`} (keys <kbd>1</kbd>-<kbd>4</kbd>). Length {sequence.length} of {length}.</p>
      <div className="mg-simon">{SIMON.map(([color, key], i) => (
        <button key={key} className={lit === i ? 'lit' : ''} style={{ '--c': color }} disabled={showing} onMouseDown={() => press(i)}>{key}</button>
      ))}</div>
      {!showing && <Timer left={left} total={total} />}
    </div>
  )
}

/* grid: some squares flash, then click every one of them from memory */
function MemoryGrid({ config, done }) {
  const size = Math.min(7, Math.max(3, Number(config.size) || 5))
  const startCells = Math.min(size * size - 1, Math.max(2, Number(config.cells) || 5))
  const rounds = Math.max(1, Number(config.rounds) || 3)
  const show = Math.max(0.3, Number(config.show) || 1.5)
  const total = Math.max(2, Number(config.time) || 10)
  const maxMistakes = Math.max(0, Number(config.mistakes ?? 1))
  const pickCells = count => { const all = [...Array(size * size).keys()].sort(() => Math.random() - 0.5); return new Set(all.slice(0, Math.min(count, size * size - 1))) }
  const [round, setRound] = useState(0)
  const [cells, setCells] = useState(() => pickCells(startCells))
  const [found, setFound] = useState(() => new Set())
  const [wrong, setWrong] = useState(() => new Set())
  const [showing, setShowing] = useState(true)
  const timeout = useCallback(() => done(false), [done])
  const [left, restart] = useCountdown(total, timeout, !showing)

  useEffect(() => { setShowing(true); const timer = setTimeout(() => { setShowing(false); restart(total) }, 400 + show * 1000); return () => clearTimeout(timer) }, [cells]) // eslint-disable-line react-hooks/exhaustive-deps
  const click = index => {
    if (showing || found.has(index) || wrong.has(index)) return
    if (!cells.has(index)) {
      const next = new Set(wrong).add(index); setWrong(next)
      if (next.size > maxMistakes) done(false)
      return
    }
    const next = new Set(found).add(index); setFound(next)
    if (next.size < cells.size) return
    if (round + 1 >= rounds) return done(true)
    setShowing(true)
    setTimeout(() => { setRound(round + 1); setFound(new Set()); setWrong(new Set()); setCells(pickCells(startCells + round + 1)) }, 450)
  }
  return (
    <div className="mg-game">
      <h3>Remember the pattern</h3>
      <p>{showing ? 'Memorise the lit squares…' : `Click every lit square. Round ${round + 1} of ${rounds}.`}</p>
      <div className="mg-grid" style={{ gridTemplateColumns: `repeat(${size}, 1fr)` }}>
        {Array.from({ length: size * size }, (_, i) => (
          <button key={`${round}-${i}`} disabled={showing} onClick={() => click(i)}
            className={showing && cells.has(i) ? 'lit' : found.has(i) ? 'found' : wrong.has(i) ? 'wrong' : ''} aria-label={`square ${i + 1}`} />
        ))}
      </div>
      <Lives used={wrong.size} max={maxMistakes} />
      {!showing && <Timer left={left} total={total} />}
    </div>
  )
}

/* safe: turn the dial (A / D or the arrow keys, hold to spin) until it clicks, then press Space; alternate direction
   for each number like a real combination lock */
function Safe({ config, done }) {
  const numbers = Math.min(6, Math.max(1, Number(config.numbers) || 3))
  const tolerance = Math.max(0, Number(config.tolerance ?? 2))
  const speed = Math.max(5, Number(config.speed) || 30) // dial numbers per second while held
  const total = Math.max(5, Number(config.time) || 40)
  const maxMistakes = Math.max(0, Number(config.mistakes ?? 2))
  const [combo] = useState(() => Array.from({ length: numbers }, () => Math.floor(Math.random() * 100)))
  const [step, setStep] = useState(0)
  const [mistakes, setMistakes] = useState(0)
  const [value, setValue] = useState(0)
  const [flash, setFlash] = useState('')
  const dial = useRef(0)
  const held = useRef(0)
  const turned = useRef({ '1': 0, '-1': 0 }) // dial numbers turned each way since the last number
  const timeout = useCallback(() => done(false), [done])
  const [left] = useCountdown(total, timeout)
  const need = step % 2 === 0 ? 1 : -1 // right, left, right…
  const distance = target => { const d = Math.abs(((value - target) % 100 + 100) % 100); return Math.min(d, 100 - d) }
  const near = distance(combo[step])

  useEffect(() => {
    let frame, last = performance.now()
    const tick = now => {
      const dt = (now - last) / 1000; last = now
      if (held.current) {
        dial.current = ((dial.current + held.current * speed * dt) % 100 + 100) % 100
        turned.current[held.current] += speed * dt
        setValue(Math.round(dial.current) % 100)
      }
      frame = requestAnimationFrame(tick)
    }
    frame = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(frame)
  }, [speed])
  const nudge = direction => { dial.current = ((Math.round(dial.current) + direction) % 100 + 100) % 100; turned.current[direction] += 1; setValue(dial.current) }
  const attempt = useCallback(() => {
    const ok = distance(combo[step]) <= tolerance && turned.current[need] > turned.current[-need] // mostly turned the right way (small corrections are fine)
    setFlash(ok ? 'hit' : 'miss'); setTimeout(() => setFlash(''), 220)
    if (ok) { turned.current = { '1': 0, '-1': 0 }; if (step + 1 >= numbers) return done(true); return setStep(step + 1) }
    if (mistakes + 1 > maxMistakes) return done(false)
    setMistakes(mistakes + 1)
  }, [value, combo, step, tolerance, need, numbers, mistakes, maxMistakes, done]) // eslint-disable-line react-hooks/exhaustive-deps
  const attemptRef = useRef(attempt)
  attemptRef.current = attempt
  useEffect(() => {
    const dir = event => (['a', 'A', 'ArrowLeft'].includes(event.key) ? -1 : ['d', 'D', 'ArrowRight'].includes(event.key) ? 1 : 0)
    const down = event => {
      if (event.code === 'Space') { event.preventDefault(); if (!event.repeat) attemptRef.current(); return }
      const d = dir(event); if (!d) return
      event.preventDefault()
      if (event.shiftKey) nudge(d); else held.current = d
    }
    const up = event => { if (dir(event) === held.current) held.current = 0 }
    window.addEventListener('keydown', down); window.addEventListener('keyup', up)
    return () => { window.removeEventListener('keydown', down); window.removeEventListener('keyup', up); held.current = 0 }
  }, [])
  const heat = Math.max(0, 1 - near / 25)
  return (
    <div className="mg-game">
      <h3>Crack the safe</h3>
      <p>Hold <kbd>A</kbd>/<kbd>D</kbd> to turn (<kbd>Shift</kbd> for one notch). When the light turns green press <kbd>Space</kbd>. Turn {need > 0 ? 'right' : 'left'} for this number.</p>
      <div className="mg-pins">{Array.from({ length: numbers }, (_, i) => <span key={i} className={i < step ? 'set' : i === step ? 'current' : ''} />)}</div>
      <div className={`mg-safe ${flash}`}>
        <div className="mg-dial" style={{ transform: `rotate(${-value * 3.6}deg)` }}>
          {Array.from({ length: 20 }, (_, i) => <i key={i} style={{ transform: `rotate(${i * 18}deg)` }}><b>{i * 5}</b></i>)}
        </div>
        <div className="mg-dial-pointer" />
        <div className="mg-dial-value">{String(value).padStart(2, '0')}</div>
        <div className={`mg-dial-light${near <= tolerance ? ' ok' : ''}`} style={{ '--heat': heat }} />
      </div>
      <div className="mg-seq-buttons mg-safe-buttons">
        <button onMouseDown={() => { held.current = -1 }} onMouseUp={() => { held.current = 0 }} onMouseLeave={() => { held.current = 0 }}>◀ Left</button>
        <button onClick={attempt}>Set</button>
        <button onMouseDown={() => { held.current = 1 }} onMouseUp={() => { held.current = 0 }} onMouseLeave={() => { held.current = 0 }}>Right ▶</button>
      </div>
      <Lives used={mistakes} max={maxMistakes} />
      <Timer left={left} total={total} />
    </div>
  )
}

/* reaction: hit the green targets before they fade; red ones are traps */
function Reaction({ config, done }) {
  const grid = Math.min(5, Math.max(3, Number(config.grid) || 4))
  const targets = Math.max(3, Number(config.targets) || 12)
  const life = Math.max(0.25, Number(config.life) || 0.9)
  const traps = Math.min(0.6, Math.max(0, Number(config.traps ?? 0.25)))
  const maxMisses = Math.max(0, Number(config.misses ?? 2))
  const [hits, setHits] = useState(0)
  const [misses, setMisses] = useState(0)
  const [active, setActive] = useState(null) // { cell, trap, id }
  const [flash, setFlash] = useState(null)
  const state = useRef({ hits: 0, misses: 0 })
  const miss = useCallback(() => {
    state.current.misses += 1; setMisses(state.current.misses)
    if (state.current.misses > maxMisses) done(false)
  }, [maxMisses, done])
  const current = useRef(null)
  const show = target => { current.current = target; setActive(target) }
  useEffect(() => {
    let timer, alive = true
    const spawn = () => {
      if (!alive) return
      const trap = Math.random() < traps
      let cell = Math.floor(Math.random() * grid * grid)
      if (cell === current.last) cell = (cell + 1 + Math.floor(Math.random() * (grid * grid - 1))) % (grid * grid)
      current.last = cell
      const target = { cell, trap, id: Math.random() }
      show(target)
      timer = setTimeout(() => {
        if (!alive) return
        if (current.current && current.current.id === target.id) { show(null); if (!target.trap) miss() }
        timer = setTimeout(spawn, 120 + Math.random() * 260)
      }, life * 1000 * (trap ? 0.85 : 1))
    }
    timer = setTimeout(spawn, 500)
    return () => { alive = false; clearTimeout(timer) }
  }, [grid, life, traps, miss])
  const click = cell => {
    const target = current.current
    if (!target || target.cell !== cell) return
    show(null); setFlash({ cell, ok: !target.trap }); setTimeout(() => setFlash(null), 160)
    if (target.trap) return miss()
    state.current.hits += 1; setHits(state.current.hits)
    if (state.current.hits >= targets) done(true)
  }
  return (
    <div className="mg-game">
      <h3>Short the circuit</h3>
      <p>Click green nodes before they fade. Don't touch red ones. {hits} / {targets}</p>
      <div className="mg-grid mg-reaction" style={{ gridTemplateColumns: `repeat(${grid}, 1fr)` }}>
        {Array.from({ length: grid * grid }, (_, i) => (
          <button key={i} onMouseDown={() => click(i)} aria-label={`node ${i + 1}`}
            className={active && active.cell === i ? (active.trap ? 'trap' : 'target') : flash && flash.cell === i ? (flash.ok ? 'found' : 'wrong') : ''}
            style={active && active.cell === i ? { animationDuration: `${life}s` } : undefined} />
        ))}
      </div>
      <Lives used={misses} max={maxMisses} />
    </div>
  )
}

/* order: click the numbers from lowest to highest; they can jump around after each click */
function NumberOrder({ config, done }) {
  const count = Math.min(20, Math.max(4, Number(config.count) || 10))
  const total = Math.max(3, Number(config.time) || 15)
  const shuffle = config.shuffle === true
  const maxMistakes = Math.max(0, Number(config.mistakes ?? 0))
  const place = () => {
    const spots = []
    for (let n = 0; n < count; n++) {
      let spot, tries = 0
      do { spot = { x: 6 + Math.random() * 88, y: 11 + Math.random() * 78 }; tries++ } while (tries < 40 && spots.some(s => Math.hypot(s.x - spot.x, (s.y - spot.y) * 0.6) < 11))
      spots.push(spot)
    }
    return spots
  }
  const [spots, setSpots] = useState(place)
  const [next, setNext] = useState(1)
  const [mistakes, setMistakes] = useState(0)
  const [wrong, setWrong] = useState(null)
  const timeout = useCallback(() => done(false), [done])
  const [left] = useCountdown(total, timeout)
  const click = n => {
    if (n < next) return
    if (n !== next) {
      setWrong(n); setTimeout(() => setWrong(null), 220)
      if (mistakes + 1 > maxMistakes) return done(false)
      return setMistakes(mistakes + 1)
    }
    if (n >= count) return done(true)
    setNext(n + 1)
    if (shuffle) setSpots(place())
  }
  return (
    <div className="mg-game">
      <h3>Reset the breakers</h3>
      <p>Click 1 to {count} in order{shuffle ? '. They move after every click' : ''}.</p>
      <div className="mg-order">
        {spots.map((spot, i) => i + 1 >= next && (
          <button key={i} className={wrong === i + 1 ? 'wrong' : ''} style={{ left: `${spot.x}%`, top: `${spot.y}%` }} onMouseDown={() => click(i + 1)}>{i + 1}</button>
        ))}
      </div>
      <Lives used={mistakes} max={maxMistakes} />
      <Timer left={left} total={total} />
    </div>
  )
}

/* circle: a needle sweeps the ring; press Space as it crosses each gold arc. Every hit reverses it and speeds it up */
function Circle({ config, done }) {
  const zones = Math.min(8, Math.max(1, Number(config.zones) || 4))
  const width = Math.min(90, Math.max(8, Number(config.zone) || 28)) // degrees
  const speed = Math.max(0.1, Number(config.speed) || 0.6) // turns per second
  const total = Math.max(4, Number(config.time) || 20)
  const maxMistakes = Math.max(0, Number(config.mistakes ?? 1))
  const reverse = config.reverse !== false
  const placeArcs = () => {
    const arcs = []
    for (let tries = 0; arcs.length < zones && tries < 500; tries++) {
      const start = Math.random() * 360
      if (arcs.every(a => Math.min(Math.abs(a - start), 360 - Math.abs(a - start)) > width + 12)) arcs.push(start)
    }
    return arcs
  }
  const [arcs, setArcs] = useState(placeArcs)
  const [total0] = useState(() => arcs.length)
  const [mistakes, setMistakes] = useState(0)
  const [flash, setFlash] = useState('')
  const angle = useRef(0)
  const dir = useRef(1)
  const boost = useRef(1)
  const needle = useRef(null)
  const timeout = useCallback(() => done(false), [done])
  const [left] = useCountdown(total, timeout)
  useEffect(() => {
    let frame, last = performance.now()
    const tick = now => {
      angle.current = ((angle.current + dir.current * speed * boost.current * 360 * (now - last) / 1000) % 360 + 360) % 360; last = now
      if (needle.current) needle.current.style.transform = `rotate(${angle.current}deg)`
      frame = requestAnimationFrame(tick)
    }
    frame = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(frame)
  }, [speed])
  const attempt = useCallback(() => {
    const a = angle.current
    const hit = arcs.findIndex(start => ((a - start) % 360 + 360) % 360 <= width)
    setFlash(hit >= 0 ? 'hit' : 'miss'); setTimeout(() => setFlash(''), 180)
    if (hit < 0) { if (mistakes + 1 > maxMistakes) return done(false); return setMistakes(mistakes + 1) }
    const rest = arcs.filter((_, i) => i !== hit)
    if (!rest.length) return done(true)
    setArcs(rest)
    if (reverse) dir.current = -dir.current
    boost.current *= 1.12
  }, [arcs, width, mistakes, maxMistakes, reverse, done])
  useEffect(() => {
    const onKey = event => { if (event.code === 'Space' || event.key === 'e' || event.key === 'E') { event.preventDefault(); if (!event.repeat) attempt() } }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [attempt])
  const arcPath = start => {
    const r = 42, rad = d => (d - 90) * Math.PI / 180
    const [x1, y1, x2, y2] = [50 + r * Math.cos(rad(start)), 50 + r * Math.sin(rad(start)), 50 + r * Math.cos(rad(start + width)), 50 + r * Math.sin(rad(start + width))]
    return `M ${x1} ${y1} A ${r} ${r} 0 ${width > 180 ? 1 : 0} 1 ${x2} ${y2}`
  }
  return (
    <div className="mg-game">
      <h3>Time the tumblers</h3>
      <p>Press <kbd>Space</kbd> or click when the needle is in a gold arc. {total0 - arcs.length} / {total0}</p>
      <div className={`mg-circle ${flash}`} onMouseDown={attempt}>
        <svg viewBox="0 0 100 100">
          <circle cx="50" cy="50" r="42" fill="none" stroke="#ffffff14" strokeWidth="7" />
          {arcs.map(start => <path key={start} d={arcPath(start)} fill="none" stroke="#ffd23c" strokeWidth="7" />)}
        </svg>
        <div className="mg-needle" ref={needle}><i /></div>
      </div>
      <Lives used={mistakes} max={maxMistakes} />
      <Timer left={left} total={total} />
    </div>
  )
}

const GAMES = { crafting: CraftingMinigame, lockpick: ShearLineLockpick, drill: ShearLineLockpick, grinder: ShearLineLockpick, skimmer: ShearLineLockpick, keypad: Keypad, sequence: Sequence,
  simon: Simon, grid: MemoryGrid, safe: Safe, reaction: Reaction, order: NumberOrder, circle: Circle }

export default function Minigame({ config, onResult }) {
  const [result, setResult] = useState(null)
  const sent = useRef(false)
  const resultTimer = useRef(null)
  useEffect(() => () => clearTimeout(resultTimer.current), [])
  const done = useCallback((success, details) => {
    if (sent.current) return
    sent.current = true
    setResult(success)
    resultTimer.current = setTimeout(() => onResult(success, details), 650)
  }, [onResult])
  useEffect(() => {
    const onKey = event => { if (event.key === 'Escape') { event.preventDefault(); done(false) } }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  }, [done])
  const Game = GAMES[config?.game] || ShearLineLockpick
  return (
    <div className="mg-overlay" role="dialog">
      <div className={`mg-card${config?.game==='crafting'?' mg-crafting-card':''}${['lockpick','drill','grinder','skimmer'].includes(config?.game) ? ' mg-shear-card' : ''}${result === true ? ' won' : result === false ? ' lost' : ''}`}>
        {result == null ? <Game config={config || {}} done={done} /> : <div className="mg-result">{result ? 'Success' : 'Failed'}</div>}
        {result == null && <button className="mg-quit" onClick={() => done(false)}>Give up (Esc)</button>}
      </div>
    </div>
  )
}

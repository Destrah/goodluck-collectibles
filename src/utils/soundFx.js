// Synthesised (Web Audio) sound effects — no audio files, so they work the same in standalone and FiveM NUI.
let audioContext

function ctx() {
  if (!audioContext) audioContext = new (window.AudioContext || window.webkitAudioContext)()
  if (audioContext.state === 'suspended') audioContext.resume()
  return audioContext
}

const rand = (a, b) => a + Math.random() * (b - a)

function tone({ frequency = 440, duration = 0.12, type = 'sine', gain = 0.08, endFrequency = null, delay = 0, vibrato = 0, vibratoRate = 6 }) {
  const audio = ctx()
  // a partial above the Nyquist limit is inaudible anyway, and the browser logs a warning for every one
  // (a coin clink's top partial reaches ~30 kHz)
  const nyquist = audio.sampleRate / 2
  if (frequency >= nyquist) return
  if (endFrequency) endFrequency = Math.min(endFrequency, nyquist - 1)
  const start = audio.currentTime + delay
  const osc = audio.createOscillator()
  const amp = audio.createGain()
  osc.type = type
  osc.frequency.setValueAtTime(frequency, start)
  if (endFrequency) osc.frequency.exponentialRampToValueAtTime(Math.max(20, endFrequency), start + duration)
  if (vibrato) {
    const lfo = audio.createOscillator(), depth = audio.createGain()
    lfo.frequency.value = vibratoRate; depth.gain.value = vibrato
    lfo.connect(depth).connect(osc.frequency); lfo.start(start); lfo.stop(start + duration + 0.02)
  }
  amp.gain.setValueAtTime(0.0001, start)
  amp.gain.exponentialRampToValueAtTime(gain, start + Math.min(0.025, duration / 3))
  amp.gain.exponentialRampToValueAtTime(0.0001, start + duration)
  osc.connect(amp).connect(audio.destination)
  osc.start(start)
  osc.stop(start + duration + 0.02)
}

function noise({ duration = 0.18, gain = 0.06, highpass = null, lowpass = null, bandpass = null, q = 1, sweepTo = null, attack = 0, delay = 0 }) {
  const audio = ctx()
  const start = audio.currentTime + delay
  const buffer = audio.createBuffer(1, Math.max(1, Math.floor(audio.sampleRate * duration)), audio.sampleRate)
  const data = buffer.getChannelData(0)
  for (let i = 0; i < data.length; i += 1) data[i] = Math.random() * 2 - 1
  const source = audio.createBufferSource()
  source.buffer = buffer
  let node = source
  const chain = (type, frequency, Q = 0.7) => { const f = audio.createBiquadFilter(); f.type = type; f.frequency.setValueAtTime(frequency, start); f.Q.value = Q; node.connect(f); node = f; return f }
  if (lowpass) chain('lowpass', lowpass)
  if (highpass) chain('highpass', highpass)
  if (bandpass) { const f = chain('bandpass', bandpass, q); if (sweepTo) f.frequency.exponentialRampToValueAtTime(sweepTo, start + duration) }
  const amp = audio.createGain()
  if (attack) { amp.gain.setValueAtTime(0.0001, start); amp.gain.exponentialRampToValueAtTime(gain, start + attack) } else amp.gain.setValueAtTime(gain, start)
  amp.gain.exponentialRampToValueAtTime(0.0001, start + duration)
  node.connect(amp).connect(audio.destination)
  source.start(start)
  source.stop(start + duration + 0.02)
}

/* ------------------------------------------------------------------ material building blocks */

// many tiny bright clicks at irregular intervals: cellophane, foil, tape, paper
function crackle({ duration = 0.4, density = 70, low = 2200, high = 8000, gain = 0.05, fade = true, delay = 0 }) {
  const count = Math.max(1, Math.round(duration * density))
  for (let i = 0; i < count; i++) {
    const at = Math.pow(Math.random(), fade ? 1.5 : 1) * duration
    const level = gain * (fade ? 1 - (at / duration) * 0.6 : 1) * rand(0.35, 1)
    noise({ duration: rand(0.004, 0.016), gain: level, bandpass: rand(low, high), q: rand(1.5, 5), delay: delay + at })
  }
}

// plastic wrap tearing: a descending "zzrrip" body plus dense crackle
function plasticRip({ duration = 0.32, gain = 0.07, delay = 0 } = {}) {
  noise({ duration, gain: gain * 0.7, bandpass: 5200, sweepTo: 1600, q: 1.2, attack: 0.012, delay })
  noise({ duration: duration * 0.8, gain: gain * 0.35, highpass: 3500, lowpass: 9000, delay: delay + 0.02 })
  crackle({ duration, density: 140, low: 1800, high: 9000, gain: gain * 0.75, delay })
}

// wood under stress: stick-slip pulses through the resonances of a plank / hinge
function creak({ duration = 0.7, pitch = 110, gain = 0.05, bright = 1, delay = 0 } = {}) {
  const audio = ctx()
  const start = audio.currentTime + delay
  const osc = audio.createOscillator()
  osc.type = 'sawtooth'
  const steps = Math.max(4, Math.round(duration * 18))
  for (let i = 0; i <= steps; i++) osc.frequency.setValueAtTime(pitch * rand(0.75, 1.35), start + (i / steps) * duration)
  const pulse = audio.createOscillator(), pulseDepth = audio.createGain(), amp = audio.createGain()
  pulse.type = 'square'; pulse.frequency.setValueAtTime(rand(22, 34), start); pulse.frequency.linearRampToValueAtTime(rand(12, 20), start + duration)
  pulseDepth.gain.value = gain * 0.5
  amp.gain.setValueAtTime(0.0001, start)
  amp.gain.linearRampToValueAtTime(gain * 0.5, start + duration * 0.15)
  amp.gain.linearRampToValueAtTime(gain * 0.6, start + duration * 0.7)
  amp.gain.exponentialRampToValueAtTime(0.0001, start + duration)
  pulse.connect(pulseDepth).connect(amp.gain)
  const body = audio.createBiquadFilter(); body.type = 'bandpass'; body.frequency.value = 700 * bright; body.Q.value = 3
  const grain = audio.createBiquadFilter(); grain.type = 'peaking'; grain.frequency.value = 2100 * bright; grain.Q.value = 5; grain.gain.value = 9
  osc.connect(body).connect(grain).connect(amp).connect(audio.destination)
  osc.start(start); pulse.start(start)
  osc.stop(start + duration + 0.05); pulse.stop(start + duration + 0.05)
}

// a solid knock: wood or cardboard on a surface
function thud({ pitch = 80, gain = 0.09, body = 500, delay = 0 } = {}) {
  tone({ frequency: pitch * 1.6, endFrequency: pitch * 0.7, duration: 0.18, type: 'sine', gain, delay })
  noise({ duration: 0.09, gain: gain * 0.7, lowpass: body, delay })
}

function knock({ pitch = 220, gain = 0.06, delay = 0 } = {}) {
  tone({ frequency: pitch, endFrequency: pitch * 0.82, duration: 0.07, type: 'triangle', gain, delay })
  noise({ duration: 0.035, gain: gain * 0.6, bandpass: pitch * 4, q: 2, delay })
}

// a struck metal coin: inharmonic partials with a fast decay
function clink({ pitch = 2600, gain = 0.035, delay = 0 } = {}) {
  ;[1, 2.76, 5.4, 8.93].forEach((ratio, i) => tone({ frequency: pitch * ratio * rand(0.98, 1.02), duration: 0.28 - i * 0.05, type: 'sine', gain: gain / (i + 1), delay }))
  noise({ duration: 0.012, gain: gain * 0.8, highpass: 4000, delay })
}

function jingle({ count = 4, spread = 0.18, gain = 0.03, delay = 0 } = {}) {
  for (let i = 0; i < count; i++) clink({ pitch: rand(2100, 3400), gain: gain * rand(0.5, 1), delay: delay + Math.random() * spread })
}

// fabric moving: velvet is soft and dark, satin is a bright swish, leather is a dry rub
function rustle({ fabric = 'velvet', duration = 0.35, gain = 0.045, delay = 0 } = {}) {
  if (fabric === 'satin') noise({ duration, gain, bandpass: 3800, sweepTo: 2200, q: 0.9, attack: duration * 0.4, delay })
  else if (fabric === 'leather') { noise({ duration, gain: gain * 0.8, bandpass: 1300, q: 1.4, attack: duration * 0.3, delay }); creak({ duration: duration * 0.8, pitch: 260, gain: gain * 0.35, bright: 1.6, delay: delay + 0.04 }) }
  else noise({ duration, gain, lowpass: 1100, highpass: 120, attack: duration * 0.45, delay })
}

// cord pulled through eyelets
function drawstring({ gain = 0.035, delay = 0 } = {}) {
  noise({ duration: 0.22, gain, bandpass: 1800, sweepTo: 3600, q: 3, attack: 0.05, delay })
  noise({ duration: 0.18, gain: gain * 0.8, bandpass: 3200, sweepTo: 1500, q: 3, attack: 0.04, delay: delay + 0.2 })
}

function cardboardRip(delay = 0) {
  noise({ duration: 0.12, gain: 0.08, lowpass: 2400, highpass: 250, delay })
  noise({ duration: 0.15, gain: 0.05, lowpass: 1600, highpass: 180, delay: delay + 0.06 })
  tone({ frequency: 110, endFrequency: 72, duration: 0.2, type: 'triangle', gain: 0.03, delay: delay + 0.02 })
}

// packing tape peeling off cardboard: sticky crackle with a rising tone
function tapePeel({ duration = 0.45, gain = 0.05, delay = 0 } = {}) {
  crackle({ duration, density: 110, low: 900, high: 4200, gain, fade: false, delay })
  noise({ duration, gain: gain * 0.4, bandpass: 900, sweepTo: 2600, q: 2, delay })
}

function cellophaneCrinkle(delay = 0) {
  crackle({ duration: 0.2, density: 90, low: 2400, high: 9000, gain: 0.05, delay })
}

function sparkle({ gain = 0.03, delay = 0 } = {}) {
  ;[1568, 2093, 2637, 3136].forEach((frequency, i) => tone({ frequency, duration: 0.35, type: 'sine', gain: gain * (1 - i * 0.15), delay: delay + i * 0.055 }))
}

/* ------------------------------------------------------------------ container sound design */

const FABRIC = { velvet: 'velvet', satin: 'satin', leather: 'leather' }

// Sound for each moment of a 3D container opening, chosen by what is being opened.
// kind: bag | box | case; style: the container design; animation: its opening animation
function containerSound({ kind, style, animation, event, itemKind, innerKind }) {
  const fabric = FABRIC[style] || 'velvet'
  const wooden = style === 'chest' || style === 'crate'
  if (event === 'charge') {
    // shaking it: what rattles depends on the container and what is inside
    for (let i = 0; i < 5; i++) {
      const at = i * 0.16
      if (kind === 'bag') { rustle({ fabric, duration: 0.14, gain: 0.03, delay: at }); jingle({ count: 2, spread: 0.08, gain: 0.018, delay: at + 0.03 }) }
      else if (wooden) { knock({ pitch: rand(150, 230), gain: 0.05, delay: at }); if (innerKind === 'bag') jingle({ count: 2, gain: 0.012, delay: at + 0.02 }) }
      else { knock({ pitch: rand(260, 360), gain: 0.035, delay: at }); noise({ duration: 0.05, gain: 0.02, lowpass: 900, delay: at + 0.02 }) }
    }
    return
  }
  if (event === 'open') {
    if (kind === 'bag') {
      drawstring({})
      rustle({ fabric, duration: 0.5, gain: 0.05, delay: 0.15 })
      if (animation === 'pour') { rustle({ fabric, duration: 0.6, gain: 0.04, delay: 0.55 }); jingle({ count: 6, spread: 0.5, gain: 0.02, delay: 0.7 }) }
      else if (animation === 'pop') { noise({ duration: 0.12, gain: 0.07, lowpass: 900, delay: 0 }); thud({ pitch: 70, gain: 0.05 }) }
      else sparkle({ gain: 0.018, delay: 0.5 })
      return
    }
    if (style === 'chest') {
      tone({ frequency: 2400, duration: 0.05, type: 'square', gain: 0.02 }) // latch
      knock({ pitch: 900, gain: 0.03 })
      creak({ duration: 0.9, pitch: 95, gain: 0.06, delay: 0.08 })
      tone({ frequency: 820, endFrequency: 640, duration: 0.7, type: 'sawtooth', gain: 0.006, vibrato: 30, vibratoRate: 11, delay: 0.15 }) // hinge squeal
      thud({ pitch: 60, gain: 0.08, body: 400, delay: 1.0 })
      sparkle({ gain: 0.02, delay: 0.7 })
      return
    }
    if (style === 'crate') {
      // prying the lid boards: creak + nail screech per board, then the boards clatter down
      for (let b = 0; b < 4; b++) {
        const at = b * 0.2
        creak({ duration: 0.3, pitch: rand(120, 170), gain: 0.045, bright: 1.3, delay: at })
        tone({ frequency: rand(1900, 2600), endFrequency: rand(1400, 1800), duration: 0.16, type: 'sawtooth', gain: 0.006, vibrato: 60, vibratoRate: 23, delay: at + 0.08 })
        knock({ pitch: rand(160, 240), gain: 0.06, delay: at + 0.55 })
        knock({ pitch: rand(180, 260), gain: 0.035, delay: at + 0.66 })
      }
      return
    }
    if (style === 'gift') {
      noise({ duration: 0.4, gain: 0.04, bandpass: 3600, sweepTo: 1800, q: 1, attack: 0.15 }) // ribbon slipping off
      crackle({ duration: 0.35, density: 45, low: 1200, high: 5000, gain: 0.03, delay: 0.25 }) // wrapping paper
      noise({ duration: 0.08, gain: 0.05, lowpass: 1200, delay: 0.5 }) // lid pop
      sparkle({ gain: 0.02, delay: 0.55 })
      return
    }
    // cardboard boxes, display cases, window boxes
    if (style === 'display' || style === 'window') tapePeel({ duration: 0.4 })
    else crackle({ duration: 0.25, density: 60, low: 1500, high: 6000, gain: 0.03 })
    noise({ duration: 0.25, gain: 0.045, lowpass: 900, highpass: 120, attack: 0.08, delay: 0.3 }) // flap swinging
    knock({ pitch: 190, gain: 0.04, delay: 0.55 })
    if (animation === 'unfold') for (let w = 0; w < 4; w++) thud({ pitch: wooden ? 70 : 95, gain: 0.05, body: wooden ? 500 : 800, delay: 0.55 + w * 0.17 })
    if (animation === 'burst') { noise({ duration: 0.18, gain: 0.08, lowpass: 2000 }); thud({ pitch: 65, gain: 0.07 }) }
    return
  }
  if (event === 'emerge') {
    if (kind === 'bag' && animation === 'float') sparkle({ gain: 0.015 })
    if (kind === 'case' && animation === 'unfold') for (let w = 0; w < 4; w++) thud({ pitch: wooden ? 65 : 95, gain: 0.045, body: wooden ? 450 : 800, delay: w * 0.15 })
    return
  }
  if (event === 'land') {
    // each collectible lands with its own material
    if (itemKind === 'coin') { clink({ pitch: rand(2300, 3200), gain: 0.03 }); clink({ pitch: rand(2300, 3200), gain: 0.012, delay: 0.09 }) }
    else if (itemKind === 'plush') { thud({ pitch: 110, gain: 0.04, body: 350 }); if (Math.random() < 0.4) tone({ frequency: 900, endFrequency: 1300, duration: 0.12, type: 'sine', gain: 0.012, delay: 0.05 }) }
    else if (itemKind === 'bag') { noise({ duration: 0.09, gain: 0.04, lowpass: 900 }); jingle({ count: 2, gain: 0.012, delay: 0.02 }) }
    else knock({ pitch: rand(200, 260), gain: 0.035 })
    return
  }
  if (event === 'reveal') {
    if (itemKind === 'coin') { clink({ pitch: 3000, gain: 0.03 }); sparkle({ gain: 0.022, delay: 0.05 }) }
    else { noise({ duration: 0.12, gain: 0.03, lowpass: 900 }); sparkle({ gain: 0.022, delay: 0.04 }) }
  }
}

export const soundFx = {
  // booster pack: foil/cellophane wrapper being handled and ripped open
  packOpen() {
    plasticRip({ duration: 0.34, gain: 0.075 })
    plasticRip({ duration: 0.22, gain: 0.05, delay: 0.2 })
  },
  packHandle() {
    crackle({ duration: 0.28, density: 60, low: 2000, high: 8000, gain: 0.035 })
  },
  packFlip() {
    crackle({ duration: 0.12, density: 70, low: 2400, high: 8000, gain: 0.025 })
    noise({ duration: 0.09, gain: 0.015, highpass: 1600, lowpass: 5200 })
  },
  packCrinkle() {
    crackle({ duration: 0.3, density: 120, low: 2000, high: 9000, gain: 0.045 })
  },
  packTear(stage = 'start') {
    plasticRip({ duration: stage === 'mid' ? 0.3 : 0.18, gain: stage === 'mid' ? 0.08 : 0.06 })
  },
  packPeel() {
    plasticRip({ duration: 0.4, gain: 0.06 })
    crackle({ duration: 0.3, density: 50, low: 2500, high: 8000, gain: 0.025, delay: 0.35 })
  },
  cardsSlide() {
    noise({ duration: 0.11, gain: 0.027, lowpass: 2600, highpass: 650 })
    tone({ frequency: 225, endFrequency: 180, duration: 0.1, type: 'triangle', gain: 0.014 })
  },
  cardsFan() {
    for (let i = 0; i < 5; i += 1) {
      noise({ duration: 0.04, gain: 0.016, lowpass: 2800, highpass: 1100, delay: i * 0.035 })
      tone({ frequency: 240 + i * 20, endFrequency: 205 + i * 18, duration: 0.055, type: 'triangle', gain: 0.012, delay: i * 0.035 })
    }
  },
  // booster box: shrink-wrap torn off, then the cardboard lid
  boxOpen() {
    plasticRip({ duration: 0.3, gain: 0.06 })
    cardboardRip(0.3)
    knock({ pitch: 170, gain: 0.04, delay: 0.5 })
  },
  boxReveal() {
    tone({ frequency: 180, endFrequency: 120, duration: 0.18, type: 'triangle', gain: 0.03 })
    noise({ duration: 0.08, gain: 0.022, lowpass: 1800, highpass: 180, delay: 0.04 })
  },
  deal() {
    noise({ duration: 0.055, gain: 0.035, lowpass: 2200, highpass: 900 })
    tone({ frequency: 240, endFrequency: 180, duration: 0.07, type: 'triangle', gain: 0.022 })
  },
  flip() {
    tone({ frequency: 210, endFrequency: 510, duration: 0.11, type: 'sine', gain: 0.04 })
    noise({ duration: 0.06, gain: 0.018, highpass: 2400, lowpass: 5800 })
  },
  zoom() {
    tone({ frequency: 320, endFrequency: 420, duration: 0.09, type: 'sine', gain: 0.02 })
  },
  rare(tier) {
    const notes = tier === 'legendary' ? [523, 659, 784, 1047] : tier === 'ultra_rare' ? [440, 554, 659] : [392, 523]
    notes.forEach((frequency, index) => tone({ frequency, duration: 0.18, type: 'sine', gain: 0.035, delay: index * 0.08 }))
  },
  // coin bags, plushie boxes and their outer cases (3D openings)
  container(details) {
    try { containerSound(details) } catch (error) { console.warn('[sound] container effect failed', error) }
  },
}

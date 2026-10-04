let audioContext

function ctx() {
  if (!audioContext) audioContext = new (window.AudioContext || window.webkitAudioContext)()
  if (audioContext.state === 'suspended') audioContext.resume()
  return audioContext
}

function tone({ frequency = 440, duration = 0.12, type = 'sine', gain = 0.08, endFrequency = null, delay = 0 }) {
  const audio = ctx()
  const start = audio.currentTime + delay
  const osc = audio.createOscillator()
  const amp = audio.createGain()
  osc.type = type
  osc.frequency.setValueAtTime(frequency, start)
  if (endFrequency) osc.frequency.exponentialRampToValueAtTime(Math.max(20, endFrequency), start + duration)
  amp.gain.setValueAtTime(0.0001, start)
  amp.gain.exponentialRampToValueAtTime(gain, start + Math.min(0.025, duration / 3))
  amp.gain.exponentialRampToValueAtTime(0.0001, start + duration)
  osc.connect(amp).connect(audio.destination)
  osc.start(start)
  osc.stop(start + duration + 0.02)
}

function noise({ duration = 0.18, gain = 0.06, highpass = null, lowpass = null, delay = 0 }) {
  const audio = ctx()
  const start = audio.currentTime + delay
  const buffer = audio.createBuffer(1, Math.max(1, Math.floor(audio.sampleRate * duration)), audio.sampleRate)
  const data = buffer.getChannelData(0)
  for (let i = 0; i < data.length; i += 1) data[i] = Math.random() * 2 - 1
  const source = audio.createBufferSource()
  const firstFilter = audio.createBiquadFilter()
  const secondFilter = audio.createBiquadFilter()
  const amp = audio.createGain()
  source.buffer = buffer

  let destination = source
  if (lowpass) {
    firstFilter.type = 'lowpass'
    firstFilter.frequency.value = lowpass
    destination.connect(firstFilter)
    destination = firstFilter
  }
  if (highpass) {
    secondFilter.type = 'highpass'
    secondFilter.frequency.value = highpass
    destination.connect(secondFilter)
    destination = secondFilter
  }

  amp.gain.setValueAtTime(gain, start)
  amp.gain.exponentialRampToValueAtTime(0.0001, start + duration)
  destination.connect(amp).connect(audio.destination)
  source.start(start)
  source.stop(start + duration + 0.02)
}

function cardboardRip(delay = 0) {
  noise({ duration: 0.12, gain: 0.08, lowpass: 2400, highpass: 250, delay })
  noise({ duration: 0.15, gain: 0.05, lowpass: 1600, highpass: 180, delay: delay + 0.06 })
  tone({ frequency: 110, endFrequency: 72, duration: 0.2, type: 'triangle', gain: 0.03, delay: delay + 0.02 })
}

function cellophaneCrinkle(delay = 0) {
  noise({ duration: 0.11, gain: 0.055, lowpass: 4200, highpass: 1500, delay })
  noise({ duration: 0.1, gain: 0.04, lowpass: 5200, highpass: 2200, delay: delay + 0.05 })
  noise({ duration: 0.08, gain: 0.03, lowpass: 6200, highpass: 2600, delay: delay + 0.11 })
}

export const soundFx = {
  packOpen() {
    cardboardRip(0)
    cardboardRip(0.12)
    tone({ frequency: 185, endFrequency: 92, duration: 0.22, type: 'triangle', gain: 0.045, delay: 0.06 })
  },
  packHandle() {
    cellophaneCrinkle(0)
  },
  packFlip() {
    noise({ duration: 0.075, gain: 0.018, highpass: 1600, lowpass: 5200 })
    tone({ frequency: 170, endFrequency: 245, duration: 0.13, type: 'triangle', gain: 0.018 })
  },
  packCrinkle() {
    cellophaneCrinkle(0)
    noise({ duration: 0.07, gain: 0.026, highpass: 2400, lowpass: 6800, delay: 0.08 })
  },
  packTear(stage = 'start') {
    const gain = stage === 'mid' ? 0.072 : 0.058
    noise({ duration: stage === 'mid' ? 0.18 : 0.12, gain, lowpass: 3900, highpass: 550 })
    noise({ duration: 0.08, gain: gain * 0.65, lowpass: 6200, highpass: 2100, delay: 0.035 })
    tone({ frequency: stage === 'mid' ? 125 : 150, endFrequency: 82, duration: 0.18, type: 'triangle', gain: 0.018, delay: 0.015 })
  },
  packPeel() {
    cellophaneCrinkle(0)
    noise({ duration: 0.16, gain: 0.04, lowpass: 3200, highpass: 500, delay: 0.035 })
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
  boxOpen() {
    cellophaneCrinkle(0)
    cellophaneCrinkle(0.15)
    tone({ frequency: 130, endFrequency: 78, duration: 0.3, type: 'square', gain: 0.026, delay: 0.08 })
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
}

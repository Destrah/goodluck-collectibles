import React, { useEffect, useRef } from 'react'

const clamp = (n, min, max) => Math.min(Math.max(n, min), max)
const rand = (min, max) => min + Math.random() * (max - min)

// ---- perf helpers: shared image decode, shared analysis cache, one heavy job per idle slot ----
const imageCache = new Map()
function loadImage(url) {
  let p = imageCache.get(url)
  if (!p) {
    p = new Promise((resolve, reject) => {
      const i = new Image()
      i.crossOrigin = 'anonymous'
      i.onload = () => resolve(i)
      i.onerror = reject
      i.src = url
    })
    imageCache.set(url, p)
  }
  return p
}
const fxCache = new Map()
const FX_CACHE_MAX = 24
const fxQueue = []
let fxPumping = false
function pumpFxQueue() {
  if (fxPumping) return
  fxPumping = true
  const run = () => {
    const job = fxQueue.shift()
    if (job) { try { job() } catch (e) { console.warn(e) } }
    if (fxQueue.length) schedule(run)
    else fxPumping = false
  }
  const schedule = fn => (window.requestIdleCallback ? window.requestIdleCallback(fn, { timeout: 120 }) : setTimeout(fn, 16))
  schedule(run)
}
function scheduleFxJob(job) { fxQueue.push(job); pumpFxQueue() }

function coverRect(srcW, srcH, dstW, dstH, focusX = 0.5, focusY = 0.5) {
  const scale = Math.max(dstW / srcW, dstH / srcH)
  const w = srcW * scale
  const h = srcH * scale
  const fx = clamp(Number(focusX), 0, 1)
  const fy = clamp(Number(focusY), 0, 1)
  return { x: -(w - dstW) * fx, y: -(h - dstH) * fy, w, h }
}

function maskValue(data, index, mode) {
  const r = data[index]
  const g = data[index + 1]
  const b = data[index + 2]
  const a = data[index + 3]
  if (mode === 'alpha') return a / 255
  const lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
  if (mode === 'luminance-invert') return (1 - lum) * (a / 255)
  return lum * (a / 255)
}

function deriveMask(imageData, width, height, mode) {
  const src = imageData.data
  const inside = new Uint8Array(width * height)
  const threshold = mode === 'alpha' ? 0.14 : 0.48
  const samples = []

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const p = y * width + x
      const value = maskValue(src, p * 4, mode)
      inside[p] = value >= threshold ? 1 : 0
      if (inside[p] && x % 3 === 0 && y % 3 === 0) samples.push({ x, y })
    }
  }

  const edges = []
  for (let y = 2; y < height - 2; y += 2) {
    for (let x = 2; x < width - 2; x += 2) {
      const p = y * width + x
      if (!inside[p]) continue

      const left = inside[p - 2]
      const right = inside[p + 2]
      const up = inside[p - width * 2]
      const down = inside[p + width * 2]
      if (left && right && up && down) continue

      let nx = (left ? 1 : 0) - (right ? 1 : 0)
      let ny = (up ? 1 : 0) - (down ? 1 : 0)
      const len = Math.hypot(nx, ny) || 1
      nx /= len
      ny /= len
      if (Math.abs(nx) + Math.abs(ny) < 0.25) ny = -1
      edges.push({ x, y, nx, ny, tx: -ny, ty: nx })
    }
  }

  return { inside, samples, edges }
}

function pickContourFlameEmitters(edges, width, height, variant = 'v1') {
  if (!edges.length) return []

  const denseMode = variant !== 'v1'
  const candidates = edges
    .filter(edge => edge.y < height * 0.91)
    .map(edge => {
      const yn = edge.y / height
      const topBias = clamp(1 - yn, 0, 1)
      const upwardFacing = clamp((-edge.ny + 1) * 0.5, 0, 1)
      const sideFacing = Math.abs(edge.nx)
      const undersidePenalty = Math.max(0, edge.ny) * 0.86
      const score = topBias * 0.58 + upwardFacing * 0.76 + sideFacing * 0.2 - undersidePenalty
      return { ...edge, score, topness: topBias }
    })
    .filter(edge => edge.score > (denseMode ? 0.19 : 0.28))
    .sort((a, b) => b.score - a.score)

  const selected = []
  const minDist = denseMode
    ? Math.max(2.1, Math.min(width, height) * 0.015)
    : Math.max(4.2, Math.min(width, height) * 0.032)
  const maxCount = denseMode ? 72 : 30

  for (const edge of candidates) {
    if (selected.length >= maxCount) break
    const tooClose = selected.some(other => Math.hypot(other.x - edge.x, other.y - edge.y) < minDist)
    if (tooClose) continue
    selected.push({
      ...edge,
      phase: rand(0, Math.PI * 2),
      reach: 0.7 + edge.topness * 0.9 + rand(-0.08, 0.1),
      widthScale: denseMode ? rand(0.9, 1.16) : rand(0.86, 1.16),
    })
  }

  return selected
}

function buildFlameEdgeCanvas(edges, width, height, strength) {
  const canvas = document.createElement('canvas')
  canvas.width = Math.max(1, Math.round(width))
  canvas.height = Math.max(1, Math.round(height))
  const ctx = canvas.getContext('2d')
  ctx.globalCompositeOperation = 'lighter'

  // Several soft passes merge the individual boundary samples into one continuous hot edge.
  const passes = [
    { r: 5.5, fill: `rgba(255,55,8,${0.05 + strength * 0.035})`, blur: 8 },
    { r: 3.1, fill: `rgba(255,117,24,${0.08 + strength * 0.055})`, blur: 4 },
    { r: 1.45, fill: `rgba(255,231,105,${0.16 + strength * 0.08})`, blur: 2 },
  ]

  for (const pass of passes) {
    ctx.fillStyle = pass.fill
    ctx.shadowBlur = pass.blur
    ctx.shadowColor = pass.r > 4 ? '#ff4b12' : '#ffd75c'
    for (let i = 0; i < edges.length; i += 1) {
      const edge = edges[i]
      ctx.beginPath()
      ctx.arc(edge.x, edge.y, pass.r, 0, Math.PI * 2)
      ctx.fill()
    }
  }
  ctx.shadowBlur = 0
  return canvas
}

function flamePalette(style) {
  if (style === 'anime') return {
    outer: '#e82d12', mid: '#ff6a0d', inner: '#ffc928', core: '#fff08a', smoke: '#6b7280',
  }
  if (style === 'smoky') return {
    outer: '#b93816', mid: '#f26b20', inner: '#ffb23b', core: '#ffe496', smoke: '#667085',
  }
  return {
    outer: '#e83c12', mid: '#ff7418', inner: '#ffbd38', core: '#fff1a0', smoke: '#707784',
  }
}

function drawStaticFlameTongue(ctx, emitter, strength, style, scale = 1, heightBoost = 1, alpha = 1) {
  const palette = flamePalette(style)
  const top = emitter.topness
  const baseX = emitter.x + emitter.nx * (1.2 + strength * 1.1)
  const baseY = emitter.y + emitter.ny * (1.2 + strength * 1.1)
  const phaseVariation = 0.78 + ((Math.sin(emitter.phase * 2.31) + 1) * 0.5) * 0.48
  const height = (7 + top * 17 + strength * 6) * emitter.reach * heightBoost * phaseVariation
  const width = (2.8 + top * 2 + strength * 1.7) * emitter.widthScale * scale
  const lean = Math.sin(emitter.phase) * (style === 'anime' ? 2.7 : 1.65)
  const tipX = baseX + lean
  const tipY = baseY - height

  ctx.save()
  ctx.globalAlpha = alpha
  ctx.globalCompositeOperation = 'source-over'
  ctx.lineJoin = 'round'

  const drawShape = (w, h, color, blur = 0) => {
    const tY = baseY - h
    const tX = tipX + (height - h) * 0.035
    ctx.fillStyle = color
    ctx.shadowBlur = blur
    ctx.shadowColor = color
    ctx.beginPath()
    ctx.moveTo(baseX - width * w, baseY + 0.6)
    ctx.bezierCurveTo(
      baseX - width * w * 0.95,
      baseY - h * 0.25,
      tX - width * w * 0.32,
      baseY - h * 0.82,
      tX,
      tY,
    )
    ctx.bezierCurveTo(
      tX + width * w * 0.32,
      baseY - h * 0.8,
      baseX + width * w * 0.95,
      baseY - h * 0.24,
      baseX + width * w,
      baseY + 0.6,
    )
    ctx.closePath()
    ctx.fill()
  }

  if (style === 'anime') {
    drawShape(1.16, height, palette.outer, 0)
    drawShape(0.82, height * 0.77, palette.mid, 0)
    drawShape(0.48, height * 0.48, palette.inner, 0)
  } else {
    drawShape(1.28, height, palette.outer, style === 'smoky' ? 4 : 6)
    drawShape(0.94, height * 0.86, palette.mid, style === 'smoky' ? 2 : 3)
    drawShape(0.62, height * 0.63, palette.inner, 1.4)
    drawShape(0.28, height * 0.36, palette.core, 0.8)
  }
  ctx.restore()
}

function buildFlameStyleCanvas(emitters, width, height, strength, style) {
  const canvas = document.createElement('canvas')
  canvas.width = Math.max(1, Math.round(width))
  canvas.height = Math.max(1, Math.round(height))
  const ctx = canvas.getContext('2d')
  if (!emitters.length) return canvas

  const ordered = [...emitters].sort((a, b) => a.x - b.x || a.y - b.y)
  const broad = ordered.filter((_, i) => i % 2 === 0)
  const medium = ordered.filter((_, i) => i % 3 !== 1)
  const tall = ordered.filter((_, i) => i % 4 === 0)

  if (style === 'smooth') {
    // Broader, fewer, more connected waves of flame.
    broad.forEach(emitter => drawStaticFlameTongue(ctx, emitter, strength, 'smooth', 1.3, 0.88, 0.3 + strength * 0.16))
    medium.forEach(emitter => drawStaticFlameTongue(ctx, emitter, strength, 'smooth', 0.92, 0.72, 0.26 + strength * 0.14))
    tall.forEach(emitter => drawStaticFlameTongue(ctx, emitter, strength, 'smooth', 0.56, 1.04, 0.18 + strength * 0.1))
  } else if (style === 'hybrid') {
    // Stronger core and more height variation to feel closer to layered / realistic fire.
    ordered.forEach(emitter => drawStaticFlameTongue(ctx, emitter, strength, 'smooth', 1.12, 0.94, 0.34 + strength * 0.18))
    broad.forEach(emitter => drawStaticFlameTongue(ctx, emitter, strength, 'smooth', 0.92, 1.16 + (Math.sin(emitter.phase) * 0.08), 0.28 + strength * 0.16))
    tall.forEach(emitter => drawStaticFlameTongue(ctx, emitter, strength, 'smooth', 0.62, 1.42 + (Math.cos(emitter.phase * 1.7) * 0.12), 0.22 + strength * 0.12))
  } else if (style === 'anime') {
    // Cleaner, sharper peaks with more exaggerated silhouettes.
    ordered.forEach(emitter => drawStaticFlameTongue(ctx, emitter, strength, 'anime', 1.0, 1.1, 0.82))
    tall.forEach(emitter => drawStaticFlameTongue(ctx, emitter, strength, 'anime', 0.72, 1.34, 0.7))
  } else if (style === 'smoky') {
    // Dimmer flame body because the smoke needs room to be visible.
    broad.forEach(emitter => drawStaticFlameTongue(ctx, emitter, strength, 'smoky', 1.18, 0.9, 0.26 + strength * 0.14))
    medium.forEach(emitter => drawStaticFlameTongue(ctx, emitter, strength, 'smoky', 0.84, 1.06, 0.18 + strength * 0.1))
    tall.forEach(emitter => drawStaticFlameTongue(ctx, emitter, strength, 'smoky', 0.5, 1.26, 0.12 + strength * 0.06))
  }

  return canvas
}

function buildSmokeBackdropCanvas(emitters, width, height, strength) {
  const canvas = document.createElement('canvas')
  canvas.width = Math.max(1, Math.round(width))
  canvas.height = Math.max(1, Math.round(height))
  const ctx = canvas.getContext('2d')
  if (!emitters.length) return canvas

  const anchors = [...emitters].sort((a, b) => a.x - b.x || a.y - b.y).filter((_, i) => i % 6 === 0)
  ctx.globalCompositeOperation = 'source-over'

  for (const emitter of anchors) {
    const stack = 3 + Math.floor(((Math.sin(emitter.phase) + 1) * 0.5) * 2)
    const baseX = emitter.x + Math.sin(emitter.phase * 1.3) * 5
    const baseY = emitter.y - (10 + emitter.topness * 16)
    const drift = Math.cos(emitter.phase * 1.9) * 6

    for (let i = 0; i < stack; i += 1) {
      const rise = i * (8 + emitter.topness * 5)
      const rx = (8 + emitter.topness * 7 + i * 2.6) * (0.92 + strength * 0.24)
      const ry = (5.2 + emitter.topness * 4.2 + i * 2.2) * (0.9 + strength * 0.18)
      const x = baseX + drift * (i / Math.max(1, stack - 1))
      const y = baseY - rise
      const alpha = (0.12 + strength * 0.08) * (1 - i / (stack + 1))
      const g = ctx.createRadialGradient(x, y, 0, x, y, rx)
      g.addColorStop(0, `rgba(126,130,139,${alpha * 0.95})`)
      g.addColorStop(0.35, `rgba(96,100,110,${alpha * 0.82})`)
      g.addColorStop(0.72, `rgba(60,64,72,${alpha * 0.62})`)
      g.addColorStop(1, 'rgba(42,46,54,0)')
      ctx.fillStyle = g
      ctx.beginPath()
      ctx.ellipse(x, y, rx, ry, Math.sin(emitter.phase + i) * 0.2, 0, Math.PI * 2)
      ctx.fill()
    }
  }

  return canvas
}

function makeSmokeParticle(emitter, strength) {
  return {
    x: emitter.x + rand(-6, 6),
    y: emitter.y - rand(4, 14),
    vx: rand(-0.06, 0.06),
    vy: -rand(0.1, 0.26),
    life: 0,
    maxLife: rand(68, 136),
    r: rand(6.5, 13.5) * (0.86 + strength * 0.42),
    phase: rand(0, Math.PI * 2),
  }
}

function drawSmokeParticle(ctx, particle, strength = 1) {
  const t = clamp(particle.life / particle.maxLife, 0, 1)
  const alpha = Math.sin(Math.PI * t) * (0.16 + strength * 0.08)
  const r = particle.r * (1 + t * 1.45)
  ctx.save()
  ctx.globalCompositeOperation = 'source-over'
  const g = ctx.createRadialGradient(particle.x, particle.y, 0, particle.x, particle.y, r)
  g.addColorStop(0, `rgba(158,164,173,${alpha * 0.9})`)
  g.addColorStop(0.28, `rgba(114,120,130,${alpha * 0.84})`)
  g.addColorStop(0.62, `rgba(72,78,88,${alpha * 0.72})`)
  g.addColorStop(1, 'rgba(44,48,56,0)')
  ctx.fillStyle = g
  ctx.beginPath()
  ctx.arc(particle.x, particle.y, r, 0, Math.PI * 2)
  ctx.fill()
  ctx.restore()
}

function makeFlameParticle(emitter, strength, ember = false) {
  const spread = ember ? 5 : 4
  const baseHeight = emitter.reach || 1
  return {
    x: emitter.x + rand(-spread, spread),
    y: emitter.y + rand(-2, 2),
    vx: rand(-0.08, 0.08) + emitter.nx * rand(0.01, 0.06),
    vy: ember ? -rand(0.46, 0.88) : -rand(0.2, 0.52) * baseHeight,
    life: 0,
    maxLife: ember ? rand(26, 52) : rand(14, 26),
    size: ember ? rand(1.2, 2.8) : rand(3.6, 7.6) * (0.72 + strength * 0.38),
    hue: rand(8, 52),
    ember,
    sway: rand(0.012, 0.03),
    phase: rand(0, Math.PI * 2),
  }
}

function drawContourFlame(ctx, emitter, strength, time) {
  const flicker = 1 + Math.sin(time * 0.009 + emitter.phase) * 0.11
  const height = (8 + emitter.topness * 15 + strength * 7) * emitter.reach * flicker
  const halfWidth = (2.4 + strength * 1.8) * emitter.widthScale
  const outward = 1.4 + strength * 1.4
  const baseX = emitter.x + emitter.nx * outward
  const baseY = emitter.y + emitter.ny * outward
  const tipSway = Math.sin(time * 0.0065 + emitter.phase) * (1.2 + emitter.topness * 1.4)
  const tipX = baseX + tipSway
  const tipY = baseY - height
  const leftX = baseX - emitter.tx * halfWidth
  const leftY = baseY - emitter.ty * halfWidth
  const rightX = baseX + emitter.tx * halfWidth
  const rightY = baseY + emitter.ty * halfWidth

  ctx.save()
  ctx.globalCompositeOperation = 'screen'

  // Outer flame body. Adjacent roots overlap so they read as a single flame front.
  const outer = ctx.createLinearGradient(baseX, baseY, tipX, tipY)
  outer.addColorStop(0, `rgba(255,245,150,${0.5 + strength * 0.28})`)
  outer.addColorStop(0.28, `rgba(255,174,48,${0.54 + strength * 0.24})`)
  outer.addColorStop(0.7, `rgba(255,72,18,${0.42 + strength * 0.2})`)
  outer.addColorStop(1, 'rgba(255,35,5,0)')
  ctx.fillStyle = outer
  ctx.shadowBlur = 7
  ctx.shadowColor = '#ff6a18'
  ctx.beginPath()
  ctx.moveTo(leftX, leftY)
  ctx.bezierCurveTo(
    baseX - halfWidth * 1.15,
    baseY - height * 0.28,
    tipX - halfWidth * 0.72,
    tipY + height * 0.25,
    tipX,
    tipY,
  )
  ctx.bezierCurveTo(
    tipX + halfWidth * 0.78,
    tipY + height * 0.28,
    baseX + halfWidth * 1.08,
    baseY - height * 0.25,
    rightX,
    rightY,
  )
  ctx.closePath()
  ctx.fill()

  // Hot yellow/white core starts at the same contour and reaches a shorter height.
  const coreHeight = height * (0.52 + emitter.topness * 0.08)
  const coreTipX = baseX + tipSway * 0.45
  const coreTipY = baseY - coreHeight
  const coreW = halfWidth * 0.46
  const core = ctx.createLinearGradient(baseX, baseY, coreTipX, coreTipY)
  core.addColorStop(0, `rgba(255,255,244,${0.62 + strength * 0.25})`)
  core.addColorStop(0.38, `rgba(255,239,120,${0.58 + strength * 0.22})`)
  core.addColorStop(1, 'rgba(255,154,45,0)')
  ctx.fillStyle = core
  ctx.shadowBlur = 4
  ctx.shadowColor = '#fff19a'
  ctx.beginPath()
  ctx.moveTo(baseX - emitter.tx * coreW, baseY - emitter.ty * coreW)
  ctx.quadraticCurveTo(baseX - coreW * 0.5, baseY - coreHeight * 0.5, coreTipX, coreTipY)
  ctx.quadraticCurveTo(baseX + coreW * 0.5, baseY - coreHeight * 0.48, baseX + emitter.tx * coreW, baseY + emitter.ty * coreW)
  ctx.closePath()
  ctx.fill()

  ctx.restore()
}

function drawFlameParticle(ctx, particle, strength, time) {
  const t = particle.life / particle.maxLife
  const alpha = Math.sin(Math.PI * clamp(t, 0, 1)) * (particle.ember ? 0.72 : 0.42 + strength * 0.24)
  const radius = particle.size * (1 - t * (particle.ember ? 0.2 : 0.45))
  const sway = Math.sin(time * particle.sway + particle.phase) * (particle.ember ? 1.2 : 2.1)

  ctx.save()
  ctx.translate(particle.x + sway, particle.y)
  if (!particle.ember) ctx.scale(0.72, 1.5 + t * 0.56)
  const gradient = ctx.createRadialGradient(0, 0, 0, 0, 0, Math.max(1, radius))
  if (particle.ember) {
    gradient.addColorStop(0, `rgba(255,255,255,${alpha})`)
    gradient.addColorStop(0.3, `hsla(${particle.hue},100%,65%,${alpha * 0.9})`)
    gradient.addColorStop(1, 'rgba(255,80,0,0)')
  } else {
    gradient.addColorStop(0, `rgba(255,255,235,${alpha})`)
    gradient.addColorStop(0.22, `rgba(255,232,105,${alpha * 0.95})`)
    gradient.addColorStop(0.58, `hsla(${particle.hue},100%,56%,${alpha * 0.72})`)
    gradient.addColorStop(1, 'rgba(255,40,0,0)')
  }
  ctx.fillStyle = gradient
  ctx.beginPath()
  ctx.arc(0, 0, radius, 0, Math.PI * 2)
  ctx.fill()
  ctx.restore()
}

function makeElectricArc(edge, width, height, strength) {
  const tangentLength = rand(10, 25) * (0.75 + strength * 0.45)
  const outward = rand(4, 11) * (0.65 + strength * 0.4)
  const points = []
  const segments = 5 + Math.floor(Math.random() * 4)

  for (let i = 0; i <= segments; i += 1) {
    const q = i / segments - 0.5
    const wrap = Math.sin((q + 0.5) * Math.PI) * outward
    const jitter = rand(-2.1, 2.1)
    points.push({
      x: clamp(edge.x + edge.tx * q * tangentLength + edge.nx * (wrap + jitter), 0, width),
      y: clamp(edge.y + edge.ty * q * tangentLength + edge.ny * (wrap + jitter), 0, height),
    })
  }

  return {
    points,
    life: 0,
    maxLife: rand(4, 10),
    width: rand(0.8, 1.8),
    cyan: Math.random() < 0.58,
  }
}

function drawArc(ctx, arc, strength) {
  const t = arc.life / arc.maxLife
  const alpha = (1 - t) * (0.42 + strength * 0.58)
  if (arc.points.length < 2) return

  ctx.save()
  ctx.lineJoin = 'round'
  ctx.lineCap = 'round'

  ctx.beginPath()
  arc.points.forEach((point, index) => index === 0 ? ctx.moveTo(point.x, point.y) : ctx.lineTo(point.x, point.y))
  ctx.strokeStyle = arc.cyan
    ? `rgba(75,220,255,${alpha * 0.75})`
    : `rgba(132,146,255,${alpha * 0.72})`
  ctx.lineWidth = arc.width * 4.4
  ctx.shadowBlur = 9
  ctx.shadowColor = arc.cyan ? '#50eaff' : '#7f8cff'
  ctx.stroke()

  ctx.beginPath()
  arc.points.forEach((point, index) => index === 0 ? ctx.moveTo(point.x, point.y) : ctx.lineTo(point.x, point.y))
  ctx.strokeStyle = `rgba(255,255,255,${alpha})`
  ctx.lineWidth = arc.width
  ctx.shadowBlur = 4
  ctx.shadowColor = '#ffffff'
  ctx.stroke()
  ctx.restore()
}

function makeBubble(sample, sx, sy) {
  return {
    x: sample.x * sx,
    y: sample.y * sy,
    r: rand(1.8, 4.2),
    vy: -rand(0.18, 0.5),
    phase: rand(0, Math.PI * 2),
    wobble: rand(0.012, 0.03),
    life: 0,
    maxLife: rand(120, 260),
  }
}

function drawBubble(ctx, bubble, time) {
  const x = bubble.x + Math.sin(time * bubble.wobble + bubble.phase) * bubble.r * 0.7
  const y = bubble.y
  ctx.save()
  ctx.strokeStyle = 'rgba(225,248,255,.82)'
  ctx.fillStyle = 'rgba(190,236,255,.12)'
  ctx.lineWidth = Math.max(0.7, bubble.r * 0.22)
  ctx.shadowBlur = 4
  ctx.shadowColor = '#bfefff'
  ctx.beginPath()
  ctx.arc(x, y, bubble.r, 0, Math.PI * 2)
  ctx.fill()
  ctx.stroke()
  ctx.fillStyle = 'rgba(255,255,255,.9)'
  ctx.beginPath()
  ctx.arc(x - bubble.r * 0.28, y - bubble.r * 0.3, Math.max(0.6, bubble.r * 0.18), 0, Math.PI * 2)
  ctx.fill()
  ctx.restore()
}

function drawPop(ctx, pop) {
  const t = pop.life / pop.maxLife
  const radius = pop.r * (1 + t * 1.8)
  ctx.save()
  ctx.strokeStyle = `rgba(220,248,255,${(1 - t) * 0.8})`
  ctx.lineWidth = Math.max(0.5, 1.2 - t * 0.7)
  ctx.shadowBlur = 5
  ctx.shadowColor = '#d9f5ff'
  ctx.beginPath()
  ctx.arc(pop.x, pop.y, radius, 0, Math.PI * 2)
  ctx.stroke()
  ctx.restore()
}

export default function ElementalMaskFX({ layer, active = false, framing, comparison }) {
  const canvasRef = useRef(null)
  const activeRef = useRef(active)
  const framingX = clamp(Number(framing?.x ?? 50), 0, 100)
  const framingY = clamp(Number(framing?.y ?? 50), 0, 100)
  const framingZoom = clamp(Number(framing?.zoom ?? 100), 100, 220)

  useEffect(() => { activeRef.current = active }, [active])

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas || !layer?.image) return undefined

    const host = canvas.parentElement
    if (!host) return undefined

    // A grading pair uses the very same particle frame. Independent random
    // emitters otherwise make identical prints look like different masks.
    const comparisonKey = JSON.stringify([layer.image, layer.maskSource, layer.mode, layer.strength, framingX, framingY, framingZoom])
    const shared = comparison?.get(comparisonKey)
    if (shared) {
      const copyFrame = () => {
        const source = shared.canvas
        if (!source.width || !source.height || !source.style.width) return
        if (canvas.width !== source.width) canvas.width = source.width
        if (canvas.height !== source.height) canvas.height = source.height
        const ratio = host.offsetWidth / (source.parentElement?.offsetWidth || host.offsetWidth || 1)
        for (const name of ['left', 'top', 'width', 'height']) canvas.style[name] = `${parseFloat(source.style[name]) * ratio}px`
        const ctx = canvas.getContext('2d')
        ctx.clearRect(0, 0, canvas.width, canvas.height)
        ctx.drawImage(source, 0, 0)
      }
      shared.listeners.add(copyFrame)
      copyFrame()
      return () => shared.listeners.delete(copyFrame)
    }
    const published = comparison ? { canvas, listeners: new Set() } : null
    if (published) comparison.set(comparisonKey, published)

    let cancelled = false
    let frame = 0
    let observer
    let visibilityObserver
    let inViewport = false
    let img = null
    let resizeTimer = 0
    let pageVisible = !document.hidden
    let edges = []
    let contourFlameEmitters = []
    let insideMap = new Uint8Array(0)
    let insideSamples = []
    let analysisW = 1
    let analysisH = 1
    let cssWidth = 1
    let cssHeight = 1
    let dpr = 1
    let overscanX = 0
    let overscanY = 0
    let windowRect = { x0: 0, y0: 0, x1: 1, y1: 1 }
    let particles = []
    let arcs = []
    let bubbles = []
    let pops = []
    let smokeParticles = []
    let last = performance.now()
    let flameAccumulator = 0
    let emberAccumulator = 0
    let arcAccumulator = 0
    let bubbleAccumulator = 0
    let smokeAccumulator = 0
    let maskCanvas = null
    let waterCanvas = null
    let flameEdgeCanvas = null
    let flameStyleCanvas = null
    let smokeBackdropCanvas = null

    const mode = layer.maskSource || 'alpha'
    const strength = clamp(Number(layer.strength ?? 70) / 100, 0, 1)
    const effectByMode = {
      'foil-flame': 'flame',
      'foil-flame-v2': 'flame-smooth',
      'foil-flame-hybrid': 'flame-hybrid',
      'foil-flame-anime': 'flame-anime',
      'foil-flame-smoky': 'flame-smoky',
      'foil-electric': 'electric',
      'foil-water': 'water',
    }
    const effect = effectByMode[layer.mode]
    // Defensive guard: never fall back to flame for prism/outline/galaxy/etc.
    if (!effect) return undefined

    const pointInside = (x, y) => {
      if (!insideMap.length) return false
      const ax = clamp(Math.floor((x / cssWidth) * analysisW), 0, analysisW - 1)
      const ay = clamp(Math.floor((y / cssHeight) * analysisH), 0, analysisH - 1)
      return Boolean(insideMap[ay * analysisW + ax])
    }

    const rebuild = () => {
      if (!img || !img.naturalWidth || !img.naturalHeight || cancelled) return

      // IMPORTANT: use the host's layout box, not getBoundingClientRect().
      // The pack viewer animates from a transformed/scaled card into the large viewer.
      // getBoundingClientRect() includes that temporary transform, which caused the
      // elemental canvas to be built at the pack-card size and stay misaligned after
      // the large-card animation completed. offset/client dimensions stay tied to the
      // actual card layout and therefore match editor + pack viewers consistently.
      const layoutWidth = host.offsetWidth || host.clientWidth
      const layoutHeight = host.offsetHeight || host.clientHeight
      if (layoutWidth < 4 || layoutHeight < 4) return

      cssWidth = layoutWidth
      cssHeight = layoutHeight
      // Gallery cards are much cheaper at 1x DPR; large cards keep a little extra sharpness.
      dpr = cssWidth <= 260 ? 1 : Math.min(window.devicePixelRatio || 1, 1.5)
      overscanX = cssWidth * 0.18
      overscanY = cssHeight * 0.18
      const canvasCssW = cssWidth + overscanX * 2
      const canvasCssH = cssHeight + overscanY * 2

      canvas.style.left = `${-overscanX}px`
      canvas.style.top = `${-overscanY}px`
      canvas.style.width = `${canvasCssW}px`
      canvas.style.height = `${canvasCssH}px`
      canvas.width = Math.max(1, Math.round(canvasCssW * dpr))
      canvas.height = Math.max(1, Math.round(canvasCssH * dpr))

      const analysisScale = cssWidth <= 260 ? 0.92 : Math.min(1.15, Math.max(0.72, 320 / cssWidth))
      analysisW = Math.max(80, Math.round(cssWidth * analysisScale))
      analysisH = Math.max(80, Math.round(cssHeight * analysisScale))
      const off = document.createElement('canvas')
      off.width = analysisW
      off.height = analysisH
      const offCtx = off.getContext('2d', { willReadFrequently: true })
      // X/Y are baked into the analyzed crop. Zoom is applied by the shared
      // subject-layer transform so cutout, CSS masks and contour canvas scale
      // together exactly once.
      const focusX = framingX / 100
      const focusY = framingY / 100
      const fit = coverRect(img.naturalWidth, img.naturalHeight, analysisW, analysisH, focusX, focusY)
      // The subject layer is scaled by the art zoom around the focus point, so only part of this (unscaled) box
      // shows through the artwork window. Mask parts outside it sit behind the card frame: they must not emit
      // anything (flames from inside the window may still rise past the border).
      const shown = 100 / framingZoom
      windowRect = {
        x0: focusX * cssWidth * (1 - shown), y0: focusY * cssHeight * (1 - shown),
        x1: focusX * cssWidth * (1 - shown) + cssWidth * shown, y1: focusY * cssHeight * (1 - shown) + cssHeight * shown,
      }
      const inWindow = (x, y) => x >= windowRect.x0 && x <= windowRect.x1 && y >= windowRect.y0 && y <= windowRect.y1
      offCtx.clearRect(0, 0, analysisW, analysisH)
      offCtx.drawImage(img, fit.x, fit.y, fit.w, fit.h)

      const cacheKey = `${layer.image.length}:${layer.image.slice(-48)}|${mode}|${effect}|${strength}|${Math.round(focusX * 100)}:${Math.round(focusY * 100)}:${Math.round(framingZoom)}|${Math.round(cssWidth)}x${Math.round(cssHeight)}`
      try {
        const hit = fxCache.get(cacheKey)
        if (hit) {
          ;({ insideMap, insideSamples, edges, contourFlameEmitters, flameEdgeCanvas, flameStyleCanvas, smokeBackdropCanvas, maskCanvas } = hit)
          waterCanvas = document.createElement('canvas')
          waterCanvas.width = maskCanvas.width
          waterCanvas.height = maskCanvas.height
        } else {
        const data = offCtx.getImageData(0, 0, analysisW, analysisH)
        const derived = deriveMask(data, analysisW, analysisH, mode)
        insideMap = derived.inside
        const sx = cssWidth / analysisW
        const sy = cssHeight / analysisH
        derived.edges = derived.edges.filter(edge => inWindow(edge.x * sx, edge.y * sy))
        insideSamples = derived.samples.filter(sample => inWindow(sample.x * sx, sample.y * sy))
        edges = derived.edges.map(edge => ({
          x: overscanX + edge.x * sx,
          y: overscanY + edge.y * sy,
          nx: edge.nx,
          ny: edge.ny,
          tx: edge.tx,
          ty: edge.ty,
        }))

        const localEdges = derived.edges.map(edge => ({ ...edge, x: edge.x * sx, y: edge.y * sy }))
        const denseFlame = effect !== 'flame'
        contourFlameEmitters = pickContourFlameEmitters(localEdges, cssWidth, cssHeight, denseFlame ? 'dense' : 'v1').map(edge => ({
          ...edge,
          x: overscanX + edge.x,
          y: overscanY + edge.y,
        }))

        flameEdgeCanvas = effect?.startsWith('flame') ? buildFlameEdgeCanvas(edges, canvasCssW, canvasCssH, strength) : null
        const styleByEffect = {
          'flame-smooth': 'smooth',
          'flame-hybrid': 'hybrid',
          'flame-anime': 'anime',
          'flame-smoky': 'smoky',
        }
        flameStyleCanvas = styleByEffect[effect]
          ? buildFlameStyleCanvas(contourFlameEmitters, canvasCssW, canvasCssH, strength, styleByEffect[effect])
          : null
        smokeBackdropCanvas = effect === 'flame-smoky'
          ? buildSmokeBackdropCanvas(contourFlameEmitters, canvasCssW, canvasCssH, strength)
          : null

        const mw = Math.max(1, Math.round(cssWidth))
        const mh = Math.max(1, Math.round(cssHeight))
        maskCanvas = document.createElement('canvas')
        maskCanvas.width = mw
        maskCanvas.height = mh
        const mctx = maskCanvas.getContext('2d', { willReadFrequently: true })
        const mfit = coverRect(img.naturalWidth, img.naturalHeight, mw, mh, focusX, focusY)
        mctx.clearRect(0, 0, mw, mh)
        mctx.drawImage(img, mfit.x, mfit.y, mfit.w, mfit.h)
        const maskData = mctx.getImageData(0, 0, mw, mh)
        for (let i = 0; i < maskData.data.length; i += 4) {
          const value = maskValue(maskData.data, i, mode)
          maskData.data[i] = 255
          maskData.data[i + 1] = 255
          maskData.data[i + 2] = 255
          maskData.data[i + 3] = Math.round(value * 255)
        }
        mctx.putImageData(maskData, 0, 0)

        waterCanvas = document.createElement('canvas')
        waterCanvas.width = mw
        waterCanvas.height = mh
        if (fxCache.size >= FX_CACHE_MAX) fxCache.delete(fxCache.keys().next().value)
        fxCache.set(cacheKey, { insideMap, insideSamples, edges, contourFlameEmitters, flameEdgeCanvas, flameStyleCanvas, smokeBackdropCanvas, maskCanvas })
        }
      } catch (error) {
        console.warn('Elemental mask FX could not read this mask image. Same-origin/data URLs work best.', error)
        edges = []
        contourFlameEmitters = []
        flameEdgeCanvas = null
        flameStyleCanvas = null
        smokeBackdropCanvas = null
        insideMap = new Uint8Array(0)
        insideSamples = []
      }

      particles = []
      smokeParticles = []
      arcs = []
      bubbles = []
      pops = []
    }

    let imgReady = false
    let built = false
    let queued = false
    const build = () => {
      if (built || queued || cancelled) return
      queued = true
      scheduleFxJob(() => {
        queued = false
        if (cancelled) return
        rebuild()
        built = true
        let lastW = host.offsetWidth
        let lastH = host.offsetHeight
        observer = new ResizeObserver(() => {
          if (Math.abs(host.offsetWidth - lastW) < 2 && Math.abs(host.offsetHeight - lastH) < 2) return
          lastW = host.offsetWidth
          lastH = host.offsetHeight
          clearTimeout(resizeTimer)
          resizeTimer = setTimeout(() => scheduleFxJob(rebuild), 120)
        })
        observer.observe(host)
      })
    }
    loadImage(layer.image).then(loaded => {
      if (cancelled) return
      img = loaded
      imgReady = true
      if (inViewport) build()
    }).catch(() => { edges = []; contourFlameEmitters = []; flameEdgeCanvas = null; flameStyleCanvas = null; smokeBackdropCanvas = null })

    const onPageVisibility = () => { pageVisible = !document.hidden }
    document.addEventListener('visibilitychange', onPageVisibility)
    visibilityObserver = new IntersectionObserver((entries) => {
      inViewport = Boolean(entries[0]?.isIntersecting)
      if (inViewport && imgReady) build()
    }, { rootMargin: '240px', threshold: 0.01 })
    visibilityObserver.observe(host)

    const drawWater = (ctx, now, dt, activeNow) => {
      if (!maskCanvas || !waterCanvas || !insideSamples.length) return
      const wctx = waterCanvas.getContext('2d')
      const w = waterCanvas.width
      const h = waterCanvas.height
      wctx.clearRect(0, 0, w, h)

      const drift = (now * 0.018) % 80
      const grad = wctx.createLinearGradient(0, 0, 0, h)
      grad.addColorStop(0, 'rgba(210,248,255,.62)')
      grad.addColorStop(0.28, 'rgba(82,214,248,.58)')
      grad.addColorStop(0.62, 'rgba(20,146,225,.62)')
      grad.addColorStop(1, 'rgba(5,65,145,.68)')
      wctx.fillStyle = grad
      wctx.fillRect(0, 0, w, h)

      const foil = wctx.createLinearGradient(-drift, 0, w + drift, h)
      foil.addColorStop(0, 'rgba(95,240,255,.16)')
      foil.addColorStop(0.28, 'rgba(155,120,255,.14)')
      foil.addColorStop(0.52, 'rgba(255,255,255,.2)')
      foil.addColorStop(0.75, 'rgba(80,220,255,.16)')
      foil.addColorStop(1, 'rgba(70,110,255,.14)')
      wctx.globalCompositeOperation = 'screen'
      wctx.fillStyle = foil
      wctx.fillRect(0, 0, w, h)

      wctx.lineWidth = 1
      for (let row = 14; row < h; row += 16) {
        wctx.beginPath()
        for (let x = 0; x <= w; x += 5) {
          const y = row + Math.sin(x * 0.045 + now * 0.003 + row * 0.03) * 2.3
          if (x === 0) wctx.moveTo(x, y)
          else wctx.lineTo(x, y)
        }
        wctx.strokeStyle = 'rgba(225,250,255,.22)'
        wctx.stroke()
      }

      bubbleAccumulator += dt * (activeNow ? 0.3 : 0.13) * (0.7 + strength)
      while (bubbleAccumulator >= 1 && bubbles.length < (activeNow ? 30 : 20)) {
        bubbleAccumulator -= 1
        let sample = insideSamples[Math.floor(Math.random() * insideSamples.length)]
        for (let tries = 0; tries < 6; tries += 1) {
          const candidate = insideSamples[Math.floor(Math.random() * insideSamples.length)]
          if (candidate.y > analysisH * 0.45) { sample = candidate; break }
        }
        bubbles.push(makeBubble(sample, cssWidth / analysisW, cssHeight / analysisH))
      }

      const nextBubbles = []
      for (const bubble of bubbles) {
        bubble.life += dt
        bubble.y += bubble.vy * dt
        const wobbleX = Math.sin(now * bubble.wobble + bubble.phase) * bubble.r * 0.7
        const checkX = bubble.x + wobbleX
        const stillInside = pointInside(checkX, bubble.y)
        if (!stillInside || bubble.life >= bubble.maxLife) {
          pops.push({ x: overscanX + checkX, y: overscanY + bubble.y, r: bubble.r, life: 0, maxLife: 14 })
          continue
        }
        drawBubble(wctx, bubble, now)
        nextBubbles.push(bubble)
      }
      bubbles = nextBubbles

      wctx.globalCompositeOperation = 'destination-in'
      wctx.drawImage(maskCanvas, 0, 0)
      wctx.globalCompositeOperation = 'source-over'

      // Layer strength is also the water opacity: 0 = invisible, 1 = full water fill.
      ctx.save()
      ctx.globalAlpha = strength
      ctx.beginPath()
      ctx.rect(overscanX + windowRect.x0, overscanY + windowRect.y0, windowRect.x1 - windowRect.x0, windowRect.y1 - windowRect.y0)
      ctx.clip()
      ctx.drawImage(waterCanvas, overscanX, overscanY, cssWidth, cssHeight)
      ctx.restore()

      const nextPops = []
      ctx.save()
      ctx.globalAlpha = strength
      for (const pop of pops) {
        pop.life += dt
        if (pop.life < pop.maxLife) {
          drawPop(ctx, pop)
          nextPops.push(pop)
        }
      }
      ctx.restore()
      pops = nextPops
    }

    const tick = (now) => {
      if (cancelled) return
      frame = requestAnimationFrame(tick)
      if (!inViewport || !pageVisible) { last = now; return }

      const activeNow = activeRef.current
      const targetFps = cssWidth <= 260 ? (activeNow ? 36 : 20) : (activeNow ? 48 : 28)
      const frameInterval = 1000 / targetFps
      const elapsed = now - last
      if (elapsed < frameInterval) return

      const ctx = canvas.getContext('2d')
      const dt = Math.min(50, elapsed) / 16.667
      last = now
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
      ctx.clearRect(0, 0, canvas.width / dpr, canvas.height / dpr)
      ctx.globalCompositeOperation = 'screen'

      if (effect === 'water') {
        drawWater(ctx, now, dt, activeNow)
      } else if (edges.length) {
        if (effect?.startsWith('flame')) {
          if (flameEdgeCanvas) {
            ctx.save()
            ctx.globalAlpha = effect === 'flame-anime' ? 0.62 : 0.72
            ctx.drawImage(flameEdgeCanvas, 0, 0)
            ctx.restore()
          }

          if (effect === 'flame') {
            contourFlameEmitters.forEach((emitter) => drawContourFlame(ctx, emitter, strength, now))
            flameAccumulator += dt * (activeNow ? 0.36 : 0.12) * (0.45 + strength)
            emberAccumulator += dt * (activeNow ? 0.22 : 0.08) * (0.45 + strength)

            while (flameAccumulator >= 1 && particles.filter(p => !p.ember).length < 12 && contourFlameEmitters.length) {
              flameAccumulator -= 1
              particles.push(makeFlameParticle(contourFlameEmitters[Math.floor(Math.random() * contourFlameEmitters.length)], strength, false))
            }
            while (emberAccumulator >= 1 && particles.filter(p => p.ember).length < 18 && contourFlameEmitters.length) {
              emberAccumulator -= 1
              particles.push(makeFlameParticle(contourFlameEmitters[Math.floor(Math.random() * contourFlameEmitters.length)], strength, true))
            }
          } else {
            // v2-v5 are mostly pre-rendered flame fronts. This keeps the gallery responsive while
            // still giving them live flicker, vertical movement, embers, and (for v3/v5) extra detail.
            if (flameStyleCanvas) {
              const flicker = 0.92 + Math.sin(now * 0.011) * 0.045
              const bob = Math.sin(now * 0.008) * (effect === 'flame-anime' ? 0.6 : 1.05)
              ctx.save()
              ctx.globalAlpha = flicker * (effect === 'flame-smoky' ? (0.46 + strength * 0.22) : (0.64 + strength * 0.34))
              ctx.drawImage(flameStyleCanvas, 0, bob)
              if (effect === 'flame-smooth' || effect === 'flame-hybrid') {
                ctx.globalAlpha = 0.16 + strength * 0.08
                ctx.drawImage(flameStyleCanvas, 0, bob - 1.4)
              }
              ctx.restore()
            }

            if (effect === 'flame-hybrid') {
              ctx.save()
              ctx.globalAlpha = 0.42 + strength * 0.18
              contourFlameEmitters.filter((_, i) => i % 5 === 0).forEach((emitter) => drawContourFlame(ctx, emitter, strength * 0.86, now))
              ctx.restore()
            }

            emberAccumulator += dt * (activeNow ? 0.13 : 0.045) * (0.32 + strength)
            const maxEmbers = effect === 'flame-anime' ? 5 : effect === 'flame-smoky' ? 8 : 10
            while (emberAccumulator >= 1 && particles.filter(p => p.ember).length < maxEmbers && contourFlameEmitters.length) {
              emberAccumulator -= 1
              particles.push(makeFlameParticle(contourFlameEmitters[Math.floor(Math.random() * contourFlameEmitters.length)], strength, true))
            }

            if (effect === 'flame-smoky') {
              smokeAccumulator += dt * (activeNow ? 0.18 : 0.08) * (0.5 + strength)
              while (smokeAccumulator >= 1 && smokeParticles.length < (activeNow ? 22 : 14) && contourFlameEmitters.length) {
                smokeAccumulator -= 1
                smokeParticles.push(makeSmokeParticle(contourFlameEmitters[Math.floor(Math.random() * contourFlameEmitters.length)], strength))
              }
            }
          }

          const next = []
          for (const particle of particles) {
            particle.life += dt
            particle.x += particle.vx * dt
            particle.y += particle.vy * dt
            particle.vy -= particle.ember ? 0.004 * dt : 0.005 * dt
            particle.vx *= 0.992
            if (particle.life < particle.maxLife) {
              drawFlameParticle(ctx, particle, strength, now)
              next.push(particle)
            }
          }
          particles = next

          if (effect === 'flame-smoky') {
            if (smokeBackdropCanvas) {
              ctx.save()
              ctx.globalAlpha = 0.58 + strength * 0.26
              ctx.drawImage(smokeBackdropCanvas, 0, Math.sin(now * 0.0034) * 1.2)
              ctx.globalAlpha = 0.2 + strength * 0.12
              ctx.drawImage(smokeBackdropCanvas, 1.6, -2 + Math.sin(now * 0.0026 + 0.8) * 1.8)
              ctx.restore()
            }

            const nextSmoke = []
            for (const smoke of smokeParticles) {
              smoke.life += dt
              smoke.x += smoke.vx * dt + Math.sin(now * 0.0018 + smoke.phase) * 0.05
              smoke.y += smoke.vy * dt
              if (smoke.life < smoke.maxLife) {
                drawSmokeParticle(ctx, smoke, strength)
                nextSmoke.push(smoke)
              }
            }
            smokeParticles = nextSmoke
          }
        } else {
          arcAccumulator += dt * (activeNow ? 0.58 : 0.24) * (0.55 + strength)
          while (arcAccumulator >= 1 && arcs.length < (activeNow ? 22 : 13)) {
            arcAccumulator -= 1
            const edge = edges[Math.floor(Math.random() * edges.length)]
            arcs.push(makeElectricArc(edge, canvas.width / dpr, canvas.height / dpr, strength))
          }

          arcs = arcs.filter(arc => arc.life < arc.maxLife)
          for (const arc of arcs) {
            arc.life += dt
            drawArc(ctx, arc, strength)
          }

          const sparks = activeNow ? 7 : 2
          for (let i = 0; i < sparks; i += 1) {
            const edge = edges[Math.floor(Math.random() * edges.length)]
            if (Math.random() < 0.58) continue
            const x = edge.x + edge.nx * rand(2, 8)
            const y = edge.y + edge.ny * rand(2, 8)
            const r = rand(0.8, 1.7)
            const gradient = ctx.createRadialGradient(x, y, 0, x, y, r * 4)
            gradient.addColorStop(0, `rgba(255,255,255,${0.7 + strength * 0.3})`)
            gradient.addColorStop(0.28, `rgba(100,225,255,${0.45 + strength * 0.35})`)
            gradient.addColorStop(1, 'rgba(70,120,255,0)')
            ctx.fillStyle = gradient
            ctx.beginPath()
            ctx.arc(x, y, r * 4, 0, Math.PI * 2)
            ctx.fill()
          }
        }
      }

      published?.listeners.forEach(copyFrame => copyFrame())
    }

    frame = requestAnimationFrame(tick)
    return () => {
      cancelled = true
      cancelAnimationFrame(frame)
      clearTimeout(resizeTimer)
      observer?.disconnect()
      visibilityObserver?.disconnect()
      document.removeEventListener('visibilitychange', onPageVisibility)
      if (published && comparison.get(comparisonKey) === published) comparison.delete(comparisonKey)
    }
  }, [layer.image, layer.maskSource, layer.mode, layer.strength, framingX, framingY, framingZoom, comparison])

  return <canvas ref={canvasRef} className={`elemental-mask-fx elemental-mask-fx--${layer.mode}`} aria-hidden="true" />
}

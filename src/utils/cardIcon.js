/**
 * Draws a small inventory icon for a card print (default 100x100, transparent background):
 * a mini card in the print's accent colour with its artwork, name, HP and rarity pips.
 * Pure Canvas 2D, so it works in FiveM's embedded Chromium and needs no extra library.
 * Returns a data URL (WebP, falling back to PNG; PNG when format = 'png').
 */
import { rarityFx } from './rarityFx'
import { resolveAsset } from '../runtime/assets'
import { packsPerCopy, starStyle } from './printOdds.js'

const PIPS = { common: 1, uncommon: 2, rare: 3, ultra_rare: 4, legendary: 5 }
const clamp = (n, min, max) => Math.min(Math.max(Number(n) || 0, min), max)

const loadImage = async src => {
  if (!src) return null
  const resolved = await resolveAsset(src)
  if (resolved.status !== 'loaded' || !resolved.url) return null
  return new Promise(resolve => {
    const img = new Image()
    img.onload = () => resolve(img)
    img.onerror = () => resolve(null)
    img.src = resolved.url
  })
}

const roundRect = (ctx, x, y, w, h, r) => {
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + h, r)
  ctx.arcTo(x + w, y + h, x, y + h, r)
  ctx.arcTo(x, y + h, x, y, r)
  ctx.arcTo(x, y, x + w, y, r)
  ctx.closePath()
}

const star = (ctx, cx, cy, r) => {
  ctx.beginPath()
  for (let i = 0; i < 10; i++) {
    const a = -Math.PI / 2 + (i * Math.PI) / 5
    const rr = i % 2 ? r * 0.45 : r
    ctx.lineTo(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr)
  }
  ctx.closePath()
}

export async function renderCardIcon(card, size = 100, format = 'webp') {
  const scale = 2 // draw at 2x, then downsample for smoother edges
  const S = size * scale
  const canvas = document.createElement('canvas')
  canvas.width = S; canvas.height = S
  const ctx = canvas.getContext('2d')

  const fx = rarityFx(card?.rarityKey)
  const accent = card?.accent || fx.color
  const h = S * 0.98, w = h * (230 / 322)
  const x = (S - w) / 2, y = (S - h) / 2, r = w * 0.08

  // frame
  ctx.save()
  ctx.shadowColor = fx.color; ctx.shadowBlur = S * 0.05
  roundRect(ctx, x, y, w, h, r)
  const frame = ctx.createLinearGradient(x, y, x + w, y + h)
  frame.addColorStop(0, '#ffffff'); frame.addColorStop(0.18, accent); frame.addColorStop(1, accent)
  ctx.fillStyle = frame
  ctx.fill()
  ctx.restore()

  // card body
  const b = w * 0.055
  roundRect(ctx, x + b, y + b, w - b * 2, h - b * 2, r * 0.7)
  ctx.fillStyle = '#10131b'
  ctx.fill()

  // artwork
  const art = await loadImage(card?.image)
  const ax = x + b * 1.8, ay = y + h * 0.17, aw = w - b * 3.6, ah = h * 0.47
  ctx.save()
  roundRect(ctx, ax, ay, aw, ah, r * 0.4)
  ctx.clip()
  if (art) {
    const focusX = clamp(card?.imagePositionX ?? 50, 0, 100) / 100
    const focusY = clamp(card?.imagePositionY ?? 50, 0, 100) / 100
    const zoom = clamp(card?.imageZoom ?? 100, 100, 220) / 100
    const k = Math.max(aw / art.width, ah / art.height) * zoom
    const drawW = art.width * k, drawH = art.height * k
    const dx = ax - Math.max(0, drawW - aw) * focusX
    const dy = ay - Math.max(0, drawH - ah) * focusY
    ctx.drawImage(art, dx, dy, drawW, drawH)
  } else {
    ctx.fillStyle = accent; ctx.fillRect(ax, ay, aw, ah)
  }
  ctx.restore()

  // name + HP (the name is shortened to fit the space the HP leaves)
  ctx.fillStyle = '#f8fafc'
  ctx.textBaseline = 'middle'
  const font = px => `800 ${Math.round(px)}px Inter, "Segoe UI", Arial, sans-serif`
  let hpW = 0
  if (card?.hp != null) {
    ctx.font = font(h * 0.07)
    hpW = ctx.measureText(String(card.hp)).width
    ctx.textAlign = 'right'
    ctx.fillText(String(card.hp), ax + aw, y + h * 0.1)
    ctx.textAlign = 'left'
  }
  ctx.font = font(h * 0.078)
  const full = String(card?.title || 'Card')
  const maxTitle = aw - hpW - w * 0.05
  let title = full
  while (title.length > 1 && ctx.measureText(title + (title === full ? '' : '…')).width > maxTitle) title = title.slice(0, -1)
  ctx.fillText(title === full ? full : title.trimEnd() + '…', ax, y + h * 0.1)

  // lower panel lines (suggests the text block at icon size)
  ctx.fillStyle = 'rgba(255,255,255,.14)'
  for (let i = 0; i < 3; i++) ctx.fillRect(ax, y + h * (0.7 + i * 0.065), aw * (i === 2 ? 0.6 : 1), h * 0.022)

  // rarity stars: how many = the tier; colour = the print's real pull odds (the server sends starColour; otherwise
  // the odds this UI worked out from the catalogue, see utils/printOdds.js), the same as on the card itself
  const pips = PIPS[card?.rarityKey] || 1
  const pr = h * 0.032, gap = pr * 2.5
  const startX = x + w / 2 - ((pips - 1) * gap) / 2
  ctx.fillStyle = card?.starColour || (packsPerCopy(card) ? starStyle(card).colour : fx.color)
  ctx.strokeStyle = 'rgba(0,0,0,.7)'; ctx.lineWidth = scale
  for (let i = 0; i < pips; i++) { star(ctx, startX + i * gap, y + h * 0.92, pr); ctx.fill(); ctx.stroke() }

  // downsample
  const out = document.createElement('canvas')
  out.width = size; out.height = size
  const octx = out.getContext('2d')
  octx.imageSmoothingQuality = 'high'
  octx.drawImage(canvas, 0, 0, size, size)
  try {
    if (format === 'png') return out.toDataURL('image/png') // saved as a .png file in ox_inventory/web/images
    const webp = out.toDataURL('image/webp', 0.92)
    return webp.startsWith('data:image/webp') ? webp : out.toDataURL('image/png')
  } catch {
    return null // artwork from another site without CORS: the server keeps the rarity icon for this print
  }
}

// Uploaded artwork is stored inline as a data URL, so a raw phone photo (several MB) quickly overflows
// browser storage and bloats FiveM saves. Downscale and re-encode it in the browser before it reaches the draft.
const MAX_EDGE = 1024
const QUALITY = 0.85
const KEEP_AS_IS_BYTES = 200 * 1024 // small files (and small animated GIFs) are kept untouched

const readAsDataUrl = file => new Promise((resolve, reject) => {
  const reader = new FileReader()
  reader.onload = () => resolve(reader.result)
  reader.onerror = () => reject(new Error('Could not read that image file.'))
  reader.readAsDataURL(file)
})

const loadImage = src => new Promise((resolve, reject) => {
  const image = new Image()
  image.onload = () => resolve(image)
  image.onerror = () => reject(new Error('That file is not an image this browser can open.'))
  image.src = src
})

export async function compressImageFile(file, { maxEdge = MAX_EDGE, quality = QUALITY } = {}) {
  const original = await readAsDataUrl(file)
  if (file.size <= KEEP_AS_IS_BYTES || file.type === 'image/svg+xml') return original
  const image = await loadImage(original)
  const scale = Math.min(1, maxEdge / Math.max(image.naturalWidth, image.naturalHeight))
  const canvas = document.createElement('canvas')
  canvas.width = Math.max(1, Math.round(image.naturalWidth * scale))
  canvas.height = Math.max(1, Math.round(image.naturalHeight * scale))
  canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height)
  const webp = canvas.toDataURL('image/webp', quality)
  // Browsers without a WebP encoder fall back to PNG, which keeps transparency but is much larger.
  const compressed = webp.startsWith('data:image/webp') ? webp : canvas.toDataURL('image/png')
  return compressed.length < original.length ? compressed : original
}

export const dataUrlKb = value => Math.round(String(value || '').length * 0.75 / 1024)

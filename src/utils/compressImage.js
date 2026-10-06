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

export const dataUrlKb = value => Math.round(String(value || '').length * 0.75 / 1024)

/** Resolves { dataUrl, width, height, kb, originalKb, resized }. */
export async function compressImage(file, { maxEdge = MAX_EDGE, quality = QUALITY } = {}) {
  const original = await readAsDataUrl(file)
  const originalKb = Math.round(file.size / 1024)
  const image = await loadImage(original).catch(error => { if (file.type === 'image/svg+xml') return null; throw error })
  const keep = { dataUrl: original, width: image?.naturalWidth || 0, height: image?.naturalHeight || 0, kb: dataUrlKb(original), originalKb, resized: false }
  if (!image || file.size <= KEEP_AS_IS_BYTES || file.type === 'image/svg+xml') return keep
  const scale = Math.min(1, maxEdge / Math.max(image.naturalWidth, image.naturalHeight))
  const canvas = document.createElement('canvas')
  canvas.width = Math.max(1, Math.round(image.naturalWidth * scale))
  canvas.height = Math.max(1, Math.round(image.naturalHeight * scale))
  canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height)
  const webp = canvas.toDataURL('image/webp', quality)
  // Browsers without a WebP encoder fall back to PNG, which keeps transparency but is much larger.
  const compressed = webp.startsWith('data:image/webp') ? webp : canvas.toDataURL('image/png')
  if (compressed.length >= original.length) return keep
  return { dataUrl: compressed, width: canvas.width, height: canvas.height, kb: dataUrlKb(compressed), originalKb, resized: true }
}

const blobToDataUrl = blob => new Promise((resolve, reject) => {
  const reader = new FileReader()
  reader.onload = () => resolve(reader.result)
  reader.onerror = () => reject(new Error('Could not read the image.'))
  reader.readAsDataURL(blob)
})

/**
 * Downscale artwork that is already saved (an inline data: URL or a remote URL, already resolved to a
 * canvas-safe url) for the FiveM legacy artwork command. Resolves the data URL to store, or '' to keep it
 * as it is (onlyIfSmaller: nothing would shrink). Masks are kept lossless so their edges stay exact.
 */
export async function downscaleImageUrl(url, { maxEdge = MAX_EDGE, quality = QUALITY, lossless = false, onlyIfSmaller = false } = {}) {
  const original = url.startsWith('data:') ? url : await fetch(url).then(response => response.blob()).then(blobToDataUrl)
  if (/^data:image\/(gif|svg)/i.test(original)) return onlyIfSmaller ? '' : original // animation / vector: move it as it is
  const image = await loadImage(original)
  const scale = Math.min(1, maxEdge / Math.max(image.naturalWidth, image.naturalHeight))
  const canvas = document.createElement('canvas')
  canvas.width = Math.max(1, Math.round(image.naturalWidth * scale))
  canvas.height = Math.max(1, Math.round(image.naturalHeight * scale))
  canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height)
  const webp = lossless ? '' : canvas.toDataURL('image/webp', quality)
  const encoded = webp.startsWith('data:image/webp') ? webp : canvas.toDataURL('image/png')
  if (encoded.length < original.length) return encoded
  return onlyIfSmaller ? '' : original
}

export const compressImageFile = async (file, options) => (await compressImage(file, options)).dataUrl

const sizeLabel = kb => kb >= 1024 ? `${(kb / 1024).toFixed(1)} MB` : `${kb} KB`
export const describeUpload = info => info.resized
  ? `Artwork optimized: ${info.width}×${info.height}, ${sizeLabel(info.kb)} (was ${sizeLabel(info.originalKb)}).`
  : `Artwork kept as uploaded: ${info.width ? `${info.width}×${info.height}, ` : ''}${sizeLabel(info.kb)}.`

/**
 * onChange handler body for an artwork <input type="file">. Clears the input afterwards so choosing a file
 * again (the same one, or after a save / switching items) always fires a new change event.
 */
export function pickArtwork(input, onLoaded, { onInfo, ...options } = {}) {
  const file = input?.files?.[0]
  if (input) input.value = ''
  if (!file) return
  compressImage(file, options).then(info => { onLoaded(info.dataUrl); onInfo?.(describeUpload(info)) },
    error => onInfo ? onInfo(error.message) : console.warn('Could not load artwork file.', error))
}

const imageFileOf = transfer => [...(transfer?.files || [])].find(file => file.type.startsWith('image/'))
  || [...(transfer?.items || [])].find(item => item.kind === 'file' && item.type.startsWith('image/'))?.getAsFile()

/**
 * Props for an artwork URL <input>: pasting (Ctrl+V) or dropping an image puts it in like a chosen file.
 * The FiveM game browser's file dialog can stop opening, so this is the in-game fallback. Pasted text still works as usual.
 */
export function artworkPasteProps(onLoaded, { onInfo, ...options } = {}) {
  const take = (event, transfer) => {
    const file = imageFileOf(transfer)
    if (!file) return
    event.preventDefault()
    compressImage(file, options).then(info => { onLoaded(info.dataUrl); onInfo?.(describeUpload(info)) },
      error => onInfo ? onInfo(error.message) : console.warn('Could not load artwork file.', error))
  }
  return {
    onPaste: event => take(event, event.clipboardData),
    onDrop: event => take(event, event.dataTransfer),
    onDragOver: event => { if ([...(event.dataTransfer?.types || [])].includes('Files')) event.preventDefault() },
  }
}

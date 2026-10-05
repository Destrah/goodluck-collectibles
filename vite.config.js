import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const MAX_REMOTE_ASSET_BYTES = 12 * 1024 * 1024

function sniffImageType(body) {
  if (!body || body.length < 4) return ''
  if (body[0] === 0x89 && body[1] === 0x50 && body[2] === 0x4e && body[3] === 0x47) return 'image/png'
  if (body[0] === 0xff && body[1] === 0xd8 && body[2] === 0xff) return 'image/jpeg'
  const head6 = body.subarray(0, 6).toString('ascii')
  if (head6 === 'GIF87a' || head6 === 'GIF89a') return 'image/gif'
  if (body.length >= 12 && body.subarray(0, 4).toString('ascii') === 'RIFF' && body.subarray(8, 12).toString('ascii') === 'WEBP') return 'image/webp'
  if (body.length >= 12 && body.subarray(4, 8).toString('ascii') === 'ftyp' && ['avif', 'avis'].includes(body.subarray(8, 12).toString('ascii'))) return 'image/avif'
  return ''
}

function sendJson(res, status, payload) {
  res.statusCode = status
  res.setHeader('Content-Type', 'application/json; charset=utf-8')
  res.end(JSON.stringify(payload))
}

async function proxyRemoteAsset(req, res) {
  let remoteUrl = ''
  try {
    const parsed = new URL(req.url || '/', 'http://meta.local')
    remoteUrl = String(parsed.searchParams.get('url') || '').trim()
    const target = new URL(remoteUrl)
    if (!/^https?:$/.test(target.protocol)) {
      return sendJson(res, 400, { ok: false, code: 'INVALID_URL', error: 'Only HTTP(S) remote asset URLs are supported.' })
    }

    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), 15000)
    let upstream
    try {
      upstream = await fetch(target, {
        redirect: 'follow',
        signal: controller.signal,
        headers: { 'User-Agent': 'MetaComic/5 remote-asset-resolver' },
      })
    } finally {
      clearTimeout(timeout)
    }

    if (!upstream.ok) {
      return sendJson(res, 502, { ok: false, code: `HTTP_${upstream.status}`, error: `Remote server returned HTTP ${upstream.status}.`, httpStatus: upstream.status })
    }

    const declaredLength = Number(upstream.headers.get('content-length') || 0)
    if (declaredLength > MAX_REMOTE_ASSET_BYTES) {
      return sendJson(res, 413, { ok: false, code: 'ASSET_TOO_LARGE', error: `Remote image is larger than ${Math.round(MAX_REMOTE_ASSET_BYTES / 1024 / 1024)} MB.` })
    }

    const declaredType = String(upstream.headers.get('content-type') || '').split(';')[0].trim().toLowerCase()
    if (declaredType && !declaredType.startsWith('image/') && declaredType !== 'application/octet-stream') {
      return sendJson(res, 415, { ok: false, code: 'UNSUPPORTED_CONTENT_TYPE', error: `Remote URL returned ${declaredType}, not an image.` })
    }

    const body = Buffer.from(await upstream.arrayBuffer())
    if (!body.length) return sendJson(res, 502, { ok: false, code: 'EMPTY_RESPONSE', error: 'Remote asset returned an empty response.' })
    if (body.length > MAX_REMOTE_ASSET_BYTES) {
      return sendJson(res, 413, { ok: false, code: 'ASSET_TOO_LARGE', error: `Remote image is larger than ${Math.round(MAX_REMOTE_ASSET_BYTES / 1024 / 1024)} MB.` })
    }

    const type = (declaredType && declaredType.startsWith('image/') ? declaredType : '') || sniffImageType(body)
    if (!type) return sendJson(res, 415, { ok: false, code: 'UNSUPPORTED_IMAGE', error: 'Remote response did not decode as a supported PNG, JPEG, WebP, GIF, or AVIF image.' })

    res.statusCode = 200
    res.setHeader('Content-Type', type)
    res.setHeader('Content-Length', String(body.length))
    res.setHeader('Cache-Control', 'public, max-age=300')
    res.setHeader('X-Meta-Asset-Source', 'vite-proxy')
    res.end(body)
  } catch (error) {
    const aborted = error?.name === 'AbortError'
    sendJson(res, 502, {
      ok: false,
      code: aborted ? 'TIMEOUT' : 'PROXY_FETCH_FAILED',
      error: aborted ? 'Remote asset request timed out.' : `Remote asset request failed: ${error?.message || error}`,
      url: remoteUrl,
    })
  }
}

function remoteAssetResolverPlugin() {
  const install = server => {
    server.middlewares.use('/__meta_comic_asset', (req, res) => {
      proxyRemoteAsset(req, res)
    })
  }
  return {
    name: 'meta-remote-asset-resolver',
    configureServer: install,
    configurePreviewServer: install,
  }
}

export default defineConfig(({ mode }) => {
  const fivem = mode === 'fivem'
  return {
    plugins: [react(), remoteAssetResolverPlugin()],
    base: fivem ? './' : '/',
    build: fivem
      ? { outDir: 'fivem/web', emptyOutDir: true }
      : { outDir: 'dist' },
    server: { port: 5173 },
  }
})

import { useEffect, useState } from 'react'
import { getResourceName, isFiveM } from './env'

const assetCache = new Map()
const objectUrls = new Set()
const MAX_CACHE = 256
const DIRECT_FETCH_TIMEOUT_MS = 8000

class AssetError extends Error {
  constructor(code, message, details = {}) {
    super(message)
    this.name = 'AssetError'
    this.code = code
    Object.assign(this, details)
  }
}

function stringUrl(value) {
  return String(value || '').trim()
}

function classify(url) {
  if (!url) return 'empty'
  if (/^data:/i.test(url)) return 'data'
  if (/^blob:/i.test(url)) return 'blob'
  let parsed
  try { parsed = new URL(url, window.location.href) } catch { return 'local' }
  if (!/^https?:$/i.test(parsed.protocol)) return 'local'
  return parsed.origin === window.location.origin ? 'local' : 'remote'
}

function baseState(url) {
  const kind = classify(url)
  if (kind === 'empty') return { status: 'idle', url: '', source: 'none', originalUrl: url }
  if (kind !== 'remote') return { status: 'loaded', url, source: kind, originalUrl: url }
  return { status: 'loading', url: '', source: 'remote', originalUrl: url }
}

function errorCode(error) {
  if (error?.code) return error.code
  const text = String(error?.message || error || '').toLowerCase()
  if (text.includes('decode')) return 'DECODE_FAILED'
  if (text.includes('cors') || text.includes('failed to fetch') || error?.name === 'TypeError') return 'CORS_OR_NETWORK'
  return 'LOAD_FAILED'
}

function errorSummary(error) {
  if (!error) return ''
  return String(error.message || error)
}

function makeObjectUrl(blob) {
  const url = URL.createObjectURL(blob)
  objectUrls.add(url)
  return url
}

async function verifyDecodes(url) {
  await new Promise((resolve, reject) => {
    const image = new Image()
    image.onload = () => resolve()
    image.onerror = () => reject(new AssetError('DECODE_FAILED', 'The downloaded asset is not a browser-decodable image.'))
    image.src = url
  })
}

async function responseToSafeUrl(response, source, originalUrl) {
  if (!response.ok) throw new AssetError(`HTTP_${response.status}`, `HTTP ${response.status} while loading the remote asset.`, { httpStatus: response.status })
  const blob = await response.blob()
  if (!blob.size) throw new AssetError('EMPTY_RESPONSE', 'The remote asset returned an empty response.')
  const objectUrl = makeObjectUrl(blob)
  try {
    await verifyDecodes(objectUrl)
  } catch (error) {
    URL.revokeObjectURL(objectUrl)
    objectUrls.delete(objectUrl)
    throw error
  }
  return {
    status: 'loaded',
    url: objectUrl,
    source,
    originalUrl,
    contentType: blob.type || response.headers.get('content-type') || '',
    bytes: blob.size,
  }
}

async function directCors(url) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), DIRECT_FETCH_TIMEOUT_MS)
  try {
    const response = await fetch(url, {
      method: 'GET',
      mode: 'cors',
      credentials: 'omit',
      cache: 'force-cache',
      signal: controller.signal,
    })
    return await responseToSafeUrl(response, 'direct-cors', url)
  } catch (error) {
    if (error instanceof AssetError) throw error
    if (error?.name === 'AbortError') throw new AssetError('DIRECT_TIMEOUT', 'Direct browser loading timed out before CORS access could be confirmed.', { cause: error })
    throw new AssetError('CORS_OR_NETWORK', 'Direct browser loading was blocked by CORS or a network error.', { cause: error })
  } finally {
    clearTimeout(timeout)
  }
}

async function fiveMProxy(url) {
  let response
  try {
    response = await fetch(`https://${getResourceName()}/resolveRemoteAsset`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify({ url }),
    })
  } catch (error) {
    throw new AssetError('FIVEM_RESOLVER_UNAVAILABLE', 'The FiveM remote-asset resolver could not be reached.', { cause: error })
  }

  const payload = await response.json().catch(() => null)
  if (!response.ok || payload?.ok === false) {
    const code = payload?.code || `HTTP_${response.status}`
    throw new AssetError(code, payload?.error || `FiveM asset resolver failed (${response.status}).`, { httpStatus: payload?.httpStatus })
  }
  if (!payload?.dataUrl) throw new AssetError('EMPTY_PROXY_RESPONSE', 'The FiveM asset resolver returned no image data.')
  try {
    await verifyDecodes(payload.dataUrl)
  } catch (error) {
    throw new AssetError('DECODE_FAILED', 'FiveM downloaded the asset, but Chromium could not decode it.', { cause: error })
  }
  return {
    status: 'loaded',
    url: payload.dataUrl,
    source: payload.cached ? 'fivem-proxy-cache' : 'fivem-proxy',
    originalUrl: url,
    contentType: payload.contentType || '',
    bytes: payload.bytes || 0,
  }
}

async function viteProxy(url) {
  const endpoint = `/__meta_comic_asset?url=${encodeURIComponent(url)}`
  let response
  try {
    response = await fetch(endpoint, { method: 'GET', cache: 'force-cache' })
  } catch (error) {
    throw new AssetError('VITE_RESOLVER_UNAVAILABLE', 'The Vite remote-asset resolver could not be reached.', { cause: error })
  }
  if (!response.ok) {
    let payload = null
    try { payload = await response.json() } catch {}
    throw new AssetError(payload?.code || `HTTP_${response.status}`, payload?.error || `Vite asset resolver failed (${response.status}).`, { httpStatus: response.status })
  }
  return responseToSafeUrl(response, 'vite-proxy', url)
}

async function resolveRemote(url) {
  let directError = null
  try {
    return await directCors(url)
  } catch (error) {
    directError = error
  }

  try {
    const resolved = isFiveM ? await fiveMProxy(url) : await viteProxy(url)
    return {
      ...resolved,
      directError: {
        code: errorCode(directError),
        message: errorSummary(directError),
      },
    }
  } catch (proxyError) {
    const directCode = errorCode(directError)
    const proxyCode = errorCode(proxyError)
    const message = `Remote asset failed. Direct browser load: ${errorSummary(directError)} Resolver fallback: ${errorSummary(proxyError)}`
    throw new AssetError(proxyCode || directCode || 'LOAD_FAILED', message, {
      directError: { code: directCode, message: errorSummary(directError) },
      proxyError: { code: proxyCode, message: errorSummary(proxyError) },
    })
  }
}

function evictIfNeeded() {
  if (assetCache.size <= MAX_CACHE) return
  for (const [key, entry] of assetCache) {
    if (entry?.state?.status === 'loading' || (entry?.refs || 0) > 0) continue
    const url = entry?.state?.url
    if (url && url.startsWith('blob:') && objectUrls.has(url)) {
      URL.revokeObjectURL(url)
      objectUrls.delete(url)
    }
    assetCache.delete(key)
    if (assetCache.size <= MAX_CACHE) break
  }
}

export function getResolvedAssetState(input) {
  const url = stringUrl(input)
  return assetCache.get(url)?.state || baseState(url)
}

export function resolveAsset(input) {
  const url = stringUrl(input)
  const kind = classify(url)
  if (kind !== 'remote') return Promise.resolve(baseState(url))

  const existing = assetCache.get(url)
  if (existing) return existing.promise

  const entry = {
    state: { status: 'loading', url: '', source: 'remote', originalUrl: url },
    promise: null,
    refs: 0,
  }
  entry.promise = resolveRemote(url)
    .then(state => {
      entry.state = state
      evictIfNeeded()
      return state
    })
    .catch(error => {
      const state = {
        status: 'error',
        url: '',
        source: 'remote',
        originalUrl: url,
        code: errorCode(error),
        error: errorSummary(error),
        directError: error?.directError,
        proxyError: error?.proxyError,
      }
      entry.state = state
      return state
    })
  assetCache.set(url, entry)
  return entry.promise
}

export function useResolvedAsset(input, { showOriginalWhileLoading = false } = {}) {
  const url = stringUrl(input)
  const [state, setState] = useState(() => getResolvedAssetState(url))

  useEffect(() => {
    let cancelled = false
    const remote = classify(url) === 'remote'
    const pending = resolveAsset(url)
    if (remote) {
      const entry = assetCache.get(url)
      if (entry) entry.refs = (entry.refs || 0) + 1
    }
    setState(getResolvedAssetState(url))
    pending.then(next => {
      if (!cancelled) setState(next)
    })
    return () => {
      cancelled = true
      if (remote) {
        const entry = assetCache.get(url)
        if (entry) entry.refs = Math.max(0, (entry.refs || 1) - 1)
      }
    }
  }, [url])

  return {
    ...state,
    displayUrl: state.url || (showOriginalWhileLoading ? url : ''),
  }
}

if (typeof window !== 'undefined') {
  window.addEventListener('beforeunload', () => {
    for (const url of objectUrls) URL.revokeObjectURL(url)
    objectUrls.clear()
    assetCache.clear()
  }, { once: true })
}

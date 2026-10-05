import { bridge } from './bridge'
import { isFiveM } from './env'
import { readMigratedStorage } from './legacyStorage.js'
import { sanitizeContainerAnimations } from '../collectables/containerPrefs.js'

export const MIN_SPEED = 1 // 1x is the original pace and is the slowest allowed
export const DEFAULT_MAX_SPEED = 3
export const DEFAULT_FLIP_ALL_KEY = 'F'
export const DEFAULT_PREFS = { speed: 1, tear: 'peel', fan: 'line' }
export const FIVEM_DEFAULT_PREFS = { speed: 1, tear: 'random', fan: 'random' }

export const TEARS = ['peel', 'top', 'random']
const RETIRED_TEARS = { seam: 'peel' } // saved prefs from older versions move to the replacement
export const FANS = ['line', 'arc', 'wave', 'deal', 'random']

export function defaultPackPrefs() {
  return { ...(isFiveM ? FIVEM_DEFAULT_PREFS : DEFAULT_PREFS) }
}

export function clampSpeed(value, maxSpeed = DEFAULT_MAX_SPEED) {
  const max = Math.max(MIN_SPEED, Number(maxSpeed) || DEFAULT_MAX_SPEED)
  const n = Number(value)
  if (!Number.isFinite(n)) return MIN_SPEED
  return Math.min(max, Math.max(MIN_SPEED, n))
}

export function sanitizePrefs(raw, maxSpeed = DEFAULT_MAX_SPEED) {
  const defaults = defaultPackPrefs()
  const p = raw && typeof raw === 'object' ? raw : {}
  return {
    speed: clampSpeed(p.speed ?? defaults.speed, maxSpeed),
    tear: TEARS.includes(p.tear) ? p.tear : (RETIRED_TEARS[p.tear] || defaults.tear),
    fan: FANS.includes(p.fan) ? p.fan : defaults.fan,
    containerAnimations: sanitizeContainerAnimations(p.containerAnimations),
  }
}

/** Server/config limits (FiveM: Config.PackAnimation). Falls back to standalone defaults. */
export async function loadPackLimits() {
  try {
    const info = await bridge.getInfo()
    const rawKey = String(info?.packAnimation?.flipAllKey || DEFAULT_FLIP_ALL_KEY).trim()
    return {
      maxSpeed: Math.max(MIN_SPEED, Number(info?.packAnimation?.maxSpeed) || DEFAULT_MAX_SPEED),
      flipAllKey: rawKey || DEFAULT_FLIP_ALL_KEY,
    }
  } catch {
    return { maxSpeed: DEFAULT_MAX_SPEED, flipAllKey: DEFAULT_FLIP_ALL_KEY }
  }
}

/** Per-player preferences. Standalone: localStorage. FiveM: client KVP via NUI (survives cache clears). */
export async function loadPackPrefs(maxSpeed = DEFAULT_MAX_SPEED) {
  try {
    if (isFiveM) {
      const res = await bridge.getPackPrefs()
      return sanitizePrefs(res?.prefs, maxSpeed)
    }
    const saved = readMigratedStorage(KEY)
    return sanitizePrefs(saved ? JSON.parse(saved) : null, maxSpeed)
  } catch {
    return defaultPackPrefs()
  }
}

const KEY = 'meta-comic-pack-prefs-v1'

export async function savePackPrefs(prefs, maxSpeed = DEFAULT_MAX_SPEED, throwOnError = false) {
  const clean = sanitizePrefs(prefs, maxSpeed)
  try {
    if (isFiveM) await bridge.savePackPrefs(clean)
    else localStorage.setItem(KEY, JSON.stringify(clean))
  } catch (error) {
    if (throwOnError) throw error
    console.warn('Could not save pack animation preferences.', error)
  }
  return clean
}

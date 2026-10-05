import { CONTAINER_LOOKS, innerLookKind, normalizeLook } from './container3dOptions.js'

export function sanitizeContainerAnimations(raw) {
  return Object.fromEntries(Object.entries(CONTAINER_LOOKS).map(([kind, options]) => [kind,
    options.animations.some(entry => entry.id === raw?.[kind]) ? raw[kind] : 'random']))
}

export function openingLook(run, preferences, random = Math.random) {
  const kind = run.outer ? 'case' : innerLookKind(run.container)
  const look = normalizeLook(kind, run.outer ? run.container.outer?.look : run.container.look)
  const selected = sanitizeContainerAnimations(preferences?.containerAnimations)[kind]
  const animations = CONTAINER_LOOKS[kind].animations
  return {...look, animation: selected === 'random' ? animations[Math.min(animations.length-1,Math.floor(random()*animations.length))].id : selected}
}

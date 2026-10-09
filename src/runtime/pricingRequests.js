// Share active requests across effect restarts and embedded-view remounts.
const pending = new Map()
export function sharePricingRequest(key, request) {
  if (pending.has(key)) return pending.get(key)
  const promise = Promise.resolve().then(request).finally(() => {
    if (pending.get(key) === promise) pending.delete(key)
  })
  pending.set(key, promise)
  return promise
}

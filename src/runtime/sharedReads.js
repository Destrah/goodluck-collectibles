// Coalesce overlapping reads only. Completed results are never cached, so reopening
// a portal or refreshing after an action still asks the authoritative server.
const pending = new Map()
export function shareRead(key, request) {
  if (pending.has(key)) return pending.get(key)
  const promise = Promise.resolve().then(request).finally(() => {
    if (pending.get(key) === promise) pending.delete(key)
  })
  pending.set(key, promise)
  return promise
}

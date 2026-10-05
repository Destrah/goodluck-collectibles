export function queueInspectorBuild(previous, { isCurrent, build, publish, onError }) {
  return previous.catch(() => {}).then(async () => {
    if (!isCurrent()) return
    const result = await build()
    if (!result) return
    if (isCurrent()) publish(result)
    else result.dispose()
  }).catch(error => { if (isCurrent()) onError(error) })
}

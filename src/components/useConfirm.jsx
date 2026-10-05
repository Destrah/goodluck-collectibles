import { useCallback, useEffect, useRef, useState } from 'react'

// Native browser dialogs can invisibly block FiveM's embedded browser.
// Keep confirmations in React so NUI continues rendering and accepting input.
export default function useConfirm() {
  const [prompt, setPrompt] = useState(null)
  const pending = useRef(null)
  const cancelButton = useRef(null)
  const acceptButton = useRef(null)
  const finish = useCallback(accepted => {
    const request = pending.current
    pending.current = null
    setPrompt(null)
    request?.resolve(accepted)
    if (request?.focus?.isConnected) request.focus.focus()
  }, [])
  const confirm = useCallback((message, acceptLabel = 'Discard') => {
    // A second request must not leave the first action waiting forever.
    pending.current?.resolve(false)
    return new Promise(resolve => {
      pending.current = { resolve, focus: document.activeElement }
      setPrompt({ message, acceptLabel })
    })
  }, [])
  useEffect(() => () => {
    pending.current?.resolve(false)
    pending.current = null
  }, [])
  useEffect(() => {
    if (!prompt) return
    cancelButton.current?.focus()
    const onKeyDown = event => {
      if (event.key === 'Escape') {
        event.preventDefault()
        event.stopImmediatePropagation()
        finish(false)
      } else if (event.key === 'Tab') {
        event.preventDefault()
        event.stopImmediatePropagation()
        const next = document.activeElement === cancelButton.current ? acceptButton.current : cancelButton.current
        next?.focus()
      } else if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') {
        event.preventDefault()
        event.stopImmediatePropagation()
      }
    }
    window.addEventListener('keydown', onKeyDown, true)
    return () => window.removeEventListener('keydown', onKeyDown, true)
  }, [prompt, finish])
  const dialog = prompt && <div className="unsaved-overlay" role="presentation">
    <section className="unsaved-dialog" role="dialog" aria-modal="true" aria-labelledby="confirm-title" aria-describedby="confirm-message">
      <span className="eyebrow">Confirm action</span>
      <h3 id="confirm-title">{prompt.acceptLabel === 'Discard' ? 'Discard unsaved changes?' : 'Continue?'}</h3>
      <p id="confirm-message">{prompt.message}</p>
      <div className="unsaved-actions">
        <button ref={cancelButton} className="ghost" onClick={() => finish(false)}>Cancel</button>
        <button ref={acceptButton} className="danger ghost" onClick={() => finish(true)}>{prompt.acceptLabel}</button>
      </div>
    </section>
  </div>
  return { confirm, dialog, cancel: () => finish(false) }
}

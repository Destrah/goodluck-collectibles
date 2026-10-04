import React, { useEffect, useRef, useState } from 'react'

// Shared queue: at most 2 cards are mounted per animation frame, so fast scrolling never builds a whole row at once.
const mountQueue = []
let pumping = false
function pump() {
  if (pumping) return
  pumping = true
  const step = () => {
    for (let i = 0; i < 2 && mountQueue.length; i += 1) mountQueue.shift()()
    if (mountQueue.length) requestAnimationFrame(step)
    else pumping = false
  }
  requestAnimationFrame(step)
}
function enqueueMount(fn) { mountQueue.push(fn); pump() }

/**
 * Renders children only once the placeholder gets near the viewport (and keeps them mounted after that).
 * Used for the Print collection / effect sampler so dozens of holo/foil cards don't all build at once.
 */
export default function LazyMount({ width = 230, height = 322, margin = '500px', children, className = '' }) {
  const ref = useRef(null)
  const [show, setShow] = useState(typeof IntersectionObserver === 'undefined')

  useEffect(() => {
    if (show || !ref.current) return undefined
    const io = new IntersectionObserver((entries) => {
      if (entries.some(e => e.isIntersecting)) { io.disconnect(); enqueueMount(() => setShow(true)) }
    }, { rootMargin: margin })
    io.observe(ref.current)
    return () => io.disconnect()
  }, [show, margin])

  return (
    <div ref={ref} className={`lazy-mount ${show ? 'is-ready' : ''} ${className}`} style={show ? undefined : { width, height }}>
      {show ? children : null}
    </div>
  )
}

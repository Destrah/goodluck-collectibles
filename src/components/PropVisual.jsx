import React, { useEffect, useState } from 'react'

export default function PropVisual({ modelUrl, imageUrl, alt, className = '' }) {
  const [hasModel, setHasModel] = useState(false)

  useEffect(() => {
    let active = true
    fetch(modelUrl, { method: 'HEAD' })
      .then(response => {
        const contentType = response.headers.get('content-type') || ''
        if (active) setHasModel(response.ok && !contentType.includes('text/html'))
      })
      .catch(() => { if (active) setHasModel(false) })
    return () => { active = false }
  }, [modelUrl])

  if (!hasModel) return <img className={className} src={imageUrl} alt={alt} />

  return (
    <model-viewer
      className={className}
      src={modelUrl}
      alt={alt}
      camera-controls
      auto-rotate
      rotation-per-second="22deg"
      shadow-intensity="1"
      exposure="1.05"
      interaction-prompt="none"
    />
  )
}

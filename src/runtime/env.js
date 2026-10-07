// Embedded page: another resource shows this UI in an iframe (exports.<resource>:GetEmbedUrl). There
// GetParentResourceName may be missing or name the host, so the page's own nui:// / cfx-nui-<name> address decides.
const params = typeof window !== 'undefined' ? new URLSearchParams(window.location.search) : new URLSearchParams()
const nuiHost = typeof window !== 'undefined' && (window.location.protocol === 'nui:' ? window.location.hostname
  : window.location.hostname.startsWith('cfx-nui-') ? window.location.hostname.slice(8) : '')
export const isEmbedded = params.get('embed') === '1'
export const embedView = params.get('view') || 'admin'
export const embedTab = params.get('tab') || ''
// GetEmbedUrl with several tabs: only these are shown (the server still decides which the player may open)
export const embedTabs = (params.get('tabs') || '').split(',').map(tab => tab.trim()).filter(Boolean)
export const isFiveM = typeof window !== 'undefined' && (typeof window.GetParentResourceName === 'function' || (isEmbedded && !!nuiHost))

export function getResourceName() {
  if (!isFiveM) return 'meta-comic'
  if (isEmbedded) return params.get('resource') || nuiHost || window.GetParentResourceName()
  return window.GetParentResourceName()
}

// tells the page hosting the iframe that the user closed this UI
export function notifyEmbedHost(type, detail = {}) {
  if (!isEmbedded || typeof window === 'undefined' || window.parent === window) return
  window.parent.postMessage({ type, resource: getResourceName(), ...detail }, '*')
}

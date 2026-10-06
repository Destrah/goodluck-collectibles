import { getCollectibleType } from './registry.js'
import './tradingCards.jsx'
import './objects.jsx'

export default function CollectibleView({ item, ...props }) {
  const definition = getCollectibleType(item)
  if (!definition) return <div role="status">This collectible type is not installed.</div>
  const Renderer = definition.render
  return <Renderer item={item} {...props} />
}

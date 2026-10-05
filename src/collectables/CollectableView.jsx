import { getCollectableType } from './registry.js'
import './tradingCards.jsx'
import './objects.jsx'

export default function CollectableView({ item, ...props }) {
  const definition = getCollectableType(item)
  if (!definition) return <div role="status">This collectable type is not installed.</div>
  const Renderer = definition.render
  return <Renderer item={item} {...props} />
}

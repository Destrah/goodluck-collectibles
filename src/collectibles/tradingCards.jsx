import TradingCard from '../components/TradingCard'
import { registerCollectibleType } from './registry.js'
import { useResolvedAsset } from '../runtime/assets'
import ConditionOverlay from '../grading/ConditionOverlay'
import ProtectionShell from '../grading/ProtectionShell'
import { conditionStyle } from '../grading/condition.js'

// The back of a copy: its own centering (the back print is shifted inside the cut) and wear, in its sleeve / slab.
export function CardBack({ item, showProtection = true }) {
  const image = useResolvedAsset(item.backImage || '/img/Cards_Back.jpg', { showOriginalWhileLoading: true })
  const protection = showProtection ? (item.graded ? 'slab' : item.protection || 'none') : 'none'
  return <div className={`collectible-card-back-stage ${protection !== 'none' ? `is-protected is-${protection}` : ''}`}>
    {/* the same art underneath: where a miscut back print is shifted, its own border shows through instead of a gap */}
    <div className={`collectible-card-back-face ${item.condition ? 'has-condition' : ''}`} style={{ ...conditionStyle(item.condition, 'back'), ...(item.condition && image.url ? { backgroundImage: `url("${image.url}")` } : {}) }}>
      <img className="collectible-card-back" src={image.url} alt="Meta Comics card back" draggable="false" />
      <ConditionOverlay condition={item.condition} side="back" />
    </div>
    {protection !== 'none' && <ProtectionShell card={{ ...item, protection }} side="back" />}
  </div>
}

registerCollectibleType('trading_card', {
  label: 'Trading Card',
  render: ({ item, back, ...props }) => back ? <CardBack item={item} showProtection={props.showProtection} /> : <TradingCard card={item} {...props} />,
})

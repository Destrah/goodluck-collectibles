import TradingCard from '../components/TradingCard'
import { registerCollectableType } from './registry.js'
import { useResolvedAsset } from '../runtime/assets'

function CardBack({ item }) {
  const image = useResolvedAsset(item.backImage || '/img/Cards_Back.jpg', { showOriginalWhileLoading: true })
  return <img className="collectible-card-back" src={image.url} alt="Meta Comics card back" draggable="false" />
}

registerCollectableType('trading_card', {
  label: 'Trading Card',
  render: ({ item, back, ...props }) => back ? <CardBack item={item} /> : <TradingCard card={item} {...props} />,
})

import { isFiveM } from '../runtime/env'
import { artworkPasteProps, pickArtwork } from '../utils/compressImage.js'

// "Choose file" for artwork. FiveM's game browser doesn't support file dialogs (the first one may open, later
// ones never do), so in FiveM the field is a paste box instead: click it and press Ctrl+V with an image copied.
// `options` go to compressImage (maxEdge, onInfo...).
export default function ArtworkFileInput({ accept = 'image/*', onLoaded, options }) {
  if (!isFiveM) return <input className="file-input" type="file" accept={accept} onChange={e => pickArtwork(e.target, onLoaded, options)} />
  return <input className="file-input paste-target" value="" onChange={() => {}} placeholder="Click here, then Ctrl+V a copied image"
    aria-label="Paste an image" {...artworkPasteProps(onLoaded, options)} />
}

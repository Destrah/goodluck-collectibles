// Designs and opening animations for the 3D coin bags, plushie boxes and their outer cases. Kept separate
// from Container3D.js so the lab can list them without pulling three.js into the main bundle. The chosen
// look is saved on the container config (container.look / container.outer.look), so it reaches FiveM players
// and sealed items carry it in their snapshot.
export const CONTAINER_LOOKS = {
  bag: {
    styles: [
      { id: 'velvet', label: 'Black velvet pouch' },
      { id: 'satin', label: 'Meta satin pouch' },
      { id: 'leather', label: 'Leather coin purse' },
    ],
    animations: [
      { id: 'float', label: 'Peek inside, coins float out' },
      { id: 'pour', label: 'Tip over and pour out' },
      { id: 'pop', label: 'Shake and pop out' },
    ],
  },
  box: {
    styles: [
      { id: 'window', label: 'Collector window box' },
      { id: 'cube', label: 'Mystery flap cube' },
      { id: 'gift', label: 'Ribbon lid box' },
    ],
    animations: [
      { id: 'lift', label: 'Open the top, rise out' },
      { id: 'unfold', label: 'Walls fold down' },
      { id: 'burst', label: 'Shake and burst out' },
    ],
  },
  case: {
    styles: [
      { id: 'display', label: 'Counter display box' },
      { id: 'chest', label: 'Treasure chest' },
      { id: 'crate', label: 'Wooden shipping crate' },
    ],
    animations: [
      { id: 'lift', label: 'Open the lid, containers rise out' },
      { id: 'unfold', label: 'Walls fold down' },
      { id: 'burst', label: 'Shake and burst out' },
    ],
  },
}

export function normalizeLook(kind, look) {
  const options = CONTAINER_LOOKS[kind] || CONTAINER_LOOKS.box
  return {
    style: options.styles.some(entry => entry.id === look?.style) ? look.style : options.styles[0].id,
    animation: options.animations.some(entry => entry.id === look?.animation) ? look.animation : options.animations[0].id,
  }
}

export const innerLookKind = container => container?.kind === 'bag' ? 'bag' : 'box'

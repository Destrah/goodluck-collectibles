import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { resolve } from 'node:path'
import { defaultCards } from '../src/cardData.js'

const slug = value => String(value || 'item')
  .toLowerCase()
  .trim()
  .replace(/[^a-z0-9]+/g, '-')
  .replace(/^-|-$/g, '')

const input = process.argv[2]
const raw = input
  ? JSON.parse(await readFile(resolve(process.cwd(), input), 'utf8'))
  : defaultCards

const catalog = raw.map(card => ({
  ...card,
  id: slug(card.title),
  variants: (card.variants || []).map(variant => ({
    ...variant,
    id: `${slug(card.title)}--${slug(variant.name)}`,
    subjectLayers: (variant.subjectLayers || []).map((layer, index) => ({
      ...layer,
      id: `${slug(card.title)}--${slug(variant.name)}--layer-${index + 1}`,
    })),
  })),
}))

const output = resolve(process.cwd(), 'fivem', 'data', 'catalog.json')
await mkdir(resolve(process.cwd(), 'fivem', 'data'), { recursive: true })
await writeFile(output, JSON.stringify(catalog, null, 2))
console.log(`Wrote ${catalog.length} base cards to ${output}`)

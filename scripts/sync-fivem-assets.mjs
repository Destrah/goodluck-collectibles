import { cp, mkdir } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(process.cwd())
const source = resolve(root, 'public', 'img')
const destination = resolve(root, 'fivem', 'img')
await mkdir(destination, { recursive: true })
await cp(source, destination, { recursive: true, force: true })
console.log(`Synced public/img -> fivem/img`)

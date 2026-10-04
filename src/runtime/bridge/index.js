import { isFiveM } from '../env'
import { standaloneBridge } from './standalone'
import { fivemBridge } from './fivem'

export const bridge = isFiveM ? fivemBridge : standaloneBridge

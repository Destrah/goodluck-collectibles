import { isFiveM } from '../env'
import { standaloneStorage } from './standalone'
import { fivemStorage } from './fivem'

export const storage = isFiveM ? fivemStorage : standaloneStorage

import { printsOf, weightedPick, withPrint } from './prints.js'
import { withCollectibleKeys } from './legacyKeys.js'

export const COLLECTIBLES_KEY = 'meta-comic-collectibles-v1'
const copy = value => structuredClone(value)

export function loadCollectibles(storage = localStorage) {
  const raw = storage.getItem(COLLECTIBLES_KEY)
  if (!raw) return { definitions: [], sets: [], containers: {}, instances: [], sealed: [] }
  const data = withCollectibleKeys(JSON.parse(raw))
  if (!Array.isArray(data.definitions) || !Array.isArray(data.instances) || !data.containers || typeof data.containers !== 'object') throw new Error('Saved collectible data is invalid. Export or restore your browser data before proceeding.')
  data.sets ??= []
  data.sealed ??= []
  for (const typeId of ['plushie','challenge_coin']) {
    const existing = data.definitions.filter(item => item.collectibleType === typeId)
    if (!data.sets.some(set => set.collectibleType === typeId) && existing.length) data.sets.push({ id: `${typeId}-base`, collectibleType:typeId, name:'Base Set', itemIds:existing.map(item => item.id) })
    const container = data.containers[typeId]
    if (container) {
      container.setId ||= data.sets.find(set => set.collectibleType === typeId)?.id || ''
      if (typeId === 'challenge_coin' && container.id === 'coin_capsule') {
        container.id = 'coin_bag'; container.kind = 'bag'
        if (container.label === 'Coin Capsule') container.label = 'Coin Bag'
        if (container.count === 1) container.count = 3
      }
      container.outer ||= typeId === 'plushie' ? {id:'plushie_case',label:'Plushie Case',count:18} : {id:'coin_bag_box',label:'Coin Bag Box',count:10}
    }
  }
  return data
}

const isQuotaError = error => error?.name === 'QuotaExceededError' || error?.name === 'NS_ERROR_DOM_QUOTA_REACHED' || error?.code === 22 || error?.code === 1014

export function saveCollectibles(data, storage = localStorage) {
  const json = JSON.stringify(data)
  try {
    storage.setItem(COLLECTIBLES_KEY, json)
  } catch (error) {
    if (!isQuotaError(error)) throw error
    const mb = (json.length / 1024 / 1024).toFixed(1)
    throw new Error(`Not saved: collectibles need ${mb} MB but browser storage is full (about 5 MB). Use artwork URLs instead of uploaded files, or upload smaller images.`)
  }
  return copy(data)
}

export function saveDefinition(data, draft) {
  if (!draft.title?.trim()) throw new Error('Enter a name for this collectible.')
  const next = copy(data)
  const item = { ...copy(draft), title: draft.title.trim(), chanceWeight: Math.max(1, Number(draft.chanceWeight) || 1) }
  const index = next.definitions.findIndex(entry => entry.id === item.id)
  if (index < 0) next.definitions.push(item)
  else next.definitions[index] = item
  return next
}

export function openContainer(data, typeId, random = Math.random, id = () => crypto.randomUUID(), now = () => new Date().toISOString()) {
  const container = data.containers[typeId]
  if (!container) throw new Error('Save a container before opening it.')
  const membership = container.setId ? data.sets?.find(set => set.id === container.setId && set.collectibleType === typeId)?.itemIds || [] : container.itemIds || []
  const pool = data.definitions.filter(item => item.collectibleType === typeId && membership.includes(item.id))
  if (!pool.length) throw new Error('This container needs at least one saved collectible.')
  const pulled = Array.from({ length: Math.min(24, Math.max(1, Math.floor(Number(container.count) || 1))) }, () => {
    // two-stage roll like the server: the collectible by its weight, then one of its prints by the print's weight
    const selected = weightedPick(pool, random)
    return { ...withPrint(selected, weightedPick(printsOf(selected), random)), instanceId: id(), acquiredAt: now(), containerId: container.id, snapshotVersion: 2 }
  })
  return { data: { ...copy(data), instances: [...copy(data.instances), ...copy(pulled)] }, pulled }
}

export function openOuterContainer(data, typeId, id = () => crypto.randomUUID()) {
  const container = data.containers[typeId]
  if (!container?.outer) throw new Error('Save the container and its outer box first.')
  const sealed = Array.from({length: Math.min(100,Math.max(1,Math.floor(Number(container.outer.count) || 1)))}, () => ({
    instanceId:id(), collectibleType:typeId, containerSnapshot:copy(container), label:container.label,
  }))
  return { data:{...copy(data), sealed:[...(data.sealed || []).map(copy), ...copy(sealed)]}, sealed }
}

export function openSealedContainer(data, instanceId, random = Math.random, id = () => crypto.randomUUID()) {
  const sealed = (data.sealed || []).find(item => item.instanceId === instanceId)
  if (!sealed) throw new Error('This sealed container is no longer available.')
  const result = openContainer({...data,containers:{...data.containers,[sealed.collectibleType]:sealed.containerSnapshot}},sealed.collectibleType,random,id)
  result.data.containers = copy(data.containers)
  result.data.sealed = data.sealed.filter(item => item.instanceId !== instanceId).map(copy)
  return result
}

export function saveSet(data, draft) {
  if (!draft.name?.trim()) throw new Error('Give the set a name.')
  const members = new Set(data.definitions.filter(item => item.collectibleType === draft.collectibleType).map(item => item.id))
  if (draft.itemIds.some(id => !members.has(id))) throw new Error('Sets can only contain saved collectibles of their type.')
  const next = copy(data)
  const set = {...copy(draft),name:draft.name.trim(),itemIds:[...new Set(draft.itemIds)]}
  next.sets = [...(next.sets || []).filter(item => item.id !== set.id),set]
  return next
}

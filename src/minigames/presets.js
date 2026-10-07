// Speed scaling for the admin Minigames tab (the same rules as testScale in client/minigames.lua): moving parts
// get faster and time limits shorter. Counts (pins, wires, length, mistakes) never change.
const FASTER = ['speed']
const SHORTER = ['time', 'seconds', 'show', 'perKey', 'minutes', 'lose', 'life']

export function scalePreset(preset, speed = 1) {
  const factor = Math.max(0.1, Number(speed) || 1)
  const out = { ...preset }
  for (const key of FASTER) if (typeof out[key] === 'number') out[key] = out[key] * factor
  for (const key of SHORTER) if (typeof out[key] === 'number') out[key] = Math.max(0.5, out[key] / factor)
  return out
}

// built-in presets shown by the standalone browser lab (FiveM sends Config.Minigames instead)
export const DEMO_PRESETS = [
  { name: 'lockpick_easy', type: 'builtin', game: 'lockpick', level: 'easy', pins: 3, speed: 0.8, zone: 0.22, time: 30, mistakes: 4 },
  { name: 'lockpick_medium', type: 'builtin', game: 'lockpick', level: 'medium', pins: 4, speed: 1.1, zone: 0.16, time: 25, mistakes: 3 },
  { name: 'lockpick_hard', type: 'builtin', game: 'lockpick', level: 'hard', pins: 6, speed: 1.5, zone: 0.1, time: 25, mistakes: 2 },
  { name: 'wires_easy', type: 'builtin', game: 'wires', level: 'easy', wires: 4, time: 25, mistakes: 2 },
  { name: 'wires_medium', type: 'builtin', game: 'wires', level: 'medium', wires: 6, time: 20, mistakes: 1 },
  { name: 'wires_hard', type: 'builtin', game: 'wires', level: 'hard', wires: 8, time: 18, mistakes: 0 },
  { name: 'keypad_easy', type: 'builtin', game: 'keypad', level: 'easy', length: 4, show: 3, time: 15, rounds: 1 },
  { name: 'keypad_medium', type: 'builtin', game: 'keypad', level: 'medium', length: 6, show: 3, time: 12, rounds: 2 },
  { name: 'keypad_hard', type: 'builtin', game: 'keypad', level: 'hard', length: 8, show: 2.5, time: 10, rounds: 3 },
  { name: 'sequence_easy', type: 'builtin', game: 'sequence', level: 'easy', keys: 6, perKey: 1.6, rounds: 1 },
  { name: 'sequence_medium', type: 'builtin', game: 'sequence', level: 'medium', keys: 8, perKey: 1.2, rounds: 2 },
  { name: 'sequence_hard', type: 'builtin', game: 'sequence', level: 'hard', keys: 10, perKey: 0.9, rounds: 2 },
  { name: 'simon_easy', type: 'builtin', game: 'simon', level: 'easy', start: 3, length: 5, show: 0.6, time: 10 },
  { name: 'simon_medium', type: 'builtin', game: 'simon', level: 'medium', start: 3, length: 7, show: 0.5, time: 8 },
  { name: 'simon_hard', type: 'builtin', game: 'simon', level: 'hard', start: 4, length: 10, show: 0.35, time: 6 },
  { name: 'grid_easy', type: 'builtin', game: 'grid', level: 'easy', size: 4, cells: 4, rounds: 2, show: 1.8, time: 12, mistakes: 2 },
  { name: 'grid_medium', type: 'builtin', game: 'grid', level: 'medium', size: 5, cells: 5, rounds: 3, show: 1.5, time: 10, mistakes: 1 },
  { name: 'grid_hard', type: 'builtin', game: 'grid', level: 'hard', size: 6, cells: 7, rounds: 3, show: 1.1, time: 8, mistakes: 0 },
  { name: 'safe_easy', type: 'builtin', game: 'safe', level: 'easy', numbers: 2, tolerance: 3, speed: 25, time: 45, mistakes: 3 },
  { name: 'safe_medium', type: 'builtin', game: 'safe', level: 'medium', numbers: 3, tolerance: 2, speed: 30, time: 40, mistakes: 2 },
  { name: 'safe_hard', type: 'builtin', game: 'safe', level: 'hard', numbers: 4, tolerance: 1, speed: 40, time: 40, mistakes: 1 },
  { name: 'reaction_easy', type: 'builtin', game: 'reaction', level: 'easy', grid: 3, targets: 8, life: 1.2, traps: 0.15, misses: 3 },
  { name: 'reaction_medium', type: 'builtin', game: 'reaction', level: 'medium', grid: 4, targets: 12, life: 0.9, traps: 0.25, misses: 2 },
  { name: 'reaction_hard', type: 'builtin', game: 'reaction', level: 'hard', grid: 5, targets: 16, life: 0.65, traps: 0.35, misses: 1 },
  { name: 'order_easy', type: 'builtin', game: 'order', level: 'easy', count: 8, time: 15, shuffle: false, mistakes: 1 },
  { name: 'order_medium', type: 'builtin', game: 'order', level: 'medium', count: 12, time: 15, shuffle: false, mistakes: 0 },
  { name: 'order_hard', type: 'builtin', game: 'order', level: 'hard', count: 10, time: 14, shuffle: true, mistakes: 0 },
  { name: 'circle_easy', type: 'builtin', game: 'circle', level: 'easy', zones: 3, zone: 36, speed: 0.45, time: 20, mistakes: 2 },
  { name: 'circle_medium', type: 'builtin', game: 'circle', level: 'medium', zones: 4, zone: 28, speed: 0.6, time: 20, mistakes: 1 },
  { name: 'circle_hard', type: 'builtin', game: 'circle', level: 'hard', zones: 6, zone: 20, speed: 0.8, time: 20, mistakes: 0 },
  { name: 'skill_medium', type: 'ox_skillcheck', level: 'medium', difficulty: ['easy', 'medium', 'medium'], inputs: ['w', 'a', 's', 'd'], available: false },
]

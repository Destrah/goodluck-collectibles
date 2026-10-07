import React, { useEffect, useMemo, useState } from 'react'
import { bridge, isFiveM } from '../runtime'
import Minigame from './Minigame'
import { scalePreset } from './presets'
import './minigameTest.css'

// Admin "Minigames" tab: try every Config.Minigames preset at a chosen speed. Built-in games play right here;
// presets from other resources (ox_lib, ps-ui, ...) run in game: the menu closes, the game runs, and the menu
// opens again on this tab with the result. Speed only changes this test, never the config.
const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 2, 3]
const LOG_KEY = 'metaComic:minigameTestLog'
const readLog = () => { try { return JSON.parse(sessionStorage.getItem(LOG_KEY) || '[]') } catch { return [] } }
const writeLog = log => { try { sessionStorage.setItem(LOG_KEY, JSON.stringify(log.slice(0, 30))) } catch { /* private mode */ } }
const describe = params => Object.entries(params || {}).filter(([key]) => !['type', 'level', 'game', 'name', 'available', 'id'].includes(key))
  .map(([key, value]) => `${key} ${typeof value === 'object' ? JSON.stringify(value) : Math.round(Number(value) * 100) / 100 || value}`).join(' · ')

export default function MinigameTestPanel() {
  const [presets, setPresets] = useState([])
  const [message, setMessage] = useState('')
  const [speed, setSpeed] = useState(1)
  const [filter, setFilter] = useState('')
  const [playing, setPlaying] = useState(null)
  const [log, setLog] = useState(readLog)

  const addLog = entry => setLog(current => { const next = [entry, ...current].slice(0, 30); writeLog(next); return next })

  useEffect(() => {
    bridge.getMinigames().then(result => {
      setPresets(result.presets || [])
      const last = result.lastResult
      // a test that ran in game comes back here when the menu reopens
      if (last && !readLog().some(entry => entry.at === last.at)) addLog(last)
    }).catch(error => setMessage(error?.message || String(error)))
  }, [])

  // Escape gives up the game being tested instead of closing the whole menu
  useEffect(() => {
    if (!playing) return undefined
    const onKey = event => { if (event.key === 'Escape') event.preventDefault() }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  }, [playing])

  const shown = useMemo(() => presets.filter(preset => !filter || `${preset.name} ${preset.type} ${preset.game || ''} ${preset.level || ''}`.toLowerCase().includes(filter.toLowerCase())), [presets, filter])

  const test = async preset => {
    setMessage('')
    if ((preset.type || 'builtin') === 'builtin') {
      setPlaying({ preset, config: { ...scalePreset(preset, speed), id: `test-${Date.now()}` }, started: performance.now() })
      return
    }
    if (!isFiveM) { setMessage(`${preset.name} uses ${preset.type}, which only runs in game.`); return }
    if (!preset.available) { setMessage(`${preset.type} isn't running, so the game would fall back to the built-in lockpick (${preset.level || 'medium'}).`) }
    try { await bridge.testMinigame({ name: preset.name, speed }) } catch (error) { setMessage(error?.message || String(error)) }
  }
  const finished = success => {
    const { preset, started } = playing
    addLog({ at: Date.now(), name: preset.name, speed, success, seconds: Math.round((performance.now() - started) / 100) / 10 })
    setPlaying(null)
  }

  return (
    <section className="management-page minigame-test-page">
      <div className="management-heading">
        <div><span className="eyebrow">Restricted FiveM tools</span><h2>Minigames</h2><p>Try each skill check from Config.Minigames at different speeds. The speed here is only for testing; change a preset's numbers in config.lua to keep them.</p></div>
      </div>
      {message && <div className="management-message">{message}</div>}

      <div className="management-card mgt-speed">
        <div className="mgt-speed-row">
          <strong>Speed {speed}×</strong>
          <input type="range" min="0.25" max="4" step="0.05" value={speed} onChange={event => setSpeed(Number(event.target.value))} aria-label="Speed" />
        </div>
        <div className="mgt-speed-buttons">
          {SPEEDS.map(value => <button key={value} className={speed === value ? 'primary' : 'ghost'} onClick={() => setSpeed(value)}>{value}×</button>)}
        </div>
        <p className="mgt-note">Faster means moving parts speed up and time limits shrink (time, seconds, show, per key). Pins, wires, code length and mistakes stay as configured.</p>
      </div>

      <div className="mgt-grid">
        <div className="management-card">
          <div className="records-card-head"><h3>Presets</h3><input className="records-filter" placeholder="Search name, type, level…" value={filter} onChange={event => setFilter(event.target.value)} /></div>
          {!presets.length && !message && <p className="records-empty">Loading presets…</p>}
          {shown.map(preset => {
            const scaled = scalePreset(preset, speed)
            return (
              <div key={preset.name} className="mgt-preset">
                <div className="mgt-preset-info">
                  <strong>{preset.name}</strong>
                  <span>{preset.type || 'builtin'}{preset.game ? ` · ${preset.game}` : ''}{preset.level ? ` · ${preset.level}` : ''}{(preset.type || 'builtin') !== 'builtin' && !preset.available ? ' · not running' : ''}</span>
                  <em>{describe(scaled)}</em>
                </div>
                <button className="primary" disabled={!!playing} onClick={() => test(preset)}>Test</button>
              </div>
            )
          })}
        </div>

        <div className="management-card">
          <div className="records-card-head"><h3>Results</h3><button className="ghost" disabled={!log.length} onClick={() => { setLog([]); writeLog([]) }}>Clear</button></div>
          {!log.length && <p className="records-empty">No tests yet.</p>}
          <ol className="mgt-log">
            {log.map(entry => (
              <li key={entry.at} className={entry.success ? 'won' : 'lost'}>
                <b>{entry.success ? 'Passed' : 'Failed'}</b> {entry.name} at {entry.speed}×{entry.seconds != null ? ` in ${entry.seconds}s` : ''}
              </li>
            ))}
          </ol>
        </div>
      </div>

      {playing && <Minigame key={playing.config.id} config={playing.config} onResult={finished} />}
    </section>
  )
}

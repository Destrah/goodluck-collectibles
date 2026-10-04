import React, { useEffect, useState } from 'react'
import { TEAR_INFO, FAN_INFO, RANDOM_INFO, BASE_SECONDS, TEAR_KEYS } from './PackOpenScene'
import {
  MIN_SPEED,
  TEARS,
  FANS,
  clampSpeed,
  defaultPackPrefs,
  loadPackLimits,
  loadPackPrefs,
  savePackPrefs,
} from '../runtime/packPrefs'

export default function PackOptions({ onClose }) {
  const [prefs, setPrefs] = useState(defaultPackPrefs)
  const [maxSpeed, setMaxSpeed] = useState(3)
  const [ready, setReady] = useState(false)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    let alive = true
    ;(async () => {
      const limits = await loadPackLimits()
      const current = await loadPackPrefs(limits.maxSpeed)
      if (!alive) return
      setMaxSpeed(limits.maxSpeed)
      setPrefs(current)
      setReady(true)
    })()
    return () => { alive = false }
  }, [])

  const update = patch => {
    setSaved(false)
    setPrefs(current => ({ ...current, ...patch, speed: clampSpeed(patch.speed ?? current.speed, maxSpeed) }))
  }

  const save = async () => {
    setSaving(true)
    const clean = await savePackPrefs(prefs, maxSpeed)
    setPrefs(clean)
    setSaving(false)
    setSaved(true)
  }

  const seconds = ((prefs.tear === 'random'
    ? TEAR_KEYS.reduce((sum, key) => sum + BASE_SECONDS[key], 0) / TEAR_KEYS.length
    : BASE_SECONDS[prefs.tear] || BASE_SECONDS.seam) / prefs.speed).toFixed(1)

  return (
    <div className="pack-options-overlay" role="dialog" aria-modal="true" aria-label="Card pack opening options">
      <section className="pack-options-panel">
        <div className="pack-options-head">
          <div>
            <span className="eyebrow">Player preferences</span>
            <h2>Pack opening options</h2>
            <p>Choose how your booster packs open. New players default to Random for both animation choices.</p>
          </div>
          <button type="button" className="ghost pack-options-close" onClick={onClose}>Close</button>
        </div>

        <div className="pk-settings pack-options-settings">
          <div className="pk-set-group">
            <span className="pk-set-title">Tear style</span>
            <div className="pk-set-row">
              {TEARS.map(key => {
                const info = key === 'random' ? RANDOM_INFO : TEAR_INFO[key]
                return <button key={key} type="button" className={`pk-opt ${prefs.tear === key ? 'selected' : ''}`} onClick={() => update({ tear: key })} disabled={!ready || saving} title={info.short}>{info.label}</button>
              })}
            </div>
            <small className="pk-set-desc">{(prefs.tear === 'random' ? RANDOM_INFO : TEAR_INFO[prefs.tear]).short}</small>
          </div>

          <div className="pk-set-group">
            <span className="pk-set-title">Card fan-out</span>
            <div className="pk-set-row">
              {FANS.map(key => {
                const info = key === 'random' ? RANDOM_INFO : FAN_INFO[key]
                return <button key={key} type="button" className={`pk-opt ${prefs.fan === key ? 'selected' : ''}`} onClick={() => update({ fan: key })} disabled={!ready || saving} title={info.short}>{info.label}</button>
              })}
            </div>
            <small className="pk-set-desc">{(prefs.fan === 'random' ? RANDOM_INFO : FAN_INFO[prefs.fan]).short}</small>
          </div>

          <div className="pk-set-group pk-set-speed">
            <span className="pk-set-title">Opening speed <b>{Number(prefs.speed.toFixed(2))}×</b></span>
            <input
              type="range"
              min={MIN_SPEED}
              max={maxSpeed}
              step={0.25}
              value={prefs.speed}
              onChange={event => update({ speed: Number(event.target.value) })}
              disabled={!ready || saving || maxSpeed <= MIN_SPEED}
              aria-label="Pack opening speed"
            />
            <small className="pk-set-desc">1× is the original pace · up to {maxSpeed}× · about {seconds} s per pack</small>
          </div>
        </div>

        <div className="pack-options-footer">
          <span className={saved ? 'pack-options-saved is-visible' : 'pack-options-saved'}>{saved ? 'Saved for this player' : 'Preferences are saved per player'}</span>
          <div>
            <button type="button" className="ghost" onClick={onClose}>Cancel</button>
            <button type="button" className="primary" onClick={save} disabled={!ready || saving}>{saving ? 'Saving…' : 'Save options'}</button>
          </div>
        </div>
      </section>
    </div>
  )
}

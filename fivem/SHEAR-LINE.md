# Shear Line minigames

Lockpicking uses the latest supplied fixed-tension engine. Cabinet drilling now uses the supplied drill engine rather than a key-sequence game. Existing `drill_hard` sequence presets are routed to the drill game for compatibility with saved configs. Other unrelated minigames remain as configured.

Configure presets in `Config.Minigames`. Both `game = 'lockpick'` and `game = 'drill'` accept `theme = 'padlock'` or `theme = 'camlock'`. Padlocks show their shackle seated in the body before it lifts and swivels; cam locks show a silver barrel and turning rear cam. No key is drawn. The cylinder still rotates during the success sequence. The admin Minigames tab has an appearance selector for testing both lock themes without saving a config change.

Lockpick tuning: `pins` (2–10), `tol` (pin tolerance), `band` (tension window width), `spools`, `showBand`, `time` in seconds. Existing moving-bar fields such as `zone`, `speed` and `mistakes` do not affect this engine. Tension does not drift.

Drill tuning: `pins` (2–10), `tol` (height tolerance), `angTol` (angle tolerance), `wob` (vibration), `hard` (hardened pin count), `oil` (virtual cooling charges), `time` in seconds. Cooling charges are game mechanics; they do not consume separate inventory items. Existing server tool and break-chance checks still apply. Use W/S to raise/lower, A/D to level, Space or click to drill, the wheel/slider to adjust pressure, and R to cool.

The new `game = 'grinder'` accepts `target = 'shackle'` or `target = 'bolts'`. Tune `cuts` (1–2 for shackles, 1–8 for bolts), `tol` (alignment tolerance), `feed` (cutting rate), `heatRate`, `wearRate`, `wob`, `drift`, `angleDrift`, `angleTol`, and `time`. Higher feed speeds up cutting. Higher heat/wear/wob or lower tolerance increases difficulty. Maintain position with A/D or the mouse and keep the disc square with Q/E. Holding a stationary cursor does not anchor a running disc: pressure causes persistent position drift and tilt. `drift` controls movement under load; `angleDrift` controls tilt under load; `angleTol` is the allowed angle in degrees. Set either drift value to 0 to disable that force. The handle displays the angle and safe window, and its actual tilt matches the angle: perfectly horizontal is zero degrees. Vertical mouse movement raises/lowers the handle, with Q/E available as an alternative. Set `mouseTilt` (default 0.25 degrees per canvas pixel, range 0–1) to change sensitivity or use 0 to disable mouse tilt. A disc outside the position or angle tolerance stops cutting; a tilted disc adds wear. Hold Space/click to cut, use the pressure slider or wheel, and release to cool. Escape cancels all three games, including during the unlock animation.

Ready-made presets: `drill_easy`, `drill_medium`, `drill_hard`, `grinder_easy`, `grinder_medium`, `grinder_hard`, `grinder_bolts`, and `lockpick_cam_medium`. The grinder is available in the admin test lab and through the existing action preset/export interface. To use it for a particular cutting action, assign its `Minigame` to a grinder preset and configure the action's required item, animation, duration and failure rules separately; the UI itself never removes tools or awards items.

```lua
local success = exports['<resource>']:Minigame('grinder_bolts')
-- A custom preset can be configured without changing the game engine:
-- Config.Minigames.my_cut = {
--   type = 'builtin', game = 'grinder', level = 'medium', target = 'bolts',
--   cuts = 3, time = 90, tol = 12, feed = 24, heatRate = 17, wearRate = 12, wob = 4
-- }
```

Deploy the updated client minigame runner, merged config presets and rebuilt `web` together. Both FiveM NUI and the standalone Vite lab use the same isolated game documents. The game benches scale to fit the viewport with all controls visible and without scrollbars. No separate minigame resource is required.


## Skimmer wiring

`Crime.InstallSkimmer.Minigame = 'skimmer_medium'` runs the wiring bench before installation. Existing server tool, range and transaction checks remain authoritative.

Move the cutter jaws over the requested labeled wire and click. Hover the stripper over its end to snap on, click to close its jaws into the green depth band, then pull the mouse away to remove insulation. Drag the bare end to its matching pad. It stays exactly where released; a misplaced end can be dragged again. Press R during soldering to reposition it (this resets that joint).

Choose `solderMode` in a preset or at the call site:
- `heat_feed` (default): hold left mouse/Space to heat both surfaces, then right mouse/F to feed solder while in the heat band. Feeding too early makes a cold joint.
- `trace`: hold heat and cover all eight segments of the ring evenly. Staying at one spot cannot complete the joint.
- `steady`: keep the iron tip centered and hold heat within the band until the bead is complete.

All modes require the iron to contact the joint, can overheat, and require cooling before proceeding. `drift = true` enables tool movement under heat in any mode; default is false. `driftStrength` controls its speed (0–35). Correct drift by moving the mouse. Releasing heat cools the joint. Escape cancels; losing focus releases tools.

```lua
local success = exports['<resource>']:Minigame('skimmer_medium', {
    solderMode = 'trace', drift = true, driftStrength = 12
})
-- Internal function uses the same optional second argument:
local success = MetaComic.RunMinigames('skimmer_medium', {
    solderMode = 'steady', drift = false
})
-- A complete inline preset also works:
local success = exports['<resource>']:Minigame({
    type = 'builtin', game = 'skimmer', level = 'easy', wires = 2,
    time = 120, solderMode = 'heat_feed', drift = false
})
```

Overrides are per invocation and do not mutate Config.Minigames. A list/random selection accepts the same overrides. Presets remain configurable in Config.Minigames; the admin and standalone test lab have solder-mode and drift selectors that only affect the test.

Tune `wires` (1–6), `time` (seconds), `mistakes` (failure at this count), `stripTol` (jaw-depth tolerance), `stripClick` (depth per click, default 8), `snapRelease` (canvas pixels to disengage, default 65), `placementTol` (pad tolerance, default 12), `solderTime`, `heatLow`, `heatHigh`, `heatRate` and `coolRate`. Legacy `stripSpeed` is accepted but jaw movement now uses clicks. Colors have labels for matching without relying solely on color vision.

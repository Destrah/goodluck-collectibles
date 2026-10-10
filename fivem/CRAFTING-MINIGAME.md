# Card production

Restart the updated resource after copying its Lua files and rebuilt `web` folder. No SQL migration or extra resource is required.

Open `/collectiblesadmin` → **Crafting**, select a recipe with **Makes → Booster pack / box → Booster pack**, and enable **Interactive card production**. Edit the draft and click **Save recipes**. **Revert** discards unsaved edits. Production settings require `Config.Crafting.MinigameAce` (default `metacomic.manage`); recipe saves check this permission on the server too.

Choose precision, production cutter or random. Set sheet columns/rows (1–10 each, maximum 60 cells; total must be divisible by five), error limit, flaw probability and time limit. Every five printed cells form one visible pack. Players print, inspect, cut strips, individually move/rotate strips for card cuts, load five cards per wrapper, fold all wrappers, and then align/seal all packs. Multiple aligned strips can be cut in one blade cycle. There are no stage-skipping controls. Cut pieces, stock, wrappers, packs and the sealer stay within the table.

The open wrapper shows silver lining and crimped top/bottom ridges. Two wings show the actual pack-back halves as they fold inward; folded packs expose the rear seam. Finished packs flip to their front artwork. Sound can be toggled during the game.

**Packs awarded per completed batch** is independent of the number of visible packs. Ingredients and money are charged once per batch. Adjust the recipe's ingredients accordingly; enabling a larger sheet does not silently change your costs. The workbench asks for a **card set** and **packs requested**. Recipes are shared across sets; an old recipe’s set field does not restrict production. One session produces up to the configured batch award. For example, requesting 7 packs with a 3-pack award runs three sessions with base payouts of 3, 3, and 1; the default bulk milestone adds one pack on the second session, and perfect-batch bonuses are extra and do not reduce the requested count. A final partial batch still costs a full batch. Before starting, the server checks room for the remaining requested packs and every possible batch bonus, using the selected set’s exact inventory metadata. Each batch rechecks capacity, costs and permission; cancellation/failure stops the queue and retains previously completed rewards. All packs use the selected set and its normal opening odds: print-sheet artwork is a visual crafting task, not a way to override the set's guaranteed pulls or choose pack contents.

**Extra packs** is the fixed, optional bonus for a completed batch with zero errors inside **Perfect batch bonus time limit**. Set extra packs to 0 to disable. The server uses its own elapsed time and saved reward settings, rejects incomplete/expired/too-fast or replayed completions, and rechecks inventory, capacity, station and permission before charging/granting. Failure/cancellation gives no items and consumes no ingredients, matching the existing crafting transaction behavior. As with other client-side FiveM skill checks, UI performance reports are not anti-cheat proof.

Default config recipe `booster_pack`: random cutter, 5 × 3 sheet, 3 packs, 6-error failure threshold, 15-minute limit, 50% obvious-flaw probability, and 1 bonus pack for zero errors within 180 seconds. Existing saved recipes take priority over config: enable production in the dashboard for those recipes. Other recipes retain their progress bars.

Recipe settings remain a bounded settings record in memory/persistence through the existing explicit `MetaComic.Settings.set` editor save. A craft does not write settings or growing logs to the database. These settings are not available as employee pricing controls.

## Client export

Call from a client thread/coroutine; it waits until success, failure or cancellation:

```lua
local success, detail = exports['YOUR_RESOURCE_NAME']:CraftingMinigame({
    setId = 'base', -- omitted: server's current default set; reads current saved cards
    cutter = 'industrial', -- 'bench', 'industrial', or 'random'
    cols = 5, rows = 3, time = 900, maxErrors = 6, flawChance = 0.5,
})
-- detail: errors, seconds, packs, printed, inspected, cuts, folds, seals
if success then
    -- Notify YOUR server of its pending crafting session; recheck costs and grant there.
end
```

The export is a UI-only skill check and never grants items. Optional `cards` is a list of resolved card print snapshots (including `variantId`, layout, accent, artwork and masks) instead of loading a set. Optional `packFront`/`packBack` can supply wrapper art URLs. Remote card artwork and masks use the same asset resolver and card renderer as the rest of the UI.

`exports['YOUR_RESOURCE_NAME']:Minigame({type='builtin',game='crafting',...})` also works but returns a boolean only. Recipe-driven production automatically uses the richer result report.

Choose **Test production card set**, then test draft settings with **Test draft production · no rewards** in Crafting. The Minigames tab also has `crafting_precision` and `crafting_production` presets, in FiveM and standalone Vite mode. Tests never grant rewards.

The Minigames tab also has a **Production card set** selector. Both testing surfaces use the selected set exclusively; unknown/empty sets fail instead of substituting unrelated cards. Sheets sample the whole selected set, including its configured variants/prints. Sheet stock keeps matching edges; different card identities in that edge group are used before repetition. Small matching groups may necessarily repeat. FiveM samples the whole set on the server, then sends only the requested sheet and a few alternate-stock previews with latent events (a 15-card sheet normally needs at most 20 print snapshots). Card faces, masks and effect canvases stay mounted when cuts split a piece or strips rotate.

To start the real recipe workflow from another client resource:

```lua
exports['YOUR_RESOURCE_NAME']:StartCrafting(stationIndex, 'booster_pack', 7, 'your_set_id')
```

The server validates station access, set, quantity and each batch transaction. `OpenCrafting(stationIndex)` opens the normal set/quantity picker. The UI-only `CraftingMinigame({setId=...})` export remains available for custom workflows.

## Bulk orders and larger sheets

Production now defaults to one guaranteed extra pack for every five **requested packs completed within the same order**, up to five guaranteed extras. For example, 10 requested packs award 12 even with minor mistakes, plus any separate perfect-batch extras. Bonus packs never count toward the next milestone. Each milestone is paid with the successful batch that crosses it; failure/cancellation cannot remove completed batches or milestone extras already paid. Costs still apply per completed batch. There is no discount or extra material charge for bonus packs.

In `/collectiblesadmin` → Crafting → Interactive card production, set **Completed packs per bulk bonus milestone**, **Guaranteed extra packs per milestone**, and **Maximum bulk extra packs per order**. Set either extra count or cap to zero to disable. **Give larger sheets proportionally more time** scales the configured perfect bonus allowance above 15 cards: a 180-second allowance becomes 360 seconds for 30 cards, capped by the game's time limit. This affects the perfect bonus deadline, not the game's overall limit or minimum completion time. Mistakes on one batch do not carry into the next batch's perfect check. All these fields require the management ACE and explicit Save; existing recipe values are preserved and missing new options use the defaults.

The server checks capacity for the remaining base packs, maximum perfect extras, and all remaining milestone extras before starting. Bulk progress lives only in the active server crafting session; no per-step database writes are introduced.

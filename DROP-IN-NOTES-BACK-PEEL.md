# Pack opening update — progressive drop-in (cumulative)

Copy everything in this zip over your `Trading Cards` folder, then rebuild:

```powershell
npm run build:fivem   # FiveM NUI -> fivem/web
npm run dev           # standalone
```

Includes every earlier Back peel / flip-effects / overlay change, so it is safe whatever you applied before.

## Latest round (v11): one Fivemanage icon per card + rarity, deleted icons re-uploaded
- Icons are now made per **base card + rarity**, not per variant: a card can have at most 5 icons (one per rarity), shared by
  every variant and every copy of it. Giving card items or opening packs never creates new uploads; only a card + rarity that
  has no icon yet (or whose look was edited in-game) is uploaded, once.
- Your old per-variant entries in `fivem/data/card_icons.json` are dropped on start (the console says how many) and the
  per-rarity icons are made instead.
- **Deleted on Fivemanage?** On every start the saved urls are checked; any that no longer exist are uploaded again and the
  card items switch to the new url. `cardicons` in the server console runs the same check any time.
- Why you saw no new uploads after deleting: the server still had the old urls saved (and the game had the pictures cached).

## Latest round (v10): no duplicate uploads
- Each card print + look is uploaded to Fivemanage **once**: the upload is skipped when that print already has a url, when an
  identical picture was already uploaded, or when it was already sent this session. File names are now fixed per print + look
  (`metacard_<print>_<look>.webp`) instead of time-stamped.
- Fixed the cause of the repeats: when a picture file couldn't be written into ox_inventory's images folder, the same card
  was redrawn and re-uploaded over and over. Writes are now verified, and a failed one is logged once and not retried until
  the next start.
- If your Fivemanage account uses a custom CDN domain, the plain `r2.fivemanage.com` url is used when ox wouldn't trust the CDN one.
- Duplicates already on Fivemanage can be deleted from the dashboard; `fivem/data/card_icons.json` lists the url each card uses.

## Latest round (v9): per-card icons that survive ox_inventory's url check
v8 stopped giving ox_inventory urls it deletes, but that meant rarity icons only. Now, when your ox_inventory would delete the
Fivemanage urls (`inventory:webhook` set), each print's icon is also saved as a picture file in `ox_inventory/web/images` and
used through `metadata.image`, which ox doesn't check, so it stays put when the card is moved.
- New / redrawn icons show **after the next server restart** (FiveM only serves files that existed when ox_inventory started).
  Until then that card shows its rarity icon. Restart once after installing this and every existing print has its picture.
- To get Fivemanage icons instantly instead, remove `inventory:webhook` from server.cfg (ox only uses it for Discord logs of
  picture urls) or update ox_inventory to 2.45.1+. The script picks the url route automatically when ox will keep the urls.
- The server console prints one `card pictures: ...` line on start saying which route is active.
- v9.1: picture files go wherever your `inventory:imagepath` convar points (default `ox_inventory/web/images`), and the console
  says how many per-card pictures are ready this session.
Files: `fivem/server/main.lua`, `fivem/client/main.lua`, `src/utils/cardIcon.js`, `src/App.jsx`, `fivem/README.md`.

## Latest round (v8): card icons that stick + automatic Fivemanage icons
**Why card items showed the old picture / reverted after moving:** with the convar `inventory:webhook` set, ox_inventory
checks item picture urls and deletes the ones it doesn't trust. Before ox_inventory **2.45.1** that is every url except
`i.imgur.com`, so the `nui://` rarity icon was removed when the card item was created (you saw the item's default picture).
Viewing a card re-set the url; ox showed it, then removed it on the server, so moving the card brought the old picture back.

**Fix:** the server now mirrors ox_inventory's rules (version, `inventory:webhook`, `inventory:validhosts`) and only uses a url
ox will keep. Otherwise it uses `metadata.image` with the rarity pictures, which it copies into `ox_inventory/web/images` for
you. **Restart the server once** after the first start with this version so players download those pictures. The console
says which case you're in. Card items already in inventories are corrected when their owner joins.
For per-card Fivemanage icons on your server: update ox_inventory to 2.45.1+ (or remove `inventory:webhook`).

**Automatic icons (`Config.CardIcons.Mode = 'upload'`):** every catalog print without a current icon is drawn and uploaded:
on resource start, on player join, when the catalog is saved in-game (new cards, and edited cards are redrawn), and on pulls.
Inventories update straight away. `cardicons` in the server console retries prints that failed 3 times.
Files: `fivem/server/main.lua`, `fivem/client/main.lua`, `fivem/config.lua` (comments only), `fivem/README.md`,
`src/App.jsx`, `src/runtime/bridge/fivem.js`. Standalone is unchanged apart from the shared code still building.

## Earlier rounds (standalone + FiveM)
| Problem | Fix |
| --- | --- |
| Flipped card text tiny and fuzzy | Reveal row now renders the **full-size card layout** (readable type) and scales the row with a plain 2D transform, centred on whole pixels. Once a flip finishes the card drops its 3D layers (`settled`), so the face renders flat and sharp. In the FiveM overlay the cards sit at 1:1 (340 px wide) on a 1080p screen. |
| Rarity glow / rays missing in FiveM | FiveM's embedded Chromium is older than `color-mix()` and the individual `translate/rotate/scale` properties. The effects now use pre-computed `rgba` colours and plain `transform`. The card frame's own `color-mix` borders got plain fallbacks too. |
| 3D pack cut in half | The 3D layer is no longer clipped to the stage: it spans the full screen width and well above / below the stage, and the camera is offset so the pack still sits on the stage centre. |
| No card items after opening | `GiveCardItems` now defaults to `true`: 5 `tradingcard` items per pack with name / print / rarity labels (and card art in ox_inventory). Given once all cards are flipped or the opening is closed (2-minute fallback). Free `/cardpack` test opens give no items. Using a card item shows it large on screen. |
| Character animation too short | The pack prop + hand animation now starts with the rip and holds until the cards have fanned out (`Config.Props.Pack.MaxDuration` safety limit). |
| ox_inventory didn't remove the pack | Removal is now verified (count before / after), inventory detection works regardless of start order, and the console prints the active setup on start. See "ox_inventory checklist" below. |

## Item use with ox_inventory
Your items call the client exports `OpenPack`, `OpenBox`, `ShowCard` and `ShowOthersCard`. They now do the right thing
when ox_inventory calls them for an item:

| Export | From an item | Called with no item (other scripts) |
| --- | --- | --- |
| `OpenPack` | takes 1 pack (server-side, verified), opens it centre-screen, 5 card items after the reveal | free test opening, like `/cardpack` |
| `OpenBox` | takes 1 box, gives `PacksPerBox` packs | lab box, like `/cardbox` |
| `ShowCard` | shows that card large on your screen | — |
| `ShowOthersCard(slot)` | shows that card to players within `Config.ShowCard.Distance` metres (closes itself after `Seconds`) | — |

Keep `consume = 0` on all three items (the resource removes the pack / box itself) and `client.image` for the pictures.
Restart the resource; the console should print `... inventory=ox_inventory ... itemUse=framework+ox_export cardItems=true`.
If a pack still isn't taken, set `Config.Debug = true`, use one and send the server console + F8 output.

## Card items: view, inventory icons, binder
- **Using a card item** shows only the card in the centre of the screen; the game stays visible.
- **Inventory icons** (`Config.CardIcons.Mode`):
  - `'rarity'` (default) — 5 icons, one per rarity, no setup.
  - `'upload'` — each print gets its own 100x100 icon, drawn in-game on its first pull and uploaded to **Fivemanage**
    (`set metacomic_fivemanage_key "..."` in server.cfg). URLs are kept in `fivem/data/card_icons.json`.
  - `/cardicons` refreshes the icons of the card items you already hold (server console: retries missing icons).
- **Binder:** `Config.Items.Binder` now defaults to `{ 'trading_card_binder', 'cardbinder' }`. The binder must be an ox_inventory
  container (`setContainerProperties('trading_card_binder', ...)` in ox_inventory's `modules/items/containers.lua`) and must be
  a binder given **after** that line was added. View Binder now tells you in-game / in the console if either is missing.
- **Fixed:** a server error whenever a player disconnected (the binder cooldown table was declared after the disconnect handler).

### If you applied the previous (v5) zip
Delete `scripts/render-card-thumbs.mjs` and the 38 per-card PNGs + `index.json` in `public/img/cards` and `fivem/img/cards`
(this zip puts the 5 rarity icons there), and use the `package.json` from this zip (removes `playwright-core` / `cards:thumbs`).

## Files
| File | Status |
| --- | --- |
| `src/components/PeelTear3D.js`, `src/utils/rarityFx.js` | new |
| `src/components/PackOpenScene.jsx`, `src/components/PackSimulator.jsx`, `src/components/CardViewer.jsx`, `src/App.jsx` | changed |
| `src/components/BinderView.jsx`, `src/styles/binder.css`, `src/utils/cardIcon.js` | new (binder UI, in-game icon drawing) |
| `public/img/cards/metacard_*.png`, `fivem/img/cards/metacard_*.png`, `fivem/examples/ox_inventory_images/*` | new (rarity icons) |
| `package.json` | unchanged from your project (restores it if you applied v5) |
| `src/runtime/packPrefs.js`, `src/runtime/bridge/fivem.js`, `src/runtime/bridge/standalone.js` | changed |
| `src/styles/packOpen.css`, `src/styles.css` | changed |
| `fivem/config.lua`, `fivem/client/main.lua`, `fivem/server/main.lua`, `fivem/server/cards.lua`, `fivem/server/runtime.lua` | changed |
| `fivem/server/adapters/inventory_ox.lua`, `fivem/server/adapters/inventory_qbcore.lua` | changed |
| `fivem/examples/ox_inventory-items.lua`, `fivem/examples/qbcore-items.lua`, `fivem/README.md` | changed |

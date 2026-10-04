# Rush Trading Cards — FiveM integration

This folder is an optional FiveM host for the same React application.

## Build the NUI
From the project root:

```powershell
npm install
npm run build:fivem
```

This builds the React app into `fivem/web` and synchronizes `public/img` into `fivem/img`.

Then copy/rename the `fivem` folder into your FiveM resources directory, for example:

```text
resources/[custom]/rush-tradingcards/
```

and add:

```cfg
ensure rush-tradingcards
```

## Runtime modes
Edit `config.lua`.

### Fully standalone FiveM
```lua
Config.Framework = 'standalone'
Config.Inventory = 'none'
Config.Persistence = 'json'
Config.Items.RequireForOpen = false
```

No QBCore/Qbox/database is required.

### QBCore
```lua
Config.Framework = 'qbcore'
Config.Inventory = 'qbcore' -- or ox_inventory
Config.Persistence = 'json' -- or mysql
```

### Qbox
```lua
Config.Framework = 'qbox'
Config.Inventory = 'ox_inventory'
Config.Persistence = 'json' -- or mysql
```

Qbox player access uses `qbx_core` exports. Inventory remains its own adapter so Qbox can use ox_inventory without coupling card logic to the framework.

### Auto detection
```lua
Config.Framework = 'auto'
Config.Inventory = 'auto'
Config.Persistence = 'json'
```

Framework auto-detection checks Qbox first, then QBCore, otherwise standalone.
Inventory auto-detection checks ox_inventory first, then QBCore inventory, otherwise none.

## MySQL
Set:

```lua
Config.Persistence = 'mysql'
Config.Database.Resource = 'oxmysql'
```

`AutoCreateSchema = true` creates the owned-card table automatically. The same schema is also in `data/mysql.sql`.

## JSON persistence
`Config.Persistence = 'json'` stores owned card instances in `data/collections.json`.

## No persistence
`Config.Persistence = 'none'` allows pack opening but does not store the collection server-side.

## Inventory / item validation
By default:

```lua
Config.Items.RequireForOpen = false
```

so the resource works without an inventory.

To require physical booster items:

```lua
Config.Items.RequireForOpen = true
```

Then define the configured items in your inventory/framework:
- `boosterpack`
- `boosterbox`
- optional `tradingcard` if `GiveCardItems = true`

The pack roll is always done on the FiveM server. The NUI only receives the resulting cards and animates them.

## Using the items
- **Booster pack:** the server checks and removes one pack, then the opening plays in the **centre of the player's screen**
  (no lab UI): the selected tear style, the cards fanned out in the middle of the screen, **Flip all** and **Done**. Players can also press the configured `Config.PackAnimation.FlipAllKey` (default **F**) to flip all remaining cards.
- **Booster box:** the server removes one box and adds `Config.Items.PacksPerBox` booster packs to the player's inventory
  (refunds the box if the packs don't fit). A produced box carries `setId` / `setName` metadata and every pack created from it inherits that same set metadata. A box-opening animation can hook into `rush_cards:client:boxOpened` later.
- **Booster pack set filtering:** a produced pack carries its series/set metadata. When that exact inventory slot is used, the server removes that exact pack and rolls only cards assigned to that set in `data/sets.json`. Pulled card items also record the source set.
- **Trading cards:** with `GiveCardItems = true` (default) every pulled card becomes a `tradingcard` item: 5 per pack, labelled
  with the card name / print / rarity (ox_inventory also shows the card art). They're handed over once all five are flipped or the
  opening is closed (2-minute fallback), so inventory pop-ups don't spoil the reveal. Free `/cardpack` test opens give no items.
  Using a card item shows that card large in the centre of the screen.
- The character holds the pack prop from the rip until the cards have fanned out (`Config.Props.Pack.MaxDuration` is a safety limit).
- On start the console prints one line, e.g. `framework=qbcore inventory=ox_inventory itemUse=ox_export cardItems=true`.
  If `inventory` says `none`, item use can't work: set `Config.Inventory` or start your inventory before this resource.
- Using an item always takes it, whatever `RequireForOpen` says. `RequireForOpen` only affects `/cardpack`, `/cardbox` and the lab.

How item use is wired (`Config.Items.UseMethod`, default `'auto'` = both routes):

| Setup | Route | Item definitions |
| --- | --- | --- |
| QBCore + qb-inventory | framework | `examples/qbcore-items.lua` |
| QBCore or Qbox + ox_inventory | framework (ox passes the use to QBCore / Qbox) | block **A** of `examples/ox_inventory-items.lua` (`consume = 0`, no client export) |
| Standalone + ox_inventory | ox_export | block **B** of `examples/ox_inventory-items.lua` (client export; rename `rush-tradingcards` if needed) |
| Custom framework | `framework` | Fill in `registerUsableItem` in `server/adapters/framework_custom.lua`. |

## Card inventory icons (ox_inventory)
`Config.CardIcons.Mode`:
- `'rarity'` (default): one 100x100 icon per rarity (`img/cards/rushcard_<rarity>.png`). Nothing to set up.
- `'upload'`: every card gets **one icon per rarity it comes in** (at most 5 per card; all variants and copies of that card at
  that rarity share it), a 100x100 icon (frame in the card's colour, artwork, name, HP, rarity stars),
  drawn in a player's game UI, uploaded to Fivemanage by the server and remembered in `data/card_icons.json`.
  Add your key to **server.cfg** (never config.lua, which players receive): `set rushcards_fivemanage_key "your-api-key"`.
  Each icon is uploaded once; opening packs or giving items never uploads anything new. On start (and with `cardicons` in
  the server console) the saved urls are checked, and icons deleted from Fivemanage are uploaded again.
  Missing icons are made automatically, 8 at a time, by the first player online whose UI has loaded:
  - when the resource starts (players already online) and whenever a player joins,
  - when the catalog is saved in-game: new cards get icons, edited cards (name, HP, colour, rarity or artwork) get redrawn,
  - when a print is pulled from a pack.
  Card items in inventories switch to the new icon right away; players who were offline get theirs when they join.
  A print whose icon can't be drawn (e.g. artwork hosted somewhere that blocks cross-site use) is tried 3 times and keeps
  the rarity icon. `cardicons` in the **server console** retries those.
- `/cardicons` in game updates the card items in your inventory to the current icons. Cards inside a binder are updated
  when the binder is viewed.

### ox_inventory and picture urls
If the convar `inventory:webhook` is set, ox_inventory checks every item picture url on add / update and **deletes** the
ones it doesn't trust. It still shows the url until that slot refreshes, which is why an icon could appear after viewing a
card and then turn back into the item's default picture when the card was moved.
- ox_inventory **2.45.1+**: `nui://` pictures and the hosts in `inventory:validhosts` (default `r2.fivemanage.com`,
  `i.fmfile.com`) are allowed, so rarity and Fivemanage icons work.
- **Older** ox_inventory: only `i.imgur.com`, so Fivemanage urls are always deleted.

When ox would delete the urls, the script switches to **picture files**: each print's icon is also saved into
`ox_inventory/web/images/rushcard_<print>_<version>.png` and given to the item as `metadata.image`, which ox never checks.
FiveM only lets players download files that existed when ox_inventory started, so a new or redrawn icon shows **after the
next server restart** (the card keeps its rarity icon until then; items switch over automatically when their owner joins).
The 5 rarity pictures are copied there too. The server console prints which case you're in on every start
(`card pictures: ox_inventory <version>, inventory:webhook ...`).

For per-card icons that show **straight away**, either remove `set inventory:webhook ...` from server.cfg (ox_inventory only
uses it to post picture urls to Discord) or update ox_inventory to 2.45.1+. The Fivemanage uploads keep happening either way,
so nothing has to be redrawn when you do.

## Card binder (ox_inventory container)
1. `Config.Items.Binder` = your binder item name(s) (default `{ 'trading_card_binder', 'cardbinder' }`).
2. In **ox_inventory/modules/items/containers.lua**: `setContainerProperties('trading_card_binder', { slots = 36, maxWeight = 3600, whitelist = { 'tradingcard' } })`.
   ox_inventory gives a binder its pockets when the item is created: restart ox_inventory and use a **newly given** binder.
3. Add the **View Binder** button to the binder item (`examples/ox_inventory-items.lua`).

The binder shows 9-pocket sleeve pages, cards in the binder's slot order (empty slots = empty sleeves);
click a card to see it large. If something's off the player gets a message and the server console says what to fix.

## Commands
Defaults:

```text
/cards
/cardpack
/cardbox
/cardoptions
/cardadmin
```

`/cardpack` opens a pack in the centre-screen overlay (same as using the item). `/cardbox` opens the lab and starts a box.
`/cardoptions` opens the player's saved pack-opening preferences: tear style, card fan-out, and speed. New players default to **Random** tear + **Random** fan. Preferences are stored per player in client KVP.
`/cardadmin` opens the restricted **Sets & production** screen. It is available only when the server-side management permission check passes.
Without `RequireForOpen = true` the pack/box commands are free test commands and `/cardbox` only shows a virtual box (no inventory items).

## Exports
Client:

```lua
exports['rush-tradingcards']:OpenCards('pack')
exports['rush-tradingcards']:OpenPack()
exports['rush-tradingcards']:OpenBox()
exports['rush-tradingcards']:CloseCards()
```

Server:

```lua
local collection = exports['rush-tradingcards']:GetCollection(source)
local result = exports['rush-tradingcards']:OpenPackForPlayer(source) -- rolls + saves a pack, no animation
exports['rush-tradingcards']:GivePackOpening(source)                -- plays a free pack opening on the player's screen
```

## Card catalog
The authoritative FiveM catalog is:

```text
data/catalog.json
```

Generate it from the React default card data with:

```powershell
npm run catalog:fivem
```

Or generate from a JSON export:

```powershell
node scripts/export-fivem-catalog.mjs .\my-card-export.json
```

## Restricted card management

All authoring / production actions are checked again on the **server**. Hiding the UI is not the security boundary. The same permission controls:

- adding / editing cards in the FiveM editor
- creating, editing, or deleting card series/sets
- assigning the allowed base-card list for each set
- manually printing a physical card inventory item
- producing set-bound booster packs and booster boxes

Configure access in `config.lua`:

```lua
Config.Management = {
    Enabled = true,
    Ace = 'rushcards.manage',
    QBCorePermissions = { 'admin', 'god' },
    Jobs = {
        -- cardshop = 0,
        -- police = { minGrade = 4, onDuty = true },
    },
    QboxGroups = {},
    Identifiers = {},
    MaxCreateAmount = 100,
}
```

ACE example:

```cfg
add_ace group.admin rushcards.manage allow
```

The older `rushcards.catalog.write` ACE is still accepted for backwards compatibility. `Config.Catalog.AllowWrite` must also be `true` for card-editor saves; set management and item production are still governed by `Config.Management`.

### Series / sets and sealed-item metadata

Set definitions live in:

```text
data/sets.json
```

Each set contains an `id`, `name`, optional code/description, and `cardIds` array. `/cardadmin` provides checkboxes for this list.

Produced packs and boxes store `setId`, `setName`, and `setCode` metadata. Opening a box gives packs with the **same set metadata**. Opening a set-bound pack filters the server catalog to the cards assigned to that set; the resulting physical cards keep `setId` / `setName` metadata so their origin can be inspected later.

Old packs/boxes that have no set metadata use `Config.Sets.Default` (default `base`). A sealed item that references a set that no longer exists is rejected rather than silently opening as a different set.

For QBCore/qb-inventory, keep the supplied `boosterpack` and `boosterbox` examples as `unique = true` so differently-tagged sealed items cannot merge into a stack and lose their set identity.

### Manual prints

`/cardadmin` can create a chosen card + print variant directly as an inventory item. Manual prints include metadata such as `manualPrint`, `printType = 'MANUAL PRINT'`, `acquisitionSource = 'manual_print'`, `printedBy`, `printedByIdentifier`, and `printedAt`. Their inventory label/description and card viewer visibly show **MANUAL PRINT**, so they can be distinguished from normal booster pulls even after the item is transferred.

## Streamed models restored
The supplied GTA/FiveM assets are back under `stream/`:

- `prop_boosterpack_01.ydr`
- `prop_boosterbox_01.ydr`
- `prop_deckbox_01.ydr`
- `booster_props.ytyp`
- `prop_deckbox_01.ytyp`

Pack/box opening uses these props without requiring QBCore progress bars.

The original DDS source textures are preserved under `assets/source-textures/`.

## Item definition examples
See:

```text
examples/qbcore-items.lua
examples/ox_inventory-items.lua
```

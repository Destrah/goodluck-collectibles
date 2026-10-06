# Meta Comic Collectibles — FiveM integration

This folder is an optional FiveM host for the same React application.

## Generate the Sample testing set

Run `/collectiblessample` in game with the same management permission as `/collectiblesadmin` (or run `collectiblessample` in the server console). It imports **Sample**: 100 original illustrated base cards and 800 prints, covering all five rarity tiers, all eight holo choices, four layouts, all supported subject effects, varying base/print weights, and aligned alpha/luminance/inverted masks. Base artwork and masks are uploaded first; only HTTPS URLs are saved. Inventory icons are then drawn/uploaded through the existing background pipeline.

Set `metacomic_fivemanage_key_artwork` in server.cfg, or use the existing `metacomic_fivemanage_key` fallback. Keep secrets in server.cfg. Existing Fivemanage folder settings are respected. Inventory icon uploads also require `Config.CardIcons.Mode = 'upload'` and the existing trading-card upload key. Progress appears in notifications and the server console; the initial run uploads 150 unique artwork/mask assets and then generates the print icons. Allow it to finish before testing a full collection.

Reopen `/collectiblesadmin`, choose the Sample set in Sets & containers or the pack lab, and create/open Sample booster packs. The command does not replace other sets, change the default set, or give inventory items. Reruns add missing sample cards and membership links while preserving edits to existing samples. Failed uploads can be retried using the same command; previously uploaded artwork is cached. MySQL saves all new definitions and membership links in one transaction.

For this feature deploy `server/modules/sample_cards.lua`, the updated `server/main.lua`, `server/persistence/mysql.lua`, `fxmanifest.lua`, `data/sample-cards.json`, `img/sample/`, and the rebuilt `web/` folder together. Preserve your current config values. The generated PNG assets and manifest are bundled; Python is only needed if you want to rebuild them with `scripts/generate-sample-cards.py`.

Sample artwork has no embedded lettering, so full-art layouts use only the card's own text. If you already imported the older images, deploy the updated sample images and server files and run `/collectiblessample refreshart` to upload and apply the text-free artwork. This explicitly replaces the base artwork on Sample cards while preserving their other edits and print settings. Already acquired items retain their stored snapshots.

## Existing installation upgrade

For grading troubleshooting, add `Debug = true` inside your existing `Config.Grading` table and restart the resource. The grading bench then offers a debugger with the server's real flaw list, highlights, raw condition values, and print tolerance limits. Small visible shifts inside those limits are normal variation and cannot be confirmed as errors. The reference uses the acquired card's saved print, so later catalog edits do not alter that comparison. Grading checks and inventory updates remain on the server. Set `Debug = false` after testing; while enabled, graders can see the answers.

New card conditions use independent text offsets for subtitle, title, HP, type/rarity, description, attacks, and footer. Each out-of-tolerance section is a separate finding and must be marked on that text. Existing acquired cards with the older text-layer array keep their original condition and single finding. Off-centre borders now confirm only centering; use the artwork and text tools for their respective shifts. Deploy `server/modules/grading.lua`, `server/main.lua`, and rebuilt `web/` together.

The main commands are now `/collectibles`, `/collectiblesadmin`, `/collectiblesoptions`, `/collectiblespack`, `/collectiblesbox`, and `/collectiblesicons`. Existing `/card...` commands remain aliases, and older configuration files still work. `/collectiblesrestoreseed` is console-only. These commands used to be spelled `/collectables...`; if your `config.lua` still has the old names, change them there. Items, saved data and the MySQL `collectable_type` columns from before the spelling change keep working: the column is renamed to `collectible_type` on the next start.

Coin bags, plushie boxes, and outer cases roll and consume their container on the server, but deliver the frozen contents only after everything is revealed or the opening is closed. Pending deliveries use `goodluck_collectibles_openings` in MySQL (or `data/collectible_openings.json` with JSON persistence). Restart recovery uses the character identifier. Full inventories keep their pending delivery for retry. With `AutoCreateSchema = true`, the new table is created at resource startup; otherwise apply the updated `data/collectibles.sql` first.

Deploy the updated `client/main.lua`, `server/main.lua`, `server/modules/objects.lua`, `data/collectibles.sql`, and rebuilt `web` folder together. Container animation preferences are per player in `/collectiblesoptions`; Random is the default for bags, plushie boxes, and cases. The sealed design and inventory snapshot are preserved.

Keep your existing resource folder name during the upgrade to preserve resource-scoped JSON files and player KVP preferences. New installations can use `meta-comic` as shown below. Preserve your configured framework, inventory, commands, item names, and gameplay values.

At startup, the MySQL adapter automatically transfers the old table prefix to `goodluck_collectibles_` using one table rename statement before schema creation and catalog loading. Existing definitions, memberships, acquisition snapshots, and migration markers stay in those tables. Do not pre-create the new tables on an existing installation: if both names exist the adapter stops and logs the conflicting table, preserving both copies for manual review. The database account needs table-renaming permissions. Back up the database before upgrading.

Current ACE names are `metacomic.manage` and `metacomic.catalog.write`; the upload key convar is `metacomic_fivemanage_key`. Upgrade-only aliases preserve existing grants/keys and migrate saved player preferences. Internal events and NUI messages now use `meta_comic` / `metaComic`; update any custom integrations that referenced the previous event names. Existing inventory item names remain unchanged. Copy the updated example inventory images if you manage those images manually.

See [collectible modules](../docs/collectible-modules.md) for the trading card module and future container/type extension points.

## Build the NUI
From the project root:

```powershell
npm install
npm run build:fivem
```

This builds the React app into `fivem/web` and synchronizes `public/img` into `fivem/img`.

The build does not deploy Lua or the manifest to your running server. For an upgrade, copy the complete updated `fivem` resource, including `fxmanifest.lua`, `shared`, `server`, `client`, `web`, and `img`, into the existing server resource directory. Preserve server-owned configuration values and data files; update the table prefix or let the adapter normalize the previous prefix. Copying only `web` leaves the old backend running. The migration is now internal to `server/persistence/mysql.lua`, with no separate migration-script startup dependency.

Then copy/rename the `fivem` folder into your FiveM resources directory, for example:

```text
resources/[custom]/meta-comic/
```

and add:

```cfg
ensure meta-comic
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

`AutoCreateSchema = true` creates the relational tables automatically from `data/mysql.sql`. When disabled, apply that schema manually before starting the resource. Start `oxmysql` before this resource.

The default tables are:

| Table | Purpose |
| --- | --- |
| `goodluck_collectibles_cards` | One row per base card, with title, stats, text, artwork URL and colors in individual columns. |
| `goodluck_collectibles_card_prints` | One row per print, linked to its base card, with rarity, layout, foil settings, artwork and its own framing columns. |
| `goodluck_collectibles_card_sets` | One row per set, with name, code and description. |
| `goodluck_collectibles_card_set_cards` | One row per set/card membership; supports cards in multiple sets and preserves membership order. |
| `goodluck_collectibles_card_storage` | Internal schema/migration marker; prevents repeated imports, including intentionally empty catalogs. |
| `goodluck_collectibles_card_instances` | Original acquisition history and immutable card snapshots. |

Each print belongs to one base card. Set membership refers to base cards, so a set can pull their eligible print variants. IDs use a case-sensitive collation. Composite primary keys prevent duplicate prints within a card and duplicate set memberships; foreign keys prevent orphaned links. Deleting a definition cascades to its prints and memberships, while physical item snapshots and acquisition history remain independent. Only variable nested content (moves, subject-effect layers and additional extensible fields) uses JSON; set membership is stored as rows, not a JSON list.

**Migration:** On first startup, the adapter migrates update 003's `catalog` and `sets` records from the legacy definitions table, if present. Otherwise it imports your configured JSON seed files. The marker and all imported rows commit in one transaction. Existing legacy database documents and local JSON files are preserved. Stale memberships referencing already deleted cards are skipped with a server log message. Invalid seed data or database failures stop the migration instead of falling back to JSON. If populated relational tables have no migration marker, the adapter refuses to overwrite them. Once initialized, restarts use the relational tables; seed files no longer override them.

**FiveM runtime:** Four bulk reads populate the catalog/set cache at startup, avoiding per-card queries and joins that repeat large artwork or effect data. Pack rolling, previews and set selection use that cache. Admin Save/Delete compares against the cache and writes only changed rows and columns in a single [oxmysql transaction](https://coxdocs.dev/oxmysql/Functions/transaction). A crop-only edit updates framing columns without resending unchanged artwork or mask JSON. Cache updates happen only after commit; failed transactions leave both the cache and rows unchanged. Overlapping admin writes receive a retry message. Acquired cards from a pack are inserted together in a separate transaction. Changes made directly in SQL require a resource restart to refresh the cache; use `/cardadmin` for normal edits. One running resource should manage a given set of tables.

Existing `Config.Database.Table`, `Resource` and `AutoCreateSchema` values are preserved. Optional table-name overrides are `CardsTable`, `PrintsTable`, `SetsTable`, `SetCardsTable`, and `StorageTable`. Default names derive from `Config.Database.Table` with a trailing `_instances` removed; the standard instance table uses the names above. `DefinitionsTable` selects the legacy migration source only. For manual schema installation with custom names, adjust the SQL table names and foreign-key references consistently. Names must be distinct and contain only letters, digits and underscores, up to 55 characters.

The acquired-card table records original pulls/manual prints, rather than current inventory ownership. Trading or removing an item does not update that history. Your inventory system persists physical cards and binders; item metadata snapshots remain the display source of truth after catalog edits. Existing acquired-card records are untouched by migration, and `collections.json` is not imported into that table.

Switching back to JSON mode reads the old JSON files; it does not export current database edits. Back up the database and resource data before changing storage modes.

### Catalog display and recovery

FiveM displays only the server's persisted catalog. Bundled standalone demo cards/prints are not inserted into the FiveM editor, and a failed or empty catalog load does not fall back to demo data. Saving one card uses the persistence adapter's current catalog to preserve unrelated records, even if the editor/domain cache is stale. Full JSON Import and the confirmed demo Reset remain explicit catalog replacements.

If cards were missing from the database while the old UI still showed bundled demos, rebuild/deploy the updated NUI and restart the resource. Then run `cardrestoreseed` in the **server console**, and reopen `/cardadmin`. This MySQL-only command merges missing cards, prints, sets and membership links from the preserved legacy definitions table and configured JSON seeds in one transaction. Existing relational IDs, card/print edits, set details, and new cards are kept; no records are deleted. It prints the recovery counts, and repeating it does not duplicate records. It can also restore deliberately deleted seed entries, so recovery is explicit rather than automatic. Recovery depends on those preserved sources containing the missing records.

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
  (refunds the box if the packs don't fit). A produced box carries `setId` / `setName` metadata and every pack created from it inherits that same set metadata. A box-opening animation can hook into `meta_comic:client:boxOpened` later.
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
| Standalone + ox_inventory | ox_export | block **B** of `examples/ox_inventory-items.lua` (client export; rename `meta-comic` if needed) |
| Custom framework | `framework` | Fill in `registerUsableItem` in `server/adapters/framework_custom.lua`. |

## Card inventory icons (ox_inventory)
`Config.CardIcons.Mode`:
- `'rarity'` (default): one 100x100 icon per rarity (`img/cards/metacard_<rarity>.png`). Nothing to set up.
- `'upload'`: **one icon per distinct look** of a card, coin or plushie. Prints that look the same (same artwork, colour,
  name, HP, rarity stars / same coin or plushie design) share one icon; a different look (full art, another plushie
  colour, ...) gets its own. Card icons are 100x100 (frame in the card's colour, artwork, name, HP, rarity stars),
  drawn in a player's game UI, uploaded to Fivemanage by the server and remembered in `data/card_icons.json`.
  Add your key to **server.cfg** (never config.lua, which players receive): `set metacomic_fivemanage_key "your-api-key"`.
  Each look is uploaded once; saving without changing a look, opening packs or giving items never uploads anything new.
  When a collectible or print is deleted, or saved with a different look, the old look's icon is deleted from Fivemanage
  (failed deletes are retried from `data/card_icons_trash.json`) and items still showing it fall back to the rarity icon.
  Items stored in stashes / trunks are only updated when they reach a player inventory. On start (and with `cardicons` in
  the server console) the saved urls are checked, and icons deleted from Fivemanage are uploaded again.
  After updating from the per-rarity version, icons that match a current look are kept and the others are deleted once.
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
`ox_inventory/web/images/metacard_<print>_<version>.png` and given to the item as `metadata.image`, which ox never checks.
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

## Card case (slab case, ox_inventory container)
Set up like the binder: `Config.Items.CardCase` (default `{ 'card_case' }`), `setContainerProperties('card_case', { slots = 48, maxWeight = 6000, whitelist = { 'tradingcard' } })`,
the **View Case** button (`examples/ox_inventory-items.lua`) and the image `examples/ox_inventory_images/card_case.png`.
Cards stand upright in 8 compartments (hover one to lift it, click to see it large). It holds any card: slabs,
toploaders, sleeved and raw. The card hand (your inventory's cards) works as in the binder: drag a card onto a
compartment to put it in, drag a case card onto the hand to take it out (when your inventory has room), or drag
between compartments to move / swap.

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
exports['meta-comic']:OpenCards('pack')
exports['meta-comic']:OpenPack()
exports['meta-comic']:OpenBox()
exports['meta-comic']:CloseCards()
```

Server:

```lua
local collection = exports['meta-comic']:GetCollection(source)
local result = exports['meta-comic']:OpenPackForPlayer(source) -- rolls + saves a pack, no animation
exports['meta-comic']:GivePackOpening(source)                -- plays a free pack opening on the player's screen
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
    Ace = 'metacomic.manage',
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
add_ace group.admin metacomic.manage allow
```

The older `metacomic.catalog.write` ACE is still accepted for backwards compatibility. `Config.Catalog.AllowWrite` must also be `true` for card-editor saves; set management and item production are still governed by `Config.Management`.

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

## Plushies and challenge coins

The shared editor now supports plushie boxes/cases and challenge coin bags/boxes with server-owned opening and immutable inventory snapshots. Deploy all updated Lua files and the manifest as well as the NUI build, and register the items from `examples/ox_inventory-collectibles.lua`. See [collectible systems](../docs/collectible-modules.md) for schema, defaults, setup, and extension details.

## Vending machines

`stream/metacomics_vending_machine.ydr` (archetype in `stream/metacomics_props.ytyp`, loaded by `fxmanifest.lua`) can be placed around the map by anyone with the management permission:

- `/placevending` shows a see-through machine where you look (green outline: can place, red: too far). Rotate with the mouse wheel or hold Q / E (hold Shift for fine steps). Left click or Enter places it; right click, Backspace or Esc cancels.
- `/removevending` removes the closest placed machine within `RemoveDistance`.

Placements are saved with your `Config.Persistence`: MySQL uses the `goodluck_collectibles_vending_machines` table (created at startup when `Config.Database.AutoCreateSchema = true`), anything else uses `data/vending_machines.json`. Every player receives the list when they join and keeps it in memory; each machine is spawned locally (not networked) within `SpawnDistance` and deleted beyond `DespawnDistance`. The distance check sleeps for as long as the player would need to reach the nearest edge, so it costs almost nothing when no machine is near. Settings are in `Config.VendingMachines`; add that block to a preserved config (without it the defaults above are used).

With ox_target and ox_lib running, every machine has up to three target options. Each machine keeps its own products (a card set, booster pack or box, price and stock):

- **Buy** (everyone): lists this machine's products with price and stock left. The server checks the player stands at the machine, the stock, the money (`Shop.Account`: `'money'` is the ox_inventory money item, `'cash'` / `'bank'` the QBCore / Qbox account) and inventory space, then gives a sealed pack or box of that set. If the item can't be added, the money and stock go back.
- **Restock** (managers and the jobs in `Restock.Jobs`): adds stock to a product. Restocking N always needs N sealed packs / boxes of that set in the restocker's inventory, admins included; they are taken from the inventory. Stock is capped at `Restock.MaxStock` per product.
- **Manage** (management permission): add products (pick a set, packs and/or boxes and prices; they start empty), change a price, lower stock or remove a product, or **Move machine** to pick it up with the placement preview and set it down somewhere nearby.

A newly placed machine starts with `Shop.Items`. Products and stock are saved per machine in the `products_json` column (MySQL, added automatically to an existing table) or in `data/vending_machines.json`.

Manual MySQL setup (only when `AutoCreateSchema = false`):

```sql
CREATE TABLE IF NOT EXISTS `goodluck_collectibles_vending_machines` (
 `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 `model` VARCHAR(64) NOT NULL,
 `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL,
 `heading` DOUBLE NOT NULL,
 `products_json` LONGTEXT NULL,
 `placed_by` VARCHAR(100) NULL,
 `placed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

Deploy `fxmanifest.lua`, `client/vending_machines.lua`, `server/modules/vending_machines.lua`, `server/main.lua` and the `stream` folder together.

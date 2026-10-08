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

### ox_core
```lua
Config.Framework = 'ox_core'
Config.Inventory = 'ox_inventory'
Config.Persistence = 'mysql' -- or json
```

Players are identified by character (`char:<charId>`) and named after it. `Config.Management.OxGroups` (group = minimum grade) grants management, and the active group counts as the job for `Config.Management.Jobs` and vending `Restock.Jobs`. Vending machines with `Shop.Account = 'bank'` charge the ox_core bank account; cash is the ox_inventory money item (`Config.Money.Cash = 'auto'`). Notifications use ox_lib when it is running (on any framework).

### Auto detection
```lua
Config.Framework = 'auto'
Config.Inventory = 'auto'
Config.Persistence = 'json'
```

Framework auto-detection checks Qbox first, then QBCore, then ox_core, otherwise standalone.
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

- **Buy** (everyone): lists this machine's products with price and stock left. The server checks the player stands at the machine, the stock, the money (`Shop.Account`, paid the way `Config.Money` says) and inventory space, then gives a sealed pack or box of that set. If the item can't be added, the money and stock go back.
- **Restock** (managers and the jobs in `Restock.Jobs`): adds stock to a product. Restocking N always needs N sealed packs / boxes of that set in the restocker's inventory, admins included; they are taken from the inventory. Stock is capped at `Restock.MaxStock` per product.
- **Manage** (management permission): add products (pick a set, packs and/or boxes and prices; they start empty), change a price, **Take out stock**, lower stock or remove a product (removed stock returns as matching sealed packs/boxes), or **Move machine** to pick it up with the placement preview and set it down somewhere nearby.

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

### Machine ownership, serials and records

Every machine has a serial number (`VM-7F3K-2Q9D`), kept by the placed machine and by its item when it is picked up, stolen or crafted. The serial's record is what decides who owns the machine and where its card payments go, so the owner stays with the machine wherever it ends up.

- **Machines as items.** The `vending` crafting result (and `exports['<resource>']:GiveVendingMachine(source)`) gives a `vending_machine` item with a new serial owned by the business. Using the item places it with the usual preview (`Ownership.ItemPlacement`: `'anyone'` or `'managers'`). **Manage > Pick up** turns it back into the item with its serial, stock and cash.
- **Owners and tax.** In the admin UI **Machine records** tab a manager registers people as owners (an online player or an identifier), sets each owner's tax %, and assigns machines to them. A machine keeps its owner and the owner's routing number until the business assigns it to someone else.
- **Payments.** Buyers pick card or cash (`Shop.Payment`). A card sale pays the tax to the business account (`Ownership.Business`) and the rest to the routing number on the record; offline owners are paid when they next join. Cash stays in the machine (`Shop.MaxCash`) until the owner collects it in **Manage** (the tax is taken then).
- **Records.** The records tab lists every serial with its owner, routing, status (placed, item, stolen, removed) and history. Managers can reset a hacked routing, print a `vending_registration` certificate for one machine, or take a `vending_ledger` that lists every owner and machine. Using either item shows the paper in game; a certificate warns when it is out of date, the machine is reported stolen or its payments are rerouted.

The business's share goes to the first banking resource found (`Ownership.Business.Banking = 'auto'`: Renewed-Banking, okokBanking, qb-banking, qb-management or the ox_core group account), or to your own `Deposit` function with `'custom'`. If nothing takes it, it is held in the records and a manager can pay it out from the tab.

### Vending machine crime and police alerts

Players holding the configured items get extra ox_target options (`Config.VendingMachines.Crime`). The current configuration enables crimes, requires no police online (`MinPolice = 0`), and prevents players from robbing machines they currently control (`OwnersCanRob = false`). Individual actions can be disabled or configured separately.

| Action | Tools and checks in the current config | Progress time | Result |
| --- | --- | --- | --- |
| Break in | Lockpick; hard lockpick and safe games | 45 seconds | Unlocks the cabinet and reveals rough cash/stock levels; opens a choice to loot cash, stock, or both gradually. |
| Hack payment terminal | Laptop and electronic kit; hard keypad, simon and wires games | 90 seconds | Consumes the electronic kit, reroutes card payments to the hacker and grants management/control access. The laptop is retained. Original ownership remains. |
| Take over machine operating system | Laptop and electronic kit; six hard games (keypad, simon, grid, wires, safe and order) | 300 seconds | Consumes the kit and grants operating-system control while keeping the registered owner and existing payment routing unchanged. GPS can be switched off directly in Manage without tools or another minigame. |
| Disable machine GPS | Electronic kit, retained; hard wires game | 30 seconds | Persists GPS disabling against the serial. Required before theft when GPS is enabled. Owners can also disable their GPS. |
| Unbolt machine | Drill; hard sequence, wires and order games; the same player's recent successful break-in; disabled GPS | 180 seconds | Gives a machine item with the same serial, remaining stock and cash; marks its record stolen. Ownership and payment routing remain attached to the serial. |
| Install card skimmer | One configured skimmer item, consumed; medium wires game; available custom prop | 30 seconds | Installs a persistent device that copies the card of every card purchase (and optionally keeps part of the payment from the owner). No tamper cooldown. |
| Read card skimmer | Installer only (only they see it) | 3 seconds | Gives a `skimmer_card_data` item with the copied purchases and empties the skimmer. Sell the data to a buyer ped for `Buyers.Percent` of every copied purchase. |
| Remove card skimmer | Installer only (only they see it) | 3 seconds | Returns the skimmer item with any copied card data still on it; use the item (or its **Read skimmer** button) to print the data. Owners, managers and police find skimmers with **Check coin panel for tampering**, which wipes and seizes them. |
| Replace machine control board | Registered owner/business at a compromised placed machine; replacement board consumed | 60 seconds | Restores owner OS control and payment routing; rearms GPS. |
| Enable machine GPS | Management/control access | 3 seconds | Rearms GPS and registers the current location as its new home position. |

Progress times are **in addition to minigame time**. The normal full-theft sequence is **disable GPS → break in → unbolt → transport**: at least 4 minutes 15 seconds of progress, plus six hard minigames. Finish unbolting within `Steal.BreakInWindow = 600` seconds of your own successful break-in. GPS and the break-in window are checked again when drilling finishes. Hacking is an alternative payment crime, not a theft prerequisite; a successful hacker becomes the controller and cannot rob that machine with `OwnersCanRob = false`. `Hack.Hours = 0` keeps the hacked routing until the owner/business resets it; a positive value makes it expire after that many hours.

Successful/failed cooldowns are per machine and action, in seconds: break-in **900/30**, hacking **1800/60**, theft **300/120**, and GPS disabling **0/60**. Actions without explicit values use **600/30**. A failed minigame can destroy the lockpick (30% chance) or drill (25% chance); other tools are retained unless their item entry specifies `remove = true` on success. Canceling the progress clears the attempt without granting its reward.

**Full system takeover** is the hardest action: five minutes of progress plus six hard games, with a one-hour successful cooldown and five-minute failure cooldown (`Crime.FullHack`). No payment hack is required. OS takeover leaves the current payment destination unchanged. The system hacker can use **Manage → Change card payment recipient** to select an online player ID or a registered routing number (including the business routing number), and can switch GPS directly in Manage. The server resolves the recipient; arbitrary/unregistered bank numbers are rejected. Payments use the existing framework payout account and offline-payout handling, with the normal owner tax rules. Selecting a payee does not grant them machine control. This is the registry's routing system, not an adapter for arbitrary external banking account numbers.

**Physical OS recovery:** Full takeover persists until the control board is replaced; routing reset and ownership reassignment do not remove it. The registered owner/business must physically recover and place the cabinet if it is currently an item or loose/towed prop, stand at the placed machine, and use **Replace machine control board** in Manage or ox_target. `Crime.ReplaceBoard` currently requires one `vending_control_board` and 60 seconds of work. The server checks proximity, tools, time and owner/business authorization again at completion, consumes the board, clears OS/payment tampering, restores owner routing and rearms GPS at the recovered location. The system hacker cannot repair it merely by being the controller. While compromised, only the system hacker can use the direct GPS/payment switches; the owner/business can perform the board replacement. Reset routing remains available for ordinary payment hacks when there is no OS takeover. Register the replacement-board item from the inventory examples.

Existing management capabilities (cash collection, restocking and pickup subject to `Ownership.AllowPickup`) apply to the system controller. Assignment/certificates still identify the registered owner. An ordinary payment hacker can attempt the full upgrade, but an active full takeover cannot be overwritten through another full-hack attempt.

The server validates range, tools, police requirements, cooldowns and an active attempt before starting; completion checks the attempt token, elapsed time, range and tools before granting the result. Inventory removals, rewards, ownership changes and skimmer balances run on the server. Minigames run on the client. Configure each action's `Items`, `Minigame`, `Duration`, `Cooldown`, `FailCooldown`, animation and messages without replacing the rest of the config.

Each action has its own items (`remove`, `breakChance`), minigames, animation and hand prop, duration, cooldowns and failure message. Timers and item checks run on the server. `Config.Minigames` holds the skill-check presets: the built-in games at three difficulties (lockpick, wires, keypad, sequence, plus simon: repeat a growing colour signal, grid: click the squares that flashed, safe: turn a combination dial by feel, reaction: hit green nodes and avoid red ones, order: click numbers in order while they move, circle: stop a speeding, reversing needle on each arc), plus presets for ox_lib skill checks, ps-ui, bl_ui, memorygame, qb-minigames, utk_fingerprint and glow_minigames. If a preset's resource isn't running, the built-in lockpick of the same level is used. Other scripts can call `exports['<resource>']:Minigame('lockpick_hard')` (or a list of names), which returns true or false. Lists require every game to pass; an entry can be `{ random = { ... } }` to pick from alternatives. The principal crime actions currently use fixed lists of hard games. Managers can try every preset at different speeds in the admin UI **Minigames** tab.

### Unlocked cabinets and incremental looting

Deployment requires `server/modules/vending_loot.lua` in `fxmanifest.lua` **before** `server/modules/vending_crime.lua`, plus the updated client crime script. Gradual looting defaults on even when `BreakIn.Loot` is absent; only an explicit `Loot.Enabled = false` selects the legacy reward. A missing loot module reports an error and blocks the break-in instead of silently paying all cash.

After a successful break-in, **Inspect / loot unlocked machine** shows cash and stock as **empty / low / medium / high**, plus estimated time for cash, stock or both. Choose one category or both; both alternates cash and stock batches. Current defaults transfer **$100 every 4 seconds** and **one sealed pack/box every 5 seconds**. More contents take more time; selected contents are taken from the actual remaining stock/cash rather than a random one-time reward. `BreakIn.RewardAccount` or `RewardItem` still chooses the cash payout method.

`BreakIn.Loot.Visuals` enables a reach-and-stash sequence per batch with a cash-note, booster-pack or booster-box prop selected from the actual stock kind. Packs and boxes reuse `Config.Props.Pack`/`Box`; optional `Visuals.Pack`/`Box` overrides can replace models and hand offsets. Configure `Reach`, `Stash`, phase fractions and `Pocket` attachment to tune the motion. Cancellation, death, new batches and resource stop clear the props. Set `Visuals.Enabled = false` for the previous working pose. Visuals never trigger payouts and missing models do not stop server loot timers. The built-in animations approximate pocketing; adjust the clips/offsets after checking your character in game.

The server controls each payout deadline and rechecks range, player identity, cabinet state and session ownership. No client progress completion grants loot. **Backspace**, canceling the progress bar, leaving range, disconnecting, expiry or securing stops future batches; completed batches stay with the player. A canceled/failed pending batch remains in the machine. An inventory refusal or failed save stops looting and restores that batch. Only one looter can operate a cabinet at a time, and stock/payment/movement mutations are blocked while a looter owns it.

`Config.VendingMachines.Crime.BreakIn.Loot` controls `UnlockSeconds` (currently **600**, ten minutes from unlocking), `CashBatch`, `CashBatchMs`, `StockBatch`, `StockBatchMs`, and `CashLevels`/`StockLevels` threshold pairs. Canceling or resuming does not extend the unlock deadline. Return within the window without repeating lockpicking; other eligible thieves can also loot the open cabinet. The unlock timestamp follows the serial through persistence/restarts. Time estimates assume uninterrupted looting; expiry or securing can end it first. `Loot.Enabled = false` restores the legacy immediate cash/random-stock reward using `TakePercent`, `StockChance` and `StockMax`; those legacy settings are preserved but do not limit the gradual mode.

**Secure vending machine** closes the cabinet early and stops its active looter. `Crime.Secure.Duration` currently takes **5 seconds**; `Access` is currently `'anyone'`, with `'police'`, `'controllers'`, or `'police_or_controllers'` alternatives. The server checks the securing player's permission and proximity. Securing/expiry also closes access to the bolts: the thief must break in again before unbolting. Returning to loot an already open cabinet does not send another break-in dispatch; evidence can still be left through the separately configured `loot` fingerprint action.

### Safe fixed placement and stock withdrawal

`Config.VendingMachines.Placement` applies to placing an item, business placement and **Move machine**. The preview rejects road overlap using cabinet footprint samples, steep surfaces, cabinet intersections and blocked front clearance. By default it requires the cabinet's back to be within **0.8 metres of a wall or low barrier** (checked at 0.3, 0.6 and 1.0 metres above the base), with **1.5 metres clear in front**, so machines cannot normally be left in the middle of a path or across a narrow alley. Configure `BlockRoads`, `RoadMargin`, `RoadCheckMode`, `RoadLaneWidth`, `RoadHeightTolerance`, `RoadSidewalkMinRise`, `SurfaceHeightTolerance`, `FrontClearance`, `SideClearance`, `RequireRearWall`, `RearWallDistance`, `RearWallProbeHeights`, `FrontIsNegativeY`, `MinSurfaceNormalZ`, and `CheckInterval`; set `Enabled = false` to disable restrictions. Invalid previews are red and explain why placement is blocked; the final click rechecks the current position/rotation.

The default `RoadCheckMode = 'lanes'` uses [GetClosestRoad lane counts and median gap](https://github.com/citizenfx/natives/blob/master/PATHFIND/GetClosestRoad.md) to estimate the driving corridor, but a lane estimate alone **never clears a native road hit**. Every flagged footprint sample must lie outside that corridor, be on level pavement at least `RoadSidewalkMinRise = 0.08` metres above the raycast road surface, and stay within `SurfaceHeightTolerance = 0.08` metres of the cabinet base. The cabinet must also have broad rear support, even when `RequireRearWall` is disabled. Three probes across 80% of the cabinet width must hit at the same configured height; a narrow signpost or pole does not qualify. Missing ground/road data rejects placement. `RoadLaneWidth = 3.5` estimates metres per lane; `RoadHeightTolerance = 2.5` excludes roads on another elevation. Footprint samples include `RoadMargin`. Set `RoadCheckMode = 'native'` for the strict native region check. Unusual junctions and custom maps remain imperfect; use forbidden zones where precise exclusions matter.

Road/surface/clearance checks are client-side geometry checks and cannot classify every custom-map path or enforce against a modified client. Add **server-enforced** `ForbiddenZones` for important roads, entrances, paths and alleys: use `Center` plus `Radius` (optional `MinZ`/`MaxZ`), or `Center`, `Size` and `Heading` for a rotated box. `ZoneMargin` expands the zone around the cabinet. The server rechecks zones before consuming the machine item or changing its fixed location. Authorized staff can bypass using the configured `BypassAce` (default `rush-tradingcards.placement.bypass`); this requires an explicit server ACE grant. These restrictions apply to fixed placement, not loose dropped/towed cabinets.

**Manage → product → Take out stock** moves the requested quantity into the player's inventory as matching sealed packs/boxes of that set. **Lower stock** returns the difference; **Remove from machine** returns all remaining stock before removing the product. Additions still use **Restock** with real items. The server validates management access, proximity, quantity and inventory capacity; a save/payout failure restores stock instead of silently discarding it. Stock transfers and purchases are serialized to prevent overlapping withdrawals from duplicating items.

### Dispatch, optional phone alerts, GPS and skimmers

`Config.Police.CrimeAlertStage` selects the only crime stage that can send a police dispatch (`'start'` by default; `'fail'` or `'success'` are alternatives). An attempt gets one chance at that stage; failing or completing it does not send a second call. Phone stages and GPS movement alerts are independent.

Current start-stage police chances are **break-in 50%, hacking 35%, full takeover 100%, unbolting 100%, GPS disabling 25%, and skimmer installation 25%**. This is one chance per action attempt, not one call for the entire theft chain. Adjust `Config.Police.Alerts` for each action. `Steal.NeedsGPSDisabled` is ignored when GPS is globally disabled.

Start `rush-dispatch` before this resource. `Config.Police.System = 'auto'` now detects it first; set `'rush-dispatch'` explicitly to pin that choice. The adapter calls the supplied fork's client `CustomAlert` export with `dispatchCode`, `message`, `description`, coordinates and `job`. Configure its actual department names in `Config.Police.RushDispatchJobs` (defaults: `lspd`, `bcso`, `sasp`); `Jobs` still controls police counts and `DispatchJobs` still controls ps-dispatch groups. Existing crime chances remain in `Config.Police.Alerts`.

Phone delivery is optional and **disabled by default**. The supplied dispatch ZIP has no phone messaging export; its phone notifications use LB Phone. `Config.Police.Phone.Enabled = true` enables direct LB Phone server exports independently of the police chance roll. `Recipient = 'controller'` resolves the current network-chip controller from the serial registry (active full-system hacker, otherwise the active payment hacker or owner). `Mode = 'notification'` uses `SendNotification`; `'sms'` uses `SendMessage` and requires a valid `FromNumber`. Configure `Stages`, `Cooldown`, `Title` and `Message`; templates support `{serial}`, `{action}`, `{stage}`, `{title}` and `{message}`. An offline controller is resolved by their framework identifier via `GetEquippedPhoneNumber`; delivery requires a phone number known to LB Phone. A business-owned machine without a personal controller has no personal recipient. [LB Phone export reference](https://docs.lbscripts.com/phone/exports/server-exports/).

`Config.VendingMachines.GPS` controls movement detection. The first placed location is stored against the serial and survives picking up, towing, dropping and replacing the machine. Movement beyond `MovementThreshold` triggers an in-game alert to the **current chip controller**, throttled by `Cooldown` and checked every `CheckInterval` milliseconds. Current settings are a 2-metre threshold, a 5-second check interval and a 60-second alert cooldown. Tracking follows placed cabinets, towed/dropped entities and the player holding the machine item; authorized movement also triggers detection while GPS remains armed. **Disable machine GPS** requires the configured electronic kit and wire minigame; disabling persists until someone with management/control access uses **Enable machine GPS**, which registers the current spot as the new home position. GPS movement phone messages remain optional. `Config.Police.Alerts.gps.chance.movement` defaults to 0: raise it to also send GPS movement to police dispatch.

`Config.VendingMachines.Skimmer` configures the custom prop, item and payment mode. Stream your own `metacomics_card_skimmer` drawable and register its archetype in the loaded `metacomics_props.ytyp` (or add your own YTYP to the manifest). **Install card skimmer** is blocked until that model is available on the installing client. `Offset` and `Rotation` attach it to the cabinet near the coin/card slot; tune these so the device slightly overlaps the slot. The prop is cosmetic; installation, payment recording, item removal and collection are server authoritative. Add `card_skimmer` from the inventory examples.

Whoever installs a skimmer picks its cut (0 to `Skimmer.MaxPercent`, default `Percent`). That share of every card payment never reaches the machine's owner; the skimmer records it with the copied card. Reading the skimmer, or using a removed skimmer item, gives a `skimmer_card_data` item (cards, total, skimmed amount, machine serial, dates). Card data buyers (`Skimmer.Buyers`, one `Ped` or a list of `Peds`, spawned near players) recover the skimmed money and pay the seller `Buyers.Percent` (default 50%) of it into `Account`. Each card purchase is copied until `Capacity` is reached. Owners, managers and controllers see every sale in **Manage > Sales records** (`Ownership.SalesLog`, default 50): price, tax and what was paid out, so a skimmed card payment pays out less than it should. Managers can test every side of this with `/vendingtestrole` (player, stranger, police, employee, manager, off).

### Modular crime evidence and injuries

`Config.CrimeEvidence` controls evidence independently of police dispatch. Accepted break-in, payment hack, full takeover, drilling, GPS tampering and skimmer-installation attempts each have a **75% fingerprint chance** at start. Invalid requests and canceled requests that never started do not emit evidence. Canceling an accepted attempt does not erase prints already left. `Fingerprints.Actions` enables individual actions; `Chance = 0` prevents prints. Optional `IsWearingGloves(source, payload)` is a server callback returning true to suppress prints using your own validated clothing state.

A reported minigame failure can injure the player: currently **15% chance / 5 health damage** for break-in and **25% / 10 damage** for drilling. Configure `Injury.Actions`, `Chance` and `Damage`, or disable injuries. Blood has a separately configurable chance (currently 100%) following a selected injury; other actions and canceled progress do not roll injuries. The server selects the injury after validating the pending attempt and proximity, then applies it on the player's client. The client clamps damage and preserves at least 101 health; players already at/below that level are skipped. Minigame failure remains a client-reported result.

The enabled **rush-evidence adapter** matches the supplied ZIP's event API: `evidence:client:CreateFingerprint(coords)` and `evidence:client:GetBloodInfo`. That ZIP has no dedicated fingerprint/blood creation exports. Its fingerprint event applies its own glove rules. Fingerprints are placed just outside the nearest cabinet face toward the player, with slight horizontal/vertical scatter; `Fingerprints.Placement.Face = 'front'` forces the front. Tune footprint half-width/depth, surface offset, height and scatter for custom models. Blood uses a server-selected random spot within `Blood.ScatterRadius` (0.25 metres) of the injured player. A client raycast returns only ground height under that chosen spot; the server validates a single-use request and forwards `src` and coordinates to `evidence:server:CreateBlood`. Unknown/replayed requests and invalid heights are rejected. The old `GetBloodInfo` event ignores supplied coordinates and is no longer used by this adapter. Start `rush-evidence` before this resource. If it is absent/stopped, the adapter skips delivery; these scripts do not store their own physical evidence. Evidence collection, identity/DNA, persistence and expiry remain the evidence resource's responsibility.

`Adapters` supports multiple providers. Disable the rush adapter when replacing it to avoid duplicate evidence. A generic **server export** receives one payload table:

```lua
{ Enabled = true, Resource = 'my-evidence', Export = 'CreateEvidence',
  Kinds = { fingerprint = true, blood = true } },
```

For an export with different arguments, use a server-side mapping function instead:

```lua
{ Enabled = true, Kinds = { fingerprint = true }, Create = function(payload)
    exports['my-evidence']:AddFingerprint(payload.source, payload.coords)
end },
```

These names are examples; substitute your resource's documented exports. Payload fields are `kind`, `source`, framework `identifier`, `serial`, `machineId`, `action`, `stage`, `coords`, `timestamp`, and `damage` for blood. Adapters run under `pcall` so a provider error does not cancel the crime or prevent other adapters from running. Set `CrimeEvidence.Enabled = false` to disable both evidence and incidental injuries.

### Moving machines: dolly and rope

While a player has a vending machine item they push it on a dolly (`Config.VendingCarry`): walking pace, no sprint, jump or weapons. Vehicle entry follows the configured block/drop policy below. A **stolen** machine can be tied to the back of a vehicle (ox_target on the vehicle, standing behind it) and dragged on a rope; the item leaves the inventory while it is dragged. **Untie vending machine** (ox_target on the machine or behind the towing vehicle) puts it back in the player's inventory. Set `Tow.StolenOnly = false` to allow other machines to be towed too.

`Dolly.offset` positions the dolly relative to the player; `Machine.offset` positions the cabinet base relative to the dolly, with model-origin height compensated automatically. Offsets are `vec3(left/right, forward/back, height)` in metres; rotations are degrees. Raising the dolly raises the whole assembly; raising the machine changes only the cabinet. With the current dolly Z rotation of 180 degrees, decreasing `Machine.offset.y` moves the cabinet away from the player. Model, animation, walking pace and rope length are also configurable.

Towed and dropped machines are journaled in `data/vending_tow_recovery.json`, including serial, contents and last known world position. They are **not automatically returned to anyone's inventory** on disconnect, disappearance, stop or restart. Resource stop detaches ropes and freezes props; startup adopts the matching cabinet or attempts to restore it at the journaled location as an untied world object. Someone must physically pick it up/untie it to receive an item. If a prop disappears during runtime, or an older journal has no reliable location, its contents remain recorded as missing for future reconciliation rather than being returned or fabricated at an assumed location. Preserve the journal during deployment. A failed initial tow spawn still rolls back the item removal because no successful tow occurred.

The registry retains legal ownership, physical theft status, OS/payment-compromise state and unplugged/missing world state independently. A world cabinet is not a placed, connected shop. This supplies data for a future owner/business lost/stolen reporting system; that reporting interface and remote connectivity monitor are not implemented here. Deploy the updated `stream/metacomics_vending_machine.ydr` too: its collision filters allow world collision while dragged. `node scripts/fix-vending-collision.mjs` validates and reapplies those filters without changing geometry or textures.

`Config.VendingCarry.VehicleEntry` selects `'block'` (refuse vehicle entry while carrying a machine) or `'drop'` (attempting entry drops one machine in front of the player; try entering again once the inventory has updated). If carrying several machines, drop each before entering. Dropped cabinets use **Pick up vending machine** in ox_target and retain their serial, stock and cash. Removal and pickup run on the server.

`Config.VendingCarry.Tow.Physics` controls `Mass` (currently 1000), `Gravity` (1), `LinearDamping` (0.1, movement resistance) and `AngularDamping` (0.5, spin resistance). Set `Enabled = false` to use the model defaults. Physics settings are applied by the entity's network owner and reapplied when ownership changes; mass is separate from inventory item weight.

`Config.VendingCarry.Tow.Snap.Enabled` toggles automatic snapping and is currently **false**. The server snaps the rope after an overload lasts `Duration` milliseconds (default 600), following `GracePeriod` after ground placement (3000). Overload means centre-to-centre separation exceeds `Tow.Length + Snap.ExtraDistance` (6 + 3 metres by default), or vehicle speed exceeds `MaxSpeedKmh` (100 by default; 0 disables the speed trigger). This is a distance/speed rule rather than a measurement of rope force. Snapping leaves the machine available for pickup, frees the vehicle for another tow, and preserves machine contents and restart recovery.

`Config.Police.System = 'auto'` uses the first running dispatch resource in this order: rush-dispatch, ps-dispatch, cd_dispatch, qs-dispatch, core_dispatch, rcore_dispatch, lb-tablet, tk_dispatch. Otherwise it uses a built-in notification and blip for `Jobs`. `MinPolice` counts on-duty players in those jobs. Other scripts can call the server export below; its crime stage must match `CrimeAlertStage` to be eligible for police delivery, and the configured chance still applies:

```lua
exports['rush-tradingcards']:PoliceAlert(source, {
    action = 'breakin', stage = 'start',
    coords = vec3(100.0, 200.0, 30.0), serial = 'VM-EXAMPLE',
})
```

Replace `rush-tradingcards` with your actual resource name. Phone delivery uses its own stage settings and can be added later without changing crime handlers.

Existing MySQL tables get a `meta_json` column automatically (serial, cash and access). Deploy `fxmanifest.lua`, the updated `client` and `server/modules` folders, model assets and a fresh NUI build (`npm run build:fivem`) together. Merge settings into your existing `config.lua`: `Shop.CashAccount / Payment / MaxCash`, `VendingMachines.Item / Ownership / Records / Crime / GPS / Skimmer`, `Config.VendingCarry`, `Config.Minigames` and `Config.Police`. Item definitions are in `examples/ox_inventory-items.lua` and `examples/qbcore-items.lua`. Preserve the tow recovery journal during deployment.

### Cabinet keys, cylinders and temporary security seals

`Config.VendingMachines.Keys.Enabled = true` requires a current inventory key and an explicit cabinet unlock before restocking, changing prices, removing stock, collecting cash, picking up or moving a placed machine. The server validates machine serial, cylinder ID, numbered key ID, access level, proximity and the actual inventory key on each action. A **service** key permits restocking and price changes; a **full** key also permits cash collection, product/stock changes, pickup and movement. A stolen valid key grants its physical access, but does not grant registered ownership, general key issuance or payment-routing authority. Payment/OS hacks remain separately recorded; hacking alone does not supply a physical cabinet key.

Add `vending_key`, `vending_key_record` and `vending_lock_cylinder` from the inventory examples, using your resource name for the ox_inventory client exports. Deploy both new `client/vending_keys.lua` and `server/modules/vending_keys.lua` with the updated manifest and NUI. Merge the new **Keys** settings into existing configs; existing crime durations, cooldowns and `Secure.Access` values are preserved. While keys are enabled, `Keys.SecureAccess` governs sealing (default `police_or_controllers`, meaning police, the registered owner or business; payment hackers are not treated as registered owners).

Newly installed factory machines include one full-access key for the installer. Reinstallation, theft and an unregistered cylinder replacement cannot generate another factory key. Failed included-key delivery can be retried with **Collect replacement key**. Existing machines with no surviving keys must be opened and rekeyed; ownership alone does not recreate a working key.

Business managers duplicate keys through **Machine records → Issue a numbered machine key**, or **Cabinet lock / keys → Issue / duplicate numbered key** at a machine. The issuer must physically hold a working **full-access key for the actual current cylinder**, including when using the records panel. Ownership, business permission, a retired key or a service key cannot substitute for it. The server checks again after saving and before delivering the copy. Reading and printing business records retain their existing permissions and do not require the cabinet or cash box to be open. Each copy gets its own permanent key ID without invalidating existing keys. There is no universal business master key. Use **Cabinet lock / keys → Unlock cabinet with key** to open management, and **Lock cabinet** to close all key access sessions. Key sessions expire after `Keys.SessionSeconds` (300 by default); an intact cylinder remains intact when a normal key session ends.

**Replace / rekey cylinder** requires the cabinet to already be open, including for owners, managers and employees. The server checks this at both start and completion. Open an intact cylinder with a matching key; if someone changed the cylinder without permission, the registered owner can use **Break in** to regain cabinet access even with `OwnersCanRob = false` (the ordinary timed break-in mode; legacy immediate robbery rewards retain their owner restriction). Replacement takes `Keys.ReplaceDuration` (60 seconds), consumes one `vending_lock_cylinder` and issues one new full-access key to the verified requester. All old keys stop unlocking the machine. The business can then issue further copies. The default business crafting recipe makes cylinders from two steel and one aluminum. If recipes are already customized, add this recipe through the Crafting editor to retain your other custom recipes. If key delivery fails after replacement, **Collect replacement key** retries delivery without another cylinder.

A successful break-in leaves the primary cylinder **damaged**. Police/owner/business securing, and expiry of the configured robbery opening window, fit a **temporary security seal** instead of repairing the lock. The existing opening-window value is retained. In **Cabinet lock / keys**, the registered owner, manager, authorized employee or holder of a current key matching the damaged cylinder can **Remove security seal and open cabinet**, then replace the cylinder. A retired key cannot remove the seal. Anyone nearby can open or close an unsealed damaged cabinet; closing its door does not lock it, and it remains accessible until sealed, repaired or rekeyed. A replacement in progress holds the door open for the entire job. Sales continue. An unauthorized break-in must defeat the seal as well as complete the configured break-in checks. `Keys.Seal` adds a minigame and 20 seconds by default, while existing crime cooldowns still apply. Replacement does not repair hacked routing/control boards, erase crime evidence or restore stolen contents.

**Permanent evidence:** cylinder generations and every numbered key issuance live in `record.keyArchive`, separate from the capped activity history. They survive rekeying, pickup, towing, placement and resource restarts. Retired key items retain their original serial, cylinder and key ID and remain usable to read their identification. The archive includes recipient/issuer identifiers, access level, issue dates, and cylinder installation/retirement dates. It records original issuance rather than current possession.

Police can use `/vendingkeys SERIAL` to read the complete archive and `/vendingkeys SERIAL print` to receive a `vending_key_record` evidence item. Registered owners and the business can also use these commands, or read/print through the cabinet menu. The business records panel searches current and retired key/cylinder identifiers and offers **Print key records**. Printed records are immutable snapshots, readable by anyone holding the paper; printing after a later rekey includes the newer cylinder without altering previously printed evidence. Large record views use latent events. Preserve the vending registry in the configured settings persistence during deployment; the permanent key archive is not pruned by `Ownership.HistoryLength`.

Printed snapshots are stored separately as `vending_key_reports` in the configured settings persistence; inventory paper carries only a report reference. Preserve these settings alongside the registry so old evidence papers remain readable. Opening a report sends its full archive through a latent event instead of bloating inventory metadata updates.

Standalone Vite mode shows current and retired sample cylinders, supports demo key issuance, and previews printed key records without an inventory. Physical cabinet operations run in FiveM.

## Money

`Config.Money` decides how each account is paid. `'framework'` uses QBCore / Qbox `player.Functions.AddMoney` / `RemoveMoney` (cash, bank or any other account) and the ox_core bank account; `'item'` uses an inventory item (`CashItem`, default the ox_inventory `money` item). `Cash = 'auto'` uses the item on ox_core and the framework cash everywhere else. `Custom = { add = ..., remove = ..., balance = ... }` plugs in any other money system.

## Crafting

`Config.Crafting` sets up workbenches (ox_target, optional prop) and recipes for any item: inventory items, booster packs and boxes, plushie and coin containers, shipping crates and vending machines. Each recipe can have a time, money cost, jobs, stations, managers-only and tools that aren't used up. Packs and boxes are made from `card_blank`, plushie boxes and cases from `generic_plushie`, coin bags and coin bag boxes from `coin_blank`; the blanks themselves are crafted from paper and plastic, fabric, and copper. Recipes saved in the admin UI replace the config ones, so press **Reset** in the Crafting tab to pick up new default recipes. Managers edit the recipes in the admin UI **Crafting** tab (Save / Revert, Reset goes back to the config) and can craft anywhere with `/collectiblescraft`. Other scripts: `exports['<resource>']:OpenCrafting(stationIndex)` (client) and `GetCraftingRecipes()` (server).

## Vending transport and trunk restrictions

Stolen loose-world cabinets use the custom vending body directly for collision, with its swinging door attached; the body YDR must include a collision bound. Intact cabinets use the full custom machine. Carrying retains its existing visual body/door assembly, and the door trails movement when turning. Only the cabinet's network owner attaches a physics rope; other clients draw its endpoints. Deploy both client vending transport files, the server carry module and the collision-equipped body YDR, restart the resource, and pick up/re-tie existing cabinets to use the new body. No NUI build is needed for these Lua changes.

`Config.VendingCarry.TrunkRestrictions` uses an ox_inventory server `swapItems` hook; no inventory source edit is needed. Lists are empty by default. For example:

```lua
BlockedModels = { 'adder', `zentorno` },
BlockedTypes = { 'bike', 'boat', 'heli', 'plane' },
BlockedClasses = { 'sedans', 'sports', 7 },
ModelClasses = { sultan = 'sports', adder = 7, speedo = 'vans' },
BlockUnknownClass = true,
```

Models accept names or signed/unsigned hashes. Classes accept names or GTA class IDs (sedans 1, sports 6, super 7, vans 12). `ModelClasses` is trusted server configuration because GTA's class lookup is client-side. When class rules are set, unmapped models are blocked by default: add permitted models and their classes to this mapping, or set `BlockUnknownClass = false` to apply class restrictions only to mapped models. Model/type restrictions do not require that mapping. Moves, stacks and both directions of swaps are checked, while taking a machine out remains permitted. Hooks re-register when ox_inventory restarts. This integration covers ox_inventory UI transfers; other inventory systems and direct server AddItem calls need equivalent enforcement in their own integration.

### Installation, bolts and replacement cylinders

Recovery has two independent parts: replacing the control board revokes the private OS group and restores remote business access; replacing the cylinder invalidates any working physical keys the group obtained. A board replacement alone does not invalidate key items. During a takeover, designated OS operators may duplicate numbered keys at the cabinet only while holding a working full-access key for the current cylinder; this is the takeover-specific exception to normal business-only key issuance. Revoking OS access does not remotely destroy a physical key.

**OS takeover and remote access:** a full board/OS takeover starts a new private operating log. Previous business history, sales and key/cylinder records remain historical business records; they are not copied into the taken-over OS. New activity and sales are recorded separately for the OS controller and designated operators. Business/owner records show **OS offline · historical records only** and no live location, cash or movement fixes while that board controls the machine. Their vending-map markers disappear. Designated operators get remote access through `/cardportal` to the map and new OS records, and owner-like operating permissions, including payment/GPS settings and maintenance. Keys, physical cabinet/cash-box access and duplication's working full-key requirement still apply. Registered ownership and registration documents do not transfer.

Only the OS controller can grant/revoke operators: use **Manage → Manage OS operating access**, the private OS record's grant/revoke controls, or `/vendingosgrant SERIAL PLAYER_ID` and `/vendingosrevoke SERIAL PLAYER_ID`. Operator identifiers persist through restarts; the records page also lets the controller revoke an existing operator while offline. Grant/revoke/takeover/recovery refresh an open map/records page. Physically replacing the control board revokes the whole OS group's remote and operating access, restores the registered group's map and future logging, and restores routing/GPS through the existing recovery process. Takeover-period logs remain separate server archives and are not backfilled into business history. A later takeover starts another empty private log. Merely repairing/replacing the cylinder or changing payment routing does not recover the board. Payment diversion alone grants no private map or OS record access. Existing takeover saves are upgraded without transferring their existing records to the new OS. Printed papers remain immutable physical evidence.

Registered ownership, payment routing/OS control and physical cabinet access are separate permissions. Employees remain eligible to maintain business-owned machines even after payment diversion or a full OS takeover; routing a payment to someone does not make them an owner or employee. Staff can inspect skimmers, seal/unseal damaged cabinets, repair/rekey cylinders and recover a taken-over control board on business machines. These permissions do not extend to unrelated privately owned machines. A locked cabinet still needs a working key, and replacing a cylinder requires it open. Employees can restock an already broken-open business cabinet without a key, but their employee role alone does not permit cash collection or other full-access operations. Board replacement requires the cabinet and cash box open at start and completion. A stolen working key grants only its physical service/full access; it does not confer ownership, business records or general key issuance. Payment/OS changes separately require system authority plus physical cabinet access when keys are enabled; recovering a cylinder does not recover a hacked OS. Existing configured GPS/phone notification recipients are retained.

Physical contents require an open cabinet door. The break-in timer and persistent damaged state alone do not allow looting, stock withdrawal, restocking or owner cash collection through a closed door. Cash also requires the cash-box lid to be open; closing either access point during a loot batch or save stops the payout and restores undelivered contents. Closing a damaged door still does not repair or secure its lock, and anyone may reopen it while unsealed. A successful break-in opens the door before presenting the loot inspection menu.

Police can target a placed vending machine and select **Inspect machine serial number** without a cabinet key. The server verifies their police role and distance, and returns only the machine's physical serial. Compare it with the serial on the owner's `vending_registration` document; inspecting the plate does not expose unregistered cylinder changes or automatically label legitimate cylinder maintenance as theft. Registration papers are readable by whoever holds them, so the owner can hand them to an officer for verification.

Cylinder changes made by someone outside the registered owner/business/authorized employee permissions do not update business records. The operating system continues showing its last registered cylinder and keys, without recording retirement or exposing the unregistered replacement or its key. Physical keys still validate against the real current cylinder on the server. A later authorized replacement registers that cylinder without publishing earlier unregistered cylinders. Readable and printed reports retain the known historical keys. Players with an unlocked service or full-access key can check for skimmers from **Manage → Check coin panel for tampering**; the server checks their session again at completion.

New installations and relocations start **unbolted**. The standing prop remains frozen for stability; use **Bolt machine down** with a drill to physically secure it (10 seconds by default). The installer, owner, manager, authorized business employee or a player with an unlocked full-access key may bolt it down. Loose machines show **Steal Machine** instead of the drilling/unbolting action (5 seconds, no drill or break-in required by default). Existing placements retain their previous bolted behavior until moved. Configure these actions under `Crime.BoltMachine` and `Crime.TakeMachine`.

A broken-open cabinet picked up and installed elsewhere stays open across the normal security deadline and resource restarts. Police, owners, managers and authorized employees may secure it with the temporary security seal; repair or cylinder replacement also ends the persistent open state. Bolting it down alone does not repair its lock. Ordinary break-ins that have not been transported still use the configured automatic seal timer.

The person installing a stolen machine, or anyone at a currently broken-open machine even before it is moved, can use **Cabinet lock / keys → Replace / rekey cylinder**. This consumes one cylinder and performs the repair animation while facing the right side of the machine. Owners/managers use `Keys.ReplaceDuration`; other installers use `Keys.ForcedReplaceDuration` (three minutes by default) plus `Keys.ForcedReplaceMinigame` (hard lockpick and wiring challenges). The work pose continues through the minigames and timer. `Keys.ReplaceOffset` adjusts the work position; that side must be accessible. A valid replacement attempt pauses the automatic seal timer; canceling or leaving allows it to resume. Replacement automatically includes **one full-access key** for the installer. If delivery fails, **Collect replacement key** lets that same player retry without another cylinder or duplicate delivered keys. General key issuance remains restricted to business managers. Replacing a cylinder retains every previous cylinder and numbered key in the readable/printable permanent archive, and does not transfer the registered owner or payment routing.

## Shipping crates

A `shipping_crate` item (crafted, or `/givecrate [crate id]` for managers, or the server export `GiveShippingCrate(source, crateId, count)`) holds a crate type from `Config.ShippingCrates.Crates`. Using it puts the crate prop on the ground, plays the prying animation with a crowbar (`Tool`), opens the lid in game and then shows a 3D reveal of the contents (`Animation3D`: lid, panels, pry, straps or random). The props are from the 2024 Bottom Dollar Bounties update, so add `set sv_enforceGameBuild 3258` (or newer) to `server.cfg`.

## Opening the UI from other scripts

`exports['<resource>']:OpenAdmin(tab)` opens the admin UI on a tab (`'vending'`, `'records'`, `'crafting'`, ...) after the server checks the management permission. `exports['<resource>']:GetEmbedUrl('admin', 'vending')` returns an address for an `<iframe>` in your own NUI page; it posts `metaComic:embedReady` and `metaComic:embedClose` to the parent window.

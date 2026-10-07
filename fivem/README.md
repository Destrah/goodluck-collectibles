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

### Machine ownership, serials and records

Every machine has a serial number (`VM-7F3K-2Q9D`), kept by the placed machine and by its item when it is picked up, stolen or crafted. The serial's record is what decides who owns the machine and where its card payments go, so the owner stays with the machine wherever it ends up.

- **Machines as items.** The `vending` crafting result (and `exports['<resource>']:GiveVendingMachine(source)`) gives a `vending_machine` item with a new serial owned by the business. Using the item places it with the usual preview (`Ownership.ItemPlacement`: `'anyone'` or `'managers'`). **Manage > Pick up** turns it back into the item with its serial, stock and cash.
- **Owners and tax.** In the admin UI **Machine records** tab a manager registers people as owners (an online player or an identifier), sets each owner's tax %, and assigns machines to them. A machine keeps its owner and the owner's routing number until the business assigns it to someone else.
- **Payments.** Buyers pick card or cash (`Shop.Payment`). A card sale pays the tax to the business account (`Ownership.Business`) and the rest to the routing number on the record; offline owners are paid when they next join. Cash stays in the machine (`Shop.MaxCash`) until the owner collects it in **Manage** (the tax is taken then).
- **Records.** The records tab lists every serial with its owner, routing, status (placed, item, stolen, removed) and history. Managers can reset a hacked routing, print a `vending_registration` certificate for one machine, or take a `vending_ledger` that lists every owner and machine. Using either item shows the paper in game; a certificate warns when it is out of date, the machine is reported stolen or its payments are rerouted.

The business's share goes to the first banking resource found (`Ownership.Business.Banking = 'auto'`: Renewed-Banking, okokBanking, qb-banking, qb-management or the ox_core group account), or to your own `Deposit` function with `'custom'`. If nothing takes it, it is held in the records and a manager can pay it out from the tab.

### Vending machine crime and police alerts

Players holding the configured items get extra ox_target options on machines they don't control (`Config.VendingMachines.Crime`):

- **Break in** (lockpick): takes the cash stored in the machine, and sometimes a few sealed packs or boxes.
- **Hack payment terminal** (laptop and electronic kit): reroutes the machine's card payments to the hacker and gives them control of it until the owner or the business resets the routing (`Hack.Hours = 0`), or for that many hours.
- **Unbolt machine** (drill, only shortly after a break-in): the thief gets the machine item with the same serial. The record is marked stolen and payments still go to the owner unless it is also hacked.

Each action has its own items (`remove`, `breakChance`), minigames, animation and hand prop, duration, cooldowns and failure message. Timers and item checks run on the server. `Config.Minigames` holds the skill-check presets: the built-in games at three difficulties (lockpick, wires, keypad, sequence, plus simon: repeat a growing colour signal, grid: click the squares that flashed, safe: turn a combination dial by feel, reaction: hit green nodes and avoid red ones, order: click numbers in order while they move, circle: stop a speeding, reversing needle on each arc), plus presets for ox_lib skill checks, ps-ui, bl_ui, memorygame, qb-minigames, utk_fingerprint and glow_minigames. If a preset's resource isn't running, the built-in lockpick of the same level is used. Other scripts can call `exports['<resource>']:Minigame('lockpick_hard')` (or a list of names), which returns true or false. A list entry can be `{ random = { ... } }`, so the defaults pick a different game each time. Managers can try every preset at different speeds in the admin UI **Minigames** tab.

### Dispatch, optional phone alerts, GPS and skimmers

`Config.Police.CrimeAlertStage` selects the only crime stage that can send a police dispatch (`'start'` by default; `'fail'` or `'success'` are alternatives). An attempt gets one chance at that stage; failing or completing it does not send a second call. Phone stages and GPS movement alerts are independent.

Crime progress defaults are 45 seconds for break-in, 90 seconds for hacking, 30 seconds for GPS disabling/skimmer installation, and 180 seconds for unbolting, in addition to minigame time. Break-in uses two hard games; hacking and theft use three. Theft requires the thief's own recent break-in and disabled GPS (`Steal.NeedsGPSDisabled`, ignored when GPS is globally disabled). The 600-second break-in window and GPS state are checked again when drilling finishes. Configure durations, games and prerequisites under `Config.VendingMachines.Crime`.

Start `rush-dispatch` before this resource. `Config.Police.System = 'auto'` now detects it first; set `'rush-dispatch'` explicitly to pin that choice. The adapter calls the supplied fork's client `CustomAlert` export with `dispatchCode`, `message`, `description`, coordinates and `job`. Configure its actual department names in `Config.Police.RushDispatchJobs` (defaults: `lspd`, `bcso`, `sasp`); `Jobs` still controls police counts and `DispatchJobs` still controls ps-dispatch groups. Existing crime chances remain in `Config.Police.Alerts`.

Phone delivery is optional and **disabled by default**. The supplied dispatch ZIP has no phone messaging export; its phone notifications use LB Phone. `Config.Police.Phone.Enabled = true` enables direct LB Phone server exports independently of the police chance roll. `Recipient = 'controller'` resolves the current network-chip controller from the serial registry (active hacker, otherwise the owner). `Mode = 'notification'` uses `SendNotification`; `'sms'` uses `SendMessage` and requires a valid `FromNumber`. Configure `Stages`, `Cooldown`, `Title` and `Message`; templates support `{serial}`, `{action}`, `{stage}`, `{title}` and `{message}`. An offline controller is resolved by their framework identifier via `GetEquippedPhoneNumber`; delivery requires a phone number known to LB Phone. A business-owned machine without a personal controller has no personal recipient. [LB Phone export reference](https://docs.lbscripts.com/phone/exports/server-exports/).

`Config.VendingMachines.GPS` controls movement detection. The first placed location is stored against the serial and survives picking up, towing, dropping and replacing the machine. Movement beyond `MovementThreshold` triggers an in-game alert to the **current chip controller**, throttled by `Cooldown` and checked every `CheckInterval` milliseconds. **Disable machine GPS** requires the configured electronic kit and wire minigame; disabling persists until someone with management/control access uses **Enable machine GPS**, which registers the current spot as the new home position. GPS movement phone messages remain optional. `Config.Police.Alerts.gps.chance.movement` defaults to 0: raise it to also send GPS movement to police dispatch.

`Config.VendingMachines.Skimmer` configures the custom prop, item and payment mode. Stream your own `metacomics_card_skimmer` drawable and register its archetype in the loaded `metacomics_props.ytyp` (or add your own YTYP to the manifest). **Install card skimmer** is blocked until that model is available on the installing client. `Offset` and `Rotation` attach it to the cabinet near the coin/card slot; tune these so the device slightly overlaps the slot. The prop is cosmetic; installation, payment recording, item removal and collection are server authoritative. Add `card_skimmer` from the inventory examples.

Skimmer `Mode` is `'record'` (default, logs purchases without diverting money), `'cut'` (retains `Percent` of card revenue), or `'divert'` (retains the entire card payment). The remaining revenue follows the machine's normal routing/tax rules. Cash purchases are unaffected. **Read card skimmer** lets its installer collect retained funds and see the recorded purchase count. Records are bounded by `MaxRecords`; balances survive mode changes, machine movement and restarts. The installer or a controller/manager can remove an empty skimmer and receive the item; retained funds must be collected first. A configured custom prop is required for the visible attachment—none is generated by these scripts.

### Moving machines: dolly and rope

While a player has a vending machine item they push it on a dolly (`Config.VendingCarry`): walking pace, no sprint, jump or weapons, until they get into a vehicle. A **stolen** machine can be tied to the back of a vehicle (ox_target on the vehicle, standing behind it) and dragged on a rope; the item leaves the inventory while it is dragged. **Untie vending machine** (ox_target on the machine or behind the towing vehicle) puts it back in the player's inventory. Dolly model, offsets, animation, pace and rope length are in the config.

Towed machines are journaled in `data/vending_tow_recovery.json`. On resource stop, ropes are detached and machine props are frozen; inventory returns and ownership database writes run after the next start. Recovery waits for an offline owner to join or a full inventory to have space. Preserve this file when deploying updates. Deploy the updated `stream/metacomics_vending_machine.ydr` too: its collision filters allow the cabinet to collide with the world while being dragged. `node scripts/fix-vending-collision.mjs` validates and reapplies those filters without changing the model geometry or textures.

`Config.VendingCarry.VehicleEntry` selects `'block'` (refuse vehicle entry while carrying a machine) or `'drop'` (attempting entry drops one machine in front of the player; try entering again once the inventory has updated). If carrying several machines, drop each before entering. Dropped cabinets use **Pick up vending machine** in ox_target and retain their serial, stock and cash. Removal and pickup run on the server.

`Config.VendingCarry.Tow.Physics` controls `Mass` (default 250), `Gravity` (1), `LinearDamping` (0.1, movement resistance) and `AngularDamping` (0.5, spin resistance). Set `Enabled = false` to use the model defaults. Physics settings are applied by the entity's network owner and reapplied when ownership changes; mass is separate from inventory item weight.

`Config.VendingCarry.Tow.Snap.Enabled` toggles automatic snapping. The server snaps the rope after an overload lasts `Duration` milliseconds (default 600), following `GracePeriod` after ground placement (3000). Overload means centre-to-centre separation exceeds `Tow.Length + Snap.ExtraDistance` (6 + 3 metres by default), or vehicle speed exceeds `MaxSpeedKmh` (100 by default; 0 disables the speed trigger). This is a distance/speed rule rather than a measurement of rope force. Snapping leaves the machine available for pickup, frees the vehicle for another tow, and preserves machine contents and restart recovery.

`Config.Police` sends alerts at the start, failure or success of an attempt, each with its own chance. `System = 'auto'` uses the first dispatch resource running (ps-dispatch, cd_dispatch, qs-dispatch, tk_dispatch, core_dispatch, rcore_dispatch, lb-tablet), else a built-in notification and blip for `Jobs`. `MinPolice` counts on-duty players in those jobs. Other scripts can raise one with the server export `PoliceAlert(source, { action = 'breakin', stage = 'start', coords = vec3(...), serial = 'VM-...' })`.

Existing MySQL tables get a `meta_json` column automatically (serial, cash and access). Deploy `fxmanifest.lua`, `config.lua` (the new blocks are `Shop.CashAccount / Payment / MaxCash`, `VendingMachines.Item / Ownership / Records / Crime`, `Config.Minigames` and `Config.Police`), the `client` and `server/modules` folders and a fresh NUI build (`npm run build:fivem`) together. Item definitions are in `examples/ox_inventory-items.lua` and `examples/qbcore-items.lua`.

## Money

`Config.Money` decides how each account is paid. `'framework'` uses QBCore / Qbox `player.Functions.AddMoney` / `RemoveMoney` (cash, bank or any other account) and the ox_core bank account; `'item'` uses an inventory item (`CashItem`, default the ox_inventory `money` item). `Cash = 'auto'` uses the item on ox_core and the framework cash everywhere else. `Custom = { add = ..., remove = ..., balance = ... }` plugs in any other money system.

## Crafting

`Config.Crafting` sets up workbenches (ox_target, optional prop) and recipes for any item: inventory items, booster packs and boxes, plushie and coin containers, shipping crates and vending machines. Each recipe can have a time, money cost, jobs, stations, managers-only and tools that aren't used up. Packs and boxes are made from `card_blank`, plushie boxes and cases from `generic_plushie`, coin bags and coin bag boxes from `coin_blank`; the blanks themselves are crafted from paper and plastic, fabric, and copper. Recipes saved in the admin UI replace the config ones, so press **Reset** in the Crafting tab to pick up new default recipes. Managers edit the recipes in the admin UI **Crafting** tab (Save / Revert, Reset goes back to the config) and can craft anywhere with `/collectiblescraft`. Other scripts: `exports['<resource>']:OpenCrafting(stationIndex)` (client) and `GetCraftingRecipes()` (server).

## Shipping crates

A `shipping_crate` item (crafted, or `/givecrate [crate id]` for managers, or the server export `GiveShippingCrate(source, crateId, count)`) holds a crate type from `Config.ShippingCrates.Crates`. Using it puts the crate prop on the ground, plays the prying animation with a crowbar (`Tool`), opens the lid in game and then shows a 3D reveal of the contents (`Animation3D`: lid, panels, pry, straps or random). The props are from the 2024 Bottom Dollar Bounties update, so add `set sv_enforceGameBuild 3258` (or newer) to `server.cfg`.

## Opening the UI from other scripts

`exports['<resource>']:OpenAdmin(tab)` opens the admin UI on a tab (`'vending'`, `'records'`, `'crafting'`, ...) after the server checks the management permission. `exports['<resource>']:GetEmbedUrl('admin', 'vending')` returns an address for an `<iframe>` in your own NUI page; it posts `metaComic:embedReady` and `metaComic:embedClose` to the parent window.

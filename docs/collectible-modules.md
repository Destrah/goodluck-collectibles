# Collectible systems

Choose Trading Cards, Plushies, or Challenge Coins using the system selector above the shared tabs. Each system provides Editor, Sets & containers, Collection, Effect sampler, and an opening lab. Editors and container/set changes use explicit Save/Revert. Switching systems asks before discarding drafts.

| System | Inner container | Default contents | Outer container | Default contents |
| --- | --- | --- | --- | --- |
| Cards | Booster pack | 5 cards | Booster box | 12 packs |
| Plushies | Plushie box | 1 plushie | Plushie case | 18 sealed plushie boxes |
| Challenge coins | Coin bag | 3 random coins | Coin bag box | 10 sealed coin bags |

Counts are configurable. Outer containers deliver sealed inner containers; those must be opened separately.

Openings are real-time Three.js scenes (`Container3D.js`, lazy-loaded like the card pack). The contents physically leave the container: coins and plushies land as silhouettes and are revealed by clicking, then clicked again to inspect; outer cases unpack miniature sealed containers. Each container has a saved **look** (design + opening animation) chosen in the Bag/Box lab and stored on the container config (`look` and `outer.look`), so every FiveM player sees it and sealed items carry it in their snapshot:

| Container | Designs | Animations |
| --- | --- | --- |
| Coin bag | Black velvet pouch, Meta satin pouch, Leather coin purse | Peek inside and float out, Tip over and pour, Shake and pop |
| Plushie box | Collector window box, Mystery flap cube, Ribbon lid box | Open the top, Walls fold down, Shake and burst |
| Outer case | Counter display box, Treasure chest, Wooden shipping crate | Open the lid, Walls fold down, Shake and burst |

Enlarged views of coins and plushies (lab, binder, FiveM items) use the same 3D models: drag to turn, hover to tilt and catch the light; finishes map to iridescent (rainbow), polished (metallic) and sparkling clearcoat (glitter). Plushies are inflated from their artwork outline into a closed, rounded shape; without back artwork the back shows the front colours softened. Coins accept face art position X/Y and zoom (same framing as card artwork, shared by the 2D and 3D coin), optional rim artwork (ring round the face), edge artwork (wrapped round the side) and an edge style (reeded, smooth, rope, studded, lettered). Opening sounds are synthesised per material (`src/utils/soundFx.js`, no audio files): cellophane rips for booster packs, wood creaks and hinge squeal for the chest, prying and plank clatter for the crate, tape and cardboard for boxes, fabric rustle, drawstring and coin jingle for pouches, and coin clinks / soft thumps as items land. Cards keep their foil/mask effects and show card-stock thickness when turned. Without WebGL everything falls back to the 2D CSS views. Supply front/back artwork URLs to author both sides; remote URLs work in both environments.

## Prints, rarity and weights

Coins and plushies have prints (versions) like trading cards. Every tab uses the same layouts as the trading cards: the editor has the shared identity (name, artwork, back, type fields, description, pull weight) and print tabs; each print has its own name, rarity tier (Common, Uncommon, Rare, Ultra Rare, Legendary), chance weight, artwork overrides, finish and accent. Coin prints add face-art framing, edge style, rim artwork and edge artwork; plushie prints add fabric colour (re-hues the artwork, keeping its shading) and seam stitching (colour, pattern: running, cross, zigzag, blanket, double row or hidden, and thread thickness), drawn along the plushie's outline on both halves.

Opening rolls in two stages, the same in standalone and on the server: the collectible by its pull weight, then one of its prints by the print's weight. The pulled snapshot is the definition with the print laid over it (`printId`, `printName`, `rarityKey`, `rarity`). Definitions saved before prints existed act as a single "Standard" print with id `base`.

## Inventory items and pictures

`fivem/examples/ox_inventory-collectibles.lua` (and the QBCore block in `qbcore-items.lua`) define the six items with pictures from `fivem/examples/ox_inventory_images/`. Every pulled coin / plushie item gets metadata: `label` (title + print), `description` (rarity · print), `rarity`, `rarityKey`, `printName`, `collectibleSnapshot` (what the game UI renders) and its picture. With `Config.CardIcons.Mode = 'upload'` each print's icon is drawn from its 3D model in a player's NUI and uploaded to Fivemanage — each collectible type into its own folder with its own optional API key (`Config.FivemanageFolders`, convars `metacomic_fivemanage_key_cards` / `_coins` / `_plushies`, falling back to `metacomic_fivemanage_key`). Until an icon exists, items use the rarity pictures `img/collectibles/metacoin_<rarity>.png` / `metaplush_<rarity>.png`.

Older resources that still use a previous `fxmanifest.lua` print a clear console error naming the files that were not loaded (trading cards keep working; coins and plushies stay off) — replace `fxmanifest.lua` and restart.

## Standalone

Browser storage persists generic definitions, sets, container settings, sealed containers, and acquired snapshots. Card sets and pack/box counts have separate browser storage alongside the existing card catalog. Set membership controls the random pool. A sealed generic container retains its saved count/configuration; the collectible definitions are resolved when it is opened. Once acquired, the collectible is a complete immutable copy, so later definition edits do not change it.

## FiveM deployment

Deploy the complete updated `fivem` resource, including `fxmanifest.lua`, client/server/shared Lua, `data/collectibles.sql`, and the rebuilt `web` folder. Building NUI alone does not deploy the new server endpoints. Preserve the live server's config values.

Register the six items in `fivem/examples/ox_inventory-collectibles.lua` with ox_inventory. Replace `RESOURCE` in the client export with the actual resource folder name. All use `stack=false` and `consume=0`; the server handles consumption. Framework usable items are also registered. Optional `Config.Collectibles.plushie` and `.challenge_coin` mappings accept `item`, `inner`, and `outer` inventory names.

With MySQL enabled and AutoCreateSchema enabled, startup creates the generic schema automatically. Otherwise import `data/collectibles.sql` before starting. The new tables are:

- `goodluck_collectibles_items`: collectible definitions with type-specific attributes.
- `goodluck_collectibles_sets`: named sets and their type.
- `goodluck_collectibles_set_items`: individual membership rows, position, and foreign keys.
- `goodluck_collectibles_containers`: saved container configuration and set reference.

Card/print tables stay separate. Catalog changes use focused transactions and update the server cache only after success; openings use that cache rather than querying the database for every item. Non-MySQL persistence writes `data/collectibles.json`.

Administration endpoints require management permission. Opening validates the exact owned inventory slot, uses its server-stored container metadata, rolls on the server, consumes the source, and adds the results. Capacity/delivery failures restore the source and roll back partial delivery. A permitted admin lab can simulate openings when `Config.Items.RequireForOpen` is false; simulations do not grant inventory items. Use the creation buttons for physical sealed items.

Physical generic collectibles carry their complete `collectibleSnapshot` in inventory metadata. Physical sealed containers carry `containerSnapshot`. Display uses those copies. The acquired collection reflects currently owned inventory items, not an ownership ledger in SQL. Existing card pull history remains separate.

Large RPC requests and results use the existing latent transport. Runtime remote artwork remains supported in both environments.

## Extending

`src/collectibles/registry.js` owns presentation registration; `objects.jsx` declares coin/plushie labels, fields, renderers, and nested container defaults. `CollectiblesLab.jsx` supplies the common workflow. `Container3D.js` builds the 3D containers, collectibles, openings and inspector; `ContainerOpening3D.jsx` hosts it and `container3dOptions.js` lists the designs. `ContainerVisual.jsx` and `ContainerOpening.jsx` are the 2D fallback, and `RotatableCollectible.jsx` supplies inspection.

The server type registry lives in `fivem/shared/collectibles.lua`. Cards register in `server/modules/trading_cards.lua`; generic objects use `server/modules/objects.lua`. A future type needs matching UI registration, validated server type/item mapping, usable inventory items, and container presentation. Generic objects do not enter trading-card binder slots.


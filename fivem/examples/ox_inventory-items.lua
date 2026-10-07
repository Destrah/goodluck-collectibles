-- Merge ONE of these two blocks into ox_inventory/data/items.lua (replace any older boosterpack / boosterbox / tradingcard entries).
-- consume = 0 in both: this resource checks and removes the item itself (one pack / one box per use).

-------------------------------------------------------------------------------------------------
-- A) QBCore or Qbox + ox_inventory (recommended). No client export: ox_inventory hands the use to
--    this resource's QBCore / Qbox usable items, so it works whatever the resource folder is called.
-------------------------------------------------------------------------------------------------
['boosterpack'] = {
    label = 'Trading Card Booster Pack',
    weight = 100,
    stack = true,
    close = true,
    consume = 0,
    description = 'A sealed Meta Comic Collectibles booster pack.'
},
['boosterbox'] = {
    label = 'Trading Card Booster Box',
    weight = 1000,
    stack = true,
    close = true,
    consume = 0,
    description = 'A sealed box containing booster packs.'
},
['tradingcard'] = {
    label = 'Trading Card',
    weight = 10,
    stack = false,
    close = true,
    consume = 0,
    description = 'A collectible trading card. Use it to view the card.'
},

-------------------------------------------------------------------------------------------------
-- B) Any framework + ox_inventory, with item pictures and a "Show Card" button (client exports).
--    'meta-comic' must be your resource folder name. Export names: OpenPack / OpenBox / ShowCard / ShowOthersCard
--    (useBoosterPack / useBoosterBox / useTradingCard also work). The server checks and removes the item itself.
-------------------------------------------------------------------------------------------------
-- ['boosterpack'] = {
--     label = 'Trading Card Booster Pack', weight = 100, stack = true, close = true, consume = 0,
--     description = 'A sealed Meta Comic Collectibles booster pack.',
--     client = { image = 'boosterpack_item.png', export = 'meta-comic.OpenPack' },
-- },
-- ['boosterbox'] = {
--     label = 'Trading Card Booster Box', weight = 1000, stack = true, close = true, consume = 0,
--     description = 'A sealed box containing booster packs.',
--     client = { image = 'booster_box_item.png', export = 'meta-comic.OpenBox' },
-- },
-- ['tradingcard'] = {
--     label = 'Trading Card', weight = 100, stack = false, close = true, consume = 0,
--     description = 'A trading card',
--     client = { image = 'tradingcard_item_purple.png', export = 'meta-comic.ShowCard' },
--     buttons = {
--         { label = 'Show Card', action = function(slot)
--             exports.ox_inventory:closeInventory()
--             exports['meta-comic']:ShowOthersCard(slot)
--         end },
--     },
-- },

-------------------------------------------------------------------------------------------------
-- Card binder. Two parts, both in ox_inventory (this resource can't create containers itself):
--  1) items.lua: the binder item with a "View Binder" button. Its name must be in Config.Items.Binder.
--  2) modules/items/containers.lua: make it a container. ox_inventory gives a binder its pockets when the item
--     is created, so restart ox_inventory and give yourself a NEW binder after adding this line.
-------------------------------------------------------------------------------------------------
-- ['trading_card_binder'] = {
--     label = 'Trading Card Binder', weight = 500, stack = false, close = false, consume = 0,
--     client = { image = 'tcbinder.png' },
--     buttons = {
--         { label = 'View Binder', action = function(slot)
--             exports.ox_inventory:closeInventory()
--             exports['meta-comic']:ViewBinder(slot)
--         end },
--     },
-- },
--
-- containers.lua:
-- setContainerProperties('trading_card_binder', {
--     slots = 36,               -- pockets (9 per binder page)
--     maxWeight = 3600,
--     whitelist = { 'tradingcard' },
-- })

-------------------------------------------------------------------------------------------------
-- Card case (slab case): an aluminium carry case. Cards stand upright in 8 compartments, slabs and toploaders
-- included. Same two parts as the binder; its name must be in Config.Items.CardCase. Image: card_case.png.
-------------------------------------------------------------------------------------------------
-- ['card_case'] = {
--     label = 'Card Case', weight = 1500, stack = false, close = false, consume = 0,
--     description = 'Aluminium carry case for slabs, toploaders and sleeved cards.',
--     client = { image = 'card_case.png' },
--     buttons = {
--         { label = 'View Case', action = function(slot)
--             exports.ox_inventory:closeInventory()
--             exports['meta-comic']:ViewCardCase(slot)
--         end },
--     },
-- },
--
-- containers.lua:
-- setContainerProperties('card_case', {
--     slots = 48,               -- 8 compartments of 6 (any multiple of 8 lays out evenly)
--     maxWeight = 6000,
--     whitelist = { 'tradingcard' },
-- })

-------------------------------------------------------------------------------------------------
-- Grading and card protection (Config.Grading). Add these buttons to your 'tradingcard' item (next to Show Card),
-- and the three supply items. 'meta-comic' must be your resource folder name.
-------------------------------------------------------------------------------------------------
-- ['tradingcard'] = {
--     ...,
--     buttons = {
--         { label = 'Show Card', action = function(slot) exports.ox_inventory:closeInventory() exports['meta-comic']:ShowOthersCard(slot) end },
--         { label = 'Grade card', action = function(slot) exports.ox_inventory:closeInventory() exports['meta-comic']:GradeCard(slot) end },
--         { label = 'Put in sleeve', action = function(slot) exports['meta-comic']:SleeveCard(slot) end },
--         { label = 'Put in toploader', action = function(slot) exports['meta-comic']:ToploaderCard(slot) end },
--         { label = 'Take out of sleeve / toploader', action = function(slot) exports['meta-comic']:UnprotectCard(slot) end },
--     },
-- },
-- Pictures: copy card_sleeve.png, card_toploader.png and grading_slab.png from examples/ox_inventory_images/
-- into ox_inventory/web/images/.
-- ['card_sleeve'] = { label = 'Card Sleeve', weight = 1, stack = true, close = true, description = 'A soft penny sleeve. Keeps a card from scuffing.', client = { image = 'card_sleeve.png' } },
-- ['card_toploader'] = { label = 'Toploader', weight = 15, stack = true, close = true, description = 'A rigid clear holder. Stops cards bending and creasing.', client = { image = 'card_toploader.png' } },
-- ['grading_slab'] = { label = 'Grading Slab', weight = 60, stack = true, close = true, description = 'An empty grading case. Grade a card to seal it inside.', client = { image = 'grading_slab.png' } },

-------------------------------------------------------------------------------------------------
-- Shipping crates, vending machines and machine records (add with either block above).
-- The client exports work with every framework; with QBCore / Qbox you can leave `client` out, the
-- items are also registered as usable there. Change 'meta-comic' to your resource folder name.
-------------------------------------------------------------------------------------------------
['shipping_crate'] = {
    label = 'Shipping Crate', weight = 25000, stack = false, close = true, consume = 0,
    description = 'A sealed crate of collectibles. Needs a crowbar to open.',
    client = { image = 'shipping_crate.png', export = 'meta-comic.UseShippingCrate' },
},
['vending_machine'] = {
    label = 'Vending Machine', weight = 60000, stack = false, close = true, consume = 0,
    description = 'A collectibles vending machine. Use it to set it up.',
    client = { export = 'meta-comic.UseVendingMachine' },
},
['vending_registration'] = {
    label = 'Vending Registration', weight = 10, stack = false, close = true, consume = 0,
    description = 'Registration papers for one vending machine.',
    client = { export = 'meta-comic.UseVendingRecord' },
},
['vending_ledger'] = {
    label = 'Vending Ledger', weight = 300, stack = false, close = true, consume = 0,
    description = 'The business ledger of vending machine owners.',
    client = { export = 'meta-comic.UseVendingLedger' },
},
['vending_key'] = {
    label = 'Vending Key', weight = 20, stack = false, close = true, consume = 0,
    description = 'Numbered cabinet key. Serial, cylinder and key ID remain readable after retirement.',
    client = { export = 'meta-comic.UseVendingKey' },
},
['vending_key_record'] = {
    label = 'Vending Key Records', weight = 10, stack = false, close = true, consume = 0,
    description = 'Printed permanent cylinder and key archive, including retired keys.',
    client = { export = 'meta-comic.UseVendingKeyRecord' },
},
['vending_lock_cylinder'] = {
    label = 'Vending Lock Cylinder', weight = 200, stack = true, close = true,
    description = 'Replacement cylinder for damaged locks or compromised keys.',
},
-- Tools used by the default recipes and crime settings, if your server doesn't have them yet:
['card_skimmer'] = {
    label = 'Card Skimmer', weight = 100, stack = true, close = true, consume = 0,
    description = 'A device that can be installed over a vending machine card reader.',
    client = { export = 'meta-comic.UseCardSkimmer' }, -- a removed skimmer with card data prints it out
    buttons = { { label = 'Read skimmer', action = function(slot) exports['meta-comic']:UseCardSkimmer(slot) end } },
},
['skimmer_card_data'] = {
    label = 'Card Data', weight = 10, stack = false, close = true, consume = 0,
    description = 'Card details copied by a card skimmer. A buyer will pay for these.',
    client = { export = 'meta-comic.UseSkimmerData' },
},
['vending_control_board'] = {
    label = 'Vending Control Board', weight = 500, stack = true, close = true,
    description = 'Replacement control board for recovering a compromised vending machine.',
},
-- crowbar, lockpick, laptop, electronickit, drill, and crafting materials paper, plastic, cardboard, glass,
-- rubber, aluminum, fabric, copper, wood, steel.
['card_blank'] = {
    label = 'Card Blank', weight = 2, stack = true, close = true,
    description = 'An unprinted trading card. Crafted into booster packs and boxes.',
},
['generic_plushie'] = {
    label = 'Generic Plushie', weight = 150, stack = true, close = true,
    description = 'A plain stuffed plushie. Crafted into plushie boxes and cases.',
},
['coin_blank'] = {
    label = 'Coin Blank', weight = 20, stack = true, close = true,
    description = 'An unstamped metal coin. Crafted into coin bags and coin bag boxes.',
},

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
    description = 'A sealed Meta Comic Collectables booster pack.'
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
--     description = 'A sealed Meta Comic Collectables booster pack.',
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

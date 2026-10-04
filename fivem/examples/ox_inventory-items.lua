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
    description = 'A sealed Rush Trading Cards booster pack.'
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
--    'rush-tradingcards' must be your resource folder name. Export names: OpenPack / OpenBox / ShowCard / ShowOthersCard
--    (useBoosterPack / useBoosterBox / useTradingCard also work). The server checks and removes the item itself.
-------------------------------------------------------------------------------------------------
-- ['boosterpack'] = {
--     label = 'Trading Card Booster Pack', weight = 100, stack = true, close = true, consume = 0,
--     description = 'A sealed Rush Trading Cards booster pack.',
--     client = { image = 'boosterpack_item.png', export = 'rush-tradingcards.OpenPack' },
-- },
-- ['boosterbox'] = {
--     label = 'Trading Card Booster Box', weight = 1000, stack = true, close = true, consume = 0,
--     description = 'A sealed box containing booster packs.',
--     client = { image = 'booster_box_item.png', export = 'rush-tradingcards.OpenBox' },
-- },
-- ['tradingcard'] = {
--     label = 'Trading Card', weight = 100, stack = false, close = true, consume = 0,
--     description = 'A trading card',
--     client = { image = 'tradingcard_item_purple.png', export = 'rush-tradingcards.ShowCard' },
--     buttons = {
--         { label = 'Show Card', action = function(slot)
--             exports.ox_inventory:closeInventory()
--             exports['rush-tradingcards']:ShowOthersCard(slot)
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
--             exports['rush-tradingcards']:ViewBinder(slot)
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

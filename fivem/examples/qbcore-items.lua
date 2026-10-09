-- Merge these into qb-core/shared/items.lua (adjust weights/images to your server).
['boosterpack'] = {
    name = 'boosterpack', label = 'Trading Card Booster Pack', weight = 100,
    type = 'item', image = 'boosterpack.png', unique = true, useable = true,
    shouldClose = true, description = 'A sealed Meta Comic Collectibles booster pack.'
},
['boosterbox'] = {
    name = 'boosterbox', label = 'Trading Card Booster Box', weight = 1000,
    type = 'item', image = 'boosterBox.png', unique = true, useable = true,
    shouldClose = true, description = 'A sealed box containing booster packs.'
},
['tradingcard'] = {
    name = 'tradingcard', label = 'Trading Card', weight = 10,
    type = 'item', image = 'Cards_Back.jpg', unique = true, useable = true,
    shouldClose = true, description = 'A collectible trading card instance.'
},

-- Challenge coins, plushies and their containers. Copy the pictures from examples/ox_inventory_images/
-- into your inventory's image folder (qb-inventory: html/images). Items carry their print's picture and
-- collectibleSnapshot in metadata (info) when pulled.
['challenge_coin'] = {
    name = 'challenge_coin', label = 'Challenge Coin', weight = 40,
    type = 'item', image = 'challenge_coin.png', unique = true, useable = true,
    shouldClose = true, description = 'A Meta Comics challenge coin. Use it to inspect it in 3D.'
},
['collectible_plushie'] = {
    name = 'collectible_plushie', label = 'Plushie', weight = 200,
    type = 'item', image = 'collectible_plushie.png', unique = true, useable = true,
    shouldClose = true, description = 'A Meta Comics plushie. Use it to inspect it in 3D.'
},
['coin_bag'] = {
    name = 'coin_bag', label = 'Meta Comics Coin Bag', weight = 150,
    type = 'item', image = 'coin_bag.png', unique = true, useable = true,
    shouldClose = true, description = 'A sealed velvet pouch of challenge coins.'
},
['coin_bag_box'] = {
    name = 'coin_bag_box', label = 'Meta Comics Coin Bag Box', weight = 1500,
    type = 'item', image = 'coin_bag_box.png', unique = true, useable = true,
    shouldClose = true, description = 'A case of sealed coin bags.'
},
['plushie_box'] = {
    name = 'plushie_box', label = 'Meta Comics Plushie Box', weight = 250,
    type = 'item', image = 'plushie_box.png', unique = true, useable = true,
    shouldClose = true, description = 'A sealed collector plushie box.'
},
['plushie_case'] = {
    name = 'plushie_case', label = 'Meta Comics Plushie Case', weight = 4500,
    type = 'item', image = 'plushie_case.png', unique = true, useable = true,
    shouldClose = true, description = 'A shipping case of sealed plushie boxes.'
},
['shipping_crate'] = {
    name = 'shipping_crate', label = 'Shipping Crate', weight = 25000,
    type = 'item', image = 'shipping_crate.png', unique = true, useable = true,
    shouldClose = true, description = 'A sealed crate of collectibles. Needs a crowbar to open.'
},
['vending_machine'] = {
    name = 'vending_machine', label = 'Vending Machine', weight = 60000,
    type = 'item', image = 'vending_machine.png', unique = true, useable = true,
    shouldClose = true, description = 'A collectibles vending machine. Use it to set it up.'
},
['vending_registration'] = {
    name = 'vending_registration', label = 'Vending Registration', weight = 10,
    type = 'item', image = 'vending_registration.png', unique = true, useable = true,
    shouldClose = true, description = 'Registration papers for one vending machine.'
},
['vending_ledger'] = {
    name = 'vending_ledger', label = 'Vending Ledger', weight = 300,
    type = 'item', image = 'vending_ledger.png', unique = true, useable = true,
    shouldClose = true, description = 'The business ledger of vending machine owners.'
},
['vending_key'] = {
    name = 'vending_key', label = 'Vending Key', weight = 20, type = 'item', image = 'vending_key.png',
    unique = true, useable = true, shouldClose = true, description = 'Numbered cabinet key; serial, cylinder and key ID remain readable after retirement.',
},
['vending_key_record'] = {
    name = 'vending_key_record', label = 'Vending Key Records', weight = 10, type = 'item', image = 'vending_key_record.png',
    unique = true, useable = true, shouldClose = true, description = 'Permanent printed cylinder and key archive, including retired keys.',
},
['vending_lock_cylinder'] = {
    name = 'vending_lock_cylinder', label = 'Vending Lock Cylinder', weight = 200, type = 'item', image = 'vending_lock_cylinder.png',
    unique = false, useable = false, shouldClose = true, description = 'Replacement cylinder for damaged locks or compromised keys.',
},
['vending_padlock'] = {
    name = 'vending_padlock', label = 'Vending Padlock', weight = 150, type = 'item', image = 'vending_padlock.png',
    unique = false, useable = false, shouldClose = true,
    description = 'Fit to a closed vending cabinet using a valid key for its current cylinder.',
},
['card_blank'] = {
    name = 'card_blank', label = 'Card Blank', weight = 2,
    type = 'item', image = 'card_blank.png', unique = false, useable = false,
    shouldClose = true, description = 'An unprinted trading card. Crafted into booster packs and boxes.'
},
['generic_plushie'] = {
    name = 'generic_plushie', label = 'Generic Plushie', weight = 150,
    type = 'item', image = 'generic_plushie.png', unique = false, useable = false,
    shouldClose = true, description = 'A plain stuffed plushie. Crafted into plushie boxes and cases.'
},
['coin_blank'] = {
    name = 'coin_blank', label = 'Coin Blank', weight = 20,
    type = 'item', image = 'coin_blank.png', unique = false, useable = false,
    shouldClose = true, description = 'An unstamped metal coin. Crafted into coin bags and coin bag boxes.'
},
['card_skimmer'] = {
    name = 'card_skimmer', label = 'Card Skimmer', weight = 100,
    type = 'item', image = 'card_skimmer.png', unique = true, useable = true, -- unique: a removed skimmer keeps its card data
    shouldClose = true, description = 'A device installed over a vending machine card reader.',
},
['skimmer_card_data'] = {
    name = 'skimmer_card_data', label = 'Card Data', weight = 10,
    type = 'item', image = 'skimmer_card_data.png', unique = true, useable = true,
    shouldClose = true, description = 'Card details copied by a card skimmer. A buyer will pay for these.',
},
['vending_control_board'] = {
    name = 'vending_control_board', label = 'Vending Control Board', weight = 500,
    type = 'item', image = 'vending_control_board.png', unique = false, useable = false,
    shouldClose = true, description = 'Replacement control board for recovering a compromised vending machine.',
},

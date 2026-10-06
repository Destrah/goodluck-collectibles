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

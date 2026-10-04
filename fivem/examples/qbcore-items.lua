-- Merge these into qb-core/shared/items.lua (adjust weights/images to your server).
['boosterpack'] = {
    name = 'boosterpack', label = 'Trading Card Booster Pack', weight = 100,
    type = 'item', image = 'boosterpack.png', unique = true, useable = true,
    shouldClose = true, description = 'A sealed Rush Trading Cards booster pack.'
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

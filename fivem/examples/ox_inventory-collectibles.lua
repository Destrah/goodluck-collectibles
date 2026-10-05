-- Challenge coins, plushies and their containers for ox_inventory.
-- Merge ONE of the two blocks below into ox_inventory/data/items.lua.
--
-- Pictures: copy these files from examples/ox_inventory_images/ into ox_inventory/web/images/:
--   challenge_coin.png  collectible_plushie.png  coin_bag.png  coin_bag_box.png  plushie_box.png  plushie_case.png
--   metacoin_<rarity>.png  metaplush_<rarity>.png   (rarity fallbacks: common, uncommon, rare, ultra_rare, legendary)
-- (the resource also copies the rarity fallbacks there itself when ox_inventory can't use picture urls).
--
-- Every coin / plushie item gets metadata from the server when it is pulled: label, description (rarity · print),
-- rarity, printName, collectibleSnapshot (what the game UI renders when the item is used) and its picture:
-- metadata.imageurl = its print's own icon uploaded to Fivemanage (Config.CardIcons.Mode = 'upload', in the
-- collectible's own folder, see Config.FivemanageFolders), or the rarity picture until that upload exists.
-- consume = 0 everywhere: the resource checks, rolls and removes items itself on the server.

-------------------------------------------------------------------------------------------------
-- A) QBCore or Qbox + ox_inventory (recommended). No client export: ox_inventory hands the use to
--    this resource's usable items, so it works whatever the resource folder is called.
-------------------------------------------------------------------------------------------------
['challenge_coin'] = {
    label = 'Challenge Coin',
    weight = 40,
    stack = false,
    close = true,
    consume = 0,
    description = 'A Meta Comics challenge coin. Use it to inspect it in 3D.',
    client = { image = 'challenge_coin.png' },
},
['collectible_plushie'] = {
    label = 'Plushie',
    weight = 200,
    stack = false,
    close = true,
    consume = 0,
    description = 'A Meta Comics plushie. Use it to inspect it in 3D.',
    client = { image = 'collectible_plushie.png' },
},
['coin_bag'] = {
    label = 'Meta Comics Coin Bag',
    weight = 150,
    stack = false,
    close = true,
    consume = 0,
    description = 'A sealed velvet pouch of challenge coins.',
    client = { image = 'coin_bag.png' },
},
['coin_bag_box'] = {
    label = 'Meta Comics Coin Bag Box',
    weight = 1500,
    stack = false,
    close = true,
    consume = 0,
    description = 'A case of sealed coin bags.',
    client = { image = 'coin_bag_box.png' },
},
['plushie_box'] = {
    label = 'Meta Comics Plushie Box',
    weight = 250,
    stack = false,
    close = true,
    consume = 0,
    description = 'A sealed collector plushie box.',
    client = { image = 'plushie_box.png' },
},
['plushie_case'] = {
    label = 'Meta Comics Plushie Case',
    weight = 4500,
    stack = false,
    close = true,
    consume = 0,
    description = 'A shipping case of sealed plushie boxes.',
    client = { image = 'plushie_case.png' },
},

-------------------------------------------------------------------------------------------------
-- B) Standalone + ox_inventory (no QBCore / Qbox): items call this resource's client export.
--    The export name is the resource folder name: change 'rush-tradingcards' if yours differs.
-------------------------------------------------------------------------------------------------
-- ['challenge_coin']      = { label = 'Challenge Coin', weight = 40, stack = false, close = true, consume = 0, description = 'A Meta Comics challenge coin. Use it to inspect it in 3D.', client = { image = 'challenge_coin.png', export = 'rush-tradingcards.UseCollectible' } },
-- ['collectible_plushie'] = { label = 'Plushie', weight = 200, stack = false, close = true, consume = 0, description = 'A Meta Comics plushie. Use it to inspect it in 3D.', client = { image = 'collectible_plushie.png', export = 'rush-tradingcards.UseCollectible' } },
-- ['coin_bag']            = { label = 'Meta Comics Coin Bag', weight = 150, stack = false, close = true, consume = 0, description = 'A sealed velvet pouch of challenge coins.', client = { image = 'coin_bag.png', export = 'rush-tradingcards.UseCollectible' } },
-- ['coin_bag_box']        = { label = 'Meta Comics Coin Bag Box', weight = 1500, stack = false, close = true, consume = 0, description = 'A case of sealed coin bags.', client = { image = 'coin_bag_box.png', export = 'rush-tradingcards.UseCollectible' } },
-- ['plushie_box']         = { label = 'Meta Comics Plushie Box', weight = 250, stack = false, close = true, consume = 0, description = 'A sealed collector plushie box.', client = { image = 'plushie_box.png', export = 'rush-tradingcards.UseCollectible' } },
-- ['plushie_case']        = { label = 'Meta Comics Plushie Case', weight = 4500, stack = false, close = true, consume = 0, description = 'A shipping case of sealed plushie boxes.', client = { image = 'plushie_case.png', export = 'rush-tradingcards.UseCollectible' } },


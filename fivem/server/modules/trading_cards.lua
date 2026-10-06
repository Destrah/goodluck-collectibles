-- Trading cards are the first collectible module. Other types register independently.
MetaComic.Collectibles.registerType('trading_card', {
    label = 'Trading Card',
    itemName = Config.Items.TradingCard,
    snapshotVersion = 1,
})

MetaComic.Collectibles.registerContainer('booster_pack', {
    typeId = 'trading_card',
    label = 'Booster Pack',
    itemName = Config.Items.BoosterPack,
    open = function(context)
        return MetaComic.Cards.openPack(context.owner, context.setId)
    end,
})

MetaComic.Collectibles.registerContainer('booster_box', {
    typeId = 'trading_card',
    label = 'Booster Box',
    itemName = Config.Items.BoosterBox,
    contains = 'booster_pack',
    count = function() return tonumber(Config.Items.PacksPerBox) or 12 end,
})

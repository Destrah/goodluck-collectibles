-- Trading cards are the first collectable module. Other types register independently.
MetaComic.Collectables.registerType('trading_card', {
    label = 'Trading Card',
    itemName = Config.Items.TradingCard,
    snapshotVersion = 1,
})

MetaComic.Collectables.registerContainer('booster_pack', {
    typeId = 'trading_card',
    label = 'Booster Pack',
    itemName = Config.Items.BoosterPack,
    open = function(context)
        return MetaComic.Cards.openPack(context.owner, context.setId)
    end,
})

MetaComic.Collectables.registerContainer('booster_box', {
    typeId = 'trading_card',
    label = 'Booster Box',
    itemName = Config.Items.BoosterBox,
    contains = 'booster_pack',
    count = function() return tonumber(Config.Items.PacksPerBox) or 12 end,
})

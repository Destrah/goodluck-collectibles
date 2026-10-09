-- Upgrade-only aliases. Active events, UI, documentation, and defaults use Meta Comic.
MetaComic.Legacy = {
    prefsKey = 'rush_cards:pack_prefs',
    uploadConvar = 'rushcards_fivemanage_key',
    manageAce = 'metacomic.manage',
    catalogAce = 'rushcards.catalog.write',
}

function MetaComic.Legacy.fallbackIcon(value)
    if type(value) ~= 'string' then return value end
    for _, rarity in ipairs({'common', 'uncommon', 'rare', 'ultra_rare', 'legendary'}) do
        local old = 'rushcard_' .. rarity
        local current = 'metacard_' .. rarity
        if value == old then return current end
        local previousUrl = ('nui://%s/img/cards/%s.png'):format(GetCurrentResourceName(), old)
        if value == previousUrl then return ('nui://%s/img/cards/%s.png'):format(GetCurrentResourceName(), current) end
    end
    return value
end

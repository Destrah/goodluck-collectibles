fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Meta Comic Collectibles modular integration'
description 'Standalone React trading cards with optional FiveM/QBCore/Qbox/database adapters'

ui_page 'web/index.html'

shared_scripts {
    'config.lua',
    'shared/utils.lua',
    'shared/card_buyer_zones.lua',
    'shared/vending_placement.lua',
    'shared/vending_cargo_geometry.lua',
    'shared/legacy.lua',
    'shared/collectibles.lua',
}

client_scripts {
    'client/main.lua',
    'client/vending_machines.lua',
    'client/vending_keys.lua',
    'client/prop_tuner.lua',
    'client/box_zone_tool.lua',
    'client/crafting.lua',
    'client/shipping_crates.lua',
    'client/minigames.lua',
    'client/police.lua',
    'client/vending_crime.lua',
    'client/vending_carry.lua',
    'client/vending_trunk_cargo.lua',
    'client/vending_door.lua',
    'client/vending_skimmer.lua',
    'client/card_buyers.lua',
}

server_scripts {
    'server/adapters/framework_standalone.lua',
    'server/adapters/framework_qbcore.lua',
    'server/adapters/framework_qbox.lua',
    'server/adapters/framework_ox_core.lua',
    'server/adapters/framework_custom.lua',
    'server/adapters/inventory_none.lua',
    'server/adapters/inventory_qbcore.lua',
    'server/adapters/inventory_ox.lua',
    'server/persistence/none.lua',
    'server/persistence/json.lua',
    'server/persistence/mysql.lua',
    'server/persistence/custom.lua',
    'server/runtime.lua',
    'server/sets.lua',
    'server/cards.lua',
    'server/modules/trading_cards.lua',
    'server/modules/objects.lua',
    'server/modules/grading.lua',
    'server/modules/sample_cards.lua',
    'server/modules/set_logos.lua',
    'server/modules/money.lua',
    'server/modules/runtime_saves.lua',
    'server/modules/settings.lua',
    'server/modules/vending_state.lua',
    'server/main.lua',
    'server/modules/rewards.lua',
    'server/modules/crafting.lua',
    'server/modules/shipping_crates.lua',
    'server/modules/police.lua',
    'server/modules/vending_registry.lua',
    'server/modules/vending_machines.lua',
    'server/modules/vending_keys.lua',
    'server/modules/vending_records.lua',
    'server/modules/vending_security.lua',
    'server/modules/crime_evidence.lua',
    'server/modules/vending_loot.lua',
    'server/modules/vending_crime.lua',
    'server/modules/vending_carry.lua',
    'server/modules/vending_trunk_cargo.lua',
    'server/modules/vending_trunks.lua',
    'server/modules/vending_door.lua',
    'server/modules/vending_testing.lua',
    'server/modules/prop_tuner.lua',
    'server/modules/card_buyer_stock.lua',
    'server/modules/card_buyers.lua',
    'server/modules/card_market_analysis.lua',
    'server/modules/box_zone_tool.lua',
}

files {
    'web/**/*',
    'img/**/*',
    'data/catalog.json',
    'data/sets.json',
    'data/collections.json',
    'stream/*.ydr',
    'stream/*.ytyp',
}

data_file 'DLC_ITYP_REQUEST' 'stream/booster_props.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/prop_deckbox_01.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/metacomics_props.ytyp'

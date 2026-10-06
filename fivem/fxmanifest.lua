fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Meta Comic Collectibles modular integration'
description 'Standalone React trading cards with optional FiveM/QBCore/Qbox/database adapters'

ui_page 'web/index.html'

shared_scripts {
    'config.lua',
    'shared/utils.lua',
    'shared/legacy.lua',
    'shared/collectibles.lua',
}

client_scripts {
    'client/main.lua',
    'client/vending_machines.lua',
}

server_scripts {
    'server/adapters/framework_standalone.lua',
    'server/adapters/framework_qbcore.lua',
    'server/adapters/framework_qbox.lua',
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
    'server/main.lua',
    'server/modules/vending_machines.lua',
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

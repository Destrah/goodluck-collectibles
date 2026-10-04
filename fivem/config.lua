Config = {}

-- Runtime adapters -----------------------------------------------------------
-- Framework: auto | standalone | qbcore | qbox | custom
Config.Framework = 'qbcore'

-- Inventory: auto | none | qbcore | ox_inventory
Config.Inventory = 'ox_inventory'

-- Persistence: none | json | mysql | custom
Config.Persistence = 'json'



-- FiveM management permissions ------------------------------------------------
-- These permissions control ALL content-authoring / item-production actions:
-- card add/edit, manual card printing, set/series management, and creating
-- sealed booster packs / boxes. Normal players can still open/use items.
Config.Management = {
    Enabled = true,
    Ace = 'rushcards.manage', -- server.cfg: add_ace group.admin rushcards.manage allow

    -- QBCore server permissions checked with QBCore.Functions.HasPermission.
    -- Leave empty to rely only on ACE/jobs/identifiers.
    QBCorePermissions = { 'admin', 'god' },

    -- Job access. Example:
    -- Jobs = { cardshop = 0, police = 4 }
    -- Value is the minimum grade required. Leave empty if jobs should not grant access.
    Jobs = {},

    -- Qbox groups/citizenids accepted by qbx_core:HasGroup. Examples:
    -- QboxGroups = { cardshop = 0, ['CID12345'] = 0 }
    QboxGroups = {},

    -- Exact identifiers that may manage cards (license:, license2:, or citizen id).
    Identifiers = {},

    -- Safety cap for one click in the FiveM production screen.
    MaxCreateAmount = 100,
}

-- Card series / sets ---------------------------------------------------------
Config.Sets = {
    File = 'data/sets.json',
    Default = 'base',
}

Config.Catalog = {
    File = 'data/catalog.json',
    AllowWrite = true,
    WriteAce = 'rushcards.catalog.write',
}

Config.Items = {
    -- Using a booster pack item opens it in the middle of the player's screen.
    -- Using a booster box item gives PacksPerBox booster pack items (box animation: coming later).
    RegisterUsableItems = true,
    -- How item use reaches this resource:
    --   'auto'      both routes below (recommended)
    --   'framework' QBCore / Qbox / custom usable-item callbacks (with ox_inventory: items WITHOUT a client export)
    --   'ox_export' ox_inventory item definitions with client.export (standalone + ox_inventory)
    -- Item definitions for each setup: examples/ox_inventory-items.lua and examples/qbcore-items.lua
    UseMethod = 'auto',
    -- Only for /cardpack, /cardbox and the lab: when true those also need (and take) the item.
    -- Using the items from the inventory always takes them.
    RequireForOpen = false,
    BoosterPack = 'boosterpack',
    BoosterBox = 'boosterbox',
    TradingCard = 'tradingcard',
    Binder = { 'trading_card_binder', 'cardbinder' }, -- your binder item name(s); it must be an ox_inventory container (containers.lua)
    GiveCardItems = true, -- every pulled card is also given as a 'tradingcard' item (5 per pack); using one shows the card
    BoxGivesPackItems = true,
    PacksPerBox = 12, -- booster packs given per booster box
}

-- Inventory icon for card items.
Config.CardIcons = {
    Enabled = true, -- false: use the card's artwork instead
    -- 'rarity': one picture per rarity (img/cards/rushcard_<rarity>.png, 100x100). Nothing to set up.
    -- 'upload': every card gets one 100x100 icon per rarity it comes in (max 5 per card, shared by all its variants and
    --           copies), drawn in a player's game UI and uploaded to Fivemanage once.
    --           Missing / outdated icons are made automatically: when the resource starts, when a player joins, when
    --           the catalog is saved in-game (new or edited cards) and when a print is pulled from a pack.
    --           Put your Fivemanage API key in server.cfg (NOT here: this file is sent to players):
    --             set rushcards_fivemanage_key "your-api-key"
    --           Uploaded URLs are remembered in data/card_icons.json. Until a print's icon is uploaded it uses the rarity icon.
    -- ox_inventory note: with the convar inventory:webhook set, ox_inventory deletes item picture urls it doesn't
    -- trust (before 2.45.1 everything except i.imgur.com). The script detects this and falls back to
    -- ox_inventory/web/images/rushcard_<rarity>.png (copied there for you); update ox_inventory for per-card icons.
    Mode = 'upload',
    Size = 100,
    OxImageFiles = false, -- true: also set metadata.image on every card item (only needed for custom inventory forks)
    RefreshCommand = 'cardicons', -- in game: updates your card items. Server console: retries missing icons. ('' to disable)
}

-- Card binder (an ox_inventory container item). Add a "View Binder" button to it (examples/ox_inventory-items.lua).
Config.Binder = {
    DefaultPockets = 100, -- shown if the binder has never been opened yet (ox creates its container on first open)
}

-- ox_inventory "Show Card" item button: shows the card to players standing near you
Config.ShowCard = {
    Distance = 3.0, -- metres
    Seconds = 8,    -- how long it stays on their screen (they can close it sooner)
}

Config.PackAnimation = {
    MaxSpeed = 3.0, -- highest pack-opening speed a player can pick (1.0 = original pace)
    FlipAllKey = 'F', -- NUI key shown during a reveal; press it to flip every remaining card
}

Config.Database = {
    Resource = 'oxmysql',
    Table = 'rush_trading_card_instances',
    AutoCreateSchema = true,
}

Config.JsonPersistence = {
    File = 'data/collections.json',
}

Config.Nui = {
    DefaultView = 'pack',
    AllowEditor = true,
}

Config.Commands = {
    Open = 'cards',
    Pack = 'cardpack',
    Box = 'cardbox',
    Options = 'cardoptions', -- per-player tear / fan / speed preferences
    Management = 'cardadmin', -- restricted set / pack / box / manual print tools
}

Config.Props = {
    Enabled = true,
    Pack = {
        model = 'prop_boosterpack_01',
        duration = 1100,     -- unused for packs now: the character holds the pack until the cards have fanned out
        MaxDuration = 30000, -- safety limit for that animation (ms)
        bone = 0xDEAD,
        offset = vector3(0.10, 0.10, 0.00),
        rotation = vector3(70.0, 10.0, 90.0),
    },
    Box = {
        model = 'prop_boosterbox_01',
        duration = 1500,
        bone = 0xDEAD,
        offset = vector3(0.10, 0.10, 0.00),
        rotation = vector3(70.0, 10.0, 90.0),
    },
    DeckBox = {
        model = 'prop_deckbox_01',
    },
}

Config.Debug = false -- true: prints every item use / removal step to the server console

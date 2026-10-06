Config = {}

-- Runtime adapters -----------------------------------------------------------
-- Framework: auto | standalone | qbcore | qbox | custom
Config.Framework = 'qbcore'

-- Inventory: auto | none | qbcore | ox_inventory
Config.Inventory = 'ox_inventory'

-- Persistence: none | json | mysql | custom
Config.Persistence = 'mysql'



-- FiveM management permissions ------------------------------------------------
-- These permissions control ALL content-authoring / item-production actions:
-- card add/edit, manual card printing, set/series management, and creating
-- sealed booster packs / boxes. Normal players can still open/use items.
Config.Management = {
    Enabled = true,
    Ace = 'metacomic.manage', -- server.cfg: add_ace group.admin metacomic.manage allow

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
    WriteAce = 'metacomic.catalog.write',
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
    CardCase = { 'card_case' }, -- slab / card case item name(s): an ox_inventory container like the binder, holds any card incl. slabs
    GiveCardItems = true, -- every pulled card is also given as a 'tradingcard' item (5 per pack); using one shows the card
    BoxGivesPackItems = true,
    PacksPerBox = 12, -- booster packs given per booster box
}

-- Inventory icon for card items.
Config.CardIcons = {
    Enabled = true, -- false: use the card's artwork instead
    -- 'rarity': one picture per rarity (img/cards/metacard_<rarity>.png, 100x100). Nothing to set up.
    -- 'upload': one 100x100 icon per distinct look (prints that look the same share it; full art / another colour gets
    --           its own), drawn in a player's game UI and uploaded to Fivemanage once. Icons of deleted looks are deleted.
    --           Missing / outdated icons are made automatically: when the resource starts, when a player joins, when
    --           the catalog is saved in-game (new or edited cards) and when a print is pulled from a pack.
    --           Put your Fivemanage API key in server.cfg (NOT here: this file is sent to players):
    --             set metacomic_fivemanage_key "your-api-key"
    --           Uploaded URLs are remembered in data/card_icons.json. Until a print's icon is uploaded it uses the rarity icon.
    -- ox_inventory note: with the convar inventory:webhook set, ox_inventory deletes item picture urls it doesn't
    -- trust (before 2.45.1 everything except i.imgur.com). The script detects this and falls back to
    -- ox_inventory/web/images/metacard_<rarity>.png (copied there for you); update ox_inventory for per-card icons.
    Mode = 'upload',
    Size = 100,
    OxImageFiles = false, -- true: also set metadata.image on every card item (only needed for custom inventory forks)
    RefreshCommand = 'collectiblesicons', -- in game: updates item icons. Server console: retries missing icons. ('' to disable)
}

-- Fivemanage upload settings per collectible: each type's inventory icons go into its own folder (Path) and may
-- use its own API key. Put keys in server.cfg (this file is sent to players), e.g.
--   set metacomic_fivemanage_key_coins "api-key"
-- A type whose own key convar is empty uses metacomic_fivemanage_key. Coins and plushies follow the same
-- Config.CardIcons settings (Mode / Size / OxImageFiles); their rarity fallback pictures are
-- img/collectibles/metacoin_<rarity>.png and metaplush_<rarity>.png.
Config.FivemanageFolders = {
    trading_card = { Path = 'Collectibles/Trading Cards', KeyConvar = 'metacomic_fivemanage_key_cards' },
    challenge_coin = { Path = 'Collectibles/Challenge Coins', KeyConvar = 'metacomic_fivemanage_key_coins' },
    plushie = { Path = 'Collectibles/Plushies', KeyConvar = 'metacomic_fivemanage_key_plushies' },
    -- artwork uploaded in the card / coin / plushie editors (stored as a URL instead of inline in the database);
    -- an empty key convar falls back to metacomic_fivemanage_key_cards, then metacomic_fivemanage_key
    artwork = { Path = 'Collectibles/Artwork', KeyConvar = 'metacomic_fivemanage_key_artwork' },
}

-- Card binder (an ox_inventory container item). Add a "View Binder" button to it (examples/ox_inventory-items.lua).
Config.Binder = {
    DefaultPockets = 100, -- shown if the binder has never been opened yet (ox creates its container on first open)
}

-- Card case (an ox_inventory container item, "View Case" button): cards stand upright in compartments, slabs too.
Config.CardCase = {
    DefaultSlots = 48, -- shown if the case has never been opened yet (8 compartments)
    Style = 'compartments', -- default layout: 'compartments', 'foam' (cut-out display) or 'topdown' (players can switch; their pick is remembered)
}

-- ox_inventory "Show Card" item button: shows the card to players standing near you
Config.ShowCard = {
    Distance = 3.0, -- metres
    Seconds = 8,    -- how long it stays on their screen (they can close it sooner)
}

-- Card condition and grading. Every pulled card copy has small print imperfections (centering, shifted art / text /
-- foil, corner and edge wear, sometimes a scratch, dent or crease) in its item metadata. Unprotected cards wear when
-- handled (used / shown, and badly when spun hard in the viewer); sleeves help, toploaders and slabs stop it.
-- Grading (the "Grade card" item button): the player inspects the card and marks its flaws; the server confirms
-- each mark (nothing that isn't there can be marked) and the slab's grade is made of the flaws they found.
-- Item buttons and items: examples/ox_inventory-items.lua.
Config.Grading = {
    Enabled = true,
    Debug = true,                   -- show real flaws and condition tolerances on the grading bench
    SlabItem = 'grading_slab',       -- an empty slab, used up by grading a card
    RequireSlabItem = true,
    SleeveItem = 'card_sleeve',      -- penny sleeve
    ToploaderItem = 'card_toploader',
    MaxWrongMarks = 6,               -- marks that turn out wrong before the grader has to submit or cancel
    Wear = true,                     -- false: cards never wear from handling
    Ace = '',                        -- optional ace a player needs to grade, e.g. 'metacomic.grade' (empty: anyone)
    GradeAdjust = 1,                 -- the grader picks the slab's grade up to this far (in grades) from what their
                                     -- confirmed calls suggest (0: always the suggestion). The record shows both.
    LookupCommand = 'gradecheck',    -- /gradecheck <cert>: anyone can look up a slab's grade, grader and marked flaws
}

Config.PackAnimation = {
    MaxSpeed = 3.0, -- highest pack-opening speed a player can pick (1.0 = original pace)
    FlipAllKey = 'F', -- NUI key shown during a reveal; press it to flip every remaining card
}

Config.Database = {
    Resource = 'oxmysql',
    Table = 'goodluck_collectibles_card_instances',
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
    Open = 'collectibles',
    Pack = 'collectiblespack',
    Box = 'collectiblesbox',
    Options = 'collectiblesoptions', -- per-player pack and collectible animation preferences
    Management = 'collectiblesadmin', -- restricted authoring / item production tools
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
    -- The character holds what they're looking at: their own card / coin / plushie when it is used ('view': looking
    -- down at it) or shown to others ('show': held out), and the pulls (as many as came out) after opening a pack,
    -- coin bag or plushie box, until the UI closes. Generic base-game props. Anything left out uses the built-in
    -- default (client/main.lua DEFAULT_HELD); models = list, the first one the game has is used.
    -- view / show = { dict, anim, bone, offset, rotation }. rotationOrder = 1 (emote-menu placements). Held = false turns it off.
    Held = {
        MaxDuration = 300, -- seconds: safety limit
        -- card  = { models = { 'prop_franklin_dl' }, max = 5,
        --           view = { dict = 'amb@world_human_tourist_map@male@base', anim = 'base', bone = 28422, offset = vector3(0.0, -0.03, 0.0), rotation = vector3(20.0, -90.0, 0.0) },
        --           show = { dict = 'paper_1_rcm_alt1-9', anim = 'player_one_dual-9', bone = 57005, offset = vector3(0.10, 0.02, -0.03), rotation = vector3(-90.0, 170.0, 78.0) } },
        -- coin  = { models = { 'vw_prop_vw_coin_01a', 'vw_prop_chip_100dollar_x1' }, max = 5 },
        -- plush = { models = { 'v_ilev_mr_rasberryclean' }, max = 2,
        --           view = { rotation = vector3(-180.0, -90.0, 0.0) }, show = { rotation = vector3(-180.0, -90.0, 0.0) } },
    },
    -- Held while a coin bag / plushie box / outer case opens (with the pack-opening hand animation); then the pulls
    -- are held as above. model = list, the first one the game has is used.
    -- Containers = {
    --     bag  = { model = { 'prop_paper_bag_small' }, bone = 0xDEAD, offset = vector3(0.10, 0.02, -0.02), rotation = vector3(0.0, 0.0, 0.0) },
    --     box  = { model = { 'prop_boosterbox_01' } },
    --     case = { model = { 'prop_boosterbox_01' } },
    -- },
}

-- Coin bags, plushie boxes and their outer cases come in three designs each (picked when creating them in
-- Sets & containers). Each design shows its own inventory picture, ox_inventory/web/images/<item>_<design>.png;
-- the pictures are in fivem/img/containers. false: every design uses the item's normal picture.
Config.Collectibles = Config.Collectibles or {}
Config.Collectibles.ContainerImages = true

-- Placeable vending machines (stream/metacomics_vending_machine.ydr). Managers place them in game; they are saved with
-- Config.Persistence (MySQL table below, otherwise the JSON file) and every player spawns them locally only when near.
Config.VendingMachines = {
    Enabled = true,
    Model = 'metacomics_vending_machine',
    Command = 'placevending',        -- look around, rotate, place (management permission, like /collectiblesadmin)
    RemoveCommand = 'removevending', -- removes the closest placed machine within RemoveDistance
    PlaceDistance = 15.0,            -- metres from the player a machine can be placed
    RemoveDistance = 5.0,
    GhostAlpha = 150,                -- see-through preview while placing (0-255)
    SpawnDistance = 100.0,           -- prop appears when a player is this close
    DespawnDistance = 120.0,         -- and is deleted again beyond this
    Table = 'goodluck_collectibles_vending_machines', -- MySQL (created automatically with Config.Database.AutoCreateSchema)
    File = 'data/vending_machines.json',             -- JSON persistence
    -- ox_target on every machine (menus need ox_lib): Buy for everyone, Restock for managers + Restock.Jobs, Manage for
    -- managers (pick which sets' packs / boxes this machine sells, prices and stock). Each machine saves its own products.
    -- Account 'money': the ox_inventory money item (QBCore cash with ox_inventory), else the framework account
    -- ('cash' / 'bank'). The server checks the price, stock, the player's distance and inventory space before charging.
    Shop = {
        Enabled = true,
        TargetDistance = 2.0,
        Account = 'bank',
        -- what a newly placed machine sells (change it per machine with Manage). set = a card set id (nil: the default set)
        Items = {
            { kind = 'pack', set = nil, price = 250 },
            { kind = 'box', set = nil, price = 2500 },
        },
    },
    Restock = {
        -- Managers and these jobs may restock (job name = minimum grade), e.g. { cardshop = 0 }. Restocking always
        -- takes that many sealed packs / boxes of the product's set from the restocker's inventory.
        Jobs = {},
        MaxStock = 100, -- per product
    },
    -- Admin UI "Vending machines" tab (/collectiblesadmin): every machine on a map with its stock. Put a square GTA V
    -- map picture at Image (a path in this resource or an https URL; without one a grid is shown). The numbers line
    -- world coordinates up with the common 8192px GTA V map tiles; adjust them if your picture is cropped differently.
    Map = {
        Image = 'img/map/gtav_map.jpg',
        CenterX = 117.3, CenterY = 172.8, ScaleX = 0.02072, ScaleY = 0.0205,
    },
}

Config.Debug = false -- true: prints every item use / removal step to the server console

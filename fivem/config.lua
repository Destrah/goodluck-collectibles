Config = {}

-- Runtime adapters -----------------------------------------------------------
-- Framework: auto | standalone | qbcore | qbox | ox_core | custom
Config.Framework = 'qbcore'

-- Inventory: auto | none | qbcore | ox_inventory
Config.Inventory = 'ox_inventory'

-- Money (crafting prices, vending machine sales, payouts). Per account: 'framework' = QBCore / Qbox
-- player.Functions.AddMoney / RemoveMoney (ox_core: its bank account), 'item' = an inventory item (CashItem),
-- 'auto' = 'item' for cash on ox_core (its cash is the ox_inventory money item), else 'framework'.
-- Custom = { add = function(source, account, amount, reason) return true end, remove = ..., balance = ... } for any
-- other money system (return nil to fall back to the setting above).
Config.Money = {
    Cash = 'auto',      -- 'auto' | 'framework' | 'item'
    Bank = 'framework', -- 'framework' | 'item'
    CashItem = 'money',
    Custom = nil,
}

-- Persistence: none | json | mysql | custom
Config.Persistence = 'mysql'
-- Server-owned runtime state: coalesce writes and flush/checkpoint on resource shutdown.
Config.RuntimeSaves = { IntervalSeconds = 30 }



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

    -- ox_core groups (Config.Framework = 'ox_core'), group name = minimum grade. Example:
    -- OxGroups = { admin = 0, cardshop = 2 }
    OxGroups = {},

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
    -- For free pack/box tests in the lab or exports: when true those also need (and take) the item.
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

-- Portal: admin UI tabs for people who aren't managers, e.g. on a business tablet that embeds them with
-- exports['<resource>']:GetEmbedUrl('admin', { 'vending', 'records' }). Managers get every tab. Registered vending
-- machine owners (people leasing machines) get OwnerTabs, which only show their own machines. Editor says who else
-- gets the card editor (e.g. the business owner). Test it with /cardportal [tabs], e.g. /cardportal vending,records
-- (as an owner: register yourself in Machine records, assign yourself a machine, then /vendingtestrole player).
Config.Portal = {
    Enabled = true,
    Command = 'cardportal',
    OwnerTabs = { 'vending', 'records' },
    Editor = { Ace = 'metacomic.editor', Jobs = {}, Identifiers = {} }, -- Jobs = { cardshop = 4 } (minimum grade)
}

-- Open/Pack/Box are retained for config compatibility but no longer register chat commands.
-- Player preferences remain available through /collectiblesoptions.
-- Inventory items and client exports provide those actions.
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

-- Crafting. These recipes are the defaults: once a manager saves recipes in the admin UI ("Crafting" tab) the saved
-- list is used instead (Reset there goes back to these). Ingredients are item names from your inventory.
-- result.type:
--   'item'      { item = 'card_sleeve', count = 10 }            any inventory item
--   'sealed'    { kind = 'pack' | 'box', set = nil, count = 1 }  booster pack / box of a card set (nil = default set)
--   'container' { collectible = 'plushie' | 'challenge_coin', outer = false }  plushie box / case, coin bag / bag box
--   'crate'     { crate = 'mixed' }                             shipping crate (Config.ShippingCrates)
--   'vending'   {}                                              vending machine item (Config.VendingMachines.Item)
-- Per recipe: time (ms, per item), money + account ('cash' | 'bank'), jobs = { jobname = minGrade },
-- managersOnly, stations = { 'station id', ... } (nil = all), ingredient keep = true (a tool that is not used up).
Config.Crafting = {
    MinigameAce = 'metacomic.manage', -- ACE required to edit production settings in collectiblesadmin
    Enabled = true,
    Command = 'collectiblescraft', -- managers: craft anywhere ('' to disable)
    MaxAmount = 25,                -- most items crafted in one go
    Animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 }, -- or { scenario = 'PROP_HUMAN_BUM_BIN' }
    -- Crafting benches (ox_target). model: optional prop spawned at the spot. recipes: recipe ids (nil = all).
    Stations = {
        -- { id = 'shop_bench', label = 'Collectibles workbench', coords = vec3(0.0, 0.0, 0.0), heading = 0.0, radius = 1.5,
        --   model = 'prop_tool_bench02', jobs = { cardshop = 0 }, recipes = nil },
    },
    Recipes = {
        -- blanks: printed / stamped / stuffed into the right collectible when a pack, plushie box or coin bag is made
        { id = 'card_blank', label = 'Card Blanks (10)', category = 'Materials', time = 3000,
          result = { type = 'item', item = 'card_blank', count = 10 },
          ingredients = { { item = 'paper', count = 2 }, { item = 'plastic', count = 1 } } },
        { id = 'generic_plushie', label = 'Generic Plushie', category = 'Materials', time = 3000,
          result = { type = 'item', item = 'generic_plushie', count = 1 },
          ingredients = { { item = 'fabric', count = 3 } } },
        { id = 'coin_blank', label = 'Coin Blank', category = 'Materials', time = 2000,
          result = { type = 'item', item = 'coin_blank', count = 1 },
          ingredients = { { item = 'copper', count = 1 } } },
        { id = 'booster_pack', label = 'Booster Pack', category = 'Cards', time = 4000,
          minigame = { enabled = true, cutter = 'random', cols = 5, rows = 3, rewardPacks = 3,
            maxErrors = 6, time = 900, minSeconds = 20, flawChance = 0.5, bonusSeconds = 180, bonusPacks = 1,
            bulkBonusEvery = 5, bulkBonusPacks = 1, bulkBonusMax = 5, scaleBonusTime = true },
          result = { type = 'sealed', kind = 'pack', count = 1 },
          ingredients = { { item = 'card_blank', count = 10 }, { item = 'plastic', count = 1 } } },
        { id = 'booster_box', label = 'Booster Box', category = 'Cards', time = 10000,
          result = { type = 'sealed', kind = 'box', count = 1 },
          ingredients = { { item = 'cardboard', count = 2 }, { item = 'card_blank', count = 60 }, { item = 'plastic', count = 6 } } },
        { id = 'card_sleeve', label = 'Card Sleeves (10)', category = 'Supplies', time = 3000,
          result = { type = 'item', item = 'card_sleeve', count = 10 },
          ingredients = { { item = 'plastic', count = 1 } } },
        { id = 'card_toploader', label = 'Toploaders (2)', category = 'Supplies', time = 3000,
          result = { type = 'item', item = 'card_toploader', count = 2 },
          ingredients = { { item = 'plastic', count = 2 } } },
        { id = 'grading_slab', label = 'Grading Slab', category = 'Supplies', time = 5000,
          result = { type = 'item', item = 'grading_slab', count = 1 },
          ingredients = { { item = 'plastic', count = 3 }, { item = 'glass', count = 1 } } },
        { id = 'card_binder', label = 'Card Binder', category = 'Supplies', time = 6000,
          result = { type = 'item', item = 'trading_card_binder', count = 1 },
          ingredients = { { item = 'plastic', count = 4 }, { item = 'rubber', count = 1 } } },
        { id = 'card_case', label = 'Card Case', category = 'Supplies', time = 8000,
          result = { type = 'item', item = 'card_case', count = 1 },
          ingredients = { { item = 'plastic', count = 6 }, { item = 'aluminum', count = 2 } } },
        { id = 'plushie_box', label = 'Plushie Box', category = 'Collectibles', time = 6000,
          result = { type = 'container', collectible = 'plushie', outer = false },
          ingredients = { { item = 'generic_plushie', count = 4 }, { item = 'cardboard', count = 1 } } },
        { id = 'plushie_case', label = 'Plushie Case', category = 'Collectibles', time = 15000,
          result = { type = 'container', collectible = 'plushie', outer = true },
          ingredients = { { item = 'generic_plushie', count = 30 }, { item = 'cardboard', count = 6 } } },
        { id = 'coin_bag', label = 'Coin Bag', category = 'Collectibles', time = 6000,
          result = { type = 'container', collectible = 'challenge_coin', outer = false },
          ingredients = { { item = 'coin_blank', count = 3 }, { item = 'fabric', count = 1 } } },
        { id = 'coin_bag_box', label = 'Coin Bag Box', category = 'Collectibles', time = 15000,
          result = { type = 'container', collectible = 'challenge_coin', outer = true },
          ingredients = { { item = 'coin_blank', count = 30 }, { item = 'cardboard', count = 4 } } },
        { id = 'shipping_crate', label = 'Shipping Crate', category = 'Shipping', time = 20000,
          result = { type = 'crate', crate = 'mixed' },
          ingredients = { { item = 'wood', count = 10 }, { item = 'steel', count = 4 }, { item = 'boosterbox', count = 2 } } },
        { id = 'vending_machine', label = 'Vending Machine', category = 'Business', time = 30000, managersOnly = true,
          result = { type = 'vending' },
          ingredients = { { item = 'steel', count = 20 }, { item = 'glass', count = 6 }, { item = 'hackingdevice', count = 2 } } },
        { id = 'vending_lock_cylinder', label = 'Vending Lock Cylinder', category = 'Business', time = 15000, managersOnly = true,
          result = { type = 'item', item = 'vending_lock_cylinder', count = 1 },
          ingredients = { { item = 'steel', count = 2 }, { item = 'aluminum', count = 1 } } },
    },
}

-- Shipping crates: one big crate item ('shipping_crate') that a player pries open to get the large collectible containers
-- inside (booster boxes, plushie / coin boxes and cases). Using the item puts the crate prop on the ground in front of the
-- player, plays the prying animation, opens the lid in game and then shows a 3D reveal of the contents.
-- The default crate uses a separate matching lid. Alternate DLC shells need a compatible enforced game build.
-- Contents use the same result list as crafting (type 'sealed' / 'container' / 'item'); chance = % (default 100).
-- ox_inventory item: ['shipping_crate'] = { label = 'Shipping Crate', weight = 25000, stack = false, close = true,
--   client = { image = 'shipping_crate.png' } }
Config.ShippingCrates = {
    Enabled = true,
    Item = 'shipping_crate',
    Default = 'mixed',          -- crate id when the item has none
    GiveCommand = 'givecrate',  -- managers: /givecrate [crate id] ('' to disable)
    OpenTime = 6000,            -- ms prying it open (per crate: openTime)
    Tool = { item = 'weapon_crowbar', label = 'crowbar' }, -- configurable inventory item; not consumed. false: no tool required
    Models = {
        Closed = 'prop_ld_crate_01', -- crate base; the matching lid is attached while sealed
        Open = 'prop_ld_crate_01',
        Lid = 'prop_ld_crate_lid_01',
        SeparateLid = true,
        -- Alternative shell pair: Closed='xm3_prop_xm3_crate_01c', Open='m23_1_prop_m31_crate_03b', Lid=false, SeparateLid=false.
    },
    Carry = {
        Enabled = true, TrunkEnabled = true, MoveRate = 0.85,
        -- Uses the vending dolly/animation by default; offsets place the crate base on the dolly.
        Prop = { offset = vec3(0.0, -0.35, 0.05), rotation = vec3(0.0, 0.0, 0.0) }, -- farther forward over the dolly platform
    },
    Animation = { dict = 'missheistfbi3b_ig7', clip = 'lift_fibagent_loop', flag = 1,
        prop = 'w_me_crowbar', bone = 57005, pos = vec3(0.10, 0.02, -0.02), rot = vec3(-90.0, 0.0, 0.0) },
    Scene = {
        Distance = 1.2,        -- metres in front of the player
        Networked = true,      -- false: only the opener sees the crate
        LidOffset = vec3(0.0, 0.0, 0.55),
        LidLanding = vec3(0.9, 0.4, 0.05), -- where the lid ends up, relative to the crate
        RevealDelay = 900,     -- ms between the lid coming off and the 3D reveal
        KeepSeconds = 20,      -- the open crate stays this long
    },
    Reveal3D = true,           -- false: only a notification with the contents
    Animation3D = 'random',    -- 3D reveal: 'lid' | 'panels' | 'pry' | 'straps' | 'random' (per crate: animation)
    Crates = {
        mixed = { label = 'Mixed Shipping Crate', contents = {
            { type = 'sealed', kind = 'box', count = 85 },
            { type = 'container', collectible = 'plushie', outer = false, count = 1 },
            { type = 'container', collectible = 'challenge_coin', outer = false, count = 1 },
            { type = 'container', collectible = 'plushie', outer = true, count = 1, chance = 15 },
        } },
        cards = { label = 'Card Shipping Crate', animation = 'straps', contents = {
            { type = 'sealed', kind = 'box', count = 85 },
            { type = 'item', item = 'card_sleeve', count = 50, chance = 50 },
        } },
        plushies = { label = 'Plushie Shipping Crate', animation = 'panels', contents = {
            { type = 'container', collectible = 'plushie', outer = true, count = 85 },
            { type = 'container', collectible = 'plushie', outer = false, count = 2 },
        } },
        coins = { label = 'Coin Shipping Crate', animation = 'pry', contents = {
            { type = 'container', collectible = 'challenge_coin', outer = true, count = 85 },
            { type = 'container', collectible = 'challenge_coin', outer = false, count = 2 },
        } },
    },
}

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
    Placement = {
        Enabled = true, BlockRoads = true, RoadMargin = 0.25,
        RoadCheckMode = 'lanes', -- 'lanes': allow verified raised pavement by a broad wall; 'native': strict GTA road region
        RoadLaneWidth = 3.5, RoadHeightTolerance = 2.5, -- estimated lane width / road height difference in metres
        RoadSidewalkMinRise = 0.08, SurfaceHeightTolerance = 0.08, -- sidewalk must be raised above road / level under footprint
        FrontClearance = 1.5, SideClearance = 0.15, -- metres of open passage beyond the cabinet
        RequireRearWall = true, RearWallDistance = 0.8, -- avoid cabinets in the middle of paths
        RearWallProbeHeights = { 0.3, 0.6, 1.0 }, -- accept low barriers as rear support (metres above the base)
        FrontIsNegativeY = true, CheckInterval = 250, MinSurfaceNormalZ = 0.85,
        ZoneMargin = 1.0, BypassAce = 'rush-tradingcards.placement.bypass',
        ForbiddenZones = {
            -- { Center = vec3(100.0, 200.0, 30.0), Radius = 8.0, MinZ = 28.0, MaxZ = 35.0 },
            -- { Center = vec3(100.0, 200.0, 30.0), Size = vec3(4.0, 20.0, 6.0), Heading = 45.0 },
        },
    },
    SpawnDistance = 100.0,           -- prop appears when a player is this close
    DespawnDistance = 120.0,         -- and is deleted again beyond this
    Table = 'goodluck_collectibles_vending_machines', -- MySQL (created automatically with Config.Database.AutoCreateSchema)
    File = 'data/vending_machines.json',             -- JSON persistence
    -- ox_target on every machine (menus need ox_lib): Buy for everyone, Restock for managers + Restock.Jobs, Manage for
    -- managers (pick which sets' packs / boxes this machine sells, prices and stock). Each machine saves its own products.
    -- Accounts: 'cash' / 'bank' (or another framework account), paid the way Config.Money says.
    -- ('cash' / 'bank'). The server checks the price, stock, the player's distance and inventory space before charging.
    Shop = {
        Enabled = true,
        TargetDistance = 2.0,
        Account = 'bank',
        CashAccount = 'cash',  -- cash payments (see Config.Money); kept in the machine
        Payment = 'both',      -- 'both' (buyer picks), 'card' (Account, routed to the owner) or 'cash'
        MaxCash = 6000,        -- most cash a machine holds before it only takes cards until emptied (0 = no limit)
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
        MaxStock = 100,   -- per pack product

        MaxBoxStock = 20, -- per booster box product
    },
    -- restocking and taking the cash take time: BaseMs + PerUnitMs for each pack / box loaded, or for each Unit dollars
    -- taken, capped at MaxMs. CycleMs = one load / grab motion.
    Work = {
        Enabled = true,
        Restock = { BaseMs = 2000, PerUnitMs = 750, MaxMs = 30000, CycleMs = 2000,
            PackBatch = 2, BoxBatch = 1, FullStockMs = 30000 }, -- full product capacity takes at most this much progress time; 0 disables the total cap
        Cash = { BaseMs = 2000, PerUnitMs = 1000, Unit = 100, MaxMs = 45000, CycleMs = 2500 },
    },
    -- pack props standing in the window's 15 slots to show stock (client/vending_machines.lua has the slot positions)
    SlotPacks = { Enabled = true, Model = 'metacomics_slot_pack', DropMs = 1500, Rotation = vec3(0.0, 0.0, 0.0), -- one prop per filled slot; each slot stands for a share of the stock
        -- Booster box products: the box stands on its side in the slot, its back reaching through into the machine.
        -- BoxRotation (pitch, roll, yaw in degrees) and BoxOffset (x left/right, y towards the back, z up, added to
        -- the pack's spot in the slot) can be tuned freely. When bought, the box slides forward to BoxDropFront while
        -- turning to BoxDropRotation (thin side towards the glass), then drops straight down to the tray.
        BoxModel = 'prop_boosterbox_01', BoxRotation = vec3(0.0, 90.0, 0.0), BoxOffset = vec3(0.0, 0.05, 0.1),
        BoxDropRotation = vec3(0.0, 90.0, 90.0), BoxDropFront = -0.38,
        -- spotlight from the top inside the window onto the packs (drawn by script for machines within Range metres).
        -- Offset: x left/right, y front/back (front is -y), z up from the model origin; Direction: where it points.
        Light = { Enabled = true, Offset = vec3(-0.15, -0.420, 0.720), Direction = vec3(0.0, 0.15, -1.0), Color = { 255, 244, 225 },
            Distance = 1.4, Brightness = 4.0, Hardness = 0.0, Radius = 55.0, Falloff = 10.0, Range = 30.0 } },
    -- Admin UI "Vending machines" tab (/collectiblesadmin): every machine on a map with its stock. Put a square GTA V
    -- map picture at Image (a path in this resource or an https URL; without one a grid is shown). The numbers line
    -- world coordinates up with the common 8192px GTA V map tiles; adjust them if your picture is cropped differently.
    Map = {
        Image = 'img/map/gtav_map.jpg',
        CenterX = 117.3, CenterY = 172.8, ScaleX = 0.02072, ScaleY = 0.0205,
    },
    -- The machine as an item (crafting recipe result 'vending'). Using it places it; Manage > Pick up turns it back
    -- into the item with its serial, stock and cash. ox_inventory item:
    -- ['vending_machine'] = { label = 'Vending Machine', weight = 60000, stack = false, close = true, client = { export = '<resource>.UseVendingMachine' } }
    Item = 'vending_machine',
    -- Owners, serial numbers and where card payments go (admin UI "Machine records" tab).
    Ownership = {
        SalesLog = 50, -- sales kept per machine for its owner (Manage > Sales records)
        BusinessName = 'Collectibles Co.',
        BusinessRouting = '000000001',  -- the business's routing number shown in records
        SerialPrefix = 'VM',            -- serials look like VM-7F3K-2Q9D
        DefaultTax = 10,                -- % of each sale a newly registered owner pays the business (set per owner in the UI)
        PayoutAccount = 'bank',         -- where owners' card earnings (and offline earnings when they join) are paid
        NotifyPayouts = true,
        ItemPlacement = 'anyone',       -- 'anyone' holding the item can set it up, or 'managers'
        AllowPickup = true,             -- owners may pick their machines up (managers always can)
        RevealHacker = false,           -- true: records show the hacker's name instead of "Unknown account"
        HistoryLength = 25,             -- events kept per serial
        -- The business's share (tax) is paid to this society / job account. Banking: 'auto' (first one running of
        -- Renewed-Banking, okokBanking, qb-banking, qb-management, ox_core group account), one of those names, or
        -- 'custom' with Deposit = function(account, amount, reason) return true end. If nothing takes it, it is held in
        -- the records and a manager can pay it out from the admin UI.
        Business = { Account = 'cardshop', Banking = 'auto' },
    },
    -- Record items. ox_inventory items (both stack = false):
    -- ['vending_registration'] = { label = 'Vending Registration', weight = 10, client = { export = '<resource>.UseVendingRecord' } }
    -- ['vending_ledger'] = { label = 'Vending Ledger', weight = 300, client = { export = '<resource>.UseVendingLedger' } }
    Records = {
        HistoryLimit = 500, -- retained events per business/OS log; portal pages load only the requested rows
        SalesLimit = 500,   -- retained sales per business/OS log; old trimmed records cannot be recovered
        CertificateItem = 'vending_registration', -- one machine's papers: shows its current owner, routing and status
        LedgerItem = 'vending_ledger',             -- every registered owner and machine
        LedgerShowsRemoved = false,
    },
    -- Front door: while someone restocks, unlocks / rekeys the cabinet with a key, loots it or breaks in, the door swings
    -- open for everyone nearby. Needs metacomics_vending_body + metacomics_vending_door streamed (the machine model split
    -- in two); without them machines simply stay shut. Hinge = door pivot in the body model (metres), Direction -1 / 1
    -- flips the swing if it opens into the machine. Seconds: how long it stays open after a restock / key unlock;
    -- crime, looting and rekeying hold it open until they finish (MaxSeconds at most).
    Door = {
        CancelAjarFraction = 0.18, -- cancelled locks leave affected doors/lids slightly open
        CancelReopenSpeed = 0.35, -- fraction of normal swing speed when a lock is cancelled
        Enabled = true, BodyModel = 'metacomics_vending_body', DoorModel = 'metacomics_vending_door',
        Hinge = vec3(-0.5825, -0.435, 0.0), Angle = 105.0, Speed = 90.0, Direction = -1,
        RestockSeconds = 20, UnlockSeconds = 300, MaxSeconds = 120, CloseDelay = 2, Crime = true, -- UnlockSeconds: key unlock lasts as long as Keys.SessionSeconds
        -- Cash box in the lower right behind the door (lid model metacomics_vending_cashlid). A key unlock opens it with
        -- the door; after a break-in it stays padlocked (Lock) until someone breaks the padlock, and looting cash waits
        -- for that. Cash props stack up inside by the machine's cash (the box is full at OverflowAt) and heap over / spill onto the ground above it.
        CashBox = {
            Enabled = true, Lock = true, OpenWithKey = true, Label = 'Break cash box padlock', Duration = 8000,
            Items = { { item = 'lockpick', label = 'lockpick', count = 1, breakChance = 25 } },
            Minigame = 'grinder_medium',
            LidModel = 'metacomics_vending_cashlid', LidHinge = vec3(0.402, 0.405, -0.6395), LidAngle = 80.0, LidDirection = -1,
            CashProps = { 'prop_cash_pile_01', 'prop_anim_cash_note' }, OverflowAt = 3000, BreakInDelay = 2500, PadlockAfterBreakIn = true,
        },
        -- Server rack in the recess right of the window (lid model metacomics_vending_racklid, hinged on its left edge).
        -- The actions in Required (board / OS / payment hacks and the GPS switch) need the cabinet and this rack open
        -- instead of the cash box. A full key opens it from the key menu; anyone else picks its lock (Items, Minigame,
        -- Duration). With Enabled = false the hacks go back to needing the cash box open.
        -- 'system' covers the Manage menu's system changes: Assign owner, card payment recipient and Reset routing.
        -- Lights: blinking LEDs on the top unit, red while the GPS is on, green for the original board, blue once the
        -- operating system was taken over. Drawn by script, only once the rack lid model is streamed.
        Rack = {
            Enabled = true, Lock = true, OpenWithKey = true, Label = 'Pick server rack lock', Icon = 'fa-solid fa-server', Duration = 10000,
            Items = { { item = 'lockpick', label = 'lockpick', count = 1, breakChance = 25 } },
            Minigame = 'lockpick_medium',
            Required = { 'hack', 'fullhack', 'replaceboard', 'disablegps', 'enablegps', 'system' },
            LidModel = 'metacomics_vending_racklid', LidHinge = vec3(0.282, -0.40, -0.208), LidAngle = 100.0, LidDirection = -1,
            Lights = { Enabled = true, Gps = vec3(0.4595, -0.363, 0.5231), Os = vec3(0.4826, -0.363, 0.5231), Size = 0.012,
                Range = 0.25, Intensity = 3.0, Distance = 15.0 },
        },
    },
    -- The criminal side. Items: every entry is needed; remove = used up on success, breakChance = % lost on a failed
    -- attempt. Minigame: a preset name from Config.Minigames, a list (all must pass) or { random = { ... } } (lists can hold randoms).
    -- Animation: { dict, clip, flag } or { scenario }, plus an optional prop held in the hand (bone, pos, rot).
    -- Cooldown / FailCooldown are seconds per machine. MinPolice: police players (Config.Police.Jobs) needed online.
    -- Physical cabinet access. Old cylinders and issued keys are permanently archived by serial.
    Keys = {
        Enabled = true,
        Item = 'vending_key', ReportItem = 'vending_key_record', CylinderItem = 'vending_lock_cylinder',
        SessionSeconds = 300, ReplaceDuration = 60000,
        UseAnimation = { Enabled = true, Model = 'tr_prop_tr_car_keys_01a', CabinetModel = 'h4_prop_h4_key_desk_01', Duration = 1800, ApproachMs = 1000,
            CylinderSpot = vec3(0.49, -0.98, -0.95), PadlockSpot = vec3(0.58, -0.98, -0.95),
            CashboxSpot = vec3(0.40, -1.05, -0.95), RackSpot = vec3(0.35, -0.95, -0.95),
            Animation = { dict = 'anim@scripted@heist@ig13_jailor_key_turn@generic@male@', clip = 'action', flag = 0 },
            -- Hand targets are model-local lock coordinates; IK corrects the clip's reach for each lock.
            Profiles = {
                InstallPadlock = { Spot = vec3(0.48, -0.94, -0.95), Target = vec3(0.58, -0.48, 0.14), Duration = 2000,
                    Bone = 64096, Offset = vec3(0.0, 0.0, -0.035), Rotation = vec3(0.0, 90.0, 0.0), ReachStart = 0.20, ReachEnd = 0.85 },
                Padlock = { Spot = vec3(0.48, -0.94, -0.95), Target = vec3(0.58, -0.48, 0.14), Duration = 2000,
                    Bone = 64096, Offset = vec3(0.015, 0.060, 0.020), Rotation = vec3(188.0, 0.0, -90.0), ReachStart = 0.20, ReachEnd = 0.80 },
                Cylinder = { Spot = vec3(0.39, -0.94, -0.95), Target = vec3(0.49, -0.48, 0.24), Duration = 2000,
                    Bone = 64096, Offset = vec3(0.010, 0.025, 0.015), Rotation = vec3(10.0, -116.0, 192.0), ReachStart = 0.20, ReachEnd = 0.80 },
                Rack = { Spot = vec3(0.40, -0.92, -0.95), Target = vec3(0.50, -0.43, -0.05), Duration = 2000,
                    Animation = { dict = 'missheistfbisetup1', clip = 'unlock_loop_janitor', flag = 1 },
                    Bone = 64096, Offset = vec3(0.015, 0.060, 0.020), Rotation = vec3(188.0, 0.0, -90.0), ReachStart = 0.15, ReachEnd = 0.85 },
                Cashbox = { Spot = vec3(0.30, -0.64, -0.95), Target = vec3(0.402, 0.35, -0.60), Duration = 2000,
                    Animation = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 1 },
                    Bone = 64096, Offset = vec3(0.015, 0.060, 0.020), Rotation = vec3(188.0, 0.0, -90.0), ReachStart = 0.25, ReachEnd = 0.85 },
            },
            OpenAnimation = { dict = 'mp_common', clip = 'givetake1_a', flag = 1, Duration = 650 },
            Bone = 57005, Offset = vec3(0.10, 0.02, -0.02), Rotation = vec3(0.0, 90.0, 0.0) },
        ReplaceOffset = vec3(0.85, -0.15, 0.0), -- right side of the cabinet, relative to the model origin
        ForcedReplaceDuration = 180000, ForcedReplaceMinigame = { 'lockpick_hard', 'skimmer_hard' }, -- non-owner/non-manager cylinder fitting
        PoliceCommand = 'vendingkeys', -- /vendingkeys SERIAL [print], police/business only
        SecureAccess = 'police_or_controllers', -- physical owners/business may secure too
        Padlock = { Enabled = true, Item = 'vending_padlock', Model = 'prop_cs_padlock',
            Offset = vec3(0.58, -0.44, 0.14), Rotation = vec3(-30.0, 0.0, 0.0) }, -- right front, between coin insert and buttons
        -- securing a broken-in machine chains it shut: no key access until the cylinder is repaired or replaced.
        -- Model: long base game chain round each face in Faces (its padlocks hidden inside); Lock: short chain lock on the front in Faces; padlock out on the front, hidden inside elsewhere.
        -- Padlock on the wrong side? flip LockSide (1 / -1). Height = chain height on the machine. FallbackModel if the chain isn't in the game build.
        Seal = { Label = 'Chain and padlock', BreakDuration = 20000, Minigame = 'lockpick_medium',
            Model = 'm23_2_prop_m32_chainlock_01a', Debug = true, Faces = { 'front', 'left', 'right', 'back' }, LockSide = -1, Height = 0.02,
            Out = 0.08, Tile = true, Overlap = 0.85, CornerReach = 0.03, -- Out: off the faces; Tile: repeat along wide faces; CornerReach: past the corners
            FrontLock = true, -- the middle front chain turns its padlock outwards
            Lock = { Enabled = false, Model = 'h4_prop_h4_chain_lock_01a', LockSide = -1 }, -- optional extra short padlock chain on the front
            -- Adjust = { front = { along, out, up, yaw }, ... } per-face nudges; with Debug on, /vendingsealtune prints this line
            FallbackModel = 'prop_cs_padlock', FallbackOffset = vec3(0.0, -0.46, 0.0) },
        -- fixing a damaged cylinder instead of replacing it: keeps the existing keys, uses up these items
        Repair = { Enabled = true, Duration = 30000, Items = { { item = 'metalscrap', label = 'metal scrap', count = 10 } } },
    },
    Crime = {
        Enabled = true,
        MinPolice = 0,
        OwnersCanRob = false, -- owners (and hackers who took a machine over) can't rob their own machines
        BreakSeal = {
            Enabled = true, Label = 'Lockpick security seal', Icon = 'fas fa-lock', ProgressLabel = 'Lockpicking the security device',
            Items = { { item = 'lockpick', label = 'lockpick', count = 1, breakChance = 30 } },
            -- Uses Keys.Seal.BreakDuration and Minigame; the cylinder is already damaged.
            Animation = { dict = 'missheistfbi3b_ig7', clip = 'lift_fibagent_loop', flag = 49, prop = 'prop_tool_screwdvr01',
                bone = 57005, pos = vec3(0.10, 0.02, -0.02), rot = vec3(-90.0, 0.0, 0.0) },
            Cooldown = 0, FailCooldown = 30, FailMessage = 'The security seal held.',
        },
        PickPadlock = {
            Enabled = true, Label = 'Lockpick padlock', Icon = 'fas fa-lock', ProgressLabel = 'Lockpicking the padlock',
            Items = { { item = 'lockpick', label = 'lockpick', count = 1, breakChance = 30 } },
            Minigame = 'lockpick_medium', Duration = 15000, Cooldown = 0, FailCooldown = 30,
            Interaction = { Spot = vec3(0.58, -1.02, -0.95), Target = vec3(0.58, -0.44, 0.14), WalkMs = 1000 },
            Animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1, prop = 'prop_tool_screwdvr01',
                bone = 57005, pos = vec3(0.10, 0.02, -0.02), rot = vec3(-90.0, 0.0, 0.0) },
            FailMessage = 'The padlock held.',
        },
        BreakIn = {
            Enabled = true, Label = 'Drill cabinet cylinder', Icon = 'fas fa-screwdriver-wrench', ProgressLabel = 'Drilling out the cabinet cylinder',
            Items = { { item = 'drill', label = 'drill', count = 1, breakChance = 30 } },
            Minigame = 'drill_hard',
            Duration = 45000,
            Interaction = { Spot = vec3(0.49, -1.04, -0.95), Target = vec3(0.49, -0.44, 0.24), WalkMs = 1000 },
            Animation = { dict = 'anim@heists@fleeca_bank@drilling', clip = 'drill_straight_idle', flag = 1, prop = 'hei_prop_heist_drill', bone = 57005, pos = vec3(0.14, 0.0, -0.01), rot = vec3(90.0, -90.0, 180.0) },
            Cooldown = 900, FailCooldown = 30,
            TakePercent = 100,       -- % of the cash stored in the machine
            RewardAccount = 'cash',  -- or RewardItem = 'black_money' / 'markedbills' (count = the amount)
            StockChance = 25, StockMax = 2, -- also grab up to StockMax sealed packs / boxes of a product (chance %)
            MinCash = 0,
            Loot = {
                Enabled = true, UnlockSeconds = 600, -- cabinet remains open after canceling; securing closes it early
                CashBatch = 100, CashBatchMs = 4000, StockBatch = 1, StockBatchMs = 5000,
                CashLevels = { 500, 2000 }, StockLevels = { 10, 40 }, -- empty / low / medium / high estimates
                Visuals = {
                    Enabled = true, -- visual only; disabling restores the break-in pose during looting
                    Reach = { dict = 'mp_common', clip = 'givetake1_a', flag = 49 },
                    Stash = { dict = 'anim@heists@ornate_bank@grab_cash', clip = 'grab', flag = 49 },
                    HandFraction = 0.25, StashFraction = 0.55, HideFraction = 0.88, -- timing within each batch
                    Pocket = { bone = 11816, pos = vec3(0.18, 0.02, -0.03), rot = vec3(0.0, 90.0, 0.0) },
                    Cash = { model = 'prop_anim_cash_note', bone = 57005, offset = vec3(0.05, 0.02, -0.02), rotation = vec3(0.0, 0.0, 0.0) },
                    -- Pack/Box reuse Config.Props.Pack / Box models and hand offsets. Optional overrides:
                    -- Pack = { model = 'prop_boosterpack_01', bone = 57005, offset = vec3(0.10, 0.10, 0.0), rotation = vec3(70.0, 10.0, 90.0) },
                    -- Box = { model = 'prop_boosterbox_01' },
                },
            },
            FailMessage = 'The lock held.',
        },
        Hack = {
            Enabled = true, Label = 'Hack payment terminal', Icon = 'fas fa-laptop-code', ProgressLabel = 'Rerouting card payments',
            Items = { { item = 'laptop', label = 'laptop', count = 1 }, { item = 'hackingdevice', label = 'electronic kit', count = 1, remove = true } },
            Minigame = { 'keypad_hard', 'simon_hard', 'skimmer_hard' },
            Duration = 90000,
            Animation = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle', flag = 49, prop = 'prop_laptop_01a', bone = 18905, pos = vec3(0.12, 0.05, 0.12), rot = vec3(-110.0, 0.0, 10.0) },
            Hours = 0,               -- 0: until the owner (or the business) resets the routing, else hours
            Cooldown = 1800, FailCooldown = 60,
            FailMessage = 'The terminal locked you out.',
        },
        FalsifyLogs = {
            Enabled = true, Label = 'Falsify machine sensor records', ProgressLabel = 'Rewriting sensor identities...',
            Duration = 45000, Cooldown = 0, FailCooldown = 60,
            Items = { { item = 'laptop', count = 1 }, { item = 'hackingdevice', count = 1, remove = true } },
            Minigame = { 'keypad_hard', 'skimmer_hard' },
            Animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
        },
        FullHack = {
            Enabled = true, Label = 'Take over machine operating system', Icon = 'fas fa-user-secret',
            ProgressLabel = 'Taking over the machine operating system',
            Items = { { item = 'laptop', count = 1 }, { item = 'hackingdevice', count = 1, remove = true } },
            Minigame = { 'keypad_hard', 'simon_hard', 'grid_hard', 'skimmer_hard', 'safe_hard', 'order_hard' },
            Duration = 300000, Cooldown = 3600, FailCooldown = 300, -- persists until the board is physically replaced
            Animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
            FailMessage = 'The operating system rejected your takeover.',
        },
        TakeMachine = {
            Enabled = true, Label = 'Steal Machine', Icon = 'fas fa-dolly', ProgressLabel = 'Taking the unsecured machine',
            Duration = 5000, Cooldown = 0, FailCooldown = 0, Items = {}, NeedsBreakIn = false, NeedsGPSDisabled = false,
            Animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
        },
        BoltMachine = {
            Enabled = true, Label = 'Bolt machine down', Icon = 'fas fa-screwdriver-wrench', ProgressLabel = 'Bolting down the machine',
            Duration = 10000, Cooldown = 0, FailCooldown = 0,
            Items = { { item = 'drill', label = 'drill', count = 1 } },
            Animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
        },
        Steal = {
            Enabled = true, Label = 'Unbolt machine', Icon = 'fas fa-dolly', ProgressLabel = 'Unbolting the machine',
            Items = { { item = 'drill', label = 'drill', count = 1, breakChance = 25 } },
            NeedsBreakIn = true, -- the machine must be open (broken into or unlocked with a key) to reach the bolts
            NeedsGPSDisabled = false, -- true: with GPS enabled, the machine's GPS must be disabled before unbolting
            Minigame = 'grinder_bolts',
            Duration = 180000,
            Animation = { dict = 'anim@heists@fleeca_bank@drilling', clip = 'drill_straight_idle', flag = 49, prop = 'hei_prop_heist_drill', bone = 57005, pos = vec3(0.14, 0.0, -0.01), rot = vec3(90.0, -90.0, 180.0) },
            Cooldown = 300, FailCooldown = 120,
            FailMessage = 'The bolts would not budge.',
        },
        DisableGPS = {
            Enabled = true, Label = 'Disable machine GPS', ProgressLabel = 'Disabling GPS',
            Items = { { item = 'hackingdevice', label = 'electronic kit', count = 1 } },
            Minigame = 'skimmer_hard', Duration = 30000, Cooldown = 0, FailCooldown = 60,
            Animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
        },
        EnableGPS = {
            Enabled = true, Label = 'Enable machine GPS', ProgressLabel = 'Rearming GPS at this location',
            Duration = 3000, Animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
        },
        InstallSkimmer = {
            Enabled = true, Label = 'Install card skimmer', ProgressLabel = 'Installing skimmer',
            Items = { { item = 'card_skimmer', label = 'card skimmer', count = 1 } },
            Duration = 30000, Minigame = 'skimmer_medium', Animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
        },
        Secure = {
            Enabled = true, Label = 'Secure vending machine', ProgressLabel = 'Securing the vending machine',
            Duration = 5000, Cooldown = 0, FailCooldown = 0,
            Access = 'anyone', -- 'anyone', 'police', 'controllers', or 'police_or_controllers'; server checks permissions
            Animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
        },
        ReplaceBoard = {
            Enabled = true, Label = 'Replace machine control board', ProgressLabel = 'Replacing the control board',
            Items = { { item = 'vending_control_board', label = 'replacement control board', count = 1 } },
            Duration = 60000, Cooldown = 0, FailCooldown = 0,
            Animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
        },
        CollectSkimmer = { Enabled = true, Label = 'Read card skimmer', ProgressLabel = 'Reading skimmer', Duration = 3000 },
        RemoveSkimmer = { Enabled = true, Label = 'Remove card skimmer', ProgressLabel = 'Removing skimmer', Duration = 3000 },
        -- installer only: change the skimmer's cut while it stays on the machine
        AdjustSkimmer = {
            Enabled = true, Label = 'Adjust card skimmer', ProgressLabel = 'Adjusting the skimmer', Duration = 15000,
            Animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
        },
        -- owners, whoever controls the machine, managers and police: finds and removes a hidden skimmer (the only way they can)
        InspectPanel = {
            Enabled = true, Label = 'Check coin panel for tampering', ProgressLabel = 'Checking the coin panel', Duration = 10000, Cooldown = 0, FailCooldown = 0,
            Animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
        },
    },
    GPS = {
        Enabled = true, MovementThreshold = 2.0, CheckInterval = 5000, Cooldown = 60,
        NotifyController = true, -- in-game notification; optional phone delivery uses Config.Police.Phone
    },
    Skimmer = {
        Enabled = true, Item = 'card_skimmer',
        Model = 'metacomics_card_skimmer', -- stream your new prop before installing; no placeholder model
        Offset = vec3(0.359, -0.4310, 0.352), Rotation = vec3(0.0, 0.0, 0.0), -- exactly over the coin panel (rounded metacomics_card_skimmer, 2026-10-08)
        DoorAdjust = vec3(0.0, -0.0, 0.0), -- extra nudge while it rides on the open door (negative y = further out)
        -- the skimmer copies the card of every card purchase (cash purchases are unaffected). The installer reads it
        -- (or removes it and uses the item) for a card data item, and sells that to a buyer below.
        -- whoever fits it picks the cut (0 - MaxPercent, default Percent): that share of each card payment never reaches the
        -- owner and sits on the skimmer's records until a buyer recovers it. Owners can spot it in Manage > Sales records.
        Percent = 15, MaxPercent = 50,
        Capacity = 200, -- card purchases it holds; when full it copies nothing more until it is read
        DataItem = 'skimmer_card_data', -- printed card data (examples/ox_inventory-items.lua)
        Buyers = {
            Enabled = true,
            Percent = 50, -- the seller's share of the skimmed money the buyer recovers: $37 skimmed = $18 paid
            Account = 'cash', -- where the buyer's money goes ('cash' or 'bank')
            Label = 'Sell card data', Icon = 'fas fa-user-secret', ProgressLabel = 'Handing over the card data', Duration = 4000,
            Distance = 2.0, SpawnDistance = 60.0, -- target range; the ped appears when a player is this close
            -- one buyer: Ped = { ... }, or several: Peds = { { ... }, { ... } }. Each can have its own Percent and label.
            -- PLACEHOLDER spot (Grove Street): set your own coords (x, y, z, heading) for your server
            Peds = {
                { model = 'g_m_y_mexgoon_02', coords = vec4(105.0, -1940.0, 20.8, 45.0), scenario = 'WORLD_HUMAN_SMOKING' },
            },
        },
    },
    -- /vendingtestrole (managers only): be yourself without admin, a stranger, police, an employee or another manager
    -- to test the vending machines (server/modules/vending_testing.lua has the details)
    Testing = { Enabled = true, Command = 'vendingtestrole' },
}

-- Carrying a vending machine item: the player pushes it on a dolly (walk only: no sprint, jump or weapons) until they get
-- into a vehicle. Stolen machines can also be tied to the back of a vehicle with a rope (ox_target on the vehicle, from
-- behind it) and dragged; untie it (ox_target on the machine) to load it back on the dolly. Offsets: Dolly from the ped,
-- Machine base from the dolly (model-origin height is compensated automatically). Tweak them in game if the model sits wrong.
-- Evidence adapters receive one payload table. Configure server exports or a custom function to map your resource's API.
-- Trading card buyback. Example location: replace with your shop's coordinates.
Config.CardBuyers = {
    Enabled = true, Account = 'cash', Distance = 2.0, SpawnDistance = 60.0,
    ZoneAdapter = 'builtin', -- or a registered adapter name / { Resource='resource', Contains='exportName' }
    MaxCartCards = 60, QuoteSeconds = 300,
    Stock = { Enabled = true, Command = 'cardbuyerstock', ManagementMinGrade = 2, PageSize = 20 },
    -- Population = unique graded copies previously bought by these businesses, across all buyers.
    GradedPopulation = { Enabled = true, ReferenceCount = 4, Exponent = 0.35, MinMultiplier = 0.75, MaxMultiplier = 1.25 },
    Analysis = { Enabled = true, SamplePacks = 2000, CacheSeconds = 120, RequireDuty = true },
    ZoneTool = { Command = 'cardzone', RayDistance = 30.0, DefaultSize = vec3(4.0, 4.0, 3.0) },
    CheckInterval = 3000, Command = 'sellcards', FundCommand = 'fundcardbuyer',
    MinPrice = 1, MaxPrice = 1000,
    Pricing = 'combined', -- 'rarity', 'odds', or 'combined' (higher multiplier, based on the $1 common baseline)
    RarityMultipliers = { common = 1, uncommon = 2, rare = 5, ultra_rare = 15, legendary = 50 },
    OddsExponent = 1.0, -- price multiplier = (commonest print / this print's expected copies per set pack)^exponent
    RarityScores = { common = 0, uncommon = 0.25, rare = 0.5, ultra_rare = 0.75, legendary = 1 },
    -- RarityScores is retained for older configurations without RarityMultipliers.
    OddsMaxRatio = 300, -- legacy setting; baseline pricing now uses OddsExponent instead
    ConditionPricing = {
        Enabled = true, DiscountPerGradePoint = 0.08, MaxDiscount = 0.80,
        -- Stricter than grading tolerances: only defects obvious without a grading bench lower raw-card offers.
        Obvious = { centeringFront = 0.20, centeringBack = 0.70, art = 1.5, text = 1.2,
            foil = 3.0, foilHue = 30, mask = 1.6, wear = 0.40 },
        MarkSeverity = { scratch = 0.50, dent = 0.70, crease = 0.20, bend = 0.40, tear = 0.15,
            roller = 0.70, printline = 0.50, inkspot = 0.70, stain = 0.50 },
        MinMarkLength = { scratch = 12, crease = 8, bend = 10, tear = 2, printline = 20, roller = 15 },
        GradeMultipliers = { [1]=0.15,[2]=0.25,[3]=0.35,[4]=0.45,[5]=0.55,[6]=0.65,[7]=0.80,
            [8]=1.0,[8.5]=1.15,[9]=1.40,[9.5]=1.75,[10]=2.50 },
    },
    AcceptManualPrints = false,
    RequireBusinessFunds = false, -- true: employees must deposit money; insufficient funds refuse the sale
    FundingAccount = 'bank', FundingMinGrade = 0,
    FixedPricesEnabled = false, FixedPricesIgnoreMaximum = false,
    -- Exact baseCardId::variantId overrides baseCardId. Prices are dollars per card.
    FixedPrices = { -- ['sample-card::standard'] = 1500, ['sample-card'] = 100,
    },
    Peds = {
        { id = 'cardshop', label = 'Trading card buyer', model = 's_m_m_highsec_01',
          coords = vec4(112.0, -1938.0, 20.8, 45.0), scenario = 'WORLD_HUMAN_CLIPBOARD',
          EmployeeJobs = { cardshop = 0 }, HideWhenEmployeesPresent = true,
          -- On-duty employees must be in Store and/or Bounds. 'any' = either; 'all' = both.
          PresenceMode = 'any', Store = { coords = vec3(112.0, -1938.0, 20.8), radius = 20.0 },
          -- Bounds = { coords = vec3(112.0, -1938.0, 20.8), size = vec3(12.0, 10.0, 6.0), heading = 45.0 },
          -- Optional counter handover: actor stands at Spot inside Bounds and deals once per selected card.
          -- SellArea = { Bounds = { coords=vec3(112.0,-1938.0,20.8),size=vec3(4.0,4.0,3.0),heading=45.0 },
          --   Spot=vec4(112.0,-1938.0,20.8,45.0), Animation={ dict='mp_common',clip='givetake1_a',Duration=850,flag=49 } },
          -- Optional overrides: MinPrice, MaxPrice, RequireBusinessFunds, FixedPrices, etc.
        },
    },
}

Config.CrimeEvidence = {
    Enabled = true,
    Fingerprints = { Enabled = true, Chance = 75,
        Actions = { breakin = true, loot = true, hack = true, fullhack = true, steal = true, disablegps = true, installskimmer = true },
        Placement = { Face = 'nearest', HalfWidth = 0.575, HalfDepth = 0.425, -- cabinet local footprint; 'front' forces the front face
            SurfaceOffset = 0.08, HeightOffset = 0.0, ScatterRadius = 0.18, VerticalScatter = 0.12 }, -- metres, relative to model origin
        -- Optional server function(source, payload): return true to suppress prints (e.g. validated glove state).
        IsWearingGloves = nil,
    },
    Injury = { Enabled = true, Actions = { breakin = { Chance = 15, Damage = 5 }, steal = { Chance = 25, Damage = 10 } } },
    Blood = { Enabled = true, Chance = 100, ScatterRadius = 0.25, HeightOffset = -0.9 }, -- near injured player; rush-evidence adapter raycasts ground
    Adapters = {
        { Enabled = true, Type = 'rush-evidence', Resource = 'rush-evidence', Kinds = { fingerprint = true, blood = true } },
        -- { Enabled = true, Resource = 'your-evidence', Export = 'CreateEvidence', Kinds = { fingerprint = true, blood = true } },
        -- { Enabled = true, Create = function(payload) exports['your-evidence']:AddFingerprint(payload.source, payload.coords) end,
        --   Kinds = { fingerprint = true } },
    },
}

-- Upright truck cargo, turned sideways. Three columns need about 2.7 m clear width.
-- Edit columns/rows at the calls below; offsets refer to the vending model's centre, not its feet.
local function vendingTruckSlots(columns, rows, centerY, centerZ, columnSpacing, rowSpacing)
    local slots = {}
    -- Load from the front of the cargo bay toward the rear doors.
    for row = 1, rows do
        for column = 1, columns do
            slots[#slots + 1] = {
                offset = vec3((column-(columns+1)/2)*columnSpacing, centerY+((rows+1)/2-row)*rowSpacing, centerZ),
                rotation = vec3(0.0, 0.0, 90.0),
            }
        end
    end
    return slots
end
local function collectibleCrateSlots(rows, centerY, floorZ)
    local slots = {}
    for row = 1, rows do
        slots[row] = { offset = vec3(0.0, centerY+((rows+1)/2-row)*1.30, floorZ), rotation = vec3(0.0,0.0,0.0), alignBottom = true }
    end
    return slots
end
local function bensonMachineSlots()
    local slots = vendingTruckSlots(2, 4, -1.65, 1.05, 0.92, 1.20)
    slots[#slots+1] = { offset = vec3(0.0, -4.55, 1.05), rotation = vec3(0.0, 0.0, 0.0) } -- centred rear machine, front faces out (-Y)
    return slots
end

Config.VendingCarry = {
    Enabled = true,
    TrunkRestrictions = {
        Enabled = true,
        Mode = 'allowlist', -- 'allowlist', 'blacklist', or 'both'; blacklist mode preserves the old rules
        AllowedModels = { 'speedo', 'speedo2', 'speedo4', 'rumpo', 'rumpo2', 'rumpo3', 'pony', 'pony2', 'burrito', 'burrito2', 'burrito3', 'burrito4', 'burrito5', 'mule', 'mule2', 'mule3', 'mule4', 'mule5', 'benson', 'trflat', 'trailers', 'trailers2', 'trailers3', 'trailers4' },
        BlockedModels = {}, -- model names or hashes: { 'adder', `zentorno` }
        BlockedClasses = {}, -- names or IDs: { 'sedans', 'sports', 7 }; see README
        BlockedTypes = {}, -- server vehicle types: { 'bike', 'boat', 'heli', 'plane' }
        -- Trusted model -> class data. GTA's class lookup is client-only.
        ModelClasses = {}, -- { sultan = 'sports', adder = 7, speedo = 'vans' }
        BlockUnknownClass = true, -- when class rules exist, deny models missing from ModelClasses
        Message = 'This vehicle cannot store a vending machine in its trunk.',
    },
    TrunkCargo = {
        Enabled = true, Inventory = 'ox_inventory', CheckInterval = 1000,
        SpawnPerTick = 2, -- stagger cargo visual creation across client ticks to avoid truck-load spawn spikes
        DoorMinimum = 3, -- server-synchronized open position, 0 closed .. 7 fully open
        DoorStopAngle = 0.25, -- obstructed doors can move freely above this fraction of their open angle
        CollisionClearance = 0.005, -- metres added to door/cargo bounds (previous hardcoded margin was 0.02)
        -- Explicit cargo profiles: vehicle exterior dimensions do not describe usable cargo space.
        -- offsets are relative to vehicle origin; add Slots to carry more machines.
        Profiles = {
            speedo4 = { Doors = {}, CollisionDoors = { 2, 3 }, Slots = { { offset = vec3(0.0, -1.25, 0.25), rotation = vec3(0.0, 90.0, 90.0) } }, CrateSlots = collectibleCrateSlots(1,-1.25,-0.45) }, -- on its side; rear doors close if the load clears them
            speedo = 'speedo4', -- default vans carry on their side and do not require open doors
            speedo2 = 'speedo', rumpo = 'speedo4', rumpo2 = 'rumpo',
            rumpo3 = {
                Doors = {}, CollisionDoors = { 2, 3 }, CollisionClearance = -0.015, -- tolerate 1.5 cm of conservative bounds overlap
                Slots = { { offset = vec3(0.0, -1.25, 0.25), rotation = vec3(0.0, 90.0, 90.0) } },
                CrateSlots = collectibleCrateSlots(1,-1.25,-0.45),
                -- Approximate closed side-door panels in vehicle space; tune for replacement vehicles.
                SlidingDoors = {
                    [2] = { center = vec3(-1.10, -0.75, 0.35), halfSize = vec3(0.025, 0.70, 0.80), travel = vec3(-0.12, -1.10, 0.0) },
                    [3] = { center = vec3(1.10, -0.75, 0.35), halfSize = vec3(0.025, 0.70, 0.80), travel = vec3(0.12, -1.10, 0.0) },
                },
            },
            pony = 'speedo', pony2 = 'speedo', burrito = 'speedo', burrito2 = 'speedo', burrito3 = 'speedo', burrito4 = 'speedo', burrito5 = 'speedo',
            -- Starting truck layouts; verify floor/roof/arches in game for each vehicle variant.
            -- arguments: columns, rows, bay centre Y, machine centre Z, column spacing, row spacing (metres).
            mule = { Doors = {}, CollisionDoors = { 2, 3 }, Slots = vendingTruckSlots(2, 3, -1.60, 1.05, 0.92, 1.20), CrateSlots = collectibleCrateSlots(3,-1.60,0.10) },
            mule2 = 'mule', mule3 = 'mule', mule4 = 'mule', mule5 = 'mule',
            benson = { Doors = {}, CollisionDoors = { 2, 3 }, Slots = bensonMachineSlots(), CrateSlots = collectibleCrateSlots(4,-1.65,0.10) },
            trflat = { Doors = {}, Slots = { { offset = vec3(0.0, 0.0, 0.60), rotation = vec3(0.0, 0.0, 0.0) } }, CrateSlots = collectibleCrateSlots(1,0.0,0.60) },
            trailers = 'trflat', trailers2 = 'trflat', trailers3 = 'trflat', trailers4 = 'trflat',
        },
        -- Other resources: server-only GetInventory(id), LoadedTrunks(), RegisterHook(callback), RemoveHook(handle).
        Adapter = nil,
    },
    -- offset = vec3(left/right, forward/back, height), in metres; rotation is in degrees.
    -- Dolly height raises the whole assembly. Machine height adjusts only the cabinet.
    -- With Dolly.rotation.z = 180, decreasing Machine.offset.y moves it away from the player.
    Dolly = { model = 'prop_sacktruck_02a', bone = 0, offset = vec3(0.0, 0.9, -0.93), rotation = vec3(-20.0, 0.0, 180.0) }, -- model = nil: no dolly
    Machine = { offset = vec3(0.0, -0.4, 0.03), rotation = vec3(0.0, 0.0, 0.0) },
    Animation = { dict = 'anim@heists@box_carry@', clip = 'idle', flag = 49 },
    MoveRate = 0.85, -- walking pace (1.0 = normal walk)
    VehicleEntry = 'block', -- 'block': refuse entry; 'drop': drop a machine when attempting entry (pick it up with ox_target)
    Tow = {
        Enabled = true, StolenOnly = true, -- false: any machine can be dragged
        Length = 6.0, Distance = 3.0, Duration = 4000, UntieDuration = 3000,
        Label = 'Tie vending machine', UntieLabel = 'Untie vending machine', Icon = 'fas fa-link',
        Physics = {
            Enabled = true, -- false: use the prop's default physics
            Mass = 1000.0, Gravity = 1.0, -- physics mass, separate from inventory weight
            LinearDamping = 0.1, AngularDamping = 0.5, -- resistance to sliding / spinning
        },
        Snap = {
            Enabled = false, -- false: disable automatic rope snapping
            ExtraDistance = 3.0, -- metres beyond Length, measured between entity centres (allows for the rear bumper)
            MaxSpeedKmh = 100.0, -- 0: disable the speed limit
            Duration = 600, GracePeriod = 3000, -- continuous overload / grace after ground placement, in milliseconds
        },
        PickupLabel = 'Pick up vending machine', -- a snapped rope leaves the cabinet on the ground
    },
}

-- Skill checks / minigames used by vending machine crime (Config.VendingMachines.Crime.*.Minigame) and by other scripts
-- through exports['<resource>']:Minigame('name'). type:
--   'builtin'        this resource's own games, no other resource needed:
--                      lockpick  Shear Line { pins, tol (pixels), band (%), time (s), showBand, spools }; tension is fixed (drift/shift unused)
--                      wires     { wires, time, mistakes }      keypad { length, show (s to memorise), time, rounds }
--                      sequence  { keys, perKey (s), rounds }
--                      simon     { start, length, show (s per flash), time (s per round) }   repeat a growing colour signal
--                      grid      { size, cells, rounds, show (s), time, mistakes }        click the squares that flashed
--                      safe      { numbers, tolerance, speed (numbers/s), time, mistakes } turn a dial to each number, alternating
--                      reaction  { grid, targets, life (s per target), traps (0-1), misses } hit green nodes, avoid red
--                      order     { count, time, shuffle (move after each click), mistakes } click 1..count in order
--                      circle    { zones, zone (degrees), speed (turns/s), time, mistakes, reverse } stop a needle on each arc
--   'ox_skillcheck'  { difficulty = { 'easy', 'medium', { areaSize = 50, speedMultiplier = 1 } }, inputs = { 'e' } }
--   'ps-ui'          { game = 'circle' | 'maze' | 'varhack' | 'thermite' | 'scrambler', circles, seconds, blocks, grid, incorrect }
--   'bl_ui'          { game = 'CircleProgress' | 'Progress' | 'KeySpam' | 'KeyCircle' | 'NumberSlide' | 'RapidLines' | 'CircleShake'
--                      | 'PathFind' | 'LightsOut' | 'MineSweeper' | 'Untangle' | 'WaveMatch' | 'WordWiz' | 'DigitDazzle' | 'PrintLock',
--                      iterations, difficulty (0-100) or config = { ... } }
--   'memorygame'     { correct, incorrect, show, lose }       'qb-minigames' { game = 'Skillbar' | 'Lockpick' | 'Hacking' | 'KeyMinigame', ... }
--   'utk_fingerprint' { levels, lives, minutes }               'glow_minigames' { game = 'path' | 'spot' | 'math', settings }
--   'custom'         { run = function() return true end }    'none' always passes
-- level = 'easy' | 'medium' | 'hard': when a preset's resource isn't running, the built-in lockpick of that level is used.
Config.Minigames = {
    crafting_precision = { type = 'builtin', game = 'crafting', cutter = 'bench', cols = 5, rows = 3, time = 900, maxErrors = 6 },
    crafting_production = { type = 'builtin', game = 'crafting', cutter = 'industrial', cols = 5, rows = 3, time = 900, maxErrors = 6 },
    -- Skimmer wiring: cut requested colors, strip to length, match terminals and pulse solder heat.
    -- solderMode: 'heat_feed', 'trace', or 'steady'; drift: true/false (default false).
    -- stripClick: jaw depth per click; snapRelease: pull distance; placementTol: pad tolerance.
    -- wires: 1–6; mistakes: failed operations allowed; stripTol/stripSpeed: stripping control.
    -- solderTime: seconds in the heat band; heatLow/heatHigh: safe band; heatRate/coolRate: temperature speed.
    skimmer_easy = { type = 'builtin', game = 'skimmer', level = 'easy', wires = 2, time = 100, mistakes = 4 },
    skimmer_medium = { type = 'builtin', game = 'skimmer', level = 'medium', wires = 3, time = 120, mistakes = 3 },
    skimmer_hard = { type = 'builtin', game = 'skimmer', level = 'hard', wires = 4, time = 150, mistakes = 2 },
    lockpick_easy = { type = 'builtin', game = 'lockpick', level = 'easy', pins = 3, speed = 0.8, zone = 0.22, time = 30, mistakes = 4, tol = 6, band = 26, showBand = true, drift = 3, shift = 5, spools = 0 },
    lockpick_medium = { type = 'builtin', game = 'lockpick', level = 'medium', pins = 4, speed = 1.1, zone = 0.16, time = 25, mistakes = 3, tol = 4, band = 17, showBand = false, drift = 5, shift = 8, spools = 1 },
    lockpick_hard = { type = 'builtin', game = 'lockpick', level = 'hard', pins = 6, speed = 1.5, zone = 0.1, time = 25, mistakes = 2, tol = 2.6, band = 11, showBand = false, drift = 7, shift = 11, spools = 2 },
    keypad_easy = { type = 'builtin', game = 'keypad', level = 'easy', length = 4, show = 3, time = 15, rounds = 1 },
    keypad_medium = { type = 'builtin', game = 'keypad', level = 'medium', length = 6, show = 3, time = 12, rounds = 2 },
    keypad_hard = { type = 'builtin', game = 'keypad', level = 'hard', length = 8, show = 2.5, time = 10, rounds = 3 },
    sequence_easy = { type = 'builtin', game = 'sequence', level = 'easy', keys = 6, perKey = 1.6, rounds = 1 },
    sequence_medium = { type = 'builtin', game = 'sequence', level = 'medium', keys = 8, perKey = 1.2, rounds = 2 },
    sequence_hard = { type = 'builtin', game = 'sequence', level = 'hard', keys = 10, perKey = 0.9, rounds = 2 },
    -- Shear Line themes: 'padlock' (default), 'camlock'. Grinder targets: 'shackle', 'bolts'.
    -- Drill: pins, tol (height), angTol (angle), wob, hard (hardened pins), oil (virtual cooling charges), time.
    lockpick_cam_medium = { type = 'builtin', game = 'lockpick', level = 'medium', theme = 'camlock', pins = 4, time = 50 },
    drill_easy = { type = 'builtin', game = 'drill', level = 'easy', theme = 'camlock', pins = 4, time = 70 },
    drill_medium = { type = 'builtin', game = 'drill', level = 'medium', theme = 'camlock', pins = 5, time = 70 },
    drill_hard = { type = 'builtin', game = 'drill', level = 'hard', theme = 'camlock', pins = 6, time = 70 },
    -- Grinder: cuts, tol (alignment), feed, heatRate, wearRate, wob, time; larger feed is faster.
    -- drift: load-driven movement; angleDrift: tilt under load; angleTol: allowable degrees from square.
    -- Set drift / angleDrift to 0 to disable either force. Mouse up/down or Q/E levels the handle.
    -- A/D or mouse left/right corrects position. mouseTilt: sensitivity (default 0.25; 0 disables mouse tilt).
    grinder_easy = { type = 'builtin', game = 'grinder', level = 'easy', target = 'shackle', cuts = 1, time = 60, drift = 14, angleDrift = 6, angleTol = 12 },
    grinder_medium = { type = 'builtin', game = 'grinder', level = 'medium', target = 'shackle', cuts = 1, time = 60, drift = 22, angleDrift = 10, angleTol = 9 },
    grinder_hard = { type = 'builtin', game = 'grinder', level = 'hard', target = 'shackle', cuts = 2, time = 60, drift = 30, angleDrift = 15, angleTol = 6 },
    grinder_bolts = { type = 'builtin', game = 'grinder', level = 'medium', target = 'bolts', cuts = 4, time = 120, drift = 22, angleDrift = 10, angleTol = 9 },
    skill_easy = { type = 'ox_skillcheck', level = 'easy', difficulty = { 'easy', 'easy' }, inputs = { 'e' } },
    skill_medium = { type = 'ox_skillcheck', level = 'medium', difficulty = { 'easy', 'medium', 'medium' }, inputs = { 'w', 'a', 's', 'd' } },
    skill_hard = { type = 'ox_skillcheck', level = 'hard', difficulty = { 'medium', 'hard', { areaSize = 30, speedMultiplier = 2 } }, inputs = { 'w', 'a', 's', 'd' } },
    ps_circle = { type = 'ps-ui', level = 'medium', game = 'circle', circles = 4, seconds = 10 },
    ps_thermite = { type = 'ps-ui', level = 'hard', game = 'thermite', seconds = 10, grid = 6, incorrect = 3 },
    ps_varhack = { type = 'ps-ui', level = 'hard', game = 'varhack', blocks = 6, seconds = 5 },
    bl_circle = { type = 'bl_ui', level = 'medium', game = 'CircleProgress', iterations = 3, difficulty = 50 },
    bl_untangle = { type = 'bl_ui', level = 'medium', game = 'Untangle', iterations = 1, config = { numberOfNodes = 8, duration = 15000 } },
    memory_thermite = { type = 'memorygame', level = 'hard', correct = 12, incorrect = 3, show = 3, lose = 12 },
    qb_lockpick = { type = 'builtin', level = 'medium', game = 'lockpick', pins = 4 },
    qb_hacking = { type = 'qb-minigames', level = 'hard', game = 'Hacking', length = 5, seconds = 30 },
    utk_fingerprint = { type = 'utk_fingerprint', level = 'hard', levels = 2, lives = 3, minutes = 2 },
    simon_easy = { type = 'builtin', game = 'simon', level = 'easy', start = 3, length = 5, show = 0.6, time = 10 },
    simon_medium = { type = 'builtin', game = 'simon', level = 'medium', start = 3, length = 7, show = 0.5, time = 8 },
    simon_hard = { type = 'builtin', game = 'simon', level = 'hard', start = 4, length = 10, show = 0.35, time = 6 },
    grid_easy = { type = 'builtin', game = 'grid', level = 'easy', size = 4, cells = 4, rounds = 2, show = 1.8, time = 12, mistakes = 2 },
    grid_medium = { type = 'builtin', game = 'grid', level = 'medium', size = 5, cells = 5, rounds = 3, show = 1.5, time = 10, mistakes = 1 },
    grid_hard = { type = 'builtin', game = 'grid', level = 'hard', size = 6, cells = 7, rounds = 3, show = 1.1, time = 8, mistakes = 0 },
    safe_easy = { type = 'builtin', game = 'safe', level = 'easy', numbers = 2, tolerance = 3, speed = 25, time = 45, mistakes = 3 },
    safe_medium = { type = 'builtin', game = 'safe', level = 'medium', numbers = 3, tolerance = 2, speed = 30, time = 40, mistakes = 2 },
    safe_hard = { type = 'builtin', game = 'safe', level = 'hard', numbers = 4, tolerance = 1, speed = 40, time = 40, mistakes = 1 },
    reaction_easy = { type = 'builtin', game = 'reaction', level = 'easy', grid = 3, targets = 8, life = 1.2, traps = 0.15, misses = 3 },
    reaction_medium = { type = 'builtin', game = 'reaction', level = 'medium', grid = 4, targets = 12, life = 0.9, traps = 0.25, misses = 2 },
    reaction_hard = { type = 'builtin', game = 'reaction', level = 'hard', grid = 5, targets = 16, life = 0.65, traps = 0.35, misses = 1 },
    order_easy = { type = 'builtin', game = 'order', level = 'easy', count = 8, time = 15, shuffle = false, mistakes = 1 },
    order_medium = { type = 'builtin', game = 'order', level = 'medium', count = 12, time = 15, shuffle = false, mistakes = 0 },
    order_hard = { type = 'builtin', game = 'order', level = 'hard', count = 10, time = 14, shuffle = true, mistakes = 0 },
    circle_easy = { type = 'builtin', game = 'circle', level = 'easy', zones = 3, zone = 36, speed = 0.45, time = 20, mistakes = 2 },
    circle_medium = { type = 'builtin', game = 'circle', level = 'medium', zones = 4, zone = 28, speed = 0.6, time = 20, mistakes = 1 },
    circle_hard = { type = 'builtin', game = 'circle', level = 'hard', zones = 6, zone = 20, speed = 0.8, time = 20, mistakes = 0 },
}
Config.MinigameFallback = nil -- preset used when a preset's resource isn't running (nil: built-in lockpick of its level)

-- Police alerts for vending machine crime (break-ins, hacks, thefts). System: 'auto' | 'ps-dispatch' | 'cd_dispatch'
-- | 'rush-dispatch' | 'qs-dispatch' | 'tk_dispatch' | 'core_dispatch' | 'rcore_dispatch' | 'lb-tablet' | 'builtin' | 'custom' | 'none'.
-- 'auto' uses the first of those that is running, else 'builtin' (notification + blip for Jobs).
Config.Police = {
    Enabled = true,
    System = 'auto',
    CrimeAlertStage = 'start', -- legacy/export alert stage; vending attempts use CrimeRules below; phone/GPS alerts are independent
    -- Per-action percentages: a witness OR an outcome roll can alert; at most one dispatch per attempt.
    -- These replace CrimeAlertStage for vending attempts. GPS/phone alerts stay independent.
    CrimeRules = {
        default = { witness = 100, fail = 50, success = 25 },
        pickpadlock = { witness = 100, fail = 50, success = 0 },
        pickseal = { witness = 100, fail = 50, success = 0 },
        rackpick = { witness = 100, fail = 50, success = 0 },
        installskimmer = { witness = 100, fail = 50, success = 0 },
        breakin = { witness = 100, fail = 50, success = 25 },
        cashbox = { witness = 100, fail = 50, success = 25 },
        -- Other actions (hack, fullhack, steal, disablegps, falsifylogs, takemachine) inherit default;
        -- add an entry with witness/fail/success percentages here to override any one action.
    },
    Witness = { Enabled = true, Radius = 25.0, Interval = 1000, FacingDot = 0.25 },
    Jobs = { 'police', 'sheriff' },  -- who counts as police (alerts, MinPolice)
    DispatchJobs = { 'leo' },        -- ps-dispatch job groups
    RushDispatchJobs = { 'lspd', 'bcso', 'sasp' }, -- actual job names used by rush-dispatch
    OnDutyOnly = true,
    Code = '10-90',
    Blip = { sprite = 52, color = 1, scale = 1.0, time = 90, radius = 40.0 },
    -- chance (%) at CrimeAlertStage; other crime stages never send police dispatch
    Alerts = {
        fullhack = { title = 'Vending machine system intrusion', message = 'Operating system intrusion detected on machine {serial}', code = '10-90', priority = 1, chance = { start = 100, fail = 100, success = 100 } },
        gps = { title = 'Vending machine GPS movement', message = 'Machine {serial} moved from its registered spot. {location}', chance = { movement = 0 } },
        disablegps = { title = 'Vending machine GPS tampering', message = 'GPS tampering detected on machine {serial}', chance = { start = 25, fail = 60, success = 10 } },
        installskimmer = { title = 'Vending machine reader tampering', message = 'Card reader tampering detected on machine {serial}', chance = { start = 25, fail = 50, success = 10 } },
        breakin = { title = 'Vending machine break-in', message = 'Someone is breaking into vending machine {serial}', code = '10-90', priority = 2,
            chance = { start = 50, fail = 100, success = 50 } },
        hack = { title = 'Vending machine tampering', message = 'Payment terminal of vending machine {serial} reported tampering', code = '10-90', priority = 3,
            chance = { start = 35, fail = 80, success = 25 } },
        steal = { title = 'Vending machine theft', message = 'Vending machine {serial} is being stolen', code = '10-90', priority = 1,
            chance = { start = 100, fail = 100, success = 100 }, blip = { sprite = 67 } },
    },
    -- System = 'custom': Custom = function(source, alert) ... end  (alert.coords, alert.title, alert.message, alert.code, alert.serial)
    Custom = nil,
    Phone = {
        Enabled = false, Resource = 'lb-phone', -- optional future phone delivery
        Recipient = 'controller', -- current network-chip controller (active hacker, otherwise owner); or 'owner' / 'actor'
        Mode = 'notification', -- 'notification' or 'sms'
        App = 'information-app', Title = 'Vending machine security',
        FromNumber = nil, -- SMS only: set a valid sender phone number for SendMessage
        Message = '{title}: {message} (stage: {stage})', -- {serial}, {action}, {stage}, {title}, {message}
        Stages = { start = true, fail = false, success = true, movement = true },
        Cooldown = 60, -- seconds per recipient / machine / action / stage; independent of police alert chances
    },
}

Config.Debug = false -- true: prints every item use / removal step to the server console

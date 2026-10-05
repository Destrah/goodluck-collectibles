-- 'starting' counts too, so start order in server.cfg doesn't matter
local function running(name)
    local state = GetResourceState(name)
    return state == 'started' or state == 'starting'
end

local function detectFramework()
    if Config.Framework ~= 'auto' then return Config.Framework end
    if running('qbx_core') then return 'qbox' end
    if running('qb-core') then return 'qbcore' end
    return 'standalone'
end

local function detectInventory(framework)
    if Config.Inventory ~= 'auto' then return Config.Inventory end
    if running('ox_inventory') then return 'ox_inventory' end
    if framework == 'qbcore' then return 'qbcore' end
    return 'none'
end

local function detectPersistence()
    if Config.Persistence ~= 'auto' then return Config.Persistence end
    if running(Config.Database.Resource or 'oxmysql') then return 'mysql' end
    return 'json'
end

local frameworkName = detectFramework()
local frameworkFactory = MetaComic.FrameworkAdapters[frameworkName]
if not frameworkFactory then error(('Unknown Meta Comic framework adapter: %s'):format(frameworkName)) end
MetaComic.Framework = frameworkFactory()

local inventoryName = detectInventory(frameworkName)
local inventoryFactory = MetaComic.InventoryAdapters[inventoryName]
if not inventoryFactory then error(('Unknown Meta Comic inventory adapter: %s'):format(inventoryName)) end
MetaComic.Inventory = inventoryFactory()

local persistenceName = detectPersistence()
local persistenceFactory = MetaComic.PersistenceAdapters[persistenceName]
if not persistenceFactory then error(('Unknown Meta Comic persistence adapter: %s'):format(persistenceName)) end
MetaComic.Persistence = persistenceFactory()
MetaComic.Persistence.init()

MetaComic.RuntimeInfo = {
    runtime = 'fivem',
    framework = MetaComic.Framework.name,
    inventory = MetaComic.Inventory.name,
    persistence = MetaComic.Persistence.name,
    capabilities = {
        editor = Config.Nui.AllowEditor == true,
        catalogWrite = Config.Catalog.AllowWrite == true,
        collection = MetaComic.Persistence.name ~= 'none',
    }
}

MetaComic.Debug('framework', MetaComic.Framework.name, 'inventory', MetaComic.Inventory.name, 'persistence', MetaComic.Persistence.name)

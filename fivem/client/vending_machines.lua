-- Placed vending machines (Config.VendingMachines). Every location lives in memory here; a machine's prop only
-- exists (client-side, not networked) while the player is near it. The distance check sleeps for as long as the
-- player needs to reach the closest spawn / despawn edge, so with nothing nearby it barely runs.
local cfg = Config.VendingMachines or {}
if cfg.Enabled == false then return end

local SPAWN = tonumber(cfg.SpawnDistance) or 100.0
local DESPAWN = math.max(SPAWN + 5.0, tonumber(cfg.DespawnDistance) or SPAWN + 20.0) -- gap stops flicker at the edge
local SPEED = tonumber(cfg.CheckSpeed) or 80.0 -- m/s the player is assumed to travel at most
local MIN_SLEEP, MAX_SLEEP = 250, tonumber(cfg.MaxSleep) or 5000

local machines, count = {}, 0
local access = { manage = false, restock = false } -- which ox_target options this player sees (the server re-checks)
local missingModels = {}
local byEntity = {} -- spawned prop -> machine, for ox_target lookups
local ghost

local function notify(message, notifyType) TriggerEvent('meta_comic:client:notify', message, notifyType) end

local function loadModel(hash)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function despawn(machine)
    if machine.entity then
        if DoesEntityExist(machine.entity) then DeleteEntity(machine.entity) end
        byEntity[machine.entity] = nil
        machine.entity = nil
    end
end

local function spawn(machine)
    if machine.entity or machine.loading or missingModels[machine.hash] then return end
    machine.loading = true
    local hash = loadModel(machine.hash)
    machine.loading = false
    if not hash then
        missingModels[machine.hash] = true
        print(('[meta-comic] vending machine model %s is not streamed (is stream/metacomics_props.ytyp loaded?)'):format(machine.model))
        return
    end
    if machines[machine.id] ~= machine then return SetModelAsNoLongerNeeded(hash) end -- removed while loading
    local entity = CreateObjectNoOffset(hash, machine.coords.x, machine.coords.y, machine.coords.z, false, false, false)
    SetEntityHeading(entity, machine.heading)
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)
    SetModelAsNoLongerNeeded(hash)
    machine.entity = entity
    byEntity[entity] = machine
end

local function add(entry)
    local id = tonumber(entry.id)
    if not id then return end
    local coords, heading = vector3(entry.x + 0.0, entry.y + 0.0, entry.z + 0.0), (entry.h or 0.0) + 0.0
    local existing = machines[id]
    if existing and existing.model == entry.model and existing.coords == coords and existing.heading == heading then
        existing.products = entry.products or {} -- stock / price update: keep the spawned prop
        return existing
    end
    if existing then despawn(existing) else count = count + 1 end
    machines[id] = {
        id = id,
        model = entry.model,
        hash = joaat(entry.model),
        coords = coords,
        heading = heading,
        products = entry.products or {},
    }
    return machines[id]
end

local function remove(id)
    local machine = machines[id]
    if not machine then return end
    despawn(machine)
    machines[id] = nil
    count = count - 1
end

RegisterNetEvent('meta_comic:client:vendingMachines', function(list, playerAccess)
    local keep = {}
    for _, entry in ipairs(list or {}) do keep[tonumber(entry.id) or 0] = true end
    for id in pairs(machines) do if not keep[id] then remove(id) end end
    for _, entry in ipairs(list or {}) do add(entry) end
    if type(playerAccess) == 'table' then access = playerAccess end
end)

RegisterNetEvent('meta_comic:client:vendingAccess', function(playerAccess)
    if type(playerAccess) == 'table' then access = playerAccess end
end)
-- a new job can add or take away the Restock option
RegisterNetEvent('QBCore:Client:OnJobUpdate', function() TriggerServerEvent('meta_comic:server:vendingAccess') end)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() TriggerServerEvent('meta_comic:server:vendingAccess') end)

RegisterNetEvent('meta_comic:client:vendingMachineAdded', function(entry)
    local machine = add(entry)
    -- show a fresh placement right away instead of waiting for the next distance check
    if machine and #(GetEntityCoords(PlayerPedId()) - machine.coords) <= SPAWN then spawn(machine) end
end)

RegisterNetEvent('meta_comic:client:vendingMachineRemoved', function(id) remove(tonumber(id)) end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    TriggerServerEvent('meta_comic:server:vendingMachines')
end)

CreateThread(function()
    while true do
        local sleep = MAX_SLEEP
        if count > 0 then
            local position = GetEntityCoords(PlayerPedId())
            local margin = math.huge -- metres until any machine has to change state
            local toSpawn = {}
            for _, machine in pairs(machines) do
                local distance = #(position - machine.coords)
                if machine.entity and distance > DESPAWN then despawn(machine) end
                if machine.entity then
                    margin = math.min(margin, DESPAWN - distance)
                elseif distance <= SPAWN then
                    toSpawn[#toSpawn + 1] = machine
                    margin = math.min(margin, DESPAWN - distance)
                else
                    margin = math.min(margin, distance - SPAWN)
                end
            end
            -- spawned after the loop: loading a model waits, and the list may change meanwhile
            for _, machine in ipairs(toSpawn) do spawn(machine) end
            sleep = math.floor(math.max(MIN_SLEEP, math.min(MAX_SLEEP, margin / SPEED * 1000)))
        end
        Wait(sleep)
    end
end)

-- Placement --------------------------------------------------------------------------------------------------------
local CONTROLS = {
    place = { 24, 191 },       -- left mouse, Enter
    cancel = { 25, 177, 200 }, -- right mouse, Backspace, Esc
    left = 44, right = 38,     -- Q / E (held)
    wheelUp = 241, wheelDown = 242,
    fine = 21,                 -- Shift
}
local BLOCKED = { 14, 15, 16, 17, 24, 25, 37, 38, 44, 45, 47, 58, 69, 70, 86, 92, 140, 141, 142, 143, 177, 191, 200, 241, 242, 257, 263, 264 }
local HELP = '~INPUT_ATTACK~ Place   ~INPUT_AIM~ Cancel~n~~INPUT_COVER~ ~INPUT_PICKUP~ or scroll: rotate   ~INPUT_SPRINT~ fine'

local function anyPressed(list)
    for _, control in ipairs(list) do if IsDisabledControlJustPressed(0, control) then return true end end
    return false
end

local function cameraRay(distance)
    local from = GetGameplayCamCoord()
    local rotation = GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local flat = math.abs(math.cos(pitch))
    local to = from + vector3(-math.sin(yaw) * flat, math.cos(yaw) * flat, math.sin(pitch)) * distance
    -- 1 world + 2 vehicles + 16 objects; the ghost has no collision so it is never hit
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 19, PlayerPedId(), 4)
    local _, hit, coords = GetShapeTestResult(handle)
    return hit == 1 or hit == true, coords
end

local function outline(entity, valid)
    if not SetEntityDrawOutline then return end
    if valid ~= nil and SetEntityDrawOutlineColor then
        if valid then SetEntityDrawOutlineColor(80, 220, 120, 255) else SetEntityDrawOutlineColor(235, 70, 70, 255) end
    end
    SetEntityDrawOutline(entity, valid ~= nil)
end

local function clearGhost()
    if ghost and DoesEntityExist(ghost) then outline(ghost, nil); DeleteEntity(ghost) end
    ghost = nil
end

-- shows the see-through preview until the player places it (returns vector4) or cancels (returns nil).
-- startHeading: initial rotation, otherwise facing the camera
local function placeGhost(modelName, startHeading)
    local hash = loadModel(joaat(modelName))
    if not hash then return notify(('Model %s is not streamed. Check stream/metacomics_props.ytyp.'):format(modelName), 'error') end

    local minimum = GetModelDimensions(hash)
    local lift = -minimum.z -- puts the model's base on the surface wherever its origin is
    local reach = tonumber(cfg.PlaceDistance) or 15.0
    local heading = startHeading or (GetGameplayCamRot(2).z + 180.0) % 360.0 -- start facing the camera
    local start = GetEntityCoords(PlayerPedId())
    ghost = CreateObjectNoOffset(hash, start.x, start.y, start.z - 50.0, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityAlpha(ghost, tonumber(cfg.GhostAlpha) or 150, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityInvincible(ghost, true)

    local placed
    while ghost do
        local playerId, ped = PlayerId(), PlayerPedId()
        DisablePlayerFiring(playerId, true)
        for _, control in ipairs(BLOCKED) do DisableControlAction(0, control, true) end

        local hit, coords = cameraRay(reach + 10.0)
        local valid = hit and #(GetEntityCoords(ped) - coords) <= reach
        SetEntityVisible(ghost, hit, false)
        if hit then
            SetEntityCoordsNoOffset(ghost, coords.x, coords.y, coords.z + lift, false, false, false)
            SetEntityHeading(ghost, heading)
            outline(ghost, valid)
        end

        local fine = IsControlPressed(0, CONTROLS.fine) or IsDisabledControlPressed(0, CONTROLS.fine)
        local step = fine and 1.0 or 15.0
        local speed = (fine and 20.0 or 90.0) * GetFrameTime()
        if IsDisabledControlJustPressed(0, CONTROLS.wheelUp) then heading = heading + step end
        if IsDisabledControlJustPressed(0, CONTROLS.wheelDown) then heading = heading - step end
        if IsDisabledControlPressed(0, CONTROLS.left) then heading = heading + speed end
        if IsDisabledControlPressed(0, CONTROLS.right) then heading = heading - speed end
        heading = heading % 360.0

        BeginTextCommandDisplayHelp('STRING')
        AddTextComponentSubstringPlayerName(HELP .. ('~n~Heading: %d°'):format(math.floor(heading + 0.5) % 360))
        EndTextCommandDisplayHelp(0, false, false, -1)

        if anyPressed(CONTROLS.cancel) then
            break
        elseif anyPressed(CONTROLS.place) then
            if valid then
                placed = vector4(coords.x, coords.y, coords.z + lift, heading)
                break
            end
            notify(hit and 'Too far away: move closer.' or 'Look at the ground where it should stand.', 'error')
        end
        Wait(0)
    end
    clearGhost()
    return placed
end

RegisterNetEvent('meta_comic:client:placeVendingMachine', function()
    if ghost then return notify('You are already placing a vending machine.', 'error') end
    local placed = placeGhost(cfg.Model or 'metacomics_vending_machine')
    if placed then
        TriggerServerEvent('meta_comic:server:placeVendingMachine', placed.x, placed.y, placed.z, placed.w)
    else
        notify('Vending machine placement cancelled.', 'info')
    end
end)

-- Manage > Move machine: the current prop is hidden while the preview is out, and comes back if cancelled
local function moveMachine(id)
    local machine = machines[id]
    if not machine then return notify('That vending machine no longer exists.', 'error') end
    if ghost then return notify('You are already placing a vending machine.', 'error') end
    local entity = machine.entity
    if entity and DoesEntityExist(entity) then
        SetEntityVisible(entity, false, false)
        SetEntityCollision(entity, false, false) -- or the aim ray would hit the old machine
    end
    local placed = placeGhost(machine.model, machine.heading)
    if entity and DoesEntityExist(entity) then
        SetEntityVisible(entity, true, false)
        SetEntityCollision(entity, true, true)
    end
    if placed then
        TriggerServerEvent('meta_comic:server:moveVendingMachine', id, placed.x, placed.y, placed.z, placed.w)
    else
        notify('Move cancelled.', 'info')
    end
end

RegisterNetEvent('meta_comic:client:removeVendingMachine', function()
    local position = GetEntityCoords(PlayerPedId())
    local nearest, best = nil, tonumber(cfg.RemoveDistance) or 5.0
    for id, machine in pairs(machines) do
        local distance = #(position - machine.coords)
        if distance <= best then nearest, best = id, distance end
    end
    if not nearest then return notify('No vending machine close enough to remove.', 'error') end
    TriggerServerEvent('meta_comic:server:removeVendingMachine', nearest)
end)


-- ox_target + ox_lib menus ------------------------------------------------------------------------------------------
-- Buy: everyone. Restock: managers and employees (Config.VendingMachines.Restock.Jobs). Manage: managers.
-- The server checks permission, distance, price and stock on every action.
local shop = cfg.Shop or {}
local MAX_STOCK = math.max(1, math.floor(tonumber((cfg.Restock or {}).MaxStock) or 100))

local function machineOf(entity)
    return entity and byEntity[entity] or nil
end
local function kindLabel(kind) return kind == 'box' and 'Booster Box' or 'Booster Pack' end
local function productTitle(product) return ('%s %s'):format(product.setName or product.set, kindLabel(product.kind)) end
local function money(n) return ('$%d'):format(math.floor(tonumber(n) or 0)) end
-- the set's logo as the option icon (URLs) and as the picture beside the menu
local function productIcon(product, fallback)
    local logo = product.logo
    if type(logo) == 'string' and (logo:match('^https?://') or logo:match('^nui://')) then return logo end
    return fallback
end
local function productImage(product) return type(product.logo) == 'string' and product.logo ~= '' and product.logo or nil end
local function menu(id, title, options, parent)
    exports.ox_lib:registerContext({ id = id, title = title, menu = parent, options = options })
    exports.ox_lib:showContext(id)
end
local function input(title, rows)
    return exports.ox_lib:inputDialog(title, rows)
end
local function needsOxLib()
    if GetResourceState('ox_lib') == 'started' then return true end
    notify('Vending machine menus need ox_lib.', 'error')
    return false
end

local function openBuy(machine)
    if not needsOxLib() then return end
    local options = {}
    for _, product in ipairs(machine.products) do
        local soldOut = (product.stock or 0) < 1
        options[#options + 1] = {
            title = productTitle(product),
            description = soldOut and 'Sold out' or ('%s · %d left'):format(money(product.price), product.stock),
            icon = productIcon(product, product.kind == 'box' and 'boxes-stacked' or 'box-open'),
            image = productImage(product),
            disabled = soldOut,
            onSelect = function() TriggerServerEvent('meta_comic:server:vendingBuy', machine.id, product.set, product.kind) end,
        }
    end
    if #options == 0 then options[1] = { title = 'Nothing for sale', disabled = true } end
    menu('meta_comic_vending_buy', 'Vending Machine', options)
end

local function openRestock(machine, maxStock)
    if not needsOxLib() then return end
    local MAX_STOCK = maxStock or MAX_STOCK
    local options = {}
    for _, product in ipairs(machine.products) do
        options[#options + 1] = {
            title = productTitle(product),
            description = ('Stock %d / %d'):format(product.stock or 0, MAX_STOCK),
            icon = productIcon(product, 'truck-ramp-box'),
            image = productImage(product),
            disabled = (product.stock or 0) >= MAX_STOCK,
            onSelect = function()
                local room = MAX_STOCK - (product.stock or 0)
                local result = input(('Restock %s'):format(productTitle(product)), {
                    { type = 'number', label = 'Amount (taken from your inventory)', description = ('You need that many %s in your inventory.'):format(productTitle(product)), default = 1, min = 1, max = room, required = true },
                })
                if result and tonumber(result[1]) then
                    TriggerServerEvent('meta_comic:server:vendingRestock', machine.id, product.set, product.kind, tonumber(result[1]))
                end
            end,
        }
    end
    if #options == 0 then options[1] = { title = 'This machine sells nothing yet', disabled = true } end
    menu('meta_comic_vending_restock', 'Restock Vending Machine', options)
end

-- the server answers Buy / Restock with this machine's current products, so the menus never show a stale copy
RegisterNetEvent('meta_comic:client:vendingOpen', function(id, mode, products, maxStock)
    local machine = { id = id, products = products or {} }
    if machines[id] then machines[id].products = machine.products end
    if mode == 'restock' then openRestock(machine, tonumber(maxStock)) else openBuy(machine) end
end)

local function sendProduct(id, action, data) TriggerServerEvent('meta_comic:server:vendingProduct', id, action, data) end

-- the server sends this after "Manage" and after every change, so the menu always shows saved values
RegisterNetEvent('meta_comic:client:vendingManage', function(id, products, sets, maxStock)
    if not needsOxLib() then return end
    maxStock = tonumber(maxStock) or MAX_STOCK
    local options = {}
    for _, product in ipairs(products or {}) do
        local key = { set = product.set, kind = product.kind }
        local subId = ('meta_comic_vending_product_%s_%s'):format(product.set, product.kind)
        options[#options + 1] = {
            title = productTitle(product),
            description = ('%s · stock %d / %d'):format(money(product.price), product.stock or 0, maxStock),
            icon = productIcon(product, product.kind == 'box' and 'boxes-stacked' or 'box-open'),
            image = productImage(product),
            arrow = true,
            onSelect = function()
                menu(subId, productTitle(product), {
                    { title = 'Change price', description = money(product.price), icon = 'tag', onSelect = function()
                        local result = input('Price', { { type = 'number', label = 'Price ($)', default = product.price, min = 0, required = true } })
                        if result and tonumber(result[1]) then sendProduct(id, 'price', { set = key.set, kind = key.kind, price = tonumber(result[1]) }) end
                    end },
                    { title = 'Lower stock', description = ('%d / %d (add stock with Restock)'):format(product.stock or 0, maxStock), icon = 'warehouse', disabled = (product.stock or 0) < 1, onSelect = function()
                        local result = input('Lower stock', { { type = 'number', label = 'Stock', default = product.stock or 0, min = 0, max = product.stock or 0, required = true } })
                        if result and tonumber(result[1]) then sendProduct(id, 'stock', { set = key.set, kind = key.kind, stock = tonumber(result[1]) }) end
                    end },
                    { title = 'Remove from machine', icon = 'trash', onSelect = function()
                        local confirm = exports.ox_lib:alertDialog({ header = 'Remove product', content = ('Stop selling %s here? Its stock is dropped.'):format(productTitle(product)), cancel = true })
                        if confirm == 'confirm' then sendProduct(id, 'remove', key) end
                    end },
                }, 'meta_comic_vending_manage')
            end,
        }
    end
    local setOptions = {}
    for _, set in ipairs(sets or {}) do setOptions[#setOptions + 1] = { value = set.id, label = set.name } end
    options[#options + 1] = {
        title = 'Move machine',
        description = 'Pick it up and place it somewhere else nearby',
        icon = 'up-down-left-right',
        onSelect = function() CreateThread(function() moveMachine(id) end) end,
    }
    options[#options + 1] = {
        title = 'Add product',
        description = 'Sell booster packs and/or boxes of a set here (stock them with Restock)',
        icon = 'plus',
        disabled = #setOptions == 0,
        onSelect = function()
            local result = input('Add product', {
                { type = 'select', label = 'Card set', options = setOptions, required = true },
                { type = 'multi-select', label = 'Sell', options = { { value = 'pack', label = 'Booster Packs' }, { value = 'box', label = 'Booster Boxes' } }, default = { 'pack' }, required = true },
                { type = 'number', label = 'Pack price ($)', default = 250, min = 0 },
                { type = 'number', label = 'Box price ($)', default = 2500, min = 0 },
            })
            if not result or not result[1] then return end
            for _, kind in ipairs(type(result[2]) == 'table' and result[2] or { result[2] }) do
                sendProduct(id, 'add', {
                    set = result[1], kind = kind,
                    price = tonumber(kind == 'box' and result[4] or result[3]) or 0,
                })
            end
        end,
    }
    menu('meta_comic_vending_manage', ('Manage Vending Machine #%d'):format(id), options)
end)

CreateThread(function()
    local timeout = GetGameTimer() + 30000
    while GetResourceState('ox_target') ~= 'started' do
        if GetGameTimer() > timeout or GetResourceState('ox_target') == 'missing' then return end
        Wait(500)
    end
    local distance = tonumber(shop.TargetDistance) or 2.0
    exports.ox_target:addModel(cfg.Model or 'metacomics_vending_machine', {
        {
            name = 'meta_comic_vending_buy', label = 'Buy', icon = 'fas fa-cart-shopping', distance = distance,
            canInteract = function(entity) return shop.Enabled ~= false and machineOf(entity) ~= nil end,
            onSelect = function(data)
                local machine = machineOf(data.entity)
                if machine then TriggerServerEvent('meta_comic:server:vendingOpen', machine.id, 'buy') end
            end,
        },
        {
            name = 'meta_comic_vending_restock', label = 'Restock', icon = 'fas fa-truck-ramp-box', distance = distance,
            canInteract = function(entity) return access.restock == true and machineOf(entity) ~= nil end,
            onSelect = function(data)
                local machine = machineOf(data.entity)
                if machine then TriggerServerEvent('meta_comic:server:vendingOpen', machine.id, 'restock') end
            end,
        },
        {
            name = 'meta_comic_vending_manage', label = 'Manage', icon = 'fas fa-gear', distance = distance,
            canInteract = function(entity) return access.manage == true and machineOf(entity) ~= nil end,
            onSelect = function(data)
                local machine = machineOf(data.entity)
                if machine then TriggerServerEvent('meta_comic:server:vendingManage', machine.id) end
            end,
        },
    })
end)

-- admin UI map: "Set waypoint" on a machine
RegisterNUICallback('vendingWaypoint', function(data, cb)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if x and y then SetNewWaypoint(x + 0.0, y + 0.0) end
    cb({ ok = x ~= nil and y ~= nil })
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    clearGhost()
    for _, machine in pairs(machines) do despawn(machine) end
end)

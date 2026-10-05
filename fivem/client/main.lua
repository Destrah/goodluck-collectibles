local pending = {}
local nextRequestId = 0
local nuiOpen = false

-- Normal reliable net events are ideal for the small RPCs in this resource, but the card
-- editor can legitimately send a much larger catalog (especially when an editor file
-- input has produced a data:image/... URL). FiveM explicitly recommends latent events
-- for multi-KB payloads so they are fragmented/throttled instead of overflowing the
-- reliable-event channel. Keep small RPCs instant and automatically move large ones to
-- the latent transport.
local RPC_LATENT_THRESHOLD = 16 * 1024
local RPC_LATENT_BPS = 512 * 1024

local function estimatedRpcBytes(requestId, action, payload)
    local ok, encoded = pcall(json.encode, { requestId = requestId, action = action, payload = payload or {} })
    return ok and type(encoded) == 'string' and #encoded or 0
end

local function serverRpc(action, payload, timeoutMs)
    nextRequestId = nextRequestId + 1
    local requestId = ('%s:%s'):format(GetPlayerServerId(PlayerId()), nextRequestId)
    local promiseObject = promise.new()
    pending[requestId] = promiseObject

    local rpcPayload = payload or {}
    local bytes = estimatedRpcBytes(requestId, action, rpcPayload)
    -- saveCatalog is deliberately always latent. Even a modest catalog is much larger
    -- than the other RPCs, and an embedded editor image can make it several megabytes.
    if action == 'saveCatalog' or bytes >= RPC_LATENT_THRESHOLD then
        TriggerLatentServerEvent('meta_comic:server:rpc', RPC_LATENT_BPS, requestId, action, rpcPayload)
    else
        TriggerServerEvent('meta_comic:server:rpc', requestId, action, rpcPayload)
    end

    SetTimeout(timeoutMs or 12000, function()
        if pending[requestId] then
            pending[requestId] = nil
            promiseObject:resolve({ ok = false, error = 'Card server request timed out.' })
        end
    end)

    return Citizen.Await(promiseObject)
end

RegisterNetEvent('meta_comic:client:rpcResult', function(requestId, response)
    local promiseObject = pending[requestId]
    if not promiseObject then return end
    pending[requestId] = nil
    promiseObject:resolve(response)
end)

local function openNui(view, action, overlay, mode)
    nuiOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'metaComic:open', view = view or Config.Nui.DefaultView, action = action, overlay = overlay == true, mode = mode })
end

-- Centre-screen pack opening (no lab UI): the pack animation and the card fan-out play in the middle of the screen.
local function openPackOverlay()
    openNui('pack', 'openPack', true)
end

local function openPackOptions()
    openNui('pack', nil, true, 'options')
end

local function openManagement()
    -- Authorize before taking NUI focus. This keeps the permission boundary on
    -- the server and avoids trapping an unauthorized player in an empty overlay.
    local runtimeInfo = serverRpc('getRuntimeInfo', {}, 12000)
    if not runtimeInfo or runtimeInfo.ok == false then
        TriggerEvent('meta_comic:client:notify', (runtimeInfo and runtimeInfo.error) or 'Could not verify card-admin permissions.', 'error')
        return
    end
    if not runtimeInfo.capabilities or runtimeInfo.capabilities.management ~= true then
        TriggerEvent('meta_comic:client:notify', 'You do not have permission to manage trading cards.', 'error')
        return
    end

    nuiOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    -- One canonical React route for the full admin UI. The old compatibility-only
    -- managementOpen message intentionally is no longer used.
    SendNUIMessage({
        type = 'metaComic:open',
        view = runtimeInfo.capabilities.editor == true and 'editor' or 'gallery',
        overlay = false,
        mode = 'admin',
        runtimeInfo = runtimeInfo,
    })
end

local stopPackProp -- defined below

local function closeNui()
    if stopPackProp then stopPackProp() end
    nuiOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'metaComic:close' })
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function playPropSequence(kind)
    if not Config.Props.Enabled then return end
    local data = kind == 'box' and Config.Props.Box or Config.Props.Pack
    if not data or not data.model then return end

    local model = loadModel(data.model)
    if not model then return end

    local ped = PlayerPedId()
    RequestAnimDict('mp_arresting')
    while not HasAnimDictLoaded('mp_arresting') do Wait(0) end
    TaskPlayAnim(ped, 'mp_arresting', 'a_uncuff', 8.0, -8.0, -1, 17, 0.0, false, false, false)

    local coords = GetEntityCoords(ped)
    local prop = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
    if DoesEntityExist(prop) then
        local offset = data.offset or vector3(0.1, 0.1, 0.0)
        local rotation = data.rotation or vector3(70.0, 10.0, 90.0)
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, data.bone or 0xDEAD), offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, false, false, false, false, 2, true)
        Wait(data.duration or 1000)
        DeleteEntity(prop)
    end
    ClearPedTasks(ped)
    SetModelAsNoLongerNeeded(model)
end

-- Character holds the pack prop from the rip until the cards have fanned out (the NUI sends start / stop).
local PACK_DICT, PACK_ANIM = 'mp_arresting', 'a_uncuff'
local packPropEntity = nil
local packPropActive = false
local packPropGen = 0 -- each start gets a new generation, so a stale thread can never leave a prop behind

stopPackProp = function()
    packPropActive = false
    if packPropEntity and DoesEntityExist(packPropEntity) then DeleteEntity(packPropEntity) end
    packPropEntity = nil
    StopAnimTask(PlayerPedId(), PACK_DICT, PACK_ANIM, 1.0)
end

local function startPackProp()
    if packPropActive or not Config.Props.Enabled then return end
    packPropActive = true
    packPropGen = packPropGen + 1
    local gen = packPropGen
    CreateThread(function()
        local data = Config.Props.Pack or {}
        local ped = PlayerPedId()
        RequestAnimDict(PACK_DICT)
        local timeout = GetGameTimer() + 3000
        while not HasAnimDictLoaded(PACK_DICT) and GetGameTimer() < timeout do Wait(0) end

        local model = data.model and loadModel(data.model)
        if not packPropActive or gen ~= packPropGen then return end
        if model then
            local coords = GetEntityCoords(ped)
            packPropEntity = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
            if DoesEntityExist(packPropEntity) then
                local offset = data.offset or vector3(0.1, 0.1, 0.0)
                local rotation = data.rotation or vector3(70.0, 10.0, 90.0)
                AttachEntityToEntity(packPropEntity, ped, GetPedBoneIndex(ped, data.bone or 0xDEAD), offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, false, false, false, false, 2, true)
            end
            SetModelAsNoLongerNeeded(model)
        end

        -- loop the upper-body animation until the NUI says the cards are out (safety limit: MaxDuration)
        local deadline = GetGameTimer() + (data.MaxDuration or 30000)
        while packPropActive and gen == packPropGen and GetGameTimer() < deadline do
            if not IsEntityPlayingAnim(ped, PACK_DICT, PACK_ANIM, 3) then
                TaskPlayAnim(ped, PACK_DICT, PACK_ANIM, 8.0, -8.0, -1, 49, 0.0, false, false, false)
            end
            Wait(200)
        end
        if packPropActive and gen == packPropGen then stopPackProp() end
    end)
end

RegisterNUICallback('packProp', function(data, cb)
    cb({ ok = true })
    if data and data.state == 'start' then startPackProp() else stopPackProp() end
end)

RegisterNUICallback('getRuntimeInfo', function(_, cb)
    cb(serverRpc('getRuntimeInfo', {}))
end)

RegisterNUICallback('resolveRemoteAsset', function(data, cb)
    cb(serverRpc('resolveRemoteAsset', data or {}, 60000))
end)

-- Per-player pack animation preferences, stored in client KVP (speed is clamped to 1.0 .. Config.PackAnimation.MaxSpeed).
local PREFS_KEY = 'meta_comic:pack_prefs'

RegisterNUICallback('getPackPrefs', function(_, cb)
    local raw = GetResourceKvpString(PREFS_KEY)
    if not raw then
        raw = GetResourceKvpString(MetaComic.Legacy.prefsKey)
        if raw then SetResourceKvp(PREFS_KEY, raw) end
    end
    local ok, prefs = pcall(function() return raw and json.decode(raw) or nil end)
    if not ok or type(prefs) ~= 'table' then
        prefs = { speed = 1.0, tear = 'random', fan = 'random' }
    end
    cb({ ok = true, prefs = prefs })
end)

RegisterNUICallback('savePackPrefs', function(data, cb)
    local prefs = data and data.prefs or {}
    local maxSpeed = (Config.PackAnimation and Config.PackAnimation.MaxSpeed) or 3.0
    local speed = tonumber(prefs.speed) or 1.0
    if speed < 1.0 then speed = 1.0 end
    if speed > maxSpeed then speed = maxSpeed end

    local allowedTears = { peel = true, top = true, random = true }
    local allowedFans = { line = true, arc = true, wave = true, deal = true, random = true }
    local tear = tostring(prefs.tear or 'random')
    local fan = tostring(prefs.fan or 'random')
    if not allowedTears[tear] then tear = 'random' end
    if not allowedFans[fan] then fan = 'random' end

    local containerAnimations={}
    local allowed={bag={float=true,pour=true,pop=true},box={lift=true,unfold=true,burst=true},case={lift=true,unfold=true,burst=true}}
    for kind,choices in pairs(allowed) do
        local selected=type(prefs.containerAnimations)=='table' and prefs.containerAnimations[kind] or 'random'
        containerAnimations[kind]=choices[selected] and selected or 'random'
    end
    local clean={speed=speed,tear=tear,fan=fan,containerAnimations=containerAnimations}
    SetResourceKvp(PREFS_KEY, json.encode(clean))
    cb({ ok = true, prefs = clean })
end)

RegisterNUICallback('getCatalog', function(_, cb)
    cb(serverRpc('getCatalog', {}, 120000))
end)

RegisterNUICallback('saveCatalog', function(data, cb)
    cb(serverRpc('saveCatalog', data or {}, 120000))
end)

RegisterNUICallback('saveCard', function(data, cb)
    cb(serverRpc('saveCard', data or {}, 120000))
end)

RegisterNUICallback('deleteCard', function(data, cb)
    cb(serverRpc('deleteCard', data or {}, 20000))
end)

-- Compatibility helper for the checked-in prebuilt NUI: reverting a draft reloads the
-- page so the old compiled React state is discarded, then asks the normal /cardadmin
-- path to reopen after the fresh page has installed its message listeners.
RegisterNUICallback('reopenAdmin', function(_, cb)
    cb({ ok = true })
    CreateThread(function()
        Wait(350)
        openManagement()
    end)
end)

RegisterNUICallback('getSets', function(_, cb)
    cb(serverRpc('getSets', {}))
end)

RegisterNUICallback('saveSets', function(data, cb)
    cb(serverRpc('saveSets', data or {}, 20000))
end)

RegisterNUICallback('printCard', function(data, cb)
    cb(serverRpc('printCard', data or {}, 20000))
end)

RegisterNUICallback('createSealed', function(data, cb)
    cb(serverRpc('createSealed', data or {}, 20000))
end)

RegisterNUICallback('getCollection', function(_, cb)
    cb(serverRpc('getCollection', {}))
end)

for _,action in ipairs({'getCollectibles','saveCollectible','openCollectibleContainer','createCollectibleContainer','claimCollectibles'}) do
    RegisterNUICallback(action,function(data,cb) cb(serverRpc(action,data or {},120000)) end)
end

RegisterNetEvent('meta_comic:client:openCollectible',function(typeId,slot,outer)
    openNui('pack')
    SendNUIMessage({type='metaComic:collectibleContainer',typeId=typeId,slot=slot,outer=outer==true})
end)

RegisterNUICallback('swapBinderCards', function(data, cb)
    local response = serverRpc('swapBinderCards', data or {}, 12000)
    cb(response)
    -- Compatibility for the prebuilt FiveM NUI shipped with older project zips. Native React builds update
    -- their own binder state; the compatibility drag layer asks us to resend the authoritative binder after
    -- its drop animation finishes.
    if data and data.compatRefresh == true and response and response.ok and response.binder then
        SetTimeout(760, function()
            if not nuiOpen then return end
            SendNUIMessage({ type = 'metaComic:open', view = 'pack', overlay = true, mode = 'binder', binder = response.binder })
        end)
    end
end)

RegisterNUICallback('openPack', function(data, cb)
    -- the character animation is driven by the NUI (packProp start / stop) so it lasts until the cards are fanned out
    cb(serverRpc('openPack', data or {}))
end)

RegisterNUICallback('openBox', function(data, cb)
    local response = serverRpc('openBox', data or {})
    if response and response.ok then playPropSequence('box') end
    cb(response)
end)

-- Card inventory icons (Config.CardIcons.Mode = 'upload'): the server asks this player's NUI to draw icons
-- for prints that don't have one yet; the result goes back to the server, which uploads it.
RegisterNetEvent('meta_comic:client:renderIcons', function(items, size, format)
    if type(items) ~= 'table' or #items == 0 then return end
    SendNUIMessage({ type = 'metaComic:renderIcons', items = items, size = size, format = format })
end)

RegisterNUICallback('cardIcon', function(data, cb)
    cb({ ok = true })
    if type(data) == 'table' and type(data.key) == 'string' then
        -- an empty string tells the server this icon couldn't be drawn, so it moves on
        TriggerLatentServerEvent('meta_comic:server:cardIcon', 60000, data.key, type(data.data) == 'string' and data.data or '')
    end
end)

-- The NUI has loaded: once the player is in the session, tell the server. It refreshes this player's card item
-- icons and may ask this NUI to draw catalog icons that are still missing (Config.CardIcons.Mode = 'upload').
local uiReadySent = false
RegisterNUICallback('uiReady', function(_, cb)
    cb({ ok = true })
    if uiReadySent then return end
    uiReadySent = true
    CreateThread(function()
        while not NetworkIsPlayerActive(PlayerId()) do Wait(1000) end
        Wait(5000) -- let the inventory load first
        TriggerServerEvent('meta_comic:server:uiReady')
    end)
end)

RegisterNUICallback('claimCards', function(_, cb)
    cb(serverRpc('claimCards', {}))
end)

RegisterNUICallback('close', function(_, cb)
    local response=serverRpc('claimCollectibles',{},120000)
    if response and response.ok==false then TriggerEvent('meta_comic:client:notify',response.error or 'Collectible delivery is pending; free inventory space and retry.','error') end
    closeNui()
    cb({ ok = true })
end)

RegisterNetEvent('meta_comic:client:open', function(view, action)
    openNui(view, action)
end)

-- A booster pack item was used: the server already took the item, open it in the middle of the screen.
RegisterNetEvent('meta_comic:client:openPackOverlay', function()
    openPackOverlay()
end)

-- A booster box item was used: the server already handed out Config.Items.PacksPerBox packs.
-- (Hook for a future box-opening animation; for now just the hand prop.)
RegisterNetEvent('meta_comic:client:boxOpened', function(packs)
    CreateThread(function() playPropSequence('box') end)
end)

-- ox_inventory item exports. ox calls these with the used item's data; we only forward the slot to the server,
-- which checks the player's own inventory and removes the item itself.
-- Names used by the example items AND the names in your own items.lua both work:
--   boosterpack -> useBoosterPack / OpenPack, boosterbox -> useBoosterBox / OpenBox, tradingcard -> useTradingCard / ShowCard
local function oxItem(...)
    for i = 1, select('#', ...) do
        local value = select(i, ...)
        if type(value) == 'table' and (value.name or value.slot) then return value end
    end
end
local function slotOf(...)
    for i = 1, select('#', ...) do
        local value = select(i, ...)
        if type(value) == 'table' and tonumber(value.slot) then return tonumber(value.slot) end
        if type(value) == 'number' or type(value) == 'string' then
            if tonumber(value) then return tonumber(value) end
        end
    end
end

local function usePack(...) TriggerServerEvent('meta_comic:server:useItem', 'pack', slotOf(...)) end
local function useBox(...) TriggerServerEvent('meta_comic:server:useItem', 'box', slotOf(...)) end
local function useCard(...) TriggerServerEvent('meta_comic:server:useItem', 'card', slotOf(...)) end

exports('useBoosterPack', usePack)
exports('useBoosterBox', useBox)
exports('useTradingCard', useCard)
exports('ShowCard', useCard)

-- ox_inventory item button "View Binder" on your binder item: opens the binder UI with its cards in slot order.
exports('ViewBinder', function(...)
    TriggerServerEvent('meta_comic:server:viewBinder', slotOf(...))
end)

RegisterNetEvent('meta_comic:client:viewBinder', function(binder)
    if type(binder) ~= 'table' then return end
    nuiOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'metaComic:open', view = 'pack', overlay = true, mode = 'binder', binder = binder })
end)

-- ox_inventory item button "Show Card": show this card to the players standing near you.
exports('ShowOthersCard', function(...)
    TriggerServerEvent('meta_comic:server:showCardToOthers', slotOf(...))
end)

-- Show a card large in the centre of the screen (own card item, or one another player is showing you).
local shownToken = 0
RegisterNetEvent('meta_comic:client:viewCard', function(card, shownBy)
    if type(card) ~= 'table' then return end
    if shownBy and nuiOpen then return end -- don't interrupt a pack opening / another card with someone else's card
    nuiOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'metaComic:open', view = 'pack', overlay = true, mode = 'card', card = card, shownBy = shownBy })
    shownToken = shownToken + 1
    if shownBy then
        -- someone else's card: close it by itself after a few seconds (the player can also close it straight away)
        local token = shownToken
        SetTimeout(math.floor(((Config.ShowCard and Config.ShowCard.Seconds) or 8) * 1000), function()
            if token == shownToken and nuiOpen then closeNui() end
        end)
    end
end)

RegisterNetEvent('meta_comic:client:notify', function(message, notifyType)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(('[%s] %s'):format(notifyType or 'info', message or ''))
    EndTextCommandThefeedPostTicker(false, false)
end)

if Config.Commands.Open and Config.Commands.Open ~= '' then
    RegisterCommand(Config.Commands.Open, function() openNui(Config.Nui.DefaultView) end, false)
end
if Config.Commands.Pack and Config.Commands.Pack ~= '' then
    RegisterCommand(Config.Commands.Pack, function() openPackOverlay() end, false)
end
if Config.Commands.Box and Config.Commands.Box ~= '' then
    RegisterCommand(Config.Commands.Box, function() openNui('pack', 'openBox') end, false)
end
if Config.Commands.Options and Config.Commands.Options ~= '' then
    RegisterCommand(Config.Commands.Options, function() openPackOptions() end, false)
end
-- Keep /cardadmin available for installations that intentionally preserve an
-- older config.lua. An explicit empty Management command still disables it.
local managementCommand = Config.Commands and Config.Commands.Management
if managementCommand == nil then managementCommand = 'cardadmin' end
if managementCommand ~= '' then
    RegisterCommand(managementCommand, function() openManagement() end, false)
end

-- Canonical collectables commands also work with preserved older configs.
-- Existing configured names remain aliases; empty values still disable a route.
local aliases={
    {key='Open',name='collectables',legacy='cards',action=function() openNui(Config.Nui.DefaultView) end},
    {key='Pack',name='collectablespack',legacy='cardpack',action=openPackOverlay},
    {key='Box',name='collectablesbox',legacy='cardbox',action=function() openNui('pack','openBox') end},
    {key='Options',name='collectablesoptions',legacy='cardoptions',action=openPackOptions},
    {key='Management',name='collectablesadmin',legacy='cardadmin',action=openManagement},
}
for _,entry in ipairs(aliases) do
    local configured=Config.Commands[entry.key]
    if configured~='' then
        if configured~=entry.name then RegisterCommand(entry.name,entry.action,false) end
        if configured~=entry.legacy then RegisterCommand(entry.legacy,entry.action,false) end
    end
end

exports('OpenCards', function(view) openNui(view or Config.Nui.DefaultView) end)
-- OpenPack / OpenBox: called by ox_inventory for an item -> use that item (server takes it).
-- Called by another script with no item -> the free test opening, same as /cardpack and /cardbox.
exports('OpenPack', function(...)
    if oxItem(...) or slotOf(...) then return usePack(...) end
    openPackOverlay()
end)
exports('OpenBox', function(...)
    if oxItem(...) or slotOf(...) then return useBox(...) end
    openNui('pack', 'openBox')
end)
exports('CloseCards', closeNui)
exports('UseCollectible',function(...) local slot=slotOf(...);if slot then TriggerServerEvent('meta_comic:server:useCollectible',slot) end end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    stopPackProp()
    if nuiOpen then closeNui() end
end)

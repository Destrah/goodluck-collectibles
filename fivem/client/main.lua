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

local function openManagement(tab)
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
        tab = type(tab) == 'string' and tab or nil,
        runtimeInfo = runtimeInfo,
    })
end

local stopPackProp -- defined below
local stopHeld -- defined below

local function closeNui()
    if stopPackProp then stopPackProp() end
    if stopHeld then stopHeld() end
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
-- The same goes for coin bags, plushie boxes and their cases while they open: Config.Props.Containers.bag / box /
-- case override these defaults (first model the game has is used).
local PACK_DICT, PACK_ANIM = 'mp_arresting', 'a_uncuff'
local DEFAULT_CONTAINER_PROPS = {
    bag = { model = { 'prop_paper_bag_small' }, bone = 0xDEAD, offset = vector3(0.10, 0.02, -0.02), rotation = vector3(0.0, 0.0, 0.0) },
    box = { model = { 'prop_boosterbox_01' }, bone = 0xDEAD, offset = vector3(0.10, 0.10, 0.00), rotation = vector3(70.0, 10.0, 90.0) },
    case = { model = { 'prop_boosterbox_01' }, bone = 0xDEAD, offset = vector3(0.10, 0.10, 0.00), rotation = vector3(70.0, 10.0, 90.0) },
}
local packPropEntity = nil
local packPropActive = false
local packPropGen = 0 -- each start gets a new generation, so a stale thread can never leave a prop behind

stopPackProp = function()
    packPropActive = false
    if packPropEntity and DoesEntityExist(packPropEntity) then DeleteEntity(packPropEntity) end
    packPropEntity = nil
    StopAnimTask(PlayerPedId(), PACK_DICT, PACK_ANIM, 1.0)
end

local function containerPropData(kind)
    local base = DEFAULT_CONTAINER_PROPS[kind]
    if not base then return Config.Props.Pack or {} end
    local merged = {}
    for key, value in pairs(base) do merged[key] = value end
    local custom = type(Config.Props.Containers) == 'table' and Config.Props.Containers[kind]
    if type(custom) == 'table' then for key, value in pairs(custom) do merged[key] = value end end
    merged.MaxDuration = merged.MaxDuration or (Config.Props.Pack and Config.Props.Pack.MaxDuration) or 30000
    return merged
end

-- kind: nil = booster pack, 'bag' / 'box' / 'case' = a coin bag, plushie box or outer case being opened
local function startPackProp(kind)
    if packPropActive or not Config.Props.Enabled then return end
    packPropActive = true
    packPropGen = packPropGen + 1
    local gen = packPropGen
    CreateThread(function()
        local data = kind and containerPropData(kind) or Config.Props.Pack or {}
        local ped = PlayerPedId()
        RequestAnimDict(PACK_DICT)
        local timeout = GetGameTimer() + 3000
        while not HasAnimDictLoaded(PACK_DICT) and GetGameTimer() < timeout do Wait(0) end

        local model
        for _, name in ipairs(type(data.model) == 'table' and data.model or { data.model }) do
            model = loadModel(name)
            if model then break end
        end
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
    if data and data.state == 'start' then
        stopHeld()
        startPackProp(DEFAULT_CONTAINER_PROPS[data.kind] and data.kind or nil)
    else
        stopPackProp()
    end
end)

-- ---------- held collectibles ----------
-- While a card / coin / plushie is looked at (item used, or just pulled from a pack / bag / box) the character
-- holds that many of it and looks down at it ('view'); while showing it to others they hold it out ('show').
-- Generic base-game props: override any of these in Config.Props.Held (config.lua), or set Config.Props.Held = false
-- to turn it off. Placements use rotation order 1, like the common emote menus they come from.
local LOOK_DOWN = { dict = 'amb@world_human_tourist_map@male@base', anim = 'base' } -- both hands in front, head down
local DEFAULT_HELD = {
    card = { models = { 'prop_franklin_dl' }, max = 5, rotationOrder = 1,
        view = { dict = LOOK_DOWN.dict, anim = LOOK_DOWN.anim, bone = 28422, offset = vector3(0.0, -0.03, 0.0), rotation = vector3(20.0, -90.0, 0.0) },
        show = { dict = 'paper_1_rcm_alt1-9', anim = 'player_one_dual-9', bone = 57005, offset = vector3(0.10, 0.02, -0.03), rotation = vector3(-90.0, 170.0, 78.0) },
        step = vector3(0.0, 0.0, 0.004), stepRotation = vector3(0.0, 9.0, 0.0) }, -- each extra card fanned out a little
    coin = { models = { 'vw_prop_vw_coin_01a', 'vw_prop_chip_100dollar_x1' }, max = 5, rotationOrder = 1,
        view = { dict = LOOK_DOWN.dict, anim = LOOK_DOWN.anim, bone = 28422, offset = vector3(0.0, -0.03, 0.0), rotation = vector3(20.0, -90.0, 0.0) },
        show = { dict = 'paper_1_rcm_alt1-9', anim = 'player_one_dual-9', bone = 57005, offset = vector3(0.10, 0.02, -0.03), rotation = vector3(-90.0, 170.0, 78.0) },
        step = vector3(0.0, 0.0, 0.006), stepRotation = vector3(0.0, 0.0, 0.0) }, -- coins stacked in the palm
    plush = { models = { 'v_ilev_mr_rasberryclean' }, max = 2, rotationOrder = 1,
        -- the bear sits against the chest (bone 24817), so it stays put whichever arm animation plays
        view = { dict = LOOK_DOWN.dict, anim = LOOK_DOWN.anim, bone = 24817, offset = vector3(-0.20, 0.46, -0.016), rotation = vector3(-180.0, -90.0, 0.0) },
        show = { dict = 'impexp_int-0', anim = 'mp_m_waremech_01_dual-0', bone = 24817, offset = vector3(-0.20, 0.46, -0.016), rotation = vector3(-180.0, -90.0, 0.0) },
        step = vector3(0.0, 0.0, 0.16), stepRotation = vector3(0.0, 0.0, 0.0) },
}
local KIND_OF_TYPE = { challenge_coin = 'coin', plushie = 'plush', coin = 'coin', plush = 'plush', card = 'card' }
local function heldKind(typeId) return KIND_OF_TYPE[typeId] or 'card' end
local held = { entities = {}, active = false, gen = 0 }

-- mode 'view' / 'show': the kind's shared settings with that pose's animation and placement laid over them
local function heldConfig(kind, mode)
    local custom = Config.Props and Config.Props.Held
    if custom == false or not DEFAULT_HELD[kind] then return nil end
    custom = type(custom) == 'table' and type(custom[kind]) == 'table' and custom[kind] or {}
    local merged = {}
    for _, source in ipairs({ DEFAULT_HELD[kind], DEFAULT_HELD[kind][mode] or {}, custom, type(custom[mode]) == 'table' and custom[mode] or {} }) do
        for key, value in pairs(source) do if key ~= 'view' and key ~= 'show' then merged[key] = value end end
    end
    local all = Config.Props and Config.Props.Held
    if type(all) == 'table' and tonumber(all.MaxDuration) then merged.MaxDuration = tonumber(all.MaxDuration) * 1000 end -- seconds in config
    return merged
end

stopHeld = function()
    held.active = false
    held.gen = held.gen + 1
    for _, entity in ipairs(held.entities) do if DoesEntityExist(entity) then DeleteEntity(entity) end end
    held.entities = {}
    if held.dict then StopAnimTask(PlayerPedId(), held.dict, held.anim, 1.0) end
    held.dict, held.anim = nil, nil
end

-- mode: 'view' (looking at it yourself) or 'show' (holding it out to others)
-- seconds: let go after that long (showing to others); nil: hold until the game UI closes
local function holdCollectibles(kind, count, seconds, mode)
    if not Config.Props or not Config.Props.Enabled then return end
    local data = heldConfig(kind, mode or 'view')
    if not data then return end
    stopHeld()
    count = math.max(1, math.min(math.floor(tonumber(count) or 1), tonumber(data.max) or 5))
    held.active = true
    local gen = held.gen
    CreateThread(function()
        local ped = PlayerPedId()
        local model
        for _, name in ipairs(type(data.models) == 'table' and data.models or { data.models }) do
            model = loadModel(name)
            if model then break end
        end
        local animate = data.dict and data.anim and not IsPedInAnyVehicle(ped, false)
        if animate then
            RequestAnimDict(data.dict)
            local timeout = GetGameTimer() + 3000
            while not HasAnimDictLoaded(data.dict) and GetGameTimer() < timeout do Wait(0) end
            animate = HasAnimDictLoaded(data.dict)
        end
        if gen ~= held.gen then if model then SetModelAsNoLongerNeeded(model) end return end
        if model then
            local coords = GetEntityCoords(ped)
            local bone = GetPedBoneIndex(ped, data.bone or 57005)
            local o, r = data.offset or vector3(0.1, 0.02, -0.03), data.rotation or vector3(0.0, 0.0, 0.0)
            local so, sr = data.step or vector3(0.0, 0.0, 0.0), data.stepRotation or vector3(0.0, 0.0, 0.0)
            for i = 0, count - 1 do
                local n = i - (count - 1) / 2 -- spread around the middle one
                local prop = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
                if DoesEntityExist(prop) then
                    SetEntityCollision(prop, false, false)
                    AttachEntityToEntity(prop, ped, bone, o.x + so.x * n, o.y + so.y * n, o.z + so.z * n,
                        r.x + sr.x * n, r.y + sr.y * n, r.z + sr.z * n, false, false, false, false, data.rotationOrder or 1, true)
                    held.entities[#held.entities + 1] = prop
                end
            end
            SetModelAsNoLongerNeeded(model)
        end
        if animate then held.dict, held.anim = data.dict, data.anim end
        local now = GetGameTimer()
        local deadline = now + math.floor((seconds or ((data.MaxDuration or 300000) / 1000)) * 1000)
        while gen == held.gen and GetGameTimer() < deadline do
            if animate and not IsEntityPlayingAnim(ped, data.dict, data.anim, 3) then
                TaskPlayAnim(ped, data.dict, data.anim, 8.0, -8.0, -1, 49, 0.0, false, false, false)
            end
            Wait(250)
        end
        if gen == held.gen then stopHeld() end
    end)
end

-- the NUI: a pack / bag / box has been opened and its pulls are on screen
RegisterNUICallback('holdCollectibles', function(data, cb)
    cb({ ok = true })
    if type(data) == 'table' and nuiOpen then holdCollectibles(heldKind(data.kind or data.typeId), data.count) end
end)

-- the server: you are showing an item to the players near you
RegisterNetEvent('meta_comic:client:showingCollectible', function(kind, seconds)
    if nuiOpen then return end
    holdCollectibles(heldKind(kind), 1, tonumber(seconds) or 8, 'show')
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
RegisterNUICallback('getShippingCrates', function(_, cb)
    cb(serverRpc('getShippingCrates', {}))
end)
RegisterNUICallback('createShippingCrate', function(data, cb)
    cb(serverRpc('createShippingCrate', data or {}, 20000))
end)

RegisterNUICallback('getCollection', function(_, cb)
    cb(serverRpc('getCollection', {}))
end)

RegisterNetEvent('meta_comic:client:openCardBuyer',function(index)
    local data=serverRpc('getCardBuyerUI',{index=index},120000)
    if not data or data.ok==false then TriggerEvent('meta_comic:client:notify',data and data.error or 'Could not open the buyer.','error');return end
    openNui('pack',nil,true,'cardBuyer')
    SendNUIMessage({type='metaComic:open',view='pack',overlay=true,mode='cardBuyer',buyer=data})
end)
RegisterNUICallback('getCardBuyerUI',function(data,cb) cb(serverRpc('getCardBuyerUI',data or {},120000)) end)
RegisterNUICallback('getCardMarketOptions',function(data,cb) cb(serverRpc('getCardMarketOptions',data or {},120000)) end)
RegisterNUICallback('getCardMarketAnalysis',function(data,cb) cb(serverRpc('getCardMarketAnalysis',data or {},120000)) end)
RegisterNUICallback('sellCardBuyerCart',function(data,cb)
    local checked=serverRpc('checkCardBuyerCart',data or {},120000)
    if not checked or checked.ok==false then cb(checked or {ok=false,error='Could not check the sale.'});return end
    if checked.sellArea and MetaComic.CardBuyerDeal then
        SetNuiFocus(false,false)
        local done=MetaComic.CardBuyerDeal(checked.sellArea,checked.count)
        SetNuiFocus(true,true)
        if not done then cb({ok=false,error='Handover interrupted. No cards were sold.'});return end
    end
    cb(serverRpc('sellCardBuyerCart',data or {},120000))
end)

for _,action in ipairs({'getCollectibles','saveCollectible','openCollectibleContainer','createCollectibleContainer','claimCollectibles','printCollectible',
    'gradingMark','gradingSubmit','gradingCancel','roughHandling','gradingRecord','getPrintOdds','binderStoreCard','binderTakeCard',
    'getVendingMachines','getCrafting','saveCrafting','getVendingRecords','getVendingRecordPage','saveVendingRecords'}) do
    RegisterNUICallback(action,function(data,cb) cb(serverRpc(action,data or {},120000)) end)
end

-- ---------- card grading and protection (ox_inventory item buttons on the trading card) ----------
local function gradeCard(slot)
    if not slot then return end
    CreateThread(function()
        local response = serverRpc('startGrading', { slot = slot }, 60000)
        if not response or response.ok == false then
            return TriggerEvent('meta_comic:client:notify', (response and response.error) or 'Could not start grading.', 'error')
        end
        nuiOpen = true
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        SendNUIMessage({ type = 'metaComic:open', view = 'pack', overlay = true, mode = 'grading', grading = response })
    end)
end
local function protectCard(slot, kind)
    if not slot then return end
    CreateThread(function()
        local response = serverRpc('protectCard', { slot = slot, kind = kind }, 20000)
        local done = { sleeve = 'Card put in a sleeve.', toploader = 'Card put in a toploader.', none = 'Card taken out.' }
        TriggerEvent('meta_comic:client:notify', (response and response.ok) and done[kind] or ((response and response.error) or 'Could not do that.'), (response and response.ok) and 'success' or 'error')
    end)
end

RegisterNetEvent('meta_comic:client:openCollectible',function(typeId,slot,outer,container)
    openNui('pack')
    SendNUIMessage({type='metaComic:collectibleContainer',typeId=typeId,slot=slot,outer=outer==true,container=container})
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

-- Legacy artwork command (collectiblesoptimizeart): the server asks this player's NUI to downscale one saved
-- image; the result goes back to the server, which uploads it to Fivemanage.
RegisterNetEvent('meta_comic:client:optimizeArtwork', function(id, src, options)
    if type(id) ~= 'string' or type(src) ~= 'string' then return end
    SendNUIMessage({ type = 'metaComic:optimizeArtwork', id = id, src = src, options = options })
end)

RegisterNUICallback('optimizedArtwork', function(data, cb)
    cb({ ok = true })
    if type(data) == 'table' and type(data.id) == 'string' then
        TriggerLatentServerEvent('meta_comic:server:optimizedArtwork', 250000, data.id, type(data.data) == 'string' and data.data or '')
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
-- booster box item: the 3D box opening plays centre screen; the server swaps the box for its packs when it ends
RegisterNetEvent('meta_comic:client:boxOpened', function(packs, setId, setName)
    CreateThread(function() playPropSequence('box') end)
    nuiOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'metaComic:open', view = 'pack', overlay = true, mode = 'boxOpening', box = { packs = packs, set = setId, setName = setName } })
end)
RegisterNUICallback('claimBox', function(_, cb) TriggerServerEvent('meta_comic:server:boxClaim'); cb({ ok = true }) end)

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

-- ox_inventory item button "View Case" on a card case (Config.Items.CardCase): same server path as the binder,
-- the NUI shows the case layout because the payload says kind = 'case'.
exports('ViewCardCase', function(...)
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

-- ox_inventory item buttons on the trading card: grade it (needs an empty grading slab), sleeve / toploader it
exports('GradeCard', function(...) gradeCard(slotOf(...)) end)

-- /gradecheck [cert]: look up a slab's grading record (grade, grader and the flaws they marked). Anyone can use it.
local function openGradeRecord(cert)
    CreateThread(function()
        local response = cert and cert ~= '' and serverRpc('gradingRecord', { cert = cert }, 20000) or nil
        nuiOpen = true
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        SendNUIMessage({ type = 'metaComic:open', view = 'pack', overlay = true, mode = 'gradeRecord', cert = cert or '',
            found = response and response.ok and response.record and { record = response.record, card = response.card } or nil })
    end)
end
exports('OpenGradeRecord', function(cert) openGradeRecord(cert and tostring(cert) or '') end)
local lookupCommand = Config.Grading and Config.Grading.LookupCommand
if lookupCommand == nil then lookupCommand = 'gradecheck' end
if lookupCommand ~= '' then
    RegisterCommand(lookupCommand, function(_, args) openGradeRecord(args[1] and tostring(args[1]):gsub('%D', '') or '') end, false)
end
exports('SleeveCard', function(...) protectCard(slotOf(...), 'sleeve') end)
exports('ToploaderCard', function(...) protectCard(slotOf(...), 'toploader') end)
exports('UnprotectCard', function(...) protectCard(slotOf(...), 'none') end)

-- ox_inventory item button "Show" on a challenge coin / plushie: same as Show Card.
exports('ShowOthersCollectible', function(...)
    TriggerServerEvent('meta_comic:server:showCollectibleToOthers', slotOf(...))
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
    if not shownBy then holdCollectibles(heldKind(card.collectibleType or card.collectableType), 1) end -- your own item: hold it while looking at it (older items use the misspelled key)
    shownToken = shownToken + 1
    if shownBy then
        -- someone else's card: close it by itself after a few seconds (the player can also close it straight away)
        local token = shownToken
        SetTimeout(math.floor(((Config.ShowCard and Config.ShowCard.Seconds) or 8) * 1000), function()
            if token == shownToken and nuiOpen then closeNui() end
        end)
    end
end)

local OX_NOTIFY_TYPES = { success = 'success', error = 'error', warning = 'warning', inform = 'inform', info = 'inform', primary = 'inform' }
RegisterNetEvent('meta_comic:client:notify', function(message, notifyType)
    if GetResourceState('ox_lib') == 'started' then
        return exports.ox_lib:notify({ description = message or '', type = OX_NOTIFY_TYPES[notifyType] or 'inform' })
    end
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

-- Canonical collectibles commands also work with preserved older configs.
-- Existing configured names remain aliases; empty values still disable a route.
local aliases={
    {key='Open',name='collectibles',legacy='cards',action=function() openNui(Config.Nui.DefaultView) end},
    {key='Pack',name='collectiblespack',legacy='cardpack',action=openPackOverlay},
    {key='Box',name='collectiblesbox',legacy='cardbox',action=function() openNui('pack','openBox') end},
    {key='Options',name='collectiblesoptions',legacy='cardoptions',action=openPackOptions},
    {key='Management',name='collectiblesadmin',legacy='cardadmin',action=function() openManagement() end},
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

-- For other scripts ------------------------------------------------------------------------------------------------
-- exports['<resource>']:OpenAdmin(tab)   full admin UI (the server checks management permission first).
--   tab: 'editor' | 'management' (Sets & containers) | 'vending' | 'crafting' ... or nil for the default
exports('OpenAdmin', function(tab) CreateThread(function() openManagement(tab) end) end)
RegisterNetEvent('meta_comic:client:openAdmin', function(tab) openManagement(tab) end) -- server export OpenAdmin(source, tab)
exports('OpenPackOptions', openPackOptions)
exports('IsOpen', function() return nuiOpen end)
-- exports['<resource>']:GetEmbedUrl('admin', 'vending') -> an address for an <iframe> in your own NUI page.
-- The embedded page talks to this resource directly, so permission checks still apply. It posts
-- { type = 'metaComic:embedClose' } to the parent window when the user closes it, and 'metaComic:embedReady' once open.
-- tab: one tab ('vending') or several ({ 'vending', 'records' } or 'vending,records'): only those tabs are shown, and only
-- the ones the player may open (Config.Portal: owners see their own machines, Editor people get the editor).
local function embedQuery(view, tab)
    local resource = GetCurrentResourceName()
    local query = ('embed=1&resource=%s&view=%s'):format(resource, tostring(view or 'admin'))
    local tabs = type(tab) == 'table' and table.concat(tab, ',') or tostring(tab or '')
    if tabs ~= '' then query = query .. '&tab=' .. (tabs:match('^[^,]+') or tabs) .. '&tabs=' .. tabs end
    return query
end
exports('GetEmbedUrl', function(view, tab)
    return ('nui://%s/web/index.html?%s'):format(GetCurrentResourceName(), embedQuery(view, tab))
end)
-- /cardportal [tabs]: opens the embedded view (as another resource would show it) to test it
local portalConfig = Config.Portal or {}
if portalConfig.Enabled ~= false and (portalConfig.Command or 'cardportal') ~= '' then
    RegisterCommand(portalConfig.Command or 'cardportal', function(_, args)
        CreateThread(function()
            local info = serverRpc('getRuntimeInfo', {}, 12000)
            local allowed = info and info.capabilities and info.capabilities.portal and info.capabilities.portal.tabs or {}
            local requested = args[1] and args[1] ~= '' and args[1] or table.concat(allowed, ',')
            local wanted = {}
            for tab in tostring(requested):gmatch('[^,%s]+') do
                for _, ok in ipairs(allowed) do if ok == tab then wanted[#wanted + 1] = tab end end
            end
            if #wanted == 0 then
                return TriggerEvent('meta_comic:client:notify', #allowed > 0 and ('You can open: %s'):format(table.concat(allowed, ', '))
                    or 'You have no portal access (managers, vending machine owners and card editors only).', 'error')
            end
            nuiOpen = true
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
            SendNUIMessage({ type = 'metaComic:embedTest', query = embedQuery('admin', wanted) })
        end)
    end, false)
end
exports('UseCollectible',function(...) local slot=slotOf(...);if slot then TriggerServerEvent('meta_comic:server:useCollectible',slot) end end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    stopPackProp()
    stopHeld()
    if nuiOpen then closeNui() end
end)

RegisterNUICallback('saveCardSetPayout',function(data,cb) cb(serverRpc('saveCardSetPayout',data or {},20000)) end)

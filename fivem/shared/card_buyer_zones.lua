-- The same adapter contract runs on server and client. Server containment is authoritative.
local adapters,selected={},nil
MetaComic.CardBuyerZones={}
local service=MetaComic.CardBuyerZones
local function builtin(position,box)
    local c,size=box and box.coords,box and box.size
    if not c or not size then return false end
    local angle=math.rad(tonumber(box.heading) or 0)
    local dx,dy=position.x-c.x,position.y-c.y
    local x,y=dx*math.cos(angle)+dy*math.sin(angle),-dx*math.sin(angle)+dy*math.cos(angle)
    return math.abs(x)<=size.x/2 and math.abs(y)<=size.y/2 and math.abs(position.z-c.z)<=size.z/2
end
function service.contains(position,box)
    local selector=selected or (Config.CardBuyers or {}).ZoneAdapter or 'builtin'
    if selector=='builtin' then return builtin(position,box) end
    local callback=type(selector)=='string' and adapters[selector]
    if type(selector)=='table' and selector.Resource and selector.Contains then
        if GetResourceState(selector.Resource)~='started' then return false end
        callback=function(p,b) return exports[selector.Resource][selector.Contains](p,b) end
    end
    if not callback then return false end -- an unavailable custom adapter must never authorize a sale
    local ok,result=pcall(callback,position,box)
    return ok and result==true
end
exports('RegisterCardBuyerZoneAdapter',function(name,adapter)
    local callback=type(adapter)=='table' and adapter.contains or adapter
    if type(name)~='string' or name=='builtin' or type(callback)~='function' then return false end
    adapters[name]=callback;return true
end)
exports('UseCardBuyerZoneAdapter',function(name)
    if name~='builtin' and not adapters[name] then return false end
    selected=name;return true
end)

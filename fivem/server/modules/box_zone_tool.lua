-- A local preview/export tool. Config is changed only by explicitly pasting its output.
local function start(source,options)
    local check=MetaComic.CanManageReal or MetaComic.CanManage
    if source<=0 or not check or check(source)~=true then
        if MetaComic.Framework.notify then MetaComic.Framework.notify(source,'Only collectibles admins can create box zones.','error') end
        return false
    end
    TriggerClientEvent('meta_comic:client:boxZoneTool',source,options or {})
    return true
end
RegisterCommand(((Config.CardBuyers or {}).ZoneTool or {}).Command or 'cardzone',function(source,args)
    start(source,{name=args[1] or 'cardshop_sale'})
end,false)
exports('StartBoxZoneTool',function(source,options) return start(tonumber(source) or 0,options) end)

MetaComic.PersistenceAdapters.json = function()
    local resource = GetCurrentResourceName()
    local fileName = Config.JsonPersistence.File
    local collections = {}

    local function load()
        local raw = LoadResourceFile(resource, fileName)
        if not raw or raw == '' then collections = {}; return end
        local ok, decoded = pcall(json.decode, raw)
        collections = ok and type(decoded) == 'table' and decoded or {}
    end

    local function save()
        SaveResourceFile(resource, fileName, json.encode(collections), -1)
    end

    return {
        name = 'json',
        init = function()
            load()
            return true
        end,
        addCards = function(owner, cards)
            collections[owner] = collections[owner] or {}
            for _, card in ipairs(cards or {}) do
                collections[owner][#collections[owner] + 1] = card
            end
            save()
            return true
        end,
        getCollection = function(owner)
            return MetaComic.CopyTable(collections[owner] or {})
        end,
    }
end

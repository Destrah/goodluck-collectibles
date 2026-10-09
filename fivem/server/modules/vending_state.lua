-- Normalized persistence for the two unbounded vending settings. Runtime objects stay in memory.
if MetaComic.Persistence.name ~= 'mysql' then return end
local service, cached, loaded, loading, initializing = {}, {}, {}, {}, {}
MetaComic.VendingState = service
local resource = GetCurrentResourceName()
local STATE, ENTRIES = 'goodluck_collectibles_vending_state', 'goodluck_collectibles_vending_entries'
local schema = false
local function db() return exports[Config.Database.Resource or 'oxmysql'] end
local function query(sql, params) local rows=db():query_async(sql,params or {}); assert(rows~=nil,'Vending state query failed'); return rows end
local function canonical(value)
    if type(value)~='table' then return json.encode(value) end
    local keys={};for key in pairs(value) do keys[#keys+1]=key end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    local parts={}
    for _,key in ipairs(keys) do parts[#parts+1]=json.encode(tostring(key))..':'..canonical(value[key]) end
    return '{'..table.concat(parts,',')..'}'
end
local function identity(section,id,path,position) return canonical({section,id,path,position}) end
local function copyValue(value)
    if type(value)=='table' then return MetaComic.CopyTable(value) end
    return value
end
local function extract(value,path,section,id,entries)
    if type(value)~='table' then return value end
    local fields={}
    for key,child in pairs(value) do
        local location=path=='' and tostring(key) or path..'.'..tostring(key)
        if type(child)=='table' and #child>0 then
            assert(#location<=255,'Vending collection path is too long')
            fields[key]={}
            for position,item in ipairs(child) do
                local stripped=extract(item,location..'.'..position,section,id,entries)
                entries[identity(section,id,location,position)]={section=section,id=id,path=location,position=position,value=stripped}
            end
        else fields[key]=extract(child,location,section,id,entries) end
    end
    return fields
end
local function flatten(key,data)
    local state,entries={},{}
    local function add(section,id,value)
        id=tostring(id); assert(#id<=160,'Vending identity is too long')
        state[identity(section,id)]={section=section,id=id,value=extract(value,'',section,id,entries)}
    end
    if key=='vending_registry' then
        for id,person in pairs(data.people or {}) do add('people',id,person) end
        for serial,record in pairs(data.serials or {}) do add('machines',serial,record) end
        for id,amount in pairs(data.pending or {}) do add('pending',id,amount) end
        add('business','business',data.business or {pending=0})
    elseif key=='vending_key_reports' then
        for id,report in pairs(data.reports or {}) do add('reports',id,report) end
        add('meta','nextId',data.nextId or 0)
    else error('Unknown vending dataset') end
    add('meta','schema',1)
    return {state=state,entries=entries}
end
local function parent(root,path)
    local current=root
    for segment in path:gmatch('[^.]+') do
        local key=tonumber(segment) or segment
        current[key]=type(current[key])=='table' and current[key] or {}
        current=current[key]
    end
    return current
end
local function inflate(key,rows)
    local data=key=='vending_registry' and {people={},serials={},pending={},business={pending=0}} or {reports={},nextId=0}
    local roots={}
    local processed=0
    for id,row in pairs(rows.state) do
        local value=copyValue(row.value);roots[id]=value
        if row.section=='people' then data.people[row.id]=value
        elseif row.section=='machines' then data.serials[row.id]=value
        elseif row.section=='pending' then data.pending[row.id]=value
        elseif row.section=='business' then data.business=value
        elseif row.section=='reports' then data.reports[row.id]=value
        elseif row.section=='meta' and row.id=='nextId' then data.nextId=value end
        processed=processed+1;if processed%100==0 then Wait(0) end
    end
    local entries={};for _,row in pairs(rows.entries) do
        local _,depth=row.path:gsub('%.','')
        entries[#entries+1]={row=row,depth=depth}
        processed=processed+1;if processed%100==0 then Wait(0) end
    end
    table.sort(entries,function(a,b)
        if a.depth~=b.depth then return a.depth<b.depth end
        if a.row.path~=b.row.path then return a.row.path<b.row.path end
        return a.row.position<b.row.position
    end)
    for index,entry in ipairs(entries) do
        local row=entry.row
        local root=roots[identity(row.section,row.id)]
        if type(root)=='table' then parent(root,row.path)[row.position]=copyValue(row.value) end
        if index%100==0 then Wait(0) end
    end
    return data
end
local function prepare()
    if schema then return end
    if Config.Database.AutoCreateSchema then
        query(('CREATE TABLE IF NOT EXISTS `%s` (dataset VARCHAR(32) NOT NULL, section VARCHAR(32) NOT NULL, record_id VARCHAR(160) NOT NULL, data_json LONGTEXT NOT NULL, PRIMARY KEY(dataset,section,record_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin'):format(STATE))
        query(('CREATE TABLE IF NOT EXISTS `%s` (dataset VARCHAR(32) NOT NULL, section VARCHAR(32) NOT NULL, record_id VARCHAR(160) NOT NULL, `collection` VARCHAR(255) NOT NULL, `position` INT UNSIGNED NOT NULL, data_json LONGTEXT NOT NULL, PRIMARY KEY(dataset,section,record_id,`collection`,`position`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin'):format(ENTRIES))
    end
    schema=true
end
local function read(key)
    if cached[key] then return end
    if loading[key] then while loading[key] do Wait(0) end; assert(cached[key],'Vending state load failed');return end
    loading[key]=true
    local ok,err=pcall(function()
        prepare()
        local rows={state={},entries={}}
        for index,row in ipairs(query(('SELECT section,record_id,data_json FROM `%s` WHERE dataset=?'):format(STATE),{key})) do
            rows.state[identity(row.section,row.record_id)]={section=row.section,id=row.record_id,value=json.decode(row.data_json)}
            if index%100==0 then Wait(0) end
        end
        for index,row in ipairs(query(('SELECT section,record_id,`collection`,`position`,data_json FROM `%s` WHERE dataset=?'):format(ENTRIES),{key})) do
            local position=tonumber(row.position)
            rows.entries[identity(row.section,row.record_id,row.collection,position)]={section=row.section,id=row.record_id,path=row.collection,position=position,value=json.decode(row.data_json)}
            if index%100==0 then Wait(0) end
        end
        cached[key]=rows
    end)
    loading[key]=nil
    if not ok then error(err) end
end
local function persist(key,data)
    read(key)
    local desired=flatten(key,data);local old=cached[key];local statements={}
    local function statement(sql,values) statements[#statements+1]={query=sql,values=values} end
    -- Bulk upsert only changed rows, at most 100 rows per statement.
    for _,bucket in ipairs({'state','entries'}) do
        local groups,params={},{}
        local function flush()
            if #groups==0 then return end
            local columns=bucket=='state' and 'dataset,section,record_id,data_json' or 'dataset,section,record_id,`collection`,`position`,data_json'
            statement(('INSERT INTO `%s` (%s) VALUES %s ON DUPLICATE KEY UPDATE data_json=VALUES(data_json)'):format(bucket=='state' and STATE or ENTRIES,columns,table.concat(groups,',')),params)
            groups,params={},{}
        end
        for id,row in pairs(desired[bucket]) do
            if not old[bucket][id] or canonical(old[bucket][id].value)~=canonical(row.value) then
                groups[#groups+1]=bucket=='state' and '(?,?,?,?)' or '(?,?,?,?,?,?)'
                for _,value in ipairs({key,row.section,row.id}) do params[#params+1]=value end
                if bucket=='entries' then params[#params+1]=row.path;params[#params+1]=row.position end
                params[#params+1]=json.encode(row.value)
                if #groups>=100 then flush() end
            end
        end
        flush()
        local removed,values={},{}
        local function deleteRows()
            if #removed==0 then return end
            statement(('DELETE FROM `%s` WHERE %s'):format(bucket=='state' and STATE or ENTRIES,table.concat(removed,' OR ')),values)
            removed,values={},{}
        end
        for id,row in pairs(old[bucket]) do
            if not desired[bucket][id] then
                removed[#removed+1]=bucket=='state' and '(dataset=? AND section=? AND record_id=?)' or '(dataset=? AND section=? AND record_id=? AND `collection`=? AND `position`=?)'
                for _,value in ipairs({key,row.section,row.id}) do values[#values+1]=value end
                if bucket=='entries' then values[#values+1]=row.path;values[#values+1]=row.position end
                if #removed>=100 then deleteRows() end
            end
        end
        deleteRows()
    end
    if #statements>0 then assert(db():transaction_async(statements)==true,'Vending state transaction failed') end
    cached[key]=desired
    return true
end
local function loadData(key,legacy)
    if loaded[key] then return loaded[key] end
    read(key)
    local queue=MetaComic.RuntimeSaves
    local previous=queue.pending('settings')[key]
    local initialized=cached[key].state[identity('meta','schema')]~=nil
    if type(legacy)=='table' or previous then
        local backup=previous and previous.value or legacy
        assert(SaveResourceFile(resource,'data/'..key..'-legacy-backup.json',json.encode(backup),-1),'Could not back up legacy vending state')
    end
    if not initialized or previous then
        local imported=previous and previous.value or type(legacy)=='table' and legacy or {}
        local saved,err=queue.immediate('settings',key,function() return persist(key,imported) end)
        assert(saved,err or 'Could not migrate legacy vending state')
    end
    local pending=queue.pending('vending_state')[key]
    loaded[key]=pending or inflate(key,cached[key])
    -- The legacy blob is removed only after the normalized transaction and local backup succeeded.
    if type(legacy)=='table' or previous then
        local ok,err=pcall(query,'DELETE FROM `goodluck_collectibles_settings` WHERE setting_key=?',{key})
        if not ok then print('[meta-comic] legacy vending settings retained: '..tostring(err)) end
    end
    if MetaComic.Settings.forget then MetaComic.Settings.forget(key) end
    return loaded[key]
end
function service.load(key,legacy)
    if initializing[key] then while initializing[key] do Wait(0) end;assert(loaded[key],'Vending migration failed');return loaded[key] end
    initializing[key]=true
    local ok,result=pcall(loadData,key,legacy)
    initializing[key]=nil
    if not ok then error(result) end
    return result
end
function service.stage(key,data)
    loaded[key]=data
    return MetaComic.RuntimeSaves.mark('vending_state',key,data)
end
function service.saveNow(key,data)
    local ok,err=MetaComic.RuntimeSaves.immediate('vending_state',key,function() return persist(key,data) end)
    if ok then loaded[key]=data end
    return ok,err
end
MetaComic.RuntimeSaves.register('vending_state',persist)

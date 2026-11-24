-- Resolves NPC names from the client's creature cache.
-- An uncached NPC returns nothing on the first query; the query itself asks the server,
-- and the name is available a moment later (confirmed in-game on Forever 1.60.1).
local _, ns = ...

local NpcNames = {}
ns.NpcNames = NpcNames

-- seconds to wait before attempts 2 and 3; after the third failure the NPC keeps its fallback label
local RETRY_DELAYS = { 0.5, 1 }
local MAX_ATTEMPTS = #RETRY_DELAYS + 1

local names -- LocateVendorDB cache for the current locale, set by Init
local pending = {} -- [npcId] = true while attempts are scheduled
local failed = {} -- [npcId] = true after MAX_ATTEMPTS misses, for this session
local listeners = {}

local function creatureLink(npcId)
    return string.format("unit:Creature-0-0-0-0-%d-0000000000", npcId)
end

local function queryName(npcId)
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, creatureLink(npcId))
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local line = data.lines[1]
    local text = line and line.leftText
    if type(text) ~= "string" or text == "" or text == UNKNOWNOBJECT then return nil end
    return text
end

local function notify(npcId, name)
    for _, listener in ipairs(listeners) do
        xpcall(listener, geterrorhandler(), npcId, name)
    end
end

local function retry(npcId, attempt)
    local name = queryName(npcId)
    if name then
        pending[npcId] = nil
        names[npcId] = name
        notify(npcId, name)
    elseif attempt >= MAX_ATTEMPTS then
        pending[npcId] = nil
        failed[npcId] = true
    else
        C_Timer.After(RETRY_DELAYS[attempt], function() retry(npcId, attempt + 1) end)
    end
end

-- Binds the name cache inside the saved variables table; it is dropped whenever the client build changes.
function NpcNames.Init(db)
    local build = select(2, GetBuildInfo())
    local cache = db.npcNames
    if type(cache) ~= "table" or cache.build ~= build or type(cache.locales) ~= "table" then
        cache = { build = build, locales = {} }
        db.npcNames = cache
    end
    local locale = GetLocale()
    if type(cache.locales[locale]) ~= "table" then cache.locales[locale] = {} end
    names = cache.locales[locale]
end

-- Returns the name when it is already known. Otherwise starts at most one request per NPC
-- and returns nil; listeners hear about a name that arrives later. A name found during this
-- call is returned without notifying, so callers rendering a tooltip are never re-entered.
function NpcNames.Resolve(npcId)
    if not names then return nil end
    local name = names[npcId]
    if name then return name end
    if pending[npcId] or failed[npcId] then return nil end
    name = queryName(npcId)
    if name then
        names[npcId] = name
        return name
    end
    pending[npcId] = true
    C_Timer.After(RETRY_DELAYS[1], function() retry(npcId, 2) end)
    return nil
end

function NpcNames.IsPending(npcId)
    return pending[npcId] == true
end

-- listener(npcId, name) runs once for every name that arrives asynchronously
function NpcNames.Subscribe(listener)
    tinsert(listeners, listener)
end

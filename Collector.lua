-- Records vendor positions in-game while collection mode is on (/lv collect).
-- A point is taken when a merchant window opens: the player then stands within interaction range.
-- Checks, in order: the unit is an NPC, it sells recipes, the player is outside instances,
-- the map is a zone, the position is inside the map. Instance vendors are kept without coordinates.
-- Repeated visits are averaged only when UnitPosition confirms both samples lie within
-- MERGE_DISTANCE_YARDS; every other repeated sample goes to conflicts and leaves the point unchanged.
-- Verified points from Data/Vendors.lua are never written; they are only compared against.
local _, ns = ...
local L, Coordinates = ns.L, ns.Coordinates

local Collector = {}
ns.Collector = Collector

local MERGE_DISTANCE_YARDS = 15
local MAX_CONFLICTS = 5
-- map units; a larger gap between a new sample and a verified point gets a warning
local VERIFIED_WARNING_DISTANCE = 0.5
local RECIPE_ITEM_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
local ZONE_MAP_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
local PREFIX = "|cff33ff99LocateVendor|r: "
local WARNING_COLOR = "ffff6060"

local CONFLICT_MAP = "map"
local CONFLICT_FAR = "far"
local CONFLICT_UNVERIFIED = "unverified"
local CONFLICT_INSTANCE = "instance"

local store -- LocateVendorDB.collector
local session -- the merchant window currently open: { guid, npcId, captured, waiting, unresolved }
local merchantEvents = CreateFrame("Frame")
local loginEvents = CreateFrame("Frame")

local function say(format, ...)
    print(PREFIX .. string.format(format, ...))
end

local function warn(format, ...)
    print(PREFIX .. "|c" .. WARNING_COLOR .. string.format(format, ...) .. "|r")
end

local function round2(value)
    return math.floor(value * 100 + 0.5) / 100
end

local function npcFromGuid(guid)
    if type(guid) ~= "string" then return nil end
    local unitType, _, _, _, _, id = strsplit("-", guid)
    if unitType ~= "Creature" then return nil end
    id = tonumber(id)
    if id and id > 0 and id % 1 == 0 then return id end
    return nil
end

local function scanRecipes()
    local recipes, unresolved = {}, 0
    for index = 1, GetMerchantNumItems() or 0 do
        local itemId = GetMerchantItemID(index)
        if not itemId then
            unresolved = unresolved + 1
        elseif select(6, C_Item.GetItemInfoInstant(itemId)) == RECIPE_ITEM_CLASS then
            tinsert(recipes, itemId)
        end
    end
    return recipes, unresolved
end

local function mergeRecipes(record, recipes)
    local known = {}
    for _, itemId in ipairs(record.recipes or {}) do known[itemId] = true end
    for _, itemId in ipairs(recipes) do known[itemId] = true end
    local merged = {}
    for itemId in pairs(known) do tinsert(merged, itemId) end
    table.sort(merged)
    record.recipes = merged
end

-- Returns { uiMapId, x, y } with x and y in 0-100, or nil and a reason.
local function mapPosition()
    local uiMapId = C_Map.GetBestMapForUnit("player")
    if not uiMapId then return nil, L.SKIP_NO_MAP end
    local info = C_Map.GetMapInfo(uiMapId)
    local mapType = info and info.mapType
    if mapType ~= ZONE_MAP_TYPE then return nil, string.format(L.SKIP_MAP_TYPE, tostring(mapType)) end
    local position = C_Map.GetPlayerMapPosition(uiMapId, "player")
    local x, y
    if position then x, y = position:GetXY() end
    if type(x) ~= "number" or type(y) ~= "number" then return nil, L.SKIP_NO_POSITION end
    x, y = round2(x * 100), round2(y * 100)
    if x <= 0 or x >= 100 or y <= 0 or y >= 100 then return nil, L.SKIP_NO_POSITION end
    return { uiMapId = uiMapId, x = x, y = y }
end

-- World position in yards, or nil when UnitPosition is unavailable.
local function worldPosition()
    if type(UnitPosition) ~= "function" then return nil end
    local y, x, _, instanceId = UnitPosition("player")
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return { x = x, y = y, instance = instanceId }
end

local function yardsBetween(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or a.instance ~= b.instance then return nil end
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

local function addConflict(record, conflict)
    record.conflicts = type(record.conflicts) == "table" and record.conflicts or {}
    tinsert(record.conflicts, conflict)
    while #record.conflicts > MAX_CONFLICTS do tremove(record.conflicts, 1) end
end

local function compareWithVerified(npcId, name, position)
    local uiMapId, x, y = Coordinates.GetVerified(npcId)
    if not uiMapId then return end
    if uiMapId ~= position.uiMapId then
        warn(L.VERIFIED_OTHER_MAP, name, npcId, uiMapId, position.uiMapId)
        return
    end
    local distance = math.sqrt((x - position.x) ^ 2 + (y - position.y) ^ 2)
    if distance > VERIFIED_WARNING_DISTANCE then
        warn(L.VERIFIED_FAR, name, npcId, distance)
    else
        say(L.VERIFIED_CLOSE, name, npcId, distance)
    end
end

local function touch(record, name, zone)
    record.name, record.zone = name, zone
    record.lastSeen = time()
    record.build = select(2, GetBuildInfo())
end

local function recordInstance(npcId, name, zone, recipes)
    local record = store.vendors[npcId]
    if not record then
        record = { instance = true, samples = 0, firstSeen = time() }
        store.vendors[npcId] = record
    elseif not record.instance then
        addConflict(record, { reason = CONFLICT_INSTANCE, time = time() })
    end
    touch(record, name, zone)
    mergeRecipes(record, recipes)
    say(L.RECORDED_INSTANCE, name, npcId, #recipes)
end

local function recordSample(npcId, name, zone, position, recipes)
    local world = worldPosition()
    local record = store.vendors[npcId]
    if not record then
        record = {
            uiMapId = position.uiMapId, x = position.x, y = position.y, world = world,
            samples = 1, firstSeen = time(),
        }
        store.vendors[npcId] = record
        touch(record, name, zone)
        mergeRecipes(record, recipes)
        say(L.RECORDED_NEW, name, npcId, zone, position.x, position.y, #recipes)
        compareWithVerified(npcId, name, position)
        return
    end
    touch(record, name, zone)
    mergeRecipes(record, recipes)
    local conflict = { uiMapId = position.uiMapId, x = position.x, y = position.y, time = time() }
    if record.instance or record.uiMapId ~= position.uiMapId then
        conflict.reason = CONFLICT_MAP
        addConflict(record, conflict)
        warn(L.CONFLICT_MAP, name, npcId)
    else
        local yards = yardsBetween(record.world, world)
        if not yards then
            conflict.reason = CONFLICT_UNVERIFIED
            addConflict(record, conflict)
            warn(L.CONFLICT_UNVERIFIED, name, npcId)
        elseif yards > MERGE_DISTANCE_YARDS then
            conflict.reason, conflict.yards = CONFLICT_FAR, yards
            addConflict(record, conflict)
            warn(L.CONFLICT_FAR, name, npcId, yards)
        else
            local samples = record.samples + 1
            record.x = round2(record.x + (position.x - record.x) / samples)
            record.y = round2(record.y + (position.y - record.y) / samples)
            record.world.x = record.world.x + (world.x - record.world.x) / samples
            record.world.y = record.world.y + (world.y - record.world.y) / samples
            record.samples = samples
            say(L.RECORDED_MERGED, name, npcId, samples, record.x, record.y, yards)
        end
    end
    compareWithVerified(npcId, name, position)
end

-- Runs the checks for the open merchant and records a sample at most once per window.
local function tryCapture()
    local guid = UnitGUID("npc")
    if not session or guid ~= session.guid or session.captured then return end
    local npcId = session.npcId
    local name = UnitName("npc") or string.format(L.NPC_FALLBACK, npcId)
    local recipes, unresolved = scanRecipes()
    session.unresolved = unresolved
    if #recipes == 0 then
        -- items still loading may hide recipes; MERCHANT_UPDATE retries
        session.waiting = unresolved > 0
        if not session.waiting then say(L.SKIP_NO_RECIPES, name, npcId) end
        return
    end
    session.waiting, session.captured = false, true
    local zone = GetRealZoneText() or ""
    if IsInInstance() then
        recordInstance(npcId, name, zone, recipes)
        return
    end
    local position, reason = mapPosition()
    if not position then
        say(L.SKIPPED, name, npcId, reason)
        return
    end
    recordSample(npcId, name, zone, position, recipes)
end

local function onMerchantShow()
    local guid = UnitGUID("npc")
    local npcId = npcFromGuid(guid)
    if not npcId then
        session = nil
        say(L.SKIP_NOT_NPC)
        return
    end
    session = { guid = guid, npcId = npcId }
    tryCapture()
end

-- late item data: finish a pending capture, or add recipes to the record made on show
local function onMerchantUpdate()
    if not session or UnitGUID("npc") ~= session.guid then return end
    if session.waiting then
        tryCapture()
    elseif session.captured and (session.unresolved or 0) > 0 then
        local recipes, unresolved = scanRecipes()
        session.unresolved = unresolved
        local record = store.vendors[session.npcId]
        if record then mergeRecipes(record, recipes) end
    end
end

merchantEvents:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then onMerchantShow()
    elseif event == "MERCHANT_UPDATE" then onMerchantUpdate()
    elseif event == "MERCHANT_CLOSED" then session = nil end
end)

local function applyEnabled()
    if store.enabled then
        merchantEvents:RegisterEvent("MERCHANT_SHOW")
        merchantEvents:RegisterEvent("MERCHANT_UPDATE")
        merchantEvents:RegisterEvent("MERCHANT_CLOSED")
    else
        merchantEvents:UnregisterAllEvents()
        session = nil
    end
end

loginEvents:RegisterEvent("PLAYER_LOGIN")
loginEvents:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if store and store.enabled then say(L.COLLECT_ON_LOGIN) end
end)

function Collector.Init(db)
    if type(db.collector) ~= "table" then db.collector = {} end
    store = db.collector
    store.enabled = store.enabled == true
    if type(store.vendors) ~= "table" then store.vendors = {} end
    applyEnabled()
end

function Collector.IsEnabled()
    return store ~= nil and store.enabled
end

function Collector.SetEnabled(enabled)
    if not store then return end
    store.enabled = enabled == true
    applyEnabled()
end

-- A collected point usable for waypoints: outside instances and without conflicts.
function Collector.GetPoint(npcId)
    local record = store and store.vendors[npcId]
    if type(record) ~= "table" or record.instance then return nil end
    if type(record.conflicts) == "table" and #record.conflicts > 0 then return nil end
    return record.uiMapId, record.x, record.y
end

-- Returns counts: total, usable points, instance vendors, vendors with conflicts.
function Collector.Counts()
    local total, usable, instances, conflicted = 0, 0, 0, 0
    for npcId, record in pairs(store and store.vendors or {}) do
        total = total + 1
        if type(record) == "table" then
            if record.instance then instances = instances + 1 end
            if type(record.conflicts) == "table" and #record.conflicts > 0 then conflicted = conflicted + 1 end
            if Coordinates.GetCollected(npcId) then usable = usable + 1 end
        end
    end
    return total, usable, instances, conflicted
end

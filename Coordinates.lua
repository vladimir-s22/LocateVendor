-- Validated access to vendor coordinates. Entries that fail validation count as missing.
-- Priority: verified points from Data/Vendors.lua, then points collected in-game without conflicts.
local _, ns = ...

local Coordinates = {}
ns.Coordinates = Coordinates

local function isMapCoordinate(value)
    return type(value) == "number" and value > 0 and value < 100
end

local function validated(uiMapId, x, y)
    if type(uiMapId) ~= "number" or uiMapId <= 0 or uiMapId % 1 ~= 0 then return nil end
    if not (isMapCoordinate(x) and isMapCoordinate(y)) then return nil end
    return uiMapId, x, y
end

-- Returns uiMapId, x, y (0-100) from Data/Vendors.lua, or nil.
function Coordinates.GetVerified(npcId)
    local entry = (ns.VendorData or {})[npcId]
    if type(entry) ~= "table" then return nil end
    return validated(entry.uiMapId, entry.x, entry.y)
end

-- Returns uiMapId, x, y (0-100) collected in-game, or nil.
function Coordinates.GetCollected(npcId)
    local Collector = ns.Collector
    if not Collector then return nil end
    return validated(Collector.GetPoint(npcId))
end

-- Returns uiMapId, x, y (0-100) or nil; a verified point always wins over a collected one.
function Coordinates.Get(npcId)
    local uiMapId, x, y = Coordinates.GetVerified(npcId)
    if uiMapId then return uiMapId, x, y end
    return Coordinates.GetCollected(npcId)
end

-- Adds uiMapId, x and y to every vendor that has valid coordinates; returns how many have them.
-- A wandering vendor never gets coordinates: any single point would soon be wrong.
function Coordinates.Attach(vendors)
    local count = 0
    for _, vendor in ipairs(vendors) do
        vendor.uiMapId, vendor.x, vendor.y = nil, nil, nil
        if not vendor.isWandering then
            vendor.uiMapId, vendor.x, vendor.y = Coordinates.Get(vendor.npcId)
        end
        if vendor.uiMapId then count = count + 1 end
    end
    return count
end

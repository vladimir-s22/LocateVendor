-- Validated access to vendor coordinates. Entries that fail validation count as missing.
local _, ns = ...

local Coordinates = {}
ns.Coordinates = Coordinates

local function isMapCoordinate(value)
    return type(value) == "number" and value > 0 and value < 100
end

-- Returns uiMapId, x, y (0-100) or nil.
function Coordinates.Get(npcId)
    local entry = (ns.VendorData or {})[npcId]
    if type(entry) ~= "table" then return nil end
    local uiMapId = entry.uiMapId
    if type(uiMapId) ~= "number" or uiMapId <= 0 or uiMapId % 1 ~= 0 then return nil end
    if not (isMapCoordinate(entry.x) and isMapCoordinate(entry.y)) then return nil end
    return uiMapId, entry.x, entry.y
end

-- Adds uiMapId, x and y to every vendor that has valid coordinates; returns how many have them.
function Coordinates.Attach(vendors)
    local count = 0
    for _, vendor in ipairs(vendors) do
        vendor.uiMapId, vendor.x, vendor.y = Coordinates.Get(vendor.npcId)
        if vendor.uiMapId then count = count + 1 end
    end
    return count
end

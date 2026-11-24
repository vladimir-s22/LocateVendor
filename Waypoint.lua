-- Places waypoints through an external navigation addon; LocateVendor has no navigation of its own.
-- Providers are tried in order. A future public What's Training? waypoint method would be added
-- in front of TomTom here; nothing else in the addon talks to a provider directly.
local addonName, ns = ...

local Waypoint = {}
ns.Waypoint = Waypoint

local function tomtom()
    local addon = _G.TomTom
    if type(addon) == "table" and type(addon.AddWaypoint) == "function" then return addon end
    return nil
end

-- the TomTom waypoint LocateVendor placed last; the only one we ever remove
local ownWaypoint

local function removeOwnWaypoint(addon)
    local uid = ownWaypoint
    ownWaypoint = nil
    if not uid or type(addon.RemoveWaypoint) ~= "function" then return end
    -- TomTom drops a waypoint on arrival, and the player may remove it by hand
    if type(addon.IsValidWaypoint) == "function" then
        local ok, valid = pcall(addon.IsValidWaypoint, addon, uid)
        if ok and not valid then return end
    end
    pcall(addon.RemoveWaypoint, addon, uid)
end

local tomtomProvider = {
    id = "tomtom",
    isAvailable = function() return tomtom() ~= nil end,
    -- x and y are 0-100
    setWaypoint = function(uiMapId, x, y, title)
        local addon = tomtom()
        removeOwnWaypoint(addon)
        local ok, uid = xpcall(addon.AddWaypoint, geterrorhandler(), addon, uiMapId, x / 100, y / 100, {
            title = title,
            from = addonName,
            persistent = false,
            minimap = true,
            world = true,
            crazy = true,
        })
        if not ok or not uid then return false end
        ownWaypoint = uid
        return true
    end,
}

local providers = { tomtomProvider }

local function activeProvider()
    for _, provider in ipairs(providers) do
        local ok, available = pcall(provider.isAvailable)
        if ok and available then return provider end
    end
    return nil
end

function Waypoint.IsAvailable()
    return activeProvider() ~= nil
end

-- Returns whether a waypoint was placed.
function Waypoint.Set(uiMapId, x, y, title)
    local provider = activeProvider()
    if not provider then return false end
    return provider.setWaypoint(uiMapId, x, y, title) == true
end

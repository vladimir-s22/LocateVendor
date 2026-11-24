-- Shared text for vendors in tooltips, menus and waypoint titles.
local _, ns = ...
local L, NpcNames = ns.L, ns.NpcNames

local Format = {}
ns.Format = Format

Format.MAP_ICON = "|TInterface\\Icons\\INV_Misc_Map_01:0|t"

function Format.Colorize(text, color)
    return "|c" .. color .. text .. "|r"
end

function Format.ZoneName(areaId)
    local name = areaId and areaId > 0 and C_Map.GetAreaInfo(areaId)
    if type(name) == "string" and name ~= "" then return name end
    return L.UNKNOWN_ZONE
end

-- Returns the vendor's name, or the "NPC #id" fallback and false while the name is unknown.
function Format.VendorName(vendor)
    local name = NpcNames.Resolve(vendor.npcId)
    if name then return name, true end
    return string.format(L.NPC_FALLBACK, vendor.npcId), false
end

-- Zone, with the vendor's faction for recipes only the other faction can obtain.
function Format.VendorZone(vendor)
    local zone = Format.ZoneName(vendor.areaId)
    if vendor.isOtherFaction and vendor.faction then
        zone = string.format("%s (%s)", zone, L["FACTION_" .. vendor.faction])
    end
    return zone
end

-- Plain "Name — Zone", used for menu entries and waypoint titles.
function Format.VendorText(vendor)
    return (Format.VendorName(vendor)) .. " — " .. Format.VendorZone(vendor)
end

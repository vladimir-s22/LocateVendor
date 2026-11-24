-- Picks the vendors to show for a What's Training? recipe row.
-- Availability comes only from fields What's Training? computed for the row:
--   data.sources            usable sources; "vendor" is absent when WT dropped it for the player's faction
--   data.otherFactionSource "Alliance" or "Horde" when only that faction can obtain the recipe
--                           (WT shows such rows only with its "show other faction recipes" option)
local _, ns = ...

local VendorFilter = {}
ns.VendorFilter = VendorFilter

local KNOWN_FACTIONS = { Alliance = true, Horde = true }

local function hasVendorSource(data)
    if type(data.sources) ~= "table" then return false end
    for _, source in ipairs(data.sources) do
        if source == "vendor" then return true end
    end
    return false
end

-- Returns an array of { npcId, areaId, faction, isOtherFaction }; empty when nothing applies.
function VendorFilter.ForRow(data)
    local result = {}
    local recipe = type(data) == "table" and data.recipe
    if type(recipe) ~= "table" or type(recipe.vendors) ~= "table" or not hasVendorSource(data) then
        return result
    end
    local otherFaction = data.otherFactionSource
    -- an unknown value means WT changed its model; show nothing rather than guess
    if otherFaction ~= nil and not KNOWN_FACTIONS[otherFaction] then return result end
    local playerFaction = UnitFactionGroup("player")
    local seen = {}
    for _, vendor in ipairs(recipe.vendors) do
        local npcId = type(vendor) == "table" and tonumber(vendor.npc)
        if npcId and not seen[npcId] then
            local include
            if otherFaction then
                include = vendor.faction == otherFaction
            else
                -- same rule as WT's addSourceZones in Crafting/RecipeList.lua
                include = not vendor.faction or vendor.faction == playerFaction
            end
            if include then
                seen[npcId] = true
                tinsert(result, {
                    npcId = npcId,
                    areaId = tonumber(vendor.area),
                    faction = vendor.faction,
                    isOtherFaction = otherFaction ~= nil,
                })
            end
        end
    end
    return result
end

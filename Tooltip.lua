local _, ns = ...
local L, Bridge, NpcNames, VendorFilter = ns.L, ns.Bridge, ns.NpcNames, ns.VendorFilter

local Tooltip = {}
ns.Tooltip = Tooltip

local HEADER_COLOR = { 1, 0.82, 0 }
local NAME_COLOR = "ffffffff"
local PENDING_NAME_COLOR = "ff9d9d9d"
local ZONE_COLOR = "ffb0b0b0"

-- Every build, clear or hide of GameTooltip starts a new generation. A name that arrives later
-- refreshes the tooltip only if the context waiting for it belongs to the current generation.
local generation = 0
-- last context we rendered: { generation, row, spellId, waiting = { [npcId] = true } };
-- it is stale as soon as its generation differs from the current one
local context
-- generation a deferred refresh is already scheduled for
local scheduledGeneration

local function invalidate()
    generation = generation + 1
end

local function colorize(text, color)
    return "|c" .. color .. text .. "|r"
end

local function zoneName(areaId)
    local name = areaId and areaId > 0 and C_Map.GetAreaInfo(areaId)
    if type(name) == "string" and name ~= "" then return name end
    return L.UNKNOWN_ZONE
end

local function vendorLine(vendor, name)
    local label = name
        and colorize(name, NAME_COLOR)
        or colorize(string.format(L.NPC_FALLBACK, vendor.npcId), PENDING_NAME_COLOR)
    local zone = zoneName(vendor.areaId)
    if vendor.isOtherFaction and vendor.faction then
        zone = string.format("%s (%s)", zone, L["FACTION_" .. vendor.faction])
    end
    return "  " .. label .. " " .. colorize("— " .. zone, ZONE_COLOR)
end

function Tooltip.Render(tooltip, tooltipData)
    local row, data = Bridge.GetRecipeRow(tooltip, tooltipData and tooltipData.id)
    if not row then return end
    invalidate()
    local vendors = VendorFilter.ForRow(data)
    if #vendors == 0 then return end
    local waiting = {}
    tooltip:AddLine(L.VENDORS_HEADER, unpack(HEADER_COLOR))
    for _, vendor in ipairs(vendors) do
        local name = NpcNames.Resolve(vendor.npcId)
        if not name and NpcNames.IsPending(vendor.npcId) then waiting[vendor.npcId] = true end
        tooltip:AddLine(vendorLine(vendor, name), 1, 1, 1, true)
    end
    context = { generation = generation, row = row, spellId = tooltipData.id, waiting = waiting }
end

-- Rebuilds the tooltip the same way WT's OnEnter does. Resolve() inside the rebuild finds
-- names in the cache or sees them pending, so a refresh never starts another request.
local function refresh(expectedGeneration)
    if scheduledGeneration == expectedGeneration then scheduledGeneration = nil end
    local current = context
    if expectedGeneration ~= generation or not current or current.generation ~= expectedGeneration then return end
    -- defence in depth: the owner and recipe must still match
    if not (GameTooltip:IsShown() and GameTooltip:IsOwned(current.row)
        and Bridge.RowShowsSpell(current.row, current.spellId)) then
        return
    end
    GameTooltip:SetSpellByID(current.spellId)
end

NpcNames.Subscribe(function(npcId)
    local current = context
    if not current or current.generation ~= generation or not current.waiting[npcId] then return end
    current.waiting[npcId] = nil
    -- names arriving in the same frame share one rebuild of this generation
    if scheduledGeneration == current.generation then return end
    scheduledGeneration = current.generation
    local expectedGeneration = current.generation
    C_Timer.After(0, function() refresh(expectedGeneration) end)
end)

GameTooltip:HookScript("OnHide", invalidate)
if GameTooltip:HasScript("OnTooltipCleared") then
    GameTooltip:HookScript("OnTooltipCleared", invalidate)
end

local _, ns = ...
local L, Bridge, NpcNames, Format, RowClick = ns.L, ns.Bridge, ns.NpcNames, ns.Format, ns.RowClick

local Tooltip = {}
ns.Tooltip = Tooltip

local HEADER_COLOR = { 1, 0.82, 0 }
local HINT_COLOR = { 0.4, 0.8, 1 }
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

local function vendorLine(vendor)
    local name, known = Format.VendorName(vendor)
    local label = Format.Colorize(name, known and NAME_COLOR or PENDING_NAME_COLOR)
    if vendor.uiMapId then label = Format.MAP_ICON .. " " .. label end
    return "  " .. label .. " " .. Format.Colorize("— " .. Format.VendorZone(vendor), ZONE_COLOR)
end

-- Bridge calls this for WT recipe rows only, after WT's own lines.
function Tooltip.Render(tooltip, tooltipData, row, data)
    invalidate()
    local vendors = RowClick.Vendors(data)
    if #vendors == 0 then return end
    local waiting = {}
    tooltip:AddLine(L.VENDORS_HEADER, unpack(HEADER_COLOR))
    for _, vendor in ipairs(vendors) do
        tooltip:AddLine(vendorLine(vendor), 1, 1, 1, true)
        if NpcNames.IsPending(vendor.npcId) then waiting[vendor.npcId] = true end
    end
    local action = RowClick.Action(vendors)
    if action == RowClick.WAYPOINT then
        tooltip:AddLine(L.HINT_WAYPOINT, unpack(HINT_COLOR))
    elseif action == RowClick.MENU then
        tooltip:AddLine(L.HINT_MENU, unpack(HINT_COLOR))
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

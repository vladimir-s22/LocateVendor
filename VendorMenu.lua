-- Context menu for choosing one of several vendors.
local _, ns = ...
local L, Format = ns.L, ns.Format

local VendorMenu = {}
ns.VendorMenu = VendorMenu

local UNAVAILABLE_COLOR = "ff808080"

local function navigableFirst(vendors)
    local sorted = {}
    for index, vendor in ipairs(vendors) do sorted[index] = vendor end
    local order = {}
    for index, vendor in ipairs(vendors) do order[vendor] = index end
    table.sort(sorted, function(a, b)
        if (a.uiMapId ~= nil) ~= (b.uiMapId ~= nil) then return a.uiMapId ~= nil end
        return order[a] < order[b]
    end)
    return sorted
end

local function ignoreClick() end

-- Vendors without coordinates stay visible, greyed out, marked and disabled.
-- onSelect(vendor) runs for a vendor with coordinates.
function VendorMenu.Open(owner, title, vendors, onSelect)
    local entries = navigableFirst(vendors)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(title)
        for _, vendor in ipairs(entries) do
            local text = Format.VendorText(vendor)
            if vendor.uiMapId then
                root:CreateButton(Format.MAP_ICON .. " " .. text, function() onSelect(vendor) end)
            else
                -- a wandering vendor already carries its own mark in the zone text
                if not vendor.isWandering then text = text .. " (" .. L.NO_COORDINATES .. ")" end
                local label = Format.Colorize(text, UNAVAILABLE_COLOR)
                local button = root:CreateButton(label, ignoreClick)
                if button and button.SetEnabled then button:SetEnabled(false) end
            end
        end
    end)
end

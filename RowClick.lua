-- Decides what a plain left click on a recipe row does:
--   one vendor with coordinates            -> waypoint right away
--   several vendors, any with coordinates  -> menu listing every vendor
--   anything else, or no waypoint provider -> nothing
local _, ns = ...
local Coordinates, Format, VendorFilter, VendorMenu, Waypoint =
    ns.Coordinates, ns.Format, ns.VendorFilter, ns.VendorMenu, ns.Waypoint

local RowClick = {}
ns.RowClick = RowClick

RowClick.WAYPOINT = "waypoint"
RowClick.MENU = "menu"

-- Returns the vendors to show for a row, each with coordinates attached when known.
function RowClick.Vendors(data)
    local vendors = VendorFilter.ForRow(data)
    Coordinates.Attach(vendors)
    return vendors
end

-- Returns RowClick.WAYPOINT, RowClick.MENU or nil for vendors from RowClick.Vendors.
function RowClick.Action(vendors)
    local navigable = 0
    for _, vendor in ipairs(vendors) do
        if vendor.uiMapId then navigable = navigable + 1 end
    end
    if navigable == 0 or not Waypoint.IsAvailable() then return nil end
    return #vendors == 1 and RowClick.WAYPOINT or RowClick.MENU
end

local function navigateTo(vendor)
    if Waypoint.Set(vendor.uiMapId, vendor.x, vendor.y, Format.VendorText(vendor)) then
        PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
    end
end

function RowClick.OnClick(row, data, button)
    if button ~= "LeftButton" or IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown() then return end
    local vendors = RowClick.Vendors(data)
    local action = RowClick.Action(vendors)
    if action == RowClick.WAYPOINT then
        navigateTo(vendors[1])
    elseif action == RowClick.MENU then
        VendorMenu.Open(row, data.name or "", vendors, navigateTo)
    end
end

local addonName, ns = ...

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, loadedName)
    if loadedName ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    if type(LocateVendorDB) ~= "table" then LocateVendorDB = {} end
    ns.NpcNames.Init(LocateVendorDB)
    ns.Collector.Init(LocateVendorDB)
    ns.Bridge.Start(ns.Tooltip.Render, ns.RowClick.OnClick)
end)

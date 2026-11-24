local addonName, ns = ...

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, loadedName)
    if loadedName ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    ns.NpcNames.Init()
    ns.Bridge.Start(ns.Tooltip.Render, ns.RowClick.OnClick)
end)

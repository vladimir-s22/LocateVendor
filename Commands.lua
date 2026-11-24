local _, ns = ...
local L, Collector = ns.L, ns.Collector

local PREFIX = "|cff33ff99LocateVendor|r: "

local function say(format, ...)
    print(PREFIX .. string.format(format, ...))
end

local function showStatus()
    local total, usable, instances, conflicted = Collector.Counts()
    say(L.STATUS, Collector.IsEnabled() and L.STATE_ON or L.STATE_OFF, total, usable, instances, conflicted)
end

SLASH_LOCATEVENDOR1 = "/lv"
SLASH_LOCATEVENDOR2 = "/locatevendor"
SlashCmdList.LOCATEVENDOR = function(input)
    local command = string.lower((input or ""):match("^%s*(.-)%s*$"))
    if command == "collect" then
        Collector.SetEnabled(not Collector.IsEnabled())
        say(Collector.IsEnabled() and L.COLLECT_ENABLED or L.COLLECT_DISABLED)
    elseif command == "status" then
        showStatus()
    else
        say(L.HELP)
    end
end

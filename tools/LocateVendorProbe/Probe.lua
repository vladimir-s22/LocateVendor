-- LocateVendor Probe: verifies the client APIs LocateVendor depends on.
-- Every message is printed to chat and appended to the LocateVendorProbeLog saved variable.
local addonName = ...

local PREFIX = "|cff33ff99LV Probe|r: "
local MAX_SESSIONS = 10
local NAME_RETRY_DELAYS = { 0, 0.5, 1, 2, 4 } -- seconds since the first attempt
local RECIPE_ITEM_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or LE_ITEM_CLASS_RECIPE or 9

local sessionLog
local lastCapture

local function out(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local message = table.concat(parts, " ")
    print(PREFIX .. message)
    if sessionLog then tinsert(sessionLog.lines, date("%H:%M:%S ") .. message) end
end

local function formatPosition(x, y)
    if not x or not y then return "nil" end
    return string.format("%.4f, %.4f (%.2f, %.2f)", x, y, x * 100, y * 100)
end

-- Creature GUID: Creature-0-<server>-<instance>-<zoneUID>-<npcId>-<spawnUID>
local function parseGuid(guid)
    if not guid then return nil, nil end
    local unitType, _, _, _, _, npcId = strsplit("-", guid)
    return unitType, tonumber(npcId)
end

local function creatureLink(npcId)
    return string.format("unit:Creature-0-0-0-0-%d-0000000000", npcId)
end

-- NPC name lookups ---------------------------------------------------------

local function firstLineText(line)
    if not line then return nil end
    if line.leftText then return line.leftText end
    -- 10.0.x style data needs its args surfaced manually
    for _, arg in ipairs(line.args or {}) do
        if arg.field == "leftText" then return arg.stringVal end
    end
end

local function nameViaTooltipInfo(npcId)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then
        return nil, "C_TooltipInfo.GetHyperlink is missing"
    end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, creatureLink(npcId))
    if not ok then return nil, "error: " .. tostring(data) end
    if not data then return nil, "returned nil" end
    local lineCount = data.lines and #data.lines or 0
    local text = firstLineText(data.lines and data.lines[1])
    if text and text ~= "" then return text, "lines=" .. lineCount end
    return nil, "empty, lines=" .. lineCount
end

local scanner
local function nameViaScanner(npcId)
    if not scanner then
        scanner = CreateFrame("GameTooltip", "LocateVendorProbeScanner", UIParent, "GameTooltipTemplate")
    end
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    scanner:ClearLines()
    local ok, err = pcall(scanner.SetHyperlink, scanner, creatureLink(npcId))
    if not ok then
        scanner:Hide()
        return nil, "error: " .. tostring(err)
    end
    local lineCount = scanner:NumLines()
    local fontString = _G.LocateVendorProbeScannerTextLeft1
    local text = fontString and fontString:GetText()
    scanner:Hide()
    if text and text ~= "" then return text, "lines=" .. lineCount end
    return nil, "empty, lines=" .. lineCount
end

local function probeName(method, label, npcId)
    out(label, "npc", npcId, "locale", GetLocale())
    local function attempt(index)
        local name, details = method(npcId)
        if name then
            out(label, "OK on attempt", index, "after", NAME_RETRY_DELAYS[index], "s ->", name, "(" .. details .. ")")
            return
        end
        if index == #NAME_RETRY_DELAYS then
            out(label, "FAILED after", index, "attempts:", details)
            return
        end
        out(label, "attempt", index, "->", details)
        C_Timer.After(NAME_RETRY_DELAYS[index + 1] - NAME_RETRY_DELAYS[index], function() attempt(index + 1) end)
    end
    attempt(1)
end

-- Merchant capture ---------------------------------------------------------

local function merchantItemId(index)
    if GetMerchantItemID then return GetMerchantItemID(index) end
    local link = GetMerchantItemLink(index)
    return link and tonumber(link:match("item:(%d+)"))
end

local function itemClassId(itemId)
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getInstant then return nil end
    return (select(6, getInstant(itemId)))
end

local function currentPosition()
    local mapId = C_Map.GetBestMapForUnit("player")
    local position = mapId and C_Map.GetPlayerMapPosition(mapId, "player")
    local x, y
    if position then x, y = position:GetXY() end
    return mapId, x, y
end

local function captureMerchant(trigger)
    local guid = UnitGUID("npc")
    local unitType, npcId = parseGuid(guid)
    local npcName = UnitName("npc")
    out("[" .. trigger .. "] guid:", guid, "type:", unitType, "npcId:", npcId, "name:", npcName)

    local mapId, x, y = currentPosition()
    local mapInfo = mapId and C_Map.GetMapInfo(mapId)
    local inInstance, instanceType = IsInInstance()
    out("map:", mapId, mapInfo and mapInfo.name, "mapType:", mapInfo and mapInfo.mapType,
        "parent:", mapInfo and mapInfo.parentMapID, "instance:", inInstance, instanceType)
    out("position:", formatPosition(x, y), "zone:", GetRealZoneText(), "/", GetSubZoneText())

    local itemCount = GetMerchantNumItems()
    local recipes, unresolved = {}, 0
    for index = 1, itemCount do
        local itemId = merchantItemId(index)
        if not itemId then
            unresolved = unresolved + 1
        elseif itemClassId(itemId) == RECIPE_ITEM_CLASS then
            tinsert(recipes, itemId)
        end
    end
    out("merchant items:", itemCount, "unresolved:", unresolved, "recipes:", #recipes, table.concat(recipes, ","))

    lastCapture = { npcId = npcId, name = npcName, mapId = mapId, x = x, y = y }
    if sessionLog then
        tinsert(sessionLog.captures, {
            trigger = trigger, guid = guid, npcId = npcId, name = npcName, mapId = mapId, x = x, y = y,
            instance = inInstance, items = itemCount, unresolved = unresolved, recipes = recipes,
        })
    end
end

-- TomTom -------------------------------------------------------------------

local function probeTomTom(args)
    local tomtom = _G.TomTom
    if not (tomtom and tomtom.AddWaypoint) then
        out("TomTom is not loaded")
        return
    end
    local target
    local mapId, x, y = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if mapId and x and y then
        target = { name = "Probe target", mapId = mapId, x = x / 100, y = y / 100 }
    elseif args[2] == "here" or not lastCapture then
        local currentMap, currentX, currentY = currentPosition()
        target = { name = "Probe: player position", mapId = currentMap, x = currentX, y = currentY }
    else
        target = lastCapture
    end
    if not (target.mapId and target.x and target.y) then
        out("no usable position for", target.name)
        return
    end
    out("TomTom:AddWaypoint", target.mapId, formatPosition(target.x, target.y), target.name)
    local ok, result = pcall(tomtom.AddWaypoint, tomtom, target.mapId, target.x, target.y, {
        title = target.name, from = addonName, persistent = false, minimap = true, world = true, crazy = true,
    })
    out("result:", ok, result)
end

-- Environment --------------------------------------------------------------

local function probeApi()
    local version, build, _, interface = GetBuildInfo()
    out("build:", version, build, "interface:", interface, "project:", WOW_PROJECT_ID, "locale:", GetLocale())
    out("player faction:", UnitFactionGroup("player"))
    local checks = {
        { "C_TooltipInfo.GetHyperlink", C_TooltipInfo and C_TooltipInfo.GetHyperlink },
        { "TooltipDataProcessor.AddTooltipPostCall", TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall },
        { "MenuUtil.CreateContextMenu", MenuUtil and MenuUtil.CreateContextMenu },
        { "C_Map.GetBestMapForUnit", C_Map.GetBestMapForUnit },
        { "C_Map.GetPlayerMapPosition", C_Map.GetPlayerMapPosition },
        { "C_Map.GetAreaInfo", C_Map.GetAreaInfo },
        { "C_Map.SetUserWaypoint", C_Map.SetUserWaypoint },
        { "GetMerchantItemID", GetMerchantItemID },
        { "C_Item.GetItemInfoInstant", C_Item and C_Item.GetItemInfoInstant },
        { "GetItemInfoInstant", GetItemInfoInstant },
        { "TomTom.AddWaypoint", _G.TomTom and _G.TomTom.AddWaypoint },
        { "WT_API", _G.WT_API },
        { "WhatsTrainingCraftingScrollBox", _G.WhatsTrainingCraftingScrollBox },
    }
    for _, check in ipairs(checks) do out(check[1], check[2] and "yes" or "NO") end
    out("recipe item class id:", RECIPE_ITEM_CLASS, "WT_API.version:", _G.WT_API and _G.WT_API.version,
        "WT_WaypointProvider:", _G.WT_WaypointProvider)
end

local function probeAreas(args)
    for index = 2, #args do
        local areaId = tonumber(args[index])
        if areaId then out("area", areaId, "->", C_Map.GetAreaInfo(areaId)) end
    end
end

local function probeMap(args)
    for index = 2, #args do
        local mapId = tonumber(args[index])
        local info = mapId and C_Map.GetMapInfo(mapId)
        out("uiMap", mapId, "->", info and info.name, "type:", info and info.mapType,
            "parent:", info and info.parentMapID)
    end
end

local function hoveredFrame()
    if GetMouseFoci then return GetMouseFoci()[1] end
    return GetMouseFocus and GetMouseFocus()
end

-- run while the cursor rests on a What's Training? recipe row
local function probeHover()
    local frame = hoveredFrame()
    local scrollBox = _G.WhatsTrainingCraftingScrollBox
    local inList, parent = false, frame
    while parent do
        if parent == scrollBox then inList = true break end
        parent = parent:GetParent()
    end
    out("hover:", frame and frame.GetDebugName and frame:GetDebugName(), "in WT list:", inList)
    local data = frame and frame.data
    if not (data and data.recipe) then
        out("no recipe data on the hovered frame")
        return
    end
    out("spell:", data.recipe.spell, "source:", data.source, "otherFactionSource:", data.otherFactionSource,
        "PostClick set:", frame:GetScript("PostClick") ~= nil)
    for _, vendor in ipairs(data.recipe.vendors or {}) do
        out("  vendor npc:", vendor.npc, "area:", vendor.area, C_Map.GetAreaInfo(vendor.area or 0),
            "faction:", vendor.faction or "neutral")
    end
end

local function printHelp()
    out("/lvprobe api | name <npcId> | scan <npcId> | merchant | tomtom [here | <uiMapId> <x> <y>]"
        .. " | area <areaId...> | map <uiMapId...> | hover")
end

SLASH_LOCATEVENDORPROBE1 = "/lvprobe"
SlashCmdList.LOCATEVENDORPROBE = function(input)
    local args = {}
    for word in (input or ""):gmatch("%S+") do tinsert(args, word) end
    local command = (args[1] or ""):lower()
    local npcId = tonumber(args[2])
    if command == "api" then probeApi()
    elseif command == "name" and npcId then probeName(nameViaTooltipInfo, "C_TooltipInfo", npcId)
    elseif command == "scan" and npcId then probeName(nameViaScanner, "scanner", npcId)
    elseif command == "merchant" then captureMerchant("manual")
    elseif command == "tomtom" then probeTomTom(args)
    elseif command == "area" then probeAreas(args)
    elseif command == "map" then probeMap(args)
    elseif command == "hover" then probeHover()
    else printHelp() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("MERCHANT_SHOW")
events:SetScript("OnEvent", function(_, event, loadedName)
    if event == "ADDON_LOADED" and loadedName == addonName then
        LocateVendorProbeLog = LocateVendorProbeLog or {}
        sessionLog = {
            started = date("%Y-%m-%d %H:%M:%S"), build = select(2, GetBuildInfo()), lines = {}, captures = {},
        }
        tinsert(LocateVendorProbeLog, sessionLog)
        while #LocateVendorProbeLog > MAX_SESSIONS do tremove(LocateVendorProbeLog, 1) end
    elseif event == "MERCHANT_SHOW" then
        captureMerchant("MERCHANT_SHOW")
    end
end)

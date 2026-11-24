-- Offline tests with a mocked WoW API. Run from the repo root: luajit tests/run.lua
-- load files in TOC order, so the TOC itself is under test
local ADDON_FILES = {}
for line in io.lines("LocateVendor.toc") do
    if line:match("^[^#%s].*%.lua%s*$") then
        table.insert(ADDON_FILES, (line:gsub("\\", "/"):gsub("%s+$", "")))
    end
end

local failures, passed = 0, 0
local function check(condition, message)
    if condition then passed = passed + 1 else failures = failures + 1; print("FAIL: " .. message) end
end

-- Builds a fresh mocked client and loads the addon into it. options:
--   locale, faction, build, savedDB, creatureNames (npcId -> name), nameDelayQueries (npcId -> misses before name),
--   tomtom (false: not installed), noSetEnabled (menu elements without SetEnabled), supportsCleared
local function newClient(options)
    options = options or {}
    local env = setmetatable({}, { __index = _G })
    env._G = env
    local timers, frames = {}, {}
    local state = { now = 0, timers = timers, queries = {}, setSpellCalls = 0, sounds = 0, menus = {},
        modifiers = {} }

    env.GetLocale = function() return options.locale or "ruRU" end
    env.GetBuildInfo = function() return "1.60.1", options.build or "71037", "", 16001 end
    env.UnitFactionGroup = function() return options.faction or "Alliance" end
    env.UNKNOWNOBJECT = "Unknown"
    env.tinsert = table.insert
    env.geterrorhandler = function() return function(err) error(err) end end
    env.LocateVendorDB = options.savedDB

    -- like the client, a zero-delay timer created while timers run waits for the next frame:
    -- it fires only on a later advance() call
    state.frame = 0
    env.C_Timer = { After = function(delay, callback)
        table.insert(timers, { at = state.now + delay, callback = callback, nextFrame = delay == 0 and state.frame })
    end }
    function state.advance(seconds)
        local target = state.now + seconds
        state.frame = state.frame + 1
        while true do
            table.sort(timers, function(a, b) return a.at < b.at end)
            local nextTimer
            for index, timer in ipairs(timers) do
                if timer.at > target then break end
                if timer.nextFrame ~= state.frame then
                    nextTimer = table.remove(timers, index)
                    break
                end
            end
            if not nextTimer then break end
            state.now = nextTimer.at
            nextTimer.callback()
        end
        state.now = target
    end

    local misses = {}
    env.C_TooltipInfo = { GetHyperlink = function(link)
        local npcId = tonumber(link:match("Creature%-0%-0%-0%-0%-(%d+)%-"))
        state.queries[npcId] = (state.queries[npcId] or 0) + 1
        local name = (options.creatureNames or {})[npcId]
        local needed = (options.nameDelayQueries or {})[npcId] or 0
        misses[npcId] = misses[npcId] or 0
        if not name or misses[npcId] < needed then
            misses[npcId] = misses[npcId] + 1
            return nil
        end
        return { lines = { { leftText = name } } }
    end }
    env.C_Map = { GetAreaInfo = function(areaId)
        return ({ [40] = "Западный Край", [38] = "Лок Модан", [17] = "Степи", [1637] = "Оргриммар",
            [267] = "Предгорья Хилсбрада", [331] = "Ясеневый лес", [1519] = "Штормград", [1657] = "Дарнас",
            [1537] = "Стальгорн", [1377] = "Силитус", [16593] = "Остров Зефрис" })[areaId]
    end }

    env.IsShiftKeyDown = function() return state.modifiers.shift == true end
    env.IsControlKeyDown = function() return state.modifiers.ctrl == true end
    env.IsAltKeyDown = function() return state.modifiers.alt == true end
    env.SOUNDKIT = { U_CHAT_SCROLL_BUTTON = 1115 }
    env.PlaySound = function() state.sounds = state.sounds + 1 end

    -- MenuUtil records every menu it builds
    env.MenuUtil = { CreateContextMenu = function(owner, generator)
        local menu = { owner = owner, entries = {} }
        local root = {}
        function root.CreateTitle(_, title) table.insert(menu.entries, { kind = "title", text = title }) end
        function root.CreateButton(_, text, callback)
            local entry = { kind = "button", text = text, callback = callback, enabled = true }
            table.insert(menu.entries, entry)
            local element = {}
            if not options.noSetEnabled then
                function element.SetEnabled(_, enabled) entry.enabled = enabled end
            end
            return element
        end
        generator(owner, root)
        table.insert(state.menus, menu)
        return menu
    end }

    -- TomTom keeps waypoints by uid table, like the real addon
    if options.tomtom ~= false then
        local tomtom = { waypoints = {} }
        function tomtom.AddWaypoint(self, uiMapId, x, y, opts)
            local uid = { uiMapId, x, y, title = opts and opts.title, from = opts and opts.from }
            self.waypoints[uid] = true
            return uid
        end
        function tomtom.RemoveWaypoint(self, uid) self.waypoints[uid] = nil end
        function tomtom.IsValidWaypoint(self, uid) return self.waypoints[uid] == true end
        function tomtom.list(self)
            local list = {}
            for uid in pairs(self.waypoints) do table.insert(list, uid) end
            return list
        end
        env.TomTom = tomtom
        state.tomtom = tomtom
    end

    -- frames and the tooltip
    local function newFrame(parent)
        local frame = { parent = parent, scripts = {} }
        function frame.GetParent(self) return self.parent end
        function frame.RegisterEvent() end
        function frame.UnregisterEvent() end
        function frame.SetScript(self, name, fn) self.scripts[name] = fn end
        frame.hooks = {}
        function frame.HookScript(self, name, fn)
            self.hooks[name] = self.hooks[name] or {}
            table.insert(self.hooks[name], fn)
        end
        table.insert(frames, frame)
        return frame
    end
    env.CreateFrame = function() return newFrame(nil) end

    local postCalls = {}
    env.Enum = { TooltipDataType = { Spell = 1, Item = 0 } }
    env.TooltipDataProcessor = { AddTooltipPostCall = function(tooltipType, fn)
        table.insert(postCalls, { type = tooltipType, fn = fn })
    end }
    env.hooksecurefunc = function(target, name, hook)
        local original = target[name]
        target[name] = function(...)
            local result = original(...)
            hook(...)
            return result
        end
    end

    local tooltip = { lines = {}, shown = false, hooks = {} }
    env.GameTooltip = tooltip
    local function fire(scriptName)
        for _, hook in ipairs(tooltip.hooks[scriptName] or {}) do hook(tooltip) end
    end
    local supportedScripts = { OnHide = true, OnTooltipCleared = options.supportsCleared ~= false }
    function tooltip.HasScript(_, scriptName) return supportedScripts[scriptName] == true end
    function tooltip.HookScript(self, scriptName, hook)
        assert(supportedScripts[scriptName], "HookScript on unsupported script " .. scriptName)
        self.hooks[scriptName] = self.hooks[scriptName] or {}
        table.insert(self.hooks[scriptName], hook)
    end
    function tooltip.SetOwner(self, owner) self.owner = owner end
    function tooltip.GetOwner(self) return self.owner end
    function tooltip.IsOwned(self, owner) return self.owner == owner end
    function tooltip.IsShown(self) return self.shown end
    function tooltip.Hide(self)
        self.shown = false
        fire("OnHide")
    end
    function tooltip.AddLine(self, text) table.insert(self.lines, text) end
    function tooltip.SetItemByID(self, itemId)
        fire("OnTooltipCleared")
        self.lines = { "item " .. itemId }
        self.shown = true
    end
    function tooltip.SetSpellByID(self, spellId)
        state.setSpellCalls = state.setSpellCalls + 1
        fire("OnTooltipCleared")
        self.lines = { "spell " .. spellId }
        for _, postCall in ipairs(postCalls) do
            if postCall.type == env.Enum.TooltipDataType.Spell then postCall.fn(self, { id = spellId }) end
        end
        self.shown = true
    end

    -- mimics wt.CreateRecipeList: ScrollBox first, then WT's own Spell post-call
    function state.createWtList()
        env.WhatsTrainingCraftingScrollBox = newFrame(nil)
        state.scrollTarget = newFrame(env.WhatsTrainingCraftingScrollBox)
        env.TooltipDataProcessor.AddTooltipPostCall(env.Enum.TooltipDataType.Spell, function(tip, data)
            local owner = tip:GetOwner()
            if owner and owner.data and owner.data.recipe and owner.data.recipe.spell == data.id then
                tip:AddLine("WT: Sold in")
            end
        end)
    end
    function state.newRow(data) local row = newFrame(state.scrollTarget); row.data = data; return row end
    function state.hover(row)
        tooltip:SetOwner(row)
        tooltip:SetSpellByID(row.data.recipe.spell)
    end
    -- a click as the client delivers it: OnClick (set by WT), then PostClick hooks
    function state.click(row, button, modifiers)
        state.modifiers = modifiers or {}
        if row.scripts.OnClick then row.scripts.OnClick(row, button) end
        for _, hook in ipairs(row.hooks.PostClick or {}) do hook(row, button, false) end
        state.modifiers = {}
    end
    function state.lastMenu() return state.menus[#state.menus] end

    if options.wtListFirst then state.createWtList() end

    -- load the addon, then fire its ADDON_LOADED
    local ns = {}
    for _, file in ipairs(ADDON_FILES) do
        local chunk = assert(loadfile(file))
        setfenv(chunk, env)
        chunk("LocateVendor", ns)
    end
    for _, frame in ipairs(frames) do
        if frame.scripts.OnEvent then frame.scripts.OnEvent(frame, "ADDON_LOADED", "LocateVendor") end
    end

    state.env, state.ns, state.tooltip, state.postCalls = env, ns, tooltip, postCalls
    return state
end

local function text(tooltip) return table.concat(tooltip.lines, "\n") end
local function indexOf(lines, needle)
    for i, line in ipairs(lines) do if line:find(needle, 1, true) then return i end end
end

-- recipe 6617 from WT's Camelot Alchemy data
local RECIPE_6617 = { spell = 6617, source = { "vendor" }, vendors = {
    { npc = 1669, area = 40 }, { npc = 1685, area = 38, faction = "Alliance" },
    { npc = 3335, area = 1637, faction = "Horde" }, { npc = 3499, area = 17 } } }
local RECIPE_HORDE_ONLY = { spell = 9001, source = { "vendor" }, vendors = {
    { npc = 2393, area = 267, faction = "Horde" }, { npc = 3335, area = 1637, faction = "Horde" } } }
local NAMES = {
    [1669] = "Пройдоха", [1685] = "Ксаварик", [3335] = "Хаградин", [3499] = "Раник", [2393] = "Кристоф Френч",
}

do -- registration order: our post-call runs after WT's, registered exactly once
    local client = newClient({ creatureNames = NAMES })
    check(#client.postCalls == 0, "nothing registered before the WT list exists")
    client.createWtList()
    check(#client.postCalls == 2, "one WT post-call plus exactly one of ours, got " .. #client.postCalls)
    client.env.TooltipDataProcessor.AddTooltipPostCall(client.env.Enum.TooltipDataType.Spell, function() end)
    check(#client.postCalls == 3, "later registrations by others do not add ours again")
    local row = client.newRow({ recipe = RECIPE_6617, sources = { "vendor" } })
    client.hover(row)
    local lines = client.tooltip.lines
    check(indexOf(lines, "WT: Sold in") < indexOf(lines, "Торговцы:"), "vendor lines come after WT lines")
end

do -- WT list already created before LocateVendor loads
    local client = newClient({ creatureNames = NAMES, wtListFirst = true })
    check(#client.postCalls == 2, "registered right at load, after WT's post-call")
    client.env.TooltipDataProcessor.AddTooltipPostCall(client.env.Enum.TooltipDataType.Spell, function() end)
    check(#client.postCalls == 3, "no hook-driven second registration")
    client.hover(client.newRow({ recipe = RECIPE_6617, sources = { "vendor" } }))
    local lines = client.tooltip.lines
    check(indexOf(lines, "WT: Sold in") < indexOf(lines, "Торговцы:"), "order kept when WT list came first")
end

do -- player faction filter and names resolved on the first query
    local client = newClient({ creatureNames = NAMES })
    client.createWtList()
    local row = client.newRow({ recipe = RECIPE_6617, sources = { "vendor" } })
    client.hover(row)
    local shown = text(client.tooltip)
    check(shown:find("Пройдоха", 1, true) and shown:find("Ксаварик", 1, true) and shown:find("Раник", 1, true),
        "neutral and Alliance vendors shown")
    check(not shown:find("Хаградин", 1, true) and not client.queries[3335], "Horde vendor hidden and never queried")
end

do -- other-faction recipe shows only that faction's vendors, labelled
    local client = newClient({ creatureNames = NAMES })
    client.createWtList()
    local row = client.newRow({ recipe = RECIPE_HORDE_ONLY, sources = { "vendor" }, otherFactionSource = "Horde" })
    client.hover(row)
    local shown = text(client.tooltip)
    check(shown:find("Кристоф Френч", 1, true) and shown:find("(Орда)", 1, true), "other-faction vendors labelled")
    local mixed = client.newRow({ recipe = RECIPE_6617, sources = { "vendor" }, otherFactionSource = "Horde" })
    client.hover(mixed)
    shown = text(client.tooltip)
    check(shown:find("Хаградин", 1, true) and not shown:find("Раник", 1, true), "only the matching faction")
end

do -- no vendor source, unknown otherFactionSource, foreign tooltip owner
    local client = newClient({ creatureNames = NAMES })
    client.createWtList()
    client.hover(client.newRow({ recipe = RECIPE_6617, sources = { "quest" } }))
    check(not text(client.tooltip):find("Торговцы:", 1, true), "no lines when WT dropped the vendor source")
    client.hover(client.newRow({ recipe = RECIPE_6617, sources = { "vendor" }, otherFactionSource = "Альянс" }))
    check(not text(client.tooltip):find("Торговцы:", 1, true), "no lines for an unknown otherFactionSource")
    local stranger = { data = { recipe = RECIPE_6617, sources = { "vendor" } }, GetParent = function() return nil end }
    client.tooltip:SetOwner(stranger)
    client.tooltip:SetSpellByID(6617)
    check(not text(client.tooltip):find("Торговцы:", 1, true), "ignores frames outside the WT list")
end

do -- async name: fallback, one refresh, no duplicate requests, independent updates
    local client = newClient({ creatureNames = NAMES, nameDelayQueries = { [1669] = 1, [3499] = 2 } })
    client.createWtList()
    local row = client.newRow({ recipe = RECIPE_6617, sources = { "vendor" } })
    client.hover(row)
    local shown = text(client.tooltip)
    check(shown:find("NPC #1669", 1, true) and shown:find("NPC #3499", 1, true), "fallback label while loading")
    check(#client.tooltip.lines == 6, "spell, WT line, header and three vendors, no duplicates")
    local callsBefore = client.setSpellCalls
    client.hover(row) -- hovering again while pending must not start new requests
    check(client.queries[1669] == 1 and client.queries[3499] == 1, "no parallel request on re-hover")
    client.advance(0.5)
    client.advance(0) -- run the coalesced refresh
    shown = text(client.tooltip)
    check(shown:find("Пройдоха", 1, true) and shown:find("NPC #3499", 1, true), "first name arrives on its own")
    check(client.setSpellCalls == callsBefore + 2, "exactly one refresh for the first name")
    check(client.queries[1669] == 2 and client.queries[3499] == 2, "refresh did not trigger extra queries")
    client.advance(1)
    client.advance(0)
    check(text(client.tooltip):find("Раник", 1, true), "second name arrives independently")
    check(client.queries[3499] == 3, "three attempts at most")
    check(#client.tooltip.lines == 6, "still no duplicated lines after refreshes")
end

do -- three failures keep the fallback forever this session
    local client = newClient({ creatureNames = {} })
    client.createWtList()
    local row = client.newRow({ recipe = RECIPE_6617, sources = { "vendor" } })
    client.hover(row)
    client.advance(10)
    check(client.queries[1669] == 3, "exactly three attempts, got " .. tostring(client.queries[1669]))
    client.hover(row)
    client.advance(10)
    check(client.queries[1669] == 3, "no further attempts after failure")
    check(text(client.tooltip):find("NPC #1669", 1, true), "fallback stays")
end

do -- A -> B -> A: only the context of the current generation may refresh
    local client = newClient({ creatureNames = NAMES, nameDelayQueries = { [1669] = 1 } })
    client.createWtList()
    local recipeA = client.newRow({ recipe = RECIPE_6617, sources = { "vendor" } })
    local recipeB = client.newRow({ recipe = RECIPE_HORDE_ONLY, sources = { "quest" } })
    client.hover(recipeA)
    client.hover(recipeB)
    client.hover(recipeA)
    check(client.queries[1669] == 1, "returning to A does not start a second request")
    local calls = client.setSpellCalls
    client.advance(0.5) -- the late answer to the very first request arrives
    client.advance(0) -- next frame: the scheduled refresh runs
    check(client.setSpellCalls == calls + 1, "exactly one refresh, made for the current show of A")
    check(text(client.tooltip):find("Пройдоха", 1, true), "current A shows the name")
end

do -- A -> B, then the late answer: no refresh, but the name is cached
    local client = newClient({ creatureNames = NAMES, nameDelayQueries = { [1669] = 1 } })
    client.createWtList()
    local recipeA = client.newRow({ recipe = RECIPE_6617, sources = { "vendor" } })
    local recipeB = client.newRow({ recipe = RECIPE_HORDE_ONLY, sources = { "quest" } })
    client.hover(recipeA)
    client.hover(recipeB)
    local calls = client.setSpellCalls
    client.advance(1)
    check(client.setSpellCalls == calls, "no refresh after moving to another recipe")
    check(text(client.tooltip) == "spell 9001\nWT: Sold in", "B tooltip untouched")
    client.hover(recipeA)
    check(text(client.tooltip):find("Пройдоха", 1, true) and client.queries[1669] == 2,
        "name came from the cache on the next show")
end

do -- same owner, different content: the cleared tooltip is a new generation
    local client = newClient({ creatureNames = NAMES, nameDelayQueries = { [1669] = 1 } })
    client.createWtList()
    local recipeA = client.newRow({ recipe = RECIPE_6617, sources = { "vendor" } })
    client.hover(recipeA)
    client.tooltip:SetItemByID(5631) -- owner is still row A
    local calls = client.setSpellCalls
    client.advance(1)
    check(client.setSpellCalls == calls and text(client.tooltip) == "item 5631", "item tooltip left alone")
end

do -- content changes between scheduling a refresh and the next frame
    local client = newClient({ creatureNames = NAMES, nameDelayQueries = { [1669] = 1 } })
    client.createWtList()
    local recipeA = client.newRow({ recipe = RECIPE_6617, sources = { "vendor" } })
    client.hover(recipeA)
    client.advance(0.5) -- the name arrives; the refresh waits for the next frame
    client.tooltip:SetItemByID(5631) -- same owner, new content, same frame
    local calls = client.setSpellCalls
    client.advance(0)
    check(client.setSpellCalls == calls and text(client.tooltip) == "item 5631",
        "a scheduled refresh is dropped when its generation is gone")
end

do -- hidden tooltip and pooled row reuse
    local client = newClient({ creatureNames = NAMES, nameDelayQueries = { [1669] = 1, [3499] = 1 } })
    client.createWtList()
    local recipeA = client.newRow({ recipe = RECIPE_6617, sources = { "vendor" } })
    client.hover(recipeA)
    client.tooltip:Hide()
    local calls = client.setSpellCalls
    client.advance(1)
    check(client.setSpellCalls == calls, "no refresh after the tooltip was hidden")

    local reused = newClient({ creatureNames = NAMES, nameDelayQueries = { [1669] = 1 } })
    reused.createWtList()
    local row = reused.newRow({ recipe = RECIPE_6617, sources = { "vendor" } })
    reused.hover(row)
    row.data = { recipe = RECIPE_HORDE_ONLY, sources = { "vendor" } } -- pool reuse without a rebuild
    calls = reused.setSpellCalls
    reused.advance(1)
    check(reused.setSpellCalls == calls, "no refresh when the row now holds another recipe")
end

do -- clients without OnTooltipCleared still get generation checks from Render and OnHide
    local client = newClient({ creatureNames = NAMES, nameDelayQueries = { [1669] = 1 }, supportsCleared = false })
    client.createWtList()
    local recipeA = client.newRow({ recipe = RECIPE_6617, sources = { "vendor" } })
    local recipeB = client.newRow({ recipe = RECIPE_HORDE_ONLY, sources = { "quest" } })
    client.hover(recipeA)
    client.hover(recipeB)
    local calls = client.setSpellCalls
    client.advance(1)
    check(client.setSpellCalls == calls, "no refresh after moving on, without OnTooltipCleared")
end

do -- cache persists per locale and resets on build change
    local db = {}
    local client = newClient({ creatureNames = NAMES, savedDB = db })
    client.createWtList()
    client.hover(client.newRow({ recipe = RECIPE_6617, sources = { "vendor" } }))
    db = client.env.LocateVendorDB
    check(db.npcNames.locales.ruRU[1685] == "Ксаварик", "name cached under the locale")
    local again = newClient({ creatureNames = {}, savedDB = db })
    again.createWtList()
    again.hover(again.newRow({ recipe = RECIPE_6617, sources = { "vendor" } }))
    check(text(again.tooltip):find("Ксаварик", 1, true) and not again.queries[1685], "cached name used without query")
    local patched = newClient({ creatureNames = {}, savedDB = db, build = "72000" })
    patched.createWtList()
    patched.hover(patched.newRow({ recipe = RECIPE_6617, sources = { "vendor" } }))
    check(text(patched.tooltip):find("NPC #1685", 1, true), "cache dropped after a build change")
    local english = newClient({ creatureNames = {}, savedDB = again.env.LocateVendorDB, locale = "enUS" })
    english.createWtList()
    english.hover(english.newRow({ recipe = RECIPE_6617, sources = { "vendor" } }))
    check(text(english.tooltip):find("NPC #1685", 1, true), "other locale has its own cache")
end

-- Milestone 2: vendor menu and waypoints ------------------------------------------------

-- recipe 7443 from WT's Camelot Enchanting data; 1318 (Jessara Cordell) is the only vendor with coordinates
local RECIPE_7443 = { spell = 7443, source = { "vendor" }, vendors = {
    { npc = 1318, area = 1519, faction = "Alliance" }, { npc = 3012, area = 1638, faction = "Horde" },
    { npc = 3346, area = 1637, faction = "Horde" }, { npc = 4228, area = 1657, faction = "Alliance" },
    { npc = 4617, area = 1497, faction = "Horde" }, { npc = 5158, area = 1537, faction = "Alliance" },
    { npc = 5695, area = 85, faction = "Horde" }, { npc = 5757, area = 130, faction = "Horde" },
    { npc = 5758, area = 130, faction = "Horde" }, { npc = 15419, area = 1377 },
    { npc = 257004, area = 16593 }, { npc = 257020, area = 16593 } } }
local RECIPE_JESSARA_ONLY = { spell = 9101, source = { "vendor" }, vendors = { { npc = 1318, area = 1519 } } }
local RECIPE_ONE_NO_COORDS = { spell = 9102, source = { "vendor" }, vendors = { { npc = 1685, area = 38 } } }
local ENCHANTING_NAMES = { [1318] = "Джессара Корделл", [4228] = "Вина", [5158] = "Тилли",
    [15419] = "Кания", [257004] = "Зефир", [257020] = "Бриз", [1685] = "Ксаварик" }

local function buttons(menu)
    local list = {}
    for _, entry in ipairs(menu.entries) do
        if entry.kind == "button" then table.insert(list, entry) end
    end
    return list
end

local function setupRow(client, recipe, extra)
    client.createWtList()
    local data = { recipe = recipe, sources = { "vendor" }, name = "Рецепт " .. recipe.spell }
    for key, value in pairs(extra or {}) do data[key] = value end
    local row = client.newRow(data)
    client.hover(row)
    return row
end

do -- several vendors, one with coordinates: hint, menu, waypoint to the chosen vendor
    local client = newClient({ creatureNames = ENCHANTING_NAMES })
    local row = setupRow(client, RECIPE_7443)
    local shown = text(client.tooltip)
    check(shown:find("ЛКМ: выбрать торговца", 1, true), "menu hint shown")
    check(shown:find("INV_Misc_Map_01", 1, true) and select(2, shown:gsub("INV_Misc_Map_01", "")) == 1,
        "map icon only on the vendor with coordinates")
    client.click(row, "LeftButton")
    local menu = client.lastMenu()
    check(menu and menu.entries[1].kind == "title" and menu.entries[1].text == "Рецепт 7443", "menu titled by recipe")
    local entries = buttons(menu)
    check(#entries == 6, "all six Alliance and neutral vendors listed, got " .. #entries)
    check(entries[1].enabled and entries[1].text:find("Джессара Корделл — Штормград", 1, true),
        "navigable vendor first and enabled")
    local disabled = 0
    for index = 2, #entries do
        if not entries[index].enabled and entries[index].text:find("(координаты не собраны)", 1, true)
            and entries[index].text:find("|cff808080", 1, true) then
            disabled = disabled + 1
        end
    end
    check(disabled == 5, "five vendors without coordinates are visible, greyed, marked and disabled")
    check(#client.tomtom:list() == 0, "opening the menu places nothing")
    entries[1].callback()
    local waypoints = client.tomtom:list()
    check(#waypoints == 1, "choosing the vendor places one waypoint")
    local uid = waypoints[1]
    check(uid[1] == 1453 and math.abs(uid[2] - 0.5301) < 1e-9 and math.abs(uid[3] - 0.7421) < 1e-9,
        "waypoint at Jessara Cordell's verified point")
    check(uid.title == "Джессара Корделл — Штормград" and uid.from == "LocateVendor", "waypoint title and source")
    check(client.sounds == 1, "click sound played")
end

do -- one vendor with coordinates: a click places the waypoint without a menu
    local client = newClient({ creatureNames = ENCHANTING_NAMES })
    local row = setupRow(client, RECIPE_JESSARA_ONLY)
    check(text(client.tooltip):find("ЛКМ: поставить метку", 1, true), "waypoint hint shown")
    client.click(row, "LeftButton")
    check(#client.menus == 0 and #client.tomtom:list() == 1, "direct waypoint, no menu")
end

do -- nothing to navigate to: no hint and clicks do nothing
    local single = newClient({ creatureNames = ENCHANTING_NAMES })
    local row = setupRow(single, RECIPE_ONE_NO_COORDS)
    check(not text(single.tooltip):find("ЛКМ", 1, true), "no hint for a single vendor without coordinates")
    single.click(row, "LeftButton")
    check(#single.menus == 0 and #single.tomtom:list() == 0, "single vendor without coordinates: nothing")

    local several = newClient({ creatureNames = NAMES })
    row = setupRow(several, RECIPE_6617)
    check(not text(several.tooltip):find("ЛКМ", 1, true), "no hint when no vendor has coordinates")
    several.click(row, "LeftButton")
    check(#several.menus == 0 and #several.tomtom:list() == 0, "several vendors without coordinates: nothing")
end

do -- without TomTom there is no hint and no action
    local client = newClient({ creatureNames = ENCHANTING_NAMES, tomtom = false })
    local row = setupRow(client, RECIPE_7443)
    check(not text(client.tooltip):find("ЛКМ", 1, true), "no hint without TomTom")
    client.click(row, "LeftButton")
    check(#client.menus == 0, "no menu without TomTom")
    check(text(client.tooltip):find("INV_Misc_Map_01", 1, true), "coordinates are still marked in the tooltip")
end

do -- modified clicks and right clicks stay with WT
    local client = newClient({ creatureNames = ENCHANTING_NAMES })
    local row = setupRow(client, RECIPE_JESSARA_ONLY)
    client.click(row, "LeftButton", { shift = true })
    client.click(row, "LeftButton", { ctrl = true })
    client.click(row, "LeftButton", { alt = true })
    client.click(row, "RightButton")
    check(#client.tomtom:list() == 0 and #client.menus == 0, "modifiers and right button ignored")
end

do -- PostClick is hooked once per row frame
    local client = newClient({ creatureNames = ENCHANTING_NAMES })
    local row = setupRow(client, RECIPE_JESSARA_ONLY)
    client.hover(row)
    client.hover(row)
    check(#(row.hooks.PostClick or {}) == 1, "one PostClick hook after several tooltips")
    client.click(row, "LeftButton")
    check(#client.tomtom:list() == 1, "one click places one waypoint")
end

do -- the action is decided by the row's data at click time
    local client = newClient({ creatureNames = ENCHANTING_NAMES })
    local row = setupRow(client, RECIPE_JESSARA_ONLY)
    row.data = { recipe = RECIPE_ONE_NO_COORDS, sources = { "vendor" } } -- pooled row now shows another recipe
    client.click(row, "LeftButton")
    check(#client.tomtom:list() == 0, "no waypoint from stale tooltip state")
end

do -- only LocateVendor's own waypoint is ever replaced
    local client = newClient({ creatureNames = ENCHANTING_NAMES })
    local row = setupRow(client, RECIPE_JESSARA_ONLY)
    local userWaypoint = client.tomtom:AddWaypoint(1429, 0.4, 0.6, { title = "My spot" })
    local otherAddon = client.tomtom:AddWaypoint(1453, 0.5301, 0.7421, { title = "Same spot", from = "Other" })
    client.click(row, "LeftButton")
    client.click(row, "LeftButton")
    client.click(row, "LeftButton")
    local own = 0
    for _, uid in ipairs(client.tomtom:list()) do
        if uid.from == "LocateVendor" then own = own + 1 end
    end
    check(own == 1, "one LocateVendor waypoint after repeated clicks, got " .. own)
    check(client.tomtom.waypoints[userWaypoint] and client.tomtom.waypoints[otherAddon],
        "player and other addon waypoints untouched")
    -- TomTom dropped ours on arrival; the next click must not touch anything else
    for uid in pairs(client.tomtom.waypoints) do
        if uid.from == "LocateVendor" then client.tomtom.waypoints[uid] = nil end
    end
    client.click(row, "LeftButton")
    check(#client.tomtom:list() == 3, "after arrival: new waypoint added, others intact")
end

do -- menu choice replaces the previous own waypoint too
    local client = newClient({ creatureNames = ENCHANTING_NAMES })
    local single = setupRow(client, RECIPE_JESSARA_ONLY)
    client.click(single, "LeftButton")
    local several = client.newRow({ recipe = RECIPE_7443, sources = { "vendor" }, name = "x" })
    client.hover(several)
    client.click(several, "LeftButton")
    buttons(client.lastMenu())[1].callback()
    check(#client.tomtom:list() == 1, "menu waypoint replaced the direct one")
end

do -- other-faction vendors are navigable when WT shows their recipe
    local client = newClient({ creatureNames = ENCHANTING_NAMES, faction = "Horde" })
    local row = setupRow(client, { spell = 9103, source = { "vendor" }, vendors = {
        { npc = 1318, area = 1519, faction = "Alliance" }, { npc = 4228, area = 1657, faction = "Alliance" } } },
        { otherFactionSource = "Alliance" })
    client.click(row, "LeftButton")
    local entries = buttons(client.lastMenu())
    check(entries[1].enabled and entries[1].text:find("Штормград (Альянс)", 1, true), "other-faction vendor labelled")
    entries[1].callback()
    check(#client.tomtom:list() == 1, "waypoint to an other-faction vendor")
end

do -- menus without SetEnabled still mark unavailable vendors and ignore their clicks
    local client = newClient({ creatureNames = ENCHANTING_NAMES, noSetEnabled = true })
    local row = setupRow(client, RECIPE_7443)
    client.click(row, "LeftButton")
    local entries = buttons(client.lastMenu())
    check(entries[2].text:find("(координаты не собраны)", 1, true), "marked without SetEnabled")
    entries[2].callback()
    check(#client.tomtom:list() == 0, "clicking an unavailable vendor does nothing")
end

do -- invalid coordinates count as missing
    local client = newClient({ creatureNames = ENCHANTING_NAMES })
    local data = client.ns.VendorData
    data[1685] = { uiMapId = 1432, x = 150, y = 20 }
    data[4228] = { uiMapId = 0, x = 40, y = 40 }
    data[5158] = { uiMapId = 1455, x = 40 }
    data[15419] = { uiMapId = 14.5, x = 40, y = 40 }
    data[257004] = { uiMapId = 1453, x = 0, y = 50 }
    local get = client.ns.Coordinates.Get
    check(not get(1685) and not get(4228) and not get(5158) and not get(15419) and not get(257004),
        "out-of-range, zero map, missing axis, fractional map and edge values rejected")
    check(get(1318) == 1453, "verified entry accepted")
end

print(string.format("%d passed, %d failed", passed, failures))
os.exit(failures == 0 and 0 or 1)

local _, ns = ...

local strings = {
    enUS = {
        VENDORS_HEADER = "Vendors:",
        NPC_FALLBACK = "NPC #%d",
        UNKNOWN_ZONE = "Unknown zone",
        FACTION_Alliance = "Alliance",
        FACTION_Horde = "Horde",
        HINT_WAYPOINT = "Click: set a waypoint",
        HINT_MENU = "Click: choose a vendor",
        NO_COORDINATES = "coordinates not collected",
    },
    ruRU = {
        VENDORS_HEADER = "Торговцы:",
        NPC_FALLBACK = "NPC #%d",
        UNKNOWN_ZONE = "Неизвестная зона",
        FACTION_Alliance = "Альянс",
        FACTION_Horde = "Орда",
        HINT_WAYPOINT = "ЛКМ: поставить метку",
        HINT_MENU = "ЛКМ: выбрать торговца",
        NO_COORDINATES = "координаты не собраны",
    },
}

-- missing keys in a locale fall back to enUS
ns.L = setmetatable(strings[GetLocale()] or {}, { __index = strings.enUS })

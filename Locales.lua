local _, ns = ...

local strings = {
    enUS = {
        VENDORS_HEADER = "Vendors:",
        NPC_FALLBACK = "NPC #%d",
        UNKNOWN_ZONE = "Unknown zone",
        FACTION_Alliance = "Alliance",
        FACTION_Horde = "Horde",
    },
    ruRU = {
        VENDORS_HEADER = "Торговцы:",
        NPC_FALLBACK = "NPC #%d",
        UNKNOWN_ZONE = "Неизвестная зона",
        FACTION_Alliance = "Альянс",
        FACTION_Horde = "Орда",
    },
}

-- missing keys in a locale fall back to enUS
ns.L = setmetatable(strings[GetLocale()] or {}, { __index = strings.enUS })

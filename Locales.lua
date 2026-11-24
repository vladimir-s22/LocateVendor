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
        WANDERING = "moves around",

        HELP = "/lv collect: turn coordinate collection on or off; /lv status: collection summary",
        COLLECT_ENABLED = "coordinate collection is on: open vendor windows to record their positions",
        COLLECT_DISABLED = "coordinate collection is off",
        COLLECT_ON_LOGIN = "coordinate collection is on (/lv collect to turn it off)",
        STATE_ON = "on",
        STATE_OFF = "off",
        STATUS = "collection: %s; vendors: %d (usable points: %d, in instances: %d, with conflicts: %d)",
        SKIP_NOT_NPC = "this merchant is not an NPC, skipped",
        SKIP_NO_RECIPES = "%s (%d): sells no recipes, skipped",
        SKIPPED = "%s (%d): skipped, %s",
        SKIP_NO_MAP = "no map for the current position",
        SKIP_MAP_TYPE = "map type %s is not a zone",
        SKIP_NO_POSITION = "no position on the map",
        RECORDED_NEW = "recorded %s (%d): %s %.2f, %.2f; recipes: %d",
        RECORDED_MERGED = "%s (%d): sample %d, point %.2f, %.2f (%.1f yd from the saved point)",
        RECORDED_INSTANCE = "%s (%d): inside an instance, recipes recorded (%d), no coordinates",
        CONFLICT_MAP = "conflict: %s (%d) was seen on another map; the saved point is unchanged",
        CONFLICT_UNVERIFIED = "conflict: %s (%d), the distance to the saved point cannot be confirmed;"
            .. " the saved point is unchanged",
        CONFLICT_FAR = "conflict: %s (%d) is %.1f yd from the saved point; the saved point is unchanged",
        VERIFIED_CLOSE = "%s (%d): verified point kept; this sample is %.2f map units from it",
        VERIFIED_FAR = "%s (%d): this sample is %.2f map units from the verified point, please check;"
            .. " verified point kept",
        VERIFIED_OTHER_MAP = "%s (%d): the verified point is on map %d, this sample on map %d;"
            .. " verified point kept",
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
        WANDERING = "перемещается",

        HELP = "/lv collect: включить или выключить сбор координат; /lv status: сводка сбора",
        COLLECT_ENABLED = "сбор координат включён: открывайте окна торговцев, чтобы записать их позиции",
        COLLECT_DISABLED = "сбор координат выключен",
        COLLECT_ON_LOGIN = "сбор координат включён (/lv collect, чтобы выключить)",
        STATE_ON = "вкл",
        STATE_OFF = "выкл",
        STATUS = "сбор: %s; торговцев: %d (точек для меток: %d, в подземельях: %d, с конфликтами: %d)",
        SKIP_NOT_NPC = "торговец не является NPC, пропущен",
        SKIP_NO_RECIPES = "%s (%d): рецептов не продаёт, пропущен",
        SKIPPED = "%s (%d): пропущен, %s",
        SKIP_NO_MAP = "нет карты для текущей позиции",
        SKIP_MAP_TYPE = "тип карты %s, а не зона",
        SKIP_NO_POSITION = "нет позиции на карте",
        RECORDED_NEW = "записан %s (%d): %s %.2f, %.2f; рецептов: %d",
        RECORDED_MERGED = "%s (%d): замер %d, точка %.2f, %.2f (%.1f ярд. от сохранённой)",
        RECORDED_INSTANCE = "%s (%d): в подземелье, рецепты записаны (%d), координаты не сохраняются",
        CONFLICT_MAP = "конфликт: %s (%d) замечен на другой карте; сохранённая точка не изменена",
        CONFLICT_UNVERIFIED = "конфликт: %s (%d), расстояние до сохранённой точки не подтверждено;"
            .. " сохранённая точка не изменена",
        CONFLICT_FAR = "конфликт: %s (%d) в %.1f ярд. от сохранённой точки; сохранённая точка не изменена",
        VERIFIED_CLOSE = "%s (%d): проверенная точка не изменена; замер отличается от неё на %.2f ед. карты",
        VERIFIED_FAR = "%s (%d): замер в %.2f ед. карты от проверенной точки, проверьте;"
            .. " проверенная точка не изменена",
        VERIFIED_OTHER_MAP = "%s (%d): проверенная точка на карте %d, замер на карте %d;"
            .. " проверенная точка не изменена",
    },
}

-- missing keys in a locale fall back to enUS
ns.L = setmetatable(strings[GetLocale()] or {}, { __index = strings.enUS })

std = "lua51"
max_line_length = 120

read_globals = {
    -- api functions
    "CreateFrame",
    "GetBuildInfo",
    "GetItemInfoInstant",
    "GetLocale",
    "GetMerchantItemID",
    "GetMerchantItemLink",
    "GetMerchantNumItems",
    "GetMouseFoci",
    "GetMouseFocus",
    "GetRealZoneText",
    "GetSubZoneText",
    "IsAltKeyDown",
    "IsControlKeyDown",
    "IsInInstance",
    "IsShiftKeyDown",
    "PlaySound",
    "UnitFactionGroup",
    "UnitGUID",
    "UnitName",
    "UnitPosition",
    "time",
    "geterrorhandler",
    "hooksecurefunc",

    -- function aliases
    "date",
    "strsplit",
    "tinsert",
    "tremove",

    -- namespaces
    "C_Item",
    "C_Map",
    "C_Timer",
    "C_TooltipInfo",
    "MenuUtil",
    "TooltipDataProcessor",

    -- enums and constants
    "Enum",
    "LE_ITEM_CLASS_RECIPE",
    "SOUNDKIT",
    "UNKNOWNOBJECT",
    "WOW_PROJECT_ID",

    -- blizzard frames
    "GameTooltip",
    "UIParent",

    -- other addons
    "TomTom",
    "WT_API",
    "WT_WaypointProvider",
    "WhatsTrainingCraftingScrollBox",
}

globals = {
    "LocateVendorDB",
    "SLASH_LOCATEVENDOR1",
    "SLASH_LOCATEVENDOR2",
    "SlashCmdList",
}

files["tools/LocateVendorProbe/"] = {
    globals = {
        "LocateVendorProbeLog",
        "SLASH_LOCATEVENDORPROBE1",
    },
}

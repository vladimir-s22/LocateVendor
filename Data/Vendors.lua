-- Vendor positions verified in-game on WoW Forever.
-- uiMapId comes from C_Map.GetBestMapForUnit at the vendor; x and y are map coordinates (0-100).
-- Add a point only after it was recorded at the vendor and a waypoint to it was confirmed in-game.
local _, ns = ...

ns.VendorData = {
    -- Jessara Cordell, Stormwind; recorded by the probe and confirmed by waypoint on 2026-11-25
    [1318] = { uiMapId = 1453, x = 53.01, y = 74.21 },
}

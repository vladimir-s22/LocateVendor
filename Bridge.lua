-- The only file that knows What's Training? internals:
--   WhatsTrainingCraftingScrollBox  global ScrollBox of the Forever recipe list (created lazily by WT)
--   row.data.recipe                 recipe record of a row, including vendors
--   row.data.sources, .otherFactionSource  WT's availability decisions for the row
--   row OnClick                     WT sets it with SetScript on every row init; a plain left click does nothing
local _, ns = ...

local Bridge = {}
ns.Bridge = Bridge

local registered = false
local hooked = false
local onRecipeTooltip, onRecipeClick
-- rows that already carry our PostClick hook; weak keys so pooled frames are never pinned
local trackedRows = setmetatable({}, { __mode = "k" })

local function recipeScrollBox()
    return _G.WhatsTrainingCraftingScrollBox
end

local function recipeData(row)
    local data = type(row) == "table" and row.data
    if type(data) == "table" and type(data.recipe) == "table" then return data end
    return nil
end

-- PostClick survives WT's SetScript("OnClick") and runs after WT's own click handling
local function onPostClick(row, button)
    local data = recipeData(row)
    if data and onRecipeClick then onRecipeClick(row, data, button) end
end

local function trackRow(row)
    if trackedRows[row] or type(row.HookScript) ~= "function" then return end
    trackedRows[row] = true
    row:HookScript("PostClick", onPostClick)
end

-- Returns the row frame and its data when the tooltip belongs to a WT recipe row for spellId.
function Bridge.GetRecipeRow(tooltip, spellId)
    if tooltip ~= GameTooltip then return nil end
    local scrollBox = recipeScrollBox()
    local owner = tooltip:GetOwner()
    if not scrollBox or type(owner) ~= "table" then return nil end
    local data = recipeData(owner)
    if not data or data.recipe.spell ~= spellId then return nil end
    -- rows live on the ScrollBox's ScrollTarget; anything else that happens to carry .data is ignored
    local parent = owner.GetParent and owner:GetParent()
    while parent and parent ~= scrollBox do parent = parent:GetParent() end
    if not parent then return nil end
    return owner, data
end

-- Whether the row still shows the recipe it showed when a tooltip was built from it.
function Bridge.RowShowsSpell(row, spellId)
    local data = recipeData(row)
    return data ~= nil and data.recipe.spell == spellId
end

-- The mouse always passes over a row, building its tooltip, before the row can be clicked,
-- so rows get their click hook the first time their tooltip is built.
local function spellPostCall(tooltip, tooltipData)
    local row, data = Bridge.GetRecipeRow(tooltip, tooltipData and tooltipData.id)
    if not row then return end
    trackRow(row)
    onRecipeTooltip(tooltip, tooltipData, row, data)
end

-- Registers our Spell post-call once, and only after WT registered its own: WT creates the
-- ScrollBox right before calling AddTooltipPostCall inside wt.CreateRecipeList, so our lines
-- follow WT's. Registration never happens while a tooltip is being processed.
local function tryRegister()
    if registered or not recipeScrollBox() then return end
    registered = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, spellPostCall)
end

-- tooltipHandler(tooltip, tooltipData, row, data) runs after WT's handler for WT recipe rows.
-- clickHandler(row, data, button) runs after WT's click handling of a recipe row.
-- Returns false when the client lacks the tooltip API, in which case nothing is hooked.
function Bridge.Start(tooltipHandler, clickHandler)
    if hooked or registered then return true end
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell) then
        return false
    end
    onRecipeTooltip, onRecipeClick = tooltipHandler, clickHandler
    tryRegister()
    if not registered then
        hooked = true
        hooksecurefunc(TooltipDataProcessor, "AddTooltipPostCall", function(tooltipType)
            if tooltipType == Enum.TooltipDataType.Spell then tryRegister() end
        end)
    end
    return true
end

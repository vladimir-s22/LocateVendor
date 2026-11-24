-- The only file that knows What's Training? internals:
--   WhatsTrainingCraftingScrollBox  global ScrollBox of the Forever recipe list (created lazily by WT)
--   row.data.recipe                 recipe record of a row, including vendors
--   row.data.sources, .otherFactionSource  WT's availability decisions for the row
local _, ns = ...

local Bridge = {}
ns.Bridge = Bridge

local registered = false
local hooked = false
local spellPostCall

local function recipeScrollBox()
    return _G.WhatsTrainingCraftingScrollBox
end

-- Registers our Spell post-call once, and only after WT registered its own: WT creates the
-- ScrollBox right before calling AddTooltipPostCall inside wt.CreateRecipeList, so our lines
-- follow WT's. Registration never happens while a tooltip is being processed.
local function tryRegister()
    if registered or not recipeScrollBox() then return end
    registered = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, spellPostCall)
end

-- Returns the row frame and its data when the tooltip belongs to a WT recipe row for spellId.
function Bridge.GetRecipeRow(tooltip, spellId)
    if tooltip ~= GameTooltip then return nil end
    local scrollBox = recipeScrollBox()
    local owner = tooltip:GetOwner()
    if not scrollBox or type(owner) ~= "table" then return nil end
    local data = owner.data
    if type(data) ~= "table" or type(data.recipe) ~= "table" or data.recipe.spell ~= spellId then return nil end
    -- rows live on the ScrollBox's ScrollTarget; anything else that happens to carry .data is ignored
    local parent = owner.GetParent and owner:GetParent()
    while parent and parent ~= scrollBox do parent = parent:GetParent() end
    if not parent then return nil end
    return owner, data
end

-- Whether the row still shows the recipe it showed when a tooltip was built from it.
function Bridge.RowShowsSpell(row, spellId)
    local data = type(row) == "table" and row.data
    return type(data) == "table" and type(data.recipe) == "table" and data.recipe.spell == spellId
end

-- postCall(tooltip, tooltipData) runs for every Spell tooltip after WT's handler.
-- Returns false when the client lacks the tooltip API, in which case nothing is hooked.
function Bridge.Start(postCall)
    if hooked or registered then return true end
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell) then
        return false
    end
    spellPostCall = postCall
    tryRegister()
    if not registered then
        hooked = true
        hooksecurefunc(TooltipDataProcessor, "AddTooltipPostCall", function(tooltipType)
            if tooltipType == Enum.TooltipDataType.Spell then tryRegister() end
        end)
    end
    return true
end

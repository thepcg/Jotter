local addonName, Jotter = ...

local MINIMAP_ICON_PATH = "Interface\\AddOns\\Jotter\\Textures\\Jotter_Minimap_Icon_32_CircleMask_Desaturated"

local MINIMAP_BUTTON_NAME = "JotterMinimapButton"

-- Optional: starting angle in radians (0 is to the right, Pi/2 is up)
local Jotter_MinimapAngle = math.rad(45)

-----------------------------------------------------------------------
-- Helper functions - adjust frame names if yours differ
-----------------------------------------------------------------------

-- Main UI toggle - assumes your main frame is called JotterMainFrame
local function Jotter_ToggleMainUI()
    local f = JotterMainFrame
    if not f then return end

    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end

-- Config opener - use the existing editor window
local function Jotter_OpenConfig()
    if Jotter and Jotter.ToggleEditor then
        Jotter:ToggleEditor()
    end
end


-----------------------------------------------------------------------
-- Minimap positioning helpers
-----------------------------------------------------------------------

local function Jotter_Minimap_UpdatePosition(btn)
    if not Minimap then return end

    local radius = (Minimap:GetWidth() / 2) + 5  -- small offset to sit outside a bit
    local x = math.cos(Jotter_MinimapAngle) * radius
    local y = math.sin(Jotter_MinimapAngle) * radius

    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function Jotter_Minimap_OnUpdate(self)
    if not Minimap then return end

    local mx, my = Minimap:GetCenter()
    if not mx or not my then return end

    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px = px / scale
    py = py / scale

    -- Calculate angle from minimap center to cursor
    Jotter_MinimapAngle = math.atan2(py - my, px - mx)

    Jotter_Minimap_UpdatePosition(self)
end

-----------------------------------------------------------------------
-- Minimap button scripts
-----------------------------------------------------------------------

local function Jotter_Minimap_OnClick(self, button)
    if button == "LeftButton" then
        if IsControlKeyDown() then
            Jotter_OpenConfig()
        else
            Jotter_ToggleMainUI()
        end
    end
end



local function Jotter_Minimap_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Jotter", 1, 1, 1)

    GameTooltip:AddLine("Click - Show or hide Jotter", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Ctrl-Click - Open configuration", 0.9, 0.9, 0.9)

    GameTooltip:Show()
end

local function Jotter_Minimap_OnLeave(self)
    GameTooltip:Hide()
end

local function Jotter_Minimap_OnDragStart(self)
    self:SetScript("OnUpdate", Jotter_Minimap_OnUpdate)
end

local function Jotter_Minimap_OnDragStop(self)
    self:SetScript("OnUpdate", nil)
end

-----------------------------------------------------------------------
-- Creation
-----------------------------------------------------------------------

function Jotter_CreateMinimapButton()
    if _G[MINIMAP_BUTTON_NAME] then
        return
    end

    local btn = CreateFrame("Button", MINIMAP_BUTTON_NAME, Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MINIMAP_ICON_PATH)
    icon:SetAllPoints(btn)

    -- Drag support
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", Jotter_Minimap_OnDragStart)
    btn:SetScript("OnDragStop", Jotter_Minimap_OnDragStop)

    -- Mouse and tooltip
    btn:SetScript("OnClick", Jotter_Minimap_OnClick)
    btn:SetScript("OnEnter", Jotter_Minimap_OnEnter)
    btn:SetScript("OnLeave", Jotter_Minimap_OnLeave)

    -- Initial position around the minimap
    Jotter_Minimap_UpdatePosition(btn)
end

-----------------------------------------------------------------------
-- Hook into ADDON_LOADED
-----------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, name)
    if name == addonName then
        Jotter_CreateMinimapButton()
    end
end)

local addonName, Jotter = ...

-----------------------------------------------------------------------
-- Minimap button configuration (saved outside JotterDB for simplicity)
-----------------------------------------------------------------------
local MINIMAP_BUTTON_NAME = "JotterMinimapButton"

Jotter_MinimapAngle = Jotter_MinimapAngle or 225 -- degrees

-----------------------------------------------------------------------
-- Toggle helpers
-----------------------------------------------------------------------
local function Jotter_ToggleMainUI()
    if not Jotter or not Jotter.mainFrame then return end
    if Jotter.mainFrame:IsShown() then
        Jotter:SetMainVisible(false, "user")
    else
        Jotter:SetMainVisible(true, "user")
        Jotter:RefreshList()
    end
end

local function Jotter_OpenConfig()
    if Jotter and Jotter.ToggleConfig then
        Jotter:ToggleConfig()
    end
end

-----------------------------------------------------------------------
-- Minimap positioning helpers
-----------------------------------------------------------------------
local function Jotter_Minimap_UpdatePosition(self)
    local angle = Jotter_MinimapAngle or 225
    local rad = math.rad(angle)

    -- Keep the button outside the minimap ring. Use a dynamic radius so it works
    -- for different minimap sizes and UI scales.
    local radius = (Minimap:GetWidth() / 2) + 10

    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    self:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function Jotter_Minimap_OnUpdate(self)
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = UIParent:GetScale()
    px, py = px / scale, py / scale

    Jotter_MinimapAngle = math.deg(math.atan2(py - my, px - mx))
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
    elseif button == "RightButton" then
        if Jotter and Jotter.ToggleEditor then
            Jotter:ToggleEditor()
        end
    end
end

local function Jotter_Minimap_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Jotter", 1, 1, 1)
    GameTooltip:AddLine("Left Click - Toggle main window", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Right Click - Open editor", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Ctrl-Click - Open configuration", 0.9, 0.9, 0.9)
    GameTooltip:Show()
end

local function Jotter_Minimap_OnLeave()
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
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("AnyUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)
    btn:EnableMouse(true)

    btn:SetScript("OnClick", Jotter_Minimap_OnClick)
    btn:SetScript("OnEnter", Jotter_Minimap_OnEnter)
    btn:SetScript("OnLeave", Jotter_Minimap_OnLeave)
    btn:SetScript("OnDragStart", Jotter_Minimap_OnDragStart)
    btn:SetScript("OnDragStop", Jotter_Minimap_OnDragStop)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(Jotter.ICON_PATH or 134400)
    icon:SetAllPoints(btn)
    btn.icon = icon

    Jotter_Minimap_UpdatePosition(btn)
end

-- Create minimap button after UI is ready
C_Timer.After(1, function()
    if Jotter_CreateMinimapButton then
        Jotter_CreateMinimapButton()
    end
end)

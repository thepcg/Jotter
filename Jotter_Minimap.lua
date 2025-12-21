--[[
Jotter
Repository: https://github.com/thepcg/Jotter
Author: Edag
License: MIT

Copyright (c) 2025 Edag

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local addonName, Jotter = ...

-----------------------------------------------------------------------
-- Minimap button (persisted in JotterDB.settings.minimap)
-----------------------------------------------------------------------
local MINIMAP_BUTTON_NAME = "JotterMinimapButton"

local function GetMiniSettings()
    if not Jotter or not Jotter.db or not Jotter.db.settings then return nil end
    Jotter.db.settings.minimap = Jotter.db.settings.minimap or {}
    local mm = Jotter.db.settings.minimap
    if mm.angle == nil then mm.angle = 225 end
    if mm.hide == nil then mm.hide = false end
    return mm
end

-----------------------------------------------------------------------
-- Toggle helpers
-----------------------------------------------------------------------
local function Jotter_ToggleMainUI()
    if not Jotter or not Jotter.mainFrame then return end
    if Jotter.mainFrame:IsShown() then
        Jotter:SetMainVisible(false, "user")
    else
        Jotter:SetMainVisible(true, "user")
        if Jotter.UpdateZone then
            Jotter:UpdateZone()
        end
    end
end

-----------------------------------------------------------------------
-- Positioning
-----------------------------------------------------------------------
local function Jotter_Minimap_UpdatePosition(btn)
    if not btn then return end
    local mm = GetMiniSettings()
    local angle = (mm and mm.angle) or 225
    if angle < 0 then angle = angle + 360 end

    -- Radius tuned to keep the button sitting just outside the minimap ring.
    -- Users can still drag it anywhere around the minimap; this just controls
    -- the distance from the minimap center.
    local radius = (Minimap:GetWidth() / 2) + 12

    local rad = math.rad(angle)
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-----------------------------------------------------------------------
-- Drag
-----------------------------------------------------------------------
local function Jotter_Minimap_OnDragStart(self)
    self:LockHighlight()
    self.isMoving = true

    -- Update position while dragging.
    self:SetScript("OnUpdate", function(btn)
        if not btn.isMoving then return end

        local mm = GetMiniSettings()
        if not mm then return end

        local cursorX, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cursorX, cursorY = cursorX / scale, cursorY / scale

        local mx, my = Minimap:GetCenter()
        local dx, dy = cursorX - mx, cursorY - my

        -- Update angle and snap the button back to the configured radius.
        local angle = math.deg(math.atan2(dy, dx))
        if angle < 0 then angle = angle + 360 end
        mm.angle = angle
        Jotter_Minimap_UpdatePosition(btn)
    end)
end

local function Jotter_Minimap_OnDragStop(self)
    self:UnlockHighlight()
    self.isMoving = false

    -- Stop live updates.
    self:SetScript("OnUpdate", nil)

    -- Final snap (angle already updated during drag).
    Jotter_Minimap_UpdatePosition(self)
end

-----------------------------------------------------------------------
-- Create
-----------------------------------------------------------------------
function Jotter_CreateMinimapButton()
    if _G[MINIMAP_BUTTON_NAME] then
        local btn = _G[MINIMAP_BUTTON_NAME]
        Jotter_Minimap_UpdatePosition(btn)
        return
    end

    local mm = GetMiniSettings()
    if mm and mm.hide then
        return
    end

    local btn = CreateFrame("Button", MINIMAP_BUTTON_NAME, Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Allow dragging with either button (people often right-drag minimap buttons).
    btn:RegisterForDrag("LeftButton", "RightButton")

    btn:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            Jotter_ToggleMainUI()
        elseif button == "RightButton" then
            if IsShiftKeyDown() then
                if Jotter and Jotter.ToggleEditor then
                    Jotter:ToggleEditor()
                end
            else
                if Jotter and Jotter.ToggleConfig then
                    Jotter:ToggleConfig()
                end
            end
        end
    end)

    btn:SetScript("OnDragStart", Jotter_Minimap_OnDragStart)
    btn:SetScript("OnDragStop", Jotter_Minimap_OnDragStop)

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Jotter", 1, 1, 1)
        GameTooltip:AddLine("Left Click: Show/Hide", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Right Click: Options", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Shift + Right Click: Notes Editor", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Drag: Move", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)


    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(Jotter.ICON_PATH or 134400)
    icon:SetAllPoints(btn)
    btn.icon = icon

    Jotter_Minimap_UpdatePosition(btn)
end

-- Create minimap button after DB is ready
local function TryCreate()
    if not Jotter or not Jotter.db or not Jotter.db.settings then
        C_Timer.After(0.5, TryCreate)
        return
    end
    Jotter_CreateMinimapButton()
end

C_Timer.After(0.5, TryCreate)

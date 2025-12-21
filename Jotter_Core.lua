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
Jotter = Jotter or {}
_G.Jotter = Jotter -- handy for /dump Jotter

-- Shared icon path for minimap, main UI, editor, and config
Jotter.ICON_PATH = "Interface\\AddOns\\Jotter\\Textures\\Jotter_Minimap_Icon_32_CircleMask_Desaturated"

--------------------------------------------------------------
-- Shared constants (layout helpers, not hard rules)
--------------------------------------------------------------
Jotter.maxEditorRows   = 20
Jotter.rowHeightMain   = 18
Jotter.rowGapMain      = 2

--------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------
function Jotter.Trim(str)
    if str == nil then return "" end
    str = tostring(str)
    return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Jotter.GetCurrentZoneName()
    -- Retail: GetZoneText() is reliable for display name
    local z = GetZoneText()
    return Jotter.Trim(z)
end

local Trim = Jotter.Trim
local GetCurrentZoneName = Jotter.GetCurrentZoneName

local function Bool(v) return v and true or false end

----

function Jotter:DebugPrint(...)
    if self.db and self.db.settings and self.db.settings.debug then
        print("|cff00ff99Jotter(debug):|r", ...)
    end
end
----------------------------------------------------------
-- SavedVariables defaults
--------------------------------------------------------------
local DEFAULTS = {
    notes = {},
    settings = {
        -- Existing
        useCurrentZoneByDefault = true,  -- Quick-add box uses current zone if enabled
        hideCompletedOnMain     = false, -- If enabled, completed notes are hidden on the main UI

        -- hide while in combat (default ON)
        hideInCombat            = true,

        -- lockable + resizable main UI
        lockMainWindow          = false,
        mainVisible             = true,
        mainFrame = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
            width = 260,
            height = 220,
        },

        -- Editor + Config window persistence
        editorVisible = false,
        editorFrame = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
            width = 740,
            height = 460,
        },

        configVisible = false,
        configFrame = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
            width = 480,
            height = 520,
        },

        -- Minimap button persistence
        minimap = {
            angle = 225,
            hide  = false,
        },

        -- Debug logging toggle (off by default)
        debug = false,
        -- categories
        categoryOrder     = {},  -- array of category names in desired order
        categoryCollapsed = {},  -- map: [categoryName] = true if collapsed
    }
}

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local t = {}
    for k, v in pairs(src) do
        t[k] = DeepCopy(v)
    end
    return t
end

local function MergeDefaults(dst, defaults)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(defaults) do
        if dst[k] == nil then
            dst[k] = DeepCopy(v)
        elseif type(v) == "table" then
            dst[k] = MergeDefaults(dst[k], v)
        end
    end
    return dst
end

local function NormalizeCategoryName(cat)
    cat = Trim(cat or "")
    if cat == "" then return "" end
    return cat
end

function Jotter:GetNoteCategory(note)
    local cat = NormalizeCategoryName(note and note.category or "")
    if cat == "" then
        return "Uncategorized"
    end
    return cat
end

function Jotter:EnsureCategoryInOrder(categoryName)
    local settings = self.db and self.db.settings
    if not settings then return end

    categoryName = Trim(categoryName or "")
    if categoryName == "" then
        categoryName = "Uncategorized"
    end

    settings.categoryOrder = settings.categoryOrder or {}
    for _, existing in ipairs(settings.categoryOrder) do
        if existing == categoryName then
            return
        end
    end
    table.insert(settings.categoryOrder, categoryName)
end

local function InitDB()
    JotterDB = JotterDB or {}
    JotterDB = MergeDefaults(JotterDB, DEFAULTS)

    -- Migrate/normalize each note
    for _, note in ipairs(JotterDB.notes) do
        if note.zone == nil then note.zone = "" end
        if note.description == nil then note.description = "" end
        if note.done == nil then note.done = false end
        if note.text == nil then note.text = "" end
        if note.coords == nil then note.coords = "" end
        if note.category == nil then note.category = "" end -- 
    end

    -- Ensure "Uncategorized" is always part of ordering once we see any categories
    JotterDB.settings.categoryOrder = JotterDB.settings.categoryOrder or {}
    JotterDB.settings.categoryCollapsed = JotterDB.settings.categoryCollapsed or {}

    Jotter.db = JotterDB
end

--------------------------------------------------------------
-- Coordinates parsing + waypoint support
--------------------------------------------------------------
local function Jotter_ParseCoordsString(coordsStr)
    coordsStr = Trim(coordsStr or "")
    if coordsStr == "" then return nil end

    -- Accept: "12.3, 45.6" or "12.3 45.6" or "12 45"
    local a, b = coordsStr:match("^(%d+%.?%d*)%s*[, ]%s*(%d+%.?%d*)$")
    if not a or not b then return nil end

    local x = tonumber(a)
    local y = tonumber(b)
    if not x or not y then return nil end
    return x, y
end

function Jotter:CreateWaypointForNote(note)
    if not note then return end
    local coordsStr = Trim(note.coords or "")
    if coordsStr == "" then return end

    local x, y = Jotter_ParseCoordsString(coordsStr)
    if not x or not y then
        print("|cff00ff99Jotter:|r Could not parse coordinates: " .. coordsStr)
        return
    end

    local zoneName    = Trim(note.zone or "")
    local currentZone = self.currentZone or GetCurrentZoneName()

    -- Current implementation only supports the current zone (simple + reliable).
    if zoneName ~= "" and zoneName ~= currentZone then
        print("|cff00ff99Jotter:|r Waypoints are currently only supported in your current zone: " .. currentZone)
        return
    end

    local uiMapID = C_Map.GetBestMapForUnit("player")
    if not uiMapID then
        print("|cff00ff99Jotter:|r Could not determine current map.")
        return
    end

    local mapX = x / 100.0
    local mapY = y / 100.0
    if mapX < 0 then mapX = 0 end
    if mapY < 0 then mapY = 0 end
    if mapX > 1 then mapX = 1 end
    if mapY > 1 then mapY = 1 end

    local point = UiMapPoint and UiMapPoint.CreateFromCoordinates and UiMapPoint.CreateFromCoordinates(uiMapID, mapX, mapY)
    if not point then
        print("|cff00ff99Jotter:|r Failed to create waypoint.")
        return
    end

    C_Map.SetUserWaypoint(point)
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
end

--------------------------------------------------------------
-- Main UI visibility helpers
--------------------------------------------------------------
Jotter._combatHidden = false
Jotter._wasVisibleBeforeCombat = false
Jotter._userHidden = false -- set when user explicitly hides/closes main UI

function Jotter:SetMainVisible(visible, reason)
    if not self.mainFrame then return end
    visible = Bool(visible)

    -- Track explicit user intent so we don't "pop" the window back unexpectedly.
    if reason == "user" then
        self._userHidden = not visible
        if self.db and self.db.settings then
            self.db.settings.mainVisible = visible
        end
    end

    if visible then
        self.mainFrame:Show()
    else
        self.mainFrame:Hide()
    end
end

function Jotter:IsMainVisible()
    return self.mainFrame and self.mainFrame:IsShown()
end

--------------------------------------------------------------
-- Zone update (used by the main UI)
--------------------------------------------------------------
function Jotter:UpdateZone()
    self.currentZone = GetCurrentZoneName()
    if self.zoneText then
        self.zoneText:SetText(self.currentZone or "")
    end

    -- Refresh list to reflect current zone, but do NOT auto-hide if empty.
    if self.RefreshList then
        self:RefreshList()
    end

end
--------------------------------------------------------------
-- Event handling
--------------------------------------------------------------
function Jotter:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= addonName then return end

        InitDB()

        self:CreateMainFrame()
        -- Editor and config frames are created lazily when first opened.
        -- This keeps login/UI reload a bit lighter.

        self:UpdateZone()

-- Restore persisted window visibility (main/editor/config)
if self.db and self.db.settings then
    -- Main
    local wantMain = self.db.settings.mainVisible
    if wantMain == nil then wantMain = true end
    self._userHidden = not wantMain
    self:SetMainVisible(wantMain, "restore")

    -- Editor/Config are lazily created. Restore after a short delay so UI is fully ready.
    C_Timer.After(0, function()
        if not Jotter or not Jotter.db or not Jotter.db.settings then return end
        if Jotter.db.settings.editorVisible then
            Jotter:ToggleEditor(true)
        end
        if Jotter.db.settings.configVisible then
            Jotter:ToggleConfig()
        end
    end)
end


    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_NEW_AREA" then

        self:UpdateZone()

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Hide while in combat (respect prior user intent)
        if self.db and self.db.settings and self.db.settings.hideInCombat and self.mainFrame then
            self._wasVisibleBeforeCombat = self:IsMainVisible() and (not self._userHidden)
            if self._wasVisibleBeforeCombat then
                self._combatHidden = true
                self:SetMainVisible(false, "combat")
            end
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if self._combatHidden then
            self._combatHidden = false
            if self.db and self.db.settings and self.db.settings.hideInCombat then
                -- Only restore if it was visible prior to combat AND user didn't explicitly hide it.
                if self._wasVisibleBeforeCombat and (not self._userHidden) then
                    self:SetMainVisible(true, "combat")
                end
            end
            self._wasVisibleBeforeCombat = false
        end
elseif event == "PLAYER_LOGOUT" then
    if self.db and self.db.settings then
        -- Persist visibility state (positions are already saved on drag/resize)
        if self.mainFrame then
            self.db.settings.mainVisible = self.mainFrame:IsShown() and true or false
        end
        if self.editorFrame then
            self.db.settings.editorVisible = self.editorFrame:IsShown() and true or false
        end
        if self.configFrame then
            self.db.settings.configVisible = self.configFrame:IsShown() and true or false
        end
    end

    end
end

function Jotter:Init()
    self.frame = CreateFrame("Frame")
    self.frame:SetScript("OnEvent", function(_, event, ...)
        Jotter:OnEvent(event, ...)
    end)

    self.frame:RegisterEvent("ADDON_LOADED")
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.frame:RegisterEvent("ZONE_CHANGED")
    self.frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

    -- 
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.frame:RegisterEvent("PLAYER_LOGOUT")
end

--------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------
SLASH_JOTTER1 = "/jotter"
SlashCmdList["JOTTER"] = function(msg)
    msg = Trim(msg or "")
    if msg == "editor" or msg == "edit" then
        Jotter:ToggleEditor()
    elseif msg == "config" or msg == "options" then
        Jotter:ToggleConfig()
    elseif msg == "show" then
        Jotter:SetMainVisible(true, "user")
    elseif msg == "hide" then
        Jotter:SetMainVisible(false, "user")
    elseif msg == "debug" then
        if Jotter.db and Jotter.db.settings then
            Jotter.db.settings.debug = not (Jotter.db.settings.debug and true or false)
            print("|cff00ff99Jotter:|r Debug is now " .. (Jotter.db.settings.debug and "ON" or "OFF"))
        end
    else
        print("|cff00ff99Jotter:|r /jotter show, /jotter hide, /jotter editor, /jotter config, /jotter debug")
    end
end

--------------------------------------------------------------
-- Kick off
--------------------------------------------------------------
Jotter:Init()

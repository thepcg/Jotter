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

--------------------------------------------------------------
-- SavedVariables defaults + migration
--------------------------------------------------------------
local DEFAULTS = {
    todos = {},
    settings = {
        -- Existing
        useCurrentZoneByDefault = true,  -- Quick-add box uses current zone if enabled
        hideCompletedOnMain     = false, -- If enabled, completed todos are hidden on the main UI

        -- Feature 2: hide while in combat (default ON)
        hideInCombat            = true,

        -- Feature 5: lockable + resizable main UI
        lockMainWindow          = false,
        mainFrame = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
            width = 260,
            height = 220,
        },

        -- Feature 3: categories
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

function Jotter:GetTodoCategory(todo)
    local cat = NormalizeCategoryName(todo and todo.category or "")
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

    -- Migrate/normalize each todo
    for _, todo in ipairs(JotterDB.todos) do
        if todo.zone == nil then todo.zone = "" end
        if todo.description == nil then todo.description = "" end
        if todo.done == nil then todo.done = false end
        if todo.text == nil then todo.text = "" end
        if todo.coords == nil then todo.coords = "" end
        if todo.category == nil then todo.category = "" end -- Feature 3
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

function Jotter:CreateWaypointForTodo(todo)
    if not todo then return end
    local coordsStr = Trim(todo.coords or "")
    if coordsStr == "" then return end

    local x, y = Jotter_ParseCoordsString(coordsStr)
    if not x or not y then
        print("|cff00ff99Jotter:|r Could not parse coordinates: " .. coordsStr)
        return
    end

    local zoneName    = Trim(todo.zone or "")
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
        self:CreateEditorFrame()
        self:CreateConfigFrame()

        self:UpdateZone()

    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_NEW_AREA" then

        self:UpdateZone()

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Feature 2: Hide while in combat (respect prior user intent)
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

    -- Feature 2
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
    else
        print("|cff00ff99Jotter:|r /jotter show, /jotter hide, /jotter editor, /jotter config")
    end
end

--------------------------------------------------------------
-- Kick off
--------------------------------------------------------------
Jotter:Init()

local addonName, Jotter = ...
Jotter = Jotter or {}
_G.Jotter = Jotter   -- handy for /dump Jotter

-- Shared icon path for minimap, main UI, and config
Jotter.ICON_PATH = "Interface\\AddOns\\Jotter\\Textures\\Jotter_Minimap_Icon_32_CircleMask_Desaturated"


--------------------------------------------------------------
-- Shared config
--------------------------------------------------------------
Jotter.maxDisplayRows = 40
Jotter.maxEditorRows = 20
Jotter.rowHeightMain = 18
Jotter.rowGapMain = 2

--------------------------------------------------------------
-- Utils
--------------------------------------------------------------
function Jotter.Trim(str)
    if not str then return "" end
    return str:match("^%s*(.-)%s*$")
end

local Trim = Jotter.Trim

function Jotter.GetCurrentZoneName()
    local name = GetRealZoneText() or GetZoneText() or ""
    return name
end

local GetCurrentZoneName = Jotter.GetCurrentZoneName

-- Parse a coordinate string like "45, 62" or "45.3 62.8" into numeric x, y
local function Jotter_ParseCoordsString(str)
    if not str then return nil, nil end
    str = Trim(str)
    if str == "" then return nil, nil end

    -- Common "x, y" format
    local x, y = str:match("(%d+%.?%d*)%s*[, ]%s*(%d+%.?%d*)")
    if not x or not y then
        -- Fallback: first two numbers in the string
        local nums = {}
        for num in str:gmatch("(%d+%.?%d*)") do
            nums[#nums + 1] = num
            if #nums >= 2 then break end
        end
        if #nums >= 2 then
            x, y = nums[1], nums[2]
        end
    end

    x, y = tonumber(x), tonumber(y)
    if not x or not y then return nil, nil end

    -- We treat values > 1 as "percent" style 0-100 coordinates
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

    -- For now, only set waypoints in the current zone
    if zoneName ~= "" and zoneName ~= currentZone then
        print("|cff00ff99Jotter:|r Waypoints are currently only supported in your current zone: " .. currentZone)
        return
    end

    if not C_Map or not C_Map.GetBestMapForUnit then
        print("|cff00ff99Jotter:|r Map APIs are not available.")
        return
    end

    local uiMapID = C_Map.GetBestMapForUnit("player")
    if not uiMapID then
        print("|cff00ff99Jotter:|r Unable to determine current map for waypoint.")
        return
    end

    if C_Map.CanSetUserWaypoint and not C_Map.CanSetUserWaypointOnMap(uiMapID) then
        print("|cff00ff99Jotter:|r Waypoints are not supported on this map.")
        return
    end

    if not C_Map.SetUserWaypoint or not C_SuperTrack or not C_SuperTrack.SetSuperTrackedUserWaypoint then
        print("|cff00ff99Jotter:|r Waypoint APIs are not available in this client.")
        return
    end

    -- Convert 0-100 style coords into 0-1 map coords if needed
    local mapX, mapY = x, y
    if x > 1 or y > 1 then
        if x > 100 then x = 100 end
        if y > 100 then y = 100 end
        mapX = x / 100.0
        mapY = y / 100.0
    end

    local point = UiMapPoint and UiMapPoint.CreateFromCoordinates and UiMapPoint.CreateFromCoordinates(uiMapID, mapX, mapY)
    if not point then
        print("|cff00ff99Jotter:|r Failed to create waypoint.")
        return
    end

    C_Map.SetUserWaypoint(point)
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)

    print(string.format("|cff00ff99Jotter:|r Waypoint set to %.1f, %.1f in %s.", x, y, currentZone))
end


--------------------------------------------------------------
-- Saved variables init
--------------------------------------------------------------
local function InitDB()
    JotterDB = JotterDB or {}
    local db = JotterDB

    db.todos = db.todos or {
        {
            text        = "Welcome to Jotter. Type a todo and press Enter.",
            done        = false,
            zone        = "",
            description = "",
            coords      = "",   -- NEW
        },
    }

    db.framePos = db.framePos or { point = "CENTER", x = 0, y = 0 }

    db.settings = db.settings or {}
    if db.settings.useCurrentZoneByDefault == nil then
        db.settings.useCurrentZoneByDefault = false
    end
    if db.settings.hideCompletedOnMain == nil then
        db.settings.hideCompletedOnMain = false
    end

    for _, todo in ipairs(db.todos) do
        if todo.zone == nil then todo.zone = "" end
        if todo.description == nil then todo.description = "" end
        if todo.done == nil then todo.done = false end
        if todo.text == nil then todo.text = "" end
        if todo.coords == nil then todo.coords = "" end   -- NEW
    end

    Jotter.db = db
end


--------------------------------------------------------------
-- Zone update used by the main UI
--------------------------------------------------------------
function Jotter:UpdateZone()
    self.currentZone = GetCurrentZoneName()
    if self.zoneText then
        if self.currentZone and self.currentZone ~= "" then
            self.zoneText:SetText(self.currentZone)
        else
            self.zoneText:SetText("")
        end
    end
    self:RefreshList()
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
        self:UpdateZone()

    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_NEW_AREA" then

        self:UpdateZone()
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
end

--------------------------------------------------------------
-- Slash command
--------------------------------------------------------------
SLASH_JOTTER1 = "/jotter"
SlashCmdList["JOTTER"] = function(msg)
    msg = Trim(msg or "")
    if msg == "editor" or msg == "edit" then
        Jotter:ToggleEditor()
    elseif msg == "show" then
        if Jotter.mainFrame then Jotter.mainFrame:Show() end
    elseif msg == "hide" then
        if Jotter.mainFrame then Jotter.mainFrame:Hide() end
    else
        print("|cff00ff99Jotter:|r /jotter show, /jotter hide, /jotter editor")
    end
end

--------------------------------------------------------------
-- Kick off
--------------------------------------------------------------
Jotter:Init()

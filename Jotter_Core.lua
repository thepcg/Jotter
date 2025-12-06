local addonName, Jotter = ...
Jotter = Jotter or {}
_G.Jotter = Jotter   -- handy for /dump Jotter

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

--------------------------------------------------------------
-- Saved variables init
--------------------------------------------------------------
local function InitDB()
    JotterDB = JotterDB or {}
    local db = JotterDB

    db.todos = db.todos or {
        { text = "Welcome to Jotter. Type a todo and press Enter.", done = false, zone = "", description = "" },
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

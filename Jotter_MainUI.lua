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
local Trim = Jotter.Trim
local GetCurrentZoneName = Jotter.GetCurrentZoneName

--------------------------------------------------------------
-- Main UI (zone-aware list)
--------------------------------------------------------------
Jotter._mainWidgets = Jotter._mainWidgets or {
    headers = {},
    rows = {},
    active = {},
}

local function ApplyMainLockState()
    local f = Jotter.mainFrame
    if not f or not Jotter.db or not Jotter.db.settings then return end

    local locked = Jotter.db.settings.lockMainWindow and true or false
    f._locked = locked

    -- Update lock button icon
    if f._lockBtn and f._lockBtn._tex then
        if locked then
            f._lockBtn._tex:SetTexture("Interface\\AddOns\\Jotter\\Textures\\lock_locked.tga")
        else
            f._lockBtn._tex:SetTexture("Interface\\AddOns\\Jotter\\Textures\\lock_unlocked.tga")
        end
    end

    -- Locking should prevent moving/resizing, but the UI must remain interactive
    -- (checkboxes, click-to-edit, tooltips, etc.). So we do NOT disable mouse input
    -- on the frame. We only disable drag + sizing affordances.
    f:EnableMouse(true)

    if locked then
        f:SetMovable(false)
        f:RegisterForDrag() -- clears drag registration
        if f._resizeGrip then f._resizeGrip:Hide() end
    else
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        if f._resizeGrip then f._resizeGrip:Show() end
    end
end

local function SaveMainFramePositionAndSize()
    if not Jotter.db or not Jotter.db.settings or not Jotter.mainFrame then return end
    local f = Jotter.mainFrame
    local s = Jotter.db.settings.mainFrame

    local point, _, relativePoint, xOfs, yOfs = f:GetPoint(1)
    s.point = point
    s.relativePoint = relativePoint
    s.x = xOfs
    s.y = yOfs
    s.width = f:GetWidth()
    s.height = f:GetHeight()
end

local function RestoreMainFramePositionAndSize()
    if not Jotter.db or not Jotter.db.settings or not Jotter.mainFrame then return end
    local f = Jotter.mainFrame
    local s = Jotter.db.settings.mainFrame or {}

    local w = tonumber(s.width) or 260
    local h = tonumber(s.height) or 220
    if w < 220 then w = 220 end
    if h < 160 then h = 160 end

    f:SetSize(w, h)
    f:ClearAllPoints()
    f:SetPoint(s.point or "CENTER", UIParent, s.relativePoint or "CENTER", s.x or 0, s.y or 0)
end

local function EnsureCategoryOrderForVisibleNotes(notes)
    if not Jotter.db or not Jotter.db.settings then return end
    for _, note in ipairs(notes) do
        local cat = Jotter:GetNoteCategory(note)
        Jotter:EnsureCategoryInOrder(cat)
    end
end

local function BuildGroupsForZone(zoneName)
    local settings = Jotter.db and Jotter.db.settings
    if not settings then return {}, {} end

    local hideCompleted = settings.hideCompletedOnMain and true or false
    local notes = Jotter.db.notes or {}

    local groups = {}          -- map categoryName -> { indices = {...} }
    local categorySeen = {}    -- set
    local anyCategorized = false

    zoneName = Trim(zoneName or "")

    for i, note in ipairs(notes) do
        local noteZone = Trim(note.zone or "")
        if noteZone == zoneName then
            if (not hideCompleted) or (not note.done) then
                local cat = Jotter:GetNoteCategory(note)
                if cat ~= "Uncategorized" then anyCategorized = true end
                groups[cat] = groups[cat] or { indices = {} }
                table.insert(groups[cat].indices, i)
                categorySeen[cat] = true
            end
        end
    end

    if not anyCategorized then
        -- If nobody has categories, don't show the header group at all.
        -- Return a single implicit group "flat" handled by renderer.
        return groups, { __noCategories = true }
    end

    -- Make sure ordering includes any new categories
    local visibleNotes = {}
    for cat, g in pairs(groups) do
        for _, idx in ipairs(g.indices) do
            table.insert(visibleNotes, notes[idx])
        end
    end
    EnsureCategoryOrderForVisibleNotes(visibleNotes)

    -- Build ordered list
    local orderedCategories = {}
    local order = settings.categoryOrder or {}

    -- Always include ordered categories that are present in this zone
    for _, cat in ipairs(order) do
        if categorySeen[cat] then
            table.insert(orderedCategories, cat)
            categorySeen[cat] = nil
        end
    end
    -- Any remaining categories not in ordering yet (should be rare) go to the end
    do
        local remaining = {}
        for cat, _ in pairs(categorySeen) do
            table.insert(remaining, cat)
        end
        table.sort(remaining)
        for _, cat in ipairs(remaining) do
            table.insert(orderedCategories, cat)
        end
    end

    -- Keep Uncategorized last by default if present and not explicitly ordered
    -- (If the user moved it via ordering UI, it will be handled above.)
    -- Here we just avoid it being randomly earlier from map iteration.
    local function MoveToEnd(name)
        local pos
        for i, v in ipairs(orderedCategories) do
            if v == name then pos = i break end
        end
        if pos and pos < #orderedCategories then
            table.remove(orderedCategories, pos)
            table.insert(orderedCategories, name)
        end
    end
    MoveToEnd("Uncategorized")

    return groups, { orderedCategories = orderedCategories, __noCategories = false }
end

local function ReleaseAllWidgets()
    local w = Jotter._mainWidgets
    if not w then return end

    for _, obj in ipairs(w.active) do
        obj:Hide()
        obj:ClearAllPoints()
    end
    wipe(w.active)
end

local function AcquireHeader()
    local w = Jotter._mainWidgets
    local obj = table.remove(w.headers)
    if not obj then
        obj = CreateFrame("Button", nil, Jotter.listContent)
        obj:SetHeight(20)
        obj:SetNormalFontObject("GameFontNormal")
        obj:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        local fs = obj:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", 2, 0)
        fs:SetPoint("RIGHT", -18, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        obj.text = fs

        local arrow = obj:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(14, 14)
        arrow:SetPoint("RIGHT", -2, 0)
        obj.arrow = arrow

        obj:SetScript("OnClick", function(selfBtn)
            local cat = selfBtn.categoryName
            if not cat or not Jotter.db or not Jotter.db.settings then return end
            local collapsed = Jotter.db.settings.categoryCollapsed[cat] and true or false
            Jotter.db.settings.categoryCollapsed[cat] = not collapsed
            Jotter:RefreshList()
        end)
    end

    obj:Show()
    table.insert(w.active, obj)
    return obj
end

local function AcquireRow()
    local w = Jotter._mainWidgets
    local row = table.remove(w.rows)
    if not row then
        row = CreateFrame("Frame", nil, Jotter.listContent)
        row:SetHeight(Jotter.rowHeightMain)
        row:EnableMouse(true)

        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(16, 16)
        cb:SetPoint("LEFT", 0, 0)

        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 1)
        fs:SetPoint("RIGHT", -4, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetNonSpaceWrap(false)

        row.check = cb
        row.text = fs

        row:SetScript("OnEnter", function(selfRow)
            local idx = selfRow.noteIndex
            if not idx then return end
            local note = Jotter.db.notes[idx]
            if not note then return end

            GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
            GameTooltip:SetText(note.text or "", 1, 1, 1)

            local cat = Trim(note.category or "")
            if cat ~= "" then
                GameTooltip:AddLine("Category: " .. cat, 0.9, 0.9, 0.9)
            end

            local desc = Trim(note.description or "")
            if desc ~= "" then
                GameTooltip:AddLine(desc, 0.9, 0.9, 0.9, true)
            end

            local coords = Trim(note.coords or "")
            if coords ~= "" then
                GameTooltip:AddLine("Coords: " .. coords .. " (click note to set waypoint)", 0.7, 0.9, 1.0)
            end

            GameTooltip:AddLine("Right click + Shift: /say (or run /commands)", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)

        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row:SetScript("OnMouseUp", function(selfRow, button)
            local index = selfRow.noteIndex
            if not index then return end
            local note = Jotter.db.notes[index]
            if not note then return end

            if button == "LeftButton" then
                -- Primary UX:
                -- If coords exist, create a waypoint.
                -- Otherwise open the editor for fast edits.
                if Trim(note.coords or "") ~= "" then
                    Jotter:CreateWaypointForNote(note)
                else
                    Jotter.selectedNoteIndex = index
                    Jotter:ToggleEditor(true)
                end
            elseif button == "RightButton" and IsShiftKeyDown() then
                local desc = Trim(note.description or "")
                local sayText = desc ~= "" and desc or (note.text or "")
                sayText = Trim(sayText)
                if sayText ~= "" then
                    -- If the note starts with a slash, treat it like a chat command.
                    -- Example: /me points at %t
                    if sayText:sub(1, 1) == "/" and ChatFrame_OpenChat then
                        ChatFrame_OpenChat(sayText)
                        if ChatEdit_GetActiveWindow then
                            local editBox = ChatEdit_GetActiveWindow()
                            if editBox and editBox.SetText then
                                -- Ensure the edit box contains the slash command, then parse and send it.
                                editBox:SetText(sayText)
                                if ChatEdit_ParseText then
                                    ChatEdit_ParseText(editBox, 0)
                                end
                                if ChatEdit_SendText then
                                    ChatEdit_SendText(editBox, 0)
                                end
                                if ChatEdit_DeactivateChat then
                                    ChatEdit_DeactivateChat(editBox)
                                end
                            end
                        end
                    else
                        SendChatMessage(sayText, "SAY")
                    end
                end
            end
        end)

        cb:SetScript("OnClick", function(selfBtn)
            local parentRow = selfBtn:GetParent()
            local index = parentRow.noteIndex
            if not index then return end
            local note = Jotter.db.notes[index]
            if note then
                note.done = selfBtn:GetChecked() and true or false
                Jotter:RefreshList()
                -- Only refresh the editor if it's currently visible.
                if Jotter.editorFrame and Jotter.editorFrame:IsShown() then
                    Jotter:RefreshEditor()
                end
            end
        end)
    end

    row:Show()
    table.insert(w.active, row)
    return row
end

--------------------------------------------------------------
-- Frame creation
--------------------------------------------------------------
function Jotter:CreateMainFrame()
    if self.mainFrame then return end

    local f = CreateFrame("Frame", "JotterMainFrame", UIParent, "BackdropTemplate")
    self.mainFrame = f

    f:SetClampedToScreen(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(220, 160, 1200, 900)
    elseif f.SetMinResize then
        f:SetMinResize(220, 160)
    end

    -- Backdrop (WoW native-ish)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.92)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT", 2, -2)
    titleBar:SetPoint("TOPRIGHT", -2, -2)
    titleBar:SetHeight(22)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    titleBar:SetBackdropColor(0.12, 0.12, 0.12, 0.9)

    -- Icon
    local icon = titleBar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 4, 0)
    icon:SetTexture(Jotter.ICON_PATH or 134400)

    -- Title text
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetText("Jotter")

    -- Zone text (right side)
    -- This will be re-anchored after the Close button and lock hint are created,
    -- so it never overlaps the lock indicator.
    local zoneText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneText:SetPoint("RIGHT", -24, 0)
    zoneText:SetJustifyH("RIGHT")
    zoneText:SetText("")
    self.zoneText = zoneText

    -- Lock/Unlock button (replaces close button; minimap toggles visibility)
    local lockBtn = CreateFrame("Button", nil, titleBar)
    lockBtn:SetSize(18, 18)
    lockBtn:SetPoint("RIGHT", -4, 0)

    local lockTex = lockBtn:CreateTexture(nil, "ARTWORK")
    lockTex:SetAllPoints(lockBtn)
    lockBtn._tex = lockTex

    -- Zone text anchors between the title and the lock button.
    -- This prevents overlap and keeps the zone left-aligned.
    zoneText:ClearAllPoints()
    zoneText:SetPoint("LEFT", title, "RIGHT", 10, 0)
    zoneText:SetPoint("RIGHT", lockBtn, "LEFT", -8, 0)
    zoneText:SetJustifyH("LEFT")


    -- Keep a handle for state updates
    f._lockBtn = lockBtn

    lockBtn:SetScript("OnClick", function()
        if not Jotter.db or not Jotter.db.settings then return end
        Jotter.db.settings.lockMainWindow = not (Jotter.db.settings.lockMainWindow and true or false)
        ApplyMainLockState()
        SaveMainFramePositionAndSize()
    end)

    lockBtn:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOPRIGHT")
        if f._locked then
            GameTooltip:SetText("Unlock window")
        else
            GameTooltip:SetText("Lock window")
        end
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Dragging
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(selfFrame)
        if selfFrame._locked then return end
        selfFrame:StartMoving()
    end)
    f:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        SaveMainFramePositionAndSize()
    end)

    -- Resize grip
    local grip = CreateFrame("Button", nil, f)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetSize(16, 16)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        if f._locked then return end
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        SaveMainFramePositionAndSize()
        Jotter:RefreshList()
    end)
    f._resizeGrip = grip

    -- Quick add input
    local input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    input:SetAutoFocus(false)
    input:SetHeight(20)
    input:SetPoint("TOPLEFT", 10, -30)
    input:SetPoint("TOPRIGHT", -10, -30)
    input:SetText("Type a note and press Enter")

    input:SetScript("OnEditFocusGained", function(selfEdit)
        if selfEdit:GetText() == "Type a note and press Enter" then
            selfEdit:SetText("")
        end
    end)
    input:SetScript("OnEditFocusLost", function(selfEdit)
        if Trim(selfEdit:GetText()) == "" then
            selfEdit:SetText("Type a note and press Enter")
        end
    end)

    input:SetScript("OnEnterPressed", function(selfEdit)
        local text = Trim(selfEdit:GetText() or "")
        if text ~= "" and text ~= "Type a note and press Enter" then
            local zone = ""
            if Jotter.db.settings and Jotter.db.settings.useCurrentZoneByDefault then
                zone = Jotter.currentZone or GetCurrentZoneName()
            end

            -- Insert at top (global ordering remains stable across reloads)
            table.insert(Jotter.db.notes, 1, {
                text = text,
                done = false,
                zone = zone,
                description = "",
                coords = "",
                category = "",
            })

            -- Ensure we keep "Uncategorized" visible in ordering when categories exist later
            Jotter:EnsureCategoryInOrder("Uncategorized")

            Jotter:RefreshList()
            if Jotter.editorFrame and Jotter.editorFrame:IsShown() then
                Jotter:RefreshEditor()
            end
        end
        selfEdit:SetText("")
        selfEdit:SetFocus()
    end)

    self.inputBox = input

    -- Scrollable list area
    local scrollFrame = CreateFrame("ScrollFrame", "JotterListScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -58)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)
    self.listScrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetPoint("TOPLEFT", 0, 0)
    content:SetPoint("TOPRIGHT", 0, 0)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    self.listContent = content

    scrollFrame:SetScript("OnSizeChanged", function(_, width, _)
        content:SetWidth(width)
    end)

    -- Empty state label
    local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", 4, -4)
    empty:SetPoint("RIGHT", -4, 0)
    empty:SetJustifyH("LEFT")
    empty:SetText("No notes for this zone.")
    empty:Hide()
    self.emptyLabel = empty

    -- Restore saved position/size and apply lock state
    RestoreMainFramePositionAndSize()
    ApplyMainLockState()

    self:RefreshList()
end

--------------------------------------------------------------
-- Public API for other files
--------------------------------------------------------------
function Jotter:ApplyMainFrameLockState()
    ApplyMainLockState()
end

--------------------------------------------------------------
-- Main list rendering
--------------------------------------------------------------
function Jotter:RefreshList()
    if not self.mainFrame or not self.listContent or not self.db then return end

    local zone = self.currentZone or GetCurrentZoneName()
    zone = Trim(zone)

    ReleaseAllWidgets()

    local groups, meta = BuildGroupsForZone(zone)
    local anyNotes = false

    local yOffset = -2
    local anchorTo = self.listContent

    local function AnchorNext(widget, height)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", 0, yOffset)
        widget:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT", 0, yOffset)
        yOffset = yOffset - height
    end

    if meta.__noCategories then
        -- Flat list (no category headers)
        local indices = (groups["Uncategorized"] and groups["Uncategorized"].indices) or {}
        for _, noteIndex in ipairs(indices) do
            anyNotes = true
            local note = self.db.notes[noteIndex]
            local row = AcquireRow()
            AnchorNext(row, self.rowHeightMain + self.rowGapMain)

            row.noteIndex = noteIndex
            row.check:SetChecked(note.done and true or false)

            local text = note.text or ""
            if note.done then
                row.text:SetText("|cff888888" .. text .. "|r")
            else
                row.text:SetText(text)
            end
        end
    else
        local ordered = meta.orderedCategories or {}
        for _, cat in ipairs(ordered) do
            local g = groups[cat]
            if g and g.indices and #g.indices > 0 then
                anyNotes = true

                local header = AcquireHeader()
                header.categoryName = cat

                local collapsed = self.db.settings.categoryCollapsed[cat] and true or false
                header.text:SetText(cat)

                if collapsed then
                    header.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
                else
                    header.arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
                end

                AnchorNext(header, 20 + 2)

                if not collapsed then
                    for _, noteIndex in ipairs(g.indices) do
                        local note = self.db.notes[noteIndex]
                        local row = AcquireRow()
                        AnchorNext(row, self.rowHeightMain + self.rowGapMain)

                        row.noteIndex = noteIndex
                        row.check:SetChecked(note.done and true or false)

                        local text = note.text or ""
                        if note.done then
                            row.text:SetText("|cff888888" .. text .. "|r")
                        else
                            row.text:SetText(text)
                        end
                    end
                end
            end
        end
    end

    -- Content height
    local contentHeight = (-yOffset) + 6
    if contentHeight < 1 then contentHeight = 1 end
    self.listContent:SetHeight(contentHeight)

    -- do not auto-hide when empty. Show an empty state instead.
    if not anyNotes then
        self.emptyLabel:Show()
        self.emptyLabel:SetText("No notes for this zone.")
    else
        self.emptyLabel:Hide()
    end

    -- Visibility: only hide if user explicitly hid it (close button, slash hide, minimap).
    -- RefreshList should never hide the window.
end

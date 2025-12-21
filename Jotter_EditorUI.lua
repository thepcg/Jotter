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

Jotter.editorRows = Jotter.editorRows or {}

--------------------------------------------------------------
-- Shared: build category list from current notes
--------------------------------------------------------------
local function GetAllCategoryNames()
    local seen = {}
    local list = {}

    local notes = (Jotter.db and Jotter.db.notes) or {}
    for _, note in ipairs(notes) do
        local cat = Trim(note.category or "")
        if cat ~= "" and not seen[cat] then
            seen[cat] = true
            table.insert(list, cat)
        end
    end
    table.sort(list)
    return list
end

--------------------------------------------------------------
-- Persistence helpers
--------------------------------------------------------------
local function SaveFrameState(frame, settingsKey)
    if not frame or not Jotter.db or not Jotter.db.settings then return end
    local s = Jotter.db.settings[settingsKey]
    if type(s) ~= "table" then
        s = {}
        Jotter.db.settings[settingsKey] = s
    end

    local point, _, relativePoint, x, y = frame:GetPoint(1)
    s.point = point or "CENTER"
    s.relativePoint = relativePoint or "CENTER"
    s.x = x or 0
    s.y = y or 0
    s.width = frame:GetWidth()
    s.height = frame:GetHeight()
end

local function ApplyFrameState(frame, settingsKey, defaultW, defaultH)
    if not frame then return end
    local s = (Jotter.db and Jotter.db.settings and Jotter.db.settings[settingsKey]) or nil
    local w = (s and s.width) or defaultW
    local h = (s and s.height) or defaultH
    frame:SetSize(w, h)

    frame:ClearAllPoints()
    if s and s.point and s.relativePoint then
        frame:SetPoint(s.point, UIParent, s.relativePoint, s.x or 0, s.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

--------------------------------------------------------------
-- Editor window (notes + details)
--------------------------------------------------------------
function Jotter:CreateEditorFrame()
    if self.editorFrame then return end

    local f = CreateFrame("Frame", "JotterEditorFrame", UIParent, "BackdropTemplate")
    self.editorFrame = f

    ApplyFrameState(f, "editorFrame", 740, 460)
    f:SetClampedToScreen(true)

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.92)

    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetMovable(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        SaveFrameState(selfFrame, "editorFrame")
    end)

    -- Do not auto-open this window on UI reload.
    f:Hide()

    -- Header
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 12, -10)
    icon:SetTexture(Jotter.ICON_PATH or 134400)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("Jotter - Note Editor")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    close:SetScript("OnClick", function()
        f:Hide()
        if Jotter.db and Jotter.db.settings then
            Jotter.db.settings.configVisible = false
        end
        SaveFrameState(f, "configFrame")
    end)

    close:SetScript("OnClick", function()
        f:Hide()
        if Jotter.db and Jotter.db.settings then
            Jotter.db.settings.editorVisible = false
        end
        SaveFrameState(f, "editorFrame")
    end)

    -- Left column container
    local left = CreateFrame("Frame", nil, f)
    left:SetPoint("TOPLEFT", 12, -44)
    left:SetPoint("BOTTOMLEFT", 12, 12)
    left:SetWidth(340)

    local leftTitle = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", 0, 0)
    leftTitle:SetText("Notes")

    local listBorder = CreateFrame("Frame", nil, left, "BackdropTemplate")
    listBorder:SetPoint("TOPLEFT", 0, -18)
    listBorder:SetPoint("BOTTOMRIGHT", 0, 0)
    listBorder:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    listBorder:SetBackdropColor(0.05, 0.05, 0.05, 0.65)

    local scrollFrame = CreateFrame("ScrollFrame", "JotterEditorScrollFrame", listBorder, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 6, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 6)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetPoint("TOPLEFT", 0, 0)
    content:SetPoint("TOPRIGHT", 0, 0)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)

    scrollFrame:SetScript("OnSizeChanged", function(_, width, _)
        content:SetWidth(width)
    end)

    self.editorScrollFrame = scrollFrame
    self.editorContent = content

    -- Rows (simple pool)
    local previous
    local rowHeight = 24
    local gap = 4

    for i = 1, self.maxEditorRows do
        local row = CreateFrame("Frame", nil, content)
        row:SetHeight(rowHeight)
        row:SetPoint("LEFT", 0, 0)
        row:SetPoint("RIGHT", 0, 0)

        if i == 1 then
            row:SetPoint("TOPLEFT", 0, 0)
            row:SetPoint("TOPRIGHT", 0, 0)
        else
            row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -gap)
            row:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -gap)
        end
        previous = row

        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        hl:Hide()
        row.highlight = hl

        local textBtn = CreateFrame("Button", nil, row)
        textBtn:SetPoint("LEFT", 0, 0)
        textBtn:SetPoint("RIGHT", -110, 0)
        textBtn:SetPoint("TOP", 0, 0)
        textBtn:SetPoint("BOTTOM", 0, 0)

        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 4, 0)
        fs:SetPoint("RIGHT", -110, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        row.text = fs

        textBtn:SetScript("OnClick", function()
            local idx = row.noteIndex
            if not idx then return end
            Jotter.selectedNoteIndex = idx
            Jotter:RefreshEditor()
        end)

        local up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        up:SetSize(20, 20)
        up:SetPoint("RIGHT", -84, 0)
        up:SetText("^")

        local down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        down:SetSize(20, 20)
        down:SetPoint("RIGHT", -60, 0)
        down:SetText("v")

        local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        del:SetSize(44, 20)
        del:SetPoint("RIGHT", -4, 0)
        del:SetText("Del")

        up:SetScript("OnClick", function()
            local index = row.noteIndex
            if not index then return end
            Jotter:MoveNoteWithinCategory(index, -1)
        end)

        down:SetScript("OnClick", function()
            local index = row.noteIndex
            if not index then return end
            Jotter:MoveNoteWithinCategory(index, 1)
        end)

        del:SetScript("OnClick", function()
            local index = row.noteIndex
            if not index then return end
            table.remove(Jotter.db.notes, index)
            if Jotter.selectedNoteIndex == index then
                Jotter.selectedNoteIndex = nil
            elseif Jotter.selectedNoteIndex and Jotter.selectedNoteIndex > index then
                Jotter.selectedNoteIndex = Jotter.selectedNoteIndex - 1
            end
            Jotter:RefreshList()
            Jotter:RefreshEditor()
            Jotter:RefreshConfig()
        end)

        row.up = up
        row.down = down
        row.del = del

        self.editorRows[i] = row
    end

    -- Right column: details
    local right = CreateFrame("Frame", nil, f)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 16, 0)
    right:SetPoint("BOTTOMRIGHT", -12, 12)

    local detailTitle = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailTitle:SetPoint("TOPLEFT", 0, 0)
    detailTitle:SetText("Details")

    local detailBox = CreateFrame("Frame", nil, right, "BackdropTemplate")
    detailBox:SetPoint("TOPLEFT", 0, -18)
    detailBox:SetPoint("BOTTOMRIGHT", 0, 0)
    detailBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    detailBox:SetBackdropColor(0.05, 0.05, 0.05, 0.65)

    local padX = 10
    local y = -10

    local function AddLabel(text)
        local l = detailBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", padX, y)
        l:SetText(text)
        y = y - 16
        return l
    end

    local function AddEditBox(width)
        local e = CreateFrame("EditBox", nil, detailBox, "InputBoxTemplate")
        e:SetAutoFocus(false)
        e:SetHeight(20)
        e:SetPoint("TOPLEFT", padX, y)
        e:SetWidth(width)
        y = y - 28
        return e
    end

    -- Text (read-only label, edited in list)
    local selectedTextLabel = AddLabel("Selected note")
    local selectedTextValue = detailBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectedTextValue:SetPoint("TOPLEFT", padX, y)
    selectedTextValue:SetPoint("RIGHT", -padX, 0)
    selectedTextValue:SetJustifyH("LEFT")
    selectedTextValue:SetText("")
    y = y - 26
    self.detailSelectedText = selectedTextValue

    -- Zone
    AddLabel("Zone")
    local zoneEdit = AddEditBox(220)
    self.detailZoneEdit = zoneEdit

    -- Coordinates
    AddLabel("Coordinates (ex: 12.3, 45.6)")
    local coordEdit = AddEditBox(220)
    self.detailCoordsEdit = coordEdit

    -- Category
    AddLabel("Category (optional)")
    local catEdit = AddEditBox(220)
    self.detailCategoryEdit = catEdit

    local pick = CreateFrame("Button", nil, detailBox, "UIPanelButtonTemplate")
    pick:SetSize(60, 20)
    pick:SetPoint("LEFT", catEdit, "RIGHT", 6, 0)
    pick:SetText("Pick")

    pick:SetScript("OnClick", function()
        local categories = GetAllCategoryNames()
        if #categories == 0 then
            print("|cff00ff99Jotter:|r No categories exist yet. Type a new category name.")
            return
        end

        local menu = {}
        table.insert(menu, { text = "Select Category", isTitle = true, notCheckable = true })
        table.insert(menu, { text = "(Clear)", notCheckable = true, func = function()
            catEdit:SetText("")
            catEdit:ClearFocus()
            Jotter:SaveSelectedNoteField("category", "")
        end })

        for _, name in ipairs(categories) do
            table.insert(menu, { text = name, notCheckable = true, func = function()
                catEdit:SetText(name)
                catEdit:ClearFocus()
                Jotter:SaveSelectedNoteField("category", name)
            end })
        end

        EasyMenu(menu, CreateFrame("Frame", "JotterCategoryPickMenu", UIParent, "UIDropDownMenuTemplate"), pick, 0, 0, "MENU")
    end)

    -- Description (scrolling multiline)
    local descLabel = AddLabel("Description")
    local descBorder = CreateFrame("Frame", nil, detailBox, "BackdropTemplate")
    descBorder:SetPoint("TOPLEFT", padX, y)
    descBorder:SetPoint("BOTTOMRIGHT", -padX, 10)
    descBorder:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    descBorder:SetBackdropColor(0.02, 0.02, 0.02, 0.9)

    local descScroll = CreateFrame("ScrollFrame", nil, descBorder, "UIPanelScrollFrameTemplate")
    descScroll:SetPoint("TOPLEFT", 6, -6)
    descScroll:SetPoint("BOTTOMRIGHT", -28, 6)

    local descEdit = CreateFrame("EditBox", nil, descScroll)
    descEdit:SetMultiLine(true)
    descEdit:SetAutoFocus(false)
    descEdit:SetFontObject("GameFontHighlightSmall")
    descEdit:SetWidth(1)
    descEdit:SetTextInsets(2, 2, 2, 2)
    descEdit:SetScript("OnEscapePressed", function(selfEdit) selfEdit:ClearFocus() end)
    -- Some builds do not expose EditBox:GetStringHeight().
    -- Use GetTextHeight() when available, otherwise measure via a hidden FontString.
    descEdit:SetScript("OnTextChanged", function(selfEdit)
        local text = selfEdit:GetText() or ""
        local textH

        if selfEdit.GetTextHeight then
            textH = selfEdit:GetTextHeight()
        end

        if not textH then
            if not selfEdit._measureFS then
                local fs = selfEdit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:Hide()
                fs:SetWidth(selfEdit:GetWidth())
                fs:SetJustifyH("LEFT")
                fs:SetJustifyV("TOP")
                fs:SetWordWrap(true)
                selfEdit._measureFS = fs
            end
            local fs = selfEdit._measureFS
            fs:SetWidth(selfEdit:GetWidth())
            fs:SetText(text)
            textH = fs:GetStringHeight()
        end

        local h = math.max(120, (textH or 0) + 12)
        selfEdit:SetHeight(h)
    end)

    descScroll:SetScrollChild(descEdit)
    self.detailDescEdit = descEdit

    descScroll:SetScript("OnSizeChanged", function(_, width, _)
        descEdit:SetWidth(width)
    end)

    ----------------------------------------------------------
    -- Field save wiring
    ----------------------------------------------------------
    zoneEdit:SetScript("OnEnterPressed", function(selfEdit)
        selfEdit:ClearFocus()
        Jotter:SaveSelectedNoteField("zone", selfEdit:GetText() or "")
    end)
    zoneEdit:SetScript("OnEditFocusLost", function(selfEdit)
        Jotter:SaveSelectedNoteField("zone", selfEdit:GetText() or "")
    end)

    -- Coordinates: also auto-fill zone if blank (your previous behavior)
    coordEdit:SetScript("OnEnterPressed", function(selfEdit)
        selfEdit:ClearFocus()
        Jotter:SaveCoordsAndAutoZone(selfEdit:GetText() or "")
    end)
    coordEdit:SetScript("OnEditFocusLost", function(selfEdit)
        Jotter:SaveCoordsAndAutoZone(selfEdit:GetText() or "")
    end)

    catEdit:SetScript("OnEnterPressed", function(selfEdit)
        selfEdit:ClearFocus()
        Jotter:SaveSelectedNoteField("category", selfEdit:GetText() or "")
    end)
    catEdit:SetScript("OnEditFocusLost", function(selfEdit)
        Jotter:SaveSelectedNoteField("category", selfEdit:GetText() or "")
    end)

    descEdit:SetScript("OnEditFocusLost", function(selfEdit)
        Jotter:SaveSelectedNoteField("description", selfEdit:GetText() or "")
    end)

    self:RefreshEditor()
end

--------------------------------------------------------------
-- Editor helpers
--------------------------------------------------------------
function Jotter:SaveSelectedNoteField(field, value)
    if not self.selectedNoteIndex then return end
    local note = self.db and self.db.notes and self.db.notes[self.selectedNoteIndex]
    if not note then return end

    if field == "zone" then
        note.zone = Trim(value or "")
    elseif field == "coords" then
        note.coords = Trim(value or "")
    elseif field == "description" then
        note.description = value or ""
    elseif field == "category" then
        note.category = Trim(value or "")
        -- Keep category ordering stable once categories exist
        local cat = self:GetNoteCategory(note)
        self:EnsureCategoryInOrder(cat)
    end

    self:RefreshList()
    self:RefreshEditor()
    self:RefreshConfig()
end

-- Keeps your existing "coords implies current zone if blank" behavior
function Jotter:SaveCoordsAndAutoZone(value)
    if not self.selectedNoteIndex then return end
    local note = self.db and self.db.notes and self.db.notes[self.selectedNoteIndex]
    if not note then return end

    value = Trim(value or "")
    note.coords = value

    -- If we now have coords but no zone, assume the current zone
    if value ~= "" then
        local z = Trim(note.zone or "")
        if z == "" then
            note.zone = self.currentZone or GetCurrentZoneName()
            if self.detailZoneEdit then
                self.detailZoneEdit:SetText(note.zone)
            end
        end
    end

    self:RefreshList()
    self:RefreshEditor()
end

-- Reorder within the same category and zone.
-- This is a simpler first pass compared to full drag-and-drop.
function Jotter:MoveNoteWithinCategory(noteIndex, direction)
    local notes = self.db and self.db.notes
    if not notes then return end

    local note = notes[noteIndex]
    if not note then return end

    local zone = Trim(note.zone or "")
    local cat = self:GetNoteCategory(note)

    local function SameBucket(t)
        if not t then return false end
        return Trim(t.zone or "") == zone and self:GetNoteCategory(t) == cat
    end

    if direction < 0 then
        for i = noteIndex - 1, 1, -1 do
            if SameBucket(notes[i]) then
                notes[noteIndex], notes[i] = notes[i], notes[noteIndex]
                self.selectedNoteIndex = i
                self:RefreshList()
                self:RefreshEditor()
                return
            end
        end
    else
        for i = noteIndex + 1, #notes do
            if SameBucket(notes[i]) then
                notes[noteIndex], notes[i] = notes[i], notes[noteIndex]
                self.selectedNoteIndex = i
                self:RefreshList()
                self:RefreshEditor()
                return
            end
        end
    end
end

--------------------------------------------------------------
-- Editor refresh
--------------------------------------------------------------
function Jotter:RefreshEditor()
    if not self.editorFrame or not self.db then return end

    local rows = self.editorRows
    local notes = self.db.notes or {}

    -- List: show all notes (not only current zone) for editing
    local contentHeight = 0
    local shown = 0

    for i = 1, self.maxEditorRows do
        local row = rows[i]
        local note = notes[i]
        if note then
            shown = shown + 1
            row.noteIndex = i
            row:Show()

            local text = note.text or ""
            local zone = Trim(note.zone or "")
            local cat = Trim(note.category or "")

            local suffix = ""
            if zone ~= "" then suffix = suffix .. "  |cff888888[" .. zone .. "]|r" end
            if cat ~= "" then suffix = suffix .. "  |cff99ccff{" .. cat .. "}|r" end

            if note.done then
                row.text:SetText("|cff777777" .. text .. "|r" .. suffix)
            else
                row.text:SetText(text .. suffix)
            end

            if self.selectedNoteIndex == i then
                row.highlight:Show()
            else
                row.highlight:Hide()
            end

            contentHeight = contentHeight + 24 + 4
        else
            row.noteIndex = nil
            row:Hide()
            row.highlight:Hide()
        end
    end

    if contentHeight < 1 then contentHeight = 1 end
    self.editorContent:SetHeight(contentHeight)

    -- Details panel
    local idx = self.selectedNoteIndex
    local note = idx and notes[idx] or nil

    if not note then
        if self.detailSelectedText then self.detailSelectedText:SetText("Select a note from the list.") end
        if self.detailZoneEdit then self.detailZoneEdit:SetText("") end
        if self.detailCoordsEdit then self.detailCoordsEdit:SetText("") end
        if self.detailCategoryEdit then self.detailCategoryEdit:SetText("") end
        if self.detailDescEdit then self.detailDescEdit:SetText("") end
        return
    end

    if self.detailSelectedText then self.detailSelectedText:SetText(note.text or "") end
    if self.detailZoneEdit then self.detailZoneEdit:SetText(note.zone or "") end
    if self.detailCoordsEdit then self.detailCoordsEdit:SetText(note.coords or "") end
    if self.detailCategoryEdit then self.detailCategoryEdit:SetText(note.category or "") end
    if self.detailDescEdit then self.detailDescEdit:SetText(note.description or "") end
end

--------------------------------------------------------------
-- Toggle editor
--------------------------------------------------------------
function Jotter:ToggleEditor(forceShow)
    self:CreateEditorFrame()

    local show = false
    if forceShow then
        show = true
    else
        show = not self.editorFrame:IsShown()
    end

    if show then
        self.editorFrame:Show()
        if self.db and self.db.settings then
            self.db.settings.editorVisible = true
        end
        self:RefreshEditor()
    else
        self.editorFrame:Hide()
        if self.db and self.db.settings then
            self.db.settings.editorVisible = false
        end
        SaveFrameState(self.editorFrame, "editorFrame")
    end
end

--------------------------------------------------------------
-- Config window (refactored)
--------------------------------------------------------------
function Jotter:CreateConfigFrame()
    if self.configFrame then return end

    local f = CreateFrame("Frame", "JotterConfigFrame", UIParent, "BackdropTemplate")
    self.configFrame = f

    ApplyFrameState(f, "configFrame", 480, 520)
    f:SetClampedToScreen(true)

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.92)

    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetMovable(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        SaveFrameState(selfFrame, "configFrame")
    end)

    -- Do not auto-open this window on UI reload.
    f:Hide()

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 12, -10)
    icon:SetTexture(Jotter.ICON_PATH or 134400)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("Jotter - Configuration")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Scroll container
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -44)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT", 0, 0)
    content:SetPoint("TOPRIGHT", 0, 0)
    content:SetHeight(1)
    scroll:SetScrollChild(content)

    scroll:SetScript("OnSizeChanged", function(_, width, _)
        content:SetWidth(width)
    end)

    self.configContent = content
    self.configScrollFrame = scroll

    local y = -4
    local function SectionHeader(text)
        local h = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", 0, y)
        h:SetText(text)
        y = y - 22
        return h
    end

    local function Checkbox(label, tooltip)
        local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 0, y)
        cb.text:SetText(label)
        cb.tooltipText = tooltip
        y = y - 26
        return cb
    end

    local function SmallText(text)
        local t = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        t:SetPoint("TOPLEFT", 24, y)
        t:SetPoint("RIGHT", -4, 0)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(true)
        t:SetText(text)

        -- SmallText lines can wrap. Adjust y based on the actual rendered height
        -- to prevent later controls from overlapping this text.
        local h = t:GetStringHeight()
        if not h or h < 14 then h = 14 end
        y = y - (h + 6)

        return t
    end

    SectionHeader("General")
    local useZone = Checkbox("Quick add uses current zone", "When enabled, notes typed into the main window are automatically assigned to your current zone.")
    SmallText("Tip: You can still edit the zone later in the editor window.")
    self.cfg_useZone = useZone

    SectionHeader("Visibility")
    local hideCombat = Checkbox("Hide Jotter window while in combat", "When enabled, the main Jotter window will hide in combat and restore afterward if it was visible before combat.")
    self.cfg_hideCombat = hideCombat

    local hideCompleted = Checkbox("Hide completed notes on the main window", "When enabled, completed notes will not be shown in the main list.")
    self.cfg_hideCompleted = hideCompleted

    local lockMain = Checkbox("Lock the main window (prevents moving/resizing)", "When enabled, the main Jotter window cannot be moved or resized.")
    self.cfg_lockMain = lockMain

    SectionHeader("Categories and Sorting")
    SmallText("Category ordering affects how groups appear on the main window. Notes are ordered within a category based on their position in your note list (use the editor up/down buttons).")

    -- Category ordering list
    local listBorder = CreateFrame("Frame", nil, content, "BackdropTemplate")
    listBorder:SetPoint("TOPLEFT", 0, y)
    listBorder:SetPoint("RIGHT", -4, 0)
    listBorder:SetHeight(200)
    listBorder:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    listBorder:SetBackdropColor(0.05, 0.05, 0.05, 0.65)
    y = y - 212

    local catScroll = CreateFrame("ScrollFrame", nil, listBorder, "UIPanelScrollFrameTemplate")
    catScroll:SetPoint("TOPLEFT", 6, -6)
    catScroll:SetPoint("BOTTOMRIGHT", -30, 6)

    local catContent = CreateFrame("Frame", nil, catScroll)
    catContent:SetPoint("TOPLEFT", 0, 0)
    catContent:SetPoint("TOPRIGHT", 0, 0)
    catContent:SetHeight(1)
    catScroll:SetScrollChild(catContent)

    catScroll:SetScript("OnSizeChanged", function(_, width, _)
        catContent:SetWidth(width)
    end)

    self.cfg_catContent = catContent
    self.cfg_catRows = self.cfg_catRows or {}

    local resetCollapsed = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetCollapsed:SetPoint("TOPLEFT", 0, y)
    resetCollapsed:SetSize(220, 22)
    resetCollapsed:SetText("Reset collapsed states")
    y = y - 30

    resetCollapsed:SetScript("OnClick", function()
        if not Jotter.db or not Jotter.db.settings then return end
        wipe(Jotter.db.settings.categoryCollapsed)
        Jotter:RefreshList()
        Jotter:RefreshConfig()
    end)

    -- Wire checkbox handlers
    local function ApplyToDB()
        local s = Jotter.db.settings
        s.useCurrentZoneByDefault = useZone:GetChecked() and true or false
        s.hideInCombat = hideCombat:GetChecked() and true or false
        s.hideCompletedOnMain = hideCompleted:GetChecked() and true or false
        s.lockMainWindow = lockMain:GetChecked() and true or false

        Jotter:ApplyMainFrameLockState()
        Jotter:RefreshList()
    end

    useZone:SetScript("OnClick", ApplyToDB)
    hideCombat:SetScript("OnClick", ApplyToDB)
    hideCompleted:SetScript("OnClick", ApplyToDB)
    lockMain:SetScript("OnClick", ApplyToDB)

    self:RefreshConfig()
end

function Jotter:RefreshConfig()
    if not self.configFrame or not self.db or not self.db.settings then return end
    local s = self.db.settings

    if self.cfg_useZone then self.cfg_useZone:SetChecked(s.useCurrentZoneByDefault and true or false) end
    if self.cfg_hideCombat then self.cfg_hideCombat:SetChecked(s.hideInCombat and true or false) end
    if self.cfg_hideCompleted then self.cfg_hideCompleted:SetChecked(s.hideCompletedOnMain and true or false) end
    if self.cfg_lockMain then self.cfg_lockMain:SetChecked(s.lockMainWindow and true or false) end

    -- Category order rows
    if not self.cfg_catContent then return end

    local order = s.categoryOrder or {}
    -- Ensure Uncategorized exists if any categories exist
    if #order == 0 then
        self:EnsureCategoryInOrder("Uncategorized")
        order = s.categoryOrder
    end

    local rowHeight = 22
    local gap = 4
    local contentHeight = 0

    for i = 1, math.max(#order, 1) do
        local row = self.cfg_catRows[i]
        if not row then
            row = CreateFrame("Frame", nil, self.cfg_catContent)
            row:SetHeight(rowHeight)
            row:SetPoint("LEFT", 0, 0)
            row:SetPoint("RIGHT", 0, 0)

            if i == 1 then
                row:SetPoint("TOPLEFT", 0, 0)
                row:SetPoint("TOPRIGHT", 0, 0)
            else
                row:SetPoint("TOPLEFT", self.cfg_catRows[i - 1], "BOTTOMLEFT", 0, -gap)
                row:SetPoint("TOPRIGHT", self.cfg_catRows[i - 1], "BOTTOMRIGHT", 0, -gap)
            end

            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", 2, 0)
            fs:SetPoint("RIGHT", -90, 0)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row.text = fs

            local up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            up:SetSize(20, 20)
            up:SetPoint("RIGHT", -56, 0)
            up:SetText("^")

            local down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            down:SetSize(20, 20)
            down:SetPoint("RIGHT", -32, 0)
            down:SetText("v")

            local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            del:SetSize(26, 20)
            del:SetPoint("RIGHT", -2, 0)
            del:SetText("X")

            up:SetScript("OnClick", function()
                if i <= 1 then return end
                order[i], order[i - 1] = order[i - 1], order[i]
                Jotter:RefreshConfig()
                Jotter:RefreshList()
            end)

            down:SetScript("OnClick", function()
                if i >= #order then return end
                order[i], order[i + 1] = order[i + 1], order[i]
                Jotter:RefreshConfig()
                Jotter:RefreshList()
            end)

            del:SetScript("OnClick", function()
                -- Removing a category from the ordering does NOT delete notes.
                table.remove(order, i)
                Jotter:RefreshConfig()
                Jotter:RefreshList()
            end)

            row.up = up
            row.down = down
            row.del = del

            self.cfg_catRows[i] = row
        end

        local name = order[i]
        if name then
            row:Show()
            row.text:SetText(name)
            contentHeight = contentHeight + rowHeight + gap
        else
            row:Hide()
        end
    end

    if contentHeight < 1 then contentHeight = 1 end
    self.cfg_catContent:SetHeight(contentHeight)
end

function Jotter:ToggleConfig()
    self:CreateConfigFrame()
    local show = not self.configFrame:IsShown()
    if show then
        self.configFrame:Show()
        if self.db and self.db.settings then
            self.db.settings.configVisible = true
        end
        self:RefreshConfig()
    else
        self.configFrame:Hide()
        if self.db and self.db.settings then
            self.db.settings.configVisible = false
        end
        SaveFrameState(self.configFrame, "configFrame")
    end
end


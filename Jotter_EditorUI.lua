local addonName, Jotter = ...
local Trim = Jotter.Trim
local GetCurrentZoneName = Jotter.GetCurrentZoneName

Jotter.editorRows = Jotter.editorRows or {}

--------------------------------------------------------------
-- Editor window
--------------------------------------------------------------
function Jotter:CreateEditorFrame()
    if self.editorFrame then return end

    local f = CreateFrame("Frame", "JotterEditorFrame", UIParent, "BackdropTemplate")
    self.editorFrame = f

    -- wider editor for side-by-side layout
    f:SetSize(720, 400)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:Hide()

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)

    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    -- Icon in the config window header
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 10, -8)
    icon:SetTexture(Jotter.ICON_PATH or 134400)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetText("Jotter Todos")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)


    ----------------------------------------------------------
    -- Options (top, spanning full width)
    ----------------------------------------------------------
    -- Default zone toggle
    local zoneToggle = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    zoneToggle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -4)
    zoneToggle:SetChecked(Jotter.db.settings.useCurrentZoneByDefault)

    local zoneToggleLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneToggleLabel:SetPoint("LEFT", zoneToggle, "RIGHT", 2, 0)
    zoneToggleLabel:SetWidth(260)
    zoneToggleLabel:SetJustifyH("LEFT")
    zoneToggleLabel:SetText("New todos use current zone")

    zoneToggle:SetScript("OnClick", function(selfBtn)
        Jotter.db.settings.useCurrentZoneByDefault = selfBtn:GetChecked() and true or false
    end)

    -- Hide completed toggle
    local hideToggle = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    hideToggle:SetPoint("TOPLEFT", zoneToggle, "BOTTOMLEFT", 0, -2)
    hideToggle:SetChecked(Jotter.db.settings.hideCompletedOnMain)

    local hideToggleLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideToggleLabel:SetPoint("LEFT", hideToggle, "RIGHT", 2, 0)
    hideToggleLabel:SetWidth(260)
    hideToggleLabel:SetJustifyH("LEFT")
    hideToggleLabel:SetText("Hide completed on main list")

    hideToggle:SetScript("OnClick", function(selfBtn)
        Jotter.db.settings.hideCompletedOnMain = selfBtn:GetChecked() and true or false
        Jotter:RefreshList()
    end)

    ----------------------------------------------------------
    -- Left column: todo list with scrolling
    ----------------------------------------------------------
    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 14, -94)                    -- under the options
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -8, 50)    -- up to the center, small gap

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    self.editorScrollFrame = scrollFrame
    self.editorContent = content

    -- keep the list content width matched to the scroll frame width
    scrollFrame:SetScript("OnSizeChanged", function(_, width, _)
        content:SetWidth(width)
    end)


    self.editorScrollFrame = scrollFrame
    self.editorContent = content

    scrollFrame:SetScript("OnSizeChanged", function(_, width, _)
        content:SetWidth(width)
    end)

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

        row:EnableMouse(true)

        local idxText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        idxText:SetPoint("LEFT", 2, 0)
        idxText:SetWidth(18)
        idxText:SetJustifyH("CENTER")
        row.indexText = idxText

        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(16, 16)
        cb:SetPoint("LEFT", idxText, "RIGHT", 2, 0)
        row.check = cb

        local textEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        textEdit:SetAutoFocus(false)
        textEdit:SetHeight(18)
        textEdit:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        textEdit:SetWidth(190)
        textEdit:SetMaxLetters(200)
        row.textEdit = textEdit

        local up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        up:SetSize(20, 18)
        up:SetPoint("LEFT", textEdit, "RIGHT", 4, 0)
        up:SetText("^")
        row.up = up

        local down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        down:SetSize(20, 18)
        down:SetPoint("LEFT", up, "RIGHT", 2, 0)
        down:SetText("v")
        row.down = down

        local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        del:SetSize(20, 18)
        del:SetPoint("LEFT", down, "RIGHT", 2, 0)
        del:SetText("X")
        row.delete = del

        local detailsBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        detailsBtn:SetSize(50, 18)
        detailsBtn:SetPoint("LEFT", del, "RIGHT", 4, 0)
        detailsBtn:SetText("Details")
        row.detailsBtn = detailsBtn

        cb:SetScript("OnClick", function()
            local index = row.todoIndex
            if not index then return end
            local todo = Jotter.db.todos[index]
            if todo then
                todo.done = cb:GetChecked() and true or false
                Jotter:RefreshList()
                Jotter:RefreshEditor()
            end
        end)

        textEdit:SetScript("OnEnterPressed", function(selfEdit)
            local index = row.todoIndex
            if not index then return end
            local todo = Jotter.db.todos[index]
            if todo then
                todo.text = Trim(selfEdit:GetText() or "")
                Jotter:RefreshList()
            end
            selfEdit:ClearFocus()
        end)
        textEdit:SetScript("OnEditFocusLost", function(selfEdit)
            local index = row.todoIndex
            if not index then return end
            local todo = Jotter.db.todos[index]
            if todo then
                todo.text = Trim(selfEdit:GetText() or "")
                Jotter:RefreshList()
            end
        end)

        up:SetScript("OnClick", function()
            local index = row.todoIndex
            if not index or index <= 1 then return end
            local todos = Jotter.db.todos
            todos[index], todos[index - 1] = todos[index - 1], todos[index]
            Jotter.selectedTodoIndex = index - 1
            Jotter:RefreshList()
            Jotter:RefreshEditor()
        end)

        down:SetScript("OnClick", function()
            local index = row.todoIndex
            local todos = Jotter.db.todos
            if not index or index >= #todos then return end
            todos[index], todos[index + 1] = todos[index + 1], todos[index]
            Jotter.selectedTodoIndex = index + 1
            Jotter:RefreshList()
            Jotter:RefreshEditor()
        end)

        del:SetScript("OnClick", function()
            local index = row.todoIndex
            local todos = Jotter.db.todos
            if not index or not todos[index] then return end
            table.remove(todos, index)
            if Jotter.selectedTodoIndex and Jotter.selectedTodoIndex > #todos then
                Jotter.selectedTodoIndex = #todos
            end
            Jotter:RefreshList()
            Jotter:RefreshEditor()
        end)

        local function selectRow()
            if row.todoIndex then
                Jotter:SetSelectedTodoIndex(row.todoIndex)
            end
        end

        detailsBtn:SetScript("OnClick", selectRow)
        row:SetScript("OnMouseDown", selectRow)

        Jotter.editorRows[i] = row
    end

    ----------------------------------------------------------
    -- Right column: details (zone + description)
    ----------------------------------------------------------
    local detailBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
    -- start at the center of the editor, same top line as the list, with a small gap
    detailBox:SetPoint("TOPLEFT", f, "TOP", 8, -94)
    -- extend down, but stay above the help text and Add button
    detailBox:SetPoint("BOTTOMRIGHT", -16, 40)

    detailBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    detailBox:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    self.detailBox = detailBox

    local dTitle = detailBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dTitle:SetPoint("TOPLEFT", 8, -6)
    dTitle:SetText("Details for selected todo")

    local zoneLabel = detailBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneLabel:SetPoint("TOPLEFT", dTitle, "BOTTOMLEFT", 0, -6)
    zoneLabel:SetText("Zone:")

    local zoneEdit = CreateFrame("EditBox", nil, detailBox, "InputBoxTemplate")
    zoneEdit:SetAutoFocus(false)
    zoneEdit:SetHeight(18)
    zoneEdit:SetPoint("LEFT", zoneLabel, "RIGHT", 4, 0)
    zoneEdit:SetPoint("RIGHT", -10, 0)
    zoneEdit:SetMaxLetters(60)
    self.detailZoneEdit = zoneEdit

    -- NEW: coordinates label + edit box
    local coordLabel = detailBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    coordLabel:SetPoint("TOPLEFT", zoneLabel, "BOTTOMLEFT", 0, -8)
    coordLabel:SetText("Coords:")

    local coordEdit = CreateFrame("EditBox", nil, detailBox, "InputBoxTemplate")
    coordEdit:SetAutoFocus(false)
    coordEdit:SetHeight(18)
    coordEdit:SetPoint("LEFT", coordLabel, "RIGHT", 4, 0)
    coordEdit:SetPoint("RIGHT", -10, 0)
    coordEdit:SetMaxLetters(40)
    self.detailCoordsEdit = coordEdit

    local descLabel = detailBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    descLabel:SetPoint("TOPLEFT", coordLabel, "BOTTOMLEFT", 0, -8)
    descLabel:SetText("Description:")

    local descScroll = CreateFrame("ScrollFrame", nil, detailBox, "UIPanelScrollFrameTemplate")
    descScroll:SetPoint("TOPLEFT", descLabel, "BOTTOMLEFT", 0, -4)
    descScroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local descEdit = CreateFrame("EditBox", nil, descScroll)
    descEdit:SetMultiLine(true)
    descEdit:SetAutoFocus(false)
    descEdit:SetFontObject("GameFontHighlightSmall")
    descEdit:SetWidth(descScroll:GetWidth())
    descEdit:SetText("")
    descEdit:EnableMouse(true)
    descEdit:SetScript("OnMouseDown", function(selfEdit)
        selfEdit:SetFocus()
    end)

    descScroll:SetScrollChild(descEdit)
    self.detailDescEdit = descEdit

    descScroll:SetScript("OnSizeChanged", function(_, width, _)
        descEdit:SetWidth(width)
    end)

    descEdit:SetScript("OnEscapePressed", function(selfEdit)
        selfEdit:ClearFocus()
    end)

    descEdit:SetScript("OnTextChanged", function(selfEdit, userInput)
        if not userInput or Jotter.updatingDetails then return end
        local idx = Jotter.selectedTodoIndex
        if not idx then return end
        local todo = Jotter.db.todos[idx]
        if not todo then return end
        todo.description = selfEdit:GetText() or ""
    end)

    zoneEdit:SetScript("OnEnterPressed", function(selfEdit)
        if Jotter.updatingDetails then return end
        local idx = Jotter.selectedTodoIndex
        if not idx then return end
        local todo = Jotter.db.todos[idx]
        if not todo then return end
        todo.zone = Trim(selfEdit:GetText() or "")
        Jotter:RefreshList()
        Jotter:RefreshEditor()
        selfEdit:ClearFocus()
    end)

    zoneEdit:SetScript("OnEditFocusLost", function(selfEdit)
        if Jotter.updatingDetails then return end
        local idx = Jotter.selectedTodoIndex
        if not idx then return end
        local todo = Jotter.db.todos[idx]
        if not todo then return end
        todo.zone = Trim(selfEdit:GetText() or "")
        Jotter:RefreshList()
        Jotter:RefreshEditor()
    end)

    -- NEW: helper to save coords and auto-fill zone if blank
    local function Jotter_SaveCoordsFromEdit(selfEdit)
        if Jotter.updatingDetails then return end
        local idx = Jotter.selectedTodoIndex
        if not idx then return end
        local todo = Jotter.db.todos[idx]
        if not todo then return end

        local value = Trim(selfEdit:GetText() or "")
        todo.coords = value

        -- If we now have coords but no zone, assume the current zone
        local zoneText = Trim(todo.zone or "")
        if value ~= "" and zoneText == "" then
            local currentZone = Jotter.currentZone or GetCurrentZoneName()
            todo.zone = currentZone

            if Jotter.detailZoneEdit then
                Jotter.updatingDetails = true
                Jotter.detailZoneEdit:SetText(currentZone or "")
                Jotter.updatingDetails = false
            end
        end

        -- Main list may need to re-filter based on zone
        Jotter:RefreshList()
    end

    coordEdit:SetScript("OnEnterPressed", function(selfEdit)
        Jotter_SaveCoordsFromEdit(selfEdit)
        selfEdit:ClearFocus()
    end)

    coordEdit:SetScript("OnEditFocusLost", function(selfEdit)
        Jotter_SaveCoordsFromEdit(selfEdit)
    end)


    ----------------------------------------------------------
    -- Bottom helper text + add button
    ----------------------------------------------------------
    local help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("BOTTOMLEFT", 16, 28)
    help:SetPoint("RIGHT", -120, 28)
    help:SetJustifyH("LEFT")
    help:SetText("Zone is optional. If set, the todo only shows in that zone. Description is used for /say on Shift + right click if present.")

    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 22)
    addBtn:SetPoint("BOTTOMRIGHT", -16, 24)
    addBtn:SetText("Add row")
    addBtn:SetScript("OnClick", function()
        local zone = ""
        if Jotter.db.settings and Jotter.db.settings.useCurrentZoneByDefault then
            zone = Jotter.currentZone or GetCurrentZoneName()
        end
        table.insert(Jotter.db.todos, 1, {
            text        = "New todo",
            done        = false,
            zone        = zone,
            description = "",
            coords      = "",    -- NEW
        })
        Jotter.selectedTodoIndex = 1
        Jotter:RefreshList()
        Jotter:RefreshEditor()
    end)
end

--------------------------------------------------------------
-- Selection and refresh helpers
--------------------------------------------------------------
function Jotter:SetSelectedTodoIndex(index)
    local todos = self.db.todos or {}
    if not todos[index] then
        self.selectedTodoIndex = nil
        if self.detailBox then
            self.detailBox:Hide()
        end
        for _, row in ipairs(self.editorRows) do
            if row.highlight then row.highlight:Hide() end
        end
        return
    end

    self.selectedTodoIndex = index

    if not self.detailBox then return end

    self.detailBox:Show()
    local todo = todos[index]

    self.updatingDetails = true
    self.detailZoneEdit:SetText(todo.zone or "")
    if self.detailCoordsEdit then
        self.detailCoordsEdit:SetText(todo.coords or "")   -- NEW
    end
    self.detailDescEdit:SetText(todo.description or "")
    self.updatingDetails = false

    for _, row in ipairs(self.editorRows) do
        if row.todoIndex == index then
            if row.highlight then row.highlight:Show() end
        else
            if row.highlight then row.highlight:Hide() end
        end
    end
end


function Jotter:ToggleEditor()
    if not self.editorFrame then return end
    if self.editorFrame:IsShown() then
        self.editorFrame:Hide()
    else
        self.editorFrame:Show()
        self:RefreshEditor()
    end
end

function Jotter:RefreshEditor()
    if not self.editorFrame then return end

    local todos = self.db.todos or {}
    local count = #todos

    if self.selectedTodoIndex and self.selectedTodoIndex > count then
        self.selectedTodoIndex = count > 0 and count or nil
    end

    local contentHeight = 0
    local rowHeight = 24
    local gap = 4

    for i = 1, self.maxEditorRows do
        local row = self.editorRows[i]
        local todo = todos[i]

        if todo then
            row.todoIndex = i
            row.indexText:SetText(i)
            row.check:SetChecked(todo.done and true or false)
            row.textEdit:SetText(todo.text or "")
            row:Show()
            if self.selectedTodoIndex == i then
                if row.highlight then row.highlight:Show() end
            else
                if row.highlight then row.highlight:Hide() end
            end

            contentHeight = contentHeight + rowHeight
            if i > 1 then
                contentHeight = contentHeight + gap
            end
        else
            row.todoIndex = nil
            row:Hide()
            if row.highlight then row.highlight:Hide() end
        end
    end

    if contentHeight == 0 then
        contentHeight = rowHeight
    end
    if self.editorContent then
        self.editorContent:SetHeight(contentHeight)
    end

    if self.selectedTodoIndex then
        self:SetSelectedTodoIndex(self.selectedTodoIndex)
    else
        if self.detailBox then
            self.detailBox:Hide()
        end
    end
end

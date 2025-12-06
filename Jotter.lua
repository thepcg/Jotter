local addonName, ns = ...

local Jotter = CreateFrame("Frame")
Jotter:RegisterEvent("ADDON_LOADED")
Jotter:RegisterEvent("PLAYER_ENTERING_WORLD")
Jotter:RegisterEvent("ZONE_CHANGED")
Jotter:RegisterEvent("ZONE_CHANGED_NEW_AREA")

Jotter.rows = {}
Jotter.editorRows = {}
Jotter.maxDisplayRows = 40
Jotter.maxEditorRows = 20
Jotter.rowHeightMain = 18
Jotter.rowGapMain = 2

--------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------
local function Trim(str)
    if not str then return "" end
    return str:match("^%s*(.-)%s*$")
end

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

    -- Ensure all todos have the new fields
    for _, todo in ipairs(db.todos) do
        if todo.zone == nil then todo.zone = "" end
        if todo.description == nil then todo.description = "" end
        if todo.done == nil then todo.done = false end
        if todo.text == nil then todo.text = "" end
    end

    Jotter.db = db
end

--------------------------------------------------------------
-- Utility
--------------------------------------------------------------
local function GetCurrentZoneName()
    local name = GetRealZoneText() or GetZoneText() or ""
    return name
end

--------------------------------------------------------------
-- Main frame and compact list
--------------------------------------------------------------
function Jotter:CreateMainFrame()
    if self.mainFrame then return end

    local f = CreateFrame("Frame", "JotterMainFrame", UIParent, "BackdropTemplate")
    self.mainFrame = f

    f:SetSize(260, 220)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, _, x, y = frame:GetPoint()
        Jotter.db.framePos = { point = point, x = x, y = y }
    end)

    local pos = self.db.framePos or { point = "CENTER", x = 0, y = 0 }
    f:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0, 0, 0, 0.55)

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

    -- Icon in top left to open editor
    local icon = titleBar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 4, 0)
    icon:SetTexture(134400) -- INV_Misc_Note_01

    local iconButton = CreateFrame("Button", nil, titleBar)
    iconButton:SetAllPoints(icon)
    iconButton:SetScript("OnClick", function()
        Jotter:ToggleEditor()
    end)
    iconButton:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Jotter", 1, 1, 1)
        GameTooltip:AddLine("Click to open the editor", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    iconButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Title text
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    title:SetText("Jotter")

    -- Current zone indicator
    local zoneText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneText:SetPoint("RIGHT", -6, 0)
    zoneText:SetText("")
    self.zoneText = zoneText

    -- Input box (top, under title)
    local input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    input:SetHeight(20)
    input:SetPoint("TOPLEFT", 10, -28)
    input:SetPoint("TOPRIGHT", -10, -28)
    input:SetAutoFocus(false)
    input:SetMaxLetters(200)
    input:SetText("Type a todo and press Enter")

    input:SetScript("OnEditFocusGained", function(selfEdit)
        if selfEdit:GetText() == "Type a todo and press Enter" then
            selfEdit:SetText("")
        end
    end)

    input:SetScript("OnEditFocusLost", function(selfEdit)
        if Trim(selfEdit:GetText()) == "" then
            selfEdit:SetText("Type a todo and press Enter")
        end
    end)

    input:SetScript("OnEnterPressed", function(selfEdit)
        local text = Trim(selfEdit:GetText() or "")
        if text ~= "" and text ~= "Type a todo and press Enter" then
            local zone = ""
            if Jotter.db.settings and Jotter.db.settings.useCurrentZoneByDefault then
                zone = Jotter.currentZone or GetCurrentZoneName()
            end
            table.insert(Jotter.db.todos, {
                text = text,
                done = false,
                zone = zone,
                description = "",
            })
            Jotter:RefreshList()
            Jotter:RefreshEditor()
        end
        selfEdit:SetText("")
        selfEdit:SetFocus() -- keep focus for rapid entry
    end)

    self.inputBox = input

    -- Scrollable list area
    local scrollFrame = CreateFrame("ScrollFrame", "JotterListScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 6, -56)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 8)
    self.listScrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    self.listContainer = content

    -- Rows inside scroll content
    local previous
    for i = 1, self.maxDisplayRows do
        local row = CreateFrame("Frame", nil, content)
        row:SetHeight(self.rowHeightMain)
        row:SetPoint("LEFT", 0, 0)
        row:SetPoint("RIGHT", 0, 0)

        if i == 1 then
            row:SetPoint("TOPLEFT", 0, 0)
            row:SetPoint("TOPRIGHT", 0, 0)
        else
            row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -self.rowGapMain)
            row:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -self.rowGapMain)
        end
        previous = row

        row:EnableMouse(true)

        -- Checkbox
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(16, 16)
        cb:SetPoint("LEFT", 0, 0)

        -- Text
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 1)
        fs:SetPoint("RIGHT", -4, 0)
        fs:SetJustifyH("LEFT")

        row.check = cb
        row.text = fs

        row:SetScript("OnMouseUp", function(selfRow, button)
            local index = selfRow.todoIndex
            if not index then return end
            if button == "RightButton" and IsShiftKeyDown() then
                local todo = Jotter.db.todos[index]
                if todo then
                    local desc = Trim(todo.description or "")
                    local sayText = desc ~= "" and desc or (todo.text or "")
                    sayText = Trim(sayText)
                    if sayText ~= "" then
                        SendChatMessage(sayText, "SAY")
                    end
                end
            end
        end)

        cb:SetScript("OnClick", function(selfCb)
            local index = row.todoIndex
            if not index then return end
            local todo = Jotter.db.todos[index]
            if todo then
                todo.done = selfCb:GetChecked() and true or false
                Jotter:RefreshList()
                Jotter:RefreshEditor()
            end
        end)

        self.rows[i] = row
    end

    f:Show()
end

--------------------------------------------------------------
-- Editor window
--------------------------------------------------------------
function Jotter:CreateEditorFrame()
    if self.editorFrame then return end

    local f = CreateFrame("Frame", "JotterEditorFrame", UIParent, "BackdropTemplate")
    self.editorFrame = f

    f:SetSize(460, 400)
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

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("Jotter Todos")

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Default zone toggle - placed under the title on the left
    local zoneToggle = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    zoneToggle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -4)
    zoneToggle:SetChecked(Jotter.db.settings.useCurrentZoneByDefault)

    local zoneToggleLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneToggleLabel:SetPoint("LEFT", zoneToggle, "RIGHT", 2, 0)
    zoneToggleLabel:SetWidth(220)
    zoneToggleLabel:SetJustifyH("LEFT")
    zoneToggleLabel:SetText("New todos use current zone")

    zoneToggle:SetScript("OnClick", function(selfBtn)
        Jotter.db.settings.useCurrentZoneByDefault = selfBtn:GetChecked() and true or false
    end)

    -- Scroll area for rows
    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 14, -58)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 150)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    self.editorScrollFrame = scrollFrame
    self.editorContent = content

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

        -- Highlight for selected row
        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        hl:Hide()
        row.highlight = hl

        row:EnableMouse(true)

        -- Index label
        local idxText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        idxText:SetPoint("LEFT", 2, 0)
        idxText:SetWidth(18)
        idxText:SetJustifyH("CENTER")
        row.indexText = idxText

        -- Done checkbox
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(16, 16)
        cb:SetPoint("LEFT", idxText, "RIGHT", 2, 0)
        row.check = cb

        -- Text edit box (summary)
        local textEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        textEdit:SetAutoFocus(false)
        textEdit:SetHeight(18)
        textEdit:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        textEdit:SetWidth(230)
        textEdit:SetMaxLetters(200)
        row.textEdit = textEdit

        -- Up button
        local up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        up:SetSize(20, 18)
        up:SetPoint("LEFT", textEdit, "RIGHT", 4, 0)
        up:SetText("^")
        row.up = up

        -- Down button
        local down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        down:SetSize(20, 18)
        down:SetPoint("LEFT", up, "RIGHT", 2, 0)
        down:SetText("v")
        row.down = down

        -- Delete button
        local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        del:SetSize(20, 18)
        del:SetPoint("LEFT", down, "RIGHT", 2, 0)
        del:SetText("X")
        row.delete = del

        -- Details button
        local detailsBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        detailsBtn:SetSize(50, 18)
        detailsBtn:SetPoint("LEFT", del, "RIGHT", 4, 0)
        detailsBtn:SetText("Details")
        row.detailsBtn = detailsBtn

        -- Handlers
        cb:SetScript("OnClick", function(selfCb)
            local index = row.todoIndex
            if not index then return end
            local todo = Jotter.db.todos[index]
            if todo then
                todo.done = selfCb:GetChecked() and true or false
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

        self.editorRows[i] = row
    end

    -- Details box (zone + description)
    local detailBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
    detailBox:SetPoint("TOPLEFT", scrollFrame, "BOTTOMLEFT", 0, -6)
    detailBox:SetPoint("BOTTOMRIGHT", -16, 50)
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

    local descLabel = detailBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    descLabel:SetPoint("TOPLEFT", zoneLabel, "BOTTOMLEFT", 0, -8)
    descLabel:SetText("Description:")

    local descScroll = CreateFrame("ScrollFrame", nil, detailBox, "UIPanelScrollFrameTemplate")
    descScroll:SetPoint("TOPLEFT", descLabel, "BOTTOMLEFT", 0, -4)
    descScroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local descEdit = CreateFrame("EditBox", nil, descScroll)
    descEdit:SetMultiLine(true)
    descEdit:SetAutoFocus(false)
    descEdit:SetFontObject("GameFontHighlightSmall")
    descEdit:SetWidth(1)
    descEdit:SetText("")
    descScroll:SetScrollChild(descEdit)
    self.detailDescEdit = descEdit

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

    -- Helper text
    local help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("BOTTOMLEFT", 16, 28)
    help:SetPoint("RIGHT", -120, 28)
    help:SetJustifyH("LEFT")
    help:SetText("Zone is optional. If set, the todo only shows in that zone. Description is used for /say on Shift + right click if present.")

    -- Add button for new todo from editor
    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 22)
    addBtn:SetPoint("BOTTOMRIGHT", -16, 24)
    addBtn:SetText("Add row")
    addBtn:SetScript("OnClick", function()
        local zone = ""
        if Jotter.db.settings and Jotter.db.settings.useCurrentZoneByDefault then
            zone = Jotter.currentZone or GetCurrentZoneName()
        end
        table.insert(Jotter.db.todos, { text = "New todo", done = false, zone = zone, description = "" })
        Jotter.selectedTodoIndex = #Jotter.db.todos
        Jotter:RefreshList()
        Jotter:RefreshEditor()
    end)
end

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

--------------------------------------------------------------
-- Refresh main list
--------------------------------------------------------------
function Jotter:RefreshList()
    if not self.mainFrame then return end
    local todos = self.db.todos or {}

    local currentZone = self.currentZone or GetCurrentZoneName()
    local visibleIndices = {}

    for i, todo in ipairs(todos) do
        local zone = Trim(todo.zone or "")
        local show = false
        if zone == "" then
            show = true
        else
            if currentZone == zone then
                show = true
            end
        end
        if show then
            table.insert(visibleIndices, i)
        end
    end

    local contentHeight = 0
    local shownCount = 0

    for rowIndex = 1, self.maxDisplayRows do
        local row = self.rows[rowIndex]
        if not row then break end
        local todoIndex = visibleIndices[rowIndex]

        if todoIndex then
            local todo = todos[todoIndex]
            row.todoIndex = todoIndex
            row:Show()

            row.check:SetChecked(todo.done and true or false)

            local text = todo.text or ""
            if todo.done then
                row.text:SetText("|cff888888" .. text .. "|r")
            else
                row.text:SetText(text)
            end

            shownCount = shownCount + 1
            contentHeight = contentHeight + self.rowHeightMain
            if rowIndex > 1 then
                contentHeight = contentHeight + self.rowGapMain
            end
        else
            row.todoIndex = nil
            row:Hide()
        end
    end

    if contentHeight == 0 then
        contentHeight = self.rowHeightMain
    end
    if self.listContainer then
        self.listContainer:SetHeight(contentHeight)
    end

    if shownCount == 0 then
        self.mainFrame:Hide()
    else
        self.mainFrame:Show()
    end
end

--------------------------------------------------------------
-- Refresh editor list
--------------------------------------------------------------
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

--------------------------------------------------------------
-- Zone updates
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
-- Events
--------------------------------------------------------------
Jotter:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= addonName then return end
        InitDB()
        self:CreateMainFrame()
        self:CreateEditorFrame()
        self:UpdateZone()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
        self:UpdateZone()
    end
end)

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

local addonName, Jotter = ...
local Trim = Jotter.Trim
local GetCurrentZoneName = Jotter.GetCurrentZoneName

Jotter.rows = Jotter.rows or {}

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

    -- Icon
    local icon = titleBar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 4, 0)
    icon:SetTexture(134400)

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

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    title:SetText("Jotter")

    local zoneText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneText:SetPoint("RIGHT", -6, 0)
    zoneText:SetText("")
    self.zoneText = zoneText

    ----------------------------------------------------------
    -- Input box (top, under title)
    ----------------------------------------------------------
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
            -- insert at top
            table.insert(Jotter.db.todos, 1, {
                text = text,
                done = false,
                zone = zone,
                description = "",
            })
            Jotter:RefreshList()
            Jotter:RefreshEditor()
        end
        selfEdit:SetText("")
        selfEdit:SetFocus()
    end)

    self.inputBox = input

    ----------------------------------------------------------
    -- Scrollable list area
    ----------------------------------------------------------
    local scrollFrame = CreateFrame("ScrollFrame", "JotterListScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 6, -56)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 8)
    self.listScrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(content)
    self.listContainer = content

    scrollFrame:SetScript("OnSizeChanged", function(_, width, _)
        content:SetWidth(width)
    end)

    ----------------------------------------------------------
    -- Rows
    ----------------------------------------------------------
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
            local index = selfRow.todoIndex
            if not index then return end
            local todo = Jotter.db.todos[index]
            if not todo then return end

            GameTooltip:SetOwner(selfRow, "ANCHOR_CURSOR")
            if todo.text and todo.text ~= "" then
                GameTooltip:SetText(todo.text, 1, 1, 1, true)
            end

            local desc = Trim(todo.description or "")
            if desc ~= "" then
                GameTooltip:AddLine(desc, 0.9, 0.9, 0.9, true)
            end

            local zone = Trim(todo.zone or "")
            if zone ~= "" then
                GameTooltip:AddLine("Zone: " .. zone, 0.7, 0.9, 1.0, true)
            end

            GameTooltip:Show()
        end)

        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

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

        self.rows[i] = row
    end

    f:Show()
end

--------------------------------------------------------------
-- Refresh main list
--------------------------------------------------------------
function Jotter:RefreshList()
    if not self.mainFrame then return end
    local todos = self.db.todos or {}

    local currentZone = self.currentZone or GetCurrentZoneName()
    local hideCompleted = self.db.settings and self.db.settings.hideCompletedOnMain

    local incomplete, complete = {}, {}

    for i, todo in ipairs(todos) do
        local zone = Trim(todo.zone or "")
        local show
        if zone == "" then
            show = true
        else
            show = (currentZone == zone)
        end
        if show then
            if todo.done then
                if not hideCompleted then
                    table.insert(complete, i)
                end
            else
                table.insert(incomplete, i)
            end
        end
    end

    local visibleIndices = {}
    for _, idx in ipairs(incomplete) do
        table.insert(visibleIndices, idx)
    end
    for _, idx in ipairs(complete) do
        table.insert(visibleIndices, idx)
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

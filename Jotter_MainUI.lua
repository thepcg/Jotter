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

    if locked then
        f:EnableMouse(false)
        f:SetMovable(false)
        f:RegisterForDrag()
        if f._resizeGrip then f._resizeGrip:Hide() end
        if f._lockHint then f._lockHint:Show() end
    else
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        if f._resizeGrip then f._resizeGrip:Show() end
        if f._lockHint then f._lockHint:Hide() end
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

local function EnsureCategoryOrderForVisibleTodos(todos)
    if not Jotter.db or not Jotter.db.settings then return end
    for _, todo in ipairs(todos) do
        local cat = Jotter:GetTodoCategory(todo)
        Jotter:EnsureCategoryInOrder(cat)
    end
end

local function BuildGroupsForZone(zoneName)
    local settings = Jotter.db and Jotter.db.settings
    if not settings then return {}, {} end

    local hideCompleted = settings.hideCompletedOnMain and true or false
    local todos = Jotter.db.todos or {}

    local groups = {}          -- map categoryName -> { indices = {...} }
    local categorySeen = {}    -- set
    local anyCategorized = false

    zoneName = Trim(zoneName or "")

    for i, todo in ipairs(todos) do
        local todoZone = Trim(todo.zone or "")
        if todoZone == zoneName then
            if (not hideCompleted) or (not todo.done) then
                local cat = Jotter:GetTodoCategory(todo)
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
    local visibleTodos = {}
    for cat, g in pairs(groups) do
        for _, idx in ipairs(g.indices) do
            table.insert(visibleTodos, todos[idx])
        end
    end
    EnsureCategoryOrderForVisibleTodos(visibleTodos)

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
    for cat, _ in pairs(categorySeen) do
        table.insert(orderedCategories, cat)
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
            local idx = selfRow.todoIndex
            if not idx then return end
            local todo = Jotter.db.todos[idx]
            if not todo then return end

            GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
            GameTooltip:SetText(todo.text or "", 1, 1, 1)

            local cat = Trim(todo.category or "")
            if cat ~= "" then
                GameTooltip:AddLine("Category: " .. cat, 0.9, 0.9, 0.9)
            end

            local desc = Trim(todo.description or "")
            if desc ~= "" then
                GameTooltip:AddLine(desc, 0.9, 0.9, 0.9, true)
            end

            local coords = Trim(todo.coords or "")
            if coords ~= "" then
                GameTooltip:AddLine("Coords: " .. coords .. " (click todo to set waypoint)", 0.7, 0.9, 1.0)
            end

            GameTooltip:AddLine("Right click + Shift: /say description", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)

        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row:SetScript("OnMouseUp", function(selfRow, button)
            local index = selfRow.todoIndex
            if not index then return end
            local todo = Jotter.db.todos[index]
            if not todo then return end

            if button == "LeftButton" then
                -- Primary UX:
                -- If coords exist, create a waypoint.
                -- Otherwise open the editor for fast edits.
                if Trim(todo.coords or "") ~= "" then
                    Jotter:CreateWaypointForTodo(todo)
                else
                    Jotter.selectedTodoIndex = index
                    Jotter:ToggleEditor(true)
                end
            elseif button == "RightButton" and IsShiftKeyDown() then
                local desc = Trim(todo.description or "")
                local sayText = desc ~= "" and desc or (todo.text or "")
                sayText = Trim(sayText)
                if sayText ~= "" then
                    SendChatMessage(sayText, "SAY")
                end
            end
        end)

        cb:SetScript("OnClick", function(selfBtn)
            local parentRow = selfBtn:GetParent()
            local index = parentRow.todoIndex
            if not index then return end
            local todo = Jotter.db.todos[index]
            if todo then
                todo.done = selfBtn:GetChecked() and true or false
                Jotter:RefreshList()
                Jotter:RefreshEditor()
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
    local zoneText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneText:SetPoint("RIGHT", -24, 0)
    zoneText:SetJustifyH("RIGHT")
    zoneText:SetText("")
    self.zoneText = zoneText

    -- Close button (explicit user hide)
    local close = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    close:SetPoint("RIGHT", -2, 0)
    close:SetScript("OnClick", function()
        Jotter:SetMainVisible(false, "user")
    end)

    -- Lock hint (shown when locked)
    local lockHint = titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lockHint:SetPoint("RIGHT", close, "LEFT", -6, 0)
    lockHint:SetText("Locked")
    lockHint:Hide()
    f._lockHint = lockHint

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

            -- Insert at top (global ordering remains stable across reloads)
            table.insert(Jotter.db.todos, 1, {
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
            Jotter:RefreshEditor()
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

    -- Empty state label (Feature 1)
    local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", 4, -4)
    empty:SetPoint("RIGHT", -4, 0)
    empty:SetJustifyH("LEFT")
    empty:SetText("No todos for this zone.")
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
    local anyTodos = false

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
        for _, todoIndex in ipairs(indices) do
            anyTodos = true
            local todo = self.db.todos[todoIndex]
            local row = AcquireRow()
            AnchorNext(row, self.rowHeightMain + self.rowGapMain)

            row.todoIndex = todoIndex
            row.check:SetChecked(todo.done and true or false)

            local text = todo.text or ""
            if todo.done then
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
                anyTodos = true

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
                    for _, todoIndex in ipairs(g.indices) do
                        local todo = self.db.todos[todoIndex]
                        local row = AcquireRow()
                        AnchorNext(row, self.rowHeightMain + self.rowGapMain)

                        row.todoIndex = todoIndex
                        row.check:SetChecked(todo.done and true or false)

                        local text = todo.text or ""
                        if todo.done then
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

    -- Feature 1: do not auto-hide when empty. Show an empty state instead.
    if not anyTodos then
        self.emptyLabel:Show()
        self.emptyLabel:SetText("No todos for this zone.")
    else
        self.emptyLabel:Hide()
    end

    -- Visibility: only hide if user explicitly hid it (close button, slash hide, minimap).
    -- RefreshList should never hide the window.
end

--[[-------------------------------------------------------------------------
    PUG Helper - UI/Window.lua
---------------------------------------------------------------------------
    The main window: frame, toolbar, left category list, and the pooled
    message pane. Renders the EFFECTIVE content (defaults + user overrides)
    for the selected instance via ns.Content.Effective.

    UI is texture-based (no :SetBackdrop) and only uses templates the client
    ships (UIPanelButtonTemplate, UIPanelCloseButton, UIPanelScrollFrameTemplate)
    per the WoW API rules in CLAUDE.md. The Set-Names panel and the in-game
    editor live in their own files and hook in through ns.UI.
---------------------------------------------------------------------------]]

local _, ns = ...
local UI = ns.UI

-- Layout constants. BUTTON_H is shared with the panels (NamesPanel/EditPanel).
local FRAME_W      = 680
local FRAME_H      = 480
local LEFT_W       = 150       -- left list column width (scrollbar sits just right of it)
local CONTENT_X    = 190
local ROW_H        = 22
local ROW_INSET    = 22
local ROW_VPAD     = 8
local HEADER_H     = 20
local SECTION_GAP  = 8
local TITLE_H      = 26
UI.BUTTON_H        = 22

UI.editMode        = false
UI.instanceButtons = {}
UI.sectionHeaders  = {}         -- section index -> header frame (rebuilt each render)
UI.drag            = nil        -- active section drag: { instanceId, fromIndex, toIndex }

-- Object pools: reuse pooled frames rather than creating new ones per render.
local rowPool, headerPool = {}, {}

-- A thin line shown between sections during a drag to mark the drop position.
local dropIndicator
local function DropIndicator()
    if not dropIndicator then
        dropIndicator = UI.scrollContent:CreateTexture(nil, "OVERLAY")
        dropIndicator:SetColorTexture(0.4, 0.8, 1.0, 0.95)
        dropIndicator:Hide()
    end
    return dropIndicator
end

-- During a drag, mark `targetIndex` (1..#sections+1) as the drop slot and draw
-- the indicator at the top edge of that section's header (or the "+ Add section"
-- row for the end slot).
function UI.SetDropTarget(targetIndex)
    if not UI.drag then return end
    UI.drag.toIndex = targetIndex
    local anchor = UI.sectionHeaders[targetIndex]
    if not anchor and targetIndex == (UI.sectionCount or 0) + 1 then
        anchor = UI.addSectionRow
    end
    local ind = DropIndicator()
    if anchor then
        ind:ClearAllPoints()
        ind:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 0)
        ind:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 0)
        ind:SetHeight(2)
        ind:Show()
    else
        ind:Hide()
    end
end

local function ClearDrop()
    if dropIndicator then dropIndicator:Hide() end
end

local function AcquireRow()
    for _, b in ipairs(rowPool) do
        if not b.inUse then b.inUse = true; b:Show(); return b end
    end
    local b = CreateFrame("Button", nil, UI.scrollContent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(true)
    hl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.4)

    local bullet = b:CreateTexture(nil, "ARTWORK")
    bullet:SetTexture("Interface\\Buttons\\UI-RadioButton")
    bullet:SetTexCoord(0, 0.25, 0, 1)
    bullet:SetSize(12, 12)
    bullet:SetPoint("TOPLEFT", 2, -4)
    b.bullet = bullet

    -- Full callout text, wrapped over as many lines as needed (no truncation).
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", bullet, "TOPRIGHT", 4, 0)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    b.label = fs

    b:SetScript("OnClick", function(self, button)
        if UI.editMode then
            if self.addSection then
                UI.OpenAddSectionEditor(self.instanceId)
            elseif self.addRow then
                UI.OpenAddEditor(self.instanceId, self.sectionIndex)
            elseif button == "RightButton" then
                UI.DeleteLine(self.instanceId, self.sectionIndex, self.lineIndex)
            else
                UI.OpenLineEditor(self.instanceId, self.sectionIndex, self.lineIndex, self.fullText)
            end
        elseif self.fullText and button == "LeftButton" then
            ns.Chat.SendLine(self.fullText)
        end
    end)
    b:SetScript("OnEnter", function(self)
        -- While dragging a section, hovering any row targets that section's slot.
        if UI.drag then
            if UI.drag.instanceId == self.instanceId then
                if self.addSection then
                    UI.SetDropTarget((UI.sectionCount or 0) + 1)
                elseif self.sectionIndex then
                    UI.SetDropTarget(self.sectionIndex)
                end
            end
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if UI.editMode then
            if self.addSection then
                GameTooltip:AddLine("Click to add a new section", 0.6, 1, 0.6)
            elseif self.addRow then
                GameTooltip:AddLine("Click to add a new line", 0.6, 1, 0.6)
            else
                GameTooltip:AddLine("Click to edit  -  Right-click to delete", 0.6, 0.8, 1)
            end
            GameTooltip:Show()
        elseif self.fullText then
            GameTooltip:AddLine("Click to send to " .. ns.Chat.ResolveChannel(), 0.6, 0.8, 1)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b.inUse = true
    table.insert(rowPool, b)
    return b
end

-- Section headers are clickable in edit mode (rename / delete section); mouse is
-- disabled in normal mode so they read as plain headers.
local function AcquireHeader()
    for _, h in ipairs(headerPool) do
        if not h.inUse then h.inUse = true; h:Show(); return h end
    end
    local h = CreateFrame("Button", nil, UI.scrollContent)
    h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    h:RegisterForDrag("LeftButton")

    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(true)
    hl:SetColorTexture(1, 0.82, 0, 0.15)

    local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", 2, 0)
    fs:SetPoint("RIGHT", -2, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetTextColor(1, 0.82, 0)
    h.label = fs

    h:SetScript("OnClick", function(self, button)
        if not UI.editMode then return end
        if button == "RightButton" then
            UI.DeleteSection(self.instanceId, self.sectionIndex)
        else
            UI.OpenSectionEditor(self.instanceId, self.sectionIndex, self.titleText)
        end
    end)
    -- Drag the section title to reorder. A click without movement still fires
    -- OnClick (rename), so the two gestures coexist.
    h:SetScript("OnDragStart", function(self)
        if not UI.editMode then return end
        UI.drag = { instanceId = self.instanceId, fromIndex = self.sectionIndex }
        self.label:SetAlpha(0.35)
        GameTooltip:Hide()
    end)
    h:SetScript("OnDragStop", function(self)
        local d = UI.drag
        UI.drag = nil
        self.label:SetAlpha(1)
        ClearDrop()
        if d and d.toIndex then
            ns.Content.MoveSection(d.instanceId, d.fromIndex, d.toIndex)
            UI.Refresh()
        end
    end)
    h:SetScript("OnEnter", function(self)
        if UI.drag then
            if UI.drag.instanceId == self.instanceId then UI.SetDropTarget(self.sectionIndex) end
            return
        end
        if not UI.editMode then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Drag to reorder  -  Click to rename  -  Right-click to delete", 1, 0.82, 0.4)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)

    h.inUse = true
    table.insert(headerPool, h)
    return h
end

local function ReleasePool()
    for _, b in ipairs(rowPool) do b.inUse = false; b:Hide() end
    for _, h in ipairs(headerPool) do h.inUse = false; h:Hide() end
end

-- Position a row, set its (already-styled) label width FIRST, then its text, so
-- GetStringHeight reflects the wrapped height. Returns the row height.
local function LayoutRow(row, width, y, text)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 6, y)
    row:SetWidth(width - 12)
    row.label:SetWidth((width - 12) - ROW_INSET)
    row.label:SetText(text)
    local rowH = math.max(row.label:GetStringHeight() + ROW_VPAD, ROW_H)
    row:SetHeight(rowH)
    return rowH
end

-- Reset a pooled row's per-render fields, then style + position it as a line.
local function PrepRow(id)
    local row = AcquireRow()
    row.addRow, row.addSection = nil, nil
    row.fullText, row.lineIndex, row.sectionIndex = nil, nil, nil
    row.instanceId = id
    return row
end

-- Rebuild the right-hand pane for the currently selected instance (effective
-- content). In edit mode each section gets a trailing "+ Add line" row, section
-- headers become clickable (rename/delete), and an "+ Add section" row is added.
function UI.Refresh()
    local sc = UI.scrollContent
    if not sc then return end
    ReleasePool()

    local id   = ns.Config.SelectedInstance()
    local inst = id and ns.Content.Effective(id)
    if type(inst) ~= "table" then
        UI.contentHeader:SetText("")
        sc:SetHeight(10)
        return
    end

    local headerText = (inst.name or "(unnamed)")
        .. (inst.note and ("  |cff999999" .. inst.note .. "|r") or "")
    if ns.Content.HasCustom(id) then
        headerText = headerText .. "  |cff66bb66(customized)|r"
    end
    UI.contentHeader:SetText(headerText)

    local sections = ns.util.asList(inst.sections)
    UI.sectionHeaders = {}
    UI.sectionCount   = #sections
    UI.addSectionRow  = nil

    local width = sc:GetWidth()
    local y = -4
    for si, section in ipairs(sections) do
        local h = AcquireHeader()
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 2, y)
        h:SetSize(math.max(width - 6, 1), HEADER_H)
        h:EnableMouse(UI.editMode)
        h.instanceId   = id
        h.sectionIndex = si
        h.titleText    = section.title or ""
        h.label:SetText(section.title or "")
        h.label:SetAlpha(1)
        UI.sectionHeaders[si] = h
        y = y - HEADER_H

        for li, line in ipairs(ns.util.asList(section.lines)) do
            local row = PrepRow(id)
            row.fullText     = line
            row.sectionIndex = si
            row.lineIndex    = li
            row.bullet:Show()
            row.bullet:SetVertexColor(0.5, 0.7, 1.0)
            row.label:SetTextColor(1, 1, 1)
            y = y - LayoutRow(row, width, y, ns.Chat.Substitute(line))
        end

        if UI.editMode then
            local add = PrepRow(id)
            add.addRow       = true
            add.sectionIndex = si
            add.bullet:Hide()
            add.label:SetTextColor(0.5, 1.0, 0.5)
            y = y - LayoutRow(add, width, y, "+ Add line")
        end

        y = y - SECTION_GAP
    end

    if UI.editMode then
        local addSec = PrepRow(id)
        addSec.addSection = true
        addSec.bullet:Hide()
        addSec.label:SetTextColor(0.5, 0.85, 1.0)
        y = y - LayoutRow(addSec, width, y, "+ Add section")
        UI.addSectionRow = addSec
    end

    -- Keep the current scroll position across edit-driven refreshes (clamped to
    -- the new range); SelectInstance resets to the top when switching tabs.
    local newHeight = math.max(-y + 4, 10)
    sc:SetHeight(newHeight)
    local sf = sc:GetParent()
    if sf and sf.SetVerticalScroll then
        local maxScroll = math.max(0, newHeight - sf:GetHeight())
        if sf:GetVerticalScroll() > maxScroll then sf:SetVerticalScroll(maxScroll) end
    end
end

function UI.SelectInstance(instanceId)
    ns.Config.SetSelectedInstance(instanceId)
    for id, btn in pairs(UI.instanceButtons) do
        if id == instanceId then btn:LockHighlight() else btn:UnlockHighlight() end
    end
    UI.Refresh()
    local sf = UI.scrollContent and UI.scrollContent:GetParent()
    if sf and sf.SetVerticalScroll then sf:SetVerticalScroll(0) end
end

function UI.UpdateChannelButton()
    if UI.channelBtn then UI.channelBtn:SetText("Channel: " .. ns.Config.Channel()) end
end

-- ---------------------------------------------------------------------------
--  Window position
-- ---------------------------------------------------------------------------
local function SavePoint()
    local point, _, relPoint, x, y = UI.frame:GetPoint()
    ns.Config.SetPoint({ point = point, relPoint = relPoint, x = x, y = y })
end

function UI.RestorePoint()
    if not UI.frame then return end
    UI.frame:ClearAllPoints()
    local p = ns.Config.Point()
    if p and p.point then
        UI.frame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    else
        UI.frame:SetPoint("CENTER")
    end
end

-- Wire mouse-wheel scrolling onto a scroll frame (the template ships a draggable
-- bar; this adds the wheel). Uses only standard ScrollFrame methods.
local function EnableWheel(scrollFrame, step)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local pos = self:GetVerticalScroll() - delta * (step or 24)
        if pos < 0 then pos = 0 elseif pos > range then pos = range end
        self:SetVerticalScroll(pos)
    end)
end

-- ---------------------------------------------------------------------------
--  Build the left category list (one header per category, then its instances).
--  Built into a scroll child (`parent`) so any number of tabs fits.
-- ---------------------------------------------------------------------------
local function BuildList(parent)
    local y = -4
    for ci, cat in ipairs(ns.Content.Categories()) do
        if ci > 1 then y = y - 12 end          -- gap between categories
        local h = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetPoint("TOPLEFT", 4, y)
        h:SetText(string.upper(cat.label or cat.id))
        y = y - 14

        for _, inst in ipairs(ns.Content.Instances(cat.id)) do
            local b = CreateFrame("Button", nil, parent)
            b:SetSize(LEFT_W - 8, ROW_H)
            b:SetPoint("TOPLEFT", 4, y)

            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(true)
            hl:SetColorTexture(0.3, 0.5, 0.9, 0.35)

            local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", 6, 0)
            fs:SetPoint("RIGHT", -4, 0)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            fs:SetText(inst.name or "(unnamed)")

            local id = inst.id
            b:SetScript("OnClick", function() UI.SelectInstance(id) end)
            b.instanceId = id
            UI.instanceButtons[id] = b
            y = y - (ROW_H + 2)
        end
    end
    parent:SetHeight(math.max(-y + 6, 10))
end

-- ---------------------------------------------------------------------------
--  Build the window (lazy, on first open)
-- ---------------------------------------------------------------------------
function UI.BuildUI()
    local mainFrame = CreateFrame("Frame", "PugHelperFrame", UIParent)
    UI.frame = mainFrame
    mainFrame:SetSize(FRAME_W, FRAME_H)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mainFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePoint() end)
    table.insert(UISpecialFrames, "PugHelperFrame")   -- closes with Escape

    local bg = mainFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(0.04, 0.04, 0.06, 0.96)

    UI.AddBorder(mainFrame, 0.25, 0.25, 0.30, 1)

    local titleBg = mainFrame:CreateTexture(nil, "ARTWORK")
    titleBg:SetPoint("TOPLEFT", 2, -2)
    titleBg:SetPoint("TOPRIGHT", -2, -2)
    titleBg:SetHeight(TITLE_H)
    titleBg:SetColorTexture(0.10, 0.10, 0.16, 1)

    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", titleBg, "LEFT", 10, 0)
    title:SetText("PUG Helper")

    local close = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() mainFrame:Hide() end)

    -- toolbar: channel + names (+ edit controls from EditPanel)
    local channelBtn = UI.Button(mainFrame, 150, UI.BUTTON_H, nil, function()
        ns.Config.CycleChannel()
        UI.UpdateChannelButton()
    end)
    channelBtn:SetPoint("TOPLEFT", 10, -32)
    UI.Tooltip(channelBtn, {
        { "Where buttons send messages", 1, 1, 1 },
        { "AUTO picks Raid > Party > Say. RAID_WARNING needs lead/assist.", 0.8, 0.8, 0.8, true },
    })
    UI.channelBtn = channelBtn
    UI.UpdateChannelButton()

    local namesBtn = UI.Button(mainFrame, 110, UI.BUTTON_H, "Set Names", function() UI.ToggleNames() end)
    namesBtn:SetPoint("LEFT", channelBtn, "RIGHT", 8, 0)

    -- Edit-mode + Reset controls (defined in UI/EditPanel.lua).
    if UI.BuildEditControls then UI.BuildEditControls(mainFrame, namesBtn) end

    -- left tab list (scrollable, so any number of raids/heroics fits)
    local listScroll = CreateFrame("ScrollFrame", "PugHelperListScroll", mainFrame, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 10, -58)
    listScroll:SetPoint("BOTTOMLEFT", 10, 12)
    listScroll:SetWidth(LEFT_W)
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(LEFT_W, 10)
    listScroll:SetScrollChild(listContent)
    EnableWheel(listScroll, 28)
    BuildList(listContent)

    -- right content header + hint
    local contentHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    contentHeader:SetPoint("TOPLEFT", CONTENT_X, -58)
    contentHeader:SetPoint("RIGHT", -16, 0)
    contentHeader:SetJustifyH("LEFT")
    contentHeader:SetText("")
    UI.contentHeader = contentHeader

    local hint = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", contentHeader, "BOTTOMLEFT", 0, -2)
    hint:SetText("Click a line to send it to chat.")
    UI.hint = hint

    local scroll = CreateFrame("ScrollFrame", "PugHelperScroll", mainFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", CONTENT_X, -92)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)

    UI.scrollContent = CreateFrame("Frame", nil, scroll)
    UI.scrollContent:SetWidth(440)
    UI.scrollContent:SetHeight(10)
    scroll:SetScrollChild(UI.scrollContent)

    scroll:SetScript("OnSizeChanged", function(_, w)
        if w and w > 1 then
            UI.scrollContent:SetWidth(w)
            UI.Refresh()
        end
    end)
    EnableWheel(scroll, 40)

    if UI.BuildNamesPanel then UI.BuildNamesPanel(mainFrame) end
    UI.RestorePoint()
    mainFrame:Hide()
end

function UI.Toggle()
    if not UI.frame then UI.BuildUI() end
    if UI.frame:IsShown() then
        UI.frame:Hide()
    else
        UI.frame:Show()
        UI.SelectInstance(ns.Config.SelectedInstance() or ns.Content.FirstInstanceId())
    end
end

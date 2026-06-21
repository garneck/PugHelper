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

-- Object pools: reuse pooled frames rather than creating new ones per render.
local rowPool, headerPool = {}, {}

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
            if self.addRow then
                UI.OpenAddEditor(self.instanceId, self.sectionTitle)
            elseif button == "RightButton" then
                UI.DeleteLine(self.instanceId, self.sectionTitle, self.meta)
            else
                UI.OpenLineEditor(self.instanceId, self.sectionTitle, self.meta, self.fullText)
            end
        elseif self.fullText and button == "LeftButton" then
            ns.Chat.SendLine(self.fullText)
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if UI.editMode then
            if self.addRow then
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

local function AcquireHeader()
    for _, h in ipairs(headerPool) do
        if not h.inUse then h.inUse = true; h:Show(); return h end
    end
    local h = UI.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetJustifyH("LEFT")
    h:SetTextColor(1, 0.82, 0)
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

-- Rebuild the right-hand pane for the currently selected instance (effective
-- content). In edit mode each section also gets a trailing "+ Add line" row.
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

    UI.contentHeader:SetText((inst.name or "(unnamed)")
        .. (inst.note and ("  |cff999999" .. inst.note .. "|r") or ""))

    local width = sc:GetWidth()
    local y = -4
    for _, section in ipairs(ns.util.asList(inst.sections)) do
        local h = AcquireHeader()
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 2, y)
        h:SetText(section.title or "")
        y = y - HEADER_H

        local meta = section.lineMeta or {}
        for i, line in ipairs(ns.util.asList(section.lines)) do
            local row = AcquireRow()
            row.addRow       = nil
            row.fullText     = line
            row.meta         = meta[i]
            row.instanceId   = id
            row.sectionTitle = section.title or ""
            row.bullet:Show()
            if row.meta and row.meta.overridden then
                row.bullet:SetVertexColor(1, 0.82, 0.2)   -- customized line
                row.label:SetTextColor(1, 0.93, 0.72)
            else
                row.bullet:SetVertexColor(0.5, 0.7, 1.0)
                row.label:SetTextColor(1, 1, 1)
            end
            y = y - LayoutRow(row, width, y, ns.Chat.Substitute(line))
        end

        if UI.editMode then
            local add = AcquireRow()
            add.addRow       = true
            add.fullText     = nil
            add.meta         = nil
            add.instanceId   = id
            add.sectionTitle = section.title or ""
            add.bullet:Hide()
            add.label:SetTextColor(0.5, 1.0, 0.5)
            y = y - LayoutRow(add, width, y, "+ Add line")
        end

        y = y - SECTION_GAP
    end

    sc:SetHeight(math.max(-y + 4, 10))
    local sf = sc:GetParent()
    if sf and sf.SetVerticalScroll then sf:SetVerticalScroll(0) end
end

function UI.SelectInstance(instanceId)
    ns.Config.SetSelectedInstance(instanceId)
    for id, btn in pairs(UI.instanceButtons) do
        if id == instanceId then btn:LockHighlight() else btn:UnlockHighlight() end
    end
    UI.Refresh()
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

    -- A 2px border edge; callers anchor it and set its own width/height.
    local function Edge()
        local t = mainFrame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.25, 0.25, 0.30, 1)
        return t
    end
    local top = Edge(); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
    local bot = Edge(); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(2)
    local lft = Edge(); lft:SetPoint("TOPLEFT"); lft:SetPoint("BOTTOMLEFT"); lft:SetWidth(2)
    local rgt = Edge(); rgt:SetPoint("TOPRIGHT"); rgt:SetPoint("BOTTOMRIGHT"); rgt:SetWidth(2)

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
    local channelBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    channelBtn:SetSize(150, UI.BUTTON_H)
    channelBtn:SetPoint("TOPLEFT", 10, -32)
    channelBtn:SetScript("OnClick", function()
        ns.Config.CycleChannel()
        UI.UpdateChannelButton()
    end)
    channelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Where buttons send messages", 1, 1, 1)
        GameTooltip:AddLine("AUTO picks Raid > Party > Say. RAID_WARNING needs lead/assist.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    channelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.channelBtn = channelBtn
    UI.UpdateChannelButton()

    local namesBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    namesBtn:SetSize(110, UI.BUTTON_H)
    namesBtn:SetPoint("LEFT", channelBtn, "RIGHT", 8, 0)
    namesBtn:SetText("Set Names")
    namesBtn:SetScript("OnClick", function() UI.ToggleNames() end)

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

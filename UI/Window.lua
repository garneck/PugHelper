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
UI.lineDrag        = nil        -- active line drag: { instanceId, sectionIndex, fromIndex, toIndex }

-- Object pools: reuse pooled frames rather than creating new ones per render.
-- A render walks each pool with a forward cursor (reset in ReleasePool), so
-- acquiring N frames is O(N) rather than re-scanning the pool for a free slot.
local rowPool, headerPool = {}, {}
local rowCursor, headerCursor = 0, 0

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

-- Cancel an in-progress drop target: the cursor left a header/row into dead
-- space, and releasing there must not reorder. Shared by the row and header
-- OnLeave handlers.
local function CancelDropTarget()
    if UI.drag then UI.drag.toIndex = nil; ClearDrop() end
end

-- During a LINE drag, mark the hovered row as the drop slot (insert before it)
-- and draw the indicator at that row's top edge. Mirrors SetDropTarget, but for
-- lines within a single section.
function UI.SetLineDropTarget(row, targetIndex)
    if not UI.lineDrag then return end
    UI.lineDrag.toIndex = targetIndex
    local ind = DropIndicator()
    ind:ClearAllPoints()
    ind:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 0, 0)
    ind:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", 0, 0)
    ind:SetHeight(2)
    ind:Show()
end

local function AcquireRow()
    rowCursor = rowCursor + 1
    local b = rowPool[rowCursor]
    if b then b:Show(); return b end
    b = CreateFrame("Button", nil, UI.scrollContent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")   -- drag a line to reorder it (edit mode only)

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
            if self.addSection or self.addRow then
                -- Add rows act on left-click only; ignore other buttons so a
                -- right-click can't fall through to the delete branch below (which
                -- would target a nil line index and remove the section's last line).
                if button ~= "LeftButton" then return end
                if self.addSection then
                    UI.OpenAddSectionEditor(self.instanceId)
                else
                    UI.OpenAddEditor(self.instanceId, self.sectionIndex)
                end
            elseif button == "RightButton" then
                UI.DeleteLine(self.instanceId, self.sectionIndex, self.lineIndex, self.fullText)
            elseif self.lineIndex and ns.api.ControlDown() then
                ns.Content.DuplicateLine(self.instanceId, self.sectionIndex, self.lineIndex)
                UI.Refresh()
            else
                UI.OpenLineEditor(self.instanceId, self.sectionIndex, self.lineIndex, self.fullText)
            end
        elseif self.fullText and button == "LeftButton" then
            ns.Chat.SendLine(self.fullText)
        end
    end)
    -- Drag a line to reorder it within its section (mirrors section-title drag).
    -- A click without movement still fires OnClick, so edit/delete/duplicate work.
    b:SetScript("OnDragStart", function(self)
        if not UI.editMode or not self.lineIndex then return end
        UI.lineDrag = { instanceId = self.instanceId, sectionIndex = self.sectionIndex, fromIndex = self.lineIndex }
        self.label:SetAlpha(0.35)
        GameTooltip:Hide()
    end)
    b:SetScript("OnDragStop", function(self)
        local d = UI.lineDrag
        UI.lineDrag = nil
        self.label:SetAlpha(1)
        ClearDrop()
        if d and d.toIndex then
            ns.Content.MoveLine(d.instanceId, d.sectionIndex, d.fromIndex, d.toIndex)
            UI.Refresh()
        end
    end)
    b:SetScript("OnEnter", function(self)
        -- While dragging a line, hovering a row / add-row in the SAME section
        -- marks the drop slot.
        if UI.lineDrag then
            if UI.lineDrag.instanceId == self.instanceId
                and UI.lineDrag.sectionIndex == self.sectionIndex then
                if self.lineIndex then
                    UI.SetLineDropTarget(self, self.lineIndex)
                elseif self.addRow then
                    UI.SetLineDropTarget(self, (self.lineCount or 0) + 1)
                end
            end
            return
        end
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
                GameTooltip:AddLine("Drag to reorder  -  Ctrl-click to duplicate", 0.6, 0.8, 1)
            end
            GameTooltip:Show()
        elseif self.fullText then
            GameTooltip:AddLine("Click to send to " .. ns.Chat.ResolveChannel(), 0.6, 0.8, 1)
            if self.unresolved then
                GameTooltip:AddLine("Unset: " .. self.unresolved .. " - pick names in Set Names.", 1, 0.6, 0.1, true)
            end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
        CancelDropTarget()
        if UI.lineDrag then UI.lineDrag.toIndex = nil; ClearDrop() end
    end)

    rowPool[rowCursor] = b
    return b
end

-- Section headers are clickable in edit mode (rename / delete section); mouse is
-- disabled in normal mode so they read as plain headers.
local function AcquireHeader()
    headerCursor = headerCursor + 1
    local h = headerPool[headerCursor]
    if h then h:Show(); return h end
    h = CreateFrame("Button", nil, UI.scrollContent)
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
            UI.DeleteSection(self.instanceId, self.sectionIndex, self.titleText)
        elseif ns.api.ControlDown() then
            ns.Content.DuplicateSection(self.instanceId, self.sectionIndex)
            UI.Refresh()
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
        GameTooltip:AddLine("Ctrl-click to duplicate this section", 1, 0.82, 0.4)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function()
        GameTooltip:Hide()
        CancelDropTarget()
    end)

    headerPool[headerCursor] = h
    return h
end

local function ReleasePool()
    for _, b in ipairs(rowPool) do b:Hide() end
    for _, h in ipairs(headerPool) do h:Hide() end
    rowCursor, headerCursor = 0, 0
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
    row.unresolved, row.lineCount = nil, nil
    row.label:SetAlpha(1)
    row:EnableMouse(true)
    row.instanceId = id
    return row
end

-- Rebuild the right-hand pane for the currently selected instance (effective
-- content). In edit mode each section gets a trailing "+ Add line" row, section
-- headers become clickable (rename/delete), and an "+ Add section" row is added.
function UI.Refresh(preserveEditor)
    local sc = UI.scrollContent
    if not sc then return end
    -- A structural rebuild (edit, tab switch, reset, toggle) invalidates the
    -- editor popup's target indices, so dismiss it rather than let Save misfire.
    -- A cosmetic refresh (resize, name set) passes preserveEditor to leave an open
    -- edit in place, since it changes no content the popup is bound to.
    if not preserveEditor and UI.CloseEditPopup then UI.CloseEditPopup() end
    -- A full rebuild also invalidates the display indices any in-flight drag was
    -- started against; clear any drag still marked active as a defensive guard so a
    -- rebuild can never leave the pane stuck in phantom-drag mode.
    UI.drag, UI.lineDrag = nil, nil
    ClearDrop()
    ReleasePool()

    local id   = ns.Config.SelectedInstance()
    local inst = id and ns.Content.Effective(id)
    if type(inst) ~= "table" then
        UI.contentHeader:SetText("")
        sc:SetHeight(10)
        return
    end

    local headerText = (inst.name or "(unnamed)")
        -- Escape any literal '|' in the note (e.g. "25-player | Phase 1") to '||',
        -- or WoW's FontString parser eats it as a stray color/escape lead.
        .. (inst.note and ("  |cff999999" .. inst.note:gsub("|", "||") .. "|r") or "")
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

        local lines = ns.util.asList(section.lines)
        for li, line in ipairs(lines) do
            local row = PrepRow(id)
            row.fullText     = line
            row.sectionIndex = si
            row.lineIndex    = li
            row.bullet:Show()
            row.label:SetTextColor(1, 1, 1)
            -- After substitution, any remaining {TOKEN} is an unset name that
            -- would be sent literally: flag the bullet amber and remember which.
            local shown = ns.Chat.Substitute(line)
            local unset
            for tok in shown:gmatch("{(%w+)}") do
                unset = unset and (unset .. ", {" .. tok .. "}") or ("{" .. tok .. "}")
            end
            row.unresolved = unset
            if unset then
                row.bullet:SetVertexColor(1, 0.6, 0.1)
            else
                row.bullet:SetVertexColor(0.5, 0.7, 1.0)
            end
            y = y - LayoutRow(row, width, y, shown)
        end

        -- Empty boss in normal mode: a dim, non-clickable nudge toward Edit (edit
        -- mode shows the "+ Add line" row below instead).
        if #lines == 0 and not UI.editMode then
            local empty = PrepRow(id)
            empty.bullet:Hide()
            empty:EnableMouse(false)
            empty.label:SetTextColor(0.5, 0.5, 0.5)
            y = y - LayoutRow(empty, width, y, "(no callouts yet - turn on Edit to add some)")
        end

        if UI.editMode then
            local add = PrepRow(id)
            add.addRow       = true
            add.sectionIndex = si
            add.lineCount    = #lines
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
    -- Per-raid custom roles are tied to the selected tab, so keep the Set Names
    -- panel in sync when it's open (cheap no-op while it's hidden).
    if UI.RefreshNamesPanel then UI.RefreshNamesPanel() end
    local sf = UI.scrollContent and UI.scrollContent:GetParent()
    if sf and sf.SetVerticalScroll then sf:SetVerticalScroll(0) end
end

-- Show the configured channel and, when it differs, the channel a send would
-- ACTUALLY land in right now (AUTO's pick, or a downgrade when a manual channel's
-- group state isn't met). Kept current by the group/leader watcher in BuildUI.
function UI.UpdateChannelButton()
    if not UI.channelBtn then return end
    local cfg = ns.Config.Channel()
    local res = ns.Chat.ResolveChannel()
    local txt = "Channel: " .. cfg
    if res ~= cfg then
        local code = (cfg == "AUTO") and "ff88dd88" or "ffffaa33"
        txt = txt .. " |c" .. code .. "> " .. res .. "|r"
    end
    UI.channelBtn:SetText(txt)
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

-- ---------------------------------------------------------------------------
--  Build the left category list (one header per category, then its instances).
--  Built into a scroll child (`parent`) so any number of tabs fits.
-- ---------------------------------------------------------------------------
-- Lay out the left list, showing only instances whose name contains `filter`
-- (nil/"" = all) and only the category headers that still have a match. The
-- buttons/headers are created once (BuildList); this just shows/positions them,
-- so it's cheap to run on every keystroke. Selection highlight lives on the
-- persistent buttons and is untouched here.
function UI.LayoutList(filter)
    if filter == "" then filter = nil end
    local parent = UI.listContent
    if not parent then return end
    local y, first, anyShown = -4, true, false
    for _, group in ipairs(UI.listGroups or {}) do
        local shown = {}
        for _, b in ipairs(group.buttons) do
            if not filter or b.searchName:find(filter, 1, true) then
                shown[#shown + 1] = b
            else
                b:Hide()
            end
        end
        if #shown == 0 then
            group.header:Hide()
        else
            if not first then y = y - 12 end   -- gap between categories
            first = false
            group.header:ClearAllPoints()
            group.header:SetPoint("TOPLEFT", 4, y)
            group.header:Show()
            y = y - 14
            for _, b in ipairs(shown) do
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 4, y)
                b:Show()
                y = y - (ROW_H + 2)
            end
            anyShown = true
        end
    end
    if not anyShown then
        if not UI.listEmpty then
            UI.listEmpty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            UI.listEmpty:SetPoint("TOPLEFT", 6, -6)
            UI.listEmpty:SetWidth(LEFT_W - 12)
            UI.listEmpty:SetJustifyH("LEFT")
            UI.listEmpty:SetWordWrap(true)
        end
        UI.listEmpty:SetText("(no matches)")
        UI.listEmpty:Show()
    elseif UI.listEmpty then
        UI.listEmpty:Hide()
    end
    parent:SetHeight(math.max(-y + 6, 10))
end

-- Build every category header + instance button once into the scroll child,
-- grouped so UI.LayoutList can filter them.
local function BuildList(parent)
    UI.listContent = parent
    UI.listGroups  = {}
    for _, cat in ipairs(ns.Content.Categories()) do
        local h = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetText(string.upper(cat.label or cat.id))
        local group = { header = h, buttons = {} }

        for _, inst in ipairs(ns.Content.Instances(cat.id)) do
            local b = CreateFrame("Button", nil, parent)
            b:SetSize(LEFT_W - 8, ROW_H)

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
            b.searchName = (inst.name or ""):lower()
            UI.instanceButtons[id] = b
            group.buttons[#group.buttons + 1] = b
        end
        UI.listGroups[#UI.listGroups + 1] = group
    end
    UI.LayoutList(nil)
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
    -- A confirm dialog lives at UIParent (so it floats above everything), so an
    -- Escape-close of the window would otherwise strand it on screen; hide it
    -- whenever the window hides.
    mainFrame:SetScript("OnHide", function()
        if UI.HideConfirm then UI.HideConfirm() end
        -- Close the editor popup too (it's a child of this frame): clears its shown
        -- flag so a reopen doesn't briefly re-show it, and drops its modal blocker.
        if UI.CloseEditPopup then UI.CloseEditPopup() end
    end)
    table.insert(UISpecialFrames, "PugHelperFrame")   -- closes with Escape

    UI.Background(mainFrame, 0.04, 0.04, 0.06, 0.96)
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
    local channelBtn = UI.Button(mainFrame, 170, UI.BUTTON_H, nil, function()
        ns.Config.CycleChannel()
        UI.UpdateChannelButton()
    end)
    channelBtn:SetPoint("TOPLEFT", 10, -32)
    -- Dynamic tooltip: rebuilt each hover so it names where a send lands right now.
    channelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Output channel", 1, 1, 1)
        local cfg, res = ns.Config.Channel(), ns.Chat.ResolveChannel()
        if res ~= cfg then
            GameTooltip:AddLine("Set to " .. cfg .. ", sending to " .. res .. " right now.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("Sending to " .. res .. " right now.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine("AUTO picks Raid > Party > Say. RAID_WARNING only delivers if you're raid lead/assist.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Click to change.", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    channelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.channelBtn = channelBtn
    UI.UpdateChannelButton()

    -- Keep the resolved channel (and, while open, the Set Names roster dropdowns)
    -- current as the group / leadership changes - same event pattern as Boot.lua.
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
    watcher:RegisterEvent("PARTY_LEADER_CHANGED")
    watcher:SetScript("OnEvent", function()
        UI.UpdateChannelButton()
        if UI.RefreshNamesPanel then UI.RefreshNamesPanel() end
    end)
    UI.watcher = watcher

    -- "Editing" badge (top-right), shown only in edit mode (toggled in EditPanel).
    local editTag = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editTag:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -34, -36)
    editTag:SetText("\226\151\143 EDITING")
    editTag:SetTextColor(1, 0.6, 0.1)
    editTag:Hide()
    UI.editTag = editTag

    local namesBtn = UI.Button(mainFrame, 110, UI.BUTTON_H, "Set Names", function() UI.ToggleNames() end)
    namesBtn:SetPoint("LEFT", channelBtn, "RIGHT", 8, 0)

    -- Edit-mode + Reset controls (defined in UI/EditPanel.lua).
    if UI.BuildEditControls then UI.BuildEditControls(mainFrame, namesBtn) end

    -- search box above the tab list (filters the raids/heroics list as you type)
    local searchBox = UI.MakeInput(mainFrame, LEFT_W - 4, 0, nil)
    searchBox:SetPoint("TOPLEFT", 12, -58)
    local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", 4, 0)
    searchHint:SetText("Search...")
    searchBox:SetScript("OnTextChanged", function(self)
        local t = self:GetText()
        if t ~= "" then searchHint:Hide() else searchHint:Show() end
        UI.LayoutList(t:lower())
    end)
    searchBox:SetScript("OnEditFocusGained", function() searchHint:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then searchHint:Show() end
    end)
    UI.searchBox = searchBox

    -- left tab list (scrollable, so any number of raids/heroics fits)
    local listScroll = CreateFrame("ScrollFrame", "PugHelperListScroll", mainFrame, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 10, -84)
    listScroll:SetPoint("BOTTOMLEFT", 10, 12)
    listScroll:SetWidth(LEFT_W)
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(LEFT_W, 10)
    listScroll:SetScrollChild(listContent)
    UI.EnableWheel(listScroll, 28)
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
    hint:SetText("Click a line to send it. {TOKENS} like {MT} fill in from Set Names.")
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
            UI.Refresh(true)   -- preserve any open edit across a resize
        end
    end)
    UI.EnableWheel(scroll, 40)

    if UI.BuildNamesPanel then UI.BuildNamesPanel(mainFrame) end
    UI.RestorePoint()
    mainFrame:Hide()
end

-- Bring the window up (building it on first use) and select the resolved
-- instance. The single "open the window" sequence, shared by Toggle and the
-- slash commands so neither re-implements it.
function UI.Open()
    if not UI.frame then UI.BuildUI() end
    if not UI.frame:IsShown() then
        UI.frame:Show()
        UI.SelectInstance(ns.Content.ResolveSelectedInstance())
    end
end

function UI.Toggle()
    if UI.frame and UI.frame:IsShown() then
        UI.frame:Hide()
    else
        UI.Open()
    end
end

--[[-------------------------------------------------------------------------
    PUG Helper - UI/EditPanel.lua
---------------------------------------------------------------------------
    In-game callout editor. An "Edit" toggle in the toolbar flips the message
    pane into edit mode (see UI/Window.lua): clicking a line edits it,
    right-clicking deletes it, and each section gains a "+ Add line" row. All
    edits go through ns.Content (which persists them in PugHelperDB), then the
    pane refreshes.

    Uses only proven/standard API: a plain multiline EditBox with a texture
    background and UIPanelButtonTemplate buttons. No :SetBackdrop, no exotic
    templates (per CLAUDE.md WoW API rules).
---------------------------------------------------------------------------]]

local _, ns = ...
local UI = ns.UI

-- Strip newlines/tabs so a callout always stays a single chat line.
local function sanitize(text)
    text = tostring(text or ""):gsub("[\r\n\t]+", " ")
    return ns.util.trim(text)
end

-- ---------------------------------------------------------------------------
--  Shared edit popup (built once, reused for edit + add)
-- ---------------------------------------------------------------------------
local popup

local function BuildPopup()
    local p = CreateFrame("Frame", nil, UI.frame)
    p:SetFrameStrata("DIALOG")
    p:SetSize(440, 200)
    p:SetPoint("CENTER")
    p:EnableMouse(true)
    p:SetFrameLevel(UI.frame:GetFrameLevel() + 200)

    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.98)

    local function Edge()
        local t = p:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.3, 0.3, 0.36, 1)
        return t
    end
    local top = Edge(); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
    local bot = Edge(); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(2)
    local lft = Edge(); lft:SetPoint("TOPLEFT"); lft:SetPoint("BOTTOMLEFT"); lft:SetWidth(2)
    local rgt = Edge(); rgt:SetPoint("TOPRIGHT"); rgt:SetPoint("BOTTOMRIGHT"); rgt:SetWidth(2)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    p.title = title

    -- Edit box with its own dark inset background for readability.
    local boxBg = p:CreateTexture(nil, "BORDER")
    boxBg:SetPoint("TOPLEFT", 12, -40)
    boxBg:SetPoint("BOTTOMRIGHT", -12, 44)
    boxBg:SetColorTexture(0, 0, 0, 0.5)

    local edit = CreateFrame("EditBox", nil, p)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetMaxLetters(500)
    edit:SetTextInsets(6, 6, 6, 6)
    edit:SetJustifyH("LEFT")
    edit:SetPoint("TOPLEFT", boxBg, "TOPLEFT", 2, -2)
    edit:SetPoint("BOTTOMRIGHT", boxBg, "BOTTOMRIGHT", -2, 2)
    edit:SetScript("OnEscapePressed", function() p:Hide() end)
    p.edit = edit

    local save = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    save:SetSize(90, UI.BUTTON_H)
    save:SetPoint("BOTTOMRIGHT", -14, 12)
    save:SetText("Save")
    save:SetScript("OnClick", function()
        if p.onSave then p.onSave(edit:GetText()) end
        p:Hide()
    end)

    local cancel = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    cancel:SetSize(90, UI.BUTTON_H)
    cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function() p:Hide() end)

    p:Hide()
    return p
end

local function OpenPopup(titleText, initialText, onSave)
    popup = popup or BuildPopup()
    popup.title:SetText(titleText)
    popup.onSave = onSave
    popup.edit:SetText(initialText or "")
    popup:Show()
    popup.edit:SetFocus()
    popup.edit:SetCursorPosition(#(initialText or ""))
end

-- ---------------------------------------------------------------------------
--  Editor actions (called from message rows in edit mode)
-- ---------------------------------------------------------------------------
function UI.OpenLineEditor(instanceId, sectionTitle, meta, currentText)
    OpenPopup("Edit line  -  " .. (sectionTitle or ""), currentText, function(text)
        ns.Content.SetLine(instanceId, sectionTitle, meta, sanitize(text))
        UI.Refresh()
    end)
end

function UI.OpenAddEditor(instanceId, sectionTitle)
    OpenPopup("Add line  -  " .. (sectionTitle or ""), "", function(text)
        ns.Content.AddLine(instanceId, sectionTitle, sanitize(text))
        UI.Refresh()
    end)
end

function UI.DeleteLine(instanceId, sectionTitle, meta)
    ns.Content.DeleteLine(instanceId, sectionTitle, meta)
    UI.Refresh()
end

-- ---------------------------------------------------------------------------
--  Toolbar controls + edit-mode toggle
-- ---------------------------------------------------------------------------
function UI.ToggleEdit()
    UI.editMode = not UI.editMode
    if UI.editBtn then UI.editBtn:SetText(UI.editMode and "Edit: ON" or "Edit: OFF") end
    if UI.resetBtn then
        if UI.editMode then UI.resetBtn:Show() else UI.resetBtn:Hide() end
    end
    if UI.hint then
        UI.hint:SetText(UI.editMode
            and "Edit mode: click a line to edit, right-click to delete."
            or  "Click a line to send it to chat.")
    end
    if popup then popup:Hide() end
    UI.Refresh()
end

function UI.BuildEditControls(parent, after)
    local editBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    editBtn:SetSize(90, UI.BUTTON_H)
    editBtn:SetPoint("LEFT", after, "RIGHT", 8, 0)
    editBtn:SetText("Edit: OFF")
    editBtn:SetScript("OnClick", UI.ToggleEdit)
    editBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Customize callouts", 1, 1, 1)
        GameTooltip:AddLine("Edit or delete lines and add your own. Changes are saved per tab.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    editBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.editBtn = editBtn

    local resetBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    resetBtn:SetSize(110, UI.BUTTON_H)
    resetBtn:SetPoint("LEFT", editBtn, "RIGHT", 8, 0)
    resetBtn:SetText("Reset tab")
    resetBtn:SetScript("OnClick", function()
        local id = ns.Config.SelectedInstance()
        if id then
            ns.Content.ResetInstance(id)
            UI.Refresh()
        end
    end)
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Restore this tab's built-in callouts", 1, 1, 1)
        GameTooltip:AddLine("Removes all your edits, additions, and deletions for the selected tab.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    resetBtn:Hide()
    UI.resetBtn = resetBtn

    return editBtn
end

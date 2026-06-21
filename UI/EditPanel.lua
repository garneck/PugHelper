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

    UI.Background(p, 0.05, 0.05, 0.08, 0.98)
    UI.AddBorder(p, 0.3, 0.3, 0.36, 1)

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

    local save = UI.Button(p, 90, UI.BUTTON_H, "Save", function()
        if p.onSave then p.onSave(edit:GetText()) end
        p:Hide()
    end)
    save:SetPoint("BOTTOMRIGHT", -14, 12)

    local cancel = UI.Button(p, 90, UI.BUTTON_H, "Cancel", function() p:Hide() end)
    cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)

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

-- Dismiss the editor popup. UI.Refresh calls this so a popup can never outlive
-- the content it was opened against (e.g. after a tab switch or Reset tab),
-- which would otherwise let Save write to the wrong instance/index.
function UI.CloseEditPopup()
    if popup then popup:Hide() end
end

-- ---------------------------------------------------------------------------
--  Editor actions (called from message rows / section headers in edit mode).
--  Sections and lines are addressed by their current display index.
-- ---------------------------------------------------------------------------
function UI.OpenLineEditor(instanceId, sectionIndex, lineIndex, currentText)
    OpenPopup("Edit line", currentText, function(text)
        ns.Content.SetLine(instanceId, sectionIndex, lineIndex, sanitize(text))
        UI.Refresh()
    end)
end

function UI.OpenAddEditor(instanceId, sectionIndex)
    OpenPopup("Add line", "", function(text)
        ns.Content.AddLine(instanceId, sectionIndex, sanitize(text))
        UI.Refresh()
    end)
end

function UI.DeleteLine(instanceId, sectionIndex, lineIndex)
    ns.Content.DeleteLine(instanceId, sectionIndex, lineIndex)
    UI.Refresh()
end

function UI.OpenSectionEditor(instanceId, sectionIndex, currentTitle)
    OpenPopup("Rename section", currentTitle, function(text)
        ns.Content.SetSectionTitle(instanceId, sectionIndex, sanitize(text))
        UI.Refresh()
    end)
end

function UI.OpenAddSectionEditor(instanceId)
    OpenPopup("New section title", "", function(text)
        ns.Content.AddSection(instanceId, sanitize(text))
        UI.Refresh()
    end)
end

function UI.DeleteSection(instanceId, sectionIndex)
    ns.Content.DeleteSection(instanceId, sectionIndex)
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
            and "Edit mode: drag a section title to reorder; click to edit, right-click to delete."
            or  "Click a line to send it to chat.")
    end
    if popup then popup:Hide() end
    UI.Refresh()
end

function UI.BuildEditControls(parent, after)
    local editBtn = UI.Button(parent, 90, UI.BUTTON_H, "Edit: OFF", UI.ToggleEdit)
    editBtn:SetPoint("LEFT", after, "RIGHT", 8, 0)
    UI.Tooltip(editBtn, {
        { "Customize callouts", 1, 1, 1 },
        { "Edit/add/delete lines and rename, add, or remove sections. Changes are saved per tab.", 0.8, 0.8, 0.8, true },
    })
    UI.editBtn = editBtn

    local resetBtn = UI.Button(parent, 110, UI.BUTTON_H, "Reset tab", function()
        local id = ns.Config.SelectedInstance()
        if id then
            ns.Content.ResetInstance(id)
            UI.Refresh()
        end
    end)
    resetBtn:SetPoint("LEFT", editBtn, "RIGHT", 8, 0)
    UI.Tooltip(resetBtn, {
        { "Restore this tab's built-in callouts", 1, 1, 1 },
        { "Removes all your edits, additions, and deletions for the selected tab.", 0.8, 0.8, 0.8, true },
    })
    resetBtn:Hide()
    UI.resetBtn = resetBtn

    return editBtn
end

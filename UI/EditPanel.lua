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

-- ---------------------------------------------------------------------------
--  Shared edit popup (built once, reused for edit + add)
-- ---------------------------------------------------------------------------
local popup

local function BuildPopup()
    local p = CreateFrame("Frame", nil, UI.frame)
    p:SetFrameStrata("DIALOG")
    p:SetSize(440, 240)
    p:SetPoint("CENTER")
    p:EnableMouse(true)
    p:SetFrameLevel(UI.frame:GetFrameLevel() + 200)

    UI.Background(p, 0.05, 0.05, 0.08, 0.98)
    UI.AddBorder(p, 0.3, 0.3, 0.36, 1)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    p.title = title

    -- Edit box with its own dark inset background for readability. The bottom
    -- anchor is re-set per OpenPopup so the live preview can sit below it.
    local boxBg = p:CreateTexture(nil, "BORDER")
    boxBg:SetPoint("TOPLEFT", 12, -40)
    boxBg:SetPoint("BOTTOMRIGHT", -12, 92)
    boxBg:SetColorTexture(0, 0, 0, 0.5)
    p.boxBg = boxBg

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

    -- Live preview of the resolved callout (tokens filled from Set Names; any
    -- still-unset {TOKEN} highlighted). Shown only for line edit/add.
    local previewCap = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    previewCap:SetPoint("TOPLEFT", boxBg, "BOTTOMLEFT", 2, -6)
    previewCap:SetText("Preview")
    p.previewCap = previewCap

    local previewText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewText:SetPoint("TOPLEFT", previewCap, "BOTTOMLEFT", 0, -2)
    previewText:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    previewText:SetJustifyH("LEFT")
    previewText:SetWordWrap(true)
    p.previewText = previewText

    edit:SetScript("OnTextChanged", function(self)
        if not p.showPreview then return end
        -- Cap the previewed text so a very long callout can't grow the preview down
        -- over the Save/Cancel buttons; the edit box itself keeps the full text.
        local raw = self:GetText()
        if #raw > 160 then raw = raw:sub(1, 160) .. "..." end
        local resolved = ns.Chat.Substitute(raw)
        resolved = resolved:gsub("{(%w+)}", "|cffff8800{%1}|r")
        previewText:SetText(resolved)
    end)

    local save = UI.Button(p, 90, UI.BUTTON_H, "Save", function()
        if p.onSave then p.onSave(edit:GetText()) end
        p:Hide()
    end)
    save:SetPoint("BOTTOMRIGHT", -14, 12)

    local cancel = UI.Button(p, 90, UI.BUTTON_H, "Cancel", function() p:Hide() end)
    cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)

    -- Modal: while the editor is open nothing behind it is clickable, so an
    -- unrelated gesture (deleting another line, switching tab, Set Names, etc.)
    -- can't trigger a refresh that silently discards the in-progress edit. The
    -- user must Save, Cancel, or Escape first.
    UI.MakeModal(p)

    p:Hide()
    return p
end

local function OpenPopup(titleText, initialText, onSave, showPreview)
    local text = initialText or ""
    popup = popup or BuildPopup()
    popup.title:SetText(titleText)
    popup.onSave = onSave
    popup.showPreview = showPreview and true or false
    -- Make room for the preview only when it's shown (section title popups don't).
    popup.boxBg:SetPoint("BOTTOMRIGHT", -12, showPreview and 92 or 44)
    if showPreview then
        popup.previewCap:Show()
        popup.previewText:Show()
    else
        popup.previewCap:Hide()
        popup.previewText:Hide()
    end
    popup.edit:SetText(text)   -- fires OnTextChanged, which refreshes the preview
    popup:Show()
    popup.edit:SetFocus()
    popup.edit:SetCursorPosition(#text)
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
        ns.Content.SetLine(instanceId, sectionIndex, lineIndex, text)
        UI.Refresh()
    end, true)
end

function UI.OpenAddEditor(instanceId, sectionIndex)
    OpenPopup("Add line", "", function(text)
        ns.Content.AddLine(instanceId, sectionIndex, text)
        UI.Refresh()
    end, true)
end

-- Right-click delete is confirmed first so a stray click can't drop a callout.
-- The line's text (trimmed for the dialog) is shown so you delete the right one.
function UI.DeleteLine(instanceId, sectionIndex, lineIndex, preview)
    preview = tostring(preview or "")
    if #preview > 120 then preview = preview:sub(1, 120) .. "..." end
    local msg = "Delete this line?"
    if preview ~= "" then msg = msg .. "\n\n|cffffd200" .. preview .. "|r" end
    UI.Confirm(msg, function()
        ns.Content.DeleteLine(instanceId, sectionIndex, lineIndex)
        UI.Refresh()
    end, "Delete")
end

function UI.OpenSectionEditor(instanceId, sectionIndex, currentTitle)
    OpenPopup("Rename section", currentTitle, function(text)
        ns.Content.SetSectionTitle(instanceId, sectionIndex, text)
        UI.Refresh()
    end)
end

function UI.OpenAddSectionEditor(instanceId)
    OpenPopup("New section title", "", function(text)
        ns.Content.AddSection(instanceId, text)
        UI.Refresh()
    end)
end

function UI.DeleteSection(instanceId, sectionIndex, title)
    title = tostring(title or "")
    local what = (title ~= "") and ('the section "' .. title .. '"') or "this section"
    UI.Confirm("Delete " .. what .. " and all of its lines?", function()
        ns.Content.DeleteSection(instanceId, sectionIndex)
        UI.Refresh()
    end, "Delete")
end

-- ---------------------------------------------------------------------------
--  Toolbar controls + edit-mode toggle
-- ---------------------------------------------------------------------------
function UI.ToggleEdit()
    UI.editMode = not UI.editMode
    if UI.editBtn then
        UI.editBtn:SetText(UI.editMode and "Edit: ON" or "Edit: OFF")
        if UI.editMode then UI.editBtn:LockHighlight() else UI.editBtn:UnlockHighlight() end
    end
    if UI.editTag then
        if UI.editMode then UI.editTag:Show() else UI.editTag:Hide() end
    end
    if UI.resetBtn then
        if UI.editMode then UI.resetBtn:Show() else UI.resetBtn:Hide() end
    end
    if UI.hint then
        UI.hint:SetText(UI.editMode
            and "Edit mode: drag lines/sections to reorder; click to edit, right-click to delete, Ctrl-click to duplicate."
            or  "Click a line to send it. {TOKENS} like {MT} fill in from Set Names.")
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
        if not id then return end
        -- Reset tab drops ALL of this tab's edits/additions/deletions, so it is
        -- confirmed like every other destructive action (shared UI.Confirm).
        local name = ns.Content.InstanceName(id, "this tab")
        UI.Confirm("Restore the built-in callouts for " .. name
            .. " and discard all your edits, additions, and deletions for it?",
            function()
                ns.Content.ResetInstance(id)
                UI.Refresh()
            end, "Reset tab")
    end)
    resetBtn:SetPoint("LEFT", editBtn, "RIGHT", 8, 0)
    UI.Tooltip(resetBtn, {
        { "Restore this tab's built-in callouts", 1, 1, 1 },
        { "Removes all your edits, additions, and deletions for the selected tab.", 0.8, 0.8, 0.8, true },
    })
    resetBtn:Hide()
    UI.resetBtn = resetBtn
end

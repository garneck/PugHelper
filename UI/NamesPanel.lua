--[[-------------------------------------------------------------------------
    PUG Helper - UI/NamesPanel.lua
---------------------------------------------------------------------------
    The "Set Names" overlay: one row per role token (a name dropdown populated
    live from the current party/raid), plus an "add a custom role" control.

    Roles come from ns.Content.EffectiveRoles(selectedInstance): the built-ins
    (Content/Roles.lua), the user's global custom roles, and the custom roles
    scoped to the currently selected raid tab - returned in the user's saved
    per-tab order, with any per-tab label override applied. The row list is
    rebuilt whenever roles change (add/remove/edit/reorder) or the tab switches,
    reusing pooled widgets so the named dropdown frames are never duplicated.

    Each row can be:
      - assigned a name (the dropdown),
      - deleted (the X),
      - edited (the Edit button, or clicking the row): rename the label, and for
        a custom role change its {TOKEN} too - via ns.Content.EditRole,
      - reordered (drag the row): ns.Content.MoveRole, with a drop indicator and a
        trailing end-zone for "move to the bottom". Mirrors the section/line drag
        in UI/Window.lua.

    Names are read/written through ns.Config (never PugHelperDB directly) and are
    keyed by bare token, so a name picked here fills {TOKEN} everywhere.

    Uses only proven/standard API: UIPanelScrollFrameTemplate, UIDropDownMenu_*
    helpers, plain CreateFrame("EditBox") inputs, and the shared UI builders
    (per the WoW API rules in CLAUDE.md). No :SetBackdrop, no exotic templates.
---------------------------------------------------------------------------]]

local _, ns = ...
local UI = ns.UI
local T  = UI.Theme   -- design tokens (colours / sizes / fonts)

local STEP       = 30   -- minimum role row height (a single text line)
local DD_W       = 100  -- dropdown selected-text width
local LABEL_X    = 72   -- role label x: right of the delete X + Edit button (label is first)
local DD_RESERVE = 165  -- right-side room reserved for the dropdown + edge margin

-- Shared dropdown initializer. UIDropDownMenu_Initialize calls this with the
-- dropdown frame each time the menu opens, so it reads the row's CURRENT token
-- (set on rebuild) rather than capturing a stale one. Lists the live roster plus
-- a "(clear)" entry; selecting writes the name through Config keyed by token.
local function InitNameDropdown(dropdown)
    local token = dropdown.token
    if not token then return end
    for _, name in ipairs(ns.api.GroupRoster()) do
        local info = UIDropDownMenu_CreateInfo()
        info.text    = name
        info.checked = (ns.Config.GetName(token) == name)
        info.func    = function()
            ns.Config.SetName(token, name)
            UIDropDownMenu_SetText(dropdown, name)
            if UI.RebuildRoleRows then UI.RebuildRoleRows() end   -- flip the row's unset cue now
        end
        UIDropDownMenu_AddButton(info)
    end
    local clearInfo = UIDropDownMenu_CreateInfo()
    clearInfo.text         = T.colorize(T.color.muted, "(clear)")
    clearInfo.notCheckable = true
    clearInfo.func         = function()
        ns.Config.SetName(token, "")
        UIDropDownMenu_SetText(dropdown, "")
        if UI.RebuildRoleRows then UI.RebuildRoleRows() end
    end
    UIDropDownMenu_AddButton(clearInfo)
end

-- (The single-line input builder lives in UI/Helpers.lua as UI.MakeInput.)

-- ---------------------------------------------------------------------------
--  Drag-to-reorder: a single drop indicator line, mirroring UI/Window.lua.
-- ---------------------------------------------------------------------------
-- UI.roleDrag holds the active drag: { instanceId, fromIndex, toIndex }.
local roleDropIndicator

local function RoleDropIndicator()
    local panel = UI.namesPanel
    if not panel or not panel.scrollChild then return nil end
    if not roleDropIndicator then
        roleDropIndicator = panel.scrollChild:CreateTexture(nil, "OVERLAY")
        roleDropIndicator:SetColorTexture(T.rgba(T.color.accent))
        roleDropIndicator:Hide()
    end
    return roleDropIndicator
end

local function ClearRoleDrop()
    if roleDropIndicator then roleDropIndicator:Hide() end
end

-- During a drag, mark `targetIndex` (1..#roles+1) as the drop slot and draw the
-- indicator at the TOP edge of `anchor` (a role row, or the end-zone for the last
-- slot). targetIndex means "insert before role #targetIndex".
function UI.SetRoleDropTarget(anchor, targetIndex)
    if not UI.roleDrag or not anchor then return end
    UI.roleDrag.toIndex = targetIndex
    local ind = RoleDropIndicator()
    if not ind then return end
    ind:ClearAllPoints()
    ind:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 0)
    ind:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 0)
    ind:SetHeight(2)
    ind:Show()
end

-- ---------------------------------------------------------------------------
--  Edit-role popup (built once, reused). Label for any role; token for customs.
-- ---------------------------------------------------------------------------
local rolePopup

local function BuildRolePopup()
    local p = CreateFrame("Frame", nil, UI.frame)
    p:SetFrameStrata("DIALOG")
    p:SetSize(360, 200)
    p:SetPoint("CENTER")
    p:EnableMouse(true)

    UI.PanelChrome(p)
    p.title = UI.TitleBar(p)   -- text set per open in UI.OpenRoleEditor

    -- Label field (every role has an editable display label).
    local nameCap = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameCap:SetPoint("TOPLEFT", 16, -42)
    nameCap:SetText("Label")
    local nameBox = UI.MakeInput(p, 240, 0, function() if p.onSave then p.onSave() end end)
    nameBox:SetPoint("TOPLEFT", 64, -38)
    nameBox:SetScript("OnEscapePressed", function() p:Hide() end)
    p.nameBox = nameBox

    -- Token field (custom roles only) and a static token label (built-ins).
    local tokenCap = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tokenCap:SetPoint("TOPLEFT", 16, -80)
    tokenCap:SetText("Token")
    local tokenBox = UI.MakeInput(p, 120, 16, function() if p.onSave then p.onSave() end end)
    tokenBox:SetPoint("TOPLEFT", 64, -76)
    tokenBox:SetScript("OnEscapePressed", function() p:Hide() end)
    p.tokenBox = tokenBox

    local tokenStatic = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tokenStatic:SetPoint("LEFT", tokenBox, "LEFT", 2, 0)
    p.tokenStatic = tokenStatic

    -- Tab cycles between Label and Token (only when the Token box is shown).
    nameBox:SetScript("OnTabPressed", function() if tokenBox:IsShown() then tokenBox:SetFocus() end end)
    tokenBox:SetScript("OnTabPressed", function() nameBox:SetFocus() end)
    -- Typing into a field clears a stale validation error.
    local function clearErr() if p.err then p.err:SetText("") end end
    nameBox:SetScript("OnTextChanged", clearErr)
    tokenBox:SetScript("OnTextChanged", clearErr)

    -- A per-role hint (token-fixed note for built-ins / how the token works).
    local hint = p:CreateFontString(nil, "OVERLAY", T.font.hint)
    hint:SetPoint("TOPLEFT", 16, -104)
    hint:SetPoint("RIGHT", p, "RIGHT", -16, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    p.hint = hint

    -- Validation error (red), shown in place of falling back to the chat log
    -- (which is hidden behind the overlay).
    local err = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    err:SetPoint("TOPLEFT", 16, -138)
    err:SetPoint("RIGHT", p, "RIGHT", -16, 0)
    err:SetJustifyH("LEFT")
    err:SetWordWrap(true)
    err:SetTextColor(T.rgb(T.color.loud))
    p.err = err

    local save = UI.Button(p, 90, UI.BUTTON_H, "Save", function() if p.onSave then p.onSave() end end)
    save:SetPoint("BOTTOMRIGHT", -16, 14)
    local cancel = UI.Button(p, 90, UI.BUTTON_H, "Cancel", function() p:Hide() end)
    cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)

    p:SetScript("OnHide", function(self)
        if self.err then self.err:SetText("") end
        self.nameBox:ClearFocus()
        self.tokenBox:ClearFocus()
    end)

    -- Modal over the Set Names overlay so a click behind can't refresh the panel
    -- (and re-index the roles) out from under an in-progress edit.
    UI.MakeModal(p, UI.namesPanel)

    p:Hide()
    return p
end

-- Open the editor for a role (an EffectiveRoles entry: key, label, baseLabel,
-- scope). instanceId is the current tab. Built-ins edit the label only (token is
-- fixed); customs edit label + token.
function UI.OpenRoleEditor(instanceId, role)
    if not role then return end
    rolePopup = rolePopup or BuildRolePopup()
    local p = rolePopup
    p.title:SetText("Edit role  " .. T.colorize(T.color.title, "{" .. role.key .. "}"))
    p.err:SetText("")
    p.nameBox:SetText(role.label or "")

    local isBuiltin = (role.scope == "builtin")
    if isBuiltin then
        p.tokenBox:Hide(); p.tokenBox.bg:Hide()
        p.tokenStatic:Show()
        p.tokenStatic:SetText(T.colorize(T.color.title, "{" .. role.key .. "}")
            .. "  " .. T.colorize(T.color.faint, "(built-in - fixed)"))
        p.hint:SetText("A built-in token can't be changed (your callouts reference {"
            .. role.key .. "}). Edit the label only; clear it to restore \""
            .. ns.util.escapePipes(role.baseLabel or role.key) .. "\".")
    else
        p.tokenStatic:Hide()
        p.tokenBox:Show(); p.tokenBox.bg:Show()
        p.tokenBox:SetText(role.key or "")
        p.hint:SetText("Token: letters/numbers only. Changing it moves the assigned name with it.")
    end

    p.onSave = function()
        -- Read the tab fresh on save (as DeleteRoleRow does), falling back to the
        -- open-time tab. The editor is closed on any tab switch, so these agree, but
        -- binding the write to the live selection keeps it correct without the closure.
        local id = ns.Config.SelectedInstance() or instanceId
        local newLabel = p.nameBox:GetText()
        local newToken = isBuiltin and role.key or p.tokenBox:GetText()
        local ok, reason = ns.Content.EditRole(id, role.scope, role.key, newLabel, newToken)
        if ok then
            p:Hide()
            UI.RebuildRoleRows()
        else
            p.err:SetText(reason or "Could not save the role.")
        end
    end

    p:Show()
    p:Raise()
    p.nameBox:SetFocus()
    p.nameBox:SetCursorPosition(#(role.label or ""))
end

-- Dismiss the editor popup. Called on tab switch / window hide so a Save can never
-- write against a stale tab or a since-removed role.
function UI.CloseRoleEditor()
    if rolePopup then rolePopup:Hide() end
end

-- ---------------------------------------------------------------------------
--  Role rows (pooled by index, laid out into the scroll child each rebuild)
-- ---------------------------------------------------------------------------
-- Build (or reuse) the row widgets at pool index `i`. The row itself is a Button
-- so it can be clicked (edit) and dragged (reorder), mirroring the callout rows
-- in UI/Window.lua. Children: a delete X, an Edit button, the label, and the name
-- dropdown (uniquely named by index so the template is happy and the frame is
-- reused, never leaked).
local function AcquireRoleRow(panel, i)
    local rows = panel.rows
    if rows[i] then return rows[i] end

    local row = CreateFrame("Button", nil, panel.scrollChild)
    row:RegisterForDrag("LeftButton")   -- drag the row to reorder it (Edit button renames)

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(true)
    hl:SetColorTexture(T.wash(T.color.accent, 0.18))

    -- Delete button on the FAR LEFT, well clear of the scroll frame's right edge
    -- (whose clip boundary swallowed clicks placed there). Every role is
    -- deletable; how is decided by scope in UI.DeleteRoleRow.
    local remove = UI.Button(row, 18, 18, "X", function(self)
        UI.DeleteRoleRow(self.scope, self.token, self.label)
    end)
    remove:SetPoint("TOPLEFT", 2, -3)
    -- Scope-aware tooltip (set per rebuild via self.scope), since the X does three
    -- different things: remove a per-raid role, remove a global role everywhere, or
    -- hide a built-in on this tab.
    remove:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.scope == "instance" then
            T.addLine(GameTooltip, "Remove this custom role from this tab", T.color.stale)
        elseif self.scope == "global" then
            T.addLine(GameTooltip, "Remove this global role from every tab", T.color.stale)
        else
            T.addLine(GameTooltip, "Hide this built-in role here (Reset roles restores it)", T.color.stale)
        end
        GameTooltip:Show()
    end)
    remove:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.remove = remove

    -- Edit button: rename the label (and, for a custom role, change the token).
    local editBtn = UI.Button(row, 42, 18, "Edit", function()
        if row.role then UI.OpenRoleEditor(row.instanceId, row.role) end
    end)
    editBtn:SetPoint("TOPLEFT", 24, -3)
    UI.Tooltip(editBtn, {
        { "Edit this role", 1, 1, 1 },
        { "Rename the label; custom roles can also change their {TOKEN}.", 0.8, 0.8, 0.8, true },
    })
    row.editBtn = editBtn

    -- "{TOKEN} Name" label comes after the buttons; the dropdown sits to its
    -- right. Wide and word-wrapping so the token and full name are NEVER
    -- truncated; the exact width/x is set per-rebuild from the scroll width.
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(true)
    row.label = label

    local dd = CreateFrame("Frame", "PugHelperNameDD" .. i, row, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dd, DD_W)
    UIDropDownMenu_Initialize(dd, InitNameDropdown)
    row.dd = dd

    -- Drag the row to reorder (the X deletes, the Edit button renames, the dropdown
    -- assigns a name - so the row body is reserved for the drag gesture only, with no
    -- click handler to fight the dropdown's own click area).
    row:SetScript("OnDragStart", function(self)
        if not self.roleIndex then return end
        UI.roleDrag = { instanceId = self.instanceId, fromIndex = self.roleIndex }
        self.label:SetAlpha(0.35)
        GameTooltip:Hide()
    end)
    row:SetScript("OnDragStop", function(self)
        local d = UI.roleDrag
        UI.roleDrag = nil
        self.label:SetAlpha(1)
        ClearRoleDrop()
        if d and d.toIndex then
            ns.Content.MoveRole(d.instanceId, d.fromIndex, d.toIndex)
            UI.RebuildRoleRows()
        end
    end)
    row:SetScript("OnEnter", function(self)
        if UI.roleDrag then
            if UI.roleDrag.instanceId == self.instanceId and self.roleIndex then
                UI.SetRoleDropTarget(self, self.roleIndex)
            end
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        T.addLine(GameTooltip, "Drag to reorder", T.color.accent)
        T.addLine(GameTooltip, "Use Edit to rename / change token", T.color.muted)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if UI.roleDrag then UI.roleDrag.toIndex = nil; ClearRoleDrop() end
    end)

    rows[i] = row
    return row
end

-- Rebuild the role list for the currently selected tab: one full-width row per
-- effective role, stacked top to bottom. Reuses pooled rows, hides the surplus,
-- and grows each row (and the scroll child) to fit a wrapped label.
function UI.RebuildRoleRows()
    local panel = UI.namesPanel
    if not panel or not panel.scrollChild then return end

    -- A rebuild re-indexes the roles, invalidating any in-flight drag started
    -- against the old indices; drop it defensively (matches UI.Refresh in Window).
    UI.roleDrag = nil
    ClearRoleDrop()

    local selId = ns.Config.SelectedInstance()
    local roles = ns.Content.EffectiveRoles(selId)
    panel.rows = panel.rows or {}

    -- Roster as a set (+ count), to flag a name assigned to someone not currently
    -- grouped, and to explain the solo state where the dropdowns only list you.
    local roster, rosterN = {}, 0
    for _, n in ipairs(ns.api.GroupRoster()) do roster[n] = true; rosterN = rosterN + 1 end
    if panel.help then
        if rosterN <= 1 then
            panel.help:SetText("Not in a group yet - the dropdowns fill from your party/raid once you invite. You can also type names with /pug name TOKEN Name.")
        else
            panel.help:SetText("These names fill the {TOKENS} in your callouts. Pick a party/raid member for each role.")
        end
    end

    -- Name the current tab so the "This tab" scope is unambiguous (the panel
    -- covers the tab list while it's open).
    if panel.addHeader then
        -- A pending add-role error survives a rebuild (a background roster update
        -- triggers RebuildRoleRows and would otherwise wipe the error before the
        -- user reads it). Cleared on a successful add or when the input changes.
        if panel.addError then
            panel.addHeader:SetText(T.colorize(T.color.loud, panel.addError))
        else
            local tab = ns.Content.InstanceName(selId, "this tab")
            panel.addHeader:SetText("Add a custom role  " .. T.colorize(T.color.faint, "(This tab = " .. tab .. ")"))
        end
    end

    local width = panel.scrollChild:GetWidth()
    if not width or width < 1 then width = 600 end
    -- Label fills from LABEL_X up to the dropdown column on the right; the
    -- dropdown follows it, inset from the scroll edge so its click never clips.
    local labelW = math.max(120, width - LABEL_X - DD_RESERVE)
    local ddX    = LABEL_X + labelW + 8

    local y = -2
    for i, role in ipairs(roles) do
        local row = AcquireRoleRow(panel, i)
        row.instanceId = selId
        row.roleIndex  = i
        row.role       = role
        row.label:SetAlpha(1)

        -- Token first (gold), then the full name; the label wraps so nothing is
        -- ever cut off.
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", LABEL_X, -7)
        row.label:SetWidth(labelW)

        row.dd:ClearAllPoints()
        row.dd:SetPoint("TOPLEFT", ddX, -1)
        row.dd.token = role.key
        local assigned = ns.Config.GetName(role.key) or ""
        -- Show "(not set)" rather than a blank box; amber the label while unset, and
        -- reddish when the assigned player isn't in the current group (only while
        -- actually grouped, so pre-invite name entry isn't flagged as wrong).
        UIDropDownMenu_SetText(row.dd, assigned ~= "" and assigned or T.colorize(T.color.faint, "(not set)"))
        -- role.key is %W-stripped (no '|'); escape the free-form label for display.
        local labelText = T.colorize(T.color.title, "{" .. role.key .. "}") .. " " .. ns.util.escapePipes(role.label or role.key)
        if assigned == "" then
            row.label:SetTextColor(T.rgb(T.color.unset))
        elseif rosterN > 1 and not roster[assigned] then
            row.label:SetTextColor(T.rgb(T.color.stale))
            -- Back the reddish tint with words so the stale state isn't color-only.
            labelText = labelText .. "  " .. T.colorize(T.color.stale, "(assigned player not in group)")
        else
            row.label:SetTextColor(T.rgb(T.color.text))
        end
        row.label:SetText(labelText)

        -- Every role is deletable; the row carries how (see UI.DeleteRoleRow).
        row.remove.scope = role.scope
        row.remove.token = role.key
        row.remove.label = role.label

        local h = math.max(STEP, row.label:GetStringHeight() + 12)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 4, y)
        row:SetSize(width - 8, h)
        row:Show()
        y = y - h - 2
    end

    for i = #roles + 1, #panel.rows do
        local row = panel.rows[i]
        row:Hide()
        -- Clear the per-render drag key on surplus pooled rows so a hidden frame can
        -- never start a drag with a stale index (OnDragStart guards on roleIndex).
        row.roleIndex = nil
    end

    -- Trailing end-zone: only meaningful during a drag, where hovering it targets
    -- the last slot ("move to the bottom"). Mirrors the "+ Add section" end anchor.
    panel.roleCount      = #roles
    panel.roleInstanceId = selId
    if panel.endZone then
        panel.endZone:ClearAllPoints()
        panel.endZone:SetPoint("TOPLEFT", 4, y)
        panel.endZone:SetSize(width - 8, STEP)
        panel.endZone:Show()
        y = y - STEP
    end

    panel.scrollChild:SetHeight(-y + 6)
end

-- Delete the role behind a row's X button (confirmed first): a per-raid custom
-- role is removed, a global custom role is removed everywhere, and a built-in is
-- hidden on the current tab (reversible via Reset roles). selId is read fresh so
-- it tracks the tab.
function UI.DeleteRoleRow(scope, token, label)
    local selId    = ns.Config.SelectedInstance()
    local namePart = (label and label ~= "" and label:upper() ~= token:upper())
        and (" (" .. ns.util.escapePipes(label) .. ")") or ""
    local who = T.colorize(T.color.title, "{" .. token .. "}") .. namePart

    local msg, acceptText, action
    if scope == "instance" then
        msg, acceptText = "Delete the role " .. who .. " from this tab?", "Delete"
        action = function() ns.Content.RemoveCustomRole(selId, token) end
    elseif scope == "global" then
        msg, acceptText = "Delete the global role " .. who .. " from every tab?", "Delete"
        action = function() ns.Content.RemoveCustomRole(nil, token) end
    else
        msg, acceptText = "Hide the built-in role " .. who
            .. " on this tab? You can restore it with the Reset roles button below.", "Hide"
        action = function() ns.Content.HideRole(selId, token) end
    end

    UI.Confirm(msg, function() action(); UI.RebuildRoleRows() end, acceptText)
end

-- ---------------------------------------------------------------------------
--  Add-a-role control (Name + Token + scope toggle + Add)
-- ---------------------------------------------------------------------------
local function BuildAddRow(panel)
    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 14, -56)
    header:SetText("Add a custom role:")
    panel.addHeader = header   -- text updated per tab in RebuildRoleRows

    local nameCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameCap:SetPoint("TOPLEFT", 14, -82)
    nameCap:SetText("Name")

    local function submit() panel.doAddRole() end

    local nameBox = UI.MakeInput(panel, 150, 32, submit)
    nameBox:SetPoint("TOPLEFT", 52, -78)

    local tokenCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tokenCap:SetPoint("TOPLEFT", 214, -82)
    tokenCap:SetText("Token")

    local tokenBox = UI.MakeInput(panel, 80, 16, submit)
    tokenBox:SetPoint("TOPLEFT", 256, -78)
    -- Tab cycles between the Name and Token fields for quick entry.
    nameBox:SetScript("OnTabPressed", function() tokenBox:SetFocus() end)
    tokenBox:SetScript("OnTabPressed", function() nameBox:SetFocus() end)
    -- Typing into either field clears a stale add-role error (shown in the header)
    -- and restores the normal caption; guarded so normal typing is cheap.
    local function clearAddError()
        if panel.addError then
            panel.addError = nil
            UI.RebuildRoleRows()
        end
    end
    nameBox:SetScript("OnTextChanged", clearAddError)
    tokenBox:SetScript("OnTextChanged", clearAddError)

    -- Scope toggle: a custom role is either Global (every tab) or This tab only.
    -- Defaults to This tab, the clutter-reducing case the user asked for.
    panel.addScope = "instance"
    local scopeBtn = UI.Button(panel, 116, UI.BUTTON_H, nil, nil)
    scopeBtn:SetPoint("TOPLEFT", 348, -78)
    local function updateScope()
        scopeBtn:SetText("Scope: " .. (panel.addScope == "instance" and "This tab" or "Global"))
    end
    scopeBtn:SetScript("OnClick", function()
        panel.addScope = (panel.addScope == "instance") and "global" or "instance"
        updateScope()
    end)
    updateScope()
    UI.Tooltip(scopeBtn, {
        { "Where this role shows", 1, 1, 1 },
        { "This tab: only the current tab. Global: every tab.", 0.8, 0.8, 0.8, true },
    })

    local addBtn = UI.Button(panel, 56, UI.BUTTON_H, "Add", function() panel.doAddRole() end)
    addBtn:SetPoint("TOPLEFT", 472, -78)

    -- Stored on the panel so OnEnterPressed and the button share one path. On
    -- failure the reason is shown red in the add header (the chat log is hidden
    -- behind this overlay); a successful add rebuilds, which resets that header.
    panel.doAddRole = function()
        local instanceId = (panel.addScope == "instance") and ns.Config.SelectedInstance() or nil
        local key, reason = ns.Content.AddCustomRole(instanceId, nameBox:GetText(), tokenBox:GetText())
        if key then
            panel.addError = nil
            nameBox:SetText("")
            tokenBox:SetText("")
            nameBox:ClearFocus()
            tokenBox:ClearFocus()
            UI.RebuildRoleRows()
        else
            -- Stash the reason so a background rebuild (roster update) re-renders it
            -- via RebuildRoleRows instead of wiping it with the static caption.
            panel.addError = reason or "Could not add role."
            UI.RebuildRoleRows()
        end
    end
end

-- ---------------------------------------------------------------------------
--  Panel construction (chrome built once; rows are rebuilt on demand)
-- ---------------------------------------------------------------------------
function UI.BuildNamesPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    UI.namesPanel = panel
    panel.rows = {}
    panel:SetPoint("TOPLEFT", 8, -58)
    panel:SetPoint("BOTTOMRIGHT", -8, 8)
    -- Sit above the scroll content (a deeper frame level) so the panel fully
    -- covers the message rows instead of letting their text bleed through.
    panel:SetFrameLevel(parent:GetFrameLevel() + 100)
    panel:EnableMouse(true)
    -- The edit popup floats at UIParent-ish strata and isn't a child of this panel,
    -- so hide it whenever the panel hides (Done/X/Escape, or the window closing) -
    -- otherwise its shown flag survives and it re-appears on reopen.
    panel:SetScript("OnHide", function() if UI.CloseRoleEditor then UI.CloseRoleEditor() end end)

    -- Same chrome as the window/editor so the overlay reads as one design (it
    -- previously had a fill but no border or title strip).
    UI.PanelChrome(panel)
    UI.TitleBar(panel, "Set Player / Role Names")

    -- Close X (top-right), so leaving the overlay doesn't depend on finding "Done".
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() panel:Hide(); UI.Refresh(true) end)

    local help = panel:CreateFontString(nil, "OVERLAY", T.font.body)
    help:SetPoint("TOPLEFT", panel.titleBar, "BOTTOMLEFT", 12, -4)
    help:SetText("These names fill the {TOKENS} in your callouts. Pick a party/raid member for each role.")
    help:SetTextColor(T.rgb(T.color.muted))
    panel.help = help   -- text becomes a solo-state hint in RebuildRoleRows

    BuildAddRow(panel)

    -- Scrollable role list, so any number of roles fits.
    local scroll = CreateFrame("ScrollFrame", "PugHelperNamesScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -108)
    scroll:SetPoint("BOTTOMRIGHT", -30, 44)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(scroll:GetWidth(), 10)
    scroll:SetScrollChild(child)
    panel.scrollChild = child
    UI.EnableWheel(scroll, STEP)
    scroll:SetScript("OnSizeChanged", function(_, w)
        if w and w > 1 then
            child:SetWidth(w)
            if panel:IsShown() then UI.RebuildRoleRows() end
        end
    end)

    -- End-zone: a mouse-only frame after the last row that, during a drag, marks the
    -- last drop slot so a role can be moved to the very bottom (rows themselves only
    -- target "insert before me"). Inert when not dragging.
    local endZone = CreateFrame("Frame", nil, child)
    endZone:EnableMouse(true)
    endZone:Hide()
    endZone:SetScript("OnEnter", function(self)
        if UI.roleDrag and UI.roleDrag.instanceId == panel.roleInstanceId then
            UI.SetRoleDropTarget(self, (panel.roleCount or 0) + 1)
        end
    end)
    endZone:SetScript("OnLeave", function()
        if UI.roleDrag then UI.roleDrag.toIndex = nil; ClearRoleDrop() end
    end)
    panel.endZone = endZone

    -- Reset roles (confirmed) at the bottom-left: separate local / global scopes.
    local resetRaid = UI.Button(panel, 96, UI.BUTTON_H, "Reset roles", function()
        local id   = ns.Config.SelectedInstance()
        local tab  = ns.Content.InstanceName(id, "this tab")
        UI.Confirm("Restore the built-in roles for " .. tab
            .. " and remove the custom roles, edits, and ordering you set on it?",
            function() ns.Content.ResetRoles(id, "instance"); UI.RebuildRoleRows() end,
            "Reset roles")
    end)
    resetRaid:SetPoint("BOTTOMLEFT", 14, 12)
    UI.Tooltip(resetRaid, {
        { "Reset this tab's roles", 1, 1, 1 },
        { "Drops roles, label edits, and the order you set on this tab, and un-hides its built-ins.", 0.8, 0.8, 0.8, true },
    })

    local resetGlobal = UI.Button(panel, 104, UI.BUTTON_H, "Reset global", function()
        UI.Confirm("Remove ALL of your global custom roles (the ones shown on every tab)?",
            function() ns.Content.ResetRoles(nil, "global"); UI.RebuildRoleRows() end,
            "Reset global")
    end)
    resetGlobal:SetPoint("LEFT", resetRaid, "RIGHT", 8, 0)
    UI.Tooltip(resetGlobal, {
        { "Reset your global roles", 1, 1, 1 },
        { "Removes every global custom role. Built-ins and per-raid roles are kept.", 0.8, 0.8, 0.8, true },
    })

    local done = UI.Button(panel, 90, UI.BUTTON_H, "Done", function()
        panel:Hide()
        UI.Refresh(true)   -- closing Set Names changes no callout content
    end)
    done:SetPoint("BOTTOMRIGHT", -14, 12)

    local clear = UI.Button(panel, 96, UI.BUTTON_H, "Clear names", function()
        -- Confirmed like every other destructive action - it wipes the exact data
        -- the user came here to enter.
        UI.Confirm("Clear the player names shown on this tab? The roles stay.", function()
            for _, row in ipairs(panel.rows) do
                if row:IsShown() and row.dd and row.dd.token then
                    ns.Config.SetName(row.dd.token, "")
                end
            end
            UI.RebuildRoleRows()
        end, "Clear names")
    end)
    clear:SetPoint("RIGHT", done, "LEFT", -8, 0)
    UI.Tooltip(clear, { { "Clear the names assigned here (keeps the roles)", 1, 1, 1 } })

    UI.RebuildRoleRows()
    panel:Hide()
end

-- Re-sync the panel with the current tab/roster while it's open (no-op when
-- hidden, so callers like SelectInstance and /pug name can call it freely).
function UI.RefreshNamesPanel()
    local panel = UI.namesPanel
    if not panel or not panel:IsShown() then return end
    UI.RebuildRoleRows()
end

function UI.ToggleNames()
    local panel = UI.namesPanel
    if not panel then return end
    if panel:IsShown() then
        panel:Hide()
        UI.Refresh(true)   -- match the X/Done close paths so unset-token cues update
    else
        panel:Show()
        UI.RebuildRoleRows()
    end
end

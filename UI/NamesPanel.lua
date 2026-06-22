--[[-------------------------------------------------------------------------
    PUG Helper - UI/NamesPanel.lua
---------------------------------------------------------------------------
    The "Set Names" overlay: one dropdown per role token, populated live from
    the current party/raid, plus an "add a custom role" control.

    Roles come from ns.Content.EffectiveRoles(selectedInstance): the built-ins
    (Content/Roles.lua), the user's global custom roles, and the custom roles
    scoped to the currently selected raid tab. The row list is rebuilt whenever
    roles change (add/remove) or the tab switches, reusing pooled widgets so the
    named dropdown frames are never leaked or duplicated.

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
local LABEL_X    = 24   -- role label x: just right of the delete X (label is first)
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
--  Role rows (pooled by index, laid out into the scroll child each rebuild)
-- ---------------------------------------------------------------------------
-- Build (or reuse) the row widgets at pool index `i`: a container, a label, a
-- name dropdown (uniquely named by index so the template is happy and the frame
-- is reused, never leaked), and a remove button shown only for custom roles.
local function AcquireRoleRow(panel, i)
    local rows = panel.rows
    if rows[i] then return rows[i] end

    local container = CreateFrame("Frame", nil, panel.scrollChild)

    -- Delete button on the FAR LEFT, well clear of the scroll frame's right edge
    -- (whose clip boundary swallowed clicks placed there). Every role is
    -- deletable; how is decided by scope in UI.DeleteRoleRow.
    local remove = UI.Button(container, 18, 18, "X", function(self)
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

    -- "{TOKEN} Name" label comes FIRST (after the delete X); the dropdown sits to
    -- its right. Wide and word-wrapping so the token and full name are NEVER
    -- truncated; the exact width/x is set per-rebuild from the scroll width.
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(true)

    local dd = CreateFrame("Frame", "PugHelperNameDD" .. i, container, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dd, DD_W)
    UIDropDownMenu_Initialize(dd, InitNameDropdown)

    local row = { container = container, label = label, dd = dd, remove = remove }
    rows[i] = row
    return row
end

-- Rebuild the role list for the currently selected tab: one full-width row per
-- effective role, stacked top to bottom. Reuses pooled rows, hides the surplus,
-- and grows each row (and the scroll child) to fit a wrapped label.
function UI.RebuildRoleRows()
    local panel = UI.namesPanel
    if not panel or not panel.scrollChild then return end

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
        local tab = ns.Content.InstanceName(selId, "this tab")
        panel.addHeader:SetText("Add a custom role  " .. T.colorize(T.color.faint, "(This tab = " .. tab .. ")"))
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
        local labelText = T.colorize(T.color.title, "{" .. role.key .. "}") .. " " .. (role.label or role.key)
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
        row.container:ClearAllPoints()
        row.container:SetPoint("TOPLEFT", 4, y)
        row.container:SetSize(width - 8, h)
        row.container:Show()
        y = y - h - 2
    end

    for i = #roles + 1, #panel.rows do
        panel.rows[i].container:Hide()
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
        and (" (" .. label .. ")") or ""
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
            nameBox:SetText("")
            tokenBox:SetText("")
            nameBox:ClearFocus()
            tokenBox:ClearFocus()
            UI.RebuildRoleRows()
        elseif panel.addHeader then
            panel.addHeader:SetText(T.colorize(T.color.loud, reason or "Could not add role."))
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

    -- Reset roles (confirmed) at the bottom-left: separate local / global scopes.
    local resetRaid = UI.Button(panel, 96, UI.BUTTON_H, "Reset roles", function()
        local id   = ns.Config.SelectedInstance()
        local tab  = ns.Content.InstanceName(id, "this tab")
        UI.Confirm("Restore the built-in roles for " .. tab
            .. " and remove the custom roles you added to it?",
            function() ns.Content.ResetRoles(id, "instance"); UI.RebuildRoleRows() end,
            "Reset roles")
    end)
    resetRaid:SetPoint("BOTTOMLEFT", 14, 12)
    UI.Tooltip(resetRaid, {
        { "Reset this tab's roles", 1, 1, 1 },
        { "Drops roles you added to this tab and un-hides its built-ins.", 0.8, 0.8, 0.8, true },
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
                if row.container:IsShown() and row.dd.token then
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
    else
        panel:Show()
        UI.RebuildRoleRows()
    end
end

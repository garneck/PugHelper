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

local STEP    = 30                -- minimum role row height (a single text line)
local DD_W    = 100               -- dropdown selected-text width
local LABEL_X = 22 + DD_W + 30    -- role label x: after the delete X + dropdown

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
        end
        UIDropDownMenu_AddButton(info)
    end
    local clearInfo = UIDropDownMenu_CreateInfo()
    clearInfo.text         = "|cff999999(clear)|r"
    clearInfo.notCheckable = true
    clearInfo.func         = function()
        ns.Config.SetName(token, "")
        UIDropDownMenu_SetText(dropdown, "")
    end
    UIDropDownMenu_AddButton(clearInfo)
end

-- A single-line text input with a dark inset background, mirroring the editor's
-- EditBox setup (plain CreateFrame, no template). `onEnter` fires on Return.
local function MakeInput(parent, width, maxLetters, onEnter)
    local bg = parent:CreateTexture(nil, "BORDER")
    bg:SetColorTexture(0, 0, 0, 0.5)

    local edit = CreateFrame("EditBox", nil, parent)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetMaxLetters(maxLetters)
    edit:SetTextInsets(5, 5, 2, 2)
    edit:SetJustifyH("LEFT")
    edit:SetSize(width, UI.BUTTON_H)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if onEnter then edit:SetScript("OnEnterPressed", onEnter) end

    -- The texture frames the box; anchor it to the edit so callers place one.
    bg:SetPoint("TOPLEFT", edit, "TOPLEFT", -2, 2)
    bg:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", 2, -2)
    edit.bg = bg
    return edit
end

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
        UI.DeleteRoleRow(self.scope, self.token)
    end)
    remove:SetPoint("TOPLEFT", 2, -3)
    UI.Tooltip(remove, { { "Delete this role", 1, 0.6, 0.6 } })

    local dd = CreateFrame("Frame", "PugHelperNameDD" .. i, container, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", 22, -1)
    UIDropDownMenu_SetWidth(dd, DD_W)
    UIDropDownMenu_Initialize(dd, InitNameDropdown)

    -- Wide, word-wrapping label so the {TOKEN} and full role name are NEVER
    -- truncated: a long name wraps and the row grows to fit (see RebuildRoleRows).
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", LABEL_X, -7)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(true)

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

    -- Name the current tab so "This raid" scope is unambiguous (the panel covers
    -- the tab list while it's open).
    if panel.addHeader then
        local inst = selId and ns.Content.Get(selId)
        local raid = (type(inst) == "table" and inst.name) or "this raid"
        panel.addHeader:SetText("Add a custom role  |cff808080(This raid = " .. raid .. ")|r")
    end

    local width = panel.scrollChild:GetWidth()
    if not width or width < 1 then width = 600 end
    local labelW = math.max(80, width - LABEL_X - 12)

    local y = -2
    for i, role in ipairs(roles) do
        local row = AcquireRoleRow(panel, i)

        -- Token first (gold), then the full name; the label wraps so nothing is
        -- ever cut off.
        row.label:SetWidth(labelW)
        row.label:SetText("|cffffd200{" .. role.key .. "}|r " .. (role.label or role.key))

        row.dd.token = role.key
        UIDropDownMenu_SetText(row.dd, ns.Config.GetName(role.key) or "")

        -- Every role is deletable; the row carries how (see UI.DeleteRoleRow).
        row.remove.scope = role.scope
        row.remove.token = role.key

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

-- Delete the role behind a row's X button: a per-raid custom role is removed, a
-- global custom role is removed everywhere, and a built-in is hidden on the
-- current tab (reversible via Reset). selId is read fresh so it tracks the tab.
function UI.DeleteRoleRow(scope, token)
    local selId = ns.Config.SelectedInstance()
    if scope == "instance" then
        ns.Content.RemoveCustomRole(selId, token)
    elseif scope == "global" then
        ns.Content.RemoveCustomRole(nil, token)
    else
        ns.Content.HideRole(selId, token)
    end
    UI.RebuildRoleRows()
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

    local nameBox = MakeInput(panel, 150, 32, submit)
    nameBox:SetPoint("TOPLEFT", 52, -78)

    local tokenCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tokenCap:SetPoint("TOPLEFT", 214, -82)
    tokenCap:SetText("Token")

    local tokenBox = MakeInput(panel, 80, 16, submit)
    tokenBox:SetPoint("TOPLEFT", 256, -78)
    -- Tab from the name to the token field for quick entry.
    nameBox:SetScript("OnTabPressed", function() tokenBox:SetFocus() end)

    -- Scope toggle: a custom role is either Global (every tab) or This raid only.
    -- Defaults to This raid, the clutter-reducing case the user asked for.
    panel.addScope = "instance"
    local scopeBtn = UI.Button(panel, 96, UI.BUTTON_H, nil, nil)
    scopeBtn:SetPoint("TOPLEFT", 348, -78)
    local function updateScope()
        scopeBtn:SetText(panel.addScope == "instance" and "This raid" or "Global")
    end
    scopeBtn:SetScript("OnClick", function()
        panel.addScope = (panel.addScope == "instance") and "global" or "instance"
        updateScope()
    end)
    updateScope()
    UI.Tooltip(scopeBtn, {
        { "Where this role shows", 1, 1, 1 },
        { "This raid: only on the current tab. Global: on every tab.", 0.8, 0.8, 0.8, true },
    })

    local addBtn = UI.Button(panel, 56, UI.BUTTON_H, "Add", function() panel.doAddRole() end)
    addBtn:SetPoint("TOPLEFT", 452, -78)

    -- Stored on the panel so OnEnterPressed and the button share one path.
    panel.doAddRole = function()
        local instanceId = (panel.addScope == "instance") and ns.Config.SelectedInstance() or nil
        local key = ns.Content.AddCustomRole(instanceId, nameBox:GetText(), tokenBox:GetText())
        if key then
            nameBox:SetText("")
            tokenBox:SetText("")
            nameBox:ClearFocus()
            tokenBox:ClearFocus()
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

    UI.Background(panel, 0.05, 0.05, 0.07, 0.97)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Set Player / Role Names")

    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    help:SetText("These names fill the {TOKENS} in your callouts. Pick a party/raid member for each role.")
    help:SetTextColor(0.8, 0.8, 0.8)

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
    local resetRaid = UI.Button(panel, 96, UI.BUTTON_H, "Reset raid", function()
        local id   = ns.Config.SelectedInstance()
        local inst = id and ns.Content.Get(id)
        local raid = (type(inst) == "table" and inst.name) or "this raid"
        UI.Confirm("Restore the built-in roles for " .. raid
            .. " and remove the custom roles you added to it?",
            function() ns.Content.ResetRoles(id, "instance"); UI.RebuildRoleRows() end,
            "Reset raid")
    end)
    resetRaid:SetPoint("BOTTOMLEFT", 14, 12)
    UI.Tooltip(resetRaid, {
        { "Reset this raid's roles", 1, 1, 1 },
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
        UI.Refresh()
    end)
    done:SetPoint("BOTTOMRIGHT", -14, 12)

    local clear = UI.Button(panel, 90, UI.BUTTON_H, "Clear All", function()
        for _, row in ipairs(panel.rows) do
            if row.container:IsShown() and row.dd.token then
                ns.Config.SetName(row.dd.token, "")
                UIDropDownMenu_SetText(row.dd, "")
            end
        end
    end)
    clear:SetPoint("RIGHT", done, "LEFT", -8, 0)
    UI.Tooltip(clear, { { "Clear the names shown here (keeps the roles)", 1, 1, 1 } })

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

--[[-------------------------------------------------------------------------
    PUG Helper - Core/Content.lua
---------------------------------------------------------------------------
    The callout registry and the customization engine.

    Content files (Content/*.lua) register DEFAULT content here at load time:
        ns:RegisterRoles{ ... }
        ns:RegisterInstance("raids", { name = "Karazhan", sections = {...} })

    User edits live in PugHelperDB.custom (per instance) and are returned by
    Effective() in place of the defaults, which it never mutates. This is what
    makes callouts customizable in-game and persistent across /reload and addon
    updates. Reset = drop the instance's custom entry.

    Customization is fork-on-edit: the first edit copies the instance's whole
    section list into the store (see materialize), and that copy is then
    authoritative. Storage shape (per instanceId):
        PugHelperDB.custom[instanceId] = {
            sections = { { title = "...", lines = { "...", ... } }, ... }
        }
    Sections and lines are addressed by display index (recomputed each render),
    so section titles may repeat (e.g. two "Trash" sections).
---------------------------------------------------------------------------]]

local _, ns = ...
local Content = ns.Content
local Config  = ns.Config
local util    = ns.util

-- Ordered categories drive the left-list section headers in the UI. "heroics"
-- is declared even while empty so its label shows, ready for future content.
Content.categories = {
    { id = "raids",   label = "Raids" },
    { id = "heroics", label = "Heroics" },
}
Content.defaults = { raids = {}, heroics = {} }  -- categoryId -> ordered instances
Content.byId     = {}                            -- instanceId -> default def
Content.roles    = {}                            -- list of { key, label }

-- ---------------------------------------------------------------------------
--  Registration (called from Content/*.lua at load time)
-- ---------------------------------------------------------------------------
local function getCategory(categoryId)
    for _, cat in ipairs(Content.categories) do
        if cat.id == categoryId then return cat end
    end
    return nil
end

function Content.SetRoles(list)
    Content.roles = util.asList(list)
end

-- Normalize a section list so each entry is { title = "...", lines = { ... } }.
-- A plain string is shorthand for a section with that title and no lines yet, so
-- content files can list bosses as bare strings; a table form is kept as-is with
-- lines defaulted to {}.
local function normalizeSections(sections)
    local out = {}
    for _, section in ipairs(util.asList(sections)) do
        if type(section) == "string" then
            table.insert(out, { title = section, lines = {} })
        elseif type(section) == "table" then
            section.lines = util.asList(section.lines)
            table.insert(out, section)
        end
    end
    return out
end

function Content.AddInstance(categoryId, def)
    if type(def) ~= "table" or not def.name then
        ns.Print("|cffff5555Data warning:|r RegisterInstance needs a table with a name - skipped.")
        return
    end
    def.sections = normalizeSections(def.sections)
    -- Unknown category: keep the content rather than drop it, and surface a tab
    -- for it (label defaults to the id) at the end of the list.
    if not Content.defaults[categoryId] then
        Content.defaults[categoryId] = {}
        if not getCategory(categoryId) then
            table.insert(Content.categories, { id = categoryId, label = categoryId })
        end
    end
    def.category = categoryId
    def.id = categoryId .. ":" .. util.slug(def.name)
    -- Two instances whose names slug to the same id would collide (last wins in
    -- byId) and produce a dead duplicate tab. Skip the duplicate with a warning
    -- rather than silently hide one instance's content.
    if Content.byId[def.id] then
        ns.Print("|cffff5555Data warning:|r another instance is already registered as '"
            .. def.id .. "' ('" .. tostring(def.name) .. "') - skipping the duplicate. Give it a unique name.")
        return
    end
    table.insert(Content.defaults[categoryId], def)
    Content.byId[def.id] = def
    return def.id
end

-- Convenience methods on the namespace so data files read naturally.
function ns:RegisterRoles(list)        return Content.SetRoles(list) end
function ns:RegisterInstance(cat, def) return Content.AddInstance(cat, def) end

-- ---------------------------------------------------------------------------
--  Read access (for UI / chat / names)
-- ---------------------------------------------------------------------------
function Content.Roles()
    return util.asList(Content.roles)
end

-- Keep only well-formed { key, label } entries (a table with a key) from a role
-- list, so a malformed entry degrades instead of erroring downstream. Shared by
-- the built-in (ValidRoles) and custom (GlobalRoles/InstanceRoles) readers.
local function validRoleList(list)
    local out = {}
    for _, role in ipairs(util.asList(list)) do
        if type(role) == "table" and role.key then table.insert(out, role) end
    end
    return out
end

-- Only the well-formed roles. Consumers that just want to USE roles (names
-- panel, /pug names, name pruning) go through EffectiveRoles, which calls this
-- for the built-ins; the diagnostic path (Content.Validate) still walks the raw
-- list to report typos.
function Content.ValidRoles()
    return validRoleList(Content.Roles())
end

-- ---------------------------------------------------------------------------
--  Custom roles (user-defined {TOKEN}s, scoped global or per-instance)
-- ---------------------------------------------------------------------------
-- These let the user add their own role tokens at runtime (via the Set Names
-- panel) on top of the built-ins from Content/Roles.lua. A "global" role shows
-- on every tab; a per-instance role only shows on its raid's tab, so the panel
-- doesn't fill up with one raid's roles while you're looking at another.
-- Names themselves stay keyed by bare token in Config.Names (you only run one
-- raid at a time and pick names from the live roster), so substitution and the
-- send path are untouched.

function Content.GlobalRoles()
    return validRoleList(Config.CustomRoles().global)
end

function Content.InstanceRoles(instanceId)
    if not instanceId then return {} end
    return validRoleList(Config.CustomRoles().byInstance[instanceId])
end

-- The set of uppercased tokens the user has hidden on a given tab (or nil). Lets
-- any role - including a built-in we can't erase - be deleted from a raid.
local function hiddenSet(instanceId)
    local h = instanceId and Config.CustomRoles().hidden[instanceId]
    return (type(h) == "table") and h or nil
end

-- The per-tab display-label overrides for a tab (uppercased token -> label), or
-- nil. A user-edited label lives here so the rename stays scoped to the tab it was
-- changed on; the built-in/global definition is never mutated. Mirrors hiddenSet.
local function labelSet(instanceId)
    local l = instanceId and Config.CustomRoles().labels[instanceId]
    return (type(l) == "table") and l or nil
end

-- The saved per-tab display order (a list of uppercased tokens), or nil.
local function orderList(instanceId)
    local o = instanceId and Config.CustomRoles().order[instanceId]
    return (type(o) == "table") and o or nil
end

-- Reorder a list of role entries to match `order` (a list of tokens): tokens named
-- in `order` come first in that order, then any roles not named keep their natural
-- relative order after. Stable and O(n); a token in `order` that isn't present is
-- skipped, and a present role missing from `order` is appended. Returns a new list,
-- so the input (and thus EffectiveRoles' build order) is never mutated in place.
local function applyOrder(list, order)
    if not order or #order == 0 then return list end
    local byKey = {}
    for _, r in ipairs(list) do byKey[r.key:upper()] = r end
    local out, used = {}, {}
    for _, tok in ipairs(order) do
        local up = tostring(tok):upper()
        local r = byKey[up]
        if r and not used[up] then used[up] = true; out[#out + 1] = r end
    end
    for _, r in ipairs(list) do
        if not used[r.key:upper()] then out[#out + 1] = r end
    end
    return out
end

-- The full ordered role list to offer for name assignment on the given tab:
-- built-ins, then global custom roles, then this instance's custom roles, minus
-- any built-in hidden on this tab. Each entry is tagged { key, label, scope,
-- instanceId } so the UI knows the token, its display label, and how to delete
-- it (custom -> remove; built-in -> hide). Deduped by uppercased token (first
-- occurrence wins) so a stray collision never shows the same token twice. Single
-- source of "roles the user can assign a name to", used by the names panel,
-- /pug names, and PruneNames.
function Content.EffectiveRoles(instanceId)
    local out, seen = {}, {}
    local hidden = hiddenSet(instanceId)
    local labels = labelSet(instanceId)
    local function add(role, scope, owner)
        local key = tostring(role.key)
        local up  = key:upper()
        if seen[up] then return end
        -- `hidden` only ever holds built-in tokens (HideRole is its lone writer,
        -- and the UI only hides built-ins). Scope the suppression to built-ins so
        -- a user can re-add their OWN role under a token whose built-in they hid -
        -- otherwise that custom role would pass AddCustomRole's duplicate check
        -- (which consults this list) yet be filtered straight back out here, going
        -- invisible with no feedback.
        if scope == "builtin" and hidden and hidden[up] then return end
        seen[up] = true
        -- baseLabel is the shipped (built-in) or definition (custom) label; `label`
        -- is what this tab shows, with any per-tab override applied. Editing a label
        -- writes the override, so the registered defaults and the custom-role
        -- definition are never mutated. The UI uses baseLabel for "restore default".
        local baseLabel = role.label or key
        local label = baseLabel
        if labels and labels[up] and labels[up] ~= "" then label = labels[up] end
        table.insert(out, { key = key, label = label, baseLabel = baseLabel, scope = scope, instanceId = owner })
    end
    for _, role in ipairs(Content.ValidRoles())              do add(role, "builtin")            end
    for _, role in ipairs(Content.GlobalRoles())             do add(role, "global")             end
    for _, role in ipairs(Content.InstanceRoles(instanceId)) do add(role, "instance", instanceId) end
    -- Finally apply the user's per-tab display order (no-op without a saved order).
    return applyOrder(out, orderList(instanceId))
end

-- True if any effective role on the given tab already uses this (uppercased)
-- token. A global add is thus checked against built-ins + globals; a per-instance
-- add additionally against that instance's own roles. Cross-raid reuse of a
-- token is allowed (the two tabs are never shown together).
local function tokenTaken(instanceId, token)
    local up = token:upper()
    for _, role in ipairs(Content.EffectiveRoles(instanceId)) do
        if role.key:upper() == up then return true end
    end
    return false
end

-- True if ANY per-instance custom-role list already uses this token. A GLOBAL add
-- is checked against this in addition to tokenTaken, because EffectiveRoles(nil)
-- can't see per-instance roles - without it a global role would silently shadow an
-- existing per-tab role of the same token (dedup in EffectiveRoles drops it).
local function tokenUsedByAnyInstance(token)
    local up = token:upper()
    for _, list in pairs(Config.CustomRoles().byInstance) do
        for _, role in ipairs(validRoleList(list)) do
            if tostring(role.key):upper() == up then return true end
        end
    end
    return false
end

-- Add a user-defined role. instanceId == nil => global (every tab); otherwise it
-- only appears on that raid's tab. The token is sanitized to letters/numbers and
-- uppercased so it matches the {%w+} substitution pattern. Returns the stored key
-- on success, or nil (with a chat warning) on an empty or duplicate token.
-- On failure returns nil plus a short reason string, so the caller can surface it
-- in the panel (the chat log is hidden behind the Set Names overlay).
function Content.AddCustomRole(instanceId, name, token)
    token = tostring(token or ""):gsub("%W", ""):upper()
    if token == "" then
        return nil, "Enter a token (letters or numbers only)."
    end
    if tokenTaken(instanceId, token) then
        return nil, "Token {" .. token .. "} is already used here."
    end
    -- A global add can't see per-instance roles via EffectiveRoles(nil), so check
    -- them explicitly; otherwise the global role would silently hide an existing
    -- per-tab role that shares the token (and steal its saved name).
    if not instanceId and tokenUsedByAnyInstance(token) then
        return nil, "Token {" .. token .. "} is already a per-tab role - remove it there first."
    end
    name = util.trim(name)
    if name == "" then name = token end

    local store = Config.CustomRoles()
    local list
    if instanceId then
        store.byInstance[instanceId] = store.byInstance[instanceId] or {}
        list = store.byInstance[instanceId]
    else
        list = store.global
    end
    table.insert(list, { key = token, label = name })
    return token
end

-- Remove a user-defined role by key from the given scope (instanceId == nil =>
-- global). Drops an emptied per-instance list so the store doesn't accumulate
-- empty tables. Any saved player name is left to PruneNames to clean up.
function Content.RemoveCustomRole(instanceId, key)
    local store = Config.CustomRoles()
    -- Explicit branch (NOT `a and b or c`): for an instanceId with no list this
    -- must be a no-op, not fall through to the global list and remove from there.
    local list
    if instanceId then list = store.byInstance[instanceId] else list = store.global end
    if type(list) ~= "table" then return end
    local up = tostring(key):upper()
    for i = #list, 1, -1 do
        local role = list[i]
        if type(role) == "table" and tostring(role.key):upper() == up then
            table.remove(list, i)
        end
    end
    if instanceId and #list == 0 then
        store.byInstance[instanceId] = nil
    end

    -- Forget any per-tab label override / order entry that referenced this token, so
    -- it can't bleed onto a future role re-added under the same token (a stale order
    -- entry would also pin the re-add to the deleted role's old slot). A per-tab role
    -- only ever has entries on its own tab; a global role can have them on any. Empty
    -- maps are nil'd AFTER iterating, never by deleting a key from the table being
    -- walked, so the pairs() traversal can't be corrupted.
    local function forgetLabel(lab)   -- returns true if the override map is now empty
        if type(lab) ~= "table" then return false end
        lab[up] = nil
        return next(lab) == nil
    end
    local function forgetOrder(ord)   -- returns true if the order list is now empty
        if type(ord) ~= "table" then return false end
        for i = #ord, 1, -1 do
            if tostring(ord[i]):upper() == up then table.remove(ord, i) end
        end
        return #ord == 0
    end
    if instanceId then
        if forgetLabel(store.labels[instanceId]) then store.labels[instanceId] = nil end
        if forgetOrder(store.order[instanceId]) then store.order[instanceId]  = nil end
    else
        local emptyLabels, emptyOrder = {}, {}
        for id, lab in pairs(store.labels) do if forgetLabel(lab) then emptyLabels[#emptyLabels + 1] = id end end
        for id, ord in pairs(store.order)  do if forgetOrder(ord) then emptyOrder[#emptyOrder + 1]  = id end end
        for _, id in ipairs(emptyLabels) do store.labels[id] = nil end
        for _, id in ipairs(emptyOrder)  do store.order[id]  = nil end
    end
end

-- Hide a role on a tab without deleting any definition. Used to "delete" a
-- built-in (or a global custom role) from one raid: EffectiveRoles skips hidden
-- tokens, and a per-raid reset un-hides them. instanceId is required (hiding is
-- always tab-local; built-ins stay available on every other tab).
function Content.HideRole(instanceId, key)
    if not instanceId then return end
    local hidden = Config.CustomRoles().hidden
    hidden[instanceId] = hidden[instanceId] or {}
    hidden[instanceId][tostring(key):upper()] = true
end

-- Set (or clear) the per-tab display-label override for a token on `instanceId`.
-- An empty label clears the override, restoring the role's shipped/definition
-- label. Scoped to the tab so a rename here never affects other tabs (matching the
-- per-tab customization model). The lone writer of CustomRoles().labels; used by
-- EditRole.
function Content.SetRoleLabel(instanceId, token, label)
    if not instanceId then return end
    local up = tostring(token or ""):upper()
    if up == "" then return end
    local labels = Config.CustomRoles().labels
    label = util.oneLine(label)
    if label == "" then
        if labels[instanceId] then
            labels[instanceId][up] = nil
            if next(labels[instanceId]) == nil then labels[instanceId] = nil end
        end
    else
        labels[instanceId] = labels[instanceId] or {}
        labels[instanceId][up] = label
    end
end

-- When a custom role's token changes, follow it through the saved per-tab maps so a
-- reorder / label / hide entry that referenced the old token keeps applying to the
-- renamed role. (The assigned player name is migrated separately in EditRole.)
-- Built-in tokens never change, so this only ever runs for a custom-role token edit.
local function renameTokenInMaps(oldUp, newUp)
    local cr = Config.CustomRoles()
    for _, list in pairs(cr.order) do
        if type(list) == "table" then
            for i, tok in ipairs(list) do
                if tostring(tok):upper() == oldUp then list[i] = newUp end
            end
        end
    end
    for _, map in pairs(cr.labels) do
        if type(map) == "table" and map[oldUp] ~= nil then
            map[newUp] = map[oldUp]; map[oldUp] = nil
        end
    end
    for _, map in pairs(cr.hidden) do
        if type(map) == "table" and map[oldUp] ~= nil then
            map[newUp] = map[oldUp]; map[oldUp] = nil
        end
    end
end

-- Edit a role shown on `instanceId`. A BUILT-IN role's token is fixed (callout
-- lines reference it as {TOKEN}), so only its display label changes - stored as a
-- per-tab override. A CUSTOM role (global or per-instance) can change both its token
-- and its label in its own definition; a token change migrates the assigned player
-- name and follows the token through the saved order / label / hidden maps.
-- Returns true on success, or nil + a short reason on an empty/duplicate token, so
-- the editor can surface it (the chat log is hidden behind the overlay). Mirrors
-- AddCustomRole's validation.
function Content.EditRole(instanceId, scope, oldKey, newLabel, newToken)
    oldKey = tostring(oldKey or ""):upper()
    if oldKey == "" then return nil, "Missing role." end

    if scope == "builtin" then
        -- Label only, per-tab; an empty label restores the shipped default.
        Content.SetRoleLabel(instanceId, oldKey, newLabel)
        return true
    end

    local token = tostring(newToken or ""):gsub("%W", ""):upper()
    if token == "" then
        return nil, "Enter a token (letters or numbers only)."
    end

    local tokenChanged = (token ~= oldKey)
    if tokenChanged then
        -- The role itself still holds oldKey here, so a hit on `token` is a genuine
        -- collision with a DIFFERENT role (we only check when the token changed).
        if tokenTaken(instanceId, token) then
            return nil, "Token {" .. token .. "} is already used here."
        end
        if scope == "global" and tokenUsedByAnyInstance(token) then
            return nil, "Token {" .. token .. "} is already a per-tab role - remove it there first."
        end
    end

    -- Find the role's own definition entry (a live ref into the store).
    local store = Config.CustomRoles()
    local list  = (scope == "instance") and store.byInstance[instanceId] or store.global
    local entry
    if type(list) == "table" then
        for _, r in ipairs(list) do
            if type(r) == "table" and tostring(r.key):upper() == oldKey then entry = r; break end
        end
    end
    if not entry then return nil, "That role no longer exists." end

    entry.key = token

    if tokenChanged then
        -- Move the assigned name onto the new token. Leave the old name in place for
        -- PruneNames to reap: another tab may still reuse the old token (cross-raid
        -- token reuse is allowed), and we must never drop a name another role needs.
        local nm = Config.GetName(oldKey)
        if nm and nm ~= "" then Config.SetName(token, nm) end
        renameTokenInMaps(oldKey, token)
    end

    -- A label equal to the definition's own default is stored as "no override" so
    -- the role keeps tracking its definition; otherwise the typed text is the
    -- per-tab override. entry.label is the custom role's own (default) label.
    if util.oneLine(newLabel) == util.oneLine(entry.label) then
        Content.SetRoleLabel(instanceId, token, "")
    else
        Content.SetRoleLabel(instanceId, token, newLabel)
    end
    return true
end

-- Move the role at display index `fromIndex` so it lands immediately before
-- `insertBefore` (1..#roles+1; #roles+1 = "to the end") on `instanceId`. The order
-- is captured from the CURRENT effective order, so a single drag yields a complete
-- per-tab ordering and later-added roles append in natural order. Mirrors
-- MoveSection / MoveLine. No-op if the move wouldn't change anything.
function Content.MoveRole(instanceId, fromIndex, insertBefore)
    if not instanceId then return end
    local roles = Content.EffectiveRoles(instanceId)
    local n = #roles
    if fromIndex < 1 or fromIndex > n then return end
    insertBefore = math.max(1, math.min(insertBefore or (n + 1), n + 1))
    if insertBefore == fromIndex or insertBefore == fromIndex + 1 then return end
    local tokens = {}
    for _, r in ipairs(roles) do tokens[#tokens + 1] = r.key:upper() end
    local item = table.remove(tokens, fromIndex)
    if insertBefore > fromIndex then insertBefore = insertBefore - 1 end
    table.insert(tokens, insertBefore, item)
    Config.CustomRoles().order[instanceId] = tokens
end

-- Restore default roles. scope "instance" drops this raid's added roles and
-- un-hides its built-ins; scope "global" removes every global custom role. Built-
-- in definitions are never touched, so this only clears the user's own overrides.
function Content.ResetRoles(instanceId, scope)
    local store = Config.CustomRoles()
    if scope == "global" then
        local g = store.global
        for i = #g, 1, -1 do g[i] = nil end
    elseif scope == "instance" and instanceId then
        store.byInstance[instanceId] = nil
        store.hidden[instanceId]     = nil
        store.labels[instanceId]     = nil
        store.order[instanceId]      = nil
    end
end

function Content.Categories()
    return Content.categories
end

function Content.Instances(categoryId)
    return util.asList(Content.defaults[categoryId])
end

function Content.Get(instanceId)
    return Content.byId[instanceId]
end

-- Display name for an instance id, or `fallback` (default "(unnamed)") when the
-- id is unknown. One home for the id -> label lookup the UI would otherwise
-- re-roll with its own type-check and fallback string.
function Content.InstanceName(instanceId, fallback)
    local inst = Content.Get(instanceId)
    return (type(inst) == "table" and inst.name) or fallback or "(unnamed)"
end

function Content.FirstInstanceId()
    for _, cat in ipairs(Content.categories) do
        local list = Content.defaults[cat.id]
        if list and list[1] then return list[1].id end
    end
    return nil
end

-- The instance to open: the saved selection if it still exists, else the first
-- registered one (handles old saves / removed content). The single source of
-- this fallback, shared by Boot (normalizes the saved value at load) and the UI
-- open path, so the policy isn't re-derived per caller.
function Content.ResolveSelectedInstance()
    local sel = Config.SelectedInstance()
    if sel and Content.Get(sel) then return sel end
    return Content.FirstInstanceId()
end

-- The instance's user-owned section copy if one exists (the fork-on-edit store),
-- else nil. The single "is this instance customized?" predicate, shared by
-- Effective, materialize, and HasCustom so the storage shape lives in one place.
local function customSections(instanceId)
    local c = Config.Custom()[instanceId]
    if type(c) == "table" and type(c.sections) == "table" then return c.sections end
    return nil
end

-- The instance's current section list WITHOUT forking: the user-owned copy if one
-- exists, else the registered defaults (read-only). Used by the mutators below to
-- answer "did this actually change?" before calling materialize, so a no-op edit
-- or drop-in-place drag doesn't fork the instance and falsely mark it customized.
local function sourceSections(instanceId)
    local s = customSections(instanceId)
    if s then return s end
    local def = Content.byId[instanceId]
    return def and def.sections or nil
end

-- Build the effective instance to display/send. If the user has customized this
-- instance, its sections are a fully user-owned copy (fork-on-edit, see the
-- mutators below); otherwise they are a copy of the registered defaults. Either
-- way a fresh table is returned and the registered defaults are never mutated.
-- Sections and lines are addressed positionally (section index, line index) by
-- the editor, recomputed on every render.
function Content.Effective(instanceId)
    local def = Content.byId[instanceId]
    if type(def) ~= "table" then return nil end

    -- Copy the scalar instance fields, then the sections from whichever source
    -- applies exactly once (copying def wholesale would deep-copy the default
    -- sections only to discard them on the customized path).
    local result = {}
    for k, v in pairs(def) do
        if k ~= "sections" then result[k] = util.deepCopy(v) end
    end
    result.sections = util.deepCopy(customSections(instanceId) or def.sections)
    -- Both sources are already normalized (defaults via normalizeSections, custom
    -- via the mutators), and every reader wraps section.lines in util.asList, so
    -- no extra normalization pass is needed here.
    return result
end

-- ---------------------------------------------------------------------------
--  Customization mutators (fork-on-edit; persisted via Config.Custom)
-- ---------------------------------------------------------------------------
-- Return the instance's owned, editable section list, copying it out of the
-- registered defaults the first time it's touched. From then on this copy is
-- authoritative for the instance until Reset restores the defaults. This avoids
-- any title/index identity problems and lets sections be renamed, added, or
-- removed freely (e.g. two separate "Trash" sections).
local function materialize(instanceId)
    local sections = customSections(instanceId)
    if not sections then
        local def = Content.byId[instanceId]
        sections = util.deepCopy(def and def.sections or {})
        Config.Custom()[instanceId] = { sections = sections }
    end
    return sections
end

-- Fetch an owned section by display index, guaranteeing section.lines is a table
-- so the line mutators below don't each re-assert it. Returns nil for a missing
-- or non-table slot.
local function getSection(instanceId, sectionIndex)
    local section = materialize(instanceId)[sectionIndex]
    if type(section) ~= "table" then return nil end
    section.lines = util.asList(section.lines)
    return section
end

-- Lines (addressed by section index + line index) ----------------------------
function Content.SetLine(instanceId, sectionIndex, lineIndex, text)
    text = util.oneLine(text)
    -- Compare against the current value WITHOUT forking, so re-saving identical
    -- text (a no-op edit) doesn't materialize a redundant custom copy and falsely
    -- flip the tab to "(customized)". Only an actual change calls getSection.
    local src = sourceSections(instanceId)
    local cur = src and src[sectionIndex]
    local existing = cur and util.asList(cur.lines)[lineIndex]
    if existing == nil then return end       -- only edit a line that exists
    if existing == text then return end      -- unchanged: do not fork
    local section = getSection(instanceId, sectionIndex)
    if section then
        section.lines[lineIndex] = text
    end
end

function Content.AddLine(instanceId, sectionIndex, text)
    text = util.oneLine(text)
    if text == "" then return end
    local section = getSection(instanceId, sectionIndex)
    if not section then return end
    table.insert(section.lines, text)
end

function Content.DeleteLine(instanceId, sectionIndex, lineIndex)
    local section = getSection(instanceId, sectionIndex)
    if not section then return end
    table.remove(section.lines, lineIndex)
end

-- Move the line at fromIndex within its section so it lands immediately before
-- `insertBefore` (1..#lines+1; #lines+1 = "to the end"). Mirrors MoveSection.
-- No-op if the move wouldn't change order.
function Content.MoveLine(instanceId, sectionIndex, fromIndex, insertBefore)
    -- Validate + no-op check against the un-forked source first, so a drop-in-place
    -- line drag doesn't materialize a custom copy identical to the defaults.
    local src = sourceSections(instanceId)
    local cur = src and src[sectionIndex]
    local n = cur and #util.asList(cur.lines) or 0
    if fromIndex < 1 or fromIndex > n then return end
    insertBefore = math.max(1, math.min(insertBefore or (n + 1), n + 1))
    if insertBefore == fromIndex or insertBefore == fromIndex + 1 then return end
    local section = getSection(instanceId, sectionIndex)
    if not section then return end
    local lines = section.lines
    local item = table.remove(lines, fromIndex)
    if insertBefore > fromIndex then insertBefore = insertBefore - 1 end
    table.insert(lines, insertBefore, item)
end

-- Duplicate a line, inserting the copy right after the original.
function Content.DuplicateLine(instanceId, sectionIndex, lineIndex)
    local section = getSection(instanceId, sectionIndex)
    if not section then return end
    local line = section.lines[lineIndex]
    if line == nil then return end
    table.insert(section.lines, lineIndex + 1, line)
end

-- Sections (addressed by section index) --------------------------------------
function Content.SetSectionTitle(instanceId, sectionIndex, title)
    title = util.oneLine(title)
    if title == "" then return end
    -- No-op rename (same title) must not fork the instance; check the source first.
    local src = sourceSections(instanceId)
    local cur = src and src[sectionIndex]
    if not cur then return end
    if cur.title == title then return end
    local section = getSection(instanceId, sectionIndex)
    if section then section.title = title end
end

function Content.AddSection(instanceId, title)
    title = util.oneLine(title)
    if title == "" then return end
    table.insert(materialize(instanceId), { title = title, lines = {} })
end

function Content.DeleteSection(instanceId, sectionIndex)
    local sections = materialize(instanceId)
    if sections[sectionIndex] then table.remove(sections, sectionIndex) end
end

-- Move the section at fromIndex so it lands immediately before `insertBefore`
-- (a slot in 1..#sections+1; #sections+1 means "to the end"). No-op if the move
-- wouldn't change order.
function Content.MoveSection(instanceId, fromIndex, insertBefore)
    -- Validate + no-op check against the un-forked source first, so a drop-in-place
    -- section drag doesn't materialize a custom copy identical to the defaults.
    local src = sourceSections(instanceId)
    local n = src and #src or 0
    if fromIndex < 1 or fromIndex > n then return end
    insertBefore = math.max(1, math.min(insertBefore or (n + 1), n + 1))
    if insertBefore == fromIndex or insertBefore == fromIndex + 1 then return end
    local sections = materialize(instanceId)
    local item = table.remove(sections, fromIndex)
    if insertBefore > fromIndex then insertBefore = insertBefore - 1 end
    table.insert(sections, insertBefore, item)
end

-- Duplicate a section (title + all its lines), inserting the deep copy right
-- after the original.
function Content.DuplicateSection(instanceId, sectionIndex)
    local sections = materialize(instanceId)
    local section = sections[sectionIndex]
    if type(section) ~= "table" then return end
    table.insert(sections, sectionIndex + 1, util.deepCopy(section))
end

-- Drop all user customization for an instance (restore built-in defaults).
function Content.ResetInstance(instanceId)
    Config.Custom()[instanceId] = nil
end

-- True if the instance has a user-owned section copy (controls the Reset button).
function Content.HasCustom(instanceId)
    return customSections(instanceId) ~= nil
end

-- ---------------------------------------------------------------------------
--  Validation + name pruning (run at load from Boot.lua)
-- ---------------------------------------------------------------------------
-- Friendly, actionable warnings for content typos instead of cryptic errors.
function Content.Validate()
    local roles = Content.Roles()
    if #roles == 0 then
        ns.Print("|cffff5555Data warning:|r no roles registered (Content/Roles.lua).")
    end
    for i, role in ipairs(roles) do
        if type(role) ~= "table" or not role.key or not role.label then
            ns.Print("|cffff5555Data warning:|r role #" .. i .. " needs both a key and a label - skipped.")
        elseif not tostring(role.key):match("^%w+$") then
            ns.Print("|cffff5555Data warning:|r role key '" .. tostring(role.key)
                .. "' must be letters/numbers only, or its {TOKEN} will never fill in.")
        end
    end

    for _, cat in ipairs(Content.categories) do
        for _, inst in ipairs(Content.Instances(cat.id)) do
            local label = (type(inst) == "table" and inst.name) or "(unnamed)"
            if type(inst) ~= "table" or type(inst.sections) ~= "table" then
                ns.Print("|cffff5555Data warning:|r instance '" .. tostring(label) .. "' has no sections.")
            else
                for s, section in ipairs(inst.sections) do
                    if type(section) ~= "table" or type(section.lines) ~= "table" then
                        ns.Print("|cffff5555Data warning:|r instance '" .. tostring(label)
                            .. "', section #" .. s .. " has no lines.")
                    end
                end
            end
        end
    end
end

-- Drop saved customization (content overrides, custom roles, hidden sets) whose
-- instanceId no longer resolves to a registered instance - e.g. a raid file
-- removed/renamed across addon versions. Without this, PugHelperDB accumulates
-- dead per-instance data forever. Run from Boot BEFORE PruneNames so name pruning
-- sees the already-reaped role store. The saved-vars iteration lives in Config.
function Content.PruneCustomization()
    Config.PruneCustomization(function(id) return Content.Get(id) ~= nil end)
end

-- Drop saved names whose token is neither a role key nor used by any (effective)
-- callout line, so PugHelperDB.names doesn't accumulate leftovers as content
-- changes. Case-insensitive; leaves custom-but-still-used tokens alone.
function Content.PruneNames()
    local live = {}
    local function markLive(roles)
        for _, role in ipairs(roles) do
            live[tostring(role.key):upper()] = true
        end
    end
    -- Defined roles keep their name even before any callout references them:
    -- built-ins, global custom roles, and every instance's custom roles.
    markLive(Content.ValidRoles())
    markLive(Content.GlobalRoles())
    for id, list in pairs(Config.CustomRoles().byInstance) do
        -- Skip roles for instances that no longer exist, so an orphaned per-tab
        -- role can't pin its saved name alive forever (PruneCustomization also
        -- reaps these, but gate here too so ordering can't reintroduce the leak).
        if Content.Get(id) then markLive(validRoleList(list)) end
    end
    for _, cat in ipairs(Content.categories) do
        for _, inst in ipairs(Content.Instances(cat.id)) do
            local eff = Content.Effective(inst.id)
            for _, section in ipairs(util.asList(eff and eff.sections)) do
                for _, line in ipairs(util.asList(section.lines)) do
                    if type(line) == "string" then
                        for token in line:gmatch("{(%w+)}") do live[token:upper()] = true end
                    end
                end
            end
        end
    end
    Config.PruneNames(function(token) return live[token:upper()] end)
end

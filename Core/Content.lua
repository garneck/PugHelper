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
        table.insert(out, { key = key, label = role.label or key, scope = scope, instanceId = owner })
    end
    for _, role in ipairs(Content.ValidRoles())              do add(role, "builtin")            end
    for _, role in ipairs(Content.GlobalRoles())             do add(role, "global")             end
    for _, role in ipairs(Content.InstanceRoles(instanceId)) do add(role, "instance", instanceId) end
    return out
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

-- Add a user-defined role. instanceId == nil => global (every tab); otherwise it
-- only appears on that raid's tab. The token is sanitized to letters/numbers and
-- uppercased so it matches the {%w+} substitution pattern. Returns the stored key
-- on success, or nil (with a chat warning) on an empty or duplicate token.
function Content.AddCustomRole(instanceId, name, token)
    token = tostring(token or ""):gsub("%W", ""):upper()
    if token == "" then
        ns.Print("|cffff5555Role:|r token must contain at least one letter or number.")
        return nil
    end
    if tokenTaken(instanceId, token) then
        ns.Print("|cffff5555Role:|r a role with token {" .. token .. "} already exists here.")
        return nil
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
    local list  = instanceId and store.byInstance[instanceId] or store.global
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
    local section = getSection(instanceId, sectionIndex)
    if not section then return end
    if section.lines[lineIndex] ~= nil then
        section.lines[lineIndex] = util.oneLine(text)
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
    local section = getSection(instanceId, sectionIndex)
    if not section then return end
    local lines = section.lines
    local n = #lines
    if fromIndex < 1 or fromIndex > n then return end
    insertBefore = math.max(1, math.min(insertBefore or (n + 1), n + 1))
    if insertBefore == fromIndex or insertBefore == fromIndex + 1 then return end
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
    local sections = materialize(instanceId)
    local n = #sections
    if fromIndex < 1 or fromIndex > n then return end
    insertBefore = math.max(1, math.min(insertBefore or (n + 1), n + 1))
    if insertBefore == fromIndex or insertBefore == fromIndex + 1 then return end
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
    for _, list in pairs(Config.CustomRoles().byInstance) do
        markLive(validRoleList(list))
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

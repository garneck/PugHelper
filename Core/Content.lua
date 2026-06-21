--[[-------------------------------------------------------------------------
    PUG Helper - Core/Content.lua
---------------------------------------------------------------------------
    The callout registry and the customization engine.

    Content files (Content/*.lua) register DEFAULT content here at load time:
        ns:RegisterRoles{ ... }
        ns:RegisterInstance("raids", { name = "Karazhan", sections = {...} })

    User edits live in PugHelperDB.custom (per instance) and are layered over
    the defaults by Effective(), which never mutates the registered defaults.
    This is what makes callouts customizable in-game and persistent across
    /reload and addon updates. Reset = drop the instance's custom entry.

    Override storage shape (per instanceId), all keyed by section TITLE:
        overrides[title][i] = "text"   -- replace default line i
        added[title]        = { ... }  -- extra lines appended to the section
        hidden[title][i]    = true     -- hide default line i
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

function Content.AddInstance(categoryId, def)
    if type(def) ~= "table" or not def.name then
        ns.Print("|cffff5555Data warning:|r RegisterInstance needs a table with a name - skipped.")
        return
    end
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

function Content.Categories()
    return Content.categories
end

function Content.Instances(categoryId)
    return util.asList(Content.defaults[categoryId])
end

function Content.Get(instanceId)
    return Content.byId[instanceId]
end

function Content.FirstInstanceId()
    for _, cat in ipairs(Content.categories) do
        local list = Content.defaults[cat.id]
        if list and list[1] then return list[1].id end
    end
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

    local result = util.deepCopy(def)
    local custom = Config.Custom()[instanceId]
    if type(custom) == "table" and type(custom.sections) == "table" then
        result.sections = util.deepCopy(custom.sections)
    end
    -- Normalize so the UI can always ipairs lines safely.
    for _, section in ipairs(util.asList(result.sections)) do
        section.lines = util.asList(section.lines)
    end
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
    local store = Config.Custom()
    local c = store[instanceId]
    if type(c) ~= "table" or type(c.sections) ~= "table" then
        local def = Content.byId[instanceId]
        c = { sections = util.deepCopy(def and def.sections or {}) }
        store[instanceId] = c
    end
    return c.sections
end

local function getSection(instanceId, sectionIndex)
    local section = materialize(instanceId)[sectionIndex]
    return type(section) == "table" and section or nil
end

-- Lines (addressed by section index + line index) ----------------------------
function Content.SetLine(instanceId, sectionIndex, lineIndex, text)
    local section = getSection(instanceId, sectionIndex)
    if not section then return end
    section.lines = util.asList(section.lines)
    if section.lines[lineIndex] ~= nil then
        section.lines[lineIndex] = util.trim(text)
    end
end

function Content.AddLine(instanceId, sectionIndex, text)
    text = util.trim(text)
    if text == "" then return end
    local section = getSection(instanceId, sectionIndex)
    if not section then return end
    section.lines = util.asList(section.lines)
    table.insert(section.lines, text)
end

function Content.DeleteLine(instanceId, sectionIndex, lineIndex)
    local section = getSection(instanceId, sectionIndex)
    if not section or type(section.lines) ~= "table" then return end
    table.remove(section.lines, lineIndex)
end

-- Sections (addressed by section index) --------------------------------------
function Content.SetSectionTitle(instanceId, sectionIndex, title)
    title = util.trim(title)
    if title == "" then return end
    local section = getSection(instanceId, sectionIndex)
    if section then section.title = title end
end

function Content.AddSection(instanceId, title)
    title = util.trim(title)
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

-- Drop all user customization for an instance (restore built-in defaults).
function Content.ResetInstance(instanceId)
    Config.Custom()[instanceId] = nil
end

-- True if the instance has a user-owned section copy (controls the Reset button).
function Content.HasCustom(instanceId)
    local c = Config.Custom()[instanceId]
    return type(c) == "table" and type(c.sections) == "table"
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
    if not PugHelperDB or type(PugHelperDB.names) ~= "table" then return end
    local live = {}
    for _, role in ipairs(Content.Roles()) do
        if type(role) == "table" and role.key then live[tostring(role.key):upper()] = true end
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
    for key in pairs(PugHelperDB.names) do
        if type(key) ~= "string" or not live[key:upper()] then
            PugHelperDB.names[key] = nil
        end
    end
end

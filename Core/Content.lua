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

-- Build the effective (default + user override) instance to display/send.
-- Returns a fresh table; each section gets:
--   section.lines    = { "text", ... }           -- for rendering & sending
--   section.lineMeta = { {origin=i[,overridden]} | {added=j}, ... }  (parallel)
-- The editor uses lineMeta to know where to write a change back.
function Content.Effective(instanceId)
    local def = Content.byId[instanceId]
    if type(def) ~= "table" then return nil end

    local result = util.deepCopy(def)
    local custom = Config.Custom()[instanceId]
    custom = (type(custom) == "table") and custom or {}
    local overrides, added, hidden =
        util.asList(custom.overrides), util.asList(custom.added), util.asList(custom.hidden)

    for _, section in ipairs(util.asList(result.sections)) do
        local title  = section.title or ""
        local secOv  = util.asList(overrides[title])
        local secHi  = util.asList(hidden[title])
        local lines, meta = {}, {}
        for i, line in ipairs(util.asList(section.lines)) do
            if not secHi[i] then
                table.insert(lines, secOv[i] or line)
                table.insert(meta, { origin = i, overridden = secOv[i] ~= nil })
            end
        end
        for j, extra in ipairs(util.asList(added[title])) do
            table.insert(lines, extra)
            table.insert(meta, { added = j })
        end
        section.lines, section.lineMeta = lines, meta
    end
    return result
end

-- ---------------------------------------------------------------------------
--  Customization mutators (write PugHelperDB.custom via Config.Custom)
-- ---------------------------------------------------------------------------
local function ensure(t, k)
    t[k] = t[k] or {}
    return t[k]
end

local function instCustom(instanceId)
    local store = Config.Custom()
    store[instanceId] = store[instanceId] or {}
    return store[instanceId]
end

-- Edit a line in place. `meta` is the lineMeta entry for the displayed row.
function Content.SetLine(instanceId, sectionTitle, meta, text)
    if not meta then return end
    text = util.trim(text)
    local c = instCustom(instanceId)
    if meta.added then
        ensure(ensure(c, "added"), sectionTitle)[meta.added] = text
    elseif meta.origin then
        ensure(ensure(c, "overrides"), sectionTitle)[meta.origin] = text
    end
end

-- Append a brand-new line to a section.
function Content.AddLine(instanceId, sectionTitle, text)
    text = util.trim(text)
    if text == "" then return end
    table.insert(ensure(ensure(instCustom(instanceId), "added"), sectionTitle), text)
end

-- Remove a displayed line: hide it if it's a default, or drop it if user-added.
function Content.DeleteLine(instanceId, sectionTitle, meta)
    if not meta then return end
    local c = instCustom(instanceId)
    if meta.added then
        local sec = c.added and c.added[sectionTitle]
        if sec then table.remove(sec, meta.added) end
    elseif meta.origin then
        ensure(ensure(c, "hidden"), sectionTitle)[meta.origin] = true
        if c.overrides and c.overrides[sectionTitle] then
            c.overrides[sectionTitle][meta.origin] = nil
        end
    end
end

-- Drop all user customization for an instance (restore built-in defaults).
function Content.ResetInstance(instanceId)
    Config.Custom()[instanceId] = nil
end

-- True if the instance has any user customization (controls the Reset button).
function Content.HasCustom(instanceId)
    local c = Config.Custom()[instanceId]
    return type(c) == "table" and next(c) ~= nil
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
                local seen = {}
                for s, section in ipairs(inst.sections) do
                    if type(section) ~= "table" or type(section.lines) ~= "table" then
                        ns.Print("|cffff5555Data warning:|r instance '" .. tostring(label)
                            .. "', section #" .. s .. " has no lines.")
                    else
                        local t = section.title or ""
                        if seen[t] then
                            ns.Print("|cffff5555Data warning:|r instance '" .. tostring(label)
                                .. "' has duplicate section title '" .. t
                                .. "' - per-line customization may target the wrong section.")
                        end
                        seen[t] = true
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

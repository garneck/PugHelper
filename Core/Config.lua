--[[-------------------------------------------------------------------------
    PUG Helper - Core/Config.lua
---------------------------------------------------------------------------
    Owns the saved variables. This module's typed accessors are the ONLY code
    that touches the PugHelperDB global directly, so the schema lives in one
    place and the rest of the addon never pokes raw saved-variable tables.

    Add any new persistent setting to DEFAULTS (merged via util.applyDefaults
    on load) and expose it through an accessor here.
---------------------------------------------------------------------------]]

local _, ns = ...
local Config = ns.Config

-- Defaults merged into PugHelperDB on load. Keys with a nil value (point,
-- selectedInstance) are intentionally absent here and resolved lazily/at boot.
local DEFAULTS = {
    channel = "AUTO",   -- one of CHANNEL_NAMES below
    names   = {},       -- token -> player name
    custom  = {},       -- instanceId -> content overrides (see Content.lua)
    -- User role customization (see Content.lua). `global` applies on every tab;
    -- `byInstance[instanceId]` only shows on that raid's tab (each a list of
    -- { key, label }, like the built-ins in Content/Roles.lua). `hidden[instanceId]`
    -- is a set of uppercased tokens suppressed on that tab, so any role -
    -- including a built-in - can be deleted from a raid without touching defaults.
    -- `labels[instanceId]` is a per-tab map of token -> display-label override (so a
    -- renamed built-in/global role stays scoped to the tab it was edited on), and
    -- `order[instanceId]` is a per-tab list of uppercased tokens giving the display
    -- order (tokens not listed fall in after, in natural order).
    customRoles = { global = {}, byInstance = {}, hidden = {}, labels = {}, order = {} },
    -- Minimap launcher button: angle (degrees) around the ring + a hidden flag.
    minimap = { angle = 220, hide = false },
    -- One-time UI tips already shown (so they print once, ever). e.g. the edit-mode
    -- gesture tip on first entering Edit.
    editTipShown = false,
}

-- Output channels in cycle order, defined in ONE place. `requires` is the group
-- state the channel needs; Chat.ResolveChannel downgrades when it isn't met.
Config.CHANNELS = {
    { name = "AUTO" },
    { name = "RAID",         requires = "raid"  },
    { name = "RAID_WARNING", requires = "raid"  },
    { name = "PARTY",        requires = "group" },
    { name = "SAY" },
    { name = "GUILD",        requires = "guild" },
}

Config.CHANNEL_NAMES, Config.CHANNEL_REQUIRES, Config.CHANNEL_INDEX = {}, {}, {}
for i, c in ipairs(Config.CHANNELS) do
    Config.CHANNEL_NAMES[i]          = c.name
    Config.CHANNEL_REQUIRES[c.name]  = c.requires
    Config.CHANNEL_INDEX[c.name]     = i
end

-- Max bytes per SendChatMessage. Hard client limit is 255; we leave headroom
-- and split longer callout lines on word boundaries before sending.
Config.CHAT_LIMIT = 240

-- Initialize saved variables. Call once on ADDON_LOADED (see Boot.lua).
function Config.Init()
    PugHelperDB = PugHelperDB or {}
    ns.util.applyDefaults(PugHelperDB, DEFAULTS)
end

-- ---------------------------------------------------------------------------
--  Channel
-- ---------------------------------------------------------------------------
function Config.Channel()
    -- Self-heal a stale/invalid saved channel (a name removed across versions, or
    -- a hand-edited save) so ResolveChannel never hands an unknown channel to
    -- SendChatMessage, which would error.
    local c = PugHelperDB and PugHelperDB.channel
    if Config.IsChannel(c) then return c end
    return "AUTO"
end

function Config.IsChannel(name)
    return Config.CHANNEL_INDEX[name] ~= nil
end

function Config.SetChannel(name)
    if PugHelperDB and Config.IsChannel(name) then
        PugHelperDB.channel = name
        return true
    end
    return false
end

-- Step the channel one position; `back` cycles to the previous (right-click) so a
-- single overshoot is one click to recover, instead of a full loop around. Routes
-- the write through SetChannel so the PugHelperDB nil-guard + validation live in
-- one place (every stepped name is valid, so this always sets). Returns the name.
function Config.CycleChannel(back)
    local n = #Config.CHANNEL_NAMES
    local idx = Config.CHANNEL_INDEX[Config.Channel()] or 1
    idx = back and ((idx - 2) % n) + 1 or (idx % n) + 1
    Config.SetChannel(Config.CHANNEL_NAMES[idx])
    return Config.Channel()
end

-- ---------------------------------------------------------------------------
--  Names (token -> player name)
-- ---------------------------------------------------------------------------
function Config.Names()
    if not PugHelperDB then return {} end
    PugHelperDB.names = PugHelperDB.names or {}
    return PugHelperDB.names
end

-- Tokens are case-insensitive. Every write path already stores them uppercase
-- (built-in role keys, /pug name, custom roles), so normalize on read/write here
-- too - this is what lets a callout written with a lowercase {mt} fill in from a
-- name set under MT instead of being sent to chat literally. Idempotent for the
-- existing uppercase callers.
function Config.GetName(token)
    return Config.Names()[tostring(token or ""):upper()]
end

function Config.SetName(token, value)
    Config.Names()[tostring(token or ""):upper()] = value or ""
end

-- Drop every saved name whose token `keep(token)` returns falsy. The pruning
-- POLICY (which tokens are still live) lives in Content; this owns only the
-- saved-vars iteration so PugHelperDB stays Config's alone.
function Config.PruneNames(keep)
    local names = Config.Names()
    for token in pairs(names) do
        if type(token) ~= "string" or not keep(token) then
            names[token] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
--  Window position
-- ---------------------------------------------------------------------------
function Config.Point()
    return PugHelperDB and PugHelperDB.point
end

function Config.SetPoint(p)
    if PugHelperDB then PugHelperDB.point = p end
end

-- ---------------------------------------------------------------------------
--  Selected instance (which raid/heroic is open) + content override store
-- ---------------------------------------------------------------------------
function Config.SelectedInstance()
    return PugHelperDB and PugHelperDB.selectedInstance
end

function Config.SetSelectedInstance(id)
    if PugHelperDB then PugHelperDB.selectedInstance = id end
end

-- The raw customization store (instanceId -> { sections = {...} }). Content.lua
-- gives this structure meaning (fork-on-edit); callers should prefer Content's
-- mutators rather than writing it directly.
function Config.Custom()
    if not PugHelperDB then return {} end
    PugHelperDB.custom = PugHelperDB.custom or {}
    return PugHelperDB.custom
end

-- ---------------------------------------------------------------------------
--  Custom role definitions (user-added {TOKEN}s; see Content.lua)
-- ---------------------------------------------------------------------------
-- The raw custom-role store, structure ensured: { global = {...}, byInstance =
-- { [instanceId] = {...} } } where each list holds { key, label } entries.
-- Content.lua owns the add/remove policy (token sanitizing, collisions); this
-- just guarantees the shape so the rest of the addon never pokes PugHelperDB.
function Config.CustomRoles()
    if not PugHelperDB then return { global = {}, byInstance = {}, hidden = {}, labels = {}, order = {} } end
    local cr = PugHelperDB.customRoles or {}
    cr.global     = cr.global or {}
    cr.byInstance = cr.byInstance or {}
    cr.hidden     = cr.hidden or {}
    cr.labels     = cr.labels or {}
    cr.order      = cr.order or {}
    PugHelperDB.customRoles = cr
    return cr
end

-- Drop per-instance customization (content overrides, custom roles, hidden sets)
-- for any instanceId where `isLive(id)` is falsy. The POLICY (which ids still
-- exist) lives in Content; this owns only the saved-vars iteration so PugHelperDB
-- stays Config's alone, mirroring Config.PruneNames.
function Config.PruneCustomization(isLive)
    if not PugHelperDB then return end
    local function sweep(tbl)
        if type(tbl) ~= "table" then return end
        for id in pairs(tbl) do
            if not isLive(id) then tbl[id] = nil end
        end
    end
    sweep(PugHelperDB.custom)
    local cr = PugHelperDB.customRoles
    if type(cr) == "table" then
        sweep(cr.byInstance)
        sweep(cr.hidden)
        sweep(cr.labels)
        sweep(cr.order)
    end
end

-- ---------------------------------------------------------------------------
--  Minimap button (angle around the ring + show/hide)
-- ---------------------------------------------------------------------------
function Config.Minimap()
    if not PugHelperDB then return { angle = 220, hide = false } end
    PugHelperDB.minimap = PugHelperDB.minimap or { angle = 220, hide = false }
    return PugHelperDB.minimap
end

function Config.MinimapAngle()
    return Config.Minimap().angle or 220
end

function Config.SetMinimapAngle(angle)
    Config.Minimap().angle = angle
end

function Config.MinimapHidden()
    return Config.Minimap().hide and true or false
end

function Config.SetMinimapHidden(hide)
    Config.Minimap().hide = hide and true or false
end

-- ---------------------------------------------------------------------------
--  One-time tips
-- ---------------------------------------------------------------------------
function Config.EditTipShown()
    return PugHelperDB and PugHelperDB.editTipShown and true or false
end

function Config.SetEditTipShown(shown)
    if PugHelperDB then PugHelperDB.editTipShown = shown and true or false end
end

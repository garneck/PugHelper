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
    customRoles = { global = {}, byInstance = {}, hidden = {} },
}

-- Output channels in cycle order, defined in ONE place. `requires` is the group
-- state the channel needs; Chat.ResolveChannel downgrades when it isn't met.
Config.CHANNELS = {
    { name = "AUTO" },
    { name = "RAID",         requires = "raid"  },
    { name = "RAID_WARNING", requires = "raid"  },
    { name = "PARTY",        requires = "group" },
    { name = "SAY" },
    { name = "GUILD" },
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
    return (PugHelperDB and PugHelperDB.channel) or "AUTO"
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

-- Advance to the next channel in cycle order; returns the new channel name.
function Config.CycleChannel()
    local idx = Config.CHANNEL_INDEX[Config.Channel()] or 1
    idx = (idx % #Config.CHANNEL_NAMES) + 1
    PugHelperDB.channel = Config.CHANNEL_NAMES[idx]
    return PugHelperDB.channel
end

-- ---------------------------------------------------------------------------
--  Names (token -> player name)
-- ---------------------------------------------------------------------------
function Config.Names()
    if not PugHelperDB then return {} end
    PugHelperDB.names = PugHelperDB.names or {}
    return PugHelperDB.names
end

function Config.GetName(token)
    return Config.Names()[token]
end

function Config.SetName(token, value)
    Config.Names()[token] = value or ""
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
    if not PugHelperDB then return { global = {}, byInstance = {}, hidden = {} } end
    local cr = PugHelperDB.customRoles or {}
    cr.global     = cr.global or {}
    cr.byInstance = cr.byInstance or {}
    cr.hidden     = cr.hidden or {}
    PugHelperDB.customRoles = cr
    return cr
end

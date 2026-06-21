--[[-------------------------------------------------------------------------
    PUG Helper - Core/Api.lua
---------------------------------------------------------------------------
    Every version-sensitive WoW API call lives here, in ONE place, behind a
    type-guard with a fallback and a safe default. See CLAUDE.md: the
    Anniversary client may expose the modern call, the old 2.0.5-era name, or
    neither, so we never hard-depend on a single one.

    `has`/`hasMethod` replace the repeated inline `type(Foo) == "function"`
    checks the engine used to sprinkle around (DRY). Introduce new shims here
    rather than calling a possibly-missing global bare elsewhere.
---------------------------------------------------------------------------]]

local _, ns = ...
local api = ns.api

-- True if a global function of this name exists in the current client.
function api.has(name)
    return type(_G[name]) == "function"
end

-- True if tbl is a table with a callable method `name` (for C_* namespaces etc).
function api.hasMethod(tbl, name)
    return type(tbl) == "table" and type(tbl[name]) == "function"
end

-- ---------------------------------------------------------------------------
--  Group / roster state (modern call preferred, old name as fallback)
-- ---------------------------------------------------------------------------
function api.InRaid()
    if api.has("IsInRaid") then return IsInRaid() end
    if api.has("GetNumRaidMembers") then return GetNumRaidMembers() > 0 end
    return false
end

function api.InGroup()
    if api.has("IsInGroup") then return IsInGroup() end
    if api.has("GetNumPartyMembers") and GetNumPartyMembers() > 0 then return true end
    return api.InRaid()
end

-- Number of raid members (whole raid, incl. self).
function api.RaidCount()
    if api.has("GetNumGroupMembers") then return GetNumGroupMembers() end
    if api.has("GetNumRaidMembers") then return GetNumRaidMembers() end
    return 0
end

-- Number of party members NOT counting the player.
function api.PartyCount()
    if api.has("GetNumSubgroupMembers") then return GetNumSubgroupMembers() end
    if api.has("GetNumGroupMembers") then return math.max(GetNumGroupMembers() - 1, 0) end
    if api.has("GetNumPartyMembers") then return GetNumPartyMembers() end
    return 0
end

-- Current group member names (self + party/raid), sorted and de-duped.
function api.GroupRoster()
    local names, seen = {}, {}
    local function add(n)
        if n and n ~= "" and not seen[n] then
            seen[n] = true
            table.insert(names, n)
        end
    end
    if api.InRaid() then
        for i = 1, api.RaidCount() do
            local raidName = (api.has("GetRaidRosterInfo") and GetRaidRosterInfo(i))
                or UnitName("raid" .. i)
            add(raidName)
        end
    else
        add(UnitName("player"))
        for i = 1, api.PartyCount() do
            add(UnitName("party" .. i))
        end
    end
    table.sort(names)
    return names
end

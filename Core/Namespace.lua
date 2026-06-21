--[[-------------------------------------------------------------------------
    PUG Helper - Core/Namespace.lua
---------------------------------------------------------------------------
    Bootstrap for the addon's private namespace.

    Every file of the addon receives the same private table as its second
    vararg:  local ADDON_NAME, ns = ...
    `ns` is shared across all files by the WoW addon loader, so we hang every
    module off it instead of polluting the global namespace. Only PugHelperDB
    (saved variables) and the SLASH_* / SlashCmdList globals remain global.

    This file MUST load first (see PugHelper.toc). It just creates the empty
    sub-tables the other modules fill in; no WoW API is called here.
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME
ns.VERSION    = "2.0"

-- Module sub-tables. Each is created with `x or {}` so load order can shift
-- without a file accidentally wiping another's contribution.
ns.util    = ns.util    or {}   -- pure helpers, no WoW API (Util.lua)
ns.api     = ns.api     or {}   -- WoW API compat shims (Api.lua)
ns.Config  = ns.Config  or {}   -- saved variables / settings (Config.lua)
ns.Content = ns.Content or {}   -- callout registry + override merge (Content.lua)
ns.Chat    = ns.Chat    or {}   -- substitution / channel / send (Chat.lua)
ns.UI      = ns.UI      or {}   -- window, panels, editor (UI/*.lua)
ns.Slash   = ns.Slash   or {}   -- /pug command handling (Slash.lua)

-- Friendly chat print, used everywhere. Kept here (not in Util) because it is
-- the one helper that legitimately depends on a WoW global, and every module
-- wants it available immediately.
function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66bbffPUG Helper|r: " .. tostring(msg))
end

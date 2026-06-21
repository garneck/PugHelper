-- luacheck config for the PUG Helper WoW addon (TBC Anniversary, 2.0.5)
-- Run:  luacheck .
-- Install: luarocks install luacheck

-- Use the Lua 5.1 standard library (WoW's Lua flavor) plus no implicit globals.
std = "lua51"

-- WoW loads each .lua in its own chunk and shares state via the global table,
-- so the addon's own cross-file globals are expected, not errors.
globals = {
    "PugHelperDB",        -- saved variables (Core.lua)
    "PugHelperRaids",     -- raid content (Data.lua)
    "PugHelperRoles",     -- role definitions (Data.lua)
    "SlashCmdList",       -- written: command handler registration
    "SLASH_PUGHELPER1",   -- slash alias /pug   (read by the WoW client, not by us)
    "SLASH_PUGHELPER2",   -- slash alias /pughelper
}

-- WoW frame/callback handlers (OnEvent, OnDragStop, ...) get fixed-signature
-- args we often don't use. That's expected, not a smell.
unused_args = false

-- WoW API surface used by the addon. read_globals = referenced but never assigned.
read_globals = {
    "CreateFrame",
    "UIParent",
    "UISpecialFrames",
    "GetTime",
    "SendChatMessage",
    "IsInRaid",
    "IsInGroup",
    "GetNumRaidMembers",
    "GetNumPartyMembers",
    "GetNumGroupMembers",
    "InCombatLockdown",
    "PlaySound",
    "GameTooltip",
    "DEFAULT_CHAT_FRAME",
    "C_Timer",
    "strsplit",
    "strtrim",
    "strjoin",
    "tinsert",
    "tremove",
    "wipe",
    "format",
}

-- Long callout strings in Data.lua are intentional; don't flag line length.
max_line_length = false

exclude_files = {
    ".luacheckrc",
}

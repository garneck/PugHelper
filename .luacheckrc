-- luacheck config for the PUG Helper WoW addon (TBC Anniversary, 2.0.5)
-- Run:  luacheck .
-- Install: luarocks install luacheck

-- Use the Lua 5.1 standard library (WoW's Lua flavor) plus no implicit globals.
std = "lua51"

-- Cross-file state is shared via the addon's private namespace (the second
-- `...` vararg: `local _, ns = ...`), NOT via globals. The only true globals
-- left are the saved variables and the slash registration below.
globals = {
    "PugHelperDB",        -- saved variables (Core/Config.lua)
    "SlashCmdList",       -- written: command handler registration (Core/Slash.lua)
    "SLASH_PUGHELPER1",   -- slash alias /pug   (read by the WoW client, not by us)
    "SLASH_PUGHELPER2",   -- slash alias /pughelper
}

-- WoW frame/callback handlers (OnEvent, OnDragStop, ...) get fixed-signature
-- args we often don't use. That's expected, not a smell.
unused_args = false

-- WoW API surface used by the addon. read_globals = referenced but never assigned.
-- Keep this list in sync with what the addon actually calls: every entry should be
-- used, and every WoW global the code touches should be listed (or luacheck flags
-- it as an undefined global). Standard Lua 5.1 names come from std = "lua51".
read_globals = {
    -- Frames / UI
    "CreateFrame",
    "UIParent",
    "UISpecialFrames",
    "GameTooltip",
    "DEFAULT_CHAT_FRAME",
    -- Dropdown menu helpers (UIDropDownMenuTemplate)
    "UIDropDownMenu_SetWidth",
    "UIDropDownMenu_Initialize",
    "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_AddButton",
    "UIDropDownMenu_SetText",
    -- Chat
    "SendChatMessage",
    -- Group / roster state
    "IsInRaid",
    "IsInGroup",
    "GetNumRaidMembers",
    "GetNumPartyMembers",
    "GetNumGroupMembers",
    "GetNumSubgroupMembers",
    "GetRaidRosterInfo",
    "UnitName",
}

-- Long callout strings in Data.lua are intentional; don't flag line length.
max_line_length = false

exclude_files = {
    ".luacheckrc",
}

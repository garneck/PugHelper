--[[-------------------------------------------------------------------------
    PUG Helper - Content/Roles.lua
---------------------------------------------------------------------------
    Role tokens shown in the "Set Names" panel. key = the {TOKEN} used in
    callout lines; label = the display name in the panel.

    IMPORTANT: keys must be letters/numbers only (no spaces, dashes, or
    underscores). Substitution matches {%w+}, so a key like "INT_1" would
    never get filled in.
---------------------------------------------------------------------------]]

local _, ns = ...

ns:RegisterRoles({
    { key = "MT",   label = "Main Tank" },
    { key = "OT",   label = "Off Tank" },
    { key = "OT2",  label = "Off Tank 2" },
    { key = "OT3",  label = "Off Tank 3" },
    { key = "H1",   label = "Healer 1" },
    { key = "H2",   label = "Healer 2" },
    { key = "H3",   label = "Healer 3" },
    { key = "H4",   label = "Healer 4" },
    { key = "H5",   label = "Healer 5" },
    { key = "CC1",  label = "Crowd Control 1" },
    { key = "CC2",  label = "Crowd Control 2" },
    { key = "CC3",  label = "Crowd Control 3" },
    { key = "INT1", label = "Interrupt 1" },
    { key = "INT2", label = "Interrupt 2" },
    { key = "DISP", label = "Dispel / Decurse" },
    { key = "BL",   label = "Bloodlust / Hero" },
})

--[[-------------------------------------------------------------------------
    PUG Helper - Content/Raids/Karazhan.lua
---------------------------------------------------------------------------
    A single raid instance. This is the file you edit to change Karazhan
    callouts (or copy it to add a new raid: change the name and content, then
    add the file to PugHelper.toc).

    HOW IT WORKS
      ns:RegisterInstance(category, { name, note, sections }) adds a tab.
      Each section has a title and a list of "lines" (strings ending in commas).
      Any {TOKEN} in a line is replaced with the name set in "Set Names".
      Lines longer than ~240 chars are auto-split when sent; shorter reads better.

    The section titles below are pre-filled (Trash + every boss); the line
    lists are empty so you can add your own callouts here, or in-game with the
    "Edit" button (those edits persist without touching this file).
---------------------------------------------------------------------------]]

local _, ns = ...

ns:RegisterInstance("raids", {
    name = "Karazhan",
    note = "10-player | Phase 1",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Attumen the Huntsman", lines = {} },
        { title = "Moroes", lines = {} },
        { title = "Maiden of Virtue", lines = {} },
        { title = "Opera Event", lines = {} },
        { title = "The Curator", lines = {} },
        { title = "Terestian Illhoof", lines = {} },
        { title = "Shade of Aran", lines = {} },
        { title = "Netherspite", lines = {} },
        { title = "Chess Event", lines = {} },
        { title = "Prince Malchezaar", lines = {} },
        { title = "Nightbane (optional)", lines = {} },
    },
})

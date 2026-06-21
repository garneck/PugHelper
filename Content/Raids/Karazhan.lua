--[[-------------------------------------------------------------------------
    PUG Helper - Content/Raids/Karazhan.lua
---------------------------------------------------------------------------
    Edit this file to change Karazhan, or copy it to add a raid (change the
    name/sections, then add the file to PugHelper.toc).

    ns:RegisterInstance(category, { name, note, sections })
      `sections` is a list; each entry is either:
        "Boss Name"                                       -- title only, no lines
        { title = "Boss", lines = { "callout", ... } }    -- title with callouts
      Any {TOKEN} in a line is replaced with the name set in "Set Names".

    The titles below have empty line lists, so add your own callouts here or
    in-game with the "Edit" button (in-game edits persist without this file).
---------------------------------------------------------------------------]]

local _, ns = ...

ns:RegisterInstance("raids", {
    name = "Karazhan",
    note = "10-player | Phase 1",
    sections = {
        "Trash",
        "Attumen the Huntsman",
        "Moroes",
        "Maiden of Virtue",
        "Opera Event",
        "The Curator",
        "Terestian Illhoof",
        "Shade of Aran",
        "Netherspite",
        "Chess Event",
        "Prince Malchezaar",
        "Nightbane (optional)",
    },
})

--[[ PUG Helper - Content/Heroics/Mana-Tombs.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "Mana-Tombs",
    note = "5-player Heroic | Auchindoun",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Pandemonius", lines = {} },
        { title = "Tavarok", lines = {} },
        { title = "Nexus-Prince Shaffar", lines = {} },
        { title = "Yor (Heroic only)", lines = {} },
    },
})

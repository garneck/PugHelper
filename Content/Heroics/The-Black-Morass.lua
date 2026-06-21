--[[ PUG Helper - Content/Heroics/The-Black-Morass.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "The Black Morass",
    note = "5-player Heroic | Caverns of Time",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Chrono Lord Deja", lines = {} },
        { title = "Temporus", lines = {} },
        { title = "Aeonus", lines = {} },
    },
})

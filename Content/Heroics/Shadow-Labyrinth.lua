--[[ PUG Helper - Content/Heroics/Shadow-Labyrinth.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "Shadow Labyrinth",
    note = "5-player Heroic | Auchindoun",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Ambassador Hellmaw", lines = {} },
        { title = "Blackheart the Inciter", lines = {} },
        { title = "Grandmaster Vorpil", lines = {} },
        { title = "Murmur", lines = {} },
    },
})

--[[ PUG Helper - Content/Heroics/The-Botanica.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "The Botanica",
    note = "5-player Heroic | Tempest Keep",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Commander Sarannis", lines = {} },
        { title = "High Botanist Freywinn", lines = {} },
        { title = "Thorngrin the Tender", lines = {} },
        { title = "Laj", lines = {} },
        { title = "Warp Splinter", lines = {} },
    },
})

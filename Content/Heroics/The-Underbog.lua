--[[ PUG Helper - Content/Heroics/The-Underbog.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "The Underbog",
    note = "5-player Heroic | Coilfang Reservoir",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Hungarfen", lines = {} },
        { title = "Ghaz'an", lines = {} },
        { title = "Swamplord Musel'ek", lines = {} },
        { title = "The Black Stalker", lines = {} },
    },
})

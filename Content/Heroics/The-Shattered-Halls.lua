--[[ PUG Helper - Content/Heroics/The-Shattered-Halls.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "The Shattered Halls",
    note = "5-player Heroic | Hellfire Citadel",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Grand Warlock Nethekurse", lines = {} },
        { title = "Blood Guard Porung", lines = {} },
        { title = "Warbringer O'mrogg", lines = {} },
        { title = "Warchief Kargath Bladefist", lines = {} },
    },
})

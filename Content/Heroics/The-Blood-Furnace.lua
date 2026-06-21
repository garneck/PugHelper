--[[ PUG Helper - Content/Heroics/The-Blood-Furnace.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "The Blood Furnace",
    note = "5-player Heroic | Hellfire Citadel",
    sections = {
        { title = "Trash", lines = {} },
        { title = "The Maker", lines = {} },
        { title = "Broggok", lines = {} },
        { title = "Keli'dan the Breaker", lines = {} },
    },
})

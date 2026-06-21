--[[ PUG Helper - Content/Heroics/Hellfire-Ramparts.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "Hellfire Ramparts",
    note = "5-player Heroic | Hellfire Citadel",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Watchkeeper Gargolmar", lines = {} },
        { title = "Omor the Unscarred", lines = {} },
        { title = "Nazan & Vazruden", lines = {} },
    },
})

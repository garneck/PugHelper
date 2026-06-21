--[[ PUG Helper - Content/Heroics/Auchenai-Crypts.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "Auchenai Crypts",
    note = "5-player Heroic | Auchindoun",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Shirrak the Dead Watcher", lines = {} },
        { title = "Exarch Maladaar", lines = {} },
    },
})

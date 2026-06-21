--[[ PUG Helper - Content/Heroics/The-Steamvault.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "The Steamvault",
    note = "5-player Heroic | Coilfang Reservoir",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Hydromancer Thespia", lines = {} },
        { title = "Mekgineer Steamrigger", lines = {} },
        { title = "Warlord Kalithresh", lines = {} },
    },
})

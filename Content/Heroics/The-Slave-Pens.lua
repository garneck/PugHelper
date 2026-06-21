--[[ PUG Helper - Content/Heroics/The-Slave-Pens.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "The Slave Pens",
    note = "5-player Heroic | Coilfang Reservoir",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Mennu the Betrayer", lines = {} },
        { title = "Rokmar the Crackler", lines = {} },
        { title = "Quagmirran", lines = {} },
    },
})

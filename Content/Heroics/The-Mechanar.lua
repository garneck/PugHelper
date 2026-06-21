--[[ PUG Helper - Content/Heroics/The-Mechanar.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "The Mechanar",
    note = "5-player Heroic | Tempest Keep",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Gatewatcher Gyro-Kill", lines = {} },
        { title = "Gatewatcher Iron-Hand", lines = {} },
        { title = "Mechano-Lord Capacitus", lines = {} },
        { title = "Nethermancer Sepethrea", lines = {} },
        { title = "Pathaleon the Calculator", lines = {} },
    },
})

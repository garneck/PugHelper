--[[ PUG Helper - Content/Raids/Gruuls-Lair.lua
     Section titles (Trash + bosses) are pre-filled; line lists are empty so you
     can add your own callouts here or in-game via the "Edit" button. ]]

local _, ns = ...

ns:RegisterInstance("raids", {
    name = "Gruul's Lair",
    note = "25-player | Phase 1",
    sections = {
        { title = "Trash", lines = {} },
        { title = "High King Maulgar", lines = {} },
        { title = "Gruul the Dragonkiller", lines = {} },
    },
})

--[[ PUG Helper - Content/Raids/Magtheridons-Lair.lua
     Section titles (Trash + bosses) are pre-filled; line lists are empty so you
     can add your own callouts here or in-game via the "Edit" button. ]]

local _, ns = ...

ns:RegisterInstance("raids", {
    name = "Magtheridon's Lair",
    note = "25-player | Phase 1",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Magtheridon", lines = {} },
    },
})

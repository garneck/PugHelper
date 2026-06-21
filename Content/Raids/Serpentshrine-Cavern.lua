--[[ PUG Helper - Content/Raids/Serpentshrine-Cavern.lua
     Section titles (Trash + bosses) are pre-filled; line lists are empty so you
     can add your own callouts here or in-game via the "Edit" button. ]]

local _, ns = ...

ns:RegisterInstance("raids", {
    name = "Serpentshrine Cavern",
    note = "25-player | Phase 2",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Hydross the Unstable", lines = {} },
        { title = "The Lurker Below", lines = {} },
        { title = "Leotheras the Blind", lines = {} },
        { title = "Fathom-Lord Karathress", lines = {} },
        { title = "Morogrim Tidewalker", lines = {} },
        { title = "Lady Vashj", lines = {} },
    },
})

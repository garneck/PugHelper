--[[ PUG Helper - Content/Raids/The-Eye.lua
     Section titles (Trash + bosses) are pre-filled; line lists are empty so you
     can add your own callouts here or in-game via the "Edit" button. ]]

local _, ns = ...

ns:RegisterInstance("raids", {
    name = "The Eye (Tempest Keep)",
    note = "25-player | Phase 2",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Al'ar", lines = {} },
        { title = "Void Reaver", lines = {} },
        { title = "High Astromancer Solarian", lines = {} },
        { title = "Kael'thas Sunstrider", lines = {} },
    },
})

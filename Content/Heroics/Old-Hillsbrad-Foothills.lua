--[[ PUG Helper - Content/Heroics/Old-Hillsbrad-Foothills.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "Old Hillsbrad Foothills",
    note = "5-player Heroic | Caverns of Time",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Lieutenant Drake", lines = {} },
        { title = "Captain Skarloc", lines = {} },
        { title = "Epoch Hunter", lines = {} },
    },
})

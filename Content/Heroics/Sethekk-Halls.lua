--[[ PUG Helper - Content/Heroics/Sethekk-Halls.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "Sethekk Halls",
    note = "5-player Heroic | Auchindoun",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Darkweaver Syth", lines = {} },
        { title = "Talon King Ikiss", lines = {} },
        { title = "Anzu (Druid summon)", lines = {} },
    },
})

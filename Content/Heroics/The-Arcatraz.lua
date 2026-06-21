--[[ PUG Helper - Content/Heroics/The-Arcatraz.lua
     Trash + boss titles pre-filled; line lists empty for your own callouts
     (edit here or in-game via the "Edit" button). ]]

local _, ns = ...

ns:RegisterInstance("heroics", {
    name = "The Arcatraz",
    note = "5-player Heroic | Tempest Keep",
    sections = {
        { title = "Trash", lines = {} },
        { title = "Zereketh the Unbound", lines = {} },
        { title = "Dalliah the Doomsayer", lines = {} },
        { title = "Wrath-Scryer Soccothrates", lines = {} },
        { title = "Harbinger Skyriss", lines = {} },
    },
})

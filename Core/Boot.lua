--[[-------------------------------------------------------------------------
    PUG Helper - Core/Boot.lua
---------------------------------------------------------------------------
    Loaded LAST. Wires the init order on ADDON_LOADED, by which point the
    saved variables are populated and every module + all content is registered.
---------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON_NAME then return end

    ns.Config.Init()

    -- Resolve the selected instance: keep a still-valid saved choice, else fall
    -- back to the first registered instance (handles old saves / removed content).
    local sel = ns.Config.SelectedInstance()
    if not sel or not ns.Content.Get(sel) then
        ns.Config.SetSelectedInstance(ns.Content.FirstInstanceId())
    end

    ns.Content.Validate()
    ns.Content.PruneNames()
    ns.Print("loaded. Type /pug to open.")

    self:UnregisterEvent("ADDON_LOADED")
end)

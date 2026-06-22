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

    -- Normalize the saved selection (keep it if still valid, else fall back to
    -- the first registered instance) so old saves / removed content can't leave
    -- a dangling id. The fallback policy lives in Content.ResolveSelectedInstance.
    ns.Config.SetSelectedInstance(ns.Content.ResolveSelectedInstance())

    ns.Content.Validate()
    ns.Content.PruneNames()

    -- Build the minimap launcher now (not lazily with the window) so it's visible
    -- at login. Guarded: a no-op if the build helper or Minimap global is absent.
    if ns.UI.BuildMinimapButton then ns.UI.BuildMinimapButton() end

    -- Name both entry points (slash + the eagerly-built minimap button), dropping
    -- the button mention when the user has hidden it so the line stays accurate.
    local entry = ns.Config.MinimapHidden() and "Type /pug" or "Type /pug or click the minimap button"
    ns.Print("loaded. " .. entry .. " to open.")

    self:UnregisterEvent("ADDON_LOADED")
end)

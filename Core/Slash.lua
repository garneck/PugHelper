--[[-------------------------------------------------------------------------
    PUG Helper - Core/Slash.lua
---------------------------------------------------------------------------
    /pug (alias /pughelper) command parsing. Thin dispatch layer: it parses
    arguments and delegates to Config / Content / UI. No state of its own.
---------------------------------------------------------------------------]]

local _, ns = ...
local Slash = ns.Slash

function Slash.Handle(msg)
    msg = ns.util.trim(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "" or cmd == "show" or cmd == "toggle" then
        ns.UI.Toggle()

    elseif cmd == "edit" then
        ns.UI.Open()
        ns.UI.ToggleEdit()

    elseif cmd == "name" then
        -- "TOKEN value" or just "TOKEN" (value defaults to "" -> clears the name).
        local token, value = rest:match("^(%S+)%s*(.*)$")
        if not token then
            ns.Print("Usage: /pug name TOKEN Yourname   (e.g. /pug name MT Bigtank)")
        elseif not token:match("^%w+$") then
            -- Substitution only matches {%w+}; reject tokens that could never fill in.
            ns.Print("Token must be letters/numbers only (no spaces, dashes, or underscores): " .. token)
        else
            token = token:upper()
            ns.Config.SetName(token, value)
            if value ~= "" then
                ns.Print("Set {" .. token .. "} = " .. value)
            else
                ns.Print("Cleared {" .. token .. "}")
            end
            ns.UI.RefreshNamesPanel()
            if ns.UI.frame and ns.UI.frame:IsShown() then ns.UI.Refresh(true) end
        end

    elseif cmd == "names" then
        ns.Print("Current names:")
        for _, role in ipairs(ns.Content.EffectiveRoles(ns.Config.SelectedInstance())) do
            local n = ns.Config.GetName(role.key)
            ns.Print("  {" .. role.key .. "} (" .. (role.label or "?") .. ") = "
                .. (n and n ~= "" and n or "|cff888888-not set-|r"))
        end

    elseif cmd == "channel" then
        local c = rest:upper()
        if ns.Config.SetChannel(c) then
            ns.UI.UpdateChannelButton()
            ns.Print("Channel set to " .. c)
        else
            -- No/invalid argument: report the current channel (and where it lands
            -- right now) before listing the valid values.
            local cfg, res = ns.Config.Channel(), ns.Chat.ResolveChannel()
            ns.Print("Channel: " .. cfg .. (res ~= cfg and (" (sending to " .. res .. ")") or ""))
            ns.Print("Channels: " .. table.concat(ns.Config.CHANNEL_NAMES, ", "))
        end

    elseif cmd == "minimap" then
        ns.Config.SetMinimapHidden(not ns.Config.MinimapHidden())
        if ns.UI.UpdateMinimapButton then ns.UI.UpdateMinimapButton() end
        ns.Print(ns.Config.MinimapHidden() and "Minimap button hidden." or "Minimap button shown.")

    elseif cmd == "reset" then
        ns.Config.SetPoint(nil)
        ns.UI.RestorePoint()
        ns.Print("Window position reset.")

    else
        ns.Print("Commands:")
        ns.Print("  /pug                 - open/close the window (or click the minimap button)")
        ns.Print("  /pug edit            - toggle in-game callout editing")
        ns.Print("  /pug name MT Name    - assign a player to a {TOKEN} (letters/numbers only)")
        ns.Print("  /pug names           - list role names")
        ns.Print("  /pug channel RAID    - set channel (AUTO/RAID/RAID_WARNING/PARTY/SAY/GUILD)")
        ns.Print("  /pug minimap         - show/hide the minimap button")
        ns.Print("  /pug reset           - reset window position")
        ns.Print("Tip: open Set Names to assign roles, then click a callout line to send it.")
    end
end

SLASH_PUGHELPER1 = "/pug"
SLASH_PUGHELPER2 = "/pughelper"
SlashCmdList["PUGHELPER"] = Slash.Handle

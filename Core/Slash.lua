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
        local token, value = rest:match("^(%S+)%s+(.+)$")
        if not token then
            token = rest:match("^(%S+)$")
            value = ""
        end
        if not token then
            ns.Print("Usage: /pug name TOKEN Yourname   (e.g. /pug name MT Bigtank)")
        elseif not token:match("^%w+$") then
            -- Substitution only matches {%w+}; reject tokens that could never fill in.
            ns.Print("Token must be letters/numbers only (no spaces, dashes, or underscores): " .. token)
        else
            token = token:upper()
            ns.Config.SetName(token, value or "")
            if value and value ~= "" then
                ns.Print("Set {" .. token .. "} = " .. value)
            else
                ns.Print("Cleared {" .. token .. "}")
            end
            ns.UI.RefreshNamesPanel()
            if ns.UI.frame and ns.UI.frame:IsShown() then ns.UI.Refresh() end
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
            ns.Print("Channels: " .. table.concat(ns.Config.CHANNEL_NAMES, ", "))
        end

    elseif cmd == "reset" then
        ns.Config.SetPoint(nil)
        ns.UI.RestorePoint()
        ns.Print("Window position reset.")

    else
        ns.Print("Commands:")
        ns.Print("  /pug                 - open/close the window")
        ns.Print("  /pug edit            - toggle in-game callout editing")
        ns.Print("  /pug name MT Name    - set a role name")
        ns.Print("  /pug names           - list role names")
        ns.Print("  /pug channel RAID    - set output channel")
        ns.Print("  /pug reset           - reset window position")
    end
end

SLASH_PUGHELPER1 = "/pug"
SLASH_PUGHELPER2 = "/pughelper"
SlashCmdList["PUGHELPER"] = Slash.Handle

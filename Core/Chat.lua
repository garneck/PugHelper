--[[-------------------------------------------------------------------------
    PUG Helper - Core/Chat.lua
---------------------------------------------------------------------------
    Token substitution, channel resolution, and sending callouts to chat.
    Pulls names from Config, group state from Api, and text wrapping from Util,
    so the actual SendChatMessage path stays tiny.
---------------------------------------------------------------------------]]

local _, ns = ...
local Chat   = ns.Chat
local Config = ns.Config
local api    = ns.api
local util   = ns.util

-- Replace {TOKEN} with the configured name, or leave {TOKEN} visible if unset.
function Chat.Substitute(text)
    return (tostring(text or ""):gsub("{(%w+)}", function(key)
        local n = Config.GetName(key)
        if n and n ~= "" then return n end
        return "{" .. key .. "}"
    end))
end

-- Resolve the configured channel to one valid for the CURRENT group state.
-- AUTO picks Raid > Party > Say; a manual RAID/RAID_WARNING/PARTY override is
-- quietly downgraded when you're not in such a group, so sending never errors
-- with "You are not in a raid/party group".
function Chat.ResolveChannel()
    local ch = Config.Channel()
    if ch == "AUTO" then
        if api.InRaid() then return "RAID"
        elseif api.InGroup() then return "PARTY"
        else return "SAY" end
    end
    local requires = Config.CHANNEL_REQUIRES[ch]
    if requires == "raid" and not api.InRaid() then
        return api.InGroup() and "PARTY" or "SAY"
    end
    if requires == "group" and not api.InGroup() then
        return "SAY"
    end
    return ch
end

-- Send a line, substituting tokens and splitting on word boundaries to the
-- chat length limit before each SendChatMessage.
function Chat.SendLine(text)
    local channel = Chat.ResolveChannel()
    for _, chunk in ipairs(util.wrap(Chat.Substitute(text), Config.CHAT_LIMIT)) do
        SendChatMessage(chunk, channel)
    end
end

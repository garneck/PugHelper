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

-- Best channel for the current group state: Raid > Party > Say. Used both for
-- AUTO and to downgrade a manual raid-only override when not in a raid.
local function bestAvailable()
    if api.InRaid() then return "RAID" end
    if api.InGroup() then return "PARTY" end
    return "SAY"
end

-- Resolve the configured channel to one valid for the CURRENT state. AUTO picks
-- the best available; a manual RAID/RAID_WARNING/PARTY/GUILD override is quietly
-- downgraded when you're not in such a group/guild, so sending never errors with
-- "You are not in a raid/party group" or "You are not in a guild".
function Chat.ResolveChannel()
    local ch = Config.Channel()
    if ch == "AUTO" then return bestAvailable() end
    local requires = Config.CHANNEL_REQUIRES[ch]
    if requires == "raid"  and not api.InRaid()  then return bestAvailable() end
    if requires == "group" and not api.InGroup() then return "SAY" end
    if requires == "guild" and not api.InGuild() then return bestAvailable() end
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

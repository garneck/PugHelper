--[[-------------------------------------------------------------------------
    PUG Helper - Core/Macro.lua
---------------------------------------------------------------------------
    Turns a callout line into a real WoW macro the user can drag onto an action
    bar, so a single hotkey/click broadcasts the callout mid-pull.

    The macro body is self-contained -- "/pug send <the raw callout>" (handled
    in Slash.lua) -- so it survives /reload, relog, and addon updates with NO
    saved-vars mapping, and it still substitutes {TOKENS} and resolves the
    channel LIVE at click time (the same Chat.SendLine path the in-window click
    uses). The line text (and its {TOKENS}) is baked in, so editing the callout --
    or renaming a custom role token it uses -- does NOT update an already-placed
    macro: it's a snapshot. Drag the line again to place a fresh one. Each distinct
    snapshot is its own macro, so heavy editing accumulates entries in /macro (we
    never delete a placed macro, since the user may still want it on their bar).

    Macro names are a hash of the body ("PH" + base-36, well under the client's
    16-char macro-name limit) so re-dragging the same line REUSES one macro
    instead of spawning duplicates. General (account-wide) macros are used.

    Per the WoW API rules in CLAUDE.md, every macro API is guarded (api.has) and
    creation is wrapped in pcall -- CreateMacro raises a Lua error when the macro
    list is full, so we never call it bare.
---------------------------------------------------------------------------]]

local _, ns = ...
local Macro = ns.Macro
local api   = ns.api
local util  = ns.util

-- The macro runs this slash command, passing the RAW callout so token
-- substitution + channel resolution happen at CLICK time, not now.
local PREFIX = "/pug send "
-- Hard client limit on a macro body. A callout longer than (255 - #PREFIX) can't
-- fit in one macro; we refuse rather than silently truncate the callout text.
local MAX_BODY = 255
Macro.MAX_LINE = MAX_BODY - #PREFIX

-- A "callout/shout" icon, present since vanilla (a wrong icon name only renders
-- blank, never errors). Shared by the drag handle and the created macro so the
-- bar button reads as a PUG Helper callout.
Macro.ICON = "Ability_Warrior_BattleShout"

-- Base-36 encode a non-negative integer (0 -> "0").
local function base36(n)
    local digits, s = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    repeat
        local r = n % 36
        s = digits:sub(r + 1, r + 1) .. s
        n = math.floor(n / 36)
    until n == 0
    return s
end

-- A deterministic, name-safe macro name from the body: "PH" + a base-36 hash.
-- Stays <= 8 chars (well under the 16-char macro-name limit) and maps one body
-- to one macro, so the same callout reuses a single macro across drags.
local function macroName(body)
    local h = 5381
    for i = 1, #body do
        h = (h * 33 + body:byte(i)) % 2147483647   -- exact in doubles (< 2^53)
    end
    return "PH" .. base36(h)
end

-- The macro body for a callout: one trimmed line (a stray newline would turn the
-- macro's second line into a bogus command), prefixed with the send command.
local function lineBody(line)
    return PREFIX .. util.oneLine(line)
end

-- True if `line` is short enough to fit in a single macro. The UI uses this to
-- warn before the user tries to drag an over-long callout.
function Macro.Fits(line)
    return #lineBody(line) <= MAX_BODY
end

-- Ensure a general macro for `body` exists and return its index, or nil + reason.
-- Reuses an existing same-named macro (refreshing its body to cover the rare hash
-- collision / a hand-edit); otherwise creates one. CreateMacro errors when the
-- list is full, so it's pcall'd and a failure is reported as "full".
local function ensureMacro(body)
    if not api.has("CreateMacro") then return nil, "unsupported" end
    local name = macroName(body)
    local idx = (api.has("GetMacroIndexByName") and GetMacroIndexByName(name)) or 0
    if idx and idx > 0 then
        if api.has("EditMacro") then pcall(EditMacro, idx, name, Macro.ICON, body) end
        return idx
    end
    -- 4th arg false => a general (account-wide) macro, shared across characters.
    local ok, newIdx = pcall(CreateMacro, name, Macro.ICON, body, false)
    if ok and type(newIdx) == "number" and newIdx > 0 then return newIdx end
    return nil, "full"
end

-- Build (or reuse) the macro for `line` and put it on the cursor, so the user can
-- drop it on an action-bar slot. Returns true on success, or false + a reason
-- code (see Explain). All preconditions are checked BEFORE creating anything, so
-- we never leave a macro made but un-pickable.
function Macro.PickupForLine(line)
    line = util.oneLine(line)
    if line == "" then return false, "empty" end
    if not (api.has("CreateMacro") and api.has("PickupMacro")) then
        return false, "unsupported"
    end
    -- CreateMacro/PickupMacro are themselves blocked in combat (and an action-bar
    -- drop is a protected action), so refuse to START the gesture in combat. (If
    -- combat begins AFTER pickup, the drop just fails and the macro waits on the
    -- cursor until dropped/cleared - an inherent limit of any pickup-then-place.)
    if api.InCombat() then return false, "combat" end
    if not Macro.Fits(line) then return false, "toolong" end
    local idx, reason = ensureMacro(lineBody(line))
    if not idx then return false, reason end
    PickupMacro(idx)
    return true
end

-- Chat feedback for a PickupForLine failure. "empty" is silent (nothing to make a
-- macro from); the rest explain how to proceed.
function Macro.Explain(reason)
    if reason == "combat" then
        ns.Print("Can't move macros to your action bars during combat - try after the pull.")
    elseif reason == "toolong" then
        ns.Print("This callout is too long to fit in a macro (limit " .. Macro.MAX_LINE
            .. " characters). Shorten it, or split it into two lines.")
    elseif reason == "full" then
        ns.Print("Your macro list is full. Free a slot (type /macro to manage them), then try again.")
    elseif reason == "unsupported" then
        ns.Print("This client doesn't support creating macros from the addon.")
    end
end

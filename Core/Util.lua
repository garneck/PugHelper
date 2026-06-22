--[[-------------------------------------------------------------------------
    PUG Helper - Core/Util.lua
---------------------------------------------------------------------------
    Pure, reusable helpers with ZERO WoW API dependency. Everything here is
    plain Lua, so it can be reasoned about (and in principle tested) in
    isolation. Anything that touches a WoW global belongs in Api.lua instead.
---------------------------------------------------------------------------]]

local _, ns = ...
local util = ns.util

-- Recursively fill missing keys in `dst` from `src` without overwriting values
-- the user already set. Used to merge PugHelperDB against DEFAULTS.
function util.applyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            util.applyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- Coerce a possibly-missing/garbage value into a table we can ipairs without
-- erroring. Malformed content is meant to degrade, not crash the addon.
function util.asList(t)
    return type(t) == "table" and t or {}
end

-- Deep copy a table (used to snapshot default content so the override merge
-- never mutates the registered defaults). Non-tables are returned as-is.
function util.deepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = util.deepCopy(v)
    end
    return copy
end

-- Trim leading/trailing whitespace. Accepts nil safely.
function util.trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Collapse embedded newlines/returns/tabs to a single space and trim the ends,
-- so a value stays one line. Used by the callout text/section-title mutators in
-- Content so a saved callout is always a single chat line regardless of caller.
function util.oneLine(s)
    s = tostring(s or ""):gsub("[\r\n\t]+", " ")
    return util.trim(s)
end

-- Derive a stable, lowercase id from a display name: alphanumeric runs kept,
-- everything else collapsed to single dashes, ends trimmed.
--   "Karazhan"               -> "karazhan"
--   "The Eye (Tempest Keep)" -> "the-eye-tempest-keep"
function util.slug(s)
    s = tostring(s or ""):lower()
    s = s:gsub("[^%w]+", "-")
    s = s:gsub("^%-+", ""):gsub("%-+$", "")
    return s
end

-- Break text into a list of lines no longer than maxChars, splitting on spaces
-- (a single over-long word is hard-cut). Shared by chat sending and any UI
-- preview so both wrap text identically. Empty input yields an empty list.
function util.wrap(text, maxChars)
    local lines = {}
    text = tostring(text or ""):gsub("^%s+", "")   -- a leading run would emit an empty first chunk
    while #text > maxChars do
        local slice = text:sub(1, maxChars)
        local sp = slice:match(".*()%s")           -- index of last whitespace
        local cut = (sp and sp - 1) or maxChars     -- no space to break on: hard-cut
        if not sp then
            -- # and string.sub are byte-based here, so a hard-cut can land inside a
            -- multibyte UTF-8 character. Back the cut off while the next byte is a
            -- continuation byte (0x80-0xBF) so a glyph is never split; stays <= maxChars.
            while cut > 1 do
                local b = text:byte(cut + 1)
                if not b or b < 128 or b >= 192 then break end
                cut = cut - 1
            end
        end
        table.insert(lines, text:sub(1, cut))
        text = text:sub(cut + 1):gsub("^%s+", "")
    end
    if #text > 0 then table.insert(lines, text) end
    return lines
end

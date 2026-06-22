--[[-------------------------------------------------------------------------
    PUG Helper - UI/Theme.lua
---------------------------------------------------------------------------
    The addon's design tokens: ONE place that owns every colour, size, and
    font the UI uses, so the look can't drift per-file. This is NOT a
    user-facing theming system (no skins to pick, nothing saved) - it is the
    internal palette every UI module reads from, the addon equivalent of CSS
    design tokens. Change a value here and the whole window restyles.

    Loads before UI/Helpers.lua (see PugHelper.toc) so the shared builders can
    read it. Pure data + tiny pure helpers; the only WoW-ish calls are
    string.format / math.floor inside hex(), which run at call time and are
    standard Lua 5.1 (present on this client).

    Usage:
      local r,g,b   = T.rgb(T.color.accent)        -- SetTextColor / AddLine / SetVertexColor
      local r,g,b,a = T.rgba(T.color.panelBg)      -- SetColorTexture / Background / AddBorder
      tex:SetColorTexture(T.wash(T.color.unset, 0.12))   -- a token at a custom alpha
      fs:SetText(T.colorize(T.color.title, "{MT}")) -- "|cAARRGGBB...|r" inline escape

    IMPORTANT for AddLine: GameTooltip:AddLine(text, r, g, b, wrap) reads a 4th
    arg as the wrap flag, so always use T.rgb (3 values) there, never T.rgba.
---------------------------------------------------------------------------]]

local _, ns = ...
local UI = ns.UI

local Theme = {}
UI.Theme = Theme

-- Colour tokens: { r, g, b [, a] }, 0-1. One entry per SEMANTIC role (what the
-- colour means), not per call site - that is what keeps the palette coherent.
Theme.color = {
    -- Surfaces / chrome
    panelBg     = { 0.05, 0.05, 0.07, 0.96 },  -- main window + every overlay/popup/dialog
    panelBorder = { 0.25, 0.25, 0.30, 1 },     -- the shared 2px frame around panels
    titleBg     = { 0.10, 0.10, 0.16, 1 },     -- title-bar strip behind a panel's title
    divider     = { 0.28, 0.28, 0.34, 1 },     -- thin internal separators
    inputBg     = { 0, 0, 0, 0.5 },            -- dark well behind edit boxes
    modalDim    = { 0, 0, 0, 0.45 },           -- dim wash over a modal-blocked area

    -- Text / accents (semantic - reuse by MEANING)
    title  = { 1, 0.82, 0 },     -- gold: window/section/panel titles and {TOKEN}s
    text   = { 1, 1, 1 },        -- normal body text
    muted  = { 0.8, 0.8, 0.8 },  -- secondary text: hints, tooltip bodies, notes
    faint  = { 0.5, 0.5, 0.5 },  -- placeholder / empty-state / "(not set)"
    accent = { 0.5, 0.7, 1.0 },  -- info blue: bullets, links, hovers, "+ Add section"
    unset  = { 1, 0.6, 0.1 },    -- amber: unset {TOKEN}, edit mode, downgraded channel
    ok     = { 0.45, 0.9, 0.45 },-- green (static): "+ Add line", "(customized)", AUTO-resolved
    flash  = { 0.3, 1.0, 0.3 },  -- green (transient): the vivid pulse on a successful send
    loud   = { 1, 0.38, 0.38 },  -- red: SAY/GUILD warning, error reasons
    stale  = { 1, 0.5, 0.5 },    -- soft red: assigned player not in group, destructive hint
}

-- Layout tokens (pixels). Only the genuinely CROSS-FILE sizes live here, so the
-- panels can't diverge from the window; window-internal metrics (row/header
-- heights, section gap) stay local to Window.lua where they're used.
Theme.size = {
    buttonH = 22,   -- shared button / input height (exposed as UI.BUTTON_H below)
    titleH  = 26,   -- title-bar strip height (UI.TitleBar)
    inset   = 2,    -- title-bar / inner inset from the panel border
}

-- Font objects, named by ROLE. All are stock Blizzard font objects (guaranteed
-- on this client); routing them through here lets a future change stay in one
-- place. (We deliberately do NOT call SetFont with a raw path.)
Theme.font = {
    title  = "GameFontNormalLarge",    -- panel titles
    header = "GameFontNormal",         -- section headers
    body   = "GameFontHighlightSmall", -- message lines, list buttons, captions
    hint   = "GameFontDisableSmall",   -- dimmed hints / placeholders
}

-- The shared button height other modules already read off ns.UI; sourced here
-- now so it has one definition instead of living in Window.lua.
UI.BUTTON_H = Theme.size.buttonH

-- r, g, b (three values) - for SetTextColor / SetVertexColor / GameTooltip:AddLine.
function Theme.rgb(c)
    return c[1], c[2], c[3]
end

-- r, g, b, a (four values; a defaults opaque) - for SetColorTexture / Background /
-- AddBorder, where the alpha matters.
function Theme.rgba(c)
    return c[1], c[2], c[3], c[4] or 1
end

-- A token's colour at a caller-chosen alpha - for translucent washes/highlights.
function Theme.wash(c, a)
    return c[1], c[2], c[3], a
end

-- A token as a WoW colour-escape lead "ffRRGGBB" (alpha forced opaque, as text
-- escapes ignore it). Built from the same token, so an inline {TOKEN} tint can
-- never drift from the matching texture/vertex colour again.
function Theme.hex(c)
    return string.format("ff%02x%02x%02x",
        math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

-- Wrap text in a token's colour escape: T.colorize(T.color.title, "{MT}").
function Theme.colorize(c, text)
    return "|c" .. Theme.hex(c) .. text .. "|r"
end

-- GameTooltip:AddLine with a token colour and optional wrap. ALWAYS use this for
-- a wrapped, coloured line instead of AddLine(text, T.rgb(c), true): splicing
-- T.rgb (3 returns) before a trailing wrap arg truncates it to one value (so g
-- becomes the wrap flag, b becomes nil, and the real wrap flag is lost).
function Theme.addLine(tooltip, text, c, wrap)
    tooltip:AddLine(text, c[1], c[2], c[3], wrap)
end

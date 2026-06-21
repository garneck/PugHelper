--[[-------------------------------------------------------------------------
    PUG Helper - UI/Helpers.lua
---------------------------------------------------------------------------
    Small shared UI construction helpers, to keep the panel/window code free of
    repeated CreateFrame / SetScript / texture boilerplate. Loads before the
    other UI files (see PugHelper.toc). Uses only API already relied on
    elsewhere (CreateFrame, GameTooltip, SetColorTexture).
---------------------------------------------------------------------------]]

local _, ns = ...
local UI = ns.UI

-- A standard UIPanelButtonTemplate button. Caller positions it (SetPoint) since
-- placement varies. `text`/`onClick` are optional.
function UI.Button(parent, width, height, text, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, height)
    if text then b:SetText(text) end
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- Wire a static right-anchored GameTooltip onto a frame. `lines` is a list of
-- { text, r, g, b, wrap } entries (r/g/b/wrap optional per WoW's AddLine).
function UI.Tooltip(frame, lines)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for _, l in ipairs(lines) do
            GameTooltip:AddLine(l[1], l[2], l[3], l[4], l[5])
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Fill a frame with a flat BACKGROUND-layer color texture (the dark panel fill
-- used by the window and overlays). Texture-based on purpose (no :SetBackdrop),
-- companion to AddBorder.
function UI.Background(frame, r, g, b, a)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(true)
    t:SetColorTexture(r, g, b, a)
    return t
end

-- Add a 2px texture border (top/bottom/left/right) around a frame. Texture-based
-- on purpose (no :SetBackdrop), matching the rest of the UI.
function UI.AddBorder(frame, r, g, b, a)
    local function edge()
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a)
        return t
    end
    local top = edge(); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
    local bot = edge(); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(2)
    local lft = edge(); lft:SetPoint("TOPLEFT"); lft:SetPoint("BOTTOMLEFT"); lft:SetWidth(2)
    local rgt = edge(); rgt:SetPoint("TOPRIGHT"); rgt:SetPoint("BOTTOMRIGHT"); rgt:SetWidth(2)
end

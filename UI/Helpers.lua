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

-- Wire mouse-wheel scrolling onto a UIPanelScrollFrameTemplate (the template
-- ships a draggable bar; this adds the wheel). `step` is the pixels-per-notch.
-- Uses only standard ScrollFrame methods. Shared by the window list, message
-- pane, and the Set Names role list.
function UI.EnableWheel(scrollFrame, step)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local pos = self:GetVerticalScroll() - delta * (step or 24)
        if pos < 0 then pos = 0 elseif pos > range then pos = range end
        self:SetVerticalScroll(pos)
    end)
end

-- A shared yes/no confirmation modal, built once and reused. Sits at
-- FULLSCREEN_DIALOG strata so it floats above the window and its overlays.
-- `onAccept` runs only if the user confirms; `acceptText` labels that button
-- (e.g. "Delete", "Reset"). Texture-based and template-light, like the rest of
-- the UI. Used for destructive actions (deleting callout lines/sections,
-- resetting roles) so an accidental click can't drop content.
local confirmDialog
function UI.Confirm(message, onAccept, acceptText)
    local d = confirmDialog
    if not d then
        d = CreateFrame("Frame", nil, UIParent)
        d:SetFrameStrata("FULLSCREEN_DIALOG")
        d:SetSize(380, 150)
        d:SetPoint("CENTER")
        d:EnableMouse(true)
        UI.Background(d, 0.06, 0.06, 0.09, 0.98)
        UI.AddBorder(d, 0.40, 0.40, 0.50, 1)

        local msg = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        msg:SetPoint("TOPLEFT", 18, -20)
        msg:SetPoint("TOPRIGHT", -18, -20)
        msg:SetJustifyH("LEFT")
        msg:SetWordWrap(true)
        d.msg = msg

        local accept = UI.Button(d, 130, UI.BUTTON_H, "Confirm", function()
            d:Hide()
            if d.onAccept then d.onAccept() end
        end)
        accept:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -6, 16)
        d.accept = accept

        local cancel = UI.Button(d, 130, UI.BUTTON_H, "Cancel", function() d:Hide() end)
        cancel:SetPoint("BOTTOMLEFT", d, "BOTTOM", 6, 16)

        d:Hide()
        confirmDialog = d
    end
    d.onAccept = onAccept
    d.msg:SetText(message or "Are you sure?")
    d.accept:SetText(acceptText or "Confirm")
    d:Show()
    d:Raise()
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

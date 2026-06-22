--[[-------------------------------------------------------------------------
    PUG Helper - UI/Minimap.lua
---------------------------------------------------------------------------
    A small launcher button on the minimap ring: click to toggle the window,
    drag to reposition it around the ring (the angle persists via Config).

    Pure Blizzard API only - CreateFrame, textures, GameTooltip, the Minimap
    global, GetCursorPosition, and math (no libraries, no XML, no SetBackdrop),
    per the WoW API rules in CLAUDE.md. The Minimap global is guarded since we
    never assume a global exists on this client.

    Built eagerly from Boot.lua (not lazily with the window) so it's visible at
    login for discoverability.
---------------------------------------------------------------------------]]

local _, ns = ...
local UI = ns.UI
local T  = UI.Theme   -- design tokens (colours / sizes / fonts)

local RADIUS = 80   -- distance of the button center from the minimap center
local button

-- math.atan2 was removed from WoW's Lua in 8.0; the Classic-era/Anniversary
-- client (post-8.0 engine) only has math.atan, which now takes the optional
-- second arg. Pick whichever exists so the drag math never calls a nil global.
local atan2 = math.atan2 or math.atan

-- Place the button on the ring at the saved angle (degrees).
local function positionButton()
    if not button then return end
    local a = math.rad(ns.Config.MinimapAngle())
    button:SetPoint("CENTER", Minimap, "CENTER", RADIUS * math.cos(a), RADIUS * math.sin(a))
end

-- While dragging, follow the cursor around the ring and save the new angle.
local function dragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    ns.Config.SetMinimapAngle(math.deg(atan2(cy - my, cx - mx)))
    positionButton()
end

function UI.BuildMinimapButton()
    if button then UI.UpdateMinimapButton(); return end
    if not Minimap then return end   -- never assume the global exists

    button = CreateFrame("Button", "PugHelperMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetSize(33, 33)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- crop the icon's built-in border
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)

    button:SetScript("OnClick", function() ns.UI.Toggle() end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", dragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("PUG Helper", T.rgb(T.color.text))
        GameTooltip:AddLine("Click to open / close.", T.rgb(T.color.muted))
        GameTooltip:AddLine("Drag to move around the minimap.", T.rgb(T.color.muted))
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    positionButton()
    UI.minimapButton = button
    UI.UpdateMinimapButton()
end

-- Show or hide the button per the saved setting (toggled via /pug minimap).
function UI.UpdateMinimapButton()
    if not button then return end
    if ns.Config.MinimapHidden() then button:Hide() else button:Show() end
end

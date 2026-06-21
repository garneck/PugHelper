--[[-------------------------------------------------------------------------
    PUG Helper - UI/NamesPanel.lua
---------------------------------------------------------------------------
    The "Set Names" overlay: one dropdown per role token, populated live from
    the current party/raid. Reads roles from ns.Content and reads/writes names
    through ns.Config (never PugHelperDB directly).
---------------------------------------------------------------------------]]

local _, ns = ...
local UI = ns.UI

function UI.BuildNamesPanel(parent)
    -- Anonymous frame; its dropdowns carry their own names for the template.
    local panel = CreateFrame("Frame", nil, parent)
    UI.namesPanel = panel
    panel:SetPoint("TOPLEFT", 8, -58)
    panel:SetPoint("BOTTOMRIGHT", -8, 8)
    -- Sit above the scroll content (a deeper frame level) so the panel fully
    -- covers the message rows instead of letting their text bleed through.
    panel:SetFrameLevel(parent:GetFrameLevel() + 100)
    panel:EnableMouse(true)

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.97)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Set Player / Role Names")

    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    help:SetText("These names fill the {TOKENS} in your messages. Pick a party/raid member from each dropdown.")
    help:SetTextColor(0.8, 0.8, 0.8)

    -- Fixed two-column grid. A lot more roles than the ~16 defaults would
    -- overflow vertically (no scroll here); widen or add a column if needed.
    panel.boxes = {}
    local roles = {}
    for _, role in ipairs(ns.Content.Roles()) do
        if type(role) == "table" and role.key then table.insert(roles, role) end
    end
    local perCol = math.ceil(#roles / 2)
    local colX = { 18, 320 }
    local startY = -56
    local stepY = 34

    for i, role in ipairs(roles) do
        local col = (i <= perCol) and 1 or 2
        local rowIndex = (col == 1) and (i - 1) or (i - perCol - 1)
        local x = colX[col]
        local yy = startY - rowIndex * stepY

        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", x, yy - 4)
        lbl:SetWidth(110)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(role.label or role.key)

        local dd = CreateFrame("Frame", "PugHelperNameDD" .. role.key, panel, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", x + 104, yy)
        dd.token = role.key
        UIDropDownMenu_SetWidth(dd, 110)
        UIDropDownMenu_Initialize(dd, function()
            for _, name in ipairs(ns.api.GroupRoster()) do
                local nm = name
                local info = UIDropDownMenu_CreateInfo()
                info.text    = nm
                info.checked = (ns.Config.GetName(dd.token) == nm)
                info.func    = function()
                    ns.Config.SetName(dd.token, nm)
                    UIDropDownMenu_SetText(dd, nm)
                end
                UIDropDownMenu_AddButton(info)
            end
            local clearInfo = UIDropDownMenu_CreateInfo()
            clearInfo.text         = "|cff999999(clear)|r"
            clearInfo.notCheckable = true
            clearInfo.func         = function()
                ns.Config.SetName(dd.token, "")
                UIDropDownMenu_SetText(dd, "")
            end
            UIDropDownMenu_AddButton(clearInfo)
        end)
        panel.boxes[role.key] = dd
    end

    local done = UI.Button(panel, 90, UI.BUTTON_H, "Done", function()
        panel:Hide()
        UI.Refresh()
    end)
    done:SetPoint("BOTTOMRIGHT", -14, 12)

    local clear = UI.Button(panel, 90, UI.BUTTON_H, "Clear All", function()
        for key, dd in pairs(panel.boxes) do
            ns.Config.SetName(key, "")
            UIDropDownMenu_SetText(dd, "")
        end
    end)
    clear:SetPoint("RIGHT", done, "LEFT", -8, 0)

    panel:Hide()
end

function UI.RefreshNamesPanel()
    local panel = UI.namesPanel
    if not panel then return end
    for key, dd in pairs(panel.boxes) do
        UIDropDownMenu_SetText(dd, ns.Config.GetName(key) or "")
    end
end

function UI.ToggleNames()
    local panel = UI.namesPanel
    if not panel then return end
    if panel:IsShown() then
        panel:Hide()
    else
        UI.RefreshNamesPanel()
        panel:Show()
    end
end

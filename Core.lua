--[[-------------------------------------------------------------------------
    PUG Helper - Core.lua
    Engine + UI. You normally don't need to edit this file; put your raids
    and messages in Data.lua instead.
---------------------------------------------------------------------------]]

local ADDON_NAME = ...

-- ===========================================================================
--  Saved variables / defaults
-- ===========================================================================
local DEFAULTS = {
    channel = "AUTO",          -- AUTO | RAID | RAID_WARNING | PARTY | SAY | GUILD
    names   = {},              -- token -> name
    point   = nil,             -- saved window position
    selectedRaid = 1,
}

local CHANNELS = { "AUTO", "RAID", "RAID_WARNING", "PARTY", "SAY", "GUILD" }

-- ===========================================================================
--  Small helpers
-- ===========================================================================
local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- Group detection that works on both modern Classic and very old API names.
local function InRaid()
    if type(IsInRaid) == "function" then return IsInRaid() end
    if type(GetNumRaidMembers) == "function" then return GetNumRaidMembers() > 0 end
    return false
end

local function InGroup()
    if type(IsInGroup) == "function" then return IsInGroup() end
    if type(GetNumPartyMembers) == "function" and GetNumPartyMembers() > 0 then return true end
    return InRaid()
end

-- Replace {TOKEN} with the configured name, or leave {TOKEN} visible if unset.
local function Substitute(text)
    return (text:gsub("{(%w+)}", function(key)
        local n = PugHelperDB and PugHelperDB.names and PugHelperDB.names[key]
        if n and n ~= "" then return n end
        return "{" .. key .. "}"
    end))
end

local function ResolveChannel()
    local ch = (PugHelperDB and PugHelperDB.channel) or "AUTO"
    if ch == "AUTO" then
        if InRaid() then return "RAID"
        elseif InGroup() then return "PARTY"
        else return "SAY" end
    end
    return ch
end

-- Send a line, splitting on spaces if it exceeds the chat length limit.
local function SendLine(text)
    text = Substitute(text)
    local channel = ResolveChannel()
    local LIMIT = 240
    while #text > LIMIT do
        local slice = text:sub(1, LIMIT)
        local sp = slice:match(".*()%s")          -- index of last whitespace
        local cut = (sp and sp - 1) or LIMIT
        SendChatMessage(text:sub(1, cut), channel)
        text = text:sub(cut + 1):gsub("^%s+", "")
    end
    if #text > 0 then
        SendChatMessage(text, channel)
    end
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66bbffPUG Helper|r: " .. tostring(msg))
end

-- Shorten a (substituted) line for display on a button.
local function Truncate(text, maxChars)
    text = Substitute(text)
    if #text > maxChars then
        return text:sub(1, maxChars - 1) .. "..."
    end
    return text
end

-- ===========================================================================
--  UI
-- ===========================================================================
local mainFrame
local namesPanel
local scrollContent
local raidButtons = {}
local rowPool, headerPool = {}, {}
local contentHeader            -- the line at the top of the right pane

local LEFT_W       = 158
local CONTENT_X    = 178
local ROW_H        = 22
local HEADER_H     = 20
local SECTION_GAP  = 8
local LABEL_CHARS  = 78

local function ChannelLabel()
    return "Channel: " .. ((PugHelperDB and PugHelperDB.channel) or "AUTO")
end

-- Acquire a pooled message-row button (parented to the scroll content).
local function AcquireRow()
    for _, b in ipairs(rowPool) do
        if not b.inUse then b.inUse = true; b:Show(); return b end
    end
    local b = CreateFrame("Button", nil, scrollContent)
    b:SetHeight(ROW_H)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(true)
    hl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.4)

    local bullet = b:CreateTexture(nil, "ARTWORK")
    bullet:SetTexture("Interface\\Buttons\\UI-RadioButton")
    bullet:SetTexCoord(0, 0.25, 0, 1)
    bullet:SetSize(12, 12)
    bullet:SetPoint("LEFT", 2, 0)
    bullet:SetVertexColor(0.5, 0.7, 1.0)

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", bullet, "RIGHT", 4, 0)
    fs:SetPoint("RIGHT", -4, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    b.label = fs

    b:SetScript("OnClick", function(self)
        if self.fullText then SendLine(self.fullText) end
    end)
    b:SetScript("OnEnter", function(self)
        if not self.fullText then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Click to send to " .. ResolveChannel(), 0.6, 0.8, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Substitute(self.fullText), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b.inUse = true
    table.insert(rowPool, b)
    return b
end

-- Acquire a pooled section-header fontstring.
local function AcquireHeader()
    for _, h in ipairs(headerPool) do
        if not h.inUse then h.inUse = true; h:Show(); return h end
    end
    local h = scrollContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetJustifyH("LEFT")
    h:SetTextColor(1, 0.82, 0)
    h.inUse = true
    table.insert(headerPool, h)
    return h
end

local function ReleasePool()
    for _, b in ipairs(rowPool) do b.inUse = false; b:Hide() end
    for _, h in ipairs(headerPool) do h.inUse = false; h:Hide() end
end

-- Rebuild the right-hand pane for the currently selected raid.
local function RefreshContent()
    if not scrollContent then return end
    ReleasePool()

    local raid = PugHelperRaids[PugHelperDB.selectedRaid]
    if not raid then return end

    contentHeader:SetText(raid.name .. (raid.note and ("  |cff999999" .. raid.note .. "|r") or ""))

    local width = scrollContent:GetWidth()
    local y = -4
    for _, section in ipairs(raid.sections) do
        local h = AcquireHeader()
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 2, y)
        h:SetText(section.title)
        y = y - HEADER_H

        for _, line in ipairs(section.lines) do
            local row = AcquireRow()
            row.fullText = line
            row.label:SetText(Truncate(line, LABEL_CHARS))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 6, y)
            row:SetWidth(width - 12)
            y = y - ROW_H
        end
        y = y - SECTION_GAP
    end

    scrollContent:SetHeight(math.max(-y + 4, 10))
    -- reset scroll to top
    local sf = scrollContent:GetParent()
    if sf and sf.SetVerticalScroll then sf:SetVerticalScroll(0) end
end

local function SelectRaid(index)
    PugHelperDB.selectedRaid = index
    for i, btn in ipairs(raidButtons) do
        if i == index then btn:LockHighlight() else btn:UnlockHighlight() end
    end
    RefreshContent()
end

-- ---------------------------------------------------------------------------
--  Names panel
-- ---------------------------------------------------------------------------
local function BuildNamesPanel()
    namesPanel = CreateFrame("Frame", "PugHelperNamesPanel", mainFrame)
    namesPanel:SetPoint("TOPLEFT", 8, -58)
    namesPanel:SetPoint("BOTTOMRIGHT", -8, 8)

    local bg = namesPanel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.97)

    local title = namesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Set Player / Role Names")

    local help = namesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    help:SetText("These names fill the {TOKENS} in your messages. Type a name and press Enter.")
    help:SetTextColor(0.8, 0.8, 0.8)

    namesPanel.boxes = {}
    local roles = PugHelperRoles
    local perCol = math.ceil(#roles / 2)
    local colX = { 18, 320 }
    local startY = -56
    local stepY = 30

    for i, role in ipairs(roles) do
        local col = (i <= perCol) and 1 or 2
        local rowIndex = (col == 1) and (i - 1) or (i - perCol - 1)
        local x = colX[col]
        local yy = startY - rowIndex * stepY

        local lbl = namesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", x, yy)
        lbl:SetWidth(120)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(role.label)

        local eb = CreateFrame("EditBox", nil, namesPanel, "InputBoxTemplate")
        eb:SetAutoFocus(false)
        eb:SetSize(120, 18)
        eb:SetPoint("TOPLEFT", x + 122, yy + 2)
        eb:SetMaxLetters(40)
        eb.token = role.key
        eb:SetScript("OnTextChanged", function(self)
            PugHelperDB.names[self.token] = self:GetText()
        end)
        eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        namesPanel.boxes[role.key] = eb
    end

    local done = CreateFrame("Button", nil, namesPanel, "UIPanelButtonTemplate")
    done:SetSize(90, 22)
    done:SetPoint("BOTTOMRIGHT", -14, 12)
    done:SetText("Done")
    done:SetScript("OnClick", function()
        namesPanel:Hide()
        RefreshContent()
    end)

    local clear = CreateFrame("Button", nil, namesPanel, "UIPanelButtonTemplate")
    clear:SetSize(90, 22)
    clear:SetPoint("RIGHT", done, "LEFT", -8, 0)
    clear:SetText("Clear All")
    clear:SetScript("OnClick", function()
        for key, eb in pairs(namesPanel.boxes) do
            PugHelperDB.names[key] = ""
            eb:SetText("")
        end
    end)

    namesPanel:Hide()
end

local function RefreshNamesPanel()
    if not namesPanel then return end
    for key, eb in pairs(namesPanel.boxes) do
        eb:SetText(PugHelperDB.names[key] or "")
    end
end

-- ---------------------------------------------------------------------------
--  Main window
-- ---------------------------------------------------------------------------
local function SavePoint()
    local point, _, relPoint, x, y = mainFrame:GetPoint()
    PugHelperDB.point = { point = point, relPoint = relPoint, x = x, y = y }
end

local function RestorePoint()
    mainFrame:ClearAllPoints()
    local p = PugHelperDB.point
    if p and p.point then
        mainFrame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    else
        mainFrame:SetPoint("CENTER")
    end
end

local function BuildUI()
    mainFrame = CreateFrame("Frame", "PugHelperFrame", UIParent)
    mainFrame:SetSize(660, 480)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mainFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePoint() end)
    tinsert(UISpecialFrames, "PugHelperFrame")   -- closes with Escape

    -- background + simple border (texture-based, no backdrop dependency)
    local bg = mainFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(0.04, 0.04, 0.06, 0.96)

    local function Edge(p1, p2, w, h)
        local t = mainFrame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.25, 0.25, 0.30, 1)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        return t
    end
    local top = Edge(); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
    local bot = Edge(); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(2)
    local lft = Edge(); lft:SetPoint("TOPLEFT"); lft:SetPoint("BOTTOMLEFT"); lft:SetWidth(2)
    local rgt = Edge(); rgt:SetPoint("TOPRIGHT"); rgt:SetPoint("BOTTOMRIGHT"); rgt:SetWidth(2)

    -- title bar
    local titleBg = mainFrame:CreateTexture(nil, "ARTWORK")
    titleBg:SetPoint("TOPLEFT", 2, -2)
    titleBg:SetPoint("TOPRIGHT", -2, -2)
    titleBg:SetHeight(26)
    titleBg:SetColorTexture(0.10, 0.10, 0.16, 1)

    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", titleBg, "LEFT", 10, 0)
    title:SetText("PUG Helper")

    local close = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() mainFrame:Hide() end)

    -- toolbar (channel + names)
    local channelBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    channelBtn:SetSize(150, 22)
    channelBtn:SetPoint("TOPLEFT", 10, -32)
    channelBtn:SetText(ChannelLabel())
    channelBtn:SetScript("OnClick", function(self)
        local cur = PugHelperDB.channel or "AUTO"
        local idx = 1
        for i, c in ipairs(CHANNELS) do if c == cur then idx = i break end end
        idx = (idx % #CHANNELS) + 1
        PugHelperDB.channel = CHANNELS[idx]
        self:SetText(ChannelLabel())
    end)
    channelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Where buttons send messages", 1, 1, 1)
        GameTooltip:AddLine("AUTO picks Raid > Party > Say. RAID_WARNING needs lead/assist.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    channelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local namesBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    namesBtn:SetSize(110, 22)
    namesBtn:SetPoint("LEFT", channelBtn, "RIGHT", 8, 0)
    namesBtn:SetText("Set Names")
    namesBtn:SetScript("OnClick", function()
        if namesPanel:IsShown() then
            namesPanel:Hide()
        else
            RefreshNamesPanel()
            namesPanel:Show()
        end
    end)

    -- left raid list
    local listHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listHeader:SetPoint("TOPLEFT", 12, -58)
    listHeader:SetText("RAIDS")

    local prev
    for i, raid in ipairs(PugHelperRaids) do
        local b = CreateFrame("Button", nil, mainFrame)
        b:SetSize(LEFT_W, ROW_H)
        if prev then
            b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
        else
            b:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 0, -4)
        end

        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(true)
        hl:SetColorTexture(0.3, 0.5, 0.9, 0.35)

        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 6, 0)
        fs:SetPoint("RIGHT", -4, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetText(raid.name)

        b:SetScript("OnClick", function() SelectRaid(i) end)
        raidButtons[i] = b
        prev = b
    end

    -- right content header
    contentHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    contentHeader:SetPoint("TOPLEFT", CONTENT_X, -58)
    contentHeader:SetPoint("RIGHT", -16, 0)
    contentHeader:SetJustifyH("LEFT")
    contentHeader:SetText("")

    local hint = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", contentHeader, "BOTTOMLEFT", 0, -2)
    hint:SetText("Click a line to send it. Hover to preview the full text.")

    -- scroll frame for messages
    local scroll = CreateFrame("ScrollFrame", "PugHelperScroll", mainFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", CONTENT_X, -92)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)

    scrollContent = CreateFrame("Frame", nil, scroll)
    scrollContent:SetWidth(440)
    scrollContent:SetHeight(10)
    scroll:SetScrollChild(scrollContent)

    -- keep content width in sync with the scroll frame
    scroll:SetScript("OnSizeChanged", function(self, w)
        if w and w > 1 then
            scrollContent:SetWidth(w)
            RefreshContent()
        end
    end)

    BuildNamesPanel()
    RestorePoint()
    mainFrame:Hide()
end

-- ===========================================================================
--  Public toggle
-- ===========================================================================
local function Toggle()
    if not mainFrame then BuildUI() end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        SelectRaid(PugHelperDB.selectedRaid or 1)
    end
end

-- ===========================================================================
--  Slash commands
-- ===========================================================================
local function HandleSlash(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "" or cmd == "show" or cmd == "toggle" then
        Toggle()
    elseif cmd == "name" then
        local token, value = rest:match("^(%S+)%s+(.+)$")
        if not token then
            token = rest:match("^(%S+)$")
            value = ""
        end
        if token then
            token = token:upper()
            PugHelperDB.names[token] = value or ""
            if value and value ~= "" then
                Print("Set {" .. token .. "} = " .. value)
            else
                Print("Cleared {" .. token .. "}")
            end
            RefreshNamesPanel()
            if mainFrame and mainFrame:IsShown() then RefreshContent() end
        else
            Print("Usage: /pug name TOKEN Yourname   (e.g. /pug name MT Bigtank)")
        end
    elseif cmd == "names" then
        Print("Current names:")
        for _, role in ipairs(PugHelperRoles) do
            local n = PugHelperDB.names[role.key]
            Print("  {" .. role.key .. "} (" .. role.label .. ") = " .. (n and n ~= "" and n or "|cff888888-not set-|r"))
        end
    elseif cmd == "channel" then
        local c = rest:upper()
        local ok = false
        for _, v in ipairs(CHANNELS) do if v == c then ok = true break end end
        if ok then
            PugHelperDB.channel = c
            Print("Channel set to " .. c)
        else
            Print("Channels: AUTO, RAID, RAID_WARNING, PARTY, SAY, GUILD")
        end
    elseif cmd == "reset" then
        PugHelperDB.point = nil
        if mainFrame then RestorePoint() end
        Print("Window position reset.")
    else
        Print("Commands:")
        Print("  /pug                 - open/close the window")
        Print("  /pug name MT Name    - set a role name")
        Print("  /pug names           - list role names")
        Print("  /pug channel RAID    - set output channel")
        Print("  /pug reset           - reset window position")
    end
end

SLASH_PUGHELPER1 = "/pug"
SLASH_PUGHELPER2 = "/pughelper"
SlashCmdList["PUGHELPER"] = HandleSlash

-- ===========================================================================
--  Init
-- ===========================================================================
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON_NAME then return end
    PugHelperDB = PugHelperDB or {}
    ApplyDefaults(PugHelperDB, DEFAULTS)
    if not PugHelperRaids[PugHelperDB.selectedRaid] then
        PugHelperDB.selectedRaid = 1
    end
    Print("loaded. Type /pug to open.")
    self:UnregisterEvent("ADDON_LOADED")
end)

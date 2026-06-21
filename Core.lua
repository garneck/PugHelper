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
    channel = "AUTO",          -- one of the CHANNELS below
    names   = {},              -- token -> name
    point   = nil,             -- saved window position
    selectedRaid = 1,
}

-- The output channels the user can pick, in cycle order, defined in ONE place.
-- `requires` is the group state the channel needs; ResolveChannel downgrades to a
-- valid channel when it isn't met (AUTO is resolved dynamically). The flat name
-- list and a name->requires lookup are derived below so nothing repeats the list.
local CHANNELS = {
    { name = "AUTO" },
    { name = "RAID",         requires = "raid"  },
    { name = "RAID_WARNING", requires = "raid"  },
    { name = "PARTY",        requires = "group" },
    { name = "SAY" },
    { name = "GUILD" },
}

local CHANNEL_NAMES, CHANNEL_REQUIRES = {}, {}
for _, c in ipairs(CHANNELS) do
    table.insert(CHANNEL_NAMES, c.name)
    CHANNEL_REQUIRES[c.name] = c.requires
end

-- Max bytes per SendChatMessage. The hard client limit is 255; we leave headroom
-- and split longer callout lines on word boundaries before sending (see SendLine).
local CHAT_LIMIT = 240

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

-- Coerce a possibly-missing/garbage value from Data.lua into a list we can ipairs
-- without erroring. Malformed content is meant to degrade, not crash the addon.
local function asList(t)
    return type(t) == "table" and t or {}
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

-- Number of raid members (whole raid, incl. self). Prefers the modern engine's
-- GetNumGroupMembers (the Anniversary client) and falls back to the old API.
local function RaidCount()
    if type(GetNumGroupMembers) == "function" then return GetNumGroupMembers() end
    if type(GetNumRaidMembers) == "function" then return GetNumRaidMembers() end
    return 0
end

-- Number of party members NOT counting the player.
local function PartyCount()
    if type(GetNumSubgroupMembers) == "function" then return GetNumSubgroupMembers() end
    if type(GetNumGroupMembers) == "function" then return math.max(GetNumGroupMembers() - 1, 0) end
    if type(GetNumPartyMembers) == "function" then return GetNumPartyMembers() end
    return 0
end

-- Current group member names (self + party/raid), sorted and de-duped.
local function GroupRoster()
    local names, seen = {}, {}
    local function add(n)
        if n and n ~= "" and not seen[n] then
            seen[n] = true
            table.insert(names, n)
        end
    end
    if InRaid() then
        for i = 1, RaidCount() do
            local raidName = (type(GetRaidRosterInfo) == "function" and GetRaidRosterInfo(i))
                or UnitName("raid" .. i)
            add(raidName)
        end
    else
        add(UnitName("player"))
        for i = 1, PartyCount() do
            add(UnitName("party" .. i))
        end
    end
    table.sort(names)
    return names
end

-- Replace {TOKEN} with the configured name, or leave {TOKEN} visible if unset.
local function Substitute(text)
    return (text:gsub("{(%w+)}", function(key)
        local n = PugHelperDB and PugHelperDB.names and PugHelperDB.names[key]
        if n and n ~= "" then return n end
        return "{" .. key .. "}"
    end))
end

-- Resolve the configured channel to one that is valid for the CURRENT group state.
-- AUTO picks Raid > Party > Say. A manual RAID/RAID_WARNING/PARTY override is quietly
-- downgraded when you're not in such a group, so clicking a line can never error out
-- with "You are not in a raid/party group".
local function ResolveChannel()
    local ch = (PugHelperDB and PugHelperDB.channel) or "AUTO"
    if ch == "AUTO" then
        if InRaid() then return "RAID"
        elseif InGroup() then return "PARTY"
        else return "SAY" end
    end
    local requires = CHANNEL_REQUIRES[ch]
    if requires == "raid" and not InRaid() then
        return InGroup() and "PARTY" or "SAY"
    end
    if requires == "group" and not InGroup() then
        return "SAY"
    end
    return ch
end

-- Break text into a list of lines no longer than maxChars, splitting on spaces
-- (a single over-long word is hard-cut). Shared by chat sending and the hover
-- preview so both wrap text the same way.
local function WrapText(text, maxChars)
    local lines = {}
    while #text > maxChars do
        local slice = text:sub(1, maxChars)
        local sp = slice:match(".*()%s")          -- index of last whitespace
        local cut = (sp and sp - 1) or maxChars   -- no space to break on: hard-cut
        table.insert(lines, text:sub(1, cut))
        text = text:sub(cut + 1):gsub("^%s+", "")
    end
    if #text > 0 then table.insert(lines, text) end
    return lines
end

-- Send a line, splitting on spaces if it exceeds the chat length limit.
local function SendLine(text)
    local channel = ResolveChannel()
    for _, chunk in ipairs(WrapText(Substitute(text), CHAT_LIMIT)) do
        SendChatMessage(chunk, channel)
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

-- One-time sanity check of the user-edited content in Data.lua. Prints friendly,
-- actionable warnings instead of letting a typo throw a cryptic Lua error later.
-- It only reports problems; the UI code below also degrades gracefully (asList).
local function ValidateData()
    if type(PugHelperRoles) ~= "table" then
        Print("|cffff5555Data error:|r PugHelperRoles (Data.lua) is missing or not a table.")
    else
        for i, role in ipairs(PugHelperRoles) do
            if type(role) ~= "table" or not role.key or not role.label then
                Print("|cffff5555Data warning:|r role #" .. i .. " needs both a key and a label - skipped.")
            elseif not tostring(role.key):match("^%w+$") then
                Print("|cffff5555Data warning:|r role key '" .. tostring(role.key)
                    .. "' must be letters/numbers only, or its {TOKEN} will never fill in.")
            end
        end
    end

    if type(PugHelperRaids) ~= "table" then
        Print("|cffff5555Data error:|r PugHelperRaids (Data.lua) is missing or not a table.")
        return
    end
    for i, raid in ipairs(PugHelperRaids) do
        local label = (type(raid) == "table" and raid.name) or ("#" .. i)
        if type(raid) ~= "table" then
            Print("|cffff5555Data warning:|r raid #" .. i .. " is not a table - skipped.")
        elseif type(raid.sections) ~= "table" then
            Print("|cffff5555Data warning:|r raid '" .. tostring(label) .. "' has no sections.")
        else
            for s, section in ipairs(raid.sections) do
                if type(section) ~= "table" or type(section.lines) ~= "table" then
                    Print("|cffff5555Data warning:|r raid '" .. tostring(label)
                        .. "', section #" .. s .. " has no lines.")
                end
            end
        end
    end
end

-- Drop saved names whose token can no longer be filled in - i.e. it is neither a
-- current role key nor referenced by any callout line. Keeps PugHelperDB.names
-- from accumulating leftovers as Data.lua's roles/lines change, without touching
-- custom tokens that are still in use somewhere. Matching is case-insensitive.
local function PruneNames()
    if type(PugHelperDB) ~= "table" or type(PugHelperDB.names) ~= "table" then return end
    local live = {}
    for _, role in ipairs(asList(PugHelperRoles)) do
        if type(role) == "table" and role.key then live[tostring(role.key):upper()] = true end
    end
    for _, raid in ipairs(asList(PugHelperRaids)) do
        for _, section in ipairs(asList(type(raid) == "table" and raid.sections)) do
            for _, line in ipairs(asList(type(section) == "table" and section.lines)) do
                if type(line) == "string" then
                    for token in line:gmatch("{(%w+)}") do live[token:upper()] = true end
                end
            end
        end
    end
    for key in pairs(PugHelperDB.names) do
        if type(key) ~= "string" or not live[key:upper()] then
            PugHelperDB.names[key] = nil
        end
    end
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
local channelBtn               -- toolbar channel button (label kept in sync, see below)

local FRAME_W      = 660       -- main window size
local FRAME_H      = 480
local LEFT_W       = 158       -- raid-list column width
local CONTENT_X    = 178       -- left edge of the right-hand message pane
local ROW_H        = 22        -- message row height
local HEADER_H     = 20        -- section header height
local SECTION_GAP  = 8         -- gap between sections
local LABEL_CHARS  = 78        -- chars before a row label is truncated
local PREVIEW_CHARS = 60       -- wrap width (chars) for the hover preview tooltip
local BUTTON_H     = 22        -- toolbar / panel button height
local TITLE_H      = 26        -- title bar height

local function ChannelLabel()
    return "Channel: " .. ((PugHelperDB and PugHelperDB.channel) or "AUTO")
end

-- Keep the toolbar's channel button label in sync with PugHelperDB.channel,
-- whichever input path changed it (the button's own cycle or `/pug channel`).
local function UpdateChannelButton()
    if channelBtn then channelBtn:SetText(ChannelLabel()) end
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
        -- Show the whole line, wrapped to a fixed readable width across multiple
        -- tooltip lines, so long callouts are never cut off at the screen edge.
        for _, line in ipairs(WrapText(Substitute(self.fullText), PREVIEW_CHARS)) do
            GameTooltip:AddLine(line, 1, 1, 1)
        end
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

    local raid = asList(PugHelperRaids)[PugHelperDB.selectedRaid]
    if type(raid) ~= "table" then return end

    contentHeader:SetText((raid.name or "(unnamed)") .. (raid.note and ("  |cff999999" .. raid.note .. "|r") or ""))

    local width = scrollContent:GetWidth()
    local y = -4
    for _, section in ipairs(asList(raid.sections)) do
        local h = AcquireHeader()
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 2, y)
        h:SetText(section.title or "")
        y = y - HEADER_H

        for _, line in ipairs(asList(section.lines)) do
            if type(line) == "string" then
                local row = AcquireRow()
                row.fullText = line
                row.label:SetText(Truncate(line, LABEL_CHARS))
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 6, y)
                row:SetWidth(width - 12)
                y = y - ROW_H
            end
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
    -- Anonymous: nothing references this panel by global name (its dropdowns carry
    -- their own names for the template), so we avoid polluting the global namespace.
    namesPanel = CreateFrame("Frame", nil, mainFrame)
    namesPanel:SetPoint("TOPLEFT", 8, -58)
    namesPanel:SetPoint("BOTTOMRIGHT", -8, 8)
    -- Sit above the scroll content (which lives at a deeper frame level), so the
    -- panel's background fully covers the message rows instead of letting their
    -- text bleed through. Draw layers only order within a single frame level.
    namesPanel:SetFrameLevel(mainFrame:GetFrameLevel() + 100)
    namesPanel:EnableMouse(true)

    local bg = namesPanel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.97)

    local title = namesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Set Player / Role Names")

    local help = namesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    help:SetText("These names fill the {TOKENS} in your messages. Pick a party/raid member from each dropdown.")
    help:SetTextColor(0.8, 0.8, 0.8)

    -- Fixed two-column grid sized to the ~16 default roles. A lot more roles than
    -- that would overflow the panel vertically (there's no scroll here) — widen the
    -- panel or add a third column if PugHelperRoles grows substantially.
    namesPanel.boxes = {}
    -- Only roles with a usable key get a box; malformed roles are skipped here
    -- (and flagged at load by ValidateData) instead of erroring on concatenation.
    local roles = {}
    for _, role in ipairs(asList(PugHelperRoles)) do
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

        local lbl = namesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", x, yy - 4)
        lbl:SetWidth(110)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(role.label or role.key)

        -- Dropdown populated live from the current party/raid each time it opens.
        local dd = CreateFrame("Frame", "PugHelperNameDD" .. role.key, namesPanel, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", x + 104, yy)
        dd.token = role.key
        UIDropDownMenu_SetWidth(dd, 110)
        UIDropDownMenu_Initialize(dd, function()
            for _, name in ipairs(GroupRoster()) do
                local nm = name
                local info = UIDropDownMenu_CreateInfo()
                info.text    = nm
                info.checked = (PugHelperDB.names[dd.token] == nm)
                info.func    = function()
                    PugHelperDB.names[dd.token] = nm
                    UIDropDownMenu_SetText(dd, nm)
                end
                UIDropDownMenu_AddButton(info)
            end
            local info = UIDropDownMenu_CreateInfo()
            info.text         = "|cff999999(clear)|r"
            info.notCheckable = true
            info.func         = function()
                PugHelperDB.names[dd.token] = ""
                UIDropDownMenu_SetText(dd, "")
            end
            UIDropDownMenu_AddButton(info)
        end)
        namesPanel.boxes[role.key] = dd
    end

    local done = CreateFrame("Button", nil, namesPanel, "UIPanelButtonTemplate")
    done:SetSize(90, BUTTON_H)
    done:SetPoint("BOTTOMRIGHT", -14, 12)
    done:SetText("Done")
    done:SetScript("OnClick", function()
        namesPanel:Hide()
        RefreshContent()
    end)

    local clear = CreateFrame("Button", nil, namesPanel, "UIPanelButtonTemplate")
    clear:SetSize(90, BUTTON_H)
    clear:SetPoint("RIGHT", done, "LEFT", -8, 0)
    clear:SetText("Clear All")
    clear:SetScript("OnClick", function()
        for key, dd in pairs(namesPanel.boxes) do
            PugHelperDB.names[key] = ""
            UIDropDownMenu_SetText(dd, "")
        end
    end)

    namesPanel:Hide()
end

local function RefreshNamesPanel()
    if not namesPanel then return end
    for key, dd in pairs(namesPanel.boxes) do
        UIDropDownMenu_SetText(dd, PugHelperDB.names[key] or "")
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
    mainFrame:SetSize(FRAME_W, FRAME_H)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mainFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePoint() end)
    table.insert(UISpecialFrames, "PugHelperFrame")   -- closes with Escape

    -- background + simple border (texture-based, no backdrop dependency)
    local bg = mainFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(0.04, 0.04, 0.06, 0.96)

    -- A 2px border edge; callers anchor it and set its own width/height.
    local function Edge()
        local t = mainFrame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.25, 0.25, 0.30, 1)
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
    titleBg:SetHeight(TITLE_H)
    titleBg:SetColorTexture(0.10, 0.10, 0.16, 1)

    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", titleBg, "LEFT", 10, 0)
    title:SetText("PUG Helper")

    local close = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() mainFrame:Hide() end)

    -- toolbar (channel + names)
    channelBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    channelBtn:SetSize(150, BUTTON_H)
    channelBtn:SetPoint("TOPLEFT", 10, -32)
    channelBtn:SetText(ChannelLabel())
    channelBtn:SetScript("OnClick", function()
        local cur = PugHelperDB.channel or "AUTO"
        local idx = 1
        for i, name in ipairs(CHANNEL_NAMES) do if name == cur then idx = i break end end
        idx = (idx % #CHANNEL_NAMES) + 1
        PugHelperDB.channel = CHANNEL_NAMES[idx]
        UpdateChannelButton()
    end)
    channelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Where buttons send messages", 1, 1, 1)
        GameTooltip:AddLine("AUTO picks Raid > Party > Say. RAID_WARNING needs lead/assist.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    channelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local namesBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    namesBtn:SetSize(110, BUTTON_H)
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
    for i, raid in ipairs(asList(PugHelperRaids)) do
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
        fs:SetText((type(raid) == "table" and raid.name) or "(unnamed)")

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
        if not token then
            Print("Usage: /pug name TOKEN Yourname   (e.g. /pug name MT Bigtank)")
        elseif not token:match("^%w+$") then
            -- Substitution only matches {%w+}, so a non-alphanumeric token could be
            -- stored but never filled in. Reject it up front instead.
            Print("Token must be letters/numbers only (no spaces, dashes, or underscores): " .. token)
        else
            token = token:upper()
            PugHelperDB.names[token] = value or ""
            if value and value ~= "" then
                Print("Set {" .. token .. "} = " .. value)
            else
                Print("Cleared {" .. token .. "}")
            end
            RefreshNamesPanel()
            if mainFrame and mainFrame:IsShown() then RefreshContent() end
        end
    elseif cmd == "names" then
        Print("Current names:")
        for _, role in ipairs(asList(PugHelperRoles)) do
            if type(role) == "table" and role.key then
                local n = PugHelperDB.names[role.key]
                Print("  {" .. role.key .. "} (" .. (role.label or "?") .. ") = " .. (n and n ~= "" and n or "|cff888888-not set-|r"))
            end
        end
    elseif cmd == "channel" then
        local c = rest:upper()
        local ok = false
        for _, name in ipairs(CHANNEL_NAMES) do if name == c then ok = true break end end
        if ok then
            PugHelperDB.channel = c
            UpdateChannelButton()
            Print("Channel set to " .. c)
        else
            Print("Channels: " .. table.concat(CHANNEL_NAMES, ", "))
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
    if type(PugHelperRaids) ~= "table" or not PugHelperRaids[PugHelperDB.selectedRaid] then
        PugHelperDB.selectedRaid = 1
    end
    ValidateData()
    PruneNames()
    Print("loaded. Type /pug to open.")
    self:UnregisterEvent("ADDON_LOADED")
end)

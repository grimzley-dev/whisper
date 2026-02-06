local addonName, whisper = ...
local Log = {}
whisper:RegisterModule("Log", Log)

-- =========================================================================
-- CONFIRMATION POPUP
-- =========================================================================
StaticPopupDialogs["WHISPER_LOG_CLEAR_CONFIRM"] = {
    text = "Are you sure you want to clear the Mail Log?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        whisperDB.log.mail = {}
        Log:RefreshMailLog()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- =========================================================================
-- CONFIG & CONSTANTS
-- =========================================================================
local tinsert = table.insert
local tconcat = table.concat
local tremove = table.remove
local format = string.format
local date = date
local time = time
local lower = string.lower
local floor = math.floor
local abs = math.abs
local unpack = unpack

local PLAYER_NAME = UnitName("player")

-- Visual Constants
local STANDARD_FONT = "Fonts\\FRIZQT__.TTF"
local FONT_SIZE_GOLD = 13
local FONT_SIZE_NAME = 13
local FONT_SIZE_ICON = 24
local FONT_SIZE_SUBJ = 11
local FONT_SIZE_DETAILS = 10
local FONT_SIZE_VALUES  = 12

local ROW_HEIGHT_COLLAPSED = 30
local ROW_HEIGHT_HEADER = 30
local LINE_HEIGHT = 18
local PADDING = 8

-- Colors & Assets
local C = {
    RED      = {1, 0.2, 0.2},
    GREEN    = {0, 1, 0.2},
    INCOMING = {0.4, 0.8, 0.4},
    OUTGOING = {0.8, 0.4, 0.4},

    HEX_GOLD   = "|cffffd700",
    HEX_SILVER = "|cffc7c7cf",
    HEX_COPPER = "|cffeda55f",

    TEXT_PRIMARY   = {1, 1, 1},
    TEXT_SECONDARY = {0.7, 0.7, 0.7},
    TEXT_TERTIARY  = {0.5, 0.5, 0.5},

    BG_NORMAL      = {1, 1, 1, 0.0},
    BG_ALTERNATE   = {0, 0, 0, 0.3},
    BG_HOVER       = {1, 1, 1, 0.05},
    BG_EXPANDED    = {0, 0, 0, 0.4},

    TEX_GOLD   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t",
    TEX_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t",
    TEX_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t",

    SYMBOL_IN   = "»",
    SYMBOL_OUT  = "«",
    SYMBOL_FLOW = "•"
}

-- State
local mailLogFrame
local logoButton
local currentMailFilter = ""
local currentTypeFilter = "ALL"
local showAllCharacters = false
local filteredMailList = nil
local displayList = {}
local mailRowPool = {}

-- Pending State for Outgoing Mail
Log.pendingMail = nil
Log.moneyBefore = 0

-- =========================================================================
-- ANIMATION HELPERS
-- =========================================================================
local function FadeIn(frame, duration)
    frame:SetAlpha(0)
    frame:Show()
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        local progress = elapsed / duration
        if progress >= 1 then
            self:SetAlpha(1)
            self:SetScript("OnUpdate", nil)
        else
            self:SetAlpha(progress * (2 - progress))
        end
    end)
end

local function FadeOut(frame, duration)
    local startAlpha = frame:GetAlpha()
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        local progress = elapsed / duration
        if progress >= 1 then
            self:SetAlpha(0)
            self:Hide()
            self:SetScript("OnUpdate", nil)
        else
            self:SetAlpha(startAlpha * (1 - progress * progress))
        end
    end)
end

-- =========================================================================
-- HELPER FUNCTIONS
-- =========================================================================
local function Adler32(str)
    local a, b = 1, 0
    local len = #str
    for i = 1, len do
        a = (a + string.byte(str, i)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%08x", (b * 65536) + a)
end

local function GenerateChecksum(data)
    local src = data.target or "Unknown"
    local money = tostring(data.money or 0)
    local subj = data.subject or ""
    local type = data.type or ""
    local ts = string.sub(data.timestamp or "", 1, 16)
    return Adler32(src .. money .. subj .. type .. ts)
end

local function FormatLargeNumber(amount)
    local formatted = tostring(amount)
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if (k==0) then break end
    end
    return formatted
end

local function FormatCurrencyStyled(amount)
    if not amount then return "0" end
    local isNegative = amount < 0
    amount = abs(amount)
    local gold = floor(amount / 10000)
    local silver = floor((amount % 10000) / 100)
    local copper = floor(amount % 100)

    local parts = {}
    if isNegative then tinsert(parts, "-") end

    local hasGold = gold > 0
    local hasSilver = silver > 0
    local hasCopper = copper > 0

    if hasGold then
        tinsert(parts, C.HEX_GOLD .. FormatLargeNumber(gold) .. "|r" .. C.TEX_GOLD)
    end
    if hasSilver then
        tinsert(parts, C.HEX_SILVER .. silver .. "|r" .. C.TEX_SILVER)
    end
    if hasCopper or (not hasGold and not hasSilver) then
        tinsert(parts, C.HEX_COPPER .. copper .. "|r" .. C.TEX_COPPER)
    end

    return tconcat(parts, " ")
end

local function GetServerTimestamp() return GetServerTime() end

local function GetFullTimestampStr(ts)
    if ts then return ts end
    return date("%Y-%m-%d %H:%M:%S", GetServerTime())
end

local function EstimateSentDate(daysLeft)
    if not daysLeft then return GetFullTimestampStr() end
    local now = GetServerTime()
    local secondsElapsed = (31 - daysLeft) * 24 * 60 * 60
    return date("%Y-%m-%d %H:%M:%S", now - secondsElapsed)
end

local function ParseDate(ts)
    if not ts then return nil end
    local y, m, d = string.match(ts, "(%d%d%d%d)-(%d%d)-(%d%d)")
    if y and m and d then return y, m, d end
    return nil
end

local function GetDateKey(ts)
    if not ts then return "Unknown" end
    local y, m, d = ParseDate(ts)
    if y then return y.."-"..m.."-"..d end
    return "Unknown"
end

local function FormatDateHeader(ts)
    local y, m, d = ParseDate(ts)
    if y and m and d then
        local t = time({year=y, month=m, day=d})
        return date("%b %d", t)
    end
    return "Recent"
end

local function TruncateText(fontString, text, width)
    fontString:SetText(text)
    if fontString:GetStringWidth() > width then
        local len = string.len(text)
        local ratio = width / fontString:GetStringWidth()
        local newLen = floor(len * ratio) - 3
        if newLen > 0 then fontString:SetText(string.sub(text, 1, newLen) .. "...") end
    end
end

local function SanitizeData(item)
    if not item.owner then
        item.owner = UnitName("player")
    end

    if not item.money or item.money == 0 then
        if item.gold and item.gold > 0 then item.money = item.gold
        elseif item.amount and item.amount > 0 then item.money = item.amount end
    end

    if (not item.money or item.money == 0) and item.subject then
        local s = item.subject:gsub("%D", "")
        local val = tonumber(s)
        if val and val > 0 then
            item.money = val * 10000
        end
    end
end

local function FilterData(data, search, typeFilter, showAll)
    search = lower(search)
    local myName = UnitName("player")
    local res = {}

    for i, item in ipairs(data) do
        -- PERMANENT RULE: Ignore all zero-gold mail
        if (not item.money or item.money == 0) then
            -- Skip entirely
        else
            local isMine = (item.owner == myName)
            if showAll or isMine then
                local matchesSearch = true
                if search ~= "" then
                    matchesSearch = false
                    local moneyStr = tostring(item.money or 0)
                    if (item.target and string.find(lower(item.target), search, 1, true)) or
                       (item.subject and string.find(lower(item.subject), search, 1, true)) or
                       (string.find(moneyStr, search, 1, true)) then
                        matchesSearch = true
                    end
                end

                local matchesType = true
                if typeFilter == "IN" and item.type ~= "Received" then matchesType = false end
                if typeFilter == "OUT" and item.type ~= "Sent" then matchesType = false end

                if matchesSearch and matchesType then tinsert(res, item) end
            end
        end
    end

    table.sort(res, function(a, b)
        local keyA = GetDateKey(a.timestamp)
        local keyB = GetDateKey(b.timestamp)
        if keyA == "Unknown" and keyB ~= "Unknown" then return false end
        if keyA ~= "Unknown" and keyB == "Unknown" then return true end
        return (a.timestamp or "") > (b.timestamp or "")
    end)
    return res
end

-- =========================================================================
-- INITIALIZATION & HOOKS
-- =========================================================================
function Log:Init()
    whisperDB.log = whisperDB.log or { mail = {}, guild = {} }

    if whisperDB.log.mail then
        for _, entry in ipairs(whisperDB.log.mail) do
            SanitizeData(entry)
        end
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("GUILDBANKFRAME_OPENED")
    -- Listen for money changes to verify sent
    f:RegisterEvent("PLAYER_MONEY")
    f:RegisterEvent("MAIL_FAILED")
    f:RegisterEvent("MAIL_SHOW")
    f:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")

    f:SetScript("OnEvent", function(_, event, ...)
        if event == "GUILDBANKFRAME_OPENED" then
            Log:CreateGuildBankButton()
        elseif event == "PLAYER_MONEY" then
            Log:CheckMoneyVerify()
        elseif event == "MAIL_FAILED" then
            Log:ClearPendingMail()
        elseif event == "MAIL_SHOW" then
            Log:CreateButton()
        elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            local interactionType = ...
            if interactionType == Enum.PlayerInteractionType.MailInfo then
                if mailLogFrame then mailLogFrame:Hide() end
                if whisper.modules.Mail and whisper.modules.Mail.ResetPanel then
                    whisper.modules.Mail:ResetPanel()
                end
            end
        end
    end)
    self:HookMailFunctions()
end

function Log:CreateButton()
    if logoButton then logoButton:Show() return end

    logoButton = CreateFrame("Button", nil, MailFrame)
    logoButton:SetSize(40, 40)
    logoButton:SetPoint("BOTTOM", MailFrame, "BOTTOM", 4, 34)
    logoButton:SetFrameStrata("MEDIUM")
    logoButton:SetFrameLevel(2)

    local tex = logoButton:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface/AddOns/whisper/Media/whisperLogo")
    tex:SetAllPoints()
    tex:SetAlpha(0.7)
    logoButton.tex = tex

    logoButton:SetScript("OnEnter", function(self) self.tex:SetVertexColor(0.8, 0.8, 0.8) end)
    logoButton:SetScript("OnLeave", function(self) self.tex:SetVertexColor(1, 1, 1) end)
    logoButton:SetScript("OnMouseDown", function(self) self.tex:SetVertexColor(0.6, 0.6, 0.6) end)
    logoButton:SetScript("OnMouseUp", function(self) self.tex:SetVertexColor(0.8, 0.8, 0.8) end)

    -- FIXED: Toggle Logic with Animations
    logoButton:SetScript("OnClick", function()
        if mailLogFrame and mailLogFrame:IsShown() then
            FadeOut(mailLogFrame, 0.1) -- Hiding triggers OnHide which resets Mail module too
        else
            Log:ToggleMailLog(MailFrame)
        end
    end)
end

function Log:HookMailFunctions()
    hooksecurefunc("SendMail", function(target, subject, body)
        local money = GetSendMailMoney()
        local ts = GetFullTimestampStr()
        local actualBody = body
        if not actualBody or actualBody == "" then
            if SendMailBodyEditBox then actualBody = SendMailBodyEditBox:GetText() end
        end
        local fromAddon = false
        if whisper.modules.Mail and whisper.modules.Mail._sending then fromAddon = true end

        Log.pendingMail = {
            type = "Sent", target = target, owner = PLAYER_NAME,
            subject = subject or "No Subject", body = actualBody or "",
            money = money, timestamp = ts, dateSent = ts, dateOpened = ts,
            expanded = false, fromAddon = fromAddon
        }
        -- SNAPSHOT: Capture exact money before send
        Log.moneyBefore = GetMoney()
    end)

    hooksecurefunc("TakeInboxMoney", function(index) Log:CaptureReceivedMail(index) end)
    hooksecurefunc("AutoLootMailItem", function(index) Log:CaptureReceivedMail(index) end)

    if OpenMailFrame then
        OpenMailFrame:HookScript("OnShow", function()
            local index = InboxFrame.openMailID
            if index then Log:CaptureReceivedMail(index) end
        end)
    end
end

-- NEW: Called on PLAYER_MONEY
function Log:CheckMoneyVerify()
    if not Log.pendingMail then return end

    local currentMoney = GetMoney()
    local spent = Log.moneyBefore - currentMoney
    local expected = Log.pendingMail.money + 30 -- Amount + 30c postage

    -- Exact match required
    if spent == expected then
        Log:CommitLog()
    end
end

function Log:CommitLog()
    local entry = Log.pendingMail

    -- NEW: Ignore any outgoing mail with 0 gold attached
    if not entry.money or entry.money == 0 then
        Log.pendingMail = nil
        return
    end

    -- Duplicate safety check
    local isDuplicate = false
    if whisperDB.log.mail and #whisperDB.log.mail > 0 then
        local last = whisperDB.log.mail[1]
        if last.target == entry.target and last.money == entry.money and
           last.subject == entry.subject and last.timestamp == entry.timestamp then
            isDuplicate = true
        end
    end

    if not isDuplicate then
        SanitizeData(entry)
        tinsert(whisperDB.log.mail, 1, entry)
        Log:RefreshMailLog()
    end

    Log.pendingMail = nil
end

function Log:ClearPendingMail()
    Log.pendingMail = nil
end

function Log:CaptureReceivedMail(index)
    local _, _, sender, subject, money, _, daysLeft = GetInboxHeaderInfo(index)
    if not sender then return end

    -- NEW: Immediately return if no gold is attached
    if not money or money == 0 then return end

    local now = GetFullTimestampStr()
    local sent = EstimateSentDate(daysLeft)
    local bodyText = GetInboxText(index) or ""

    local entry = {
        type = "Received", target = sender, owner = PLAYER_NAME,
        subject = subject or "No Subject", body = bodyText,
        money = money or 0, timestamp = now, dateOpened = now, dateSent = sent, expanded = false
    }

    entry.id = GenerateChecksum(entry)
    SanitizeData(entry)

    local isDuplicate = false
    for _, v in ipairs(whisperDB.log.mail) do
        if v.id == entry.id then isDuplicate = true break end
    end

    if not isDuplicate then
        tinsert(whisperDB.log.mail, 1, entry)
        Log:RefreshMailLog()
    end
end

function Log:ProcessGuildBankLog() end
function Log:CreateGuildBankButton() end

-- =========================================================================
-- UI COMPONENTS
-- =========================================================================
local function CreateFilterPill(parent, text, value, callback)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(20)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetFont(STANDARD_FONT, 11, "OUTLINE")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    btn.fs = fs
    btn:SetWidth(fs:GetStringWidth() + 16)
    local line = btn:CreateTexture(nil, "ARTWORK")
    line:SetHeight(2)
    line:SetPoint("BOTTOMLEFT", 4, 0)
    line:SetPoint("BOTTOMRIGHT", -4, 0)
    line:SetColorTexture(1, 1, 1, 1)
    line:Hide()
    btn.line = line
    btn:SetScript("OnClick", function() callback(value) end)
    btn.UpdateState = function(self, selectedValue)
        if value == selectedValue then fs:SetTextColor(1, 1, 1) line:Show()
        else fs:SetTextColor(0.5, 0.5, 0.5) line:Hide() end
    end
    return btn
end

local function CreateSearchBox(parent, callback)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(200, 24)
    f:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0, 0, 0, 0.2)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    local eb = CreateFrame("EditBox", nil, f)
    eb:SetPoint("LEFT", 8, 0)
    eb:SetPoint("RIGHT", -8, 0)
    eb:SetHeight(20)
    eb:SetFont(STANDARD_FONT, 11, "OUTLINE")
    eb:SetAutoFocus(false)
    eb:SetTextColor(unpack(C.TEXT_PRIMARY))
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local searchTimer
    eb:SetScript("OnTextChanged", function(self)
        if searchTimer then searchTimer:Cancel() end
        local text = self:GetText()
        searchTimer = C_Timer.NewTimer(0.3, function() callback(text) end)
    end)

    local placeholder = eb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    placeholder:SetPoint("LEFT", 0, 0)
    placeholder:SetFont(STANDARD_FONT, 11, "OUTLINE")
    placeholder:SetTextColor(0.4, 0.4, 0.4)
    placeholder:SetText("Search character, amount")
    eb:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
    eb:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then placeholder:Show() end end)
    return f
end

local function CreateBasePanel(name, titleText, parent)
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(8/255, 8/255, 8/255, 0.8)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    local logo = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    logo:SetSize(256, 256)
    logo:SetPoint("BOTTOMRIGHT", 0, 0)
    logo:SetTexture("Interface/AddOns/whisper/Media/whisperLogo")
    logo:SetAlpha(0.5)
    local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 20, -20)
    header:SetText(titleText)
    header:SetFont(STANDARD_FONT, 20, "OUTLINE")
    header:SetTextColor(unpack(C.TEXT_PRIMARY))

    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -5, -5)
    local tex = close:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    tex:SetSize(22, 22)
    tex:SetPoint("CENTER")
    close:SetScript("OnClick", function() FadeOut(f, 0.1) end) -- Animated close
    close:SetScript("OnEnter", function() tex:SetVertexColor(0.5,0.5,0.5) end)
    close:SetScript("OnLeave", function() tex:SetVertexColor(1,1,1) end)

    return f
end

local function CreateDynamicRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT_COLLAPSED)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(C.BG_NORMAL))
    row.bg = bg

    local accent = row:CreateTexture(nil, "OVERLAY")
    accent:SetSize(2, ROW_HEIGHT_COLLAPSED)
    accent:SetPoint("LEFT", 0, 0)
    accent:SetColorTexture(1, 1, 1, 0.5)
    accent:Hide()
    row.accent = accent

    local Y_OFFSET = -8
    local ICON_Y = -1

    local function CreateCol(align, w, size, color)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetFont(STANDARD_FONT, size, "OUTLINE")
        fs:SetJustifyH(align)
        fs:SetWidth(w)
        fs:SetTextColor(unpack(color))
        return fs
    end

    row.colDir = CreateCol("CENTER", 30, FONT_SIZE_ICON, C.TEXT_PRIMARY)
    row.colDir:SetPoint("TOPLEFT", 10, ICON_Y)

    row.colSender = CreateCol("CENTER", 110, FONT_SIZE_NAME, C.TEXT_PRIMARY)
    row.colSender:SetPoint("TOPLEFT", 40, Y_OFFSET)

    row.colReceiver = CreateCol("CENTER", 110, FONT_SIZE_NAME, C.TEXT_PRIMARY)
    row.colReceiver:SetPoint("TOPLEFT", 155, Y_OFFSET)

    row.colAmount = CreateCol("RIGHT", 130, FONT_SIZE_GOLD, C.TEXT_PRIMARY)
    row.colAmount:SetPoint("TOPRIGHT", -15, Y_OFFSET)

    row.colSubject = CreateCol("LEFT", 1, FONT_SIZE_SUBJ, C.TEXT_TERTIARY)
    row.colSubject:SetPoint("TOPLEFT", 270, -14)
    row.colSubject:SetPoint("RIGHT", row.colAmount, "LEFT", -10, 0)

    -- HEADER STATE
    row.header = CreateFrame("Frame", nil, row)
    row.header:SetAllPoints()
    row.header:Hide()
    row.headerText = row.header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.headerText:SetFont(STANDARD_FONT, 14, "OUTLINE")
    row.headerText:SetTextColor(unpack(C.TEXT_PRIMARY))
    row.headerText:SetPoint("LEFT", 10, 0)
    row.headerLine = row.header:CreateTexture(nil, "ARTWORK")
    row.headerLine:SetHeight(1)
    row.headerLine:SetColorTexture(1, 1, 1, 0.2)
    row.headerLine:SetPoint("LEFT", row.headerText, "RIGHT", 10, 0)
    row.headerLine:SetPoint("RIGHT", -10, 0)

    -- EXPANDED VIEW
    local details = CreateFrame("Frame", nil, row)
    details:SetPoint("TOPLEFT", 0, -ROW_HEIGHT_COLLAPSED)
    details:SetPoint("BOTTOMRIGHT", 0, 0)
    details:Hide()
    row.details = details

    local function CreateDetailRow(label)
        local l = details:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        l:SetFont(STANDARD_FONT, FONT_SIZE_DETAILS, "OUTLINE")
        l:SetTextColor(unpack(C.TEXT_TERTIARY))
        l:SetText(string.upper(label))
        l:SetWidth(55)
        l:SetJustifyH("RIGHT")

        local v = details:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        v:SetFont(STANDARD_FONT, FONT_SIZE_VALUES, "OUTLINE")
        v:SetTextColor(unpack(C.TEXT_PRIMARY))
        v:SetPoint("TOPLEFT", l, "TOPRIGHT", 4, 2)
        return l, v
    end

    row.lblSent,    row.valSent    = CreateDetailRow("Sent")
    row.lblReceived,row.valReceived= CreateDetailRow("Received")
    row.lblOpened,  row.valOpened  = CreateDetailRow("Opened")
    row.lblFlow,    row.valFlow    = CreateDetailRow("Flow")
    row.lblRealm,   row.valRealm   = CreateDetailRow("Realm")

    row.lblSubject = details:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.lblSubject:SetFont(STANDARD_FONT, FONT_SIZE_DETAILS, "OUTLINE")
    row.lblSubject:SetTextColor(unpack(C.TEXT_TERTIARY))
    row.lblSubject:SetText("SUBJECT")
    row.lblSubject:SetWidth(55)
    row.lblSubject:SetJustifyH("RIGHT")

    row.valSubject = details:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.valSubject:SetFont(STANDARD_FONT, FONT_SIZE_VALUES, "OUTLINE")
    row.valSubject:SetTextColor(unpack(C.TEXT_PRIMARY))
    row.valSubject:SetJustifyH("LEFT")
    row.valSubject:SetWidth(300)
    row.valSubject:SetPoint("TOPLEFT", row.lblSubject, "TOPRIGHT", 4, 2)

    row.lblBody = details:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.lblBody:SetFont(STANDARD_FONT, FONT_SIZE_DETAILS, "OUTLINE")
    row.lblBody:SetTextColor(unpack(C.TEXT_TERTIARY))
    row.lblBody:SetText("BODY")
    row.lblBody:SetWidth(55)
    row.lblBody:SetJustifyH("RIGHT")

    row.valBody = details:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.valBody:SetFont(STANDARD_FONT, FONT_SIZE_VALUES, "OUTLINE")
    row.valBody:SetTextColor(unpack(C.TEXT_SECONDARY))
    row.valBody:SetJustifyH("LEFT")
    row.valBody:SetJustifyV("TOP")
    row.valBody:SetWidth(300)
    row.valBody:SetHeight(60)
    row.valBody:SetPoint("TOPLEFT", row.lblBody, "TOPRIGHT", 4, 2)

    row:SetScript("OnEnter", function()
        if row.isHeader then return end
        if not row.isExpanded then row.bg:SetColorTexture(unpack(C.BG_HOVER)) end
        row.accent:Show()
    end)
    row:SetScript("OnLeave", function()
        if row.isHeader then return end
        if not row.isExpanded then
            if row.isAlternate then row.bg:SetColorTexture(unpack(C.BG_ALTERNATE))
            else row.bg:SetColorTexture(unpack(C.BG_NORMAL)) end
            row.accent:Hide()
        end
    end)
    return row
end

function Log:ToggleMailLog(anchorFrame)
    if not mailLogFrame then
        mailLogFrame = CreateBasePanel("whisperMailLog", "Mail Log", UIParent)
        mailLogFrame:SetSize(650, 570)

        local scroll = CreateFrame("ScrollFrame", "whisperMailLogScroll", mailLogFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -60)
        scroll:SetPoint("BOTTOMRIGHT", -30, 30)
        if scroll.ScrollBar then scroll.ScrollBar:SetAlpha(0) scroll.ScrollBar:EnableMouse(false) end

        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(610, 500)
        scroll:SetScrollChild(content)
        mailLogFrame.content = content

        local empty = mailLogFrame.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        empty:SetFont(STANDARD_FONT, 14, "OUTLINE")
        empty:SetPoint("CENTER", mailLogFrame, "CENTER", 0, 0)
        empty:SetText("No mail records found.")
        empty:SetTextColor(unpack(C.TEXT_TERTIARY))
        empty:Hide()
        mailLogFrame.emptyState = empty

        local search = CreateSearchBox(mailLogFrame, function(text)
            currentMailFilter = text
            Log:RefreshMailLog()
        end)
        search:SetPoint("TOPRIGHT", -30, -20)

        local btnCharToggle = CreateFrame("Button", nil, mailLogFrame, "BackdropTemplate")
        btnCharToggle:SetSize(120, 22)
        btnCharToggle:SetPoint("BOTTOMLEFT", 8, 4)
        btnCharToggle:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        btnCharToggle:SetBackdropColor(0, 0, 0, 1)
        btnCharToggle:SetBackdropBorderColor(0, 0, 0, 1)

        local charToggleText = btnCharToggle:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        charToggleText:SetFont(STANDARD_FONT, 12, "OUTLINE")
        charToggleText:SetPoint("CENTER", 0, 0)
        btnCharToggle.text = charToggleText

        local btnMail = CreateFrame("Button", nil, mailLogFrame, "BackdropTemplate")
        btnMail:SetSize(60, 22)
        btnMail:SetPoint("LEFT", btnCharToggle, "RIGHT", 12, 0)
        btnMail:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        btnMail:SetBackdropColor(0, 0, 0, 1)
        btnMail:SetBackdropBorderColor(0, 0, 0, 1)

        local mailText = btnMail:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        mailText:SetFont(STANDARD_FONT, 12, "OUTLINE")
        mailText:SetPoint("CENTER", 0, 0)
        mailText:SetText("Mail")

        btnMail:SetScript("OnClick", function()
            if whisper.modules.Mail then
                whisper.modules.Mail:TogglePanel(mailLogFrame)
            end
        end)
        btnMail:SetScript("OnEnter", function(self) self:SetBackdropColor(0.1, 0.1, 0.1, 1) end)
        btnMail:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 1) end)

        local function UpdateCharToggleText()
            if showAllCharacters then
                charToggleText:SetText("All Characters")
                charToggleText:SetTextColor(1, 1, 1)
            else
                charToggleText:SetText("This Character")
                charToggleText:SetTextColor(1, 1, 1)
            end
        end

        UpdateCharToggleText()

        btnCharToggle:SetScript("OnClick", function()
            showAllCharacters = not showAllCharacters
            UpdateCharToggleText()
            for _, entry in ipairs(whisperDB.log.mail) do entry.expanded = false end
            Log:RefreshMailLog()
        end)

        local function AddHover(btn)
            btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.1, 0.1, 0.1, 1) end)
            btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 1) end)
        end
        AddHover(btnCharToggle)

        local function SetFilter(val)
            currentTypeFilter = val
            if mailLogFrame.pillAll then
                mailLogFrame.pillAll.UpdateState(mailLogFrame.pillAll, val)
                mailLogFrame.pillIn.UpdateState(mailLogFrame.pillIn, val)
                mailLogFrame.pillOut.UpdateState(mailLogFrame.pillOut, val)
            end
            for _, entry in ipairs(whisperDB.log.mail) do entry.expanded = false end
            Log:RefreshMailLog()
        end

        local pillAll = CreateFilterPill(mailLogFrame, "All", "ALL", SetFilter)
        pillAll:SetPoint("RIGHT", search, "LEFT", -10, 0)
        mailLogFrame.pillAll = pillAll

        local pillIn = CreateFilterPill(mailLogFrame, "Incoming", "IN", SetFilter)
        pillIn:SetPoint("RIGHT", pillAll, "LEFT", -5, 0)
        mailLogFrame.pillIn = pillIn

        local pillOut = CreateFilterPill(mailLogFrame, "Outgoing", "OUT", SetFilter)
        pillOut:SetPoint("RIGHT", pillIn, "LEFT", -5, 0)
        mailLogFrame.pillOut = pillOut

        local clearBtn = CreateFrame("Button", nil, mailLogFrame, "BackdropTemplate")
        clearBtn:SetSize(80, 22)
        clearBtn:SetPoint("BOTTOMRIGHT", -8, 4)
        clearBtn:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        clearBtn:SetBackdropColor(0, 0, 0, 1)
        clearBtn:SetBackdropBorderColor(0, 0, 0, 1)
        local ct = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        ct:SetFont(STANDARD_FONT, 12, "OUTLINE")
        ct:SetPoint("CENTER")
        ct:SetText("Clear")
        ct:SetTextColor(unpack(C.RED))
        clearBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.1, 0.1, 0.1, 1) end)
        clearBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 1) end)

        clearBtn:SetScript("OnClick", function()
            StaticPopup_Show("WHISPER_LOG_CLEAR_CONFIRM")
        end)

        mailLogFrame:SetScript("OnHide", function()
            currentTypeFilter = "ALL"
            showAllCharacters = false
            UpdateCharToggleText()
            if whisper.modules.Mail and whisper.modules.Mail.ResetPanel then
                whisper.modules.Mail:ResetPanel()
            end
            if mailLogFrame.pillAll then
                mailLogFrame.pillAll.UpdateState(mailLogFrame.pillAll, "ALL")
                mailLogFrame.pillIn.UpdateState(mailLogFrame.pillIn, "ALL")
                mailLogFrame.pillOut.UpdateState(mailLogFrame.pillOut, "ALL")
            end
            for _, entry in ipairs(whisperDB.log.mail) do entry.expanded = false end
        end)

        SetFilter("ALL")
    end

    if anchorFrame then
        mailLogFrame:SetParent(anchorFrame)
        mailLogFrame:ClearAllPoints()
        mailLogFrame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 2, 0)
        FadeIn(mailLogFrame, 0.1) -- ANIMATED SHOW
        Log:RefreshMailLog()
    else
        FadeOut(mailLogFrame, 0.1) -- ANIMATED HIDE
    end
end

function Log:HideMailLog() if mailLogFrame then mailLogFrame:Hide() end end

function Log:RefreshMailLog()
    if not mailLogFrame or not mailLogFrame:IsShown() then return end
    if not mailLogFrame.content then return end

    filteredMailList = FilterData(whisperDB.log.mail, currentMailFilter, currentTypeFilter, showAllCharacters)
    displayList = {}
    local lastDateKey = nil

    for _, entry in ipairs(filteredMailList) do
        local entryDateKey = GetDateKey(entry.timestamp)
        if entryDateKey ~= lastDateKey then
            tinsert(displayList, { isHeader = true, text = FormatDateHeader(entry.timestamp) })
            lastDateKey = entryDateKey
        end
        tinsert(displayList, entry)
    end

    for _, row in ipairs(mailRowPool) do row:Hide() end
    if #displayList == 0 then if mailLogFrame.emptyState then mailLogFrame.emptyState:Show() end
    else if mailLogFrame.emptyState then mailLogFrame.emptyState:Hide() end end

    local yOffset = 0
    for i, item in ipairs(displayList) do
        local row = mailRowPool[i]
        if not row then
            row = CreateDynamicRow(mailLogFrame.content)
            mailRowPool[i] = row
            row:SetScript("OnClick", function()
                if not row.isHeader then
                    row.data.expanded = not row.data.expanded
                    Log:RefreshMailLog()
                end
            end)
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -yOffset)
        row:SetPoint("RIGHT", 0, 0)
        row:Show()
        row.data = item

        if item.isHeader then
            row.isHeader = true
            row.isExpanded = false
            row:SetHeight(ROW_HEIGHT_HEADER)
            row.bg:Hide()
            row.accent:Hide()
            row.colDir:Hide() row.colSender:Hide() row.colReceiver:Hide() row.colSubject:Hide() row.colAmount:Hide()
            row.details:Hide()
            row.header:Show()
            row.headerText:SetText(item.text)
            yOffset = yOffset + ROW_HEIGHT_HEADER
        else
            row.isHeader = false
            row.isExpanded = item.expanded
            row.header:Hide()
            row.colDir:Show() row.colSender:Show() row.colReceiver:Show() row.colSubject:Show() row.colAmount:Show()

            row.isAlternate = (i % 2 == 0)
            if row.isAlternate then row.bg:SetColorTexture(unpack(C.BG_ALTERNATE))
            else row.bg:SetColorTexture(unpack(C.BG_NORMAL)) end

            local sender, receiver
            local owner = item.owner or PLAYER_NAME

            if item.type == "Sent" then
                row.colDir:SetText(C.SYMBOL_OUT)
                row.colDir:SetTextColor(unpack(C.OUTGOING))
                sender = owner
                receiver = item.target
            else
                row.colDir:SetText(C.SYMBOL_IN)
                row.colDir:SetTextColor(unpack(C.INCOMING))
                sender = item.target
                receiver = owner
            end

            TruncateText(row.colSender, sender, 105)
            TruncateText(row.colReceiver, receiver, 105)
            TruncateText(row.colSubject, item.subject, 190)
            row.colAmount:SetText(FormatCurrencyStyled(item.money))

            if item.expanded then
                row.accent:Show()
                row.bg:SetColorTexture(unpack(C.BG_EXPANDED))
                row.bg:Show()
                row.details:Show()

                row.lblSent:Hide()    row.valSent:Hide()
                row.lblReceived:Hide() row.valReceived:Hide()
                row.lblOpened:Hide()   row.valOpened:Hide()

                local currentY = -PADDING - 4
                if item.type == "Sent" then
                    row.lblSent:Show() row.valSent:Show() row.valSent:SetText(item.timestamp)
                    row.lblSent:SetPoint("TOPLEFT", 40, currentY)
                    currentY = currentY - LINE_HEIGHT
                else
                    row.lblReceived:Show() row.valReceived:Show() row.valReceived:SetText(item.dateSent or item.timestamp)
                    row.lblReceived:SetPoint("TOPLEFT", 40, currentY)
                    currentY = currentY - LINE_HEIGHT
                    row.lblOpened:Show() row.valOpened:Show() row.valOpened:SetText(item.dateOpened or item.timestamp)
                    row.lblOpened:SetPoint("TOPLEFT", 40, currentY)
                    currentY = currentY - LINE_HEIGHT
                end

                row.lblFlow:Show() row.valFlow:Show()
                row.lblFlow:SetPoint("TOPLEFT", 40, currentY)
                row.valFlow:SetText(sender .. " " .. C.SYMBOL_FLOW .. " " .. receiver)
                currentY = currentY - LINE_HEIGHT

                row.lblRealm:Show() row.valRealm:Show()
                row.lblRealm:SetPoint("TOPLEFT", 40, currentY)
                if item.target and string.find(item.target, "-") then
                    local _, r = strsplit("-", item.target)
                    row.valRealm:SetText(r)
                else
                    row.valRealm:SetText(GetRealmName())
                end
                currentY = currentY - LINE_HEIGHT

                local rightX = 270
                local rightY = -PADDING - 4

                row.lblSubject:Show() row.valSubject:Show()
                row.lblSubject:SetPoint("TOPLEFT", rightX, rightY)
                row.valSubject:SetText(item.subject or "No Subject")
                rightY = rightY - LINE_HEIGHT

                row.lblBody:Show() row.valBody:Show()
                row.lblBody:SetPoint("TOPLEFT", rightX, rightY)
                row.valBody:SetText(item.body or "")
                local bodyHeight = row.valBody:GetStringHeight()
                row.valBody:SetHeight(bodyHeight)

                local totalH = math.max(abs(currentY), abs(rightY - LINE_HEIGHT - bodyHeight)) + PADDING
                local dynamicHeight = ROW_HEIGHT_COLLAPSED + totalH

                row:SetHeight(dynamicHeight)
                row.accent:SetHeight(dynamicHeight)
                yOffset = yOffset + dynamicHeight
            else
                row:SetHeight(ROW_HEIGHT_COLLAPSED)
                row.accent:SetHeight(ROW_HEIGHT_COLLAPSED) -- FORCE RESET ON COLLAPSE
                row.accent:Hide()
                row.details:Hide()
                yOffset = yOffset + ROW_HEIGHT_COLLAPSED
            end
        end
    end
    mailLogFrame.content:SetHeight(yOffset)
end

function Log:CreateGuildBankButton() end
function Log:ToggleGuildLog() end
function Log:RefreshGuildLog() end
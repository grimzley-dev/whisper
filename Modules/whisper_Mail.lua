local addonName, whisper = ...
local Mail = {}
Mail.enabled = true
whisper:RegisterModule("Mail", Mail)

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local GetMoney = GetMoney
local SendMail = SendMail
local SetSendMailMoney = SetSendMailMoney
local ClearSendMail = ClearSendMail
local tinsert = tinsert
local unpack = unpack
local floor = math.floor
local format = string.format
local abs = math.abs

local button, panel, eventFrame
local statusTimer 
local resultStatusTimer
local STANDARD_FONT = "Fonts\\FRIZQT__.TTF"
-- TEXTURE FIX: Updated to use whisperBar.tga
local BAR_TEXTURE = "Interface\\AddOns\\whisper\\Media\\whisperBar.tga"

local COLOR_RED = {1, 0.2, 0.2}
local COLOR_GREEN = {0, 1, 0.2}
local COLOR_WHITE = {1, 1, 1}

local HEX_RED = "|cffFF3333"
local HEX_GREEN = "|cff00FF33"
local HEX_GREY = "|cff999999"
local HEX_GOLD = "|cffffd700"
local HEX_SILVER = "|cffc7c7cf"
local HEX_COPPER = "|cffeda55f"

local function CreateStyledButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetText(text)
    btn:SetPushedTextOffset(0, 0)

    local fs = btn:GetFontString()
    if not fs then
        fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        btn:SetFontString(fs)
    end
    
    fs:SetPoint("CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetFont(STANDARD_FONT, 14, "OUTLINE")
    fs:SetTextColor(1, 1, 1) 
    
    btn:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    
    btn:SetBackdropColor(0, 0, 0, 0.8)      
    btn:SetBackdropBorderColor(0, 0, 0, 1)      

    btn.textColor = COLOR_WHITE

    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            self:SetBackdropColor(0.1, 0.1, 0.1, 0.9) 
            self:SetBackdropBorderColor(0, 0, 0, 1) 
            local r, g, b = unpack(self.textColor or COLOR_WHITE)
            if self:GetFontString() then self:GetFontString():SetTextColor(r, g, b) end
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0.8) 
        self:SetBackdropBorderColor(0, 0, 0, 1) 
        if self:IsEnabled() then
            local r, g, b = unpack(self.textColor or COLOR_WHITE)
            if self:GetFontString() then self:GetFontString():SetTextColor(r, g, b) end
        else
            if self:GetFontString() then self:GetFontString():SetTextColor(0.5, 0.5, 0.5) end
        end
    end)
    
    btn:SetScript("OnMouseDown", function(self) 
        if self:IsEnabled() then self:SetBackdropColor(0.15, 0.15, 0.15, 1) end
    end)
    btn:SetScript("OnMouseUp", function(self) 
        if self:IsEnabled() then self:SetBackdropColor(0.1, 0.1, 0.1, 0.9) end
    end)
    
    btn:SetScript("OnEnable", function(self)
        local r, g, b = unpack(self.textColor or COLOR_WHITE)
        if self:GetFontString() then self:GetFontString():SetTextColor(r, g, b) end
    end)
    btn:SetScript("OnDisable", function(self)
        if self:GetFontString() then self:GetFontString():SetTextColor(0.5, 0.5, 0.5) end
    end)

    return btn
end

local function FormatCurrency(copper)
    copper = floor(copper + 0.5)
    if not copper or copper == 0 then return "0" .. HEX_COPPER .. "c|r" end
    
    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local cop = floor(copper % 100)
    
    local text = ""
    if gold > 0 then
        text = text .. gold .. HEX_GOLD .. "g|r "
    end
    if silver > 0 or gold > 0 then
        text = text .. silver .. HEX_SILVER .. "s|r "
    end
    text = text .. cop .. HEX_COPPER .. "c|r"
    return text
end

function Mail:Init()
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("MAIL_SHOW")
    eventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "MAIL_SHOW" then
            Mail:CreateButton()
        elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            local interactionType = ...
            if interactionType == Enum.PlayerInteractionType.MailInfo then
                if button then button:Hide() end
                if panel then 
                    Mail:ResetPanel()
                end
            end
        elseif event == "MAIL_SEND_SUCCESS" then
            Mail:OnMailSendSuccess()
        end
    end)
end

function Mail:Disable()
    self.enabled = false
    if button then button:Hide() end
    if panel then panel:Hide() end
    if eventFrame then
        eventFrame:UnregisterAllEvents()
        eventFrame:SetScript("OnEvent", nil)
    end
    self._queue = nil
    self._sending = false
    self._index = nil
end

function Mail:ResetPanel()
    if not panel then return end
    
    if statusTimer then
        statusTimer:Cancel()
        statusTimer = nil
    end
    if resultStatusTimer then
        resultStatusTimer:Cancel()
        resultStatusTimer = nil
    end
    
    if eventFrame then
        eventFrame:UnregisterEvent("MAIL_SEND_SUCCESS")
    end
    
    self._queue = nil
    self._sending = false
    self._index = nil
    
    local p = panel
    panel = nil
    
    p:Hide()
    p:SetParent(nil)
end

function Mail:CreateButton()
    if button then
        button:Show()
        return
    end

    button = CreateFrame("Button", nil, MailFrame)
    button:SetSize(40, 40)
    button:SetPoint("BOTTOM", MailFrame, "BOTTOM", 4, 34)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(2)

    local tex = button:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface/AddOns/whisper/Media/whisperLogo")
    tex:SetAllPoints()
    tex:SetAlpha(0.7)
    button.tex = tex

    button:SetScript("OnEnter", function(self)
        self.tex:SetVertexColor(0.8, 0.8, 0.8)
    end)
    button:SetScript("OnLeave", function(self)
        self.tex:SetVertexColor(1, 1, 1)
    end)
    button:SetScript("OnMouseDown", function(self)
        self.tex:SetVertexColor(0.6, 0.6, 0.6)
    end)
    button:SetScript("OnMouseUp", function(self)
        self.tex:SetVertexColor(0.8, 0.8, 0.8)
    end)

    button:SetScript("OnClick", function()
        Mail:TogglePanel()
    end)
end

function Mail:TogglePanel()
    if panel then
        panel:SetShown(not panel:IsShown())
        return
    end

    panel = CreateFrame("Frame", "whisperMailPanel", UIParent, "BackdropTemplate")
    
    local parentHeight = MailFrame:GetHeight() or 424
    local parentWidth = MailFrame:GetWidth() or 384
    panel:SetSize(parentWidth, parentHeight)

    panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 2, 0)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    
    panel:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    
    panel:SetBackdropColor(8/255, 8/255, 8/255, 0.8)
    panel:SetBackdropBorderColor(0, 0, 0, 1)
    
    tinsert(UISpecialFrames, panel:GetName())

    local subHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    subHeader:SetPoint("TOPLEFT", 20, -20)
    subHeader:SetText("Mail")
    subHeader:SetFont(STANDARD_FONT, 20, "OUTLINE")
    subHeader:SetTextColor(1, 1, 1)

    Mail:CreateLogo(panel)
    Mail:CreateCloseButton(panel)
    Mail:CreateScrollArea(panel)
    Mail:CreatePreviewPane(panel)
    Mail:CreateResultPane(panel) 
    Mail:CreateControlButtons(panel)
    Mail:CreateProgressBar(panel)
end

function Mail:CreateLogo(parent)
    local logo = parent:CreateTexture(nil, "BACKGROUND", nil, -1)
    logo:SetSize(256, 256)
    logo:SetPoint("BOTTOMLEFT", 0, 0)
    logo:SetTexture("Interface/AddOns/whisper/Media/whisperLogo")
    logo:SetAlpha(0.5)
end

function Mail:CreateCloseButton(parent)
    local close = CreateFrame("Button", nil, parent)
    close:SetHitRectInsets(6, 6, 7, 7)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -2)

    if not close.Texture then
        close.Texture = close:CreateTexture(nil, "OVERLAY")
        close.Texture:SetPoint("CENTER")
        close.Texture:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        close.Texture:SetSize(22, 22)
    end

    close:SetScript("OnEnter", function(self)
        self.Texture:SetVertexColor(0.5, 0.5, 0.5) 
    end)
    close:SetScript("OnLeave", function(self)
        self.Texture:SetVertexColor(1, 1, 1) 
    end)
    close:SetScript("OnMouseDown", function(self)
        self.Texture:SetVertexColor(0.3, 0.3, 0.3) 
    end)
    close:SetScript("OnMouseUp", function(self)
        if self:IsMouseOver() then
            self.Texture:SetVertexColor(0.5, 0.5, 0.5)
        else
            self.Texture:SetVertexColor(1, 1, 1)
        end
    end)
    
    close:SetScript("OnClick", function()
        Mail:ResetPanel()
    end)
end

function Mail:CreateScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", 14, -50)
    scroll:SetPoint("BOTTOMRIGHT", -14, 90)
    scroll:EnableMouse(true)
    scroll:SetClipsChildren(true)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetFont(STANDARD_FONT, 13, "OUTLINE")
    editBox:SetWidth(scroll:GetWidth())
    editBox:SetHeight(600)
    editBox:SetAutoFocus(false)
    editBox:SetTextInsets(6,6,6,6)
    editBox:SetJustifyH("LEFT")
    editBox:SetJustifyV("TOP")
    
    panel.scrollFrame = scroll
    panel.editBox = editBox
    scroll:SetScrollChild(editBox)
    if scroll.ScrollBar then scroll.ScrollBar:Hide() end
    
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        if not child then return end
        local maxScroll = math.max(child:GetHeight() - self:GetHeight(), 0)
        local offset = self:GetVerticalScroll() or 0
        local newOffset = math.min(math.max(offset - (delta * 20), 0), maxScroll)
        self:SetVerticalScroll(newOffset)
    end)
end

function Mail:CreatePreviewPane(parent)
    local preview = CreateFrame("Frame", nil, parent)
    preview:SetPoint("TOPLEFT", 14, -50)
    preview:SetPoint("BOTTOMRIGHT", -14, 90)
    preview:Hide()
    
    local lblTo = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lblTo:SetFont(STANDARD_FONT, 12, "OUTLINE")
    lblTo:SetTextColor(0.6, 0.6, 0.6)
    lblTo:SetPoint("TOP", 0, -20)
    lblTo:SetText("Sending to")
    
    local txtTo = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txtTo:SetFont(STANDARD_FONT, 24, "OUTLINE")
    txtTo:SetTextColor(1, 1, 1)
    txtTo:SetPoint("TOP", lblTo, "BOTTOM", 0, -5)
    
    local txtAmount = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txtAmount:SetFont(STANDARD_FONT, 18, "OUTLINE")
    txtAmount:SetPoint("TOP", txtTo, "BOTTOM", 0, -15)
    
    local line = preview:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.2)
    line:SetHeight(1)
    line:SetWidth(200)
    line:SetPoint("TOP", txtAmount, "BOTTOM", 0, -15)
    
    local txtSubject = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txtSubject:SetFont(STANDARD_FONT, 14, "OUTLINE")
    txtSubject:SetTextColor(0.9, 0.9, 0.9)
    txtSubject:SetPoint("TOP", line, "BOTTOM", 0, -15)
    
    local txtBody = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txtBody:SetFont(STANDARD_FONT, 13, "OUTLINE")
    txtBody:SetTextColor(0.7, 0.7, 0.7)
    txtBody:SetJustifyH("CENTER") 
    txtBody:SetJustifyV("TOP")
    txtBody:SetPoint("TOPLEFT", preview, "TOPLEFT", 10, -160)
    txtBody:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -10, 0)
    
    panel.preview = preview
    panel.preview.recipient = txtTo
    panel.preview.amount = txtAmount
    panel.preview.subject = txtSubject
    panel.preview.body = txtBody
end

function Mail:CreateResultPane(parent)
    local result = CreateFrame("Frame", nil, parent)
    result:SetPoint("TOPLEFT", 14, -50)
    result:SetPoint("BOTTOMRIGHT", -14, 90)
    result:Hide()
    
    local title = result:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetFont(STANDARD_FONT, 24, "OUTLINE")
    title:SetPoint("TOP", 0, -20)
    title:SetText("Summary")
    
    local line = result:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.2)
    line:SetHeight(1)
    line:SetWidth(200)
    line:SetPoint("TOP", title, "BOTTOM", 0, -15)
    
    local footerStatus = result:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    footerStatus:SetFont(STANDARD_FONT, 16, "OUTLINE")
    footerStatus:SetPoint("BOTTOM", result, "BOTTOM", 0, 10) 
    
    local scroll = CreateFrame("ScrollFrame", nil, result)
    scroll:SetPoint("TOPLEFT", result, "TOPLEFT", 0, -80)
    scroll:SetPoint("BOTTOMRIGHT", result, "BOTTOMRIGHT", 0, 40) 
    scroll:EnableMouse(true)
    
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(scroll:GetWidth(), 500)
    scroll:SetScrollChild(content)
    
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        if not child then return end
        local maxScroll = math.max(child:GetHeight() - self:GetHeight(), 0)
        local offset = self:GetVerticalScroll() or 0
        local newOffset = math.min(math.max(offset - (delta * 20), 0), maxScroll)
        self:SetVerticalScroll(newOffset)
    end)
    
    result.footerStatus = footerStatus
    result.scroll = scroll
    result.content = content
    panel.result = result
end

function Mail:CreateControlButtons(parent)
    local send = CreateStyledButton(parent, "Parse & Queue", 140, 28)
    send:SetPoint("BOTTOM", 0, 12) 
    panel.sendButton = send

    send:SetScript("OnClick", function()
        if panel.result:IsShown() then
            Mail._queue = nil
            Mail._sending = false
            Mail._index = nil
            panel.result:Hide()
            panel.scrollFrame:Show()
            panel.sendButton:SetText("Parse & Queue")
            panel.sendButton:ClearAllPoints()
            panel.sendButton:SetPoint("BOTTOM", 0, 12)
        else
            Mail:HandleSendButton()
        end
    end)

    local clear = CreateStyledButton(parent, "Clear", 140, 28)
    clear:Hide() 
    panel.clearButton = clear

    clear:SetScript("OnClick", function()
        Mail:FinishQueue(true)
    end)
end

function Mail:CreateProgressBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
    bar:SetSize(290, 20) 
    bar:SetPoint("BOTTOM", parent, "BOTTOM", 0, 48) 
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetStatusBarColor(0.5, 0.5, 1, 1) 
    
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetTexture(BAR_TEXTURE)
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.8) 
    bar.bg = bg
    
    bar:SetBackdrop({
        bgFile = nil,
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    bar:SetBackdropBorderColor(0, 0, 0, 1)

    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    text:SetFont(STANDARD_FONT, 12, "OUTLINE")
    text:SetText("0 / 0")
    bar.text = text

    bar.targetValue = 0
    bar:SetScript("OnUpdate", function(self, elapsed)
        local current = self:GetValue()
        local target = self.targetValue or current
        if abs(current - target) > 0.01 then
            local change = (target - current) * (elapsed * 8)
            if abs(target - current) < 0.05 then
                self:SetValue(target)
            else
                self:SetValue(current + change)
            end
        elseif current ~= target then
            self:SetValue(target)
        end
    end)

    panel.progressBar = bar
    panel.progressBar:Hide()

    panel.statusText = parent:CreateFontString(nil, "OVERLAY")
    panel.statusText:SetFont(STANDARD_FONT, 13, "OUTLINE")
    panel.statusText:SetPoint("BOTTOM", bar, "TOP", 0, 5)
end

function Mail:SetStatus(text, timeout)
    if statusTimer then
        statusTimer:Cancel()
        statusTimer = nil
    end
    panel.statusText:SetText(text)
    if timeout and timeout > 0 then
        statusTimer = C_Timer.NewTimer(timeout, function()
            panel.statusText:SetText("")
            statusTimer = nil
        end)
    end
end

function Mail:SetResultStatus(text, timeout)
    if resultStatusTimer then
        resultStatusTimer:Cancel()
        resultStatusTimer = nil
    end
    panel.result.footerStatus:SetText(text)
    if timeout and timeout > 0 then
        resultStatusTimer = C_Timer.NewTimer(timeout, function()
            panel.result.footerStatus:SetText("")
            resultStatusTimer = nil
        end)
    end
end

function Mail:HandleSendButton()
    if not self._queue then
        Mail:ProcessString(panel.editBox:GetText())
        return
    end
    if not self._sending then
        Mail:SendCurrentMail()
    end
end

function Mail:GoldStringToCopper(amount)
    local gold = tonumber(amount) or 0
    local copper = gold * 10000
    return floor(copper + 0.5)
end

function Mail:ProcessString(text)
    local queue = {}
    local lines = {}
    
    for line in text:gmatch("[^\r\n]+") do
        tinsert(lines, line)
    end
    
    for i, line in ipairs(lines) do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then
            local name, amount, subject, body = line:match("^([^:]+):([^:]+):([^:]+):(.+)$")
            if not (name and amount and subject and body) then
                Mail:SetStatus(HEX_RED .. "Error Line " .. i .. ": Invalid Format (Name:Amount:Subject:Body)|r", 4)
                return 
            end
            name = name:match("^%s*(.-)%s*$")
            amount = amount:match("^%s*(.-)%s*$")
            subject = subject:match("^%s*(.-)%s*$")
            body = body:match("^%s*(.-)%s*$")
            if name:match("%s") or name:gsub("-", ""):match("[:;,%p]") then
                 Mail:SetStatus(HEX_RED .. "Error Line " .. i .. ": Invalid Name|r", 4)
                 return
            end
            if subject:match(":%s*[%d%.]+%s*:") or body:match(":%s*[%d%.]+%s*:") then
                Mail:SetStatus(HEX_RED .. "Error Line " .. i .. ": Detects merged lines|r", 4)
                return
            end
            if #subject > 64 or #body > 500 then
                Mail:SetStatus(HEX_RED .. "Error Line " .. i .. ": Length Limits Exceeded|r", 4)
                return
            end
            local copper = Mail:GoldStringToCopper(amount)
            if copper <= 0 then
                Mail:SetStatus(HEX_RED .. "Error Line " .. i .. ": Invalid Amount|r", 4)
                return 
            end
            queue[#queue+1] = { target = name, money = copper, subject = subject, body = body, sent = false }
        end
    end
    if #queue == 0 then
        Mail:SetStatus(HEX_RED .. "Error: Input is empty.|r", 4)
        return
    end
    Mail:StartQueue(queue)
end

function Mail:StartQueue(queue)
    self._queue = queue
    self._index = 1
    self._sending = false
    eventFrame:RegisterEvent("MAIL_SEND_SUCCESS")
    Mail:SetStatus("")
    panel.result:Hide()
    panel.scrollFrame:Hide()
    panel.preview:Show()
    
    panel.clearButton:ClearAllPoints()
    panel.clearButton:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -5, 12)
    panel.clearButton:Show()
    panel.clearButton:Enable()
    panel.clearButton.textColor = COLOR_RED 
    
    local cr, cg, cb = unpack(COLOR_RED)
    panel.clearButton:GetFontString():SetTextColor(cr, cg, cb)

    panel.sendButton:SetText("Send")
    panel.sendButton:ClearAllPoints()
    panel.sendButton:SetPoint("BOTTOMLEFT", panel, "BOTTOM", 5, 12)
    panel.sendButton.textColor = COLOR_GREEN 
    panel.sendButton:Disable() 
    
    C_Timer.After(1.5, function() 
        if panel.sendButton then 
            panel.sendButton:Enable() 
            local gr, gg, gb = unpack(COLOR_GREEN)
            panel.sendButton:GetFontString():SetTextColor(gr, gg, gb)
        end 
    end)

    panel.progressBar:SetMinMaxValues(0, #queue)
    panel.progressBar:SetValue(0) 
    panel.progressBar.targetValue = 0
    panel.progressBar.text:SetText(format("1 / %d", #queue))
    panel.progressBar:Show()
    
    Mail:ShowCurrentMail()
end

function Mail:PopulateResults()
    local content = panel.result.content
    if content.lines then for _, obj in ipairs(content.lines) do obj:Hide() end end
    content.lines = {}
    local sentList, skippedList = {}, {}
    for _, entry in ipairs(self._queue) do
        if entry.sent then tinsert(sentList, entry) else tinsert(skippedList, entry) end
    end
    local yOffset = -5
    local function AddLine(text, isHeader)
        local line = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line:SetFont(STANDARD_FONT, 14, "OUTLINE")
        if isHeader then line:SetTextColor(0.8, 0.8, 0.8) end
        line:SetPoint("TOPLEFT", 10, yOffset)
        line:SetJustifyH("LEFT")
        line:SetText(text)
        tinsert(content.lines, line)
        yOffset = yOffset - 20
    end
    if #sentList > 0 then
        AddLine("Successfully Sent", true) 
        for _, entry in ipairs(sentList) do AddLine(HEX_GREEN .. "•|r " .. "|cffffffff" .. entry.target .. "|r  -  " .. FormatCurrency(entry.money)) end
        yOffset = yOffset - 15 
    end
    if #skippedList > 0 then
        AddLine("Not Sent / Skipped", true) 
        for _, entry in ipairs(skippedList) do AddLine(HEX_RED .. "•|r " .. "|cffffffff" .. entry.target .. "|r  -  " .. FormatCurrency(entry.money)) end
    end
    content:SetHeight(abs(yOffset) + 20)
end

function Mail:FinishQueue(wasCleared)
    self._sending = false
    eventFrame:UnregisterEvent("MAIL_SEND_SUCCESS")
    Mail:SetStatus("") 

    panel.preview:Hide()
    panel.editBox:SetText("")
    panel.progressBar:Hide()
    panel.result:Show()
    
    if wasCleared then 
        Mail:SetResultStatus(HEX_RED .. "Queue Cleared|r", 4) 
    else 
        Mail:SetResultStatus(HEX_GREEN .. "All Mail Sent|r", 4) 
    end
    
    Mail:PopulateResults()
    panel.sendButton:SetText("New Mail")
    panel.sendButton:ClearAllPoints()
    panel.sendButton:SetPoint("BOTTOM", 0, 12)
    panel.sendButton.textColor = COLOR_WHITE 
    panel.sendButton:Enable()
    panel.clearButton:Hide()
end

function Mail:ShowCurrentMail()
    local entry = self._queue[self._index]
    if not entry then return end
    panel.preview.recipient:SetText(entry.target)
    panel.preview.amount:SetText(FormatCurrency(entry.money))
    panel.preview.subject:SetText(entry.subject)
    panel.preview.body:SetText(entry.body)
    panel.progressBar.text:SetText(format("%d / %d", self._index, #self._queue))
end

function Mail:SendCurrentMail()
    local entry = self._queue[self._index]
    if not entry or self._sending then return end
    
    if GetMoney() < (entry.money + 30) then
        Mail:SetStatus(HEX_RED .. "Error: Need 30c postage for " .. entry.target .. ".|r", 4)
        self._index = self._index + 1
        Mail:AdvanceQueue()
        return
    end
    
    self._sending = true
    Mail:SetStatus(HEX_GREY .. "Sending mail to " .. entry.target .. "|r")
    ClearSendMail()
    SetSendMailMoney(entry.money)
    SendMail(entry.target, entry.subject, entry.body)
end

function Mail:OnMailSendSuccess()
    if not self._sending then return end
    self._sending = false
    if self._queue[self._index] then self._queue[self._index].sent = true end
    panel.progressBar.targetValue = self._index
    self._index = self._index + 1
    Mail:AdvanceQueue()
end

function Mail:AdvanceQueue()
    if not self._queue[self._index] then Mail:FinishQueue(false) return end
    Mail:ShowCurrentMail()
end
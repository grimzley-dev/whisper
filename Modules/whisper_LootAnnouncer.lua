local addonName, whisper = ...
local LootAnnouncer = {}
LootAnnouncer.enabled = true
LootAnnouncer.isTestMode = false
LootAnnouncer.displayName = "Loot Announcer"

LootAnnouncer.defaults = {
    offsetX = 10,
    offsetY = 10,
    soundEnabled = true,
    coloredName = true,
    showOthers = true,
    showTime = 10,
}

whisper:RegisterModule("Loot Announcer", LootAnnouncer)

-- =========================================================================
-- CONSTANTS & AESTHETICS
-- =========================================================================
local STANDARD_FONT = whisper.Style.STANDARD_FONT
local BAR_TEXTURE = "Interface\\AddOns\\whisper\\Media\\whisperBar.tga"

local ROW_HEIGHT = 38
local ROW_SPACING = 1
local WIDTH_NORMAL = 260
local MAX_VISIBLE = 6

-- Colors
local BG_COLOR = {0.031, 0.031, 0.031, 0.9}
local BORDER_COLOR = {0, 0, 0, 1}

local containerFrame
local testOverlayCtrl
local activeAnnouncements = {}
local framePool = {}
local stateByKey = {}
local eventFrame
local testTicker
local inCombat = false

-- =========================================================================
-- UTILITY FUNCTIONS
-- =========================================================================
local function GetClassColorObj(playerName)
    local name = strsplit("-", playerName) or playerName
    local _, class = UnitClass(playerName)
    if not class then _, class = UnitClass(name) end
    if class and C_ClassColor then
        return C_ClassColor.GetClassColor(class)
    end
    return nil
end

local function GetClassColoredName(playerName)
    local name = strsplit("-", playerName) or playerName
    local colorObj = GetClassColorObj(playerName)
    if colorObj then
        return string.format("|cff%02x%02x%02x%s|r", colorObj.r * 255, colorObj.g * 255, colorObj.b * 255, name)
    end
    return name
end

local function GetQualityColoredName(itemName, quality)
    local db = whisperDB.lootAnnouncer
    if not db.coloredName or not quality then return itemName end
    local color = ITEM_QUALITY_COLORS[quality]
    return color and color.color:WrapTextInColorCode(itemName) or itemName
end

-- =========================================================================
-- FRAME CREATION
-- =========================================================================

local function CreateAnnouncementFrame()
    local row = CreateFrame("Button", nil, containerFrame, "BackdropTemplate")
    row:SetSize(WIDTH_NORMAL, ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")

    row:SetBackdrop({
        bgFile = BAR_TEXTURE,
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    row:SetBackdropColor(unpack(BG_COLOR))
    row:SetBackdropBorderColor(unpack(BORDER_COLOR))

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT, ROW_HEIGHT)
    row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    local iconBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
    iconBorder:SetAllPoints(row.icon)
    iconBorder:SetBackdrop({edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1, bgFile = nil})
    iconBorder:SetBackdropBorderColor(unpack(BORDER_COLOR))
    iconBorder:SetFrameLevel(row:GetFrameLevel() + 5)

    local overlayBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
    overlayBorder:SetAllPoints(row)
    overlayBorder:SetFrameLevel(row:GetFrameLevel() + 20)
    overlayBorder:SetBackdrop({edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1, bgFile = nil})
    overlayBorder:SetBackdropBorderColor(0, 0, 0, 0)
    row.overlayBorder = overlayBorder

    row.playerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.playerText:SetFont(STANDARD_FONT, 13, "OUTLINE")
    row.playerText:SetJustifyH("LEFT")
    row.playerText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -5)

    row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.itemText:SetFont(STANDARD_FONT, 14, "OUTLINE")
    row.itemText:SetTextColor(0.8, 0.8, 0.8)
    row.itemText:SetJustifyH("LEFT")
    row.itemText:SetWordWrap(false)
    row.itemText:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 5)
    row.itemText:SetPoint("RIGHT", row, "RIGHT", -10, 0)

    row.animIn = row:CreateAnimationGroup()
    local fadeIn = row.animIn:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.25)

    row.animOut = row:CreateAnimationGroup()
    local fadeOut = row.animOut:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.3)
    row.animOut:SetScript("OnFinished", function()
        row:Hide()
        LootAnnouncer:CleanupFrame(row.key)
    end)

    row:SetScript("OnClick", function(self)
        if self.key then LootAnnouncer:RemoveAnnouncement(self.key) end
    end)

    row:SetScript("OnEnter", function(self)
        if self.data and self.data.link then
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 2, 0)
            GameTooltip:SetHyperlink(self.data.link)
            GameTooltip:Show()
        end
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        if self.data and self.data.classColor then
            local c = self.data.classColor
            self.overlayBorder:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        else
            self.overlayBorder:SetBackdropBorderColor(1, 1, 1, 1)
        end
    end)

    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self:SetBackdropColor(unpack(BG_COLOR))
        self.overlayBorder:SetBackdropBorderColor(0, 0, 0, 0)
    end)

    row:Hide()
    return row
end

-- =========================================================================
-- ANCHOR & INTERFACE LOGIC
-- =========================================================================

local function UpdateContainerPosition()
    if not containerFrame then return end
    local db = whisperDB.lootAnnouncer

    local sw = UIParent:GetWidth() or GetScreenWidth()
    local sh = UIParent:GetHeight() or GetScreenHeight()

    containerFrame:ClearAllPoints()
    containerFrame:SetPoint("TOPLEFT", UIParent, "CENTER", (db.offsetX / 100) * sw, (db.offsetY / 100) * sh)
end

local function CreateInterface()
    if containerFrame then return end

    containerFrame = CreateFrame("Frame", "whisperLootAnnouncerFrame", UIParent, "BackdropTemplate")
    containerFrame:SetSize(WIDTH_NORMAL, 1)
    containerFrame:SetClampedToScreen(true)
    containerFrame:SetMovable(true)

    containerFrame:SetScript("OnUpdate", function(self, elapsed)
        local speed = 12
        for _, frame in ipairs(activeAnnouncements) do
            if frame.targetY and frame.currentY then
                if math.abs(frame.currentY - frame.targetY) > 0.5 then
                    frame.currentY = frame.currentY + (frame.targetY - frame.currentY) * speed * elapsed
                    frame:ClearAllPoints()
                    frame:SetPoint("TOP", containerFrame, "TOP", 0, frame.currentY)
                elseif frame.currentY ~= frame.targetY then
                    frame.currentY = frame.targetY
                    frame:ClearAllPoints()
                    frame:SetPoint("TOP", containerFrame, "TOP", 0, frame.currentY)
                end
            end
        end
    end)
end

-- =========================================================================
-- CORE LOGIC
-- =========================================================================

local function AcquireFrame()
    for _, frame in ipairs(framePool) do
        if not frame:IsShown() and not frame.animOut:IsPlaying() then
            frame.currentY = nil
            frame.targetY = nil
            return frame
        end
    end
    local frame = CreateAnnouncementFrame()
    table.insert(framePool, frame)
    return frame
end

function LootAnnouncer:EnsureTestOverlay()
    if testOverlayCtrl then return end

    testOverlayCtrl = whisper.TestOverlay.Create({
        name = "WhisperLootAnnouncerOverlay",
        label = "Loot Announcer",
        container = function() return containerFrame end,
        isActive = function() return LootAnnouncer.isTestMode end,
        getContentFrames = function()
            local frames = {}
            for _, frame in ipairs(activeAnnouncements) do
                if frame:IsShown() then
                    table.insert(frames, frame)
                end
            end
            return frames
        end,
        dragMode = "move",
        onDragStop = function()
            local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
            if sw > 0 and sh > 0 and containerFrame then
                local left = containerFrame:GetLeft()
                local top = containerFrame:GetTop()
                whisperDB.lootAnnouncer.offsetX = (left - (sw / 2)) / sw * 100
                whisperDB.lootAnnouncer.offsetY = (top - (sh / 2)) / sh * 100
            end
        end,
    })
end

function LootAnnouncer:UpdateTestOverlay()
    if not self.isTestMode or not containerFrame then
        if testOverlayCtrl then testOverlayCtrl:Hide() end
        return
    end
    self:EnsureTestOverlay()
    testOverlayCtrl:Update()
end

function LootAnnouncer:UpdatePositions()
    local yOffset = ROW_SPACING
    for _, frame in ipairs(activeAnnouncements) do
        if frame:IsShown() and not frame.animOut:IsPlaying() then
            frame.targetY = -yOffset
            if not frame.currentY then
                frame.currentY = frame.targetY - 20
                frame:ClearAllPoints()
                frame:SetPoint("TOP", containerFrame, "TOP", 0, frame.currentY)
            end
            yOffset = yOffset + ROW_HEIGHT + ROW_SPACING
        end
    end

    if containerFrame then
        local totalHeight = yOffset > ROW_SPACING and (yOffset - ROW_SPACING) or ROW_HEIGHT
        containerFrame:SetHeight(math.max(ROW_HEIGHT, totalHeight))
        containerFrame:SetWidth(WIDTH_NORMAL)
    end

    self:UpdateTestOverlay()
end

function LootAnnouncer:CreateAnnouncement(data)
    if not containerFrame then CreateInterface() end
    if stateByKey[data.key] then return end

    UpdateContainerPosition()

    local frame = AcquireFrame()
    frame.key = data.key
    frame.data = data
    stateByKey[data.key] = frame

    frame.icon:SetTexture(data.icon)
    frame.playerText:SetText(data.awardedName)
    frame.itemText:SetText(data.name)

    frame.expirationTime = data.isTest and (GetTime() + 10) or (GetTime() + whisperDB.lootAnnouncer.showTime)
    table.insert(activeAnnouncements, frame)

    if #activeAnnouncements > MAX_VISIBLE then
        for _, f in ipairs(activeAnnouncements) do
            if f:IsShown() and not f.animOut:IsPlaying() then
                f.animOut:Play()
                break
            end
        end
    end

    if not data.isTest and whisperDB.lootAnnouncer.soundEnabled then
        PlaySound(165970, "Master")
    end

    frame:Show()
    self:UpdatePositions()
    frame.animIn:Play()
end

function LootAnnouncer:RemoveAnnouncement(key)
    local frame = stateByKey[key]
    if frame and frame:IsShown() then
        frame.animOut:Play()
    end
end

function LootAnnouncer:CleanupFrame(key)
    stateByKey[key] = nil
    for i = #activeAnnouncements, 1, -1 do
        if activeAnnouncements[i].key == key then
            table.remove(activeAnnouncements, i)
            break
        end
    end
    self:UpdatePositions()
end

-- =========================================================================
-- CONFIG FUNCTIONS
-- =========================================================================
function LootAnnouncer:UpdateSettings()
    UpdateContainerPosition()
end

function LootAnnouncer:ResetDefaults()
    for k, v in pairs(self.defaults) do
        whisperDB.lootAnnouncer[k] = v
    end
    self:UpdateSettings()
end


-- =========================================================================
-- EVENTS & CHAT
-- =========================================================================
local function HandleRaidMessage(message)
    if inCombat then return end

    local ok, playerName, itemLink = pcall(string.match, message, "(%S+) was awarded with (|c.-|r) for")
    if not ok or not playerName or not itemLink then return end

    local simpleName = strsplit("-", playerName)
    local mine = UnitIsUnit("player", simpleName)

    if not mine and not whisperDB.lootAnnouncer.showOthers then return end

    local itemName, _, itemQuality, itemLevel, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemLink)
    local itemID = C_Item.GetItemIDForItemInfo(itemLink)

    if not itemName then
        C_Item.RequestLoadItemDataByID(itemID)
        C_Timer.After(0.5, function() HandleRaidMessage(message) end)
        return
    end

    local key = itemID .. playerName .. (itemLevel or "")
    LootAnnouncer:CreateAnnouncement({
        key = key,
        icon = itemTexture,
        name = GetQualityColoredName(itemName, itemQuality),
        link = itemLink,
        mine = mine,
        awardedName = GetClassColoredName(playerName),
        classColor = GetClassColorObj(playerName),
        timestamp = GetTime(),
    })
end

function LootAnnouncer:Init()
    self.enabled = true
    inCombat = InCombatLockdown()

    CreateInterface()
    UpdateContainerPosition()
    if containerFrame then containerFrame:Show() end

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event, msg)
            if event == "PLAYER_REGEN_DISABLED" then
                inCombat = true
            elseif event == "PLAYER_REGEN_ENABLED" then
                inCombat = false
            elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
                HandleRaidMessage(msg)
            end
        end)
    end

    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("CHAT_MSG_RAID")
    eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")

    if not self.expirationTicker then
        self.expirationTicker = C_Timer.NewTicker(1, function()
            local now = GetTime()
            for key, frame in pairs(stateByKey) do
                if frame.expirationTime and now >= frame.expirationTime then
                    LootAnnouncer:RemoveAnnouncement(key)
                end
            end
        end)
    end
end

function LootAnnouncer:Disable()
    -- 1. Stop the test mode BEFORE setting enabled to false!
    if self.isTestMode then
        self:ToggleTestMode()
    end

    self.enabled = false

    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end

    if self.expirationTicker then
        self.expirationTicker:Cancel()
        self.expirationTicker = nil
    end

    if containerFrame then
        containerFrame:Hide()
    end

    for i = #activeAnnouncements, 1, -1 do
        local frame = activeAnnouncements[i]
        frame:Hide()
        stateByKey[frame.key] = nil
        table.remove(activeAnnouncements, i)
    end
end

function LootAnnouncer:ToggleTestMode()
    if not self.enabled then
        self.isTestMode = false
        -- Safety catch: kill the ticker if someone tries to force test mode while disabled
        if testTicker then testTicker:Cancel() testTicker = nil end
        if testOverlayCtrl then testOverlayCtrl:Hide() end
        return
    end

    self.isTestMode = not self.isTestMode
    if not containerFrame then CreateInterface() end

    -- Always clear any existing ticker safely before making a new one to prevent orphans
    if testTicker then
        testTicker:Cancel()
        testTicker = nil
    end

    if self.isTestMode then
        self:UpdateTestOverlay()

        testTicker = C_Timer.NewTicker(3, function()
            local itemID
            local slots = {1, 2, 3, 5, 7, 10, 16, 17}
            if math.random(1, 2) == 1 then
                itemID = GetInventoryItemID("player", slots[math.random(#slots)])
            else
                for b = 0, 4 do
                    for s = 1, C_Container.GetContainerNumSlots(b) do
                        itemID = C_Container.GetContainerItemID(b, s)
                        if itemID then break end
                    end
                    if itemID then break end
                end
            end

            itemID = itemID or 6948
            local itemName, itemLink, itemQuality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemID)

            local testChars = {
                { name = UnitName("player"), class = select(2, UnitClass("player")) },
                { name = "Jaina", class = "MAGE" },
                { name = "Thrall", class = "SHAMAN" },
                { name = "Anduin", class = "PRIEST" },
                { name = "Sylvanas", class = "HUNTER" },
                { name = "Illidan", class = "DEMONHUNTER" },
                { name = "Arthas", class = "DEATHKNIGHT" },
                { name = "Khadgar", class = "MAGE" },
                { name = "Baine", class = "WARRIOR" },
                { name = "Tyrande", class = "PRIEST" },
            }

            local char = testChars[math.random(#testChars)]
            local classColor = C_ClassColor.GetClassColor(char.class)

            if itemName then
                self:CreateAnnouncement({
                    key = "TEST_" .. GetTime() .. math.random(1000),
                    icon = itemTexture,
                    name = GetQualityColoredName(itemName, itemQuality),
                    link = itemLink,
                    awardedName = string.format("|cff%02x%02x%02x%s|r", classColor.r * 255, classColor.g * 255, classColor.b * 255, char.name),
                    classColor = classColor,
                    isTest = true
                })
            end
        end)
    else
        if testOverlayCtrl then testOverlayCtrl:Hide() end

        for i = #activeAnnouncements, 1, -1 do
            local frame = activeAnnouncements[i]
            if frame.data and frame.data.isTest then
                frame.animOut:Play()
            end
        end
    end
end

-- =========================
-- Config Panel UI
-- =========================
function LootAnnouncer:BuildOptionsPanel(content, toggleBtn)
    local yStart = -80
    local db = whisperDB.lootAnnouncer

    local testBtn = whisper.GUI.CreateStyledButton(content, "Test", 80, 24)
    testBtn:SetPoint("TOPLEFT", toggleBtn, "TOPRIGHT", 10, 0)
    local function UpdateTestText()
        if self.isTestMode then
            testBtn:SetText("End")
            testBtn:GetFontString():SetTextColor(1, 0.2, 0.2)
        else
            testBtn:SetText("Test")
            testBtn:GetFontString():SetTextColor(1, 1, 1)
        end
    end
    testBtn:SetScript("OnClick", function()
        if self.ToggleTestMode then self:ToggleTestMode() UpdateTestText() end
    end)
    self.testButton = testBtn

    local resetBtn = whisper.GUI.CreateStyledButton(content, "Reset", 80, 24)
    resetBtn:SetPoint("TOPLEFT", testBtn, "TOPRIGHT", 10, 0)
    resetBtn:GetFontString():SetTextColor(0.7, 0.7, 0.7)

    local xSlider = whisper.GUI.CreateCustomSlider(content, "X Offset", -50, 50, 1,
        function() return math.floor(db.offsetX + 0.5) end,
        function(val) db.offsetX = val if self.UpdateSettings then self:UpdateSettings() end end
    )
    xSlider:SetPoint("TOPLEFT", 0, yStart)

    local ySlider = whisper.GUI.CreateCustomSlider(content, "Y Offset", -50, 50, 1,
        function() return math.floor(db.offsetY + 0.5) end,
        function(val) db.offsetY = val if self.UpdateSettings then self:UpdateSettings() end end
    )
    ySlider:SetPoint("TOPLEFT", 0, yStart - 60)

    local soundBtn = whisper.GUI.CreateStyledButton(content, "", 140, 24)
    soundBtn:SetPoint("TOPLEFT", 0, yStart - 120)

    local function UpdateSoundText()
        if db.soundEnabled then
            soundBtn:SetText("Sound Alert: ON")
            soundBtn:GetFontString():SetTextColor(0.5, 0.5, 1)
        else
            soundBtn:SetText("Sound Alert: OFF")
            soundBtn:GetFontString():SetTextColor(0.6, 0.6, 0.6)
        end
    end
    UpdateSoundText()

    soundBtn:SetScript("OnClick", function()
        db.soundEnabled = not db.soundEnabled
        UpdateSoundText()
        if self.UpdateSettings then self:UpdateSettings() end
    end)

    resetBtn:SetScript("OnClick", function()
        if self.ResetDefaults then
            self:ResetDefaults()
            if xSlider and xSlider.UpdateVisuals then xSlider.UpdateVisuals(math.floor(db.offsetX + 0.5)) end
            if ySlider and ySlider.UpdateVisuals then ySlider.UpdateVisuals(math.floor(db.offsetY + 0.5)) end
            UpdateSoundText()
        end
    end)
end
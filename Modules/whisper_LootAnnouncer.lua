local addonName, whisper = ...
local LootAnnouncer = {}
LootAnnouncer.enabled = true
LootAnnouncer.isTestMode = false
LootAnnouncer.displayName = "Loot Announcer"
whisper:RegisterModule("Loot Announcer", LootAnnouncer)

-- =========================================================================
-- CONSTANTS & AESTHETICS
-- =========================================================================
local STANDARD_FONT = "Fonts\\FRIZQT__.TTF"
local BAR_TEXTURE = "Interface\\AddOns\\whisper\\Media\\whisperBar.tga"

local ROW_HEIGHT = 38
local ANCHOR_HEIGHT = 12
local ROW_SPACING = 1
local WIDTH_NORMAL = 260
local MAX_VISIBLE = 6

-- Colors
local BG_COLOR = {0.031, 0.031, 0.031, 0.9}
local BORDER_COLOR = {0, 0, 0, 1}

-- State & Config
local config = {
    coloredName = true,
    showOthers = true,
    showTime = 10,
}

local containerFrame
local anchorFrame
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
    if not config.coloredName or not quality then return itemName end
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
    containerFrame:ClearAllPoints()
    containerFrame:SetPoint("TOPLEFT", UIParent, "CENTER", db.offsetX, db.offsetY)
end

local function CreateInterface()
    if containerFrame then return end

    containerFrame = CreateFrame("Frame", "whisperLootAnnouncerFrame", UIParent, "BackdropTemplate")
    containerFrame:SetSize(WIDTH_NORMAL, 1)
    containerFrame:SetClampedToScreen(true)
    containerFrame:SetMovable(true)

    anchorFrame = CreateFrame("Frame", nil, containerFrame, "BackdropTemplate")
    anchorFrame:SetSize(WIDTH_NORMAL - 20, ANCHOR_HEIGHT)
    anchorFrame:SetPoint("TOP", containerFrame, "TOP", 0, 0)
    anchorFrame:SetBackdrop({
        bgFile = BAR_TEXTURE,
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    anchorFrame:SetBackdropColor(0.031, 0.031, 0.031, 0.9)
    anchorFrame:SetBackdropBorderColor(0, 0, 0, 1)
    anchorFrame:EnableMouse(false)
    anchorFrame:SetMovable(true)
    anchorFrame:RegisterForDrag("LeftButton")
    anchorFrame:Hide()

    local anchorText = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    anchorText:SetPoint("CENTER", 0, 1)
    anchorText:SetFont(STANDARD_FONT, 12)
    anchorText:SetText("ANCHOR")
    anchorText:SetTextColor(1, 1, 1)

    anchorFrame:SetScript("OnDragStart", function() containerFrame:StartMoving() end)
    anchorFrame:SetScript("OnDragStop", function()
        containerFrame:StopMovingOrSizing()
        local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
        if sw > 0 and sh > 0 then
            local left = containerFrame:GetLeft()
            local top = containerFrame:GetTop()
            whisperDB.lootAnnouncer.offsetX = left - (sw / 2)
            whisperDB.lootAnnouncer.offsetY = top - (sh / 2)
        end
    end)

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

function LootAnnouncer:UpdatePositions()
    local yOffset = ANCHOR_HEIGHT + ROW_SPACING
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

    frame.expirationTime = data.isTest and (GetTime() + 10) or (GetTime() + config.showTime)
    table.insert(activeAnnouncements, frame)

    if #activeAnnouncements > MAX_VISIBLE then
        for _, f in ipairs(activeAnnouncements) do
            if f:IsShown() and not f.animOut:IsPlaying() then
                f.animOut:Play()
                break
            end
        end
    end

    -- Play sound if not in test mode AND sound is enabled in settings
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
    if not whisperDB.lootAnnouncer then whisperDB.lootAnnouncer = {} end
    local db = whisperDB.lootAnnouncer
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()

    db.offsetX = (10 / 100) * sw
    db.offsetY = (10 / 100) * sh
    db.soundEnabled = true -- Reset sound back to default ON

    self:UpdateSettings()
end


-- =========================================================================
-- EVENTS & CHAT
-- =========================================================================

local function HandleRaidMessage(message)
    -- OUT OF COMBAT GUARD
    if inCombat then return end

    -- HARDENED FOR 12.0: Wrap the chat parsing in a pcall to prevent Secret String crashes
    local ok, playerName, itemLink = pcall(string.match, message, "(%S+) was awarded with (|c.-|r) for")

    -- If it's a secret string or doesn't match the format, safely ignore it
    if not ok or not playerName or not itemLink then return end

    local simpleName = strsplit("-", playerName)
    local mine = UnitIsUnit("player", simpleName)
    if not mine and not config.showOthers then return end

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
    if not whisperDB.lootAnnouncer then whisperDB.lootAnnouncer = {} end
    local db = whisperDB.lootAnnouncer
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()

    if db.offsetX == nil then db.offsetX = (10 / 100) * sw end
    if db.offsetY == nil then db.offsetY = (10 / 100) * sh end
    if db.soundEnabled == nil then db.soundEnabled = true end

    CreateInterface()
    UpdateContainerPosition()
    if containerFrame then containerFrame:Show() end

    -- Safe Event Registration
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

    -- Safe Ticker Creation
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
    self.enabled = false

    -- 1. Stop listening for chat messages immediately
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end

    -- 2. Stop the expiration loop
    if self.expirationTicker then
        self.expirationTicker:Cancel()
        self.expirationTicker = nil
    end

    -- 3. Kill Test Mode if they disabled the module while testing
    if self.isTestMode then
        self:ToggleTestMode()
    end

    -- 4. Hide the frame and sweep all current visual notifications away
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
    -- Block test mode if module is disabled
    if not self.enabled then
        self.isTestMode = false
        return
    end

    self.isTestMode = not self.isTestMode
    if not containerFrame then CreateInterface() end

    if self.isTestMode then
        anchorFrame:Show()
        anchorFrame:EnableMouse(true)

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
                    key = "TEST_" .. GetTime(),
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
        anchorFrame:Hide()
        anchorFrame:EnableMouse(false)
        if testTicker then testTicker:Cancel() testTicker = nil end

        for i = #activeAnnouncements, 1, -1 do
            local frame = activeAnnouncements[i]
            if frame.data and frame.data.isTest then
                frame.animOut:Play()
            end
        end
    end
end

function LootAnnouncer:HandleCommand(args)
    local cmd = args[1] or ""
    if cmd == "test" then
        self:ToggleTestMode()
    end
end
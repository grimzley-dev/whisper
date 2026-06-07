local addonName, whisper = ...

-- Migrate legacy Death Tracker saved data
if whisperDB then
    if whisperDB.deathTracker and not whisperDB.combatTexts then
        whisperDB.combatTexts = whisperDB.deathTracker
        if whisperDB.combatTexts.offsetX and not whisperDB.combatTexts.Position then
            local sw = UIParent and UIParent:GetWidth() or 1920
            local sh = UIParent and UIParent:GetHeight() or 1080
            whisperDB.combatTexts.Position = {
                AnchorFrom = "CENTER",
                AnchorTo = "CENTER",
                XOffset = math.floor((whisperDB.combatTexts.offsetX or 0) / 100 * sw + 0.5),
                YOffset = math.floor((whisperDB.combatTexts.offsetY or 7) / 100 * sh + 0.5),
            }
        end
    end
    if whisperDB.modules and whisperDB.modules["Death Tracker"] ~= nil and whisperDB.modules["Combat Texts"] == nil then
        whisperDB.modules["Combat Texts"] = whisperDB.modules["Death Tracker"]
    end
end

local CombatTexts = {}
CombatTexts.enabled = true
CombatTexts.isTestMode = false
CombatTexts.displayName = "Combat Texts"
CombatTexts.dbKey = "combatTexts"

CombatTexts.defaults = {
    limit = 5,
    duration = 2.5,
    spacing = 4,
    positionVersion = 1,
    EnterCombat = {
        Enabled = true,
        Text = "+Combat",
        Color = { 230 / 255, 230 / 255, 230 / 255, 1 },
    },
    ExitCombat = {
        Enabled = true,
        Text = "-Combat",
        Color = { 124 / 255, 124 / 255, 124 / 255, 1 },
    },
    LowDurability = {
        Enabled = true,
        Text = "LOW DURABILITY",
        Color = { 1, 0.3, 0.3, 1 },
        Threshold = 15,
    },
    PartyDeath = {
        Enabled = true,
    },
}

whisper:RegisterModule("Combat Texts", CombatTexts)

-- =========================
-- Locals
-- =========================
local UnitName = UnitName
local UnitClass = UnitClass
local UnitGUID = UnitGUID
local UnitIsUnit = UnitIsUnit
local UnitIsDead = UnitIsDead
local UnitInParty = UnitInParty
local UnitInRaid = UnitInRaid
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local C_ClassColor = C_ClassColor
local C_Timer = C_Timer
local UIFrameFadeOut = UIFrameFadeOut
local UIFrameFadeRemoveFrame = UIFrameFadeRemoveFrame
local InCombatLockdown = InCombatLockdown
local GetInventoryItemDurability = GetInventoryItemDurability
local format = string.format
local ipairs = ipairs
local math_floor = math.floor
local math_max = math.max
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local issecretvalue = issecretvalue

local STANDARD_FONT = whisper.Style.STANDARD_FONT
local FONT_SIZE = 16
local HOLD_TIME = 4.0
local FADE_TIME = 1.0
local RESET_WINDOW = 5.0

local MESSAGE_TYPES = { "enterCombat", "exitCombat", "lowDurability", "partyDeath" }
local LINE_HEIGHT = FONT_SIZE
local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local ENTER_TEXT = "+Combat"
local ENTER_COLOR = { 230 / 255, 230 / 255, 230 / 255, 1 }
local EXIT_TEXT = "-Combat"
local EXIT_COLOR = { 124 / 255, 124 / 255, 124 / 255, 1 }
local MIN_FRAME_WIDTH = 40
local TEXT_PADDING = 8
local DEFAULT_OFFSET_X_PERCENT = 0
local DEFAULT_OFFSET_Y_PERCENT = 7

local container
local testOverlayCtrl
local measureFS
local messageFrames = {}
local activeMessages = {}
local eventFrame
local inCombat = false
local recentDeaths = 0
local resetTimer = nil
local deathVisibleUntil = 0
local deathHideTimer = nil
local durabilityPending = false
local announcedDeadUnits = {}

-- =========================
-- Position / layout
-- =========================
local function GetDefaultPosition()
    local sw = UIParent and UIParent:GetWidth() or 1920
    local sh = UIParent and UIParent:GetHeight() or 1080
    return {
        AnchorFrom = "CENTER",
        AnchorTo = "CENTER",
        XOffset = math_floor((DEFAULT_OFFSET_X_PERCENT / 100) * sw + 0.5),
        YOffset = math_floor((DEFAULT_OFFSET_Y_PERCENT / 100) * sh + 0.5),
    }
end

local function EnsurePositionDefaults(db)
    if not db then return end
    if (db.positionVersion or 0) < 1 or not db.Position then
        db.Position = GetDefaultPosition()
        db.positionVersion = 1
    end
end

local function ApplyFramePosition(frame, pos)
    if not frame or not pos then return end
    frame:ClearAllPoints()
    frame:SetPoint(
        pos.AnchorFrom or "CENTER",
        UIParent,
        pos.AnchorTo or "CENTER",
        pos.XOffset or 0,
        pos.YOffset or 0
    )
end

local function GetLineSpacing()
    return whisperDB.combatTexts and whisperDB.combatTexts.spacing or 4
end

local function StripColorCodes(text)
    if not text then return "" end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function MeasureTextWidth(text)
    if not measureFS then return MIN_FRAME_WIDTH end
    measureFS:SetText(StripColorCodes(text))
    return measureFS:GetStringWidth() or 0
end

local function ApplyCombatTextStyles(db)
    if not db then return end
    db.EnterCombat = db.EnterCombat or {}
    db.EnterCombat.Text = ENTER_TEXT
    db.EnterCombat.Color = { ENTER_COLOR[1], ENTER_COLOR[2], ENTER_COLOR[3], ENTER_COLOR[4] }
    db.ExitCombat = db.ExitCombat or {}
    db.ExitCombat.Text = EXIT_TEXT
    db.ExitCombat.Color = { EXIT_COLOR[1], EXIT_COLOR[2], EXIT_COLOR[3], EXIT_COLOR[4] }
end

local function GetMessageConfig(db, msgType)
    if msgType == "enterCombat" then
        local cfg = db.EnterCombat or {}
        return cfg.Enabled ~= false, ENTER_TEXT, ENTER_COLOR
    elseif msgType == "exitCombat" then
        local cfg = db.ExitCombat or {}
        return cfg.Enabled ~= false, EXIT_TEXT, EXIT_COLOR
    elseif msgType == "lowDurability" then
        local cfg = db.LowDurability or {}
        return cfg.Enabled ~= false, cfg.Text or "LOW DURABILITY", cfg.Color or { 1, 0.3, 0.3, 1 }
    elseif msgType == "partyDeath" then
        local cfg = db.PartyDeath or {}
        return cfg.Enabled ~= false, nil, nil
    end
    return false, "", { 1, 1, 1, 1 }
end

function CombatTexts:ArrangeMessages()
    if not container then return end
    local spacing = GetLineSpacing()
    local yOffset = 0

    for _, msgType in ipairs(MESSAGE_TYPES) do
        local frame = messageFrames[msgType]
        if frame and frame:IsShown() then
            if frame._lastYOffset ~= yOffset then
                frame:ClearAllPoints()
                frame:SetPoint("TOP", container, "TOP", 0, -yOffset)
                frame._lastYOffset = yOffset
            end
            yOffset = yOffset + frame:GetHeight() + spacing
        end
    end

    local newHeight = math_max(LINE_HEIGHT, yOffset > 0 and (yOffset - spacing) or LINE_HEIGHT)
    local maxWidth = MIN_FRAME_WIDTH

    for _, msgType in ipairs(MESSAGE_TYPES) do
        local frame = messageFrames[msgType]
        if frame and frame:IsShown() then
            local textWidth = MIN_FRAME_WIDTH
            if frame.text then
                textWidth = frame.text:GetStringWidth() or MeasureTextWidth(frame.text:GetText())
            elseif frame._widestText then
                textWidth = MeasureTextWidth(frame._widestText)
            end
            local frameWidth = math_max(math_floor(textWidth + TEXT_PADDING), MIN_FRAME_WIDTH)
            frame:SetWidth(frameWidth)
            maxWidth = math_max(maxWidth, frameWidth)
        end
    end

    if container._lastHeight ~= newHeight or container._lastWidth ~= maxWidth then
        container:SetHeight(newHeight)
        container:SetWidth(maxWidth)
        container._lastWidth = maxWidth
        container._lastHeight = newHeight
    end

    if self.isTestMode then
        self:UpdateTestOverlay()
    end
end

function CombatTexts:CreateContainer()
    if container then return end
    container = CreateFrame("Frame", "WhisperCombatTextsContainer", UIParent)
    container:SetSize(MIN_FRAME_WIDTH, LINE_HEIGHT)
    container:SetFrameStrata("DIALOG")
    container:SetFrameLevel(100)
    container:SetClampedToScreen(true)

    measureFS = container:CreateFontString(nil, "ARTWORK")
    measureFS:SetFont(STANDARD_FONT, FONT_SIZE, "OUTLINE")
    measureFS:Hide()

    ApplyFramePosition(container, whisperDB.combatTexts.Position)
end

function CombatTexts:EnsureTestOverlay()
    if testOverlayCtrl then return end

    testOverlayCtrl = whisper.TestOverlay.Create({
        name = "WhisperCombatTextsOverlay",
        label = "Combat Texts",
        container = function() return container end,
        isActive = function() return CombatTexts.isTestMode end,
        getContentFrames = function()
            local frames = {}
            for _, frame in pairs(messageFrames) do
                if frame and frame:IsShown() then
                    table.insert(frames, frame)
                end
            end
            return frames
        end,
        dragMode = "center",
        canDrag = function() return not InCombatLockdown() and container end,
        onDragStop = function()
            CombatTexts:SaveDragPosition()
            ApplyFramePosition(container, whisperDB.combatTexts.Position)
            CombatTexts:ArrangeMessages()
        end,
    })
end

function CombatTexts:UpdateTestOverlay()
    if not self.isTestMode or not container then
        if testOverlayCtrl then testOverlayCtrl:Hide() end
        return
    end
    self:EnsureTestOverlay()
    testOverlayCtrl:Update()
end

function CombatTexts:HideTestOverlay()
    if testOverlayCtrl then testOverlayCtrl:Hide() end
end

function CombatTexts:GetMessageFrame(msgType)
    if messageFrames[msgType] then return messageFrames[msgType] end
    if not container then self:CreateContainer() end

    if msgType == "partyDeath" then
        local frame = CreateFrame("Frame", nil, container)
        frame:SetWidth(MIN_FRAME_WIDTH)
        frame:Hide()

        local scroll = CreateFrame("ScrollingMessageFrame", nil, frame)
        scroll:SetAllPoints()
        scroll:SetFont(STANDARD_FONT, FONT_SIZE, "OUTLINE")
        scroll:SetJustifyH("CENTER")
        scroll:SetJustifyV("TOP")
        scroll:SetInsertMode("TOP")
        scroll:SetFadeDuration(FADE_TIME)
        scroll:SetTimeVisible(HOLD_TIME)
        scroll:SetSpacing(GetLineSpacing())
        scroll:SetFading(true)

        frame.scroll = scroll
        frame.msgType = msgType
        messageFrames[msgType] = frame
        return frame
    end

    local frame = CreateFrame("Frame", nil, container)
    frame:SetSize(MIN_FRAME_WIDTH, LINE_HEIGHT)
    frame:Hide()

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetAllPoints(frame)
    text:SetFont(STANDARD_FONT, FONT_SIZE, "OUTLINE")
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")

    frame.text = text
    frame.msgType = msgType
    frame.generation = 0
    messageFrames[msgType] = frame
    return frame
end

function CombatTexts:UpdateDeathFrameSize()
    local frame = messageFrames.partyDeath
    if not frame or not frame.scroll then return end
    local limit = whisperDB.combatTexts.limit or 5
    local spacing = GetLineSpacing()
    local height = (limit * LINE_HEIGHT) + ((limit - 1) * spacing)
    frame:SetHeight(height)
    frame.scroll:SetMaxLines(limit)
    frame.scroll:SetSpacing(spacing)
end

function CombatTexts:PrepareMessage(msgType, overrideText, overrideColor)
    if not self.enabled then return nil end
    if self.isTestMode and not overrideText then return nil end

    local db = whisperDB.combatTexts
    local enabled, msgText, color = GetMessageConfig(db, msgType)
    if not enabled then return nil end

    if overrideText then msgText = overrideText end
    if overrideColor then color = overrideColor end

    local frame = self:GetMessageFrame(msgType)
    if not frame or not frame.text then return nil end

    UIFrameFadeRemoveFrame(frame)
    frame:SetScript("OnUpdate", nil)
    frame.text:SetText(msgText)
    frame.text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    frame:SetAlpha(1)
    frame:Show()
    activeMessages[msgType] = true
    self:ArrangeMessages()
    return frame
end

function CombatTexts:ShowFlashMessage(msgType, overrideText, overrideColor)
    local frame = self:PrepareMessage(msgType, overrideText, overrideColor)
    if not frame then return end

    local duration = whisperDB.combatTexts.duration or 2.5
    frame.generation = (frame.generation or 0) + 1
    local myGeneration = frame.generation

    UIFrameFadeOut(frame, duration, 1, 0)
    C_Timer.After(duration, function()
        if frame.generation == myGeneration and not CombatTexts.isTestMode then
            frame:Hide()
            frame._lastYOffset = nil
            activeMessages[msgType] = nil
            CombatTexts:ArrangeMessages()
        end
    end)
end

function CombatTexts:ShowPersistentMessage(msgType)
    self:PrepareMessage(msgType)
end

function CombatTexts:HidePersistentMessage(msgType)
    local frame = messageFrames[msgType]
    if frame then
        frame:Hide()
        frame._lastYOffset = nil
        activeMessages[msgType] = nil
        self:ArrangeMessages()
    end
end

-- =========================
-- Combat + durability (AES baseline)
-- =========================
function CombatTexts:OnEnterCombat()
    inCombat = true
    self:HidePersistentMessage("lowDurability")
    self:ShowFlashMessage("enterCombat")
end

function CombatTexts:OnExitCombat()
    inCombat = false
    self:ShowFlashMessage("exitCombat")
    self:CheckDurability()
end

function CombatTexts:CheckDurability()
    if not self.enabled or self.isTestMode then return end
    if durabilityPending then return end
    durabilityPending = true
    C_Timer.After(0.5, function()
        durabilityPending = false
        CombatTexts:DoCheckDurability()
    end)
end

function CombatTexts:DoCheckDurability()
    if not self.enabled or self.isTestMode then return end

    local db = whisperDB.combatTexts
    local cfg = db.LowDurability or {}
    if cfg.Enabled == false then
        self:HidePersistentMessage("lowDurability")
        return
    end

    if inCombat then
        self:HidePersistentMessage("lowDurability")
        return
    end

    local threshold = (cfg.Threshold or 15) / 100
    local hasLow = false
    for _, slot in ipairs(EQUIP_SLOTS) do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 and (current / maximum) < threshold then
            hasLow = true
            break
        end
    end

    if hasLow then
        self:ShowPersistentMessage("lowDurability")
    else
        self:HidePersistentMessage("lowDurability")
    end
end

-- =========================
-- Death detection (UNIT_DIED + GUID resolve)
-- =========================
local AnnounceDeath

local function IsSecretValue(value)
    return issecretvalue and issecretvalue(value)
end

local function GUIDsEqual(a, b)
    if not a or not b then return false end
    if IsSecretValue(a) or IsSecretValue(b) then return false end
    return a == b
end

local function ClearAnnouncedDeadUnits()
    announcedDeadUnits = {}
end

local function PruneAnnouncedDeadUnits()
    for unitID in pairs(announcedDeadUnits) do
        local isDead = UnitIsDead(unitID)
        if not IsSecretValue(isDead) and not isDead then
            announcedDeadUnits[unitID] = nil
        end
    end
end

local function GetUnitFromGUID(guid)
    if not guid or IsSecretValue(guid) then return nil end

    if UnitTokenFromGUID then
        local token = UnitTokenFromGUID(guid)
        if token and not IsSecretValue(token) then return token end
    end

    if GUIDsEqual(UnitGUID("player"), guid) then return "player" end

    if IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if GUIDsEqual(UnitGUID(u), guid) then return u end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            if GUIDsEqual(UnitGUID(u), guid) then return u end
        end
    end

    return nil
end

local function IsGUIDInGroup(guid)
    if not guid or IsSecretValue(guid) then return false end
    if GUIDsEqual(UnitGUID("player"), guid) then return true end

    if IsInRaid() then
        for i = 1, 40 do
            if GUIDsEqual(UnitGUID("raid" .. i), guid) then return true end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            if GUIDsEqual(UnitGUID("party" .. i), guid) then return true end
        end
    end

    return false
end

local function TryAnnounceUnitDeath(unitID)
    if not unitID or IsSecretValue(unitID) then return end
    if UnitIsUnit(unitID, "player") then return end
    if announcedDeadUnits[unitID] then return end

    local isDead = UnitIsDead(unitID)
    if IsSecretValue(isDead) then isDead = true end
    if not isDead then return end
    if not UnitInParty(unitID) and not UnitInRaid(unitID) then return end

    local name = UnitName(unitID)
    if not name or IsSecretValue(name) then return end

    local _, classFilename = UnitClass(unitID)
    if IsSecretValue(classFilename) then classFilename = nil end

    announcedDeadUnits[unitID] = true
    AnnounceDeath(name, classFilename)
end

local function ScanPartyForNewDeaths()
    if not IsInGroup() then return end

    PruneAnnouncedDeadUnits()

    if IsInRaid() then
        for i = 1, 40 do
            TryAnnounceUnitDeath("raid" .. i)
        end
    else
        for i = 1, 4 do
            TryAnnounceUnitDeath("party" .. i)
        end
    end
end

local function ResetSpamCounter()
    recentDeaths = 0
    resetTimer = nil
end

local function ScheduleDeathFrameHide()
    if deathHideTimer then C_Timer.CancelTimer(deathHideTimer) end
    deathHideTimer = C_Timer.After(HOLD_TIME + FADE_TIME + 0.15, function()
        deathHideTimer = nil
        if GetTime() < deathVisibleUntil then
            ScheduleDeathFrameHide()
            return
        end
        local frame = messageFrames.partyDeath
        if frame and frame.scroll then
            frame.scroll:Clear()
            frame._widestText = nil
            frame._widestWidth = nil
            frame:Hide()
            frame._lastYOffset = nil
            activeMessages.partyDeath = nil
            CombatTexts:ArrangeMessages()
        end
    end)
end

AnnounceDeath = function(name, classFilename)
    local db = whisperDB.combatTexts
    local limit = db.limit or 5
    if recentDeaths >= limit then return end

    if recentDeaths == 0 then
        if resetTimer then C_Timer.CancelTimer(resetTimer) end
        resetTimer = C_Timer.After(RESET_WINDOW, ResetSpamCounter)
    end
    recentDeaths = recentDeaths + 1

    local classColorStr = "|cffffffff"
    if classFilename and not IsSecretValue(classFilename) then
        local color = C_ClassColor.GetClassColor(classFilename)
        if color then classColorStr = "|c" .. color:GenerateHexColor() end
    end

    local frame = messageFrames.partyDeath
    if not frame then
        CombatTexts:GetMessageFrame("partyDeath")
        CombatTexts:UpdateDeathFrameSize()
        frame = messageFrames.partyDeath
    end
    if not frame or not frame.scroll then return end

    local msg = format("%s%s|r died", classColorStr, name or "Unknown")
    local plainWidth = MeasureTextWidth(format("%s died", name or "Unknown"))
    if not frame._widestWidth or plainWidth > frame._widestWidth then
        frame._widestWidth = plainWidth
        frame._widestText = format("%s died", name or "Unknown")
    end

    frame.scroll:AddMessage(msg)
    frame:Show()
    activeMessages.partyDeath = true
    deathVisibleUntil = GetTime() + HOLD_TIME + FADE_TIME
    CombatTexts:ArrangeMessages()
    ScheduleDeathFrameHide()
end

local function ResolveDeathInfo(deadGUID)
    if IsSecretValue(deadGUID) then
        ScanPartyForNewDeaths()
        return
    end

    local unitID = GetUnitFromGUID(deadGUID)
    if unitID and not IsSecretValue(unitID) then
        TryAnnounceUnitDeath(unitID)
        return
    end

    if not IsInGroup() then return end
    if GUIDsEqual(UnitGUID("player"), deadGUID) then return end
    if not IsGUIDInGroup(deadGUID) then return end

    local name, _, _, classFilename = GetPlayerInfoByGUID(deadGUID)
    if not name or IsSecretValue(name) then return end
    if IsSecretValue(classFilename) then classFilename = nil end

    AnnounceDeath(name, classFilename)
end

function CombatTexts:OnUnitDied(_, deadGUID)
    if not self.enabled or self.isTestMode then return end
    if not IsInGroup() then return end
    local enabled = select(1, GetMessageConfig(whisperDB.combatTexts, "partyDeath"))
    if not enabled then return end
    ResolveDeathInfo(deadGUID)
end

-- =========================
-- Test mode
-- =========================
function CombatTexts:RebuildTestDeaths()
    if not self.isTestMode then return end

    local db = whisperDB.combatTexts
    local deathFrame = self:GetMessageFrame("partyDeath")
    if not deathFrame or not deathFrame.scroll then return end

    self:UpdateDeathFrameSize()

    deathFrame.scroll:SetFadeDuration(0)
    deathFrame.scroll:SetTimeVisible(9999)
    deathFrame.scroll:Clear()

    deathFrame._widestText = nil
    deathFrame._widestWidth = 0

    local name = UnitName("player") or "Player"
    local _, classFilename = UnitClass("player")
    local color = C_ClassColor.GetClassColor(classFilename or "PRIEST")
    local colorStr = color and ("|c" .. color:GenerateHexColor()) or "|cffffffff"
    local limit = db.limit or 5

    for i = 1, limit do
        local plain = format("%s died (%d)", name, i)
        local msg = format("%s%s|r died (%d)", colorStr, name, i)
        local plainWidth = MeasureTextWidth(plain)
        if plainWidth > (deathFrame._widestWidth or 0) then
            deathFrame._widestWidth = plainWidth
            deathFrame._widestText = plain
        end
        deathFrame.scroll:AddMessage(msg)
    end

    deathFrame:Show()
    activeMessages.partyDeath = true
end

function CombatTexts:SaveDragPosition()
    if not container then return end
    local db = whisperDB.combatTexts
    db.Position = db.Position or {}

    local anchorFrom = db.Position.AnchorFrom or "CENTER"
    local anchorTo = db.Position.AnchorTo or "CENTER"
    local left, bottom, width, height = container:GetRect()
    if not left then return end

    local frameAnchorX = left + width / 2
    local frameAnchorY = bottom + height / 2

    if anchorFrom:find("LEFT") then
        frameAnchorX = left
    elseif anchorFrom:find("RIGHT") then
        frameAnchorX = left + width
    end
    if anchorFrom:find("TOP") then
        frameAnchorY = bottom + height
    elseif anchorFrom:find("BOTTOM") then
        frameAnchorY = bottom
    end

    local parentLeft, parentBottom, parentWidth, parentHeight = UIParent:GetRect()
    if not parentLeft then
        parentLeft, parentBottom = 0, 0
        parentWidth, parentHeight = UIParent:GetWidth(), UIParent:GetHeight()
    end

    local finalX, finalY
    if anchorTo:find("LEFT") then
        finalX = frameAnchorX - parentLeft
    elseif anchorTo:find("RIGHT") then
        finalX = frameAnchorX - (parentLeft + parentWidth)
    else
        finalX = frameAnchorX - (parentLeft + parentWidth / 2)
    end

    if anchorTo:find("TOP") then
        finalY = frameAnchorY - (parentBottom + parentHeight)
    elseif anchorTo:find("BOTTOM") then
        finalY = frameAnchorY - parentBottom
    else
        finalY = frameAnchorY - (parentBottom + parentHeight / 2)
    end

    db.Position.AnchorFrom = anchorFrom
    db.Position.AnchorTo = anchorTo
    db.Position.XOffset = math_floor(finalX + 0.5)
    db.Position.YOffset = math_floor(finalY + 0.5)
end

function CombatTexts:ShowTestPreview()
    local db = whisperDB.combatTexts
    container:Show()

    for _, msgType in ipairs({ "enterCombat", "exitCombat", "lowDurability" }) do
        local enabled, msgText, msgColor = GetMessageConfig(db, msgType)
        if enabled then
            local frame = self:GetMessageFrame(msgType)
            frame.text:SetText(msgText)
            frame.text:SetTextColor(msgColor[1], msgColor[2], msgColor[3], msgColor[4] or 1)
            frame:SetAlpha(1)
            frame:Show()
            activeMessages[msgType] = true
        end
    end

    self:RebuildTestDeaths()
    self:ArrangeMessages()
    self:UpdateTestOverlay()
end

function CombatTexts:HideTestPreview()
    for msgType, frame in pairs(messageFrames) do
        if frame.scroll then
            frame.scroll:Clear()
            frame.scroll:SetFadeDuration(FADE_TIME)
            frame.scroll:SetTimeVisible(HOLD_TIME)
        end
        frame:Hide()
        frame._lastYOffset = nil
    end
    activeMessages = {}
    self:HideTestOverlay()
    self:ArrangeMessages()
end

function CombatTexts:ToggleTestMode()
    if not container then self:CreateContainer() end

    self.isTestMode = not self.isTestMode

    if self.isTestMode then
        self:ShowTestPreview()
    else
        self:HideTestPreview()
        self:ApplySettings()
        if not inCombat then
            self:DoCheckDurability()
        end
    end
end

-- =========================
-- Settings
-- =========================
function CombatTexts:ApplySettings()
    if not container then return end
    ApplyFramePosition(container, whisperDB.combatTexts.Position)
    self:UpdateDeathFrameSize()
    self:ArrangeMessages()
end

function CombatTexts:ResetDefaults()
    for k, v in pairs(self.defaults) do
        if type(v) == "table" then
            whisperDB.combatTexts[k] = whisperDB.combatTexts[k] or {}
            for sk, sv in pairs(v) do
                whisperDB.combatTexts[k][sk] = sv
            end
        else
            whisperDB.combatTexts[k] = v
        end
    end
    whisperDB.combatTexts.Position = GetDefaultPosition()
    whisperDB.combatTexts.positionVersion = 1
    ApplyCombatTextStyles(whisperDB.combatTexts)
    self:ApplySettings()
end

-- =========================
-- Init / Disable
-- =========================
function CombatTexts:Init()
    self.enabled = true
    ApplyCombatTextStyles(whisperDB.combatTexts)
    EnsurePositionDefaults(whisperDB.combatTexts)
    self:CreateContainer()

    for _, msgType in ipairs(MESSAGE_TYPES) do
        self:GetMessageFrame(msgType)
    end
    self:UpdateDeathFrameSize()

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event, ...)
            if not CombatTexts.enabled then return end
            if CombatTexts.isTestMode then return end

            if event == "UNIT_DIED" then
                CombatTexts:OnUnitDied(nil, ...)
            elseif event == "PLAYER_REGEN_DISABLED" then
                CombatTexts:OnEnterCombat()
            elseif event == "PLAYER_REGEN_ENABLED" then
                CombatTexts:OnExitCombat()
            elseif event == "UPDATE_INVENTORY_DURABILITY" then
                CombatTexts:CheckDurability()
            elseif event == "GROUP_ROSTER_UPDATE" then
                recentDeaths = 0
                ClearAnnouncedDeadUnits()
                if resetTimer then C_Timer.CancelTimer(resetTimer) end
                resetTimer = nil
            elseif event == "PLAYER_ENTERING_WORLD" then
                recentDeaths = 0
                ClearAnnouncedDeadUnits()
                if resetTimer then C_Timer.CancelTimer(resetTimer) end
                resetTimer = nil
                CombatTexts:ApplySettings()
            end
        end)
    end

    eventFrame:RegisterEvent("UNIT_DIED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    inCombat = InCombatLockdown()
    self:ApplySettings()
    container:Show()

    C_Timer.After(0.5, function()
        if not inCombat then
            CombatTexts:DoCheckDurability()
        end
    end)
end

function CombatTexts:Disable()
    self.enabled = false

    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end

    if self.isTestMode then
        self:HideTestPreview()
        self.isTestMode = false
    end

    for _, frame in pairs(messageFrames) do
        frame:Hide()
    end
    activeMessages = {}
    inCombat = false

    if container then
        container:Hide()
    end
end

-- =========================
-- Config Panel UI
-- =========================
function CombatTexts:BuildOptionsPanel(content, toggleBtn)
    local db = whisperDB.combatTexts
    local yStart = -80

    local testBtn = whisper.GUI.CreateStyledButton(content, "Test", 80, 24)
    testBtn:SetPoint("TOPLEFT", toggleBtn, "TOPRIGHT", 10, 0)
    testBtn:GetFontString():SetTextColor(1, 1, 1)
    testBtn:SetScript("OnClick", function()
        if self.ToggleTestMode then
            self:ToggleTestMode()
            if self.isTestMode then
                testBtn:SetText("End")
                testBtn:GetFontString():SetTextColor(1, 0.2, 0.2)
            else
                testBtn:SetText("Test")
                testBtn:GetFontString():SetTextColor(1, 1, 1)
            end
        end
    end)
    self.testButton = testBtn

    local resetBtn = whisper.GUI.CreateStyledButton(content, "Reset", 80, 24)
    resetBtn:SetPoint("TOPLEFT", testBtn, "TOPRIGHT", 10, 0)
    resetBtn:GetFontString():SetTextColor(0.7, 0.7, 0.7)

    local sliderRefs = {}

    EnsurePositionDefaults(db)
    local xSlider = whisper.GUI.CreateCustomSlider(content, "X Offset", -50, 50, 1,
        function()
            local sw = UIParent:GetWidth()
            if not sw or sw == 0 then return 0 end
            return math.floor(((db.Position.XOffset or 0) / sw) * 100 + 0.5)
        end,
        function(val)
            local sw = UIParent:GetWidth()
            if not sw or sw == 0 then return end
            db.Position.XOffset = (val / 100) * sw
            if self.ApplySettings then self:ApplySettings() end
        end
    )
    xSlider:SetPoint("TOPLEFT", 0, yStart)
    sliderRefs.xSlider = xSlider

    local ySlider = whisper.GUI.CreateCustomSlider(content, "Y Offset", -50, 50, 1,
        function()
            local sh = UIParent:GetHeight()
            if not sh or sh == 0 then return 0 end
            return math.floor(((db.Position.YOffset or 0) / sh) * 100 + 0.5)
        end,
        function(val)
            local sh = UIParent:GetHeight()
            if not sh or sh == 0 then return end
            db.Position.YOffset = (val / 100) * sh
            if self.ApplySettings then self:ApplySettings() end
        end
    )
    ySlider:SetPoint("TOPLEFT", 0, yStart - 60)
    sliderRefs.ySlider = ySlider

    local limitSlider = whisper.GUI.CreateCustomSlider(content, "Death Limit", 1, 20, 1,
        function() return db.limit end,
        function(val)
            db.limit = val
            if self.isTestMode and self.RebuildTestDeaths then
                self:RebuildTestDeaths()
            elseif self.UpdateDeathFrameSize then
                self:UpdateDeathFrameSize()
            end

            if self.ArrangeMessages then
                self:ArrangeMessages()
            end
        end
    )
    limitSlider:SetPoint("TOPLEFT", 0, yStart - 120)
    sliderRefs.limitSlider = limitSlider

    resetBtn:SetScript("OnClick", function()
        if self.ResetDefaults then
            self:ResetDefaults()
            if sliderRefs.xSlider and sliderRefs.xSlider.UpdateVisuals then
                sliderRefs.xSlider.UpdateVisuals(math.floor(((db.Position.XOffset or 0) / (UIParent:GetWidth() or 1)) * 100 + 0.5))
            end
            if sliderRefs.ySlider and sliderRefs.ySlider.UpdateVisuals then
                sliderRefs.ySlider.UpdateVisuals(math.floor(((db.Position.YOffset or 0) / (UIParent:GetHeight() or 1)) * 100 + 0.5))
            end
            if sliderRefs.limitSlider and sliderRefs.limitSlider.UpdateVisuals then
                sliderRefs.limitSlider.UpdateVisuals(db.limit)
            end
        end
    end)
end

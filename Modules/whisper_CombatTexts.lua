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
CombatTexts.isAnchorMode = false
CombatTexts.isDeathAnimTestMode = false
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
local UIFrameFadeIn = UIFrameFadeIn
local UIFrameFadeOut = UIFrameFadeOut
local UIFrameFadeRemoveFrame = UIFrameFadeRemoveFrame
local InCombatLockdown = InCombatLockdown
local GetInventoryItemDurability = GetInventoryItemDurability
local format = string.format
local ipairs = ipairs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_abs = math.abs
local math_exp = math.exp
local GetTime = GetTime
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local issecretvalue = issecretvalue

local STANDARD_FONT = whisper.Style.STANDARD_FONT
local FONT_SIZE = 16
local HOLD_TIME = 4.0
local FADE_TIME = 1.0

local MESSAGE_TYPES = { "enterCombat", "exitCombat", "lowDurability", "partyDeath" }
local LINE_HEIGHT = FONT_SIZE
local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local ENTER_TEXT = "+Combat"
local ENTER_COLOR = { 230 / 255, 230 / 255, 230 / 255, 1 }
local EXIT_TEXT = "-Combat"
local EXIT_COLOR = { 124 / 255, 124 / 255, 124 / 255, 1 }
local MIN_FRAME_WIDTH = 40
local TEXT_PADDING = 8
local DEATH_LINE_SPACING = 2
local DEATH_FADE_IN = 0.35
local DEATH_FADE_OUT = 0.65
local DEATH_FADE_OUT_FAST = 0.22
local DEATH_SLIDE_IN = 14
local DEATH_SCROLL_LERP = 16
local TEST_DEATH_INTERVAL = 1.8
local MAX_DEATH_LINES = 20
local DEFAULT_OFFSET_X_PERCENT = 0
local DEFAULT_OFFSET_Y_PERCENT = 7

local container
local testOverlayCtrl
local measureFS
local messageFrames = {}
local activeMessages = {}
local eventFrame
local inCombat = false
local deathVisibleUntil = 0
local durabilityPending = false
local announcedDeadUnits = {}
local testDeathTimer
local testDeathCounter = 0

local ANCHOR_PLACEHOLDER_DEATHS = {
    { name = "Thrall", class = "SHAMAN" },
    { name = "Jaina", class = "MAGE" },
    { name = "Sylvanas", class = "HUNTER" },
    { name = "Tyrande", class = "PRIEST" },
    { name = "Varian", class = "WARRIOR" },
    { name = "Arthas", class = "DEATHKNIGHT" },
    { name = "Illidan", class = "DEMONHUNTER" },
    { name = "Gul'dan", class = "WARLOCK" },
    { name = "Anduin", class = "PRIEST" },
    { name = "Garrosh", class = "WARRIOR" },
    { name = "Vol'jin", class = "SHAMAN" },
    { name = "Rexxar", class = "HUNTER" },
    { name = "Khadgar", class = "MAGE" },
    { name = "Velen", class = "PRIEST" },
    { name = "Baine", class = "WARRIOR" },
    { name = "Lor'themar", class = "HUNTER" },
    { name = "Genn", class = "WARRIOR" },
    { name = "Malfurion", class = "DRUID" },
    { name = "Uther", class = "PALADIN" },
    { name = "Rokhan", class = "ROGUE" },
}

local function IsPreviewActive()
    return CombatTexts.isAnchorMode or CombatTexts.isDeathAnimTestMode
end

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

local function FormatClassColoredText(classFilename, text)
    if not text or not classFilename or not C_ClassColor then return text end
    local color = C_ClassColor.GetClassColor(classFilename)
    if not color or not color.r then return text end
    return format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, text)
end

local function FormatDeathMessage(name, classFilename)
    return FormatClassColoredText(classFilename, name or "Unknown") .. " died"
end

local function GetPlaceholderDeath(index)
    return ANCHOR_PLACEHOLDER_DEATHS[((index - 1) % #ANCHOR_PLACEHOLDER_DEATHS) + 1]
end

local function GetDeathLimit()
    return whisperDB.combatTexts and whisperDB.combatTexts.limit or 5
end

local function GetSortedDeathEntries(frame)
    local sorted = {}
    for _, entry in ipairs(frame.entries) do
        table.insert(sorted, entry)
    end
    table.sort(sorted, function(a, b)
        return (a.slotIndex or 0) < (b.slotIndex or 0)
    end)
    return sorted
end

local EnsureDeathAnimator

local function ForceDeathEntryOut(frame, entry, fast)
    if not entry then return end
    entry.generation = (entry.generation or 0) + 1
    entry.fadeState = "out"
    entry.fadeOutDuration = fast and DEATH_FADE_OUT_FAST or DEATH_FADE_OUT
    EnsureDeathAnimator(frame)
end

local function EnforceDeathLimitBeforeAdd(frame)
    local limit = GetDeathLimit()
    local excess = #frame.entries - limit + 1
    if excess <= 0 then return end

    local sorted = GetSortedDeathEntries(frame)
    for i = 1, excess do
        if sorted[i] then
            ForceDeathEntryOut(frame, sorted[i], true)
        end
    end
end

local function EnforceDeathLimit(frame)
    local limit = GetDeathLimit()
    local excess = #frame.entries - limit
    if excess <= 0 then return end

    local sorted = GetSortedDeathEntries(frame)
    for i = 1, excess do
        local oldest = sorted[i]
        if oldest and oldest.fadeState ~= "out" then
            ForceDeathEntryOut(frame, oldest, true)
        elseif oldest then
            oldest.fadeOutDuration = DEATH_FADE_OUT_FAST
        end
    end
end

local function GetDeathPitch()
    return LINE_HEIGHT + DEATH_LINE_SPACING
end

local function GetSlotY(slotIndex)
    return -((slotIndex - 1) * GetDeathPitch())
end

local function CompactDeathSlots(frame)
    if not frame.entries or #frame.entries == 0 then return end
    local sorted = GetSortedDeathEntries(frame)
    for i, entry in ipairs(sorted) do
        if entry.slotIndex ~= i then
            entry.slotIndex = i
            entry.targetOffsetY = GetSlotY(i)
            EnsureDeathAnimator(frame)
        end
    end
    frame.entries = sorted
end

local function ExpLerp(current, target, elapsed, speed)
    local t = 1 - math_exp(-speed * elapsed)
    return current + (target - current) * t
end

local function UpdateDeathFrameWidth(frame)
    if not frame then return end
    local width = MIN_FRAME_WIDTH
    if frame._widestWidth then
        width = math_max(math_floor(frame._widestWidth + TEXT_PADDING), MIN_FRAME_WIDTH)
    end
    frame:SetWidth(width)
end

local function RecalculateWidestDeath(frame)
    frame._widestWidth = 0
    frame._widestText = nil
    if not frame.entries then return end
    for _, entry in ipairs(frame.entries) do
        local width = MeasureTextWidth(entry.plainText)
        if width > (frame._widestWidth or 0) then
            frame._widestWidth = width
            frame._widestText = entry.plainText
        end
    end
end

local function RemoveDeathEntry(frame, entry)
    if not entry or not frame.entries then return end
    entry.generation = (entry.generation or 0) + 1
    entry.fs:Hide()
    entry.fs:SetAlpha(1)
    entry.fs._entry = nil
    for i, e in ipairs(frame.entries) do
        if e == entry then
            table.remove(frame.entries, i)
            break
        end
    end
    RecalculateWidestDeath(frame)
end

local function ClearDeathFrame(frame)
    if not frame then return end
    frame._animatorActive = false
    frame:SetScript("OnUpdate", nil)
    frame._displayHeight = nil
    frame.entries = frame.entries or {}

    for i = #frame.entries, 1, -1 do
        RemoveDeathEntry(frame, frame.entries[i])
    end

    if frame.lines then
        for _, lineFs in ipairs(frame.lines) do
            lineFs._entry = nil
            lineFs:Hide()
            lineFs:SetAlpha(1)
            lineFs:SetText("")
        end
    end

    frame.entries = {}
    frame._widestText = nil
    frame._widestWidth = nil
end

local function EnsureDeathLinePool(frame)
    frame.lines = frame.lines or {}
    local needed = math_max(MAX_DEATH_LINES, GetDeathLimit())
    for i = 1, needed do
        if not frame.lines[i] then
            local fs = frame:CreateFontString(nil, "OVERLAY")
            fs:SetFont(STANDARD_FONT, FONT_SIZE, "OUTLINE")
            fs:SetJustifyH("CENTER")
            fs:SetWordWrap(false)
            fs:Hide()
            frame.lines[i] = fs
        end
    end
end

local function UpdateDeathFrameAnimatedHeight(frame, elapsed)
    local displayHeight = LINE_HEIGHT
    if #frame.entries > 0 then
        local maxBottom = 0
        for _, entry in ipairs(frame.entries) do
            local bottom = -entry.currentOffsetY + LINE_HEIGHT
            if bottom > maxBottom then
                maxBottom = bottom
            end
        end
        displayHeight = math_max(LINE_HEIGHT, maxBottom)
    end

    if not frame._displayHeight then
        frame._displayHeight = displayHeight
    else
        frame._displayHeight = ExpLerp(frame._displayHeight, displayHeight, elapsed, DEATH_SCROLL_LERP)
    end
    frame:SetHeight(frame._displayHeight)
    UpdateDeathFrameWidth(frame)
end

local function IsDeathAnimating(frame)
    for _, entry in ipairs(frame.entries) do
        local targetY = entry.targetOffsetY or GetSlotY(entry.slotIndex or 1)
        if entry.fadeState ~= "idle" then return true end
        if math_abs(entry.currentOffsetY - targetY) > 0.25 then return true end
        if entry.fadeState == "out" and entry.alpha > 0.01 then return true end
        if entry.fadeState == "in" and entry.alpha < 0.99 then return true end
    end
    return false
end

function CombatTexts:UpdateDeathAnimations(frame, elapsed)
    if not frame or not frame.entries then return end

    for _, entry in ipairs(frame.entries) do
        local targetY = entry.targetOffsetY or GetSlotY(entry.slotIndex or 1)
        entry.targetOffsetY = targetY

        if entry.fadeState == "in" then
            entry.alpha = math_min(1, entry.alpha + elapsed / DEATH_FADE_IN)
            if entry.alpha >= 1 then
                entry.alpha = 1
                entry.fadeState = "idle"
            end
        elseif entry.fadeState == "out" then
            local duration = entry.fadeOutDuration or DEATH_FADE_OUT
            entry.alpha = math_max(0, entry.alpha - elapsed / duration)
        end

        entry.currentOffsetY = ExpLerp(entry.currentOffsetY, targetY, elapsed, DEATH_SCROLL_LERP)
        entry.fs:SetAlpha(entry.alpha)
        entry.fs:ClearAllPoints()
        entry.fs:SetPoint("TOP", frame, "TOP", 0, entry.currentOffsetY)
    end

    for i = #frame.entries, 1, -1 do
        local entry = frame.entries[i]
        if entry.fadeState == "out" and entry.alpha <= 0.01 then
            RemoveDeathEntry(frame, entry)
        end
    end

    UpdateDeathFrameAnimatedHeight(frame, elapsed)
    self:ArrangeMessages()

    if not IsDeathAnimating(frame) and #frame.entries == 0 then
        frame._animatorActive = false
        frame:SetScript("OnUpdate", nil)
        frame._displayHeight = nil
        if frame:IsShown() then
            frame:Hide()
            frame._lastYOffset = nil
            activeMessages.partyDeath = nil
            self:ArrangeMessages()
        end
    end
end

EnsureDeathAnimator = function(frame)
    if frame._animatorActive then return end
    frame._animatorActive = true
    frame:SetScript("OnUpdate", function(self, dt)
        CombatTexts:UpdateDeathAnimations(self, dt)
    end)
end

local function ScheduleDeathLineFade(frame, entry)
    entry.generation = (entry.generation or 0) + 1
    local gen = entry.generation
    C_Timer.After(HOLD_TIME, function()
        if entry.generation ~= gen or entry.fadeState ~= "idle" then return end
        ForceDeathEntryOut(frame, entry, false)
    end)
end

local function AddDeathLine(frame, msg, plainText)
    EnsureDeathLinePool(frame)
    EnforceDeathLimitBeforeAdd(frame)

    local fs
    for _, lineFs in ipairs(frame.lines) do
        if not lineFs._entry then
            fs = lineFs
            break
        end
    end
    if not fs then return end

    CompactDeathSlots(frame)

    local newSlot = #frame.entries + 1
    local targetY = GetSlotY(newSlot)
    local entry = {
        fs = fs,
        plainText = plainText,
        generation = 0,
        fadeState = "in",
        alpha = 0,
        slotIndex = newSlot,
        currentOffsetY = targetY - DEATH_SLIDE_IN,
        targetOffsetY = targetY,
    }
    fs._entry = entry
    fs:SetText(msg)
    fs:Show()

    table.insert(frame.entries, entry)

    local plainWidth = MeasureTextWidth(plainText)
    if not frame._widestWidth or plainWidth > frame._widestWidth then
        frame._widestWidth = plainWidth
        frame._widestText = plainText
    end

    EnsureDeathAnimator(frame)
    ScheduleDeathLineFade(frame, entry)
end

local function AddDeathLineStatic(frame, msg, plainText, index)
    EnsureDeathLinePool(frame)
    local fs = frame.lines[index]
    if not fs then return false end

    local targetY = GetSlotY(index)
    local entry = {
        fs = fs,
        plainText = plainText,
        generation = 0,
        fadeState = "idle",
        alpha = 1,
        slotIndex = index,
        currentOffsetY = targetY,
        targetOffsetY = targetY,
        static = true,
    }
    fs._entry = entry
    fs:SetText(msg)
    fs:SetAlpha(1)
    fs:ClearAllPoints()
    fs:SetPoint("TOP", frame, "TOP", 0, targetY)
    fs:Show()
    table.insert(frame.entries, entry)

    local plainWidth = MeasureTextWidth(plainText)
    if not frame._widestWidth or plainWidth > frame._widestWidth then
        frame._widestWidth = plainWidth
        frame._widestText = plainText
    end
    return true
end

local function ShowStaticDeathPlaceholders(frame)
    EnsureDeathLinePool(frame)
    ClearDeathFrame(frame)
    local limit = GetDeathLimit()
    for i = 1, limit do
        local sample = GetPlaceholderDeath(i)
        local plainText = format("%s died", sample.name)
        local msg = FormatDeathMessage(sample.name, sample.class)
        AddDeathLineStatic(frame, msg, plainText, i)
    end
    CombatTexts:UpdateDeathFrameSize()
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

    if self.isAnchorMode then
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
        isActive = function() return CombatTexts.isAnchorMode end,
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
    if not self.isAnchorMode or not container then
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
    if messageFrames[msgType] then
        if msgType == "partyDeath" then
            EnsureDeathLinePool(messageFrames[msgType])
        end
        return messageFrames[msgType]
    end
    if not container then self:CreateContainer() end

    if msgType == "partyDeath" then
        local frame = CreateFrame("Frame", nil, container)
        frame:SetWidth(MIN_FRAME_WIDTH)
        frame:Hide()
        frame.entries = {}
        frame.lines = {}
        frame._animatorActive = false

        for i = 1, MAX_DEATH_LINES do
            local fs = frame:CreateFontString(nil, "OVERLAY")
            fs:SetFont(STANDARD_FONT, FONT_SIZE, "OUTLINE")
            fs:SetJustifyH("CENTER")
            fs:SetWordWrap(false)
            fs:Hide()
            frame.lines[i] = fs
        end

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
    if not frame or not frame.entries then return end
    if frame._animatorActive then return end

    local maxSlot = 0
    for _, entry in ipairs(frame.entries) do
        if entry.slotIndex then
            maxSlot = math_max(maxSlot, entry.slotIndex)
        end
    end

    if maxSlot == 0 then
        frame:SetHeight(LINE_HEIGHT)
        frame._displayHeight = nil
    else
        local height = maxSlot * LINE_HEIGHT + (maxSlot - 1) * DEATH_LINE_SPACING
        frame:SetHeight(height)
        frame._displayHeight = height
    end
    UpdateDeathFrameWidth(frame)
end

function CombatTexts:PrepareMessage(msgType, overrideText, overrideColor)
    if not self.enabled then return nil end
    if IsPreviewActive() and not overrideText then return nil end

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

    local fadeOut = whisperDB.combatTexts.duration or 2.5
    frame.generation = (frame.generation or 0) + 1
    local myGeneration = frame.generation

    frame:SetAlpha(0)
    UIFrameFadeIn(frame, DEATH_FADE_IN, 0, 1)
    C_Timer.After(DEATH_FADE_IN, function()
        if frame.generation ~= myGeneration or not frame:IsShown() then return end
        UIFrameFadeOut(frame, fadeOut, 1, 0)
        C_Timer.After(fadeOut, function()
            if frame.generation == myGeneration and not IsPreviewActive() then
                frame:Hide()
                frame._lastYOffset = nil
                activeMessages[msgType] = nil
                CombatTexts:ArrangeMessages()
            end
        end)
    end)
end

function CombatTexts:ShowPersistentMessage(msgType)
    self:PrepareMessage(msgType)
end

function CombatTexts:HidePersistentMessage(msgType, instant)
    local frame = messageFrames[msgType]
    if not frame then return end

    if instant or not frame:IsShown() then
        UIFrameFadeRemoveFrame(frame)
        frame:Hide()
        frame._lastYOffset = nil
        activeMessages[msgType] = nil
        self:ArrangeMessages()
        return
    end

    UIFrameFadeRemoveFrame(frame)
    frame.generation = (frame.generation or 0) + 1
    local myGeneration = frame.generation

    UIFrameFadeOut(frame, DEATH_FADE_OUT, frame:GetAlpha(), 0)
    C_Timer.After(DEATH_FADE_OUT, function()
        if frame.generation ~= myGeneration then return end
        frame:Hide()
        frame._lastYOffset = nil
        activeMessages[msgType] = nil
        CombatTexts:ArrangeMessages()
    end)
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
    if not self.enabled or IsPreviewActive() then return end
    if durabilityPending then return end
    durabilityPending = true
    C_Timer.After(0.5, function()
        durabilityPending = false
        CombatTexts:DoCheckDurability()
    end)
end

function CombatTexts:DoCheckDurability()
    if not self.enabled or IsPreviewActive() then return end

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

AnnounceDeath = function(name, classFilename)
    local frame = messageFrames.partyDeath
    if not frame then
        CombatTexts:GetMessageFrame("partyDeath")
        CombatTexts:UpdateDeathFrameSize()
        frame = messageFrames.partyDeath
    end
    if not frame or not frame.entries then return end

    local class = classFilename
    if IsSecretValue(classFilename) then class = nil end
    local plainText = format("%s died", name or "Unknown")
    local msg = FormatDeathMessage(name, class)

    AddDeathLine(frame, msg, plainText)
    frame:Show()
    activeMessages.partyDeath = true
    deathVisibleUntil = GetTime() + HOLD_TIME + DEATH_FADE_OUT
    CombatTexts:ArrangeMessages()
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
    if not self.enabled or IsPreviewActive() then return end
    if not IsInGroup() then return end
    local enabled = select(1, GetMessageConfig(whisperDB.combatTexts, "partyDeath"))
    if not enabled then return end
    ResolveDeathInfo(deadGUID)
end

-- =========================
-- Test mode
-- =========================
function CombatTexts:StopTestDeathLoop()
    if testDeathTimer then
        C_Timer.CancelTimer(testDeathTimer)
        testDeathTimer = nil
    end
end

function CombatTexts:SpawnTestDeath()
    if not self.isDeathAnimTestMode then return end

    local frame = messageFrames.partyDeath
    if not frame then
        self:GetMessageFrame("partyDeath")
        frame = messageFrames.partyDeath
    end
    if not frame or not frame.entries then return end

    testDeathCounter = testDeathCounter + 1
    local sample = GetPlaceholderDeath(testDeathCounter)
    local plainText = format("%s died", sample.name)
    local msg = FormatDeathMessage(sample.name, sample.class)

    AddDeathLine(frame, msg, plainText)
    frame:Show()
    activeMessages.partyDeath = true
    self:ArrangeMessages()
end

function CombatTexts:StartTestDeathLoop()
    self:StopTestDeathLoop()

    local deathFrame = self:GetMessageFrame("partyDeath")
    if deathFrame then
        ClearDeathFrame(deathFrame)
    end
    testDeathCounter = 0

    local function scheduleNext()
        if not self.isDeathAnimTestMode then return end
        self:SpawnTestDeath()
        testDeathTimer = C_Timer.After(TEST_DEATH_INTERVAL, scheduleNext)
    end

    scheduleNext()
end

function CombatTexts:HideStaticCombatMessages()
    for _, msgType in ipairs({ "enterCombat", "exitCombat", "lowDurability" }) do
        local frame = messageFrames[msgType]
        if frame then
            UIFrameFadeRemoveFrame(frame)
            frame:Hide()
            frame._lastYOffset = nil
            activeMessages[msgType] = nil
        end
    end
end

function CombatTexts:ShowStaticCombatMessages()
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
end

function CombatTexts:ShowAnchorPreview()
    self:ShowStaticCombatMessages()

    local deathFrame = self:GetMessageFrame("partyDeath")
    ShowStaticDeathPlaceholders(deathFrame)
    deathFrame:Show()
    activeMessages.partyDeath = true

    self:ArrangeMessages()
    self:UpdateTestOverlay()
end

function CombatTexts:ShowDeathAnimPreview()
    self:HideTestOverlay()
    container:Show()
    self:HideStaticCombatMessages()
    self:StartTestDeathLoop()
    self:ArrangeMessages()
end

function CombatTexts:RefreshAnchorDeathPlaceholders()
    if not self.isAnchorMode then return end
    local deathFrame = messageFrames.partyDeath
    if not deathFrame then return end
    ShowStaticDeathPlaceholders(deathFrame)
    deathFrame:Show()
    activeMessages.partyDeath = true
    self:ArrangeMessages()
    self:UpdateTestOverlay()
end

function CombatTexts:HidePreview()
    self:StopTestDeathLoop()
    for _, frame in pairs(messageFrames) do
        if frame.entries then
            ClearDeathFrame(frame)
        end
        frame:Hide()
        frame._lastYOffset = nil
    end
    activeMessages = {}
    self:HideTestOverlay()
    self:ArrangeMessages()
    self:SyncPreviewFlags()
end

function CombatTexts:ToggleAnchorMode()
    if not container then self:CreateContainer() end

    if self.isAnchorMode then
        self.isAnchorMode = false
        self:HidePreview()
        self:ApplySettings()
        if not inCombat then
            self:DoCheckDurability()
        end
        self:SyncPreviewFlags()
        return
    end

    if self.isDeathAnimTestMode then
        self.isDeathAnimTestMode = false
        self:StopTestDeathLoop()
    end
    self:HidePreview()
    self.isAnchorMode = true
    self:ShowAnchorPreview()
    self:SyncPreviewFlags()
end

function CombatTexts:ToggleDeathAnimTestMode()
    if not container then self:CreateContainer() end

    if self.isDeathAnimTestMode then
        self.isDeathAnimTestMode = false
        self:HidePreview()
        self:ApplySettings()
        if not inCombat then
            self:DoCheckDurability()
        end
        self:SyncPreviewFlags()
        return
    end

    if self.isAnchorMode then
        self.isAnchorMode = false
    end
    self:HidePreview()
    self.isDeathAnimTestMode = true
    self:ShowDeathAnimPreview()
    self:SyncPreviewFlags()
end

function CombatTexts:SyncPreviewFlags()
    self.isTestMode = self.isAnchorMode or self.isDeathAnimTestMode
end

function CombatTexts:ToggleTestMode()
    if self.isDeathAnimTestMode then
        self:ToggleDeathAnimTestMode()
    elseif self.isAnchorMode then
        self:ToggleAnchorMode()
    end
    if self.anchorButton then
        self.anchorButton:SetText("Anchor")
        self.anchorButton:GetFontString():SetTextColor(1, 1, 1)
    end
    if self.deathTestButton then
        self.deathTestButton:SetText("Test")
        self.deathTestButton:GetFontString():SetTextColor(1, 1, 1)
    end
    self:SyncPreviewFlags()
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
            if IsPreviewActive() then return end

            if event == "UNIT_DIED" then
                CombatTexts:OnUnitDied(nil, ...)
            elseif event == "PLAYER_REGEN_DISABLED" then
                CombatTexts:OnEnterCombat()
            elseif event == "PLAYER_REGEN_ENABLED" then
                CombatTexts:OnExitCombat()
            elseif event == "UPDATE_INVENTORY_DURABILITY" then
                CombatTexts:CheckDurability()
            elseif event == "GROUP_ROSTER_UPDATE" then
                ClearAnnouncedDeadUnits()
            elseif event == "PLAYER_ENTERING_WORLD" then
                ClearAnnouncedDeadUnits()
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

    self:StopTestDeathLoop()

    if self.isAnchorMode or self.isDeathAnimTestMode then
        self:HidePreview()
        self.isAnchorMode = false
        self.isDeathAnimTestMode = false
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

    local anchorBtn = whisper.GUI.CreateStyledButton(content, "Anchor", 80, 24)
    anchorBtn:SetPoint("TOPLEFT", toggleBtn, "TOPRIGHT", 10, 0)
    anchorBtn:GetFontString():SetTextColor(1, 1, 1)
    anchorBtn:SetScript("OnClick", function()
        if self.ToggleAnchorMode then
            self:ToggleAnchorMode()
            if self.isAnchorMode then
                anchorBtn:SetText("End")
                anchorBtn:GetFontString():SetTextColor(1, 0.2, 0.2)
                if self.deathTestButton then
                    self.deathTestButton:SetText("Test")
                    self.deathTestButton:GetFontString():SetTextColor(1, 1, 1)
                end
            else
                anchorBtn:SetText("Anchor")
                anchorBtn:GetFontString():SetTextColor(1, 1, 1)
            end
        end
    end)
    self.anchorButton = anchorBtn

    local resetBtn = whisper.GUI.CreateStyledButton(content, "Reset", 80, 24)
    resetBtn:SetPoint("TOPLEFT", anchorBtn, "TOPRIGHT", 10, 0)
    resetBtn:GetFontString():SetTextColor(0.7, 0.7, 0.7)

    local sliderRefs = {}

    EnsurePositionDefaults(db)

    local posSection = whisper.GUI.CreateSettingsSection(content, "POSITION", { sliders = 2 })
    posSection:SetPoint("TOPLEFT", toggleBtn, "BOTTOMLEFT", 0, -16)

    local xSlider = whisper.GUI.AddSectionSlider(posSection, nil, "X Offset", -50, 50, 1,
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
    sliderRefs.xSlider = xSlider

    local ySlider = whisper.GUI.AddSectionSlider(posSection, xSlider, "Y Offset", -50, 50, 1,
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
    sliderRefs.ySlider = ySlider

    local displaySection = whisper.GUI.CreateSettingsSection(content, "DISPLAY", { sliders = 1 })
    displaySection:SetPoint("TOPLEFT", posSection, "BOTTOMLEFT", 0, -whisper.GUI.SECTION_GAP)

    local deathTestBtn = whisper.GUI.CreateStyledButton(displaySection, "Test", 50, 22)
    deathTestBtn:SetPoint("TOPRIGHT", displaySection, "TOPRIGHT", -whisper.GUI.SLIDER_INSET, -6)
    deathTestBtn:GetFontString():SetTextColor(1, 1, 1)
    deathTestBtn:SetScript("OnClick", function()
        if self.ToggleDeathAnimTestMode then
            self:ToggleDeathAnimTestMode()
            if self.isDeathAnimTestMode then
                deathTestBtn:SetText("End")
                deathTestBtn:GetFontString():SetTextColor(1, 0.2, 0.2)
                anchorBtn:SetText("Anchor")
                anchorBtn:GetFontString():SetTextColor(1, 1, 1)
            else
                deathTestBtn:SetText("Test")
                deathTestBtn:GetFontString():SetTextColor(1, 1, 1)
            end
        end
    end)
    self.deathTestButton = deathTestBtn

    local limitSlider = whisper.GUI.AddSectionSlider(displaySection, nil, "Death Limit", 1, 20, 1,
        function() return db.limit end,
        function(val)
            db.limit = val
            if self.isAnchorMode then
                self:RefreshAnchorDeathPlaceholders()
            elseif self.isDeathAnimTestMode then
                if messageFrames.partyDeath then
                    EnforceDeathLimit(messageFrames.partyDeath)
                end
            elseif self.UpdateDeathFrameSize then
                self:UpdateDeathFrameSize()
            end

            if self.ArrangeMessages then
                self:ArrangeMessages()
            end
        end
    )
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

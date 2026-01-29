local addonName, whisper = ...
local Deaths = {}
Deaths.enabled = true
Deaths.isTestMode = false 
whisper:RegisterModule("Death Tracker", Deaths)

-- =========================
-- Locals
-- =========================
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitGUID = UnitGUID
local UnitName = UnitName
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local C_ClassColor = C_ClassColor
local format = string.format
local strsplit = strsplit
local C_Timer = C_Timer
local UnitClass = UnitClass

-- Constants
local STANDARD_FONT = "Fonts\\FRIZQT__.TTF"
local FONT_SIZE = 16
local HOLD_TIME = 4.0
local FADE_TIME = 1.0
local RESET_WINDOW = 5.0
local SPACING = 2

-- Default Values
local DEFAULTS = {
    limit = 5,
    offsetX = 0,
    offsetY = 10,
    growUp = true
}

-- OPTIMIZATION: Valid unit lookup table (faster than string pattern matching)
local validUnits = {
    ["player"] = true,
}
-- Pre-populate party units
for i = 1, 4 do
    validUnits["party" .. i] = true
end
-- Pre-populate raid units
for i = 1, 40 do
    validUnits["raid" .. i] = true
end

-- State
local messageFrame
local deadCache = {}
local recentDeaths = 0
local resetTimer = nil

-- =========================
-- Logic
-- =========================
local function ResetSpamCounter()
    recentDeaths = 0
    resetTimer = nil
end

local function AnnounceDeath(unit, guid)
    -- DB UPDATE: deathTracker
    local limit = whisperDB.deathTracker.limit or DEFAULTS.limit
    if recentDeaths >= limit then return end

    if recentDeaths == 0 then
        if resetTimer then C_Timer.CancelTimer(resetTimer) end
        resetTimer = C_Timer.After(RESET_WINDOW, ResetSpamCounter)
    end

    recentDeaths = recentDeaths + 1

    local name = UnitName(unit)
    local classColorStr = "|cffffffff"
    local _, classFilename = GetPlayerInfoByGUID(guid)

    if classFilename then
        local color = C_ClassColor.GetClassColor(classFilename)
        if color then
            classColorStr = "|c" .. color:GenerateHexColor()
        end
    end

    if name and name:find("-") then
        name = strsplit("-", name)
    end

    if messageFrame then
        messageFrame:AddMessage(format("%s%s|r died", classColorStr, name or "Unknown"))
    end
end

-- =========================
-- Test Mode Logic
-- =========================
function Deaths:ToggleTestMode()
    if not messageFrame then self:Init() end

    self.isTestMode = not self.isTestMode

    if self.isTestMode then
        messageFrame:Show()
        messageFrame:Clear()
        messageFrame:SetFadeDuration(0)
        messageFrame:SetTimeVisible(9999)

        local name = UnitName("player") or "Player"
        local _, classFilename = UnitClass("player")
        local color = C_ClassColor.GetClassColor(classFilename or "PRIEST")
        local colorStr = "|cffffffff"

        if color then
            colorStr = "|c" .. color:GenerateHexColor()
        end

        -- DB UPDATE: deathTracker
        local limit = whisperDB.deathTracker.limit or DEFAULTS.limit
        for i = 1, limit do
            messageFrame:AddMessage(format("%s%s|r died (%d)", colorStr, name, i))
        end
    else
        messageFrame:Clear()
        messageFrame:SetFadeDuration(FADE_TIME)
        messageFrame:SetTimeVisible(HOLD_TIME)
    end
end

-- =========================
-- Settings Update
-- =========================
function Deaths:UpdateSettings()
    if not messageFrame then return end

    -- DB UPDATE: deathTracker
    local db = whisperDB.deathTracker
    messageFrame:ClearAllPoints()

    local limit = db.limit or DEFAULTS.limit
    local height = (limit * FONT_SIZE) + ((limit - 1) * SPACING)

    messageFrame:SetSize(600, height)
    messageFrame:SetMaxLines(limit)

    local screenWidth, screenHeight = UIParent:GetSize()
    local xPos = (db.offsetX / 100) * screenWidth
    local yPos = (db.offsetY / 100) * screenHeight

    if db.growUp then
        messageFrame:SetPoint("BOTTOM", UIParent, "CENTER", xPos, yPos)
        messageFrame:SetInsertMode("TOP")
        messageFrame:SetJustifyV("BOTTOM")
    else
        messageFrame:SetPoint("TOP", UIParent, "CENTER", xPos, yPos)
        messageFrame:SetInsertMode("BOTTOM")
        messageFrame:SetJustifyV("TOP")
    end

    if self.isTestMode then
        self.isTestMode = false
        Deaths:ToggleTestMode()
    end
end

-- =========================
-- Reset to Defaults
-- =========================
function Deaths:ResetDefaults()
    whisperDB.deathTracker.limit = DEFAULTS.limit
    whisperDB.deathTracker.offsetX = DEFAULTS.offsetX
    whisperDB.deathTracker.offsetY = DEFAULTS.offsetY
    whisperDB.deathTracker.growUp = DEFAULTS.growUp

    self:UpdateSettings()
end

-- =========================
-- Event Handling
-- =========================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_FLAGS")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, unit)
    if not Deaths.enabled or Deaths.isTestMode then return end

    if event == "UNIT_FLAGS" then
        -- OPTIMIZATION: Table lookup instead of string pattern matching
        if validUnits[unit] then
            -- OPTIMIZATION: Cache UnitGUID call - only call once
            local guid = UnitGUID(unit)
            if not guid then return end

            if UnitIsDeadOrGhost(unit) then
                if not deadCache[guid] then
                    deadCache[guid] = true
                    AnnounceDeath(unit, guid)
                end
            else
                deadCache[guid] = nil
            end
        end

    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        deadCache = {}
        recentDeaths = 0
        if resetTimer then C_Timer.CancelTimer(resetTimer) end
        resetTimer = nil
        Deaths:CheckZone()
    end
end)

-- =========================
-- Initialization
-- =========================
function Deaths:Init()
    -- Initialize DB Defaults if missing
    whisperDB.deathTracker = whisperDB.deathTracker or {}
    
    -- Apply defaults for any missing values
    if whisperDB.deathTracker.limit == nil then
        whisperDB.deathTracker.limit = DEFAULTS.limit
    end
    if whisperDB.deathTracker.offsetX == nil then
        whisperDB.deathTracker.offsetX = DEFAULTS.offsetX
    end
    if whisperDB.deathTracker.offsetY == nil then
        whisperDB.deathTracker.offsetY = DEFAULTS.offsetY
    end
    if whisperDB.deathTracker.growUp == nil then
        whisperDB.deathTracker.growUp = DEFAULTS.growUp
    end
    
    if not messageFrame then
        messageFrame = CreateFrame("ScrollingMessageFrame", nil, UIParent)
        messageFrame:SetFrameStrata("DIALOG") 
        messageFrame:SetFont(STANDARD_FONT, FONT_SIZE, "OUTLINE")
        messageFrame:SetJustifyH("CENTER")
        messageFrame:SetFadeDuration(FADE_TIME)
        messageFrame:SetTimeVisible(HOLD_TIME)
        messageFrame:SetSpacing(SPACING)
        
        self:UpdateSettings()
    end
    
    Deaths:CheckZone()
    if messageFrame then messageFrame:Show() end
end

function Deaths:Disable()
    self.enabled = false
    if messageFrame then messageFrame:Hide() end
end

function Deaths:CheckZone()
    local inInstance, instanceType = IsInInstance()
    self.isActive = inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "scenario")
end
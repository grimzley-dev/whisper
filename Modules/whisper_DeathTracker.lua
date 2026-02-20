local addonName, whisper = ...
local Deaths = {}
Deaths.enabled = true
Deaths.isTestMode = false 
whisper:RegisterModule("Death Tracker", Deaths)

-- =========================
-- Locals
-- =========================
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitName = UnitName
local UnitClass = UnitClass
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local C_ClassColor = C_ClassColor
local C_Timer = C_Timer
local format = string.format
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup

-- Constants
local STANDARD_FONT = "Fonts\\FRIZQT__.TTF"
local FONT_SIZE = 16
local HOLD_TIME = 4.0
local FADE_TIME = 1.0
local RESET_WINDOW = 5.0
local SPACING = 2
local UPDATE_THROTTLE = 0.1 -- 100ms throttle to prevent lag

-- Default Values
local DEFAULTS = {
    limit = 5,
    offsetX = 0,
    offsetY = 10,
    growUp = true
}

-- State
local messageFrame
local deadCache = {} -- Stores death state by Safe Unit ID (e.g. "raid1")
local recentDeaths = 0
local resetTimer = nil
local updateTimer = nil

-- =========================
-- Logic
-- =========================
local function ResetSpamCounter()
    recentDeaths = 0
    resetTimer = nil
end

local function AnnounceDeath(name, classFilename)
    local limit = whisperDB.deathTracker.limit or DEFAULTS.limit
    if recentDeaths >= limit then return end

    if recentDeaths == 0 then
        if resetTimer then C_Timer.CancelTimer(resetTimer) end
        resetTimer = C_Timer.After(RESET_WINDOW, ResetSpamCounter)
    end

    recentDeaths = recentDeaths + 1

    local classColorStr = "|cffffffff"
    if classFilename then
        local color = C_ClassColor.GetClassColor(classFilename)
        if color then
            classColorStr = "|c" .. color:GenerateHexColor()
        end
    end

    -- Add message to frame
    if messageFrame then
        messageFrame:AddMessage(format("%s%s|r died", classColorStr, name or "Unknown"))
    end
end

-- =========================
-- Group Scanning (12.0 Safe)
-- =========================
function Deaths:ScanGroupDeaths()
    if not Deaths.enabled then return end

    local numMembers = GetNumGroupMembers()
    local prefix = IsInRaid() and "raid" or "party"

    -- If in a party, we also need to check "player" separately
    if not IsInRaid() then
        if UnitIsDeadOrGhost("player") then
            if not deadCache["player"] then
                deadCache["player"] = true
                local _, class = UnitClass("player")
                AnnounceDeath(UnitName("player"), class)
            end
        else
            deadCache["player"] = nil
        end
    end

    -- Scan members
    for i = 1, numMembers do
        -- Construct the ID manually to avoid "Secret" taint
        local safeID = prefix .. i

        if UnitIsDeadOrGhost(safeID) then
            if not deadCache[safeID] then
                deadCache[safeID] = true

                -- Retrieve info using the safe ID
                local name = UnitName(safeID)
                local _, class = UnitClass(safeID)

                if name then
                    AnnounceDeath(name, class)
                end
            end
        else
            -- Mark as alive so we can announce their death again if they die later
            deadCache[safeID] = nil
        end
    end
end

-- =========================
-- Event Handling
-- =========================
local eventFrame = CreateFrame("Frame")
-- We use UNIT_FLAGS to detect when status changes (like health/death)
eventFrame:RegisterEvent("UNIT_FLAGS")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event)
    if not Deaths.enabled or Deaths.isTestMode then return end

    if event == "UNIT_FLAGS" then
        -- 12.0 FIX: Do NOT use the 'unit' argument. It might be Secret.
        -- Instead, request a safe group scan.
        if not updateTimer then
            updateTimer = C_Timer.NewTimer(UPDATE_THROTTLE, function()
                Deaths:ScanGroupDeaths()
                updateTimer = nil
            end)
        end

    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        -- Reset cache on load/roster change to prevent phantom announcements
        deadCache = {}
        recentDeaths = 0
        if resetTimer then C_Timer.CancelTimer(resetTimer) end
        resetTimer = nil
        Deaths:CheckZone()
    end
end)

-- =========================
-- Test Mode Logic
-- =========================
function Deaths:ToggleTestMode()
    if not messageFrame then return end

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
-- Settings Update & Init
-- =========================
function Deaths:UpdateSettings()
    if not messageFrame then return end

    local db = whisperDB.deathTracker
    messageFrame:ClearAllPoints()

    local limit = db.limit or DEFAULTS.limit
    local height = (limit * FONT_SIZE) + ((limit - 1) * SPACING)

    messageFrame:SetSize(600, height)
    messageFrame:SetMaxLines(limit)

    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()

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

function Deaths:ResetDefaults()
    local db = whisperDB.deathTracker
    db.limit = DEFAULTS.limit
    db.offsetX = DEFAULTS.offsetX
    db.offsetY = DEFAULTS.offsetY
    db.growUp = DEFAULTS.growUp
    self:UpdateSettings()
end

function Deaths:Init()
    if not whisperDB.deathTracker then whisperDB.deathTracker = {} end
    local db = whisperDB.deathTracker

    if db.limit == nil then db.limit = DEFAULTS.limit end
    if db.offsetX == nil then db.offsetX = DEFAULTS.offsetX end
    if db.offsetY == nil then db.offsetY = DEFAULTS.offsetY end
    if db.growUp == nil then db.growUp = DEFAULTS.growUp end

    if not messageFrame then
        messageFrame = CreateFrame("ScrollingMessageFrame", nil, UIParent)
        messageFrame:SetFrameStrata("DIALOG")
        messageFrame:SetFont(STANDARD_FONT, FONT_SIZE, "OUTLINE")
        messageFrame:SetJustifyH("CENTER")
        messageFrame:SetFadeDuration(FADE_TIME)
        messageFrame:SetTimeVisible(HOLD_TIME)
        messageFrame:SetSpacing(SPACING)
    end

    self:UpdateSettings()
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

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event)
    Deaths:Init()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
local addonName, whisper = ...
local PIHelper = {
    enabled = true,
    isTestMode = false,
    lastSoundTime = 0,
    soundPath = "Interface\\AddOns\\whisper\\Media\\whisperPI.mp3"
}

-- Register directly as PI Helper
whisper:RegisterModule("PI Helper", PIHelper)

-- =========================================================================
-- CONFIG & CONSTANTS
-- =========================================================================
local ipairs = ipairs
local UnitClass = UnitClass
local InCombatLockdown = InCombatLockdown
local IsInInstance = IsInInstance
local GetTime = GetTime
local UnitName = UnitName
local strsplit = strsplit

-- =========================================================================
-- UI FRAME GENERATION
-- =========================================================================
local function EnsureAlertFrameExists()
    if PIHelper.alertFrame then return end

    PIHelper.alertFrame = CreateFrame("Frame", "whisperPIAlertFrame", UIParent)
    PIHelper.alertFrame:SetSize(200, 50)
    PIHelper.alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    PIHelper.alertFrame:Hide()

    PIHelper.text = PIHelper.alertFrame:CreateFontString(nil, "OVERLAY")
    PIHelper.text:SetPoint("CENTER")
    PIHelper.text:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    PIHelper.text:SetShadowColor(0, 0, 0, 0)
    PIHelper.text:SetShadowOffset(0, 0)

    PIHelper.animGroup = PIHelper.alertFrame:CreateAnimationGroup()
    local fadeIn = PIHelper.animGroup:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.4)
    fadeIn:SetOrder(1)

    local hold = PIHelper.animGroup:CreateAnimation("Alpha")
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetDuration(8)
    hold:SetOrder(2)

    local fadeOut = PIHelper.animGroup:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.4)
    fadeOut:SetOrder(3)

    PIHelper.animGroup:SetScript("OnFinished", function()
        if not PIHelper.isTestMode then PIHelper.alertFrame:Hide() end
    end)
end

-- Internal helper to HARD strip realm names
local function GetNameOnly(fullName)
    if not fullName then return "Unknown" end
    local name = strsplit("-", fullName)
    return name
end

-- =========================================================================
-- MODULE LOGIC
-- =========================================================================

function PIHelper:Init()
    self.enabled = true

    self.frame = self.frame or CreateFrame("Frame")
    EnsureAlertFrameExists()

    -- CLASS GUARD: Non-priests will not register for any combat/whisper events
    -- but remain "enabled" so the Test Mode UI functions normally.
    local _, playerClass = UnitClass("player")
    if playerClass ~= "PRIEST" then return end

    self.frame:RegisterEvent("CHAT_MSG_WHISPER")
    self.frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

    self.frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_WHISPER" then
            local _, instanceType = IsInInstance()
            if instanceType ~= "party" and instanceType ~= "raid" then return end

            if not InCombatLockdown() then return end

            local selectedTarget = whisperDB and whisperDB.piTarget
            if not selectedTarget or selectedTarget == "None" then return end

            local shortTarget = GetNameOnly(selectedTarget)
            local _, englishClass = UnitClass(selectedTarget)

            self:ProcessPIRequest(shortTarget, englishClass)

        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unitTarget, _, spellID = ...
            if unitTarget == "player" and spellID == 10060 then -- 10060 is Power Infusion
                if self.alertFrame then
                    self.animGroup:Stop()
                    self.alertFrame:Hide()
                end
            end
        end
    end)
end

function PIHelper:ProcessPIRequest(shortName, classTag)
    if not self.alertFrame then return end

    local currentTime = GetTime()

    local soundEnabled = true
    if whisperDB and whisperDB.piHelper and whisperDB.piHelper.soundEnabled ~= nil then
        soundEnabled = whisperDB.piHelper.soundEnabled
    end

    if soundEnabled and (currentTime - self.lastSoundTime) > 5 then
        PlaySoundFile(self.soundPath, "Master")
        self.lastSoundTime = currentTime
    end

    local color = (classTag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTag]) or {r=1, g=1, b=1}
    local hex = string.format("ff%02x%02x%02x", color.r*255, color.g*255, color.b*255)

    self.animGroup:Stop()
    self.text:SetText("Power Infusion on |c" .. hex .. shortName .. "|r")
    self.text:SetTextColor(1, 1, 1)

    self.alertFrame:SetAlpha(1)
    self.alertFrame:Show()
    self.animGroup:Play()
end

function PIHelper:ToggleTestMode(state)
    if state == nil then state = not self.isTestMode end

    if state and not self.enabled then
        self.isTestMode = false
        return
    end

    self.isTestMode = state

    if state then
        local name = UnitName("player")
        local _, classTag = UnitClass("player")
        self:ProcessPIRequest(name, classTag)
    else
        if self.alertFrame then
            self.animGroup:Stop()
            self.alertFrame:Hide()
        end
    end
end

function PIHelper:Disable()
    self.enabled = false
    if self.frame then
        self.frame:UnregisterAllEvents()
    end

    if self.isTestMode then
        self:ToggleTestMode(false)
    end
end
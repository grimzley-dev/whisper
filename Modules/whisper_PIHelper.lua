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
local strsplit = string.split or strsplit
local UnitIsUnit = UnitIsUnit
local IsInRaid = IsInRaid
local C_Timer = C_Timer
local C_Spell = C_Spell

-- State
local glowFrames = {}

-- =========================================================================
-- UI FRAME GENERATION
-- =========================================================================
function PIHelper:EnsureAlertFrameExists()
    if self.alertFrame then return end

    self.alertFrame = CreateFrame("Frame", "whisperPIAlertFrame", UIParent)
    self.alertFrame:SetSize(200, 50)
    self.alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    self.alertFrame:Hide()

    self.text = self.alertFrame:CreateFontString(nil, "OVERLAY")
    self.text:SetPoint("CENTER")
    self.text:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    self.text:SetShadowColor(0, 0, 0, 0)
    self.text:SetShadowOffset(0, 0)

    self.animGroup = self.alertFrame:CreateAnimationGroup()
    local fadeIn = self.animGroup:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.4)
    fadeIn:SetOrder(1)

    local hold = self.animGroup:CreateAnimation("Alpha")
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetDuration(8)
    hold:SetOrder(2)

    local fadeOut = self.animGroup:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.4)
    fadeOut:SetOrder(3)

    self.animGroup:SetScript("OnFinished", function()
        if not self.isTestMode then self.alertFrame:Hide() end
    end)
end

-- Internal helper to HARD strip realm names
local function GetNameOnly(fullName)
    if not fullName then return "Unknown" end
    local name = strsplit("-", fullName)
    return name
end

-- =========================================================================
-- GLOW UTILITIES
-- =========================================================================
local function GetUnitFrame(unitName)
    local inRaid = IsInRaid()
    if ElvUF then
        if inRaid then
            for group = 1, 8 do
                for member = 1, 5 do
                    local layouts = {"Raid", "Raid1", "Raid2", "Raid3"}
                    for _, layout in ipairs(layouts) do
                        local frame = _G["ElvUF_"..layout.."Group"..group.."UnitButton"..member]
                        if frame and frame:IsVisible() and frame.unit and UnitIsUnit(frame.unit, unitName) then return frame end
                    end
                end
            end
        else
            for i = 1, 5 do
                local frame = _G["ElvUF_PartyGroup1UnitButton"..i]
                if frame and frame:IsVisible() and frame.unit and UnitIsUnit(frame.unit, unitName) then return frame end
            end
            local playerFrame = _G["ElvUF_Player"]
            if playerFrame and playerFrame:IsVisible() and playerFrame.unit and UnitIsUnit(playerFrame.unit, unitName) then return playerFrame end
        end
    end

    if inRaid then
        for i = 1, 40 do
            local frame = _G["CompactRaidFrame"..i]
            if frame and frame:IsVisible() and frame.unit and UnitIsUnit(frame.unit, unitName) then return frame end
        end
    else
        if PartyFrame and PartyFrame.MemberFrames then
            for _, frame in ipairs(PartyFrame.MemberFrames) do
                if frame and frame:IsVisible() and frame.unit and UnitIsUnit(frame.unit, unitName) then return frame end
            end
        end
        for i = 1, 5 do
            local frame = _G["CompactPartyFrameMember"..i]
            if frame and frame:IsVisible() and frame.unit and UnitIsUnit(frame.unit, unitName) then return frame end
        end
        local playerFrame = _G["PlayerFrame"]
        if playerFrame and playerFrame:IsVisible() and playerFrame.unit and UnitIsUnit(playerFrame.unit, unitName) then return playerFrame end
    end
    return nil
end

local function StopGlow(frame, sender)
    if frame then
        frame:Hide()
        local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
        if LCG and LCG.PixelGlow_Stop then LCG.PixelGlow_Stop(frame, "whisperPI_"..sender) end
    end
end

function PIHelper:ShowGlow(senderShort)
    local unitFrame = GetUnitFrame(senderShort)
    if not unitFrame then return end

    local overlay = glowFrames[senderShort]
    if not overlay then
        overlay = CreateFrame("Frame", nil, unitFrame)
        overlay:SetFrameStrata("HIGH")
        local icon = overlay:CreateTexture(nil, "OVERLAY")
        overlay.icon = icon
        glowFrames[senderShort] = overlay
    end

    overlay:SetParent(unitFrame)
    overlay:SetAllPoints(unitFrame)
    overlay:SetFrameLevel(9999)

    -- Dynamically fetch the Power Infusion Icon (SpellID: 10060)
    local iconTexture = 135939
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(10060)
        if info then iconTexture = info.iconID end
    else
        _, _, iconTexture = GetSpellInfo(10060)
    end

    overlay.icon:ClearAllPoints()
    overlay.icon:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    overlay.icon:SetSize(24, 24)
    overlay.icon:SetTexture(iconTexture)
    overlay:Show()

    local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
    if LCG and LCG.PixelGlow_Start then
        -- Same exact settings as Externals Tracker: color(Yellow), 6 lines, 0.3 speed, 25 length, 2 thickness, -1 offset
        LCG.PixelGlow_Start(overlay, {1, 1, 0, 1}, 6, 0.3, 25, 2, -1, -1, false, "whisperPI_"..senderShort)
    end

    -- Cleanup the glow after 10 seconds if PI was never cast
    C_Timer.After(10, function()
        if overlay and overlay:IsShown() then
            StopGlow(overlay, senderShort)
        end
    end)
end

-- =========================================================================
-- MODULE LOGIC
-- =========================================================================

function PIHelper:Init()
    self.enabled = true

    self.frame = self.frame or CreateFrame("Frame")
    self:EnsureAlertFrameExists()

    -- CLASS GUARD: Non-priests will not register for any combat/whisper events
    -- but remain "enabled" so the Test Mode UI functions normally.
    local _, playerClass = UnitClass("player")
    if playerClass ~= "PRIEST" then return end

    self.frame:RegisterEvent("CHAT_MSG_WHISPER")
    self.frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

    self.frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_WHISPER" then
            -- Removed the sender validation completely. Any whisper triggers this now.
            local text, sender = ...
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
                -- Hide Central Alert
                if self.alertFrame then
                    self.animGroup:Stop()
                    self.alertFrame:Hide()
                end

                -- Stop any active Pixel Glows on raid frames
                for sender, frame in pairs(glowFrames) do
                    StopGlow(frame, sender)
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

    -- Trigger the new Unit Frame Pixel Glow + Icon
    self:ShowGlow(shortName)

    -- Trigger the Central Text Alert
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
        -- Clean up Test Mode glows
        for sender, frame in pairs(glowFrames) do
            StopGlow(frame, sender)
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

    for sender, frame in pairs(glowFrames) do
        StopGlow(frame, sender)
    end
end

-- =========================
-- Config Panel UI
-- =========================
local function GetClassColoredName(unit, nameCounts)
    local name, realm = UnitName(unit)
    if not name then return nil end
    local _, class = UnitClass(unit)
    local color = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class] or {r=1, g=1, b=1}

    local displayName = name
    if nameCounts and nameCounts[name] and nameCounts[name] > 1 then
        if realm and realm ~= "" then displayName = name .. "-" .. realm end
    end

    local raw = (realm and realm ~= "") and (name.."-"..realm) or name
    local colored = string.format("|cff%02x%02x%02x%s|r", color.r*255, color.g*255, color.b*255, displayName)
    return colored, raw
end

local function GetGroupMembers()
    local members = { {text = "None", value = "None"} }
    local units = {"player"}
    local num = GetNumGroupMembers()
    if num > 0 then
        local prefix = IsInRaid() and "raid" or "party"
        for i = 1, num do
            local unit = prefix .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then table.insert(units, unit) end
        end
    end

    local counts = {}
    for _, u in ipairs(units) do
        local n = UnitName(u)
        if n then counts[n] = (counts[n] or 0) + 1 end
    end

    for _, u in ipairs(units) do
        local colored, raw = GetClassColoredName(u, counts)
        if raw then table.insert(members, {text = colored, value = raw}) end
    end

    return members
end

function PIHelper:BuildOptionsPanel(content, toggleBtn)
    if not whisperDB.piHelper then whisperDB.piHelper = {} end
    local db = whisperDB.piHelper

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

    local soundBtn = whisper.GUI.CreateStyledButton(content, "", 140, 24)
    soundBtn:SetPoint("TOPLEFT", testBtn, "TOPRIGHT", 10, 0)
    local function UpdateSoundBtn()
        local isSoundOn = db.soundEnabled ~= false
        soundBtn:SetText(isSoundOn and "Sound Alert: ON" or "Sound Alert: OFF")
        if isSoundOn then
            soundBtn:GetFontString():SetTextColor(0.5, 0.5, 1)
        else
            soundBtn:GetFontString():SetTextColor(0.6, 0.6, 0.6)
        end
    end
    UpdateSoundBtn()

    soundBtn:SetScript("OnClick", function()
        db.soundEnabled = not (db.soundEnabled ~= false)
        UpdateSoundBtn()
    end)

    local dd = whisper.GUI.CreateCustomDropdown(content, 180, 24,
        function() return whisperDB.piTarget or "None" end,
        function(val) whisperDB.piTarget = val end,
        GetGroupMembers
    )
    dd:SetPoint("TOPLEFT", toggleBtn, "BOTTOMLEFT", 0, -20)
end
local addonName, whisper = ...
local MythicFrames = {}
MythicFrames.enabled = true
whisper:RegisterModule("Mythic Frames", MythicFrames)

-- =========================
-- Locals & Cache
-- =========================
local ipairs = ipairs
local unpack = unpack
local GetInstanceInfo = GetInstanceInfo
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local eventFrame

-- ElvUI macro conditions
local DefaultVisibility = {
    party = '[@raid6,exists][@party1,noexists] hide;show',
    raid1 = '[@raid6,noexists][@raid21,exists] hide;show',
    raid2 = '[@raid21,noexists][@raid31,exists] hide;show',
    raid3 = '[@raid31,noexists] hide;show',
}

local MythicVisibility = {
    party = 'hide',
    raid1 = '[nogroup] hide;show',
    raid2 = 'hide',
    raid3 = 'hide',
}

-- =========================
-- Core Logic
-- =========================
local function HasVisibility(E, preset)
    local units = E.db.unitframe.units
    return units.party.visibility == preset.party
        and units.raid1.visibility == preset.raid1
        and units.raid2.visibility == preset.raid2
        and units.raid3.visibility == preset.raid3
end

local function ApplyVisibility(E, preset)
    if HasVisibility(E, preset) then return end

    -- Cannot update secure unit frames while in combat
    if InCombatLockdown() then return end

    local UF = E:GetModule('UnitFrames')
    local units = E.db.unitframe.units

    units.party.visibility = preset.party
    units.raid1.visibility = preset.raid1
    units.raid2.visibility = preset.raid2
    units.raid3.visibility = preset.raid3

    -- Only update headers if ElvUI frames are actually enabled
    for _, frame in ipairs({'party', 'raid1', 'raid2', 'raid3'}) do
        if units[frame].enable then
            UF:CreateAndUpdateHeaderGroup(frame)
        end
    end
end

function MythicFrames:UpdateRaidVisibility()
    if not self.enabled then return end

    -- Safely check if ElvUI is loaded and accessible
    local ElvUI = _G.ElvUI
    if not ElvUI then return end

    local E = unpack(ElvUI)
    if not E or not E.db or not E.db.unitframe then return end

    E.db.unitframe.maxAllowedGroups = true

    local _, instanceType, difficultyID = GetInstanceInfo()
    local isMythicRaid = (instanceType == 'raid' and difficultyID == 16)

    ApplyVisibility(E, isMythicRaid and MythicVisibility or DefaultVisibility)
end

-- =========================
-- Initialization & Toggling
-- =========================
function MythicFrames:Init()
    self.enabled = true

    -- Safely exit if ElvUI isn't installed
    if not _G.ElvUI then return end

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(self, event)
            -- Delay the check slightly to allow instance data to load completely
            C_Timer.After(1, function()
                MythicFrames:UpdateRaidVisibility()
            end)
        end)
    end

    -- Zone changes and group loading are the only times difficulty changes
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

    -- Run once immediately on load
    self:UpdateRaidVisibility()
end

function MythicFrames:Disable()
    self.enabled = false

    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end

    -- Revert back to default if disabled mid-raid
    local ElvUI = _G.ElvUI
    if ElvUI then
        local E = unpack(ElvUI)
        if E and not InCombatLockdown() then
            ApplyVisibility(E, DefaultVisibility)
        end
    end
end
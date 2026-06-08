local addonName, whisper = ...
local Keystones = {}
Keystones.enabled = true
Keystones.isTestMode = false

Keystones.defaults = {
    compactMode = false,
    growUp = false,
    useAbbreviation = false,
    transparentMode = false,
    offsetX = -20,
    offsetY = 10,
    -- New defaults for the Reroll alert position
    rerollOffsetX = 0,
    rerollOffsetY = 150,
    version = 1,
    partyCache = {}
}

whisper:RegisterModule("Keystones", Keystones)

local C_ChatInfo = C_ChatInfo
local C_ChallengeMode = C_ChallengeMode
local C_MythicPlus = C_MythicPlus
local C_ClassColor = C_ClassColor
local C_Spell = C_Spell
local C_Container = C_Container
local C_Item = C_Item
local UnitName = UnitName
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local UnitInParty = UnitInParty
local UnitFactionGroup = UnitFactionGroup
local GetRealmName = GetRealmName
local Ambiguate = Ambiguate
local IsInRaid = IsInRaid
local SendAddonMessage = C_ChatInfo.SendAddonMessage
local RegisterAddonMessagePrefix = C_ChatInfo.RegisterAddonMessagePrefix
local InCombatLockdown = InCombatLockdown
local IsSpellKnown = IsSpellKnown
local IsInGroup = IsInGroup
local GetTime = GetTime
local tonumber = tonumber
local format = string.format
local sub = string.sub
local len = string.len
local tinsert = tinsert
local table_sort = table.sort
local pairs = pairs
local type = type
local pcall = pcall

local ORL = LibStub and LibStub:GetLibrary("LibOpenRaid-1.0", true)
local LibKeystone = LibStub and LibStub:GetLibrary("LibKeystone", true)
local libKeystoneTable = {}
local orlRegistered = false
local lksRegistered = false

local STANDARD_FONT = whisper.Style.STANDARD_FONT
local BAR_TEXTURE = "Interface\\AddOns\\whisper\\Media\\whisperBar.tga"
local ROW_HEIGHT = 38
local ROW_SPACING = 1
local WIDTH_NORMAL = 210
local WIDTH_COMPACT = 110
local COMM_PREFIX = "WHISPER_KEYS"
local DEFAULT_OFFSET_X_RATIO = -0.499
local DEFAULT_OFFSET_Y_RATIO = 0.07

local DUNGEON_DB = {
    -- [Midnight]
    [557] = { abbr = "WS",    port = 1254400 }, -- Windrunner Spire
    [558] = { abbr = "MT",    port = 1254572 },
    [559] = { abbr = "NPX",   port = 1254563 }, -- Nexus-Point Xenas
    [560] = { abbr = "MC",    port = 1254559 }, -- Maisara Caverns

    -- [The War Within]
    [499] = { abbr = "PSF",   port = 445444 }, [500] = { abbr = "ROOK",  port = 445443 },
    [501] = { abbr = "SV",    port = 445269 }, [502] = { abbr = "COT",   port = 445416 },
    [503] = { abbr = "ARAK",  port = 445417 }, [504] = { abbr = "DFC",   port = 445441 },
    [505] = { abbr = "DAWN",  port = 445414 }, [506] = { abbr = "BREW",  port = 445440 },
    [525] = { abbr = "FLOOD", port = 1216786 },[542] = { abbr = "EDA",   port = 1237215 },

    -- [Dragonflight]
    [399] = { abbr = "RLP",   port = 393256 }, [400] = { abbr = "NO",    port = 393262 },
    [401] = { abbr = "AV",    port = 393279 }, [402] = { abbr = "AA",    port = 393273 },
    [403] = { abbr = "ULD",   port = 393222 }, [404] = { abbr = "NELT",  port = 393276 },
    [405] = { abbr = "BH",    port = 393267 }, [406] = { abbr = "HOI",   port = 393283 },
    [463] = { abbr = "FALL",  port = 424197 }, [464] = { abbr = "RISE",  port = 424197 },

    -- [Shadowlands]
    [375] = { abbr = "MISTS", port = 354464 }, [376] = { abbr = "NW",    port = 354462 },
    [378] = { abbr = "HOA",   port = 354465 }, [382] = { abbr = "TOP",   port = 354467 },
    [391] = { abbr = "STRT",  port = 367416 }, [392] = { abbr = "GMBT",  port = 367416 },

    -- [Battle for Azeroth]
    [244] = { abbr = "AD",    port = 424187 }, [245] = { abbr = "FH",    port = 410071 },
    [247] = { abbr = "ML",    port = {467553, 467555} }, [248] = { abbr = "WM",    port = 424167 },
    [251] = { abbr = "UNDR",  port = 410074 }, [353] = { abbr = "SIEGE", port = {445418, 464256} },
    [370] = { abbr = "WORK",  port = 373274 }, [369] = { abbr = "JUNKY", port = 373274 },

    -- [Legion]
    [198] = { abbr = "DHT",   port = 424163 }, [199] = { abbr = "BRH",   port = 424153 },
    [200] = { abbr = "HOV",   port = 393764 }, [206] = { abbr = "NL",    port = 410078 },
    [210] = { abbr = "COS",   port = 393766 }, [239] = { abbr = "SEAT",  port = 1254551 },

    -- [Warlords of Draenor]
    [165] = { abbr = "SBG",   port = 159899 }, [168] = { abbr = "EB",    port = 159901 },
    [166] = { abbr = "GRIM",  port = 159900 }, [169] = { abbr = "DOCKS", port = 159896 },
    [161] = { abbr = "SR",    port = 159898 },

    -- [Mists of Pandaria]
    [2]   = { abbr = "TJS",   port = 131204 },

    -- [Cataclysm]
    [438] = { abbr = "VP",    port = 410080 }, [456] = { abbr = "TOT",   port = 424142 },
    [507] = { abbr = "GB",    port = 445424 },

    -- [Wrath of the Lich King]
    [556] = { abbr = "POS",   port = 1254555 },
}

local KeystoneManager = { partyData = {} }
local Comms = {}
local Interface = { rows = {} }
local eventFrame
local pendingUpdate = false
local isInActiveChallenge = false
local lastBagScan = 0
local lastCooldownRefresh = 0
local rerollReminderShown = false
local talentReminderShown = false

local REMINDER_TEXT = {
    reroll = "|cffFFFFFFReroll Key?|r",
    talents = "|cffFFFFFFCheck Talents|r",
}

local function IsInPartyGroup()
    return IsInGroup() and not IsInRaid()
end

-- =========================================================================
-- HELPER FUNCTIONS
-- =========================================================================
-- Safely truncates strings counting UTF-8 characters instead of bytes
local function utf8sub(str, maxLength)
    if not str then return "" end
    local len = #str
    local charCount = 0
    local bytePos = 1
    while bytePos <= len and charCount < maxLength do
        local b = string.byte(str, bytePos)
        if not b then break end
        if b < 128 then
            bytePos = bytePos + 1
        elseif b < 224 then
            bytePos = bytePos + 2
        elseif b < 240 then
            bytePos = bytePos + 3
        else
            bytePos = bytePos + 4
        end
        charCount = charCount + 1
    end
    return string.sub(str, 1, bytePos - 1)
end

-- =========================================================================
-- REMINDER ALERTS (Reroll Key? / Check Talents)
-- =========================================================================
function Keystones:EnsureRerollTestOverlay()
    if self.rerollTestOverlayCtrl then return end

    self.rerollTestOverlayCtrl = whisper.TestOverlay.Create({
        name = "WhisperKeystoneRerollOverlay",
        label = "Reminders",
        container = function() return self.rerollContainer end,
        isActive = function() return Keystones.isTestMode end,
        getContentFrames = function()
            if Keystones.alertFrame and Keystones.alertFrame:IsShown() then
                return { Keystones.alertFrame }
            end
            return {}
        end,
        dragMode = "move",
        onDragStop = function()
            local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
            if sw > 0 and sh > 0 and Keystones.rerollContainer then
                local cx, cy = Keystones.rerollContainer:GetCenter()
                whisperDB.keystones.rerollOffsetX = cx - (sw / 2)
                whisperDB.keystones.rerollOffsetY = cy - (sh / 2)
            end
        end,
    })
end

function Keystones:UpdateRerollTestOverlay()
    if not self.isTestMode or not self.rerollContainer or not self.rerollContainer:IsShown() then
        if self.rerollTestOverlayCtrl then self.rerollTestOverlayCtrl:Hide() end
        return
    end
    self:EnsureRerollTestOverlay()
    self.rerollTestOverlayCtrl:Update()
end

function Keystones:EnsureInterfaceTestOverlay()
    if Interface.testOverlayCtrl then return end

    Interface.testOverlayCtrl = whisper.TestOverlay.Create({
        name = "WhisperKeystonesOverlay",
        label = "Keystones",
        container = function() return Interface.container end,
        isActive = function() return Keystones.isTestMode end,
        getContentFrames = function()
            local frames = {}
            for _, row in ipairs(Interface.rows) do
                if row:IsShown() then
                    table.insert(frames, row)
                end
            end
            return frames
        end,
        dragMode = "move",
        canDrag = function() return not InCombatLockdown() and Interface.container end,
        onDragStop = function()
            local growUp = whisperDB.keystones.growUp
            local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
            if sw > 0 and sh > 0 and Interface.container then
                local left = Interface.container:GetLeft()
                local y = growUp and Interface.container:GetBottom() or Interface.container:GetTop()
                whisperDB.keystones.offsetX = left - (sw / 2)
                whisperDB.keystones.offsetY = y - (sh / 2)
                Interface:UpdatePosition()
            end
        end,
    })
end

function Keystones:UpdateInterfaceTestOverlay()
    if not self.isTestMode or not Interface.container or not Interface.container:IsShown() then
        if Interface.testOverlayCtrl then Interface.testOverlayCtrl:Hide() end
        return
    end
    self:EnsureInterfaceTestOverlay()
    Interface.testOverlayCtrl:Update()
end

function Keystones:EnsureAlertFrameExists()
    if self.alertFrame then return end

    local db = whisperDB.keystones

    self.rerollContainer = CreateFrame("Frame", "whisperKeystoneRerollContainer", UIParent)
    self.rerollContainer:SetSize(300, 50)
    self.rerollContainer:SetPoint("CENTER", UIParent, "CENTER", db.rerollOffsetX, db.rerollOffsetY)
    self.rerollContainer:SetClampedToScreen(true)
    self.rerollContainer:SetMovable(true)
    self.rerollContainer:Hide()

    self.alertFrame = CreateFrame("Frame", "whisperKeystoneRerollAlert", self.rerollContainer)
    self.alertFrame:SetSize(300, 50)
    self.alertFrame:SetPoint("TOP", self.rerollContainer, "TOP", 0, 0)
    self.alertFrame:Hide()

    self.text = self.alertFrame:CreateFontString(nil, "OVERLAY")
    self.text:SetPoint("CENTER")
    self.text:SetFont(STANDARD_FONT, 24, "OUTLINE")
    self.text:SetShadowColor(0, 0, 0, 0)
    self.text:SetShadowOffset(0, 0)
    self.text:SetText(REMINDER_TEXT.reroll)

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
        if Keystones.isTestMode then return end
        if Keystones.alertFrame then Keystones.alertFrame:Hide() end
        if Keystones.rerollContainer then Keystones.rerollContainer:Hide() end
        if Keystones.rerollTestOverlayCtrl then Keystones.rerollTestOverlayCtrl:Hide() end
    end)
end

function Keystones:ShowReminder(kind)
    kind = kind or "reroll"
    if not self.enabled and not self.isTestMode then return end
    if not REMINDER_TEXT[kind] then return end

    if kind == "reroll" then
        if rerollReminderShown and not self.isTestMode then return end
        rerollReminderShown = true
    elseif kind == "talents" then
        if not self.isTestMode and not IsInPartyGroup() then return end
        if talentReminderShown and not self.isTestMode then return end
        talentReminderShown = true
    end

    if not self.alertFrame then self:EnsureAlertFrameExists() end

    self.text:SetText(REMINDER_TEXT[kind])

    if self.isTestMode then
        self.rerollContainer:SetFrameStrata("DIALOG")
        self.rerollContainer:SetFrameLevel(100)
    else
        self.rerollContainer:SetFrameStrata("FULLSCREEN_DIALOG")
        self.rerollContainer:SetFrameLevel(500)
    end
    self.rerollContainer:Show()
    self:UpdateRerollTestOverlay()

    self.animGroup:Stop()
    self.alertFrame:SetAlpha(1)
    self.alertFrame:Show()
    self.animGroup:Play()
end

function Keystones:ShowRerollReminder()
    self:ShowReminder("reroll")
end

function Keystones:ShowTalentReminder()
    self:ShowReminder("talents")
end

function Keystones:OnChallengeComplete()
    isInActiveChallenge = false
    Interface:Refresh()
    Keystones:ShowRerollReminder()

    C_Timer.After(5, function()
        KeystoneManager:ScanOwnKey()
        KeystoneManager:RequestKeys()
    end)

    C_Timer.After(15, function()
        KeystoneManager:RequestKeys()
    end)
end


-- =========================================================================
-- DATA MANAGEMENT
-- =========================================================================
local function GetPlayerNickname(fullName, shortName)
    -- Find the unit token for this player (needed for TimelineReminders)
    local unitToken = nil
    local myFullName = UnitName("player") .. "-" .. GetRealmName()

    if fullName == myFullName then
        unitToken = "player"
    else
        for i = 1, 4 do
            local partyUnit = "party" .. i
            if UnitExists(partyUnit) then
                local n, r = UnitName(partyUnit)
                r = r or GetRealmName()
                if (n .. "-" .. r) == fullName then
                    unitToken = partyUnit
                    break
                end
            end
        end
    end

    -- 1. TimelineReminders Check
    if unitToken and _G.TimelineReminders and _G.TimelineReminders.GetNickname then
        local trNick = _G.TimelineReminders:GetNickname(unitToken)
        if trNick and trNick ~= "" then return trNick end
    end

    -- 2. NSRT Check
    if _G.NSAPI and _G.NSAPI.GetName then
        local nsrtNick = _G.NSAPI:GetName(fullName, "whisper")
        if nsrtNick and nsrtNick ~= fullName and nsrtNick ~= shortName then
            return nsrtNick
        end
    end

    -- 3. NickTag / ElvUI Check (with cross-realm whitespace fix)
    local cleanFullName = string.gsub(fullName, "%s+", "")
    if _G.NickTag and _G.NickTag.nicknames and _G.NickTag.nicknames[cleanFullName] then
        return _G.NickTag.nicknames[cleanFullName]
    end

    if _G.ElvUI then
        local E = unpack(_G.ElvUI)
        if E and E.GetNickName then
            local elvNick = E:GetNickName(cleanFullName)
            if elvNick and elvNick ~= "" then return elvNick end
        end
    end

    -- 4. Fallback to standard short name
    return shortName
end

function KeystoneManager:GetMapInfo(mapID)
    local info = DUNGEON_DB[mapID]
    local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
    if not name then name = format("Unknown Dungeon (%d)", mapID) end
    local displayName = name
    if (whisperDB.keystones.compactMode or whisperDB.keystones.useAbbreviation or whisperDB.keystones.transparentMode) and info then
        displayName = info.abbr
    end
    if not texture then texture = 525134 end
    return displayName, texture
end

function KeystoneManager:GetTeleportID(mapID)
    local info = DUNGEON_DB[mapID]
    if not info or not info.port then return nil end
    if type(info.port) == "table" then
        local faction = UnitFactionGroup("player")
        if faction == "Alliance" then
            return info.port[1]
        elseif faction == "Horde" then
            return info.port[2]
        else
            return info.port[1]
        end
    end
    return info.port
end

local function GetGroupChannel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function GetMyFullName()
    return UnitName("player") .. "-" .. GetRealmName()
end

local function BuildGroupMemberSet()
    local members = {}
    local myRealm = GetRealmName()
    local myFullName = GetMyFullName()
    members[myFullName] = true

    if not IsInGroup() then
        return members
    end

    local function AddUnit(unit)
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local n, r = UnitName(unit)
            if n then
                r = (r and r ~= "") and r or myRealm
                members[n .. "-" .. r] = true
            end
        end
    end

    if IsInRaid() then
        for i = 1, 40 do
            AddUnit("raid" .. i)
        end
    else
        for i = 1, 4 do
            AddUnit("party" .. i)
        end
    end

    return members
end

function KeystoneManager:IsGroupMember(fullName)
    if not fullName or not IsInGroup() then return false end
    local members = BuildGroupMemberSet()
    if members[fullName] then return true end
    local short = Ambiguate(fullName, "none")
    for name in pairs(members) do
        if Ambiguate(name, "none") == short then return true end
    end
    return false
end

local function NormalizeSenderName(sender)
    if not sender or sender == "" then return nil end
    if type(sender) ~= "string" then return nil end
    if sender:find("-", 1, true) then return sender end

    local myRealm = GetRealmName()
    if Ambiguate(sender, "none") == UnitName("player") then
        return UnitName("player") .. "-" .. myRealm
    end

    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local n, r = UnitName(unit)
            if n and (n == sender or Ambiguate(sender, "short") == n) then
                r = r or myRealm
                return n .. "-" .. r
            end
        end
    end

    return sender .. "-" .. myRealm
end

local function ProcessKeystoneInfo(unitName, info)
    if not info or not info.level or info.level == 0 then return end
    local mapID = info.mythicPlusMapID or info.challengeMapID
    if not mapID or mapID == 0 then return end
    if not unitName or unitName == "" then return end
    KeystoneManager:UpdateEntry(unitName, mapID, info.level)
end

local function OnKeystoneUpdate(arg1, arg2, arg3, arg4)
    if not Keystones.enabled then return end

    if arg1 == "KeystoneUpdate" then
        arg1, arg2, arg3, arg4 = arg2, arg3, arg4, nil
    end

    if type(arg1) == "string" and type(arg2) == "table" and arg2.level then
        ProcessKeystoneInfo(arg1, arg2)
        if type(arg3) == "table" then
            for name, info in pairs(arg3) do
                ProcessKeystoneInfo(name, info)
            end
        end
        return
    end

    if type(arg1) == "table" and arg1.level then
        if type(arg2) == "table" then
            for name, info in pairs(arg2) do
                ProcessKeystoneInfo(name, info)
            end
        end
        return
    end

    if type(arg1) == "table" then
        for name, info in pairs(arg1) do
            if type(info) == "table" then
                ProcessKeystoneInfo(name, info)
            end
        end
    end
end

local function OnLibKeystoneUpdate(keyLevel, keyMap, playerRating, playerName, channel)
    if not Keystones.enabled then return end
    if channel ~= "PARTY" or not IsInGroup() then return end
    if not keyMap or keyMap <= 0 or not keyLevel or keyLevel <= 0 then return end
    if not playerName or playerName == "" then return end
    KeystoneManager:UpdateEntry(playerName, keyMap, keyLevel)
end

function KeystoneManager:OnKeystoneUpdate(arg1, arg2, arg3, arg4)
    OnKeystoneUpdate(arg1, arg2, arg3, arg4)
end

local function EnsureExternalLibs()
    if not ORL then
        ORL = LibStub and LibStub:GetLibrary("LibOpenRaid-1.0", true)
    end
    if ORL and not orlRegistered then
        pcall(function()
            ORL.RegisterCallback(KeystoneManager, "KeystoneUpdate", "OnKeystoneUpdate")
        end)
        orlRegistered = true
    end

    if not LibKeystone then
        LibKeystone = LibStub and LibStub:GetLibrary("LibKeystone", true)
    end
    if LibKeystone and not lksRegistered then
        pcall(function()
            LibKeystone.Register(libKeystoneTable, OnLibKeystoneUpdate)
        end)
        lksRegistered = true
    end
end

function KeystoneManager:UpdateEntry(sender, mapID, level)
    if not sender or not mapID or not level then return end
    mapID = tonumber(mapID)
    level = tonumber(level)
    if not mapID or not level or mapID == 0 or level == 0 then return end

    local fullName = NormalizeSenderName(sender)
    if not fullName then return end

    local myFullName = GetMyFullName()
    local isMe = (fullName == myFullName or Ambiguate(fullName, "none") == UnitName("player"))

    if not IsInGroup() then
        if not isMe then return end
    elseif not isMe and not self:IsGroupMember(fullName) then
        return
    end

    local shortName = fullName:match("(.+)-") or fullName

    -- Run the nickname waterfall check!
    local displayName = GetPlayerNickname(fullName, shortName)

    local _, classFilename = UnitClass(fullName)
    if not classFilename then _, classFilename = UnitClass(shortName) end

    local classColor = C_ClassColor.GetClassColor(classFilename or "PRIEST")

    self.partyData[fullName] = {
        mapID = tonumber(mapID),
        level = tonumber(level),
        displayName = displayName, -- Now utilizing the retrieved nickname
        classColor = classColor,
        isPlayer = isMe
    }
    Interface:Refresh()
end

function KeystoneManager:SyncFromOpenRaid()
    if not IsInGroup() or not ORL or not ORL.GetAllKeystonesInfo then return end
    local all = ORL.GetAllKeystonesInfo()
    if not all then return end
    for unitName, info in pairs(all) do
        local fullName = NormalizeSenderName(unitName) or unitName
        if self:IsGroupMember(fullName) or Ambiguate(fullName, "none") == UnitName("player") then
            ProcessKeystoneInfo(unitName, info)
        end
    end
end

function KeystoneManager:RequestKeys()
    if not IsInGroup() then return end

    self:ScanOwnKey()
    EnsureExternalLibs()

    local channel = GetGroupChannel()
    if channel then
        SendAddonMessage(COMM_PREFIX, "WHISPER:REQ", channel)
    end

    if ORL then
        pcall(function()
            if IsInRaid() and ORL.RequestKeystoneDataFromRaid then
                ORL.RequestKeystoneDataFromRaid()
            elseif ORL.RequestKeystoneDataFromParty then
                ORL.RequestKeystoneDataFromParty()
            end
        end)
        C_Timer.After(0.5, function() KeystoneManager:SyncFromOpenRaid() end)
        C_Timer.After(2.0, function() KeystoneManager:SyncFromOpenRaid() end)
    end

    if LibKeystone then
        pcall(function() LibKeystone.Request("PARTY") end)
    end

    Interface:Refresh()
end

function KeystoneManager:ScanOwnKey()
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel()

    if not mapID or not level or mapID == 0 or level == 0 then
        for bag = 0, 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local itemID = C_Container.GetContainerItemID(bag, slot)
                if itemID and C_Item.IsItemKeystoneByID(itemID) then
                    local itemLink = C_Container.GetContainerItemLink(bag, slot)
                    if itemLink then
                        local strMap, strLevel = itemLink:match("Hkeystone:(%d+):(%d+)")
                        if strMap and strLevel then
                            mapID = tonumber(strMap)
                            level = tonumber(strLevel)
                            break
                        end
                    end
                end
            end
            if mapID and level and mapID > 0 then break end
        end
    end

    if mapID and level and mapID > 0 and level > 0 then
        local myName = UnitName("player") .. "-" .. GetRealmName()
        self:UpdateEntry(myName, mapID, level)
        Comms:Broadcast(mapID, level)
    end
end

function KeystoneManager:CleanParty()
    if Keystones.isTestMode then return end

    local myFullName = GetMyFullName()
    local validMembers = BuildGroupMemberSet()

    for fullName, data in pairs(self.partyData) do
        local isMe = fullName == myFullName or Ambiguate(fullName, "none") == UnitName("player")
        local inScope = isMe
        if IsInGroup() then
            inScope = isMe or validMembers[fullName] or self:IsGroupMember(fullName)
        end
        if not inScope
            or not data.level or data.level == 0
            or not data.mapID or data.mapID == 0 then
            self.partyData[fullName] = nil
        end
    end
    Interface:Refresh()
end

function Comms:Broadcast(mapID, level)
    if not IsInGroup() then return end
    local channel = GetGroupChannel()
    if not channel then return end
    local payload = format("WHISPER:KEY:%d:%d", mapID, level)
    SendAddonMessage(COMM_PREFIX, payload, channel)
end

function Comms:OnMessage(_, prefix, msg, _, sender)
    if prefix ~= COMM_PREFIX then return end
    if Ambiguate(sender, "none") == UnitName("player") then return end
    if Keystones.isTestMode then return end
    if msg == "WHISPER:REQ" then
        KeystoneManager:ScanOwnKey()
        return
    end
    local mapID, level = msg:match("WHISPER:KEY:(%d+):(%d+)")
    if mapID and level and IsInGroup() then
        local fullName = NormalizeSenderName(sender)
        if fullName and (KeystoneManager:IsGroupMember(fullName) or Ambiguate(fullName, "none") == UnitName("player")) then
            KeystoneManager:UpdateEntry(sender, tonumber(mapID), tonumber(level))
        end
    end
end

local function HookExternalKeys()
    for k, v in pairs(_G) do
        if type(k) == "string" and k:match("^SLASH_") then
            if v == "/keys" then
                local cmdName = k:match("^SLASH_(.+)%d+$")
                if cmdName and SlashCmdList[cmdName] then
                    hooksecurefunc(SlashCmdList, cmdName, function()
                        if not Keystones.enabled then return end
                        KeystoneManager:RequestKeys()
                        Interface:Refresh()
                    end)
                    return
                end
            end
        end
    end
end

function Keystones:ToggleTestMode()
    self.isTestMode = not self.isTestMode

    if not self.alertFrame then self:EnsureAlertFrameExists() end

    -- Handle the Reminders preview (Reroll Key?)
    if self.isTestMode then
        self.text:SetText(REMINDER_TEXT.reroll)
        self.rerollContainer:Show()
        self.alertFrame:SetAlpha(1)
        self.alertFrame:Show()
        self.animGroup:Stop()
        self:UpdateRerollTestOverlay()
    else
        self.rerollContainer:Hide()
        if self.rerollTestOverlayCtrl then self.rerollTestOverlayCtrl:Hide() end
        self.alertFrame:Hide()
    end

    if self.isTestMode then
        KeystoneManager.partyData = {}
        local fakePlayers = {
            { name = "Thrall",    class = "SHAMAN", level = 20, map = 501 },
            { name = "Jaina",     class = "MAGE",   level = 24, map = 502 },
            { name = "Sylvanas",  class = "HUNTER", level = 18, map = 503 },
            { name = "Illidan",   class = "DEMONHUNTER", level = 26, map = 504 },
            { name = "Anduin",    class = "PALADIN", level = 15, map = 505 },
        }
        for _, p in ipairs(fakePlayers) do
            local color = C_ClassColor.GetClassColor(p.class)
            KeystoneManager.partyData[p.name] = {
                mapID = p.map,
                level = p.level,
                displayName = p.name,
                classColor = color,
                isPlayer = false
            }
        end
        Interface:Refresh()
        self:UpdateInterfaceTestOverlay()
    else
        rerollReminderShown = false
        talentReminderShown = false
        if self.alertFrame then
            self.animGroup:Stop()
            self.alertFrame:Hide()
        end
        if self.rerollContainer then
            self.rerollContainer:Hide()
        end
        if self.rerollTestOverlayCtrl then self.rerollTestOverlayCtrl:Hide() end
        if Interface.testOverlayCtrl then Interface.testOverlayCtrl:Hide() end
        KeystoneManager.partyData = whisperDB.keystones.partyCache
        KeystoneManager:ScanOwnKey()
        if IsInGroup() then KeystoneManager:RequestKeys() end
        Interface:Refresh()
    end
end

function Keystones:ResetDefaults()
    for k, v in pairs(self.defaults) do
        whisperDB.keystones[k] = v
    end
    -- Reset to a dynamic screen percentage natively
    local sw, sh = UIParent:GetWidth() or GetScreenWidth(), UIParent:GetHeight() or GetScreenHeight()
    whisperDB.keystones.offsetX = sw * DEFAULT_OFFSET_X_RATIO
    whisperDB.keystones.offsetY = sh * DEFAULT_OFFSET_Y_RATIO

    Interface:UpdatePosition()
    Interface:Refresh()

    if self.rerollContainer then
        self.rerollContainer:ClearAllPoints()
        self.rerollContainer:SetPoint("CENTER", UIParent, "CENTER", whisperDB.keystones.rerollOffsetX, whisperDB.keystones.rerollOffsetY)
    end
end

local function CreateKeystoneRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetSize(WIDTH_NORMAL, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, 0)
    row:SetBackdrop({
        bgFile = BAR_TEXTURE,
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })

    local isTransparent = whisperDB.keystones.transparentMode
    if isTransparent then
        row:SetBackdropColor(0, 0, 0, 0)
        row:SetBackdropBorderColor(0, 0, 0, 0)
    else
        row:SetBackdropColor(0.031, 0.031, 0.031, 0.9)
        row:SetBackdropBorderColor(0, 0, 0, 1)
    end

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT, ROW_HEIGHT)
    row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    local iconBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
    iconBorder:SetAllPoints(row.icon)
    iconBorder:SetBackdrop({edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1, bgFile = nil})
    if isTransparent then
        iconBorder:SetBackdropBorderColor(0, 0, 0, 0)
    else
        iconBorder:SetBackdropBorderColor(0, 0, 0, 1)
    end
    iconBorder:SetFrameLevel(row:GetFrameLevel() + 5)

    local overlayBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
    overlayBorder:SetAllPoints(row)
    overlayBorder:SetFrameLevel(row:GetFrameLevel() + 20)
    overlayBorder:SetBackdrop({edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1, bgFile = nil, insets = { left = 0, right = 0, top = 0, bottom = 0 }})
    overlayBorder:SetBackdropBorderColor(0, 0, 0, 0)
    row.overlayBorder = overlayBorder

    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    row.level:SetFont(STANDARD_FONT, 20, "OUTLINE")
    row.level:SetTextColor(1, 1, 1)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetFont(STANDARD_FONT, 13, "OUTLINE")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.dungeon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.dungeon:SetFont(STANDARD_FONT, 14, "OUTLINE")
    row.dungeon:SetTextColor(0.8, 0.8, 0.8)
    row.dungeon:SetJustifyH("LEFT")
    row.dungeon:SetWordWrap(false)

    local buttonName = "WhisperKeystoneButton" .. index
    local secure = CreateFrame("Button", buttonName, row, "InsecureActionButtonTemplate")
    secure:SetAllPoints(row)
    secure:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonUp")
    secure:SetAttribute("type", "spell")
    secure:SetAttribute("spell", nil)
    secure:SetAttribute("type2", nil)

    secure:HookScript("PostClick", function(self, button)
        if button == "RightButton" then
            KeystoneManager:RequestKeys()
        end
    end)

    secure:SetScript("OnEnter", function(self)
        if self.spellID then
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 2, 0)
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()

            local isTransparent = whisperDB.keystones.transparentMode
            if not isTransparent then
                row:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
                if self.info and self.info.classColor then
                    local c = self.info.classColor
                    row.overlayBorder:SetBackdropBorderColor(c.r, c.g, c.b, 1)
                else
                    row.overlayBorder:SetBackdropBorderColor(1, 1, 1, 1)
                end
            end
        end
    end)

    secure:SetScript("OnLeave", function()
        GameTooltip:Hide()
        local isTransparent = whisperDB.keystones.transparentMode
        if isTransparent then
            row:SetBackdropColor(0, 0, 0, 0)
        else
            row:SetBackdropColor(0.031, 0.031, 0.031, 0.9)
        end
        row.overlayBorder:SetBackdropBorderColor(0, 0, 0, 0)
    end)

    row.secure = secure
    return row
end

function Interface:Create()
    if self.container then return end

    local f = CreateFrame("Frame", "whisperKeystonesFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH_NORMAL, 50)
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:SetBackdrop(nil)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not InCombatLockdown() then
            KeystoneManager:RequestKeys()
        end
    end)

    self.container = f
    self.rows = {}

    for i = 1, 5 do
        self.rows[i] = CreateKeystoneRow(f, i)
        self.rows[i]:Hide()
    end
end

function Interface:Refresh()
    if not self.container then self:Create() end
    if not Keystones.enabled and not Keystones.isTestMode then return end

    if InCombatLockdown() then
        self.container:Hide()
        pendingUpdate = true
        return
    end

    local _, instanceType = IsInInstance()
    if instanceType == "raid" then
        self.container:Hide()
        return
    end

    if isInActiveChallenge then
        self.container:Hide()
        return
    end

    local isCompact = whisperDB.keystones.compactMode or whisperDB.keystones.transparentMode
    local growUp = whisperDB.keystones.growUp
    local currentRowWidth = isCompact and WIDTH_COMPACT or WIDTH_NORMAL

    self.container:SetWidth(currentRowWidth)

    local list = {}
    local myFullName = GetMyFullName()
    for fullName, data in pairs(KeystoneManager.partyData) do
        if not data.mapID or not data.level or data.mapID == 0 or data.level == 0 then
            -- skip incomplete cache entries
        elseif not IsInGroup() and fullName ~= myFullName and Ambiguate(fullName, "none") ~= UnitName("player") then
            -- skip non-party entries when solo
        elseif IsInGroup() and fullName ~= myFullName and Ambiguate(fullName, "none") ~= UnitName("player")
            and not KeystoneManager:IsGroupMember(fullName) then
            -- skip players not in current group
        else
        local dName, texture = KeystoneManager:GetMapInfo(data.mapID)
        local portID = KeystoneManager:GetTeleportID(data.mapID)
        tinsert(list, {
            name = data.displayName or "Unknown",
            classColor = data.classColor,
            level = data.level,
            dungeonName = dName,
            texture = texture,
            portID = portID,
            mapID = data.mapID,
            isPlayer = data.isPlayer
        })
        end
    end

    table_sort(list, function(a, b)
        if a.level ~= b.level then
            return a.level > b.level
        end
        if a.isPlayer ~= b.isPlayer then
            return a.isPlayer
        end
        if a.dungeonName ~= b.dungeonName then
            return a.dungeonName < b.dungeonName
        end
        return a.name < b.name
    end)

    local numDisplayed = 0
    local isTransparent = whisperDB.keystones.transparentMode

    for i, data in ipairs(list) do
        if i <= 5 then
            if not self.rows[i] then
                self.rows[i] = CreateKeystoneRow(self.container, i)
            end
            local row = self.rows[i]
            row:Show()
            row:SetWidth(currentRowWidth)
            row:ClearAllPoints()

            if isTransparent then
                row:SetBackdropColor(0, 0, 0, 0)
                row:SetBackdropBorderColor(0, 0, 0, 0)
            else
                row:SetBackdropColor(0.031, 0.031, 0.031, 0.9)
                row:SetBackdropBorderColor(0, 0, 0, 1)
            end

            if growUp then
                local yOffset = ROW_SPACING + ((i - 1) * (ROW_HEIGHT + ROW_SPACING))
                row:SetPoint("BOTTOMLEFT", 0, yOffset)
            else
                local yOffset = -(ROW_SPACING + ((i - 1) * (ROW_HEIGHT + ROW_SPACING)))
                row:SetPoint("TOPLEFT", 0, yOffset)
            end

            row.secure.info = data
            row.secure.spellID = data.portID
            row.icon:SetTexture(data.texture)

            if isCompact then
                -- Safely clip text using our custom UTF-8 function
                row.name:SetText(utf8sub(data.name, 8))
                row.dungeon:SetText(data.dungeonName)

                row.level:ClearAllPoints()
                row.level:SetParent(row)
                row.level:SetDrawLayer("OVERLAY", 7)
                row.level:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
                row.level:SetText(data.level)
                row.level:SetTextColor(1, 1, 1)

                -- Removed the RIGHT anchor for row.name to prevent WoW engine ellipsis
                row.name:ClearAllPoints()
                row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -5)

                -- Keep RIGHT anchor for dungeon so it stays bounded, but increased padding to match left side
                row.dungeon:ClearAllPoints()
                row.dungeon:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 5)
                row.dungeon:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            else
                -- REVERTED to original Default style
                row.name:SetText(data.name)
                row.dungeon:SetText(data.dungeonName)

                row.level:ClearAllPoints()
                row.level:SetParent(row)
                row.level:SetDrawLayer("OVERLAY", 0)
                row.level:SetPoint("RIGHT", -8, 0)
                row.level:SetText("+" .. data.level)

                if data.level >= 20 then
                    row.level:SetTextColor(1, 0.5, 0)
                elseif data.level >= 10 then
                    row.level:SetTextColor(0.64, 0.2, 0.93)
                else
                    row.level:SetTextColor(1, 1, 1)
                end

                -- Name Anchors
                row.name:ClearAllPoints()
                row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -5)
                row.name:SetPoint("RIGHT", row.level, "LEFT", -5, 0)

                -- Dungeon Anchors
                row.dungeon:ClearAllPoints()
                row.dungeon:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -20)
                row.dungeon:SetPoint("RIGHT", row.level, "LEFT", -5, 0)
            end

            if data.classColor then
                row.name:SetTextColor(data.classColor.r, data.classColor.g, data.classColor.b)
            else
                row.name:SetTextColor(1, 1, 1)
            end

            if data.portID and IsSpellKnown(data.portID) then
                row.secure:SetAttribute("spell", data.portID)
                row.secure.spellID = data.portID

                local info = C_Spell.GetSpellCooldown(data.portID)
                local start = info and info.startTime or 0
                local duration = info and info.duration or 0
                local now = GetTime()

                if start > 0 and (start + duration - now > 1.5) then
                    row.icon:SetDesaturated(true)
                    row.icon:SetVertexColor(0.4, 0.4, 0.4)
                else
                    row.icon:SetDesaturated(false)
                    row.icon:SetVertexColor(1, 1, 1)
                end
            else
                row.secure:SetAttribute("spell", nil)
                row.secure.spellID = nil
                row.icon:SetDesaturated(false)
                row.icon:SetVertexColor(1, 1, 1)
            end

            numDisplayed = numDisplayed + 1
        end
    end

    for i = numDisplayed + 1, #self.rows do
        if self.rows[i] then self.rows[i]:Hide() end
    end

    if numDisplayed > 0 then
        self.container:Show()
        local totalHeight = numDisplayed * (ROW_HEIGHT + ROW_SPACING)
        self.container:SetHeight(totalHeight)
    else
        self.container:Hide()
    end

    Keystones:UpdateInterfaceTestOverlay()
end

function Interface:UpdatePosition()
    if not self.container then self:Create() end
    local db = whisperDB.keystones
    local growUp = db.growUp

    self.container:ClearAllPoints()
    if growUp then
        self.container:SetPoint("BOTTOMLEFT", UIParent, "CENTER", db.offsetX, db.offsetY)
    else
        self.container:SetPoint("TOPLEFT", UIParent, "CENTER", db.offsetX, db.offsetY)
    end

    if not Keystones.enabled and not Keystones.isTestMode then self.container:Hide() end
end

function Keystones:Init()
    KeystoneManager.partyData = whisperDB.keystones.partyCache

    if not self.enabled then return end

    -- Prepare the reminder alert frame early
    self:EnsureAlertFrameExists()

    Interface:Create()
    Interface:UpdatePosition()
    KeystoneManager:CleanParty()
    KeystoneManager:ScanOwnKey()
    Interface:Refresh()

    EnsureExternalLibs()
    HookExternalKeys()

    if not RegisterAddonMessagePrefix(COMM_PREFIX) then return end

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(self, event, ...)
            if not Keystones.enabled then return end

            if event == "CHAT_MSG_ADDON" then
                Comms:OnMessage(...)
            elseif event == "BAG_UPDATE" then
                local now = GetTime()
                if now - lastBagScan > 1 then
                    lastBagScan = now
                    KeystoneManager:ScanOwnKey()
                end
            elseif event == "GROUP_ROSTER_UPDATE" then
                KeystoneManager:CleanParty()
                C_Timer.After(1, function() KeystoneManager:RequestKeys() end)
                C_Timer.After(3, function() KeystoneManager:RequestKeys() end)
            elseif event == "PLAYER_ENTERING_WORLD" then
                isInActiveChallenge = C_ChallengeMode.IsChallengeModeActive()
                KeystoneManager:CleanParty()
                KeystoneManager:ScanOwnKey()
                KeystoneManager:RequestKeys()
                Interface:Refresh()
            elseif event == "CHALLENGE_MODE_START" then
                isInActiveChallenge = true
                rerollReminderShown = false
                Interface:Refresh()
            elseif event == "READY_CHECK" then
                if not Keystones.isTestMode and IsInPartyGroup() then
                    Keystones:ShowTalentReminder()
                end
            elseif event == "READY_CHECK_FINISHED" then
                talentReminderShown = false
            elseif event == "CHALLENGE_MODE_COMPLETED_REWARDS" then
                Keystones:OnChallengeComplete()
            elseif event == "CHALLENGE_MODE_COMPLETED" then
                C_Timer.After(0.15, function()
                    if Keystones.enabled and not rerollReminderShown then
                        Keystones:OnChallengeComplete()
                    end
                end)
            elseif event == "CHALLENGE_MODE_RESET" then
                isInActiveChallenge = false
                rerollReminderShown = false
                Interface:Refresh()
            elseif event == "PLAYER_REGEN_ENABLED" then
                if pendingUpdate then
                    pendingUpdate = false
                    Interface:Refresh()
                end
            elseif event == "SPELL_UPDATE_COOLDOWN" then
                local now = GetTime()
                if now - lastCooldownRefresh > 0.5 then
                    lastCooldownRefresh = now
                    Interface:Refresh()
                end
            end
        end)
    end

    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("BAG_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    eventFrame:RegisterEvent("READY_CHECK")
    eventFrame:RegisterEvent("READY_CHECK_FINISHED")
    eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED_REWARDS")
    eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
end

function Keystones:UpdateSettings()
    Interface:UpdatePosition()
    Interface:Refresh()
end

function Keystones:Disable()
    self.enabled = false

    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end

    if Interface.container then
        Interface.container:Hide()
    end

    if self.rerollContainer then
        self.animGroup:Stop()
        rerollReminderShown = false
        talentReminderShown = false
        self.rerollContainer:Hide()
        self.alertFrame:Hide()
        if self.rerollTestOverlayCtrl then self.rerollTestOverlayCtrl:Hide() end
    end

    if Interface.testOverlayCtrl then Interface.testOverlayCtrl:Hide() end

    if whisperDB.keystones then
        whisperDB.keystones.partyCache = KeystoneManager.partyData
    end

    if self.isTestMode then
        self:ToggleTestMode()
    end
end

SLASH_WHISPERMAPS1 = "/cmaps"
SlashCmdList["WHISPERMAPS"] = function()
    local maps = C_ChallengeMode.GetMapTable()
    if maps then
        print("Midnight Season 1 Challenge Map IDs:")
        for _, mapID in ipairs(maps) do
            local name = C_ChallengeMode.GetMapUIInfo(mapID)
            print(mapID, "-", name)
        end
    else
        print("No Challenge Maps found.")
    end
end

-- =========================
-- Config Panel UI
-- =========================
function Keystones:BuildOptionsPanel(content, toggleBtn)
    local db = whisperDB.keystones

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

    local posSection = whisper.GUI.CreateSettingsSection(content, "POSITION", { sliders = 2 })
    posSection:SetPoint("TOPLEFT", toggleBtn, "BOTTOMLEFT", 0, -16)

    local xSlider = whisper.GUI.AddSectionSlider(posSection, nil, "X Offset", -50, 50, 1,
        function() local sw = UIParent:GetWidth() if sw == 0 then return 0 end return math.floor((db.offsetX / sw) * 100 + 0.5) end,
        function(val) local sw = UIParent:GetWidth() db.offsetX = (val / 100) * sw if self.UpdateSettings then self:UpdateSettings() end end
    )

    local ySlider = whisper.GUI.AddSectionSlider(posSection, xSlider, "Y Offset", -50, 50, 1,
        function() local sh = UIParent:GetHeight() if sh == 0 then return 0 end return math.floor((db.offsetY / sh) * 100 + 0.5) end,
        function(val) local sh = UIParent:GetHeight() db.offsetY = (val / 100) * sh if self.UpdateSettings then self:UpdateSettings() end end
    )

    local displaySection = whisper.GUI.CreateSettingsSection(content, "DISPLAY", { contentHeight = 32 })
    displaySection:SetPoint("TOPLEFT", posSection, "BOTTOMLEFT", 0, -whisper.GUI.SECTION_GAP)

    local compactBtn = whisper.GUI.CreateStyledButton(displaySection, "", 140, 24)
    compactBtn:SetPoint("TOPLEFT", displaySection, "TOPLEFT", whisper.GUI.SLIDER_INSET, -whisper.GUI.SLIDER_TOP)

    local function UpdateCompactText()
        if db.transparentMode then
            compactBtn:SetText("Style: Transparent")
            compactBtn:GetFontString():SetTextColor(0.2, 0.8, 1)
        elseif db.compactMode then
            compactBtn:SetText("Style: Compact")
            compactBtn:GetFontString():SetTextColor(1, 0.4, 0.8)
        else
            compactBtn:SetText("Style: Default")
            compactBtn:GetFontString():SetTextColor(0.5, 0.5, 1)
        end
    end
    UpdateCompactText()

    compactBtn:SetScript("OnClick", function()
        if not db.compactMode and not db.transparentMode then db.compactMode = true db.transparentMode = false
        elseif db.compactMode and not db.transparentMode then db.compactMode = false db.transparentMode = true
        else db.compactMode = false db.transparentMode = false end
        UpdateCompactText()
        if self.UpdateSettings then self:UpdateSettings() end
    end)

    local growBtn = whisper.GUI.CreateStyledButton(displaySection, "", 140, 24)
    growBtn:SetPoint("TOPLEFT", compactBtn, "TOPRIGHT", 10, 0)

    local function UpdateGrowText()
        if db.growUp then
            growBtn:SetText("Grow Up")
            growBtn:GetFontString():SetTextColor(0.5, 0.5, 1)
        else
            growBtn:SetText("Grow Down")
            growBtn:GetFontString():SetTextColor(0.5, 0.5, 1)
        end
    end
    UpdateGrowText()

    growBtn:SetScript("OnClick", function()
        db.growUp = not db.growUp
        UpdateGrowText()
        if self.UpdateSettings then self:UpdateSettings() end
    end)

    resetBtn:SetScript("OnClick", function()
        if self.ResetDefaults then
            self:ResetDefaults()
            if xSlider and xSlider.UpdateVisuals then xSlider.UpdateVisuals(math.floor((db.offsetX / UIParent:GetWidth()) * 100 + 0.5)) end
            if ySlider and ySlider.UpdateVisuals then ySlider.UpdateVisuals(math.floor((db.offsetY / UIParent:GetHeight()) * 100 + 0.5)) end
            UpdateCompactText()
            UpdateGrowText()
        end
    end)
end
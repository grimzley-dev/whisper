local addonName, whisper = ...
local Keystones = {}
Keystones.enabled = true
Keystones.isTestMode = false
whisper:RegisterModule("Keystones", Keystones)

local C_ChatInfo = C_ChatInfo
local C_ChallengeMode = C_ChallengeMode
local C_MythicPlus = C_MythicPlus
local C_ClassColor = C_ClassColor
local C_Spell = C_Spell
local UnitName = UnitName
local UnitClass = UnitClass
local UnitInParty = UnitInParty
local UnitFactionGroup = UnitFactionGroup
local GetRealmName = GetRealmName
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

local ORL = LibStub and LibStub:GetLibrary("LibOpenRaid-1.0", true)

local STANDARD_FONT = "Fonts\\FRIZQT__.TTF"
local BAR_TEXTURE = "Interface\\AddOns\\whisper\\Media\\whisperBar.tga"
local ROW_HEIGHT = 38
local ANCHOR_HEIGHT = 12
local ROW_SPACING = 1
local WIDTH_NORMAL = 210
local WIDTH_COMPACT = 110
local COMM_PREFIX = "WHISPER_KEYS"

local DUNGEON_DB = {
    [499] = { abbr = "PSF",   port = 445444 },
    [500] = { abbr = "ROOK",  port = 445443 },
    [501] = { abbr = "SV",    port = 445269 },
    [502] = { abbr = "COT",   port = 445416 },
    [503] = { abbr = "ARAK",  port = 445417 },
    [504] = { abbr = "DFC",   port = 445441 },
    [505] = { abbr = "DAWN",  port = 445414 },
    [506] = { abbr = "BREW",  port = 445440 },
    [525] = { abbr = "FLOOD", port = 1216786 },
    [542] = { abbr = "EDA",   port = 1237215 },
    [399] = { abbr = "RLP",  port = 393256 }, [400] = { abbr = "NO",   port = 393262 },
    [401] = { abbr = "AV",   port = 393279 }, [402] = { abbr = "AA",   port = 393273 },
    [403] = { abbr = "ULD",  port = 393222 }, [404] = { abbr = "NELT", port = 393276 },
    [405] = { abbr = "BH",   port = 393267 }, [406] = { abbr = "HOI",  port = 393283 },
    [463] = { abbr = "FALL", port = 424197 }, [464] = { abbr = "RISE", port = 424197 },
    [375] = { abbr = "MISTS", port = 354464 }, [376] = { abbr = "NW",    port = 354462 },
    [378] = { abbr = "HOA",   port = 354465 }, [382] = { abbr = "TOP",   port = 354467 },
    [391] = { abbr = "STRT",  port = 367416 }, [392] = { abbr = "GMBT",  port = 367416 },
    [244] = { abbr = "AD",    port = 424187 }, [245] = { abbr = "FH",    port = 410071 },
    [247] = { abbr = "ML",    port = {467553, 467555} }, [248] = { abbr = "WM",    port = 424167 },
    [251] = { abbr = "UNDR",  port = 410074 }, [353] = { abbr = "SIEGE", port = {445418, 464256} },
    [370] = { abbr = "WORK",  port = 373274 }, [369] = { abbr = "JUNKY", port = 373274 },
    [198] = { abbr = "DHT", port = 424163 }, [199] = { abbr = "BRH", port = 424153 },
    [200] = { abbr = "HOV", port = 393764 }, [206] = { abbr = "NL",  port = 410078 },
    [210] = { abbr = "COS", port = 393766 },
    [165] = { abbr = "SBG", port = 159899 }, [168] = { abbr = "EB",  port = 159901 },
    [166] = { abbr = "GRIM", port = 159900 }, [169] = { abbr = "DOCKS", port = 159896 },
    [2]   = { abbr = "TJS", port = 131204 }, [438] = { abbr = "VP",  port = 410080 },
    [456] = { abbr = "TOT", port = 424142 }, [507] = { abbr = "GB",  port = 445424 },
}

local KeystoneManager = { partyData = {} }
local Comms = {}
local Interface = { rows = {} }
local eventFrame
local pendingUpdate = false
local isInActiveChallenge = false
local lastBagScan = 0
local lastCooldownRefresh = 0

function KeystoneManager:GetMapInfo(mapID)
    local info = DUNGEON_DB[mapID]
    local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
    if not name then name = format("Unknown Dungeon (%d)", mapID) end
    local displayName = name
    if (whisperDB.keystones.compactMode or whisperDB.keystones.useAbbreviation) and info then
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

function KeystoneManager:UpdateEntry(sender, mapID, level)
    if not sender or not mapID or not level then return end
    local fullName = sender
    if not string.find(fullName, "-") then
        fullName = fullName .. "-" .. GetRealmName()
    end
    local _, classFilename = UnitClass(sender)
    local classColor = C_ClassColor.GetClassColor(classFilename or "PRIEST")
    self.partyData[fullName] = {
        mapID = tonumber(mapID),
        level = tonumber(level),
        displayName = sender:match("(.+)-") or sender,
        classColor = classColor,
        isPlayer = UnitIsUnit(sender, "player")
    }
    Interface:Refresh()
end

function KeystoneManager:ScanOpenRaid()
    if not ORL then return end
    for i = 1, 4 do
        local unitID = "party"..i
        if UnitExists(unitID) then
            local name, realm = UnitName(unitID)
            if not realm then realm = GetRealmName() end
            local fullName = name .. "-" .. realm
            local info = ORL.GetKeystoneInfo(fullName)
            if not info then info = ORL.GetKeystoneInfo(name) end
            if info and info.challengeMapID and info.challengeMapID > 0 then
                self:UpdateEntry(fullName, info.challengeMapID, info.level)
            end
        end
    end
end

function KeystoneManager:ScanOwnKey()
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel()
    if mapID and level then
        local myName = UnitName("player")
        self:UpdateEntry(myName, mapID, level)
        Comms:Broadcast(mapID, level)
    end
end

function KeystoneManager:CleanParty()
    if Keystones.isTestMode then return end
    local myFullName = UnitName("player") .. "-" .. GetRealmName()
    for fullName, _ in pairs(self.partyData) do
        local shortName = fullName:match("(.+)-")
        if fullName ~= myFullName and not UnitInParty(shortName) then
            self.partyData[fullName] = nil
        end
    end
    Interface:Refresh()
end

function Comms:Broadcast(mapID, level)
    if not IsInGroup() then return end
    local payload = format("WHISPER:KEY:%d:%d", mapID, level)
    SendAddonMessage(COMM_PREFIX, payload, "PARTY")
end

function Comms:Request()
    if not IsInGroup() then return end
    SendAddonMessage(COMM_PREFIX, "WHISPER:REQ", "PARTY")
    if ORL then
        pcall(function() ORL.RequestKeystoneDataFromParty() end)
        KeystoneManager:ScanOpenRaid()
    end
end

function Comms:OnMessage(_, prefix, msg, _, sender)
    if prefix ~= COMM_PREFIX then return end
    if sender == UnitName("player") then return end
    if Keystones.isTestMode then return end
    if msg == "WHISPER:REQ" then
        KeystoneManager:ScanOwnKey()
        return
    end
    local mapID, level = msg:match("WHISPER:KEY:(%d+):(%d+)")
    if mapID and level then
        KeystoneManager:UpdateEntry(sender, mapID, level)
    end
end

local function HookExternalKeys()
    for k, v in pairs(_G) do
        if type(k) == "string" and k:match("^SLASH_") then
            if v == "/keys" then
                local cmdName = k:match("^SLASH_(.+)%d+$")
                if cmdName and SlashCmdList[cmdName] then
                    hooksecurefunc(SlashCmdList, cmdName, function()
                        KeystoneManager:ScanOpenRaid()
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
    if Interface.anchor then
        if self.isTestMode then
            Interface.anchor:Show()
            Interface.anchor:EnableMouse(true)
            Interface.anchor:SetFrameLevel(Interface.container:GetFrameLevel() + 20)
        else
            Interface.anchor:Hide()
            Interface.anchor:EnableMouse(false)
        end
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
    else
        KeystoneManager.partyData = whisperDB.keystones.partyCache
        KeystoneManager:ScanOwnKey()
        if IsInGroup() then Comms:Request() end
        Interface:Refresh()
    end
end

function Keystones:ResetDefaults()
    local db = whisperDB.keystones
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    db.compactMode = false
    db.growUp = false
    db.useAbbreviation = false
    db.offsetX = -(sw * 0.499)
    db.offsetY = (sh * 0.08)
    Interface:UpdatePosition()
    Interface:Refresh()
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
    row:SetBackdropColor(0.031, 0.031, 0.031, 0.9)
    row:SetBackdropBorderColor(0, 0, 0, 1)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT, ROW_HEIGHT)
    row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    local iconBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
    iconBorder:SetAllPoints(row.icon)
    iconBorder:SetBackdrop({edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1, bgFile = nil})
    iconBorder:SetBackdropBorderColor(0, 0, 0, 1)
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
            KeystoneManager:ScanOpenRaid()
            Interface:Refresh()
        end
    end)

    secure:SetScript("OnEnter", function(self)
        if self.spellID then
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 2, 0)
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
            row:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
            if self.info and self.info.classColor then
                local c = self.info.classColor
                row.overlayBorder:SetBackdropBorderColor(c.r, c.g, c.b, 1)
            else
                row.overlayBorder:SetBackdropBorderColor(1, 1, 1, 1)
            end
        end
    end)

    secure:SetScript("OnLeave", function()
        GameTooltip:Hide()
        row:SetBackdropColor(0.031, 0.031, 0.031, 0.9)
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

    local anchor = CreateFrame("Frame", nil, f, "BackdropTemplate")
    anchor:SetSize(WIDTH_NORMAL - 20, ANCHOR_HEIGHT)
    anchor:SetPoint("BOTTOM", f, "TOP", 0, 1)
    anchor:SetBackdrop({
        bgFile = BAR_TEXTURE,
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    anchor:SetBackdropColor(0.031, 0.031, 0.031, 0.9)
    anchor:SetBackdropBorderColor(0, 0, 0, 1)
    anchor:EnableMouse(false)
    anchor:SetMovable(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:Hide()

    local anchorText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    anchorText:SetPoint("CENTER", 0, 1)
    anchorText:SetFont(STANDARD_FONT, 12)
    anchorText:SetText("ANCHOR")
    anchorText:SetTextColor(1, 1, 1)

    anchor:SetScript("OnDragStart", function() f:StartMoving() end)
    anchor:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local growUp = whisperDB.keystones.growUp
        local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
        if sw > 0 and sh > 0 then
            local left = f:GetLeft()
            local y = growUp and f:GetBottom() or f:GetTop()
            whisperDB.keystones.offsetX = left - (sw / 2)
            whisperDB.keystones.offsetY = y - (sh / 2)
            Interface:UpdatePosition()
        end
    end)

    self.container = f
    self.anchor = anchor
    self.rows = {}

    for i = 1, 5 do
        self.rows[i] = CreateKeystoneRow(f, i)
        self.rows[i]:Hide()
    end
end

function Interface:Refresh()
    if not self.container then self:Create() end

    if InCombatLockdown() then
        pendingUpdate = true
        return
    end

    if isInActiveChallenge then
        self.container:Hide()
        return
    end

    local isCompact = whisperDB.keystones.compactMode
    local growUp = whisperDB.keystones.growUp
    local currentRowWidth = isCompact and WIDTH_COMPACT or WIDTH_NORMAL

    self.container:SetWidth(currentRowWidth)
    self.anchor:SetWidth(currentRowWidth - 20)

    self.anchor:ClearAllPoints()
    if growUp then
        self.anchor:SetPoint("BOTTOM", self.container, "BOTTOM", 0, 0)
    else
        self.anchor:SetPoint("TOP", self.container, "TOP", 0, 0)
    end

    local list = {}
    for fullName, data in pairs(KeystoneManager.partyData) do
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
    for i, data in ipairs(list) do
        if i <= 5 then
            if not self.rows[i] then
                self.rows[i] = CreateKeystoneRow(self.container, i)
            end
            local row = self.rows[i]
            row:Show()
            row:SetWidth(currentRowWidth)
            row:ClearAllPoints()

            if growUp then
                local yOffset = ANCHOR_HEIGHT + ROW_SPACING + ((i - 1) * (ROW_HEIGHT + ROW_SPACING))
                row:SetPoint("BOTTOMLEFT", 0, yOffset)
            else
                local yOffset = -(ANCHOR_HEIGHT + ROW_SPACING + ((i - 1) * (ROW_HEIGHT + ROW_SPACING)))
                row:SetPoint("TOPLEFT", 0, yOffset)
            end

            row.secure.info = data
            row.secure.spellID = data.portID
            row.icon:SetTexture(data.texture)

            if isCompact then
                local display = data.name
                if len(display) > 8 then display = sub(display, 1, 8) end
                row.name:SetText(display)
                row.dungeon:SetText(data.dungeonName)

                row.level:ClearAllPoints()
                row.level:SetParent(row)
                row.level:SetDrawLayer("OVERLAY", 7)
                row.level:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
                row.level:SetText(data.level)
                row.level:SetTextColor(1, 1, 1)

                row.name:ClearAllPoints()
                row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -5)
                row.dungeon:ClearAllPoints()
                row.dungeon:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -20)
                row.dungeon:SetPoint("RIGHT", -5, 0)
            else
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

                row.name:ClearAllPoints()
                row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -5)

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

    if not Keystones.isTestMode and whisperDB.keystones.hideInInstance then
        local _, instanceType = IsInInstance()
        if instanceType == "party" or instanceType == "raid" or instanceType == "pvp" then
            self.container:Hide()
            return
        end
    end

    if numDisplayed > 0 then
        self.container:Show()
        local totalHeight = ANCHOR_HEIGHT + (numDisplayed * (ROW_HEIGHT + ROW_SPACING))
        self.container:SetHeight(totalHeight)
    else
        self.container:Hide()
    end
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

    if not Keystones.enabled then self.container:Hide() end
end

function Keystones:Init()
    if not whisperDB.keystones then whisperDB.keystones = {} end
    local db = whisperDB.keystones
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()

    local DB_VERSION = 1
    if not db.version or db.version < DB_VERSION then
        db.version = DB_VERSION
    end

    if not db.partyCache then db.partyCache = {} end
    KeystoneManager.partyData = db.partyCache

    if db.useAbbreviation == nil then db.useAbbreviation = false end
    if db.compactMode == nil then db.compactMode = false end
    if db.growUp == nil then db.growUp = false end
    if db.hideInInstance == nil then db.hideInInstance = false end
    if db.offsetX == nil then db.offsetX = -(sw * 0.499) end
    if db.offsetY == nil then db.offsetY = (sh * 0.08) end

    Interface:Create()
    Interface:UpdatePosition()
    Interface:Refresh()

    if ORL then
        local function OnKeystoneUpdate(unitName, info)
            if not info or not info.challengeMapID or info.challengeMapID == 0 then return end
            KeystoneManager:UpdateEntry(unitName, info.challengeMapID, info.level)
        end
        ORL.RegisterCallback(addonName, "KeystoneUpdate", OnKeystoneUpdate)
    end

    HookExternalKeys()

    if not RegisterAddonMessagePrefix(COMM_PREFIX) then return end

    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("BAG_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")

    eventFrame:SetScript("OnEvent", function(self, event, ...)
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
            C_Timer.After(1, function() Comms:Request() end)
        elseif event == "PLAYER_ENTERING_WORLD" then
            isInActiveChallenge = C_ChallengeMode.IsChallengeModeActive()
            KeystoneManager:CleanParty()
            Comms:Request()
            Interface:Refresh()
        elseif event == "CHALLENGE_MODE_START" then
            isInActiveChallenge = true
            Interface:Refresh()
        elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET" then
            isInActiveChallenge = false
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

    KeystoneManager:ScanOwnKey()
end

function Keystones:UpdateSettings()
    Interface:UpdatePosition()
    Interface:Refresh()
end

function Keystones:Disable()
    self.enabled = false
    if Interface.container then Interface.container:Hide() end
    if whisperDB.keystones then
        whisperDB.keystones.partyCache = KeystoneManager.partyData
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event)
    Keystones:Init()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
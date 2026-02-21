local addonName, whisper = ...
local Essentials = {}
whisper:RegisterModule("Essentials", Essentials)

-- =========================================================================
-- CONFIG & CONSTANTS (Global to file)
-- =========================================================================
local tinsert = table.insert
local ipairs = ipairs
local pairs = pairs
local sort = table.sort

-- Localize WoW APIs for Performance
local UnitBuff = UnitBuff
local UnitClass = UnitClass
local UnitIsUnit = UnitIsUnit
local UnitExists = UnitExists
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsConnected = UnitIsConnected
local UnitIsVisible = UnitIsVisible
local UnitPowerType = UnitPowerType
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetNumGroupMembers = GetNumGroupMembers
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsInInstance = IsInInstance
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local IsPlayerSpell = IsPlayerSpell
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local GetInventoryItemID = GetInventoryItemID
local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount
local GetItemIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon
local C_UnitAuras_GetAuraDataBySpellName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
local C_UnitAuras_GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local C_Spell_GetSpellInfo = C_Spell and C_Spell.GetSpellInfo
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture

-- Duration Threshold (5 minutes)
local THRESHOLD_SECONDS = 300

-- =========================================================================
-- TEXTURE CACHING
-- =========================================================================
local textureCache = {}

local function GetCachedSpellTexture(spellID)
    if not spellID then return nil end
    local key = "spell_" .. spellID
    if not textureCache[key] then
        textureCache[key] = GetSpellTexture(spellID)
    end
    return textureCache[key]
end

local function GetCachedItemIcon(itemID)
    if not itemID then return nil end
    local key = "item_" .. itemID
    if not textureCache[key] then
        textureCache[key] = GetItemIcon(itemID)
    end
    return textureCache[key]
end

-- =========================================================================
-- UTILITY FUNCTIONS
-- =========================================================================

local function IsUnitEligibleForBuff(unit, filterFunc)
    if not UnitExists(unit) then return false end
    if UnitIsDeadOrGhost(unit) then return false end
    if not UnitIsConnected(unit) then return false end
    if not UnitIsVisible(unit) then return false end
    if filterFunc and not filterFunc(unit) then return false end
    return true
end

-- Advanced Aura Checker: Scans for a list of Spell IDs or an Icon ID.
local function CheckAura(unit, spellIDs, iconID, requirePlayerSource)
    local timeRemaining = nil
    local hasBuff = false

    for i = 1, 40 do
        if C_UnitAuras_GetAuraDataByIndex then
            local aura = C_UnitAuras_GetAuraDataByIndex(unit, i, "HELPFUL")
            if not aura then break end

            local match = false
            if iconID and aura.icon == iconID then match = true end
            if spellIDs then
                for _, sid in ipairs(spellIDs) do
                    if aura.spellId == sid then match = true; break end
                end
            end

            if match then
                if requirePlayerSource and aura.sourceUnit ~= "player" then
                    -- Skip this aura, we didn't cast it
                else
                    hasBuff = true
                    if aura.expirationTime and aura.expirationTime > 0 then
                        timeRemaining = aura.expirationTime - GetTime()
                    end
                    return hasBuff, timeRemaining
                end
            end
        else
            -- Legacy Fallback for older API
            local name, icon, _, _, _, expirationTime, source, _, _, sid = UnitBuff(unit, i)
            if not name then break end

            local match = false
            if iconID and icon == iconID then match = true end
            if spellIDs then
                for _, checkSid in ipairs(spellIDs) do
                    if sid == checkSid then match = true; break end
                end
            end

            if match then
                if requirePlayerSource and source ~= "player" then
                    -- Skip
                else
                    hasBuff = true
                    if expirationTime and expirationTime > 0 then
                        timeRemaining = expirationTime - GetTime()
                    end
                    return hasBuff, timeRemaining
                end
            end
        end
    end
    return false, nil
end

-- Scans the entire group to see if YOU cast a specific buff on SOMEONE.
local function CheckTargetedAura(spellIDs)
    local has, remain = CheckAura("player", spellIDs, nil, true)
    if has then return true, remain end

    if IsInGroup() then
        local prefix = IsInRaid() and "raid" or "party"
        for i = 1, GetNumGroupMembers() do
            local unit = prefix .. i
            if not UnitIsUnit(unit, "player") then
                has, remain = CheckAura(unit, spellIDs, nil, true)
                if has then return true, remain end
            end
        end
    end
    return false, nil
end

local function IsPlayerEligible(dbEntry)
    if dbEntry.playerFilter and not dbEntry.playerFilter() then return false end

    if dbEntry.excludeIfSpellKnown then
        for _, spellID in ipairs(dbEntry.excludeIfSpellKnown) do
            if IsPlayerSpell(spellID) then return false end
        end
    end
    if dbEntry.talentFilter then
        if not IsPlayerSpell(dbEntry.talentFilter) then return false end
    end
    if dbEntry.specFilter then
        local currentSpec = GetSpecialization()
        local specID = currentSpec and GetSpecializationInfo(currentSpec) or 0
        local match = false
        for _, allowed in ipairs(dbEntry.specFilter) do
            if specID == allowed then match = true; break end
        end
        if not match then return false end
    end
    return true
end

local function IsOffhandEnchantable()
    local offhandID = GetInventoryItemID("player", 17)
    if not offhandID then return false end

    local info = { C_Item.GetItemInfo(offhandID) }
    if #info > 0 then
        local classID = info[12]
        return classID == 2 -- 2 is Enum.ItemClass.Weapon
    end
    return false
end

-- =========================================================================
-- ESSENTIALS CORE MANAGER
-- =========================================================================
Essentials.subModules = {}
Essentials.isTestMode = false

function Essentials:Init()
    for name, mod in pairs(self.subModules) do
        if mod.enabled ~= false and mod.Init then
            mod:Init()
        end
    end
end

function Essentials:Disable()
    self.enabled = false
    for name, mod in pairs(self.subModules) do
        if mod.Disable then mod:Disable() end
    end
end

function Essentials:ToggleTestMode()
    self.isTestMode = not self.isTestMode
    for name, mod in pairs(self.subModules) do
        if mod.enabled ~= false and mod.ToggleTestMode then
            mod:ToggleTestMode(self.isTestMode)
        end
    end
end

-- =========================================================================
-- SUB-MODULE: RAID BUFFS & CONSUMABLES
-- =========================================================================
local RaidBuffs = {
    enabled = true,
    iconPool = {},
    activeIcons = {},
    updateTimer = nil,
    playerClass = nil,
    isTesting = false,

    ICON_SIZE = 60,
    SPACING = 1,
    POS_X = 1,
    POS_Y = -1,
    UPDATE_THROTTLE = 0.2
}
Essentials.subModules["Raid Buffs & Consumables"] = RaidBuffs

local function IsManaUser(unit) return UnitPowerType(unit) == 0 end

local function IsAttackPowerUser(unit)
    local _, class = UnitClass(unit)
    if class == "WARRIOR" or class == "HUNTER" or class == "ROGUE" or
       class == "MONK" or class == "DEMONHUNTER" or class == "DEATHKNIGHT" then
        return true
    end
    if class == "DRUID" or class == "PALADIN" or class == "SHAMAN" then
        local role = UnitGroupRolesAssigned(unit)
        if role == "TANK" then return true end
        if role == "HEALER" then return false end
    end
    return false
end

local function HasClassInGroup(classToFind)
    if RaidBuffs.playerClass == classToFind then return true end
    if not IsInGroup() then return false end
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, GetNumGroupMembers() do
        local unit = prefix .. i
        local _, class = UnitClass(unit)
        if class == classToFind and UnitIsConnected(unit) then return true end
    end
    return false
end

local function UsesManaOil()
    local _, class = UnitClass("player")
    if class == "SHAMAN" then return false end -- Shamans handle their own imbues
    if class == "ROGUE" then return true end
    if class == "MAGE" or class == "WARLOCK" or class == "PRIEST" or class == "EVOKER" then return true end
    local spec = GetSpecialization()
    if not spec then return false end
    if class == "DRUID" and (spec == 1 or spec == 4) then return true end
    if class == "PALADIN" and spec == 1 then return true end
    if class == "MONK" and spec == 2 then return true end
    return false
end

local function UsesWhetstone()
    local _, class = UnitClass("player")
    if class == "SHAMAN" or class == "ROGUE" then return false end -- Excluded classes
    if class == "WARRIOR" or class == "HUNTER" or class == "DEATHKNIGHT" or class == "DEMONHUNTER" then return true end
    local spec = GetSpecialization()
    if not spec then return false end
    if class == "DRUID" and (spec == 2 or spec == 3) then return true end
    if class == "PALADIN" and (spec == 2 or spec == 3) then return true end
    if class == "MONK" and (spec == 1 or spec == 3) then return true end
    return false
end

-- RAID BUFF COVERAGE DB
RaidBuffs.DB = {
    { spellIDs = {1126, 432661}, classes = { "DRUID" }, filter = nil },
    { spellIDs = {1459, 432778}, classes = { "MAGE" }, filter = IsManaUser },
    { spellIDs = {21562}, classes = { "PRIEST" }, filter = nil },
    { spellIDs = {6673}, classes = { "WARRIOR" }, filter = IsAttackPowerUser },
    { spellIDs = {381732, 381741, 381746, 381748, 381749, 381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758}, classes = { "EVOKER" }, filter = nil },
    { spellIDs = {462854}, classes = { "SHAMAN" }, filter = nil },
}

-- SELF/TARGETED CLASS UTILITY DB
RaidBuffs.CLASS_DB = {
    ["DRUID"] = {
        { checkType = "targeted", spellIDs = { 474750 }, specFilter = { 105 }, talentFilter = 474750 } -- Symbiotic Relationship
    },
    ["ROGUE"] = {
        { checkType = "roguePoisons" }
    },
    ["SHAMAN"] = {
        -- Enhancement (Windfury/Flametongue Imbues)
        { checkType = "weaponEnchant", spellIDs = {33757}, specFilter = { 263 } },
        -- Elemental/Restoration (Flametongue/Earthliving OR Mana Oil)
        { checkType = "weaponEnchant", itemID = 224107, specFilter = { 262, 264 } },
        -- Shields
        { checkType = "aura", spellIDs = { 192106, 52127 }, specFilter = { 262, 263 } },
        -- Earth Shield (Resto casts on others)
        { checkType = "targeted", spellIDs = { 974 }, specFilter = { 264 } }
    },
    ["PALADIN"] = {
        { checkType = "aura", spellIDs = { 465, 317920, 32223 } }, -- Base Auras (Devotion is now the base icon)
        { checkType = "targeted", spellIDs = { 53563, 156910, 200025 }, specFilter = { 65 } } -- Holy Paladin Beacons
    },
}

-- PLAYER CONSUMABLES / INVENTORY DB
RaidBuffs.CONSUMABLES = {
    {
        key = "Food",
        checkType = "icon",
        iconID = 136000, -- Standard Well Fed icon
    },
    {
        key = "Flask",
        checkType = "aura",
        spellIDs = { 431971, 431972, 431973, 431974, 431975, 431976, 432021 }, -- TWW Flasks
    },
    {
        key = "Augment Rune",
        checkType = "aura",
        spellIDs = { 1234969, 1242347 },
    },
    {
        key = "Mana Oil",
        checkType = "weaponEnchant",
        itemID = 224107, -- Algari Mana Oil
        playerFilter = UsesManaOil,
    },
    {
        key = "Whetstone",
        checkType = "weaponEnchant",
        itemIDs = { 222504, 222510 }, -- Ironclaw Whetstone & Weightstone
        playerFilter = UsesWhetstone,
    },
    {
        key = "Healthstone",
        checkType = "item",
        itemID = 5512,
        requireClass = "WARLOCK"
    },
    {
        key = "Gateway Control Shard",
        checkType = "item",
        itemID = 188152,
    }
}

function RaidBuffs:Init()
    _, self.playerClass = UnitClass("player")

    self.frame = CreateFrame("Frame", "whisperRaidBuffsFrame", UIParent)
    self.frame:SetSize(1, 1)
    self.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", self.POS_X, self.POS_Y)

    self.frame:RegisterEvent("UNIT_AURA")
    self.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.frame:RegisterEvent("UNIT_INVENTORY_CHANGED") -- For weapon enchants
    self.frame:RegisterEvent("BAG_UPDATE") -- For healthstones/items

    self.frame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_DISABLED" then
            self:UpdateDisplay()
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:RequestUpdate()
        elseif event == "UNIT_AURA" then
            if unit == "player" or (unit and (string.find(unit, "party") or string.find(unit, "raid"))) then
                self:RequestUpdate()
            end
        else
            self:RequestUpdate()
        end
    end)

    self:RequestUpdate()
end

function RaidBuffs:Disable()
    if self.frame then
        self.frame:UnregisterAllEvents()
        self.frame:Hide()
    end
end

function RaidBuffs:ToggleTestMode(state)
    self.isTesting = state
    self:UpdateDisplay()
end

function RaidBuffs:RequestUpdate()
    if self.updateTimer then return end
    self.updateTimer = C_Timer.NewTimer(self.UPDATE_THROTTLE, function()
        self:UpdateDisplay()
        self.updateTimer = nil
    end)
end

function RaidBuffs:UpdateDisplay()
    for _, icon in ipairs(self.iconPool) do icon:Hide() end
    self.activeIcons = {}

    if InCombatLockdown() then return end

    if self.isTesting then
        self:RunTestMode()
        self:LayoutIcons()
        return
    end

    self:CheckMissingBuffs()
    self:LayoutIcons()
end

function RaidBuffs:RunTestMode()
    -- 1. CLASS UTILITY BUFFS (Self & Targeted)
    local classChecks = self.CLASS_DB[self.playerClass]
    if classChecks then
        for _, check in ipairs(classChecks) do
            if IsPlayerEligible(check) then
                local foundTex = nil
                if check.checkType == "roguePoisons" then
                    foundTex = GetCachedSpellTexture(315584) -- Default Instant Poison Icon
                else
                    foundTex = (check.itemIDs and GetCachedItemIcon(check.itemIDs[1])) or (check.itemID and GetCachedItemIcon(check.itemID)) or (check.spellIDs and GetCachedSpellTexture(check.spellIDs[1])) or check.icon
                end
                if foundTex then
                    self:AddIcon(foundTex)
                end
            end
        end
    end

    -- 2. CONSUMABLES (Food, Flasks, Healthstones, Runes, Generic Weapon Buffs)
    for _, cons in ipairs(self.CONSUMABLES) do
        if IsPlayerEligible(cons) then
            local iconTex = (cons.itemIDs and GetCachedItemIcon(cons.itemIDs[1])) or (cons.itemID and GetCachedItemIcon(cons.itemID)) or (cons.spellIDs and GetCachedSpellTexture(cons.spellIDs[1])) or cons.iconID
            if iconTex then
                self:AddIcon(iconTex)
            end
        end
    end

    -- 3. RAID BUFFS
    for _, info in ipairs(self.DB) do
        if IsPlayerEligible(info) then
            local texture = GetCachedSpellTexture(info.spellIDs[1])
            if texture then
                self:AddIcon(texture)
            end
        end
    end
end

function RaidBuffs:CheckMissingBuffs()
    -- 1. CLASS UTILITY BUFFS (Self & Targeted)
    local classChecks = self.CLASS_DB[self.playerClass]
    if classChecks then
        for _, check in ipairs(classChecks) do
            if IsPlayerEligible(check) then
                local isMissing = false
                local isExpiring = false
                local foundTex = nil

                if check.checkType == "weaponEnchant" then
                    local hasMain, _, _, _, hasOff = GetWeaponEnchantInfo()
                    local count = 0
                    if hasMain then count = count + 1 end
                    if hasOff then count = count + 1 end

                    if count < (check.minRequired or 1) then
                        isMissing = true
                        foundTex = (check.itemIDs and GetCachedItemIcon(check.itemIDs[1])) or (check.itemID and GetCachedItemIcon(check.itemID)) or (check.spellIDs and GetCachedSpellTexture(check.spellIDs[1])) or check.icon
                    end
                elseif check.checkType == "aura" then
                    local has, remain = CheckAura("player", check.spellIDs, nil, false)
                    if not has then
                        isMissing = true
                        foundTex = GetCachedSpellTexture(check.spellIDs[1])
                    elseif remain and remain <= THRESHOLD_SECONDS then
                        isExpiring = true
                        foundTex = GetCachedSpellTexture(check.spellIDs[1])
                    end
                elseif check.checkType == "targeted" then
                    local has, remain = CheckTargetedAura(check.spellIDs)
                    if not has then
                        isMissing = true
                        foundTex = GetCachedSpellTexture(check.spellIDs[1])
                    elseif remain and remain <= THRESHOLD_SECONDS then
                        isExpiring = true
                        foundTex = GetCachedSpellTexture(check.spellIDs[1])
                    end
                elseif check.checkType == "roguePoisons" then
                    -- 381801 is the Dragon-Tempered Blades talent spell ID
                    local expectedPerCategory = IsPlayerSpell(381801) and 2 or 1

                    local damagePoisons = { 315584, 2823 } -- Instant, Deadly
                    local utilityPoisons = { 8679, 381637, 3408, 108211, 5761 } -- Wound, Atrophic, Crippling, Leeching, Numbing

                    local damageCount = 0
                    local utilityCount = 0
                    local hasExpiringPoison = false

                    for _, pid in ipairs(damagePoisons) do
                        local has, remain = CheckAura("player", {pid}, nil, false)
                        if has then
                            damageCount = damageCount + 1
                            if remain and remain <= THRESHOLD_SECONDS then hasExpiringPoison = true end
                        end
                    end

                    for _, pid in ipairs(utilityPoisons) do
                        local has, remain = CheckAura("player", {pid}, nil, false)
                        if has then
                            utilityCount = utilityCount + 1
                            if remain and remain <= THRESHOLD_SECONDS then hasExpiringPoison = true end
                        end
                    end

                    if damageCount < expectedPerCategory or utilityCount < expectedPerCategory then
                        isMissing = true
                        foundTex = GetCachedSpellTexture(315584) -- Default to Instant Poison Icon
                    elseif hasExpiringPoison then
                        isExpiring = true
                        foundTex = GetCachedSpellTexture(315584)
                    end
                end

                if isMissing or isExpiring then
                    self:AddIcon(foundTex)
                end
            end
        end
    end

    -- 2. CONSUMABLES (Food, Flasks, Healthstones, Runes, Generic Weapon Buffs)
    for _, cons in ipairs(self.CONSUMABLES) do
        local isMissing = false
        local isExpiring = false
        local iconTex = nil

        if cons.requireClass and not HasClassInGroup(cons.requireClass) then
            -- Skip if required class isn't in group
        elseif IsPlayerEligible(cons) then
            if cons.checkType == "icon" then
                local has, remain = CheckAura("player", nil, cons.iconID, false)
                iconTex = cons.iconID
                if not has then
                    isMissing = true
                elseif remain and remain <= THRESHOLD_SECONDS then
                    isExpiring = true
                end
            elseif cons.checkType == "item" then
                if cons.itemIDs then
                    local hasAny = false
                    for _, iID in ipairs(cons.itemIDs) do
                        if GetItemCount(iID) > 0 then
                            hasAny = true
                            break
                        end
                    end
                    if not hasAny then isMissing = true end
                    iconTex = GetCachedItemIcon(cons.itemIDs[1])
                else
                    if GetItemCount(cons.itemID) == 0 then
                        isMissing = true
                    end
                    iconTex = GetCachedItemIcon(cons.itemID)
                end
            elseif cons.checkType == "aura" then
                local has, remain = CheckAura("player", cons.spellIDs, nil, false)
                if not has then
                    isMissing = true
                elseif remain and remain <= THRESHOLD_SECONDS then
                    isExpiring = true
                end
                iconTex = GetCachedSpellTexture(cons.spellIDs[1])
            elseif cons.checkType == "weaponEnchant" then
                local hasMain, _, _, _, hasOff = GetWeaponEnchantInfo()
                if not hasMain then
                    isMissing = true
                elseif IsOffhandEnchantable() and not hasOff then
                    isMissing = true
                end

                if isMissing then
                    iconTex = (cons.itemIDs and GetCachedItemIcon(cons.itemIDs[1])) or (cons.itemID and GetCachedItemIcon(cons.itemID)) or (cons.spellIDs and GetCachedSpellTexture(cons.spellIDs[1])) or cons.iconID
                end
            end

            if isMissing or isExpiring then
                self:AddIcon(iconTex)
            end
        end
    end

    -- 3. RAID BUFFS
    local numGroupMembers = GetNumGroupMembers()
    local isInGroup = IsInGroup()
    local prefix = IsInRaid() and "raid" or "party"

    for _, info in ipairs(self.DB) do
        local texture = GetCachedSpellTexture(info.spellIDs[1])

        if IsPlayerEligible(info) then
            local amProvider = false
            for _, class in ipairs(info.classes) do
                if self.playerClass == class then amProvider = true break end
            end

            if amProvider then
                local missingCount = 0
                local playerIsExpiring = false

                -- Check Self
                if IsUnitEligibleForBuff("player", info.filter) then
                    local has, remain = CheckAura("player", info.spellIDs, nil, false)
                    if not has then
                        missingCount = missingCount + 1
                    elseif remain and remain <= THRESHOLD_SECONDS then
                        playerIsExpiring = true
                    end
                end

                -- Check Group
                if isInGroup then
                    for i = 1, numGroupMembers do
                        local unit = prefix .. i
                        if not UnitIsUnit(unit, "player") then
                            if IsUnitEligibleForBuff(unit, info.filter) then
                                local has = CheckAura(unit, info.spellIDs, nil, false)
                                if not has then
                                    missingCount = missingCount + 1
                                end
                            end
                        end
                    end
                end

                if missingCount > 0 or playerIsExpiring then
                    self:AddIcon(texture)
                end
            else
                -- Receiver Logic (Someone else provides it)
                local providerAvailable = false
                for _, class in ipairs(info.classes) do
                    if HasClassInGroup(class) then providerAvailable = true break end
                end

                if providerAvailable then
                    if IsUnitEligibleForBuff("player", info.filter) then
                        local has, remain = CheckAura("player", info.spellIDs, nil, false)
                        if not has or (remain and remain <= THRESHOLD_SECONDS) then
                            self:AddIcon(texture)
                        end
                    end
                end
            end
        end
    end
end

-- =========================================================================
-- SUB-MODULE UI HELPERS
-- =========================================================================

function RaidBuffs:AddIcon(texture)
    if not texture then return end
    local icon = self:GetFreeIcon()

    icon.texture:SetTexture(texture)
    icon:Show()
    tinsert(self.activeIcons, icon)
end

function RaidBuffs:GetFreeIcon()
    for _, icon in ipairs(self.iconPool) do
        if not icon:IsShown() then return icon end
    end

    local icon = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    icon:SetSize(self.ICON_SIZE, self.ICON_SIZE)

    icon:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    icon:SetBackdropColor(0, 0, 0, 0)
    icon:SetBackdropBorderColor(0, 0, 0, 1)

    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetPoint("TOPLEFT", 1, -1)
    icon.texture:SetPoint("BOTTOMRIGHT", -1, 1)
    icon.texture:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    -- Missing glow animation
    if not icon.glow then
        local glow = icon:CreateTexture(nil, "OVERLAY")
        glow:SetTexture("Interface\\AddOns\\WeakAuras\\PowerAurasMedia\\Auras\\Aura145")
        glow:SetPoint("CENTER")
        glow:SetSize(self.ICON_SIZE * 1.3, self.ICON_SIZE * 1.3)
        glow:SetVertexColor(1, 1, 1, 1)
        glow:SetBlendMode("ADD")

        local ag = glow:CreateAnimationGroup()
        local a1 = ag:CreateAnimation("Alpha")
        a1:SetFromAlpha(0.5)
        a1:SetToAlpha(1)
        a1:SetDuration(0.5)
        a1:SetSmoothing("IN_OUT")
        a1:SetOrder(1)
        ag:SetLooping("BOUNCE")
        ag:Play()
        icon.glow = glow
    end

    tinsert(self.iconPool, icon)
    return icon
end

function RaidBuffs:LayoutIcons()
    local numIcons = #self.activeIcons
    if numIcons == 0 then
        self.frame:SetWidth(1)
        return
    end

    local totalWidth = (numIcons * self.ICON_SIZE) + ((numIcons - 1) * self.SPACING)
    self.frame:SetWidth(totalWidth)
    self.frame:SetHeight(self.ICON_SIZE)

    for i, icon in ipairs(self.activeIcons) do
        icon:ClearAllPoints()
        if i == 1 then
            icon:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
        else
            icon:SetPoint("LEFT", self.activeIcons[i-1], "RIGHT", self.SPACING, 0)
        end
    end
end

-- =========================================================================
-- SUB-MODULE: COMBAT ALERTS
-- =========================================================================
local CombatAlerts = {
    enabled = true,
    isTesting = false,
    showCrosshair = true -- Toggle state for future config integration
}
Essentials.subModules["Combat Alerts"] = CombatAlerts

function CombatAlerts:Init()
    -- Load saved config states
    if whisperDB and whisperDB.essentials and whisperDB.essentials["Combat Alerts_Crosshair"] ~= nil then
        self.showCrosshair = whisperDB.essentials["Combat Alerts_Crosshair"]
    end

    -- Ensure the main text alert frame is created
    if not self.frame then
        self.frame = CreateFrame("Frame", "whisperCombatAlertsFrame", UIParent)
        self.frame:SetSize(200, 50)
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        self.frame:Hide()

        self.text = self.frame:CreateFontString(nil, "OVERLAY")
        self.text:SetPoint("CENTER")
        self.text:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
        self.text:SetShadowColor(0, 0, 0, 0)
        self.text:SetShadowOffset(0, 0)

        self.animGroup = self.frame:CreateAnimationGroup()

        local fadeIn = self.animGroup:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.4)
        fadeIn:SetOrder(1)

        local hold = self.animGroup:CreateAnimation("Alpha")
        hold:SetFromAlpha(1)
        hold:SetToAlpha(1)
        hold:SetDuration(1.7)
        hold:SetOrder(2)

        local fadeOut = self.animGroup:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(0.4)
        fadeOut:SetOrder(3)

        self.animGroup:SetScript("OnFinished", function()
            if not self.isTesting then
                self.frame:Hide()
            end
        end)
    end

    -- Ensure the crosshair frame is created
    if not self.crosshair then
        local ch = CreateFrame("Frame", "whisperCombatCrosshair", UIParent)
        ch:SetSize(25, 25)
        ch:SetFrameStrata("HIGH")
        ch:SetPoint("CENTER", UIParent, "CENTER", 0, -30)

        local hBorder = ch:CreateTexture(nil, "BACKGROUND")
        hBorder:SetColorTexture(0, 0, 0, 1)
        hBorder:SetSize(20, 5)
        hBorder:SetPoint("CENTER")

        local vBorder = ch:CreateTexture(nil, "BACKGROUND")
        vBorder:SetColorTexture(0, 0, 0, 1)
        vBorder:SetSize(5, 20)
        vBorder:SetPoint("CENTER")

        local hFill = ch:CreateTexture(nil, "ARTWORK")
        hFill:SetColorTexture(1, 1, 1, 0.8)
        hFill:SetSize(18, 3)
        hFill:SetPoint("CENTER")

        local vFill = ch:CreateTexture(nil, "ARTWORK")
        vFill:SetColorTexture(1, 1, 1, 0.8)
        vFill:SetSize(3, 18)
        vFill:SetPoint("CENTER")

        ch:Hide()
        self.crosshair = ch
    end

    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")

    self.frame:SetScript("OnEvent", function(_, event)
        if self.isTesting then return end
        self:TriggerAlert(event == "PLAYER_REGEN_DISABLED")
    end)
end

function CombatAlerts:TriggerAlert(entering)
    self.animGroup:Stop()
    if entering then
        self.text:SetText("+Combat")
        self.text:SetTextColor(1, 1, 1, 1) -- White
        if self.showCrosshair then
            self.crosshair:Show()
        end
    else
        self.text:SetText("-Combat")
        self.text:SetTextColor(0.6, 0.6, 0.6, 1) -- Grey Shade
        if self.crosshair then
            self.crosshair:Hide()
        end
    end
    self.frame:SetAlpha(0)
    self.frame:Show()
    self.animGroup:Play()
end

function CombatAlerts:Disable()
    if self.frame then
        self.frame:UnregisterAllEvents()
        self.frame:Hide()
        self.animGroup:Stop()
    end
    if self.crosshair then
        self.crosshair:Hide()
    end
end

function CombatAlerts:ToggleTestMode(state)
    self.isTesting = state
    if self.isTesting then
        if not self.frame then self:Init() end
        self.frame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        self.frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        self.animGroup:Stop()

        self.text:SetText("+Combat")
        self.text:SetTextColor(1, 1, 1, 1)
        self.frame:SetAlpha(1)
        self.frame:Show()

        if self.showCrosshair and self.crosshair then
            self.crosshair:Show()
        end
    else
        if self.frame then
            self.frame:Hide()
            self.frame:SetAlpha(0)
            if self.enabled then
                self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
                self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
            end
        end
        if self.crosshair then
            self.crosshair:Hide()
        end
    end
end
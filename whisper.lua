local addonName, whisper = ...
whisper.modules = {}
whisperDB = whisperDB or {}
whisperDB.modules = whisperDB.modules or {}

-- =========================================================================
-- FONT RESOLUTION
-- =========================================================================
local FONT_CANDIDATES = {
    "Interface\\AddOns\\whisper\\Media\\Fonts\\Expressway.ttf",
    "Interface\\AddOns\\whisper\\Media\\Fonts\\Expressway.TTF",
}

function whisper:ResolveFontPath()
    if self._resolvedFontPath then
        return self._resolvedFontPath
    end

    local function IsFontUsable(path)
        if not path or path == "" then return false end
        local probe = UIParent:CreateFontString(nil, "ARTWORK")
        probe:SetFont(path, 12, "OUTLINE")
        local ok = probe:GetFont() ~= nil
        probe:Hide()
        return ok
    end

    local sharedMedia = LibStub and LibStub("LibSharedMedia-3.0", true)
    if sharedMedia then
        local smPath = sharedMedia:Fetch("font", "Expressway")
        if IsFontUsable(smPath) then
            self._resolvedFontPath = smPath
            return smPath
        end
    end

    for _, path in ipairs(FONT_CANDIDATES) do
        if IsFontUsable(path) then
            self._resolvedFontPath = path
            return path
        end
    end

    self._resolvedFontPath = "Fonts\\FRIZQT__.TTF"
    return self._resolvedFontPath
end

function whisper:GetFont()
    return self.Style.STANDARD_FONT
end

function whisper:RefreshStandardFont()
    self.Style.STANDARD_FONT = self:ResolveFontPath()
end

-- =========================================================================
-- MASTER STYLE TABLE
-- =========================================================================
whisper.Style = {
    STANDARD_FONT = "Interface\\AddOns\\whisper\\Media\\Fonts\\Expressway.ttf",
    BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8",
    
    Backdrop = {
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    },
    
    Colors = {
        Background = {8/255, 8/255, 8/255, 0.8},
        Border = {0, 0, 0, 1},
        LogoAlpha = 0.5,
        
        -- System Colors
        Addon = "|cff999999",
        Enabled = "|cff4AB044",
        Disabled = "|cffC7404C",
        White = "|cffffffff",
        Reset = "|r"
    }
}

local COLOR_ADDON = whisper.Style.Colors.Addon
local COLOR_ENABLED = whisper.Style.Colors.Enabled
local COLOR_DISABLED = whisper.Style.Colors.Disabled
local COLOR_RESET = whisper.Style.Colors.Reset

-- =========================================================================
-- DATABASE DEFAULTS MERGER
-- =========================================================================
local function MergeDefaults(target, defaults)
    if type(defaults) ~= "table" then return end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            MergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

-- =========================================================================
-- ADDON LOADING & INITIALIZATION
-- =========================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            whisper:RefreshStandardFont()
            whisper:InitModules()
        end
    elseif event == "PLAYER_LOGIN" then
        whisper:RefreshStandardFont()
    end
end)

function whisper:RegisterModule(name, module)
    self.modules[name] = module
    if whisperDB.modules[name] == nil then
        whisperDB.modules[name] = (module.enabled ~= false)
    end
    module.enabled = whisperDB.modules[name]
end

function whisper:InitModules()
    whisperDB.modules = whisperDB.modules or {}

    for name, module in pairs(self.modules) do
        -- Sync the module's state from the database
        if whisperDB.modules[name] ~= nil then
            module.enabled = whisperDB.modules[name]
        end

        -- Map the database key (module.dbKey, or derived from module name)
        local dbKey = module.dbKey or name:gsub("%s+", ""):gsub("^%u", string.lower)

        if module.defaults then
            whisperDB[dbKey] = whisperDB[dbKey] or {}
            MergeDefaults(whisperDB[dbKey], module.defaults)
            module.db = whisperDB[dbKey] -- Give the module an easy reference to its DB!
        end

        if module.Init and module.enabled then
            local success, err = pcall(module.Init, module)
            if not success then
                print(COLOR_ADDON .. "whisper" .. COLOR_RESET .. " Error initializing " .. name .. ": " .. tostring(err))
            end
        end
    end
end

-- =========================================================================
-- SLASH COMMANDS
-- =========================================================================
SLASH_SHH1 = "/shh"
SlashCmdList["SHH"] = function(msg)
    msg = msg and msg:lower() or ""
    whisperDB.modules = whisperDB.modules or {}
    local args = {strsplit(" ", msg)}
    local cmd = args[1] or ""
    local target = args[2] or ""

    if cmd == "" or cmd == "config" or cmd == "settings" or cmd == "options" then
        if whisper.OpenSettings then whisper:OpenSettings() else print(COLOR_ADDON .. "whisper" .. COLOR_RESET .. " Settings panel not loaded yet") end
        return
    end

    if cmd == "help" then
        print(COLOR_ADDON .. "whisper" .. COLOR_RESET .. " Commands:")
        print("  /shh - Open config panel")
        print("  /shh enable <module> - Enable module")
        print("  /shh disable <module> - Disable module")
        print("  /shh test <module> - Toggle test mode")
        return
    end

    if cmd == "test" then
        if target == "" then print(COLOR_ADDON .. "whisper" .. COLOR_RESET .. " Usage: /shh test <module>") return end
        local modName
        for name, module in pairs(whisper.modules) do
            if name:lower():find(target, 1, true) == 1 then modName = name break end
        end
        if modName then
            local module = whisper.modules[modName]
            if module.ToggleTestMode then
                module:ToggleTestMode()
                local dName = module.displayName or modName
                print(COLOR_ADDON .. "whisper" .. COLOR_RESET .. " " .. dName .. " Test Mode: " .. (module.isTestMode and COLOR_ENABLED .. "ON" or COLOR_DISABLED .. "OFF") .. COLOR_RESET)
            else
                print(COLOR_ADDON .. "whisper" .. COLOR_RESET .. " Module '" .. modName .. "' does not support Test Mode.")
            end
        else
            print(COLOR_ADDON .. "whisper" .. COLOR_RESET .. " Module '" .. target .. "' not found.")
        end
        return
    end

    if cmd == "enable" or cmd == "disable" then
        if target == "" then return end
        local modName
        for name, module in pairs(whisper.modules) do
            if name:lower():find(target, 1, true) == 1 then modName = name break end
        end

        if modName then
            local module = whisper.modules[modName]
            local dName = module.displayName or modName
            if cmd == "enable" then
                whisperDB.modules[modName] = true
                module.enabled = true
                print(COLOR_ADDON .. "whisper" .. COLOR_RESET .. " " .. dName .. " » " .. COLOR_ENABLED .. "ENABLED" .. COLOR_RESET .. " (Reload UI)")
            else
                whisperDB.modules[modName] = false
                if module.Disable then pcall(module.Disable, module) else module.enabled = false end
                print(COLOR_ADDON .. "whisper" .. COLOR_RESET .. " " .. dName .. " » " .. COLOR_DISABLED .. "DISABLED" .. COLOR_RESET)
            end
            return
        end
    end
end
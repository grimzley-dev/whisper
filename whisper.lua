local addonName, whisper = ...
whisper.modules = {}
whisperDB = whisperDB or {}
whisperDB.modules = whisperDB.modules or {}

-- =========================================================================
-- MASTER STYLE TABLE
-- =========================================================================
whisper.Style = {
    STANDARD_FONT = "Fonts\\FRIZQT__.TTF",
    BAR_TEXTURE = "Interface\\AddOns\\AtrocityMedia\\StatusBars\\Atrocity",
    
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
-- ADDON LOADING & INITIALIZATION
-- =========================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            whisperDB.deaths = whisperDB.deaths or {
                offsetX = 0,
                offsetY = 150,
                limit = 5,
                growUp = true
            }
            whisper:InitModules()
        end
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

        -- CORE FIX: Sync the module's state from the database after it has loaded
        if whisperDB.modules[name] ~= nil then
            module.enabled = whisperDB.modules[name]
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

    if cmd == "config" or cmd == "settings" or cmd == "options" then
        if whisper.OpenSettings then
            whisper:OpenSettings()
        else
            print(COLOR_ADDON .. "whisper" .. COLOR_RESET .. " Settings panel not loaded yet")
        end
        return
    end

    if cmd == "help" then
        print(COLOR_ADDON .. "whisper" .. COLOR_RESET .. " Commands:")
        print("  /shh - Show status")
        print("  /shh enable <module> - Enable module")
        print("  /shh disable <module> - Disable module")
        print("  /shh test <module> - Toggle test mode (e.g., /shh test loot)")
        return
    end

    -- TEST COMMAND HANDLER
    if cmd == "test" then
        if target == "" then
            print(COLOR_ADDON .. "whisper" .. COLOR_RESET .. " Usage: /shh test <module>")
            return
        end

        local modName
        for name, module in pairs(whisper.modules) do
            if name:lower():find(target, 1, true) == 1 then
                modName = name
                break
            end
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

    -- ENABLE / DISABLE / STATUS (Simplified)
    if cmd == "enable" or cmd == "disable" then
        if target == "" then return end
        local modName
        for name, module in pairs(whisper.modules) do
            if name:lower():find(target, 1, true) == 1 then
                modName = name
                break
            end
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

    -- Status Print
    print(COLOR_ADDON .. "whisper" .. COLOR_RESET .. " Modules:")
    for name, module in pairs(whisper.modules) do
        local enabled = module.enabled
        local statusColor = enabled and COLOR_ENABLED or COLOR_DISABLED
        local dName = module.displayName or name
        print(string.format("  • %s%s%s » %s%s%s", whisper.Style.Colors.White, dName, COLOR_RESET, statusColor, enabled and "ENABLED" or "DISABLED", COLOR_RESET))
    end
end
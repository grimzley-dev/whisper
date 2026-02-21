local addonName, whisper = ...

-- Localize Global API for Performance
local CreateFrame = CreateFrame
local tinsert = tinsert
local table_sort = table.sort
local pcall = pcall
local print = print
local tonumber = tonumber
local tostring = tostring
local math = math

-- =========================================================================
-- CONFIGURATION CONSTANTS
-- =========================================================================
local CONFIG_WIDTH = 650
local CONFIG_HEIGHT = 450
local SIDEBAR_WIDTH = 180
local CONTENT_PADDING = 20

local STANDARD_FONT = "Fonts\\FRIZQT__.TTF"
local BAR_TEXTURE = "Interface\\AddOns\\whisper\\Media\\whisperBar.tga"

local COLOR_ADDON = "|cff999999"
local COLOR_ENABLED = "|cff4AB044"
local COLOR_DISABLED = "|cffC7404C"
local COLOR_RESET = "|r"

local COLOR_RED = {1, 0.2, 0.2}
local COLOR_GREEN = {0, 1, 0.2}
local COLOR_WHITE = {1, 1, 1}
local COLOR_PURPLE = {0.5, 0.5, 1}
local COLOR_CYAN = {0.2, 0.8, 1}

-- State Variables
local configFrame, launcherPanel
local moduleButtons = {}
local currentModule = nil

local Style = whisper.Style or {
    STANDARD_FONT = "Fonts\\FRIZQT__.TTF",
    Backdrop = { bgFile = "Interface/Buttons/WHITE8X8", edgeFile = nil, edgeSize = 0 },
    Colors = {
        Background = {0.1, 0.1, 0.1, 0.9},
        Border = {0, 0, 0, 1},
        LogoAlpha = 0.5,
        Addon = "|cff999999",
        Enabled = "|cff4AB044",
        Disabled = "|cffC7404C",
        White = "|cffffffff",
        Reset = "|r"
    }
}

-- =========================================================================
-- UI COMPONENT FACTORIES
-- =========================================================================

local function CreateStyledButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetText(text)
    btn:SetPushedTextOffset(0, 0)

    local fs = btn:GetFontString() or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    btn:SetFontString(fs)
    fs:SetPoint("CENTER", 0, 0)
    fs:SetFont(Style.STANDARD_FONT, 14, "OUTLINE")
    fs:SetTextColor(1, 1, 1)

    btn:SetBackdrop(Style.Backdrop)
    btn:SetBackdropColor(unpack(Style.Colors.Background))
    btn:SetBackdropBorderColor(unpack(Style.Colors.Border))

    btn.textColor = Style.Colors.White

    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            self:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
            self:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(Style.Colors.Background))
        self:SetBackdropBorderColor(unpack(Style.Colors.Border))
    end)
    return btn
end

local function CreateMinimalButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, height)

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("CENTER", 0, 2)
    fs:SetFont(STANDARD_FONT, 20, "OUTLINE")
    fs:SetText(text)
    fs:SetTextColor(1, 1, 1)
    btn:SetFontString(fs)

    btn:SetScript("OnEnter", function(self) fs:SetTextColor(0.8, 0.8, 0.8) end)
    btn:SetScript("OnLeave", function(self) fs:SetTextColor(1, 1, 1) end)

    return btn
end

local function CreateCustomSlider(parent, label, minVal, maxVal, step, getFunc, setFunc)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(420, 50)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetFont(STANDARD_FONT, 12, "OUTLINE")
    title:SetText(label)
    title:SetTextColor(0.8, 0.8, 0.8)

    local controls = CreateFrame("Frame", nil, frame)
    controls:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    controls:SetSize(420, 30)

    -- LEFT: Minus Button
    local minusBtn = CreateMinimalButton(controls, "-", 32, 32)
    minusBtn:SetPoint("LEFT", 0, 0)

    -- RIGHT: EditBox
    local editBox = CreateFrame("EditBox", nil, controls)
    editBox:SetSize(50, 20)
    editBox:SetPoint("RIGHT", 0, 0)
    editBox:SetFont(STANDARD_FONT, 12, "OUTLINE")
    editBox:SetJustifyH("CENTER")
    editBox:SetAutoFocus(false)
    editBox:SetTextColor(1, 1, 1)

    -- MIDDLE-RIGHT: Plus Button
    local plusBtn = CreateMinimalButton(controls, "+", 32, 32)
    plusBtn:SetPoint("RIGHT", editBox, "LEFT", -2, -1)

    -- MIDDLE: Slider Bar
    local sliderBg = controls:CreateTexture(nil, "BACKGROUND")
    sliderBg:SetTexture(BAR_TEXTURE)
    sliderBg:SetVertexColor(0.2, 0.2, 0.2, 1)
    sliderBg:SetHeight(6)

    sliderBg:SetPoint("LEFT", minusBtn, "RIGHT", -4, 0)
    sliderBg:SetPoint("RIGHT", plusBtn, "LEFT", 0, 0)

    local slider = CreateFrame("Slider", nil, controls)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("LEFT", sliderBg, "LEFT")
    slider:SetPoint("RIGHT", sliderBg, "RIGHT")
    slider:SetPoint("CENTER", sliderBg, "CENTER")
    slider:SetHeight(30)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetHitRectInsets(0, 0, -10, -10)

    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetTexture(BAR_TEXTURE)
    thumb:SetVertexColor(0.6, 0.6, 0.6, 1)
    thumb:SetSize(40, 10)
    slider:SetThumbTexture(thumb)

    local isInternalUpdate = false
    local function UpdateVisuals(val)
        isInternalUpdate = true
        slider:SetValue(val)
        editBox:SetText(tostring(val))
        isInternalUpdate = false
    end

    editBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            if val < minVal then val = minVal end
            if val > maxVal then val = maxVal end
            setFunc(val)
            UpdateVisuals(val)
        else
            UpdateVisuals(getFunc())
        end
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        UpdateVisuals(getFunc())
    end)
    slider:SetScript("OnValueChanged", function(self, value)
        if isInternalUpdate then return end
        local mult = 1 / step
        value = math.floor(value * mult + 0.5) / mult
        setFunc(value)
        editBox:SetText(tostring(value))
    end)
    minusBtn:SetScript("OnClick", function()
        local current = getFunc()
        local newVal = current - step
        if newVal < minVal then newVal = minVal end
        setFunc(newVal)
        UpdateVisuals(newVal)
    end)
    plusBtn:SetScript("OnClick", function()
        local current = getFunc()
        local newVal = current + step
        if newVal > maxVal then newVal = maxVal end
        setFunc(newVal)
        UpdateVisuals(newVal)
    end)

    UpdateVisuals(getFunc())

    -- Store reference to UpdateVisuals for external updates
    frame.UpdateVisuals = UpdateVisuals

    return frame
end

local function CreateModuleButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetPushedTextOffset(0, 0)

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    btn:SetFontString(fs)
    fs:SetPoint("LEFT", 15, 0)
    fs:SetJustifyH("LEFT")
    fs:SetFont(Style.STANDARD_FONT, 13, "OUTLINE")
    fs:SetText(text)
    fs:SetTextColor(0.6, 0.6, 0.6)

    btn:SetBackdrop(Style.Backdrop)
    btn:SetBackdropColor(0, 0, 0, 0)
    btn:SetBackdropBorderColor(0, 0, 0, 0)

    function btn:Select()
        fs:SetTextColor(1, 1, 1)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    end
    function btn:Deselect()
        fs:SetTextColor(0.6, 0.6, 0.6)
        self:SetBackdropColor(0, 0, 0, 0)
    end

    btn:SetScript("OnEnter", function(self)
        if fs:GetTextColor() < 1 then
            fs:SetTextColor(0.8, 0.8, 0.8)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if self:GetBackdropColor() == 0 then
            fs:SetTextColor(0.6, 0.6, 0.6)
        else
            fs:SetTextColor(1, 1, 1)
        end
    end)
    return btn
end

local function CreateModuleContent(parent, moduleName, module)
    if parent.currentContent then
        parent.currentContent:Hide()
        parent.currentContent:SetParent(nil)
        parent.currentContent = nil
    end

    local content = CreateFrame("Frame", nil, parent)
    content:SetPoint("TOPLEFT", CONTENT_PADDING, -CONTENT_PADDING)
    content:SetPoint("BOTTOMRIGHT", -CONTENT_PADDING, CONTENT_PADDING)
    parent.currentContent = content

    local title = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetFont(Style.STANDARD_FONT, 18, "OUTLINE")
    title:SetText(moduleName)
    title:SetTextColor(1, 1, 1)

    -- Create master toggle button for standard modules (Excludes Utilities & Essentials)
    local toggleBtn
    if module and moduleName ~= "Essentials" then
        toggleBtn = CreateStyledButton(content, "", 100, 24)
        toggleBtn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -15)

        local function UpdateToggleText()
            if module.enabled then
                toggleBtn:SetText("ENABLED")
                toggleBtn:GetFontString():SetTextColor(unpack(COLOR_GREEN))
            else
                toggleBtn:SetText("DISABLED")
                toggleBtn:GetFontString():SetTextColor(unpack(COLOR_RED))
            end
        end
        UpdateToggleText()

        toggleBtn:SetScript("OnClick", function()
            module.enabled = not module.enabled
            if module.enabled and module.Init then module:Init()
            elseif not module.enabled and module.Disable then module:Disable() end
            UpdateToggleText()
        end)
    end

    -- Module-specific UI
    if moduleName == "Death Tracker" then
        local db = whisperDB.deathTracker
        local yStart = -80

        local testBtn = CreateStyledButton(content, "Test", 80, 24)
        testBtn:SetPoint("TOPLEFT", toggleBtn, "TOPRIGHT", 10, 0)
        testBtn:GetFontString():SetTextColor(1, 1, 1)
        testBtn:SetScript("OnClick", function()
            if module.ToggleTestMode then
                module:ToggleTestMode()
                if module.isTestMode then
                    testBtn:SetText("End")
                    testBtn:GetFontString():SetTextColor(unpack(COLOR_RED))
                else
                    testBtn:SetText("Test")
                    testBtn:GetFontString():SetTextColor(1, 1, 1)
                end
            end
        end)

        module.testButton = testBtn

        -- Reset Button
        local resetBtn = CreateStyledButton(content, "Reset", 80, 24)
        resetBtn:SetPoint("TOPLEFT", testBtn, "TOPRIGHT", 10, 0)
        resetBtn:GetFontString():SetTextColor(0.7, 0.7, 0.7)

        -- Sliders
        local sliderRefs = {}
        local xSlider = CreateCustomSlider(content, "X Offset", -100, 100, 1,
            function() return db.offsetX end,
            function(val) db.offsetX = val; if module.UpdateSettings then module:UpdateSettings() end end
        )
        xSlider:SetPoint("TOPLEFT", 0, yStart)
        sliderRefs.xSlider = xSlider

        local ySlider = CreateCustomSlider(content, "Y Offset", -100, 100, 1,
            function() return db.offsetY end,
            function(val) db.offsetY = val; if module.UpdateSettings then module:UpdateSettings() end end
        )
        ySlider:SetPoint("TOPLEFT", 0, yStart - 60)
        sliderRefs.ySlider = ySlider

        local limitSlider = CreateCustomSlider(content, "Death Limit", 1, 20, 1,
            function() return db.limit end,
            function(val) db.limit = val; if module.UpdateSettings then module:UpdateSettings() end end
        )
        limitSlider:SetPoint("TOPLEFT", 0, yStart - 120)
        sliderRefs.limitSlider = limitSlider

        local growBtn = CreateStyledButton(content, "", 100, 24)
        growBtn:SetPoint("TOPLEFT", 0, yStart - 180)

        local function UpdateGrowText()
            if db.growUp then
                growBtn:SetText("Grow Up")
                growBtn:GetFontString():SetTextColor(unpack(COLOR_PURPLE))
            else
                growBtn:SetText("Grow Down")
                growBtn:GetFontString():SetTextColor(unpack(COLOR_PURPLE))
            end
        end
        UpdateGrowText()

        growBtn:SetScript("OnClick", function()
            db.growUp = not db.growUp
            UpdateGrowText()
            if module.UpdateSettings then module:UpdateSettings() end
        end)

        resetBtn:SetScript("OnClick", function()
            if module.ResetDefaults then
                module:ResetDefaults()
                if sliderRefs.xSlider and sliderRefs.xSlider.UpdateVisuals then sliderRefs.xSlider.UpdateVisuals(db.offsetX) end
                if sliderRefs.ySlider and sliderRefs.ySlider.UpdateVisuals then sliderRefs.ySlider.UpdateVisuals(db.offsetY) end
                if sliderRefs.limitSlider and sliderRefs.limitSlider.UpdateVisuals then sliderRefs.limitSlider.UpdateVisuals(db.limit) end
                UpdateGrowText()
            end
        end)

    elseif moduleName == "Keystones" then
        local yStart = -80
        local db = whisperDB.keystones

        -- TEST BUTTON
        local testBtn = CreateStyledButton(content, "Test", 80, 24)
        testBtn:SetPoint("TOPLEFT", toggleBtn, "TOPRIGHT", 10, 0)

        local function UpdateTestText()
            if module.isTestMode then
                testBtn:SetText("End")
                testBtn:GetFontString():SetTextColor(unpack(COLOR_RED))
            else
                testBtn:SetText("Test")
                testBtn:GetFontString():SetTextColor(1, 1, 1)
            end
        end

        testBtn:SetScript("OnClick", function()
            if module.ToggleTestMode then
                module:ToggleTestMode()
                UpdateTestText()
            end
        end)

        module.testButton = testBtn

        -- Reset Button
        local resetBtn = CreateStyledButton(content, "Reset", 80, 24)
        resetBtn:SetPoint("TOPLEFT", testBtn, "TOPRIGHT", 10, 0)
        resetBtn:GetFontString():SetTextColor(0.7, 0.7, 0.7)

        -- Sliders
        local xSlider = CreateCustomSlider(content, "X Offset", -50, 50, 1,
            function()
                local sw = UIParent:GetWidth()
                if sw == 0 then return 0 end
                return math.floor((db.offsetX / sw) * 100 + 0.5)
            end,
            function(val)
                local sw = UIParent:GetWidth()
                db.offsetX = (val / 100) * sw
                if module.UpdateSettings then module:UpdateSettings() end
            end
        )
        xSlider:SetPoint("TOPLEFT", 0, yStart)

        local ySlider = CreateCustomSlider(content, "Y Offset", -50, 50, 1,
            function()
                local sh = UIParent:GetHeight()
                if sh == 0 then return 0 end
                return math.floor((db.offsetY / sh) * 100 + 0.5)
            end,
            function(val)
                local sh = UIParent:GetHeight()
                db.offsetY = (val / 100) * sh
                if module.UpdateSettings then module:UpdateSettings() end
            end
        )
        ySlider:SetPoint("TOPLEFT", 0, yStart - 60)

        local compactBtn = CreateStyledButton(content, "", 140, 24)
        compactBtn:SetPoint("TOPLEFT", 0, yStart - 120)

        local function UpdateCompactText()
            if db.transparentMode then
                compactBtn:SetText("Style: Transparent")
                compactBtn:GetFontString():SetTextColor(unpack(COLOR_CYAN))
            elseif db.compactMode then
                compactBtn:SetText("Style: Compact")
                compactBtn:GetFontString():SetTextColor(1, 0.4, 0.8)
            else
                compactBtn:SetText("Style: Default")
                compactBtn:GetFontString():SetTextColor(unpack(COLOR_PURPLE))
            end
        end
        UpdateCompactText()

        compactBtn:SetScript("OnClick", function()
            if not db.compactMode and not db.transparentMode then
                db.compactMode = true
                db.transparentMode = false
            elseif db.compactMode and not db.transparentMode then
                db.compactMode = false
                db.transparentMode = true
            else
                db.compactMode = false
                db.transparentMode = false
            end
            UpdateCompactText()
            if module.UpdateSettings then module:UpdateSettings() end
        end)

        local growBtn = CreateStyledButton(content, "", 120, 24)
        growBtn:SetPoint("TOPLEFT", compactBtn, "TOPRIGHT", 10, 0)

        local function UpdateGrowText()
            if db.growUp then
                growBtn:SetText("Grow Up")
                growBtn:GetFontString():SetTextColor(unpack(COLOR_PURPLE))
            else
                growBtn:SetText("Grow Down")
                growBtn:GetFontString():SetTextColor(unpack(COLOR_PURPLE))
            end
        end
        UpdateGrowText()

        growBtn:SetScript("OnClick", function()
            db.growUp = not db.growUp
            UpdateGrowText()
            if module.UpdateSettings then module:UpdateSettings() end
        end)

        resetBtn:SetScript("OnClick", function()
            if module.ResetDefaults then
                module:ResetDefaults()
                if xSlider and xSlider.UpdateVisuals then
                    local sw = UIParent:GetWidth()
                    local val = math.floor((db.offsetX / sw) * 100 + 0.5)
                    xSlider.UpdateVisuals(val)
                end
                if ySlider and ySlider.UpdateVisuals then
                    local sh = UIParent:GetHeight()
                    local val = math.floor((db.offsetY / sh) * 100 + 0.5)
                    ySlider.UpdateVisuals(val)
                end
                UpdateCompactText()
                UpdateGrowText()
            end
        end)

    elseif moduleName == "Loot Announcer" then
        local yStart = -80
        if not whisperDB.lootAnnouncer then whisperDB.lootAnnouncer = { offsetX = 20, offsetY = 300, soundEnabled = true } end
        local db = whisperDB.lootAnnouncer

        if db.soundEnabled == nil then db.soundEnabled = true end

        local testBtn = CreateStyledButton(content, "Test", 80, 24)
        testBtn:SetPoint("TOPLEFT", toggleBtn, "TOPRIGHT", 10, 0)

        local function UpdateTestText()
            if module.isTestMode then
                testBtn:SetText("End")
                testBtn:GetFontString():SetTextColor(unpack(COLOR_RED))
            else
                testBtn:SetText("Test")
                testBtn:GetFontString():SetTextColor(1, 1, 1)
            end
        end

        testBtn:SetScript("OnClick", function()
            if module.ToggleTestMode then
                module:ToggleTestMode()
                UpdateTestText()
            end
        end)

        module.testButton = testBtn

        local resetBtn = CreateStyledButton(content, "Reset", 80, 24)
        resetBtn:SetPoint("TOPLEFT", testBtn, "TOPRIGHT", 10, 0)
        resetBtn:GetFontString():SetTextColor(0.7, 0.7, 0.7)

        local xSlider = CreateCustomSlider(content, "X Offset", -50, 50, 1,
            function()
                local sw = UIParent:GetWidth()
                if sw == 0 then return 0 end
                return math.floor((db.offsetX / sw) * 100 + 0.5)
            end,
            function(val)
                local sw = UIParent:GetWidth()
                db.offsetX = (val / 100) * sw
                if module.UpdateSettings then module:UpdateSettings() end
            end
        )
        xSlider:SetPoint("TOPLEFT", 0, yStart)

        local ySlider = CreateCustomSlider(content, "Y Offset", -50, 50, 1,
            function()
                local sh = UIParent:GetHeight()
                if sh == 0 then return 0 end
                return math.floor((db.offsetY / sh) * 100 + 0.5)
            end,
            function(val)
                local sh = UIParent:GetHeight()
                db.offsetY = (val / 100) * sh
                if module.UpdateSettings then module:UpdateSettings() end
            end
        )
        ySlider:SetPoint("TOPLEFT", 0, yStart - 60)

        local soundBtn = CreateStyledButton(content, "", 140, 24)
        soundBtn:SetPoint("TOPLEFT", 0, yStart - 120)

        local function UpdateSoundText()
            if db.soundEnabled then
                soundBtn:SetText("Sound Alert: On")
                soundBtn:GetFontString():SetTextColor(unpack(COLOR_PURPLE))
            else
                soundBtn:SetText("Sound Alert: Off")
                soundBtn:GetFontString():SetTextColor(0.6, 0.6, 0.6)
            end
        end
        UpdateSoundText()

        soundBtn:SetScript("OnClick", function()
            db.soundEnabled = not db.soundEnabled
            UpdateSoundText()
            if module.UpdateSettings then module:UpdateSettings() end
        end)

        resetBtn:SetScript("OnClick", function()
            if module.ResetDefaults then
                module:ResetDefaults()
                if xSlider and xSlider.UpdateVisuals then
                    local sw = UIParent:GetWidth()
                    local val = math.floor((db.offsetX / sw) * 100 + 0.5)
                    xSlider.UpdateVisuals(val)
                end
                if ySlider and ySlider.UpdateVisuals then
                    local sh = UIParent:GetHeight()
                    local val = math.floor((db.offsetY / sh) * 100 + 0.5)
                    ySlider.UpdateVisuals(val)
                end
                UpdateSoundText()
            end
        end)

    -- ESSENTIALS (Container for specific tracking sub-modules)
        elseif moduleName == "Essentials" then
            local yPos = -20

            if not whisperDB.essentials then whisperDB.essentials = {} end

            -- Helper to get class-colored names
            local function GetClassColoredName(unit)
                local name, realm = UnitName(unit)
                if not name then return nil end
                local _, class = UnitClass(unit)
                local color = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
                local full = (realm and realm ~= "") and (name.."-"..realm) or name
                return string.format("|cff%02x%02x%02x%s|r", color.r*255, color.g*255, color.b*255, full), full
            end

            local function GetGroupMembers()
                local members = { {text = "None", value = "None"} }
                local num = GetNumGroupMembers()
                if num > 0 then
                    local prefix = IsInRaid() and "raid" or "party"
                    for i = 1, num do
                        local colored, raw = GetClassColoredName(prefix..i)
                        if raw then
                            tinsert(members, {text = colored, value = raw})
                        end
                    end
                end
                return members
            end

            -- NEW Styled Dropdown to match config buttons
                    local function CreateCustomDropdown(parent, width, height, getFunc, setFunc)
                        local btn = CreateStyledButton(parent, getFunc() or "None", width, height)

                        local function RefreshDisplay()
                            local current = getFunc()
                            if current == "None" or not IsInGroup() then
                                btn:SetText(current)
                            else
                                local found = false
                                local list = GetGroupMembers()
                                for _, data in ipairs(list) do
                                    if data.value == current then
                                        btn:SetText(data.text)
                                        found = true
                                        break
                                    end
                                end
                                if not found then btn:SetText(current) end
                            end
                        end
                        RefreshDisplay()

                        btn:SetScript("OnClick", function(self)
                            if self.menu and self.menu:IsShown() then self.menu:Hide() return end

                            local menu = self.menu or CreateFrame("Frame", nil, self, "BackdropTemplate")
                            self.menu = menu
                            menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -1)
                            menu:SetFrameStrata("TOOLTIP")
                            menu:SetBackdrop(Style.Backdrop)
                            menu:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
                            menu:SetBackdropBorderColor(0, 0, 0, 1)

                            if menu.buttons then for _, b in pairs(menu.buttons) do b:Hide() end end
                            menu.buttons = menu.buttons or {}

                            local list = GetGroupMembers()
                            menu:SetSize(width, #list * height + 10)

                            for i, data in ipairs(list) do
                                local opt = menu.buttons[i] or CreateFrame("Button", nil, menu, "BackdropTemplate")
                                menu.buttons[i] = opt
                                opt:SetSize(width - 10, height - 2)
                                opt:SetPoint("TOPLEFT", 5, -5 - ((i-1) * height))
                                opt:Show()

                                opt:SetBackdrop(Style.Backdrop)
                                opt:SetBackdropColor(0, 0, 0, 0)
                                opt:SetBackdropBorderColor(0, 0, 0, 0)

                                local text = opt.text or opt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                                opt.text = text
                                text:SetPoint("LEFT", 10, 0)
                                -- INCREASED FONT SIZE TO 14 TO MATCH BUTTONS
                                text:SetFont(Style.STANDARD_FONT, 14, "OUTLINE")
                                text:SetText(data.text)

                                -- MATCHED MOUSEOVER COLOR (0.1, 0.1, 0.1, 0.9) FROM CreateStyledButton
                                opt:SetScript("OnEnter", function()
                                    opt:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
                                    opt:SetBackdropBorderColor(0, 0, 0, 1)
                                end)
                                opt:SetScript("OnLeave", function()
                                    opt:SetBackdropColor(0, 0, 0, 0)
                                    opt:SetBackdropBorderColor(0, 0, 0, 0)
                                end)
                                opt:SetScript("OnClick", function()
                                    setFunc(data.value)
                                    RefreshDisplay()
                                    menu:Hide()
                                end)
                            end
                            menu:Show()
                        end)

                        btn.RefreshDisplay = RefreshDisplay
                        return btn
                    end

                    local subMods = {
                        { name = "Raid Buffs & Consumables", key = "Raid Buffs & Consumables", description = "Tracks missing group buffs and personal consumables.", instantToggle = true },
                        { name = "Combat Alerts", key = "Combat Alerts", description = "Provides visual alerts when entering and leaving combat.", instantToggle = true },
                        { name = "Power Infusion Helper", key = "Power Infusion Helper", description = "Alerts you when a specific player whispers 'PI me'.", instantToggle = true },
                    }

                    for index, sMod in ipairs(subMods) do
                        local subModule = module.subModules and module.subModules[sMod.key]
                        if subModule then
                            local smName = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                            smName:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, yPos)
                            smName:SetFont(Style.STANDARD_FONT, 14, "OUTLINE")
                            smName:SetText(sMod.name)

                            local smDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                            smDesc:SetPoint("TOPLEFT", smName, "BOTTOMLEFT", 0, -6)
                            smDesc:SetWidth(400)
                            smDesc:SetJustifyH("LEFT")
                            smDesc:SetFont(Style.STANDARD_FONT, 11, "OUTLINE")
                            smDesc:SetTextColor(0.6, 0.6, 0.6)
                            smDesc:SetText(sMod.description)

                            local testBtn = CreateStyledButton(content, "Test", 80, 24)
                            testBtn:SetPoint("TOPLEFT", smDesc, "BOTTOMLEFT", 0, -12)

                            local smToggle = CreateStyledButton(content, "", 100, 24)
                            smToggle:SetPoint("TOPLEFT", testBtn, "TOPRIGHT", 10, 0)

                            if whisperDB.essentials[sMod.key] ~= nil then subModule.enabled = whisperDB.essentials[sMod.key] end

                            local function UpdateToggle()
                                local active = subModule.enabled ~= false
                                smToggle:SetText(active and "ENABLED" or "DISABLED")
                                smToggle:GetFontString():SetTextColor(unpack(active and COLOR_GREEN or COLOR_RED))
                            end
                            UpdateToggle()

                            smToggle:SetScript("OnClick", function()
                                subModule.enabled = not (subModule.enabled ~= false)
                                whisperDB.essentials[sMod.key] = subModule.enabled
                                if sMod.instantToggle then
                                    if subModule.enabled and subModule.Init then subModule:Init()
                                    elseif not subModule.enabled and subModule.Disable then subModule:Disable() end
                                end
                                UpdateToggle()
                            end)

                            -- Module Specific Extras (Aligned horizontally)
                            if sMod.key == "Power Infusion Helper" then
                                local dd = CreateCustomDropdown(content, 160, 24,
                                    function() return whisperDB.piTarget or "None" end,
                                    function(val) whisperDB.piTarget = val end
                                )
                                dd:SetPoint("TOPLEFT", smToggle, "TOPRIGHT", 10, 0)
                            elseif sMod.key == "Combat Alerts" then
                                local chToggle = CreateStyledButton(content, "", 140, 24)
                                chToggle:SetPoint("TOPLEFT", smToggle, "TOPRIGHT", 10, 0)
                                local function UpdateCH()
                                    chToggle:SetText(subModule.showCrosshair and "Crosshair: ON" or "Crosshair: OFF")
                                    chToggle:GetFontString():SetTextColor(unpack(subModule.showCrosshair and COLOR_PURPLE or {0.6, 0.6, 0.6}))
                                end
                                UpdateCH()
                                chToggle:SetScript("OnClick", function()
                                    subModule.showCrosshair = not subModule.showCrosshair
                                    whisperDB.essentials["Combat Alerts_Crosshair"] = subModule.showCrosshair
                                    UpdateCH()
                                end)
                            end

                            testBtn:SetScript("OnClick", function()
                                if subModule.ToggleTestMode then
                                    subModule:ToggleTestMode(not subModule.isTesting)
                                    testBtn:SetText(subModule.isTesting and "End" or "Test")
                                    testBtn:GetFontString():SetTextColor(unpack(subModule.isTesting and COLOR_RED or COLOR_WHITE))
                                end
                            end)

                            yPos = yPos - 90
                            if index < #subMods then
                                local sep = content:CreateTexture(nil, "ARTWORK")
                                sep:SetTexture("Interface/Buttons/WHITE8X8")
                                sep:SetVertexColor(0.2, 0.2, 0.2, 0.5)
                                sep:SetHeight(1)
                                sep:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, yPos + 5)
                                sep:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yPos + 5)
                                yPos = yPos - 15
                            end
                        end
                    end

    elseif moduleName == "Utilities" then
        local yPos = -15

        -- Define utilities list
        local utilities = {
            {
                name = "Auto Queue",
                moduleName = "Auto Queue",
                description = "Auto-accepts LFG role checks.",
                instantToggle = true
            },
            {
                name = "Quest Cleaner",
                moduleName = "Quest Cleaner",
                description = "Automatically untracks hidden quests.",
                instantToggle = false
            },
            {
                name = "Mail",
                moduleName = "Mail",
                description = "Streamlines common mailbox actions and logs.",
                instantToggle = true
            },
        }

        if #utilities == 0 then
            local emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            emptyText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, yPos)
            emptyText:SetFont(Style.STANDARD_FONT, 14, "OUTLINE")
            emptyText:SetTextColor(0.6, 0.6, 0.6)
            emptyText:SetText("No utility modules available")
        else
            for index, util in ipairs(utilities) do
                local utilModule = whisper.modules[util.moduleName]

                if utilModule then
                    local utilName = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    utilName:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, yPos)
                    utilName:SetFont(Style.STANDARD_FONT, 14, "OUTLINE")
                    utilName:SetText(util.name)
                    utilName:SetTextColor(1, 1, 1)

                    local utilToggle = CreateStyledButton(content, "", 100, 24)
                    utilToggle:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, yPos - 24)

                    local function UpdateUtilToggleText()
                        if utilModule.enabled then
                            utilToggle:SetText("ENABLED")
                            utilToggle:GetFontString():SetTextColor(unpack(COLOR_GREEN))
                        else
                            utilToggle:SetText("DISABLED")
                            utilToggle:GetFontString():SetTextColor(unpack(COLOR_RED))
                        end
                    end
                    UpdateUtilToggleText()

                    utilToggle:SetScript("OnClick", function()
                        local newState = not utilModule.enabled
                        utilModule.enabled = newState
                        whisperDB.modules[util.moduleName] = newState

                        if util.instantToggle then
                            if newState and utilModule.Init then
                                utilModule:Init()
                            elseif not newState and utilModule.Disable then
                                utilModule:Disable()
                            end
                        end

                        if util.moduleName == "Mail" then
                            local logMod = whisper.modules["Log"]
                            if logMod then
                                logMod.enabled = newState
                                whisperDB.modules["Log"] = newState
                                if util.instantToggle then
                                    if newState and logMod.Init then
                                        logMod:Init()
                                    elseif not newState and logMod.Disable then
                                        logMod:Disable()
                                    end
                                end
                            end
                        end
                        UpdateUtilToggleText()
                    end)

                    local utilDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    utilDesc:SetPoint("TOPLEFT", utilName, "BOTTOMLEFT", 0, -8)
                    utilDesc:SetWidth(400)
                    utilDesc:SetJustifyH("LEFT")
                    utilDesc:SetFont(Style.STANDARD_FONT, 12, "OUTLINE")
                    utilDesc:SetTextColor(0.7, 0.7, 0.7)
                    utilDesc:SetText(util.description)

                    yPos = yPos - 60

                    if index < #utilities then
                        local separator = content:CreateTexture(nil, "ARTWORK")
                        separator:SetTexture("Interface/Buttons/WHITE8X8")
                        separator:SetVertexColor(0.3, 0.3, 0.3, 1)
                        separator:SetHeight(1)
                        separator:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, yPos + 6)
                        separator:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yPos + 6)

                        yPos = yPos - 15
                    end
                end
            end
        end
    else
        local desc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        if toggleBtn then
            desc:SetPoint("TOPLEFT", toggleBtn, "BOTTOMLEFT", 0, -20)
        else
            desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
        end
        desc:SetWidth(400)
        desc:SetJustifyH("LEFT")
        desc:SetFont(Style.STANDARD_FONT, 12, "OUTLINE")
        desc:SetTextColor(0.7, 0.7, 0.7)
        desc:SetText("Module-specific settings will appear here in future updates.")
    end

    return content
end

local function FadeIn(frame, duration)
    frame:SetAlpha(0)
    frame:Show()
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        local progress = elapsed / duration
        if progress >= 1 then
            self:SetAlpha(1)
            self:SetScript("OnUpdate", nil)
        else
            self:SetAlpha(progress * (2 - progress))
        end
    end)
end

local function FadeOut(frame, duration)
    local startAlpha = frame:GetAlpha()
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        local progress = elapsed / duration
        if progress >= 1 then
            self:SetAlpha(0)
            self:Hide()
            self:SetScript("OnUpdate", nil)
        else
            self:SetAlpha(startAlpha * (1 - progress * progress))
        end
    end)
end

local function CreateConfigFrame()
    if configFrame then return end

    configFrame = CreateFrame("Frame", "whisperConfigFrame", UIParent, "BackdropTemplate")
    configFrame:SetSize(CONFIG_WIDTH, CONFIG_HEIGHT)
    configFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    configFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    configFrame:EnableMouse(true)
    configFrame:SetMovable(true)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetClampedToScreen(true)
    configFrame:SetAlpha(0)

    tinsert(UISpecialFrames, "whisperConfigFrame")

    configFrame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    configFrame:SetBackdropColor(8/255, 8/255, 8/255, 0.8)
    configFrame:SetBackdropBorderColor(0, 0, 0, 1)

    configFrame:SetScript("OnDragStart", configFrame.StartMoving)
    configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)

    -- Add OnHide handler to turn off test mode when frame closes
    configFrame:SetScript("OnHide", function()
        for name, module in pairs(whisper.modules) do
            if module.isTestMode and module.ToggleTestMode then
                module:ToggleTestMode()
                if module.testButton then
                    module.testButton:SetText("Test")
                    module.testButton:GetFontString():SetTextColor(1, 1, 1)
                end
            end
            if module.subModules then
                for subName, subMod in pairs(module.subModules) do
                    if subMod.isTesting and subMod.ToggleTestMode then
                        subMod:ToggleTestMode(false)
                        if subMod.testButton then
                            subMod.testButton:SetText("Test")
                            subMod.testButton:GetFontString():SetTextColor(1, 1, 1)
                        end
                    end
                end
            end
        end
    end)

    local closeBtn = CreateFrame("Button", nil, configFrame)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    local tex = closeBtn:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    tex:SetSize(22, 22)
    tex:SetPoint("CENTER")
    closeBtn.Texture = tex
    closeBtn:SetScript("OnClick", function()
        for name, module in pairs(whisper.modules) do
            if module.isTestMode and module.ToggleTestMode then
                module:ToggleTestMode()
                if module.testButton then
                    module.testButton:SetText("Test")
                    module.testButton:GetFontString():SetTextColor(1, 1, 1)
                end
            end
            if module.subModules then
                for subName, subMod in pairs(module.subModules) do
                    if subMod.isTesting and subMod.ToggleTestMode then
                        subMod:ToggleTestMode(false)
                        if subMod.testButton then
                            subMod.testButton:SetText("Test")
                            subMod.testButton:GetFontString():SetTextColor(1, 1, 1)
                        end
                    end
                end
            end
        end
        FadeOut(configFrame, 0.08)
    end)

    local sidebar = CreateFrame("Frame", nil, configFrame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    sidebar:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = nil, edgeSize = 0})
    sidebar:SetBackdropColor(0, 0, 0, 0.5)

    local sidebarTitle = sidebar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sidebarTitle:SetPoint("TOP", 0, -15)
    sidebarTitle:SetText("MODULES")
    sidebarTitle:SetFont(Style.STANDARD_FONT, 14, "OUTLINE")
    sidebarTitle:SetTextColor(0.4, 0.4, 0.4)

    local contentArea = CreateFrame("Frame", nil, configFrame, "BackdropTemplate")
    contentArea:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
    contentArea:SetPoint("BOTTOMRIGHT", 0, 0)
    contentArea:SetBackdrop({bgFile = nil, edgeFile = nil, edgeSize = 0})

    local watermark = contentArea:CreateTexture(nil, "BACKGROUND", nil, -1)
    watermark:SetSize(256, 256)
    watermark:SetPoint("BOTTOMRIGHT", 0, 0)
    watermark:SetTexture("Interface/AddOns/whisper/Media/whisperLogo")
    watermark:SetAlpha(0.1)

    local yOffset = -40
    local sortedNames = {}

    -- Utilities hidden from sidebar
    local utilityModules = {
        ["Auto Queue"] = true,
        ["Quest Cleaner"] = true,
        ["Mail"] = true,
        ["Log"] = true,
    }

    for name in pairs(whisper.modules) do
        if not utilityModules[name] then
            tinsert(sortedNames, name)
        end
    end
    table_sort(sortedNames)

    tinsert(sortedNames, "Utilities")
    for _, name in ipairs(sortedNames) do
        local module = whisper.modules[name]
        local dName = (module and module.displayName) and module.displayName or name

        local btn = CreateModuleButton(sidebar, dName, SIDEBAR_WIDTH, 32)
        btn:SetPoint("TOPLEFT", 0, yOffset)

        btn:SetScript("OnClick", function(self)
            -- Turn off test modes from other tabs to keep UI clean
            for modName, mod in pairs(whisper.modules) do
                if mod.isTestMode and mod.ToggleTestMode then
                    mod:ToggleTestMode()
                    if mod.testButton then
                        mod.testButton:SetText("Test")
                        mod.testButton:GetFontString():SetTextColor(1, 1, 1)
                    end
                end
                if mod.subModules then
                    for subName, subMod in pairs(mod.subModules) do
                        if subMod.isTesting and subMod.ToggleTestMode then
                            subMod:ToggleTestMode(false)
                            if subMod.testButton then
                                subMod.testButton:SetText("Test")
                                subMod.testButton:GetFontString():SetTextColor(1, 1, 1)
                            end
                        end
                    end
                end
            end

            for _, b in pairs(moduleButtons) do b:Deselect() end
            self:Select()
            if name == "Utilities" then
                CreateModuleContent(contentArea, name, nil)
            else
                CreateModuleContent(contentArea, dName, module)
            end
            currentModule = name
        end)

        moduleButtons[name] = btn
        yOffset = yOffset - 32
    end

    local reloadBtn = CreateStyledButton(contentArea, "Reload UI", 140, 28)
    reloadBtn:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -15, 15)
    reloadBtn:SetScript("OnClick", C_UI.Reload)
    reloadBtn.textColor = Style.Colors.Enabled
    local gr, gg, gb = unpack({0, 1, 0.2})
    reloadBtn:GetFontString():SetTextColor(gr, gg, gb)

    if sortedNames[1] then moduleButtons[sortedNames[1]]:Click() end
    configFrame:Hide()
end

local function CreateLauncherPanel()
    launcherPanel = CreateFrame("Frame", nil, nil)
    launcherPanel.name = "whisper"

    local headerIcon = launcherPanel:CreateTexture(nil, "ARTWORK")
    headerIcon:SetSize(64, 64)
    headerIcon:SetPoint("TOPLEFT", 10, -10)
    headerIcon:SetTexture("Interface/AddOns/whisper/Media/whisperLogo")

    local title = launcherPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 90, -25)
    title:SetText(Style.Colors.Addon .. "whisper|r")
    title:SetFont(Style.STANDARD_FONT, 16, "OUTLINE")

    local desc = launcherPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("whisper has its own standalone configuration window.")
    desc:SetFont(Style.STANDARD_FONT, 13, "OUTLINE")

    local openBtn = CreateStyledButton(launcherPanel, "Open Config", 160, 28)
    openBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
    openBtn:SetScript("OnClick", function() whisper:OpenSettings() end)
end

local function RegisterSettings()
    CreateLauncherPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(launcherPanel, launcherPanel.name)
        Settings.RegisterAddOnCategory(category)
        whisper.settingsCategory = category
    end
end

function whisper:OpenSettings(forceShow)
    if not configFrame then CreateConfigFrame() end
    if forceShow then
        FadeIn(configFrame, 0.1)
        configFrame:Raise()
    else
        if configFrame:IsShown() then
            for name, module in pairs(whisper.modules) do
                if module.isTestMode and module.ToggleTestMode then
                    module:ToggleTestMode()
                    if module.testButton then
                        module.testButton:SetText("Test")
                        module.testButton:GetFontString():SetTextColor(1, 1, 1)
                    end
                end
                if module.subModules then
                    for subName, subMod in pairs(module.subModules) do
                        if subMod.isTesting and subMod.ToggleTestMode then
                            subMod:ToggleTestMode(false)
                            if subMod.testButton then
                                subMod.testButton:SetText("Test")
                                subMod.testButton:GetFontString():SetTextColor(1, 1, 1)
                            end
                        end
                    end
                end
            end
            FadeOut(configFrame, 0.08)
        else FadeIn(configFrame, 0.1) configFrame:Raise() end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == addonName then
        RegisterSettings()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
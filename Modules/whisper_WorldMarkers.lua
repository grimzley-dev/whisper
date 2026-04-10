local addonName, whisper = ...
local module = {}
module.displayName = "World Markers"

module.defaults = {
    placeBind = "F5",
    clearBind = "F6",
    isStatic = false,
    staticMarker = 5,
    order = {5, 6, 3, 2, 7, 1, 4, 8}
}

local binder, placeBtn, clearBtn

function module:Init()
    local db = whisperDB.worldMarkers

    if not binder then
        binder = CreateFrame("Frame", "WhisperWorldMarkerBinder")

        placeBtn = CreateFrame("Button", "WhisperWorldMarkerPlace", nil, "SecureActionButtonTemplate")
        placeBtn:SetAttribute("type", "macro")
        placeBtn:RegisterForClicks("AnyDown", "AnyUp")

        clearBtn = CreateFrame("Button", "WhisperWorldMarkerClear", nil, "SecureActionButtonTemplate")
        clearBtn:SetAttribute("type", "macro")
        clearBtn:SetAttribute("macrotext", "/clearworldmarker 9")
        clearBtn:RegisterForClicks("AnyDown", "AnyUp")

        clearBtn:SetScript("PostClick", function()
            if not InCombatLockdown() then
                SecureHandlerExecute(placeBtn, "i = 0")
            end
        end)

        SecureHandlerWrapScript(placeBtn, "PreClick", placeBtn, [[
            if not down then return end

            if isStatic then
                self:SetAttribute("macrotext", "/worldmarker [@cursor] " .. (staticMarker or 5))
            else
                if not order or #order == 0 then return end
                i = (i % #order) + 1
                self:SetAttribute("macrotext", "/worldmarker [@cursor] " .. order[i])
            end
        ]])
    end

    -- FORCE PURGE BUGGED GLOBAL BINDS
    local placeKeys = {GetBindingKey("CLICK WhisperWorldMarkerPlace:LeftButton")}
    for _, k in ipairs(placeKeys) do SetBinding(k, nil) end
    local clearKeys = {GetBindingKey("CLICK WhisperWorldMarkerClear:LeftButton")}
    for _, k in ipairs(clearKeys) do SetBinding(k, nil) end
    SaveBindings(GetCurrentBindingSet())

    self:UpdateSettings()
end

function module:UpdateSettings()
    if InCombatLockdown() then return end

    local db = whisperDB.worldMarkers

-- 1. GATEKEEPER: If the module is disabled, ensure bindings are stripped and stop running
    if not self.enabled then
        self:Disable()
        return
    end

    -- 2. GATEKEEPER: Prevent errors if settings are tweaked before the UI creates the frames
    if not placeBtn or not binder then return end

    local body = "i = 0; order = newtable();\n"
    body = body .. string.format("isStatic = %s;\n", tostring(db.isStatic or false))
    body = body .. string.format("staticMarker = %d;\n", db.staticMarker or 5)
    for _, markerID in ipairs(db.order) do
        body = body .. string.format("tinsert(order, %d);\n", markerID)
    end
    SecureHandlerExecute(placeBtn, body)

    ClearOverrideBindings(binder)
    if db.placeBind and db.placeBind ~= "" and db.placeBind ~= "None" then
        SetOverrideBindingClick(binder, true, db.placeBind, placeBtn:GetName())
    end
    if db.clearBind and db.clearBind ~= "" and db.clearBind ~= "None" then
        SetOverrideBindingClick(binder, true, db.clearBind, clearBtn:GetName())
    end
end

function module:Disable()
    if InCombatLockdown() then return end
    if binder then
        ClearOverrideBindings(binder)
    end
end

function module:ResetDefaults()
    for k, v in pairs(self.defaults) do
        if type(v) == "table" then
            whisperDB.worldMarkers[k] = {}
            for i, val in ipairs(v) do whisperDB.worldMarkers[k][i] = val end
        else
            whisperDB.worldMarkers[k] = v
        end
    end
    self:UpdateSettings()
end

whisper:RegisterModule("World Markers", module)

-- =========================
-- Config Panel UI
-- =========================
function module:BuildOptionsPanel(content, toggleBtn)
    local db = whisperDB.worldMarkers

    local resetBtn = whisper.GUI.CreateStyledButton(content, "Reset", 80, 24)
    resetBtn:SetPoint("TOPLEFT", toggleBtn, "TOPRIGHT", 10, 0)
    resetBtn:GetFontString():SetTextColor(0.7, 0.7, 0.7)

    local Y_BINDS_LBL = -80
    local Y_BINDS_BTN = -100
    local Y_MODE_TITLE = -145
    local Y_MODE_BTN = -165
    local Y_ORDER_TITLE = -205
    local Y_ROW1_LBL = -230
    local Y_ROW1_BTN = -245
    local Y_ROW2_LBL = -280
    local Y_ROW2_BTN = -295

    local function CreateKeybindButton(labelStr, parent, xOffset, yOffsetLabel, yOffsetBtn, dbKey)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", xOffset, yOffsetLabel)
        lbl:SetFont(whisper.Style.STANDARD_FONT, 14, "OUTLINE")
        lbl:SetText(labelStr)
        lbl:SetTextColor(1, 1, 1)

        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(180, 24)
        btn:SetPoint("TOPLEFT", xOffset, yOffsetBtn)
        btn:SetBackdrop(whisper.Style.Backdrop)
        btn:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
        btn:SetBackdropBorderColor(0, 0, 0, 1)

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("CENTER", 0, 0)
        text:SetFont(whisper.Style.STANDARD_FONT, 14, "OUTLINE")
        text:SetText(db[dbKey] or "None")

        btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)

        local catcher = CreateFrame("Frame", nil, UIParent)
        catcher:SetAllPoints()
        catcher:SetFrameStrata("DIALOG")
        catcher:EnableKeyboard(true)
        catcher:EnableMouse(true)
        catcher:EnableMouseWheel(true)
        catcher:Hide()

        catcher:SetScript("OnKeyDown", function(self, key)
            if key == "UNKNOWN" or key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then return end
            if key == "ESCAPE" then
                text:SetText(db[dbKey] or "None")
                self:Hide()
                return
            end

            local mod = ""
            if IsAltKeyDown() then mod = mod .. "ALT-" end
            if IsControlKeyDown() then mod = mod .. "CTRL-" end
            if IsShiftKeyDown() then mod = mod .. "SHIFT-" end

            db[dbKey] = mod .. key
            text:SetText(db[dbKey])
            if module.UpdateSettings then module:UpdateSettings() end
            self:Hide()
        end)

        catcher:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" or button == "RightButton" then
                text:SetText(db[dbKey] or "None")
                self:Hide()
                return
            end
            local key
            if button == "MiddleButton" then key = "BUTTON3"
            elseif button == "Button4" then key = "BUTTON4"
            elseif button == "Button5" then key = "BUTTON5"
            else return end

            local mod = ""
            if IsAltKeyDown() then mod = mod .. "ALT-" end
            if IsControlKeyDown() then mod = mod .. "CTRL-" end
            if IsShiftKeyDown() then mod = mod .. "SHIFT-" end

            db[dbKey] = mod .. key
            text:SetText(db[dbKey])
            if module.UpdateSettings then module:UpdateSettings() end
            self:Hide()
        end)

        catcher:SetScript("OnMouseWheel", function(self, delta)
            local key = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
            local mod = ""
            if IsAltKeyDown() then mod = mod .. "ALT-" end
            if IsControlKeyDown() then mod = mod .. "CTRL-" end
            if IsShiftKeyDown() then mod = mod .. "SHIFT-" end

            db[dbKey] = mod .. key
            text:SetText(db[dbKey])
            if module.UpdateSettings then module:UpdateSettings() end
            self:Hide()
        end)

        btn:SetScript("OnClick", function()
            text:SetText("Press key to bind...")
            catcher:Show()
        end)

        btn.UpdateDisplay = function() text:SetText(db[dbKey] or "None") end
        return btn
    end

    local placeBtn = CreateKeybindButton("Place Markers", content, 0, Y_BINDS_LBL, Y_BINDS_BTN, "placeBind")
    local clearBtn = CreateKeybindButton("Clear Markers", content, 210, Y_BINDS_LBL, Y_BINDS_BTN, "clearBind")

    local MARKERS = {
        {id = 1, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:14|t |cff00ccffSquare|r"},
        {id = 2, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:14|t |cff00ff00Triangle|r"},
        {id = 3, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14|t |cffcc00ffDiamond|r"},
        {id = 4, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:14|t |cffff0000Cross|r"},
        {id = 5, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:14|t |cffffff00Star|r"},
        {id = 6, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:14|t |cffffaa00Circle|r"},
        {id = 7, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:14|t |cffccccccMoon|r"},
        {id = 8, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:14|t |cffffffffSkull|r"}
    }

    local function GetMarkerName(id)
        for _, m in ipairs(MARKERS) do
            if m.id == id then return m.name end
        end
        return "Unknown"
    end

    local function CreateMarkerDropdown(parent, xOffset, yOffsetLabel, yOffsetBtn, width, height, isStaticMode, posIndex)
        if not isStaticMode then
            local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetPoint("TOPLEFT", xOffset, yOffsetLabel)
            lbl:SetFont(whisper.Style.STANDARD_FONT, 12, "OUTLINE")
            lbl:SetText(tostring(posIndex))
            lbl:SetTextColor(1, 1, 1)
        end

        local initialVal = isStaticMode and db.staticMarker or db.order[posIndex]

        local btn = whisper.GUI.CreateStyledButton(parent, GetMarkerName(initialVal), width, height)
        btn:SetPoint("TOPLEFT", xOffset, yOffsetBtn)
        btn:GetFontString():SetFont(whisper.Style.STANDARD_FONT, 14, "OUTLINE")

        btn:GetFontString():ClearAllPoints()
        btn:GetFontString():SetPoint("CENTER", 0, 0)

        btn:SetScript("OnClick", function(self)
            if self.menu and self.menu:IsShown() then self.menu:Hide() return end

            local menu = self.menu or CreateFrame("Frame", nil, self, "BackdropTemplate")
            self.menu = menu
            menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -1)
            menu:SetFrameStrata("TOOLTIP")
            menu:SetBackdrop(whisper.Style.Backdrop)
            menu:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
            menu:SetBackdropBorderColor(0, 0, 0, 1)
            menu:SetSize(width, #MARKERS * height + 10)

            if not menu.buttons then
                menu.buttons = {}
                for i, data in ipairs(MARKERS) do
                    local opt = CreateFrame("Button", nil, menu, "BackdropTemplate")
                    menu.buttons[i] = opt
                    opt:SetSize(width - 10, height - 2)
                    opt:SetPoint("TOPLEFT", 5, -5 - ((i-1) * height))

                    opt:SetBackdrop(whisper.Style.Backdrop)
                    opt:SetBackdropColor(0, 0, 0, 0)
                    opt:SetBackdropBorderColor(0, 0, 0, 0)

                    local text = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    text:SetPoint("CENTER", 0, 0)
                    text:SetFont(whisper.Style.STANDARD_FONT, 14, "OUTLINE")
                    text:SetText(data.name)

                    opt:SetScript("OnEnter", function()
                        opt:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
                        opt:SetBackdropBorderColor(0, 0, 0, 1)
                    end)
                    opt:SetScript("OnLeave", function()
                        opt:SetBackdropColor(0, 0, 0, 0)
                        opt:SetBackdropBorderColor(0, 0, 0, 0)
                    end)

                    opt:SetScript("OnClick", function()
                        if isStaticMode then
                            db.staticMarker = data.id
                        else
                            db.order[posIndex] = data.id
                        end
                        btn:SetText(data.name)
                        if module.UpdateSettings then module:UpdateSettings() end
                        menu:Hide()
                    end)
                end
            end

            if not self.clickBlocker then
                self.clickBlocker = CreateFrame("Button", nil, UIParent)
                self.clickBlocker:SetAllPoints()
                self.clickBlocker:SetFrameStrata("TOOLTIP")
                self.clickBlocker:SetFrameLevel(menu:GetFrameLevel() - 1)
                self.clickBlocker:SetScript("OnClick", function() menu:Hide() end)
            end
            self.clickBlocker:Show()
            menu:HookScript("OnHide", function() self.clickBlocker:Hide() end)

            menu:Show()
        end)

        return btn
    end

    local modeTitle = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    modeTitle:SetPoint("TOPLEFT", 0, Y_MODE_TITLE)
    modeTitle:SetFont(whisper.Style.STANDARD_FONT, 14, "OUTLINE")
    modeTitle:SetText("Placement Mode")
    modeTitle:SetTextColor(1, 1, 1)

    local staticTitle = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    staticTitle:SetPoint("TOPLEFT", 210, Y_MODE_TITLE)
    staticTitle:SetFont(whisper.Style.STANDARD_FONT, 14, "OUTLINE")
    staticTitle:SetText("Static Marker")
    staticTitle:SetTextColor(1, 1, 1)

    local modeBtn = whisper.GUI.CreateStyledButton(content, "", 180, 24)
    modeBtn:SetPoint("TOPLEFT", 0, Y_MODE_BTN)

    local function UpdateModeText()
        if db.isStatic then
            modeBtn:SetText("Static")
            modeBtn:GetFontString():SetTextColor(0.2, 0.8, 1)
        else
            modeBtn:SetText("Cyclical")
            modeBtn:GetFontString():SetTextColor(0.5, 0.5, 1)
        end
    end
    UpdateModeText()

    modeBtn:SetScript("OnClick", function()
        db.isStatic = not db.isStatic
        UpdateModeText()
        if module.UpdateSettings then module:UpdateSettings() end
    end)

    local staticDropdown = CreateMarkerDropdown(content, 210, Y_MODE_TITLE, Y_MODE_BTN, 180, 24, true, 0)

    local orderTitle = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    orderTitle:SetPoint("TOPLEFT", 0, Y_ORDER_TITLE)
    orderTitle:SetFont(whisper.Style.STANDARD_FONT, 14, "OUTLINE")
    orderTitle:SetText("Custom Marker Sequence")
    orderTitle:SetTextColor(1, 1, 1)

    local COL_X = {0, 105, 210, 315}
    local dropdownBtns = {}

    for i = 1, 4 do dropdownBtns[i] = CreateMarkerDropdown(content, COL_X[i], Y_ROW1_LBL, Y_ROW1_BTN, 95, 24, false, i) end
    for i = 5, 8 do dropdownBtns[i] = CreateMarkerDropdown(content, COL_X[i - 4], Y_ROW2_LBL, Y_ROW2_BTN, 95, 24, false, i) end

    resetBtn:SetScript("OnClick", function()
        if module.ResetDefaults then
            module:ResetDefaults()
            placeBtn:UpdateDisplay()
            clearBtn:UpdateDisplay()
            for i = 1, 8 do dropdownBtns[i]:SetText(GetMarkerName(db.order[i])) end
            staticDropdown:SetText(GetMarkerName(db.staticMarker))
            UpdateModeText()
        end
    end)
end
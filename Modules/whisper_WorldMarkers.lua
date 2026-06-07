local addonName, whisper = ...
local module = {}
module.displayName = "World Markers"
module.dbKey = "worldMarkers"

module.defaults = {
    placeBind = "F5",
    clearBind = "F6",
    isStatic = false,
    staticMarker = 5,
    order = { 5, 6, 3, 2, 7, 1, 4, 8 },
}

local binder, placeBtn, clearBtn, eventFrame
local pendingUpdate = false
local MARKER_ORDER_SIZE = 8

local MODIFIER_KEYS = {
    UNKNOWN = true,
    LSHIFT = true, RSHIFT = true,
    LCTRL = true, RCTRL = true,
    LALT = true, RALT = true,
}

local function ValidateMarkerID(id)
    return type(id) == "number" and id >= 1 and id <= 8
end

local function ValidateSettings(db)
    if not db then return end

    if not ValidateMarkerID(db.staticMarker) then
        db.staticMarker = module.defaults.staticMarker
    end

    if type(db.order) ~= "table" then
        db.order = {}
    end

    local defaultOrder = module.defaults.order
    for i = 1, MARKER_ORDER_SIZE do
        if not ValidateMarkerID(db.order[i]) then
            db.order[i] = defaultOrder[i] or i
        end
    end
end

local function PurgeLegacyBindingsOnce(db)
    if db._legacyBindingsPurged then return end

    local placeKeys = { GetBindingKey("CLICK WhisperWorldMarkerPlace:LeftButton") }
    for _, k in ipairs(placeKeys) do
        if k then SetBinding(k, nil) end
    end

    local clearKeys = { GetBindingKey("CLICK WhisperWorldMarkerClear:LeftButton") }
    for _, k in ipairs(clearKeys) do
        if k then SetBinding(k, nil) end
    end

    SaveBindings(GetCurrentBindingSet())
    db._legacyBindingsPurged = true
end

local function EnsureEventFrame()
    if eventFrame then return end

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and pendingUpdate then
            pendingUpdate = false
            module:UpdateSettings()
        end
    end)
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function module:Init()
    EnsureEventFrame()

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

    local db = whisperDB.worldMarkers
    PurgeLegacyBindingsOnce(db)
    ValidateSettings(db)
    self:UpdateSettings()
end

function module:UpdateSettings()
    local db = whisperDB.worldMarkers
    ValidateSettings(db)

    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    pendingUpdate = false

    if not self.enabled then
        self:Disable()
        return
    end

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
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    pendingUpdate = false

    if binder then
        ClearOverrideBindings(binder)
    end
end

function module:ResetDefaults()
    for k, v in pairs(self.defaults) do
        if type(v) == "table" then
            whisperDB.worldMarkers[k] = {}
            for i, val in ipairs(v) do
                whisperDB.worldMarkers[k][i] = val
            end
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
    ValidateSettings(db)

    local resetBtn = whisper.GUI.CreateStyledButton(content, "Reset", 80, 24)
    resetBtn:SetPoint("TOPLEFT", toggleBtn, "TOPRIGHT", 10, 0)
    local resetFs = resetBtn:GetFontString()
    resetFs:ClearAllPoints()
    resetFs:SetPoint("CENTER", resetBtn, "CENTER", 0, 0)
    resetFs:SetTextColor(0.7, 0.7, 0.7)

    local INSET = whisper.GUI.SLIDER_INSET
    local CONTENT_Y = -whisper.GUI.SLIDER_TOP

    local bindsSection = whisper.GUI.CreateSettingsSection(content, "KEYBINDS", { contentHeight = 48 })
    bindsSection:SetPoint("TOPLEFT", toggleBtn, "BOTTOMLEFT", 0, -16)

    local function FormatBindDisplay(key)
        if not key or key == "" or key == "None" then return "None" end
        return key
    end

    local function GetModifierPrefix()
        local mod = ""
        if IsAltKeyDown() then mod = mod .. "ALT-" end
        if IsControlKeyDown() then mod = mod .. "CTRL-" end
        if IsShiftKeyDown() then mod = mod .. "SHIFT-" end
        return mod
    end

    local keybindCatcher = CreateFrame("Frame", "WhisperWorldMarkerKeybindCatcher", UIParent)
    keybindCatcher:SetAllPoints()
    keybindCatcher:SetFrameStrata("DIALOG")
    keybindCatcher:EnableKeyboard(true)
    keybindCatcher:EnableMouse(true)
    keybindCatcher:EnableMouseWheel(true)
    keybindCatcher:Hide()

    local activeCapture

    local function FinishCapture(restore)
        if not activeCapture then return end
        if restore then
            activeCapture.text:SetText(FormatBindDisplay(db[activeCapture.dbKey]))
        end
        activeCapture = nil
        keybindCatcher:Hide()
    end

    local function CommitCapture(value)
        if not activeCapture then return end
        db[activeCapture.dbKey] = value
        activeCapture.text:SetText(FormatBindDisplay(value))
        if module.UpdateSettings then module:UpdateSettings() end
        FinishCapture(false)
    end

    keybindCatcher:SetScript("OnKeyDown", function(_, key)
        if not activeCapture then return end
        if MODIFIER_KEYS[key] then return end

        if key == "ESCAPE" then
            FinishCapture(true)
            return
        end
        if key == "DELETE" or key == "BACKSPACE" then
            CommitCapture("None")
            return
        end

        CommitCapture(GetModifierPrefix() .. key)
    end)

    keybindCatcher:SetScript("OnMouseDown", function(_, button)
        if not activeCapture then return end

        if button == "RightButton" then
            FinishCapture(true)
            return
        end
        if button == "LeftButton" then
            FinishCapture(true)
            return
        end

        local key
        if button == "MiddleButton" then key = "BUTTON3"
        elseif button == "Button4" then key = "BUTTON4"
        elseif button == "Button5" then key = "BUTTON5"
        else return end

        CommitCapture(GetModifierPrefix() .. key)
    end)

    keybindCatcher:SetScript("OnMouseWheel", function(_, delta)
        if not activeCapture then return end
        local key = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
        CommitCapture(GetModifierPrefix() .. key)
    end)

    local function CreateKeybindButton(labelStr, parent, xOffset, yOffsetLabel, yOffsetBtn, dbKey)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", xOffset, yOffsetLabel)
        lbl:SetFont(whisper.Style.STANDARD_FONT, 14, "OUTLINE")
        lbl:SetText(labelStr)
        lbl:SetTextColor(1, 1, 1)

        local bindBtn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        bindBtn:SetSize(180, 24)
        bindBtn:SetPoint("TOPLEFT", xOffset, yOffsetBtn)
        bindBtn:SetBackdrop(whisper.Style.Backdrop)
        bindBtn:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
        bindBtn:SetBackdropBorderColor(0, 0, 0, 1)
        bindBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local text = bindBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("CENTER", 0, 0)
        text:SetFont(whisper.Style.STANDARD_FONT, 14, "OUTLINE")
        text:SetText(FormatBindDisplay(db[dbKey]))

        bindBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1) end)
        bindBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)

        bindBtn:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                db[dbKey] = "None"
                text:SetText("None")
                if module.UpdateSettings then module:UpdateSettings() end
                return
            end

            activeCapture = { dbKey = dbKey, text = text }
            text:SetText("Press key...")
            keybindCatcher:Show()
        end)

        bindBtn.UpdateDisplay = function()
            text:SetText(FormatBindDisplay(db[dbKey]))
        end
        return bindBtn
    end

    local placeBindBtn = CreateKeybindButton("Place Markers", bindsSection, INSET, CONTENT_Y, CONTENT_Y - 16, "placeBind")
    local clearBindBtn = CreateKeybindButton("Clear Markers", bindsSection, 210, CONTENT_Y, CONTENT_Y - 16, "clearBind")

    local modeSection = whisper.GUI.CreateSettingsSection(content, "PLACEMENT MODE", { contentHeight = 32 })
    modeSection:SetPoint("TOPLEFT", bindsSection, "BOTTOMLEFT", 0, -whisper.GUI.SECTION_GAP)

    local MARKERS = {
        { id = 1, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:14|t |cff00ccffSquare|r" },
        { id = 2, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:14|t |cff00ff00Triangle|r" },
        { id = 3, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14|t |cffcc00ffDiamond|r" },
        { id = 4, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:14|t |cffff0000Cross|r" },
        { id = 5, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:14|t |cffffff00Star|r" },
        { id = 6, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:14|t |cffffaa00Circle|r" },
        { id = 7, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:14|t |cffccccccMoon|r" },
        { id = 8, name = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:14|t |cffffffffSkull|r" },
    }

    local function GetMarkerName(id)
        for _, m in ipairs(MARKERS) do
            if m.id == id then return m.name end
        end
        return "Unknown"
    end

    local dropdownBlocker = CreateFrame("Button", "WhisperWorldMarkerDropdownBlocker", UIParent)
    dropdownBlocker:SetAllPoints()
    dropdownBlocker:SetFrameStrata("TOOLTIP")
    dropdownBlocker:Hide()
    dropdownBlocker:SetScript("OnClick", function()
        if dropdownBlocker.activeMenu then
            dropdownBlocker.activeMenu:Hide()
        end
    end)

    local function CreateMarkerDropdown(parent, xOffset, yOffsetLabel, yOffsetBtn, width, height, isStaticMode, posIndex)
        local posLabel
        if not isStaticMode then
            posLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            posLabel:SetPoint("TOPLEFT", xOffset, yOffsetLabel)
            posLabel:SetFont(whisper.Style.STANDARD_FONT, 12, "OUTLINE")
            posLabel:SetText(tostring(posIndex))
            posLabel:SetTextColor(1, 1, 1)
        end

        local initialVal = isStaticMode and db.staticMarker or db.order[posIndex]

        local markerBtn = whisper.GUI.CreateStyledButton(parent, GetMarkerName(initialVal), width, height)
        markerBtn:SetPoint("TOPLEFT", xOffset, yOffsetBtn)
        markerBtn:GetFontString():SetFont(whisper.Style.STANDARD_FONT, 14, "OUTLINE")
        markerBtn:GetFontString():ClearAllPoints()
        markerBtn:GetFontString():SetPoint("CENTER", 0, 0)
        markerBtn.posLabel = posLabel

        markerBtn:SetScript("OnClick", function(self)
            if self.menu and self.menu:IsShown() then
                self.menu:Hide()
                return
            end

            local menu = self.menu
            if not menu then
                menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                self.menu = menu
                menu:SetFrameStrata("TOOLTIP")
                menu:SetBackdrop(whisper.Style.Backdrop)
                menu:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
                menu:SetBackdropBorderColor(0, 0, 0, 1)
                menu:SetSize(width, #MARKERS * height + 10)

                menu:SetScript("OnHide", function()
                    dropdownBlocker:Hide()
                    dropdownBlocker.activeMenu = nil
                end)

                menu.buttons = {}
                for i, data in ipairs(MARKERS) do
                    local opt = CreateFrame("Button", nil, menu, "BackdropTemplate")
                    menu.buttons[i] = opt
                    opt:SetSize(width - 10, height - 2)
                    opt:SetPoint("TOPLEFT", 5, -5 - ((i - 1) * height))
                    opt:SetBackdrop(whisper.Style.Backdrop)
                    opt:SetBackdropColor(0, 0, 0, 0)
                    opt:SetBackdropBorderColor(0, 0, 0, 0)

                    local optText = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    optText:SetPoint("CENTER", 0, 0)
                    optText:SetFont(whisper.Style.STANDARD_FONT, 14, "OUTLINE")
                    optText:SetText(data.name)

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
                        markerBtn:SetText(data.name)
                        if module.UpdateSettings then module:UpdateSettings() end
                        menu:Hide()
                    end)
                end
            end

            menu:ClearAllPoints()
            menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -1)

            dropdownBlocker.activeMenu = menu
            dropdownBlocker:SetFrameLevel(menu:GetFrameLevel() - 1)
            dropdownBlocker:Show()
            menu:Show()
        end)

        return markerBtn
    end

    local modeBtn = whisper.GUI.CreateStyledButton(modeSection, "", 180, 24)
    modeBtn:SetPoint("TOPLEFT", INSET, CONTENT_Y)

    local staticDropdown = CreateMarkerDropdown(modeSection, 210, CONTENT_Y, CONTENT_Y, 180, 24, true, 0)

    local orderSection = whisper.GUI.CreateSettingsSection(content, "MARKER SEQUENCE", { contentHeight = 80 })
    orderSection:SetPoint("TOPLEFT", modeSection, "BOTTOMLEFT", 0, -whisper.GUI.SECTION_GAP)
    local COL_X = { INSET, INSET + 105, INSET + 210, INSET + 315 }
    local ROW1_LBL = CONTENT_Y
    local ROW1_BTN = CONTENT_Y - 15
    local ROW2_LBL = CONTENT_Y - 35
    local ROW2_BTN = CONTENT_Y - 50

    local dropdownBtns = {}

    for i = 1, 4 do
        dropdownBtns[i] = CreateMarkerDropdown(orderSection, COL_X[i], ROW1_LBL, ROW1_BTN, 95, 24, false, i)
    end
    for i = 5, 8 do
        dropdownBtns[i] = CreateMarkerDropdown(orderSection, COL_X[i - 4], ROW2_LBL, ROW2_BTN, 95, 24, false, i)
    end

    local function UpdateModeText()
        if db.isStatic then
            modeBtn:SetText("Static")
            modeBtn:GetFontString():SetTextColor(0.2, 0.8, 1)
        else
            modeBtn:SetText("Cyclical")
            modeBtn:GetFontString():SetTextColor(0.5, 0.5, 1)
        end
    end

    local function UpdateModeVisibility()
        local isStatic = db.isStatic
        staticDropdown:SetShown(isStatic)
        orderSection:SetShown(not isStatic)
        for i = 1, MARKER_ORDER_SIZE do
            dropdownBtns[i]:SetShown(not isStatic)
            if dropdownBtns[i].posLabel then
                dropdownBtns[i].posLabel:SetShown(not isStatic)
            end
        end
    end

    UpdateModeText()
    UpdateModeVisibility()

    modeBtn:SetScript("OnClick", function()
        db.isStatic = not db.isStatic
        UpdateModeText()
        UpdateModeVisibility()
        if module.UpdateSettings then module:UpdateSettings() end
    end)

    resetBtn:SetScript("OnClick", function()
        if module.ResetDefaults then
            module:ResetDefaults()
            placeBindBtn:UpdateDisplay()
            clearBindBtn:UpdateDisplay()
            for i = 1, MARKER_ORDER_SIZE do
                dropdownBtns[i]:SetText(GetMarkerName(db.order[i]))
            end
            staticDropdown:SetText(GetMarkerName(db.staticMarker))
            UpdateModeText()
            UpdateModeVisibility()
        end
    end)
end

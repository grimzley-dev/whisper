local addonName, whisper = ...
local module = {}
module.displayName = "World Markers"

local defaultOrder = {5, 6, 3, 2, 7, 1, 4, 8}

local binder, placeBtn, clearBtn

function module:Init()
    whisperDB.worldMarkers = whisperDB.worldMarkers or {}
    local db = whisperDB.worldMarkers

    if db.enabled == nil then db.enabled = true end
    if db.placeBind == nil or db.placeBind == "ALT-`" then db.placeBind = "F5" end
    if db.clearBind == nil or db.clearBind == "CTRL-`" then db.clearBind = "F6" end

    if db.isStatic == nil then db.isStatic = false end
    if db.staticMarker == nil then db.staticMarker = 5 end

    if not db.order or type(db.order) ~= "table" or #db.order ~= 8 then
        db.order = {}
        for i, v in ipairs(defaultOrder) do db.order[i] = v end
    end

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
    if not db.enabled then
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
    whisperDB.worldMarkers.placeBind = "F5"
    whisperDB.worldMarkers.clearBind = "F6"
    whisperDB.worldMarkers.isStatic = false
    whisperDB.worldMarkers.staticMarker = 5
    whisperDB.worldMarkers.order = {}
    for i, v in ipairs(defaultOrder) do whisperDB.worldMarkers.order[i] = v end
    self:UpdateSettings()
end

whisper:RegisterModule("World Markers", module)
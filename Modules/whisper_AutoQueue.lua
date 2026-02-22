local addonName, whisper = ...
local AutoQueue = {}
AutoQueue.enabled = true
whisper:RegisterModule("Auto Queue", AutoQueue)

-- =========================
-- Locals
-- =========================
local CompleteLFGRoleCheck = CompleteLFGRoleCheck
local isActive = true
local eventFrame

-- =========================
-- Core Functionality
-- =========================
local function AcceptRoleCheck()
    if not AutoQueue.enabled or not isActive then return end
    CompleteLFGRoleCheck(true)
end

-- =========================
-- Public Functions
-- =========================
function AutoQueue:SetActive(active)
    isActive = active
    whisperDB.autoQueue.active = active
end

function AutoQueue:IsActive()
    return isActive
end

-- =========================
-- Initialization & Toggling
-- =========================
function AutoQueue:Init()
    self.enabled = true
    whisperDB.autoQueue = whisperDB.autoQueue or { active = true }
    isActive = whisperDB.autoQueue.active

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(self, event, ...)
            if event == "LFG_ROLE_CHECK_SHOW" then
                AcceptRoleCheck()
            end
        end)
    end

    -- Only register the event when the module is actually initialized/enabled
    eventFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
end

function AutoQueue:Disable()
    self.enabled = false
    isActive = false
    -- Stop listening to the game entirely to save processing power
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
end
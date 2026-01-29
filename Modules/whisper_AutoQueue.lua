local addonName, whisper = ...
local AutoQueue = {}
AutoQueue.enabled = true
whisper:RegisterModule("Auto Queue", AutoQueue)

-- =========================
-- Locals
-- =========================
local CompleteLFGRoleCheck = CompleteLFGRoleCheck
local print = print

-- State
local isActive = true

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
-- Event Handling
-- =========================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "LFG_ROLE_CHECK_SHOW" then
        AcceptRoleCheck()
    end
end)

-- =========================
-- Initialization
-- =========================
function AutoQueue:Init()
    -- Initialize DB defaults
    whisperDB.autoQueue = whisperDB.autoQueue or {
        active = true
    }

    -- Load saved state
    isActive = whisperDB.autoQueue.active
end

function AutoQueue:Disable()
    self.enabled = false
    isActive = false
end
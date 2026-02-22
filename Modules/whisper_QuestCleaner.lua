local addonName, whisper = ...
local QuestCleaner = {}
QuestCleaner.enabled = true
whisper:RegisterModule("Quest Cleaner", QuestCleaner)

-- =========================
-- Locals
-- =========================
local eventFrame
local COLOR_ADDON = "|cff999999"
local COLOR_RESET = "|r"

-- =========================
-- Core Logic
-- =========================
function QuestCleaner:CleanupTrackedQuests()
    if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return end

    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    local count = 0

    for i = 1, numEntries do
        local quest = C_QuestLog.GetInfo(i)

        if quest and quest.isHidden and quest.questID and quest.questID > 0 then
            local watchType = C_QuestLog.GetQuestWatchType(quest.questID)

            if watchType ~= nil then
                C_QuestLog.RemoveQuestWatch(quest.questID)
                count = count + 1
            end
        end
    end

    if count > 0 then
        print(string.format("%swhisper%s QuestCleaner: Removed %d hidden tracked quest(s).", COLOR_ADDON, COLOR_RESET, count))
    end
end

-- =========================
-- Initialization & Toggling
-- =========================
function QuestCleaner:Init()
    self.enabled = true

    -- Safeguard: Only create the frame if it doesn't already exist
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(self, event)
            QuestCleaner:CleanupTrackedQuests()

            if event == "QUEST_LOG_UPDATE" then
                eventFrame:UnregisterEvent("QUEST_LOG_UPDATE")
            end
        end)
    end

    -- Register events every time it is turned on
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
end

function QuestCleaner:Disable()
    self.enabled = false

    -- Simply tell the existing frame to go to sleep. Do not set it to nil.
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
end
-- whisper_QuestCleaner.lua
local addonName, whisper = ...
local QuestCleaner = {}
QuestCleaner.enabled = true  -- Default enabled
whisper:RegisterModule("Quest Cleaner", QuestCleaner)

-- =========================
-- Locals
-- =========================
local eventFrame
local COLOR_ADDON = "|cff999999" 
local COLOR_RESET = "|r"

-- =========================
-- Module Initialization
-- =========================
function QuestCleaner:Init()
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    
    eventFrame:SetScript("OnEvent", function(self, event)
        -- Run the cleanup scan
        QuestCleaner:CleanupTrackedQuests()
        
        -- Unregister QUEST_LOG_UPDATE after the first successful run 
        -- to prevent constant re-scanning during gameplay.
        if event == "QUEST_LOG_UPDATE" then
            eventFrame:UnregisterEvent("QUEST_LOG_UPDATE")
        end
    end)
end

-- =========================
-- Disable function
-- =========================
function QuestCleaner:Disable()
    self.enabled = false
    
    if eventFrame then
        eventFrame:UnregisterAllEvents()
        eventFrame:SetScript("OnEvent", nil)
        eventFrame = nil
    end
end

-- =========================
-- Core Logic
-- =========================
function QuestCleaner:CleanupTrackedQuests()
    -- Safety check: Ensure the Quest API is loaded
    if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return end

    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    local count = 0
    
    for i = 1, numEntries do
        local quest = C_QuestLog.GetInfo(i)
        
        -- 1. Check if we have valid quest data
        -- 2. Check if the quest is flagged as HIDDEN (not visible in log)
        -- 3. Check if it has a valid ID
        if quest and quest.isHidden and quest.questID and quest.questID > 0 then
            
            -- 4. CRITICAL: Check if it is currently being WATCHED (tracked on screen)
            local watchType = C_QuestLog.GetQuestWatchType(quest.questID)
            
            if watchType ~= nil then
                -- Force remove the watch
                C_QuestLog.RemoveQuestWatch(quest.questID)
                count = count + 1
            end
        end
    end
    
    -- Only notify the user if we actually removed something
    if count > 0 then
        print(string.format("%swhisper%s QuestCleaner: Removed %d hidden tracked quest(s).", COLOR_ADDON, COLOR_RESET, count))
    end
end
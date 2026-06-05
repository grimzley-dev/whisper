-- ========================================================================= --
-- whisper_Tags.lua - Custom ElvUI Tags
-- ========================================================================= --

if not ElvUI then return end

local E = unpack(ElvUI)

-- WoW API & Lua Globals
local UnitName = UnitName
local GetRealmName = GetRealmName
local issecretvalue = issecretvalue
local string_gsub = string.gsub
local utf8sub = string.utf8sub

-- ========================================================================= --
-- Tag Registrations
-- ========================================================================= --

-- [name:short8]
-- Displays the unit's name with a strict 8 character limit (UTF-8 safe)
-- Prioritizes TimelineReminders -> NSRT -> NickTag/ElvUI -> Standard names.
E:AddTag('name:short8', 'UNIT_NAME_UPDATE', function(unit)
    local name, realm = UnitName(unit)
    if not name then return nil end

    -- SECRET STRING PROTECTION:
    -- If in PvP/Combat and the name is protected, return the raw name to prevent errors.
    if issecretvalue and issecretvalue(name) then return name end

    local customName = nil

    -- 1. Check TimelineReminders (LiquidReminders) Database FIRST
    if _G.TimelineReminders and _G.TimelineReminders.GetNickname then
        customName = _G.TimelineReminders:GetNickname(unit)
    end

    -- 2. Check NSRT (Northern Sky Raid Tools) Database
    if not customName and _G.NSAPI and _G.NSAPI.GetName then
        local nsrtName = _G.NSAPI:GetName(name, "ElvUI")
        if nsrtName and nsrtName ~= name then
            customName = nsrtName
        end
    end

    -- 3. Fallback to standard NickTag/ElvUI databases (with the realm-space fix)
    if not customName then
        if realm and realm ~= "" then
            realm = string_gsub(realm, "%s+", "")
        end
        local myRealm = string_gsub(GetRealmName(), "%s+", "")

        local fullName = (realm and realm ~= "") and (name .. "-" .. realm) or (name .. "-" .. myRealm)

        if _G.NickTag and _G.NickTag.GetNickname then
            customName = _G.NickTag:GetNickname(fullName) or _G.NickTag:GetNickname(name)
        elseif E.GetNickName then
            customName = E:GetNickName(fullName) or E:GetNickName(name)
        end
    end

    -- Priority Logic: Use whatever custom name we found, otherwise standard name
    name = customName or name

    -- Finally, truncate the resolved name to 8 characters safely
    return utf8sub(name, 1, 8)
end)

-- ========================================================================= --
-- Add to ElvUI Menu
-- ========================================================================= --
local info = E.TagInfo
if info then
    info['name:short8'] = { category = "whisper", description = "Displays the unit's name with a strict 8 character limit (UTF-8 safe, supports nicknames)" }
end
local addonName, whisper = ...

local TRSkin = {}
TRSkin.enabled = true
TRSkin.displayName = "Timeline Reminders"
TRSkin.dbKey = "trSkin"

local ipairs = ipairs
local pairs = pairs
local tinsert = table.insert
local math_floor = math.floor
local hooksecurefunc = hooksecurefunc
local C_AddOns = C_AddOns
local C_Timer = C_Timer
local CreateFrame = CreateFrame

local TR_ADDON = "TimelineReminders"
local TR_WINDOW = "TimelineRemindersWindow"
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local WHISPER_LOGO = "Interface/AddOns/whisper/Media/whisperLogo"
local WATERMARK_SIZE = 256
local WATERMARK_ALPHA = 0.1
local TR_ANCHOR_TYPES = {"TEXT", "ICON", "BAR", "CIRCLE"}

local MAIN_PANEL = {8 / 255, 8 / 255, 8 / 255, 0.9}
local GREY_PANEL = {8 / 255, 8 / 255, 8 / 255, 0.8}
local BAR_BG_COLOR = MAIN_PANEL

local function C(r, g, b, a)
    return {r / 255, g / 255, b / 255, a or 1}
end

-- Greyscale depth stack: title -> window body -> sidebar -> timeline -> group mode
local COLORS = {
    titleBar = C(4, 4, 4, 1),
    titleBarHover = C(18, 18, 18, 1),

    windowTop = GREY_PANEL,
    windowBottom = GREY_PANEL,

    sidebar = MAIN_PANEL,
    sidebarRow = {8 / 255, 8 / 255, 8 / 255, 0.75},
    contentWell = MAIN_PANEL,
    groupMode = GREY_PANEL,
    groupModeTrack = GREY_PANEL,
    timeRuler = MAIN_PANEL,
    trackRow = {8 / 255, 8 / 255, 8 / 255, 0.65},

    widget = C(32, 32, 32, 0.92),
    accent = C(46, 46, 46, 0.75),
    trackHighlight = C(64, 64, 64, 0.2),

    border = C(0, 0, 0, 1),
    borderSoft = C(64, 64, 64, 0.55),
}

TRSkin.defaults = {
    rescanInterval = 2,
    anchors = {
        TEXT = {
            size = 32,
            outline = "OUTLINE",
        },
        BAR = {
            width = 240,
            height = 40,
            texture = WHITE8X8,
            invert = false,
            outline = "OUTLINE",
            fontSize = 0,
        },
    },
}

if whisperDB.modules and whisperDB.modules["TimelineReminders Skin"] ~= nil and whisperDB.modules["Timeline Reminders"] == nil then
    whisperDB.modules["Timeline Reminders"] = whisperDB.modules["TimelineReminders Skin"]
end

whisper:RegisterModule("Timeline Reminders", TRSkin)

local skinnedFrames = {}
local hookedAnchors = {}
local hookedWindows = {}
local hookedBarBackgrounds = {}
local hookedContentTextures = {}
local skinningGuard = {}
local barBgGuard = {}
local contentTexGuard = {}
local hookedSidebarContainers = {}
local hookedGroupModeFrames = {}
local hookedAnchorBackgrounds = {}
local anchorBgGuard = {}
local SkinFontString

local function ApplyColorTexture(texture, color)
    if not texture or not texture.SetColorTexture then return end
    texture:SetColorTexture(color[1], color[2], color[3], color[4])
end

local function ColorsNear(a, b)
    if not a or not b then return false end
    for i = 1, 4 do
        if math.abs((a[i] or 0) - (b[i] or 0)) >= 0.004 then
            return false
        end
    end
    return true
end

local function HookContentTexture(texture, targetColor)
    if not texture or hookedContentTextures[texture] then return end
    hookedContentTextures[texture] = true

    hooksecurefunc(texture, "SetColorTexture", function(tex, r, g, b, a)
        if not TRSkin.enabled or contentTexGuard[tex] then return end
        local probe = {r, g, b, a or 1}
        if ColorsNear(probe, targetColor) then return end
        contentTexGuard[tex] = true
        ApplyColorTexture(tex, targetColor)
        contentTexGuard[tex] = nil
    end)
end

local function PinContentTexture(texture, targetColor)
    if not texture then return end
    HookContentTexture(texture, targetColor)
    contentTexGuard[texture] = true
    ApplyColorTexture(texture, targetColor)
    contentTexGuard[texture] = nil
end

function TRSkin:IsTRLoaded()
    return C_AddOns and C_AddOns.IsAddOnLoaded(TR_ADDON)
end

function TRSkin:GetTRSaved()
    return self:IsTRLoaded() and LiquidRemindersSaved or nil
end

function TRSkin:GetFontPath()
    if whisper.RefreshStandardFont then
        whisper:RefreshStandardFont()
    end
    return whisper:GetFont()
end

function TRSkin:EnsureAnchorDB(db)
    if not db then return end
    db.anchors = db.anchors or {}
    for anchorType, defaults in pairs(self.defaults.anchors) do
        if type(db.anchors[anchorType]) ~= "table" then
            db.anchors[anchorType] = {}
        end
        for key, value in pairs(defaults) do
            if db.anchors[anchorType][key] == nil then
                db.anchors[anchorType][key] = value
            end
        end
    end
end

function TRSkin:ApplyAnchorSettings()
    if not self.enabled then return end

    local saved = self:GetTRSaved()
    if not saved or not saved.settings or not saved.settings.anchors then return end

    local db = self.db
    if not db then return end
    self:EnsureAnchorDB(db)

    local fontPath = self:GetFontPath()

    for _, anchorType in ipairs(TR_ANCHOR_TYPES) do
        local target = saved.settings.anchors[anchorType]
        if type(target) == "table" then
            target.font = fontPath
            target.defaultFontPath = fontPath
        end
    end

    for _, anchorType in ipairs({"TEXT", "BAR"}) do
        local anchorDB = db.anchors[anchorType]
        local target = saved.settings.anchors[anchorType]
        if target and type(anchorDB) == "table" then
            if anchorDB.size ~= nil then target.size = anchorDB.size end
            if anchorDB.width ~= nil then target.width = anchorDB.width end
            if anchorDB.height ~= nil then target.height = anchorDB.height end
            if anchorDB.texture ~= nil then target.texture = anchorDB.texture end
            if anchorDB.invert ~= nil then target.invert = anchorDB.invert end
            if anchorDB.outline ~= nil then target.outline = anchorDB.outline end
        end
    end
end

function TRSkin:IsTRAnchorFrame(frame)
    return frame
        and frame.group
        and frame.group.UpdateAllSettings
        and frame.group.GetRegions
        and frame.ShowReminder
        and frame.CreateRegion
end

local function GetAnchorKind(anchor)
    if not anchor or not anchor.window then return "TEXT" end
    if anchor.window.textureDropdown then return "BAR" end
    if anchor.window.growDropdownOverride then return "ICON" end
    if anchor.window.thicknessSlider then return "CIRCLE" end
    return "TEXT"
end

function TRSkin:ForEachTRAnchor(callback)
    if not callback then return end

    local visited = {}

    local function TryFrame(frame)
        if not frame or visited[frame] then return end
        if not self:IsTRAnchorFrame(frame) then return end
        visited[frame] = true
        callback(frame, GetAnchorKind(frame))
    end

    local raiser = _G.LIQUID_WINDOW_RAISER
    if raiser and raiser.windows then
        for _, frame in ipairs(raiser.windows) do
            TryFrame(frame)
        end
    end

    local function Walk(frame)
        if not frame then return end
        TryFrame(frame)
        if frame.GetChildren then
            for _, child in ipairs({frame:GetChildren()}) do
                Walk(child)
            end
        end
    end

    local window = _G[TR_WINDOW]
    if window and window.GetParent then
        Walk(window:GetParent())
    end
end

function TRSkin:RefreshTRAnchors()
    self:InstallAnchorHooks()

    local saved = self:GetTRSaved()
    if not saved then return end

    self:ForEachTRAnchor(function(anchor, anchorType)
        if anchorType ~= "TEXT" and anchorType ~= "BAR" then return end

        local settings = saved.settings.anchors[anchorType]
        if not settings or not anchor.group then return end

        for _, region in ipairs(anchor.group:GetRegions()) do
            region:SetSettings(settings)
        end

        anchor.group:UpdateAllSettings()
    end)
end

function TRSkin:HookTRAnchor(anchor)
    if not anchor or hookedAnchors[anchor] then return end
    hookedAnchors[anchor] = true

    self:ApplyAnchorChrome(anchor)

    hooksecurefunc(anchor, "ShowReminder", function()
        C_Timer.After(0, function()
            if TRSkin.enabled then
                TRSkin:ApplyRegionOverrides()
            end
        end)
        C_Timer.After(0.05, function()
            if TRSkin.enabled then
                TRSkin:ApplyRegionOverrides()
            end
        end)
    end)

    if anchor.group then
        hooksecurefunc(anchor.group, "UpdateAllSettings", function()
            C_Timer.After(0, function()
                if TRSkin.enabled then
                    TRSkin:ApplyRegionOverrides()
                end
            end)
        end)
    end
end

function TRSkin:InstallAnchorHooks()
    self:ForEachTRAnchor(function(anchor)
        self:HookTRAnchor(anchor)
    end)
end

local function IsTRGreenAnchorTexture(tex)
    local parent = tex and tex:GetParent()
    if not parent or parent.tex ~= tex or not parent.settingsButton then return false end
    return TRSkin:IsTRAnchorFrame(parent)
end

local function ApplyAnchorBackgroundTexture(texture)
    if not texture or anchorBgGuard[texture] then return end

    anchorBgGuard[texture] = true
    ApplyColorTexture(texture, MAIN_PANEL)
    texture:SetAlpha(1)
    anchorBgGuard[texture] = nil
end

local function HookAnchorBackgroundTexture(texture)
    if not texture or hookedAnchorBackgrounds[texture] then return end
    hookedAnchorBackgrounds[texture] = true

    hooksecurefunc(texture, "SetColorTexture", function(tex, r, g, b, a)
        if not TRSkin.enabled or anchorBgGuard[tex] then return end
        if not IsTRGreenAnchorTexture(tex) then return end
        if ColorsNear({r, g, b, a or 1}, MAIN_PANEL) then return end
        ApplyAnchorBackgroundTexture(tex)
    end)

    hooksecurefunc(texture, "SetAlpha", function(tex, alpha)
        if not TRSkin.enabled or anchorBgGuard[tex] then return end
        if not IsTRGreenAnchorTexture(tex) then return end
        if alpha ~= 1 then
            anchorBgGuard[tex] = true
            tex:SetAlpha(1)
            anchorBgGuard[tex] = nil
        end
    end)
end

local function ApplyAnchorHoverScripts(anchor)
    if not anchor or not anchor.tex or anchor.trSkinHoverHooked then return end
    anchor.trSkinHoverHooked = true

    anchor:SetScript("OnEnter", function()
        if not TRSkin.enabled or not anchor.tex then return end
        anchorBgGuard[anchor.tex] = true
        ApplyColorTexture(anchor.tex, {8 / 255, 8 / 255, 8 / 255, 1})
        anchor.tex:SetAlpha(1)
        anchorBgGuard[anchor.tex] = nil
    end)

    anchor:SetScript("OnLeave", function()
        if TRSkin.enabled then
            ApplyAnchorBackgroundTexture(anchor.tex)
        end
    end)
end

function TRSkin:ApplyAnchorChrome(anchor)
    if not self.enabled or not anchor or not anchor.tex then return end

    HookAnchorBackgroundTexture(anchor.tex)
    ApplyAnchorBackgroundTexture(anchor.tex)
    ApplyAnchorHoverScripts(anchor)

    if anchor.SetBorderColor then
        anchor:SetBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3])
    end

    if anchor.text then
        SkinFontString(anchor.text, self:GetFontPath(), false)
    end

    if anchor.window and anchor.window.upperTexture then
        self:SkinLiquidWindow(anchor.window, self:GetFontPath(), false)
    end
end

function TRSkin:ApplyAnchorChromeAll()
    if not self.enabled or not self:IsTRLoaded() then return end

    self:InstallAnchorHooks()
    self:ForEachTRAnchor(function(anchor)
        self:ApplyAnchorChrome(anchor)
    end)
end

local function IsTRBlueTint(r, g, b)
    if not r or not g or not b then return false end
    return b > r + 0.08 and b > 0.18
end

local function ApplyWindowBackground(frame)
    if not frame or not frame.upperTexture or not frame.lowerTexture then return end
    if skinningGuard[frame] then return end

    skinningGuard[frame] = true

    frame.upperTexture:ClearAllPoints()
    frame.upperTexture:SetAllPoints(frame)
    frame.upperTexture:SetTexture(WHITE8X8)
    frame.upperTexture:SetGradient(
        "VERTICAL",
        CreateColor(COLORS.windowTop[1], COLORS.windowTop[2], COLORS.windowTop[3], COLORS.windowTop[4]),
        CreateColor(COLORS.windowBottom[1], COLORS.windowBottom[2], COLORS.windowBottom[3], COLORS.windowBottom[4])
    )

    frame.lowerTexture:SetAlpha(0)

    if frame.SetBorderColor then
        frame:SetBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3])
    end

    if frame.resizeFrame and frame.resizeFrame.tex then
        frame.resizeFrame.tex:SetVertexColor(0.5, 0.5, 0.5)
        frame.resizeFrame:SetScript("OnEnter", function()
            frame.resizeFrame.tex:SetVertexColor(0.72, 0.72, 0.72)
        end)
        frame.resizeFrame:SetScript("OnLeave", function()
            frame.resizeFrame.tex:SetVertexColor(0.5, 0.5, 0.5)
        end)
    end

    skinningGuard[frame] = nil
end

function TRSkin:InstallWindowSkinHook(frame)
    if not frame or hookedWindows[frame] or not frame.upperTexture then return end
    hookedWindows[frame] = true

    hooksecurefunc(frame.upperTexture, "SetGradient", function()
        if not TRSkin.enabled or skinningGuard[frame] then return end
        C_Timer.After(0, function()
            if TRSkin.enabled then
                ApplyWindowBackground(frame)
            end
        end)
    end)

    if frame.lowerTexture then
        hooksecurefunc(frame.lowerTexture, "SetColorTexture", function()
            if not TRSkin.enabled or skinningGuard[frame] then return end
            C_Timer.After(0, function()
                if TRSkin.enabled and frame.lowerTexture then
                    frame.lowerTexture:SetAlpha(0)
                end
            end)
        end)
        hooksecurefunc(frame.lowerTexture, "SetAlpha", function()
            if not TRSkin.enabled or skinningGuard[frame] then return end
            if frame.lowerTexture:GetAlpha() > 0 then
                frame.lowerTexture:SetAlpha(0)
            end
        end)
    end

    if frame.moverFrame and frame.moverFrame.tex then
        hooksecurefunc(frame.moverFrame.tex, "SetColorTexture", function(tex, r, g, b)
            if not TRSkin.enabled or skinningGuard[frame] then return end
            if IsTRBlueTint(r, g, b) then
                ApplyColorTexture(tex, COLORS.titleBar)
            end
        end)
    end
end

local function SkinTitleBar(frame)
    if not frame.moverFrame or not frame.moverFrame.tex then return end

    ApplyColorTexture(frame.moverFrame.tex, COLORS.titleBar)

    frame.moverFrame:SetScript("OnEnter", function()
        ApplyColorTexture(frame.moverFrame.tex, COLORS.titleBarHover)
    end)
    frame.moverFrame:SetScript("OnLeave", function()
        ApplyColorTexture(frame.moverFrame.tex, COLORS.titleBar)
    end)
end

local function IsTrackLabel(frame)
    return frame and frame.checkButton and frame.background and frame.titleFrame and frame.icon
end

local function IsTrackLabelContainer(frame)
    if not frame or not frame.GetChildren then return false end
    for _, child in ipairs({frame:GetChildren()}) do
        if IsTrackLabel(child) then return true end
    end
    return false
end

local function SkinTrackLabelRow(frame)
    if not frame or not frame.background then return end
    ApplyColorTexture(frame.background, COLORS.sidebarRow)
end

local function EnsureSidebarPanel(container)
    if not container then return end

    local bg = container.trSkinSidebarBg
    if not bg then
        bg = container:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetAllPoints(container)
        container.trSkinSidebarBg = bg
    end

    PinContentTexture(bg, COLORS.sidebar)
end

local function FindLeftColumnTop(mainWindow, container)
    if not mainWindow or not container then return container end

    local profileDropdown
    for _, child in ipairs({mainWindow:GetChildren()}) do
        local point, relativeTo, relativePoint = child:GetPoint(1)
        if relativeTo == container and point == "BOTTOMLEFT" and relativePoint == "TOPLEFT" then
            profileDropdown = child
            break
        end
    end

    if not profileDropdown then return container end

    for _, child in ipairs({mainWindow:GetChildren()}) do
        local point, relativeTo, relativePoint = child:GetPoint(1)
        if relativeTo == profileDropdown and point == "BOTTOMLEFT" and relativePoint == "TOPLEFT" then
            return child
        end
    end

    return profileDropdown
end

local function EnsureLeftColumnPanel(mainWindow, container)
    if not mainWindow or not container then return end

    local topFrame = FindLeftColumnTop(mainWindow, container)
    local bg = mainWindow.trSkinLeftColumnBg
    if not bg then
        bg = mainWindow:CreateTexture(nil, "BACKGROUND", nil, -7)
        mainWindow.trSkinLeftColumnBg = bg
    end

    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", topFrame, "TOPLEFT")
    bg:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT")
    PinContentTexture(bg, COLORS.sidebar)

    if not mainWindow.trSkinLeftColumnSep then
        local sep = mainWindow:CreateTexture(nil, "ARTWORK", nil, -4)
        sep:SetWidth(1)
        sep:SetColorTexture(COLORS.borderSoft[1], COLORS.borderSoft[2], COLORS.borderSoft[3], COLORS.borderSoft[4])
        mainWindow.trSkinLeftColumnSep = sep
    end

    local sep = mainWindow.trSkinLeftColumnSep
    sep:ClearAllPoints()
    sep:SetPoint("TOPRIGHT", container, "TOPRIGHT", 2, 0)
    sep:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 2, 0)
end

local function HookTrackLabelContainer(container)
    if not container or hookedSidebarContainers[container] then return end
    hookedSidebarContainers[container] = true

    if container.Rebuild then
        hooksecurefunc(container, "Rebuild", function()
            C_Timer.After(0, function()
                if not TRSkin.enabled then return end
                EnsureSidebarPanel(container)
                for _, child in ipairs({container:GetChildren()}) do
                    if IsTrackLabel(child) then
                        SkinTrackLabelRow(child)
                    end
                end
            end)
        end)
    end
end

local function SkinTimelineView(frame)
    if not frame or not frame.tex or not frame.timelineClipFrame then return end
    PinContentTexture(frame.tex, COLORS.contentWell)

    if not frame.trSkinSeparator then
        local sep = frame:CreateTexture(nil, "OVERLAY", nil, -5)
        sep:SetColorTexture(COLORS.borderSoft[1], COLORS.borderSoft[2], COLORS.borderSoft[3], COLORS.borderSoft[4])
        sep:SetWidth(1)
        sep:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 0)
        sep:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -2, 0)
        frame.trSkinSeparator = sep
    end
end

local function FindGroupModeFrame(mainWindow)
    if not mainWindow or not mainWindow.GetChildren then return nil end
    for _, child in ipairs({mainWindow:GetChildren()}) do
        if child.clipFrame and child.contentFrame then
            return child
        end
    end
end

local function EnsureGroupModePanel(frame)
    if not frame then return end

    local bg = frame.trSkinGroupModeBg
    if not bg then
        bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetAllPoints(frame)
        frame.trSkinGroupModeBg = bg
    end

    PinContentTexture(bg, COLORS.groupMode)
end

local function IsGroupModeTrack(frame)
    return frame and frame.tex and frame.highlight and frame.SetData
end

local function SkinGroupModeTrack(track)
    if not IsGroupModeTrack(track) then return end
    PinContentTexture(track.tex, COLORS.groupModeTrack)
    ApplyColorTexture(track.highlight, COLORS.trackHighlight)
end

local function SkinGroupModeContents(groupMode)
    if not groupMode then return end

    EnsureGroupModePanel(groupMode)

    if groupMode.contentFrame and groupMode.contentFrame.GetChildren then
        for _, child in ipairs({groupMode.contentFrame:GetChildren()}) do
            if child.GetChildren then
                for _, track in ipairs({child:GetChildren()}) do
                    SkinGroupModeTrack(track)
                end
            end
        end
    end
end

local function EnsureTimelineGroupSeparator(mainWindow, groupMode)
    if not mainWindow or not groupMode then return end

    local sep = mainWindow.trSkinGroupSeparator
    if not sep then
        sep = mainWindow:CreateTexture(nil, "ARTWORK", nil, 7)
        mainWindow.trSkinGroupSeparator = sep
    end

    sep:SetHeight(1)
    sep:SetColorTexture(COLORS.borderSoft[1], COLORS.borderSoft[2], COLORS.borderSoft[3], COLORS.borderSoft[4])
    sep:ClearAllPoints()
    sep:SetPoint("TOPLEFT", groupMode, "TOPLEFT", 0, 1)
    sep:SetPoint("TOPRIGHT", groupMode, "TOPRIGHT", 0, 1)
end

local function HookGroupModeFrame(groupMode)
    if not groupMode or hookedGroupModeFrames[groupMode] then return end
    hookedGroupModeFrames[groupMode] = true

    if groupMode.Rebuild then
        hooksecurefunc(groupMode, "Rebuild", function()
            C_Timer.After(0, function()
                if TRSkin.enabled then
                    SkinGroupModeContents(groupMode)
                end
            end)
        end)
    end

    if groupMode.RebuildUnit then
        hooksecurefunc(groupMode, "RebuildUnit", function()
            C_Timer.After(0, function()
                if TRSkin.enabled then
                    SkinGroupModeContents(groupMode)
                end
            end)
        end)
    end
end

local function SkinDepthTexture(texture)
    if not texture or texture:GetObjectType() ~= "Texture" then return end

    local parent = texture:GetParent()
    if parent and parent.checkButton and parent.background == texture then
        return
    end
    if parent and parent.leftTexture and parent.rightTexture and parent.nameContainer
        and (parent.leftTexture == texture or parent.rightTexture == texture) then
        return
    end

    local ok, r, g, b, a = pcall(texture.GetColorTexture, texture)
    if not ok or not a or a <= 0 then return end

    if IsTRBlueTint(r, g, b) then
        ApplyColorTexture(texture, a >= 0.45 and COLORS.widget or COLORS.accent)
        return
    end

    if b > r + 0.05 and a > 0 and a < 0.2 then
        ApplyColorTexture(texture, COLORS.trackHighlight)
        return
    end

    if r > 0.08 or g > 0.08 or b > 0.08 then return end

    local height = texture:GetHeight() or 0

    if a >= 0.45 and a <= 0.58 and height > 0 and height <= 30 then
        PinContentTexture(texture, COLORS.timeRuler)
        return
    end

    if a >= 0.2 and a <= 0.55 and height > 0 and height <= 28 then
        ApplyColorTexture(texture, COLORS.trackRow)
    end
end

local function SkinMainPanelLayout(frame)
    if not frame then return end

    if IsTrackLabelContainer(frame) then
        EnsureSidebarPanel(frame)
        HookTrackLabelContainer(frame)
        for _, child in ipairs({frame:GetChildren()}) do
            if IsTrackLabel(child) then
                SkinTrackLabelRow(child)
            end
        end
        return
    end

    if IsTrackLabel(frame) then
        SkinTrackLabelRow(frame)
    end
end

local function SkinFrameChrome(frame)
    if not frame then return end

    SkinTimelineView(frame)

    if frame.GetRegions then
        for i = 1, select("#", frame:GetRegions()) do
            local region = select(i, frame:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                if region ~= frame.upperTexture and region ~= frame.lowerTexture and region ~= frame.tex then
                    SkinDepthTexture(region)
                end
            end
        end
    end

    if frame.SetBorderColor and frame.border then
        frame:SetBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3])
    end
end

SkinFontString = function(fontString, fontPath, dim)
    if not fontString then return end

    local _, size, flags = fontString:GetFont()
    fontString:SetFont(fontPath, size or 13, flags or "OUTLINE")
    if not fontString:GetFont() then
        fontString:SetFont("Fonts\\FRIZQT__.TTF", size or 13, flags or "OUTLINE")
    end

    if dim then
        fontString:SetTextColor(0.78, 0.78, 0.78)
    end
end

function TRSkin:SkinLiquidWindow(frame, fontPath, isMainWindow)
    if not frame or not frame.upperTexture or not frame.lowerTexture then return end

    self:InstallWindowSkinHook(frame)
    ApplyWindowBackground(frame)
    SkinTitleBar(frame)
    SkinFrameChrome(frame)

    if frame.GetRegions then
        for i = 1, select("#", frame:GetRegions()) do
            local region = select(i, frame:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                SkinFontString(region, fontPath, not isMainWindow)
            end
        end
    end
end

function TRSkin:SkinFrameTree(frame, fontPath, isMainWindow)
    if not frame then return end

    local isMain = isMainWindow or frame == _G[TR_WINDOW]
    self:SkinLiquidWindow(frame, fontPath, isMain)

    if not frame.upperTexture then
        SkinFrameChrome(frame)
    end

    if isMain or frame == _G[TR_WINDOW] then
        SkinMainPanelLayout(frame)
    end

    if skinnedFrames[frame] then return end
    skinnedFrames[frame] = true

    if frame.GetChildren then
        for _, child in ipairs({frame:GetChildren()}) do
            self:SkinFrameTree(child, fontPath, isMain)
        end
    end

    if frame.GetRegions then
        for i = 1, select("#", frame:GetRegions()) do
            local region = select(i, frame:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                SkinFontString(region, fontPath, false)
            end
        end
    end
end

local function GetBarBackgroundTexture(region)
    if not region or not region.GetRegions then return nil end

    for i = 1, select("#", region:GetRegions()) do
        local tex = select(i, region:GetRegions())
        if tex and tex.GetObjectType and tex:GetObjectType() == "Texture" then
            local layer, subLayer = tex:GetDrawLayer()
            if layer == "BACKGROUND" and (subLayer or 0) == 0 then
                return tex
            end
        end
    end
end

local function ApplyBarBackgroundTexture(texture)
    if not texture or barBgGuard[texture] then return end

    barBgGuard[texture] = true
    ApplyColorTexture(texture, BAR_BG_COLOR)
    barBgGuard[texture] = nil
end

local function HookBarBackgroundTexture(texture)
    if not texture or hookedBarBackgrounds[texture] then return end
    hookedBarBackgrounds[texture] = true

    hooksecurefunc(texture, "SetColorTexture", function(tex, r, g, b, a)
        if not TRSkin.enabled or barBgGuard[tex] then return end

        a = a or 1
        if ColorsNear({r, g, b, a}, BAR_BG_COLOR) then
            return
        end

        ApplyBarBackgroundTexture(tex)
    end)
end

function TRSkin:ApplyBarBackgroundToRegion(region)
    local texture = GetBarBackgroundTexture(region)
    if not texture then return end

    HookBarBackgroundTexture(texture)
    ApplyBarBackgroundTexture(texture)
end

function TRSkin:TrySkinBarRegion(frame, barSettings, fontPath)
    if not frame then return end

    self:ApplyBarBackgroundToRegion(frame)

    local fontSize = barSettings.fontSize or 0
    local outline = barSettings.outline or "OUTLINE"

    if frame.GetChildren then
        for _, child in ipairs({frame:GetChildren()}) do
            if child.GetRegions then
                local strings = {}
                for i = 1, select("#", child:GetRegions()) do
                    local region = select(i, child:GetRegions())
                    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                        tinsert(strings, region)
                    end
                end
                if #strings >= 1 then
                    local mainSize = fontSize > 0 and fontSize or math_floor((barSettings.height or 40) * 0.45)
                    strings[1]:SetFont(fontPath, mainSize, outline)
                    if strings[2] then
                        strings[2]:SetFont(fontPath, mainSize, outline)
                    end
                end
            end
        end
    end
end

function TRSkin:ApplyRegionOverrides()
    if not self.enabled or not self:IsTRLoaded() then return end

    self:EnsureAnchorDB(self.db)
    local barSettings = self.db.anchors.BAR or {}
    local fontPath = self:GetFontPath()

    self:ForEachTRAnchor(function(anchor)
        if GetAnchorKind(anchor) ~= "BAR" then return end
        for _, region in ipairs(anchor.group:GetRegions()) do
            self:TrySkinBarRegion(region, barSettings, fontPath)
        end
    end)
end

local function FindTrackLabelContainer(mainWindow)
    if not mainWindow or not mainWindow.GetChildren then return nil end

    for _, child in ipairs({mainWindow:GetChildren()}) do
        if child.timelineClipFrame then
            local _, relativeTo = child:GetPoint(1)
            if relativeTo then
                return relativeTo
            end
        end
    end
end

local function SkinTrackLabelSidebar(mainWindow)
    local container = FindTrackLabelContainer(mainWindow)
    if not container then return end

    EnsureLeftColumnPanel(mainWindow, container)
    EnsureSidebarPanel(container)
    HookTrackLabelContainer(container)

    for _, child in ipairs({container:GetChildren()}) do
        if IsTrackLabel(child) then
            SkinTrackLabelRow(child)
        end
    end
end

local function SkinGroupModeSection(mainWindow)
    local groupMode = FindGroupModeFrame(mainWindow)
    if not groupMode then return end

    HookGroupModeFrame(groupMode)
    SkinGroupModeContents(groupMode)
    EnsureTimelineGroupSeparator(mainWindow, groupMode)
end

local function EnsureTRWatermark(mainWindow)
    if not mainWindow then return end

    if mainWindow.trSkinWatermark then
        mainWindow.trSkinWatermark:Hide()
    end

    local overlay = mainWindow.trSkinWatermarkFrame
    if not overlay then
        overlay = CreateFrame("Frame", nil, mainWindow)
        overlay:SetAllPoints(mainWindow)
        overlay:EnableMouse(false)
        mainWindow.trSkinWatermarkFrame = overlay

        local watermark = overlay:CreateTexture(nil, "ARTWORK")
        overlay.watermark = watermark
        watermark:SetTexture(WHISPER_LOGO)
        watermark:SetSize(WATERMARK_SIZE, WATERMARK_SIZE)
        watermark:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
    end

    overlay:SetFrameStrata(mainWindow:GetFrameStrata() or "MEDIUM")
    overlay:SetFrameLevel(mainWindow:GetFrameLevel() + 200)
    overlay.watermark:SetAlpha(WATERMARK_ALPHA)
    overlay:Show()
end

function TRSkin:SkinAllWindows(fontPath)
    fontPath = fontPath or self:GetFontPath()
    skinnedFrames = {}

    local mainWindow = _G[TR_WINDOW]
    if mainWindow then
        self:SkinFrameTree(mainWindow, fontPath, true)
        SkinTrackLabelSidebar(mainWindow)
        SkinGroupModeSection(mainWindow)
        EnsureTRWatermark(mainWindow)
    end

    local raiser = _G.LIQUID_WINDOW_RAISER
    if raiser and raiser.windows then
        for _, child in ipairs(raiser.windows) do
            if child ~= mainWindow then
                self:SkinFrameTree(child, fontPath, false)
            end
        end
    end
end

function TRSkin:ApplyFullSkin()
    if not self.enabled or not self:IsTRLoaded() then return end

    self:ApplyAnchorSettings()
    self:RefreshTRAnchors()
    self:SkinAllWindows()
    self:ApplyAnchorChromeAll()
    self:ApplyRegionOverrides()
end

function TRSkin:InstallHooks()
    if self.hooksInstalled then return end

    local mainWindow = _G[TR_WINDOW]
    if mainWindow then
        self:InstallWindowSkinHook(mainWindow)
        hooksecurefunc(mainWindow, "Show", function()
            C_Timer.After(0, function()
                TRSkin:ApplyFullSkin()
            end)
        end)
    end

    if self.eventFrame then
        self.eventFrame:RegisterEvent("ENCOUNTER_START")
        self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end

    self.hooksInstalled = true
end

function TRSkin:StartTicker()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end

    local interval = (self.db and self.db.rescanInterval) or 2
    self.ticker = C_Timer.NewTicker(interval, function()
        if not TRSkin.enabled or not TRSkin:IsTRLoaded() then return end

        local window = _G[TR_WINDOW]
        if window and window.IsShown and window:IsShown() then
            TRSkin:ApplyFullSkin()
        else
            TRSkin:ApplyAnchorSettings()
            TRSkin:ApplyAnchorChromeAll()
            TRSkin:ApplyRegionOverrides()
        end
    end)
end

function TRSkin:StopTicker()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function TRSkin:TrySetup()
    if not self.enabled or not self:IsTRLoaded() then return end
    self:InstallHooks()
    C_Timer.After(0.1, function()
        TRSkin:ApplyFullSkin()
    end)
    self:StartTicker()
end

function TRSkin:Init()
    self.enabled = true

    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
    end

    self.eventFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "ADDON_LOADED" and arg1 == TR_ADDON then
            C_Timer.After(0.5, function()
                TRSkin:TrySetup()
            end)
        elseif event == "ENCOUNTER_START" or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            if TRSkin.enabled then
                C_Timer.After(0.05, function()
                    TRSkin:ApplyFullSkin()
                end)
            end
        end
    end)

    self.eventFrame:RegisterEvent("ADDON_LOADED")

    if self:IsTRLoaded() then
        self:TrySetup()
    end
end

function TRSkin:Disable()
    self.enabled = false
    self:StopTicker()

    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end

    skinnedFrames = {}
    hookedWindows = {}
    hookedBarBackgrounds = {}
    hookedContentTextures = {}
    hookedSidebarContainers = {}
    hookedGroupModeFrames = {}
    hookedAnchorBackgrounds = {}

    local mainWindow = _G[TR_WINDOW]
    if mainWindow then
        if mainWindow.trSkinWatermark then
            mainWindow.trSkinWatermark:Hide()
        end
        if mainWindow.trSkinWatermarkFrame then
            mainWindow.trSkinWatermarkFrame:Hide()
        end
    end
end

function TRSkin:UpdateSettings()
    if not self.enabled then return end
    self:ApplyFullSkin()
end

function TRSkin:ResetDefaults()
    if not self.defaults then return end

    for key, value in pairs(self.defaults) do
        if type(value) == "table" then
            self.db[key] = {}
            for subKey, subValue in pairs(value) do
                if type(subValue) == "table" then
                    self.db[key][subKey] = {}
                    for k, v in pairs(subValue) do
                        self.db[key][subKey][k] = v
                    end
                else
                    self.db[key][subKey] = subValue
                end
            end
        else
            self.db[key] = value
        end
    end

    self:UpdateSettings()
end

local function CreateSectionLabel(parent, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetFont(whisper.Style.STANDARD_FONT, 11, "OUTLINE")
    label:SetTextColor(0.5, 0.5, 0.5)
    label:SetText(text)
    return label
end

local function CreateSettingsSection(parent, titleText, width, height)
    local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    section:SetSize(width, height)
    section:SetClipsChildren(true)
    section:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    section:SetBackdropColor(8 / 255, 8 / 255, 8 / 255, 1)
    section:SetBackdropBorderColor(0, 0, 0, 1)

    local header = CreateSectionLabel(section, titleText)
    header:SetPoint("TOPLEFT", section, "TOPLEFT", 10, -8)

    return section
end

local SLIDER_OPTS = {fillBar = true, compact = true}
local SLIDER_HEIGHT = 40
local SLIDER_CONTROLS_HEIGHT = 24

local function InsetSlider(slider, width)
    slider:SetSize(width, SLIDER_HEIGHT)
    for i = 1, select("#", slider:GetChildren()) do
        local child = select(i, slider:GetChildren())
        if child:GetObjectType() == "Frame" then
            child:SetSize(width, SLIDER_CONTROLS_HEIGHT)
            break
        end
    end
end

function TRSkin:BuildOptionsPanel(content, toggleBtn)
    local PANEL_WIDTH = 418
    local SLIDER_INSET = 12
    local SLIDER_WIDTH = PANEL_WIDTH - SLIDER_INSET * 2

    local applyBtn = whisper.GUI.CreateStyledButton(content, "Re-apply", 90, 24)
    applyBtn:SetPoint("TOPLEFT", toggleBtn, "TOPRIGHT", 10, 0)
    applyBtn:SetScript("OnClick", function()
        TRSkin:ApplyFullSkin()
    end)

    local resetBtn = whisper.GUI.CreateStyledButton(content, "Reset", 80, 24)
    resetBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
    resetBtn:GetFontString():SetTextColor(0.7, 0.7, 0.7)

    if not self:IsTRLoaded() then
        local warn = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        warn:SetPoint("TOPLEFT", toggleBtn, "BOTTOMLEFT", 0, -16)
        warn:SetWidth(PANEL_WIDTH)
        warn:SetFont(whisper.Style.STANDARD_FONT, 12, "OUTLINE")
        warn:SetTextColor(1, 0.4, 0.4)
        warn:SetText("TimelineReminders is not installed or not loaded.")
        return
    end

    self:EnsureAnchorDB(self.db)
    local db = self.db
    local sliderRefs = {}

    local note = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    note:SetPoint("TOPLEFT", toggleBtn, "BOTTOMLEFT", 0, -12)
    note:SetWidth(PANEL_WIDTH)
    note:SetJustifyH("LEFT")
    note:SetFont(whisper.Style.STANDARD_FONT, 11, "OUTLINE")
    note:SetTextColor(0.55, 0.55, 0.55)
    note:SetText("Dark theme and Expressway font for TimelineReminders.")

    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -4)
    hint:SetWidth(PANEL_WIDTH)
    hint:SetJustifyH("LEFT")
    hint:SetFont(whisper.Style.STANDARD_FONT, 11, "OUTLINE")
    hint:SetTextColor(0.45, 0.45, 0.45)
    hint:SetText("Bar text 0 = auto; cooldown matches bar text.")

    local SLIDER_TOP = 30

    local textSection = CreateSettingsSection(content, "TEXT REMINDERS", PANEL_WIDTH, SLIDER_TOP + SLIDER_HEIGHT)
    textSection:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)

    local textSizeSlider = whisper.GUI.CreateCustomSlider(textSection, "Size", 12, 72, 1, function()
        return db.anchors.TEXT.size or 32
    end, function(value)
        db.anchors.TEXT.size = value
        TRSkin:UpdateSettings()
    end, SLIDER_OPTS)
    textSizeSlider:SetPoint("TOPLEFT", textSection, "TOPLEFT", SLIDER_INSET, -SLIDER_TOP)
    InsetSlider(textSizeSlider, SLIDER_WIDTH)
    sliderRefs.textSizeSlider = textSizeSlider

    local barSection = CreateSettingsSection(content, "BAR REMINDERS", PANEL_WIDTH, SLIDER_TOP + SLIDER_HEIGHT * 3)
    barSection:SetPoint("TOPLEFT", textSection, "BOTTOMLEFT", 0, -8)

    local barWidthSlider = whisper.GUI.CreateCustomSlider(barSection, "Width", 120, 400, 5, function()
        return db.anchors.BAR.width or 240
    end, function(value)
        db.anchors.BAR.width = value
        TRSkin:UpdateSettings()
    end, SLIDER_OPTS)
    barWidthSlider:SetPoint("TOPLEFT", barSection, "TOPLEFT", SLIDER_INSET, -SLIDER_TOP)
    InsetSlider(barWidthSlider, SLIDER_WIDTH)
    sliderRefs.barWidthSlider = barWidthSlider

    local barHeightSlider = whisper.GUI.CreateCustomSlider(barSection, "Height", 20, 60, 1, function()
        return db.anchors.BAR.height or 40
    end, function(value)
        db.anchors.BAR.height = value
        TRSkin:UpdateSettings()
    end, SLIDER_OPTS)
    barHeightSlider:SetPoint("TOPLEFT", barWidthSlider, "BOTTOMLEFT", 0, 0)
    InsetSlider(barHeightSlider, SLIDER_WIDTH)
    sliderRefs.barHeightSlider = barHeightSlider

    local barFontSlider = whisper.GUI.CreateCustomSlider(barSection, "Text Size (0 = auto)", 0, 40, 1, function()
        return db.anchors.BAR.fontSize or 0
    end, function(value)
        db.anchors.BAR.fontSize = value
        TRSkin:UpdateSettings()
    end, SLIDER_OPTS)
    barFontSlider:SetPoint("TOPLEFT", barHeightSlider, "BOTTOMLEFT", 0, 0)
    InsetSlider(barFontSlider, SLIDER_WIDTH)
    sliderRefs.barFontSlider = barFontSlider

    resetBtn:SetScript("OnClick", function()
        TRSkin:ResetDefaults()
        local defaults = TRSkin.defaults.anchors
        if sliderRefs.textSizeSlider and sliderRefs.textSizeSlider.UpdateVisuals then
            sliderRefs.textSizeSlider.UpdateVisuals(defaults.TEXT.size)
        end
        if sliderRefs.barWidthSlider and sliderRefs.barWidthSlider.UpdateVisuals then
            sliderRefs.barWidthSlider.UpdateVisuals(defaults.BAR.width)
        end
        if sliderRefs.barHeightSlider and sliderRefs.barHeightSlider.UpdateVisuals then
            sliderRefs.barHeightSlider.UpdateVisuals(defaults.BAR.height)
        end
        if sliderRefs.barFontSlider and sliderRefs.barFontSlider.UpdateVisuals then
            sliderRefs.barFontSlider.UpdateVisuals(defaults.BAR.fontSize)
        end
    end)
end

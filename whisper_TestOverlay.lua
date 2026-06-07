local addonName, whisper = ...

local STANDARD_FONT = whisper.Style.STANDARD_FONT

whisper.TestOverlay = {}

local function FadeToAlpha(frame, targetAlpha, duration)
    if not frame then return end
    duration = duration or 0.12
    if duration <= 0 then
        frame:SetAlpha(targetAlpha)
        return
    end

    local startAlpha = frame:GetAlpha() or 1
    local delta = targetAlpha - startAlpha
    local elapsed = 0

    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = elapsed / duration
        if t >= 1 then
            self:SetAlpha(targetAlpha)
            self:SetScript("OnUpdate", nil)
        else
            self:SetAlpha(startAlpha + delta * t)
        end
    end)
end

function whisper.TestOverlay.Create(opts)
    local state = {
        opts = opts,
        overlay = nil,
        dragging = false,
        hovered = false,
        dragStartX = 0,
        dragStartY = 0,
        frameStartX = 0,
        frameStartY = 0,
    }

    function state:GetContainer()
        local container = self.opts.container
        if type(container) == "function" then
            return container()
        end
        return container
    end

    function state:SetContentVisible(visible)
        if not self.opts.isActive or not self.opts.isActive() then return end

        local targetAlpha = visible and 1 or 0
        local fadeDur = 0.12

        if self.opts.getContentFrames then
            for _, frame in ipairs(self.opts.getContentFrames()) do
                if frame and frame:IsShown() then
                    FadeToAlpha(frame, targetAlpha, fadeDur)
                end
            end
        end

        if self.overlay then
            if visible then
                self.overlay:SetBackdropColor(0, 0, 0, 0.7)
                if self.overlay.label then self.overlay.label:SetTextColor(1, 1, 1, 0.55) end
            else
                self.overlay:SetBackdropColor(0, 0, 0, 0.85)
                if self.overlay.label then self.overlay.label:SetTextColor(1, 1, 1, 0.75) end
            end
        end
    end

    function state:EnsureCreated()
        if self.overlay then return end

        local overlay = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
        overlay:SetFrameStrata("FULLSCREEN_DIALOG")
        overlay:SetFrameLevel(500)
        overlay:Hide()

        overlay:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 2,
        })
        overlay:SetBackdropColor(0, 0, 0, 0.7)
        overlay:SetBackdropBorderColor(0, 0, 0, 1)

        overlay.label = overlay:CreateFontString(nil, "OVERLAY")
        overlay.label:SetFont(STANDARD_FONT, 14, "OUTLINE")
        overlay.label:SetPoint("CENTER")
        overlay.label:SetText(opts.label or "Module")
        overlay.label:SetTextColor(1, 1, 1, 0.55)
        overlay.label:SetShadowOffset(1, -1)
        overlay.label:SetShadowColor(0, 0, 0, 1)
        overlay.label:Hide()

        overlay:EnableMouse(true)
        overlay:SetMovable(true)
        overlay:RegisterForDrag("LeftButton")

        overlay:SetScript("OnEnter", function()
            if not state.opts.isActive or not state.opts.isActive() then return end
            state.hovered = true
            if overlay.label then overlay.label:Show() end
            state:SetContentVisible(false)
            overlay:Raise()
        end)

        overlay:SetScript("OnLeave", function()
            state.hovered = false
            if state.dragging then return end
            if overlay.label then overlay.label:Hide() end
            state:SetContentVisible(true)
        end)

        overlay:SetScript("OnDragStart", function()
            if state.opts.canDrag and not state.opts.canDrag() then return end
            local container = state:GetContainer()
            if not container then return end

            state.hovered = true
            state.dragging = true
            if overlay.label then overlay.label:Show() end
            state:SetContentVisible(false)
            overlay:Raise()
            overlay:SetBackdropBorderColor(0, 0, 0, 1)

            if opts.dragMode == "move" then
                container:StartMoving()
            else
                local scale = UIParent:GetEffectiveScale()
                state.dragStartX, state.dragStartY = GetCursorPosition()
                state.dragStartX, state.dragStartY = state.dragStartX / scale, state.dragStartY / scale

                local left, bottom, width, height = container:GetRect()
                if left and bottom and width and height then
                    state.frameStartX = left + width / 2
                    state.frameStartY = bottom + height / 2
                end
            end
        end)

        overlay:SetScript("OnDragStop", function()
            if not state.dragging then return end
            state.dragging = false

            local container = state:GetContainer()
            if opts.dragMode == "move" and container then
                container:StopMovingOrSizing()
            end

            if not state.hovered and overlay.label then overlay.label:Hide() end
            state:SetContentVisible(not state.hovered)

            if opts.onDragStop then opts.onDragStop() end
        end)

        overlay:SetScript("OnUpdate", function()
            if opts.dragMode ~= "center" or not state.dragging then return end
            local container = state:GetContainer()
            if not container then return end

            local scale = UIParent:GetEffectiveScale()
            local curX, curY = GetCursorPosition()
            curX, curY = curX / scale, curY / scale
            local deltaX = curX - state.dragStartX
            local deltaY = curY - state.dragStartY

            container:ClearAllPoints()
            container:SetPoint("CENTER", UIParent, "BOTTOMLEFT", state.frameStartX + deltaX, state.frameStartY + deltaY)

            overlay:ClearAllPoints()
            overlay:SetAllPoints(container)
        end)

        self.overlay = overlay
    end

    function state:Update()
        if not self.opts.isActive or not self.opts.isActive() then
            self:Hide()
            return
        end

        local container = self:GetContainer()
        if not container then
            self:Hide()
            return
        end

        self:EnsureCreated()
        self.overlay:ClearAllPoints()
        self.overlay:SetAllPoints(container)
        self.overlay:Show()
        self.overlay:Raise()
    end

    function state:Hide()
        self.dragging = false
        self.hovered = false
        if self.overlay then
            if self.overlay.label then self.overlay.label:Hide() end
            self.overlay:Hide()
        end
    end

    return state
end

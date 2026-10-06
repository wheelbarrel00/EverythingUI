-- A small model of the WoW frame API for the library's tests, loaded with dofile. A method the
-- model lacks is nil, so calling one fails loudly instead of passing silently. Layout is not
-- computed: a test that needs a position sets it with frame._top, _bottom or _center.

local M = {}

local function newLibStub()
    local LS = { libs = {}, minors = {} }
    function LS:NewLibrary(major, minor)
        assert(type(major) == "string", "Bad argument #2 to `NewLibrary' (string expected)")
        minor = assert(tonumber(string.match(minor, "%d+")), "Minor version must either be a number or contain a number.")
        local oldminor = self.minors[major]
        if oldminor and oldminor >= minor then return nil end
        self.minors[major], self.libs[major] = minor, self.libs[major] or {}
        return self.libs[major], oldminor
    end
    function LS:GetLibrary(major, silent)
        if not self.libs[major] and not silent then
            error(("Cannot find a library instance of %q."):format(tostring(major)), 2)
        end
        return self.libs[major], self.minors[major]
    end
    return setmetatable(LS, { __call = LS.GetLibrary })
end
M.newLibStub = newLibStub

local function copyInto(dst, src)
    for k, v in pairs(src) do dst[k] = v end
    return dst
end

function M.newEnv(opts)
    opts = opts or {}
    local env = { combat = false, timers = {}, created = {}, badFonts = {}, errors = {}, unknownEvents = {} }

    local Region = {}
    -- A point of a name already set replaces it, as the client does, so only a leftover point of
    -- ANOTHER name survives a re-anchor that forgot ClearAllPoints.
    function Region:SetPoint(point, ...)
        for i, p in ipairs(self._points) do
            if p[1] == point then
                self._points[i] = { point, ... }
                return
            end
        end
        self._points[#self._points + 1] = { point, ... }
    end
    function Region:ClearAllPoints() self._points = {} end
    -- As the client does: every other anchor goes, and TOPLEFT and BOTTOMRIGHT take the relative's.
    function Region:SetAllPoints(rel)
        self._points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
    end
    function Region:GetNumPoints() return #self._points end
    function Region:GetPoint(i) return unpack(self._points[i or 1] or {}) end
    function Region:SetSize(w, h) self._w, self._h = w, h end
    function Region:SetWidth(w) self._w = w end
    function Region:SetHeight(h) self._h = h end
    function Region:GetWidth() return self._w or 0 end
    function Region:GetHeight() return self._h or 0 end
    function Region:GetSize() return self._w or 0, self._h or 0 end
    function Region:Show()
        local was = self._shown
        self._shown = true
        if not was and self._fire then self:_fire("OnShow") end
    end
    function Region:Hide()
        local was = self._shown
        self._shown = false
        if was and self._fire then self:_fire("OnHide") end
    end
    function Region:SetShown(v) if v then self:Show() else self:Hide() end end
    function Region:IsShown() return self._shown end
    function Region:IsVisible()
        local o = self
        while o do
            if not o._shown then return false end
            o = o._parent
        end
        return true
    end
    function Region:GetParent() return self._parent end
    function Region:IsMouseOver() return self._mouseOver == true end
    function Region:SetAlpha(a) self._alpha = a end
    function Region:GetAlpha() return self._alpha or 1 end
    function Region:GetTop() return self._top end
    function Region:GetBottom() return self._bottom end
    function Region:GetLeft() return self._left end
    function Region:GetRight() return self._right end
    function Region:GetCenter()
        if self._center then return self._center[1], self._center[2] end
    end
    function Region:GetObjectType() return self._type end
    function Region:GetEffectiveScale()
        local s, o = 1, self
        while o do
            s = s * (o._scale or 1)
            o = o._parent
        end
        return s
    end
    function Region:SetDrawLayer(layer) self._layer = layer end

    local Texture = copyInto({}, Region)
    function Texture:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } self._file = nil end
    function Texture:SetTexture(file) self._file = file self._color = nil end
    function Texture:GetTexture() return self._file end
    function Texture:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a } end
    function Texture:GetVertexColor()
        local v = self._vertex or { 1, 1, 1, 1 }
        return v[1], v[2], v[3], v[4]
    end
    function Texture:SetTexCoord(...) self._texCoord = { ... } end
    function Texture:SetBlendMode(m) self._blend = m end

    local FontString = copyInto({}, Region)
    -- A font file replaces a font object, so a string given one no longer reads as the client's font.
    function FontString:SetFont(file, size, flags)
        self._fontObject = nil
        if env.badFonts[file] then self._font = nil return false end
        self._font = { file, size, flags }
        return true
    end
    function FontString:GetFont()
        if self._font then return self._font[1], self._font[2], self._font[3] end
    end
    function FontString:SetFontObject(obj) self._fontObject = obj self._font = { "OBJECT", 12, "" } end
    function FontString:SetText(s) self._text = s end
    function FontString:GetText() return self._text end
    function FontString:SetTextColor(r, g, b, a) self._textColor = { r, g, b, a } end
    function FontString:GetTextColor()
        local c = self._textColor or { 1, 1, 1, 1 }
        return c[1], c[2], c[3], c[4]
    end
    function FontString:GetStringWidth()
        if self._measure then return self._measure end
        return self._text and (#self._text * 6) or 0
    end
    -- env.stringHeight stands in for a string the client has not laid out yet, which answers 0.
    -- _measureH is one string's own height, as a wrapped string answers.
    function FontString:GetStringHeight()
        if self._measureH then return self._measureH end
        if env.stringHeight then return env.stringHeight end
        return self._font and self._font[2] or 12
    end
    function FontString:SetJustifyH(j) self._justifyH = j end
    function FontString:SetJustifyV(j) self._justifyV = j end
    function FontString:SetWordWrap(w) self._wrap = w end
    function FontString:SetMaxLines(n) self._maxLines = n end
    function FontString:SetShadowOffset(x, y) self._shadow = { x, y } end
    function FontString:GetShadowOffset()
        if self._shadow then return self._shadow[1], self._shadow[2] end
        return 1, -1
    end

    local Frame = copyInto({}, Region)
    function Frame:_fire(event, ...)
        local s = self._scripts[event]
        if s then s(self, ...) end
        for _, h in ipairs(self._hooks[event] or {}) do h(self, ...) end
    end
    -- SetScript replaces the handler AND every hook on it, as the client does.
    function Frame:SetScript(event, fn) self._scripts[event] = fn self._hooks[event] = nil end
    function Frame:GetScript(event) return self._scripts[event] end
    function Frame:HookScript(event, fn)
        local list = self._hooks[event] or {}
        list[#list + 1] = fn
        self._hooks[event] = list
    end
    function Frame:CreateTexture(_, layer)
        local t = env._new(Texture, "Texture", self)
        t._layer = layer
        self._regions[#self._regions + 1] = t
        return t
    end
    function Frame:CreateFontString(_, layer)
        local fs = env._new(FontString, "FontString", self)
        fs._layer = layer
        self._regions[#self._regions + 1] = fs
        return fs
    end
    function Frame:GetChildren() return unpack(self._children) end
    function Frame:GetRegions() return unpack(self._regions) end
    function Frame:SetScale(s) self._scale = s end
    function Frame:GetScale() return self._scale or 1 end
    function Frame:SetFrameStrata(s) self._strata = s end
    function Frame:GetFrameStrata() return self._strata end
    function Frame:SetFrameLevel(l) self._level = l end
    function Frame:GetFrameLevel() return self._level or 1 end
    function Frame:SetMovable(v) self._movable = v end
    function Frame:EnableMouse(v) self._mouse = v end
    function Frame:IsMouseEnabled() return self._mouse end
    function Frame:EnableMouseWheel(v) self._wheel = v end
    function Frame:EnableKeyboard(v) self._keyboard = v end
    function Frame:IsKeyboardEnabled() return self._keyboard end
    function Frame:SetPropagateKeyboardInput(v)
        if env.combat then error("SetPropagateKeyboardInput is protected in combat") end
        self._propagate = v
    end
    function Frame:RegisterForDrag(...) self._drag = { ... } end
    function Frame:SetClampedToScreen(v) self._clamped = v end
    function Frame:SetHitRectInsets(l, r, t, b) self._hitRect = { l, r, t, b } end
    function Frame:StartMoving() self._moving = true end
    function Frame:StopMovingOrSizing() self._moving = false self._sizing = nil end
    function Frame:SetResizable(v) self._resizable = v end
    function Frame:IsResizable() return self._resizable end
    function Frame:SetResizeBounds(...) self._bounds = { ... } end
    function Frame:StartSizing(point) self._sizing = point end
    -- A client raises on an event it does not have, so a test can take one away.
    function Frame:RegisterEvent(e)
        if env.unknownEvents[e] then error("Attempt to register unknown event \"" .. e .. "\"") end
        self._events[e] = true
    end
    function Frame:UnregisterEvent(e) self._events[e] = nil end
    function Frame:Raise() self._raised = (self._raised or 0) + 1 end
    function Frame:SetToplevel(v) self._toplevel = v end

    local Button = copyInto({}, Frame)
    function Button:Click(button) self:_fire("OnClick", button or "LeftButton", false) end
    function Button:RegisterForClicks(...) self._clicks = { ... } end
    function Button:SetEnabled(v) self._enabled = v and true or false end
    function Button:Enable() self._enabled = true end
    function Button:Disable() self._enabled = false end
    function Button:IsEnabled() return self._enabled ~= false end
    function Button:LockHighlight() self._locked = true end
    function Button:UnlockHighlight() self._locked = false end
    -- The client fills the button with each and shows whichever matches the state, which the
    -- model leaves to the client.
    local function stateTexture(key)
        return function(self, file)
            local t = self[key] or self:CreateTexture(nil, "ARTWORK")
            t:SetTexture(file)
            t:SetAllPoints()
            self[key] = t
        end
    end
    Button.SetNormalTexture = stateTexture("_normalTex")
    Button.SetDisabledTexture = stateTexture("_disabledTex")
    function Button:GetNormalTexture() return self._normalTex end
    function Button:GetDisabledTexture() return self._disabledTex end

    local CheckButton = copyInto({}, Button)
    function CheckButton:SetChecked(v) self._checked = v and true or false end
    function CheckButton:GetChecked() return self._checked end
    function CheckButton:Click(button)
        self._checked = not self._checked
        self:_fire("OnClick", button or "LeftButton", false)
    end

    local Slider = copyInto({}, Frame)
    function Slider:SetOrientation(o) self._orientation = o end
    function Slider:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
    function Slider:GetMinMaxValues() return self._min or 0, self._max or 0 end
    function Slider:SetValueStep(s) self._step = s end
    function Slider:SetObeyStepOnDrag(v) self._obey = v end
    function Slider:SetValue(v)
        local lo, hi = self:GetMinMaxValues()
        if v < lo then v = lo end
        if v > hi then v = hi end
        local was = self._value
        self._value = v
        if was ~= v then self:_fire("OnValueChanged", v, false) end
    end
    function Slider:GetValue() return self._value or 0 end
    -- On ARTWORK, the layer a texture gets when none is named, so a caller that needs the thumb
    -- above something has to say so.
    function Slider:SetThumbTexture(file)
        local t = self._thumb or self:CreateTexture(nil, "ARTWORK")
        t:SetTexture(file)
        self._thumb = t
    end
    function Slider:GetThumbTexture() return self._thumb end

    local ScrollFrame = copyInto({}, Frame)
    function ScrollFrame:SetScrollChild(c) self._child = c end
    function ScrollFrame:GetScrollChild() return self._child end
    function ScrollFrame:SetVerticalScroll(v) self._vscroll = v end
    function ScrollFrame:GetVerticalScroll() return self._vscroll or 0 end
    function ScrollFrame:GetVerticalScrollRange() return self._vrange or 0 end
    function ScrollFrame:SetHorizontalScroll(v) self._hscroll = v end
    function ScrollFrame:GetHorizontalScroll() return self._hscroll or 0 end
    function ScrollFrame:GetHorizontalScrollRange() return self._hrange or 0 end
    function ScrollFrame:UpdateScrollChildRect() end

    -- Focus is one at a time across the client, kept on env. SetFocus drops any selection, as the
    -- client's does, so a HighlightText made before it is lost.
    local EditBox = copyInto({}, Frame)
    function EditBox:SetAutoFocus(v) self._autoFocus = v end
    function EditBox:SetMaxLetters(n) self._maxLetters = n end
    function EditBox:SetText(s) self._text = s self._highlight = false end
    function EditBox:GetText() return self._text or "" end
    function EditBox:SetCursorPosition(p) self._cursor = p end
    function EditBox:SetFocus() self._highlight = false env.focus = self end
    function EditBox:ClearFocus() if env.focus == self then env.focus = nil end end
    function EditBox:HasFocus() return env.focus == self end
    function EditBox:HighlightText() self._highlight = true end
    function EditBox:SetFontObject(o) self._fontObject = o end
    function EditBox:SetTextInsets(...) self._insets = { ... } end
    function EditBox:SetMultiLine(v) self._multiLine = v end
    function EditBox:IsMultiLine() return self._multiLine == true end

    local GameTooltip = copyInto({}, Frame)
    function GameTooltip:SetOwner(owner, anchor) self._owner, self._anchor = owner, anchor self._lines = {} end
    function GameTooltip:SetText(text, r, g, b, a, wrap)
        self._lines = { { text = text, color = { r, g, b, a }, wrap = wrap } }
    end
    function GameTooltip:AddLine(text, r, g, b, wrap)
        self._lines[#self._lines + 1] = { text = text, color = { r, g, b }, wrap = wrap }
    end

    local TYPES = {
        Frame = Frame, Button = Button, CheckButton = CheckButton, Slider = Slider,
        ScrollFrame = ScrollFrame, GameTooltip = GameTooltip, EditBox = EditBox,
    }

    function env._new(methods, kind, parent)
        local o = setmetatable({
            _type = kind, _parent = parent, _points = {}, _shown = true,
            _scripts = {}, _hooks = {}, _children = {}, _regions = {}, _events = {},
        }, { __index = methods })
        return o
    end

    env.UIParent = env._new(Frame, "Frame", nil)
    env.UIParent._w, env.UIParent._h = opts.uiWidth or 1366, opts.uiHeight or 768

    function env.CreateFrame(kind, name, parent)
        local methods = TYPES[kind]
        if not methods then error("the model has no frame type " .. tostring(kind)) end
        local f = env._new(methods, kind, parent)
        f._name = name
        -- The client creates a child one level above its parent.
        if parent then
            parent._children[#parent._children + 1] = f
            f._level = parent:GetFrameLevel() + 1
        end
        env.created[#env.created + 1] = f
        return f
    end

    function env.InCombatLockdown() return env.combat end
    env.cursorX, env.cursorY = 0, 0
    function env.GetCursorPosition() return env.cursorX, env.cursorY end
    function env.IsShiftKeyDown() return env.shift == true end
    function env.IsMouseButtonDown(button) return env.mouseDown == button end
    function env.SetCursor(c) env.cursor = c end
    function env.geterrorhandler()
        return function(err) env.errors[#env.errors + 1] = err end
    end
    env.C_Timer = { After = function(_, fn) env.timers[#env.timers + 1] = fn end }
    function env.runTimers()
        local list = env.timers
        env.timers = {}
        for _, fn in ipairs(list) do fn() end
    end
    env.GameFontHighlight = { name = "GameFontHighlight" }
    if opts.pixelUtil ~= false then
        env.PixelUtil = {
            GetNearestPixelSize = function(size, scale) return size / scale end,
        }
    end
    function env.GetPhysicalScreenSize() return 1920, opts.screenHeight or 1080 end
    function env.GetLocale() return opts.locale or "enUS" end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.tooltip = env._new(GameTooltip, "GameTooltip", env.UIParent)
    env.tooltip._shown = false
    function env.fire(frame, event, ...) frame:_fire(event, ...) end
    return env
end

local STD = {
    "assert", "error", "ipairs", "next", "pairs", "pcall", "rawget", "rawset", "select",
    "setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "xpcall",
    "string", "table", "math",
}

-- Loads every file the XML names, in order, as one host would. The library sees only the
-- modelled API plus the Lua standard library, and setting a global raises. Globals are read
-- through to env as they are used, so a test can install or swap a frame such as the color
-- picker after the library has loaded, the way another addon's can appear in game.
function M.loadLibrary(root, env, host, LibStub)
    local fh = assert(io.open(root .. "/EverythingUI.xml", "rb"))
    local xml = fh:read("*a")
    fh:close()
    local sandbox = { LibStub = LibStub }
    for _, k in ipairs(STD) do sandbox[k] = _G[k] end
    sandbox._G = sandbox
    setmetatable(sandbox, {
        __index = env,
        __newindex = function(_, k) error("the library set a global: " .. tostring(k), 2) end,
    })
    for file in xml:gmatch('<Script%s+file="([^"]+)"') do
        local src = assert(io.open(root .. "/" .. file, "rb"))
        local chunk = assert(loadstring(src:read("*a"), "@" .. file))
        src:close()
        setfenv(chunk, sandbox)
        chunk(host, {})
    end
    return LibStub("EverythingUI-1.0")
end

return M

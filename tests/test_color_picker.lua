-- Run with Lua 5.1 from any folder: lua5.1 tests/test_color_picker.lua
--
-- WHAT EARNS THIS FILE. A user on Classic Era changed the header bar color and the bars
-- vanished, permanently - reload, relog, picking a new color, none of it brought them back.
-- The stored value read { 0.949, 0.541, 0.722, a = 0 }: the color they picked, with an alpha
-- of exactly zero. The host then does c.a or BAR_COLOR[4], and 0 is TRUTHY in Lua, so the zero
-- is kept and every later pick keeps it too.
--
-- The alpha comes from the picker's opacity control, and BOTH flavors load that control from
-- OnShow - transcribed below from Blizzard's own source:
--
--   Classic   ColorPickerFrameMixin:GetColorAlpha() -> OpacitySliderFrame:GetValue()
--             <OnShow> if self.hasOpacity then OpacitySliderFrame:Show()
--                           OpacitySliderFrame:SetValue(self.opacity) ...
--             SetupColorPickerAndShow(): ... self:SetColorRGB(r,g,b)
--                                            self:Show()
--
-- Show on a frame that is ALREADY SHOWN fires nothing, so re-seeding a picker that is still
-- open leaves the PREVIOUS swatch's alpha sitting in the control - and the run commits that
-- instead of its own. The slider's XML carries defaultValue="1" and nothing but the picker's
-- own OnShow calls SetValue on it in Blizzard's code, so an unloaded one holds whatever the
-- last picker left.
--
-- Retail reaches the same code and almost never trips it: its picker registers
-- GLOBAL_MOUSE_DOWN and cancels itself when you click outside, so clicking a second swatch
-- closes the first picker and the next Show is real. The Classic picker has no such handler.
-- That is the whole of the flavor asymmetry - the DEFECT is shared, the REACHABILITY is not.
--
-- AND THE SECOND, WHICH IS WHAT THE REPORTER ACTUALLY HIT. ElvUI's Color Picker Plus reads
-- that same slider as TRANSPARENCY - the pre-10.0 ColorPickerFrame.opacity convention -
-- while Blizzard's Classic GetColorAlpha reads it as ALPHA. Measured on 1.15.9:
--
--   slider 0.84999996  ->  ColorPPBoxA reads 15
--   slider 0           ->  ColorPPBoxA reads 100, GetColorAlpha reads 0
--
-- So its Class button writes 0 meaning OPAQUE and the host stored it as fully transparent.
-- Both UIs then agreed the color was fine and the bar was invisible.
--
-- The cases came over from EQOT's docs/test_color_picker.lua with the picker (decision 13). They
-- load the WHOLE library here, so the session state, the OnHide hook, the Class button and the
-- swatch control that the sliced harness had to stub are all driven for real.

local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
local W = dofile(root .. "/tests/wow.lua")

local pass, fail = 0, 0

local function ok(cond, label)
    if cond then
        pass = pass + 1
    else
        fail = fail + 1
        print("FAIL " .. label)
    end
end

local function case(name, fn)
    local good, err = pcall(fn)
    if not good then
        fail = fail + 1
        print("FAIL " .. name .. " raised: " .. tostring(err))
    end
end

-- Calls into the library go through this, so a mutant that RAISES fails a check rather than
-- ending the case before its later checks have run.
local function guard(fn, ...)
    local okCall, err = pcall(fn, ...)
    if not okCall then
        fail = fail + 1
        print("FAIL raised - " .. tostring(err))
    end
    return okCall
end

local function drive(obj, method, ...)
    return guard(obj[method], obj, ...)
end

-- 1 - 0.85 is not exactly 0.15 in binary floating point, so the round trip back through
-- the inversion lands a hair off. Exact equality is kept everywhere it can be.
local function near(x, y) return type(x) == "number" and math.abs(x - y) < 0.005 end

local GOLD = { 0.92, 0.72, 0.02 }

-- ------------------------------------------------- Blizzard's Classic picker, transcribed
--
-- Read off Blizzard_FrameXML/Classic/ColorPickerFrame.lua and .xml, which Era 1.15.9 loads
-- through Blizzard_FrameXML_Vanilla.toc and TBC 2.5.6 through the _TBC one. Nothing here is
-- invented: the slider bounds, the OnShow body, the OnColorSelect body and the Okay button's
-- call order are all Blizzard's. Built on a model frame, so the library can hang its Class
-- button on it and hook its OnHide the way it does in game.

local function newSlider(minV, maxV)
    local s = { min = minV, max = maxV, _v = minV, _shown = false, _writes = 0 }
    function s:SetValue(v)
        -- Counted at the top rather than beside the assignment: the point of the count is how
        -- often the control is WRITTEN, including a write that turns out to change nothing.
        self._writes = self._writes + 1
        if v == nil then v = self.min end
        if v < self.min then v = self.min elseif v > self.max then v = self.max end
        -- A slider fires OnValueChanged only when the value actually MOVES. Modeled
        -- because it is what stops OnShow correcting an already-matching stale value.
        if v == self._v then return end
        self._v = v
        if self.OnValueChanged then self:OnValueChanged() end
    end
    function s:GetValue() return self._v end
    function s:Show() self._shown = true end
    function s:Hide() self._shown = false end
    function s:IsShown() return self._shown end
    return s
end

-- startAlpha is whatever the opacity slider is carrying before this picker loads it. Driven
-- rather than assumed: the bug is that a STALE value is read, and the zero the user hit came
-- from ElvUI's Class button rather than from any slider floor. legacy drops the modern entry
-- point, for a client that only has the field-assignment form.
local function newClassicPicker(env, startAlpha, legacy)
    local slider = newSlider(0, 1)
    slider._v = startAlpha or 0

    local cp = env.CreateFrame("Frame", "ColorPickerFrame", env.UIParent)
    cp._shown = false
    cp._r, cp._g, cp._b = 1, 1, 1

    slider.OnValueChanged = function()
        if cp.opacityFunc then cp.opacityFunc() end
    end

    -- The model's Show fires OnShow only on a frame that was hidden, as the client does.
    cp:SetScript("OnShow", function(self)
        if self.hasOpacity then
            slider:Show()
            slider:SetValue(self.opacity)
        else
            slider:Hide()
        end
    end)

    function cp:GetColorRGB() return self._r, self._g, self._b end

    -- Blizzard's <OnColorSelect> calls swatchFunc and nothing else on Classic. The older form
    -- names the same callback func.
    function cp:SetColorRGB(r, g, b)
        self._r, self._g, self._b = r, g, b
        local fn = legacy and self.func or self.swatchFunc
        if fn then fn() end
    end

    -- Deliberately NOT gated on hasOpacity, matching Blizzard: it reads the slider whatever
    -- state the frame is in.
    function cp:GetColorAlpha() return slider:GetValue() end

    if not legacy then
        function cp:SetupColorPickerAndShow(info)
            self.swatchFunc  = info.swatchFunc
            self.hasOpacity  = info.hasOpacity
            self.opacityFunc = info.opacityFunc
            self.opacity     = info.opacity
            self.previousValues = { r = info.r, g = info.g, b = info.b, a = info.opacity }
            self.cancelFunc  = info.cancelFunc
            self:SetColorRGB(info.r, info.g, info.b)
            self:Show()
        end
    end

    -- The Okay button: HideUIPanel first, then swatchFunc, then opacityFunc.
    function cp:ClickOkay()
        self:Hide()
        local fn = legacy and self.func or self.swatchFunc
        fn()
        if self.opacityFunc then self.opacityFunc() end
    end

    function cp:ClickCancel()
        self:Hide()
        if self.cancelFunc then self.cancelFunc(self.previousValues) end
    end

    -- The user dragging the vertical opacity slider. Its $parentText carries no text on
    -- Classic, so the control is unlabeled beyond its own - and + marks.
    function cp:DragOpacity(v) slider:SetValue(v) end

    cp.slider = slider
    return cp
end

-- ElvUI's Color Picker Plus, read off Game/Classic/Blizzard/ColorPicker.lua rather than
-- inferred. Three things about it are load-bearing and an earlier model had all three wrong.
-- Its alpha box is AlphaValue(num) = floor(((1 - num) * 100) + .05), so it truncates rather
-- than rounds. It takes the slider with SetScript rather than a hook, so Blizzard's own
-- OnValueChanged no longer runs. And it updates its box BEFORE calling opacityFunc, which the
-- real addon defers by 0.15s and this calls inline.
local function attachColorPP(cp, invert)
    local box = { _text = "" }
    function box:GetText() return self._text end
    local function alphaValue(v)
        if invert then v = 1 - v end
        return math.floor((v * 100) + 0.05)
    end
    -- It memoizes the last percent and the last RGB it saw, in file-locals its OnShow hook
    -- never resets, and returns early when a write does not move them. Those early returns are
    -- why merely seeding a picker commits nothing until a write crosses a percent boundary.
    local last = { r = 0, g = 0, b = 0, a = 0 }
    cp.slider.OnValueChanged = function()
        local a = alphaValue(cp.slider:GetValue())
        if a == last.a then return end
        last.a = a
        box._text = tostring(a)
        if cp.opacityFunc then cp.opacityFunc() end
    end
    -- It replaces OnColorSelect as well, and the seed lands while the frame is still hidden,
    -- where its own handler reaches a DelayCall with nothing armed rather than swatchFunc.
    function cp:SetColorRGB(r, g, b)
        self._r, self._g, self._b = r, g, b
        if r == last.r and g == last.g and b == last.b then return end
        last.r, last.g, last.b = r, g, b
        if self:IsShown() and self.swatchFunc then self.swatchFunc() end
    end
    -- Its OnShow hook re-renders the box off the live slider and leaves the memo alone. A hook
    -- runs after the picker's own OnShow, which is what loaded the slider.
    cp:HookScript("OnShow", function()
        box._text = tostring(alphaValue(cp.slider:GetValue()))
    end)
    -- Its Class button sets the COLOR first and the slider second, and writes 0 for a fully
    -- opaque color. The order is the reported bug's own: swatchFunc fires while the slider
    -- still holds the previous alpha, and only the second commit carries the class color's.
    function cp:ClickClass(r, g, b)
        cp:SetColorRGB(r, g, b)
        if cp.hasOpacity then cp.slider:SetValue(invert and 0 or 1) end
    end
    return box
end

-- ------------------------------------------------------------------------------ sessions

local CLASS_COLOR = { r = 0.67, g = 0.83, b = 0.45 }

-- One session is one game client with the library loaded and a host's context made.
local function session(opts)
    opts = opts or {}
    local env = W.newEnv()
    env.UnitClass = function() return "Hunter", "HUNTER" end
    env.RAID_CLASS_COLORS = { HUNTER = CLASS_COLOR }
    local LS = W.newLibStub()
    local lib = W.loadLibrary(root, env, "HostA", LS)
    local ui = lib:NewContext({
        id = "EQOT", title = "EQ Objective Tracker", version = "1.28.0",
        accent = { 0.784, 0.216, 0.243 }, L = {},
        tooltip = function() return env.tooltip end,
        labels = { clear = "Clear" },
    })
    local s = { env = env, lib = lib, ui = ui, LibStub = LS }
    function s.state() return lib.shared.colorPicker or {} end
    -- Swaps the frames without touching session state, for a case that models one client
    -- opening two pickers rather than two clients. An absent box is a client with no Color
    -- Picker Plus.
    function s.install(cp, box)
        env.ColorPickerFrame = cp
        env.OpacitySliderFrame = cp and cp.slider or nil
        env.ColorPPBoxA = box
        s.picker = cp
    end
    if opts.picker ~= false then
        local cp = newClassicPicker(env, opts.startAlpha or 0, opts.legacy)
        s.install(cp, opts.elvui ~= nil and attachColorPP(cp, opts.elvui) or nil)
    end
    return s
end

-- A stand-in for one swatch on a host's tab: it holds a stored color and commits whatever the
-- picker hands back, exactly as CreateColorPicker's commit does.
local function swatch(s, stored, hasAlpha)
    local sw = { value = stored, commits = 0 }
    function sw:Open()
        local c = self.value or {}
        local prev = self.value and { r = c.r, g = c.g, b = c.b, a = c.a } or nil
        guard(s.ui.ShowColorPicker, s.ui, c.r or 1, c.g or 1, c.b or 1, c.a or 1, hasAlpha,
            function(nr, ng, nb, na)
                self.commits = self.commits + 1
                self.value = { r = nr, g = ng, b = nb, a = na }
            end,
            function() self.value = prev end)
    end
    return sw
end

local function A(sw) return sw.value and sw.value.a end

local function layer(frame, name)
    local out = {}
    for _, r in ipairs({ frame:GetRegions() }) do
        if r._layer == name then out[#out + 1] = r end
    end
    return out
end

local function sameColor(c, r, g, b, a)
    return c ~= nil and near(c[1], r) and near(c[2], g) and near(c[3], b) and (a == nil or near(c[4], a))
end

local function newContent(env)
    local c = env.CreateFrame("Frame", nil, env.UIParent)
    c._controls = {}
    c._w = 856
    return c
end

-- ------------------------------------------------------------------- the picker, ported

case("a picker opened on a CLOSED frame commits its own alpha", function()
    local s = session()
    local bar = swatch(s, { r = 0.80, g = 0.60, b = 0.20, a = 0.85 }, true)
    bar:Open()
    ok(s.picker:IsShown(), "the picker is up")
    ok(s.picker.slider:IsShown(), "an alpha picker shows its opacity slider")
    ok(s.picker.slider:GetValue() == 0.85, "the slider carries the color's own alpha")
    s.picker:SetColorRGB(0.94, 0.54, 0.72)
    drive(s.picker, "ClickOkay")
    ok(A(bar) == 0.85, "the alpha survives the pick")
    ok(bar.value.r == 0.94, "and the new color lands")
end)

case("the reported bug: a second swatch opened while the picker is still up", function()
    -- Nothing here is contrived. The Classic picker does not close when you click outside
    -- it, so opening one swatch and then another without pressing Okay is ordinary use.
    local s = session()
    local header = swatch(s, { r = 0.93, g = 0.32, b = 0.10 }, false)
    header:Open()
    ok(not s.picker.slider:IsShown(), "a no-alpha picker hides the opacity slider")
    ok(s.picker.slider:GetValue() == 0, "and never loads it, so it keeps what the last one left")

    local bar = swatch(s, { r = 0.80, g = 0.60, b = 0.20, a = 0.85 }, true)
    bar:Open()
    ok(s.picker.slider:IsShown(), "the opacity slider must be shown for an alpha picker")
    ok(s.picker.slider:GetValue() == 0.85, "and must carry THIS color's alpha, not the last one's")

    s.picker:SetColorRGB(0.94, 0.54, 0.72)
    drive(s.picker, "ClickOkay")
    ok(A(bar) == 0.85, "the header bar keeps its alpha instead of committing 0")
    ok(A(bar) ~= 0, "an alpha of 0 makes the bar invisible while its checkbox still reads on")
end)

case("a re-seed must not inherit the previous swatch's alpha either", function()
    local s = session()
    local first = swatch(s, { r = 0.1, g = 0.2, b = 0.3, a = 0.25 }, true)
    first:Open()
    ok(s.picker.slider:GetValue() == 0.25, "the first picker loads its own alpha")

    local second = swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    second:Open()
    s.picker:SetColorRGB(0.5, 0.5, 0.5)
    drive(s.picker, "ClickOkay")
    ok(A(second) == 0.85, "the second swatch commits 0.85, not the first swatch's 0.25")
    ok(A(first) == 0.25, "and the first swatch is left alone")
end)

case("the opacity control still wins once the user moves it", function()
    -- The fix must LOAD the control, never pin the value: a deliberate alpha is a real
    -- choice and has to survive.
    local s = session()
    local bar = swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    drive(s.picker, "DragOpacity", 0.40)
    ok(A(bar) == 0.40, "dragging the opacity slider commits that alpha")
    s.picker:SetColorRGB(0.94, 0.54, 0.72)
    drive(s.picker, "ClickOkay")
    ok(A(bar) == 0.40, "and it survives a later color pick")

    -- Zero is reachable on purpose. That is not the bug - the bug was reaching it without
    -- touching the control.
    drive(s.picker, "DragOpacity", 0)
    ok(A(bar) == 0, "a deliberate 0 is still allowed")
end)

case("a stale slider cannot leak in through a no-alpha picker", function()
    local s = session()
    local bar = swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    drive(s.picker, "ClickOkay")

    local header = swatch(s, { r = 0.93, g = 0.32, b = 0.10 }, false)
    header:Open()
    s.picker:SetColorRGB(0.1, 0.2, 0.3)
    drive(s.picker, "ClickOkay")
    ok(A(header) == 1, "a no-alpha picker commits 1 whatever the slider holds")
end)

case("Cancel restores the value the picker was opened on", function()
    local s = session()
    local bar = swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    s.picker:SetColorRGB(0.94, 0.54, 0.72)
    drive(s.picker, "ClickCancel")
    ok(bar.value.r == 0.8 and A(bar) == 0.85, "Cancel puts the original color back")
end)

case("with no onCancel, Cancel puts back the color it opened on, even after a Class click", function()
    local s = session()
    local seen
    guard(s.ui.ShowColorPicker, s.ui, 0.8, 0.6, 0.2, 0.85, true,
        function(nr, ng, nb, na) seen = { r = nr, g = ng, b = nb, a = na } end)
    local btn = s.state().classButton
    ok(btn, "the Class button is there to press")
    if btn then guard(btn.Click, btn) end
    ok(seen and seen.r == CLASS_COLOR.r, "the class color was committed")
    drive(s.picker, "ClickCancel")
    ok(seen and seen.r == 0.8 and seen.g == 0.6 and seen.b == 0.2 and seen.a == 0.85,
       "and Cancel writes back the color the picker was first opened on")
end)

case("an unset color still opens, and commits an opaque one", function()
    local s = session()
    local unset = swatch(s, nil, true)
    unset:Open()
    ok(s.picker.slider:GetValue() == 1, "an unset color seeds a fully opaque picker")
    s.picker:SetColorRGB(0.2, 0.4, 0.6)
    drive(s.picker, "ClickOkay")
    ok(A(unset) == 1, "and commits alpha 1 rather than 0")
end)

case("the older field-assignment picker still works", function()
    local s = session({ legacy = true })
    local bar = swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    ok(s.picker:IsShown() and s.picker.slider:GetValue() == 0.85, "it opens loaded with the color's alpha")
    s.picker:SetColorRGB(0.94, 0.54, 0.72)
    drive(s.picker, "ClickOkay")
    ok(bar.value and bar.value.r == 0.94 and A(bar) == 0.85, "and Okay commits the pick")
    bar:Open()
    s.picker:SetColorRGB(0.1, 0.1, 0.1)
    drive(s.picker, "ClickCancel")
    ok(bar.value and bar.value.r == 0.94, "and Cancel restores it")
end)

case("ElvUI's picker: the alpha it SHOWS is the alpha that gets stored", function()
    local s = session({ elvui = true })
    local bar = swatch(s, { r = 0.80, g = 0.60, b = 0.20, a = 0.85 }, true)
    bar:Open()
    -- Seeding matters as much as reading. Left alone, the picker opens reporting 15 for an
    -- alpha of 0.85 and the user "corrects" it into something nobody chose.
    ok(s.env.ColorPPBoxA:GetText() == "85", "the picker opens reporting the alpha the host holds")
    s.picker:SetColorRGB(0.94, 0.54, 0.72)
    drive(s.picker, "ClickOkay")
    ok(near(A(bar), 0.85), "picking a color leaves the alpha alone")
end)

case("the reported bug: ElvUI's Class button", function()
    local s = session({ elvui = true })
    local bar = swatch(s, { r = 0.80, g = 0.60, b = 0.20, a = 0.85 }, true)
    bar:Open()
    drive(s.picker, "ClickClass", 0.949, 0.541, 0.722)
    drive(s.picker, "ClickOkay")
    ok(bar.value.r == 0.949, "the class color lands")
    ok(near(A(bar), 1), "and it is fully OPAQUE, which is what that button means")
    ok(A(bar) ~= 0, "rather than the invisible bar the reporter got")
end)

case("a deliberate alpha still lands through ElvUI's slider", function()
    local s = session({ elvui = true })
    local bar = swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    drive(s.picker, "DragOpacity", 0.75)
    ok(s.env.ColorPPBoxA:GetText() == "25", "ElvUI shows 25 for a slider at 0.75")
    ok(near(A(bar), 0.25), "and the host stores the alpha the user is looking at")
end)

case("a picker that AGREES with Blizzard is left alone", function()
    -- The day ElvUI maps the slider as alpha, the calibration must invert nothing. This is
    -- what stops the fix becoming the next version of the bug.
    local s = session({ elvui = false })
    local bar = swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    ok(near(s.picker.slider:GetValue(), 0.85), "the slider is not flipped")
    ok(s.env.ColorPPBoxA:GetText() == "85", "and the box already reads the right alpha")
    s.picker:SetColorRGB(0.5, 0.5, 0.5)
    drive(s.picker, "ClickOkay")
    ok(near(A(bar), 0.85), "the alpha is read straight")
end)

case("an alpha of exactly 0.5 still calibrates, through the probe", function()
    -- 1 - na and na are the SAME NUMBER at 0.5, so the opening reading cannot tell the two
    -- conventions apart. Without the probe the flag stayed false and the reported bug came
    -- back for anyone who had ever picked 50% opacity.
    local s = session({ elvui = true })
    local bar = swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.5 }, true)
    bar:Open()
    ok(s.state().alphaInverted == true, "the probe settles the convention at the ambiguous alpha")
    ok(near(s.picker.slider:GetValue(), 0.5), "and the control still ends up where the color asked")
    ok(near(A(bar), 0.5), "while the probe and the correction leave the stored alpha where it was")
    drive(s.picker, "DragOpacity", 0.75)
    ok(near(A(bar), 0.25), "so a later drag stores the alpha ElvUI is showing, not its complement")
end)

case("the convention is settled once per session, not re-derived per swatch", function()
    local s = session({ elvui = true })
    local writes = s.picker.slider._writes
    local first = swatch(s, { r = 0.1, g = 0.2, b = 0.3, a = 0.85 }, true)
    first:Open()
    ok(s.state().alphaInverted == true, "the first open that can answer settles it")
    ok(s.picker.slider._writes == writes + 2,
       "an unambiguous first reading settles without a probe: the seed and one correction")

    local before = s.picker.slider._writes
    local second = swatch(s, { r = 0.4, g = 0.5, b = 0.6, a = 0.25 }, true)
    second:Open()
    ok(s.picker.slider._writes == before + 1,
       "a later open seeds the control once and needs no corrective write")
    ok(near(s.picker.slider:GetValue(), 0.75),
       "seeded straight to this swatch's own alpha, in the control's space")
    ok(s.state().alphaInverted == true, "and the settled answer is kept")
end)

case("a client with no picker addon is taken as the game's own picker", function()
    local s = session()
    ok(s.state().alphaInverted == nil, "nothing is settled before the first open")
    swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true):Open()
    ok(s.state().alphaInverted == false, "the first alpha open with no box settles it as straight")
end)

case("a box present but unreadable leaves the question open rather than answering it", function()
    -- ColorPPBoxA is an EditBox the user can clear. Latching false on an unreadable one would
    -- answer the question WRONGLY and, being a session flag, never ask again.
    local s = session()
    s.install(s.picker, { GetText = function() return "" end })
    swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true):Open()
    ok(s.state().alphaInverted == nil, "an unreadable box settles nothing")

    -- Same session, so the frames are swapped without clearing what it has learned.
    local good = newClassicPicker(s.env, 0)
    s.install(good, attachColorPP(good, true))
    local bar = swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    ok(s.state().alphaInverted == true, "and a later readable one still settles it")
    drive(s.picker, "DragOpacity", 0.75)
    ok(near(A(bar), 0.25), "with the alpha read the right way round from then on")
end)

case("merely opening an unset clearable color must not commit one", function()
    -- Two alpha pickers ship unset and carry a Clear button, so a commit nobody asked for both
    -- invents a color and offers to clear it. The first open of a session is the one that has
    -- to correct its own seed, and that write is the one ElvUI turns into a deferred commit.
    local s = session({ elvui = true })
    local commits, stored = 0, nil
    guard(s.ui.ShowColorPicker, s.ui, 1, 1, 1, 1, true,
        function(nr, ng, nb, na)
            commits = commits + 1
            stored = { r = nr, g = ng, b = nb, a = na }
        end,
        function() stored = nil end)

    ok(s.state().alphaInverted == true, "the first open still settles the convention")
    ok(commits == 0, "and merely opening it commits nothing")
    ok(stored == nil, "so an unset clearable color is still unset")
    ok(near(s.picker.slider:GetValue(), 0), "while the control ends up showing a fully opaque alpha")
end)

case("a probe that answers neither convention leaves the question open", function()
    -- A box that does not track the control can settle nothing. Latching false on it is the
    -- wrong answer rather than the absent one the session flag exists to hold, and only a
    -- reading taken where the two conventions differ can tell those two apart.
    local s = session({ startAlpha = 0.5 })
    local box = { _text = "50" }
    function box:GetText() return self._text end
    s.install(s.picker, box)
    swatch(s, { r = 0.1, g = 0.2, b = 0.3, a = 0.5 }, true):Open()
    ok(s.state().alphaInverted == nil, "a box that answers neither convention settles nothing")
end)

-- ----------------------------------------------------------------------- the Class button

case("the library's own Class button stands down beside another picker addon's", function()
    local s = session({ elvui = true })
    swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true):Open()
    ok(s.state().classButton == false, "no second Class button is built when a ColorPPBoxA is present")

    local elv = session()
    elv.env.C_AddOns = { IsAddOnLoaded = function(name) return name == "ElvUI" end }
    swatch(elv, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true):Open()
    ok(elv.state().classButton == false, "nor while ElvUI is loaded, which brings its own")

    local plain = session()
    plain.env.CLASS = "Klasse"
    local bar = swatch(plain, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    local btn = plain.state().classButton
    ok(btn and btn._parent == plain.picker, "it IS built on a client with no such box, on the picker")
    ok(btn and btn:IsShown(), "and shown with the picker")
    ok(btn and btn.text:GetText() == "Klasse", "labelled with the client's own word for class")
    local p = btn and btn._points[1] or {}
    ok(p[1] == "TOPLEFT" and p[2] == plain.picker and p[3] == "TOPRIGHT" and p[4] == 6 and p[5] == -34,
       "beside the picker's top right corner")
    local filled = false
    for _, t in ipairs(btn and layer(btn, "BACKGROUND") or {}) do
        if sameColor(t._color, plain.ui:Color("surface")) then filled = true end
    end
    ok(filled, "on a surface fill of its own, since it hangs over the game world")

    -- It reopens the picker seeded from the control, so it has to hand back an addon-space
    -- alpha rather than whatever the control happens to be holding.
    if btn then guard(btn.Click, btn) end
    ok(near(A(bar), 0.85), "pressing it keeps the alpha")
    ok(bar.value and bar.value.r == CLASS_COLOR.r and bar.value.g == CLASS_COLOR.g
       and bar.value.b == CLASS_COLOR.b, "and commits the player's class color at once")

    local again = swatch(plain, { r = 0.1, g = 0.1, b = 0.1, a = 1 }, true)
    again:Open()
    local children = 0
    for _, c in ipairs({ plain.picker:GetChildren() }) do
        if c == btn then children = children + 1 end
    end
    ok(plain.state().classButton == btn and #{ plain.picker:GetChildren() } == 1,
       "one button for the session, however many opens")
    ok(children == 1, "and it is the one the picker carries")

    drive(plain.picker, "ClickOkay")
    ok(btn and not btn:IsShown(), "it goes away with the picker")
end)

case("with no class color to give, the Class button does nothing", function()
    local s = session()
    s.env.RAID_CLASS_COLORS = nil
    local bar = swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    local btn = s.state().classButton
    local before = bar.commits
    if btn then guard(btn.Click, btn) end
    ok(bar.commits == before and bar.value.r == 0.8, "nothing is committed and the color is unchanged")
    ok(s.picker:IsShown(), "and the picker stays open")
end)

-- ------------------------------------------------------------------ session state, shared

case("the picker's session state is one table every copy shares", function()
    local s = session({ elvui = true })
    swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true):Open()
    drive(s.picker, "ClickOkay")
    local st = s.lib.shared.colorPicker
    ok(st ~= nil and st.alphaInverted == true, "the answer lives in lib.shared")

    -- The same host loading its copy again runs every library file a second time, which is
    -- what a newer copy loading later does too.
    W.loadLibrary(root, s.env, "HostA", s.LibStub)
    ok(s.lib.shared.colorPicker == st and st.alphaInverted == true, "a second load keeps the settled answer")
    local before = s.picker.slider._writes
    swatch(s, { r = 0.4, g = 0.5, b = 0.6, a = 0.25 }, true):Open()
    ok(s.picker.slider._writes == before + 1, "so the next open needs no corrective write")
    local hooks = s.picker._hooks.OnHide or {}
    ok(#hooks == 1, "and the picker carries one OnHide hook, not one per copy: " .. #hooks)
end)

case("closing the picker clears what the open left behind", function()
    local s = session()
    local bar = swatch(s, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    bar:Open()
    local st = s.state()
    ok(st.apply and st.reopen and st.cancel, "an open picker leaves its callbacks for the Class button")
    ok(#(s.picker._hooks.OnHide or {}) == 1, "the OnHide hook goes in once however many opens")
    drive(s.picker, "ClickOkay")
    ok(st.apply == nil and st.reopen == nil and st.cancel == nil and st.owner == nil,
       "and closing it clears every one of them")
end)

-- ---------------------------------------------------------------------- the swatch control

local function picker(s, content, get, opts)
    opts = opts or {}
    local stored = get
    local writes = {}
    local holder = s.ui:CreateColorPicker(content, opts.label or "Bar Color",
        function() return stored end,
        opts.setter or function(v) stored = v writes[#writes + 1] = v end,
        opts.tooltip, opts.hasAlpha ~= false, opts.onClear)
    return holder, function() return stored end, writes, function(v) stored = v end
end

case("CreateColorPicker draws a themed swatch row", function()
    local s = session()
    local content = newContent(s.env)
    local h = picker(s, content, { r = 0.2, g = 0.4, b = 0.6, a = 0.5 }, { tooltip = "Fill color." })
    ok(h._euiFill == true, "a full-width row a card stretches")
    ok(content._controls[#content._controls] == h, "registered for the per-view Refresh")
    ok(h.label:GetText() == "Bar Color" and h.label._font[2] == 13
       and sameColor(h.label._textColor, s.ui:Color("label")), "its label in the label style")
    local lp = h.label._points[1] or {}
    ok(lp[1] == "LEFT" and #h.label._points == 1, "on the left of the row")
    local sw = h.button
    ok(sw and sw:GetWidth() == 34 and sw:GetHeight() == 22, "a 34 x 22 swatch")
    local sp = sw and sw._points[1] or {}
    ok(sp[1] == "RIGHT" and #sw._points == 1, "at the right end of the row")
    local edges, under, fill = 0, nil, nil
    for _, t in ipairs(layer(sw, "BORDER")) do
        if t._euiOwner == sw then
            if sameColor(t._color, s.ui:Color("borderStrong")) then edges = edges + 1 end
        elseif sameColor(t._color, 0, 0, 0, 1) then
            under = t
        end
    end
    for _, t in ipairs(layer(sw, "BACKGROUND")) do
        if sameColor(t._color, s.ui:Color("input")) then fill = t end
    end
    ok(edges == 4, "a 1 px borderStrong edge on all four sides")
    ok(under ~= nil and #under._points == 2, "a black underlay inside it")
    ok(fill ~= nil, "on the input fill")
    for _, r in ipairs({ sw:GetRegions() }) do
        ok(not sameColor(r._color, GOLD[1], GOLD[2], GOLD[3]), "no gold rim")
    end
    ok(#layer(sw, "HIGHLIGHT") == 1, "a hover tint")
    local tex = layer(sw, "ARTWORK")[1]
    ok(tex and sameColor(tex._color, 0.2, 0.4, 0.6, 0.5), "the stored color drawn with its own alpha")
    ok(h.clear == nil, "no Clear without onClear")
    ok(h:GetWidth() == h.label:GetStringWidth() + 8 + 34, "its own width fits label, gap and swatch")

    s.env.fire(h, "OnEnter")
    ok(s.env.tooltip._lines[1] and s.env.tooltip._lines[1].text == "Bar Color", "the row carries the tooltip")
    s.env.tooltip._lines = {}
    s.env.fire(sw, "OnEnter")
    ok(s.env.tooltip._lines[1] and s.env.tooltip._lines[1].text == "Bar Color", "and so does the swatch")
end)

case("the swatch paints set, unset and changed colors", function()
    local s = session()
    local content = newContent(s.env)
    local h, _, _, set = picker(s, content, nil)
    local tex = layer(h.button, "ARTWORK")[1]
    ok(sameColor(tex._color, s.ui:Color("track")), "an unset color draws the track color")
    set({})
    h:Refresh()
    ok(sameColor(tex._color, s.ui:Color("track")), "a table with no channels is still unset")
    set({ r = 0.9, g = 0.1, b = 0.1 })
    h:Refresh()
    ok(sameColor(tex._color, 0.9, 0.1, 0.1, 1), "a color with no alpha draws opaque, and Refresh repaints")
end)

case("Clear shows only while there is a color to clear", function()
    local s = session()
    local content = newContent(s.env)
    local cleared = 0
    local h, get, _, set
    h, get, _, set = picker(s, content, nil, { onClear = function() cleared = cleared + 1 set(nil) end })
    local clear = h.clear
    ok(clear ~= nil and clear.text:GetText() == "Clear", "a clearable picker gets the host's Clear label")
    ok(clear and not clear:IsShown(), "hidden while the color is unset")
    local cp = clear and clear._points[1] or {}
    ok(cp[1] == "RIGHT" and cp[2] == h.button and cp[3] == "LEFT" and cp[4] == -8, "just left of the swatch")
    ok(clear and #layer(clear, "BORDER") == 0 and #layer(clear, "BACKGROUND") == 0,
       "a ghost button, with no edge and no fill")
    ok(h:GetWidth() == h.label:GetStringWidth() + 8 + clear:GetWidth() + 8 + 34,
       "room for it is kept, so the label does not move when it shows")
    set({ r = 0.5, g = 0.5, b = 0.5, a = 1 })
    h:Refresh()
    ok(clear:IsShown(), "shown once a color is set")
    guard(clear.Click, clear)
    ok(cleared == 1 and get() == nil, "pressing it runs the host's onClear")
    ok(not clear:IsShown(), "and repaints, so it hides again")

    local good, err = pcall(function()
        local h2 = s.ui:CreateColorPicker(content, "X", function() end, function() end, nil, true,
            function() end)
        return h2
    end)
    local bare = s.lib:NewContext({
        id = "B", title = "B", version = "1", accent = { 1, 0, 0 }, L = {},
        tooltip = function() return s.env.tooltip end,
    })
    ok(good, "the host's label is enough: " .. tostring(err))
    good, err = pcall(function()
        local h3 = bare:CreateColorPicker(content, "X", function() end, function() end, nil, true,
            function() end)
        return h3
    end)
    ok(not good and tostring(err):find("needs opts.labels.clear", 1, true)
       and tostring(err):find("test_color_picker.lua", 1, true),
       "a clearable picker without labels.clear is refused, pointing at the caller: " .. tostring(err))
end)

case("the swatch opens the picker on the stored color and commits what it hands back", function()
    local s = session()
    local content = newContent(s.env)
    local h, get, writes = picker(s, content, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 })
    local tex = layer(h.button, "ARTWORK")[1]
    guard(h.button.Click, h.button)
    ok(s.picker:IsShown(), "a click opens the picker")
    ok(s.picker._r == 0.8 and s.picker._g == 0.6 and s.picker._b == 0.2
       and s.picker.slider:GetValue() == 0.85, "seeded with the stored color and alpha")
    s.picker:SetColorRGB(0.1, 0.9, 0.3)
    ok(#writes >= 1 and get().g == 0.9 and get().a == 0.85, "the live preview writes through the setter")
    ok(sameColor(tex._color, 0.1, 0.9, 0.3, 0.85), "and repaints the swatch")
    drive(s.picker, "ClickOkay")
    ok(get().r == 0.1 and get().g == 0.9 and get().b == 0.3 and get().a == 0.85, "Okay keeps the pick")

    local noAlpha = picker(s, content, { r = 0.5, g = 0.5, b = 0.5 }, { hasAlpha = false })
    guard(noAlpha.button.Click, noAlpha.button)
    ok(not s.picker.slider:IsShown(), "a no-alpha picker opens without its opacity control")
end)

case("Cancel through the swatch restores the previous value exactly", function()
    local s = session()
    local content = newContent(s.env)
    -- A setter that writes INTO the stored table, as a host may. A snapshot that aliased that
    -- table would be overwritten by the live preview and restore the preview instead.
    local stored = { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }
    local h = s.ui:CreateColorPicker(content, "Bar Color", function() return stored end,
        function(v)
            if v and stored then
                stored.r, stored.g, stored.b, stored.a = v.r, v.g, v.b, v.a
            else
                stored = v
            end
        end, nil, true)
    guard(h.button.Click, h.button)
    s.picker:SetColorRGB(0.1, 0.1, 0.1)
    drive(s.picker, "ClickCancel")
    ok(stored and stored.r == 0.8 and stored.g == 0.6 and stored.b == 0.2 and stored.a == 0.85,
       "the color from before the open comes back")

    local unset = nil
    local u = s.ui:CreateColorPicker(content, "Background Color", function() return unset end,
        function(v) unset = v end, nil, true, function() unset = nil end)
    guard(u.button.Click, u.button)
    s.picker:SetColorRGB(0.3, 0.3, 0.3)
    drive(s.picker, "ClickCancel")
    ok(unset == nil, "and an unset color goes back to unset rather than to white")
end)

case("the whole row opens the picker on a left click", function()
    local s = session()
    local content = newContent(s.env)
    local h = picker(s, content, { r = 0.8, g = 0.6, b = 0.2, a = 0.85 })
    ok(h:IsMouseEnabled(), "the row takes the mouse")
    s.env.fire(h, "OnMouseUp", "RightButton")
    ok(not s.picker:IsShown(), "a right click does nothing")
    s.env.fire(h, "OnMouseUp", "LeftButton")
    ok(s.picker:IsShown(), "a left click anywhere on the row opens it")
end)

-- ------------------------------------------------------------- the window closes its picker

local function inWindow(s, make)
    local made
    s.ui:RegisterTab({ id = "appearance", title = "Appearance",
                       build = function(self, content) made = make(self, content) end })
    local f = s.ui:BuildSettings()
    f:Show()
    return f, made
end

case("closing the window cancels a picker it opened", function()
    local s = session()
    local stored = { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }
    local f, h = inWindow(s, function(ui, content)
        return ui:CreateColorPicker(content, "Bar Color", function() return stored end,
            function(v) stored = v end, nil, true)
    end)
    guard(h.button.Click, h.button)
    ok(s.state().owner == f, "the picker knows which window opened it")
    s.picker:SetColorRGB(0.1, 0.9, 0.3)
    ok(stored.g == 0.9, "the live preview has written")
    f:Hide()
    ok(not s.picker:IsShown(), "closing the window closes the picker")
    ok(stored.r == 0.8 and stored.g == 0.6 and stored.b == 0.2 and stored.a == 0.85,
       "and cancels it, rather than keeping whatever the wheel was sitting on")
end)

case("a picker closed with Okay stays committed when the window closes later", function()
    local s = session()
    local stored = { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }
    local f, h = inWindow(s, function(ui, content)
        return ui:CreateColorPicker(content, "Bar Color", function() return stored end,
            function(v) stored = v end, nil, true)
    end)
    guard(h.button.Click, h.button)
    s.picker:SetColorRGB(0.1, 0.9, 0.3)
    drive(s.picker, "ClickOkay")
    -- Reopened by something else, so the picker is up again with no callbacks of this window's.
    s.picker:Show()
    f:Hide()
    ok(stored.r == 0.1 and stored.g == 0.9, "a stale cancel does not revert the committed color")
end)

case("closing the window leaves another window's picker alone", function()
    local s = session()
    local other = s.lib:NewContext({
        id = "ED", title = "Everything Delves", version = "1", accent = { 0.2, 0.4, 0.7 }, L = {},
        tooltip = function() return s.env.tooltip end, labels = { clear = "Clear" },
    })
    local f = inWindow(s, function() end)
    local stored = { r = 0.8, g = 0.6, b = 0.2, a = 0.85 }
    other:RegisterTab({ id = "x", title = "X", build = function(self, content)
        local h = self:CreateColorPicker(content, "Bar Color", function() return stored end,
            function(v) stored = v end, nil, true)
        guard(h.button.Click, h.button)
    end })
    local g = other:BuildSettings()
    g:Show()
    ok(s.picker:IsShown(), "the other addon's picker is up")
    s.picker:SetColorRGB(0.1, 0.9, 0.3)
    f:Hide()
    ok(s.picker:IsShown(), "this window closing leaves it open")
    ok(stored.g == 0.9, "and does not cancel it")
    local quiet = inWindow(session(), function() end)
    ok(guard(quiet.Hide, quiet), "a window closing with no picker open is fine")
end)

print(("test_color_picker: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end

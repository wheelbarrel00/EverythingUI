-- Run with Lua 5.1 from any folder: lua5.1 tests/test_controls.lua

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

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.0006 end

local GOLD = { 0.92, 0.72, 0.02 }
local TEXTURES = "Interface\\AddOns\\HostA\\Libs\\EverythingUI\\Media\\Textures\\"
-- A name in Cyrillic, written as bytes so this file stays ASCII.
local CYRILLIC = "\208\147\208\176\208\188\208\188\208\176"
local PROFILES = {
    { value = "a", label = "Alpha" }, { value = "b", label = "Beta" }, { value = "c", label = CYRILLIC },
}

local function newCtx(env, lib, over)
    local opts = {
        id = "EQOT", title = "EQ Objective Tracker", version = "1.28.0",
        accent = { 0.784, 0.216, 0.243 }, L = {},
        tooltip = function() return env.tooltip end,
        labels = { testSound = "Plays the currently selected sound." },
    }
    for k, v in pairs(over or {}) do opts[k] = v end
    return lib:NewContext(opts)
end

local function setup(envOpts)
    local env = W.newEnv(envOpts)
    local lib = W.loadLibrary(root, env, "HostA", W.newLibStub())
    return env, lib, newCtx(env, lib)
end

local function newContent(env, width)
    local c = env.CreateFrame("Frame", nil, env.UIParent)
    c._controls = {}
    c._w = width or 856
    return c
end

local function sameColor(c, r, g, b)
    return c ~= nil and near(c[1], r) and near(c[2], g) and near(c[3], b)
end

local function layer(frame, name)
    local out = {}
    for _, r in ipairs({ frame:GetRegions() }) do
        if r._layer == name then out[#out + 1] = r end
    end
    return out
end

-- The latest anchor on a point, since the model keeps every SetPoint in order.
local function point(frame, name)
    for i = #frame._points, 1, -1 do
        local p = frame._points[i]
        if p[1] == name then return p end
    end
    return {}
end

-- A window holding one tab, built and shown, whose build makes whatever the case needs.
local function inWindow(ui, make)
    local made
    ui:RegisterTab({ id = "general", title = "General",
                     build = function(self, content) made = make(self, content) end })
    local f = ui:BuildSettings()
    f:Show()
    return f, made
end

case("Spacing hands tabs the library's own gaps", function()
    local _, _, ui = setup()
    ok(ui:Spacing("groupGap") == 22 and ui:Spacing("rowPadding") == 14, "a token reads back")
    ok(not pcall(ui.Spacing, ui, "nope"), "an unknown name is refused")
end)

case("a button sized from its text is sized again by Refit", function()
    local env, lib, ui = setup()
    local parent = newContent(env)
    local b = ui:CreateButton(parent, "Reset filters to defaults")
    ok(b:GetWidth() == #"Reset filters to defaults" * 6 + 28, "sized from its text and padding at build")
    ok(parent._euiFit and #parent._euiFit == 1 and parent._euiFit[1] == b, "and listed on its parent")
    -- The text as drawn is wider than it measured while the tab was built.
    b.text._measure = 144
    lib.kit.Refit(parent)
    ok(b:GetWidth() == 144 + 28, "Refit sizes it from the text as it measures now: " .. b:GetWidth())
    b.text._measure = 0
    lib.kit.Refit(parent)
    ok(b:GetWidth() == 90 + 28, "and an unmeasured string still leaves it a usable width")
    local fixed = ui:CreateButton(parent, "Go", 100)
    fixed.text._measure = 500
    lib.kit.Refit(parent)
    ok(fixed:GetWidth() == 100 and #parent._euiFit == 1, "a button given a width keeps it and is not listed")
end)

case("a danger button is outlined and lettered in danger, with a danger tint on hover", function()
    local env, _, ui = setup()
    local parent = newContent(env)
    local b = ui:CreateButton(parent, "Wipe history", nil, nil, nil, "danger")
    local edges = layer(b, "BORDER")
    local allDanger = #edges == 4
    for _, e in ipairs(edges) do allDanger = allDanger and sameColor(e._color, ui:Color("danger")) end
    ok(allDanger, "a four-sided outline in danger")
    ok(sameColor(b.text._textColor, ui:Color("danger")), "its text in danger")
    ok(#layer(b, "BACKGROUND") == 0, "and no fill, so it never reads as the accent's filled button")
    local hi = layer(b, "HIGHLIGHT")
    local r, g, bl = ui:Color("danger")
    ok(#hi == 1 and sameColor(hi[1]._color, r, g, bl) and hi[1]._color[4] == 0.12, "danger at 0.12 on hover")
    local s = ui:CreateButton(parent, "Reset")
    local sh = layer(s, "HIGHLIGHT")
    ok(#sh == 1 and sameColor(sh[1]._color, ui:Color("hover")) and sh[1]._color[4] == 0.06,
       "a secondary keeps the white hover")
    ok(sameColor(s.text._textColor, ui:Color("navText")) and sameColor(layer(s, "BORDER")[1]._color, ui:Color("navText")),
       "and its navText outline and text")
end)

case("CreateHeading is a group label", function()
    local env, _, ui = setup()
    local fs = ui:CreateHeading(newContent(env), "Profiles")
    ok(fs:GetText() == "Profiles", "it carries its text as given, never upper-cased")
    ok(fs._font[2] == 12 and fs._font[1]:find("SemiBold", 1, true) and sameColor(fs._textColor, ui:Color("muted")),
       "12 SemiBold in muted")
end)

case("CreateText draws a line in a type style", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local hint = ui:CreateText(content, "Drag and drop", "hint")
    ok(hint._parent == content and hint:GetText() == "Drag and drop", "on the content, with its text")
    ok(hint._font[2] == 12 and hint._font[1]:find("Regular", 1, true) and sameColor(hint._textColor, ui:Color("muted")),
       "12 Regular in muted for a hint")
    local name = ui:CreateText(content, "Campaign")
    ok(name._font[2] == 13 and sameColor(name._textColor, ui:Color("label")), "the label style when none is named")
end)

case("CreateIconButton shows an icon, dims it when disabled, and can flip it", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local down = ui:CreateIconButton(content, "chevron-down", 24)
    local up = ui:CreateIconButton(content, "chevron-down", 24, true)
    local n, d = down:GetNormalTexture(), down:GetDisabledTexture()
    ok(down._type == "Button" and down._w == 24 and down._h == 24, "a 24 px button")
    ok(n._file == TEXTURES .. "chevron-down" and d._file == TEXTURES .. "chevron-down", "the same icon in both states")
    ok(n._w == 16 and n._h == 16 and point(n, "CENTER")[1] == "CENTER" and d._w == 16, "drawn 16 px in the middle")
    ok(#n._points == 1 and #d._points == 1, "with nothing left of the fill the button gave each")
    ok(sameColor(n._vertex, ui:Color("navText")) and sameColor(d._vertex, ui:Color("borderStrong")),
       "navText, and borderStrong while disabled")
    ok(n._texCoord == nil, "not flipped unless asked")
    local un, ud = up:GetNormalTexture()._texCoord, up:GetDisabledTexture()._texCoord
    ok(un and un[3] == 1 and un[4] == 0 and ud and ud[3] == 1 and ud[4] == 0, "flipped top to bottom in both states")
    ok(#layer(down, "HIGHLIGHT") == 1, "with the hover tint")
end)

case("CreateCheckbox draws its box, and repaints whoever changes it", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local state, sets = { v = false }, {}
    local cb = ui:CreateCheckbox(content, "Lock tracker",
        function() return state.v end,
        function(v) sets[#sets + 1] = v end, "Disable drag-to-move and resize.")
    local fill = layer(cb, "BACKGROUND")[1]
    local edges = layer(cb, "BORDER")
    local mark = layer(cb, "ARTWORK")[1]
    local ir, ig, ib = ui:Color("input")
    local br, bg, bb = ui:Color("borderStrong")
    local ar, ag, ab = ui:Color("accent")
    local function looks(on)
        for _, e in ipairs(edges) do
            if on and not sameColor(e._color, ar, ag, ab) then return false end
            if not on and not sameColor(e._color, br, bg, bb) then return false end
        end
        local filled = on and sameColor(fill._color, ar, ag, ab) or (not on and sameColor(fill._color, ir, ig, ib))
        return filled and mark:IsShown() == on
    end

    ok(cb._type == "CheckButton" and cb._w == 16 and cb._h == 16, "a 16 px CheckButton")
    ok(#edges == 4 and #layer(cb, "HIGHLIGHT") == 1, "a four-sided edge and a hover tint")
    ok(mark and mark._file == TEXTURES .. "check" and mark._w == 16, "the check mark, drawn at the box's size")
    ok(sameColor(mark._vertex, ui:Color("accentText")), "tinted accentText, the color drawn on an accent fill")
    ok(looks(false), "unticked: an input fill, a borderStrong edge, no mark")
    local p = cb.label._points[1]
    ok(cb.label:GetText() == "Lock tracker" and p[1] == "LEFT" and p[2] == cb and p[3] == "RIGHT" and p[4] == 10,
       "the label sits 10 px right of the box")
    ok(sameColor(cb.label._textColor, ui:Color("label")), "in the label color")
    ok(cb._hitRect and cb._hitRect[2] == -(12 * 6 + 10), "the label is clickable along its width")
    ok(content._controls[#content._controls] == cb, "registered for the per-view Refresh")
    local bare = ui:CreateCheckbox(content, "Hide", function() return false end, function() end)
    ok(bare._hitRect and bare._hitRect[2] == -(4 * 6 + 10), "a box with no tooltip has a clickable label too")

    cb:Click()
    ok(sets[1] == true and looks(true), "a click ticks it, repaints it and tells the setter")
    cb:Click()
    ok(sets[2] == false and looks(false), "a second click unticks it")
    cb:SetChecked(true)
    ok(looks(true) and #sets == 2, "putting it back by hand repaints it without calling the setter")
    state.v = false
    cb:Refresh()
    ok(not cb:GetChecked() and looks(false) and #sets == 2, "Refresh reads the getter and repaints")
    state.v = 1
    cb:Refresh()
    ok(cb:GetChecked() == true and looks(true), "a truthy saved value reads as ticked")

    env.fire(cb, "OnEnter")
    local lines = env.tooltip._lines
    ok(lines[1].text == "Lock tracker" and sameColor(lines[1].color, GOLD[1], GOLD[2], GOLD[3])
       and lines[2].text == "Disable drag-to-move and resize.", "the tooltip is titled with the label, in gold")
end)

case("CreateSlider: label column, track, value column", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local state, sets = { v = 0.85 }, {}
    local h, s = ui:CreateSlider(content, "Options Window Scale", 0.7, 1.4, 0.05,
        function() return state.v end, function(v) sets[#sets + 1] = v end, "Resizes this window.")
    ok(h.slider == s and s._type == "Slider", "returns the holder and its slider")
    ok(h._euiFill == true and h._h == 30, "a full-width row, 30 tall")
    local l, r = point(s, "LEFT"), point(s, "RIGHT")
    ok(l[2] == h and l[4] == 150 + 14, "the track starts past the 150 px label column: " .. tostring(l[4]))
    ok(r[2] == h and r[4] == -(44 + 14), "and ends before the 44 px value column")
    ok(h.value._w == 44 and h.value._justifyH == "RIGHT" and point(h.value, "RIGHT")[1] == "RIGHT",
       "the value is right-aligned in its column")
    ok(sameColor(h.value._textColor, ui:Color("text")) and h.value._font[1]:find("Medium", 1, true),
       "13 Medium in the text color")
    ok(s._orientation == "HORIZONTAL" and s._min == 0.7 and s._max == 1.4 and s._step == 0.05 and s._obey == true,
       "the range, the step, and steps on drag")
    local thumb = s:GetThumbTexture()
    ok(thumb._file == TEXTURES .. "slider-thumb" and thumb._w == 8 and thumb._h == 15, "a flat 8 x 15 thumb")
    ok(sameColor(thumb._vertex, ui:Color("text")), "in the text color")
    ok(thumb._layer == "OVERLAY", "drawn over the fill")
    local track, fill = layer(s, "BACKGROUND")[1], layer(s, "ARTWORK")[1]
    ok(track and track._h == 3 and sameColor(track._color, ui:Color("track")), "a 3 px track")
    ok(point(track, "LEFT")[1] == "LEFT" and point(track, "RIGHT")[1] == "RIGHT", "running the slider's width")
    local fr = point(fill, "RIGHT")
    ok(fill and fill._h == 3 and sameColor(fill._color, ui:Color("accent")) and fr[2] == thumb and fr[3] == "CENTER",
       "an accent fill up to the thumb")
    ok(h.value:GetText() == "0.85", "the value reads with the step's decimals: " .. tostring(h.value:GetText()))
    ok(#sets == 0, "building it writes nothing")
    ok(content._controls[#content._controls] == h, "registered")

    s:SetValue(1.02)
    ok(near(sets[1], 1.0) and h.value:GetText() == "1.00", "a drag is stepped before the setter sees it: " .. tostring(sets[1]))
    state.v = 2.0
    h:Refresh()
    ok(#sets == 1 and s:GetValue() == 1.4 and h.value:GetText() == "1.40",
       "Refresh clamps an out-of-range save on screen without writing it back")
    env.fire(s, "OnEnter")
    ok(env.tooltip._lines[1].text == "Options Window Scale", "the slider itself carries the tooltip")

    local h2, s2 = ui:CreateSlider(content, "Header size offset", -6, 12, 1, function() return 3 end, function() end)
    ok(h2.value:GetText() == "+3", "a range below zero signs a positive value: " .. tostring(h2.value:GetText()))
    s2:SetValue(0)
    ok(h2.value:GetText() == "0", "but not zero")
    s2:SetValue(-2)
    ok(h2.value:GetText() == "-2", "and a negative one keeps its own sign")
    local h3, s3 = ui:CreateSlider(content, "Spacing", -0.35, 0.35, 0.05, function() return 0.1 end, function() end)
    s3:SetValue(0.001)
    ok(h3.value:GetText() == "0.00", "a step that lands a hair over zero still reads unsigned: " .. tostring(h3.value:GetText()))

    local h4, s4 = ui:CreateSlider(content, nil, 0, 10, 1, function() return 5 end, function() end)
    ok(point(s4, "LEFT")[4] == 0, "no label, no column")
    h4:SetLabelWidth(200)
    ok(point(s4, "LEFT")[4] == 0, "and none even when a group's column is handed to it")
    h:SetLabelWidth(200)
    ok(point(s, "LEFT")[4] == 214, "SetLabelWidth moves the track")
end)

case("CreateDropdown draws its field and keeps it current", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local state = { v = "b" }
    local dd = ui:CreateDropdown(content, "Active profile", PROFILES, function() return state.v end,
        function(v) state.v = v end, "Switches profile.")
    local btn = dd.button
    ok(dd._euiFill and dd._h == 30, "a full-width row, 30 tall")
    ok(btn._h == 30 and point(btn, "LEFT")[4] == 164 and point(btn, "RIGHT")[1] == "RIGHT",
       "a 30 px field from the label column to the end of the row")
    local edges = layer(btn, "BORDER")
    ok(sameColor(layer(btn, "BACKGROUND")[1]._color, ui:Color("input")) and #edges == 4
       and sameColor(edges[1]._color, ui:Color("inputBorder")), "on input with an inputBorder edge")
    local chevron = layer(btn, "ARTWORK")[1]
    ok(chevron._file == TEXTURES .. "chevron-down" and chevron._w == 12 and sameColor(chevron._vertex, ui:Color("muted")),
       "a 12 px muted chevron")
    ok(point(chevron, "RIGHT")[2] == -10, "inset 10 from the right")
    ok(btn.text:GetText() == "Beta" and btn.text:IsShown() and not btn.data:IsShown(), "the field shows the current label")
    ok(btn.text._font[1]:find("Barlow", 1, true) and sameColor(btn.text._textColor, ui:Color("text")),
       "in Barlow, in the text color")
    state.v = "c"
    dd:Refresh()
    ok(btn.data:IsShown() and not btn.text:IsShown() and btn.data:GetText() == CYRILLIC,
       "a name Barlow cannot draw goes to the client's font")
    ok(btn.data._fontObject == env.GameFontHighlight and btn.data._font[1] == "OBJECT",
       "which is a font object, never a file")
    ok(btn.data._shadow and btn.data._shadow[1] == 0 and btn.data._shadow[2] == 0, "with no shadow offset")
    state.v = "a"
    dd:Refresh()
    ok(btn.text:IsShown() and not btn.data:IsShown() and btn.text:GetText() == "Alpha", "and back to Barlow for the next")
    state.v = "zzz"
    dd:Refresh()
    ok(btn.text:GetText() == "zzz", "a value with no option shows the value itself")
    ok(content._controls[#content._controls] == dd, "registered")
    env.fire(btn, "OnEnter")
    ok(env.tooltip._lines[1].text == "Active profile" and env.tooltip._lines[2].text == "Switches profile.",
       "the field carries the tooltip")
    local plain = ui:CreateDropdown(content, nil, PROFILES, function() return "a" end, function() end)
    ok(point(plain.button, "LEFT")[4] == 0, "no label, no column")
    plain:SetLabelWidth(200)
    ok(point(plain.button, "LEFT")[4] == 0, "and none even when a group's column is handed to it")
end)

case("NeedsClientFont is true only for a character Barlow cannot draw", function()
    local _, lib = setup()
    local needs = lib.kit.NeedsClientFont
    ok(needs("Alpha") == false and needs("Caf\195\169 \195\156ber") == false, "Latin, accents included, stays in Barlow")
    ok(needs(CYRILLIC) == true, "Cyrillic does not")
    ok(needs("\228\184\173\230\150\135") == true and needs("\237\149\156") == true, "nor Chinese or Korean")
    ok(needs(nil) == false and needs(42) == false, "and a non-string is left alone")
    ok(needs("pre-selected \226\128\148 just") == false and needs("it\226\128\153s") == false
       and needs("\226\128\166") == false and needs("\226\130\172 5") == false,
       "dashes, curly quotes, an ellipsis and the euro stay in Barlow, which draws them")
    ok(needs("T\225\186\161i") == false, "and so does Vietnamese, which Barlow carries")
    ok(needs("\196\147") == false and needs("\196\148") == true,
       "decided letter by letter: U+0113 is in Barlow, U+0114 beside it is not")
    ok(needs("\226\128\148") == false and needs("\226\128\149") == true, "U+2014 is drawn, U+2015 is not")
    ok(needs("\194\160") == false and needs("\194\159") == true
       and needs("\239\172\130") == false and needs("\239\172\131") == true,
       "the first and last characters Barlow draws, and the ones just outside them")
    ok(needs("\240\159\152\128") == true, "a four-byte character Barlow lacks goes to the client's font")
    ok(needs("\169abc") == true and needs("ab\195") == true and needs("\195\233") == true
       and needs("\245") == true, "and so does text that is not well-formed UTF-8")
end)

case("the list opens under its field, picks before it hides, and closes", function()
    local env, lib, ui = setup()
    local state, seen = { v = "b" }, {}
    local f, dd = inWindow(ui, function(self, content)
        return self:CreateDropdown(content, "Active profile", PROFILES, function() return state.v end,
            function(v)
                seen[#seen + 1] = { v = v, shown = lib.shared.popup:IsShown() }
                state.v = v
            end)
    end)
    f._scale = 0.85
    dd.button._bottom, dd.button._w = 500, 300
    ok(lib.shared.popup == nil, "nothing is built until a list opens")
    dd.button:Click()
    local p = lib.shared.popup
    ok(p and p:IsShown() and p._parent == env.UIParent, "a click opens the shared list, on UIParent")
    ok(near(p._scale, 0.85), "at the scale of the field it opened from: " .. tostring(p._scale))
    ok(p._strata == "FULLSCREEN_DIALOG", "above the window")
    local tl, tr = point(p, "TOPLEFT"), point(p, "TOPRIGHT")
    ok(tl[2] == dd.button and tl[3] == "BOTTOMLEFT" and tl[5] == -2 and tr[2] == dd.button and tr[3] == "BOTTOMRIGHT",
       "under the field and as wide as it")
    ok(p._h == 3 * 22 + 8, "22 px rows: " .. tostring(p._h))
    ok(sameColor(layer(p, "BACKGROUND")[1]._color, ui:Color("surface")) and #p.edges == 4
       and sameColor(p.edges[1]._color, ui:Color("surfaceBorder")), "a surface panel with a surfaceBorder edge")
    local rows = p.rows
    ok(rows[1]:IsShown() and rows[3]:IsShown() and rows[1]._h == 22 and rows[2].text:GetText() == "Beta",
       "one 22 px row per option")
    ok(point(rows[2], "TOPLEFT")[5] == -22, "stacked one under the next")
    ok(sameColor(rows[2].text._textColor, ui:Color("accentHi")) and sameColor(rows[1].text._textColor, ui:Color("text")),
       "the current choice in accentHi, the rest in text")
    ok(rows[3].data:IsShown() and not rows[3].text:IsShown(), "a row Barlow cannot draw uses the client's font")
    ok(#layer(rows[1], "HIGHLIGHT") == 1, "rows tint on hover")
    ok(not p.bar:IsShown() and p.content._w == 300 - 2, "a short list has no scroll bar and the full width")
    ok(p.closer:IsShown(), "a click outside the list is caught")

    rows[1]:Click()
    ok(seen[1] and seen[1].v == "a" and seen[1].shown == true, "the pick runs while the list is still up")
    ok(not p:IsShown() and not p.closer:IsShown(), "then the list closes")
    ok(dd.button.text:GetText() == "Alpha", "and the field shows the new choice")

    dd.button._bottom = 30
    dd.button:Click()
    local bl = point(p, "BOTTOMLEFT")
    ok(bl[2] == dd.button and bl[3] == "TOPLEFT" and bl[5] == 2, "with no room below the field it opens above")
    ok(#p._points == 2, "with nothing left of the anchors it had below")
    p.closer:Click()
    ok(not p:IsShown(), "a click outside closes it")
    dd.button:Click()
    env.fire(p, "OnKeyDown", "ESCAPE")
    ok(not p:IsShown(), "Escape closes it")
end)

case("a pick that raises still closes the list", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    local dd = ui:CreateDropdown(content, "Profile", PROFILES, function() return "a" end,
        function() error("boom") end)
    dd.button._bottom = 500
    dd.button:Click()
    lib.shared.popup.rows[2]:Click()
    ok(#env.errors == 1 and tostring(env.errors[1]):find("boom", 1, true), "the error goes to the error handler")
    ok(not lib.shared.popup:IsShown(), "and the list still closes")
end)

case("a reused row gives back everything the last list gave it", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    env.badFonts["Fonts\\bad.ttf"] = true
    local fontList = {
        { value = "x", label = "Big Font" }, { value = "y", label = "Small", tip = "A tip" },
        { value = "bad", label = "Broken" },
    }
    local fonts = ui:CreateDropdown(content, "Font", fontList, function() return "x" end, function() end, nil,
        function(frame) frame.swatch:SetColorTexture(1, 0, 0, 1) end, nil,
        function(v) return "Fonts\\" .. v .. ".ttf" end)
    ok(sameColor(fonts.button.swatch._color, 1, 0, 0), "decorate paints the closed field's swatch")
    ok(fonts.button.text._font[1] == "Fonts\\x.ttf", "and the field shows the current face")
    fonts.button._bottom = 500
    fonts.button:Click()
    local p = lib.shared.popup
    local r1, r2, r3 = p.rows[1], p.rows[2], p.rows[3]
    ok(r1.text._font[1] == "Fonts\\x.ttf" and r1.text._font[2] == 14, "a font list draws each row in its own face")
    ok(r3.text._font and r3.text._font[1]:find("Barlow-Regular", 1, true), "a face that fails to load falls back to Barlow")
    ok(r1.swatch and r1.swatch:IsShown() and sameColor(r1.swatch._color, 1, 0, 0)
       and point(r1.text, "LEFT")[2] == 10 + 60 + 8, "a decorated list shows the swatch and moves the text past it")
    env.fire(r2, "OnEnter")
    ok(env.tooltip:IsShown() and env.tooltip._lines[1].text == "Small" and env.tooltip._lines[2].text == "A tip",
       "a row with a tip shows it, titled with its label")
    ok(env.tooltip._owner == r2 and env.tooltip._anchor == "ANCHOR_RIGHT",
       "beside the list, where it covers none of the other options")
    env.fire(r2, "OnLeave")
    ok(not env.tooltip:IsShown(), "and hides it")
    env.fire(r2, "OnEnter")
    p:Hide()
    ok(not env.tooltip:IsShown(), "closing the list hides a tip still up")

    local plain = ui:CreateDropdown(content, "Profile", { { value = 1, label = "Default" }, { value = 2, label = "Raid" } },
        function() return 1 end, function() end)
    plain.button._bottom = 500
    plain.button:Click()
    ok(p.rows[1] == r1 and p.rows[2] == r2, "the next list reuses the same rows")
    ok(r1.text._font[1]:find("Barlow-Regular", 1, true) and r1.text._font[2] == 13, "with the face put back")
    ok(not r1.swatch:IsShown() and not r1.swatchBg:IsShown() and point(r1.text, "LEFT")[2] == 10,
       "the swatch given back and the text home again")
    ok(r2:GetScript("OnEnter") == nil and r2:GetScript("OnLeave") == nil, "and no tip carried over")
    ok(not r3:IsShown(), "a row this list does not need is hidden")
    ok(sameColor(r2.text._textColor, ui:Color("text")) and sameColor(r1.text._textColor, ui:Color("accentHi")),
       "and every row's color is set again")
end)

case("a font list survives a face the client will not load", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    env.deadFonts["Fonts\\gone.ttf"] = true
    env.deadFonts["Fonts\\ru.ttf"] = true
    env.keptFonts["Fonts\\kept.ttf"] = true
    local third = "z"
    local list = function()
        return { { value = "x", label = "Big Font" }, { value = "gone", label = "Gone" },
                 { value = third, label = "Third" }, { value = "ru", label = CYRILLIC },
                 { value = "cy", label = CYRILLIC } }
    end
    local current = "gone"
    local fonts
    local built = pcall(function()
        fonts = ui:CreateDropdown(content, "Font", list, function() return current end, function(v) current = v end,
            nil, nil, nil, function(v) return "Fonts\\" .. v .. ".ttf" end)
    end)
    ok(built, "a field whose current face is gone still builds")
    if not fonts then return end
    ok(fonts.button.text._font and fonts.button.text._font[1]:find("Barlow-Regular", 1, true),
       "and draws its label in Barlow")
    fonts.button._bottom = 500
    ok(pcall(fonts.button.Click, fonts.button), "opening the list does not raise")
    local p = lib.shared.popup
    ok(p:IsShown(), "and the list is up")
    local r1, r2, r3, r4 = p.rows[1], p.rows[2], p.rows[3], p.rows[4]
    ok(r1.text._font[1] == "Fonts\\x.ttf", "a face that loads is still previewed")
    ok(r2.text._font and r2.text._font[1]:find("Barlow-Regular", 1, true) and r2.text:IsShown(),
       "a gone face falls back to Barlow")
    ok(r3.text._font[1] == "Fonts\\z.ttf", "the third row shows its own face")
    ok(r4.data:IsShown() and not r4.text:IsShown(),
       "a name Barlow cannot draw goes to the client's font when its own face is gone")
    local r5 = p.rows[5]
    ok(r5.text:IsShown() and not r5.data:IsShown() and r5.text._font[1] == "Fonts\\cy.ttf",
       "and keeps its own face when that face loads, as every font name on a Korean or Chinese client does")
    p:Hide()
    third = "kept"
    fonts.button:Click()
    ok(r3.text._font and r3.text._font[1]:find("Barlow-Regular", 1, true),
       "a face refused with false does not leave the row in the face it had before")
    p:Hide()
    current = "x"
    fonts:Refresh()
    ok(fonts.button.text._font[1] == "Fonts\\x.ttf", "and the field previews again once its face loads")
end)

local function longList(n)
    local out = {}
    for i = 1, n do out[i] = { value = i, label = ("Texture %03d"):format(i) } end
    return out
end

local function shownCount(p)
    local n = 0
    for _, r in ipairs(p.rows) do
        if r:IsShown() then n = n + 1 end
    end
    return n
end

local function rowFor(p, i) return p.rows[(i - 1) % 11 + 1] end

case("a long list builds only the rows it can show and paints them again as it scrolls", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    local picked, painted = nil, 0
    local dd = ui:CreateDropdown(content, "Texture", longList(495), function() return 1 end,
        function(v) picked = v end, nil,
        function(f, v) painted = painted + 1 f.swatch:SetColorTexture(v / 495, 0, 0, 1) end)
    dd.button._bottom = 500
    dd.button:Click()
    local p = lib.shared.popup
    ok(#p.rows == 11, "eleven rows for a ten-row list, one more for a line scrolled part way: " .. #p.rows)
    ok(p.content:GetHeight() == 495 * 22, "while the list keeps its full height, so the bar scrolls all of it")
    ok(p.rows[1].text:GetText() == "Texture 001" and point(p.rows[1], "TOPLEFT")[5] == 0,
       "the first row shows the first option at the top")
    ok(p.rows[11].text:GetText() == "Texture 011" and point(p.rows[11], "TOPLEFT")[5] == -10 * 22,
       "and the last row the eleventh, at its own place")
    local paints = painted
    p.bar:SetValue(5)
    ok(painted == paints, "a scroll inside one row paints nothing")
    local third = p.rows[3]
    p.bar:SetValue(2 * 22)
    ok(painted == paints + 2, "a scroll of two rows paints only the two coming into view: " .. (painted - paints))
    ok(rowFor(p, 3) == third and third.text:GetText() == "Texture 003" and point(third, "TOPLEFT")[5] == -2 * 22,
       "a row still in view keeps its option and its place, so it scrolls with the list")
    ok(rowFor(p, 12) == p.rows[1] and p.rows[1].text:GetText() == "Texture 012" and point(p.rows[1], "TOPLEFT")[5] == -11 * 22,
       "the row that left the top takes the option coming in at the foot")
    p.bar:SetValue(100 * 22 + 5)
    ok(rowFor(p, 101).text:GetText() == "Texture 101" and point(rowFor(p, 101), "TOPLEFT")[5] == -100 * 22,
       "a long scroll paints the options now in view, each at its own place")
    ok(rowFor(p, 111).text:GetText() == "Texture 111" and rowFor(p, 111):IsShown(), "down to the one part in view at the foot")
    ok(sameColor(rowFor(p, 101).swatch._color, 101 / 495, 0, 0), "each with its own swatch")
    p.bar:SetValue(484 * 22)
    ok(rowFor(p, 485):IsShown() and rowFor(p, 485).text:GetText() == "Texture 485", "a row the end of the list will hide")
    p.bar:SetValue(485 * 22)
    ok(rowFor(p, 495).text:GetText() == "Texture 495" and not rowFor(p, 496):IsShown() and shownCount(p) == 10,
       "at the end of the list the row with no option left is hidden")
    p.bar:SetValue(484 * 22)
    ok(rowFor(p, 485):IsShown() and rowFor(p, 485).text:GetText() == "Texture 485",
       "and scrolled back a row it comes back with its option")
    p.bar:SetValue(100 * 22)
    rowFor(p, 103):Click()
    ok(picked == 103, "a pooled row picks the option it shows: " .. tostring(picked))
    ok(not p:IsShown(), "and the list closes")
    local made = #env.created
    dd.button:Click()
    ok(#env.created == made, "opening it again builds no frame")
end)

case("the current choice is marked and scrolled to, however far down it is", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    local dd = ui:CreateDropdown(content, "Texture", longList(495), function() return 250 end, function() end)
    dd.button._bottom = 500
    dd.button:Click()
    local p = lib.shared.popup
    local function marked()
        local out = {}
        for _, r in ipairs(p.rows) do
            if r:IsShown() and sameColor(r.text._textColor, ui:Color("accentHi")) then out[#out + 1] = r end
        end
        return out
    end
    local m = marked()
    ok(#m == 1 and m[1].text:GetText() == "Texture 250", "the row showing the current choice is marked")
    ok(p.bar:GetValue() == 244 * 22, "with the list scrolled to put it in view: " .. p.bar:GetValue())
    p.bar:SetValue(0)
    ok(#marked() == 0, "scrolled away, no row that took another option keeps the mark")
end)

case("a short list after a long one paints its own options and hides the rest", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    local long = ui:CreateDropdown(content, "Texture", longList(495), function() return 1 end, function() end)
    local short = ui:CreateDropdown(content, "Profile", PROFILES, function() return "a" end, function() end)
    long.button._bottom, short.button._bottom = 500, 500
    long.button:Click()
    local p = lib.shared.popup
    p:Hide()
    short.button:Click()
    ok(p.rows[1].text:GetText() == "Alpha" and p.rows[3].data:GetText() == CYRILLIC,
       "the short list paints its own options at the same offset")
    ok(shownCount(p) == 3, "and hides every row it does not need: " .. shownCount(p))
end)

case("a row painted again for another option takes that option's tip and face, or none", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    local list = longList(40)
    list[1].tip = "First tip"
    local dd = ui:CreateDropdown(content, "Font", list, function() return 1 end, function() end, nil, nil, nil,
        function(v) return (v % 2 == 0) and ("Fonts\\f" .. v .. ".ttf") or nil end)
    dd.button._bottom = 500
    dd.button:Click()
    local p = lib.shared.popup
    local r1, r2 = p.rows[1], p.rows[2]
    env.fire(r1, "OnEnter")
    ok(env.tooltip:IsShown() and env.tooltip._lines[2] and env.tooltip._lines[2].text == "First tip",
       "the first option's tip shows")
    env.fire(r1, "OnLeave")
    ok(r2.text._font[1] == "Fonts\\f2.ttf", "the second row in option 2's face")
    p.bar:SetValue(22)
    ok(r1.text:GetText() == "Texture 012" and r1:GetScript("OnEnter") == nil,
       "scrolled a row, the first row takes option 12, which has no tip, and carries none")
    ok(r1.text._font[1] == "Fonts\\f12.ttf", "and that option's face")
    p.bar:SetValue(2 * 22)
    ok(r2.text:GetText() == "Texture 013" and r2.text._font[1]:find("Barlow-Regular", 1, true),
       "a row that drew a face takes a plain option back in Barlow")
end)

case("a host callback raising partway through a paint leaves no row of the last list live", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    local profile
    local profiles = ui:CreateDropdown(content, "Profile", PROFILES, function() return "a" end,
        function(v) profile = v end)
    local boom = true
    local tex = ui:CreateDropdown(content, "Texture", longList(30), function() return 1 end, function() end, nil,
        function(f, v)
            if boom and v == 2 then error("decorate failed") end
            f.swatch:SetColorTexture(1, 1, 1, 1)
        end)
    profiles.button._bottom, tex.button._bottom = 500, 500
    profiles.button:Click()
    local p = lib.shared.popup
    p:Hide()
    ok(not pcall(tex.button.Click, tex.button), "the host's error reaches its caller")
    ok(shownCount(p) == 1 and p.rows[1].text:GetText() == "Texture 001",
       "only the row painted before the error shows: " .. shownCount(p))
    ok(not p.rows[2]:IsShown() and not p.rows[3]:IsShown(),
       "the rows the paint never finished stay hidden, so the profile list's picks on them cannot be clicked")
    for _, r in ipairs(p.rows) do
        if r:IsShown() then r:Click() end
    end
    ok(profile == nil, "and a click on any row showing picks nothing from the profile list")
    boom = false
    p:Show()
    p.bar:SetValue(5)
    ok(p.rows[2]:IsShown() and p.rows[2].text:GetText() == "Texture 002",
       "the next paint finishes the row that raised, since it was never marked painted")
end)

case("a host callback raising during a scroll leaves the row it was painting hidden, and paints it later", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    local boom = true
    local dd = ui:CreateDropdown(content, "Texture", longList(30), function() return 1 end, function() end, nil,
        function(f, v)
            if boom and v == 12 then error("decorate failed") end
            f.swatch:SetColorTexture(1, 1, 1, 1)
        end)
    dd.button._bottom = 500
    dd.button:Click()
    local p = lib.shared.popup
    ok(not pcall(p.bar.SetValue, p.bar, 22), "the host's error reaches the scroll")
    ok(not p.rows[1]:IsShown(), "the row that was taking option 12 is hidden, not left at its new place showing option 1")
    boom = false
    p.bar:SetValue(0)
    ok(p.rows[1]:IsShown() and p.rows[1].text:GetText() == "Texture 001" and point(p.rows[1], "TOPLEFT")[5] == 0,
       "scrolled back, it shows option 1 at its own place again")
end)

case("a tip follows its row's new option when a long scroll brings the same row back under the cursor", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    local list = longList(40)
    for i, o in ipairs(list) do
        if i ~= 23 then o.tip = "tip " .. i end
    end
    local dd = ui:CreateDropdown(content, "X", list, function() return 1 end, function() end)
    dd.button._bottom = 500
    dd.button:Click()
    local p = lib.shared.popup
    local r1, r5 = p.rows[1], p.rows[5]
    env.fire(r1, "OnEnter")
    ok(env.tooltip:IsShown() and env.tooltip._owner == r1 and env.tooltip._lines[2].text == "tip 1",
       "hovering the first row shows option 1's tip")
    p.bar:SetValue(11 * 22)
    ok(r1.text:GetText() == "Texture 012", "a scroll of eleven rows hands the same row option 12")
    ok(env.tooltip:IsShown() and env.tooltip._owner == r1 and env.tooltip._lines[2].text == "tip 12",
       "and the tip follows it")
    p.bar:SetValue(22 * 22)
    ok(r1.text:GetText() == "Texture 023" and not env.tooltip:IsShown(), "an option with no tip takes the tip away")
    p.bar:SetValue(0)
    env.fire(r5, "OnEnter")
    p.bar:SetValue(2 * 22)
    ok(env.tooltip:IsShown() and env.tooltip._owner == r5 and env.tooltip._lines[2].text == "tip 5",
       "a repaint of other rows leaves a shown tip alone")
end)

case("previewEdge must be a function, and the error names the caller", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local good, err = pcall(function()
        local d = ui:CreateDropdown(content, "Border", PROFILES, function() return "a" end, function() end, nil,
            nil, nil, nil, "Interface\\Borders\\Thin")
        return d
    end)
    ok(not good and tostring(err):find("previewEdge must be a function", 1, true) ~= nil
       and tostring(err):find("test_controls.lua", 1, true) ~= nil, "a path passed in its place is refused: " .. tostring(err))
    ok(pcall(ui.CreateDropdown, ui, content, "Border", PROFILES, function() return "a" end, function() end, nil,
        nil, nil, nil, false), "false still means no preview")
end)

case("a border list draws a framed sample of each border, in the swatch's place", function()
    local env, lib, ui = setup({ backdrop = true })
    local content = newContent(env)
    local borders = { { value = "None", label = "None" }, { value = "Thin", label = "Thin" },
                      { value = "Gone", label = "Gone" } }
    local paths = { Thin = "Interface\\Borders\\Thin", Gone = "" }
    local current = "Thin"
    local dd = ui:CreateDropdown(content, "Border Texture", borders, function() return current end,
        function(v) current = v end, nil, nil, nil, nil, function(v) return paths[v] end)
    local fe = dd.button.edge
    ok(fe and fe:IsShown() and fe._w == 28 and fe._h == 18 and point(fe, "LEFT")[2] == 10,
       "the closed field shows the current border, 28 x 18 in the swatch's place")
    ok(fe and fe._backdrop and fe._backdrop.edgeFile == "Interface\\Borders\\Thin" and fe._backdrop.edgeSize == 6
       and sameColor(fe._borderColor, 1, 1, 1), "drawn from its edge file at a 6 px edge, in white")
    ok(point(dd.button.text, "LEFT")[2] == 10 + 28 + 8, "with the label past it")
    dd.button._bottom = 500
    dd.button:Click()
    local p = lib.shared.popup
    local r1, r2, r3 = p.rows[1], p.rows[2], p.rows[3]
    ok(r2.edge and r2.edge:IsShown() and r2.edge._backdrop.edgeFile == "Interface\\Borders\\Thin",
       "each row shows its own border")
    ok(r1.edge and not r1.edge:IsShown() and point(r1.text, "LEFT")[2] == 10 + 28 + 8,
       "None shows no sample but keeps its place, so the labels line up")
    ok(r3.edge and not r3.edge:IsShown(), "and a border with no file shows none either")
    local sets = r2.edge._backdropSets
    p:Hide()
    dd.button:Click()
    ok(r2.edge._backdropSets == sets, "painting the same border again does not rebuild it")
    p:Hide()
    local plain = ui:CreateDropdown(content, "Profile", PROFILES, function() return "a" end, function() end)
    plain.button._bottom = 500
    plain.button:Click()
    ok(not r2.edge:IsShown() and point(r2.text, "LEFT")[2] == 10,
       "a plain list after it hides the sample and puts the text home")
    p:Hide()
    current = "None"
    dd:Refresh()
    ok(not fe:IsShown(), "the closed field hides its sample for None")
end)

case("a border list on a client without BackdropTemplate draws no sample and raises nothing", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local dd
    local good = pcall(function()
        dd = ui:CreateDropdown(content, "Border", { { value = "Thin", label = "Thin" } }, function() return "Thin" end,
            function() end, nil, nil, nil, nil, function() return "Interface\\Borders\\Thin" end)
        dd.button._bottom = 500
        dd.button:Click()
    end)
    ok(good, "it builds and opens")
    ok(dd and dd.button.edge and dd.button.edge._backdrop == nil, "with the sample left blank")
end)

case("a dropdown takes decorate or previewEdge, not both, and the error names the caller", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local good, err = pcall(function()
        local d = ui:CreateDropdown(content, "X", PROFILES, function() return "a" end, function() end, nil,
            function() end, nil, nil, function() end)
        return d
    end)
    ok(not good and tostring(err):find("not both", 1, true) ~= nil and tostring(err):find("test_controls.lua", 1, true) ~= nil,
       "refused, pointing at the caller: " .. tostring(err))
end)

case("every context shares one list, and the list follows whoever opened it", function()
    local env, lib, ui = setup()
    local other = newCtx(env, lib, { id = "ED", accent = { 0.165, 0.447, 0.682 } })
    local content = newContent(env)
    local a = ui:CreateDropdown(content, "A", PROFILES, function() return "b" end, function() end)
    local b = other:CreateDropdown(content, "B", PROFILES, function() return "b" end, function() end)
    a.button._bottom, b.button._bottom = 500, 500
    a.button:Click()
    local p = lib.shared.popup
    p:Hide()
    b.button:Click()
    ok(lib.shared.popup == p and p:IsShown(), "the second addon opens the same list")
    ok(sameColor(p.rows[2].text._textColor, other:Color("accentHi"))
       and not sameColor(p.rows[2].text._textColor, ui:Color("accentHi")), "marked in the opener's accent")
end)

case("a long list scrolls to its choice, and a short one after it starts at the top", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    local long = {}
    for i = 1, 15 do long[i] = { value = i, label = "Item " .. i } end
    local state = { v = 12 }
    local dd = ui:CreateDropdown(content, "Sound", long, function() return state.v end, function() end)
    dd.button._bottom, dd.button._w = 500, 300
    dd.button:Click()
    local p = lib.shared.popup
    ok(p._h == 10 * 22 + 8, "ten rows show at most: " .. tostring(p._h))
    local _, max = p.bar:GetMinMaxValues()
    ok(p.bar:IsShown() and max == 5 * 22, "the bar covers the rest: " .. tostring(max))
    ok(p.scroll:GetVerticalScroll() == 5 * 22 and p.bar:GetValue() == 5 * 22, "a choice near the end scrolls as far as it goes")
    ok(p.content._w == 300 - 13 and point(p.scroll, "BOTTOMRIGHT")[4] == -12, "the rows make room for the bar")
    p:Hide()
    state.v = 7
    dd.button:Click()
    ok(p.scroll:GetVerticalScroll() == 6 * 22 - 5 * 22, "a choice in the middle is brought to the middle")
    p:Hide()
    local short = ui:CreateDropdown(content, "Profile", PROFILES, function() return "c" end, function() end)
    short.button._bottom, short.button._w = 500, 300
    short.button:Click()
    ok(p.scroll:GetVerticalScroll() == 0 and p.bar:GetValue() == 0, "the next short list starts at the top")
    ok(not p.bar:IsShown() and point(p.scroll, "BOTTOMRIGHT")[4] == -1, "with no bar")
end)

case("options can be a function, read again on every open", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    local list = { { value = 1, label = "One" } }
    local dd = ui:CreateDropdown(content, "Profile", function() return list end, function() return 1 end, function() end)
    dd.button._bottom = 500
    dd.button:Click()
    local p = lib.shared.popup
    ok(p.rows[1]:IsShown() and not p.rows[2], "one option")
    p:Hide()
    list = { { value = 1, label = "One" }, { value = 2, label = "Two" } }
    dd.button:Click()
    ok(p.rows[2] and p.rows[2]:IsShown() and p.rows[2].text:GetText() == "Two", "a second option appears on the next open")
end)

case("a dropdown with onTest gets a speaker that replays the pick", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local state, tests = { v = "ding" }, {}
    local list = { { value = "ding", label = "Ding" }, { value = "NONE", label = "None" } }
    local snd = ui:CreateDropdown(content, "Quest Complete Sound", list, function() return state.v end,
        function(v) state.v = v end, nil, nil, function(v) tests[#tests + 1] = v end)
    ok(snd.speaker and snd.speaker:IsShown() and snd.speaker._w == 20, "a 20 px speaker")
    ok(point(snd.button, "LEFT")[4] == 164 + 24 and point(snd.speaker, "RIGHT")[2] == snd.button,
       "left of the field, which moves over for it")
    snd.speaker:Click()
    ok(tests[1] == "ding", "a click plays the current pick")
    env.fire(snd.speaker, "OnEnter")
    ok(env.tooltip._lines[2] and env.tooltip._lines[2].text == "Plays the currently selected sound.",
       "its tip is the host's label")
    state.v = "NONE"
    snd:Refresh()
    ok(not snd.speaker:IsShown(), "no sound has nothing to play, so it hides")
    state.v = "None"
    snd:Refresh()
    ok(not snd.speaker:IsShown(), "nor does a no-sound value saved in another case, as Cooldown Master saves None")
    state.v = "ding"
    snd:Refresh()
    ok(snd.speaker:IsShown(), "and a sound brings it back")
end)

case("closing a window closes a list it opened, and only that one", function()
    local env, lib, ui = setup()
    local other = newCtx(env, lib, { id = "ED" })
    local fa, dd = inWindow(ui, function(self, content)
        return self:CreateDropdown(content, "A", PROFILES, function() return "a" end, function() end)
    end)
    local fb = inWindow(other, function() end)
    dd.button._bottom = 500
    dd.button:Click()
    local p = lib.shared.popup
    fb:Hide()
    ok(p:IsShown(), "another addon's window closing leaves it open")
    fa:Hide()
    ok(not p:IsShown(), "its own window closing closes it")
end)

case("CreateRadioGroup: segmented when it fits, a dropdown otherwise, the same values either way", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    local state, sets = { v = "plain" }, {}
    local two = { { value = "plain", label = "Plain" }, { value = "card", label = "Card", tip = "Boxed rows" } }
    local seg = ui:CreateRadioGroup(content, "Row layout", two, function() return state.v end,
        function(v) sets[#sets + 1] = v end)
    ok(seg.buttons and #seg.buttons == 2, "two choices draw as a segmented control")
    local b1, b2 = seg.buttons[1], seg.buttons[2]
    ok(b1.fill:IsShown() and not b2.fill:IsShown(), "the current choice is filled")
    ok(sameColor(b1.fill._color, ui:Color("accent")) and sameColor(b1.txt._textColor, ui:Color("accentText"))
       and sameColor(b2.txt._textColor, ui:Color("navText")), "accent with accentText, the rest navText")
    ok(b1._h == 26 and b1._w == 5 * 6 + 28, "26 tall, padded 14 each side")
    ok(b1.txt._font[2] == 12 and b1.txt._font[1]:find("SemiBold", 1, true), "12 SemiBold")
    local track = b1:GetParent()
    ok(track._h == 32 and track._w == (5 * 6 + 28) + 2 + (4 * 6 + 28) + 6, "the track wraps them with its inset")
    ok(point(b2, "LEFT")[4] == 3 + 58 + 2, "2 px between segments")
    ok(point(track, "LEFT")[4] == 164, "after the label column")
    b2:Click()
    ok(sets[1] == "card" and b2.fill:IsShown() and not b1.fill:IsShown(), "a click sends the value and repaints")
    env.fire(b2, "OnEnter")
    ok(env.tooltip._lines[1].text == "Card" and env.tooltip._lines[2].text == "Boxed rows", "a per-option tip")
    state.v = "plain"
    seg:Refresh()
    ok(b1.fill:IsShown() and not b2.fill:IsShown(), "Refresh follows the getter")
    ok(content._controls[#content._controls] == seg, "registered")

    local four = {}
    for i = 1, 4 do four[i] = { value = "v" .. i, label = "L" .. i } end
    local dd = ui:CreateRadioGroup(content, "Sort Order", four, function() return "v2" end,
        function(v) sets[#sets + 1] = v end)
    ok(dd.button and not dd.buttons, "four choices draw as a dropdown")
    dd.button._bottom = 500
    dd.button:Click()
    lib.shared.popup.rows[3]:Click()
    ok(sets[#sets] == "v3", "which hands the setter the same values")

    -- 400 leaves 208 past the label column, and the pair needs 304: too wide only because of
    -- the column, so a fit test that forgets the label passes it.
    local narrow = newContent(env, 400)
    local wide = { { value = 1, label = string.rep("W", 20) }, { value = 2, label = string.rep("X", 20) } }
    local nb = ui:CreateRadioGroup(narrow, "Outline", wide, function() return 1 end, function() end)
    ok(nb.button and not nb.buttons, "a translation too wide for the row draws as a dropdown")
    local hidden = 0
    for _, c in ipairs({ narrow:GetChildren() }) do
        if not c:IsShown() then hidden = hidden + 1 end
    end
    ok(hidden == 1 and #narrow._controls == 1, "the segmented attempt is hidden and only the dropdown registers")
end)

case("SetDependent dims, and never takes the mouse away", function()
    local env, _, ui = setup()
    local f = env.CreateFrame("Frame", nil, env.UIParent)
    f:EnableMouse(true)
    ui:SetDependent(f, false)
    ok(f._alpha == 0.4 and f._mouse == true, "dimmed to 0.4 and still hoverable")
    ui:SetDependent(f, true)
    ok(f._alpha == 1, "lit again")
    ok(pcall(ui.SetDependent, ui, nil, false), "a missing control is ignored")
end)

case("AlignSatelliteColumn puts every satellite past the widest label", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local a = ui:CreateCheckbox(content, "Short", function() return false end, function() end)
    local b = ui:CreateCheckbox(content, "A much longer label", function() return false end, function() end)
    local sa = env.CreateFrame("Frame", nil, content)
    local sb = env.CreateFrame("Frame", nil, content)
    sa:SetPoint("RIGHT", content, "RIGHT", -5, 0)
    ui:AlignSatelliteColumn({ b, sb }, { a, sa })
    ok(#sa._points == 1, "a satellite keeps none of the anchor it came with")
    local want = 16 + 10 + 19 * 6 + 16
    ok(point(sa, "LEFT")[2] == a and point(sa, "LEFT")[4] == want and point(sb, "LEFT")[4] == want,
       "one column for both, measured from each box: " .. tostring(point(sa, "LEFT")[4]))
    local c = ui:CreateCheckbox(content, "", function() return false end, function() end)
    local sc = env.CreateFrame("Frame", nil, content)
    ui:AlignSatelliteColumn({ c, sc })
    ok(point(sc, "LEFT")[4] == 192 + 16, "an unmeasured label falls back to the floor rather than 0")
end)

case("AlignPickerColumn lines swatches up past the widest label", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    local function picker(label)
        local p = env.CreateFrame("Frame", nil, content)
        p._w = 100
        p.label = p:CreateFontString()
        p.label:SetText(label)
        p.label:SetPoint("RIGHT", p, "RIGHT", 0, 0)
        p.button = env.CreateFrame("Button", nil, p)
        p.button._w = 34
        p.button:SetPoint("RIGHT", p, "RIGHT", 0, 0)
        return p
    end
    local p1, p2 = picker("Bar Color"), picker("Border Color Override")
    ui:AlignPickerColumn(p2, p1)
    ok(point(p1.button, "LEFT")[4] == 21 * 6 + 8 and point(p2.button, "LEFT")[4] == 21 * 6 + 8, "one swatch column")
    ok(point(p1.button, "TOP")[5] == -1 and point(p1.label, "LEFT")[2] == p1, "labels flush left")
    ok(p1._w == 21 * 6 + 8 + 34 and p2._w == 21 * 6 + 8 + 34, "a holder too narrow for its swatch grows")
    ok(#p1.button._points == 2 and #p1.label._points == 1, "with none of the anchors they were built with")
    ok(content._euiFit and #content._euiFit == 1, "the column is listed on the pickers' content for Refit")
    -- The shorter label as drawn outruns the longer one's measure at build.
    p1.label._measure = 200
    lib.kit.Refit(content)
    ok(point(p1.button, "LEFT")[4] == 208 and point(p2.button, "LEFT")[4] == 208,
       "Refit moves the swatch column past the widest label as it measures now: " .. tostring(point(p2.button, "LEFT")[4]))
    ok(p1._w == 208 + 34 and p2._w == 208 + 34, "and grows each holder to fit it")
    ok(#p1.button._points == 2, "re-anchored rather than given a second LEFT")
end)

case("AlignLabelColumn gives a group one column, dependents shortened by their indent", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local function slider(label) return (ui:CreateSlider(content, label, 0, 10, 1, function() return 1 end, function() end)) end
    local s1 = slider("Size")
    local d1 = ui:CreateDropdown(content, "Font", PROFILES, function() return "a" end, function() end)
    local s2 = slider("Shadow")
    s2._euiDependent = true
    ok(ui:AlignLabelColumn(s1, d1, s2) == 150, "short labels keep the 150 column")
    ok(point(s1.slider, "LEFT")[4] == 164 and point(d1.button, "LEFT")[4] == 164, "the rows line up")
    ok(point(s2.slider, "LEFT")[4] == 124 + 14, "a dependent's column is 26 shorter, so its control lines up too")
    local long = ui:CreateDropdown(content, string.rep("x", 30), PROFILES, function() return "a" end, function() end)
    ok(ui:AlignLabelColumn(s1, long, s2) == 180, "a longer translation widens the column")
    ok(point(s1.slider, "LEFT")[4] == 194 and point(long.button, "LEFT")[4] == 194 and point(s2.slider, "LEFT")[4] == 168,
       "for every row in the group")
    local s3 = slider(string.rep("y", 25))
    s3._euiDependent = true
    ok(ui:AlignLabelColumn(s1, s3) == 25 * 6 + 26, "a dependent's own label counts with its indent")
    local bare = slider(nil)
    ui:AlignLabelColumn(s1, bare)
    ok(point(bare.slider, "LEFT")[4] == 0, "a control with no label keeps no column")
end)

case("a text block stacks wrapping lines in the type styles", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local block = ui:CreateTextBlock(content)
    ok(block._parent == content and block._euiFill == true and #content._controls == 0,
       "a full-width frame on the content, and not a control")
    local a = block:AddLine("Version 1.28.0 by Wheelbarrel00", "value")
    ok(a._parent == block and a:GetText() == "Version 1.28.0 by Wheelbarrel00" and a._wrap == true,
       "a line is a wrapping string in the block")
    ok(a._font[2] == 13 and a._font[1]:find("Medium", 1, true) and sameColor(a._textColor, ui:Color("text")),
       "drawn in its style")
    local tl, tr = point(a, "TOPLEFT"), point(a, "TOPRIGHT")
    ok(tl[2] == block and tl[3] == "TOPLEFT" and tl[4] == 0 and tl[5] == 0
       and tr[2] == block and tr[3] == "TOPRIGHT" and tr[4] == 0 and tr[5] == 0,
       "spanning the block, so it wraps at the block's width")
    ok(block._h == 13, "the block is as tall as its text: " .. tostring(block._h))

    a._measureH = 30
    local b = block:AddLine("A standalone replacement for the default objective tracker.")
    ok(sameColor(b._textColor, ui:Color("label")) and b._font[2] == 13, "a line with no style is a label")
    ok(point(b, "TOPLEFT")[5] == -(30 + 4) and point(b, "TOPRIGHT")[5] == -(30 + 4),
       "the next line starts under the height the first measures, plus 4")
    local c = block:AddLine("New Features", "groupLabel", { gap = 10 })
    ok(point(c, "TOPLEFT")[5] == -(30 + 4 + 13 + 10), "a line can ask for more room above it")
    local d = block:AddLine("Use Blizzard's quest tracker", "label", { bullet = "-", indent = 6 })
    local bullet = block._lines[4].bullet
    local y = -(30 + 4 + 13 + 10 + 12 + 4)
    ok(bullet and bullet._parent == block and bullet:GetText() == "-"
       and sameColor(bullet._textColor, ui:Color("label")) and bullet._font[2] == 13,
       "a bullet is its own string, in the line's style")
    ok(point(bullet, "TOPLEFT")[4] == 6 and point(bullet, "TOPLEFT")[5] == y, "hung at the indent")
    ok(point(d, "TOPLEFT")[4] == 6 + 12 and point(d, "TOPLEFT")[5] == y and point(d, "TOPRIGHT")[4] == 0,
       "with the text 12 further in, so its wrapped lines clear the bullet")
    local e = block:AddLine("2026-09-30", "value", { color = "muted" })
    ok(sameColor(e._textColor, ui:Color("muted")) and e._font[1]:find("Medium", 1, true),
       "a line can take another color and keep its style's face")
    ok(block._h == 30 + 4 + 13 + 10 + 12 + 4 + 13 + 4 + 13, "the block sums its lines: " .. tostring(block._h))

    b._measureH = 52
    local h = block:Measure()
    ok(h == 30 + 4 + 52 + 10 + 12 + 4 + 13 + 4 + 13 and block._h == h,
       "Measure reads every line again and returns the new height: " .. tostring(h))
    ok(point(c, "TOPLEFT")[5] == -(30 + 4 + 52 + 10) and point(e, "TOPLEFT")[5] == -(h - 13),
       "and moves the lines under it")
end)

case("a text block line Barlow cannot draw takes the client's font, in its style's color", function()
    local env, _, ui = setup()
    local block = ui:CreateTextBlock(newContent(env))
    local cyr = block:AddLine("the Campaign term now reads " .. CYRILLIC, "label")
    ok(cyr._fontObject == env.GameFontHighlight and cyr._font[1] == "OBJECT" and cyr:GetText():find(CYRILLIC, 1, true),
       "the whole line goes to the client's font object")
    ok(sameColor(cyr._textColor, ui:Color("label")) and cyr._wrap == true and cyr._parent == block,
       "in its style's color, wrapping in the block")
    local hint = block:AddLine(CYRILLIC, "hint")
    ok(sameColor(hint._textColor, ui:Color("muted")), "a hint keeps its own muted color")
    local colored = block:AddLine(CYRILLIC, "label", { color = "text" })
    ok(sameColor(colored._textColor, ui:Color("text")), "and a line given a color keeps it")
    local latin = block:AddLine("Campaign \226\128\148 an em dash Barlow draws", "label")
    ok(latin._fontObject == nil and latin._font[1]:find("Barlow", 1, true), "a line Barlow can draw keeps Barlow")
end)

case("a line the client has not measured still takes its style's height", function()
    local env, _, ui = setup()
    env.stringHeight = 0
    local block = ui:CreateTextBlock(newContent(env))
    block:AddLine("Version 1.28.0", "value")
    local hint = block:AddLine("Providers are gated at load time.", "hint")
    ok(point(hint, "TOPLEFT")[5] == -(13 + 4) and block._h == 13 + 4 + 12,
       "the font size stands in for each unmeasured line: " .. tostring(block._h))
end)

case("a text row puts its text at the label column's edge", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local row = ui:CreateTextRow(content, "/eqot lock", "Lock moving and resizing")
    ok(row._parent == content and row._euiFill == true and #content._controls == 0,
       "a full-width holder, and not a control")
    ok(row.label:GetText() == "/eqot lock" and sameColor(row.label._textColor, ui:Color("label")),
       "the label in the label style")
    ok(row.text._parent == row and row.text:GetText() == "Lock moving and resizing" and row.text._wrap == false
       and sameColor(row.text._textColor, ui:Color("label")) and row.text._font[2] == 13,
       "the text one line in the label style")
    ok(point(row.text, "LEFT")[2] == row and point(row.text, "LEFT")[4] == 150 + 14
       and point(row.text, "RIGHT")[1] == "RIGHT", "from the 150 column to the row's end")
    row:SetLabelWidth(200)
    ok(point(row.text, "LEFT")[4] == 200 + 14, "SetLabelWidth moves the text")
    local bare = ui:CreateTextRow(content, nil, "quests")
    ok(point(bare.text, "LEFT")[4] == 0, "a row with no label keeps no column")

    local card = ui:CreateGroup(content, "Commands")
    local short = ui:CreateTextRow(content, "/eqot", "Open this window")
    local long = ui:CreateTextRow(content, string.rep("x", 30), "Long")
    local r1 = card:Add(short, { height = ui:Spacing("listRowHeight") })
    card:Add(long, { height = ui:Spacing("listRowHeight") })
    ok(r1._h == 28, "at the list row height")
    ok(point(short.text, "LEFT")[4] == 180 + 14 and point(long.text, "LEFT")[4] == 180 + 14,
       "a card lines its rows' text up past the widest label")
end)

case("CreateSlider's format writes the readout, and only the readout", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local state, sets, asked = { v = 50 }, {}, {}
    local h, s = ui:CreateSlider(content, "Objective pins per quest", 25, 250, 25,
        function() return state.v end, function(v) sets[#sets + 1] = v end, nil,
        function(v) asked[#asked + 1] = v return v >= 250 and "No limit" or ("%d"):format(v) end)
    ok(h.value:GetText() == "50" and asked[1] == 50, "the readout comes from the format at build: " .. tostring(h.value:GetText()))
    ok(asked[2] == 25 and asked[3] == 250 and #asked == 3, "and the format is asked for both ends, to size the readout")
    s:SetValue(262)
    ok(h.value:GetText() == "No limit" and sets[1] == 250, "a drag formats the stepped value, and the setter gets the number")
    state.v = 100
    h:Refresh()
    ok(h.value:GetText() == "100" and #sets == 1, "Refresh formats too, and still writes nothing back")
    local h2 = ui:CreateSlider(content, "Y offset", -50, 50, 1, function() return 7 end, function() end, nil,
        function(v) return ("%d"):format(v) end)
    ok(h2.value:GetText() == "7", "a format of its own adds no sign: " .. tostring(h2.value:GetText()))
    local good, err = pcall(function()
        local made = ui:CreateSlider(content, "Size", 0, 10, 1, function() return 1 end, function() end, nil, "%d")
        return made
    end)
    ok(not good and tostring(err):find("test_controls.lua", 1, true) ~= nil,
       "a format that is not a function raises at the caller: " .. tostring(err))
    local h3 = ui:CreateSlider(content, "Size", 0, 1, 0.05, function() return 0.5 end, function() end)
    ok(h3.value:GetText() == "0.50", "no format keeps the step's own decimals")
end)

-- The model draws 6 px a character, so "Keine Begrenzung" is 96 px against the 44 px column.
case("a formatted readout is as wide as its wider end, and Refit sizes it again", function()
    local env, lib, ui = setup()
    local content = newContent(env)
    local sp = lib.tokens.spacing
    local h, s = ui:CreateSlider(content, "Objective pins per quest", 25, 250, 25, function() return 50 end,
        function() end, nil, function(v) return v >= 250 and "Keine Begrenzung" or ("%d"):format(v) end)
    ok(h.value._w == 96, "the readout widens to the wider end: " .. tostring(h.value._w))
    local p = point(s, "RIGHT")
    ok(p[2] == h and p[3] == "RIGHT" and p[4] == -(96 + sp.controlGap), "the track stops short of it: " .. tostring(p[4]))
    ok(h.value:GetText() == "50", "and the readout still shows the value: " .. tostring(h.value:GetText()))
    local low = ui:CreateSlider(content, "Delay", 0, 10, 1, function() return 5 end, function() end, nil,
        function(v) return v == 0 and "Switched off" or ("%d"):format(v) end)
    ok(low.value._w == 72, "a word at the low end counts as well: " .. tostring(low.value._w))
    local short = ui:CreateSlider(content, "Count", 1, 9, 1, function() return 5 end, function() end, nil,
        function(v) return ("%d"):format(v) end)
    ok(short.value._w == sp.valueColumn and point(short.slider, "RIGHT")[4] == -(sp.valueColumn + sp.controlGap),
       "short ends keep the column: " .. tostring(short.value._w))
    ok(#content._euiFit == 3, "each formatted slider is listed for Refit")
    local plain = ui:CreateSlider(content, "Size", 0, 1, 0.05, function() return 0.5 end, function() end)
    ok(#content._euiFit == 3 and plain.value._w == sp.valueColumn, "a slider with no format keeps the column and is not listed")
    h.value._measure = 120.4
    lib.kit.Refit(content)
    ok(h.value._w == 121 and point(s, "RIGHT")[4] == -(121 + sp.controlGap) and h.value:GetText() == "50",
       "Refit measures it again once the tab is on screen, rounded up to a whole pixel: " .. tostring(h.value._w))
    h.value._measure = 60
    lib.kit.Refit(content)
    ok(h.value._w == 60 and point(s, "RIGHT")[4] == -(60 + sp.controlGap),
       "and a narrower measure shrinks it again: " .. tostring(h.value._w))
end)

case("CreateCheckbox with an icon puts it between the box and the label", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local path = "Interface\\Icons\\INV_Helmet_06"
    local cb = ui:CreateCheckbox(content, "Gear", function() return true end, function() end, "Rewards that are gear.", path)
    local ic = cb.icon
    ok(ic and ic._file == path and ic._w == 16 and ic._h == 16, "a 16 px icon from the path given")
    local ip = point(ic, "LEFT")
    ok(ip and ip[2] == cb and ip[3] == "RIGHT" and ip[4] == 10, "10 px right of the box")
    local lp = point(cb.label, "LEFT")
    ok(lp and lp[2] == ic and lp[3] == "RIGHT" and lp[4] == 10 and #cb.label._points == 1,
       "the label moves 10 px past the icon")
    ok(cb._hitRect and cb._hitRect[2] == -(4 * 6 + 16 + 20), "the click area covers icon and label, tooltip or not: "
       .. tostring(cb._hitRect and cb._hitRect[2]))
    local quiet = ui:CreateCheckbox(content, "Gold", function() return true end, function() end, nil, path)
    ok(quiet._hitRect and quiet._hitRect[2] == -(4 * 6 + 16 + 20), "the same without a tooltip")
    local plain = ui:CreateCheckbox(content, "Gold", function() return true end, function() end)
    ok(plain.icon == nil and point(plain.label, "LEFT")[2] == plain and plain._hitRect[2] == -(4 * 6 + 10),
       "no icon, nothing moves")
    local good, err = pcall(function()
        local made = ui:CreateCheckbox(content, "Gold", function() return true end, function() end, nil, 12)
        return made
    end)
    ok(not good and tostring(err):find("test_controls.lua", 1, true) ~= nil,
       "an icon that is not a path raises at the caller: " .. tostring(err))
end)

local function edgeColor(frame)
    for _, t in ipairs(layer(frame, "BORDER")) do
        if t._euiOwner == frame then return t._color end
    end
end

case("CreateTextField draws a labelled field in the client's font", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local stored = "Lane 1"
    local h = ui:CreateTextField(content, "Frame Name", function() return stored end, function(v) stored = v end,
        "The name on the lane's drag handle.", { maxLetters = 32 })
    ok(h._euiFill == true and h.label:GetText() == "Frame Name", "a full-width labelled row")
    ok(content._controls[#content._controls] == h, "registered for the per-view Refresh")
    local f, box = h.field, h.box
    ok(f and f._h == 30 and point(f, "RIGHT")[1] == "RIGHT" and point(f, "LEFT")[4] == 150 + 14,
       "a 30 px field from the label column's edge to the row's end")
    local filled = false
    for _, t in ipairs(layer(f, "BACKGROUND")) do
        if sameColor(t._color, ui:Color("input")) then filled = true end
    end
    ok(filled and sameColor(edgeColor(f), ui:Color("inputBorder")), "on the input fill with an inputBorder edge")
    ok(box._fontObject == env.GameFontHighlight and sameColor(box._textColor, ui:Color("text")),
       "what is typed is in the client's own font object, in the text color")
    ok(box._maxLetters == 32 and not box:IsNumeric() and box._autoFocus == false,
       "with the letter limit asked for, and never taking the keyboard by itself")
    ok(point(box, "TOPLEFT")[2] == 10 and point(box, "BOTTOMRIGHT")[2] == -10 and box._insets[1] == 0 and box._insets[2] == 0,
       "inset 10 from each end of the field, with no inset of its own")
    ok(box:GetText() == "Lane 1", "showing the stored text")
    h:SetLabelWidth(200)
    ok(point(f, "LEFT")[4] == 200 + 14, "SetLabelWidth moves the field, so AlignLabelColumn lines it up")
    env.fire(box, "OnEnter")
    ok(env.tooltip._lines[1] and env.tooltip._lines[1].text == "Frame Name", "the field carries the row's tooltip")
    env.tooltip._lines = {}
    env.fire(f, "OnEnter")
    ok(env.tooltip._lines[1] and env.tooltip._lines[1].text == "Frame Name", "and so does its padding")
    env.fire(f, "OnMouseDown")
    ok(env.focus == box, "a click on the padding puts the cursor in it")
    env.fire(box, "OnEditFocusGained")
    ok(sameColor(edgeColor(f), ui:Color("borderStrong")), "focused, its edge turns borderStrong")
    box:ClearFocus()
    env.fire(box, "OnEditFocusLost")
    ok(sameColor(edgeColor(f), ui:Color("inputBorder")), "and back when it lets go")
end)

case("a text field commits on Enter or a click away, and Escape puts its text back", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local stored, calls = "Lane 1", {}
    local h = ui:CreateTextField(content, "Frame Name", function() return stored end,
        function(v) stored = v calls[#calls + 1] = v end)
    local box = h.box
    box:SetFocus()
    env.fire(box, "OnEditFocusGained")
    box._text = "Big"
    env.fire(box, "OnTextChanged", true)
    ok(#calls == 0, "typing alone writes nothing")
    env.fire(box, "OnEnterPressed")
    ok(#calls == 1 and stored == "Big" and env.focus == nil, "Enter writes the text once and lets go of the keyboard")
    env.fire(box, "OnEditFocusLost")
    ok(#calls == 1, "and the focus loss after it writes nothing more")

    box:SetFocus()
    env.fire(box, "OnEditFocusGained")
    box._text = "Bigger"
    box:ClearFocus()
    env.fire(box, "OnEditFocusLost")
    ok(#calls == 2 and stored == "Bigger", "a click away commits what was typed")

    box:SetFocus()
    env.fire(box, "OnEditFocusGained")
    box._text = "Oops"
    env.fire(box, "OnEscapePressed")
    ok(box:GetText() == "Bigger" and env.focus == nil, "Escape puts the text back and lets go of the keyboard")
    env.fire(box, "OnEditFocusLost")
    ok(#calls == 2 and stored == "Bigger", "and nothing is written")

    box:SetFocus()
    env.fire(box, "OnEditFocusGained")
    box._text = "Bigger"
    env.fire(box, "OnEnterPressed")
    ok(#calls == 2, "Enter on unchanged text writes nothing")
end)

case("a live text field writes every keystroke, and Escape undoes them", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local stored, calls = "[cd.time]", {}
    local h = ui:CreateTextField(content, "Label Text", function() return stored end,
        function(v) stored = v calls[#calls + 1] = v end, nil, { live = true, maxLetters = 120 })
    local box = h.box
    box:SetFocus()
    env.fire(box, "OnEditFocusGained")
    box._text = "[cd.time] x"
    env.fire(box, "OnTextChanged", true)
    ok(#calls == 1 and stored == "[cd.time] x", "a keystroke is written as it is typed")
    box._text = "set by code"
    env.fire(box, "OnTextChanged", false)
    ok(#calls == 1, "text the code puts in is not written back")
    box._text = "[cd.time] xy"
    env.fire(box, "OnTextChanged", true)
    env.fire(box, "OnEscapePressed")
    ok(box:GetText() == "[cd.time]" and stored == "[cd.time]" and env.focus == nil,
       "Escape puts back the text it had on focus, writes it, and lets go")
    box:SetFocus()
    env.fire(box, "OnEditFocusGained")
    box._text = "[cd.name]"
    env.fire(box, "OnTextChanged", true)
    local n = #calls
    env.fire(box, "OnEnterPressed")
    env.fire(box, "OnEditFocusLost")
    ok(#calls == n and env.focus == nil, "Enter and the focus loss write nothing more")
end)

case("a numeric text field takes digits only and still hands its setter text", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local stored = 12345
    local got
    local h = ui:CreateTextField(content, "Trigger ID", function() return stored end, function(v) got = v end, nil,
        { numeric = true, maxLetters = 10 })
    ok(h.box:IsNumeric() and h.box._maxLetters == 10, "the box takes digits only")
    ok(h.box:GetText() == "12345", "a number from the getter is shown as text")
    h.box:SetFocus()
    env.fire(h.box, "OnEditFocusGained")
    h.box._text = "678"
    env.fire(h.box, "OnEnterPressed")
    ok(got == "678", "the setter gets the text, for the host to convert")
    local blank = ui:CreateTextField(content, "Name", function() return nil end, function() end)
    ok(blank.box:GetText() == "", "nothing stored shows an empty field")
end)

case("Refresh does not write over what is being typed", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local stored = "A"
    local h = ui:CreateTextField(content, "Name", function() return stored end, function() end)
    stored = "B"
    h:Refresh()
    ok(h.box:GetText() == "B", "Refresh shows the stored text")
    h.box:SetFocus()
    h.box._text = "typing"
    stored = "C"
    h:Refresh()
    ok(h.box:GetText() == "typing", "but leaves a focused field alone")
    h:SetText("from a tag button")
    ok(h:GetText() == "from a tag button", "SetText and GetText reach the box")
end)

case("CreateTextField checks what it is given, and the error names the caller", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local function try(...)
        local args = { ... }
        local good, err = pcall(function()
            local h = ui:CreateTextField(content, "X", unpack(args))
            return h
        end)
        return good, tostring(err)
    end
    local get, set = function() return "" end, function() end
    local good, err = try(get, set, nil, { maxLetter = 3 })
    ok(not good and err:find("unknown field maxLetter", 1, true) and err:find("test_controls.lua", 1, true),
       "a misspelled option raises at the caller: " .. err)
    good, err = try(get, set, nil, { live = "yes" })
    ok(not good and err:find("live", 1, true), "an option of the wrong type raises: " .. err)
    good, err = try(get, set, nil, "live")
    ok(not good and err:find("opts must be a table", 1, true), "opts that are not a table raise: " .. err)
    good, err = try(nil, set)
    ok(not good and err:find("needs a getter and a setter", 1, true), "a missing getter raises: " .. err)
    good, err = try(get, nil)
    ok(not good and err:find("needs a getter and a setter", 1, true), "a missing setter raises: " .. err)
    ok(select(1, try(get, set)), "no opts at all is fine")
end)

case("a slider's readout can be clicked to type an exact value", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local stored, calls = 2, {}
    local h, s = ui:CreateSlider(content, "Duration (sec)", 0, 10, 0.5, function() return stored end,
        function(v) stored = v calls[#calls + 1] = v end, "How long the timer runs.")
    ok(h.entry == nil, "a slider has no field until a host asks for one")
    ok(h:EnableTyping() == h and h.entry ~= nil, "EnableTyping adds it and hands the slider back")
    local box = h.entry
    h:EnableTyping()
    ok(h.entry == box, "asking twice builds it once")
    ok(not box:IsShown() and h.value:IsShown(), "it stays hidden behind the readout")
    ok(box._fontObject == env.GameFontHighlight and box._justifyH == "RIGHT" and box._h == 24,
       "a 24 px field, right-aligned, in the client's font")
    ok(box._maxLetters == 12 and box._autoFocus == false and box._insets[1] == 2 and box._insets[2] == 2,
       "twelve letters, never taking the keyboard by itself, inset 2 a side")
    local entryFill
    for _, t in ipairs(layer(box, "BACKGROUND")) do
        if sameColor(t._color, ui:Color("input")) then entryFill = true end
    end
    ok(entryFill and sameColor(edgeColor(box), ui:Color("borderStrong")), "on the input fill with a borderStrong edge")
    local hit
    for _, c in ipairs({ h:GetChildren() }) do
        if c._type == "Button" and c ~= s then hit = c end
    end
    ok(hit and point(hit, "LEFT")[2] == h.value and point(hit, "RIGHT")[2] == h.value and #layer(hit, "HIGHLIGHT") == 1,
       "the readout is a button over the value, with a hover tint")
    env.fire(hit, "OnEnter")
    ok(env.tooltip._lines[1] and env.tooltip._lines[1].text == "Duration (sec)", "and it carries the row's tooltip")

    hit:Click()
    ok(box:IsShown() and not h.value:IsShown() and env.focus == box and box._highlight == true,
       "a click shows the field with the value selected, so typing replaces it")
    ok(box:GetText() == "2.0", "holding the number in the step's decimals: " .. box:GetText())
    box._text = "7.3"
    env.fire(box, "OnEnterPressed")
    ok(stored == 7.5 and #calls == 1, "Enter takes the number on the step: " .. tostring(stored))
    ok(s:GetValue() == 7.5, "with the slider itself on the step, so its thumb and the next edit start there")
    ok(not box:IsShown() and h.value:IsShown() and h.value:GetText() == "7.5" and env.focus == nil,
       "and puts the readout back, showing it")

    hit:Click()
    box._text = "25"
    env.fire(box, "OnEnterPressed")
    ok(stored == 10, "a number past the end is held to the range: " .. tostring(stored))
    hit:Click()
    box._text = "2,5"
    env.fire(box, "OnEnterPressed")
    ok(stored == 2.5, "a comma reads as the decimal point: " .. tostring(stored))
    local n = #calls
    hit:Click()
    box._text = "abc"
    env.fire(box, "OnEnterPressed")
    ok(#calls == n and stored == 2.5 and not box:IsShown(), "text that is not a number changes nothing")
    hit:Click()
    box._text = "9"
    env.fire(box, "OnEscapePressed")
    ok(#calls == n and stored == 2.5 and not box:IsShown() and env.focus == nil, "Escape leaves the value as it was")
    hit:Click()
    box._text = "9"
    env.fire(box, "OnEditFocusLost")
    ok(#calls == n and stored == 2.5 and not box:IsShown() and h.value:IsShown(), "and so does a click away")
end)

case("a typed value on an offset or formatted slider", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local stored = 0
    local h = ui:CreateSlider(content, "X Offset", -100, 100, 1, function() return stored end, function(v) stored = v end)
    h:EnableTyping()
    local hit
    for _, c in ipairs({ h:GetChildren() }) do
        if c._type == "Button" and c ~= h.slider then hit = c end
    end
    hit:Click()
    h.entry._text = "-250"
    env.fire(h.entry, "OnEnterPressed")
    ok(stored == -100, "a negative number past the start is held to it: " .. tostring(stored))
    hit:Click()
    h.entry._text = "+12"
    env.fire(h.entry, "OnEnterPressed")
    ok(stored == 12, "a sign in front is read: " .. tostring(stored))

    local cap = 0
    local f = ui:CreateSlider(content, "Max Ready Icons", 0, 20, 1, function() return cap end, function(v) cap = v end,
        nil, function(v) return v == 0 and "No limit" or tostring(v) end)
    f:EnableTyping()
    local fhit
    for _, c in ipairs({ f:GetChildren() }) do
        if c._type == "Button" and c ~= f.slider then fhit = c end
    end
    ok(f.value:GetText() == "No limit", "the readout shows the format")
    fhit:Click()
    ok(f.entry:GetText() == "0", "but the field holds the number itself: " .. f.entry:GetText())
end)

case("SetRange moves a slider's ends without saving the clamp", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local raw = env.CreateFrame("Slider")
    raw:SetMinMaxValues(0, 100)
    raw:SetValue(90)
    local fired
    raw:SetScript("OnValueChanged", function(_, v) fired = v end)
    raw:SetMinMaxValues(0, 50)
    ok(fired == 50, "the model clamps and fires on a narrower range, as the client does: " .. tostring(fired))

    local stored, writes = 90, 0
    local h = ui:CreateSlider(content, "Seconds", 0, 120, 10, function() return stored end,
        function(v) stored, writes = v, writes + 1 end)
    h:EnableTyping()
    h.SetRange(0, 60)
    local lo, hi = h.slider:GetMinMaxValues()
    ok(lo == 0 and hi == 60 and writes == 0 and stored == 90,
       "a narrower range saves nothing: " .. lo .. ".." .. hi .. " writes " .. writes .. " stored " .. stored)
    ok(h.slider:GetValue() == 60 and h.value:GetText() == "60", "and shows the saved value held to the new end")
    h.SetRange(0, 120)
    ok(h.slider:GetValue() == 90 and h.value:GetText() == "90" and writes == 0, "a wider one shows the saved value again")

    h.SetRange(5, 105)
    local hit
    for _, c in ipairs({ h:GetChildren() }) do
        if c._type == "Button" and c ~= h.slider then hit = c end
    end
    hit:Click()
    h.entry._text = "32"
    env.fire(h.entry, "OnEnterPressed")
    ok(stored == 35 and writes == 1, "a typed value snaps to the step from the new start: " .. tostring(stored))

    local offset = 10
    local o = ui:CreateSlider(content, "X Offset", 0, 100, 1, function() return offset end, function(v) offset = v end)
    o.SetRange(-50, 50)
    ok(o.value:GetText() == "+10", "a range reaching below zero signs a positive value: " .. o.value:GetText())

    local cap = 0
    local f = ui:CreateSlider(content, "Max Ready Icons", 0, 20, 1, function() return cap end, function(v) cap = v end,
        nil, function(v) return v == 0 and "No limit" or tostring(v) end)
    local wide = f.value._w
    f.SetRange(1, 20)
    ok(wide > 44 and f.value._w == 44 and f.value:GetText() == "1",
       "a formatted readout is measured again for its new ends: " .. tostring(wide) .. " to " .. tostring(f.value._w))
end)

local function allEdges(frame, token, ui)
    local n, right = 0, 0
    for _, t in ipairs(layer(frame, "BORDER")) do
        if t._euiOwner == frame then
            n = n + 1
            if sameColor(t._color, ui:Color(token)) then right = right + 1 end
        end
    end
    return n == 4 and right == 4
end

-- Wraps a box so it behaves as the client's: ClearFocus fires OnEditFocusLost, and SetText fires
-- OnTextChanged with userInput false.
local function clientOrder(box)
    local clear, set = box.ClearFocus, box.SetText
    box.ClearFocus = function(b)
        local had = b:HasFocus()
        clear(b)
        if had then b:_fire("OnEditFocusLost") end
    end
    box.SetText = function(b, s)
        set(b, s)
        b:_fire("OnTextChanged", false)
    end
end

local function typingButton(h)
    for _, c in ipairs({ h:GetChildren() }) do
        if c._type == "Button" and c ~= h.slider then return c end
    end
end

case("a text field's edges all turn with its focus, and its padding takes the mouse", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local h = ui:CreateTextField(content, "Name", function() return "" end, function() end)
    ok(h.field:IsMouseEnabled(), "the padding takes the mouse with no tooltip at all")
    h.box:SetFocus()
    env.fire(h.box, "OnEditFocusGained")
    ok(allEdges(h.field, "borderStrong", ui), "all four edges turn borderStrong")
    h.box:ClearFocus()
    env.fire(h.box, "OnEditFocusLost")
    ok(allEdges(h.field, "inputBorder", ui), "and all four turn back")
end)

case("a press away from a focused field lets go of the keyboard, as retail does on its own", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local stored, calls = "Lane 1", 0
    local h = ui:CreateTextField(content, "Frame Name", function() return stored end,
        function(v) stored = v calls = calls + 1 end)
    local box, field = h.box, h.field
    ok(not box._events.GLOBAL_MOUSE_DOWN, "nothing listens while the field is idle")
    box:SetFocus()
    env.fire(box, "OnEditFocusGained")
    ok(box._events.GLOBAL_MOUSE_DOWN, "with the keyboard it listens for a press anywhere")
    box._text = "Lane 1 X"
    field._mouseOver = true
    env.fire(box, "OnEvent", "GLOBAL_MOUSE_DOWN")
    ok(env.focus == box, "a press on the field itself keeps typing")
    field._mouseOver = false
    env.fire(box, "OnEvent", "GLOBAL_MOUSE_DOWN")
    ok(env.focus == nil, "a press anywhere else lets go")
    env.fire(box, "OnEditFocusLost")
    ok(stored == "Lane 1 X" and calls == 1, "and commits, before that press can switch the form to another lane")
    ok(not box._events.GLOBAL_MOUSE_DOWN, "then it stops listening")

    local s = 3
    local sh = ui:CreateSlider(content, "Width", 0, 10, 1, function() return s end, function(v) s = v end)
    sh:EnableTyping()
    typingButton(sh):Click()
    env.fire(sh.entry, "OnEditFocusGained")
    sh.entry._text = "9"
    env.fire(sh.entry, "OnEvent", "GLOBAL_MOUSE_DOWN")
    ok(env.focus == nil, "a slider's typed value lets go the same way")
    env.fire(sh.entry, "OnEditFocusLost")
    ok(s == 3 and not sh.entry:IsShown(), "leaving the value as it was")
end)

case("a client without the global press event builds the fields all the same", function()
    local env, lib = setup()
    env.unknownEvents.GLOBAL_MOUSE_DOWN = true
    local ui = newCtx(env, lib)
    local content = newContent(env)
    local good = pcall(function()
        local h = ui:CreateTextField(content, "Name", function() return "" end, function() end)
        h.box:SetFocus()
        env.fire(h.box, "OnEditFocusGained")
        local sh = ui:CreateSlider(content, "Width", 0, 10, 1, function() return 1 end, function() end)
        sh:EnableTyping()
        typingButton(sh):Click()
        env.fire(sh.entry, "OnEditFocusGained")
    end)
    ok(good, "nothing raises when the event is refused")
end)

case("in the client's order, Enter writes once and the field shows what the host stored", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local stored, calls = "", 0
    local name = ui:CreateTextField(content, "Name", function() return stored end,
        function(v)
            calls = calls + 1
            stored = v:gsub("^%s+", ""):gsub("%s+$", "")
            if stored == "" then stored = "Fireball" end
        end)
    clientOrder(name.box)
    name.box:SetFocus()
    env.fire(name.box, "OnEditFocusGained")
    name.box._text = "  Bob  "
    env.fire(name.box, "OnEnterPressed")
    ok(calls == 1 and stored == "Bob", "a setter that tidies the text is called once: " .. calls)
    ok(name.box:GetText() == "Bob" and env.focus == nil, "and the field shows the tidied text")
    name.box:SetFocus()
    env.fire(name.box, "OnEditFocusGained")
    name.box._text = ""
    env.fire(name.box, "OnEnterPressed")
    ok(name.box:GetText() == "Fireball", "a blank the host fills in shows what it filled in")

    local id = 12345
    local idField = ui:CreateTextField(content, "Trigger ID", function() return id end,
        function(v) id = tonumber(v) end, nil, { numeric = true })
    clientOrder(idField.box)
    idField.box:SetFocus()
    env.fire(idField.box, "OnEditFocusGained")
    idField.box._text = "00678"
    env.fire(idField.box, "OnEnterPressed")
    ok(id == 678 and idField.box:GetText() == "678", "a number shows as stored, without its leading zeros")
    idField.box:SetFocus()
    env.fire(idField.box, "OnEditFocusGained")
    idField.box._text = "999"
    env.fire(idField.box, "OnEscapePressed")
    ok(id == 678 and idField.box:GetText() == "678", "and Escape returns to that, writing nothing")

    local live, lcalls = "[cd.time]", 0
    local lf = ui:CreateTextField(content, "Label Text", function() return live end,
        function(v) live = v lcalls = lcalls + 1 end, nil, { live = true })
    clientOrder(lf.box)
    lf.box:SetFocus()
    env.fire(lf.box, "OnEditFocusGained")
    env.fire(lf.box, "OnEscapePressed")
    ok(lcalls == 0 and lf.box:GetText() == "[cd.time]", "Escape on a live field with nothing typed writes nothing")
    local tidy = ui:CreateTextField(content, "Frame Name", function() return live end,
        function(v) live = v:gsub("%s+$", "") end, nil, { live = true })
    clientOrder(tidy.box)
    tidy.box:SetFocus()
    env.fire(tidy.box, "OnEditFocusGained")
    tidy.box._text = "Lane 2   "
    env.fire(tidy.box, "OnTextChanged", true)
    tidy.box:ClearFocus()
    ok(live == "Lane 2" and tidy.box:GetText() == "Lane 2", "a live field shows what was stored once it lets go")
end)

case("a text field's smaller contracts", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local stored = "A"
    local h = ui:CreateTextField(content, "Name", function() return stored end, function() end)
    stored = nil
    h:Refresh()
    ok(h.box:GetText() == "", "Refresh to nothing stored empties the field")
    h:SetText(nil)
    ok(h.box._text == "", "SetText with nothing gives the box an empty string, never nil")
    local function where(fn)
        local good, err = pcall(fn)
        return not good and tostring(err):find("test_controls.lua", 1, true) ~= nil
    end
    ok(where(function() local r = ui:CreateTextField(content, "X", nil, function() end) return r end),
       "a missing getter raises at the caller")
    ok(where(function() local r = ui:CreateTextField(content, "X", function() end, function() end, nil, 7) return r end),
       "opts that are not a table raise at the caller")
end)

case("the typed value's button and field trade places, and its tip opens where the row's does", function()
    local env, _, ui = setup()
    local content = newContent(env)
    local stored = 2
    local h = ui:CreateSlider(content, "Duration (sec)", 0, 10, 0.5, function() return stored end,
        function(v) stored = v end, "How long the timer runs.")
    ok(h:EnableTyping() == h and h:EnableTyping() == h, "EnableTyping hands the slider back every time")
    local hit = typingButton(h)
    env.fire(hit, "OnEnter")
    ok(env.tooltip._owner == h and env.tooltip._lines[1] and env.tooltip._lines[1].text == "Duration (sec)",
       "the number's tip is the row's, placed off the row")
    env.fire(hit, "OnLeave")
    ok(not env.tooltip:IsShown(), "and it goes when the mouse leaves")
    hit:Click()
    ok(not hit:IsShown(), "while the field is open the button is out of its way")
    env.fire(h.entry, "OnEscapePressed")
    ok(hit:IsShown() and h.value:IsShown(), "and after, the number can be clicked again")
end)

case("a typed value of not-a-number is turned away", function()
    local realTonumber = tonumber
    _G.tonumber = function(s, base)
        if s == "nan" then return 0 / 0 end
        return realTonumber(s, base)
    end
    local env, _, ui = setup()
    _G.tonumber = realTonumber
    local content = newContent(env)
    local stored, calls = 2, 0
    local h = ui:CreateSlider(content, "Width", 0, 10, 1, function() return stored end,
        function(v) stored = v calls = calls + 1 end)
    h:EnableTyping()
    typingButton(h):Click()
    h.entry._text = "nan"
    env.fire(h.entry, "OnEnterPressed")
    ok(calls == 0 and stored == 2 and h.value:GetText() == "2",
       "on a client whose tonumber reads nan, nothing is written: " .. tostring(stored))
end)

print(("test_controls: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end

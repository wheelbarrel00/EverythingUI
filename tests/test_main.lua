-- Run with Lua 5.1 from any folder: lua5.1 tests/test_main.lua
-- The main window pieces: CreateWindow, CreateScrollArea, CreateSearchField, CreateList, CreateTag,
-- CreateProgressBar, Paint, CreateEmptyState, a dropdown option's suffix and the owner of its list.

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

local TEXTURES = "Interface\\AddOns\\HostA\\Libs\\EverythingUI\\Media\\Textures\\"
local CYRILLIC = "\208\147\208\176\208\188\208\188\208\176"

local function newCtx(env, lib, over)
    local opts = {
        id = "EQ", title = "Everything Quests", version = "2.1.0",
        accent = { 0.784, 0.216, 0.243 }, L = {},
        tooltip = function() return env.tooltip end,
    }
    for k, v in pairs(over or {}) do opts[k] = v end
    return lib:NewContext(opts)
end

local function setup(envOpts)
    local env = W.newEnv(envOpts)
    local lib = W.loadLibrary(root, env, "HostA", W.newLibStub())
    return env, lib, newCtx(env, lib)
end

local function sameColor(c, r, g, b)
    return c ~= nil and near(c[1], r) and near(c[2], g) and near(c[3], b)
end

local function point(frame, name)
    for i = #frame._points, 1, -1 do
        local p = frame._points[i]
        if p[1] == name then return p end
    end
    return {}
end

local function layer(frame, name)
    local out = {}
    for _, r in ipairs({ frame:GetRegions() }) do
        if r._layer == name then out[#out + 1] = r end
    end
    return out
end

local function raises(fn, needle)
    local good, err = pcall(fn)
    return not good and tostring(err):find(needle, 1, true) ~= nil, err
end

-- A spec with every pair the window can take, recording what the host is told.
local function fullSpec(state, over)
    local spec = {
        title = "Chain Guide", name = "EQChainGuideFrame", width = 1100, height = 720,
        minWidth = 760, minHeight = 460, sidebarWidth = 280, gripTip = "Drag to resize",
        getSize = function() return state.w, state.h end,
        setSize = function(w, h) state.w, state.h = w, h state.sized = (state.sized or 0) + 1 end,
        getMaximized = function() return state.max end,
        setMaximized = function(v) state.max = v state.maxSet = (state.maxSet or 0) + 1 end,
        onResize = function() state.resized = (state.resized or 0) + 1 end,
    }
    for k, v in pairs(over or {}) do spec[k] = v end
    return spec
end

case("CreateWindow checks its spec and points an error at the caller", function()
    local _, _, ui = setup()
    local good, err = raises(function() ui:CreateWindow({}) end, "needs a title")
    ok(good, "a window with no title is refused")
    ok(tostring(err):find("test_main.lua", 1, true) ~= nil, "the error points at the caller: " .. tostring(err))
    ok(raises(function() ui:CreateWindow({ title = "X", sidebar = 200 }) end, "bad or unknown field sidebar"),
       "an unknown field is refused")
    ok(raises(function() ui:CreateWindow({ title = "X", width = "1100" }) end, "bad or unknown field width"),
       "a field of the wrong type is refused")
    ok(raises(function() ui:CreateWindow({ title = "X", getSize = function() end }) end, "getSize and setSize come as a pair"),
       "getSize without setSize is refused")
    ok(raises(function() ui:CreateWindow({ title = "X", setMaximized = function() end }) end, "getMaximized and setMaximized"),
       "setMaximized without getMaximized is refused")
    ok(raises(function() ui:CreateWindow({ title = "X", minWidth = 700 }) end, "minWidth and minHeight"),
       "a minimum width without a height is refused")
    local _, err2 = raises(function() ui:CreateWindow({ title = "X", nope = 1 }) end, "nope")
    ok(tostring(err2):find("test_main.lua", 1, true) ~= nil, "a field error points at the caller too")
end)

case("a window is built when the host asks, in the settings window's frame", function()
    local env, _, ui = setup()
    ok(#env.created == 0, "loading the library builds nothing")
    local state = {}
    local f = ui:CreateWindow(fullSpec(state))
    ok(f._name == "EQChainGuideFrame" and f._parent == env.UIParent, "named by the host, on UIParent")
    ok(f._w == 1100 and f._h == 720, "the default size while the host has none saved")
    ok(f._strata == "DIALOG" and f._clamped == true and f._movable == true and f._mouse == true,
       "DIALOG strata, clamped, movable, and it takes the mouse")
    ok(not f:IsShown(), "built hidden")
    ok(f._euiWindow == true, "marked as a library window")
    ok(sameColor(layer(f, "BACKGROUND")[1]._color, ui:Color("bg")), "the window body in bg")
    ok(f.header._h == 48 and sameColor(layer(f.header, "BACKGROUND")[1]._color, ui:Color("chrome")), "a 48 px chrome header")
    ok(f.title:GetText() == "Chain Guide", "the host's title in the header")
    ok(f.title._font[2] == 15, "in the title style")
    ok(not f.slash:IsShown() and f.section:GetText() == nil, "no section until the host names one")
    f:SetSection("Westfall")
    ok(f.slash:IsShown() and f.section:GetText() == "Westfall", "SetSection names it after a slash")
    f:SetSection(nil)
    ok(not f.slash:IsShown(), "and an empty section hides the slash again")
    f:Show()
    f.closeButton:Click()
    ok(not f:IsShown(), "the close button hides it")
    f:Show()
    env.fire(f, "OnKeyDown", "ESCAPE")
    ok(not f:IsShown(), "Escape hides it")

    local plain = ui:CreateWindow({ title = "What's New" })
    ok(plain._w == 1100 and plain._h == 720, "a spec with no size takes the token size")
    ok(plain.maxButton == nil and plain.grip == nil and plain.sidebar == nil,
       "no maximize, grip or sidebar unless asked for")
end)

case("the header moves the window, and a maximized window stays put", function()
    local env, _, ui = setup()
    local f = ui:CreateWindow(fullSpec({}))
    ok(f.header._mouse == true and f.header._drag and f.header._drag[1] == "LeftButton", "the header takes a left drag")
    ok(f._drag == nil, "the window itself does not, so a drag inside it never moves it")
    env.fire(f.header, "OnDragStart")
    ok(f._moving == true, "dragging the header moves the window")
    env.fire(f.header, "OnDragStop")
    ok(f._moving == false, "letting go stops it")
    f:SetMaximized(true)
    env.fire(f.header, "OnDragStart")
    ok(f._moving ~= true, "a maximized window does not move")
end)

case("a saved size is used, never below the minimum", function()
    local _, _, ui = setup()
    local f = ui:CreateWindow(fullSpec({ w = 900, h = 600 }))
    ok(f._w == 900 and f._h == 600, "the saved size")
    local g = ui:CreateWindow(fullSpec({ w = 300, h = 100 }))
    ok(g._w == 760 and g._h == 460, "a saved size below the minimum is raised to it")
    local h = ui:CreateWindow(fullSpec({ w = 0, h = -5 }))
    ok(h._w == 1100 and h._h == 720, "a nonsense saved size falls back to the default")
end)

case("the sidebar sits under the header and the body beside it", function()
    local _, _, ui = setup()
    local f = ui:CreateWindow(fullSpec({}))
    local sb = f.sidebar
    ok(sb and sb._w == 280 and point(sb, "TOPLEFT")[3] == -48, "a 280 px sidebar under the header")
    ok(sameColor(layer(sb, "BACKGROUND")[1]._color, ui:Color("chrome")), "in chrome")
    ok(type(sb._controls) == "table" and type(f.body._controls) == "table", "both can hold library controls")
    local tl = point(f.body, "TOPLEFT")
    ok(tl[2] == f and tl[4] == 280 and tl[5] == -48, "the body starts past the sidebar")
    f:SetSidebarShown(false)
    ok(not sb:IsShown() and not f:IsSidebarShown(), "the sidebar can be hidden")
    tl = point(f.body, "TOPLEFT")
    ok(tl[4] == 0 and tl[5] == -48, "and the body takes its room")
    f:SetSidebarShown(true)
    ok(point(f.body, "TOPLEFT")[4] == 280 and f:IsSidebarShown(), "and gives it back")
    local plain = ui:CreateWindow({ title = "X" })
    ok(point(plain.body, "TOPLEFT")[4] == 0, "a window with no sidebar has a full-width body")
end)

case("maximize fills the screen in the window's units and puts it back", function()
    local env, _, ui = setup({ uiWidth = 1600, uiHeight = 900 })
    local state = { w = 900, h = 600 }
    local f = ui:CreateWindow(fullSpec(state))
    local mx = f.maxButton
    ok(mx and mx:GetNormalTexture():GetTexture() == TEXTURES .. "maximize", "a maximize button with its icon")
    ok(point(mx, "RIGHT")[2] == f.closeButton, "just left of the close button")
    f._scale = 0.8
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 40, -50)
    mx:Click()
    ok(state.max == true and state.maxSet == 1, "the host is told")
    ok(near(f._w, 1600 / 0.8 - 60) and near(f._h, 900 / 0.8 - 60), "the screen less a margin, in the window's units: "
       .. tostring(f._w) .. "x" .. tostring(f._h))
    ok(point(f, "CENTER")[2] == env.UIParent, "centered on the screen")
    ok(mx:GetNormalTexture():GetTexture() == TEXTURES .. "restore", "the button now restores")
    ok(f:IsMaximized(), "IsMaximized says so")
    ok(state.resized == 1, "the host hears of the new size")
    mx:Click()
    ok(state.max == false and state.maxSet == 2 and not f:IsMaximized(), "a second click restores and says so")
    ok(f._w == 900 and f._h == 600, "at the size the host keeps")
    local tl = point(f, "TOPLEFT")
    ok(tl[2] == env.UIParent and tl[4] == 40 and tl[5] == -50 and #f._points == 1, "where it stood before")
    ok(mx:GetNormalTexture():GetTexture() == TEXTURES .. "maximize", "and the button maximizes again")
    ok(state.resized == 2, "the host hears of that too")
    f:SetMaximized(false)
    ok(state.maxSet == 2 and state.resized == 2, "asking for the state it is already in does nothing")
end)

case("a window saved maximized opens maximized, and fits again on show and Refit", function()
    local _, _, ui = setup({ uiWidth = 1600, uiHeight = 900 })
    local state = { max = true }
    local f = ui:CreateWindow(fullSpec(state))
    ok(f:IsMaximized() and state.maxSet == nil and state.resized == nil, "maximized at build, telling the host nothing")
    ok(f.maxButton:GetNormalTexture():GetTexture() == TEXTURES .. "restore", "with the restore icon")
    ok(near(f._w, 1540), "filling the screen")
    f._scale = 1.25
    f:Show()
    ok(near(f._w, 1600 / 1.25 - 60), "showing it fits it again at its scale now")
    f._scale = 1
    f:Refit()
    ok(near(f._w, 1540), "and so does Refit")
    local g = ui:CreateWindow(fullSpec({ w = 900, h = 600 }))
    g._scale = 1.2
    g:Refit()
    g:Show()
    ok(g._w == 900, "a window that is not maximized keeps its size")
end)

case("the grip resizes from the corner and tells the host the size", function()
    local env, _, ui = setup()
    local state = { w = 900, h = 600 }
    local f = ui:CreateWindow(fullSpec(state))
    local grip = f.grip
    ok(f._resizable == true and f._bounds[1] == 760 and f._bounds[2] == 460, "resizable, bounded by the minimum")
    ok(grip._w == 16 and point(grip, "BOTTOMRIGHT")[2] == -2 and point(grip, "BOTTOMRIGHT")[3] == 2,
       "a 16 px grip in the bottom right corner")
    ok(grip:GetFrameLevel() == f:GetFrameLevel() + 20, "above whatever the body holds")
    ok(grip:GetNormalTexture():GetTexture() == TEXTURES .. "grip"
       and sameColor(grip:GetNormalTexture()._vertex, ui:Color("muted")), "the grip texture in muted")
    ok(#layer(grip, "HIGHLIGHT") == 1, "with the hover tint")
    env.fire(grip, "OnMouseDown", "LeftButton")
    ok(f._sizing == "BOTTOMRIGHT", "a press starts sizing from the corner")
    f._w, f._h = 1000, 650
    env.fire(grip, "OnMouseUp", "LeftButton")
    ok(f._sizing == nil, "letting go stops")
    ok(state.w == 1000 and state.h == 650 and state.sized == 1, "the host keeps the new size")
    ok(state.resized == 1, "and hears of it")
    env.fire(grip, "OnEnter")
    ok(env.tooltip._shown and env.tooltip._lines[1] and env.tooltip._lines[1].text == "Drag to resize",
       "the grip's tip")
end)

case("grabbing the grip of a maximized window resizes it from there", function()
    local env, _, ui = setup()
    local state = { w = 900, h = 600, max = true }
    local f = ui:CreateWindow(fullSpec(state))
    env.fire(f.grip, "OnMouseDown", "LeftButton")
    ok(f._sizing == "BOTTOMRIGHT", "sizing starts from where it stands")
    ok(near(f._w, 1366 - 60), "without first shrinking back")
    ok(f:IsMaximized() and state.maxSet == nil, "still maximized until a drag is let go of")
    f._w, f._h = 1200, 700
    env.fire(f.grip, "OnMouseUp", "LeftButton")
    ok(not f:IsMaximized() and state.max == false, "no longer maximized, and the host is told")
    ok(f.maxButton:GetNormalTexture():GetTexture() == TEXTURES .. "maximize", "the button maximizes again")
    ok(state.w == 1200 and state.h == 700, "the size let go of is its normal size")
    f.maxButton:Click()
    f.maxButton:Click()
    ok(f._w == 1200 and point(f, "CENTER")[2] ~= nil, "and maximize then restore come back to it, centered")
end)

case("header buttons line up right to left before the window's own", function()
    local env, _, ui = setup()
    local hits = 0
    local f = ui:CreateWindow(fullSpec({}))
    local cog = f:AddHeaderButton("icon-settings", "Options", "Opens the options.", function() hits = hits + 1 end)
    ok(cog._w == 32 and cog:GetNormalTexture():GetTexture() == TEXTURES .. "icon-settings", "a 32 px icon button")
    ok(point(cog, "RIGHT")[2] == f.maxButton and point(cog, "RIGHT")[4] == -2, "left of maximize, 2 px apart")
    ok(point(f.maxButton, "RIGHT")[2] == f.closeButton, "maximize stays by close")
    ok(point(f.closeButton, "RIGHT")[2] == f.header and point(f.closeButton, "RIGHT")[4] == -8, "close 8 px from the edge")
    ok(point(f.section, "RIGHT")[2] == cog, "the section name stops at the last button")
    cog:Click()
    ok(hits == 1, "a click runs the host's action")
    env.fire(cog, "OnEnter")
    ok(env.tooltip._lines and env.tooltip._lines[1] and env.tooltip._lines[1].text == "Options", "with its tooltip")
    local second = f:AddHeaderButton("icon-sidebar")
    ok(point(second, "RIGHT")[2] == cog and point(f.section, "RIGHT")[2] == second, "each new one goes further left")
end)

case("hiding a window closes the tooltip and a list it opened, and only that list", function()
    local env, lib, ui = setup()
    local f = ui:CreateWindow(fullSpec({}))
    local g = ui:CreateWindow({ title = "Other" })
    local dd = ui:CreateDropdown(f.sidebar, nil, { { value = 1, label = "One" } }, function() return 1 end, function() end)
    dd.button._bottom = 500
    f:Show()
    g:Show()
    dd.button:Click()
    local p = lib.shared.popup
    ok(p.owner == f, "a list opened inside a main window belongs to it")
    g:Hide()
    ok(p:IsShown(), "another window closing leaves it open")
    f:Hide()
    ok(not p:IsShown(), "its own window closing closes it")
    f:Show()
    env.tooltip._shown = true
    f:Hide()
    ok(not env.tooltip._shown, "a window closing with no list open still closes the tooltip")
end)

-- A scroll area with a content larger than its view.
local function scrolled(ui, env, opts, xrange, yrange)
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local a = ui:CreateScrollArea(parent, opts)
    a.scroll._w, a.scroll._h = 800, 500
    a.vbar._h, a.hbar._w = 480, 780
    a.scroll._hrange, a.scroll._vrange = xrange or 0, yrange or 0
    env.fire(a.scroll, "OnScrollRangeChanged", xrange or 0, yrange or 0)
    return a
end

case("a scroll area shows a bar only for a direction it can scroll", function()
    local env, _, ui = setup()
    local a = scrolled(ui, env, nil, 0, 0)
    ok(not a.vbar:IsShown() and not a.hbar:IsShown(), "nothing to scroll, no bars")
    ok(a.scroll:GetScrollChild() == a.content, "the content is the scroll child")
    ok(point(a.scroll, "BOTTOMRIGHT")[2] == -10 and point(a.scroll, "BOTTOMRIGHT")[3] == 10, "room left for both bars")
    a.scroll._vrange = 300
    env.fire(a.scroll, "OnScrollRangeChanged", 0, 300)
    ok(a.vbar:IsShown() and not a.hbar:IsShown(), "a vertical range shows the vertical bar only")
    local _, vmax = a.vbar:GetMinMaxValues()
    ok(vmax == 300, "with the range as its maximum")
    ok(a.vbar._w == 6 and a.hbar._h == 6, "6 px bars")
    ok(near(a.vbar:GetThumbTexture()._h, math.max(24, 480 * 500 / 800)), "the thumb sized from the bar's own length: "
       .. tostring(a.vbar:GetThumbTexture()._h))
    ok(sameColor(a.vbar:GetThumbTexture()._vertex, ui:Color("borderStrong")), "a borderStrong thumb")
    a.scroll._hrange = 900
    env.fire(a.scroll, "OnScrollRangeChanged", 900, 300)
    ok(a.hbar:IsShown(), "a horizontal range shows the horizontal bar")
    ok(near(a.hbar:GetThumbTexture()._w, math.max(24, 780 * 800 / 1700)), "its thumb sized the same way")
    a.vbar:SetValue(250)
    ok(a.scroll:GetVerticalScroll() == 250, "the bar scrolls the view")
    a.hbar:SetValue(400)
    ok(a.scroll:GetHorizontalScroll() == 400, "both ways")
    a.scroll._vrange, a.scroll._hrange = 100, 50
    env.fire(a.scroll, "OnScrollRangeChanged", 50, 100)
    ok(a.vbar:GetValue() == 100 and a.hbar:GetValue() == 50, "a shrinking range pulls the position back inside it")
    a.scroll._vrange = 100000
    env.fire(a.scroll, "OnScrollRangeChanged", 50, 100000)
    ok(a.vbar:GetThumbTexture()._h == 24, "a long range keeps a thumb big enough to grab")
end)

case("in a resizable window's corner, both bars end short of the grip", function()
    local _, _, ui = setup()
    local f = ui:CreateWindow(fullSpec({ w = 900, h = 600 }))
    local gp = point(f.grip, "BOTTOMRIGHT")
    local reachX, reachY = f.grip._w - gp[2], f.grip._h + gp[3]
    local plain = ui:CreateScrollArea(f.body, {})
    ok(point(plain.vbar, "BOTTOMRIGHT")[3] == 10 and point(plain.hbar, "BOTTOMRIGHT")[2] == -10,
       "elsewhere the bars meet in a 10 px corner")
    local a = ui:CreateScrollArea(f.body, { clearGrip = true })
    local vy, hx = point(a.vbar, "BOTTOMRIGHT")[3], point(a.hbar, "BOTTOMRIGHT")[2]
    ok(vy == reachY + 2, "the upright bar ends 2 px above the grip: " .. tostring(vy) .. " for a grip reaching " .. reachY)
    ok(hx == -(reachX + 2), "the sideways bar ends 2 px left of it: " .. tostring(hx))
    ok(point(a.scroll, "BOTTOMRIGHT")[2] == -10 and point(a.scroll, "BOTTOMRIGHT")[3] == 10, "the view keeps its size")
end)

case("ScrollTo clamps to the range, and ClampScroll pulls a stale offset back", function()
    local env, _, ui = setup()
    local a = scrolled(ui, env, nil, 600, 400)
    a:ScrollTo(250, 120)
    local x, y = a:GetScrollOffset()
    ok(x == 250 and y == 120, "an offset inside the range")
    a:ScrollTo(-40, 999)
    x, y = a:GetScrollOffset()
    ok(x == 0 and y == 400, "clamped at both ends")
    a:ScrollTo(nil, 10)
    x, y = a:GetScrollOffset()
    ok(x == 0 and y == 10, "nil leaves that direction alone")
    a:SetContentSize(2000, 0)
    ok(a.content._w == 2000 and a.content._h == 1, "SetContentSize sizes the content, never below 1")
    a.scroll._hscroll, a.scroll._vscroll = 700, 500
    a:ClampScroll()
    x, y = a:GetScrollOffset()
    ok(x == 600 and y == 400, "ClampScroll pulls an offset past the edge back")
end)

case("the wheel scrolls down and up, and sideways with Shift", function()
    local env, _, ui = setup()
    local a = scrolled(ui, env, nil, 600, 400)
    ok(a.content._wheel == true, "the content takes the wheel")
    env.fire(a.content, "OnMouseWheel", -1)
    local x, y = a:GetScrollOffset()
    ok(y == 48 and x == 0, "one notch down is 48 px")
    env.fire(a.content, "OnMouseWheel", 1)
    x, y = a:GetScrollOffset()
    ok(y == 0 and x == 0, "and up again")
    env.shift = true
    env.fire(a.content, "OnMouseWheel", -2)
    x, y = a:GetScrollOffset()
    ok(x == 96 and y == 0, "Shift scrolls sideways")
    env.shift = false
    local b = scrolled(ui, env, { wheelStep = 72 }, 600, 400)
    env.fire(b.content, "OnMouseWheel", -1)
    local _, by = b:GetScrollOffset()
    ok(by == 72, "a host can set the step")
    ok(raises(function() ui:CreateScrollArea(env.UIParent, "pan") end, "opts must be a table"), "opts must be a table")
end)

case("a left drag on the content pans it, past a small threshold", function()
    local env, _, ui = setup()
    local a = scrolled(ui, env, { pan = true }, 600, 400)
    a:ScrollTo(300, 200)
    ok(a.content._mouse == true, "the content takes the mouse to pan")
    env.mouseDown = "LeftButton"
    env.cursorX, env.cursorY = 100, 100
    env.fire(a.content, "OnMouseDown", "LeftButton")
    ok(env.cursor == "UI_MOVE_CURSOR", "the move cursor while a drag can start")
    ok(a.content:GetScript("OnUpdate") ~= nil, "it follows the mouse each frame")
    ok(not a:IsPanGesture(), "not a drag before the mouse moves")
    env.tooltip._shown = true
    env.cursorX, env.cursorY = 103, 102
    env.fire(a.content, "OnUpdate")
    local x, y = a:GetScrollOffset()
    ok(x == 297 and y == 202, "the view follows the mouse, screen y the other way round: " .. x .. "," .. y)
    ok(env.tooltip._shown and not a:IsPanGesture(), "3 px is still a click")
    env.cursorX, env.cursorY = 110, 95
    ok(a:IsPanGesture(), "the distance is read again live, before the next update")
    env.fire(a.content, "OnUpdate")
    ok(not env.tooltip._shown, "past 5 px the tooltip goes")
    x, y = a:GetScrollOffset()
    ok(x == 290 and y == 195, "and the view keeps following")
    env.cursorX, env.cursorY = 101, 100
    ok(a:IsPanGesture(), "a drag that comes back near its start is still a drag")
    env.fire(a.content, "OnUpdate")
    env.mouseDown = nil
    env.fire(a.content, "OnUpdate")
    ok(a.content:GetScript("OnUpdate") == nil and env.cursor == nil, "a button let go off the frame ends it")
    ok(not a:IsPanGesture(), "after which a click is a click")

    env.mouseDown = "LeftButton"
    env.fire(a.content, "OnMouseDown", "RightButton")
    ok(a.content:GetScript("OnUpdate") == nil, "a right press does not pan")
    env.fire(a.content, "OnMouseDown", "LeftButton")
    env.fire(a.content, "OnMouseUp", "LeftButton")
    ok(a.content:GetScript("OnUpdate") == nil and env.cursor == nil, "letting go on the content ends it")
    env.fire(a.content, "OnMouseDown", "LeftButton")
    env.fire(a.content, "OnHide")
    ok(a.content:GetScript("OnUpdate") == nil, "hiding ends it")

    local flat = scrolled(ui, env, { pan = true }, 0, 0)
    env.fire(flat.content, "OnMouseDown", "LeftButton")
    ok(flat.content:GetScript("OnUpdate") == nil, "nothing to scroll, nothing to pan")
    local still = scrolled(ui, env, nil, 600, 400)
    ok(still.content._mouse ~= true and still.content:GetScript("OnMouseDown") == nil, "no pan unless asked for")
end)

case("a search field hints while empty and hands over trimmed text on Enter", function()
    local env, _, ui = setup()
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local got = {}
    local s = ui:CreateSearchField(parent, "Find quest", function(t) got[#got + 1] = t end, "Find quest", "Type a name.")
    ok(s._h == 30 and sameColor(layer(s, "BACKGROUND")[1]._color, ui:Color("input")), "a 30 px field on input")
    ok(s.box._fontObject == env.GameFontHighlight, "typed text in the client's font object")
    ok(s.box._maxLetters == 64 and s.box._autoFocus == false, "64 letters, never focused on its own")
    local icon = layer(s, "ARTWORK")[1]
    ok(icon and icon._file == TEXTURES .. "search" and icon._w == 14, "a 14 px magnifier")
    ok(s.hint:IsShown() and s.hint:GetText() == "Find quest", "the hint while empty")
    ok(sameColor(s.hint._textColor, ui:Color("muted")), "in muted")
    s.box:SetFocus()
    env.fire(s.box, "OnEditFocusGained")
    ok(not s.hint:IsShown(), "gone while typing")
    local edgeColor
    for _, r in ipairs({ s:GetRegions() }) do if r._euiAxis then edgeColor = r._color end end
    ok(sameColor(edgeColor, ui:Color("borderStrong")), "the edge brightens on focus")
    s.box:SetText("  Moonbrook  ")
    env.fire(s.box, "OnEnterPressed")
    ok(got[1] == "Moonbrook", "Enter hands over the trimmed text")
    ok(not s.box:HasFocus(), "and lets go of the keyboard")
    env.fire(s.box, "OnEditFocusLost")
    ok(not s.hint:IsShown(), "text left in the field keeps the hint away")
    for _, r in ipairs({ s:GetRegions() }) do if r._euiAxis then edgeColor = r._color end end
    ok(sameColor(edgeColor, ui:Color("inputBorder")), "and the edge settles back")
    s:SetText("")
    ok(s.hint:IsShown() and s:GetText() == "", "SetText back to empty brings the hint back")
    s.box:SetText("   ")
    env.fire(s.box, "OnEnterPressed")
    ok(#got == 1, "blank text is never handed over")
    s.box:SetFocus()
    env.fire(s.box, "OnEscapePressed")
    ok(not s.box:HasFocus() and #got == 1, "Escape only lets go")
    env.fire(s.box, "OnEnter")
    ok(env.tooltip._lines and env.tooltip._lines[1] and env.tooltip._lines[1].text == "Find quest", "the field's tooltip")
    ok(raises(function() ui:CreateSearchField(parent, "x") end, "needs onSubmit"), "onSubmit is required")
end)

local function listIn(ui, env, onClick)
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local l = ui:CreateList(parent, onClick)
    l.scroll._w, l.scroll._h = 279, 400
    return l
end

case("a list draws a 28 px row per entry, its value and its icons", function()
    local env, _, ui = setup()
    local clicks = {}
    local l = listIn(ui, env, function(key, row, i) clicks[#clicks + 1] = { key, row, i } end)
    l:SetRows({
        { key = 8000036, text = "Westfall Stew", value = "1/2" },
        { key = 8092742, text = "Testing the Wells", value = "3/11", selected = true,
          icons = { { name = "icon-map", color = "accentHi" } }, tip = { "Testing the Wells", "3 / 11 quests done" } },
        { key = 8006181, text = "A Swift Message", value = "4/4", muted = true, icons = { { name = "check" } } },
    })
    local r = l.rows
    ok(r[1]._h == 28 and point(r[2], "TOPLEFT")[5] == -28 and point(r[3], "TOPLEFT")[5] == -56, "28 px rows, one under the next")
    ok(r[1].text:GetText() == "Westfall Stew" and r[1].value:GetText() == "1/2", "the text and the value")
    ok(sameColor(r[1].text._textColor, ui:Color("label")) and r[1].text._font[2] == 13, "a plain row in label")
    ok(sameColor(r[1].value._textColor, ui:Color("muted")) and r[1].value._font[2] == 12, "the value in the hint style")
    ok(point(r[1].value, "RIGHT")[2] == -12, "12 px from the right end")
    ok(not r[1].selected:IsShown() and r[2].selected:IsShown(), "the selected row tinted")
    ok(sameColor(r[2].selected._color, ui:Color("accentSoft")) and near(r[2].selected._color[4], 0.18), "in accentSoft")
    ok(sameColor(r[2].text._textColor, ui:Color("text")) and r[2].text._font[1]:find("SemiBold", 1, true),
       "its text in text, SemiBold")
    ok(sameColor(r[3].text._textColor, ui:Color("muted")), "a muted row in muted")
    local pin = r[2].icons[1]
    ok(pin and pin:IsShown() and pin._file == TEXTURES .. "icon-map" and pin._w == 12, "a 12 px icon")
    ok(sameColor(pin._vertex, ui:Color("accentHi")), "in the color asked for")
    ok(point(pin, "RIGHT")[2] == r[2].value and point(pin, "RIGHT")[4] == -8, "8 px before the value")
    ok(sameColor(r[3].icons[1]._vertex, ui:Color("muted")), "muted when no color is given")
    local tr = point(r[2].text, "RIGHT")
    ok(tr[2] == pin and tr[3] == "LEFT" and tr[4] == -8, "the text stops short of the icon")
    tr = point(r[1].text, "RIGHT")
    ok(tr[2] == r[1].value and tr[3] == "LEFT" and tr[4] == -8, "or of the value")
    ok(#layer(r[1], "HIGHLIGHT") == 1, "rows tint on hover")
    r[2]:Click()
    ok(clicks[1] and clicks[1][1] == 8092742 and clicks[1][3] == 2 and clicks[1][2].text == "Testing the Wells",
       "a click hands over the key, the row and its index")
    env.fire(r[2], "OnEnter")
    ok(env.tooltip._anchor == "ANCHOR_RIGHT" and env.tooltip._lines[1].text == "Testing the Wells"
       and env.tooltip._lines[2].text == "3 / 11 quests done", "a row's tip beside the list")
    ok(l.content._h == 3 * 28 + 12, "the content as tall as the rows: " .. tostring(l.content._h))
end)

case("a reused row gives back what the last rows gave it", function()
    local env, _, ui = setup()
    local l = listIn(ui, env)
    l:SetRows({
        { key = 1, text = "Testing the Wells", value = "3/11", selected = true,
          icons = { { name = "icon-map" }, { name = "check" } }, tip = { "A", "B" } },
        { key = 2, text = "B" },
    })
    l:SetRows({ { key = 3, text = "Plain" } })
    local r = l.rows[1]
    ok(not r.selected:IsShown(), "no longer selected")
    ok(not r.icons[1]:IsShown() and not r.icons[2]:IsShown(), "its icons gone")
    ok(r.value:GetText() == "", "its value gone")
    ok(r:GetScript("OnEnter") == nil and r:GetScript("OnLeave") == nil, "its tip gone")
    ok(sameColor(r.text._textColor, ui:Color("label")) and not r.text._font[1]:find("SemiBold", 1, true),
       "back to the plain style")
    local tr = point(r.text, "RIGHT")
    ok(tr[2] == r.value and tr[3] == "RIGHT" and tr[4] == 0, "the text runs to the end with nothing after it")
    ok(not l.rows[2]:IsShown(), "a row past the new list is hidden")
    l:SetRows({ { text = CYRILLIC } })
    ok(l.rows[1].data:IsShown() and not l.rows[1].text:IsShown(), "a name Barlow cannot draw takes the client's font")
    ok(sameColor(l.rows[1].data._textColor, ui:Color("label")), "in the row's color")
    l:SetRows({ { text = "Latin" } })
    ok(l.rows[1].text:IsShown() and not l.rows[1].data:IsShown(), "and gives it back")
end)

case("SetRows checks every row and points at the caller", function()
    local env, _, ui = setup()
    local l = listIn(ui, env)
    local good, err = raises(function() l:SetRows({ { text = "a", colour = "red" } }) end, "unknown field colour")
    ok(good, "an unknown field is refused")
    ok(tostring(err):find("test_main.lua", 1, true) ~= nil, "pointing at the caller: " .. tostring(err))
    ok(raises(function() l:SetRows({ { value = "1/2" } }) end, "needs text"), "a row with no text is refused")
    ok(raises(function() l:SetRows({ { text = "a", selected = "yes" } }) end, "field selected"), "a mistyped field is refused")
    ok(raises(function() l:SetRows("rows") end, "needs a list"), "rows must be a list")
    ok(pcall(function() l:SetRows({ { key = { 1 }, text = "a" } }) end), "a key can be anything")
    local _, tipErr = raises(function() l:SetRows({ { text = "a", tip = {} } }) end, "tip with no text")
    ok(tostring(tipErr):find("test_main.lua", 1, true) ~= nil, "a tip with no text is refused at the caller: " .. tostring(tipErr))
    ok(pcall(function() l:SetRows({ { text = "a", tip = { nil, "Body only" } } }) end), "a tip with only a body is fine")
    local _, iconErr = raises(function() l:SetRows({ { text = "a", icons = { { color = "muted" } } } }) end, "icon with no name")
    ok(tostring(iconErr):find("test_main.lua", 1, true) ~= nil, "an icon with no name is refused at the caller: " .. tostring(iconErr))
    ok(raises(function() l:SetRows({ { text = "a", icons = { { name = "check", color = 3 } } } }) end, "icon with no name"),
       "a mistyped icon color is refused")
end)

case("ScrollToRow brings a row into view with the least scroll", function()
    local env, _, ui = setup()
    local l = listIn(ui, env)
    local rows = {}
    for i = 1, 30 do rows[i] = { text = "Chain " .. i } end
    l:SetRows(rows)
    l.scroll._h = 280
    l.scroll._vrange = 30 * 28 + 12 - 280
    l:ScrollToRow(20)
    ok(l.bar:GetValue() == 20 * 28 - 280, "a row below the view scrolls to its bottom: " .. l.bar:GetValue())
    l:ScrollToRow(3)
    ok(l.bar:GetValue() == 2 * 28, "a row above it scrolls to its top")
    l:ScrollToRow(5)
    ok(l.bar:GetValue() == 2 * 28, "a row already in view stays put")
    l:ScrollToRow(30)
    ok(l.bar:GetValue() == 30 * 28 - 280, "the last row")
end)

case("a list's content follows its width, less the bar while it shows", function()
    local env, _, ui = setup()
    local l = listIn(ui, env)
    l:SetRows({ { text = "a" } })
    ok(l.content._w == 279, "the list's width")
    l.bar:Show()
    l.scroll._w = 300
    env.fire(l, "OnSizeChanged")
    ok(l.content._w == 300 - 12, "less the bar's room once it shows")
end)

case("a tag is an accent pill or an outline, as wide as its text", function()
    local env, _, ui = setup()
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local t = ui:CreateTag(parent, "NEXT", "accent")
    local fill = layer(t, "BACKGROUND")[1]
    ok(t._h == 16 and t._w == 4 * 6 + 12, "16 px tall, the text plus 6 each side: " .. tostring(t._w))
    ok(fill:IsShown() and sameColor(fill._color, ui:Color("accent")), "filled with the accent")
    ok(sameColor(t.text._textColor, ui:Color("accentText")), "lettered in accentText")
    ok(t.text._font[2] == 12 and t.text._font[1]:find("SemiBold", 1, true), "12 SemiBold")
    local edges = {}
    for _, r in ipairs({ t:GetRegions() }) do if r._euiAxis then edges[#edges + 1] = r end end
    ok(#edges == 4 and not edges[1]:IsShown(), "no outline")
    t:SetStyle("outline")
    ok(not fill:IsShown() and edges[1]:IsShown() and sameColor(edges[1]._color, ui:Color("borderStrong")),
       "an outline in borderStrong")
    ok(sameColor(t.text._textColor, ui:Color("label")), "lettered in label")
    t:SetText("ON QUEST")
    ok(t._w == 8 * 6 + 12, "SetText fits it again")
    t.text._measure = 0
    t:Fit()
    ok(t._w == 24 + 12, "an unmeasured text still makes a tag")
    t.text._measure = 30.4
    t:Fit()
    ok(t._w == 31 + 12, "a fractional width rounds up")
    local plain = ui:CreateTag(parent, "X")
    ok(not layer(plain, "BACKGROUND")[1]:IsShown(), "an outline unless asked for")
    ok(raises(function() ui:CreateTag(parent, "X", "red") end, "no tag style named red"), "an unknown style is refused")
    ok(raises(function() t:SetStyle("red") end, "no tag style named red"), "and SetStyle refuses one too")
end)

case("a progress bar fills with the accent up to its share", function()
    local env, _, ui = setup()
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local b = ui:CreateProgressBar(parent, 120)
    ok(b._w == 120 and b._h == 3, "120 by 3")
    ok(sameColor(layer(b, "BACKGROUND")[1]._color, ui:Color("track")), "a track")
    ok(sameColor(b.fill._color, ui:Color("accent")), "an accent fill")
    ok(not b.fill:IsShown(), "empty to start")
    b:SetProgress(3 / 11)
    ok(near(b.fill._w, 120 * 3 / 11) and b.fill:IsShown(), "3 of 11 fills that share")
    b:SetProgress(2)
    ok(near(b.fill._w, 120), "never past full")
    b:SetProgress(-1)
    ok(not b.fill:IsShown(), "never below empty")
    b:SetProgress(0.5)
    b._w = 200
    env.fire(b, "OnSizeChanged")
    ok(near(b.fill._w, 100), "a resized bar fills again")
    local d = ui:CreateProgressBar(parent)
    ok(d._w == 120, "120 wide unless told")
end)

case("Paint gives any frame the library's fill and 1 px edge", function()
    local env, _, ui = setup()
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local card = env.CreateFrame("Button", nil, parent)
    local fill, edges = ui:Paint(card, "surface", "surfaceBorder")
    ok(fill and fill._layer == "BACKGROUND" and sameColor(fill._color, ui:Color("surface")), "a surface fill")
    ok(#fill._points == 2 and point(fill, "TOPLEFT")[1] and point(fill, "BOTTOMRIGHT")[1], "over the whole frame")
    ok(#edges == 4 and sameColor(edges[1]._color, ui:Color("surfaceBorder")), "an edge on all four sides")
    ok(edges[1]._h == 1 and edges[3]._w == 1, "1 px, snapped")
    local before = #ui._lines
    local f2, e2 = ui:Paint(env.CreateFrame("Frame", nil, parent), nil, "divider", "B")
    ok(f2 == nil and #e2 == 1 and #ui._lines == before + 1, "an edge alone, on one side, registered for re-snapping")
    ok(point(e2[1], "BOTTOMLEFT")[1] == "BOTTOMLEFT" and sameColor(e2[1]._color, ui:Color("divider")), "the bottom side")
    local f3, e3 = ui:Paint(env.CreateFrame("Frame", nil, parent), "chrome")
    ok(f3 and #e3 == 0, "a fill alone")
    ok(raises(function() ui:Paint(card, "nope") end, "no color named nope"), "an unknown color is refused")
end)

case("an empty state is one muted line in the middle", function()
    local env, _, ui = setup()
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local fs = ui:CreateEmptyState(parent, "Pick a chain on the left to view its quests.")
    ok(fs:GetText() == "Pick a chain on the left to view its quests.", "the host's text")
    ok(sameColor(fs._textColor, ui:Color("muted")) and fs._font[2] == 13, "13 in muted")
    ok(fs._justifyH == "CENTER" and fs._wrap == true, "centered and wrapped")
    ok(point(fs, "LEFT")[2] == 40 and point(fs, "RIGHT")[2] == -40, "40 in from each side")
end)

case("a dropdown option's suffix sits at the row's end and on the field", function()
    local env, lib, ui = setup()
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    parent._controls = {}
    local zones = {
        { value = 1436, label = "Westfall", suffix = "10-44" },
        { value = 1429, label = "Elwynn Forest", suffix = "1-27" },
        { value = 9, label = "No range" },
    }
    local cur = 1436
    local dd = ui:CreateDropdown(parent, nil, zones, function() return cur end, function(v) cur = v end)
    local btn = dd.button
    ok(btn.suffix:GetText() == "10-44", "the field shows the current option's suffix")
    ok(sameColor(btn.suffix._textColor, ui:Color("muted")) and btn.suffix._font[2] == 12, "in the hint style")
    local tr = point(btn.text, "RIGHT")
    ok(tr[2] == btn.suffix and tr[3] == "LEFT" and tr[4] == -8, "the field's text stops short of it")
    btn._bottom = 500
    btn:Click()
    local p = lib.shared.popup
    ok(p.rows[1].suffix:GetText() == "10-44" and p.rows[2].suffix:GetText() == "1-27", "each row shows its own")
    ok(point(p.rows[1].suffix, "RIGHT")[2] == -10, "at the row's right end")
    tr = point(p.rows[1].text, "RIGHT")
    ok(tr[2] == p.rows[1].suffix and tr[4] == -8, "with the row's text stopping short of it")
    tr = point(p.rows[3].text, "RIGHT")
    ok(p.rows[3].suffix:GetText() == "" and tr[2] == -10, "a row with none runs to the end")
    p.rows[3]:Click()
    ok(btn.suffix:GetText() == "" and point(btn.text, "RIGHT")[2] == -(10 + 12 + 10), "the field drops it with the pick")
    local plain = ui:CreateDropdown(parent, "Other", { { value = 1, label = "A" } }, function() return 1 end, function() end)
    plain.button._bottom = 500
    btn:Click()
    plain.button:Click()
    ok(p.rows[1].suffix:GetText() == "", "a reused row gives its suffix back")
end)

case("a tooltip in a main window opens over its own control, not over the body", function()
    local env, _, ui = setup()
    local f = ui:CreateWindow(fullSpec({}))
    f.body._center = { 830, 400 }
    local back = ui:CreateIconButton(f.body, "chevron-left", 32)
    back._center = { 312, 690 }
    ui:AttachTooltip(back, "Back")
    env.fire(back, "OnEnter")
    local p = env.tooltip._points[1]
    ok(p and p[1] == "BOTTOM" and p[2] == back and p[4] == 0, "centered on the button: " .. tostring(p and p[4]))
    f.sidebar._center = { 140, 400 }
    local side = ui:CreateIconButton(f.sidebar, "search", 32)
    side._center = { 30, 690 }
    ui:AttachTooltip(side, "Find")
    env.fire(side, "OnEnter")
    p = env.tooltip._points[1]
    ok(p and p[2] == side and p[4] == 0, "and in the sidebar too: " .. tostring(p and p[4]))
end)

case("ShowTooltip draws a host's own tooltip over its owner, and HideTooltip takes it down", function()
    local env, _, ui = setup()
    local f = ui:CreateWindow(fullSpec({}))
    f.body._center = { 830, 400 }
    local row = env.CreateFrame("Button", nil, f.body)
    row._center = { 400, 600 }
    ui:ShowTooltip(row, "|cffffd100Testing the Wells|r", "Completed 3 days ago")
    local t = env.tooltip
    ok(t._shown and t._lines[1].text == "Testing the Wells" and t._lines[2].text == "Completed 3 days ago",
       "the title without its color escape, then the body")
    ok(t._lines[1].color[4] == 1 and t._lines[1].wrap == true, "the title drawn opaque and wrapped, as every library title")
    local p = t._points[1]
    ok(p and p[1] == "BOTTOM" and p[2] == row and p[4] == 0, "over its own row in a main window: " .. tostring(p and p[4]))
    ui:ShowTooltip(row, "The Deadmines")
    ok(#t._lines == 1 and t._lines[1].text == "The Deadmines", "the next use replaces the last one's lines")
    ui:HideTooltip()
    ok(not t._shown, "HideTooltip hides it")
    ui:ShowTooltip(row, nil, nil)
    ui:ShowTooltip(nil, "Nothing to hang it on")
    ok(not t._shown, "no text, or no owner, shows nothing")
    ui:ShowTooltip(row, "", "Only a body")
    ok(t._shown and #t._lines == 1 and t._lines[1].text == "Only a body", "an empty title leaves the body alone")
end)

case("ShowTooltip on a settings column centers over the column, as AttachTooltip does", function()
    local env, _, ui = setup()
    local column = env.CreateFrame("Frame", nil, env.UIParent)
    column._euiColumn = true
    column._center = { 700, 400 }
    local box = env.CreateFrame("Button", nil, column)
    box._center = { 500, 600 }
    ui:ShowTooltip(box, "Show quest pins")
    local p = env.tooltip._points[1]
    ok(p and p[2] == box and p[4] == 200, "offset to the column's center: " .. tostring(p and p[4]))
end)

case("the stats icon ships beside the other sidebar icons", function()
    local fh = io.open(root .. "/Media/Textures/icon-stats.tga", "rb")
    local bytes = fh and fh:read("*a")
    if fh then fh:close() end
    ok(bytes and #bytes >= 18 + 16 * 16 * 4 and bytes:byte(13) == 16 and bytes:byte(15) == 16
       and bytes:byte(3) == 2 and bytes:byte(17) == 32,
       "a 16 px uncompressed 32-bit texture")
    local _, _, ui = setup()
    ok(ui:Texture("icon-stats") == TEXTURES .. "icon-stats", "and resolves inside the media path")
end)

case("a window larger than the screen at its scale is cut to fit, and the host keeps its size", function()
    local _, _, ui = setup()
    local state = { w = 1100, h = 720 }
    local f = ui:CreateWindow(fullSpec(state))
    f._scale = 1.5
    f:Show()
    ok(near(f._w, 1366 / 1.5) and near(f._h, 768 / 1.5), "cut to the screen in its own units: " .. f._w .. "x" .. f._h)
    ok(state.w == 1100 and state.h == 720 and state.sized == nil and state.resized == nil, "the host's size untouched")
    f._scale = 1
    f:Refit()
    ok(f._w == 1100 and f._h == 720, "a lower scale gives back the size the host keeps")
    f._scale = 1.1
    f:Refit()
    ok(f._w == 1100 and near(f._h, 768 / 1.1), "a window too tall but not too wide loses height only: "
       .. f._w .. "x" .. f._h)
    f._scale = 2
    f:Refit()
    ok(f._w == 760 and f._h == 460, "never below the minimum")
    f._scale = 1.5
    f:Hide()
    f:Show()
    f:SetMaximized(true)
    f:SetMaximized(false)
    ok(near(f._w, 1366 / 1.5) and near(f._h, 768 / 1.5), "and a restore lands on the fitted size")
    local plain = ui:CreateWindow({ title = "What's New", minWidth = 700, minHeight = 400 })
    plain._scale = 1.5
    plain:Show()
    ok(near(plain._w, 1366 / 1.5) and near(plain._h, 768 / 1.5), "a window with no saved size is cut from the size it has")
    plain:Hide()
    plain._w, plain._h = 800, 500
    plain:Show()
    ok(plain._w == 800 and plain._h == 500, "and keeps a size that fits, with nothing saved to go back to")
    local _, _, blind = setup({ uiWidth = 0, uiHeight = 0 })
    local g = blind:CreateWindow(fullSpec({ w = 1100, h = 720 }))
    g._scale = 1.5
    g:Show()
    ok(g._w == 1100 and g._h == 720, "a screen with no size yet leaves the window alone")
end)

case("asking a window never maximized to restore leaves it where it stands", function()
    local env, _, ui = setup()
    local state = { w = 900, h = 600 }
    local f = ui:CreateWindow(fullSpec(state))
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 40, -50)
    f:SetMaximized(false)
    local tl = point(f, "TOPLEFT")
    ok(tl[4] == 40 and tl[5] == -50 and #f._points == 1, "not moved")
    ok(state.maxSet == nil and state.resized == nil, "and the host hears nothing")
end)

case("a range of less than one unit is no range", function()
    local env, _, ui = setup()
    local a = scrolled(ui, env, { pan = true }, 0.4, 0.7)
    ok(not a.vbar:IsShown() and not a.hbar:IsShown(), "no bars for a fraction of a unit")
    local _, vmax = a.vbar:GetMinMaxValues()
    ok(vmax == 0, "and no range on the bar")
    env.mouseDown = "LeftButton"
    env.fire(a.content, "OnMouseDown", "LeftButton")
    ok(a.content:GetScript("OnUpdate") == nil, "and no pan")
    local b = scrolled(ui, env, nil, 0, 1.6)
    local _, bmax = b.vbar:GetMinMaxValues()
    ok(b.vbar:IsShown() and bmax == 1, "a unit or more still scrolls, in whole units")
    local wide = scrolled(ui, env, { pan = true }, 600, 0)
    env.fire(wide.content, "OnMouseDown", "LeftButton")
    ok(wide.content:GetScript("OnUpdate") ~= nil, "a sideways range alone still pans")
end)

case("ScrollToRow reads the range again after the rows grew, and waits for a height", function()
    local env, _, ui = setup()
    local l = listIn(ui, env)
    l:SetRows({ { text = "a" }, { text = "b" } })
    local rows = {}
    for i = 1, 30 do rows[i] = { text = "Chain " .. i } end
    l:SetRows(rows)
    l.scroll._h = 280
    l.scroll.UpdateScrollChildRect = function(s) s._vrange = math.max(0, l.content._h - s._h) end
    ok(l:ScrollToRow(30) == true, "it answers that it scrolled")
    ok(l.bar:GetValue() == 30 * 28 - 280, "to the last row, though the bar still held the short list's range: "
       .. l.bar:GetValue())
    l.scroll._h = 0
    ok(l:ScrollToRow(1) == false and l.bar:GetValue() == 30 * 28 - 280, "a list with no height yet answers false")
    l.scroll._h = 280
    l.scroll.UpdateScrollChildRect = function(s) s._vrange = 37.5 end
    l:ScrollToRow(1)
    ok(select(2, l.bar:GetMinMaxValues()) == 37, "a fractional range is floored, as the bar's own is")
end)

case("a list's rows stay clear of the bar as it comes and goes", function()
    local env, _, ui = setup()
    local l = listIn(ui, env)
    l:SetRows({ { text = "a" } })
    ok(l.content._w == 279, "the whole width with no bar")
    l.bar:Show()
    ok(l.content._w == 279 - 12, "narrower the moment the bar shows")
    l.bar:Hide()
    ok(l.content._w == 279, "and wide again once it goes")
    l:Hide()
    l.content._w = 5
    l:Show()
    ok(l.content._w == 279, "and read again when the list shows")
end)

case("a press on the grip without a drag saves nothing", function()
    local env, _, ui = setup()
    local state = { w = 1100, h = 720 }
    local f = ui:CreateWindow(fullSpec(state))
    f._scale = 1.5
    f:Show()
    env.fire(f.grip, "OnMouseDown", "LeftButton")
    env.fire(f.grip, "OnMouseUp", "LeftButton")
    ok(state.sized == nil and state.resized == nil, "the cut size is not saved")
    f._scale = 1
    f:Refit()
    ok(f._w == 1100 and f._h == 720, "so a lower scale still gives the size back")
    local m = { w = 900, h = 600, max = true }
    local g = ui:CreateWindow(fullSpec(m))
    env.fire(g.grip, "OnMouseDown", "LeftButton")
    env.fire(g.grip, "OnMouseUp", "LeftButton")
    ok(m.w == 900 and m.h == 600 and m.sized == nil, "nor is a maximized window's full size")
    ok(g:IsMaximized() and m.maxSet == nil and m.resized == nil, "and a maximized window stays maximized")
    f._scale = 1.5
    f:Refit()
    env.fire(f.grip, "OnMouseDown", "LeftButton")
    f._w = f._w + 1
    env.fire(f.grip, "OnMouseUp", "LeftButton")
    ok(state.sized == nil and near(f._w, 1366 / 1.5), "a press that moves a unit is still a click, put back")
    env.fire(g.grip, "OnMouseDown", "LeftButton")
    g._h = g._h - 2
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 30, -30)
    env.fire(g.grip, "OnMouseUp", "LeftButton")
    ok(g:IsMaximized() and near(g._h, 768 - 60), "on a maximized window too")
    ok(point(g, "CENTER")[2] == env.UIParent and #g._points == 1, "centered again, wherever sizing left its anchor")
    env.fire(f.grip, "OnMouseDown", "LeftButton")
    f._h = f._h - 40
    env.fire(f.grip, "OnMouseUp", "LeftButton")
    ok(state.sized == 1 and near(state.h, 768 / 1.5 - 40), "a drag that only changes the height is a drag")
    env.fire(f.grip, "OnMouseDown", "LeftButton")
    f._w = f._w - 40
    env.fire(f.grip, "OnMouseUp", "LeftButton")
    ok(state.sized == 2 and near(state.w, 1366 / 1.5 - 40), "and one that only changes the width")
    env.fire(f.grip, "OnMouseDown", "LeftButton")
    f._w = f._w - 5
    env.fire(f.grip, "OnMouseUp", "LeftButton")
    ok(state.sized == 3, "five units is a drag")
    local plain = ui:CreateWindow({ title = "What's New", minWidth = 700, minHeight = 400 })
    plain._w, plain._h = 900, 600
    env.fire(plain.grip, "OnMouseDown", "LeftButton")
    plain._w = plain._w + 3
    env.fire(plain.grip, "OnMouseUp", "LeftButton")
    ok(plain._w == 900 and plain._h == 600, "a click on a window with no saved size puts the nudge back")
end)

case("the grip answers the left button alone, one press at a time", function()
    local env, _, ui = setup()
    local state = { w = 900, h = 600, max = true }
    local f = ui:CreateWindow(fullSpec(state))
    env.fire(f.grip, "OnMouseDown", "RightButton")
    ok(f._sizing == nil, "a right press does not start sizing")
    env.fire(f.grip, "OnMouseUp", "LeftButton")
    ok(f:IsMaximized() and state.sized == nil, "a release with no press of its own does nothing")
    env.fire(f.grip, "OnMouseDown", "LeftButton")
    f._w, f._h = 1000, 650
    env.fire(f.grip, "OnMouseDown", "RightButton")
    env.fire(f.grip, "OnMouseUp", "RightButton")
    ok(f:IsMaximized() and f._w == 1000 and state.sized == nil, "a right press and release in the middle of a drag change nothing")
    env.fire(f.grip, "OnMouseUp", "LeftButton")
    ok(not f:IsMaximized() and state.w == 1000 and state.h == 650 and state.sized == 1, "and the drag lands")
    f._w = 800
    env.fire(f.grip, "OnMouseUp", "LeftButton")
    ok(state.sized == 1, "a second release does not reuse the finished press")
    env.fire(f.grip, "OnMouseDown", "MiddleButton")
    ok(f._sizing == nil, "nor does a middle press start sizing")
    env.fire(f.grip, "OnMouseDown", "LeftButton")
    f._w = 700
    env.fire(f.grip, "OnMouseUp", "MiddleButton")
    ok(state.sized == 1, "and a middle release does not end a drag")
    f._w = 800
    env.fire(f.grip, "OnMouseUp", "LeftButton")
    f._w = 760
    env.fire(f.grip, "OnMouseUp", "LeftButton")
    ok(state.sized == 1 and f._w == 760, "a click's press is not reused either")
end)

local function pages()
    return {
        { id = "quests", title = "Quests", icon = TEXTURES .. "icon-history" },
        { id = "timeline", title = "Chain Timeline", icon = TEXTURES .. "icon-chain" },
        { id = "stats", title = "Stats" },
    }
end

case("CreateNav checks its pages and points an error at the caller", function()
    local env, _, ui = setup()
    local side = env.CreateFrame("Frame", nil, env.UIParent)
    side._w = 196
    ok(raises(function() ui:CreateNav(side, {}) end, "needs a list of pages"), "no pages is refused")
    ok(raises(function() ui:CreateNav(side, { { id = "a" } }) end, "page 1 needs an id and a title"), "a page with no title")
    ok(raises(function() ui:CreateNav(side, { { id = "a", title = "A", badge = 2 } }) end, "unknown field badge"),
       "an unknown field")
    ok(raises(function() ui:CreateNav(side, { { id = "a", title = "A", icon = 3 } }) end, "unknown field icon"),
       "a field of the wrong type")
    ok(raises(function() ui:CreateNav(side, pages(), "go") end, "onSelect must be a function"), "a bad onSelect")
    local good, err = pcall(function() ui:CreateNav(side, {}) end)
    ok(not good and tostring(err):find("test_main.lua", 1, true), "the error names the caller's line: " .. tostring(err))
end)

case("CreateNav draws the settings window's nav items and marks a click", function()
    local env, _, ui = setup()
    local side = env.CreateFrame("Frame", nil, env.UIParent)
    side._w = 196
    local picked = {}
    local nav = ui:CreateNav(side, pages(), function(id) picked[#picked + 1] = id end)
    ok(point(nav, "TOPLEFT")[2] == 8 and point(nav, "TOPLEFT")[3] == -12 and point(nav, "TOPRIGHT")[2] == -8
       and point(nav, "TOPRIGHT")[3] == -12, "inset 8 from the sides and 12 from the top, as the settings sidebar is")
    ok(nav._h == 3 * 36 + 2 * 2, "as tall as its items and the gaps between them: " .. tostring(nav._h))
    local q, t, s = nav.items.quests, nav.items.timeline, nav.items.stats
    ok(q.label:GetText() == "Quests" and t.label:GetText() == "Chain Timeline" and s.label:GetText() == "Stats",
       "one item per page, titled")
    ok(q.icon and q.icon:GetTexture() == TEXTURES .. "icon-history" and s.icon == nil, "an icon only where a page has one")
    ok(q._h == 36 and q._w == 196 - 16, "36 tall, the sidebar less its padding")
    ok(point(t, "TOPLEFT")[2] == q and point(t, "TOPLEFT")[5] == -2 and point(t, "TOPRIGHT")[2] == q,
       "items stack with a 2 px gap, each as wide as the nav")
    ok(t.label._wrap == true and t.label._maxLines == 2, "a long title wraps, at most twice")
    ok(not q.active:IsShown() and not t.active:IsShown(), "nothing is marked before a page is picked")
    local nr, ng, nb = ui:Color("navText")
    ok(sameColor(q.label._textColor, nr, ng, nb) and q.label._font[1]:find("Medium", 1, true)
       and sameColor(q.icon._vertex, nr, ng, nb), "an unmarked item is navText Medium, its icon navText")
    t:Click()
    ok(picked[1] == "timeline" and #picked == 1, "a click calls onSelect with its page")
    ok(t.active:IsShown() and not q.active:IsShown() and nav:GetSelected() == "timeline", "and marks it alone")
    local tr, tg, tb = ui:Color("text")
    local hr, hg, hb = ui:Color("accentHi")
    ok(sameColor(t.label._textColor, tr, tg, tb) and t.label._font[1]:find("SemiBold", 1, true)
       and sameColor(t.icon._vertex, hr, hg, hb), "the marked item is text SemiBold with its icon in accentHi")
    nav:Select("quests")
    ok(#picked == 1 and q.active:IsShown() and not t.active:IsShown() and nav:GetSelected() == "quests",
       "Select marks a page without calling onSelect")
    ok(raises(function() nav:Select("gone") end, "has no page gone"), "Select refuses an unknown page")
    local quiet = ui:CreateNav(side, pages())
    local good = pcall(function() quiet.items.stats:Click() end)
    ok(good and quiet:GetSelected() == "stats", "a nav with no onSelect still marks a click")
end)

case("CreateMultilineField holds many lines in the client's font", function()
    local env, _, ui = setup()
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    ok(raises(function() ui:CreateMultilineField(parent, "read") end, "opts must be a table"), "opts must be a table")
    ok(raises(function() ui:CreateMultilineField(parent, { wrap = true }) end, "unknown field wrap"), "an unknown field")
    ok(raises(function() ui:CreateMultilineField(parent, { readOnly = 1 }) end, "unknown field readOnly"), "a field of the wrong type")
    local m = ui:CreateMultilineField(parent)
    local box = m.box
    ok(box._type == "EditBox" and box:IsMultiLine() and box._autoFocus == false, "a multi-line box that never grabs the keyboard")
    ok(box._fontObject == env.GameFontHighlight, "in the client's font object, so any alphabet draws")
    ok(m.scroll:GetScrollChild() == box and box:GetParent() == m.scroll, "scrolled by its own frame")
    ok(m._euiFill == true, "fills the width it is given")
    local fill = layer(m, "BACKGROUND")[1]
    ok(fill and sameColor(fill._color, ui:Color("input")), "an input fill")
    local edge = layer(m, "BORDER")
    ok(#edge == 4 and sameColor(edge[1]._color, ui:Color("inputBorder")), "with an inputBorder edge")
    m.scroll:_fire("OnSizeChanged", 480, 300)
    ok(box._w == 480, "the box takes the scroll frame's width, so its lines wrap there")
    m.scroll:_fire("OnScrollRangeChanged", 0, 200)
    m.bar:SetValue(120)
    m:SetText("line one\nline two")
    ok(m:GetText() == "line one\nline two" and m.bar:GetValue() == 0, "SetText shows the text from the top")
    box._text = "line one\nline two!"
    box:_fire("OnTextChanged", true)
    ok(m:GetText() == "line one\nline two!", "an editable box keeps what is typed")
    box:SetFocus()
    box:_fire("OnEditFocusGained")
    ok(sameColor(edge[1]._color, ui:Color("borderStrong")), "focus brightens the edge")
    box:_fire("OnEscapePressed")
    box:_fire("OnEditFocusLost")
    ok(not box:HasFocus() and sameColor(edge[1]._color, ui:Color("inputBorder")), "Escape lets the keyboard go")
    m:_fire("OnMouseDown", "LeftButton")
    ok(box:HasFocus(), "a click anywhere on the box takes the keyboard")
end)

case("a read-only CreateMultilineField can be selected but not changed", function()
    local env, _, ui = setup()
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local m = ui:CreateMultilineField(parent, { readOnly = true })
    local box = m.box
    m:SetText("# Quest History - 3 entries")
    box._text = "# Quest History - 3 entriesx"
    box:_fire("OnTextChanged", true)
    ok(m:GetText() == "# Quest History - 3 entries" and box._highlight == true,
       "a keystroke is undone, and the text left selected for copying")
    box._highlight = false
    box._text = "set by code"
    box:_fire("OnTextChanged", false)
    ok(m:GetText() == "set by code" and box._highlight == false, "text the code puts in is not undone")
    m:SetText("new text")
    ok(m:GetText() == "new text", "SetText still replaces it")
    m:SelectAll()
    ok(box:HasFocus() and box._highlight == true, "SelectAll takes the keyboard and then selects, so the selection holds")
end)

case("CreateMultilineField keeps the cursor in view", function()
    local env, _, ui = setup()
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local m = ui:CreateMultilineField(parent)
    m.scroll._h = 100
    m.scroll._vrange = 400
    m.scroll:_fire("OnScrollRangeChanged", 0, 400)
    m.box:_fire("OnCursorChanged", 0, -150, 2, 14)
    ok(m.bar:GetValue() == 150 + 14 - 100, "a cursor below the view scrolls it down to show the line: " .. m.bar:GetValue())
    m.scroll:SetVerticalScroll(m.bar:GetValue())
    m.box:_fire("OnCursorChanged", 0, -100, 2, 14)
    ok(m.bar:GetValue() == 64, "a cursor already in view leaves it")
    m.box:_fire("OnCursorChanged", 0, -20, 2, 14)
    ok(m.bar:GetValue() == 20, "a cursor above the view scrolls it up to the line")
end)

case("CreateMultilineField reads its range afresh when the cursor moves past the old end", function()
    local env, _, ui = setup()
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local m = ui:CreateMultilineField(parent)
    m.scroll._h = 100
    m.scroll._vrange = 0
    m.scroll.UpdateScrollChildRect = function(s) s._vrange = 14.5 end
    m.box:_fire("OnCursorChanged", 0, -100, 2, 14)
    ok(m.bar:GetValue() == 14 and select(2, m.bar:GetMinMaxValues()) == 14,
       "a new last line scrolls into view before the range event, floored: " .. m.bar:GetValue())
end)

case("CreateMultilineField's SetText takes the box's width and puts the cursor at the top", function()
    local env, _, ui = setup()
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local m = ui:CreateMultilineField(parent, { readOnly = true })
    m.scroll._w = 480
    m.box._cursor = 99
    m:SetText("line one\nline two")
    ok(m.box._w == 480 and m.box._cursor == 0, "sized to the view and the cursor at the start: "
       .. tostring(m.box._w) .. "/" .. tostring(m.box._cursor))
    m.scroll._w = 0
    m.box._w = 300
    m:SetText("again")
    ok(m.box._w == 300, "an unmeasured view leaves the width alone")
    m.box._cursor = 7
    m.box._text = "againx"
    m.box:_fire("OnTextChanged", true)
    ok(m.box._cursor == 0 and m:GetText() == "again", "an undone keystroke puts the cursor back at the top")
end)

case("CreateNav refuses two pages with one id", function()
    local env, _, ui = setup()
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local good, err = raises(function()
        ui:CreateNav(parent, { { id = "a", title = "A" }, { id = "a", title = "Again" } })
    end, "repeats the id a")
    ok(good and tostring(err):find("test_main.lua", 1, true) ~= nil, "raised at the caller: " .. tostring(err))
end)

case("an empty title with no body shows no tooltip", function()
    local env, _, ui = setup()
    local f = ui:CreateWindow(fullSpec({}))
    local b = env.CreateFrame("Button", nil, f.body)
    env.tooltip._shown = false
    ui:ShowTooltip(b, "", nil)
    ui:ShowTooltip(b, "", "")
    ok(not env.tooltip._shown, "ShowTooltip shows nothing")
    ui:AttachTooltip(b, "", "")
    env.fire(b, "OnEnter")
    ok(not env.tooltip._shown, "AttachTooltip shows nothing")
end)

case("a main window comes to the front when clicked, and a dropdown list opens above it", function()
    local _, lib, ui = setup()
    local f = ui:CreateWindow(fullSpec({}))
    ok(f._toplevel == true, "the window is toplevel")
    local dd = ui:CreateDropdown(f.body, nil, { { value = 1, label = "A" } }, function() return 1 end, function() end)
    dd.button._bottom = 500
    dd.button:Click()
    ok((lib.shared.popup._raised or 0) == 1, "the list is raised as it opens")
    ok(lib.shared.popup.closer._strata == "FULLSCREEN", "its click catcher sits over a window in the DIALOG strata")
    lib.shared.popup:Hide()
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    local order = {}
    local closer, p = lib.shared.popup.closer, lib.shared.popup
    local cRaise, pRaise = closer.Raise, p.Raise
    closer.Raise = function(s) order[#order + 1] = "closer" return cRaise(s) end
    p.Raise = function(s) order[#order + 1] = "list" return pRaise(s) end
    dd.button:Click()
    ok(closer._strata == "FULLSCREEN_DIALOG" and closer:IsShown(), "over a window raised above the world map, the catcher follows it")
    ok(table.concat(order, ",") == "closer,list", "the catcher is raised over the window and the list over the catcher: " .. table.concat(order, ","))
end)

case("a tooltip title made only of color codes counts as none", function()
    local env, _, ui = setup()
    local f = ui:CreateWindow(fullSpec({}))
    local b = env.CreateFrame("Button", nil, f.body)
    env.tooltip._shown = false
    ui:ShowTooltip(b, "|cffff0000|r", nil)
    ok(not env.tooltip._shown, "ShowTooltip shows nothing")
    ui:AttachTooltip(b, "|cffff0000|r", nil)
    env.fire(b, "OnEnter")
    ok(not env.tooltip._shown, "AttachTooltip shows nothing")
end)

case("a main window shown in combat takes Escape once combat ends", function()
    local env, _, ui = setup()
    local f = ui:CreateWindow(fullSpec({}))
    env.combat = true
    f:Show()
    local wait = f._euiEscapeWait
    ok(f._keyboard == false and wait._events.PLAYER_REGEN_ENABLED, "in combat it waits")
    env.combat = false
    env.fire(wait, "OnEvent", "PLAYER_REGEN_ENABLED")
    ok(f._keyboard == true and not wait._events.PLAYER_REGEN_ENABLED, "and takes the keyboard once combat ends")
    env.combat = true
    f:Hide()
    f:Show()
    f:Hide()
    ok(not wait._events.PLAYER_REGEN_ENABLED and f._keyboard == false, "hidden before combat ends, it stops waiting")
end)

case("NeedsClientFont answers as the library's own font rule", function()
    local _, _, ui = setup()
    ok(ui:NeedsClientFont(CYRILLIC) == true and ui:NeedsClientFont("Quest") == false
       and ui:NeedsClientFont("Caf\195\169") == false, "Cyrillic yes, plain and accented Latin no")
end)

print(("test_main: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end

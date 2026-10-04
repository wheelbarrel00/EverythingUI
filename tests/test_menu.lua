-- Run with Lua 5.1 from any folder: lua5.1 tests/test_menu.lua

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

local function setup()
    local env = W.newEnv()
    env.cursorX, env.cursorY = 400, 300
    env.GetCursorPosition = function() return env.cursorX, env.cursorY end
    local lib = W.loadLibrary(root, env, "HostA", W.newLibStub())
    local function ctx(accent)
        return lib:NewContext({
            id = "EQOT", title = "EQ Objective Tracker", version = "1.28.0",
            accent = accent or { 0.784, 0.216, 0.243 }, L = {},
            tooltip = function() return env.tooltip end,
        })
    end
    return env, lib, ctx(), ctx
end

-- The shape EQOT's row menu hands over: the quest's name, its actions, a divider, a danger item,
-- then the trailing divider and Cancel.
local function questMenu(log)
    log = log or {}
    return {
        { kind = "title", text = "The Fall of the Lich King" },
        { text = "Pin to tracker", onClick = function() log[#log + 1] = "pin" end },
        { text = "Untrack Quest", onClick = function() log[#log + 1] = "untrack" end },
        { kind = "divider" },
        { text = "Abandon Quest", danger = true, onClick = function() log[#log + 1] = "abandon" end },
        { kind = "divider" },
        { text = "Cancel" },
    }
end

local function shown(fs) return fs:IsShown() and fs or nil end

case("the menu is built when first shown, never as the files load", function()
    local env, lib, ui = setup()
    ok(#env.created == 0 and lib.shared.menu == nil, "nothing built by loading")
    ui:ShowMenu(questMenu())
    local m = lib.shared.menu
    ok(m and m:IsShown() and m._parent == env.UIParent, "a frame on UIParent, shown")
    ok(m._name == nil, "unnamed, so nothing can read it out of _G")
    ok(m._strata == "FULLSCREEN_DIALOG", "above the settings window's DIALOG strata")
    ok(m._clamped == true, "clamped to the screen")
    ok(m._mouse == true, "taking the mouse, so a click on its padding stops on it")
    ok(m._raised == 1, "raised over anything at its strata")
    local n = #env.created
    ui:ShowMenu(questMenu())
    ok(#env.created == n, "built once, its rows reused")
end)

case("one menu serves every addon", function()
    local _, lib, ui, newCtx = setup()
    local other = newCtx({ 0.165, 0.447, 0.682 })
    ui:ShowMenu(questMenu())
    local m = lib.shared.menu
    other:ShowMenu({ { text = "Get Directions" } })
    ok(lib.shared.menu == m, "the second addon opens the same frame")
    ok(m:IsShown() and m.rows[1].text:GetText() == "Get Directions" and m.count == 1,
       "showing its own items in place of the first addon's")
    ok(not m.rows[2]:IsShown(), "with the first addon's other rows put away")
    ui:ShowMenu(questMenu())
    ok(m.rows[2]:IsShown() and m.rows[7]:IsShown() and m.count == 7, "and a longer menu brings them back")
end)

case("it opens at the cursor, at UIParent's scale whatever was clicked", function()
    local env, lib, ui = setup()
    env.UIParent._scale = 0.8
    env.cursorX, env.cursorY = 500, 300
    ui:ShowMenu(questMenu())
    local m = lib.shared.menu
    local p = point(m, "TOPLEFT")
    ok(#m._points == 1 and p[2] == env.UIParent and p[3] == "BOTTOMLEFT",
       "its top left pinned to UIParent's bottom left, one point")
    ok(near(p[4], 625) and near(p[5], 375), "at the cursor in UIParent's units: " .. tostring(p[4]) .. ", " .. tostring(p[5]))
    ok(m._scale == nil, "never scaled, so it keeps UIParent's scale")
    env.cursorX, env.cursorY = 80, 40
    ui:ShowMenu(questMenu())
    p = point(m, "TOPLEFT")
    ok(#m._points == 1 and near(p[4], 100) and near(p[5], 50), "and moves to the cursor on the next open")
end)

case("the look: a surface panel, 24 px items, a muted title, red danger, divider lines", function()
    local _, lib, ui = setup()
    ui:ShowMenu(questMenu())
    local m = lib.shared.menu
    local fill, edges = nil, 0
    for _, r in ipairs({ m:GetRegions() }) do
        if r._layer == "BACKGROUND" and r._color then fill = r end
        if r._euiAxis and sameColor(r._color, ui:Color("surfaceBorder")) then edges = edges + 1 end
    end
    ok(fill and sameColor(fill._color, ui:Color("surface")), "on the surface fill")
    ok(edges == 4, "with a surfaceBorder edge all round")

    local title, pin, div, abandon, cancel = m.rows[1], m.rows[2], m.rows[4], m.rows[5], m.rows[7]
    ok(title._h == 24 and pin._h == 24 and cancel._h == 24, "items and the title 24 tall")
    ok(title.text:GetText() == "The Fall of the Lich King" and title.text._font[2] == 12
       and title.text._font[1]:find("SemiBold", 1, true) and sameColor(title.text._textColor, ui:Color("muted")),
       "the title in 12 SemiBold muted, the group-label style")
    ok(pin.text:GetText() == "Pin to tracker" and pin.text._font[2] == 13
       and pin.text._font[1]:find("Regular", 1, true) and sameColor(pin.text._textColor, ui:Color("text")),
       "an item in 13 Regular text")
    ok(sameColor(abandon.text._textColor, 1, 0.314, 0.314) and sameColor(abandon.text._textColor, ui:Color("danger")),
       "a danger item in the danger red, ff5050")
    ok(sameColor(cancel.text._textColor, ui:Color("text")), "and Cancel in plain text")
    ok(div._h == 9 and div.line:IsShown() and sameColor(div.line._color, ui:Color("divider")),
       "a divider is a divider-colored line in a 9 px slot")
    ok(not div.text:IsShown() and not div.data:IsShown(), "with no text")
    ok(point(div.line, "LEFT")[1] == "LEFT" and point(div.line, "RIGHT")[1] == "RIGHT",
       "the line runs the width of the row")
    ok(not pin.line:IsShown() and not title.line:IsShown(), "and no line on the other rows")
    local hl
    for _, r in ipairs({ pin:GetRegions() }) do if r._layer == "HIGHLIGHT" then hl = r end end
    ok(hl and sameColor(hl._color, ui:Color("hover")) and near(hl._color[4], 0.06), "items take the hover tint")
    ok(point(pin.text, "LEFT")[2] == 12 and point(pin.text, "RIGHT")[2] == -12, "text 12 in from each side")
    ok(pin.text._wrap == false and title.text._wrap == false, "on one line, so a long title is cut, not wrapped")
end)

case("rows stack inside the edge, and the menu is as tall as they are", function()
    local _, lib, ui = setup()
    ui:ShowMenu(questMenu())
    local m = lib.shared.menu
    local y = 4
    for i = 1, 7 do
        local b = m.rows[i]
        local tl, tr = point(b, "TOPLEFT"), point(b, "TOPRIGHT")
        ok(tl[2] == m and tl[4] == 1 and tl[5] == -y and tr[4] == -1 and tr[5] == -y,
           "row " .. i .. " one pixel inside the edge, at " .. y)
        y = y + b._h
    end
    ok(m._h == 4 + 24 * 5 + 9 * 2 + 4, "4 above, the rows, 4 below: " .. tostring(m._h))
end)

case("the width fits the widest row, from 160 to 320", function()
    local _, lib, ui = setup()
    ui:ShowMenu({ { text = "OK" } })
    local m = lib.shared.menu
    ok(m._w == 160, "a short menu is 160: " .. tostring(m._w))
    m.rows[1].text._measure = nil
    ui:ShowMenu({ { kind = "title", text = string.rep("x", 30) }, { kind = "divider" }, { text = "Go" } })
    ok(m._w == 30 * 6 + 24 + 2, "the widest row plus 12 a side and the edge: " .. tostring(m._w))
    ui:ShowMenu({ { text = "Go" }, { text = string.rep("y", 100) } })
    ok(m._w == 320, "a very long one stops at 320: " .. tostring(m._w))
    ui:ShowMenu({ { text = string.rep("z", 40) }, { text = "Go" } })
    ui:ShowMenu({ { kind = "divider" }, { text = "OK" } })
    ok(m._w == 160, "a divider is not measured, even on a row that last held a long item: " .. tostring(m._w))
end)

case("a click runs the action with the menu still up, then closes it", function()
    local _, lib, ui = setup()
    local during
    ui:ShowMenu({ { text = "Pin to tracker", onClick = function() during = lib.shared.menu:IsShown() end } })
    lib.shared.menu.rows[1]:Click()
    ok(during == true, "the action runs first, as Blizzard's menu runs its own")
    ok(not lib.shared.menu:IsShown(), "then the menu closes")
    local log = {}
    ui:ShowMenu(questMenu(log))
    lib.shared.menu.rows[5]:Click()
    ok(log[1] == "abandon" and #log == 1, "the row clicked runs its own action and no other")
end)

case("an item with no action only closes the menu", function()
    local env, lib, ui = setup()
    ui:ShowMenu(questMenu())
    lib.shared.menu.rows[7]:Click()
    ok(not lib.shared.menu:IsShown() and #env.errors == 0, "Cancel closes it, with nothing raised")
end)

case("a raising action still closes the menu and reaches the error handler", function()
    local env, lib, ui = setup()
    ui:ShowMenu({ { text = "Boom", onClick = function() error("boom", 0) end } })
    local good = pcall(lib.shared.menu.rows[1].Click, lib.shared.menu.rows[1])
    ok(good and not lib.shared.menu:IsShown() and env.errors[1] == "boom", "closed, the error handed on")
end)

case("an action that opens the next menu keeps it on screen", function()
    local _, lib, ui = setup()
    ui:ShowMenu({ { text = "More", onClick = function() ui:ShowMenu({ { text = "Next" } }) end } })
    lib.shared.menu.rows[1]:Click()
    ok(lib.shared.menu:IsShown() and lib.shared.menu.rows[1].text:GetText() == "Next", "the next menu stays up")
end)

case("only items take the mouse; a title or a divider is not a button", function()
    local _, lib, ui = setup()
    ui:ShowMenu(questMenu())
    local rows = lib.shared.menu.rows
    ok(rows[1]._mouse == false and rows[4]._mouse == false and rows[6]._mouse == false,
       "the title and the dividers ignore the mouse, so they neither light up nor click")
    ok(rows[2]._mouse == true and rows[5]._mouse == true and rows[7]._mouse == true, "every item takes it")
end)

case("a click anywhere else closes it and still lands where it was aimed", function()
    local env, lib, ui = setup()
    ui:ShowMenu(questMenu())
    local m = lib.shared.menu
    ok(m.closer == nil, "no catcher over the screen, so an action button or quest item still takes the click")
    ok(m._events.GLOBAL_MOUSE_DOWN == true, "it listens for the game's mouse-down while it is open")
    m._mouseOver = true
    env.fire(m, "OnEvent", "GLOBAL_MOUSE_DOWN", "LeftButton")
    ok(m:IsShown(), "a press on the menu itself leaves it open for the row's own click")
    m._mouseOver = false
    env.fire(m, "OnEvent", "GLOBAL_MOUSE_DOWN", "RightButton")
    ok(not m:IsShown(), "a press of any button anywhere else closes it")
    ok(m._events.GLOBAL_MOUSE_DOWN == nil, "and it stops listening once closed")
    ui:ShowMenu(questMenu())
    ok(m._events.GLOBAL_MOUSE_DOWN == true, "listening again on the next open")
    m:Hide()
    ok(m._events.GLOBAL_MOUSE_DOWN == nil, "closed any other way, it stops listening too")
    env.combat = true
    ui:ShowMenu(questMenu())
    ok(m._events.GLOBAL_MOUSE_DOWN == true, "a menu opened in combat listens too")
    m._mouseOver = false
    env.fire(m, "OnEvent", "GLOBAL_MOUSE_DOWN", "LeftButton")
    ok(not m:IsShown(), "and a click elsewhere closes it in combat, where Escape stands down")
    env.combat = false
end)

case("a client without the global mouse event gets a catcher over the screen instead", function()
    local env, lib, ui = setup()
    env.unknownEvents.GLOBAL_MOUSE_DOWN = true
    ui:ShowMenu(questMenu())
    local m = lib.shared.menu
    ok(m._events.GLOBAL_MOUSE_DOWN == nil, "it does not listen for an event the client refused")
    local c = m.closer
    ok(c and c:IsShown() and c._type == "Button", "a closer is up while the menu is")
    ok(c._parent == env.UIParent and #c._points == 2 and point(c, "TOPLEFT")[2] == env.UIParent
       and point(c, "BOTTOMRIGHT")[2] == env.UIParent,
       "covering the whole screen")
    ok(c._strata == "FULLSCREEN", "on the strata under the menu, so the menu's own rows still take clicks")
    ok(c._clicks and c._clicks[1] == "AnyDown", "closing on the press of any button")
    c:Click()
    ok(not m:IsShown() and not c:IsShown(), "a click on it closes the menu, and the closer goes with it")
    ui:ShowMenu(questMenu())
    m:Hide()
    ok(not c:IsShown(), "closed any other way, the closer goes too")
end)

case("Escape closes it, and stands down in combat", function()
    local env, lib, ui = setup()
    ui:ShowMenu(questMenu())
    local m = lib.shared.menu
    ok(m._keyboard == true and m._propagate == true, "open, it takes the keyboard and passes other keys on")
    env.fire(m, "OnKeyDown", "W")
    ok(m:IsShown() and m._propagate == true, "another key goes on to the game")
    env.fire(m, "OnKeyDown", "ESCAPE")
    ok(not m:IsShown() and m._propagate == false, "Escape closes it and is kept from the game")
    ok(m._keyboard == false, "and the keyboard is given back")
    env.combat = true
    ui:ShowMenu(questMenu())
    ok(m._keyboard == false, "opened in combat it leaves the keyboard alone")
    env.fire(m, "OnKeyDown", "ESCAPE")
    ok(m:IsShown(), "and a key in combat makes no protected call")
end)

case("opening it puts the clicked row's tooltip away", function()
    local env, lib, ui = setup()
    env.tooltip:Show()
    ui:ShowMenu(questMenu())
    ok(not env.tooltip:IsShown(), "the host's tooltip is hidden, since it draws above the menu")
    ok(lib.shared.menu:IsShown(), "and the menu is up")
end)

case("a reused row carries nothing from the menu before", function()
    local _, lib, ui = setup()
    local log = {}
    ui:ShowMenu(questMenu(log))
    local m = lib.shared.menu
    ui:ShowMenu({
        { text = "First", onClick = function() log[#log + 1] = "first" end },
        { text = "Second" },
        { kind = "divider" },
        { kind = "title", text = "Heading" },
        { text = "Fifth" },
    })
    local r = m.rows
    ok(r[1]._mouse == true and r[1].text._font[2] == 13 and sameColor(r[1].text._textColor, ui:Color("text")),
       "the old title row is an item again: clickable, 13 Regular, text-colored")
    ok(r[3]._h == 9 and r[3].line:IsShown() and not r[3].text:IsShown() and r[3]._mouse == false,
       "the old item row is a divider")
    ok(r[4]._h == 24 and not r[4].line:IsShown() and shown(r[4].text) and r[4].text:GetText() == "Heading"
       and r[4]._mouse == false and r[4].text._font[2] == 12,
       "the old divider row is a title: full height, no line, its text shown")
    ok(sameColor(r[5].text._textColor, ui:Color("text")) and r[5].text:GetText() == "Fifth",
       "the old danger row is no longer red")
    ok(not r[6]:IsShown() and not r[7]:IsShown(), "rows past the new menu are put away")
    r[2]:Click()
    ok(#log == 0, "a row with no action of its own runs none from before")
    ui:ShowMenu(questMenu(log))
    r[1]:Click()
    ok(#log == 0, "nor does the title row it became")
    ui:ShowMenu({ { text = "First", onClick = function() log[#log + 1] = "first" end } })
    r[1]:Click()
    ok(log[1] == "first", "while an item runs the action it was given this time")
end)

case("text Barlow cannot draw goes to the client's font", function()
    local env, lib, ui = setup()
    local cyrillic = "\208\154\208\178\208\181\209\129\209\130"
    ui:ShowMenu({ { kind = "title", text = cyrillic }, { text = "Pin to tracker" } })
    local m = lib.shared.menu
    local t = m.rows[1]
    ok(t.data:IsShown() and not t.text:IsShown() and t.data:GetText() == cyrillic, "a Cyrillic title on the client-font string")
    ok(t.data._fontObject == env.GameFontHighlight and sameColor(t.data._textColor, ui:Color("muted")),
       "in the client's font object, in the title's color")
    ok(m.rows[2].text:IsShown() and not m.rows[2].data:IsShown(), "a Latin item stays on Barlow")
    t.data._measure = 250
    ui:ShowMenu({ { kind = "title", text = cyrillic }, { text = "Pin to tracker" } })
    ok(m._w == 250 + 24 + 2, "the width is measured off the string that is shown: " .. tostring(m._w))
    ui:ShowMenu({ { text = "Plain" } })
    ok(t.text:IsShown() and not t.data:IsShown(), "and the next Latin label on that row goes back to Barlow")
    ui:ShowMenu({ { kind = "title", text = "Haldir\226\128\153s Watch \226\128\148 Part Two" } })
    ok(t.text:IsShown() and not t.data:IsShown(), "a curly quote and a dash, which Barlow draws, stay in Barlow")
end)

case("text measured before the menu was on screen is sized again a frame later", function()
    local env, lib, ui = setup()
    ui:ShowMenu({ { text = "Pin to tracker" } })
    local m = lib.shared.menu
    m.rows[1].text._measure = 210
    env.runTimers()
    ok(m._w == 210 + 24 + 2, "the width follows the text as drawn: " .. tostring(m._w))
    ui:ShowMenu({ { text = "Pin to tracker" } })
    m:Hide()
    m.rows[1].text._measure = 280
    env.runTimers()
    ok(m._w == 210 + 24 + 2, "a menu closed before the frame passed is left alone: " .. tostring(m._w))
end)

case("the edges are snapped again on every open, at the menu's own scale", function()
    local env, lib, ui = setup()
    ui:ShowMenu(questMenu())
    local m = lib.shared.menu
    ok(m.edges[1]._h == 1 and m.rows[4].line._h == 1, "one pixel at scale 1")
    env.UIParent._scale = 0.5
    ui:ShowMenu(questMenu())
    ok(m.edges[1]._h == 2 and m.edges[3]._w == 2, "the edges re-snapped after the UI scale changed")
    ok(m.rows[4].line._h == 2, "and the divider lines too")
end)

case("a menu given an owner closes once the owner is no longer visible", function()
    local env, lib, ui = setup()
    local owner = env.CreateFrame("Frame", nil, env.UIParent)
    ui:ShowMenu(questMenu(), owner)
    local m = lib.shared.menu
    m:_fire("OnUpdate", 0.01)
    ok(m:IsShown(), "it stays while the owner shows")
    owner:Hide()
    m:_fire("OnUpdate", 0.01)
    ok(not m:IsShown(), "and closes once the owner hides")
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local child = env.CreateFrame("Frame", nil, parent)
    ui:ShowMenu(questMenu(), child)
    parent:Hide()
    m:_fire("OnUpdate", 0.01)
    ok(not m:IsShown(), "an owner hidden with its parent counts as gone")
    ui:ShowMenu(questMenu())
    m:_fire("OnUpdate", 0.01)
    ok(m:IsShown(), "a menu with no owner stays")
    local again = env.CreateFrame("Frame", nil, env.UIParent)
    ui:ShowMenu(questMenu(), again)
    ui:ShowMenu(questMenu())
    again:Hide()
    m:_fire("OnUpdate", 0.01)
    ok(m:IsShown(), "the next open without an owner forgets the last one")
end)

-- A secret cannot be modelled as itself, so this owner answers false and the test calls that answer secret.
case("an owner whose visibility is a secret value is left alone", function()
    local env, lib, ui = setup()
    local owner = env.CreateFrame("Frame", nil, env.UIParent)
    owner.IsVisible = function() return false end
    env.issecretvalue = function(v) return v == false end
    ui:ShowMenu(questMenu(), owner)
    local m = lib.shared.menu
    m:_fire("OnUpdate", 0.01)
    ok(m:IsShown(), "the menu is never closed on an answer it may not read")
    env.issecretvalue = function() return false end
    m:_fire("OnUpdate", 0.01)
    ok(not m:IsShown(), "and once the answer is a plain value, a hidden owner closes it as usual")
end)

case("ShowMenu checks what it is given, and the error names the caller", function()
    local env, _, ui = setup()
    ok(not pcall(ui.ShowMenu, ui, { { text = "Pin" } }, "WorldMapFrame"), "an owner that is not a frame is refused")
    ok(not pcall(ui.ShowMenu, ui, { { text = "Pin" } }, {}), "and so is a table with no IsVisible")
    ok(pcall(ui.ShowMenu, ui, { { text = "Pin" } }, env.CreateFrame("Frame", nil, env.UIParent)), "a frame is an owner")
    local goodO, errO = pcall(function()
        local r = ui:ShowMenu({ { text = "Pin" } }, 5)
        return r
    end)
    ok(not goodO and tostring(errO):find("test_menu.lua", 1, true) ~= nil, "the owner error names the caller: " .. tostring(errO))
    ok(not pcall(ui.ShowMenu, ui, nil), "no list is refused")
    ok(not pcall(ui.ShowMenu, ui, {}), "an empty list is refused")
    local good0, err0 = pcall(ui.ShowMenu, ui, { "Pin" })
    ok(not good0 and tostring(err0):find("not a table", 1, true) ~= nil,
       "an item that is not a table is refused, by name: " .. tostring(err0))
    ok(not pcall(ui.ShowMenu, ui, { { text = "Pin", onclick = function() end } }), "a misspelled field is refused")
    ok(not pcall(ui.ShowMenu, ui, { { text = "Pin", danger = "yes" } }), "a field of the wrong type is refused")
    ok(not pcall(ui.ShowMenu, ui, { { kind = "header", text = "Quest" } }), "an unknown kind is refused")
    ok(not pcall(ui.ShowMenu, ui, { { onClick = function() end } }), "an item with no text is refused")
    ok(not pcall(ui.ShowMenu, ui, { { kind = "title" } }), "and so is a title with none")
    ok(pcall(ui.ShowMenu, ui, { { kind = "divider" }, { text = "" } }), "a divider needs no text, and empty text is text")
    local good, err = pcall(function()
        local r = ui:ShowMenu({ { text = "Pin", danger = 1 } })
        return r
    end)
    ok(not good and tostring(err):find("test_menu.lua", 1, true) ~= nil, "pointing at the caller: " .. tostring(err))
end)

print(("test_menu: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end

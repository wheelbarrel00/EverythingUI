-- Run with Lua 5.1 from any folder: lua5.1 tests/test_window.lua

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

local NIL = {}
local GOLD = { 0.92, 0.72, 0.02 }

local function setup(o)
    o = o or {}
    local env = W.newEnv(o.env)
    local lib = W.loadLibrary(root, env, "HostA", W.newLibStub())
    local state = { lastTab = o.lastTab, scale = o.scale, discord = 0, set = {} }
    local opts = {
        id = "EQOT", title = "EQ Objective Tracker", version = "1.28.0",
        accent = { 0.784, 0.216, 0.243 }, L = {},
        tooltip = function() return env.tooltip end,
        discord = function() state.discord = state.discord + 1 end,
        labels = { discord = "Join our Discord!", discordTipTitle = "Join our Discord",
                   discordTip = "Click to copy the invite link." },
        getLastTab = function() return state.lastTab end,
        setLastTab = function(id) state.lastTab = id end,
        getWindowScale = function() return state.scale end,
        setWindowScale = function(v) state.scale = v state.set[#state.set + 1] = v end,
    }
    for k, v in pairs(o.opts or {}) do
        if v == NIL then opts[k] = nil else opts[k] = v end
    end
    return env, lib, lib:NewContext(opts), state
end

local function addTabs(ui)
    local log = { build = {}, refresh = {}, controls = {}, self = {}, footer = 0 }
    for _, d in ipairs({ { "about", "About", 90 }, { "general", "General", 10 }, { "tracker", "Tracker", 20 } }) do
        local id = d[1]
        ui:RegisterTab({
            id = id, title = d[2], order = d[3], icon = ui:Texture("icon-" .. id),
            build = function(self, content)
                log.build[id] = (log.build[id] or 0) + 1
                log.self[id] = self
                content._controls[#content._controls + 1] = {
                    Refresh = function() log.controls[id] = (log.controls[id] or 0) + 1 end,
                }
            end,
            refresh = function() log.refresh[id] = (log.refresh[id] or 0) + 1 end,
            footer = (id == "tracker") and function(_, bar)
                log.footer = log.footer + 1
                log.footerBar = bar
            end or nil,
        })
    end
    return log
end

local function tab(ui, id)
    for _, t in ipairs(ui._tabs) do if t.id == id then return t end end
end

local function edgeLines(frame)
    local n, colors = 0, {}
    for _, r in ipairs({ frame:GetRegions() }) do
        if r._euiAxis then
            n = n + 1
            colors[#colors + 1] = r._color
        end
    end
    return n, colors
end

local function sameColor(c, r, g, b)
    return c and near(c[1], r) and near(c[2], g) and near(c[3], b)
end

case("RegisterTab checks its fields and keeps the order", function()
    local _, _, ui = setup()
    ok(not pcall(ui.RegisterTab, ui, { id = "x", title = "X" }), "a tab with no build is refused")
    ok(not pcall(ui.RegisterTab, ui, { id = "x", title = "X", build = function() end, sidebar = function() end }),
       "an unknown field is refused")
    ok(not pcall(ui.RegisterTab, ui, { id = "x", title = "X", build = function() end, previewRefresh = function() end }),
       "a previewRefresh with no preview is refused")
    ok(not pcall(ui.RegisterTab, ui, { id = "x", title = "X", build = function() end, order = "10" }),
       "a field of the wrong type is refused")
    addTabs(ui)
    ok(ui._tabs[1].id == "general" and ui._tabs[2].id == "tracker" and ui._tabs[3].id == "about",
       "tabs sort by order, not by registration")
end)

case("the window is built on demand, not when the files load", function()
    local env, _, ui = setup()
    ok(#env.created == 0, "loading the library builds no frame")
    addTabs(ui)
    local f = ui:BuildSettings("EQOTOptionsFrame")
    ok(f._name == "EQOTOptionsFrame", "the host names the window")
    ok(f._w == 1100 and f._h == 720, "1100 x 720")
    ok(f._strata == "DIALOG" and f._clamped == true and f._movable == true, "DIALOG strata, clamped, movable")
    ok(f._toplevel ~= true, "a click never brings it over Blizzard's color picker")
    ok(f._drag and f._drag[1] == "LeftButton", "dragged with the left button")
    ok(f:GetScript("OnDragStart") == f.StartMoving and f:GetScript("OnDragStop") == f.StopMovingOrSizing,
       "a drag moves it and letting go stops it")
    local texts = {}
    local function collect(frame)
        for _, r in ipairs({ frame:GetRegions() }) do if r.GetText then texts[r:GetText() or ""] = true end end
        for _, c in ipairs({ frame:GetChildren() }) do collect(c) end
    end
    collect(f)
    ok(texts["EQ Objective Tracker"] and texts["v1.28.0"], "the header names the addon and its version")
    local general = tab(ui, "general")
    local hp = general._holder._points
    ok(#hp == 2 and hp[1][1] == "TOPLEFT" and hp[2][1] == "BOTTOMRIGHT",
       "each tab's holder fills the content area")
    local function at(frame, name)
        for _, p in ipairs(frame._points) do if p[1] == name then return p end end
        return {}
    end
    local tl, br = at(general._scroll, "TOPLEFT"), at(general._scroll, "BOTTOMRIGHT")
    ok(tl[2] == 24 and tl[3] == -20 and br[2] == -24 and br[3] == 0,
       "its scroll area sits 24 in from each side and 20 from the top")
    ok(not f:IsShown(), "built hidden")
    ok(ui:BuildSettings() == f, "a second build returns the same window")
    ok(tab(ui, "general")._content._w == 1100 - 196 - 48, "the content column is the window less the sidebar and padding")
    ok(tab(ui, "general")._content._euiColumn == true, "marked as a column, so a tooltip centers over it")
end)

case("the sidebar carries one nav item per tab, in order", function()
    local _, _, ui = setup()
    addTabs(ui)
    ui:BuildSettings()
    local navs = {}
    for _, t in ipairs(ui._tabs) do navs[#navs + 1] = t._nav end
    ok(navs[1].label:GetText() == "General" and navs[2].label:GetText() == "Tracker"
       and navs[3].label:GetText() == "About", "labels follow the tab order")
    ok(navs[1].icon:GetTexture() == "Interface\\AddOns\\HostA\\Libs\\EverythingUI\\Media\\Textures\\icon-general",
       "the tab's icon is drawn")
    ok(navs[2]._points[1][2] == navs[1] and navs[2]._points[1][5] == -2, "items stack with a 2 px gap")
    ok(navs[1]._h == 36 and navs[1]._w == 196 - 16, "36 tall, the sidebar less its padding")
    local tr, tg, tb = ui:Color("text")
    local nr, ng, nb = ui:Color("navText")
    local hr, hg, hb = ui:Color("accentHi")
    ok(navs[1].active:IsShown() and not navs[2].active:IsShown(), "only the selected item has the accent background")
    ok(sameColor(navs[1].active._color, ui:Color("accent")) and navs[1].active._color[4] == 0.18,
       "the selected background is the accent at 0.18")
    ok(sameColor(navs[1].label._textColor, tr, tg, tb) and sameColor(navs[2].label._textColor, nr, ng, nb),
       "selected text is the text color, the rest navText")
    ok(navs[1].label._font[3] == "" and navs[1].label._font[1]:find("SemiBold", 1, true)
       and navs[2].label._font[1]:find("Medium", 1, true), "selected SemiBold, the rest Medium")
    ok(sameColor(navs[1].icon._vertex, hr, hg, hb) and sameColor(navs[2].icon._vertex, nr, ng, nb),
       "the selected icon is tinted accentHi")
    navs[2]:Click()
    ok(ui._current == "tracker" and tab(ui, "tracker")._holder:IsShown()
       and not tab(ui, "general")._holder:IsShown(), "clicking a nav item opens its tab")
end)

case("the last tab comes back, and an unknown one falls back to the first", function()
    for _, c in ipairs({ { nil, "general" }, { "tracker", "tracker" }, { "gone", "general" } }) do
        local _, _, ui, state = setup({ lastTab = c[1] })
        addTabs(ui)
        local f = ui:BuildSettings()
        ok(ui._current == c[2], "saved " .. tostring(c[1]) .. " opens " .. c[2])
        ok(state.lastTab == c[2], "and the selection is written back: " .. tostring(state.lastTab))
        ok(f.section:GetText() == tab(ui, c[2]).title, "the header names the section")
    end
end)

case("SelectTab builds once, refreshes every view, and shows one tab", function()
    local env, _, ui = setup()
    local log = addTabs(ui)
    local f = ui:BuildSettings()
    ui:SelectTab("general")
    ui:SelectTab("general")
    ok(log.build.general == 1, "built once: " .. tostring(log.build.general))
    ok(log.refresh.general == 3, "refreshed on every view, the build's included: " .. tostring(log.refresh.general))
    ok(log.controls.general == 3, "every registered control refreshes on every view")
    ok(log.self.general == ui, "build receives the context as self")
    ok(log.build.tracker == nil, "a tab never viewed is never built")
    ui:SelectTab("tracker")
    ok(tab(ui, "tracker")._holder:IsShown() and not tab(ui, "general")._holder:IsShown(), "only the current tab is shown")
    ok(log.footer == 1 and log.footerBar == tab(ui, "tracker")._footer, "the footer is built with its bar")
    ok(tab(ui, "tracker")._footer:IsShown(), "and shown with its tab")
    ui:SelectTab("general")
    ui:SelectTab("tracker")
    ok(log.footer == 1, "and built only once")
    ui:SelectTab("general")
    ok(not tab(ui, "tracker")._footer:IsShown(), "and hidden with its tab")
    ok(tab(ui, "general")._footer == nil, "a tab without a footer has no bar")
    ok(f.section:GetText() == "General", "the header follows the selection")
    ok(#env.timers > 0, "the content is measured on the next frame")
end)

case("MeasureContent sizes the column from what is shown", function()
    local env, _, ui = setup()
    addTabs(ui)
    ui:BuildSettings()
    local content = tab(ui, "general")._content
    content._top = 500
    local a = env.CreateFrame("Frame", nil, content)
    a._bottom = 300
    local hidden = env.CreateFrame("Frame", nil, content)
    hidden._bottom = 50
    hidden:Hide()
    local fs = content:CreateFontString()
    fs._bottom = 200
    env.timers = {}
    ui:MeasureContent(content)
    env.runTimers()
    ok(content._h == 500 - 200 + 24, "a region counts, a hidden child does not: " .. tostring(content._h))
end)

-- A tab whose text measures wider once the window is up than it did while the tab was built: the
-- Tracker tab in game on 2026-10-02.
local function lateTab(ui)
    local made = {}
    ui:RegisterTab({ id = "tracker", title = "Tracker",
        build = function(self, content)
            local card = self:CreateGroup(content, "Filters")
            made.slider = (self:CreateSlider(content, "Height", 0, 10, 1, function() return 1 end, function() end))
            card:Add(made.slider)
            made.button = self:CreateButton(content, "Reset")
            card:Add(made.button)
            made.content = content
        end,
        footer = function(self, bar)
            made.footer = self:CreateButton(bar, "Reset all")
            made.footer:SetPoint("RIGHT")
        end,
    })
    return made
end

local function widen(made)
    made.slider.label._measure = 300
    made.button.text._measure = 200
    made.footer.text._measure = 150
end

local function refitted(made)
    local left
    for i = #made.slider.slider._points, 1, -1 do
        local q = made.slider.slider._points[i]
        if q[1] == "LEFT" then left = q[4] break end
    end
    return left == 300 + 14, made.button:GetWidth() == 200 + 28, made.footer:GetWidth() == 150 + 28
end

case("a tab built before its window is shown is sized again once it is", function()
    local env, _, ui = setup({ lastTab = "tracker" })
    local made = lateTab(ui)
    local f = ui:BuildSettings()
    env.runTimers()
    widen(made)
    local col, btn, foot = refitted(made)
    ok(not col and not btn and not foot, "built hidden, everything is still sized from the build")
    made.content._top = 500
    env.timers = {}
    ui:SelectTab("tracker")
    f:Show()
    env.runTimers()
    col, btn, foot = refitted(made)
    ok(col, "on view the card's label column fits the label as it measures now")
    ok(btn, "a button in the content is sized again")
    ok(foot, "and so is a button in the tab's footer")
end)

case("a scale change from inside the open window sizes the tab again", function()
    local env, _, ui, state = setup({ lastTab = "tracker" })
    local made = lateTab(ui)
    local f = ui:BuildSettings()
    env.timers = {}
    state.scale = 0.9
    ui:ApplyWindowScale()
    ok(#env.timers == 0, "nothing is queued while the window is hidden")
    made.content._top = 500
    f:Show()
    env.runTimers()
    widen(made)
    state.scale = 0.85
    ui:ApplyWindowScale()
    env.runTimers()
    local col, btn, foot = refitted(made)
    ok(col and btn and foot, "the shown tab is sized again at the new scale")
end)

case("Escape closes the window, and stands down in combat", function()
    local env, _, ui = setup()
    addTabs(ui)
    local f = ui:BuildSettings()
    ok(f._keyboard == false, "no keyboard while hidden")
    f:Show()
    ok(f._keyboard == true and f._propagate == true, "keyboard on show, other keys passed through")
    f._propagate = false
    env.fire(f, "OnKeyDown", "A")
    ok(f:IsShown() and f._propagate == true, "another key leaves it open and is passed through on every press")
    env.fire(f, "OnKeyDown", "ESCAPE")
    ok(not f:IsShown() and f._propagate == false, "Escape closes it and is swallowed")
    ok(f._keyboard == false, "keyboard off once hidden")
    env.combat = true
    f:Show()
    ok(f._keyboard == false, "in combat the keyboard is never taken")
    local good = pcall(env.fire, f, "OnKeyDown", "ESCAPE")
    ok(good and f:IsShown(), "in combat Escape falls through without a protected call")
end)

case("the close button and the hide clean-up", function()
    local env, _, ui = setup()
    addTabs(ui)
    local f = ui:BuildSettings()
    f:Show()
    env.tooltip:Show()
    f.close:Click()
    ok(not f:IsShown(), "the close button hides the window")
    ok(not env.tooltip:IsShown(), "hiding the window hides the tooltip")
end)

case("ApplyWindowScale clamps to the screen and writes the clamp back", function()
    local env, _, ui, state = setup({ scale = 1.4 })
    addTabs(ui)
    local f = ui:BuildSettings()
    ui:ApplyWindowScale()
    ok(near(f._scale, 768 / 720), "1.4 is clamped to what fits: " .. tostring(f._scale))
    ok(#state.set == 1 and near(state.set[1], 768 / 720), "and the clamp is written back")
    state.scale, state.set = 0.8, {}
    f._center = { 500, 400 }
    f._scale = 1
    -- Where a drag leaves it: one point, of another name than the CENTER put back below.
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", env.UIParent, "BOTTOMLEFT", 80, 700)
    ui:ApplyWindowScale()
    ok(#f._points == 1, "the dragged anchor is let go, so only the restored center holds it")
    ok(f._scale == 0.8 and #state.set == 0, "a scale that fits is used as it is and not written")
    local p = f._points[#f._points]
    ok(p[1] == "CENTER" and p[3] == "BOTTOMLEFT" and near(p[4], 625) and near(p[5], 500),
       "the window keeps its center across the scale change")
    state.scale = "big"
    ui:ApplyWindowScale()
    ok(f._scale == 1, "a stored value that is not a number reads as 1")
    local _, _, plain = setup({ opts = { getWindowScale = NIL, setWindowScale = NIL } })
    addTabs(plain)
    local g = plain:BuildSettings()
    plain:ApplyWindowScale()
    ok(g._scale == 1, "no scale getter means 1")
end)

case("borders are one physical pixel, and re-snap with the scale", function()
    local _, _, ui, state = setup({ scale = 0.5 })
    addTabs(ui)
    local f = ui:BuildSettings()
    local n = edgeLines(f)
    ok(n == 4, "the window has a four-sided edge")
    ui:ApplyWindowScale()
    local line
    for _, r in ipairs({ f:GetRegions() }) do if r._euiAxis == "h" then line = r break end end
    ok(near(line._h, 1 / 0.5), "a horizontal line is one pixel at the new scale: " .. tostring(line._h))
    state.scale = 1
    ui:ApplyWindowScale()
    ok(near(line._h, 1), "and again after the next change")
    local env2, _, ui2 = setup({ env = { pixelUtil = false, screenHeight = 1080 } })
    addTabs(ui2)
    local f2 = ui2:BuildSettings()
    local line2
    for _, r in ipairs({ f2:GetRegions() }) do if r._euiAxis == "h" then line2 = r break end end
    ok(env2.PixelUtil == nil and near(line2._h, 768 / 1080), "without PixelUtil the fallback is 768 over the screen height")
end)

case("ToggleSettings opens and closes", function()
    local _, _, ui = setup({ scale = 0.8 })
    local log = addTabs(ui)
    ui:ToggleSettings()
    local f = ui._window
    ok(f and f:IsShown(), "the first toggle builds and shows")
    ok(f._scale == 0.8, "at the saved window scale: " .. tostring(f and f._scale))
    ok(log.refresh.general == 2, "and views the current tab again")
    ok((f._raised or 0) == 1, "in front of a main window that came forward since")
    ui:ToggleSettings()
    ok(not f:IsShown(), "the second hides")
end)

case("the Discord button", function()
    local env, _, ui, state = setup()
    addTabs(ui)
    local f = ui:BuildSettings()
    ok(f.discord and f.discord.text:GetText() == "Join our Discord!", "labelled from opts.labels")
    ok(#f.discord.text._points == 2, "its text runs from the icon to the edge, with no center left over")
    f.discord:Click()
    ok(state.discord == 1, "a click calls opts.discord")
    env.fire(f.discord, "OnEnter")
    local lines = env.tooltip._lines
    ok(lines[1].text == "Join our Discord" and sameColor(lines[1].color, GOLD[1], GOLD[2], GOLD[3]),
       "its tooltip title is gold")
    ok(lines[2] and lines[2].text == "Click to copy the invite link.", "with the body under it")
    local _, _, plain = setup({ opts = { discord = NIL } })
    addTabs(plain)
    ok(plain:BuildSettings().discord == nil, "no opts.discord, no button")
end)

case("CreateButton styles and sizes", function()
    local env, _, ui = setup()
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local clicks = 0
    local sec = ui:CreateButton(parent, "Reset", nil, function() clicks = clicks + 1 end, "Body")
    local n, colors = edgeLines(sec)
    local nr, ng, nb = ui:Color("navText")
    ok(n == 4 and sameColor(colors[1], nr, ng, nb), "secondary is the default, a navText outline")
    ok(sec._w == 5 * 6 + 28 and sec._h == 32, "sized to its label plus padding, 32 tall")
    sec:Click()
    ok(clicks == 1, "the click runs")
    env.fire(sec, "OnEnter")
    ok(env.tooltip._lines[1].text == "Reset" and env.tooltip._lines[2].text == "Body",
       "the tooltip is titled with the label, and survives the click script")
    local pri = ui:CreateButton(parent, "Go", 100, nil, nil, "primary")
    local ar, ag, ab = ui:Color("accent")
    local fill
    for _, r in ipairs({ pri:GetRegions() }) do if r._layer == "BACKGROUND" then fill = r end end
    ok(pri._w == 100 and fill and sameColor(fill._color, ar, ag, ab), "primary is an accent fill at the given width")
    ok(sameColor(pri.text._textColor, ui:Color("accentText")), "with accentText on it")
    local ghost = ui:CreateButton(parent, "X", nil, nil, nil, "ghost")
    ok(edgeLines(ghost) == 0, "ghost has no outline")
    pri:SetText("Again")
    ok(pri.text:GetText() == "Again", "SetText relabels")
    ok(not pcall(ui.CreateButton, ui, parent, "X", nil, nil, nil, "loud"), "an unknown style is refused")
    local empty = ui:CreateButton(parent, "", nil)
    ok(empty._w == 90 + 28, "an unmeasured label falls back to 90 rather than 0")
end)

case("AttachTooltip hooks, so a script the frame already has keeps running", function()
    local env, _, ui = setup()
    local f = env.CreateFrame("Button", nil, env.UIParent)
    local entered, left = 0, 0
    f:SetScript("OnEnter", function() entered = entered + 1 end)
    f:SetScript("OnLeave", function() left = left + 1 end)
    ui:AttachTooltip(f, "|cffff0000Title|r", "Body")
    env.fire(f, "OnEnter")
    ok(entered == 1, "the frame's own OnEnter still runs")
    ok(env.tooltip:IsShown() and env.tooltip._lines[1].text == "Title", "and the tooltip shows, its title stripped of color codes")
    ok(env.tooltip._owner == f and env.tooltip._anchor == "ANCHOR_NONE", "owned by the frame and placed by hand")
    ok(env.tooltip._lines[1].color[4] == 1 and env.tooltip._lines[1].wrap == true,
       "the fifth SetText argument is alpha 1 and the sixth wraps")
    env.fire(f, "OnLeave")
    ok(left == 1 and not env.tooltip:IsShown(), "leaving runs the frame's own OnLeave and hides the tooltip")
    ok(f._mouse == true, "the frame takes the mouse")
    ui:AttachTooltip(f)
    ok(true, "no title and no body is a no-op")
end)

case("a tooltip opens in one place, centered over the column just above its control", function()
    local env, _, ui = setup()
    local window = env.CreateFrame("Frame", nil, env.UIParent)
    window._scale = 0.8
    local column = env.CreateFrame("Frame", nil, window)
    column._controls = {}
    column._euiColumn = true
    column._center = { 400, 300 }
    local tip = env.tooltip
    local function only(owner, dx, label)
        local p = tip._points
        ok(#p == 1 and p[1][1] == "BOTTOM" and p[1][2] == owner and p[1][3] == "TOP"
           and near(p[1][4], dx) and p[1][5] == 4, label .. ": " .. tostring(p[1] and p[1][4]))
    end

    -- An indented row: it starts 40 in and ends 14 from the edge, so its center sits right of the column's.
    local row = env.CreateFrame("Frame", nil, column)
    row._center = { 413, 300 }
    row.slider = env.CreateFrame("Slider", nil, row)
    row.slider._center = { 600, 300 }
    ui:AttachTooltip(row, "Border Thickness", "Border thickness in pixels.")
    -- The tooltip is the host's and shared, so it can arrive still anchored by whatever showed it last.
    tip:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 10, -10)
    env.fire(row, "OnEnter")
    ok(tip._owner == row and tip._anchor == "ANCHOR_NONE", "owned by the control and placed by hand")
    only(row, (400 - 413) * 0.8, "over the label: 4 above the row, centered on the column, in the tooltip's own scale")
    env.fire(row, "OnLeave")
    env.fire(row.slider, "OnEnter")
    ok(tip._owner == row, "over the track the control still owns it")
    only(row, (400 - 413) * 0.8, "and it opens in exactly the same place")
    env.fire(row.slider, "OnLeave")

    local swatch = env.CreateFrame("Frame", nil, column)
    swatch._center = { 650, 300 }
    ui:AttachTooltip(swatch, "Shadow Color", "Its color.")
    env.fire(swatch, "OnEnter")
    only(swatch, (400 - 650) * 0.8, "a swatch at a row's end opens it over the column, not past it")
    env.fire(swatch, "OnLeave")

    local box = env.CreateFrame("CheckButton", nil, column)
    box._center = { 160, 300 }
    ui:AttachTooltip(box, "Text Shadow", "A shadow.")
    env.fire(box, "OnEnter")
    only(box, (400 - 160) * 0.8, "a box at a row's start opens it over the column too")
    env.fire(box, "OnLeave")

    local footer = env.CreateFrame("Frame", nil, window)
    footer._center = { 400, 40 }
    local reset = env.CreateFrame("Button", nil, footer)
    reset._center = { 700, 40 }
    ui:AttachTooltip(reset, "Reset to Defaults", "Restores this tab.")
    env.fire(reset, "OnEnter")
    only(reset, 0, "a button outside a tab's column is centered on itself")
    env.fire(reset, "OnLeave")

    local loose = env.CreateFrame("Frame", nil, column)
    ui:AttachTooltip(loose, "Unplaced", "No position yet.")
    env.fire(loose, "OnEnter")
    only(loose, 0, "a control with no position yet is centered on itself")
    env.fire(loose, "OnLeave")
    env.fire(swatch, "OnEnter")
    env.fire(swatch, "OnEnter")
    ok(#tip._points == 1, "each show starts from no anchors, so none piles up")
end)

case("a font that fails to load falls back to the client's", function()
    local env = W.newEnv()
    env.badFonts["Interface\\AddOns\\HostA\\Libs\\EverythingUI\\Media\\Fonts\\Barlow-Medium.ttf"] = true
    local lib = W.loadLibrary(root, env, "HostA", W.newLibStub())
    local ui = lib:NewContext({ id = "X", title = "X", version = "1", accent = { 1, 0, 0 }, L = {},
                                tooltip = function() return env.tooltip end })
    local b = ui:CreateButton(env.UIParent, "Medium text")
    ok(b.text._fontObject == env.GameFontHighlight, "the label still has a font")
    ok(b.text._shadow[1] == 0 and b.text._shadow[2] == 0, "and no shadow offset")
end)

case("the slim scroll bar", function()
    local _, _, ui = setup()
    addTabs(ui)
    ui:BuildSettings()
    local t = tab(ui, "general")
    local sf = t._scroll
    local bar
    for _, c in ipairs({ t._holder:GetChildren() }) do if c._type == "Slider" then bar = c end end
    ok(bar and bar._w == 6 and not bar:IsShown(), "6 px wide and hidden while nothing scrolls")
    ok(bar:GetThumbTexture():GetTexture():find("slider-thumb", 1, true), "the thumb is the library texture")
    sf._h = 400
    sf:_fire("OnScrollRangeChanged", 0, 300)
    local _, max = bar:GetMinMaxValues()
    ok(bar:IsShown() and max == 300, "shown once there is a range")
    bar._h = 392
    sf:_fire("OnScrollRangeChanged", 0, 300)
    ok(near(bar:GetThumbTexture()._h, 392 * 400 / 700), "the thumb is the view's share of the bar's own length")
    sf:_fire("OnScrollRangeChanged", 0, 5)
    ok(bar:GetThumbTexture()._h < 392, "so a range of a few pixels still leaves the thumb room to travel")
    local sized = bar:GetThumbTexture()._h
    bar._h = nil
    sf:_fire("OnScrollRangeChanged", 0, 300)
    ok(bar:GetThumbTexture()._h == sized, "a bar with no length yet leaves the thumb as it was")
    bar._h = 392
    sf:_fire("OnMouseWheel", -1)
    ok(bar:GetValue() == 48 and sf:GetVerticalScroll() == 48, "the wheel scrolls")
    for _ = 1, 20 do sf:_fire("OnMouseWheel", -1) end
    ok(bar:GetValue() == 300, "and stops at the end")
    sf:_fire("OnScrollRangeChanged", 0, 100)
    ok(bar:GetValue() == 100, "a shrinking range pulls the position back")
    sf:_fire("OnScrollRangeChanged", 0, 0)
    ok(not bar:IsShown(), "and no range hides it again")
    sf._h, bar._h = 50, 42
    sf:_fire("OnScrollRangeChanged", 0, 5000)
    ok(bar:GetThumbTexture()._h == 24, "the thumb never shrinks below 24")
end)

-- The bar is 392 long with its top at 1000, and a 300 range in a 400 view makes the thumb 224 long, so it travels 168.
case("the bar moves its own thumb", function()
    local env, _, ui = setup()
    addTabs(ui)
    local f = ui:BuildSettings()
    local t = tab(ui, "general")
    local sf = t._scroll
    local bar
    for _, c in ipairs({ t._holder:GetChildren() }) do if c._type == "Slider" then bar = c end end
    local grip = bar._euiGrip
    ok(not bar:IsMouseEnabled() and grip and grip:IsMouseEnabled(), "the bar takes no mouse, and the grip over it does")
    ok(grip._points[1][2] == bar and grip._points[2][1] == "BOTTOMRIGHT", "the grip covers the bar")
    sf._h, bar._h, bar._top = 400, 392, 1000
    sf:_fire("OnScrollRangeChanged", 0, 300)
    local function press(along, button)
        env.cursorY = 1000 - along
        env.mouseDown = "LeftButton"
        grip:_fire("OnMouseDown", button or "LeftButton")
    end
    local function move(along)
        env.cursorY = 1000 - along
        grip:_fire("OnUpdate", 0.016)
    end
    press(180)
    ok(bar:GetValue() == 0, "a press on the thumb leaves it where it is")
    move(264)
    ok(near(bar:GetValue(), 150) and near(sf:GetVerticalScroll(), 150), "dragged down half its travel, it scrolls half way")
    move(800)
    ok(bar:GetValue() == 300, "dragged past the end, it stops at the end")
    move(-200)
    ok(bar:GetValue() == 0, "dragged past the start, at the start")
    grip:_fire("OnMouseUp", "LeftButton")
    move(264)
    ok(bar:GetValue() == 0 and not grip:GetScript("OnUpdate"), "let go, it no longer follows")
    bar:SetValue(300)
    press(200)
    ok(bar:GetValue() == 300, "a press on a thumb at the far end leaves it there too")
    move(116)
    ok(near(bar:GetValue(), 150), "and dragging it up scrolls back up")
    grip:_fire("OnMouseUp", "LeftButton")
    bar:SetValue(0)
    press(250)
    ok(near(bar:GetValue(), (250 - 112) / 168 * 300), "a press on the track puts the thumb's middle under the cursor")
    move(230)
    ok(near(bar:GetValue(), (230 - 112) / 168 * 300), "and the thumb follows from there")
    env.mouseDown = nil
    move(300)
    ok(near(bar:GetValue(), (230 - 112) / 168 * 300) and not grip:GetScript("OnUpdate"),
       "a button let go off the grip ends the drag")
    press(180, "RightButton")
    ok(not grip:GetScript("OnUpdate"), "the right button does nothing")
    bar:SetValue(0)
    f:SetScale(0.5)
    env.mouseDown = "LeftButton"
    env.cursorY = (1000 - 180) * 0.5
    grip:_fire("OnMouseDown", "LeftButton")
    env.cursorY = (1000 - 264) * 0.5
    grip:_fire("OnUpdate", 0.016)
    ok(near(bar:GetValue(), 150), "in a scaled window the cursor is read in the bar's own units")
    sf:_fire("OnScrollRangeChanged", 0, 0)
    move(300)
    ok(bar:GetValue() == 0, "a range gone mid-drag leaves the value alone")
    grip:_fire("OnMouseUp", "LeftButton")
    f:SetScale(1)
    press(180)
    ok(bar:GetValue() == 0 and not grip:GetScript("OnUpdate"), "with nothing to scroll a press does nothing")
    sf:_fire("OnScrollRangeChanged", 0, 300)
    bar._top = nil
    press(180)
    ok(not grip:GetScript("OnUpdate"), "a bar not laid out yet takes no press")
    bar._top = 1000
    press(180)
    grip:_fire("OnHide")
    ok(not grip:GetScript("OnUpdate"), "the grip hiding ends a drag")
end)

-- The same bar: 392 long, top at 1000, a 224 thumb travelling 168 over a 300 range.
case("the drag keeps the cursor on the thumb", function()
    local env, _, ui = setup()
    addTabs(ui)
    ui:BuildSettings()
    local t = tab(ui, "general")
    local sf = t._scroll
    local bar
    for _, c in ipairs({ t._holder:GetChildren() }) do if c._type == "Slider" then bar = c end end
    local grip = bar._euiGrip
    sf._h, bar._h, bar._top = 400, 392, 1000
    sf:_fire("OnScrollRangeChanged", 0, 300)
    local function press(along)
        env.cursorY = 1000 - along
        env.mouseDown = "LeftButton"
        grip:_fire("OnMouseDown", "LeftButton")
    end
    local function move(along)
        env.cursorY = 1000 - along
        grip:_fire("OnUpdate", 0.016)
    end
    press(180)
    grip:_fire("OnMouseUp", "RightButton")
    move(264)
    ok(near(bar:GetValue(), 150), "another button let go mid-drag leaves the drag going")
    grip:_fire("OnMouseUp", "MiddleButton")
    ok(grip:GetScript("OnUpdate") ~= nil, "the middle button too")
    grip:_fire("OnMouseUp", "LeftButton")
    ok(not grip:GetScript("OnUpdate"), "the left button let go ends it")
    bar:SetValue(300)
    press(20)
    ok(bar:GetValue() == 0, "a press on the track by the top end puts the thumb at the top")
    move(40)
    ok(near(bar:GetValue(), 20 / 168 * 300), "and a move from there moves the thumb as far as the cursor, with no slide first")
    grip:_fire("OnMouseUp", "LeftButton")
    bar:SetValue(0)
    press(180)
    sf:_fire("OnScrollRangeChanged", 0, 600)
    move(180)
    local thumb = 392 * 400 / 1000
    ok(near(bar:GetValue(), (180 - 180 * thumb / 224) / (392 - thumb) * 600),
       "a range that grows mid-drag keeps the cursor at the same share of the shorter thumb")
    grip:_fire("OnMouseUp", "LeftButton")
end)

case("a tab with a preview gives the panel its right side", function()
    local _, _, ui = setup()
    addTabs(ui)
    local seen = { order = {}, built = 0, refreshed = 0 }
    ui:RegisterTab({
        id = "appearance", title = "Appearance", order = 30,
        build = function() seen.order[#seen.order + 1] = "build" end,
        preview = function(self, panel)
            seen.order[#seen.order + 1] = "preview"
            seen.built, seen.self, seen.panel = seen.built + 1, self, panel
        end,
        previewRefresh = function(self, panel)
            seen.refreshed, seen.refreshSelf, seen.refreshPanel = seen.refreshed + 1, self, panel
        end,
    })
    ui:BuildSettings()
    local t, general = tab(ui, "appearance"), tab(ui, "general")
    local panel = t._preview
    ok(panel and panel._parent == t._holder, "the panel lives in the tab's holder, so it shows and hides with the tab")
    ok(panel._w == 320, "320 wide")
    local p = panel._points
    ok(#p == 2 and p[1][1] == "TOPRIGHT" and p[1][2] == nil and p[2][1] == "BOTTOMRIGHT" and p[2][2] == nil,
       "down the whole right side of the tab")
    local fill
    for _, r in ipairs({ panel:GetRegions() }) do
        if r._layer == "BACKGROUND" and r._color then fill = r end
    end
    ok(fill and sameColor(fill._color, ui:Color("chrome")), "on the chrome fill, like the other chrome")
    local n, colors = edgeLines(panel)
    local edge
    for _, r in ipairs({ panel:GetRegions() }) do if r._euiAxis then edge = r end end
    ok(n == 1 and sameColor(colors[1], ui:Color("divider")) and edge._euiAxis == "w"
       and edge._points[1][1] == "TOPLEFT" and edge._points[2][1] == "BOTTOMLEFT",
       "with one divider line down its left edge")

    ok(t._content._w == 1100 - 196 - 48 - 320, "the column narrows by the panel: " .. tostring(t._content._w))
    local function last(frame, name)
        for i = #frame._points, 1, -1 do if frame._points[i][1] == name then return frame._points[i] end end
        return {}
    end
    ok(last(t._scroll, "BOTTOMRIGHT")[2] == -(24 + 320), "the scroll area stops short of it")
    local bar
    for _, c in ipairs({ t._holder:GetChildren() }) do if c._type == "Slider" then bar = c end end
    ok(bar and last(bar, "TOPRIGHT")[2] == -(9 + 320) and last(bar, "BOTTOMRIGHT")[2] == -(9 + 320),
       "and so does its scroll bar")
    ok(general._preview == nil and general._content._w == 1100 - 196 - 48 and last(general._scroll, "BOTTOMRIGHT")[2] == -24,
       "a tab without a preview keeps the full column")

    ok(seen.built == 0 and seen.refreshed == 0, "nothing is built until the tab is shown")
    ui:SelectTab("appearance")
    ok(seen.built == 1 and seen.self == ui and seen.panel == panel, "built on first view with the context and the panel")
    ok(seen.order[1] == "build" and seen.order[2] == "preview", "after the tab's own build")
    ok(seen.refreshed == 1 and seen.refreshSelf == ui and seen.refreshPanel == panel, "and refreshed on the view")
    ui:SelectTab("general")
    ok(seen.refreshed == 1, "not refreshed while another tab is shown")
    ui:SelectTab("appearance")
    ok(seen.built == 1 and seen.refreshed == 2, "built once, refreshed on every view")
end)

case("a nav title too long for its item takes a second line", function()
    local _, _, ui = setup()
    addTabs(ui)
    ui:BuildSettings()
    for _, t in ipairs(ui._tabs) do
        ok(t._nav.label._wrap == true and t._nav.label._maxLines == 2, t.id .. " wraps, at most twice")
    end
end)

case("a Discord label too long for one line wraps and the button grows for it", function()
    local env, _, ui = setup({ lastTab = "general" })
    addTabs(ui)
    local f = ui:BuildSettings()
    local d = f.discord
    ok(d.text._wrap == true and d.text._maxLines == 2, "the label wraps, at most twice")
    ok(d._h == 32, "one line keeps the button's height: " .. tostring(d._h))
    local listed = 0
    for _, b in ipairs(f.sidebar._euiFit or {}) do if b == d then listed = listed + 1 end end
    ok(listed == 1, "listed once on the sidebar for Refit")
    local bottom = d._points[1]
    ok(bottom[1] == "BOTTOMLEFT", "anchored at its bottom, so it grows upward")
    -- Two lines once the window is on screen: the label measures as the client draws it.
    d.text._measureH = 31
    env.timers = {}
    ui:SelectTab("general")
    env.runTimers()
    ok(d._h == 44, "the sidebar is sized again on view, and the button takes two lines: " .. tostring(d._h))
    d.text._measureH = 15
    ui:SelectTab("tracker")
    env.runTimers()
    ok(d._h == 32, "and shrinks back to one line: " .. tostring(d._h))
    d.text._measureH = 19
    ui:SelectTab("general")
    env.runTimers()
    ok(d._h == 32, "a single line drawn a little tall is still one line: " .. tostring(d._h))
end)

case("a scale capped while the window is open is read again by the tab on screen", function()
    local env, _, ui, state = setup({ scale = 0.9, lastTab = "general" })
    local log = addTabs(ui)
    local f = ui:BuildSettings()
    f:Show()
    env.runTimers()
    local before = log.controls.general
    state.scale = 1.4
    ui:ApplyWindowScale()
    ok(log.controls.general == before + 1, "the capped value reaches the slider on screen: "
       .. tostring(before) .. " then " .. tostring(log.controls.general))
    ok(log.controls.tracker == nil, "a tab not on screen is left alone")
    state.scale = 0.8
    ui:ApplyWindowScale()
    ok(log.controls.general == before + 1, "a scale that fits reads nothing again")
    f:Hide()
    state.scale = 1.4
    ui:ApplyWindowScale()
    ok(log.controls.general == before + 1, "nor does a cap while the window is hidden")
end)

case("the settings scroll range is floored to whole units", function()
    local _, _, ui = setup()
    addTabs(ui)
    ui:BuildSettings()
    local t = tab(ui, "general")
    local sf = t._scroll
    local bar
    for _, c in ipairs({ t._holder:GetChildren() }) do if c._type == "Slider" then bar = c end end
    sf._h, bar._h = 400, 392
    sf:_fire("OnScrollRangeChanged", 0, 120.7)
    local _, max = bar:GetMinMaxValues()
    ok(max == 120 and bar:IsShown(), "a fractional range drops its fraction: " .. tostring(max))
    sf:_fire("OnScrollRangeChanged", 0, 0.6)
    ok(not bar:IsShown(), "and less than a unit is no range at all")
end)

-- Cooldown Master's shape: a plain tab, two groups of pages, a plain tab. The pages' orders sort them
-- ahead of every top-level tab, so nothing passes by an order tie.
local function addGroups(ui)
    local log = { header = 0 }
    ui:RegisterTab({ id = "global", title = "Global", order = 5, icon = ui:Texture("icon-general"), build = function() end })
    ui:RegisterTab({ id = "lanes", title = "Lanes", order = 6, icon = ui:Texture("icon-tracker"), group = true })
    for i, c in ipairs({ { "lanes.general", "General" }, { "lanes.appearance", "Appearance" }, { "lanes.text", "Text" } }) do
        ui:RegisterTab({ id = c[1], parent = "lanes", title = c[2], order = i, build = function() end,
                         header = function(self, bar)
                             log.header = log.header + 1
                             log.bar, log.self = bar, self
                         end })
    end
    ui:RegisterTab({ id = "ready", title = "Ready", order = 7, icon = ui:Texture("icon-appearance"), group = true })
    for i, c in ipairs({ { "ready.general", "General" }, { "ready.text", "Text" } }) do
        ui:RegisterTab({ id = c[1], parent = "ready", title = c[2], order = i, build = function() end })
    end
    ui:RegisterTab({ id = "about", title = "About", order = 9, icon = ui:Texture("icon-about"), build = function() end })
    return log
end

local function hangs(nav, from, gap)
    local p = nav._points[1] or {}
    return #nav._points == 1 and p[1] == "TOPLEFT" and p[2] == from and p[3] == "BOTTOMLEFT" and p[5] == -gap
end

case("RegisterTab takes groups and pages, and refuses what does not fit them", function()
    local _, _, ui = setup()
    local function where(def)
        local good, err = pcall(function()
            local r = ui:RegisterTab(def)
            return r
        end)
        return not good and tostring(err):find("test_window.lua", 1, true) ~= nil, tostring(err)
    end
    ok(pcall(ui.RegisterTab, ui, { id = "lanes", title = "Lanes", group = true }), "a group needs no build")
    for _, key in ipairs({ "build", "refresh", "footer", "header", "preview" }) do
        local refused, err = where({ id = "g" .. key, title = "G", group = true, [key] = function() end })
        ok(refused and err:find("takes no " .. key, 1, true), "a group with a " .. key .. " is refused at the caller: " .. err)
    end
    local refused, err = where({ id = "gp", title = "G", group = true, parent = "lanes" })
    ok(refused and err:find("takes no parent", 1, true), "a group inside a group is refused: " .. err)
    refused, err = where({ id = "x", title = "X", build = function() end, parent = "nowhere" })
    ok(refused and err:find("parent nowhere is not a group registered before it", 1, true),
       "a page naming no group is refused at the caller: " .. err)
    ui:RegisterTab({ id = "plain", title = "Plain", build = function() end })
    refused, err = where({ id = "y", title = "Y", build = function() end, parent = "plain" })
    ok(refused and err:find("parent plain", 1, true), "and so is one naming a tab that is not a group: " .. err)
    refused, err = where({ id = "plain", title = "Again", build = function() end })
    ok(refused and err:find("id plain twice", 1, true), "an id used twice is refused at the caller: " .. err)
    refused, err = where({ id = "plain", title = "Again", group = true })
    ok(refused and err:find("id plain twice", 1, true), "and so is a group taking a tab's id: " .. err)
    refused, err = where({ id = "lanes", title = "Lanes", parent = "lanes", build = function() end })
    ok(refused and err:find("id lanes twice", 1, true), "and a page taking its group's id: " .. err)
    refused = where({ id = "z", title = "Z", group = "yes" })
    ok(refused, "group must be a boolean")
    refused = where({ id = "z", title = "Z", build = function() end, header = "strip" })
    ok(refused, "header must be a function")
    refused = where({ id = "z", title = "Z", group = false })
    ok(refused, "a tab that is not a group still needs its build")
end)

case("a group with no pages in it is refused at the caller, before any window is made", function()
    local _, _, ui = setup()
    ui:RegisterTab({ id = "global", title = "Global", build = function() end })
    ui:RegisterTab({ id = "lanes", title = "Lanes", group = true })
    ui:RegisterTab({ id = "lanes.general", parent = "lanes", title = "General", build = function() end })
    ui:RegisterTab({ id = "empty", title = "Empty", group = true })
    local function refused(fn)
        local good, err = pcall(fn)
        err = tostring(err)
        return not good and err:find("group empty has no tabs in it", 1, true) ~= nil
               and err:find("test_window.lua", 1, true) ~= nil, err
    end
    local r, err = refused(function() local f = ui:BuildSettings() return f end)
    ok(r, "built directly: " .. err)
    ok(ui._window == nil, "and no window is left half built")
    for i = 1, 2 do
        r, err = refused(function() local f = ui:ToggleSettings() return f end)
        ok(r, "opened with a toggle, try " .. i .. ", the same error: " .. err)
    end
end)

case("pages with the same order, or none, keep the order they were registered in", function()
    local names = { "defaults", "spells", "items", "trinkets", "potions", "pet", "buffs", "offensives", "utility", "custom" }
    for _, shared in ipairs({ false, true }) do
        local _, _, ui = setup()
        ui:RegisterTab({ id = "global", title = "Global", order = 1, build = function() end })
        ui:RegisterTab({ id = "filters", title = "Filters", order = 5, group = true })
        for _, n in ipairs(names) do
            ui:RegisterTab({ id = "filters." .. n, parent = "filters", title = n, order = shared and 5 or nil,
                             build = function() end })
        end
        ui:RegisterTab({ id = "about", title = "About", order = 9, build = function() end })
        ui:BuildSettings()
        local got = {}
        for i, k in ipairs(tab(ui, "filters")._kids) do got[i] = k.title end
        ok(table.concat(got, ",") == table.concat(names, ","),
           (shared and "sharing their group's order: " or "with no order: ") .. table.concat(got, ","))
    end
end)

case("library controls work in a strip and a footer, and each page's copy follows the setting", function()
    local _, _, ui = setup()
    local inst, unlocked = 1, false
    local seg, box = {}, {}
    ui:RegisterTab({ id = "lanes", title = "Lanes", order = 1, group = true })
    for i, p in ipairs({ "general", "appearance" }) do
        ui:RegisterTab({ id = "lanes." .. p, parent = "lanes", title = p, order = i, build = function() end,
            header = function(self, bar)
                seg[p] = self:CreateRadioGroup(bar, nil, { { value = 1, label = "Lane 1" }, { value = 2, label = "Lane 2" },
                    { value = 3, label = "Lane 3" } }, function() return inst end, function(v) inst = v end, 400)
            end,
            footer = function(self, bar)
                box[p] = self:CreateCheckbox(bar, "Unlock Frames", function() return unlocked end,
                                             function(v) unlocked = v end)
            end })
    end
    ui:BuildSettings()
    ui:SelectTab("lanes.appearance")
    ok(seg.general and seg.appearance and box.general and box.appearance,
       "a radio group in each strip and a checkbox in each footer")
    seg.appearance.buttons[2]:Click()
    box.appearance:Click()
    ui:SelectTab("lanes.general")
    local function lit(h) for i, b in ipairs(h.buttons) do if b.fill:IsShown() then return i end end end
    ok(inst == 2 and lit(seg.general) == 2, "the other page's strip shows the lane picked on this one")
    ok(unlocked and box.general:GetChecked(), "and its footer the box ticked on this one")
end)

case("groups draw as rows that open onto their pages, only the one holding the page open", function()
    local _, _, ui, state = setup()
    addGroups(ui)
    local f = ui:BuildSettings()
    local g, lanes, ready, about = tab(ui, "global")._nav, tab(ui, "lanes"), tab(ui, "ready"), tab(ui, "about")._nav
    local lg, la, lt = tab(ui, "lanes.general")._nav, tab(ui, "lanes.appearance")._nav, tab(ui, "lanes.text")._nav
    ok(ui._current == "global", "the first tab with no group is shown first")
    ok(g._points[1][1] == "TOPLEFT" and g._points[1][2] == 8 and g._points[1][3] == -12, "it starts the sidebar")
    ok(hangs(lanes._nav, g, 2) and hangs(ready._nav, lanes._nav, 2) and hangs(about, ready._nav, 2),
       "closed, the groups stack like tabs with a 2 px gap")
    ok(not lg:IsShown() and not la:IsShown() and not lanes._guide:IsShown(), "their pages and guide line are hidden")
    ok(lanes._nav.chevron._file:find("chevron%-right$"), "a closed group points right")
    ok(lanes._nav.label._textColor and sameColor(lanes._nav.label._textColor, ui:Color("navText")) and not lanes._nav.active:IsShown(),
       "and reads like any other row")

    lanes._nav:Click()
    ok(ui._current == "lanes.general" and tab(ui, "lanes.general")._holder:IsShown(), "a click on a group opens its first page")
    ok(f.section:GetText() == "Lanes / General" and state.lastTab == "lanes.general",
       "the header names the group and the page, and the page is what is saved")
    ok(lg:IsShown() and la:IsShown() and lt:IsShown(), "the group's pages show")
    ok(hangs(lg, lanes._nav, 2) and hangs(la, lg, 0) and hangs(lt, la, 0) and hangs(ready._nav, lt, 2),
       "under the group 2 px down, page against page, the next group 2 px under the last page")
    ok(not tab(ui, "ready.general")._nav:IsShown(), "another group stays shut")
    ok(lanes._nav.chevron._file:find("chevron%-down$") and ready._nav.chevron._file:find("chevron%-right$"),
       "the open group's chevron points down")
    local gl = lanes._guide
    local gp = gl._points[1] or {}
    ok(gl:IsShown() and gp[1] == "TOPLEFT" and gp[2] == lg and gp[3] == "TOPLEFT" and gp[4] == 19 and gp[5] == -4
       and gl._h == 3 * 28 - 8 and gl._w and gl._w > 0 and gl._w < 2 and sameColor(gl._color, ui:Color("inputBorder")),
       "a guide line under the group's icon, from 4 below the first page to 4 above the last")
    ok(sameColor(lanes._nav.label._textColor, ui:Color("text")) and not lanes._nav.active:IsShown()
       and sameColor(lanes._nav.icon._vertex, ui:Color("accentHi")) and lanes._nav.label._font[1]:find("Medium", 1, true),
       "the group holding the page reads in the text color with its icon lit, and no fill and no SemiBold")
    ok(lg.active:IsShown() and not la.active:IsShown() and not g.active:IsShown()
       and lg.label._font[1]:find("SemiBold", 1, true) and la.label._font[1]:find("Medium", 1, true),
       "the page's own row carries the fill and the SemiBold")

    la:Click()
    ok(ui._current == "lanes.appearance" and f.section:GetText() == "Lanes / Appearance", "a page row opens its page")
    ready._nav:Click()
    ok(ui._current == "ready.general" and not lg:IsShown() and tab(ui, "ready.text")._nav:IsShown(),
       "opening another group shuts the first")
    ok(ready._guide:IsShown() and ready._guide._h == 2 * 28 - 8, "a two-page group's guide spans its two pages")
    ok(sameColor(lanes._nav.label._textColor, ui:Color("navText")), "and the first goes back to a plain row")
    lanes._nav:Click()
    ok(ui._current == "lanes.appearance", "a group opens again on the page last shown in it")
    tab(ui, "global")._nav:Click()
    ok(not lg:IsShown() and not lanes._guide:IsShown() and hangs(ready._nav, lanes._nav, 2),
       "a tab outside every group shuts them all")
end)

case("a click on the open group shuts it with its page left on screen, and a second opens it again", function()
    local _, _, ui = setup()
    addGroups(ui)
    local f = ui:BuildSettings()
    local lanes, ready = tab(ui, "lanes"), tab(ui, "ready")
    local lg, la, lt = tab(ui, "lanes.general")._nav, tab(ui, "lanes.appearance")._nav, tab(ui, "lanes.text")._nav
    la:Click()
    lanes._nav:Click()
    ok(ui._current == "lanes.appearance" and tab(ui, "lanes.appearance")._holder:IsShown()
       and f.section:GetText() == "Lanes / Appearance", "the page stays on screen")
    ok(not lg:IsShown() and not la:IsShown() and not lt:IsShown() and not lanes._guide:IsShown(),
       "its pages and guide line hide")
    ok(lanes._nav.chevron._file:find("chevron%-right$"), "its chevron points right")
    ok(hangs(ready._nav, lanes._nav, 2), "the next group moves up under it")
    ok(sameColor(lanes._nav.label._textColor, ui:Color("text")) and sameColor(lanes._nav.icon._vertex, ui:Color("accentHi")),
       "shut, it still reads as the group holding the page")
    lanes._nav:Click()
    ok(ui._current == "lanes.appearance" and lg:IsShown() and la:IsShown() and la.active:IsShown()
       and lanes._nav.chevron._file:find("chevron%-down$") and hangs(ready._nav, lt, 2),
       "a second click opens it again on the same page")
    lanes._nav:Click()
    ui:SelectTab("lanes.appearance")
    ok(not lg:IsShown(), "the same page shown again, as a strip pick or a footer box does, leaves it shut")
    ui:SelectTab("lanes.text")
    ok(lg:IsShown() and ui._current == "lanes.text", "going to another of its pages opens it")
    lanes._nav:Click()
    ready._nav:Click()
    ok(ui._current == "ready.general" and tab(ui, "ready.general")._nav:IsShown() and not lg:IsShown(),
       "another group still opens on its page")
    lanes._nav:Click()
    ok(ui._current == "lanes.text" and lg:IsShown(), "and the shut group opens again, on its last page, when it is picked")
end)

case("ScrollIntoView brings a frame on a settings page into view a frame later, held to the page's range", function()
    local env, _, ui = setup()
    ui:RegisterTab({ id = "a", title = "A", build = function() end })
    ui:BuildSettings()
    local t = tab(ui, "a")
    local content, sf = t._content, t._scroll
    local bar
    for _, c in ipairs({ t._holder:GetChildren() }) do if c._type == "Slider" then bar = c end end
    local inner = env.CreateFrame("Frame", nil, env.CreateFrame("Frame", nil, content))
    content._top, inner._top = 1000, 640
    sf._vrange = 0
    bar:SetMinMaxValues(0, 800)
    -- The client works the range out again only when asked, which is what UpdateScrollChildRect does
    sf.UpdateScrollChildRect = function(self) self._vrange = 500 end
    ui:ScrollIntoView(inner)
    ok(bar:GetValue() == 0, "nothing moves before the page is measured")
    env.runTimers()
    ok(bar:GetValue() == 360 and sf:GetVerticalScroll() == 360, "a frame two deep comes to the top of the view")
    inner._top = 100
    ui:ScrollIntoView(inner)
    env.runTimers()
    ok(bar:GetValue() == 500, "one past the page's end scrolls as far as the page goes, not the bar's stale end")
    inner._top = 1100
    ui:ScrollIntoView(inner)
    env.runTimers()
    ok(bar:GetValue() == 0, "and one above the top no further than the top")
    inner._top = nil
    ui:ScrollIntoView(inner)
    ok(pcall(env.runTimers) and bar:GetValue() == 0, "a frame not laid out yet is left where it is")
    local loose = env.CreateFrame("Frame", nil, env.UIParent)
    ok(pcall(ui.ScrollIntoView, ui, loose) and bar:GetValue() == 0, "a frame on no settings page is left alone")
end)

case("a page's row is one line, lined up with its group's label, and draws no icon", function()
    local _, _, ui = setup()
    ui:RegisterTab({ id = "lanes", title = "Lanes", icon = ui:Texture("icon-tracker"), group = true })
    ui:RegisterTab({ id = "lanes.general", parent = "lanes", title = "General", icon = ui:Texture("icon-general"),
                     build = function() end })
    ui:BuildSettings()
    local nav = tab(ui, "lanes.general")._nav
    local lp = nav.label._points[1] or {}
    ok(nav._h == 28 and nav.icon == nil, "28 tall with no icon, even when one is passed")
    ok(lp[1] == "LEFT" and lp[2] == 38 and nav.label._wrap == false, "its text 38 in, on one line")
    local rp = nav.label._points[2] or {}
    ok(rp[1] == "RIGHT" and rp[2] == -12 and rp[3] == 0, "and 12 short of the row's right end")
    local ch = tab(ui, "lanes")._nav.chevron
    local cp = ch._points[1] or {}
    ok(#ch._points == 1 and cp[1] == "RIGHT" and cp[2] == -12 and cp[3] == 0 and ch._w == 12 and ch._h == 12
       and sameColor(ch._vertex, ui:Color("muted")), "a group's 12 px chevron sits 12 in from the right, muted")
    local right
    for _, p in ipairs(tab(ui, "lanes")._nav.label._points) do if p[1] == "RIGHT" then right = p end end
    ok(right and right[2] == ch and right[3] == "LEFT" and right[4] == -10 and right[5] == 0,
       "a group's label stops 10 short of its chevron")
end)

case("the saved page comes back with its group open, and a saved group opens its first page", function()
    for _, c in ipairs({ { "lanes.text", "lanes.text" }, { "ready", "ready.general" }, { "gone", "global" } }) do
        local _, _, ui, state = setup({ lastTab = c[1] })
        addGroups(ui)
        ui:BuildSettings()
        ok(ui._current == c[2] and state.lastTab == c[2], "saved " .. c[1] .. " opens " .. c[2])
    end
    local _, _, ui = setup({ lastTab = "lanes.text" })
    addGroups(ui)
    ui:BuildSettings()
    ok(tab(ui, "lanes.text")._nav:IsShown(), "with its group open")
    local _, _, lead = setup()
    lead:RegisterTab({ id = "lanes", title = "Lanes", order = 1, group = true })
    lead:RegisterTab({ id = "lanes.a", parent = "lanes", title = "A", order = 1, build = function() end })
    lead:RegisterTab({ id = "about", title = "About", order = 9, build = function() end })
    lead:BuildSettings()
    ok(lead._current == "lanes.a", "with nothing saved and a group first, that group's first page opens")
end)

case("a page's header is a pinned strip above its scrolling column", function()
    local env, _, ui = setup()
    local log = addGroups(ui)
    ui:BuildSettings()
    local t = tab(ui, "lanes.general")
    local hb = t._header
    ok(hb and hb._parent == t._holder and hb._h == 52, "a 52 px strip in the page's holder")
    local p1, p2 = hb._points[1] or {}, hb._points[2] or {}
    ok(p1[1] == "TOPLEFT" and p1[2] == nil and p2[1] == "TOPRIGHT" and p2[2] == 0, "across the top of the page")
    local bottom = 0
    for _, r in ipairs({ hb:GetRegions() }) do
        if r._layer == "BORDER" and sameColor(r._color, ui:Color("divider")) and r._points[1][1] == "BOTTOMLEFT"
                and r._points[2][1] == "BOTTOMRIGHT" then
            bottom = bottom + 1
        end
    end
    ok(bottom == 1, "with a divider under it")
    local sp = t._scroll._points[1] or {}
    ok(sp[1] == "TOPLEFT" and sp[2] == 24 and sp[3] == -(20 + 52), "the column starts under it")
    local bar
    for _, c in ipairs({ t._holder:GetChildren() }) do if c._type == "Slider" then bar = c end end
    ok(bar and bar._points[1][1] == "TOPRIGHT" and bar._points[1][3] == -(20 + 52), "and so does its scroll bar")
    local gp = tab(ui, "global")._scroll._points[1]
    ok(gp[3] == -20 and tab(ui, "global")._header == nil, "a tab with no header keeps its column where it was")

    ok(log.header == 0, "the strip is filled when its page is first shown, not before")
    local refits = 0
    ui:SelectTab("lanes.general")
    ok(log.header == 1 and log.bar == hb and log.self == ui and hb:IsShown(), "header gets the context and the strip, shown")
    hb._euiFit = { { Fit = function() refits = refits + 1 end } }
    ui:SelectTab("global")
    ui:SelectTab("lanes.general")
    ok(log.header == 1, "once")
    env.runTimers()
    ok(refits >= 1, "and sized again on screen, as a footer is")
    ui:SelectTab("lanes.appearance")
    ok(log.header == 2, "each page fills a strip of its own")
end)

case("a header beside a preview stops at the panel", function()
    local _, _, ui = setup()
    ui:RegisterTab({ id = "a", title = "A", build = function() end, header = function() end, preview = function() end })
    ui:BuildSettings()
    local p2 = tab(ui, "a")._header._points[2]
    ok(p2[1] == "TOPRIGHT" and p2[2] == -320, "its right end is the panel's left")
end)

-- MINOR 51: the settings search, which a host turns on with labels.search (the author, 2026-10-17).
local SEARCH_LABELS = {
    discord = "Join our Discord!", discordTipTitle = "Join our Discord", discordTip = "Click to copy the invite link.",
    search = "Search settings", searchEmpty = "No settings match", searchTitle = "Search results",
}

local function never() return false end
local function noop() end

-- Three pages, a group holding two more, and every kind of place a search can find or must skip. Labels in other
-- alphabets are written as bytes: E-acute, Cyrillic, Yo and the multiplication sign.
local function searchSetup()
    local env, _, ui, state = setup({ opts = { labels = SEARCH_LABELS } })
    local log = { build = {}, refresh = {}, cards = {}, rows = {} }
    local function reg(def)
        local build = def.build
        def.build = function(self, content)
            log.build[def.id] = (log.build[def.id] or 0) + 1
            build(self, content)
        end
        def.refresh = function() log.refresh[def.id] = (log.refresh[def.id] or 0) + 1 end
        ui:RegisterTab(def)
    end
    reg({ id = "general", title = "General", order = 10, build = function(self, content)
        local display = self:CreateGroup(content, "Display")
        log.cards.display, log.content = display, content
        log.rows.lock = display:Add(self:CreateCheckbox(content, "Lock tracker", never, noop))
        log.rows.scale = display:Add(self:CreateSlider(content, "Tracker scale", 50, 200, 5, function() return 100 end, noop))
        local hidden = self:CreateCheckbox(content, "Show hidden thing", never, noop)
        display:Add(hidden)
        hidden:Hide()
        display:Layout()
        display:Add(self:CreateTextRow(content, "Show version", "2.6.0"))
        log.rows.reset = display:Add(self:CreateButton(content, "Reset filters", nil, noop))
    end, footer = function(self, bar)
        log.footerButton = self:CreateButton(bar, "Reset all settings", nil, noop)
        self:CreateButton(bar, "Hidden reset", nil, noop):Hide()
    end })
    reg({ id = "tracker", title = "Tracker", order = 20, build = function(self, content)
        local details = self:CreateGroup(content, "Quest Row Details")
        log.cards.details = details
        log.rows.level = details:Add(self:CreateCheckbox(content, "Show quest level", never, noop))
        log.rows.red = details:Add(self:CreateCheckbox(content, "|cffff0000Red|r alert", never, noop))
        local sounds = self:CreateGroup(content, "Sounds")
        log.cards.sounds = sounds
        log.rows.play = sounds:Add(self:CreateCheckbox(content, "Play a sound", never, noop))
        local secret = self:CreateGroup(content, "Secret")
        secret:Add(self:CreateCheckbox(content, "Show secret", never, noop))
        secret:Hide()
        local untitled = self:CreateGroup(content, nil)
        log.rows.name = untitled:Add(self:CreateTextField(content, "Profile name", function() return "" end, noop))
        untitled:Add(self:CreateCheckbox(content, "Bareable", never, noop))
    end, footer = function(self, bar)
        log.trackerFooter = self:CreateButton(bar, "Reset tracker look", nil, noop)
    end })
    ui:RegisterTab({ id = "lanes", title = "Lanes", order = 30, group = true })
    reg({ id = "lanes.text", parent = "lanes", title = "Text", order = 1, build = function(self, content)
        local fonts = self:CreateGroup(content, "Fonts")
        log.rows.elan = fonts:Add(self:CreateCheckbox(content, "\195\137lan vital", never, noop))
        log.rows.ru = fonts:Add(self:CreateCheckbox(content, "\208\159\208\190\208\186\208\176\208\183\208\176\209\130\209\140 level", never, noop))
        log.rows.yo = fonts:Add(self:CreateCheckbox(content, "\208\129\208\187\208\186\208\176", never, noop))
        log.rows.grid = fonts:Add(self:CreateCheckbox(content, "Grid 2\195\1513", never, noop))
        fonts:Add(self:CreateCheckbox(content, "|TInterface/Icons/x:14|t Glow |A:star:12:12|aicons", never, noop))
        fonts:Add(self:CreateCheckbox(content, "Long\nwrapped name", never, noop))
        fonts:Add(self:CreateCheckbox(content, "Big-area tint", never, noop))
    end })
    reg({ id = "lanes.bars", parent = "lanes", title = "Bars", order = 2, build = function() end,
          header = function(self, bar)
              log.strip = self:CreateCheckbox(bar, "Next strip", never, noop)
          end })
    local f = ui:BuildSettings()
    -- The client fires OnTextChanged for a SetText as well as for a keystroke, and the model fires neither.
    local box = f.search and f.search.box
    if box then
        local set = box.SetText
        box.SetText = function(self, s)
            set(self, s)
            env.fire(self, "OnTextChanged", false)
        end
    end
    local function type_(s) box:SetText(s) end
    local function shown()
        local list, out = ui._results.list, {}
        for i = 1, list._shown do out[i] = { list.rows[i].text:GetText(), list.rows[i].value:GetText() } end
        return out
    end
    return env, ui, f, log, type_, shown, state
end

local function rowsAre(got, want)
    if #got ~= #want then return false end
    for i, w in ipairs(want) do
        if got[i][1] ~= w[1] or got[i][2] ~= w[2] then return false end
    end
    return true
end

case("a host without labels.search keeps its sidebar as before, and the search labels come as a set", function()
    local _, _, ui = setup()
    addTabs(ui)
    local f = ui:BuildSettings()
    ok(f.search == nil and ui._results == nil, "no search field and no results page")
    local p = tab(ui, "general")._nav._points[1] or {}
    ok(p[1] == "TOPLEFT" and p[2] == 8 and p[3] == -12, "the first page row 12 from the top, as before")
    local function labelled(extra)
        local labels = { discord = "D", discordTipTitle = "D", discordTip = "D" }
        for k, v in pairs(extra) do labels[k] = v end
        return pcall(setup, { opts = { labels = labels } })
    end
    ok(not labelled({ search = "S" }), "search alone is refused")
    ok(not labelled({ search = "S", searchEmpty = "E" }), "search with no title is refused")
    ok(not labelled({ search = "S", searchTitle = "T" }), "search with no empty line is refused")
    ok(labelled({ search = "S", searchEmpty = "E", searchTitle = "T" }), "all three are taken")
    ok(labelled({ searchEmpty = "E", searchTitle = "T" }), "the other two alone turn nothing on")
    ok(not labelled({ search = "S", searchEmpty = "E", searchTitle = "T", searchHint = "H" }), "an unknown label is still refused")
end)

case("labels.search puts a search field at the top of the sidebar and the pages under it", function()
    local _, ui, f = searchSetup()
    local field = f.search
    ok(field and field._parent == f.sidebar, "a field in the sidebar")
    local p1, p2 = field._points[1] or {}, field._points[2] or {}
    ok(p1[1] == "TOPLEFT" and p1[2] == 8 and p1[3] == -12 and p2[1] == "TOPRIGHT" and p2[2] == -8 and p2[3] == -12,
       "across the sidebar, 12 from the top and 8 in from each side")
    ok(field.hint:GetText() == "Search settings", "hinting with the host's label")
    local p = tab(ui, "general")._nav._points[1] or {}
    ok(p[1] == "TOPLEFT" and p[2] == 8 and p[3] == -(12 + 30 + 12), "the first page row 12 under the field")
    local results = ui._results
    ok(results and results._parent == f.area and not results:IsShown(), "a results page in the content area, hidden")
    local lp1, lp2 = results.list._points[1] or {}, results.list._points[2] or {}
    ok(lp1[1] == "TOPLEFT" and lp1[2] == 24 and lp1[3] == -20 and lp2[1] == "BOTTOMRIGHT" and lp2[2] == -24 and lp2[3] == 0,
       "its list where a page's column sits")
    ok(results.empty:GetText() == "No settings match", "with the host's line for no match")
end)

case("typing lists the matching settings with their place, building every page once and refreshing none", function()
    local _, ui, f, log, type_, shown = searchSetup()
    local general = tab(ui, "general")
    ok(log.build.general == 1 and log.build.tracker == nil and log.build["lanes.text"] == nil, "only the open page is built")
    type_("show")
    ok(rowsAre(shown(), { { "Show quest level", "Tracker > Quest Row Details" } }),
       "a setting on an unopened page, and no hidden control, hidden card or text row")
    ok(log.build.tracker == 1 and log.build["lanes.text"] == 1 and log.build["lanes.bars"] == 1, "every page built")
    ok(log.trackerFooter ~= nil, "and its footer")
    ok(log.refresh.tracker == nil and log.refresh["lanes.text"] == nil and log.refresh.general == 1, "none refreshed")
    ok(ui._results:IsShown() and not general._holder:IsShown() and not general._footer:IsShown(),
       "the results in place of the open page and its footer")
    ok(f.section:GetText() == "Search results", "titled for the search")
    ok(not ui._results.empty:IsShown(), "with no empty line")
    local list = ui._results.list
    list.scroll._h = 56
    list.bar:SetMinMaxValues(0, 500)
    list.bar:SetValue(200)
    type_("show q")
    ok(log.build.tracker == 1 and log.build.general == 1, "a second search builds nothing again")
    ok(list.bar:GetValue() == 0, "and starts its list at the top")
    type_("  ")
    ok(not ui._results:IsShown() and general._holder:IsShown() and general._footer:IsShown(),
       "blank text brings the open page back")
    ok(f.section:GetText() == "General" and ui._current == "general", "titled for it again")
end)

case("every word has to be in the name, its card's or its page's, and a whole match in the name comes first", function()
    local _, ui, _, _, type_, shown = searchSetup()
    type_("tracker")
    ok(rowsAre(shown(), {
        { "Lock tracker", "General > Display" }, { "Tracker scale", "General > Display" },
        { "Reset tracker look", "Tracker" },
        { "Quest Row Details", "Tracker" }, { "Show quest level", "Tracker > Quest Row Details" },
        { "Red alert", "Tracker > Quest Row Details" }, { "Sounds", "Tracker" }, { "Play a sound", "Tracker > Sounds" },
        { "Profile name", "Tracker" }, { "Bareable", "Tracker" },
    }), "names holding the word first, then the rest of the page named for it, each in page order")
    type_("sounds")
    ok(rowsAre(shown(), { { "Sounds", "Tracker" }, { "Play a sound", "Tracker > Sounds" } }), "a card is a place of its own")
    type_("sounds play")
    ok(rowsAre(shown(), { { "Play a sound", "Tracker > Sounds" } }), "one word in the card, one in the name")
    type_("level show")
    ok(rowsAre(shown(), { { "Show quest level", "Tracker > Quest Row Details" } }), "in any order")
    type_("SHOW QUEST")
    ok(#shown() == 1 and shown()[1][1] == "Show quest level", "whatever the case")
    type_("red alert")
    ok(rowsAre(shown(), { { "Red alert", "Tracker > Quest Row Details" } }), "a colored name read and shown plain")
    type_("reset filters")
    ok(rowsAre(shown(), { { "Reset filters", "General > Display" } }), "a button in a card, by its caption")
    type_("reset all")
    ok(rowsAre(shown(), { { "Reset all settings", "General" } }), "a footer's button, placed on its page")
    type_("profile")
    ok(rowsAre(shown(), { { "Profile name", "Tracker" } }), "a card with no title adds nothing to the place")
    type_("\195\169lan")
    ok(rowsAre(shown(), { { "\195\137lan vital", "Lanes > Text > Fonts" } }), "an accented capital, under its group")
    type_("\195\137LAN")
    ok(#shown() == 1, "typed in capitals too")
    type_("\208\191\208\190\208\186\208\176\208\183\208\176\209\130\209\140")
    ok(#shown() == 1 and shown()[1][2] == "Lanes > Text > Fonts", "Cyrillic typed in lower case")
    type_("\208\159\208\158\208\154\208\144\208\151\208\144\208\162\208\172")
    ok(#shown() == 1, "and in capitals, either half of the alphabet")
    type_("\209\145\208\187\208\186\208\176")
    ok(#shown() == 1, "Yo, from the block before the alphabet")
    type_("2\195\1513")
    ok(#shown() == 1, "the multiplication sign as it is")
    type_("2\195\1833")
    ok(#shown() == 0, "and never read as a division sign")
    type_("secret")
    ok(#shown() == 0 and ui._results.empty:IsShown(), "nothing in a hidden card, and the empty line says so")
    type_("version")
    ok(#shown() == 0, "nor a text row")
    type_("play")
    ok(rowsAre(shown(), {
        { "Play a sound", "Tracker > Sounds" }, { "Display", "General" },
        { "Lock tracker", "General > Display" }, { "Tracker scale", "General > Display" },
        { "Reset filters", "General > Display" },
    }), "a word starting a name before one inside a name, and both before the card's rows")
    ok(not ui._results.empty:IsShown(), "the empty line goes once something matches")
    type_("sound play")
    ok(shown()[1][1] == "Play a sound", "every word has to start a word for the first place")
    type_("ay sou")
    ok(rowsAre(shown(), { { "Play a sound", "Tracker > Sounds" } }), "inside words when nothing starts with them")
    type_("isp")
    ok(rowsAre(shown(), {
        { "Display", "General" }, { "Lock tracker", "General > Display" }, { "Tracker scale", "General > Display" },
        { "Reset filters", "General > Display" },
    }), "a name holding the word inside before the places under it")
    type_("alert red")
    ok(#shown() == 1, "a word after a color code still starts a word")
    type_("level")
    ok(rowsAre(shown(), {
        { "Show quest level", "Tracker > Quest Row Details" },
        { "\208\159\208\190\208\186\208\176\208\183\208\176\209\130\209\140 level", "Lanes > Text > Fonts" },
    }), "in the sidebar's order, a group's pages in the group's place whatever their own order numbers")
    local FONTS = "Lanes > Text > Fonts"
    local fontRows = {
        { "Fonts", "Lanes > Text" }, { "\195\137lan vital", FONTS },
        { "\208\159\208\190\208\186\208\176\208\183\208\176\209\130\209\140 level", FONTS },
        { "\208\129\208\187\208\186\208\176", FONTS }, { "Grid 2\195\1513", FONTS }, { "Glow icons", FONTS },
        { "Long wrapped name", FONTS }, { "Big-area tint", FONTS },
    }
    type_("ext")
    local want = { { "Next strip", "Lanes > Bars" } }
    for _, r in ipairs(fontRows) do want[#want + 1] = r end
    ok(rowsAre(shown(), want), "a name holding the word inside before the places only their page names")
    type_("lanes ext")
    want = {}
    for _, r in ipairs(fontRows) do want[#want + 1] = r end
    want[#want + 1] = { "Next strip", "Lanes > Bars" }
    ok(rowsAre(shown(), want), "a word missing from the name keeps it among them, whatever the other word does")
    type_("area")
    ok(rowsAre(shown(), { { "Big-area tint", FONTS }, { "Bareable", "Tracker" } }), "a word after a hyphen starts a word")
    type_("glow")
    ok(rowsAre(shown(), { { "Glow icons", FONTS } }), "a name read without its icons")
    type_("long wrapped")
    ok(rowsAre(shown(), { { "Long wrapped name", FONTS } }), "and on one line")
    type_("strip")
    ok(rowsAre(shown(), { { "Next strip", "Lanes > Bars" } }), "a setting in a page's header strip, placed on its page")
    type_("hidden")
    ok(#shown() == 0, "nothing hidden, in a card or a footer")
end)

case("a result opens its page, scrolls to the place and flashes it", function()
    local env, ui, f, log, type_ = searchSetup()
    local tracker = tab(ui, "tracker")
    local bar
    for _, c in ipairs({ tracker._holder:GetChildren() }) do if c._type == "Slider" then bar = c end end
    bar:SetMinMaxValues(0, 800)
    tracker._scroll.UpdateScrollChildRect = function(self) self._vrange = 500 end
    type_("play")
    tracker._content._top, log.rows.play._top = 1000, 700
    ui._results.list.rows[1]:Click()
    ok(ui._current == "tracker" and tracker._holder:IsShown() and not ui._results:IsShown(), "the page in place of the results")
    ok(f.search.box:GetText() == "" and f.section:GetText() == "Tracker", "the search cleared and the page titled")
    ok(log.refresh.tracker == 1, "refreshed as it opens")
    env.runTimers()
    ok(bar:GetValue() == 300, "the setting brought to the top of the view")
    local tex = log.rows.play._euiFlash
    local r, g, b = ui:Color("accent")
    ok(tex and tex._layer == "ARTWORK" and tex:IsShown() and tex:GetAlpha() == 1, "its row lit, behind the control")
    ok(tex and sameColor(tex._color, r, g, b) and near(tex._color[4], 0.3), "in the accent at 30 percent")
    ok(tex and #tex._points == 2 and tex._points[1][1] == "TOPLEFT" and tex._points[2][1] == "BOTTOMRIGHT", "across the row")
    local driver = ui._flashDriver
    env.fire(driver, "OnUpdate", 0.3)
    ok(tex:GetAlpha() == 1, "held for a moment")
    env.fire(driver, "OnUpdate", 0.5)
    ok(near(tex:GetAlpha(), 1 - 0.4 / 1.2), "then fading")
    env.fire(driver, "OnUpdate", 1.0)
    ok(not tex:IsShown() and not driver:IsShown(), "and gone, and nothing left running")
    type_("play")
    ui._results.list.rows[1]:Click()
    ok(tex:IsShown() and tex:GetAlpha() == 1 and driver:IsShown(), "the same place lit again from full")
    env.fire(driver, "OnUpdate", 5)

    type_("sounds")
    log.cards.sounds._top = 900
    ui._results.list.rows[1]:Click()
    env.runTimers()
    ok(bar:GetValue() == 100, "a card brought to the top by its title")
    local panelTex = log.cards.sounds.panel._euiFlash
    ok(panelTex and panelTex:IsShown(), "and its panel lit")

    type_("level")
    ui._results.list.rows[1]:Click()
    ok(not panelTex:IsShown() and log.rows.level._euiFlash:IsShown(), "a new flash ends the last one")

    type_("reset all")
    ui._results.list.rows[1]:Click()
    env.runTimers()
    ok(ui._current == "general" and log.footerButton._euiFlash:IsShown(), "a footer's button lit on its page")
end)

case("Enter opens the first result, and a page picked or the window closed ends the search", function()
    local env, ui, f, log, type_ = searchSetup()
    type_("play")
    env.fire(f.search.box, "OnEnterPressed")
    ok(ui._current == "tracker" and log.rows.play._euiFlash:IsShown(), "Enter opens the first result")
    type_("zzz")
    env.fire(f.search.box, "OnEnterPressed")
    ok(ui._current == "tracker" and ui._results:IsShown(), "and with none does nothing")
    type_("show")
    tab(ui, "general")._nav:Click()
    ok(ui._current == "general" and not ui._results:IsShown() and f.search.box:GetText() == "", "a page row ends the search")
    ok(tab(ui, "general")._holder:IsShown() and f.section:GetText() == "General", "and shows its page")

    type_("play")
    ui._results.list.rows[1]:Click()
    type_("show")
    f.search.box:SetFocus()
    f:Show()
    f:Hide()
    ok(not f.search.box:HasFocus(), "closing the window lets go of the keyboard")
    ok(not log.rows.play._euiFlash:IsShown() and not ui._flashDriver:IsShown(), "and ends a flash")
    ui:ToggleSettings()
    ok(f:IsShown() and not ui._results:IsShown() and f.search.box:GetText() == "", "it opens again with no search")
    ok(tab(ui, "tracker")._holder:IsShown(), "on the page that was open")
end)

case("a result in a shut group opens the group", function()
    local _, ui, _, _, type_ = searchSetup()
    ui:SelectTab("lanes.text")
    tab(ui, "lanes")._nav:Click()
    ok(tab(ui, "lanes")._collapsed and not tab(ui, "lanes.text")._nav:IsShown(), "the group holding the page shut")
    type_("\209\145\208\187\208\186\208\176")
    ui._results.list.rows[1]:Click()
    ok(ui._current == "lanes.text" and not tab(ui, "lanes")._collapsed, "opened again by the result")
    ok(tab(ui, "lanes.text")._nav:IsShown(), "with the page's row shown")
end)

print(("test_window: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end

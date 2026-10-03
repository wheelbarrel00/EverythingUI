-- Run with Lua 5.1 from any folder: lua5.1 tests/test_card.lua

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

local function layer(frame, name)
    local out = {}
    for _, r in ipairs({ frame:GetRegions() }) do
        if r._layer == name then out[#out + 1] = r end
    end
    return out
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
    local lib = W.loadLibrary(root, env, "HostA", W.newLibStub())
    local ui = lib:NewContext({
        id = "EQOT", title = "EQ Objective Tracker", version = "1.28.0",
        accent = { 0.784, 0.216, 0.243 }, L = {},
        tooltip = function() return env.tooltip end,
    })
    local content = env.CreateFrame("Frame", nil, env.UIParent)
    content._controls = {}
    content._w = 856
    content._level = 7
    return env, lib, ui, content
end

local function box(ui, content, label)
    return ui:CreateCheckbox(content, label, function() return false end, function() end)
end

local function slider(ui, content, label)
    return (ui:CreateSlider(content, label, 0, 10, 1, function() return 1 end, function() end))
end

case("CreateGroup is a group label over a surface panel", function()
    local _, _, ui, content = setup()
    local card = ui:CreateGroup(content, "General")
    ok(card._parent == content and card:GetFrameLevel() == 7 and card.panel:GetFrameLevel() == 7,
       "built at the content's own level, so the content's other children draw over it")
    ok(card.label:GetText() == "General" and card.label._font[2] == 12
       and card.label._font[1]:find("SemiBold", 1, true) and sameColor(card.label._textColor, ui:Color("muted")),
       "the label is 12 SemiBold in muted, as written")
    local lp = point(card.label, "TOPLEFT")
    ok(lp[2] == 2 and lp[3] == 0, "inset 2 at the top")
    local pp = point(card.panel, "TOPLEFT")
    ok(pp[2] == 0 and pp[3] == -(12 + 8) and point(card.panel, "TOPRIGHT")[3] == -(12 + 8),
       "the panel starts 8 under the label")
    local edges = layer(card.panel, "BORDER")
    ok(sameColor(layer(card.panel, "BACKGROUND")[1]._color, ui:Color("surface")) and #edges == 4
       and sameColor(edges[1]._color, ui:Color("surfaceBorder")), "on surface with a surfaceBorder edge")
    ok(card._h == 12 + 8 + 1, "an empty card is only its label and a sliver of panel: " .. tostring(card._h))
    local bare = ui:CreateGroup(content, nil)
    ok(bare.label == nil and point(bare.panel, "TOPLEFT")[3] == 0, "a card with no label starts with its panel")
    ok(#content._controls == 0, "a card is not a control")
end)

case("a label the client has not measured still leaves room for itself", function()
    local env, _, ui, content = setup()
    env.stringHeight = 0
    local card = ui:CreateGroup(content, "General")
    ok(point(card.panel, "TOPLEFT")[3] == -(12 + 8), "the label's font size stands in for its height")
end)

case("Add stacks rows, and the row is what satellites anchor to", function()
    local env, _, ui, content = setup()
    local card = ui:CreateGroup(content, "General")
    local a = box(ui, content, "Use Blizzard's quest tracker")
    local rowA = card:Add(a)
    ok(rowA._parent == card.panel and rowA.control == a and a._euiRow == rowA, "the row lives in the panel")
    ok(rowA._h == 44 and rowA:GetFrameLevel() == 7, "44 tall, at the card's level")
    local tl, tr = point(rowA, "TOPLEFT"), point(rowA, "TOPRIGHT")
    ok(tl[2] == card.panel and tl[5] == 0 and tr[2] == card.panel and tr[5] == 0, "the first row is at the top")
    local la = point(a, "LEFT")
    ok(la[2] == rowA and la[3] == "LEFT" and la[4] == 14 and la[5] == 0, "a checkbox sits 14 in, centered")
    ok(point(a, "RIGHT")[1] == nil, "and keeps its own width")
    ok(not rowA.divider:IsShown() and sameColor(rowA.divider._color, ui:Color("divider")), "no divider above the first row")
    ok(a._parent == content, "the control keeps the content as its parent, so it draws over the panel")

    local s = slider(ui, content, "Options Window Scale")
    local rowS = card:Add(s)
    ok(point(rowS, "TOPLEFT")[5] == -44 and rowS.divider:IsShown(), "the next row stacks under it with a divider")
    ok(point(s, "LEFT")[4] == 14 and point(s, "RIGHT")[2] == rowS and point(s, "RIGHT")[4] == -14,
       "a full-width control spans the row less its padding")

    local d = slider(ui, content, "Shadow size")
    local rowD = card:Add(d, { dependent = true })
    ok(rowD._h == 40 and point(rowD, "TOPLEFT")[5] == -88, "a dependent row is 40 tall")
    ok(point(d, "LEFT")[4] == 40 and d._euiDependent == true, "indented 40 under its master")
    ok(point(d.slider, "LEFT")[4] == 124 + 14 and point(s.slider, "LEFT")[4] == 150 + 14,
       "its label column is shortened so its control lines up with the row above")
    ok(card.panel._h == 44 + 44 + 40 and card._h == 12 + 8 + 128, "the card is sized to its rows: " .. tostring(card._h))

    local hint = content:CreateFontString()
    local rowH = card:Add(hint, { height = 30, fill = true })
    ok(rowH._h == 30 and point(hint, "RIGHT")[4] == -14, "a row can set its own height, and fill")
    ok(card._h == 12 + 8 + 158, "and is counted")
    local sat = env.CreateFrame("Button", nil, content)
    sat:SetPoint("RIGHT", rowA, "RIGHT", -14, 0)
    ok(sat:GetFrameLevel() > card:GetFrameLevel(), "a satellite anchored to a row draws over the card")
end)

case("a row follows its control, and Layout restacks the shown ones", function()
    local _, _, ui, content = setup()
    local card = ui:CreateGroup(content, "Filters")
    local c1, c2, c3 = box(ui, content, "One"), box(ui, content, "Two"), box(ui, content, "Three")
    local r1, r2, r3 = card:Add(c1), card:Add(c2), card:Add(c3)
    c2:Hide()
    card:Layout()
    ok(not r2:IsShown(), "hiding a control hides its row")
    ok(point(r3, "TOPLEFT")[5] == -44 and r3.divider:IsShown(), "and closes its gap")
    ok(card.panel._h == 88 and card._h == 12 + 8 + 88, "and leaves the height")
    c1:Hide()
    card:Layout()
    ok(point(r3, "TOPLEFT")[5] == 0 and not r3.divider:IsShown(), "the new first row loses its divider")
    c1:Show()
    c2:Show()
    card:Layout()
    ok(r1:IsShown() and r2:IsShown(), "showing the controls brings their rows back")
    ok(point(r2, "TOPLEFT")[5] == -44 and point(r3, "TOPLEFT")[5] == -88 and r2.divider:IsShown(),
       "in their order")
    c3:Hide()
    ok(card:Measure() == 88 and card._h == 12 + 8 + 88, "Measure counts only rows whose control is shown")
    local hint = content:CreateFontString()
    hint:Hide()
    local rh = card:Add(hint, { fill = true })
    ok(not rh:IsShown(), "a control hidden before it is added starts with its row hidden")
end)

case("each card aligns its own label column", function()
    local _, _, ui, content = setup()
    local a = ui:CreateGroup(content, "Appearance")
    local b = ui:CreateGroup(content, "Scenario")
    local short = slider(ui, content, "Size")
    local long = slider(ui, content, string.rep("x", 30))
    local other = slider(ui, content, "Gap")
    a:Add(short)
    a:Add(long)
    b:Add(other)
    ok(point(short.slider, "LEFT")[4] == 180 + 14 and point(long.slider, "LEFT")[4] == 180 + 14,
       "the long label widens its own card's column")
    ok(point(other.slider, "LEFT")[4] == 150 + 14, "and no other card's")
    long:Hide()
    a:Layout()
    ok(point(short.slider, "LEFT")[4] == 150 + 14, "a hidden row stops counting")
end)

case("Refit aligns a card's label column again with the widths its text measures now", function()
    local _, lib, ui, content = setup()
    local card = ui:CreateGroup(content, "Tracker Visibility")
    local short = slider(ui, content, "Height")
    local long = slider(ui, content, "Maximum Height (percent of tracker)")
    -- Measured short while the tab was built, as this label was on the Tracker tab in game.
    long.label._measure = 100
    card:Add(short)
    card:Add(long, { dependent = true })
    ok(content._euiCards and #content._euiCards == 1 and content._euiCards[1] == card,
       "the card is listed on its content")
    ok(point(short.slider, "LEFT")[4] == 150 + 14 and point(long.slider, "LEFT")[4] == 124 + 14,
       "at build the column is the token's 150")
    long.label._measure = 260
    lib.kit.Refit(content)
    ok(point(short.slider, "LEFT")[4] == 286 + 14,
       "after Refit the column fits the label as it measures now, plus its indent: "
       .. tostring(point(short.slider, "LEFT")[4]))
    ok(point(long.slider, "LEFT")[4] == 260 + 14, "and the indented row's control lines up with the rest")
    local other = ui:CreateGroup(content, "Section Order")
    ok(#content._euiCards == 2 and content._euiCards[2] == other, "every card on the content is listed")
end)

case("a fitHeight row is sized to its text block, again on every Layout", function()
    local env, lib, ui, content = setup()
    local card = ui:CreateGroup(content, "Changelog")
    card:Add(box(ui, content, "One"))
    local block = ui:CreateTextBlock(content)
    block:AddLine("1.28.0", "value")
    local item = block:AddLine("Use Blizzard's quest tracker, a new option", "label", { bullet = "-" })
    -- Wrapped to three lines once the row gives it a width.
    item._measureH = 39
    local row = card:Add(block, { fitHeight = true })
    ok(row._h == 13 + 4 + 39 + 24, "the row is its block's height with 12 above and below: " .. tostring(row._h))
    ok(point(block, "LEFT")[4] == 14 and point(block, "RIGHT")[4] == -14, "the block spans the row less its padding")
    local after = box(ui, content, "Two")
    local rowAfter = card:Add(after)
    ok(point(rowAfter, "TOPLEFT")[5] == -(44 + 80) and card._h == 12 + 8 + 44 + 80 + 44,
       "the rows under it stack below its height")

    -- Wrapped taller once the tab is on screen than it measured while the tab was built.
    item._measureH = 65
    lib.kit.Refit(content)
    ok(row._h == 13 + 4 + 65 + 24, "Refit sizes the row to the text as it measures now: " .. tostring(row._h))
    ok(point(rowAfter, "TOPLEFT")[5] == -(44 + 106) and card._h == 12 + 8 + 44 + 106 + 44,
       "and moves the rows under it")
    ok(card._rows[1]._h == 44 and rowAfter._h == 44, "a row of a set height keeps it")

    block:Hide()
    card:Layout()
    ok(not row:IsShown() and point(rowAfter, "TOPLEFT")[5] == -44, "a hidden block's row closes like any other")

    ok(not pcall(card.Add, card, box(ui, content, "Three"), { fitHeight = true }),
       "a control with no Measure is refused")
    local good, err = pcall(function()
        local r = card:Add(env.CreateFrame("Frame", nil, content), { fitHeight = true })
        return r
    end)
    ok(not good and tostring(err):find("test_card.lua", 1, true) ~= nil and tostring(err):find("Measure", 1, true) ~= nil,
       "and the error names the caller's line: " .. tostring(err))
end)

case("Add measures only the row it adds, and Layout measures every fitted row", function()
    local _, _, ui, content = setup()
    local card = ui:CreateGroup(content, "Changelog")
    local calls = 0
    for i = 1, 3 do
        local block = ui:CreateTextBlock(content)
        block:AddLine("1.2" .. i .. ".0", "value")
        local measure = block.Measure
        block.Measure = function(b) calls = calls + 1 return measure(b) end
        card:Add(block, { fitHeight = true })
    end
    ok(calls == 3, "adding three blocks measures each one once: " .. calls)
    card:Layout()
    ok(calls == 6, "and Layout measures all three again: " .. calls)
end)

case("AddDivider draws a line under a row", function()
    local _, _, ui, content = setup()
    local card = ui:CreateGroup(content, "General")
    local cb = box(ui, content, "One")
    local row = card:Add(cb)
    local line = ui:AddDivider(card, cb)
    ok(line._parent == card.panel and sameColor(line._color, ui:Color("divider")), "a divider-colored line on the panel")
    local tl, tr = point(line, "TOPLEFT"), point(line, "TOPRIGHT")
    ok(tl[2] == row and tl[3] == "BOTTOMLEFT" and tr[2] == row and tr[3] == "BOTTOMRIGHT", "across the row's foot")
    ok(line._euiAxis == "h" and near(line._h, 1), "one pixel tall, and snapped")
end)

print(("test_card: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end

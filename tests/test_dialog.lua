-- Run with Lua 5.1 from any folder: lua5.1 tests/test_dialog.lua

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

local function confirm(extra)
    local opts = { title = "EQ Objective Tracker", text = "Reset every setting on this tab?",
                   button1 = "Reset", button2 = "Not now" }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return opts
end

case("a dialog is built when first shown, never as the files load", function()
    local env, _, ui = setup()
    local before = #env.created
    ok(ui._dialog == nil and before == 0, "nothing built by loading")
    ui:ShowDialog(confirm())
    local f = ui._dialog
    ok(f and f:IsShown() and f._parent == env.UIParent, "a frame on UIParent, shown")
    ok(f._name == nil, "unnamed, so nothing can read it out of _G")
    ok(f._strata == "FULLSCREEN_DIALOG", "above the settings window's DIALOG strata")
    ok(f._movable and f._clamped and f._mouse and f._drag and f._drag[1] == "LeftButton",
       "movable by its body, clamped to the screen")
    ok(f:GetScript("OnDragStart") == f.StartMoving and f:GetScript("OnDragStop") == f.StopMovingOrSizing,
       "a drag moves it and letting go stops it")
    ok(point(f, "CENTER")[1] == "CENTER" and f._w == 420, "420 wide in the middle of the screen")
    ok(f._raised == 1, "raised over anything at its strata")
    local n = #env.created
    ui:ShowDialog(confirm())
    ok(#env.created == n, "built once")
end)

case("the look: a surface card, the title, the text, a primary button and a secondary one", function()
    local _, _, ui = setup()
    ui:ShowDialog(confirm())
    local f = ui._dialog
    local fill, edges
    for _, r in ipairs({ f:GetRegions() }) do
        if r._layer == "BACKGROUND" and r._color then fill = r end
    end
    ok(fill and sameColor(fill._color, ui:Color("surface")), "on the surface fill")
    edges = 0
    for _, r in ipairs({ f:GetRegions() }) do
        if r._euiAxis and sameColor(r._color, ui:Color("surfaceBorder")) then edges = edges + 1 end
    end
    ok(edges == 4, "with a surfaceBorder edge all round")
    ok(f.title:GetText() == "EQ Objective Tracker" and f.title._font[2] == 15
       and f.title._font[1]:find("SemiBold", 1, true) and sameColor(f.title._textColor, ui:Color("text")),
       "the title in 15 SemiBold text, no brand red")
    ok((f.title._font[3] or "") == "", "and no outline")
    ok(f.title._wrap == true, "a long title wraps")
    ok(f.body:GetText() == "Reset every setting on this tab?" and f.body._font[2] == 13
       and sameColor(f.body._textColor, ui:Color("label")) and f.body._wrap == true, "the text in 13 label, wrapping")
    ok(point(f.title, "TOPLEFT")[2] == 20 and point(f.title, "TOPLEFT")[3] == -20 and point(f.title, "TOPRIGHT")[2] == -20,
       "20 in from each side and the top")
    ok(point(f.body, "TOPLEFT")[2] == f.title and point(f.body, "TOPLEFT")[5] == -10, "the text 10 under the title")
    local ar, ag, ab = ui:Color("accent")
    local aFill
    for _, r in ipairs({ f.accept:GetRegions() }) do
        if r._layer == "BACKGROUND" and r._color then aFill = r end
    end
    ok(f.accept.text:GetText() == "Reset" and aFill and sameColor(aFill._color, ar, ag, ab),
       "the first button is primary, on the accent")
    ok(f.accept:IsShown() and not f.acceptDanger:IsShown(), "a plain confirm shows no danger button")
    ok(f.cancel:IsShown() and f.cancel.text:GetText() == "Not now", "the second is secondary, with its own word")
    ok(point(f.accept, "BOTTOMRIGHT")[2] == -20 and point(f.accept, "BOTTOMRIGHT")[3] == 16,
       "the primary at the bottom right")
    ok(point(f.cancel, "RIGHT")[2] == f.accept and point(f.cancel, "RIGHT")[3] == "LEFT"
       and point(f.cancel, "RIGHT")[4] == -10, "the secondary just left of it")
    ok(f.accept._w == #"Reset" * 6 + 28 and f.cancel._w == #"Not now" * 6 + 28, "each sized to its label")
    ok(f._h == 20 + 15 + 10 + 13 + 20 + 32 + 16, "as tall as its title, text and buttons: " .. tostring(f._h))
end)

case("a dialog with one button has no secondary", function()
    local _, _, ui = setup()
    ui:ShowDialog({ title = "EQ Objective Tracker", text = "Done.", button1 = "OK" })
    local f = ui._dialog
    ok(not f.cancel:IsShown() and f.accept:IsShown() and f.accept.text:GetText() == "OK", "OK alone, at the right")
    ui:ShowDialog(confirm())
    ok(f.cancel:IsShown(), "and the next two-button dialog brings the secondary back")
end)

local function regions(frame, layerName)
    local found = {}
    for _, r in ipairs({ frame:GetRegions() }) do
        if r._layer == layerName and r._color then found[#found + 1] = r end
    end
    return found
end

case("a confirm that erases something draws its first button in the danger style", function()
    local env, _, ui = setup()
    local accepted, during = 0, nil
    ui:ShowDialog(confirm({ danger = true, onAccept = function()
        accepted = accepted + 1
        during = ui._dialog:IsShown()
    end }))
    local f = ui._dialog
    local d = f.acceptDanger
    ok(d:IsShown() and not f.accept:IsShown() and f.shownAccept == d, "the danger button in place of the primary")
    ok(d.text:GetText() == "Reset", "carrying button1")
    local edges = regions(d, "BORDER")
    local allDanger = #edges == 4
    for _, e in ipairs(edges) do allDanger = allDanger and sameColor(e._color, ui:Color("danger")) end
    ok(allDanger and sameColor(d.text._textColor, ui:Color("danger")), "outlined and lettered in danger")
    ok(#regions(d, "BACKGROUND") == 0, "with no accent fill")
    local hi = regions(d, "HIGHLIGHT")
    ok(#hi == 1 and sameColor(hi[1]._color, ui:Color("danger")) and hi[1]._color[4] == 0.12, "danger at 0.12 on hover")
    ok(point(d, "BOTTOMRIGHT")[2] == -20 and point(d, "BOTTOMRIGHT")[3] == 16, "at the bottom right, where the primary sits")
    ok(point(f.cancel, "RIGHT")[2] == d and point(f.cancel, "RIGHT")[3] == "LEFT" and point(f.cancel, "RIGHT")[4] == -10
       and #f.cancel._points == 1, "the secondary just left of it, with no anchor left on the primary")
    ok(d._w == #"Reset" * 6 + 28, "sized to its label")
    ok(f._h == 20 + 15 + 10 + 13 + 20 + 32 + 16, "as tall as any confirm: " .. tostring(f._h))
    env.fire(f, "OnKeyDown", "ENTER")
    ok(accepted == 0 and f:IsShown(), "a stray Enter does not erase anything")
    d:Click()
    ok(accepted == 1 and during == true and not f:IsShown(), "a click accepts, the callback first")
    local cancelled = false
    ui:ShowDialog(confirm({ danger = true, onCancel = function() cancelled = true end }))
    env.fire(f, "OnKeyDown", "ESCAPE")
    ok(cancelled and not f:IsShown(), "Escape cancels it")
end)

case("the danger style is chosen again on every show of the one dialog", function()
    local env, _, ui = setup()
    ui:ShowDialog(confirm({ danger = true }))
    local f = ui._dialog
    ui:ShowDialog(confirm({ button1 = "Save" }))
    ok(f.accept:IsShown() and not f.acceptDanger:IsShown() and f.shownAccept == f.accept, "the next plain confirm is primary again")
    ok(f.accept.text:GetText() == "Save" and f.accept._w == #"Save" * 6 + 28, "with its own label and width")
    ok(point(f.cancel, "RIGHT")[2] == f.accept and #f.cancel._points == 1, "and the secondary beside it")
    ui:ShowDialog(confirm({ danger = false }))
    ok(f.accept:IsShown() and not f.acceptDanger:IsShown(), "danger = false is a plain confirm")
    ui:ShowDialog(confirm({ danger = true, button1 = "Delete" }))
    ok(f.acceptDanger:IsShown() and not f.accept:IsShown() and f.acceptDanger.text:GetText() == "Delete",
       "and danger comes back with its own label")
    ok(point(f.cancel, "RIGHT")[2] == f.acceptDanger, "the secondary following it")
    ui:ShowDialog({ title = "EQ Objective Tracker", text = "Done.", button1 = "OK" })
    ok(f.accept:IsShown() and not f.acceptDanger:IsShown() and not f.cancel:IsShown(), "a one-button dialog is primary")
    ui:ShowDialog(confirm({ danger = true }))
    f.acceptDanger.text._measure = 120
    env.runTimers()
    ok(f.acceptDanger._w == 120 + 28, "the danger button is sized again a frame later too")
end)

case("a button runs its callback with the dialog still up, then hides it", function()
    local env, _, ui = setup()
    local during
    ui:ShowDialog(confirm({ onAccept = function() during = ui._dialog:IsShown() end }))
    ui._dialog.accept:Click()
    ok(during == true, "the primary's callback runs first - a ReloadUI there was blocked when it ran after the hide")
    ok(not ui._dialog:IsShown(), "then the dialog hides")
    local cancelled
    ui:ShowDialog(confirm({ onCancel = function() cancelled = ui._dialog:IsShown() end }))
    ui._dialog.cancel:Click()
    ok(cancelled == true and not ui._dialog:IsShown(), "the secondary the same")
    local accepted, cancelledToo = 0, 0
    ui:ShowDialog(confirm({ onAccept = function() accepted = accepted + 1 end,
                            onCancel = function() cancelledToo = cancelledToo + 1 end }))
    ui._dialog.accept:Click()
    ui._dialog.accept:Click()
    env.fire(ui._dialog, "OnKeyDown", "ESCAPE")
    ok(accepted == 1 and cancelledToo == 0, "a second press after it closed does nothing")
end)

case("a callback that opens the next dialog keeps it on screen", function()
    local _, _, ui = setup()
    local second = { title = "EQ Objective Tracker", text = "Name taken.", button1 = "OK" }
    ui:ShowDialog(confirm({ onAccept = function() ui:ShowDialog(second) end }))
    ui._dialog.accept:Click()
    ok(ui._dialog:IsShown() and ui._dialog.opts == second and ui._dialog.body:GetText() == "Name taken.",
       "the next dialog stays up")
end)

case("a raising callback still closes the dialog and reaches the error handler", function()
    local env, _, ui = setup()
    ui:ShowDialog(confirm({ onAccept = function() error("boom", 0) end }))
    local good = pcall(ui._dialog.accept.Click, ui._dialog.accept)
    ok(good and not ui._dialog:IsShown() and env.errors[1] == "boom", "the primary")
    ui:ShowDialog(confirm({ onCancel = function() error("bang", 0) end }))
    good = pcall(ui._dialog.cancel.Click, ui._dialog.cancel)
    ok(good and not ui._dialog:IsShown() and env.errors[2] == "bang", "and the secondary")
end)

case("the field: what is typed reaches onAccept, with the keyboard already let go", function()
    local env, _, ui = setup()
    for _, route in ipairs({ "button", "enter" }) do
        local got, focusAtCall
        ui:ShowDialog(confirm({ hasEditBox = true, maxLetters = 32, editBoxText = "Default",
                                onAccept = function(text) got = text focusAtCall = env.focus end }))
        local edit = ui._dialog.edit
        ok(edit:IsShown() and edit._maxLetters == 32 and edit:GetText() == "Default" and edit._cursor == 0,
           route .. ": shown with its limit and text, the cursor at the start")
        ok(env.focus == edit, route .. ": and the keyboard")
        edit:SetText("Raid")
        if route == "button" then ui._dialog.accept:Click() else edit:_fire("OnEnterPressed") end
        ok(got == "Raid", route .. ": what was typed reaches onAccept: " .. tostring(got))
        ok(focusAtCall == nil, route .. ": the field let go before the callback ran, so a re-prompt gets the cursor")
    end
    local text = "unset"
    ui:ShowDialog(confirm({ onAccept = function(t) text = t end }))
    ui._dialog.accept:Click()
    ok(text == nil and not ui._dialog.edit:IsShown(), "with no field, onAccept gets nothing")
end)

case("a link to copy opens selected, so Ctrl+C takes it at once", function()
    local env, _, ui = setup()
    ui:ShowDialog({ title = "EQ Objective Tracker",
                    text = "Copy the link below (it's pre-selected \226\128\148 just press Ctrl+C):", button1 = "Close",
                    hasEditBox = true, editBoxText = "https://example.org", highlightEditBox = true })
    local edit = ui._dialog.edit
    ok(ui._dialog.body:IsShown() and not ui._dialog.bodyData:IsShown(),
       "its text keeps Barlow, which draws the dash in it")
    ok(edit:GetText() == "https://example.org" and edit._highlight == true and env.focus == edit,
       "the address selected after the focus, which would drop a selection made before it")
    ok(edit._maxLetters == 0, "with no letter limit when none is asked")
    ui:ShowDialog(confirm({ hasEditBox = true }))
    ok(edit._highlight == false, "a plain prompt opens unselected")
end)

case("the field is drawn as an input in the client's own font", function()
    local env, _, ui = setup()
    ui:ShowDialog(confirm({ hasEditBox = true }))
    local f, edit = ui._dialog, ui._dialog.edit
    ok(edit._type == "EditBox" and edit._autoFocus == false, "an edit box that does not take focus by itself")
    ok(edit._fontObject == env.GameFontHighlight, "in the client's font object, for a name in any alphabet")
    ok(edit._h == 30 and edit._insets[1] == 8 and edit._insets[2] == 8, "30 tall, the text 8 in")
    local fill
    for _, r in ipairs({ edit:GetRegions() }) do if r._layer == "BACKGROUND" and r._color then fill = r end end
    ok(fill and sameColor(fill._color, ui:Color("input")), "on the input fill")
    local rim = 0
    for _, r in ipairs({ edit:GetRegions() }) do
        if r._euiAxis and sameColor(r._color, ui:Color("inputBorder")) then rim = rim + 1 end
    end
    ok(rim == 4, "with an inputBorder edge all round")
    ok(point(edit, "TOPLEFT")[2] == f.body and point(edit, "TOPLEFT")[5] == -14, "14 under the text")
    ok(f._h == 20 + 15 + 10 + 13 + 14 + 30 + 20 + 32 + 16, "and the dialog grows to hold it: " .. tostring(f._h))
    ui:ShowDialog(confirm())
    ok(not edit:IsShown() and env.focus == nil, "a dialog without one hides it and lets the keyboard go")
end)

case("Escape cancels, from the dialog and from its field; Enter never accepts a confirm", function()
    local env, _, ui = setup()
    for _, route in ipairs({ "frame", "field", "enter", "numpad" }) do
        local got = "nothing"
        ui:ShowDialog(confirm({ hasEditBox = (route == "field"),
                                onAccept = function() got = "accepted" end, onCancel = function() got = "cancelled" end }))
        local f = ui._dialog
        if route == "frame" then
            env.fire(f, "OnKeyDown", "ESCAPE")
            ok(f._propagate == false, "Escape is kept from the game")
        elseif route == "field" then
            f.edit:_fire("OnEscapePressed")
        elseif route == "enter" then
            env.fire(f, "OnKeyDown", "ENTER")
            ok(f._propagate == false, "Enter is swallowed rather than opening chat behind the dialog")
        else
            env.fire(f, "OnKeyDown", "NUMPADENTER")
            ok(f._propagate == false, "the keypad's Enter is swallowed too")
        end
        local want = (route == "enter" or route == "numpad") and "nothing" or "cancelled"
        ok(got == want, route .. ": " .. got)
        if got == "nothing" then f.cancel:Click() end
    end
    ui:ShowDialog(confirm())
    env.fire(ui._dialog, "OnKeyDown", "ENTER")
    env.fire(ui._dialog, "OnKeyDown", "W")
    ok(ui._dialog._propagate == true and ui._dialog:IsShown(), "any other key goes on to the game, even after a swallowed Enter")
end)

case("the keyboard waits out combat", function()
    local env, _, ui = setup()
    ui:ShowDialog(confirm())
    local f = ui._dialog
    ok(f._keyboard == true and f._propagate == true, "out of combat it takes the keyboard and passes keys on")
    f:Hide()
    ok(f._keyboard == false, "hidden, it gives the keyboard back")
    env.combat = true
    local got = "nothing"
    ui:ShowDialog(confirm({ onCancel = function() got = "cancelled" end }))
    ok(f._keyboard == false and f._events.PLAYER_REGEN_ENABLED, "opened in combat it waits for combat to end")
    env.fire(f, "OnKeyDown", "ESCAPE")
    ok(got == "nothing", "a key in combat does nothing, the protected call never made")
    env.fire(f, "OnEvent", "PLAYER_REGEN_DISABLED")
    ok(f._events.PLAYER_REGEN_ENABLED and f._keyboard == false, "another event neither arms it nor ends the wait")
    env.fire(f, "OnEvent", "UNIT_AURA")
    ok(f._events.PLAYER_REGEN_ENABLED and f._keyboard == false, "nor does one it never asked for")
    env.combat = false
    env.fire(f, "OnEvent", "PLAYER_REGEN_ENABLED")
    ok(f._keyboard == true and not f._events.PLAYER_REGEN_ENABLED, "and takes the keyboard once it does")
    env.fire(f, "OnKeyDown", "ESCAPE")
    ok(got == "cancelled", "so Escape closes it after the fight")
    env.combat = true
    ui:ShowDialog(confirm())
    f:Hide()
    ok(not f._events.PLAYER_REGEN_ENABLED, "a dialog closed while waiting stops waiting")
    env.combat = false
    env.fire(f, "OnEvent", "PLAYER_REGEN_DISABLED")
    ok(f._keyboard == false, "and another event arms nothing")
end)

case("combat starting hands the keyboard back, and it is taken again after", function()
    local env, _, ui = setup()
    ui:ShowDialog(confirm())
    local f = ui._dialog
    ok(f._events.PLAYER_REGEN_DISABLED == true, "an open dialog listens for combat starting")
    env.fire(f, "OnKeyDown", "ENTER")
    ok(f._keyboard == true and f._propagate == false, "a swallowed Enter leaves it passing no key on")
    env.fire(f, "OnEvent", "PLAYER_REGEN_DISABLED")
    ok(f._keyboard == false, "combat starting lets go of the keyboard, so no key is kept from the fight")
    ok(f._events.PLAYER_REGEN_ENABLED == true, "and waits for the fight to end")
    env.combat = true
    env.fire(f, "OnKeyDown", "W")
    ok(f:IsShown() and f._keyboard == false, "a key in combat makes no protected call")
    env.combat = false
    env.fire(f, "OnEvent", "PLAYER_REGEN_ENABLED")
    ok(f._keyboard == true and f._propagate == true and not f._events.PLAYER_REGEN_ENABLED,
       "after the fight it takes the keyboard again, passing keys on")
    f:Hide()
    ok(f._events.PLAYER_REGEN_DISABLED == nil and f._keyboard == false, "closed, it stops listening")
end)

case("text Barlow cannot draw is drawn in the client's font, and the field sits under it", function()
    local env, _, ui = setup()
    local cyrillic = "\208\154\208\178\208\181\209\129\209\130"
    ui:ShowDialog(confirm({ text = "A profile named \"" .. cyrillic .. "\" already exists.", hasEditBox = true }))
    local f = ui._dialog
    ok(f.bodyData:IsShown() and not f.body:IsShown(), "a profile name in Cyrillic goes to the client-font string")
    ok(f.bodyData:GetText() == "A profile named \"" .. cyrillic .. "\" already exists.", "carrying the whole text")
    ok(f.bodyData._fontObject == env.GameFontHighlight and f.bodyData._font[1] == "OBJECT"
       and sameColor(f.bodyData._textColor, ui:Color("label"))
       and f.bodyData._wrap == true, "in the client's font object, the label color, wrapping")
    local tl = point(f.bodyData, "TOPLEFT")
    ok(tl[2] == f.title and tl[5] == -10 and point(f.bodyData, "TOPRIGHT")[2] == f.title,
       "in the body's place under the title")
    ok(point(f.edit, "TOPLEFT")[2] == f.bodyData and point(f.edit, "TOPRIGHT")[2] == f.bodyData,
       "the field hangs under the string that is shown")
    f.bodyData._measureH = 40
    ui:ShowDialog(confirm({ text = cyrillic, hasEditBox = true }))
    ok(f._h == 20 + 15 + 10 + 40 + 14 + 30 + 20 + 32 + 16, "the height follows the shown string: " .. tostring(f._h))
    ui:ShowDialog(confirm({ hasEditBox = true }))
    ok(f.body:IsShown() and not f.bodyData:IsShown(), "the next Latin text is back on Barlow")
    ok(point(f.edit, "TOPLEFT")[2] == f.body and #f.edit._points == 2, "with the field under it, and no anchor left behind")
    ui:ShowDialog(confirm({ title = "Overwrite profile?", text = "A profile named \"" .. cyrillic .. "\" already exists." }))
    ok(f.bodyData:IsShown() and not f.body:IsShown(), "a confirm with no field takes the client's font too")
    local other = "\208\148\209\128\209\131\208\179\208\190\208\185"
    ui:ShowDialog(confirm({ text = other }))
    ok(f.bodyData:GetText() == other, "and the next one shows its own text, not the last one's")
end)

case("a dialog keeps letting go of the keyboard fight after fight, and on every show", function()
    local env, _, ui = setup()
    ui:ShowDialog(confirm())
    local f = ui._dialog
    env.fire(f, "OnEvent", "PLAYER_REGEN_DISABLED")
    env.fire(f, "OnEvent", "PLAYER_REGEN_ENABLED")
    ok(f._keyboard == true and f._events.PLAYER_REGEN_DISABLED == true, "after one fight it still listens for the next")
    env.fire(f, "OnEvent", "PLAYER_REGEN_DISABLED")
    ok(f._keyboard == false, "and lets go again when the second starts")
    env.fire(f, "OnEvent", "PLAYER_REGEN_ENABLED")
    f:Hide()
    ui:ShowDialog(confirm())
    ok(f._events.PLAYER_REGEN_DISABLED == true, "a dialog shown again listens again")
    f:Hide()
    env.combat = true
    ui:ShowDialog(confirm())
    ok(f._events.PLAYER_REGEN_DISABLED == true, "one opened in combat listens for the next fight too")
    env.combat = false
    env.fire(f, "OnEvent", "PLAYER_REGEN_ENABLED")
    ok(f._keyboard == true and f._events.PLAYER_REGEN_DISABLED == true, "and still listens once it has the keyboard")
end)

case("a dialog opened over another cancels it, so no callback is dropped", function()
    local _, _, ui = setup()
    local first = "nothing"
    local nextOne = { title = "EQ Objective Tracker", text = "Next.", button1 = "OK" }
    ui:ShowDialog(confirm({ onAccept = function() first = "accepted" end, onCancel = function() first = "cancelled" end }))
    ui:ShowDialog(nextOne)
    ok(first == "cancelled" and ui._dialog:IsShown() and ui._dialog.opts == nextOne, "the first is cancelled: " .. first)
end)

case("each addon has its own dialog, in its own accent", function()
    local _, _, ui, newCtx = setup()
    local other = newCtx({ 0.165, 0.447, 0.682 })
    ui:ShowDialog(confirm())
    other:ShowDialog(confirm())
    ok(ui._dialog and other._dialog and ui._dialog ~= other._dialog, "two contexts, two dialogs")
    ok(ui._dialog:IsShown() and other._dialog:IsShown(), "one does not close the other")
    local fill
    for _, r in ipairs({ other._dialog.accept:GetRegions() }) do if r._layer == "BACKGROUND" and r._color then fill = r end end
    ok(fill and sameColor(fill._color, other:Color("accent")), "the primary in that addon's accent")
end)

case("text measured before the dialog was on screen is sized again a frame later", function()
    local env, _, ui = setup()
    ui:ShowDialog(confirm())
    local f = ui._dialog
    f.body._measureH = 52
    f.accept.text._measure = 120
    env.runTimers()
    ok(f._h == 20 + 15 + 10 + 52 + 20 + 32 + 16, "the height follows the wrapped text: " .. tostring(f._h))
    ok(f.accept._w == 120 + 28, "and the button its label")
    env.stringHeight = 0
    f.body._measureH = nil
    ui:ShowDialog(confirm())
    ok(f._h == 20 + 15 + 10 + 13 + 20 + 32 + 16, "an unmeasured title and text still take their font sizes: " .. tostring(f._h))
    f:Hide()
    f.body._measureH = 200
    env.runTimers()
    ok(f._h < 200, "a dialog closed before the frame passed is left alone")
end)

case("ShowDialog checks what it is given, and the error names the caller", function()
    local _, _, ui = setup()
    ok(not pcall(ui.ShowDialog, ui, { title = "T", text = "X" }), "no button1 is refused")
    ok(not pcall(ui.ShowDialog, ui, { text = "X", button1 = "OK" }), "no title is refused")
    ok(not pcall(ui.ShowDialog, ui, confirm({ onAcept = function() end })), "a misspelled field is refused")
    ok(not pcall(ui.ShowDialog, ui, confirm({ hasEditBox = "yes" })), "a field of the wrong type is refused")
    ok(not pcall(ui.ShowDialog, ui, confirm({ danger = "yes" })), "danger must be a boolean")
    ok(not pcall(ui.ShowDialog, ui, confirm({ dangerous = true })), "and a misspelling of it is refused")
    ok(pcall(ui.ShowDialog, ui, confirm({ danger = true })), "danger itself is accepted")
    local good, err = pcall(function()
        local r = ui:ShowDialog({ title = "T", text = "X" })
        return r
    end)
    ok(not good and tostring(err):find("test_dialog.lua", 1, true) ~= nil, "pointing at the caller: " .. tostring(err))
end)

print(("test_dialog: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end

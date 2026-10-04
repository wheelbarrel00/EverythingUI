-- Run with Lua 5.1 from any folder: lua5.1 tests/test_load.lua

local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."

local function readFile(rel)
    local fh = assert(io.open(root .. "/" .. rel, "rb"))
    local s = fh:read("*a")
    fh:close()
    return s
end

local function exists(rel)
    local fh = io.open(root .. "/" .. rel, "rb")
    if fh then fh:close() return true end
    return false
end

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

local function toHex(c)
    return ("%02X%02X%02X"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
                                   math.floor(c[3] * 255 + 0.5))
end

local function snapshot(t)
    local s = {}
    for k, v in pairs(t) do s[k] = v end
    return s
end

local function same(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

local scripts = {}
for file in readFile("EverythingUI.xml"):gmatch('<Script%s+file="([^"]+)"') do
    scripts[#scripts + 1] = file
end

local sources = {}
for _, name in ipairs(scripts) do sources[name] = readFile(name) end

local MINOR_PATTERN = '(local MAJOR, MINOR = "EverythingUI%-1%.0", )(%d+)'
local BASE = tonumber(select(2, sources["EverythingUI.lua"]:match(MINOR_PATTERN)))
local CLIENT = "Fonts\\CLIENT_FONT.TTF"

-- Mirrors LibStub's own NewLibrary and GetLibrary, since which copy wins is decided there.
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

local STD = {
    "assert", "error", "ipairs", "next", "pairs", "pcall", "rawget", "rawset", "select",
    "setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "xpcall",
    "string", "table", "math",
}

-- One session is one game client: every copy loaded into it shares one LibStub. Globals the
-- library reads but this does not stub come back nil, as an absent API does in game.
local function newSession(locale, clientFont)
    local s = { frames = 0, LibStub = newLibStub() }
    local env = {
        LibStub = s.LibStub,
        GetLocale = function() return locale end,
        CreateFrame = function() s.frames = s.frames + 1 return {} end,
        STANDARD_TEXT_FONT = clientFont,
    }
    for _, k in ipairs(STD) do env[k] = _G[k] end
    s.env = setmetatable(env, {
        __newindex = function(_, k) error("the library set a global: " .. tostring(k), 2) end,
    })
    return s
end

local function loadCopy(session, host, minor, probe)
    for _, name in ipairs(scripts) do
        local src = sources[name]
        if name == "EverythingUI.lua" and minor then
            local n
            src, n = src:gsub(MINOR_PATTERN, function(prefix) return prefix .. minor end)
            assert(n == 1, "MINOR line not found")
        end
        if name == "Context.lua" and probe then
            src = src .. "\nfunction Context:ProbeMinor() return " .. probe .. " end\n"
        end
        local chunk = assert(loadstring(src, "@" .. name))
        setfenv(chunk, session.env)
        chunk(host, {})
    end
    return session.LibStub("EverythingUI-1.0", true)
end

local NIL = {}

local function goodOpts(extra)
    local o = {
        id = "EQOT", title = "EQ Objective Tracker", version = "1.28.0",
        accent = { 0.784, 0.216, 0.243 }, L = {}, tooltip = function() end,
        discord = function() end, getLastTab = function() end, setLastTab = function() end,
        labels = { discord = "Join our Discord!" },
    }
    for k, v in pairs(extra or {}) do
        if v == NIL then o[k] = nil else o[k] = v end
    end
    return o
end

local function mediaPath(host)
    return "Interface\\AddOns\\" .. host .. "\\Libs\\EverythingUI\\Media\\"
end

case("the XML and the files it names", function()
    ok(scripts[1] == "EverythingUI.lua", "EverythingUI.lua loads first: " .. tostring(scripts[1]))
    local at = {}
    for i, name in ipairs(scripts) do at[name] = i end
    ok(at["Tokens.lua"] and at["Context.lua"] and at["Tokens.lua"] < at["Context.lua"],
       "Tokens.lua loads before Context.lua")
    for _, name in ipairs(scripts) do
        local chunk, err = loadstring(sources[name], "@" .. name)
        ok(chunk ~= nil, name .. " compiles under Lua 5.1: " .. tostring(err))
    end
    for i = 2, #scripts do
        local head = sources[scripts[i]]:match("^(.-\n.-\n.-)\n")
        ok(head == 'local addonName = ...\nlocal lib = LibStub("EverythingUI-1.0")\n'
                   .. "if lib.host ~= addonName then return end",
           scripts[i] .. " opens with the host check, so a losing copy changes nothing")
    end
    ok(BASE ~= nil, "MINOR is readable from EverythingUI.lua")
end)

case("a first copy loads", function()
    local s = newSession("enUS", CLIENT)
    local lib, minor = loadCopy(s, "HostA")
    ok(lib ~= nil and minor == BASE, "LibStub holds the library at MINOR " .. tostring(BASE))
    ok(lib.host == "HostA", "the host is the folder name from ...")
    ok(lib.media == mediaPath("HostA"), "the media path is built from the host: " .. tostring(lib.media))
    ok(type(lib.NewContext) == "function" and type(lib.Context) == "table"
       and type(lib.contextMeta) == "table" and lib.contextMeta.__index == lib.Context,
       "NewContext, the methods table and the metatable exist")
    ok(s.frames == 0, "no frame is built while the files load")
end)

case("tokens match section 4 of the design spec", function()
    local lib = loadCopy(newSession("enUS", CLIENT), "HostA")
    local t = lib.tokens
    local DESIGN = {
        bg = { 0.071, 0.078, 0.094 }, chrome = { 0.055, 0.063, 0.075 },
        surface = { 0.090, 0.102, 0.122 }, surfaceBorder = { 0.137, 0.153, 0.180 },
        divider = { 0.125, 0.141, 0.165 }, input = { 0.059, 0.067, 0.078 },
        inputBorder = { 0.165, 0.180, 0.208 }, borderStrong = { 0.227, 0.247, 0.282 },
        track = { 0.180, 0.196, 0.227 }, text = { 0.910, 0.918, 0.929 },
        label = { 0.769, 0.784, 0.808 }, navText = { 0.639, 0.659, 0.690 },
        muted = { 0.545, 0.565, 0.596 }, danger = { 1, 0.314, 0.314 }, hover = { 1, 1, 1 },
    }
    for name, want in pairs(DESIGN) do
        local c = t.colors[name]
        ok(c and near(c[1], want[1]) and near(c[2], want[2]) and near(c[3], want[3]), "color " .. name)
    end
    for name in pairs(t.colors) do ok(DESIGN[name] ~= nil, "color " .. name .. " is in the spec") end
    ok(t.alpha.bg == 0.97 and t.alpha.accentSoft == 0.18 and t.alpha.dangerSoft == 0.12 and t.alpha.hover == 0.06,
       "alphas")
    ok(t.accentHiMix == 0.35, "accentHi moves 35% toward white")

    local ACCENTS = {
        EQOT = { "C8373E", "FFFFFF" }, EQ = { "C8373E", "FFFFFF" }, ED = { "2A72AE", "FFFFFF" },
        CDM = { "D9A520", "16181C" }, LootPro = { "27795A", "FFFFFF" },
    }
    for id, want in pairs(ACCENTS) do
        local a = t.accents[id]
        ok(a and toHex(a.accent) == want[1] and toHex(a.accentText) == want[2], "accent " .. id)
    end
    ok(t.accents.EQ.accent ~= t.accents.EQOT.accent, "no two addons share one accent table")

    local TYPE = {
        title = { 15, "SemiBold", "text" }, nav = { 13, "Medium", "navText" },
        navActive = { 13, "SemiBold", "text" }, label = { 13, "Regular", "label" },
        value = { 13, "Medium", "text" }, groupLabel = { 12, "SemiBold", "muted" },
        hint = { 12, "Regular", "muted" }, segment = { 12, "SemiBold", "navText" },
    }
    for name, want in pairs(TYPE) do
        local ty = t.typography[name]
        ok(ty and ty.size == want[1] and ty.weight == want[2] and ty.color == want[3], "type " .. name)
    end
    ok(t.fontFlags == "" and t.shadowOffset == 0, "no outline and no shadow offset")

    local SPACING = {
        windowWidth = 1100, windowHeight = 720, headerHeight = 48, sidebarWidth = 196,
        footerHeight = 56, previewWidth = 320, navItemHeight = 36, navItemPadding = 12,
        navItemGap = 2, contentTop = 20, contentSides = 24, groupGap = 22, groupLabelGap = 8,
        rowHeight = 44, dependentRowHeight = 40, listRowHeight = 28, rowPadding = 14, dependentIndent = 40,
        labelColumn = 150, valueColumn = 44, checkbox = 16, swatchWidth = 34, swatchHeight = 22,
        buttonHeight = 32, segmentHeight = 26, border = 1,
        fieldHeight = 30, controlGap = 14, checkboxGap = 10, buttonGap = 10, trackHeight = 3,
        thumbWidth = 8, thumbHeight = 15, chevron = 12, segmentPadding = 14, segmentGap = 2,
        popupRowHeight = 22, popupMaxRows = 10, menuItemHeight = 24,
    }
    for name, want in pairs(SPACING) do ok(t.spacing[name] == want, "spacing " .. name) end
    for name in pairs(t.spacing) do ok(SPACING[name] ~= nil, "spacing " .. name .. " is in the spec") end
end)

case("fonts follow the client locale", function()
    for _, loc in ipairs({ "enUS", "enGB", "deDE", "frFR", "esES", "esMX", "ptBR", "itIT" }) do
        local lib = loadCopy(newSession(loc, CLIENT), "HostA")
        local f = lib.tokens.fonts
        ok(f.Regular == mediaPath("HostA") .. "Fonts\\Barlow-Regular.ttf"
           and f.Medium == mediaPath("HostA") .. "Fonts\\Barlow-Medium.ttf"
           and f.SemiBold == mediaPath("HostA") .. "Fonts\\Barlow-SemiBold.ttf",
           loc .. " uses Barlow")
    end
    for _, loc in ipairs({ "ruRU", "koKR", "zhCN", "zhTW" }) do
        local lib = loadCopy(newSession(loc, CLIENT), "HostA")
        local f = lib.tokens.fonts
        ok(f.Regular == CLIENT and f.Medium == CLIENT and f.SemiBold == CLIENT,
           loc .. " uses the client font for every weight")
    end
    local lib = loadCopy(newSession("koKR", nil), "HostA")
    ok(lib.tokens.fonts.Regular == "Fonts\\FRIZQT__.TTF", "a client with no STANDARD_TEXT_FONT falls back")
    for _, weight in ipairs({ "Regular", "Medium", "SemiBold" }) do
        ok(exists("Media/Fonts/Barlow-" .. weight .. ".ttf"), "Barlow-" .. weight .. ".ttf is on disk")
    end
    ok(exists("Media/Fonts/OFL.txt"), "the font license is on disk")
end)

case("NewContext keeps validated opts", function()
    local lib = loadCopy(newSession("enUS", CLIENT), "HostA")
    local opts = goodOpts()
    local ctx = lib:NewContext(opts)
    ok(getmetatable(ctx) == lib.contextMeta, "the context resolves through the shared metatable")
    ok(ctx.opts.id == "EQOT" and ctx.opts.L == opts.L and ctx.opts.tooltip == opts.tooltip
       and ctx.opts.getLastTab == opts.getLastTab, "opts are kept")
    ok(ctx.opts ~= opts and ctx.opts.accent ~= opts.accent, "opts and the accent are copied")
    opts.accent[1] = 0
    local r, g, b, a = ctx:Color("accent")
    ok(near(r, 0.784) and near(g, 0.216) and near(b, 0.243) and a == 1, "accent, unchanged by the host's table")
    local sr, _, _, sa = ctx:Color("accentSoft")
    ok(near(sr, 0.784) and sa == 0.18, "accentSoft is the accent at 0.18")
    local dr, dg, db, da = ctx:Color("dangerSoft")
    ok(near(dr, 1) and near(dg, 0.314) and near(db, 0.314) and da == 0.12, "dangerSoft is danger at 0.12, whatever the accent")
    r, g, b = ctx:Color("accentHi")
    ok(near(r, 0.784 + 0.216 * 0.35) and near(g, 0.216 + 0.784 * 0.35) and near(b, 0.243 + 0.757 * 0.35),
       "accentHi is 35% toward white")
    r, g, b, a = ctx:Color("accentText")
    ok(r == 1 and g == 1 and b == 1 and a == 1, "accentText defaults to white")
    local br, _, _, ba = ctx:Color("bg")
    ok(near(br, 0.071) and ba == 0.97, "bg carries its alpha")
    r, g, b, a = ctx:Color("hover")
    ok(r == 1 and g == 1 and b == 1 and a == 0.06, "hover is white at 0.06")
    ok(not pcall(ctx.Color, ctx, "nope"), "an unknown color raises")

    local dark = lib:NewContext(goodOpts({ id = "CDM", accent = { 0.851, 0.647, 0.125 },
                                           accentText = { 0.086, 0.094, 0.110 } }))
    r, g, b = dark:Color("accentText")
    ok(near(r, 0.086) and near(g, 0.094) and near(b, 0.110), "a given accentText is used")

    local file, size, flags = ctx:Font("title")
    ok(file == lib.tokens.fonts.SemiBold and size == 15 and flags == "", "Font returns file, size and flags")
    file, size = ctx:Font("label")
    ok(file == lib.tokens.fonts.Regular and size == 13, "label is 13 Regular")
    ok(not pcall(ctx.Font, ctx, "nope"), "an unknown type style raises")

    local bare = lib:NewContext(goodOpts({ discord = NIL, getLastTab = NIL, setLastTab = NIL, labels = NIL }))
    ok(bare.opts.discord == nil and bare.opts.getLastTab == nil, "the optional fields are optional")
    ok(type(bare.opts.labels) == "table" and next(bare.opts.labels) == nil, "no labels keeps an empty table")
    local given = { discord = "Join", discordTip = "Tip" }
    local labelled = lib:NewContext(goodOpts({ labels = given }))
    ok(labelled.opts.labels ~= given and labelled.opts.labels.discord == "Join"
       and labelled.opts.labels.discordTip == "Tip", "labels are copied and kept")
    ok(ctx:Texture("check") == mediaPath("HostA") .. "Textures\\check", "Texture resolves inside the media path")
end)

case("NewContext rejects bad opts", function()
    local lib = loadCopy(newSession("enUS", CLIENT), "HostA")
    local function rejects(opts, needle, label)
        -- Not a tail call: one would drop this frame and leave the error with no position.
        local good, err = pcall(function() local ctx = lib:NewContext(opts) return ctx end)
        ok(not good and tostring(err):find(needle, 1, true) ~= nil, label .. ": " .. tostring(err))
        return err
    end
    for _, key in ipairs({ "id", "title", "version", "accent", "L", "tooltip" }) do
        rejects(goodOpts({ [key] = NIL }), "needs opts." .. key, "missing " .. key)
    end
    rejects(goodOpts({ id = 5 }), "opts.id must be a string", "id not a string")
    rejects(goodOpts({ version = 1.28 }), "opts.version must be a string", "version not a string")
    rejects(goodOpts({ L = "x" }), "opts.L must be a table", "L not a table")
    rejects(goodOpts({ tooltip = {} }), "opts.tooltip must be a function", "tooltip not a function")
    rejects(goodOpts({ discord = "x" }), "opts.discord must be a function", "discord not a function")
    rejects(goodOpts({ accent = { 0.5, 0.5 } }), "opts.accent must be", "accent missing a channel")
    rejects(goodOpts({ accent = { 200, 55, 62 } }), "opts.accent must be", "accent in 0-255")
    rejects(goodOpts({ accentText = "white" }), "opts.accentText must be", "accentText not rgb")
    rejects(goodOpts({ toolTip = function() end }), "unknown opts.toolTip", "a misspelled key")
    rejects(goodOpts({ setLastTab = NIL }), "come as a pair", "getLastTab without setLastTab")
    rejects(goodOpts({ getWindowScale = function() end }), "come as a pair", "getWindowScale without setWindowScale")
    rejects(goodOpts({ labels = NIL }), "opts.discord needs opts.labels.discord", "discord with no label")
    rejects(goodOpts({ labels = { discord = "x", clearr = "y" } }), "unknown opts.labels.clearr", "a misspelled label")
    rejects(goodOpts({ labels = { discord = 5 } }), "opts.labels.discord must be a string", "a label that is not a string")
    rejects(goodOpts({ labels = "x" }), "opts.labels must be a table", "labels not a table")
    local err = rejects(nil, "expects an opts table", "no opts at all")
    ok(tostring(err):find("test_load.lua", 1, true) ~= nil, "the error points at the caller: " .. tostring(err))
end)

case("an older or equal copy loading after a newer one changes nothing", function()
    local s = newSession("enUS", CLIENT)
    local lib = loadCopy(s, "HostA", BASE)
    local ctx = lib:NewContext(goodOpts())
    local libBefore, methods, meta = snapshot(lib), snapshot(lib.Context), snapshot(lib.contextMeta)
    local tokens, colors = lib.tokens, lib.tokens.colors
    for _, older in ipairs({ BASE - 1, BASE }) do
        local lib2, minor = loadCopy(s, "HostB", older, older)
        ok(lib2 == lib and minor == BASE, "LibStub still holds MINOR " .. BASE .. " after " .. older)
        ok(same(libBefore, snapshot(lib)), "no library field changed after " .. older)
        ok(same(methods, snapshot(lib.Context)), "no context method changed after " .. older)
        ok(same(meta, snapshot(lib.contextMeta)), "the metatable did not change after " .. older)
        ok(lib.tokens == tokens and lib.tokens.colors == colors, "the tokens did not change after " .. older)
        ok(lib.host == "HostA", "the host is still the winner after " .. older)
        ok(ctx.ProbeMinor == nil, "the losing copy's Context.lua never ran after " .. older)
    end
    ok(s.frames == 0, "no frame was built")
end)

case("a newer copy replaces the methods an existing context sees", function()
    local s = newSession("enUS", CLIENT)
    local lib = loadCopy(s, "HostA", BASE)
    local ctx = lib:NewContext(goodOpts())
    local oldColor, oldFont, oldNew = ctx.Color, ctx.Font, lib.NewContext
    local Context, meta, tokens = lib.Context, lib.contextMeta, lib.tokens
    ok(ctx.ProbeMinor == nil, "the probe is not there before the upgrade")

    local lib2, minor = loadCopy(s, "HostC", BASE + 1, BASE + 1)
    ok(lib2 == lib and minor == BASE + 1, "LibStub hands back the same table at the new MINOR")
    ok(lib.host == "HostC" and lib.media == mediaPath("HostC"), "the winner's host and media path")
    ok(lib.Context == Context and lib.contextMeta == meta and getmetatable(ctx) == meta,
       "one methods table and one metatable across copies")
    ok(ctx.Color ~= oldColor and ctx.Color == lib.Context.Color, "the context reaches the newer Color")
    ok(ctx.Font ~= oldFont and ctx.Font == lib.Context.Font, "the context reaches the newer Font")
    ok(lib.NewContext ~= oldNew, "NewContext is the newer copy's")
    ok(ctx.ProbeMinor and ctx:ProbeMinor() == BASE + 1, "a method only the newer copy has reaches the old context")
    ok(lib.tokens ~= tokens and ctx:Font("label") == mediaPath("HostC") .. "Fonts\\Barlow-Regular.ttf",
       "the old context reads the newer copy's tokens")
    local r = ctx:Color("accent")
    ok(near(r, 0.784), "the old context keeps its own opts")

    loadCopy(s, "HostD", BASE, BASE)
    ok(lib.host == "HostC" and ctx:ProbeMinor() == BASE + 1, "an older copy after the upgrade changes nothing")
    ok(s.frames == 0, "no frame was built")
end)

case("a host that loads its own copy twice keeps working", function()
    local s = newSession("enUS", CLIENT)
    local lib = loadCopy(s, "HostA", BASE)
    local ctx = lib:NewContext(goodOpts())
    loadCopy(s, "HostA", BASE)
    local _, minor = s.LibStub("EverythingUI-1.0")
    ok(minor == BASE and lib.host == "HostA", "still MINOR " .. BASE .. " from HostA")
    local r = ctx:Color("accent")
    ok(near(r, 0.784) and ctx:Font("title") == lib.tokens.fonts.SemiBold, "the context still answers")
end)

print(("test_load: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end

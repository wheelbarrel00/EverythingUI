std = "lua51"
max_line_length = false
-- Methods take self for the colon call even when they read only the library.
self = false

-- The library creates no globals. Every WoW name it reads is listed here, so a new one fails
-- lint until it is added on purpose. UISpecialFrames is deliberately never listed.
read_globals = {
    "LibStub",
    "GetLocale",
    "STANDARD_TEXT_FONT",
    "GameFontHighlight",
    "CreateFrame",
    "UIParent",
    "InCombatLockdown",
    "C_Timer",
    "PixelUtil",
    "GetPhysicalScreenSize",
    "geterrorhandler",
    "GetCursorPosition",
    -- Classic's picker is driven by assigning its callbacks and opacity onto the frame itself.
    ColorPickerFrame = {
        other_fields = true,
        fields = {
            func = { read_only = false }, opacityFunc = { read_only = false },
            cancelFunc = { read_only = false }, hasOpacity = { read_only = false },
            opacity = { read_only = false },
        },
    },
    "OpacitySliderFrame",
    "C_AddOns",
    "UnitClass",
    "RAID_CLASS_COLORS",
}

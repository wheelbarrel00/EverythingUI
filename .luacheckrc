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
}

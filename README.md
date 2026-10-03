# EverythingUI

The shared UI library for Wheelbarrel00's World of Warcraft addons: one flat, dark look, with an accent color per addon. It loads through LibStub as `EverythingUI-1.0` on retail, Classic Era, TBC Anniversary, Mists and WoW Forever.

## How an addon gets it

Each addon vendors a copy at `Libs/EverythingUI/` and commits it, so a fresh checkout loads in game with no build step. Its TOC loads `Libs\EverythingUI\EverythingUI.xml` right after LibStub.

```
python sync.py                  # dry run for every addon in addons.py
python sync.py EQOT             # dry run for one addon
python sync.py EQOT --write     # copy it
```

`sync.py` never runs git. Line endings alone never count as a difference.

## Versioning

MINOR in `EverythingUI.lua` goes up on every change, and the newest copy loaded wins for every addon in the session. `sync.py` refuses to write a changed library whose MINOR was not raised. Within `EverythingUI-1.0` the API only grows: no function, parameter meaning or media file name is ever removed or changed.

## Checks

```
luacheck .
lua5.1 tests/test_load.lua
lua5.1 tests/test_window.lua
lua5.1 tests/test_controls.lua
lua5.1 tests/test_card.lua
lua5.1 tests/test_color_picker.lua
lua5.1 tests/test_dialog.lua
lua5.1 tests/test_menu.lua
python tests/mutate.py
```

`tests/mutate.py` breaks one line of a scratch copy at a time and requires some test to fail for each.

`python tools/make_textures.py` regenerates `Media/Textures/` and needs Pillow.

## Credits

Barlow by The Barlow Project Authors, from google/fonts `ofl/barlow` at commit `6cdf018`, under the SIL Open Font License 1.1 (`Media/Fonts/OFL.txt`).

## License

MIT. See `LICENSE`.

# Notes for Claude

SwingCast: extends the standard player cast bar for WoW Forever (Lua 5.1). Author and rights holder: Bencepo. All rights reserved, no open-source license.

## Layout

- `SwingCast.lua`: everything (cast bar additions, swing strip, options window, minimap button, events). `/swc` opens the options.
- `Icons/minimap.tga`: in-game icon from the Bencepo logo family. `media/logo.png`: logo for CurseForge, Wago and the website (not packaged).
- `Libs/`: LibStub, CallbackHandler, LibDataBroker, LibDBIcon, BencepoUI. The options window is its own frame (BencepoUI, like the other Bencepo addons; `opts.bugUrl` gives the "Report a bug" button).
- `Libs/BencepoUI` is shared by all Bencepo addons and must be the same file in each (canonical copy: minor 4, Nov 2026). LibStub loads only the highest minor, so two different copies with the same minor make the result depend on load order. Change it in one repo, bump the minor, copy it to the others.

## How it works

- Adds to Blizzard's cast bar instead of replacing it: spell icon, remaining cast time, latency zone.
- The swing strip mirrors Forever's built-in swing timer (Blizzard_SwingTimer): Forever keeps the combat log from addons, so that timer is the only accurate source. The built-in timer must be on (Options > Advanced > Swing Timer); its own bars can be hidden.
- The strip is tinted while an on-next-swing ability (Maul, Heroic Strike, Cleave, Raptor Strike) is queued.
- Some combat values arrive as secret values: pass them through, never compare or do math on them.
- Height, font, font size and colours are adjustable (Ben asked for this). Energy ticks are not needed: energy regenerates continuously in Forever.
- Moving is done in Edit Mode (hooked) or the unlock button.

## Rules

- English only: UI texts, commands, descriptions. No translations, no `Notes-xxXX` in the .toc. Settings in a window of its own, not Blizzard's options.
- CI runs luacheck and LuaLS with the WoW API annotations; LuaLS must report zero diagnostics or the release stops.
- Release: new version heading at the top of `CHANGELOG.md`, push to `main`; the workflow uploads to CurseForge and Wago. Test in game first.

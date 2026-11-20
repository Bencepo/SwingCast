# SwingCast

A small addon for WoW Forever that adds to the standard player cast bar instead of replacing it.

**Website and live demo:** https://bencepo.github.io/swingcast/

- **Spell icon** inside the cast bar at its left end, or left of it
- **Remaining cast time** on the bar
- **Latency zone** at the end of the bar: once the bar reaches it, the next spell can be pressed
- **Swing timer** as a thin strip right under the cast bar, with seconds to the next swing
- **Queued swing:** the strip turns orange while Maul, Heroic Strike or Raptor Strike is queued, blue for Cleave

## Before you start

SwingCast mirrors Forever's built-in swing timer, so it has to be switched on:
**Options > Advanced Options > Swing Timer.**

## Settings

Everything is set in SwingCast's own window, no commands needed. Drag it anywhere: it stays open while you play, so every change shows live, and the swing strip shows a preview meanwhile.

- **`/swc`**
- **Minimap button:** left-click opens the window, right-click shows an 8 s preview
- **Addon menu** next to the minimap, with the same clicks
- **Options > AddOns > SwingCast** points to the window

What you can change:

- Show or hide spell icon, cast time, latency zone, swing strip and its seconds
- Hide the built-in swing bars
- Strip height
- Position: under the cast bar, or anywhere you drag it: in the game's Edit Mode, or with "Move strip" in the window (right-click to lock), with its own width
- Font and font size
- Colours of the swing strip, the queued swing, Cleave and the latency zone (game colour picker, with reset)

## How it works

The swing strip mirrors Forever's built-in swing timer (`Blizzard_SwingTimer`). That timer is the only accurate source, because Forever keeps the combat log from addons and hands combat values such as the attack speed to addons as secret values. SwingCast copies the built-in bar's values and its seconds label as they are and hides the built-in bar's look. If another addon hides or replaces the standard cast bar, the strip moves to its own position. If the strip ever fails, it switches itself off and the built-in bar is shown again.

## Advanced: chat commands

Everything above is also available as a command. `/swc help` lists the settings, each one is switched with `/swc <setting>`:

| Setting | |
|---|---|
| `icon` | spell icon |
| `iconInside` | spell icon inside the cast bar (off: left of it) |
| `time` | cast time |
| `latency` | latency zone |
| `swing` | swing strip |
| `swingText` | seconds on the swing strip |
| `hideNative` | hide the built-in swing bars |
| `attach` | swing strip under the cast bar or at its own position |

`/swc` opens the window, `/swc minimap` hides or shows the minimap button, `/swc unlock` lets you drag the swing strip anywhere (right-click or `/swc lock` to lock), `/swc width <60-600>` sets its width there, `/swc position reset` puts it back under the cast bar, `/swc height <2-20>` sets the strip height, `/swc font <7-20>` the font size, `/swc color swing|queued|cleave|latency|reset` opens the colour picker, `/swc test` shows an 8 s preview, `/swc reset` restores the defaults.


## Feedback and bug reports

Found a bug or have an idea? [Open an issue](https://github.com/Bencepo/SwingCast/issues/new/choose), it takes a minute. For bugs the Lua error text (from BugSack, or `/console scriptErrors 1`) and your SwingCast version help the most. No GitHub account? Comment on [CurseForge](https://www.curseforge.com/wow/addons/swingcast#comments). Every report gets read.

## More addons by Bencepo

All addons, live demos and the web pages: **https://bencepo.github.io**

Like the addons? Support them on Ko-fi: **https://ko-fi.com/bencepo**

## AI disclosure

The code was written with the help of an AI assistant (Claude). Bencepo designed the features, tests everything in game and maintains the addon.

## License

All rights reserved, see [LICENSE](LICENSE).

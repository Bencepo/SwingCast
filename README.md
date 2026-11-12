# SwingCast

A small addon for WoW Forever that adds to the standard player cast bar instead of replacing it.

- **Spell icon** left of the cast bar
- **Remaining cast time** on the bar
- **Latency zone** at the end of the bar: once the bar reaches it, the next spell can be pressed
- **Swing timer** as a thin strip right under the cast bar, with seconds to the next swing
- **Queued swing:** the strip turns orange while Maul, Heroic Strike or Raptor Strike is queued, blue for Cleave

## Before you start

SwingCast mirrors Forever's built-in swing timer, so it has to be switched on:
**Options > Advanced Options > Swing Timer.**

## Settings

Everything is set with buttons and sliders, no commands needed:

- **Options > AddOns > SwingCast**
- **Minimap button:** left-click opens the options, right-click shows an 8 s preview
- **Addon menu** next to the minimap, with the same clicks

What you can change:

- Show or hide spell icon, cast time, latency zone, swing strip and its seconds
- Hide the built-in swing bars
- Strip height
- Font and font size
- Colours of the swing strip, the queued swing, Cleave and the latency zone (game colour picker, with reset)

## How it works

The swing strip mirrors Forever's built-in swing timer (`Blizzard_SwingTimer`). That timer is the only accurate source, because Forever keeps the combat log from addons and hands combat values such as the attack speed to addons as secret values. SwingCast copies the built-in bar's values and its seconds label as they are and hides the built-in bar's look. If the strip ever fails, it switches itself off and the built-in bar is shown again.

## Advanced: chat commands

Everything above is also available as a command. `/swc` lists the settings, each one is switched with `/swc <setting>`:

| Setting | |
|---|---|
| `icon` | spell icon |
| `time` | cast time |
| `latency` | latency zone |
| `swing` | swing strip |
| `swingText` | seconds on the swing strip |
| `hideNative` | hide the built-in swing bars |

`/swc options` opens the options window, `/swc minimap` hides or shows the minimap button, `/swc height <2-20>` sets the strip height, `/swc font <7-20>` the font size, `/swc color swing|queued|cleave|latency|reset` opens the colour picker, `/swc test` shows an 8 s preview, `/swc reset` restores the defaults.

## AI disclosure

The code was written with the help of an AI assistant (Claude). Bencepo designed the features, tests everything in game and maintains the addon.

## License

All rights reserved, see [LICENSE](LICENSE).

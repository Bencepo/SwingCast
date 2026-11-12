# SwingCast

A small addon for WoW Forever that adds to the standard player cast bar instead of replacing it.

- Spell icon left of the bar
- Remaining cast time on the bar
- Latency zone at the end of the bar: once the bar reaches it, the next spell can be pressed
- Swing timer as a thin strip right under the cast bar, with seconds to the next swing
- The strip turns orange while Maul, Heroic Strike or Raptor Strike is queued, blue for Cleave

## How it works

The swing strip mirrors Forever's built-in swing timer (`Blizzard_SwingTimer`). That timer is the only accurate source, because Forever keeps the combat log from addons and hands combat values such as the attack speed to addons as secret values. SwingCast copies the built-in bar's values and its seconds label as they are and hides the built-in bar's look. If the strip ever fails, it switches itself off and the built-in bar is shown again.

The built-in swing timer has to be switched on: Options > Advanced Options > Swing Timer.

## Options

Options > AddOns > SwingCast, or the minimap button (left-click: options, right-click: preview), or the game's addon menu next to the minimap.

## Commands

`/swc` lists the settings. Each one is switched with `/swc <setting>`:

| Setting | |
|---|---|
| `icon` | spell icon |
| `time` | cast time |
| `latency` | latency zone |
| `swing` | swing strip |
| `swingText` | seconds on the swing strip |
| `hideNative` | hide the built-in swing bars |

`/swc options` opens the options window, `/swc minimap` hides or shows the minimap button, `/swc height <2-20>` sets the strip height, `/swc test` shows an 8 s preview, `/swc reset` restores the defaults.

## License

All rights reserved, see [LICENSE](LICENSE).

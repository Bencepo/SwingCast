# Changelog

## 0.2.0-alpha

- Minimap button: left-click opens the options, right-click shows the swing strip preview. `/swc minimap` hides or shows it.
- Entry in the game's addon menu next to the minimap, with the same clicks.
- Options window under Options > AddOns > SwingCast with every setting, including the strip height.
- `/swc options` opens the options window.
- Fixed: `/swc swingText` and `/swc hideNative` did nothing because the command is read in lower case.

## 0.1.1-alpha

- Swing strip copies the built-in timer's values and seconds label as they are. Forever hands the attack speed to addons as a secret value that cannot be calculated with.
- If the strip fails, it switches itself off and the built-in swing timer is shown again.

## 0.1.0-alpha

- Spell icon, remaining cast time and latency zone on the standard player cast bar.
- Swing strip under the cast bar, mirrored from Forever's built-in swing timer (main hand, off hand and ranged where present).
- Strip turns orange while Maul, Heroic Strike or Raptor Strike is queued, blue for Cleave.
- `/swc` settings, `/swc test` preview.
- Released on CurseForge (project 1800255).

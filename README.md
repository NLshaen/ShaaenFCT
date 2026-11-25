# ShaaenFCT

Floating combat text addon for **WoW Forever**.

Current version: **v0.7.47**.

## Installation

Download [ShaaenFCT_v0.7.48.zip](https://github.com/NLshaen/ShaaenFCT/releases/download/v0.7.48/ShaaenFCT_v0.7.48.zip), extract the `shaaenFCT` folder into `Interface/AddOns/`, then run `/reload` in game. Open the addon settings with `/sfct` or the minimap icon.

## Features

- Damage numbers on independent frames anchored to enemy nameplates, with Arc, Popup, Float, Bounce and POW animations
- **Coverage** mode for available melee, spell, DoT and area-damage reports on tracked nameplates
- Green incoming-heal numbers in a dedicated frame attached to the player
- Purple experience-gain numbers in a separate player frame
- MISS, DODGE, PARRY, BLOCK and GLANCING feedback, plus configurable Overkill effects
- Custom fonts and interface themes, scale (75–120%) and opacity (30–100%) controls
- Minimap icon opens the configuration window in the screen center
- v0.7.45 fixes WoW Forever's 60-upvalue limit by splitting the nameplate event handlers

## Limitations

WoW Forever may restrict combat values and event attribution. **Coverage is best-effort in solo play** for unconfirmed source events; an observed damage event is not proof that the player caused it. For details and commands, see [README.txt](README.txt).

## Releases

Download the latest package from [GitHub Releases](https://github.com/NLshaen/ShaaenFCT/releases/latest).

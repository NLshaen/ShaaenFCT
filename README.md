# shaaenFCT

Floating combat text addon for **WoW Forever**.

Current version: **v0.7.28**.

## Installation

Place the repository contents in `Interface/AddOns/shaaenFCT/`, then run `/reload` in game. Open the addon configuration with `/sfct`.

## Features

- Animated combat text on enemy nameplates (Arc, Popup, Float and Bounce)
- Smart combat-log filtering for player and pet actions
- MISS, DODGE, PARRY, BLOCK and GLANCING feedback
- Green incoming healing text
- Final-hit / Overkill effect with a configurable shake
- Custom font support and a resizable configuration window

See [`README.txt`](README.txt) for version-specific instructions and known client limitations.

## Notes

In Smart mode, configure the game's Combat Log with **My Actions**, including pet and miss/block events. WoW Forever's `UNIT_COMBAT` events may not identify the source of damage.

Download the latest addon package from [GitHub Releases](https://github.com/NLshaen/ShaaenFCT/releases/latest).

shaaenFCT 0.7.29 | WoW Forever (live version in menu footer)
===================================

INSTALLATION
1. Extract shaaenFCT into Interface/AddOns/.
2. Make sure shaaenFCT contains shaaenFCT.toc and Core.lua.
3. In game, type /reload and /sfct.

TYPOGRAPHY COMPATIBILITY FIX (0.7.29)
- Initialize normal and critical preview FontStrings with GameFontNormal,
  and apply their selected fonts before calling SetText().
- Prevent Fonts/Typography panel construction from failing on WoW Forever
  with FontString:SetText(): Font not set.
- Preserves normal/critical font selection, Settings, Overkill and all
  existing damage and animation functionality.

SETTINGS UI REFRESH (0.7.28)
- A smooth hover highlight now animates when the pointer enters or leaves
  sidebar entries, Settings sub-tabs and standard addon option buttons.
- The top bar has two live sliders: WINDOW SCALE (70-130%, default 100%) and
  OPACITY (0-100%, default 100%). Both persist in shaaenFCTDB.
- WARNING: 0% opacity hides the window. Type /sfct ui reset (or
  /sfct windowreset) to restore both sliders to 100% without reloading.
- Former GENERAL sidebar entry is now SETTINGS with three sub-tabs:
    GENERAL: Addon status (Enable ON/OFF), Smart/Native/All modes,
             pet target filtering, final-hit duration and shake intensity.
    STYLE: Presets Ember Orange, Glacier Blue, Emerald, Amethyst, Graphite.
           Style colors apply to addon settings, not floating combat text.
    FONTS: Normal, critical and settings fonts, including custom fonts.
- Animation, Help and About remain accessible from the left sidebar.
- Existing combat, font and Overkill settings are preserved after upgrade.

BLOCKED DAMAGE AMOUNTS (0.7.27)
- BLOCK/BLOCKED events now display the amount supplied by UNIT_COMBAT,
  when positive or protected, with an accompanying gray BLOCKED status.
- A BLOCK event without a positive readable amount displays only BLOCK.
- WOUND/DAMAGE events with a BLOCK/BLOCKED descriptor show numeric damage
  with the BLOCKED label instead of losing the modifier.
- Protected amounts pass untouched to SetText; no concatenation/arithmetic.
- Numeric amounts on a BLOCK action are not treated as landed damage for
  Overkill, because the client may report the PREVENTED damage there.
- In Smart mode the filtered Combat Log must include blocked attacks.

GLANCING BLOWS (0.7.26)
- Detects the UNIT_COMBAT descriptor GLANCING on actual damage (WOUND/DAMAGE).
- Renders the real damage amount on the enemy nameplate in light gray, with
  a small GLANCING label that follows it through Arc/Popup/Float/Bounce.
- Protected WoW Forever damage values are never converted to strings.
- The damage still participates in Smart matching and can count for final hits.
- Glancing labels are hidden/recycled with their damage, including on kills.
- Smart filtering still depends on the combat log's My Actions filter; the
  UNIT_COMBAT descriptor itself does not identify the attacker.

INCOMING HEALS (0.7.25)
- UNIT_COMBAT healing received by the player is shown in green using the
  active FCT animation (Arc, Popup, Float or Bounce), including critical heals.
- The text is anchored to the visible player nameplate (if available),
  otherwise the ElvUI player unit frame or the Blizzard PlayerFrame.
  Without a visible player frame it uses a position near the on-screen player.
- Incoming heals from OTHER players count if you receive them. Healing of
  pets, party members or other targets is NOT shown.
- Heals are independent of Smart damage-log matching and never count as
  damage/last hits or cause Overkill. Active in Smart and All modes.
- Native mode remains Blizzard-managed to avoid duplicating its own healing text.
- PARRY is off-white; BLOCK is gray. MISS and DODGE retain their colors.

SMART DAMAGE FILTER
- Open the Blizzard Combat Log and choose the "My Actions" filter.
- Use /sfct source smart (default on new installs).
- Smart matches filtered log messages to UNIT_COMBAT nameplate events by
  timing, ONLY for your selected enemy or your own pet's current target.
- MISS, DODGE, PARRY and BLOCK notices use the normal nameplate animation styles.
  In Smart, the combat-log filter must include missed/parried/blocked attacks.
- Other players' pet attacks are not inferred as yours by pet-target proximity:
  unpaired UNIT_COMBAT hits are now DISCARDED, even in solo play.
- Matching is still approximate on WoW Forever: UNIT_COMBAT does not identify
  the attacker, and secret combat messages cannot always be source-verified.
  Simultaneous attacks on the SAME target may still be indistinguishable.
- All Damage mode explicitly displays everyone, including other players/pets.
  Select Smart to filter, and set the Combat Log to My Actions (include Pet).
- The combat damage amount may be a protected value on WoW Forever.
  Such amounts are sent directly to FontString:SetText without any math,
  string conversion, or comparison. The actual excess "overkill" damage
  is not exposed by the available API.

FINAL HIT / OVERKILL NUMBERS
- A matching personal killing blow displays the most recent matched damage
  amount in its OWN Frame + FontString, visually anchored to the TOP of the
  killed enemy's NAMEPLATE. It is not anchored to Blizzard's TargetFrame,
  ElvUF_Target, unit_target, or the center of the game screen.
- While the nameplate is visible the frame follows it; after removal or
  recycling, the frame freezes at the last known nameplate position and fades.
- Normal damage continues rendering directly on nameplates (0.7.14 behavior).
- No fake values: the displayed amount is the last Smart-matched personal hit,
  NOT the actual excess overkill, which WoW Forever does not expose via
  UNIT_COMBAT. Some deaths yield no usable damage amount.
- If the client does not supply a usable plate position after its removal,
  the final-hit effect is skipped instead of jumping to the screen center.
- Preview: target an enemy with a visible nameplate and type /sfct overkilltest.
- Duration is adjustable under General; custom fonts are supported.

ANIMATION STYLES / DIRECTIONS / PIXEL OFFSETS (0.7.9)
- Open /sfct > Animation and choose one of four right-panel tabs:
    ARC    Curved upward trajectory, direction, rise, curve and fade.
    POPUP  Text grows, holds its peak size, then settles and fades.
    FLOAT  Smooth upward travel, with lateral drift and oscillating sway.
    BOUNCE Spring-like rise and damped size pulses.
- Changing the tab selects the active style for new combat hits.
- Every style has its own independent saved settings and a Reset This Style button.
- Every animation style includes LEFT, RIGHT, ALTERNATE, and RANDOM direction:
    LEFT       movement towards the left
    RIGHT      movement towards the right
    ALTERNATE  each successive hit swaps sides
    RANDOM     each new hit independently picks a side
- Popup and Bounce have an additional Side travel slider (pixels) so their
  horizontal direction is visible. Float reverses its drift and sway.
- Direction values are independent of Normal/Critical offset X/Y fields.
- Saved 0.7.8 settings are preserved; new direction settings start at Alternate.
- Each style now has FOUR additional signed pixel offsets in the right-hand panel:
    Normal Damage:  Offset X / Offset Y
    Critical Damage: Offset X / Offset Y
  Both are separately configurable for Arc, Popup, Float, and Bounce.
- Offsets range from -250 to +250 px, with 1 px steps and editable numeric fields.
  X negative moves left, positive moves right. Y negative moves down,
  positive moves up. All offsets default to 0 for existing installations.
- Offsets apply during motion, after the nameplate disappears, and in previews.
  Final-hit animations preserve the relevant offset and do not apply it twice.
- Preview Style launches sample numbers; values are not real combat damage.
- Existing 0.7.6 Arc values and the Smart source setting are preserved.
- Final-hit numbers now use their own dedicated overlay Frame anchored to
  the enemy nameplate, independently of the regular damage style.

ENGLISH SETTINGS / SEARCHABLE TYPOGRAPHY / LIVE VERSIONS
- Five pages: General, Typography, Animation, Help, About (last).
- Header includes a small NL monogram, SHAAEN FCT, and FLOATING COMBAT TEXT.
- No Sleek Combat Text footer label.
- The addon version is read at runtime from the ## Version field in its TOC
  via C_AddOns.GetAddOnMetadata (legacy fallback when available).
- The game version comes from GetBuildInfo(); game family is determined from
  the live Interface version / WOW_PROJECT_ID, including WoW Forever.
- Compact graphite-and-copper styling inspired by modern WoW UI addons,
  with Arial Narrow as the default settings font. Normal damage and critical
  damage animations default to Arial (true Arial from SharedMedia when installed,
  otherwise the client's bundled Arial Narrow font).
- The options window can be enlarged using the lower-right orange grip.
  Minimum size: 755x760; maximum: 1100x940. Size and position are saved.
- About appears last in the sidebar; addon and detected WoW client name and
  patch version appear in orange at the bottom-left. SHAAEN and FCT are closer.
- Separate LibSharedMedia dropdowns for normal and critical fonts; a new
  third dropdown changes the settings UI font (without downloading fonts).
- Normal damage is white, critical damage is yellow; final-hit numbers
  use a gold accent and a longer floating animation.
- Your existing animation, font and Smart settings are preserved.

COMMANDS
/sfct                      Open or close settings
/sfct source smart         Filtered personal nameplate damage
/sfct pet on | off          Include own pet target for Smart matching
/sfct source player        Blizzard native personal damage
/sfct source all           All nameplate damage, including other players
/sfct on | /sfct off       Enable/disable addon
/sfct status               Brief diagnostic counters
/sfct finaltest            Preview 9999 on a visible target NAMEPLATE
/sfct overkilltest         Legacy alias for the same example

LIMITATIONS
- The Smart technique depends on "My Actions" being the active Blizzard
  Combat Log filter and is inherently approximate.
- PARTY_KILL may arrive when the nameplate and its GUID have vanished.
  Without a recent Smart-matched number there is no honest value to display.
- Additional fonts are provided only by installed LibSharedMedia providers.
- No commercial or third-party UI font assets are bundled.

TYPOGRAPHY FONT PICKER (0.7.11)
- Typography contains three searchable dropdowns: Normal Damage, Critical Damage,
  and Settings UI font. Lists refresh from LibSharedMedia when opened.
- Featured fonts: Numen, Ellesmere (mapped to the Expressway typeface), BigDam,
  plus matching registered options such as Inter Tight, Poppins, Russo One,
  Roboto Condensed, Gotham Narrow, Fira Sans Bold, and Expressway Bold.
- The first three featured names stay visible and are marked NOT INSTALLED
  when unavailable. You cannot accidentally select an unavailable font.
- LibSharedMedia registrations named Big Dam or BigDam are resolved as the
  same font. The picker also includes client-bundled Blizzard font options
  and every additional registered SharedMedia font.
- Two non-combat sample numbers preview the chosen normal and critical fonts.
- No third-party font files are bundled or redistributed with the addon.
  To use Numen, BigDam or Ellesmere/Expressway, install a font provider that
  registers the corresponding face with LibSharedMedia, then /reload.
- Existing saved font names remain selected; missing fonts fall back to
  Blizzard Friz Quadrata without errors.


0.7.11 HOTFIX - NAVIGATION / TYPOGRAPHY COMPATIBILITY
- Fixed missing Animation/Help content on clients where the new font-search EditBox lacks SetTextInsets or frame-level helpers.
- Typography initialization is guarded to prevent future font-picker errors from stopping other tab creation.
- Kept Typography featured fonts, filter search, font previews, four animation styles, independent X/Y positions and Smart filtering.
- No change to SavedVariables format.


0.7.11 - NL MINIMAP BUTTON / GAME OPTIONS INTEGRATION
- A native NL minimap launcher, built entirely with Blizzard textures and text (no external image/library required).
- Left-click opens the complete shaaenFCT settings. Right-click opens quick commands: Open, Smart, Blizzard, All damage, Enable/Disable, Status.
- Drag with the left mouse button to reposition the minimap icon; the angle is saved between logins.
- Tooltip includes the most useful slash commands.
- /sfct minimap show | hide | toggle | reset controls visibility and restores the default location.
- Game Menu > Options > AddOns > shaaenFCT exposes an addon information panel, buttons for full settings, mode shortcuts and minimap visibility.
- Modern Settings API used when available; fallback to InterfaceOptions_AddCategory on older clients.
- Integration.lua is independent of the combat/rendering engine to preserve Smart source and animations.
- All existing SavedVariables and UI tabs are preserved.


0.7.12 - UI / ABOUT / FONTS
- Addon version and WoW Forever version moved to the lower-left sidebar, read dynamically from .toc and GetBuildInfo().
- Typography subtitle and guidance corrected, including local-font installation details.
- Fonts/CustomFonts.lua is a user-editable font registry; put licensed .ttf/.otf files in Fonts/ then /reload.
- Libs/FontMedia.lua is a light, bundled, font-only adapter that delegates to the official LibSharedMedia-3.0 when installed and offers local fallback otherwise. It does not replace the full official LibSharedMedia library.
- NEW ABOUT sidebar tab: personal WoW guild description (Les No Life / NL), editable saved Discord invite URL.
- HELP is separate and contains only Quick Start + slash commands.
- Previous Smart filtering, animation profiles, minimap launcher and game options integration preserved.


0.7.13 - FINAL HIT / OVERKILL NAMEPLATE FIX
- Corrected PARTY_KILL payload: attackerGUID, victimGUID. Previous code used
  the attacker's GUID to find the enemy nameplate, often missing the kill.
- If the attacker GUID is readable, exclude other party members' killing blows,
  and prevent their UNIT_DIED/removal signals from triggering our own effect.
- Match UNIT_DIED to the victim's current or recently removed nameplate by GUID,
  retaining the last accepted damage value when PARTY_KILL isn't available.
- Detect readably dead mobs on nameplate removal as an additional fallback.
- Keep the number at the plate's last visible position when the plate is hidden
  before NAME_PLATE_UNIT_REMOVED arrives; the FX layer outlives the nameplate.
- Allow 0.60 seconds for delayed Smart damage attribution before finalizing.
- Protect against a cached number being displayed on an unrelated victim.
- The displayed value remains the last real UNIT_COMBAT amount accepted by the
  configured source (Smart or All), not the separately computed excess damage.
  Forever's exposed UNIT_COMBAT API has no overkill amount parameter, and raw
  CLEU damage events are unavailable to addons. If the client never sends the
  killing hit, shaaenFCT cannot reconstruct its exact number.
- Existing profiles, saved options, typography, minimap, and About UI unchanged.


0.7.14 - RESTORE REGULAR DAMAGE NUMBERS ON NAMEPLATES
- Fixed a Lua boolean error: `removed ~= nil` treated false as present,
  causing all normal combat numbers to be detached from their nameplates.
- Reverted the 0.7.13 change to ordinary damage number anchoring; regular
  nameplate hits now follow the tested 0.7.12 renderer and do not depend on
  screen-coordinate availability or a death-effect overlay.
- Retained corrected PARTY_KILL attacker/victim GUID handling and delayed
  final-hit effects from 0.7.13.
- Special detached rendering applies only after a killing blow has been
  scheduled and the hiding plate has a safely cached screen position.
- Settings and fonts are preserved; no SavedVariables reset needed.


0.7.15 - FINAL HITS ANCHORED TO TARGET UNIT FRAME
- Overkill/final-hit numbers now animate on the target unit frame
  (ElvUF_Target/ElvUI or Blizzard TargetFrame), never at the screen center.
- Incompatible/hidden/disappearing nameplates no longer change the target
  unit-frame anchor; no onscreen-position fallback is used for final hits.
- Ordinary damage continues to animate on enemy nameplates (0.7.14 fix).
- /sfct finaltest previews a 9999 final hit on the target unit frame.
- If no supported target unit frame exists, the addon skips the final FX
  instead of drawing it at the center. Check /sfct status for the count.
- The final-hit number is the last raw matched damage, not mathematically
  calculated overkill excess (not exposed by UNIT_COMBAT on Forever).


0.7.16 - FONT MEDIA FIX
- Corrected lexical declaration order for the internal fonts registry to
  prevent pairs(nil) when the official LibSharedMedia-3.0 bridge is used.

0.7.17 - FINAL HIT IN A DEDICATED NAMEPLATE FRAME
- Replaced the 0.7.15 target unit-frame anchor with a separate Frame holding
  the final-hit number. It attaches to the dying enemy's nameplate TOP.
- On nameplate removal/hide, freeze at the last cached plate position to keep
  the final-hit animation visible without following recycled nameplates.
- When the location cannot be determined, skip the effect (no screen center).
- Final numbers do not interfere with the normal nameplate damage renderer;
  active regular hits are hidden only after the dedicated final FX appears.
- The preview command /sfct overkilltest requires a visible target nameplate.
- Retains all fonts and the FontMedia.lua pairs(nil) fix from 0.7.16.


0.7.18 - DECAYING SHAKE FOR OVERKILL
- Added a short 0.42-second horizontal/vertical shake to the separate final-hit
  frame: strong on impact, smoothly easing to zero.
- Ordinary hits and the nameplate itself are not shaken or repositioned.
- Shake works while the nameplate is visible and after it disappears, using
  the last known position; no return to the center or to the target unit frame.
- Existing rise/fade timing, custom fonts, and user settings are preserved.
- Preview the effect on an enemy nameplate with /sfct overkilltest.


0.7.19 - SOFTER 1-SECOND OVERKILL SHAKE + GENERAL INTENSITY PRESETS
- Final-hit shake now eases out over 1 second, with gentler sine-wave
  motion (default MEDIUM: 5px horizontal / 2.5px vertical at peak).
- GENERAL now offers three saved settings: LÉGER / MOYEN / FORT,
  corresponding to 2.5/1.25, 5/2.5, and 8/4 pixel peak offsets.
- Shake intensity changes apply immediately to active and future final hits.
- Overkill numbers still appear on a separate frame above their nameplate,
  including freeze-on-death. Regular damage behavior and font settings
  are unchanged.
- Duration is 1 second, or shorter only if the user explicitly sets the
  final-hit lifetime below 1 second.
- Preview with /sfct overkilltest on a visible enemy nameplate.


0.7.21 — Responsive settings + footer actions
- Tab controls and typographic panels now expand as the settings window widens.
- General rows, typography font lists, animation sliders/tabs, and About fields adapt horizontally.
- Added bottom-right RELOAD UI and CLOSE buttons, in that order, anchored above the resize grip.
- The minimum settings height is 760 to reserve a non-overlapping footer.


0.7.22 - PET DAMAGE (WORLD OF WARCRAFT FOREVER)
- Smart matching includes pet hits when the Combat Log's My Actions filter
  includes Pet (enable the Pet category in the in-game log settings).
- NEW: a SOLO-only pet-target assist for otherwise unmatched UNIT_COMBAT
  hits. Enable/disable in General, next to Open Combat Log (default ON), or
  with /sfct pet on and /sfct pet off. A brief delay avoids double display
  when the proper log credit arrives. Pet hits retain your existing fonts,
  animations and enemy-nameplate placement.
- In a party/raid, solo pet-target assist is suppressed to avoid treating
  group members' hits as pet hits. Pet damage then depends on the My Actions
  combat-log Pet setting. /sfct status shows assist and candidate counters.
- IMPORTANT CLIENT LIMIT: Forever's UNIT_COMBAT does not identify the attacker.
  In solo play, unrelated hits that land on the pet's target may also appear,
  and spells from guardians without a controllable `pet` token cannot be
  identified with certainty. The addon does not claim precise pet ownership.
- Retains independent overkill nameplate frames, smooth shake, responsive UI,
  typography and the Reload UI / Close buttons from 0.7.21.

0.7.23 - MISS / DODGE + STRICTER PERSONAL / PET MATCHING
- Show MISS and DODGE over nameplates, using the same animation profile as
  regular damage, with muted grey / soft amber text respectively.
- In Smart mode, these notices require a matching filtered combat log event.
  Include misses and own-pet actions in the in-game My Actions filter.
- No numeric amount is synthesized for a miss or dodge; neither may trigger a
  killing-blow number.
- Removed the v0.7.22 SOLO pet-target damage guess (the main cause of displaying
  unrelated players' pet damage on the same target).
- Smart now only considers hits on the player's target or the player's OWN
  pet target, and unmatched unit hits are ignored. Pet target inclusion can
  be toggled in General or via /sfct pet on|off.
- Caveat: combat-log credits may be protected and UNIT_COMBAT does not expose
  an attacker GUID. Two simultaneous attackers on the very same selected
  target may still be indistinguishable. "All Damage" remains intentionally
  unfiltered.
- Kept the v0.7.22 UI, fonts, Overkill and Shake settings unchanged.

0.7.24 - PARRY / BLOCK COMBAT TEXT
- Added PARRY and BLOCK on nameplates alongside MISS and DODGE.
- PARRY: soft blue text; BLOCK: soft green text. Existing normal animation
  settings and configured damage font are reused for all combat notices.
- Works in Smart (requires a matching personal/pet filtered combat-log
  message) and All (shows all sources, including other players).
- Outcomes do not update the last damage amount or produce Overkill effects.
- Includes both PARRY/PARRIED and BLOCK/BLOCKED event aliases.
- No changes to the pet filter or the UI/overkill configuration.

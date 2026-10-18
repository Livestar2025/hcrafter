# Tests

`harness.lua` runs HCrafter under LuaJIT with stand-ins for Ashita, imgui (draw lists, invisible buttons, children and popups), the settings library, events, files, memory, packets, textures and sounds. It needs LuaJIT and a shell with `mkdir`, `rm` and `ls` (Linux, macOS or WSL).

From the repository root:

```
luajit tests/harness.lua addons/hcrafter
luajit tests/harness.lua addons/hcrafter cycle
luajit tests/harness.lua addons/hcrafter preview <output folder>
```

The harness makes a fresh `hcrafter_test_...` folder inside `HCRAFTER_TMP` (or your system temp folder) and deletes only that folder when it ends. Without a names file it uses `item_names.csv`, a few public item names the checks need. Pass your own "id,name" file as the second argument to see real names everywhere.

## What it checks

- The addon loads with no undefined globals and writes no globals.
- Settings tables are copies, never the defaults themselves.
- Every frame is balanced: windows, children, popups, style colors and variables, and fonts. No two items in a window share an id. Every draw call gets finite positions and real colors. No imgui widget text carries a percent sign.
- HQ tiers, success rates, recipes with two and three crafts, gear (including a bonus with decimals or as text), image support per craft, crafting rings, HQ odds (none for a result the rules say can't happen, or with a crafting ring on), and the image support hints.
- The skill-up model: chances, skill-up sizes, the Optimal, Costly and Dangerous bands, the break rules, rank caps, the measured rate, the recommendations and the plan to a target level.
- The prices file: quoted names, `1,500` and `900g` prices, name-only lines, bad lines, a change made by another character, and clearing a price. A save changes only that item's line and keeps comments, blank lines, unreadable lines, your names, extra columns, a byte order mark and the line ends. Two lines for one item become one. A file that is there but can't be read is never written over.
- Stack text and spare-percent rounding.
- Fonts load only from the load event, and a missing font falls back.
- Bag snapshots: names from the zone-in packet, no save while zoning, at character select or while the game still shows the old character, never wiped by an empty read, unread bags kept, a damaged character list rebuilt, another character's items counted, and their files read again after zoning.
- The recipe book: emblems, search, the recipe card, the tier ladder, material rows, opening a sub-recipe, picking a second recipe, hover cards, and the right-click menu, including setting a price.
- A worked Resource Planner: 12 Inferno Sabots, making the Ebony Sabots and Ebony Lumber, checked item by item, then with the key-item lumber recipe, with spare synths, with costs, and the Skill-up tab. Remove takes the entry you clicked, even with a saved entry whose recipe is gone.
- Gear, crafting rings and imagery buffs.
- Synth, skill-up, level-up and skills packets at the sizes LandSandBoat sends, ranks, the history file per character, fanfare and sounds, an HQ crystal, an interrupted synth, and a result that never arrives.
- The alert after a macro: no sound or countdown per synth, one alert after the set number of macro lines in a row, refused and cancelled lines counted so the next run stays in step, the material check after a synth, no early "Out of" when the next synth starts right away, the crystal named first, a pause of 25 seconds that starts a new count, an answer that never comes, the alert switched off, sounds off, and None picked. Also a request that never started, a result that names its own crystal and materials while another request came in, a result without them whose item doesn't match the guess, a synth effect with no request seen, a result whose start was missed, a skill-up long after the last synth, a skill drop followed by its lower level, and packets shorter than expected.
- The struct stub raises an error past the end of a packet, so a parser that reads too far fails the run.
- Commands, character select, hiding, the look settings, and unload.
- Window sizes: a drag on the corner, the smallest and largest sizes, never taller or wider than the screen or the room right of the window, a drag sideways or down only, a sideways drag that drifts a little, a mouse that goes missing mid-drag, a quick second grab after a drag, a click that doesn't move, the double-click reset, a set height, bad saved sizes, the Shopping list's width-only corner, and settings saved by 1.0.0.
- Text size: text drawn and measured bigger, the 80 to 130 percent limits, a NaN in the settings file, no text past the edge of its window at 130 percent with every window at its narrowest (every seventh recipe, the History and Settings tabs, and the Skill-up tab for each craft), and balanced frames at 80 percent with every window at its widest.
- Ashita's font size: 100 percent at Ashita 4.3's default 18 pixels, 155 at 28, 200 at 36, the limits, the switch, level boxes sized to a 28 pixel font with the style's padding, the planner's first spot, and every view with a 36 pixel font at 130 percent text on a 3840 by 2160 screen.
- Sounds: each alert's list in Settings, picking and playing a sound, your own .wav files in any case, file names with folders or odd characters left out, a missing file that plays nothing and shows as missing, odd values in the settings file, the 1.1.0 sound switch carried over, no break sound by default and the one-time change for 1.2.0 settings, all ten sounds present, and two toasts at once.
- The Optimal, Manageable and Risky labels, Sonic Belt at Leathercraft 107 and its estimate, no rank-up message at 100, Shopping list lines that fit at 260 wide, and a long Shopping list that stays on a 1080 screen.
- HQ fanfare for T0 and T1 only by default, and the right-click menu in the game font at HCrafter's text size.
- A window that stops on an error halfway: imgui stays balanced, the error prints once, the other windows still draw, and the window comes back once the error is gone. A draw that ends with something still open gets it closed.
- Textures load a few per frame, failures fall back and are not retried every frame, and zoning drops them.
- Every recipe drawn with every material open and every line hovered, with the Resource Planner open on every tenth.
- The Skill-up tab for every craft from 0 to 100.
- Every recipe planned with everything made, compared with a separate brute-force answer.
- 3000 random packets of every size for the ids HCrafter reads: no error gets out, frames stay balanced and craft levels stay sane.
- The `cycle` run: looping recipe data stays finite and the loop item is bought.

## Preview

`preview <folder>` draws a few scenes (recipe book, Resource Planner, Skill-up tab, Shopping list, fanfare, history, settings) and writes each frame's draw calls as an SVG file. Icons are stand-ins and text uses the stub's widths, so the result is close to the game, not the same. `tools/render_preview.js` turns the SVG files into PNG images with Playwright's Chromium.

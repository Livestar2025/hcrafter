# Changelog

## 1.3.1 (2026-10-18)

### Sound fixes from an independent review of 1.3.0

- Your own sound file deleted while you play is never passed to Windows, which would play its own sound instead. It plays nothing and shows as missing, at any volume. A game file that goes missing plays HCrafter's own sound for that alert. A folder named like a sound counts as missing too.
- Copies are written in full under a temporary name and then put in place in one step, so a crash or a full disk never leaves a short copy that plays as silence. A short or empty copy is made again. A copy that can't be written plays HCrafter's own sound and is tried again a minute later, instead of on every alert.
- Each copy's name carries a code for the size and last change time of the file it came from. A sound file you replace, or one of HCrafter's sounds changed by an update, gets a new copy.
- Turning a sound into a `.wav` file takes about a sixth of the time it did: 10 ms instead of 65 ms for a 7-second stereo sound, measured with 64-bit LuaJIT. It also leaves far less for Lua's garbage collector.
- Stepping the volume asks for each sound once, at the last volume picked, instead of once per click.
- When HCrafter loads and when you change the volume, it deletes copies from 1.3.0, copies whose sound file changed, and files a write left behind more than ten minutes ago. Past 40 copies it deletes the oldest first, never the ones in use. Copies at another character's volume stay, so nothing is made again at every login. Nothing else in the folder is touched.
- The sounds of your own character's settings are made ahead of time when Ashita switches to them at login, not only when HCrafter loads. Before, a character with other sounds or another volume had each one made on its first alert.
- Your own `.wav` files follow the volume in more formats: 8, 16, 24 and 32-bit PCM and 32-bit float, mono or stereo, up to 10 seconds at 48 kHz (480,000 samples), including WAVE_FORMAT_EXTENSIBLE files. Others play at their own volume, and Settings says so. A file HCrafter can't rescale isn't read again each time it plays.
- With no game folder found, Settings marks FFXI sounds "(no game folder)" instead of "(missing)".
- Settings now says startup also plays when you log in and when `/hcrafter` shows the book.

## 1.3.0 (2026-10-18)

### The game's own sounds

- Each alert now plays one of FFXI's own sound effects by default, picked by ear for that alert. Breaks still play nothing by default.
- HCrafter ships no game audio. It reads the sound from your own game folder (`SquareEnix\FINAL FANTASY XI\sound\win\se`, or wherever the game's `FFXiMain.dll` was loaded from) and keeps a `.wav` copy in `config\addons\hcrafter\sounds`.
- It reads the game's PS-ADPCM and PCM sound files. The few in encrypted ATRAC3 are left alone. The reader gives the same samples as vgmstream.
- 42 game sounds are in the lists: two sets picked by ear with one sound for each alert ("FFXI level-up", "FFXI level-up 2" and so on), plus 26 more named by folder and number, such as "FFXI 000-026".
- When the game's folder or a sound file can't be found or read, the alert plays HCrafter's own sound for it instead, and Settings says so.
- A game sound is turned into a `.wav` file once, a frame at a time after loading, so the first alert plays at once.

### Startup and shutdown sounds

- Two optional sounds, None by default, picked like the others in Settings.
- Startup plays as HCrafter loads while you're in game, on the first frame after you log in, and when `/hcrafter` shows the recipe book.
- Shutdown plays when you log out, or when HCrafter unloads while you're logged in. It uses your character's own choice even though Ashita switches to its default settings at logout.
- [Inference] Closing the game without logging out may cut the shutdown sound short, since the game exits right away.

### Right-click menu

- The right-click menu and the sound list are bigger: their text is the size of recipe names, with more room around and between lines.
- On Ashita builds with imgui before 1.92, which draw a font only at the size it was loaded, the menu's text is scaled to that size instead.
- A long sound list scrolls instead of running off the screen.

### Volume

- One volume for every sound, from 0 to 150 percent in Settings. HCrafter's own sounds and your own `.wav` files follow it too, through a copy at that volume in `config\addons\hcrafter\sounds`.
- At 0, nothing plays.

### Settings carried over

- A sound still at its 1.2.1 default moves to the game's sound for that alert, once. A sound you picked yourself stays.
- Skill-up and No more skill-ups had no sound in 1.2.1, so they get the game's sound even if you had picked None. Pick None again to keep them quiet.

## 1.2.1 (2026-10-18)

### Size on big screens

- 100% now matches Ashita 4.3's default font size, 18 px, or 14 px on older Ashita. 1.2.0 measured from 14 px, so on Ashita 4.3's default it drew everything 30% too big. With Ashita's font at 36 px, HCrafter draws at 200%. At 28 px, it draws at 155%.
- Settings says how big Ashita's font is and what its default is. The switch is now called "Grow with Ashita's font size".
- No window is wider than the room right of where it sits.
- The search box grows with Ashita's font, and the level boxes take their padding from Ashita's style.

### The alert after your macro

- Every line of the macro counts, even a refused or cancelled one. A macro with a refused line still alerts when it ends, and the next run stays in step. The toast says so, such as "Macro done: 6 synths."
- A pause of more than 25 seconds after the last line starts a new count.
- "Out of" no longer fires early when the next synth starts right after a result. When several things run out, it names the crystal first.
- A line whose answer never comes counts as answered after 30 seconds.

### Sounds

- Breaks play no sound by default. Their banner stays, and you can still pick a sound for them.
- A sound file that is missing plays nothing, rather than Windows' own sound, and Settings marks it "(missing)".
- Your own sounds named .WAV in capitals show up too.
- A sound setting that isn't a file name reads as None.
- If "with a sound" was off for the 1.1.0 ready cue, the alert after your macro starts with None.

### Other fixes

- A sideways drag on a corner that drifts a little no longer sets the height.
- The Shopping list keeps its rows on the screen.
- Two toasts can show at once.

## 1.2.0 (2026-10-18)

### Size on big screens

- HCrafter grows with Ashita's own font size, measured from 14 px. With Ashita's font at 28 px, it draws at 200%. Size and Text size still adjust from there. "Match Ashita's font size" in Settings turns this off. (1.2.1 measures from Ashita 4.3's default of 18 px.)
- The craft level boxes in Settings are sized to Ashita's font, so a level like 100.0 is no longer cut off and the rows don't overlap.
- No window grows wider than the screen.

### The alert after your macro

- The countdown and the chime after every synth are gone.
- HCrafter counts the synths that finish and alerts you once when a set number in a row are done: 6 by default, 1 to 6 in Settings. It also alerts you when you run out of a material for another synth like the last one.
- A pause of more than a minute starts a new count. Refused and cancelled synths don't count.
- The Shopping list shows how far the run is, such as "2 of 6 synths done."
- "Seconds between synths" is gone, since nothing counts down.

### Sounds

- Each alert has its own sound: level-up, HQ, rare HQ, break, skill-up, no more skill-ups, synths done and out of a material. Pick one of HCrafter's sounds, one of your own .wav files from the sounds folder, or None. Play lets you hear each one.
- Five new sounds: Three chimes, Bell, Ding-dong, Blip and Alert.

### HQs and menus

- Only hard HQs get a banner and a sound by default: T0 (about 1 in 64) and T1 (about 1 in 16). T2 now counts as easy, like T3.
- The right-click menus use Tahoma at HCrafter's text size, like the rest of HCrafter, when the Tahoma font is on.

### Skill-ups

- The skill-up labels are now Optimal, Manageable and Risky.
- At a rank cap of 100, HorizonXI's cap, the Skill-up tab no longer tells you to rank up.

### Recipes

- Sonic Belt needs Leathercraft 107, as on HorizonXI.

### Fixes

- A drag sideways on a window's corner changes only its width, so a window that fits its content keeps fitting.
- A quick second grab right after a drag no longer resets the window.
- A drag ignores the mouse while the game reports it as unavailable.
- The Resource Planner first opens beside the recipe book.
- "Skill up to" and "Breaks" no longer run into their controls with large text or without Tahoma.
- Shopping list lines that don't fit end in "...".
- Item icons in tooltips no longer overlap at small text.
- A broken number in the settings file shows as the default in Settings.

## 1.1.0 (2026-10-18)

### Window size

- Drag the bottom right corner of the recipe book or the Resource Planner to change its width and height. The Shopping list's corner changes its width only, since its height follows its list.
- Double-click the corner to go back to the default size. The height then fits the content again.
- Sizes are saved with your settings at 100 percent, so the Size setting still scales the whole window.
- At 100 percent size, widths run from 460 to 1400 pixels for the recipe book, 480 to 1400 for the Resource Planner and 260 to 720 for the Shopping list. The recipe book and the Resource Planner stay at least 240 pixels tall. No window grows taller than the game window.

### Text size

- A Text size setting under Look, from 80 to 130 percent. It changes only the text. Size still scales whole windows.
- Buttons, tabs, chips, checkboxes and steppers grow with the text. Rows that run out of room wrap to a second line or end in "...". Letters drawn on icon stand-ins keep their size.

### Settings

- Settings saved by 1.0.0 carry over. Windows open at the same widths as before.

## 1.0.0 (2026-10-17)

First release. Built from the crafty component of xitools v0.26 by lin (GPL-3.0), which ships unchanged in Aravix's xitools 0.27. Changes from that code:

### Look

- Standalone addon with its own windows, settings and commands (`/hcrafter`, `/hcraft`).
- Every window is drawn in a game-style look modeled on XIUI: framed panels with corner brackets, item slots, gradient bars, chips and gold section titles. Navy or Charcoal frame, adjustable opacity and size.
- Item icons and guild emblems come from the game's own pictures. The emblems are the craft imagery status icons. Drawn stand-ins replace any that can't load.
- Tahoma text with a thin outline, loaded once when the addon loads. Without Tahoma, imgui's own font is used.

### Recipe book

- Craftable materials open into their own recipes, nested to any depth, with a picker when several recipes make one item.
- Material rows show what you carry against what the recipe uses, colored by whether your inventory or your other bags and characters cover it, and where else you have it.
- An HQ tier ladder per recipe. Under cap, it shows your chance to succeed.
- Chips for image support that would reach the next tier, imagery on another craft, a crafting ring that blocks HQ, and how good the recipe is for skill-ups.
- Recent recipes show when the search is empty. A search with one match opens it.
- Search by material. Search uses plain text, so symbols in a search can't cause an error.

### Estimates

- HQ tiers and one-craft success follow the HorizonXI wiki. Recipes with more than one craft use HCrafter's own estimate: about 92 percent success at cap with two crafts and 91 percent with three, less 10 points for each level under cap in any of the crafts.
- Gear bonus read from the crafting gear you wear, or typed per craft.
- Image support counts only while that craft's imagery buff is on, at Basic +1 or Advanced +3.
- Anti-HQ crafting rings are detected in the ring slots.

### Resource Planner

- Queue recipes, set synth counts, pick Buy or Make per material, see items to buy in stacks, synths in order, leftovers, key items and odds. (This was the shopping list.)
- Costs from your prices, with an estimated total.
- Skill-up tab: recipes ranked Optimal, Costly or Dangerous for a craft, an estimate of synths to a target level, your rank cap, a choice of break rule, and the option to use your own measured skill-up rate.

### Shopping list

- A quest-tracker style list over the game for your queue.
- The ready cue for your next `/lastsynth`: a countdown, then a toast and a sound when the next synth should go through, or what ran out. It never presses anything.
- How good your last recipe still is for skill-ups.

### Fanfare and sounds

- Banners and sounds for level-ups, hard HQs (bigger the rarer), breaks with what was lost, and when your repeated recipe stops giving skill-ups. Optional banners for easy HQs and for every skill-up.
- Five original sounds made for HCrafter (`sounds\`).

### Prices

- Prices you type in game or with `/hcrafter price`, shared by all characters in `config\addons\hcrafter\prices.csv`. Lines may give a name instead of an item id. Saving a price changes only that item's line, keeps your extra columns, and never writes over a file it couldn't read.

### Craft data

- Craft levels and guild ranks read from the game's skills packet. Skill-ups are rounded to one decimal, so ten 0.1 skill-ups land exactly on a level.
- Craft history in its own file per character, kept to 500 synths, with the recipe and your skill before each synth so the skill-up rate can be measured. The latest 60 show with a summary.
- Snapshots of each character's bags so other characters can be counted. Names come from the zone-in packet. The other characters' files are read when you change character, after you zone, and every ten minutes.

### Fixes to crafty behavior

- A skill-up with an empty history no longer errors.
- An unknown crystal no longer errors.
- A synth result that never arrives no longer blocks tracking.
- An interrupted synth is recorded as a break that lost its materials.
- A "You must wait longer" refusal is not recorded as a synth.
- The synth request is read only as far as the packet goes. crafty read its inventory slot numbers 2 bytes apart, past the end of the 0x24-byte packet. A packet shorter than expected is skipped instead of raising an error.
- The skill flags crafty read from the synth result are gone. On LandSandBoat those bytes are plain skill ids.
- A synth is recorded as the recipe its result names, when the server lists the crystal and materials in the result. crafty used only the guess from the request, which a second request during lag could replace.
- Skill-ups attach only to the synth that just ended.
- A level shown after a skill drop is not treated as a level-up.
- A request the server never started gives way to the next one.

### Stability

- Each window draws on its own. If one hits an error or leaves something open, HCrafter closes what it had open in imgui, skips it for that frame and prints the problem once, and the other windows still draw.
- Numbers from a hand-edited settings file (levels, gear) are read as numbers, and gear bonuses as whole numbers.

### Tests

- `tests\harness.lua` runs HCrafter under LuaJIT with stand-ins for Ashita and imgui. It also has a preview mode that draws each window to an SVG file.

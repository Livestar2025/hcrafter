# HCrafter

A recipe book for Ashita v4 that looks like part of the game. It shows every recipe's skill levels and materials with the game's own item icons and guild emblems. Craftable materials open into their own recipes. It estimates your HQ odds, warns when image support would reach the next tier, plans what to buy and make, suggests recipes for skilling up, and cheers when something good happens.

HCrafter is based on the crafty component of [xitools](https://github.com/mousseng/xitools) by lin, version 0.26. The same crafty code also ships unchanged in Aravix's xitools 0.27. HCrafter is released under the same license, GPL-3.0. Its look follows [XIUI](https://github.com/tirem/XIUI)'s gold-on-dark style.

## Status on HorizonXI

HCrafter has not been approved for HorizonXI. Check the server's approved addon list before you use it there.

## Windows

| Window | What it is |
|---|---|
| HCrafter | The recipe book, with Recipes, History and Settings tabs |
| Resource Planner | What to buy and make for the recipes you queue, plus a Skill-up tab |
| Shopping list | A small list over the game, like a quest tracker, that also counts your /lastsynth macro |

Drag the bottom right corner of a window to resize it. The recipe book and the Resource Planner change width and height. The Shopping list changes width only. Double-click the corner to go back to the default size. HCrafter keeps each window's place and size.

## Recipe book

- The top row shows a guild emblem for each craft with your level under it. A craft at its rank cap gets a gold ring. A blue star means its imagery buff is on. Click an emblem for skill-up ideas in that craft.
- Search recipes by name, or tick Materials to find every recipe that uses an item. A search with one match opens it.
- With an empty search, your recent recipes are listed.
- An open recipe shows its item, the crafts it needs with a check or a cross, any key item, and the HQ tier ladder.
- Each material row shows the item, how many you carry against how many the recipe uses, and where else you have it, such as "+5 in Mog Safe" or "+3 on Mule".
  - A green border means your inventory covers it.
  - Amber means you have enough counting your other bags and characters.
- A material you can craft has an arrow. Click the row and its recipe opens underneath, as deep as the chain goes. When several recipes make it, pick Recipe 1, 2 or 3.
- Hover any item to see every place it is, each other character's last save date, and its price if you set one.
- Right-click any item to add its recipe to the Resource Planner or to set its price.

## HQ odds

| Levels over cap | Tier | HQ chance |
|---|---|---|
| 0 to 10 | T0 | about 1 in 64 |
| 11 to 30 | T1 | about 1 in 16 |
| 31 to 50 | T2 | about 1 in 4 |
| 51 and up | T3 | about 1 in 2 |

- At or above cap, success is about 95 percent.
- Under cap there is no HQ. Success drops 10 points per level and never goes below 5 percent. The ladder then shows your chance to succeed.
- On recipes with more than one craft, the craft with the smallest margin sets the tier. Success at cap is a little lower: about 92 percent with two crafts and 91 percent with three. Each level under cap, in any of the crafts, takes off 10 more points, down to 5 percent.
- Gear counts. HCrafter can read your crafting gear from what you wear, or you can type a bonus per craft in Settings.
- Image support counts only while that craft's imagery buff is on. Pick Basic +1 or Advanced +3 in Settings, since the game shows the same buff for both.
- Chips under a recipe tell you when support would help, such as "Advanced support (+3) reaches T1", when your imagery is for a different craft, and when a crafting ring you wear blocks HQ.

The tier table and the one-craft success rates come from the [HorizonXI wiki crafts page](https://horizonffxi.wiki/Category:Crafts). The weakest-craft rule, whole skill levels, the crafting ring rule and the HQ2 and HQ3 odds come from the [LandSandBoat](https://github.com/LandSandBoat/server) server code. The two- and three-craft success figures are HCrafter's own estimate. HorizonXI may differ, so treat every number here as an estimate.

## Resource Planner

### Plan tab

1. Right-click a recipe and pick "Add to Resource Planner."
2. Set how many synths with the minus and plus buttons.
3. For each craftable material, pick Buy or Make. A material you make adds its own materials. If several recipes make it, pick one.

The plan then shows:

- Every item to buy, with what you hold, how many to buy, and how to buy them in stacks, such as "2 stacks + 3, or 3 stacks (9 spare)."
- What each item costs, and an estimated total, for items with a price.
- Every synth to do, deepest step first, with what each makes, what is left over, and your HQ odds.
- Any key items the plan needs.

Notes on the math:

- Each recipe you make is rounded up to whole synths.
- What you already hold is used once per item, before that item's own materials are counted.
- Your other bags count by default. Your other characters count only if you tick that box.
- "Extra for breaks" adds that percentage of extra synths at every step, rounded up.
- You can queue several recipes. Shared materials are added together.

### Skill-up tab

- Pick a craft and a target level.
- HCrafter lists the recipes that give skill-ups now, best first, and labels each one:
  - Optimal: the recipe is above your skill and breaks are unlikely.
  - Manageable: breaks are common.
  - Risky: most synths break, and breaks give nothing.
- It estimates how many synths it takes to reach your target, using the best recipe at each level.
- With prices set, it shows what the materials cost per synth.
- Your gear and image support lower the break risk. Skill-ups still count from your real skill, as the server does.

The skill-up numbers follow LandSandBoat's era rules: about 60 percent per good synth below 50.0 and 25 percent from 50.0, up to 0.5 per skill-up below 60.0 and 0.1 from 60.0. A break can still skill up when the recipe is 1 to 5 levels over your skill. LandSandBoat gives breaks half the chance. The HorizonXI wiki says the same chance, so the tab lets you pick. HorizonXI may tune any of this, so HCrafter can also use the skill-up rate measured from your own synth history once it has 30 synths to go on.

## Shopping list

The Shopping list is a small list over the game for your queued recipes:

- What to buy, with a bar for what you hold.
- What to make, in order, with the craft and HQ tier.
- How far your `/lastsynth` macro is, such as "2 of 6 synths done."
- How good your last recipe still is for skill-ups, such as "Skill-up: Optimal, 2 levels to go."

### The alert after your macro

Many crafters synth once, then repeat it with a `/lastsynth` macro, often six lines long. HCrafter counts the synths that finish and alerts you once, so you know when to press the macro again.

- HCrafter counts each synth you start, one per macro line. A line the server refuses or cancels still counts, so the count stays in step with your macro.
- When a set number of lines in a row are done, a toast says so, such as "Macro done: 6 synths," and a sound plays. The number is 6 by default. Pick 1 to 6 in Settings.
- When you run out of a material for another synth like the last one, a toast says what, such as "Out of Namtar Bone."
- A pause of more than 25 seconds after the last line starts a new count.

The alert only shows and sounds. It never presses your macro and never sends anything.

## Fanfare and sounds

- A banner and a sound for each craft level-up.
- A banner for a hard HQ: T0 (about 1 in 64) gets the biggest one, T1 (about 1 in 16) a smaller one. Easy HQs, T2 and T3, stay quiet unless you turn them on.
- A banner for a break that lists what you lost. Breaks have no sound unless you pick one.
- A toast when the recipe you repeat stops giving skill-ups.
- Every skill-up can get a small banner too. It is off by default.
- An optional startup sound when HCrafter loads while you're in game, when you log in, and when `/hcrafter` shows the recipe book, and an optional shutdown sound when you log out or unload HCrafter. Both are None by default. Closing the game without logging out may cut the shutdown sound short.

Each one can be turned off in Settings. Each alert also has its own sound: one of the game's own sound effects, one of HCrafter's ten sounds, one of your own `.wav` files, or None. Press Play to hear it. "Play sounds" turns every sound off, and Volume sets the level of all of them from 0 to 150 percent.

### The game's own sounds

By default each alert plays one of FFXI's own sound effects, picked by ear for that alert. Breaks play nothing by default. The lists hold 42 game sounds: a second set picked for each alert, and 26 more named by folder and number. The list scrolls when it is taller than the screen allows.

- HCrafter ships no game audio. It reads each sound from your own game folder, `SquareEnix\FINAL FANTASY XI\sound\win\se` inside your HorizonXI `Game` folder, or wherever the game's `FFXiMain.dll` was loaded from.
- It turns the sound into a `.wav` file once and keeps it in `config\addons\hcrafter\sounds`, then plays that file. Changing the volume makes a copy at the new volume. HCrafter keeps at most 40 copies, deleting the oldest first but never the ones in use, and deletes copies whose sound file changed.
- It reads the game's PS-ADPCM and PCM sound files, which are most of them. The few in encrypted ATRAC3 are left alone.
- If your game folder or a sound can't be found or read, the alert plays HCrafter's own sound for it, and Settings marks it "(no game folder)", "(missing)" or "(can't read)".

### Your own sounds

Put your own `.wav` files in `addons\hcrafter\sounds` and they show up in the lists. A picked file that is no longer there plays nothing and shows as missing. They follow the volume when they are PCM (8, 16, 24 or 32-bit) or 32-bit float, mono or stereo, and up to 10 seconds long at 48 kHz. Others play at their own volume. HCrafter's own sounds were made for it from plain sine tones.

## Prices

- Right-click any item and pick "Set price," or type `/hcrafter price <item name> <gil>`.
- Prices are for one item, in gil, and are shared by all your characters.
- They live in `config\addons\hcrafter\prices.csv`, one item per line:

```
item_id,name,price,updated
4099,Earth Crystal,120,2026-10-17
```

- You can edit the file yourself. A line can leave `item_id` empty, and HCrafter matches the name against the items recipes use. Prices like `1,200` or `1200g` read fine.
- When HCrafter saves a price, it changes only that item's line. Your other lines, comments starting with `#`, the names you wrote and any columns you add after the date stay as they are. If the file can't be read at that moment, HCrafter doesn't save and tells you why.
- Type `/hcrafter prices` or press Reload in Settings after you edit it.
- HCrafter never looks up prices anywhere. It only uses what you put in.

## Craft levels, ranks and gear

- Your whole craft levels and guild ranks are read from the game when you log in or zone. Decimals come from skill-up messages. You can turn this off and type levels in Settings.
- Your rank sets your skill cap, which the skill-up tab respects.
- Crafting gear is read from what you wear. HCrafter knows the guild aprons, smocks, torques, gloves, spectacles and the anti-HQ crafting rings. You can turn detection off and type your gear bonus instead.

## History

The History tab keeps your last 500 synths with results, skill-ups and lost materials, and shows the latest 60 with a summary. It is saved in its own file for each character when you zone, log out or unload, and every five minutes after a change.

## Settings

- Look: Navy or Charcoal frame, opacity, size from 75 to 150 percent, text size from 80 to 130 percent, growing with Ashita's font size, game icons on or off, and the Tahoma font on or off. Size scales whole windows. Text size changes only the text. Without Tahoma or game icons, HCrafter draws its own.
- Fanfare, the alert after your macro, a sound for each alert, one volume for all of them, and the Shopping list's opacity.
- Hide with the map open, in cutscenes, or with the game interface hidden.

### Size on big screens

HCrafter grows with Ashita's own font size, set by `font0.size` in your Ashita boot `.ini`. HCrafter's 100% is drawn for Ashita's default size: 18 px on Ashita 4.3, 14 px before that. On Ashita 4.3, a 36 px font draws HCrafter at 200% and 28 px at 155%. Before 4.3, 28 px draws it at 200%. Size and Text size adjust from there. Settings shows both numbers. Untick "Grow with Ashita's font size" to size HCrafter on its own.

## Install

1. Copy the `addons\hcrafter` folder into your Ashita `addons` folder. On HorizonXI that is `HorizonXI\Game\addons`.
2. In game, type `/addon load hcrafter`.
3. If you also run xitools, you can turn off its crafty component so you don't have two recipe windows.

## Commands

| Command | What it does |
|---|---|
| `/hcrafter` | Show or hide the recipe book |
| `/hcrafter plan` | Show or hide the Resource Planner |
| `/hcrafter list` | Show or hide the Shopping list |
| `/hcrafter price <item> <gil>` | Set a price. Leave out the gil to clear it |
| `/hcrafter prices` | Read prices.csv again |
| `/hcrafter save` | Save this character's bags now |
| `/hcrafter clear` | Clear the craft history |
| `/hcrafter help` | List the commands |

`/hcraft` works the same as `/hcrafter`.

## How the other-character counts work

- The game only shows the bags of the character you are on.
- HCrafter saves a small snapshot of each character's bags whenever you play that character with HCrafter loaded. It saves a few seconds after your bags finish loading, then at most once a minute when something changes.
- The character's name comes from the zone-in packet, the way Ashita's own settings library does it. HCrafter saves only while the game shows that same character, and never at character select.
- Other characters' counts are as of their last save. Log in on each character once to get them on file.
- HCrafter reads the other characters' files when you change character, after you zone, and every ten minutes.
- Snapshots live in `config\addons\hcrafter\characters`. Each computer keeps its own files. They are safe to delete.
- If a bag is not readable at the moment, HCrafter keeps what it saw in that bag last time. Settings has a Bag check that shows which bags the game reports right now.

## Safety

- HCrafter only reads. It never sends packets and never acts for you.
- It reads incoming packets for synth results, skill-ups, craft levels and ranks, "You must wait longer," zoning and inventory loading. It also reads the outgoing synth request, the same way xitools crafty does.
- It reads your equipped items, your buffs and your character's status from game memory.
- It draws item and status icons from the pictures the game already has in memory, the way Ashita's equipmon addon does.
- It plays `.wav` files with Ashita's sound function: from its own sounds folder, and the copies it makes in `config\addons\hcrafter\sounds`. It lists its sounds folder to find any sounds you add.
- It reads the game's own sound effect files from your game folder, only the ones picked in Settings, to make those copies. To find the folder it asks Windows where the game's `FFXiMain.dll` was loaded from. To tell when a copy is out of date, it asks Windows for the size and last change time of the sound file it came from. It puts a finished copy in place with Windows' MoveFileEx, and names a copy it is still writing with its process id. It deletes only copies it made.
- It makes no network connections.
- It writes files only under `config\addons\hcrafter`. It reads its own Lua files in an empty environment, so a damaged file can only fail to load.
- If one of its windows hits an error or leaves something open in imgui, HCrafter closes what that window had open, skips it for the frame and prints the problem once.

## Data and limits

- The recipe table is the one xitools ships, which its authors generated from AirSkyBoat's recipe data. A recipe that differs on your server shows wrong here. Check the [HorizonXI wiki](https://horizonffxi.wiki/) when in doubt.
- HCrafter changes the recipes HorizonXI is known to have changed: Sonic Belt needs Leathercraft 107.
- LandSandBoat reports every HQ the same way, so HCrafter shows "HQ" rather than HQ1, HQ2 or HQ3 unless the server says which.
- History names each synth from the crystal and materials the server lists in the result. A server that doesn't list them falls back to the synth you asked for, which can be wrong if you press a different recipe while the server lags.
- HQ crystals are not counted toward the normal crystal of the same element.
- Other characters are matched by name only.
- All odds and synth counts are estimates.

## Credits

- lin for xitools and its crafty component, which this is built on, and Aravix for continuing xitools.
- The XIUI authors for the look HCrafter follows, and for the way XIUI loads fonts, outlines text and loads icons, which HCrafter's drawing code is modeled on.
- atom0s and the Ashita team for Ashita and the equipmon addon, whose icon loading HCrafter follows.
- Velyn for the memory signatures used to hide windows during cutscenes and with the game interface, by way of xitools.
- The LandSandBoat team, whose server code is the source for the synth rules and the crafting gear list.

## License

GPL-3.0. See [LICENSE](LICENSE). The changes from xitools crafty are listed in [CHANGELOG.md](CHANGELOG.md).

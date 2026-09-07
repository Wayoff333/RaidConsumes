# RaidConsumes

A raid consumable checker for OctoWoW (1.12-era vanilla API), built the same
way as WarlockCursePower: no external libraries, just raw Lua and stock
FrameXML templates.

## What it does

Click the minimap button (or type `/rc`) to open a window. It scans your
current raid (or party, or just you if solo), sorts everyone by class, and
lists each raider with what they're missing shown as small item icons (or
"Ready" in green). A summary line at the top reads "All N raiders are
ready!" or "X of N raiders missing a consumable."

Each missing icon uses the same live game icon as everything else in the
addon (see "Where the item list comes from, and the icons" below) -- hover
one to see the item's name in a tooltip. Underneath the icons, a second
line spells the names out too, so you're not stuck hovering everyone's
icons one at a time to know what a raid is short on. If someone's missing
more than 12 things, the icon row shows the first 12 plus a red "+N" for
the rest, and the names line lists as many full names as fit on one line
followed by "+N more" for whatever didn't (it can't wrap without running
into the next raider's row). Offline raiders just show "offline" as plain
text on both lines (there's no way to know what an offline player would be
missing).

Next to each raider's name is a small role button, tinted so it's
noticeably clickable rather than looking like plain text. By default (no
override yet) it shows their own class, abbreviated and colored to match
(e.g. a Warrior shows "War" in the Warrior class color) -- that's what
they're currently being checked against. Click it to cycle through the
roles that class can actually fill, then back to their class -- a Warrior
only ever offers Tank -> Physical DPS (never Healer, never Caster DPS), a
Priest only offers Healer -> Caster DPS (never Tank, never Physical DPS),
a Hunter/Rogue only offers Physical DPS, a Mage/Warlock only offers Caster
DPS, and a Paladin/Shaman/Druid offer whichever mix of the four they can
actually play. Overriding a raider onto a role checks them against that
role's checklist instead of their class's. Useful for something like a
Protection Warrior, whose consumable needs look nothing
like a generic Warrior's -- or for telling apart two DPS specs on
different classes that need completely different consumables, like a Ret
Paladin (Physical DPS) and a Balance Druid (Caster DPS), without lumping
them into one shared "DPS" list.

Note: the main window can only ever show whoever you're currently
grouped with -- your raid, or your party, or just yourself if you're
solo. There's no API to see players outside your own group, so if the
list looks empty, check that you're actually in a raid or party.

`/rc check` opens the window and scans in one step.

**Only show not ready** (checkbox above the roster list): a purely
cosmetic display filter that hides everyone currently marked "Ready" from
the list below, so a big raid's screen only shows who still needs to pop
something. It doesn't affect scanning, history, or auto-whisper -- all of
those still see and act on everyone, ready or not; the summary line at
the top also always reports the true full-raid counts regardless of this
filter.

**Auto-check** (checkbox near the bottom of the window, off by default):
re-scans on its own every N seconds while this window is open, instead of
needing a manual Check Raid click each time. The interval box next to it
is adjustable (2-300 seconds, defaults to 5) -- type a new number and
press Enter. Off by default, and it only ever runs while the window is
actually open: repeatedly scanning a full raid (each raider's buffs, read
one by one via a hidden tooltip) isn't free, so there's no point paying
that cost in the background while you're not even looking at the window.

**Auto-whisper** (checkbox near the bottom of the window, off by default
-- moved here from Settings in v2.6.0): automatically whispers a raider
the moment a scan finds them missing something required. It won't spam
the same raider every single scan (especially with Auto-check running
every few seconds) -- it whispers once when they're newly found missing
something, then waits for the cooldown next to the checkbox (30-1800
seconds, defaults to 300/5 min) before it'll whisper them again for still
being short, though a raider falling behind on something *new* always
triggers immediately regardless of the cooldown. It never whispers you
(the scanning player) and never whispers an offline raider. Works off
whatever scan already ran -- Check Raid, `/rc check`, or an Auto-check
tick.

**Send Whisper Now** (button at the bottom of the window, new in v2.6.0):
an on-demand version of the same whisper, for "I want to nag everyone
right now" instead of waiting on auto-whisper's pacing. Immediately
whispers every raider currently missing something from the last scan,
bypassing the cooldown entirely -- it works whether or not auto-whisper
itself is turned on. It still records into the same cooldown tracker
auto-whisper uses, so it won't immediately re-whisper the same people
again on the very next auto-check tick.

**Window opacity** (box at the bottom of the window, new in v2.6.0): sets
how transparent both this window and the Settings window are, from 20% to
100% (fully opaque, the default) -- type a new number and press Enter.
Handy if the window is sitting over something you need to see through
during a fight.

**Settings** opens a second window: pick a class OR a role (Tank / Healer /
Physical DPS / Caster DPS, spelled out in full -- these use the exact same
checklist system as a class, so you can maintain them independently of any
specific class) from the color-coded grid along the top (each button
tinted with that class's standard color, or a blue/green/orange/purple
accent for Tank/Healer/Physical DPS/Caster DPS), then a scrollable
checklist -- icon, checkbox, item name -- of every consumable from the
sheet, grouped by category (Tanks, Healers, Physical DPS, Caster DPS,
Universal (ALL), Paladin/Shaman Mix) and then by type (Flask, Food Buff,
General, Other), alphabetically within each. Whatever's ticked is required
for that class/role; every list is completely independent (ticking
something for Warriors doesn't touch Priests, and Physical DPS doesn't
touch Caster DPS). Every class/role starts with a sensible seeded default
(see `RaidConsumes_ClassDefaults` in `Data.lua`) -- "Reset to Defaults"
puts the currently-selected list back to that seed at any time if you've
been experimenting.

Picking a class or role also narrows which categories the checklist below
actually shows: a Mage only sees Caster DPS + Universal (ALL), not all six
categories' ~40 items -- a Warrior can never be a Healer or Caster DPS, so
it hides those; a Paladin/Shaman also gets the Paladin/Shaman Mix category
alongside their other roles; a role profile (Tank/Healer/Physical DPS/
Caster DPS) shows just its own matching category plus Universal (ALL).
The **Show categories** checkboxes right above the checklist reflect that
automatic narrowing and let you override it by hand -- tick any hidden
category (e.g. peek at the Tank list while a Paladin is selected) or
untick a shown one, independent of what's actually required; it's purely
a display filter, and switching classes resets it back to that class's
defaults.

**Sync This Class** / **Sync All** push whatever's ticked out to your
raid or party over the game's own addon-message channel, so everyone
else running RaidConsumes ends up with the exact same checklist as you
-- no need to configure Settings by hand on every character. "Sync This
Class" sends just the currently-selected class/role; "Sync All" sends
all 13 (9 classes + Tank/Healer/Physical DPS/Caster DPS) in one go. You
need to actually be in a raid or party for either to do anything.

**Only a raid officer/leader, or the party leader, can push a sync.**
Anyone else who clicks either button just gets a warning telling them to
use "Request Sync From Officer" instead -- nothing gets sent. This is
checked both when you click (so a regular raider gets an immediate
explanation) and again on the receiving end (so a sender claiming false
rank can't sneak one through) -- the receiving check looks up the
sender's rank in YOUR OWN view of the raid roster, not anything the
message itself claims. On top of that, "Accept checklist syncs from
raid/party" (checked by default) has to be on for you to accept incoming
syncs at all. Every sync that's sent, applied, or rejected prints a line
to chat, so nothing changes silently and you'll know if someone without
rank tried.

**Request Sync From Officer** is the other side of that: anyone can click
it (no rank needed to ask), which asks your raid/party's officers over
the same channel. Whichever officer's client is online with the addon
replies automatically -- privately, via whisper, not to the whole raid --
with every checklist. If nobody with officer rank has the addon running
at the time, nothing comes back (it's fire-and-forget, so there's no "no
one answered" message -- if you don't get a chat line back within a few
seconds, ask again or ask them directly).

`/rc sync` (needs rank), `/rc sync <class or role>` (needs rank -- for the
role lists you can type `physical`/`phys`/`melee` for Physical DPS or
`caster`/`ranged` for Caster DPS, as well as the exact `physdps`/
`casterdps` tokens), `/rc sync request`, `/rc sync on`, and `/rc sync off`
do the same things from the chat line if you'd rather type them.

**History** (button on the main window) shows how many times each raider
has actually popped each required consumable, tallied since tracking
started -- sorted by player, then most-used first. It only counts a fresh
application (not-had -> has, between two scans), so clicking Check Raid
five times during one still-active 2-hour flask counts as one use, not
five. It's an on-demand-scan approximation, not a combat-log audit: since
scanning doesn't run on a timer, whatever's true right when you click
Check Raid is what gets recorded, so it can miss something that's popped
and worn off entirely between two of your scans. "Clear All History"
wipes it (with a confirmation prompt) if you want to start fresh for a new
tier or season.

The History window opens next to whichever of your other RaidConsumes
windows is currently open -- to the right of Settings if Settings is
open, otherwise to the right of the main window if that's open, otherwise
centered on screen. (v2.6.3)

**Removed (v2.6.3): the "Missed" history view.** It logged once, the
moment someone showed up in your group who wasn't there on your previous
scan -- but that's presence edge-detection, not an actual measure of
whether they were prepared, and it turned out to not be a reliable or
accurate signal in practice. History now only tracks Usage, which reflects
something real: consumables actually popped.

**Export** (next to Clear All History) opens a second window with your
usage history as CSV text (`Player,Item,Count`, one line per player/item).
There's no 1.12 API for an addon to write a file or touch the OS clipboard
directly, so -- same as every other classic-era addon's "export string" --
click inside the box, Ctrl+A, Ctrl+C, then paste it into Excel/Google
Sheets, a text file, or Discord.

## Where the item list comes from, and the icons

All ~40 items are pulled from Waylock's "Recommend Consume Sheet" (the
General Consumes tab: Tanks / Healers / Physical DPS / Caster DPS / ALL
columns, plus the Paladin/Shaman 2-in-1 mixes).

**Most icons now pull live from the game itself and are correct.** Every
item with a known item ID (`itemID` in `Data.lua`) fetches its icon via
`GetItemIcon(itemID)` at display time -- that's authoritative, straight
from OctoWoW's own item data, not a guess. The Blizzard-original items were
checked against Wowhead Classic; the OctoWoW/Turtle-WoW-custom items
(the Danonzo's foods, the Concoctions, Dreamtonic, the Nordanaar/Medivh's
drinks, etc.) were looked up directly on OctoWoW's own database at
octowow.st/db. One item -- **Concoction of the Emerald Mongoose** --
couldn't be found in that database at all (only the Dreamwater and Arcane
Giant concoctions seem to exist there); it's still in the list with a
guessed icon in case that's a naming difference rather than a missing
item, but it's worth double-checking in-game.

**R.O.I.D.S.** (added in v2.2.0, seeded as a Warrior/Hunter/Rogue/Physical
DPS default alongside Ground Scorpok Assay, its OR-alternative on the
sheet) is worth a special mention: unlike every other item, its buff name
doesn't match its item name at all. Wowhead Classic and a second
independent database both agree the on-use effect it applies is called
"Rage of Ages" (+25 Strength for 60 minutes) -- which happens to also be
the name of the quest that originally rewards the item -- so that's what
`Data.lua` matches against instead of "R.O.I.D.S." itself. This is the
one item most worth double-checking against OctoWoW's actual buff
tooltip in-game before trusting it -- if the real buff name differs, `/rc
name` (below) fixes it in-game, no code edit needed.

**Wizard Oil** (added in v2.3.0, the lesser alternative to Brilliant Wizard
Oil -- same weapon-oil slot, seeded alongside it for Mage/Warlock/Caster
DPS) matches its item name exactly per Wowhead Classic, no naming surprise
like R.O.I.D.S.

**Heavy Runecloth Bandage**, also on the sheet's Universal (ALL) column,
is deliberately left out. Bandaging in 1.12 is a 3-second **channeled**
instant heal, not a buff -- it never produces the persistent buff-bar
aura this addon's scanning is built around, so there's no reliable way
for RaidConsumes to detect whether someone's actually been keeping
bandages on them. Adding it as a normal checklist item would just show
everyone as permanently missing it.

**If any icon is still wrong** (a server data difference, or a typo on my
end), you can fix it yourself in-game, no code edit needed:

```
/rc icon <itemKey>
```

...then **shift-click the real item into the same chat line** so its
item link lands right after the command (e.g. typing `/rc icon
flaskTitans ` and then shift-clicking Flask of the Titans from your
bags). That permanently overrides the icon for that item. `/rc icon list`
prints every override you've set; the `<itemKey>` for each item is its
`key` field in `Data.lua` (e.g. `flaskTitans`, `dreamtonic`).

Likewise, double check the item **names** themselves against OctoWoW's
actual tooltips (exact wording, including apostrophes) before trusting
this in a real raid -- that's what the buff-scanning matches against, and
it's separate from the icon. **If a name doesn't match** (a custom
OctoWoW/Turtle item applying a differently-named buff than expected --
R.O.I.D.S./"Rage of Ages" is the known example, but it's worth checking
any custom item), fix it yourself in-game the same way, no code edit
needed:

```
/rc name <itemKey> <exact buff name>
```

e.g. `/rc name danonzosDelight Danonzo's Tel'Abim Delight` -- type the
buff name exactly as its tooltip shows it (apostrophes included). This is
**additive**: it adds an extra name the item can also match, on top of
whatever's already in `Data.lua`, so it can never break an
already-working match. `/rc name list` prints every override you've set;
`/rc name clear <itemKey>` removes all of them for that item.

**If a raider's using something and it's still showing as missing**, and
you've double-checked the buff's tooltip name is right, `/rc debug` prints
every buff currently on you straight to chat -- its name, and whether it
matched a known item -- which tells you whether the problem is a name
mismatch (fixable with `/rc name` above), a buff whose tooltip came back
blank (the name-scanning technique itself failing on that buff), or that
you simply don't have the buff active when you checked.

**Resolved (v2.5.0): why food buffs and weapon oils were under-detecting.**
Both root causes are now confirmed (via `/rc debug` output and in-game
tooltip screenshots) and fixed:

- **Danonzo's Tel'Abim Delight** applies a buff generically named "Well
  Fed" (like all vanilla food), with the item-specific stat on the
  tooltip's *second* line -- confirmed exactly "Spell Damage increased by
  22.". That exact line is now matched directly, alongside the item's own
  name. If your other Food Buff items are still under-detecting, run `/rc
  debug` right after eating and add whatever line 2 actually says with
  `/rc name <itemKey> <that line>` -- a blanket "Well Fed" rule isn't used
  since it would risk misattributing a *different* food to the wrong
  item.
- **Wizard Oil, Brilliant Wizard Oil, Elemental Sharpening Stone, and
  Brilliant Mana Oil never show up via buff scanning at all.** These are
  temporary weapon enchants, and in vanilla they never produce a
  `UnitBuff` entry -- the only place "Wizard Oil (18 min)" appears is as
  an extra line on the *weapon item's own tooltip* when you hover it.
  These 4 items are now flagged `isWeaponEnchant = true` in `Data.lua` and
  checked via `GetWeaponEnchantInfo()` instead (the same self-only
  mechanic the "Known limitations" weapon-buff line below already
  describes) -- which also means, same as that limitation, they can only
  ever be checked for **your own** weapon, never a teammate's, so they're
  never flagged missing (or logged in history) for anyone but you. `/rc
  debug` now also reports your current weapon-enchant status directly, to
  make this visible without guessing.

**Resolved (v2.6.0): some icons in the Settings checklist showed the wrong
item entirely.** `GetItemIcon(itemID)` was being trusted blindly -- on a
private server, a hardcoded item ID sourced from a general (Wowhead
Classic/Turtle WoW) item database can actually belong to a completely
different, unrelated item on OctoWoW's own database, so `GetItemIcon`
returned a real icon, just the wrong one. The Settings checklist now
double-checks: it looks up `GetItemInfo(itemID)` and only trusts the
live icon if that item's actual name matches the item's label in
`Data.lua`; otherwise it falls back to the originally-guessed icon
instead of silently showing a mismatched one. (This was a separate bug
from the v2.5.0 icon-overlap fix below -- overlap was rows drawing under
another addon's frame, this was rows drawing the *wrong* icon correctly.)
(v2.6.1: also nudged the checklist icon a few pixels right -- it was
rendering almost flush against the Settings window's own left border.)

**Resolved (v2.6.0): History showed nothing, ever, no matter how much
usage or missed data was recorded.** Same root cause as the Settings
checklist icon-overlap bug just below: History's rows were parented to
its inner scroll frame at normal window strata, and something else in
this client's UI draws on top of that exact strip of the screen -- so the
rows never actually rendered, even though the data was there and being
correctly tallied the whole time. Bumped to the same TOOLTIP-strata fix
already applied to the main window and Settings rows.

**Dreamshard Elixir** was missing from Mage/Warlock/Caster DPS's default
checklist even though it's filed under the sheet's Healers column --
OctoWoW's own item database confirms it's actually class-unrestricted
(Allowable Classes: All), so as of v2.6.0 it's seeded for casters too. Its
category (which column it's grouped under in Settings) is unchanged.

**Resolved (v2.6.1): the Usage tab was showing inflated counts for
Wizard Oil, Brilliant Wizard Oil, Elemental Sharpening Stone, and
Brilliant Mana Oil** -- popping a single Wizard Oil was logging +1 to all
4 of those items at once, not just Wizard Oil. Root cause:
`GetWeaponEnchantInfo()` can only report whether *some* main-hand enchant
is currently active, never which specific one -- so there was never a way
to credit the one you actually used without also crediting the other 3
you didn't. They're now logged as a single shared "Weapon Enchant
(oil/stone)" line in the Usage tab instead of 4 separate (and
identical-looking, always-wrong) item counts. **Existing history is
automatically corrected the next time you log in** -- whatever count was
on any of the 4 real items gets folded into the new shared line (not
summed across all 4, just the one true count), then the 4 bogus entries
are removed. No action needed on your end.

**Resolved (v2.6.2): the main window's roster list was rendering off to
the left, and the Settings checklist was still crowding the left border
and spilling past the bottom.** Two separate bugs:

- The roster's scrollable list was accidentally anchored off the "Only
  show not ready" checkbox, which is deliberately off-center (shifted
  left so its own label reads centered next to it) -- inheriting that
  offset dragged the entire 380px-wide roster list about 40px past the
  window's own left edge. Re-anchored off the hint text above it instead
  (which stays properly centered under the window), same as before that
  checkbox existed.
- The Settings checklist's icon needed another nudge right (the v2.6.1
  nudge wasn't enough), and the Settings window itself was about
  20-40px too short for everything stacked above the checklist plus the
  checklist's own 14 rows -- the last category/item was rendering at or
  past the bottom border. Grown with real margin instead of another
  minimal bump.

**Changed (v2.6.3): windows now use a solid black background instead of
the semi-translucent stock dialog texture**, matching how CombatLedger's
Options window looks at 100% opacity. All four windows (main, Settings,
History, Export) now fill with a plain white texture tinted pure black
via `SetBackdropColor`, instead of Blizzard's `UI-DialogBox-Background`
art (which has its own baked-in translucency no matter what opacity you
set). The Window Opacity slider still works exactly the same as before --
it's a separate `SetAlpha()` call layered on top, so 100% now reads as
genuinely solid black instead of always-a-bit-see-through.

Adding a new item, or changing a class/role's default checklist, is a
small edit to `Data.lua` -- no other file needs to change.

## Known limitations (these are vanilla API limits, not bugs)

- **Weapon buffs (oils/stones/sharpening stones) can only be checked for
  yourself.** There is no 1.12 client API that exposes another player's
  temporary weapon enchant, so these items are only ever checked (and only
  ever flagged missing, or logged in history) against your own weapon --
  `/rc debug` prints your current weapon-enchant status directly if you
  want to see it without hovering your weapon yourself.
- **Identification is by buff tooltip name, not spellID.** True 1.12
  `UnitBuff()` only returns a texture and a stack count, so the addon opens
  a hidden tooltip on each buff to read its name. This is slower than a
  spellID lookup (only matters if you scan very large raids repeatedly --
  it's on-demand via the Check button, not a running timer) and it depends
  on the name matching exactly what's in `Data.lua`.
- **Role overrides are keyed by character name**, not a persistent
  character ID (vanilla doesn't expose one to addons) -- so they carry
  over across sessions/raids as long as the name doesn't change, but two
  different servers' same-named characters would share an override if you
  ever played both from the same account (unlikely to matter on a single
  private server).

## Install

Drop the `RaidConsumes` folder into `Interface/AddOns/` and restart or
`/reload`.

## Files

- `RaidConsumes.toc` -- addon manifest / load order
- `Data.lua` -- the editable item list (with item IDs, icons, categories),
  and per-class/role defaults
- `Scan.lua` -- roster scanning, buff-name matching (checks a buff's first
  two tooltip lines, and one matched name can satisfy more than one
  checklist item -- needed for shared generic buff names like "Well Fed"),
  weapon-enchant detection for `isWeaponEnchant` items, and usage-history
  recording (edge-detected, see History.lua)
- `UI.lua` -- the main class-sorted list (with per-raider role override,
  an "only show not ready" display filter, optional auto-check,
  auto-whisper + an on-demand Send Whisper Now button, and window
  opacity) and the Settings window (color-coded class/role grid +
  category/subcategory checklist with show/hide filtering and hoverable
  item-icon tooltips validated against the live item data, and sync
  controls)
- `History.lua` -- the Usage history window (who's popped what, how many
  times), with a Clear All option and a CSV Export window
- `Sync.lua` -- pushes/receives checklists over the raid/party addon-
  message channel ("Sync This Class" / "Sync All" in Settings, `/rc sync`)
- `Minimap.lua` -- minimap button
- `RaidConsumes.lua` -- SavedVariables init + slash commands (`/rc`,
  `/rc check`, `/rc icon`, `/rc name`, `/rc sync`, `/rc debug`)
- `test_scan.lua` -- a standalone logic + rendering test (name matching,
  class sorting, per-profile required defaults and isolation, missing-list
  computation, actual window/row rendering, icon resolution, reset-to-
  defaults, role overrides, class/role button coloring, per-category
  checklist filtering and its toggles, `/rc name` overrides, `/rc debug`,
  weapon-enchant items, usage-history edge-detection, the History window,
  checklist syncing including the trust checks, auto-check, and
  auto-whisper), run with `lua5.1 test_scan.lua` outside the game (not
  loaded in-game, not listed in the .toc). Useful if you extend `Data.lua`
  and want to sanity check the logic before hopping in-game.

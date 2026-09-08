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

**Items required by more than one role show up under each of them**
(v2.6.5, per Waylock's request): Flask of the Titans, Elixir of the
Mongoose, Elixir of Giants, Juju Power, Ground Scorpok Assay, and Elemental
Sharpening Stone are all seeded defaults for both Tanks and Physical DPS
(a Warrior needs the same Strength/Agility items whether tanking or
DPSing), and Dreamshard Elixir and Cerebral Cortex Compound (added
v2.6.7) are both defaults for Healers and Caster DPS -- each of these now
appears, fully checkable, in both of its sections instead of being buried
under just one (a Warrior, who sees both Tanks and Physical DPS by
default, will actually see Flask of the Titans listed twice -- that's
intentional, not a duplicate bug). There's still only one real checkbox
per item per class/role behind the scenes -- ticking or unticking it in
either section instantly updates the same one, and the other listing
reflects the change right away too.

**Added (v2.6.7): Cerebral Cortex Compound is now also a Mage/Warlock/
Caster DPS default**, per Waylock's report that it was "hiding under
Healers" -- it's an Intellect potion useful to any caster, not just
healers, so (same treatment as Dreamshard Elixir) it's now seeded on those
three checklists too and shows under both the Healers and Caster DPS
sections in Settings, on top of its existing Priest/Druid/Healer defaults.

**Fixed (v2.6.12): a full buff-name audit of every Flask/Elixir/Potion in
the list**, after Waylock reported "other flasks are not counting
either" following the v2.6.11 fixes. Researched each item's real applied
buff name via Wowhead Classic spell data (the item's own "Use:" tooltip
line links to a spell ID; that spell's title, on the Classic tab
specifically, is what actually shows on the buff bar and its tooltip --
not necessarily the item's own name), cross-checked against classicdb.ch
and a live buff-tracking addon's `GetSpellInfo()` table where possible.
Same story as v2.6.11's three: several of these drop a "Flask of"/"Elixir
of" prefix, and a couple don't resemble the item name at all. Every fix
below is additive (the item's own name still matches too):

| Item | Actual buff name |
|---|---|
| Flask of Distilled Wisdom | "Distilled Wisdom" |
| Elixir of Superior Defense | "Greater Armor" |
| Greater Stoneshield Potion | "Greater Stoneshield" |
| Elixir of Giants | "Elixir of **the** Giants" (extra word, easy to miss) |
| Ground Scorpok Assay | "Strike of the Scorpok" |
| Major Troll's Blood Potion | "Regeneration" |
| Mageblood Potion | "Mana Regeneration" |
| Elixir of Greater Firepower | "Greater Firepower" |
| Limited Invulnerability Potion | "Invulnerability" |

Two of these ("Regeneration" and "Mana Regeneration") are generic enough
that some unrelated effect could theoretically share the name -- flagged
in `Data.lua` as worth an `/rc debug` spot-check if either ever seems to
over-trigger.

**Confirmed correct, no change needed:** Flask of the Titans, Elixir of
the Mongoose, Juju Power, Juju Might, Greater Arcane Elixir, R.O.I.D.S.
("Rage of Ages", already known), and Potion of Quickness.

**Deliberately left alone, needs your own `/rc debug` to resolve:**

- **Elixir of Fortitude** -- two independent databases suggest the real
  buff is called "Health II" (a generic Blizzard template name used
  across many unrelated effects), but nothing could confirm it against an
  actual player's buff bar, and it's exactly the kind of generic name
  that could misfire on something else entirely. Not added automatically
  -- if this one's still not detecting for you, run `/rc debug` with it up
  and I'll add the real name once it's confirmed.
- **Elixir of Greater Nature Power** and **Potion of Quickness** --
  their item IDs (50237 / 61181) don't exist on Wowhead Classic/real
  Blizzard Classic at all, only on Turtle WoW's own database -- likely
  where OctoWoW's item set draws from for these two. Potion of Quickness's
  Turtle-WoW buff name matches its item name (confirmed, no change
  needed); Elixir of Greater Nature Power's couldn't be confirmed either
  way.

**Also newly documented (not a fix, a real limitation): Major Healing
Potion and Major Mana Potion can never be detected, for anyone, ever.**
They're instant-effect potions (a direct heal / direct mana restore) with
no timed buff or aura at all -- there's nothing for `UnitBuff` to see,
the same reason Heavy Runecloth Bandage was left out of the list entirely
(see below). Both are off by default on every class/role already, so
this has no real-world effect unless you specifically tick one on in
Settings -- if you do, it will read as permanently missing with no way to
clear it. Worth removing from the list entirely in a future version
rather than leaving a checkbox that can never be satisfied.

Food-buff items (Nightfin Soup, Mightfish Steak, Le Fishe Au Chocolat, and
similar) and the remaining OctoWoW/Turtle-WoW-custom items (Dreamshard
Elixir, Dreamtonic, the Concoctions, the rested-drink items) haven't been
audited yet -- Wowhead Classic doesn't have most of them (their item IDs
are outside Blizzard's real range), so they need either OctoWoW's own
database or your own `/rc debug` output to verify properly. Continuing
that pass separately.

**Fixed (v2.6.11): Flask of Supreme Power and Elixir of Shadow Power
weren't detecting for Waylock even with both genuinely active** (plus a
third, unreported one his own debug output caught: Cerebral Cortex
Compound). Root cause, found via `/rc debug`: same class of mismatch as
R.O.I.D.S./"Rage of Ages" below -- the actual buff each of these applies
drops the "Flask of"/"Elixir of" prefix, or in Cerebral Cortex Compound's
case doesn't resemble the item name at all:

| Item | Actual buff name |
|---|---|
| Flask of Supreme Power | "Supreme Power" |
| Elixir of Shadow Power | "Shadow Power" |
| Cerebral Cortex Compound | "Infallible Mind" |

All three now match on either name (additive -- the item's own name still
works too, in case that's ever what actually applies). Elixir of Frost
Power (v2.6.8) got the same defensive treatment ("Frost Power" added
alongside "Elixir of Frost Power") since it's the same family of item and
hasn't been confirmed in-game yet -- if it turns out unnecessary, it's
harmless.

**Changed (v2.6.10): weapon-enchant items now always show as missing for
anyone but yourself, rather than being excluded from their checklist.**
Follow-up to v2.6.9 below, after Waylock reported the same underlying
symptom again: excluding an item from the checklist and silently assuming
it's satisfied look identical on the roster (no missing icon either way),
so v2.6.9 didn't actually fix what he was seeing -- a raider's row still
read as fine regardless of whether they really had anything applied.
Wizard Oil, Brilliant Wizard Oil, Elemental Sharpening Stone, and
Brilliant Mana Oil now always count as missing for every raider except
you when required, since there's genuinely no way to confirm one for
anyone else. This does mean a raider who legitimately has one of these
applied will still show as missing it -- an accepted tradeoff (erring
toward "flag it" over "assume it's fine") given there's no API that could
ever tell the two cases apart. Still checked normally against your own
real weapon-enchant status, the one raider it's actually knowable for.

**Fixed (v2.6.9, superseded by v2.6.10 above): a raider's row could read
as having Wizard Oil (or the other weapon-enchant items) applied when
they actually just had some unrelated weapon enchant on.** Reported by
Waylock. Root cause: there's no 1.12 API to check anyone's weapon enchant
but your own, so for every other raider the old code just silently
assumed "satisfied" rather than flagging it missing -- which reads
exactly like "confirmed has Wizard Oil" even though it's really "no
idea." This version's fix (pulling the item out of a non-player raider's
checklist entirely) turned out to look the same on screen as the original
bug, hence v2.6.10 above.

**Added (v2.6.8): a Mage's checklist now auto-detects which of Frost/Fire/
Arcane Power they're running instead of expecting all three.** Elixir of
Frost Power, Elixir of Greater Firepower, and Greater Arcane Elixir are
mutually exclusive in practice -- a Mage only ever has the one matching
their current build's damage school active, since a raid elixir only
comes in "Frost" or "Fire" or "Arcane," never all three at once. All three
are now checked as Mage defaults, but they're tied together as a "spec
group" (`RaidConsumes_SpecGroups` in `Data.lua`): having ANY ONE of them
detected on a raider stops the other two from being flagged missing for
them, instead of (incorrectly) always showing 2 of the 3 as missing no
matter which one they're actually running. Each elixir is still tracked
completely separately -- its own icon, its own Usage-history count -- this
just stops the false "missing" flags. Elixir of Frost Power (item ID
17708) is a new item, confirmed against Wowhead Classic. This is scoped to
the Mage checklist specifically for now, per Waylock's request -- Warlock
and the generic Caster DPS role keep today's existing behavior (both
Elixir of Greater Firepower and Greater Arcane Elixir checked
independently, same as before).

**Fixed (v2.6.6): opening or scrolling a checklist with a multi-category
item on it (v2.6.5's Flask of the Titans/Dreamshard Elixir/etc. change,
just above) could throw "attempt to index local 'item' (a nil value)" and
error out**, confirmed by Ryan on the Warlock checklist specifically once
scrolled past its first ~14 rows. Root cause: the game's own Lua runtime
doesn't reliably handle a `for x in ipairs(someFunctionCall(...))` loop
the same way the plain Lua this addon is tested under does -- the same
underlying class of runtime quirk as the "category checkbox throws 'table
index is nil'" bug fixed back in the per-category filtering work. The
category-lookup code (`RaidConsumes_GetSortedItems` in `Data.lua`) is
rewritten to use plain numeric loops instead, and Settings now also (1)
never crashes outright even if a row somehow still comes back malformed --
it just hides that one row -- and (2) wraps the class/role button click in
the same safety net `RaidConsumes_ToggleSettings` already had, so any
future rendering bug shows a chat error message instead of a raw Lua error
box. If you still see anything odd on the checklist after this update,
`/reload` and let me know exactly which class/role and roughly which
scroll position.

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

**Clear-history prompt on entering a raid instance** (v2.6.4): zoning into
Molten Core, Onyxia's Lair, Blackwing Lair, Zul'Gurub, Ruins of Ahn'Qiraj,
Temple of Ahn'Qiraj, or Naxxramas pops a confirmation asking whether to
clear your usage history for a fresh start -- so last raid night's counts
don't linger into a new one just because you forgot to click Clear All
History yourself. It only asks once per continuous stay in the zone (it
won't re-ask every pull), and only actually clears anything if you click
"Clear History" -- declining, or clicking away, leaves history untouched.
There's no 1.12 API to detect "this is a raid instance" (that's a 2.0+
concept), so this works the same way everything else in the addon does:
by matching the zone's name. If OctoWoW ever adds a custom raid this list
doesn't know about, add it yourself with `/rc raidzone add <exact zone
name>` -- `/rc raidzone list` shows the current list, `/rc raidzone
remove <exact zone name>` takes one off, and `/rc raidzone reset` restores
the default 7.

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

**Elixir of Shadow Power** (added in v2.6.4, per Waylock's report) was
missing from the sheet's Caster DPS items entirely. It boosts Shadow
damage specifically, so it's seeded only for Warlock's default checklist
-- not Mage, and not the generic Caster DPS role -- since Balance Druids
and Elemental Shamans don't do Shadow damage. Item ID (9264) confirmed
against OctoWoW's own database.

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
- `Data.lua` -- the editable item list (with item IDs, icons, categories --
  optionally more than one via `extraCategories`, for items required by
  multiple roles), per-class/role defaults, and `RaidConsumes_SpecGroups`
  (items where having any one detected, like a Mage's Frost/Fire/Arcane
  elixir, covers the rest of the group for a given profile)
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
  times), with a Clear All option, a CSV Export window, and the raid-zone
  list + clear-history prompt for entering a raid instance
- `Sync.lua` -- pushes/receives checklists over the raid/party addon-
  message channel ("Sync This Class" / "Sync All" in Settings, `/rc sync`)
- `Minimap.lua` -- minimap button
- `RaidConsumes.lua` -- SavedVariables init + slash commands (`/rc`,
  `/rc check`, `/rc icon`, `/rc name`, `/rc sync`, `/rc raidzone`, `/rc debug`),
  and the `ZONE_CHANGED_NEW_AREA` handler that triggers the raid-entry
  clear-history prompt
- `test_scan.lua` -- a standalone logic + rendering test (name matching,
  class sorting, per-profile required defaults and isolation, missing-list
  computation, actual window/row rendering, icon resolution, reset-to-
  defaults, role overrides, class/role button coloring, per-category
  checklist filtering and its toggles, multi-category items, `/rc name`
  overrides, `/rc debug`,
  weapon-enchant items, usage-history edge-detection, the History window,
  the raid-zone clear-history prompt, checklist syncing including the
  trust checks, auto-check, auto-whisper, Mage spec-group elixir
  detection, weapon-enchant items always flagging missing for non-player
  raiders, and the v2.6.11/v2.6.12 buff-name audit fixes), run with `lua5.1
  test_scan.lua` outside the game (not
  loaded in-game, not listed in the .toc). Useful if you extend `Data.lua`
  and want to sanity check the logic before hopping in-game.

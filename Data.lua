--[[
RaidConsumes - Data.lua

Every individual consumable from Waylock's "Recommend Consume Sheet" for
OctoWoW (General Consumes tab: Tanks / Healers / Physical DPS / Caster DPS
/ ALL columns, plus the Paladin/Shaman 2-in-1 mixes), as one flat master
list. Required-ness is tracked per checklist "profile" -- either a CLASS
token (WARRIOR, MAGE, ...) or a ROLE token (TANK, HEALER, DPS) -- in
RaidConsumesDB.required[profile]. Settings lets you edit any class's list
OR any role's list; on the main window, each raider is checked against
their class's list by default, unless you've overridden that specific
raider to a role (see RaidConsumes_ToggleWindow / the role button on each
row in UI.lua), in which case they're checked against that role's list
instead. Useful for e.g. a Protection Warrior who needs the Tank list,
not the generic Warrior list.

Matched by BUFF NAME, not spellID or texture: true 1.12 UnitBuff() only
returns a texture and a stack count, so Scan.lua reads each buff's
tooltip text instead. Multiple names under one item are "any of these
counts" (e.g. either Rune of the Dawn or Seal of the Dawn satisfies it).

ICONS: where `itemID` is set below, the actual icon is pulled live via
GetItemIcon(itemID) at render time -- that's always correct, straight
from the game's own item data, and self-corrects if OctoWoW ever changes
an item. Those itemIDs were verified against Wowhead Classic. For items
OctoWoW/Turtle-WoW added that aren't in any public Blizzard database
(custom food, the Concoctions, etc.), `itemID` is left nil and the `icon`
string is a best-effort guess -- if it's wrong in-game, use `/rc icon
<key>` while shift-clicking the real item into chat to fix it yourself
(see README.md); no code edit needed.

RaidConsumes_ClassDefaults / the TANK/HEALER/PHYSDPS/CASTERDPS entries in
the same table seed a sensible starting checklist (matching the sheet's
columns), but every box is freely toggleable in Settings -- these are just
starting points, not fixed rules. "Reset to Defaults" in Settings puts a
class or role's list back to this seed at any time.

Verify names against OctoWoW's actual tooltips before trusting this raid
night -- exact wording (including apostrophes) matters for matching.
--]]

RaidConsumes_Classes = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

RaidConsumes_ClassLabels = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter",
    ROGUE = "Rogue", PRIEST = "Priest", SHAMAN = "Shaman",
    MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

-- Role "pseudo-class" profiles -- edited in Settings exactly like a real
-- class (same RaidConsumesDB.required[...] table, same EnsureRequiredDefaults
-- function), and assignable per-raider on the main window as an override
-- of that raider's class-based list. DPS is split into Physical and Caster
-- (matching the sheet's own Physical DPS / Caster DPS columns) since the
-- two need very different consumables -- a Ret Paladin and a Balance Druid
-- can both be overridden to "DPS" without sharing a checklist that fits
-- neither of them.
RaidConsumes_Roles = { "TANK", "HEALER", "PHYSDPS", "CASTERDPS" }

RaidConsumes_RoleLabels = {
    TANK = "Tank", HEALER = "Healer", PHYSDPS = "Physical DPS", CASTERDPS = "Caster DPS",
}

-- Which of the 4 roles above each class can actually be overridden to, in
-- cycle order -- a class never offers a role it can't realistically fill
-- (a Mage's role button never offers Tank or Healer, a Warrior's never
-- offers Healer, etc.), so the button only ever shows options that make
-- sense for that raider. Druid is the one true 4-role hybrid; everyone
-- else gets a subset.
RaidConsumes_ClassRoles = {
    WARRIOR = { "TANK", "PHYSDPS" },
    PALADIN = { "TANK", "HEALER", "PHYSDPS" },
    HUNTER = { "PHYSDPS" },
    ROGUE = { "PHYSDPS" },
    PRIEST = { "HEALER", "CASTERDPS" },
    SHAMAN = { "HEALER", "PHYSDPS", "CASTERDPS" },
    MAGE = { "CASTERDPS" },
    WARLOCK = { "CASTERDPS" },
    DRUID = { "TANK", "HEALER", "PHYSDPS", "CASTERDPS" },
}

-- Category order used for grouping the Settings checklist (sorted by this
-- order, then by subcategory, then alphabetically by label).
RaidConsumes_CategoryOrder = {
    "Tanks", "Healers", "Physical DPS", "Caster DPS", "Universal (ALL)", "Paladin/Shaman Mix",
}

-- Subcategory order within each category.
RaidConsumes_SubcategoryOrder = {
    "Flask", "Food Buff", "General", "Other",
}

RaidConsumes_Items = {
    -- ---- Tanks column ----
    { key = "elixirSuperiorDefense", label = "Elixir of Superior Defense", category = "Tanks", subcategory = "General", itemID = 13445, icon = "Interface\\Icons\\INV_Potion_66", names = { "Elixir of Superior Defense" } },
    { key = "greaterStoneshieldPotion", label = "Greater Stoneshield Potion", category = "Tanks", subcategory = "General", itemID = 13455, icon = "Interface\\Icons\\INV_Potion_69", names = { "Greater Stoneshield Potion" } },
    { key = "leFisheAuChocolat", label = "Le Fishe Au Chocolat", category = "Tanks", subcategory = "Food Buff", itemID = 84040, icon = "Interface\\Icons\\INV_Misc_Fishe_Au_Chocolate", names = { "Le Fishe Au Chocolat" } },
    { key = "dirgesChimaerokChops", label = "Dirge's Kickin' Chimaerok Chops", category = "Tanks", subcategory = "Food Buff", itemID = 21023, icon = "Interface\\Icons\\INV_Misc_Food_65", names = { "Dirge's Kickin' Chimaerok Chops" } },
    -- These 5 (plus Flask of the Titans below) are also on the Physical
    -- DPS default list -- a Warrior/Hunter/Rogue needs the exact same
    -- Strength/Agility items whether tanking or DPSing. `extraCategories`
    -- (see the comment on RaidConsumes_GetSortedItems in this file) makes
    -- each one show up, fully interactive, under BOTH the Tanks and
    -- Physical DPS sections of the Settings checklist instead of being
    -- buried under just Tanks -- there's still only one real "required"
    -- checkbox per item per profile, this only changes where it's shown.
    { key = "elixirMongoose", label = "Elixir of the Mongoose", category = "Tanks", extraCategories = { "Physical DPS" }, subcategory = "General", itemID = 13452, icon = "Interface\\Icons\\INV_Potion_32", names = { "Elixir of the Mongoose" } },
    { key = "elixirGiants", label = "Elixir of Giants", category = "Tanks", extraCategories = { "Physical DPS" }, subcategory = "General", itemID = 9206, icon = "Interface\\Icons\\INV_Potion_61", names = { "Elixir of Giants" } },
    { key = "jujuPower", label = "Juju Power", category = "Tanks", extraCategories = { "Physical DPS" }, subcategory = "General", itemID = 12451, icon = "Interface\\Icons\\INV_Misc_MonsterScales_11", names = { "Juju Power" } },
    { key = "groundScorpokAssay", label = "Ground Scorpok Assay", category = "Tanks", extraCategories = { "Physical DPS" }, subcategory = "General", itemID = 8412, icon = "Interface\\Icons\\INV_Misc_Dust_02", names = { "Ground Scorpok Assay" } },
    { key = "winterfallFirewater", label = "Winterfall Firewater", category = "Tanks", subcategory = "Food Buff", itemID = 12820, icon = "Interface\\Icons\\INV_Potion_92", names = { "Winterfall Firewater" } },
    { key = "jujuMight", label = "Juju Might", category = "Tanks", subcategory = "General", itemID = 12460, icon = "Interface\\Icons\\INV_Misc_MonsterScales_07", names = { "Juju Might" } },
    { key = "majorTrollsBloodPotion", label = "Major Troll's Blood Potion", category = "Tanks", subcategory = "General", itemID = 20004, icon = "Interface\\Icons\\INV_Potion_80", names = { "Major Troll's Blood Potion" } },
    { key = "flaskTitans", label = "Flask of the Titans", category = "Tanks", extraCategories = { "Physical DPS" }, subcategory = "Flask", itemID = 13510, icon = "Interface\\Icons\\INV_Potion_62", names = { "Flask of the Titans" } },

    -- ---- Healers column ----
    { key = "magebloodPotion", label = "Mageblood Potion", category = "Healers", subcategory = "General", itemID = 20007, icon = "Interface\\Icons\\INV_Potion_45", names = { "Mageblood Potion" } },
    -- Not actually healer-specific -- OctoWoW's own item page lists it as
    -- Allowable Classes: All, no restriction -- so it's seeded for Mage/
    -- Warlock/Caster DPS too. `extraCategories` (see the comment on
    -- RaidConsumes_GetSortedItems below) shows it under both the Healers
    -- and Caster DPS sections of the Settings checklist, not just Healers.
    { key = "dreamshardElixir", label = "Dreamshard Elixir", category = "Healers", extraCategories = { "Caster DPS" }, subcategory = "General", itemID = 61224, icon = "Interface\\Icons\\INV_Potion_113", names = { "Dreamshard Elixir" } },
    -- Temporary weapon enchant -- see the isWeaponEnchant comment below
    -- (Caster DPS column, next to Wizard Oil) for why this is flagged.
    { key = "brilliantManaOil", label = "Brilliant Mana Oil", category = "Healers", subcategory = "Other", itemID = 20748, icon = "Interface\\Icons\\INV_Potion_100", names = { "Brilliant Mana Oil" }, isWeaponEnchant = true },
    { key = "medivhsMerlotBlue", label = "Medivh's Merlot Blue", category = "Healers", subcategory = "Food Buff", itemID = 61175, icon = "Interface\\Icons\\INV_Drink_Waterskin_01", names = { "Medivh's Merlot Blue" } },
    { key = "empoweringHerbalSalad", label = "Empowering Herbal Salad", category = "Healers", subcategory = "Food Buff", itemID = 83309, icon = "Interface\\Icons\\INV_Misc_Food_Salad", names = { "Empowering Herbal Salad" } },
    { key = "nightfinSoup", label = "Nightfin Soup", category = "Healers", subcategory = "Food Buff", itemID = 13931, icon = "Interface\\Icons\\INV_Drink_17", names = { "Nightfin Soup" } },
    -- Per Waylock's request (v2.6.7): an Intellect potion useful to any
    -- caster, not just healers -- same treatment as Dreamshard Elixir
    -- above, shown under both Healers and Caster DPS and seeded as a
    -- Mage/Warlock/Caster DPS default alongside it, not just Priest/Druid/
    -- Healer.
    -- Confirmed via Waylock's own /rc debug output (v2.6.11): the buff this
    -- actually applies is named "Infallible Mind" ("Increases Intellect by
    -- 25."), not "Cerebral Cortex Compound" -- same kind of mismatch as
    -- R.O.I.D.S./"Rage of Ages" below. Both names kept (additive), in case
    -- a future item-data change ever makes the literal item name match too.
    { key = "cerebralCortexCompound", label = "Cerebral Cortex Compound", category = "Healers", extraCategories = { "Caster DPS" }, subcategory = "General", itemID = 8423, icon = "Interface\\Icons\\INV_Potion_32", names = { "Cerebral Cortex Compound", "Infallible Mind" } },
    { key = "flaskDistilledWisdom", label = "Flask of Distilled Wisdom", category = "Healers", subcategory = "Flask", itemID = 13511, icon = "Interface\\Icons\\INV_Potion_97", names = { "Flask of Distilled Wisdom" } },

    -- ---- Physical DPS column (some overlap with Tanks, listed once above) ----
    { key = "sourMountainBerries", label = "Sour Mountain Berries", category = "Physical DPS", subcategory = "Food Buff", itemID = 51711, icon = "Interface\\Icons\\INV_Misc_Food_74", names = { "Sour Mountain Berries", "Sour Mountain Berry" } },
    { key = "squidEelSkewer", label = "Squid Eel Skewer", category = "Physical DPS", subcategory = "Food Buff", itemID = 42163, icon = "Interface\\Icons\\INV_Misc_Food_68", names = { "Squid Eel Skewer" } },
    { key = "powerMushroom", label = "Power Mushroom", category = "Physical DPS", subcategory = "Food Buff", itemID = 51720, icon = "Interface\\Icons\\INV_Mushroom_14", names = { "Power Mushroom" } },
    { key = "smokedDesertDumplings", label = "Smoked Desert Dumplings", category = "Physical DPS", subcategory = "Food Buff", itemID = 20452, icon = "Interface\\Icons\\INV_Misc_Food_64", names = { "Smoked Desert Dumplings" } },
    { key = "mightfishSteak", label = "Mightfish Steak", category = "Physical DPS", subcategory = "Food Buff", itemID = 13934, icon = "Interface\\Icons\\INV_Misc_Food_47", names = { "Mightfish Steak" } },
    { key = "danonzosSurprise", label = "Danonzo's Tel'Abim Surprise", category = "Physical DPS", subcategory = "Food Buff", itemID = 60976, icon = "Interface\\Icons\\INV_Misc_Food_92", names = { "Danonzo's Tel'Abim Surprise" } },
    -- Temporary weapon enchant -- see the isWeaponEnchant comment below
    -- (Caster DPS column, next to Wizard Oil) for why this is flagged.
    -- Also on the Tanks default list (same weapon-oil slot regardless of
    -- spec), so it's shown under both via extraCategories.
    { key = "elementalSharpeningStone", label = "Elemental Sharpening Stone", category = "Physical DPS", extraCategories = { "Tanks" }, subcategory = "Other", itemID = 18262, icon = "Interface\\Icons\\INV_Stone_02", names = { "Elemental Sharpening Stone" }, isWeaponEnchant = true },
    -- The sheet lists this as "Ground Scorpok Assay OR R.O.I.D.S." -- an
    -- alternate Strength potion, same slot as Scorpok Assay. Its buff is
    -- named "Rage of Ages" (+25 Strength, 60 min) per Wowhead/classicdb --
    -- unusually, that name doesn't match the item name at all (it happens
    -- to share a name with the quest that awards the item), so this is
    -- the one most worth double-checking against OctoWoW's actual buff
    -- tooltip in-game before trusting it.
    { key = "roids", label = "R.O.I.D.S.", category = "Physical DPS", subcategory = "General", itemID = 8410, icon = "Interface\\Icons\\INV_Stone_15", names = { "Rage of Ages" } },

    -- ---- Caster DPS column (some overlap with Healers, listed once above) ----
    { key = "greaterArcaneElixir", label = "Greater Arcane Elixir", category = "Caster DPS", subcategory = "General", itemID = 13454, icon = "Interface\\Icons\\INV_Potion_25", names = { "Greater Arcane Elixir" } },
    -- Confirmed via Waylock's own /rc debug output: this food's buff shows
    -- up generically named "Well Fed" on tooltip line 1 (like every vanilla
    -- food buff), with the item-specific stat on line 2 -- exactly
    -- "Spell Damage increased by 22." -- so that line is matched directly
    -- rather than guessing at a blanket "Well Fed" rule that could
    -- misattribute a DIFFERENT food to this item.
    { key = "danonzosDelight", label = "Danonzo's Tel'Abim Delight", category = "Caster DPS", subcategory = "Food Buff", itemID = 60977, icon = "Interface\\Icons\\INV_Drink_21", names = { "Danonzo's Tel'Abim Delight", "Spell Damage increased by 22." } },
    { key = "dreamtonic", label = "Dreamtonic", category = "Caster DPS", subcategory = "General", itemID = 61423, icon = "Interface\\Icons\\INV_Potion_114", names = { "Dreamtonic" } },
    { key = "elixirGreaterFirepower", label = "Elixir of Greater Firepower", category = "Caster DPS", subcategory = "General", itemID = 21546, icon = "Interface\\Icons\\INV_Potion_60", names = { "Elixir of Greater Firepower" } },
    -- Added for Mage spec-based elixir detection -- see RaidConsumes_SpecGroups
    -- below. Item ID and buff name (matches item name exactly) confirmed via
    -- Wowhead Classic (wowhead.com/classic/item=17708). Its sibling elixirs
    -- (Shadow Power, Supreme Power below) both turned out to apply a buff
    -- named without the "Elixir of"/"Flask of" prefix -- added "Frost
    -- Power" defensively for the same reason, unconfirmed until a Mage
    -- runs /rc debug with it up (both names kept either way, additive).
    { key = "elixirFrostPower", label = "Elixir of Frost Power", category = "Caster DPS", subcategory = "General", itemID = 17708, icon = "Interface\\Icons\\INV_Potion_03", names = { "Elixir of Frost Power", "Frost Power" } },
    { key = "elixirGreaterNaturePower", label = "Elixir of Greater Nature Power", category = "Caster DPS", subcategory = "General", itemID = 50237, icon = "Interface\\Icons\\INV_Potion_106", names = { "Elixir of Greater Nature Power" } },
    -- Added per Waylock's request -- was missing from the sheet's Caster DPS
    -- items entirely. Boosts Shadow damage specifically, so it's seeded only
    -- for Warlock below (not Mage, and not the generic Caster DPS role,
    -- since Balance Druids/Elemental Shamans don't do Shadow damage either).
    -- Item ID confirmed against OctoWoW's own database (octowow.st/db/?item=9264).
    -- Confirmed via Waylock's own /rc debug output (v2.6.11): the buff this
    -- actually applies is named just "Shadow Power", dropping the "Elixir
    -- of" -- same kind of mismatch as R.O.I.D.S./"Rage of Ages" below. Both
    -- names kept (additive).
    { key = "elixirShadowPower", label = "Elixir of Shadow Power", category = "Caster DPS", subcategory = "General", itemID = 9264, icon = "Interface\\Icons\\INV_Potion_23", names = { "Elixir of Shadow Power", "Shadow Power" } },
    -- isWeaponEnchant: confirmed via a screenshot of Waylock's own weapon
    -- tooltip that temporary weapon enchants (oils/stones) NEVER show up
    -- via UnitBuff scanning in vanilla at all -- "Wizard Oil (18 min)" only
    -- ever appears as an extra line on the WEAPON ITEM's own tooltip, and
    -- /rc debug (which lists everything UnitBuff reports) never sees it
    -- either. Structurally undetectable via name-matching, so these 4
    -- items (this one, Wizard Oil below, Brilliant Mana Oil under Healers,
    -- Elemental Sharpening Stone under Physical DPS) are satisfied instead
    -- via GetWeaponEnchantInfo() -- see entry.weaponBuff/weaponBuffKnown in
    -- Scan.lua, and the isWeaponEnchant branch in MissingKeysFor/
    -- MissingItemsFor. That API only ever reports the SCANNING PLAYER's own
    -- weapon (no client API exists for anyone else's), so these items are
    -- only ever flagged missing for yourself, never for other raiders.
    { key = "brilliantWizardOil", label = "Brilliant Wizard Oil", category = "Caster DPS", subcategory = "Other", itemID = 20749, icon = "Interface\\Icons\\INV_Potion_105", names = { "Brilliant Wizard Oil" }, isWeaponEnchant = true },
    -- The sheet's lesser weapon-oil alternative to Brilliant Wizard Oil (same
    -- slot, can't have both applied at once) -- included alongside it the
    -- same way Ground Scorpok Assay/R.O.I.D.S. are paired.
    { key = "wizardOil", label = "Wizard Oil", category = "Caster DPS", subcategory = "Other", itemID = 20750, icon = "Interface\\Icons\\INV_Potion_104", names = { "Wizard Oil" }, isWeaponEnchant = true },
    -- Confirmed via Waylock's own /rc debug output (v2.6.11): the buff this
    -- actually applies is named just "Supreme Power", dropping the "Flask
    -- of" -- same kind of mismatch as R.O.I.D.S./"Rage of Ages" below. Both
    -- names kept (additive).
    { key = "flaskSupremePower", label = "Flask of Supreme Power", category = "Caster DPS", subcategory = "Flask", itemID = 13512, icon = "Interface\\Icons\\INV_Potion_41", names = { "Flask of Supreme Power", "Supreme Power" } },

    -- ---- ALL column (universal, off by default -- see RaidConsumes_ClassDefaults) ----
    { key = "restedDrink", label = "Nordanaar Herbal Tea / Tea With Sugar", category = "Universal (ALL)", subcategory = "Food Buff", itemID = 61675, icon = "Interface\\Icons\\INV_Drink_Waterskin_03", names = { "Nordanaar Herbal Tea", "Tea With Sugar" } },
    { key = "wineBuff", label = "Medivh's Merlot / Rumsey Rum Black Label", category = "Universal (ALL)", subcategory = "Food Buff", itemID = 61174, icon = "Interface\\Icons\\INV_Drink_Waterskin_05", names = { "Medivh's Merlot", "Rumsey Rum Black Label" } },
    { key = "elixirFortitude", label = "Elixir of Fortitude", category = "Universal (ALL)", subcategory = "General", itemID = 3825, icon = "Interface\\Icons\\INV_Potion_43", names = { "Elixir of Fortitude" } },
    { key = "zanzaBuff", label = "Spirit / Swiftness of Zanza", category = "Universal (ALL)", subcategory = "General", itemID = 20079, icon = "Interface\\Icons\\INV_Potion_30", names = { "Spirit of Zanza", "Swiftness of Zanza" } },
    { key = "majorHealingPotion", label = "Major Healing Potion", category = "Universal (ALL)", subcategory = "General", itemID = 13446, icon = "Interface\\Icons\\INV_Potion_54", names = { "Major Healing Potion" } },
    { key = "majorManaPotion", label = "Major Mana Potion", category = "Universal (ALL)", subcategory = "General", itemID = 13444, icon = "Interface\\Icons\\INV_Potion_76", names = { "Major Mana Potion" } },
    { key = "limitedInvulnerabilityPotion", label = "Limited Invulnerability Potion", category = "Universal (ALL)", subcategory = "General", itemID = 3387, icon = "Interface\\Icons\\INV_Potion_62", names = { "Limited Invulnerability Potion" } },
    { key = "potionOfQuickness", label = "Potion of Quickness", category = "Universal (ALL)", subcategory = "General", itemID = 61181, icon = "Interface\\Icons\\INV_Potion_08", names = { "Potion of Quickness" } },

    -- ---- Paladin/Shaman 2-in-1 mixes ----
    -- NOTE: "Concoction of the Emerald Mongoose" could not be found in
    -- OctoWoW's own item database at all (checked directly, several ways)
    -- -- only the Dreamwater and Arcane Giant concoctions exist there.
    -- Left without an itemID (guessed icon only) in case it's added later
    -- or the name is slightly different in-game; worth double-checking.
    { key = "concoctionEmeraldMongoose", label = "Concoction of the Emerald Mongoose", category = "Paladin/Shaman Mix", subcategory = "General", icon = "Interface\\Icons\\INV_Potion_92", names = { "Concoction of the Emerald Mongoose" } },
    { key = "concoctionDreamwater", label = "Concoction of the Dreamwater", category = "Paladin/Shaman Mix", subcategory = "General", itemID = 47414, icon = "Interface\\Icons\\INV_Green_Pink_Elixir_1", names = { "Concoction of the Dreamwater" } },
    { key = "concoctionArcaneGiant", label = "Concoction of the Arcane Giant", category = "Paladin/Shaman Mix", subcategory = "General", itemID = 47412, icon = "Interface\\Icons\\INV_Yellow_Purple_Elixir_2", names = { "Concoction of the Arcane Giant" } },
}

RaidConsumes_ItemByKey = {}
for _, item in ipairs(RaidConsumes_Items) do
    RaidConsumes_ItemByKey[item.key] = item
end

-- Starting checklist per class/role -- freely editable in Settings.
-- Not a rule about what a profile "must" run, just a reasonable seed so
-- Settings isn't a wall of unchecked boxes the first time you open it.
local function ItemSet(...)
    local set = {}
    local items = { ... }
    for _, k in ipairs(items) do
        set[k] = true
    end
    return set
end

RaidConsumes_ClassDefaults = {
    WARRIOR = ItemSet("flaskTitans", "elixirMongoose", "elixirGiants", "jujuPower",
        "groundScorpokAssay", "roids", "elementalSharpeningStone", "sourMountainBerries"),
    PALADIN = ItemSet("flaskDistilledWisdom", "magebloodPotion", "dreamshardElixir",
        "nightfinSoup", "concoctionEmeraldMongoose", "concoctionDreamwater", "concoctionArcaneGiant"),
    HUNTER = ItemSet("flaskTitans", "elixirMongoose", "elixirGiants", "jujuPower",
        "groundScorpokAssay", "roids", "elementalSharpeningStone", "sourMountainBerries", "squidEelSkewer"),
    ROGUE = ItemSet("flaskTitans", "elixirMongoose", "elixirGiants", "jujuPower",
        "groundScorpokAssay", "roids", "elementalSharpeningStone", "sourMountainBerries", "powerMushroom"),
    PRIEST = ItemSet("flaskDistilledWisdom", "magebloodPotion", "dreamshardElixir",
        "brilliantManaOil", "medivhsMerlotBlue", "nightfinSoup", "cerebralCortexCompound"),
    SHAMAN = ItemSet("flaskDistilledWisdom", "magebloodPotion", "dreamshardElixir",
        "nightfinSoup", "concoctionEmeraldMongoose", "concoctionDreamwater", "concoctionArcaneGiant"),
    -- Frost/Fire/Arcane are mutually exclusive in practice (a Mage only
    -- ever has the one matching their current build's damage school
    -- active) -- all three are checked here, but RaidConsumes_SpecGroups
    -- below stops the other two from being falsely flagged missing once
    -- any one of them is detected.
    MAGE = ItemSet("flaskSupremePower", "greaterArcaneElixir", "elixirGreaterFirepower", "elixirFrostPower",
        "brilliantWizardOil", "wizardOil", "dreamtonic", "danonzosDelight", "dreamshardElixir",
        "cerebralCortexCompound"),
    WARLOCK = ItemSet("flaskSupremePower", "greaterArcaneElixir", "elixirGreaterFirepower",
        "brilliantWizardOil", "wizardOil", "dreamtonic", "danonzosDelight", "dreamshardElixir",
        "elixirShadowPower", "cerebralCortexCompound"),
    DRUID = ItemSet("flaskDistilledWisdom", "magebloodPotion", "dreamshardElixir",
        "nightfinSoup", "cerebralCortexCompound"),

    -- Role profiles -- edited in Settings just like a class, and assignable
    -- per-raider on the main window to override that raider's class-based
    -- list (e.g. a Protection Warrior who should be checked as a Tank).
    TANK = ItemSet("flaskTitans", "elixirMongoose", "elixirGiants", "jujuPower",
        "groundScorpokAssay", "elementalSharpeningStone", "elixirSuperiorDefense",
        "greaterStoneshieldPotion", "majorTrollsBloodPotion", "jujuMight"),
    HEALER = ItemSet("flaskDistilledWisdom", "magebloodPotion", "dreamshardElixir",
        "brilliantManaOil", "nightfinSoup", "cerebralCortexCompound"),
    -- Melee/physical: a Ret Paladin, an Enhancement Shaman, a Feral/melee
    -- Druid, a Protection Warrior playing DPS -- same needs as the Warrior
    -- class default.
    PHYSDPS = ItemSet("flaskTitans", "elixirMongoose", "elixirGiants", "jujuPower",
        "groundScorpokAssay", "roids", "elementalSharpeningStone", "sourMountainBerries"),
    -- Caster/ranged: a Balance Druid, a Shadow Priest, an Elemental Shaman
    -- -- same needs as the Mage/Warlock class default.
    CASTERDPS = ItemSet("flaskSupremePower", "greaterArcaneElixir", "elixirGreaterFirepower",
        "brilliantWizardOil", "wizardOil", "dreamtonic", "danonzosDelight", "dreamshardElixir",
        "cerebralCortexCompound"),
}

function RaidConsumes_GetCheckableItems()
    return RaidConsumes_Items
end

-- True for the handful of items (Wizard Oil and friends) that never show up
-- via UnitBuff name-scanning at all in vanilla -- see the isWeaponEnchant
-- comment on those Data.lua entries. Scan.lua/UI.lua use this to satisfy
-- them via GetWeaponEnchantInfo() (entry.weaponBuff/weaponBuffKnown)
-- instead of the normal buff-name hit, and to only ever flag them missing
-- for the scanning player, never for other raiders.
function RaidConsumes_ItemRequiresWeaponEnchant(item)
    return item.isWeaponEnchant == true
end

-- "Spec groups": some profiles list more than one version of what's
-- really the same raid buff because which one a raider should be running
-- depends on something the addon has no other way to know -- a Mage's
-- current build decides whether they buff Frost, Fire, or Arcane damage,
-- and only ONE of those elixirs is ever active on them at a time. Checking
-- all three as "required" would otherwise flag the two they're NOT running
-- as permanently missing. This says: for the listed profile(s), if a
-- raider has ANY ONE of a group's items detected, none of that group's
-- OTHER items get flagged missing for them. Each item is still tracked
-- completely separately (own icon/itemID/usage-history) -- this doesn't
-- merge them into one item, it only stops the double-flagging.
--
-- Scoped to specific profiles, not applied wherever 2+ of these items
-- happen to be required -- per Waylock's "just Mage for now". Warlock and
-- the generic Caster DPS role default keep today's existing behavior
-- (Greater Arcane Elixir and Elixir of Greater Firepower both checked,
-- same as before) until/unless that's asked for too.
RaidConsumes_SpecGroups = {
    { items = { "elixirFrostPower", "elixirGreaterFirepower", "greaterArcaneElixir" }, profiles = { "MAGE" } },
}

-- Returns the sibling item-key list for itemKey's spec group IF one
-- applies to the given profile, otherwise nil. Numeric for-loops
-- throughout (not ipairs over a function result) -- see the crash
-- postmortem in README.md for why nested generic-for loops are avoided
-- here.
function RaidConsumes_GetSpecGroupFor(itemKey, profile)
    for i = 1, table.getn(RaidConsumes_SpecGroups) do
        local group = RaidConsumes_SpecGroups[i]
        local matchesProfile = false
        for p = 1, table.getn(group.profiles) do
            if group.profiles[p] == profile then
                matchesProfile = true
            end
        end
        if matchesProfile then
            for k = 1, table.getn(group.items) do
                if group.items[k] == itemKey then
                    return group.items
                end
            end
        end
    end
    return nil
end

-- Shared synthetic usageHistory item key for weapon enchants.
-- GetWeaponEnchantInfo() can only report whether SOME main-hand
-- enchant is active, never which one -- so Wizard Oil, Brilliant Wizard
-- Oil, Elemental Sharpening Stone, and Brilliant Mana Oil can't be told
-- apart by history logging (Scan.lua logs a "use" against this one shared
-- key instead of all 4 real items every time any single one is applied --
-- see the isWeaponEnchant comment above and Scan.lua's usage-history
-- block). History.lua gives it a friendly display label since it isn't a
-- real entry in RaidConsumes_Items.
RaidConsumes_WEAPON_ENCHANT_HISTORY_KEY = "__weaponEnchant"

-- Insertion-sort helper (plain strings). Used instead of table.sort with a
-- custom comparator -- WoW's older embedded Lua runtime can be finicky
-- about comparator-based sorts (it can throw "invalid order function for
-- sorting" even for comparators that look fine on paper), so grouping is
-- built by hand with straightforward insertion instead.
local function InsertSortedString(list, s)
    for i = 1, table.getn(list) do
        if s < list[i] then
            table.insert(list, i, s)
            return
        end
    end
    table.insert(list, s)
end

-- An item's `category` field is its PRIMARY category (used for icon/label
-- purposes and anywhere else that needs exactly one). Some items are
-- default-required for more than one role (e.g. Flask of the Titans, on
-- both the Tanks and Physical DPS default lists) -- `extraCategories`, an
-- optional list on the item, names any additional categories it should
-- ALSO appear under in the Settings checklist (see RaidConsumes_GetSortedItems
-- below). There's still only one real "required" checkbox per item per
-- profile (RaidConsumesDB.required[profile][item.key]) -- extraCategories
-- only changes where that same checkbox is SHOWN, so ticking it under
-- Physical DPS and checking Tanks shows it ticked there too, instantly.
-- Numeric for-loops throughout (not "for _, x in ipairs(...)") -- matches
-- the established, defensive style already used elsewhere in this file
-- for anything performance/correctness-sensitive, and sidesteps any doubt
-- about generic-for/closure behavior in the game's own older Lua runtime
-- (see the "this.category" comment on the category toggle buttons in
-- UI.lua for a previous, confirmed instance of that runtime not behaving
-- like lua5.1 despite passing every test here).
local function CategoriesFor(item)
    local cats = { item.category or "Other" }
    if item.extraCategories then
        for i = 1, table.getn(item.extraCategories) do
            table.insert(cats, item.extraCategories[i])
        end
    end
    return cats
end

-- Returns a flat list of { item = <item>, category = <cat>, subcategory =
-- <sub> } entries, sorted by category (per RaidConsumes_CategoryOrder),
-- then subcategory (per RaidConsumes_SubcategoryOrder), then alphabetically
-- by label. Used by the Settings checklist so items group visually by role
-- and type instead of appearing in raw declaration order. Any category or
-- subcategory not listed in the order tables gets its own group appended
-- after the known ones, alphabetically by name.
--
-- An item with more than one category (see CategoriesFor above) gets one
-- entry per category it belongs to, each wrapping the SAME item table --
-- that's what makes it show up, fully interactive, in every relevant
-- section instead of being buried under just its primary one. Entries are
-- wrapped (rather than returning items directly) specifically so each
-- occurrence carries its OWN display category/subcategory -- an item's own
-- `.category` field always names its primary category, which would be
-- wrong for the second (or third) occurrence otherwise.
function RaidConsumes_GetSortedItems()
    local catRank = {}
    for i, cat in ipairs(RaidConsumes_CategoryOrder) do catRank[cat] = i end
    local subRank = {}
    for i, sub in ipairs(RaidConsumes_SubcategoryOrder) do subRank[sub] = i end

    local catOrder, extraCats = {}, {}
    for _, cat in ipairs(RaidConsumes_CategoryOrder) do table.insert(catOrder, cat) end
    for _, item in ipairs(RaidConsumes_Items) do
        local itemCats = CategoriesFor(item)
        for ci = 1, table.getn(itemCats) do
            local cat = itemCats[ci]
            if not catRank[cat] and not extraCats[cat] then
                extraCats[cat] = true
                InsertSortedString(catOrder, cat)
            end
        end
    end

    -- Bucket by category, then by subcategory within category.
    local buckets = {} -- buckets[category][subcategory] = { entries }
    local subOrderByCat = {} -- subOrderByCat[category] = ordered list of subcategory names seen
    for _, item in ipairs(RaidConsumes_Items) do
        local sub = item.subcategory or "Other"
        local itemCats = CategoriesFor(item)
        for ci = 1, table.getn(itemCats) do
            local cat = itemCats[ci]
            buckets[cat] = buckets[cat] or {}
            subOrderByCat[cat] = subOrderByCat[cat] or {}
            if not buckets[cat][sub] then
                buckets[cat][sub] = {}
                -- Seed with the known subcategory order, then append unknowns alphabetically.
                if table.getn(subOrderByCat[cat]) == 0 then
                    for _, s in ipairs(RaidConsumes_SubcategoryOrder) do table.insert(subOrderByCat[cat], s) end
                end
                local known = false
                for _, s in ipairs(subOrderByCat[cat]) do if s == sub then known = true end end
                if not known then InsertSortedString(subOrderByCat[cat], sub) end
            end
            local bucket = buckets[cat][sub]
            local entry = { item = item, category = cat, subcategory = sub }
            local inserted = false
            for i = 1, table.getn(bucket) do
                if item.label < bucket[i].item.label then
                    table.insert(bucket, i, entry)
                    inserted = true
                    break
                end
            end
            if not inserted then
                table.insert(bucket, entry)
            end
        end
    end

    local sorted = {}
    for _, cat in ipairs(catOrder) do
        if buckets[cat] then
            for _, sub in ipairs(subOrderByCat[cat]) do
                if buckets[cat][sub] then
                    for _, entry in ipairs(buckets[cat][sub]) do
                        table.insert(sorted, entry)
                    end
                end
            end
        end
    end
    return sorted
end

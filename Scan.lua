--[[
RaidConsumes - Scan.lua

Scans the current raid/party roster for the consumables listed in
Data.lua. Runs on demand (the "Check Raid" button), not on a timer.

Why tooltip scanning: true 1.12 UnitBuff(unit, index) only returns a
texture path and a stack count, not a spellID or name. Setting a hidden
tooltip to the buff and reading its first couple of lines is slower
per-call but name-accurate -- the same technique classic-era raid addons
(oRA2, CTRA) used before richer buff APIs existed. Checking more than just
line 1 matters here: some buffs (vanilla's generic "Well Fed" food buff,
some temporary weapon enchants) don't put the specific item's name on the
first line at all.

Known vanilla API limitation: GetWeaponEnchantInfo() (temporary weapon
enchants -- oils/stones/sharpening stones) only ever reports YOUR OWN
weapon buff, never another raider's. There's no client API for that, so
it's shown as a single self-only line, not a raid-wide column.
--]]

local scanTooltip = CreateFrame("GameTooltip", "RaidConsumesScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

RaidConsumes_LastResults = {}
RaidConsumes_LastScanTime = nil

-- Most buffs put their item/spell name on tooltip line 1 (what this used to
-- read exclusively), but not all of them do: vanilla food/drink buffs are
-- all generically named "Well Fed" regardless of which specific food was
-- eaten, and temporary weapon enchants (oils/stones) have been reported to
-- format differently too. Reading the first couple of lines and letting
-- the caller check both against Data.lua's names covers more of these
-- without touching what already matched on line 1 alone.
local MAX_TOOLTIP_LINES_CHECKED = 2

local function GetBuffTooltipLines(unit, index)
    scanTooltip:ClearLines()
    scanTooltip:SetUnitBuff(unit, index)
    local lines = {}
    for i = 1, MAX_TOOLTIP_LINES_CHECKED do
        local fs = getglobal("RaidConsumesScanTooltipTextLeft" .. i)
        if fs then
            local text = fs:GetText()
            if text and text ~= "" then
                table.insert(lines, text)
            end
        end
    end
    return lines
end

function RaidConsumes_GetRosterUnits()
    local units = {}
    local n = GetNumRaidMembers()
    if n and n > 0 then
        for i = 1, n do
            table.insert(units, "raid" .. i)
        end
        return units
    end

    local pn = GetNumPartyMembers()
    table.insert(units, "player")
    if pn and pn > 0 then
        for i = 1, pn do
            table.insert(units, "party" .. i)
        end
    end
    return units
end

-- Builds a buffName -> {itemKey, ...} lookup for the checkable items (a
-- LIST of item keys per name, not just one -- some buffs are shared by
-- multiple items, e.g. vanilla's generic "Well Fed" food buff, so one
-- matched name can satisfy more than one checklist entry at once). Also
-- folds in any player-set /rc name overrides (RaidConsumesDB.nameOverrides)
-- -- extra buff names added on top of the built-in list, for custom
-- OctoWoW/Turtle items whose actual applied buff name doesn't match what's
-- in Data.lua (see the R.O.I.D.S./Danonzo's Delight comments there).
local function BuildLookup()
    local lookup = {}
    local function AddName(n, key)
        lookup[n] = lookup[n] or {}
        table.insert(lookup[n], key)
    end
    for _, item in ipairs(RaidConsumes_GetCheckableItems()) do
        for _, n in ipairs(item.names) do
            AddName(n, item.key)
        end
        local overrides = RaidConsumesDB and RaidConsumesDB.nameOverrides and RaidConsumesDB.nameOverrides[item.key]
        if overrides then
            for _, n in ipairs(overrides) do
                AddName(n, item.key)
            end
        end
    end
    return lookup
end


local function ScanUnitBuffs(unit, lookup)
    local hits = {}
    for i = 1, 32 do
        local texture = UnitBuff(unit, i)
        if not texture then
            break
        end
        for _, line in ipairs(GetBuffTooltipLines(unit, i)) do
            local itemKeys = lookup[line]
            if itemKeys then
                for _, key in ipairs(itemKeys) do
                    hits[key] = true
                end
            end
        end
    end
    return hits
end

-- "/rc debug" -- prints every buff currently on the player and whether it
-- matched a known consumable, straight to chat. For figuring out WHY
-- something isn't being detected: a name that doesn't match anything in
-- Data.lua (name mismatch -- fixable with "/rc name"), a buff whose tooltip
-- comes back blank (the name-scanning technique itself failing), or zero
-- buffs found at all (nothing active, or UnitBuff/tooltip scanning broken
-- on this server).
function RaidConsumes_DebugPlayerBuffs()
    local lookup = BuildLookup()
    local count = 0
    for i = 1, 32 do
        local texture = UnitBuff("player", i)
        if not texture then
            break
        end
        count = count + 1
        local lines = GetBuffTooltipLines("player", i)
        if table.getn(lines) > 0 then
            local matchedLabels = {}
            for _, line in ipairs(lines) do
                local itemKeys = lookup[line]
                if itemKeys then
                    for _, key in ipairs(itemKeys) do
                        local label = (RaidConsumes_ItemByKey[key] and RaidConsumes_ItemByKey[key].label) or key
                        table.insert(matchedLabels, label)
                    end
                end
            end
            local linesText = table.concat(lines, "\" / \"")
            if table.getn(matchedLabels) > 0 then
                DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes debug: buff " .. i .. " = \"" .. linesText .. "\" -> matched " .. table.concat(matchedLabels, ", "))
            else
                DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes debug: buff " .. i .. " = \"" .. linesText .. "\" -> no matching item in Data.lua (use /rc name to add it if this should count)")
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes debug: buff " .. i .. " has a texture but its tooltip returned no text at all")
        end
    end
    if count == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes debug: UnitBuff(\"player\", 1) found nothing at all -- either you have zero buffs active right now, or buff detection itself is being blocked at the API level (not a Data.lua naming issue).")
    else
        DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes debug: " .. count .. " total buff(s) found on you (see above for which matched).")
    end

    -- Temporary weapon enchants (Wizard Oil, Brilliant Wizard Oil, Elemental
    -- Sharpening Stone, Brilliant Mana Oil) never show up in the buff list
    -- above at all in vanilla -- checked separately here via
    -- GetWeaponEnchantInfo(), the only API that can see them.
    if type(GetWeaponEnchantInfo) == "function" then
        local hasMainHandEnchant = GetWeaponEnchantInfo()
        if hasMainHandEnchant then
            DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes debug: main-hand weapon enchant detected (Wizard Oil/Brilliant Wizard Oil/etc. -- can't tell which one, just that one is applied).")
        else
            DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes debug: no main-hand weapon enchant detected.")
        end
    end
end

-- Full roster scan. Populates and returns RaidConsumes_LastResults, where
-- each entry's `hits` table maps itemKey -> true for every checkable item
-- the raider currently has active.
function RaidConsumes_ScanRaid()
    local lookup = BuildLookup()

    local results = {}
    local units = RaidConsumes_GetRosterUnits()

    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local name = UnitName(unit)
            local _, class = UnitClass(unit)
            local online = true
            if UnitIsConnected then
                online = UnitIsConnected(unit) and true or false
            end

            local entry = {
                unit = unit,
                name = name,
                class = class,
                online = online,
                hits = {},
                weaponBuffKnown = false,
            }

            if online then
                entry.hits = ScanUnitBuffs(unit, lookup)
            end

            -- Weapon enchant is only ever knowable for the player themself.
            -- In a raid the player's own token is "raidN", not "player",
            -- so identity is checked with UnitIsUnit, not the token string.
            -- Done BEFORE the usage-history block below so it can fold
            -- weapon-enchant items (which never appear in entry.hits at
            -- all -- see isWeaponEnchant in Data.lua) into that same
            -- not-had -> has tracking, instead of those items being
            -- structurally unable to ever log a "use".
            if UnitIsUnit(unit, "player") and type(GetWeaponEnchantInfo) == "function" then
                local hasMainHandEnchant = GetWeaponEnchantInfo()
                entry.weaponBuffKnown = true
                entry.weaponBuff = hasMainHandEnchant and true or false
            end

            -- Usage history: count an item as "used" only on the
            -- not-had -> has transition between scans, not on every scan
            -- while it's still active (a flask lasts 2 hours -- clicking
            -- Check Raid five times during that window is one use, not
            -- five). RaidConsumes_LastHitsByPlayer is in-memory only (not
            -- persisted), so a UI reload while a buff is already up can
            -- at most double-count that one buff once -- an acceptable
            -- edge case for an on-demand-scan design.
            --
            -- Weapon-enchant items never appear in entry.hits (see
            -- isWeaponEnchant) -- they're tracked instead via
            -- weaponBuffKnown/weaponBuff, which is only ever true for the
            -- scanning player, so this can only ever log a weapon-enchant
            -- "use" for yourself, never for another raider.
            --
            -- IMPORTANT: GetWeaponEnchantInfo() only reports whether SOME
            -- main-hand enchant is active, never which one -- Wizard Oil,
            -- Brilliant Wizard Oil, Elemental Sharpening Stone, and
            -- Brilliant Mana Oil are indistinguishable from it. Crediting
            -- a "use" to all 4 real items every time any single one gets
            -- applied would inflate history for oils/stones never
            -- actually used (confirmed: popping one Wizard Oil logged +1
            -- to all 4) -- so they're excluded from the normal per-item
            -- loop below and logged once instead, as one shared bucket
            -- (RaidConsumes_WEAPON_ENCHANT_HISTORY_KEY, see Data.lua).
            if online and RaidConsumesDB then
                RaidConsumesDB.usageHistory = RaidConsumesDB.usageHistory or {}
                RaidConsumesDB.usageHistoryClass = RaidConsumesDB.usageHistoryClass or {}
                RaidConsumes_LastHitsByPlayer = RaidConsumes_LastHitsByPlayer or {}
                RaidConsumesDB.usageHistoryClass[name] = class
                local prevHits = RaidConsumes_LastHitsByPlayer[name] or {}
                for _, item in ipairs(RaidConsumes_GetCheckableItems()) do
                    if not RaidConsumes_ItemRequiresWeaponEnchant(item) then
                        local has = entry.hits[item.key]
                        if has and not prevHits[item.key] then
                            RaidConsumesDB.usageHistory[name] = RaidConsumesDB.usageHistory[name] or {}
                            RaidConsumesDB.usageHistory[name][item.key] = (RaidConsumesDB.usageHistory[name][item.key] or 0) + 1
                        end
                        prevHits[item.key] = has
                    end
                end
                if entry.weaponBuffKnown then
                    local hasEnchant = entry.weaponBuff
                    if hasEnchant and not prevHits[RaidConsumes_WEAPON_ENCHANT_HISTORY_KEY] then
                        RaidConsumesDB.usageHistory[name] = RaidConsumesDB.usageHistory[name] or {}
                        RaidConsumesDB.usageHistory[name][RaidConsumes_WEAPON_ENCHANT_HISTORY_KEY] =
                            (RaidConsumesDB.usageHistory[name][RaidConsumes_WEAPON_ENCHANT_HISTORY_KEY] or 0) + 1
                    end
                    prevHits[RaidConsumes_WEAPON_ENCHANT_HISTORY_KEY] = hasEnchant
                end
                RaidConsumes_LastHitsByPlayer[name] = prevHits
            end

            table.insert(results, entry)
        end
    end

    table.sort(results, function(a, b)
        return (a.name or "") < (b.name or "")
    end)

    RaidConsumes_LastResults = results
    RaidConsumes_LastScanTime = time()

    return results
end

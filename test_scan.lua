-- Standalone logic + rendering test for Data.lua/Scan.lua/UI.lua, run under
-- plain lua5.1 (no real WoW client available). Not shipped with the addon
-- (not listed in the .toc).
--
-- Every mocked frame is its OWN distinct table (not one shared dummy
-- object that returns itself for everything). That distinction matters:
-- a shared-singleton mock makes every row/frame alias the same object, so
-- per-row bugs (wrong target, a field never set, nil-checks that should
-- have failed) silently pass. A real WoW frame named via CreateFrame's
-- second argument also becomes a global of that name -- this mock does
-- the same, so the test can reach into RaidConsumesRow1, etc. exactly the
-- way the addon's own getglobal() calls do.

local frameRegistry = {}
local allFrames = {}

local function NewMock(frameType)
    local m = { _frameType = frameType, _shown = false, _checked = false }

    function m:SetPoint(...) self._point = { ... } end
    function m:ClearAllPoints() self._point = nil end
    function m:GetPoint()
        local p = self._point or { "CENTER", nil, "CENTER", 0, 0 }
        return p[1], p[2], p[3], p[4], p[5]
    end
    function m:SetWidth(w) self._width = w end
    function m:SetHeight(h) self._height = h end
    function m:GetWidth() return self._width end
    function m:GetHeight() return self._height end
    function m:SetBackdrop() end
    function m:SetMovable() end
    function m:EnableMouse() end
    function m:RegisterForDrag() end
    function m:RegisterEvent(e)
        self._events = self._events or {}
        self._events[e] = true
    end
    function m:SetFrameStrata(s) self._strata = s end
    function m:GetFrameStrata() return self._strata end
    function m:SetParent(p) self._parent = p end
    function m:GetParent() return self._parent end
    function m:IsVisible() return self._shown end
    function m:GetEffectiveAlpha() return self._alpha or 1 end
    function m:SetClampedToScreen(b) self._clamped = b end
    function m:SetToplevel(b) self._toplevel = b end
    function m:SetAlpha(a) self._alpha = a end
    function m:GetAlpha() return self._alpha end
    function m:SetFrameLevel(l) self._frameLevel = l end
    function m:GetFrameLevel() return self._frameLevel or 1 end
    function m:SetAllPoints(f) self._point = { "ALL", f } end
    function m:SetJustifyH() end
    function m:SetScript(event, fn)
        self._scripts = self._scripts or {}
        self._scripts[event] = fn
    end
    function m:GetScript(event) return self._scripts and self._scripts[event] end
    function m:Show() self._shown = true end
    function m:Hide() self._shown = false end
    function m:IsShown() return self._shown end
    function m:SetText(t) self._text = t end
    function m:GetText() return self._text end
    function m:SetTextColor(r, g, b) self._r, self._g, self._b = r, g, b end
    function m:SetTexture(t) self._texture = t end
    function m:GetTexture() return self._texture end
    function m:SetVertexColor(r, g, b, a) self._vr, self._vg, self._vb, self._va = r, g, b, a end
    function m:SetNormalTexture(t) self._normalTexture = t end
    function m:GetNormalTexture() return self._normalTexture end
    function m:SetChecked(v) self._checked = v and true or false end
    function m:GetChecked() return self._checked end
    function m:LockHighlight() self._highlighted = true end
    function m:UnlockHighlight() self._highlighted = false end
    function m:SetOwner() end
    function m:SetUnitBuff() end
    function m:ClearLines() end
    function m:StartMoving() end
    function m:StopMovingOrSizing() end
    function m:SetFontObject(f) self._font = f end
    function m:SetHighlightTexture() end
    function m:SetMultiLine(b) self._multiLine = b and true or false end
    function m:SetAutoFocus(b) self._autoFocus = b and true or false end
    function m:SetFocus() self._focused = true end
    function m:ClearFocus() self._focused = false end
    function m:HighlightText() self._highlightedText = true end
    function m:SetScrollChild(c) self._scrollChild = c end
    function m:SetMaxLetters(n) self._maxLetters = n end
    function m:GetFontString()
        if not self._fontString then self._fontString = NewMock("FontString") end
        return self._fontString
    end
    function m:CreateFontString(name, layer, template)
        local fs = NewMock("FontString")
        if name then _G[name] = fs; frameRegistry[name] = fs end
        return fs
    end
    function m:CreateTexture(name, layer)
        local tex = NewMock("Texture")
        if name then _G[name] = tex; frameRegistry[name] = tex end
        return tex
    end

    return m
end

-- ---- Fake raid roster ----
-- Waylock (Warlock): has his class-default caster items.
-- Aiden (Warrior): has his class-default items.
-- Brine (Warrior): has nothing.
-- Anahita (Priest): has everything except Flask of Distilled Wisdom.
local fakeRoster = {
    raid1 = { name = "Waylock", class = "WARLOCK",
        buffs = { "Flask of Supreme Power", "Greater Arcane Elixir", "Elixir of Greater Firepower", "Brilliant Wizard Oil", "Wizard Oil", "Dreamtonic", "Danonzo's Tel'Abim Delight" } },
    raid2 = { name = "Anahita", class = "PRIEST",
        buffs = { "Mageblood Potion", "Dreamshard Elixir", "Brilliant Mana Oil", "Medivh's Merlot Blue", "Nightfin Soup", "Cerebral Cortex Compound" } },
    raid3 = { name = "Brine", class = "WARRIOR",
        buffs = { "Some Unrelated Buff" } },
    raid4 = { name = "Aiden", class = "WARRIOR",
        buffs = { "Flask of the Titans", "Elixir of the Mongoose", "Elixir of Giants", "Juju Power", "Ground Scorpok Assay", "Rage of Ages", "Elemental Sharpening Stone", "Sour Mountain Berries" } },
}
-- "player" always aliases to Waylock (raid1) -- /rc debug and anything else
-- that reads UnitBuff("player", ...) directly (not through the roster scan)
-- needs this key to resolve even while a raid roster (not soloRoster) is
-- the active one.
fakeRoster.player = fakeRoster.raid1

-- Solo roster used for the "why is the main window blank" regression test:
-- exactly one unit, "player", with no raid/party at all.
local soloRoster = {
    player = { name = "Achillia", class = "WARLOCK",
        buffs = { "Flask of Supreme Power" } },
}

local activeRoster = fakeRoster -- switched to soloRoster for the solo test below

local currentTooltipText = nil
local fakeTooltip = {
    SetOwner = function() end,
    ClearLines = function() end,
    SetUnitBuff = function(self, unit, index)
        local u = activeRoster[unit]
        currentTooltipText = u and u.buffs[index]
    end,
}

_G.CreateFrame = function(frameType, name, parent, template)
    if frameType == "GameTooltip" then
        return fakeTooltip
    end
    local f = NewMock(frameType)
    table.insert(allFrames, f)
    if name then _G[name] = f; frameRegistry[name] = f end
    return f
end

-- Dispatches a fake game event to every mock frame that RegisterEvent'd
-- for it -- lets tests drive real event-driven code (like Sync.lua's
-- CHAT_MSG_ADDON handler) instead of only calling its exported functions
-- directly, the same "actually exercise the real wiring" principle as the
-- rendering tests below.
_G.FireEvent = function(eventName, a1, a2, a3, a4)
    _G.event = eventName
    _G.arg1, _G.arg2, _G.arg3, _G.arg4 = a1, a2, a3, a4
    for _, f in ipairs(allFrames) do
        if f._events and f._events[eventName] then
            local fn = f:GetScript("OnEvent")
            if fn then fn() end
        end
    end
end

_G.getglobal = function(name)
    if name == "RaidConsumesScanTooltipTextLeft1" then
        return { GetText = function() return currentTooltipText end }
    end
    return frameRegistry[name]
end

_G.UIParent = NewMock("Frame")
_G.GameTooltip = NewMock("GameTooltip")
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(self, msg) print("[chat] " .. tostring(msg)) end }

_G.math = math
_G.table = table
_G.string = string
_G.ipairs = ipairs
_G.pairs = pairs
_G.type = type
_G.tostring = tostring

_G.RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    PRIEST = { r = 1, g = 1, b = 1 },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
    MAGE = { r = 0.41, g = 0.8, b = 0.94 },
}
_G.FauxScrollFrame_Update = function() end
_G.FauxScrollFrame_GetOffset = function() return 0 end
_G.FauxScrollFrame_OnVerticalScroll = function() end

local fakeRaidCount = 4 -- mutable so the join-detection tests can simulate someone joining/leaving
_G.GetNumRaidMembers = function() return activeRoster == fakeRoster and fakeRaidCount or 0 end
_G.GetNumPartyMembers = function() return 0 end
_G.UnitExists = function(u) return activeRoster[u] ~= nil end
_G.UnitName = function(u)
    if u == "player" and activeRoster == fakeRoster then
        return activeRoster.raid1.name -- Waylock is "raid1", the player, in the fake raid roster
    end
    return activeRoster[u] and activeRoster[u].name
end

-- Raid rank mocks for the sync-authority tests: Waylock (raid1, "you") is
-- the raid leader, Anahita (raid2) is an officer/assist, Brine and Aiden
-- are plain members. youAreRaidLeader/youAreRaidOfficer are mutable so a
-- test can temporarily simulate being a non-officer.
local raidRanks = { Waylock = 2, Anahita = 1, Brine = 0, Aiden = 0 }
_G.GetRaidRosterInfo = function(i)
    local unit = "raid" .. i
    local u = activeRoster[unit]
    if not u then return nil end
    return u.name, raidRanks[u.name] or 0
end
local youAreRaidLeader = true
local youAreRaidOfficer = false
_G.IsRaidLeader = function() return youAreRaidLeader end
_G.IsRaidOfficer = function() return youAreRaidOfficer end
_G.IsPartyLeader = function() return false end
_G.GetPartyLeaderIndex = function() return 0 end

_G.__sentMessages = {}
_G.SendAddonMessage = function(prefix, msg, channel, target)
    table.insert(_G.__sentMessages, { prefix = prefix, msg = msg, channel = channel, target = target })
end
_G.__sentWhispers = {}
_G.SendChatMessage = function(msg, chatType, language, target)
    table.insert(_G.__sentWhispers, { msg = msg, chatType = chatType, target = target })
end
_G.UnitClass = function(u) return activeRoster[u].class, activeRoster[u].class end
local offlineUnits = {} -- mutable so a test can simulate one raid unit going offline
_G.UnitIsConnected = function(u) return not offlineUnits[u] end
_G.UnitBuff = function(u, i)
    local b = activeRoster[u].buffs[i]
    if b then return "faketexture" .. i end
    return nil
end
_G.UnitIsUnit = function(a, b)
    if b == "player" then
        if activeRoster == soloRoster then return a == "player" end
        return a == "raid1"
    end
    return a == b
end
_G.GetWeaponEnchantInfo = function() return true end
_G.time = function() return 123456 end
_G.date = function(fmt, t) return "12:34:56" end
_G.GetItemIcon = function(id) return id and ("Interface\\Icons\\FakeIcon" .. tostring(id)) or nil end
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function(name) _G.__lastStaticPopupShown = name end

RaidConsumesDB = { required = {}, syncEnabled = true, autoScanEnabled = false, autoScanInterval = 5, autoWhisperEnabled = false, autoWhisperCooldown = 300 }

dofile("Data.lua")
dofile("Scan.lua")
dofile("UI.lua")
dofile("History.lua")
dofile("Sync.lua")

local function check(cond, msg)
    if cond then
        print("PASS: " .. msg)
    else
        print("FAIL: " .. msg)
        os.exit(1)
    end
end

RaidConsumes_ScanRaid()
local rows, total, readyCount = RaidConsumes_ComputeDisplayRows()

check(total == 4, "scanned 4 raiders")

-- Class-sort order: WARRIOR (Aiden, Brine alphabetically), PRIEST (Anahita), WARLOCK (Waylock).
check(rows[1].entry.name == "Aiden", "row 1 is a Warrior (Aiden)")
check(rows[2].entry.name == "Brine", "row 2 is the other Warrior (Brine)")
check(rows[3].entry.name == "Anahita", "row 3 is the Priest")
check(rows[4].entry.name == "Waylock", "row 4 is the Warlock")

local byName = {}
for _, r in ipairs(rows) do byName[r.entry.name] = r end

check(table.getn(byName["Aiden"].missing) == 0, "Aiden (Warrior) has everything from the Warrior default list")
check(table.getn(byName["Waylock"].missing) == 0, "Waylock (Warlock) has everything from the Warlock default list")
check(table.getn(byName["Brine"].missing) > 0, "Brine (Warrior, nothing popped) is missing items")

-- Anahita (Priest) is missing only Flask of Distilled Wisdom from the Priest default list.
local anahitaMissing = byName["Anahita"].missing
check(table.getn(anahitaMissing) == 1, "Anahita is missing exactly 1 required item")
check(anahitaMissing[1] == "Flask of Distilled Wisdom", "Anahita is specifically missing Flask of Distilled Wisdom")

-- Per-class isolation: toggling a requirement for WARRIOR must not affect PRIEST's list.
local warriorReq = RaidConsumes_EnsureRequiredDefaults("WARRIOR")
warriorReq.elementalSharpeningStone = false -- Aiden already had this; untoggling shouldn't change his (still 0) missing count
local rows2 = RaidConsumes_ComputeDisplayRows()
local byName2 = {}
for _, r in ipairs(rows2) do byName2[r.entry.name] = r end
check(table.getn(byName2["Aiden"].missing) == 0, "Untoggling a satisfied item doesn't create a false miss")

local priestReq = RaidConsumes_EnsureRequiredDefaults("PRIEST")
check(priestReq.elementalSharpeningStone == false, "Priest's required table is independent of Warrior's (not seeded with that item at all)")

-- Turning on an extra requirement for Warrior that Brine lacks should show up by label.
warriorReq.flaskTitans = true -- already on by default, but explicitly confirm it's checked
local rows3 = RaidConsumes_ComputeDisplayRows()
local byName3 = {}
for _, r in ipairs(rows3) do byName3[r.entry.name] = r end
local brineMissing = byName3["Brine"].missing
local hasFlaskMissing = false
for _, label in ipairs(brineMissing) do
    if label == "Flask of the Titans" then hasFlaskMissing = true end
end
check(hasFlaskMissing, "Brine is specifically flagged missing 'Flask of the Titans'")

-- Category -> subcategory -> alphabetical sort for the Settings checklist.
local sortedItems = RaidConsumes_GetSortedItems()
check(table.getn(sortedItems) == table.getn(RaidConsumes_Items), "sorted list has the same item count as the master list")

local catRankOf, subRankOf = {}, {}
for i, cat in ipairs(RaidConsumes_CategoryOrder) do catRankOf[cat] = i end
for i, sub in ipairs(RaidConsumes_SubcategoryOrder) do subRankOf[sub] = i end
local lastCatRank, prevCategory, prevSub, prevLabel = 0, nil, nil, nil
local orderOk = true
for _, item in ipairs(sortedItems) do
    local catRank = catRankOf[item.category] or 999
    if catRank < lastCatRank then orderOk = false end
    if item.category == prevCategory then
        local subRank = subRankOf[item.subcategory] or 999
        local prevSubRank = subRankOf[prevSub] or 999
        if subRank < prevSubRank then orderOk = false end
        if item.subcategory == prevSub and prevLabel and item.label < prevLabel then orderOk = false end
    end
    lastCatRank = catRank
    prevCategory = item.category
    prevSub = item.subcategory
    prevLabel = item.label
end
check(orderOk, "sorted items are grouped by category, then subcategory (Flask/Food Buff/General/Other), then alphabetical by label")
check(sortedItems[1].category == "Tanks", "first sorted item is in the Tanks category")

-- ===================== rendering tests (the real bug-catchers) =====================
-- These actually invoke RaidConsumes_RefreshList() / RaidConsumes_ToggleSettings()
-- and inspect the mocked frame objects, instead of only checking the pure
-- data functions -- this is what would have caught "main window shows the
-- right count but no rows" and "Settings window never opens" before shipping.

RaidConsumes_ScanRaid()
RaidConsumes_RefreshList()

check(_G.RaidConsumesRow1 ~= nil, "row 1 frame exists")
check(_G.RaidConsumesRow1:IsShown() == true, "row 1 is shown after a 4-person scan")
check(_G.RaidConsumesRow1.nameText:GetText() == "Aiden", "row 1 displays Aiden's name")
check(_G.RaidConsumesRow5 == nil or _G.RaidConsumesRow5:IsShown() == false, "row 5 is hidden (only 4 raiders)")

-- Missing-item icons: Brine (row 2, popped nothing) shows icon buttons
-- instead of a text list, one per missing required item, each with a
-- texture and a hoverable item-name label.
local brineRow = _G.RaidConsumesRow2
check(brineRow.nameText:GetText() == "Brine", "row 2 is Brine (sanity check for the icon tests below)")
check(brineRow.missingText:IsShown() == false, "Brine's row hides the text list in favor of icons (he's missing things)")
check(brineRow.missingIcons[1]:IsShown() == true, "Brine's row shows at least one missing-item icon")
check(brineRow.missingIcons[1]:GetNormalTexture() ~= nil, "the first missing-item icon has a texture set")
check(type(brineRow.missingIcons[1].itemLabel) == "string", "the first missing-item icon has a hoverable item-name label")

-- Line 2: the missing items' names are spelled out under the icons, not
-- just hover-only tooltips.
check(brineRow.missingNamesText:IsShown() == true, "Brine's row shows the missing-item names line")
check(string.len(brineRow.missingNamesText:GetText() or "") > 0, "the missing-item names line has text in it")
check(string.find(brineRow.missingNamesText:GetText(), brineRow.missingIcons[1].itemLabel, 1, true) ~= nil,
    "the first missing item's full name actually appears in the names line")

-- Aiden (row 1) has everything -- "Ready" text, no icons, no names line.
check(_G.RaidConsumesRow1.missingText:GetText() == "Ready", "row 1 (Aiden, has everything) shows 'Ready'")
check(_G.RaidConsumesRow1.missingIcons[1]:IsShown() == false, "row 1 (Ready) shows no missing-item icons")
check(_G.RaidConsumesRow1.missingNamesText:IsShown() == false, "row 1 (Ready) shows no names line")

-- Offline: text, not icons or names (can't know what an offline raider
-- would have popped).
offlineUnits["raid3"] = true -- Brine (row 2) goes offline
RaidConsumes_ScanRaid()
RaidConsumes_RefreshList()
check(_G.RaidConsumesRow2.missingText:GetText() == "offline", "an offline raider shows 'offline' text instead of icons")
check(_G.RaidConsumesRow2.missingText:IsShown() == true, "the 'offline' text is actually shown")
check(_G.RaidConsumesRow2.missingIcons[1]:IsShown() == false, "an offline raider shows no missing-item icons")
check(_G.RaidConsumesRow2.missingNamesText:IsShown() == false, "an offline raider shows no names line")
offlineUnits["raid3"] = nil
RaidConsumes_ScanRaid()
RaidConsumes_RefreshList()

-- Overflow: missing more than MAX_MISSING_ICONS (12) required items gets
-- a "+N" label after the last icon instead of a silently truncated list.
local warriorReqAll = RaidConsumes_EnsureRequiredDefaults("WARRIOR")
for _, item in ipairs(RaidConsumes_Items) do
    warriorReqAll[item.key] = true
end
RaidConsumes_ScanRaid()
RaidConsumes_RefreshList()
local totalItemCount = table.getn(RaidConsumes_Items)
-- Weapon-enchant items (Wizard Oil and friends) are never flagged missing
-- for anyone but the scanning player -- see isWeaponEnchant -- so Brine
-- (not the player) has all of them silently excluded from his missing
-- count even though he's required for and doesn't have any of them.
local weaponEnchantCount = 0
for _, item in ipairs(RaidConsumes_Items) do
    if RaidConsumes_ItemRequiresWeaponEnchant(item) then
        weaponEnchantCount = weaponEnchantCount + 1
    end
end
local expectedMissing = totalItemCount - weaponEnchantCount
check(totalItemCount > 12, "sanity check: there are more than 12 total items to test icon overflow with")
check(_G.RaidConsumesRow2.missingIcons[12]:IsShown() == true, "all 12 icon slots are used when missing more than 12 items")
check(_G.RaidConsumesRow2.missingMoreText:IsShown() == true, "a '+N' label appears when missing more than 12 items")
check(_G.RaidConsumesRow2.missingMoreText:GetText() == "+" .. (expectedMissing - 12), "'+N' reflects exactly how many items didn't fit in the icon row (weapon-enchant items excluded, unknowable for a non-player raider)")
-- The names line is capped by character count (not item count) so it can
-- never wrap into the row below -- with this many missing, it must end in
-- a "+N more" summary rather than trying to spell out every single name.
check(string.find(_G.RaidConsumesRow2.missingNamesText:GetText(), " more$") ~= nil,
    "the names line falls back to a '+N more' summary when the full list would be too long to show")
RaidConsumes_ResetProfileToDefaults("WARRIOR")
RaidConsumes_ScanRaid()
RaidConsumes_RefreshList()

-- Solo case: exactly the scenario Ryan reported (main window shows the
-- correct "1 of 1" summary but the row list underneath was blank).
activeRoster = soloRoster
RaidConsumes_ScanRaid()
RaidConsumes_RefreshList()
local soloTotal = select(2, RaidConsumes_ComputeDisplayRows())
check(soloTotal == 1, "solo scan finds exactly 1 unit (the player)")
check(_G.RaidConsumesRow1:IsShown() == true, "solo: row 1 is shown")
check(_G.RaidConsumesRow1.nameText:GetText() == "Achillia", "solo: row 1 displays the player's own name")
activeRoster = fakeRoster

-- Settings window: opening it must not error, must actually show, and the
-- checklist rows must reflect the sorted category -> subcategory -> item
-- order with correct checked state for the selected class.
RaidConsumes_ToggleSettings()
check(_G.RaidConsumesSettingsFrame:IsShown() == true, "Settings window is shown after one ToggleSettings call")
check(RaidConsumesDB_SelectedClass ~= nil, "a class is auto-selected on first open")

RaidConsumes_SelectSettingsClass("WARRIOR")
-- Tanks category -> Flask subcategory (Flask of the Titans) -> Food Buff
-- subcategory (Dirge's..., Le Fishe..., Winterfall...) -> General subcategory.
check(_G.RaidConsumesSettingRow1.headerText:GetText() == "Tanks", "Settings row 1 is the 'Tanks' category header")
check(_G.RaidConsumesSettingRow1.headerText:IsShown() == true, "Settings row 1 header text is shown")
check(_G.RaidConsumesSettingRow1.icon:IsShown() == false, "Settings row 1 (a header) hides its icon")
check(_G.RaidConsumesSettingRow2.headerText:GetText() == "Flask", "Settings row 2 is the 'Flask' subcategory header")
check(_G.RaidConsumesSettingRow3.label:GetText() == "Flask of the Titans", "Settings row 3 is the Flask of the Titans item")
check(_G.RaidConsumesSettingRow3.headerText:IsShown() == false, "Settings row 3 (an item) hides its header text")
check(_G.RaidConsumesSettingRow4.headerText:GetText() == "Food Buff", "Settings row 4 is the 'Food Buff' subcategory header")
check(_G.RaidConsumesSettingRow5.label:GetText() == "Dirge's Kickin' Chimaerok Chops", "Settings row 5 is the first Food Buff item alphabetically")

-- Icon resolution: itemID-bearing items pull their icon live via GetItemIcon;
-- items without one fall back to the guessed icon string.
check(_G.RaidConsumesSettingRow3.icon.texture:GetTexture() == "Interface\\Icons\\FakeIcon13510", "Flask of the Titans icon resolves via GetItemIcon(itemID)")
RaidConsumes_SetIconOverride("flaskTitans", 99999)
RaidConsumes_RefreshSettings()
check(_G.RaidConsumesSettingRow3.icon.texture:GetTexture() == "Interface\\Icons\\FakeIcon99999", "/rc icon override wins over the built-in itemID")
check(RaidConsumesDB.iconOverrides.flaskTitans == 99999, "icon override is persisted in RaidConsumesDB")

-- Settings list icons are hoverable buttons (not plain textures) so they
-- can show a tooltip naming the item, same as the main window's missing
-- icons -- and headers/blank slots must not carry a stale label over from
-- whatever item last occupied that pooled row.
check(_G.RaidConsumesSettingRow3.icon.itemLabel == "Flask of the Titans", "item row's icon carries its item label for the hover tooltip")
check(_G.RaidConsumesSettingRow1.icon.itemLabel == nil, "header row's icon has no stale item label")

-- R.O.I.D.S. (the sheet's alternate Strength potion alongside Ground Scorpok
-- Assay): registered, resolves its icon via itemID, matched by its actual
-- buff name (which doesn't match the item name), and seeded as a default
-- for Warrior/Hunter/Rogue/Physical DPS alongside Ground Scorpok Assay.
check(RaidConsumes_ItemByKey.roids ~= nil, "R.O.I.D.S. is a registered item")
check(RaidConsumes_ItemByKey.roids.itemID == 8410, "R.O.I.D.S. has the correct item ID")
check(RaidConsumes_ItemByKey.roids.names[1] == "Rage of Ages", "R.O.I.D.S. is matched by its actual buff name, not its item name")
check(GetItemIcon(RaidConsumes_ItemByKey.roids.itemID) == "Interface\\Icons\\FakeIcon8410", "R.O.I.D.S. icon resolves via GetItemIcon(itemID)")
local roidsWarriorReq = RaidConsumes_EnsureRequiredDefaults("WARRIOR")
local roidsHunterReq = RaidConsumes_EnsureRequiredDefaults("HUNTER")
local roidsRogueReq = RaidConsumes_EnsureRequiredDefaults("ROGUE")
local roidsPhysReq = RaidConsumes_EnsureRequiredDefaults("PHYSDPS")
check(roidsWarriorReq.roids == true, "R.O.I.D.S. is a Warrior default")
check(roidsHunterReq.roids == true, "R.O.I.D.S. is a Hunter default")
check(roidsRogueReq.roids == true, "R.O.I.D.S. is a Rogue default")
check(roidsPhysReq.roids == true, "R.O.I.D.S. is a Physical DPS default")

-- Wizard Oil (the sheet's lesser alternative to Brilliant Wizard Oil, same
-- weapon-oil slot): registered, resolves its icon, and seeded for
-- Mage/Warlock/Caster DPS alongside Brilliant Wizard Oil.
check(RaidConsumes_ItemByKey.wizardOil ~= nil, "Wizard Oil is a registered item")
check(RaidConsumes_ItemByKey.wizardOil.itemID == 20750, "Wizard Oil has the correct item ID")
check(GetItemIcon(RaidConsumes_ItemByKey.wizardOil.itemID) == "Interface\\Icons\\FakeIcon20750", "Wizard Oil icon resolves via GetItemIcon(itemID)")
local wizardOilMageReq = RaidConsumes_EnsureRequiredDefaults("MAGE")
local wizardOilWarlockReq = RaidConsumes_EnsureRequiredDefaults("WARLOCK")
local wizardOilCasterReq = RaidConsumes_EnsureRequiredDefaults("CASTERDPS")
check(wizardOilMageReq.wizardOil == true, "Wizard Oil is a Mage default")
check(wizardOilWarlockReq.wizardOil == true, "Wizard Oil is a Warlock default")
check(wizardOilCasterReq.wizardOil == true, "Wizard Oil is a Caster DPS default")

-- ===================== weapon-enchant items (Wizard Oil and friends) =====================
-- Confirmed via Ryan's own screenshots: temporary weapon enchants never
-- show up via UnitBuff scanning in vanilla at all -- the enchant only shows
-- as an extra line on the WEAPON's own tooltip. isWeaponEnchant items are
-- satisfied instead via GetWeaponEnchantInfo() (self-only), and must never
-- be flagged missing for anyone but the scanning player.
check(RaidConsumes_ItemRequiresWeaponEnchant(RaidConsumes_ItemByKey.wizardOil) == true, "Wizard Oil is flagged isWeaponEnchant")
check(RaidConsumes_ItemRequiresWeaponEnchant(RaidConsumes_ItemByKey.brilliantWizardOil) == true, "Brilliant Wizard Oil is flagged isWeaponEnchant")
check(RaidConsumes_ItemRequiresWeaponEnchant(RaidConsumes_ItemByKey.brilliantManaOil) == true, "Brilliant Mana Oil is flagged isWeaponEnchant")
check(RaidConsumes_ItemRequiresWeaponEnchant(RaidConsumes_ItemByKey.elementalSharpeningStone) == true, "Elemental Sharpening Stone is flagged isWeaponEnchant")
check(RaidConsumes_ItemRequiresWeaponEnchant(RaidConsumes_ItemByKey.roids) == false, "an ordinary item (R.O.I.D.S.) is NOT flagged isWeaponEnchant")
-- (behavioral coverage -- satisfied via weaponBuff, never flagged for a
-- non-player raider -- follows below once FindRowByPlayerName exists)

-- ===================== settings grid: full (non-abbreviated) labels =====================
-- Physical DPS/Caster DPS used to show as "Phys DPS"/"Cast DPS" on the grid
-- buttons to fit a narrower button; the button (and window) were widened so
-- the full role name shows everywhere, consistent with Tank/Healer.
for i, profile in ipairs({ "TANK", "HEALER", "PHYSDPS", "CASTERDPS" }) do
    local btn = getglobal("RaidConsumesClassBtn" .. (9 + i)) -- 9 classes come first
    check(btn.profile == profile, "grid button " .. (9 + i) .. " is the " .. profile .. " role button")
    check(btn:GetText() == RaidConsumes_RoleLabels[profile], "the " .. profile .. " grid button shows its full label (\"" .. RaidConsumes_RoleLabels[profile] .. "\"), not an abbreviation")
end

-- ===================== settings: per-category show/hide filtering =====================
-- Selecting a class/role narrows the checklist to only the categories that
-- profile can actually use (RaidConsumes_ClassRoles), plus Universal (ALL)
-- always, plus Paladin/Shaman Mix only for those two classes -- instead of
-- always showing all ~40 items across every category regardless of who's
-- selected.
RaidConsumes_SelectSettingsClass("WARLOCK")
local warlockCats = RaidConsumes_GetVisibleCategories()
check(warlockCats["Caster DPS"] == true, "Warlock's checklist shows the Caster DPS category")
check(warlockCats["Universal (ALL)"] == true, "Warlock's checklist shows the Universal (ALL) category")
check(warlockCats["Tanks"] == nil, "Warlock's checklist hides the Tanks category (Warlock can never be a Tank)")
check(warlockCats["Healers"] == nil, "Warlock's checklist hides the Healers category (Warlock can never be a Healer)")
check(warlockCats["Physical DPS"] == nil, "Warlock's checklist hides the Physical DPS category (Warlock can never be Physical DPS)")
check(warlockCats["Paladin/Shaman Mix"] == nil, "Warlock's checklist hides the Paladin/Shaman Mix category")
-- Sanity-check the actual rendered checklist agrees with that state, not
-- just the internal flags: the first visible row should be Caster DPS's
-- header, not Tanks -- Tanks alone runs past the 14-row scroll window, so
-- this is checked directly rather than by scanning every rendered row.
check(_G.RaidConsumesSettingRow1.headerText:GetText() == "Caster DPS", "Warlock's checklist actually renders Caster DPS first (Tanks is filtered out, not just scrolled past)")

RaidConsumes_SelectSettingsClass("PALADIN")
local paladinCats = RaidConsumes_GetVisibleCategories()
check(paladinCats["Tanks"] == true, "Paladin's checklist shows the Tanks category")
check(paladinCats["Healers"] == true, "Paladin's checklist shows the Healers category")
check(paladinCats["Physical DPS"] == true, "Paladin's checklist shows the Physical DPS category")
check(paladinCats["Paladin/Shaman Mix"] == true, "Paladin's checklist shows the Paladin/Shaman Mix category (Paladin-specific)")
check(paladinCats["Caster DPS"] == nil, "Paladin's checklist hides the Caster DPS category (Paladin can never be Caster DPS)")

RaidConsumes_SelectSettingsClass("TANK")
local tankRoleCats = RaidConsumes_GetVisibleCategories()
check(tankRoleCats["Tanks"] == true, "the Tank role profile's checklist shows the Tanks category")
check(tankRoleCats["Universal (ALL)"] == true, "the Tank role profile's checklist shows the Universal (ALL) category")
check(tankRoleCats["Paladin/Shaman Mix"] == nil, "the Tank role profile's checklist hides Paladin/Shaman Mix (that's class-specific, not role-specific)")

-- The per-category checkboxes reflect that filtering, and clicking a hidden
-- one reveals it (a manual override on top of the automatic defaults).
RaidConsumes_SelectSettingsClass("WARLOCK")
check(_G.RaidConsumesCategoryToggle1.category == "Tanks", "category toggle 1 is the Tanks checkbox")
check(_G.RaidConsumesCategoryToggle1:GetChecked() ~= true, "the Tanks checkbox starts unchecked for a Warlock")
-- Real UICheckButtonTemplate clicks flip the checked state before firing
-- OnClick, and the game engine sets the global `this` to the clicked
-- frame -- both mirrored here since the test harness has no click
-- simulation of its own.
_G.RaidConsumesCategoryToggle1:SetChecked(true)
_G.this = _G.RaidConsumesCategoryToggle1
_G.RaidConsumesCategoryToggle1:GetScript("OnClick")()
check(RaidConsumes_GetVisibleCategories()["Tanks"] == true, "manually checking the Tanks box reveals the Tanks category even for a Warlock")
_G.RaidConsumesCategoryToggle1:SetChecked(false) -- toggle back off so later tests aren't affected
_G.this = _G.RaidConsumesCategoryToggle1
_G.RaidConsumesCategoryToggle1:GetScript("OnClick")()
_G.this = nil
check(_G.RaidConsumesCategoryToggle1:GetChecked() ~= true, "Tanks checkbox is unchecked again after a second click")
check(RaidConsumes_GetVisibleCategories()["Tanks"] == nil, "Tanks category is hidden again after unchecking")

-- Reset to Defaults: dirty the Warrior list, reset, confirm it's back to seed.
local warriorReqBefore = RaidConsumes_EnsureRequiredDefaults("WARRIOR")
warriorReqBefore.flaskTitans = false
warriorReqBefore.dreamtonic = true -- not a Warrior default
RaidConsumes_ResetProfileToDefaults("WARRIOR")
local warriorReqAfter = RaidConsumes_EnsureRequiredDefaults("WARRIOR")
check(warriorReqAfter.flaskTitans == true, "Reset to Defaults restores a default-on item that had been unchecked")
check(warriorReqAfter.dreamtonic == false, "Reset to Defaults clears an item that isn't actually a Warrior default")

RaidConsumes_ToggleSettings()
check(_G.RaidConsumesSettingsFrame:IsShown() == false, "Settings window closes on a second ToggleSettings call")

-- Per-raider role override: Brine (Warrior, no buffs) overridden to HEALER
-- should be checked against the Healer list, not the Warrior list.
activeRoster = fakeRoster
RaidConsumesDB.roleOverride = {}
RaidConsumes_ScanRaid()
RaidConsumes_RefreshList()
local _, _, brineRowIdx
local rowsBeforeOverride = RaidConsumes_ComputeDisplayRows()
for i, r in ipairs(rowsBeforeOverride) do if r.entry.name == "Brine" then brineRowIdx = i end end
check(brineRowIdx ~= nil, "Brine is found in the display rows")

-- With no override set, the role button shows the raider's own class
-- (abbreviated) instead of a bare "-", colored to match their class --
-- makes it read as "here's the current setting, click to change" rather
-- than a blank/disabled-looking dash.
local function FindRowByPlayerName(name)
    for i = 1, 16 do -- NUM_ROWS in UI.lua
        local r = _G["RaidConsumesRow" .. i]
        if r and r.playerName == name then return r end
    end
    return nil
end
local brineRowFrame = FindRowByPlayerName("Brine")
check(brineRowFrame ~= nil, "found Brine's actual row frame")
check(brineRowFrame.roleBtn.text:GetText() == "War", "Brine (Warrior, no override) shows his class abbreviation on the role button")
local warriorClassColor = RAID_CLASS_COLORS.WARRIOR
check(brineRowFrame.roleBtn.text._r == warriorClassColor.r and brineRowFrame.roleBtn.text._g == warriorClassColor.g,
    "the class-abbreviation role button text is colored with the Warrior class color")

-- ===================== weapon-enchant items (Wizard Oil and friends) =====================
-- Confirmed via Ryan's own screenshots: temporary weapon enchants never
-- show up via UnitBuff scanning in vanilla at all -- the enchant only shows
-- as an extra line on the WEAPON's own tooltip. isWeaponEnchant items are
-- satisfied instead via GetWeaponEnchantInfo() (self-only), and must never
-- be flagged missing for anyone but the scanning player.
do
    -- Give the scanning player (Waylock) a Warlock/Caster requirement he'd
    -- otherwise fail by name alone, then strip the buff-name text so the
    -- ONLY way to satisfy it is via GetWeaponEnchantInfo() (mocked true).
    local savedBuffs = fakeRoster.raid1.buffs
    local strippedBuffs = {}
    for _, b in ipairs(savedBuffs) do
        if b ~= "Wizard Oil" and b ~= "Brilliant Wizard Oil" then
            table.insert(strippedBuffs, b)
        end
    end
    fakeRoster.raid1.buffs = strippedBuffs

    RaidConsumes_ScanRaid()
    RaidConsumes_RefreshList()
    local waylockRow = FindRowByPlayerName("Waylock")
    check(waylockRow ~= nil, "sanity check: Waylock's row is found for the weapon-enchant test")
    check(waylockRow.missingText:GetText() == "Ready", "Waylock still shows 'Ready' with no Wizard Oil buff BY NAME -- satisfied via weaponBuff instead")

    -- Aiden (not the scanning player) genuinely has no weapon enchant text
    -- either, and his Warrior default requires Elemental Sharpening Stone
    -- -- but it must be silently excluded (never flagged), not shown missing,
    -- since weapon-enchant status is unknowable for anyone but the player.
    local aidenRow = FindRowByPlayerName("Aiden")
    check(aidenRow ~= nil, "sanity check: Aiden's row is found for the weapon-enchant test")
    check(aidenRow.missingText:GetText() == "Ready", "Aiden shows 'Ready' -- Elemental Sharpening Stone is never flagged missing for a non-player raider")

    fakeRoster.raid1.buffs = savedBuffs
    RaidConsumes_ScanRaid()
    RaidConsumes_RefreshList()
end

RaidConsumesDB.roleOverride["Brine"] = "HEALER"
local rowsAfterOverride = RaidConsumes_ComputeDisplayRows()
local brineMissingAsHealer = nil
for _, r in ipairs(rowsAfterOverride) do if r.entry.name == "Brine" then brineMissingAsHealer = r.missing end end
local healerReq = RaidConsumes_EnsureRequiredDefaults("HEALER")
local expectedHealerMissCount = 0
for key, required in pairs(healerReq) do
    -- Weapon-enchant items (e.g. Brilliant Mana Oil) are never flagged
    -- missing for a non-player raider like Brine -- see isWeaponEnchant.
    if required and not (RaidConsumes_ItemByKey[key] and RaidConsumes_ItemRequiresWeaponEnchant(RaidConsumes_ItemByKey[key])) then
        expectedHealerMissCount = expectedHealerMissCount + 1
    end
end
check(table.getn(brineMissingAsHealer) == expectedHealerMissCount, "Brine overridden to HEALER is checked against the Healer list, not the Warrior list (misses every required Healer item since he popped nothing, except weapon-enchant items which are never flagged for a non-player raider)")
RaidConsumesDB.roleOverride["Brine"] = nil

-- Physical DPS and Caster DPS are separate profiles (not one shared "DPS"
-- bucket), and their seeded defaults genuinely differ from each other --
-- this is the whole point of the split (a Ret Paladin and a Balance Druid
-- shouldn't be checked against the same list).
local physReq = RaidConsumes_EnsureRequiredDefaults("PHYSDPS")
local casterReq = RaidConsumes_EnsureRequiredDefaults("CASTERDPS")
check(physReq.elixirMongoose == true and casterReq.elixirMongoose == false,
    "Physical DPS's default checklist includes a melee item Caster DPS's doesn't")
check(casterReq.dreamtonic == true and physReq.dreamtonic == false,
    "Caster DPS's default checklist includes a caster item Physical DPS's doesn't")

RaidConsumesDB.roleOverride["Brine"] = "PHYSDPS"
local rowsAsPhys = RaidConsumes_ComputeDisplayRows()
local brineMissingAsPhys = nil
for _, r in ipairs(rowsAsPhys) do if r.entry.name == "Brine" then brineMissingAsPhys = r.missing end end
-- Weapon-enchant items are never flagged missing for a non-player raider
-- like Brine -- see isWeaponEnchant -- so they're excluded from both
-- expected counts below (Physical DPS has 1: Elemental Sharpening Stone;
-- Caster DPS has 2: Brilliant Wizard Oil, Wizard Oil).
local function IsNotWeaponEnchant(key)
    return not (RaidConsumes_ItemByKey[key] and RaidConsumes_ItemRequiresWeaponEnchant(RaidConsumes_ItemByKey[key]))
end
local expectedPhysMissCount = 0
for key, required in pairs(physReq) do if required and IsNotWeaponEnchant(key) then expectedPhysMissCount = expectedPhysMissCount + 1 end end
check(table.getn(brineMissingAsPhys) == expectedPhysMissCount, "Brine overridden to PHYSDPS is checked against Physical DPS's list")

RaidConsumesDB.roleOverride["Brine"] = "CASTERDPS"
local rowsAsCaster = RaidConsumes_ComputeDisplayRows()
local brineMissingAsCaster = nil
for _, r in ipairs(rowsAsCaster) do if r.entry.name == "Brine" then brineMissingAsCaster = r.missing end end
local expectedCasterMissCount = 0
for key, required in pairs(casterReq) do if required and IsNotWeaponEnchant(key) then expectedCasterMissCount = expectedCasterMissCount + 1 end end
check(table.getn(brineMissingAsCaster) == expectedCasterMissCount, "Brine overridden to CASTERDPS is checked against Caster DPS's list")
check(expectedPhysMissCount ~= expectedCasterMissCount, "sanity check: Physical and Caster DPS actually require a different number of items with the seeded defaults")

-- The role button's own text for an active PHYSDPS/CASTERDPS override reads
-- "Phys"/"Cast" -- real words like Tank/Heal, not an acronym like the old
-- "PDPS"/"CDPS".
RaidConsumes_RefreshList()
local brineRowAsCaster = FindRowByPlayerName("Brine")
check(brineRowAsCaster.roleBtn.text:GetText() == "Cast", "a Caster DPS override shows \"Cast\" on the role button, not an abbreviation like \"CDPS\"")
RaidConsumesDB.roleOverride["Brine"] = "PHYSDPS"
RaidConsumes_RefreshList()
local brineRowAsPhys = FindRowByPlayerName("Brine")
check(brineRowAsPhys.roleBtn.text:GetText() == "Phys", "a Physical DPS override shows \"Phys\" on the role button, not an abbreviation like \"PDPS\"")

RaidConsumesDB.roleOverride["Brine"] = nil

-- The role button cycles only through the roles that raider's CLASS can
-- actually fill (RaidConsumes_ClassRoles), driven by clicking it rather
-- than setting roleOverride directly -- this is what would catch a
-- broken cycle. Brine is a Warrior (Tank, Physical DPS only -- no
-- Healer, no Caster DPS); Anahita is a Priest (Healer, Caster DPS only
-- -- no Tank, no Physical DPS).
RaidConsumes_ScanRaid()
RaidConsumes_RefreshList()
local brineRoleRow = FindRowByPlayerName("Brine")
check(brineRoleRow ~= nil, "found Brine's actual row frame to click its role button")
local warriorClickOrder = {}
for _ = 1, 3 do
    brineRoleRow.roleBtn:GetScript("OnClick")()
    table.insert(warriorClickOrder, RaidConsumesDB.roleOverride["Brine"])
end
check(warriorClickOrder[1] == "TANK" and warriorClickOrder[2] == "PHYSDPS" and warriorClickOrder[3] == nil,
    "a Warrior's role button only cycles Tank -> Physical DPS -> class default (no Healer, no Caster DPS)")
check(brineRoleRow.roleBtn.text:GetText() == "War", "after cycling all the way back around, the button shows the class abbreviation again, not a bare '-'")

local anahitaRoleRow = FindRowByPlayerName("Anahita")
check(anahitaRoleRow ~= nil, "found Anahita's actual row frame to click its role button")
local priestClickOrder = {}
for _ = 1, 3 do
    anahitaRoleRow.roleBtn:GetScript("OnClick")()
    table.insert(priestClickOrder, RaidConsumesDB.roleOverride["Anahita"])
end
check(priestClickOrder[1] == "HEALER" and priestClickOrder[2] == "CASTERDPS" and priestClickOrder[3] == nil,
    "a Priest's role button only cycles Healer -> Caster DPS -> class default (no Tank, no Physical DPS)")
RaidConsumesDB.roleOverride["Anahita"] = nil
RaidConsumes_RefreshList()

-- ===================== class/role button color coding =====================
-- settingsProfiles = 9 classes then 4 roles (Tank/Healer/Physical DPS/
-- Caster DPS); WARLOCK is class #8, TANK is role #1 (grid index 10).
check(_G.RaidConsumesClassBtn8.profile == "WARLOCK", "button 8 is the Warlock button")
local warlockFS = _G.RaidConsumesClassBtn8:GetFontString()
check(warlockFS._r == 0.58 and warlockFS._g == 0.51 and warlockFS._b == 0.79, "Warlock button text is colored with the Warlock class color")

check(_G.RaidConsumesClassBtn10.profile == "TANK", "button 10 is the Tank role button")
local tankFS = _G.RaidConsumesClassBtn10:GetFontString()
check(tankFS._r == 0.4 and tankFS._g == 0.7 and tankFS._b == 1, "Tank button text is colored with the Tank role accent color")

-- ===================== /rc name overrides & /rc debug =====================
-- A name override is additive (extra buff name on top of Data.lua's own
-- list), used for a custom OctoWoW/Turtle item whose actual applied buff
-- doesn't match what's guessed in Data.lua.
check(RaidConsumesDB.nameOverrides == nil or RaidConsumesDB.nameOverrides.elixirGiants == nil, "sanity check: elixirGiants has no name override yet")
local addedFirst = RaidConsumes_AddNameOverride("elixirGiants", "Totally Different Buff Name")
check(addedFirst == true, "adding a new name override reports success")
check(RaidConsumesDB.nameOverrides.elixirGiants[1] == "Totally Different Buff Name", "the override is stored under the item's key")
local addedDupe = RaidConsumes_AddNameOverride("elixirGiants", "Totally Different Buff Name")
check(addedDupe == false, "adding the exact same override twice reports it was already set, doesn't duplicate it")
check(table.getn(RaidConsumesDB.nameOverrides.elixirGiants) == 1, "no duplicate was actually stored")

-- The override actually feeds the buff-name lookup used during a scan: a
-- unit whose buffs list has ONLY the override name (not the built-in
-- "Elixir of Giants") should still register a hit for elixirGiants. Uses
-- Brine (raid3, normally buff-less) rather than Aiden, so this doesn't
-- perturb Aiden's usage-history counts checked further down.
--
-- The SAME override name is also added to a second item (elixirMongoose)
-- here, to verify one buff name can satisfy more than one checklist entry
-- at once -- the shared-name case the lookup was restructured for (a list
-- of item keys per name, not just one), needed because vanilla's generic
-- "Well Fed" food buff is shared by every stat food, not unique per item.
RaidConsumes_AddNameOverride("elixirMongoose", "Totally Different Buff Name")
fakeRoster.raid3.buffs = { "Totally Different Buff Name" }
RaidConsumes_ScanRaid()
local overrideResults = RaidConsumes_LastResults
local brineAfterOverride = nil
for _, e in ipairs(overrideResults) do if e.name == "Brine" then brineAfterOverride = e end end
check(brineAfterOverride ~= nil and brineAfterOverride.hits.elixirGiants == true, "a scan matches the override name even though it's not in Data.lua's built-in names list")
check(brineAfterOverride ~= nil and brineAfterOverride.hits.elixirMongoose == true, "the SAME buff name also satisfies a second item it was added to -- one shared name can match multiple checklist entries")

RaidConsumes_ClearNameOverrides("elixirGiants")
RaidConsumes_ClearNameOverrides("elixirMongoose")
check(RaidConsumesDB.nameOverrides.elixirGiants == nil, "clearing removes every override for that item")
fakeRoster.raid3.buffs = { "Some Unrelated Buff" } -- restore Brine's normal (empty) buffs for later tests
RaidConsumes_ScanRaid()
-- That brief override scan logged Brine a usage-history "hit" for
-- elixirGiants (a real not-had -> has transition at the time) -- clear it
-- back out so it doesn't trip the "Brine has no usage history" check below.
RaidConsumesDB.usageHistory["Brine"] = nil

-- "/rc debug" (RaidConsumes_DebugPlayerBuffs) just prints straight to chat
-- -- a smoke test that it runs cleanly against both a buffed and an
-- unbuffed "player" unit is the meaningful check here (a nil buff, a blank
-- tooltip name, or zero buffs found are all real cases it has to handle
-- without erroring).
local debugOk1, debugErr1 = pcall(RaidConsumes_DebugPlayerBuffs)
check(debugOk1, "RaidConsumes_DebugPlayerBuffs runs without erroring when the player has buffs: " .. tostring(debugErr1))
fakeRoster.player = { buffs = {} } -- temporarily swap out the player/raid1 alias
local debugOk2, debugErr2 = pcall(RaidConsumes_DebugPlayerBuffs)
check(debugOk2, "RaidConsumes_DebugPlayerBuffs runs without erroring when the player has zero buffs: " .. tostring(debugErr2))
fakeRoster.player = fakeRoster.raid1 -- restore the alias (raid1 itself was never touched)

-- ===================== usage history =====================
-- Aiden, Anahita, and Waylock have all had their buffs up across 3
-- separate RaidConsumes_ScanRaid() calls on fakeRoster by this point in
-- the test (the initial scan, the rendering-test scan, and the role-
-- override scan just above) -- edge detection should mean each item was
-- only counted ONCE despite being seen as "already active" on every
-- re-scan, not three times.
check(RaidConsumesDB.usageHistory["Aiden"] ~= nil, "Aiden has recorded usage history")
check(RaidConsumesDB.usageHistory["Aiden"]["flaskTitans"] == 1, "Aiden's Flask of the Titans use is counted once, not once per re-scan while it's still active")
check(RaidConsumesDB.usageHistory["Brine"] == nil, "Brine (popped nothing) has no usage history at all")
check(RaidConsumesDB.usageHistoryClass["Aiden"] == "WARRIOR", "Aiden's class is recorded alongside his history for color coding")

-- Weapon-enchant items (Wizard Oil and friends) never appear in entry.hits
-- at all in the real game -- history logging was moved onto
-- weaponBuffKnown/weaponBuff specifically so these still show up in the
-- Usage tab instead of never being logged (a real gap that would have
-- looked just like "history isn't showing anything" for exactly the two
-- items that report they're actually being used).
check(RaidConsumesDB.usageHistory["Waylock"] ~= nil, "Waylock (the scanning player) has recorded usage history")
check(RaidConsumesDB.usageHistory["Waylock"]["wizardOil"] == 1, "Wizard Oil use is logged via weaponBuff even though it never shows up by name in the real game")
check(RaidConsumesDB.usageHistory["Waylock"]["brilliantWizardOil"] == 1, "Brilliant Wizard Oil use is logged via weaponBuff the same way")

-- Re-scanning once more must not inflate an already-active buff's count.
RaidConsumes_ScanRaid()
check(RaidConsumesDB.usageHistory["Aiden"]["flaskTitans"] == 1, "A 4th re-scan with the same buffs still up still doesn't inflate the count")

local historyRows = RaidConsumes_GetHistoryRows()
check(table.getn(historyRows) > 0, "history rows are non-empty after scanning")
-- NOTE: "Achillia" (from the earlier solo-roster test scan, still on
-- record) alphabetically precedes "Aiden", so she's expected at row 1 --
-- this checks Aiden's own block specifically rather than assuming index 1.
local aidenStartIdx = nil
for i, r in ipairs(historyRows) do
    if r.name == "Aiden" then aidenStartIdx = i; break end
end
check(aidenStartIdx ~= nil, "Aiden appears somewhere in the history rows")
check(historyRows[aidenStartIdx].name == "Aiden" and (aidenStartIdx == 1 or historyRows[aidenStartIdx - 1].name < "Aiden"), "history rows are grouped/sorted by player name")
-- Elemental Sharpening Stone (Aiden's actual alphabetically-first item) is
-- correctly ABSENT from his history now -- it's a weapon-enchant item, and
-- weapon-enchant status is never knowable for anyone but the scanning
-- player, so it can never be logged as "used" for a teammate either (same
-- reasoning as it never being flagged missing for one). "Elixir of Giants"
-- is next alphabetically among his remaining tracked items.
check(historyRows[aidenStartIdx].label == "Elixir of Giants", "within a tied count, history sorts alphabetically by item label (Aiden's items are all count 1, weapon-enchant items excluded)")

RaidConsumes_ToggleHistory()
check(_G.RaidConsumesHistoryFrame:IsShown() == true, "History window opens")
check(_G.RaidConsumesHistoryRow1.nameText:GetText() == historyRows[1].name, "History row 1 matches the first sorted history entry")
check(_G.RaidConsumesHistoryRow1.countText:GetText() == "1", "History row 1 displays a count of 1")

-- ===================== history export =====================
-- Pure CSV-building step: a header row, then "Player,Item,Count" per row,
-- matching what RaidConsumes_GetHistoryRows already returned above.
local usageExportText = RaidConsumes_BuildHistoryExportText("usage")
check(string.find(usageExportText, "^Player,Item,Count") ~= nil, "usage export starts with a Player,Item,Count header")
check(string.find(usageExportText, "Aiden,Elixir of Giants,1", 1, true) ~= nil,
    "usage export contains a correctly-formatted CSV line for one of Aiden's items")
local usageExportLineCount = 0
for _ in string.gfind(usageExportText, "\n") do usageExportLineCount = usageExportLineCount + 1 end
check(usageExportLineCount == table.getn(historyRows), "usage export has exactly one line per history row, plus the header")

-- The Export button opens a popup pre-filled with that same text, focused
-- and ready to Ctrl+A/Ctrl+C.
_G.RaidConsumesHistoryExportButton:GetScript("OnClick")()
check(_G.RaidConsumesExportFrame:IsShown() == true, "clicking Export opens the export window")
check(_G.RaidConsumesExportEditBox:GetText() == usageExportText, "the export box's text matches the built CSV for the currently-shown (Usage) view")
_G.RaidConsumesExportFrame:Hide()

-- "Clear All History" goes through a StaticPopup confirmation -- simulate
-- the player clicking "Clear" on it.
_G.RaidConsumesHistoryClearButton:GetScript("OnClick")()
check(_G.__lastStaticPopupShown == "RAIDCONSUMES_CLEAR_HISTORY", "Clear All History opens the confirmation popup rather than clearing immediately")
StaticPopupDialogs["RAIDCONSUMES_CLEAR_HISTORY"].OnAccept()
check(next(RaidConsumesDB.usageHistory) == nil, "confirming the popup clears all usage history")

RaidConsumes_ToggleHistory()
check(_G.RaidConsumesHistoryFrame:IsShown() == false, "History window closes")

-- ===================== checklist sync (Sync.lua) =====================
-- Fires the real CHAT_MSG_ADDON event through FireEvent rather than only
-- calling exported functions directly -- this is what would catch a
-- broken event registration or prefix mismatch, not just a broken parser.

_G.__sentMessages = {}
RaidConsumes_ResetProfileToDefaults("HEALER")
local healerReq = RaidConsumes_EnsureRequiredDefaults("HEALER")
local expectedKeys = {}
for _, item in ipairs(RaidConsumes_Items) do
    if healerReq[item.key] then table.insert(expectedKeys, item.key) end
end
RaidConsumes_SyncBroadcastProfile("HEALER")
check(table.getn(_G.__sentMessages) == 1, "Sync This Class sends exactly one addon message")
local sent = _G.__sentMessages[1]
check(sent.prefix == "RCsync", "sync message uses the RCsync prefix")
check(sent.channel == "RAID", "sync message goes out on RAID (we're in a 4-person raid)")
check(sent.msg == "REQ:HEALER:" .. table.concat(expectedKeys, ","), "sync payload lists exactly Healer's currently-checked items")

_G.__sentMessages = {}
RaidConsumes_SyncBroadcastAll()
check(table.getn(_G.__sentMessages) == 13, "Sync All sends one message per class/role (9 classes + 4 roles: tank/healer/physical dps/caster dps)")

-- Incoming sync from a trusted sender (a raid officer -- Anahita, rank 1
-- in raidRanks above) overwrites the target profile's checklist exactly
-- -- clearing anything not listed, not just adding the new items on top
-- of the old ones.
RaidConsumes_EnsureRequiredDefaults("MAGE")
check(RaidConsumesDB.required.MAGE.flaskSupremePower == true, "Mage starts with its seeded default (Flask of Supreme Power) checked")
FireEvent("CHAT_MSG_ADDON", "RCsync", "REQ:MAGE:flaskTitans,elementalSharpeningStone", "RAID", "Anahita")
check(RaidConsumesDB.required.MAGE.flaskTitans == true, "incoming sync checks every item it lists")
check(RaidConsumesDB.required.MAGE.elementalSharpeningStone == true, "incoming sync checks every item it lists (2nd item)")
check(RaidConsumesDB.required.MAGE.flaskSupremePower == false, "incoming sync clears items NOT in the new list, not just adds to the old one")

-- ROGUE/DRUID/HUNTER/SHAMAN were all already seeded by the "Sync All"
-- broadcast above (broadcasting a profile touches it locally too), so a
-- nil-check can't tell "ignored" apart from "already existed" -- snapshot
-- the whole table instead and confirm it's byte-for-byte unchanged.
local function SnapshotReq(profile)
    local req = RaidConsumes_EnsureRequiredDefaults(profile)
    local snap = {}
    for k, v in pairs(req) do snap[k] = v end
    return snap
end
local function ReqUnchanged(profile, snap)
    local req = RaidConsumesDB.required[profile]
    for k, v in pairs(snap) do
        if req[k] ~= v then return false end
    end
    for k, v in pairs(req) do
        if snap[k] ~= v then return false end
    end
    return true
end

-- Untrusted (not in your raid/party at all): ignored entirely.
local rogueBefore = SnapshotReq("ROGUE")
FireEvent("CHAT_MSG_ADDON", "RCsync", "REQ:ROGUE:flaskTitans", "RAID", "RandomStranger")
check(ReqUnchanged("ROGUE", rogueBefore), "a sync from someone not in your raid/party is ignored")

-- In your raid, but not an officer/leader (Aiden, rank 0): rejected too --
-- being grouped with someone isn't enough, they also need rank.
local shamanBefore = SnapshotReq("SHAMAN")
FireEvent("CHAT_MSG_ADDON", "RCsync", "REQ:SHAMAN:flaskTitans", "RAID", "Aiden")
check(ReqUnchanged("SHAMAN", shamanBefore), "a sync from an in-raid member who isn't an officer/leader is rejected")

-- Sync toggled off locally: ignored even from an officer.
RaidConsumesDB.syncEnabled = false
local druidBefore = SnapshotReq("DRUID")
FireEvent("CHAT_MSG_ADDON", "RCsync", "REQ:DRUID:flaskTitans", "RAID", "Anahita")
check(ReqUnchanged("DRUID", druidBefore), "sync is ignored while 'Accept checklist syncs' is turned off")
RaidConsumesDB.syncEnabled = true

-- Never applies a message that echoes back from yourself.
local hunterBefore = SnapshotReq("HUNTER")
FireEvent("CHAT_MSG_ADDON", "RCsync", "REQ:HUNTER:flaskTitans", "RAID", "Waylock")
check(ReqUnchanged("HUNTER", hunterBefore), "a message that echoes back from yourself is ignored")

-- Unknown profile token (different addon version, or garbage): ignored,
-- no error, no stray table created.
FireEvent("CHAT_MSG_ADDON", "RCsync", "REQ:BARD:flaskTitans", "RAID", "Anahita")
check(RaidConsumesDB.required.BARD == nil, "an unrecognized profile token is ignored rather than blindly stored")

-- ---- sending side: only sync authority (raid officer/leader, party
-- leader) can push a sync at all ----
youAreRaidLeader = false
youAreRaidOfficer = false
_G.__sentMessages = {}
RaidConsumes_SyncBroadcastProfile("HUNTER")
check(table.getn(_G.__sentMessages) == 0, "a non-officer/leader's 'Sync This Class' click sends nothing")
RaidConsumes_SyncBroadcastAll()
check(table.getn(_G.__sentMessages) == 0, "a non-officer/leader's 'Sync All' click sends nothing")
youAreRaidLeader = true

-- ---- Request Sync: anyone can ask, only an officer/leader auto-responds ----
_G.__sentMessages = {}
RaidConsumes_SyncRequest()
check(table.getn(_G.__sentMessages) == 1, "Request Sync sends exactly one REQSYNC message")
check(_G.__sentMessages[1].msg == "REQSYNC", "Request Sync's message body is REQSYNC")
check(_G.__sentMessages[1].channel == "RAID", "Request Sync goes out on RAID")
check(_G.__sentMessages[1].target == nil, "Request Sync isn't targeted at anyone specific -- it goes to the whole group")

-- You (Waylock) are the raid leader, so your client auto-responds to
-- someone else's request with every checklist, privately.
_G.__sentMessages = {}
FireEvent("CHAT_MSG_ADDON", "RCsync", "REQSYNC", "RAID", "Aiden")
check(table.getn(_G.__sentMessages) == 13, "an officer/leader auto-responds to a sync request with all 13 checklists")
local allWhisperedToAiden = true
for _, m in ipairs(_G.__sentMessages) do
    if m.channel ~= "WHISPER" or m.target ~= "Aiden" then allWhisperedToAiden = false end
end
check(allWhisperedToAiden, "the response is whispered privately to the requester, not broadcast to the whole raid")

-- A non-officer's client should NOT auto-respond to someone else's request.
youAreRaidLeader = false
_G.__sentMessages = {}
FireEvent("CHAT_MSG_ADDON", "RCsync", "REQSYNC", "RAID", "Brine")
check(table.getn(_G.__sentMessages) == 0, "a non-officer/leader doesn't auto-respond to someone else's sync request")
youAreRaidLeader = true

-- Never responds to your own request echoing back.
_G.__sentMessages = {}
FireEvent("CHAT_MSG_ADDON", "RCsync", "REQSYNC", "RAID", "Waylock")
check(table.getn(_G.__sentMessages) == 0, "doesn't respond to a REQSYNC that echoes back from yourself")

-- ===================== missed-consumable history (join detection) =====================
-- A new raider ("Zephyr") isn't in the roster yet -- adding him and
-- bumping the raid count simulates him joining mid-raid. The first scan
-- that sees him should log a "missed" entry for everything currently
-- required of Mages that he doesn't have (edge-detected the same way
-- usage is, just for "present in the raid" instead of "has the buff") --
-- and a second scan right after, while he's still there, must NOT log it
-- again.
local mageReq = RaidConsumes_EnsureRequiredDefaults("MAGE")
local expectedMissedKeys = {}
for _, item in ipairs(RaidConsumes_Items) do
    -- Weapon-enchant items (Wizard Oil and friends) are never knowable for
    -- anyone but the scanning player, so they can never be logged as
    -- "missed" for another raider like Zephyr either -- same isWeaponEnchant
    -- reasoning as the missing-list and usage-history tests above.
    if mageReq[item.key] and not RaidConsumes_ItemRequiresWeaponEnchant(item) then table.insert(expectedMissedKeys, item.key) end
end
check(table.getn(expectedMissedKeys) > 0, "Mage currently requires at least one item (sanity check for this test)")

fakeRoster.raid5 = { name = "Zephyr", class = "MAGE", buffs = {} } -- pops nothing
fakeRaidCount = 5
RaidConsumes_ScanRaid()
local zephyrMissed = RaidConsumesDB.missedHistory["Zephyr"]
check(zephyrMissed ~= nil, "a raider who just appeared in the raid gets a missed-history entry")
local allLoggedOnce = true
for _, key in ipairs(expectedMissedKeys) do
    if zephyrMissed[key] ~= 1 then allLoggedOnce = false end
end
check(allLoggedOnce, "every currently-required Mage item Zephyr is missing gets logged once on join")

RaidConsumes_ScanRaid() -- re-scan while Zephyr is still in the raid, still missing the same things
local stillOnce = true
for _, key in ipairs(expectedMissedKeys) do
    if zephyrMissed[key] ~= 1 then stillOnce = false end
end
check(stillOnce, "re-scanning the same raid does NOT log the miss again (once per join, not once per click)")

-- Zephyr leaves (removed from the roster), then rejoins later in the same
-- session -- that's a fresh join and should log again.
fakeRoster.raid5 = nil
fakeRaidCount = 4
RaidConsumes_ScanRaid()
fakeRoster.raid5 = { name = "Zephyr", class = "MAGE", buffs = {} }
fakeRaidCount = 5
RaidConsumes_ScanRaid()
check(zephyrMissed[expectedMissedKeys[1]] == 2, "leaving and rejoining the raid logs a fresh miss")

-- The History window's "Missed" view surfaces this; the "Usage" view is
-- unaffected -- Zephyr never popped anything, so he shouldn't appear there.
RaidConsumes_ToggleHistory() -- opens (starts on the "Usage" view)
local usageRows = RaidConsumes_GetHistoryRows("usage")
local zephyrInUsage = false
for _, r in ipairs(usageRows) do
    if r.name == "Zephyr" then zephyrInUsage = true end
end
check(not zephyrInUsage, "a raider who never popped anything doesn't show up in the Usage view")

_G.RaidConsumesHistoryViewButton:GetScript("OnClick")()
local missedRows = RaidConsumes_GetHistoryRows()
local zephyrMissedRow = nil
for _, r in ipairs(missedRows) do
    if r.name == "Zephyr" then zephyrMissedRow = r end
end
check(zephyrMissedRow ~= nil, "Zephyr shows up in the Missed view after switching to it")
check(zephyrMissedRow.count == 2, "Zephyr's Missed-view count matches the 2 logged joins")

-- Export follows the currently-shown view (Missed, from the toggle above)
-- and its header/column name reflects that.
local missedExportText = RaidConsumes_BuildHistoryExportText("missed")
check(string.find(missedExportText, "^Player,Item,Missed") ~= nil, "missed export starts with a Player,Item,Missed header")
check(string.find(missedExportText, "Zephyr," .. zephyrMissedRow.label .. ",2", 1, true) ~= nil,
    "missed export contains Zephyr's logged-twice item at the right count")
_G.RaidConsumesHistoryExportButton:GetScript("OnClick")()
check(_G.RaidConsumesExportEditBox:GetText() == missedExportText, "the export box picks up the Missed view's text when that's what's showing")
_G.RaidConsumesExportFrame:Hide()

RaidConsumes_ToggleHistory() -- close

-- Clearing history only wipes the currently-shown view, not both.
check(next(RaidConsumesDB.missedHistory) ~= nil, "missedHistory has data before clearing")
StaticPopupDialogs["RAIDCONSUMES_CLEAR_HISTORY"].OnAccept() -- historyViewMode is "missed" from the toggle above
check(next(RaidConsumesDB.missedHistory) == nil, "clearing history while on the Missed view wipes missedHistory")

-- ===================== auto-check =====================
-- Off by default, and the checkbox/interval box reflect RaidConsumesDB
-- whenever the window opens.
check(RaidConsumesDB.autoScanEnabled == false, "auto-check is off by default")
check(RaidConsumesDB.autoScanInterval == 5, "auto-check defaults to a 5 second interval")
RaidConsumes_RefreshAutoScanControls()
check(_G.RaidConsumesAutoScanCheck:GetChecked() ~= true, "the auto-check box starts unchecked, matching the default")
check(_G.RaidConsumesAutoScanInterval:GetText() == "5", "the interval box starts showing the default 5")

-- The checkbox click just flips the saved setting (a single non-loop
-- button, so `this` works the same way it does for syncAcceptCheck above).
_G.this = _G.RaidConsumesAutoScanCheck
_G.RaidConsumesAutoScanCheck:SetChecked(true)
_G.RaidConsumesAutoScanCheck:GetScript("OnClick")()
_G.this = nil
check(RaidConsumesDB.autoScanEnabled == true, "checking the auto-check box turns it on")

-- The interval box parses on Enter, clamps out-of-range or garbage input,
-- and always reflects back whatever was actually accepted.
_G.this = _G.RaidConsumesAutoScanInterval
_G.RaidConsumesAutoScanInterval:SetText("15")
_G.RaidConsumesAutoScanInterval:GetScript("OnEnterPressed")()
check(RaidConsumesDB.autoScanInterval == 15, "typing a valid interval and pressing Enter saves it")

_G.RaidConsumesAutoScanInterval:SetText("0")
_G.RaidConsumesAutoScanInterval:GetScript("OnEnterPressed")()
check(RaidConsumesDB.autoScanInterval == 2, "an interval below the 2-second floor is clamped up to it")
check(_G.RaidConsumesAutoScanInterval:GetText() == "2", "the box reflects the clamped value back, not the raw typed one")

_G.RaidConsumesAutoScanInterval:SetText("99999")
_G.RaidConsumesAutoScanInterval:GetScript("OnEnterPressed")()
check(RaidConsumesDB.autoScanInterval == 300, "an interval above the 300-second ceiling is clamped down to it")

_G.RaidConsumesAutoScanInterval:SetText("banana")
_G.RaidConsumesAutoScanInterval:GetScript("OnEnterPressed")()
check(RaidConsumesDB.autoScanInterval == 300, "non-numeric garbage falls back to whatever was already saved, not an error or a silent no-op")
_G.this = nil

-- The OnUpdate timer only fires a scan once the configured interval has
-- actually elapsed, and only while the window is shown (no point scanning
-- into the void while it's closed). RaidConsumes_ScanRaid() always builds
-- and assigns a brand new results table, so comparing table identity
-- (not content -- the mocked time() is a constant, so timestamps can't
-- tell two scans apart) is what actually proves whether a rescan ran.
RaidConsumesDB.autoScanInterval = 5
local onUpdate = _G.RaidConsumesFrame:GetScript("OnUpdate")
local resultsRefBeforeHidden = RaidConsumes_LastResults
_G.RaidConsumesFrame:Hide()
_G.arg1 = 10 -- well past the 5-second interval -- would fire if shown
onUpdate()
onUpdate()
_G.arg1 = nil
check(RaidConsumes_LastResults == resultsRefBeforeHidden, "auto-check never scans while the window is hidden, no matter how much time passes")

_G.RaidConsumesFrame:Show()
local resultsRefBeforeShown = RaidConsumes_LastResults
_G.arg1 = 2 -- under the 5 second interval -- shouldn't fire yet
onUpdate()
check(RaidConsumes_LastResults == resultsRefBeforeShown, "auto-check doesn't scan before the interval has actually elapsed")
_G.arg1 = 2 -- 2 + 2 = 4, still under 5
onUpdate()
check(RaidConsumes_LastResults == resultsRefBeforeShown, "still no scan at 4 of 5 seconds")
_G.arg1 = 2 -- 4 + 2 = 6, now past 5 -- should fire
onUpdate()
_G.arg1 = nil
check(RaidConsumes_LastResults ~= resultsRefBeforeShown, "auto-check scans once accumulated elapsed time crosses the configured interval while the window is shown")

_G.RaidConsumesFrame:Hide()
RaidConsumesDB.autoScanEnabled = false -- back to the default so nothing keeps auto-scanning after the test suite ends

-- ===================== auto-whisper =====================
-- Off by default, and the checkbox/cooldown box reflect RaidConsumesDB
-- whenever the Settings window opens -- same pattern as auto-check above.
check(RaidConsumesDB.autoWhisperEnabled == false, "auto-whisper is off by default")
check(RaidConsumesDB.autoWhisperCooldown == 300, "auto-whisper defaults to a 300 second cooldown")
RaidConsumes_RefreshAutoWhisperControls()
check(_G.RaidConsumesAutoWhisperCheck:GetChecked() ~= true, "the auto-whisper box starts unchecked, matching the default")
check(_G.RaidConsumesAutoWhisperCooldown:GetText() == "300", "the cooldown box starts showing the default 300")

_G.this = _G.RaidConsumesAutoWhisperCheck
_G.RaidConsumesAutoWhisperCheck:SetChecked(true)
_G.RaidConsumesAutoWhisperCheck:GetScript("OnClick")()
_G.this = nil
check(RaidConsumesDB.autoWhisperEnabled == true, "checking the auto-whisper box turns it on")

_G.this = _G.RaidConsumesAutoWhisperCooldown
_G.RaidConsumesAutoWhisperCooldown:SetText("120")
_G.RaidConsumesAutoWhisperCooldown:GetScript("OnEnterPressed")()
check(RaidConsumesDB.autoWhisperCooldown == 120, "typing a valid cooldown and pressing Enter saves it")

_G.RaidConsumesAutoWhisperCooldown:SetText("5")
_G.RaidConsumesAutoWhisperCooldown:GetScript("OnEnterPressed")()
check(RaidConsumesDB.autoWhisperCooldown == 30, "a cooldown below the 30-second floor is clamped up to it")
check(_G.RaidConsumesAutoWhisperCooldown:GetText() == "30", "the box reflects the clamped value back, not the raw typed one")

_G.RaidConsumesAutoWhisperCooldown:SetText("99999")
_G.RaidConsumesAutoWhisperCooldown:GetScript("OnEnterPressed")()
check(RaidConsumesDB.autoWhisperCooldown == 1800, "a cooldown above the 1800-second ceiling is clamped down to it")

_G.RaidConsumesAutoWhisperCooldown:SetText("banana")
_G.RaidConsumesAutoWhisperCooldown:GetScript("OnEnterPressed")()
check(RaidConsumesDB.autoWhisperCooldown == 1800, "non-numeric garbage falls back to whatever was already saved, not an error or a silent no-op")
_G.this = nil

-- Behavioral coverage of RaidConsumes_ProcessAutoWhispers itself, via
-- synthetic rows rather than a real scan -- isolates the edge-detection/
-- cooldown/self/offline rules from Data.lua's real item list and the
-- current class requirements, and the mocked time() is a constant so
-- "cooldown elapsed" is simulated by rewinding RaidConsumes_LastWhisperTime
-- directly rather than by advancing a clock.
do
    _G.__sentWhispers = {}
    RaidConsumesDB.autoWhisperEnabled = true
    RaidConsumesDB.autoWhisperCooldown = 300
    RaidConsumes_LastWhisperTime = {}
    RaidConsumes_LastMissingSet = {}

    local fakeItemA = { key = "testItemA", label = "Test Item A" }
    local fakeItemB = { key = "testItemB", label = "Test Item B" }
    local function MakeRow(name, unit, missingItems, online)
        if online == nil then online = true end
        return { entry = { name = name, unit = unit, online = online }, missingItems = missingItems }
    end

    RaidConsumes_ProcessAutoWhispers({ MakeRow("Brine", "raid3", { fakeItemA }) })
    check(table.getn(_G.__sentWhispers) == 1, "a raider newly found missing something gets whispered")
    check(_G.__sentWhispers[1].target == "Brine", "the whisper targets the right raider")
    check(_G.__sentWhispers[1].chatType == "WHISPER", "the whisper actually uses the WHISPER chat type")
    check(string.find(_G.__sentWhispers[1].msg, "Test Item A", 1, true) ~= nil, "the whisper names the missing item")

    _G.__sentWhispers = {}
    RaidConsumes_ProcessAutoWhispers({ MakeRow("Brine", "raid3", { fakeItemA }) })
    check(table.getn(_G.__sentWhispers) == 0, "the same still-missing item doesn't re-whisper before the cooldown elapses")

    RaidConsumes_ProcessAutoWhispers({ MakeRow("Brine", "raid3", { fakeItemA, fakeItemB }) })
    check(table.getn(_G.__sentWhispers) == 1, "a newly-missing item re-triggers a whisper even before the cooldown elapses")

    _G.__sentWhispers = {}
    RaidConsumes_LastWhisperTime["Brine"] = 123456 - RaidConsumesDB.autoWhisperCooldown - 1
    RaidConsumes_ProcessAutoWhispers({ MakeRow("Brine", "raid3", { fakeItemA, fakeItemB }) })
    check(table.getn(_G.__sentWhispers) == 1, "still missing the same items re-whispers once the cooldown elapses")

    _G.__sentWhispers = {}
    RaidConsumes_ProcessAutoWhispers({ MakeRow("Brine", "raid3", {}) })
    check(table.getn(_G.__sentWhispers) == 0, "no whisper once the raider has everything")
    check(RaidConsumes_LastMissingSet["Brine"] == nil, "going Ready clears the tracked missing set")

    RaidConsumes_LastWhisperTime["Brine"] = 123456 -- pretend we JUST whispered (cooldown not elapsed)
    RaidConsumes_ProcessAutoWhispers({ MakeRow("Brine", "raid3", { fakeItemA }) })
    check(table.getn(_G.__sentWhispers) == 1, "falling behind again after being Ready re-whispers immediately, even inside the cooldown")

    _G.__sentWhispers = {}
    RaidConsumes_ProcessAutoWhispers({ MakeRow("Waylock", "raid1", { fakeItemA }) })
    check(table.getn(_G.__sentWhispers) == 0, "the scanning player is never auto-whispered")

    _G.__sentWhispers = {}
    RaidConsumes_ProcessAutoWhispers({ MakeRow("Brine", "raid3", { fakeItemA }, false) })
    check(table.getn(_G.__sentWhispers) == 0, "an offline raider is never auto-whispered")

    _G.__sentWhispers = {}
    RaidConsumesDB.autoWhisperEnabled = false
    RaidConsumes_ProcessAutoWhispers({ MakeRow("Brine", "raid3", { fakeItemA, fakeItemB }) })
    check(table.getn(_G.__sentWhispers) == 0, "auto-whisper does nothing at all while turned off")

    -- Reset shared state back to defaults so nothing bleeds past this block.
    RaidConsumesDB.autoWhisperEnabled = false
    RaidConsumesDB.autoWhisperCooldown = 300
    RaidConsumes_LastWhisperTime = {}
    RaidConsumes_LastMissingSet = {}
    _G.__sentWhispers = {}
end

print("ALL CHECKS PASSED")

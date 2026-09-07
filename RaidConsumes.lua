--[[
RaidConsumes - RaidConsumes.lua

Entry point: SavedVariables init, slash commands, minimap button startup.
Loaded last (see the .toc) so everything in Data.lua / Scan.lua / UI.lua /
Minimap.lua already exists by the time this runs.
--]]

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "RaidConsumes" then
        if not RaidConsumesDB then
            RaidConsumesDB = {}
        end
        if not RaidConsumesDB.required then
            RaidConsumesDB.required = {}
        end
        if not RaidConsumesDB.roleOverride then
            RaidConsumesDB.roleOverride = {}
        end
        if not RaidConsumesDB.iconOverrides then
            RaidConsumesDB.iconOverrides = {}
        end
        if not RaidConsumesDB.nameOverrides then
            RaidConsumesDB.nameOverrides = {}
        end
        if RaidConsumesDB.autoScanEnabled == nil then
            RaidConsumesDB.autoScanEnabled = false -- opt-in: repeated scanning isn't free
        end
        if not RaidConsumesDB.autoScanInterval then
            RaidConsumesDB.autoScanInterval = 5
        end
        if RaidConsumesDB.autoWhisperEnabled == nil then
            RaidConsumesDB.autoWhisperEnabled = false -- opt-in: don't whisper anyone without being asked
        end
        if not RaidConsumesDB.autoWhisperCooldown then
            RaidConsumesDB.autoWhisperCooldown = 300
        end
        if RaidConsumesDB.hideReadyPlayers == nil then
            RaidConsumesDB.hideReadyPlayers = false -- opt-in: default view shows everyone
        end
        if not RaidConsumesDB.windowOpacity then
            RaidConsumesDB.windowOpacity = 100
        end
        if not RaidConsumesDB.usageHistory then
            RaidConsumesDB.usageHistory = {}
        end
        if not RaidConsumesDB.usageHistoryClass then
            RaidConsumesDB.usageHistoryClass = {}
        end
        -- v2.6.3: the "Missed" history view (who joined missing
        -- something) was removed -- it wasn't reliably accurate, and
        -- Usage (what people have actually popped) is. Any old
        -- RaidConsumesDB.missedHistory data from before this update is
        -- simply left alone, unused -- harmless, and not worth writing
        -- migration code to clean up.
        if RaidConsumesDB.syncEnabled == nil then
            RaidConsumesDB.syncEnabled = true -- accept incoming checklist syncs by default
        end
        -- v2.0.0: the old single "DPS" role override was split into
        -- Physical DPS / Caster DPS. There's no way to know which one an
        -- existing "DPS" override meant, and leaving it as-is would
        -- silently resolve to a brand new, empty "DPS" profile (nothing
        -- required -> that raider would wrongly show "Ready" always) --
        -- so it's reset back to class default instead. Re-assign it with
        -- the role button, now a 4-way Tank/Healer/Physical DPS/Caster
        -- DPS cycle.
        for name, role in pairs(RaidConsumesDB.roleOverride) do
            if role == "DPS" then
                RaidConsumesDB.roleOverride[name] = nil
            end
        end
        -- v2.1.0: role overrides are now restricted to whatever that
        -- raider's class can actually fill (RaidConsumes_ClassRoles) --
        -- clean up anything already set to a role that class can't. Only
        -- possible on a best-effort basis, for names we happen to have a
        -- recorded class for (from usage/missed history); anything else
        -- self-corrects the next time that row's button is clicked.
        for name, role in pairs(RaidConsumesDB.roleOverride) do
            local class = RaidConsumesDB.usageHistoryClass and RaidConsumesDB.usageHistoryClass[name]
            local validRoles = class and RaidConsumes_ClassRoles[class]
            if validRoles then
                local stillValid = false
                for _, r in ipairs(validRoles) do
                    if r == role then stillValid = true end
                end
                if not stillValid then
                    RaidConsumesDB.roleOverride[name] = nil
                end
            end
        end
        -- v2.6.1: usage history for the 4 weapon-enchant items (Wizard
        -- Oil, Brilliant Wizard Oil, Elemental Sharpening Stone,
        -- Brilliant Mana Oil) was being logged as 4 separate item counts,
        -- but GetWeaponEnchantInfo() can't actually tell them apart --
        -- every one of the 4 got credited +1 together each time ANY
        -- single one was applied, inflating all 4 counts identically
        -- (confirmed: one real Wizard Oil application logged as 2/2/2/2
        -- across all 4). Existing data already has these bogus per-item
        -- counts baked in, so on first login after this update, collapse
        -- whatever's there into the new shared bucket (highest of the 4
        -- counts -- they should already match, since every transition
        -- credited all 4 identically -- rather than summing them, which
        -- would inflate it further) and drop the 4 individual entries.
        local WEAPON_ENCHANT_KEYS = { "wizardOil", "brilliantWizardOil", "elementalSharpeningStone", "brilliantManaOil" }
        for name, items in pairs(RaidConsumesDB.usageHistory or {}) do
            local merged = 0
            local hadAny = false
            for _, key in ipairs(WEAPON_ENCHANT_KEYS) do
                if items[key] then
                    hadAny = true
                    if items[key] > merged then merged = items[key] end
                    items[key] = nil
                end
            end
            if hadAny then
                items[RaidConsumes_WEAPON_ENCHANT_HISTORY_KEY] = (items[RaidConsumes_WEAPON_ENCHANT_HISTORY_KEY] or 0) + merged
            end
        end
    elseif event == "PLAYER_LOGIN" then
        RaidConsumes_InitMinimapButton()
    end
end)

-- "/rc icon <itemKey>" plus a shift-clicked item link on the same line
-- (e.g. "/rc icon flaskTitans [Flask of the Titans]") permanently fixes
-- that item's icon to whatever the shift-clicked item's real icon is --
-- no code edit needed. "/rc icon list" prints every current override.
local function HandleIconCommand(rest)
    rest = rest or ""
    if string.lower(rest) == "list" or rest == "" then
        local any = false
        for key, id in pairs(RaidConsumesDB.iconOverrides or {}) do
            any = true
            local label = (RaidConsumes_ItemByKey[key] and RaidConsumes_ItemByKey[key].label) or key
            DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes icon override: " .. label .. " (" .. key .. ") -> item " .. id)
        end
        if not any then
            DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: no icon overrides set. Usage: /rc icon <itemKey> then shift-click the real item into the same chat line.")
        end
        return
    end

    local _, _, key, itemIDStr = string.find(rest, "^(%S+)%s*.-item:(%d+)")
    if not key or not itemIDStr then
        DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: couldn't find an item link. Usage: type \"/rc icon <itemKey>\" then shift-click the real item so its link lands on the same line.")
        return
    end
    if not RaidConsumes_ItemByKey[key] then
        DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: \"" .. key .. "\" isn't a known item key. Open Settings to find the right key (hover isn't shown, but the item order matches Data.lua).")
        return
    end

    RaidConsumes_SetIconOverride(key, tonumber(itemIDStr))
    DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: icon for " .. RaidConsumes_ItemByKey[key].label .. " updated.")
end

-- "/rc name <itemKey> <exact buff name>" adds an extra buff name to match
-- for that item -- for a custom OctoWoW/Turtle item whose actual applied
-- buff doesn't match what's guessed in Data.lua (R.O.I.D.S. and Danonzo's
-- Tel'Abim Delight are both flagged there as worth double-checking).
-- Additive, not a replacement, so it can't break an already-working match.
-- "/rc name clear <itemKey>" removes all overrides for that item.
-- "/rc name list" prints every override currently set.
local function HandleNameCommand(rest)
    rest = rest or ""
    local trimmed = string.gsub(rest, "^%s+", "")
    if trimmed == "" or string.lower(trimmed) == "list" then
        local any = false
        for key, names in pairs(RaidConsumesDB.nameOverrides or {}) do
            for _, n in ipairs(names) do
                any = true
                local label = (RaidConsumes_ItemByKey[key] and RaidConsumes_ItemByKey[key].label) or key
                DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes name override: " .. label .. " (" .. key .. ") also matches \"" .. n .. "\"")
            end
        end
        if not any then
            DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: no name overrides set. Usage: /rc name <itemKey> <exact buff name>, or /rc name clear <itemKey>.")
        end
        return
    end

    local _, _, clearKey = string.find(trimmed, "^clear%s+(%S+)$")
    if clearKey then
        if not RaidConsumes_ItemByKey[clearKey] then
            DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: \"" .. clearKey .. "\" isn't a known item key.")
            return
        end
        RaidConsumes_ClearNameOverrides(clearKey)
        DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: cleared name overrides for " .. RaidConsumes_ItemByKey[clearKey].label .. ".")
        return
    end

    local _, _, key, buffName = string.find(trimmed, "^(%S+)%s+(.+)$")
    if not key or not buffName or buffName == "" then
        DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: usage \"/rc name <itemKey> <exact buff name>\" (e.g. /rc name danonzosDelight Danonzo's Tel'Abim Delight), \"/rc name clear <itemKey>\", or \"/rc name list\".")
        return
    end
    if not RaidConsumes_ItemByKey[key] then
        DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: \"" .. key .. "\" isn't a known item key. Open Settings to find the right key (hover isn't shown, but the item order matches Data.lua).")
        return
    end

    local added = RaidConsumes_AddNameOverride(key, buffName)
    if added then
        DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: " .. RaidConsumes_ItemByKey[key].label .. " will now also match the buff \"" .. buffName .. "\".")
    else
        DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: that name is already set for " .. RaidConsumes_ItemByKey[key].label .. ".")
    end
end

-- "/rc sync" (or "sync all") broadcasts every checklist to your raid/party
-- (requires sync authority -- raid officer/leader, or party leader);
-- "/rc sync <class or role>" sends just that one; "/rc sync request" asks
-- your raid/party's officers to send theirs to you privately; "/rc sync
-- on"/"off" toggles whether YOU accept incoming syncs. Same actions are
-- also on buttons/a checkbox in the Settings window (see Sync.lua/UI.lua).
--
-- The Physical DPS / Caster DPS role tokens are PHYSDPS/CASTERDPS
-- internally -- these friendlier aliases let you type something more
-- natural instead ("/rc sync physical", "/rc sync caster").
local SYNC_PROFILE_ALIASES = {
    PHYSICAL = "PHYSDPS", PHYS = "PHYSDPS", MELEE = "PHYSDPS", PHYSICALDPS = "PHYSDPS",
    CASTER = "CASTERDPS", RANGED = "CASTERDPS", CASTERS = "CASTERDPS",
}
local function HandleSyncCommand(rest)
    rest = rest and string.gsub(rest, "^%s+", "") or ""
    local lower = string.lower(rest)
    if lower == "" or lower == "all" then
        RaidConsumes_SyncBroadcastAll()
    elseif lower == "request" then
        RaidConsumes_SyncRequest()
    elseif lower == "on" then
        RaidConsumesDB.syncEnabled = true
        DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: now accepting checklist syncs from your raid/party.")
    elseif lower == "off" then
        RaidConsumesDB.syncEnabled = false
        DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: no longer accepting checklist syncs.")
    else
        local upper = string.upper(rest)
        upper = SYNC_PROFILE_ALIASES[upper] or upper
        if RaidConsumes_ClassLabels[upper] or RaidConsumes_RoleLabels[upper] then
            RaidConsumes_SyncBroadcastProfile(upper)
        else
            DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: usage \"/rc sync\" (everything, needs officer/leader), \"/rc sync warrior\" (one class/role -- tank/healer/physical/caster for the role lists), \"/rc sync request\" (ask an officer to sync you), \"/rc sync on\", or \"/rc sync off\".")
        end
    end
end

SLASH_RAIDCONSUMES1 = "/raidconsumes"
SLASH_RAIDCONSUMES2 = "/rc"
SlashCmdList["RAIDCONSUMES"] = function(msg)
    msg = msg or ""
    local lower = string.lower(msg)
    if lower == "check" then
        RaidConsumes_ScanRaid()
        RaidConsumes_RefreshList()
        if not RaidConsumesFrame:IsShown() then
            RaidConsumes_ShowWindow()
        end
    elseif string.find(lower, "^icon") then
        HandleIconCommand(string.sub(msg, 5))
    elseif string.find(lower, "^sync") then
        HandleSyncCommand(string.sub(msg, 5))
    elseif string.find(lower, "^name") then
        HandleNameCommand(string.sub(msg, 5))
    elseif lower == "debug" then
        RaidConsumes_DebugPlayerBuffs()
    else
        RaidConsumes_ToggleWindow()
    end
end

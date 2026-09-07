--[[
RaidConsumes - Sync.lua

Lets a raid officer/leader (or party leader) push their "required"
checklists to everyone else in the group who also has the addon -- no
external library, just vanilla 1.12's own addon-message channel
(SendAddonMessage / CHAT_MSG_ADDON), the same mechanism real classic-era
raid addons used for this.

Wire format, on our own "RCsync" prefix:
    REQ:<profile>:<comma-separated item keys that are CHECKED>
        e.g. "REQ:WARRIOR:flaskTitans,elixirGiants,restedDrink" -- anything
        not listed is implicitly OFF on the receiving end, so a profile
        with nothing checked still sends (with an empty list) to correctly
        clear it.
    REQSYNC
        "someone please send me the current checklists" -- sent by anyone,
        answered automatically (privately, via whisper) by whoever
        receives it AND currently holds sync authority.

Trust model: pushing a sync (the buttons, or "/rc sync") only works if
YOU currently hold "sync authority" -- raid leader or raid officer/assist
in a raid, or the party leader in a party. Everyone else gets a chat
warning telling them to use "Request Sync" instead. On the receiving end,
an incoming REQ is only ever applied if (a) syncing is turned on locally
(RaidConsumesDB.syncEnabled, on by default -- the "Accept checklist
syncs" checkbox, or "/rc sync on|off"), and (b) OUR OWN view of the raid
roster says the sender currently holds that same authority -- not taken
on the sender's word, so a modified client can't just claim to be an
officer. Every applied, rejected, or requested sync prints a line to
chat, so nothing happens silently.
--]]

local SYNC_PREFIX = "RCsync"

local function ProfileLabel(key)
    return RaidConsumes_ClassLabels[key] or RaidConsumes_RoleLabels[key] or key or "?"
end

local function GroupChannel()
    local n = GetNumRaidMembers()
    if n and n > 0 then
        return "RAID"
    end
    local pn = GetNumPartyMembers()
    if pn and pn > 0 then
        return "PARTY"
    end
    return nil
end

-- True if YOU currently hold enough rank to push a checklist sync: raid
-- leader or officer/assist in a raid, or the party leader in a party.
-- Not grouped at all -> false (there's nowhere to send it anyway). Fails
-- closed (false) if a check function isn't even present on this client,
-- rather than assuming you're authorized.
function RaidConsumes_IsSyncAuthority()
    if GetNumRaidMembers() > 0 then
        return (type(IsRaidLeader) == "function" and IsRaidLeader() and true or false)
            or (type(IsRaidOfficer) == "function" and IsRaidOfficer() and true or false)
    end
    if GetNumPartyMembers() > 0 then
        return type(IsPartyLeader) == "function" and IsPartyLeader() and true or false
    end
    return false
end

-- True if `name` currently holds that same authority, per OUR OWN view of
-- the group roster -- looked up locally rather than trusted from the
-- message itself, so it can't be spoofed by a modified client claiming
-- false rank. Fails closed (false) if the lookup can't be done at all.
local function IsNameSyncAuthority(name)
    if not name then return false end
    local n = GetNumRaidMembers()
    if n and n > 0 then
        for i = 1, n do
            local rname, rank = GetRaidRosterInfo(i)
            if rname == name then
                return rank ~= nil and rank >= 1
            end
        end
        return false
    end
    local pn = GetNumPartyMembers()
    if pn and pn > 0 then
        if type(GetPartyLeaderIndex) ~= "function" then
            return false -- can't verify party leadership on this client -- fail closed
        end
        local leaderIdx = GetPartyLeaderIndex()
        if leaderIdx == 0 then
            return name == UnitName("player")
        end
        return leaderIdx ~= nil and name == UnitName("party" .. leaderIdx)
    end
    return false
end

-- Raw send, no authority check -- used both by the gated public broadcast
-- functions below (after THEY'VE checked) and by the private whispered
-- response to a sync request.
local function SendProfilePayload(profile, channel, target)
    local req = RaidConsumes_EnsureRequiredDefaults(profile)
    local keys = {}
    for _, item in ipairs(RaidConsumes_Items) do
        if req[item.key] then
            table.insert(keys, item.key)
        end
    end
    local payload = "REQ:" .. profile .. ":" .. table.concat(keys, ",")
    SendAddonMessage(SYNC_PREFIX, payload, channel, target)
    return table.getn(keys)
end

-- Broadcasts one profile's checklist to your raid/party -- "Sync This
-- Class" / "/rc sync <class or role>". Requires sync authority.
function RaidConsumes_SyncBroadcastProfile(profile)
    local channel = GroupChannel()
    if not channel then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff3030RaidConsumes:|r you need to be in a raid or party to sync checklists.")
        return
    end
    if not RaidConsumes_IsSyncAuthority() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff3030RaidConsumes:|r only a raid officer/leader or party leader can push a checklist sync. Use \"Request Sync\" to ask one of them for the current list instead.")
        return
    end
    local count = SendProfilePayload(profile, channel)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffRaidConsumes:|r sent " .. ProfileLabel(profile) .. "'s checklist to your "
        .. string.lower(channel) .. " (" .. count .. " item(s) required).")
end

-- Broadcasts every class and role's checklist, one message each -- the
-- "Sync All" button / bare "/rc sync". Requires sync authority.
function RaidConsumes_SyncBroadcastAll()
    local channel = GroupChannel()
    if not channel then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff3030RaidConsumes:|r you need to be in a raid or party to sync checklists.")
        return
    end
    if not RaidConsumes_IsSyncAuthority() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff3030RaidConsumes:|r only a raid officer/leader or party leader can push a checklist sync. Use \"Request Sync\" to ask one of them for the current list instead.")
        return
    end
    for _, c in ipairs(RaidConsumes_Classes) do
        local count = SendProfilePayload(c, channel)
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffRaidConsumes:|r sent " .. ProfileLabel(c) .. "'s checklist to your "
            .. string.lower(channel) .. " (" .. count .. " item(s) required).")
    end
    for _, r in ipairs(RaidConsumes_Roles) do
        local count = SendProfilePayload(r, channel)
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffRaidConsumes:|r sent " .. ProfileLabel(r) .. "'s checklist to your "
            .. string.lower(channel) .. " (" .. count .. " item(s) required).")
    end
    local totalProfiles = table.getn(RaidConsumes_Classes) + table.getn(RaidConsumes_Roles)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffRaidConsumes:|r finished broadcasting all " .. totalProfiles .. " checklists.")
end

-- "Request Sync" -- anyone can ask; no authority needed to ask, only to
-- answer. Goes out to the whole raid/party (not targeted at anyone in
-- particular), so whichever officer happens to be online with the addon
-- can pick it up.
function RaidConsumes_SyncRequest()
    local channel = GroupChannel()
    if not channel then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff3030RaidConsumes:|r you need to be in a raid or party to request a sync.")
        return
    end
    SendAddonMessage(SYNC_PREFIX, "REQSYNC", channel)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffRaidConsumes:|r asked your raid/party's officers for a checklist sync.")
end

-- Auto-response to someone else's "Request Sync": only fires if YOU
-- currently hold sync authority, and replies privately (whisper) with
-- every checklist rather than re-broadcasting to the whole raid just
-- because one person asked.
local function RespondToSyncRequest(requester)
    if not RaidConsumes_IsSyncAuthority() then
        return
    end
    for _, c in ipairs(RaidConsumes_Classes) do
        SendProfilePayload(c, "WHISPER", requester)
    end
    for _, r in ipairs(RaidConsumes_Roles) do
        SendProfilePayload(r, "WHISPER", requester)
    end
    local totalProfiles = table.getn(RaidConsumes_Classes) + table.getn(RaidConsumes_Roles)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffRaidConsumes:|r " .. tostring(requester) .. " requested a checklist sync -- sent all " .. totalProfiles .. " privately.")
end

-- Pure-ish (only touches RaidConsumesDB + triggers a UI refresh) so the
-- parsing itself is testable independent of the CHAT_MSG_ADDON plumbing.
function RaidConsumes_SyncApplyIncoming(profile, keyList, sender)
    if not (RaidConsumes_ClassLabels[profile] or RaidConsumes_RoleLabels[profile]) then
        return false -- unknown profile token: different addon version, or garbage -- ignore
    end
    RaidConsumes_EnsureRequiredDefaults(profile)
    local req = RaidConsumesDB.required[profile]
    for key in pairs(req) do
        req[key] = false
    end
    local count = 0
    if keyList and keyList ~= "" then
        for key in string.gfind(keyList, "[^,]+") do
            if RaidConsumes_ItemByKey[key] then
                req[key] = true
                count = count + 1
            end
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffRaidConsumes:|r " .. tostring(sender) .. " synced " .. ProfileLabel(profile)
        .. "'s checklist (" .. count .. " item(s) required).")
    if RaidConsumesDB_SelectedClass == profile and RaidConsumes_RefreshSettings then
        RaidConsumes_RefreshSettings()
    end
    if RaidConsumes_RefreshList then
        RaidConsumes_RefreshList()
    end
    return true
end

local syncFrame = CreateFrame("Frame")
syncFrame:RegisterEvent("CHAT_MSG_ADDON")
syncFrame:SetScript("OnEvent", function()
    if event ~= "CHAT_MSG_ADDON" then return end
    local prefix, message, _, sender = arg1, arg2, arg3, arg4
    if prefix ~= SYNC_PREFIX then return end
    if sender == UnitName("player") then return end

    if message == "REQSYNC" then
        RespondToSyncRequest(sender)
        return
    end

    if not RaidConsumesDB or not RaidConsumesDB.syncEnabled then return end
    local _, _, profile, keyList = string.find(message, "^REQ:([^:]+):(.*)$")
    if not profile then return end
    if not IsNameSyncAuthority(sender) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff3030RaidConsumes:|r ignored a checklist sync from " .. tostring(sender)
            .. " -- only a raid officer/leader or party leader can push syncs.")
        return
    end
    RaidConsumes_SyncApplyIncoming(profile, keyList, sender)
end)

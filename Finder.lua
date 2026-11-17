local _, ns = ...

-- The group finder side: reading listings out of the search results, remembering every group seen
-- (by each member's name, so an invite from any of them matches) and running searches. Forever's
-- finder is the vanilla-style one (leader, members, activities, comment; one category a search),
-- and anything the game may hide is read safely: left out, never compared.

local Finder = {}
ns.Finder = Finder

local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local KEEP = 30 * 60 -- how long a group seen in the results is remembered (seconds)

local seen = {} -- [name key] = entry, for every member of every group seen
local current = {} -- [search result ID] = true, for the results the game holds now

-- A name as a key: lowercased, without its realm; nil when it's hidden or missing.
function Finder.Key(name)
    if type(name) ~= "string" or issecret(name) or name == "" then return nil end
    return (name:match("^[^-]+") or name):lower()
end

local function Roles(roles)
    if type(roles) ~= "table" then return nil end
    return { tank = Safe(roles.tank), healer = Safe(roles.healer), dps = Safe(roles.dps) }
end

local function Player(info)
    if type(info) ~= "table" then return nil end
    return {
        name = Safe(info.name), level = Safe(info.level), area = Safe(info.areaName),
        class = Safe(info.classFilename), className = Safe(info.className),
        role = Safe(info.assignedRole), roles = Roles(info.lfgRoles), leader = Safe(info.isLeader),
    }
end

-- One search result as a plain table, or nil when the game won't give it.
local function Read(id)
    local ok, info = pcall(C_LFGList.GetSearchResultInfo, id)
    if not ok or type(info) ~= "table" then return nil end
    local entry = {
        id = id,
        leader = Safe(info.leaderName),
        comment = Safe(info.comment), -- a protected string: shown, never read
        numMembers = Safe(info.numMembers) or 0,
        age = Safe(info.age),
        delisted = Safe(info.isDelisted),
        autoAccept = Safe(info.autoAccept),
        generalPlaystyle = Safe(info.generalPlaystyle), -- the group type: learning, relaxed...
        newPlayerFriendly = Safe(info.newPlayerFriendly),
        activities = {},
        members = {},
        seenAt = GetTime(),
    }
    if type(info.activityIDs) == "table" and not issecret(info.activityIDs) then
        for _, activityID in ipairs(info.activityIDs) do
            activityID = Safe(activityID)
            if activityID then entry.activities[#entry.activities + 1] = activityID end
        end
    end
    for i = 1, math.min(entry.numMembers, 40) do
        local fine, player = pcall(C_LFGList.GetSearchResultPlayerInfo, id, i)
        player = fine and Player(player)
        if player then entry.members[#entry.members + 1] = player end
    end
    if #entry.members == 0 then
        -- Only the leader, when the members can't be read.
        local fine, player = pcall(C_LFGList.GetSearchResultLeaderInfo, id)
        player = fine and Player(player)
        if player then
            player.leader = true
            entry.members[1] = player
        end
    end
    return entry
end

local function Remember(entry)
    local leader = Finder.Key(entry.leader)
    if leader then seen[leader] = entry end
    for _, member in ipairs(entry.members) do
        local key = Finder.Key(member.name)
        if key then seen[key] = entry end
    end
end

-- Reads every result the game holds now into the memory (on each search's results).
function Finder.Snapshot()
    wipe(current)
    local ok, _, results = pcall(C_LFGList.GetSearchResults)
    if ok and type(results) == "table" then
        for _, id in ipairs(results) do
            id = Safe(id)
            if id then
                current[id] = true
                local entry = Read(id)
                if entry then Remember(entry) end
            end
        end
    end
    -- Forget groups not seen for a while.
    local now = GetTime()
    for key, entry in pairs(seen) do
        if now - entry.seenAt > KEEP then seen[key] = nil end
    end
end

-- One result changed (members joined or left, delisted): read again if it's remembered.
function Finder.Updated(id)
    id = Safe(id)
    if not (id and current[id]) then return end
    local entry = Read(id)
    if entry then Remember(entry) end
end

local function Has(entry, key)
    if Finder.Key(entry.leader) == key then return true end
    for _, member in ipairs(entry.members) do
        if Finder.Key(member.name) == key then return true end
    end
    return false
end

-- The group `name` is in: its entry and whether it's in the game's results now (then it's read
-- afresh), or nil.
function Finder.Find(name)
    local key = Finder.Key(name)
    if not key then return nil end
    local entry = seen[key]
    if not entry then return nil end
    if current[entry.id] then
        local fresh = Read(entry.id)
        if fresh and Has(fresh, key) then
            Remember(fresh)
            return fresh, true
        end
    end
    return entry, false
end

------------------------------------------------------------------------------
-- Activities and categories
------------------------------------------------------------------------------

local function Activity(id)
    local ok, info = pcall(C_LFGList.GetActivityInfoTable, id)
    if ok and type(info) == "table" then return info end
end

local function FirstActivity(entry)
    return entry.activities[1] and Activity(entry.activities[1])
end

-- The names of what a group's listed for.
function Finder.ActivityNames(entry)
    local names = {}
    for _, id in ipairs(entry.activities) do
        local activity = Activity(id)
        local name = activity and ((activity.shortName ~= "" and activity.shortName) or activity.fullName)
        names[#names + 1] = name or ("Activity " .. id)
    end
    return names
end

-- The dungeon's own banner art, to try in turn as { file, { left, right, top, bottom } } (a missing
-- file won't set): its journal pictures, then its lore painting and group finder background by name.
local LORE = "Interface\\EncounterJournal\\UI-EJ-LOREBG-"
local BACKGROUND = "Interface\\LFGFrame\\UI-LFG-BACKGROUND-"
local LORE_CUT = { 0.08, 0.69, 0.23, 0.35 } -- the painting inside the lore picture's frame
local BACKGROUND_CUT = { 0, 1, 0.31, 0.69 }

function Finder.Art(entry)
    local activity = FirstActivity(entry)
    if not activity then return nil end
    local tries = {}
    local mapID = Safe(activity.mapID)
    if mapID and mapID > 0 and C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap and EJ_GetInstanceInfo then
        local ok, journal = pcall(C_EncounterJournal.GetInstanceForGameMap, mapID)
        if ok and journal then
            local fine, _, _, background, _, lore = pcall(EJ_GetInstanceInfo, journal)
            if fine and lore and lore ~= 0 then tries[#tries + 1] = { lore, LORE_CUT } end
            if fine and background and background ~= 0 then tries[#tries + 1] = { background, { 0, 1, 0.3, 0.5 } } end
        end
    end
    local name = Safe(activity.fullName)
    local token = type(name) == "string" and name:gsub("[^%a]", "")
    if token and token ~= "" then
        tries[#tries + 1] = { LORE .. token, LORE_CUT }
        tries[#tries + 1] = { BACKGROUND .. token, BACKGROUND_CUT }
    end
    return tries
end

-- Where a player is, for those the game will say: a friend's or a guild member's zone.
function Finder.KnownZone(name)
    local key = Finder.Key(name)
    if not key then return nil end
    if C_FriendList and C_FriendList.GetFriendInfo then
        local ok, info = pcall(C_FriendList.GetFriendInfo, name)
        if ok and type(info) == "table" and Safe(info.connected) then
            local area = Safe(info.area)
            if area and area ~= "" then return area end
        end
    end
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, GetNumGuildMembers() do
            local memberName, _, _, _, _, zone, _, _, online = GetGuildRosterInfo(i)
            if online and Finder.Key(memberName) == key then
                zone = Safe(zone)
                if zone and zone ~= "" then return zone end
            end
        end
    end
end

-- How many players its activity takes (the first one's), or nil.
function Finder.MaxPlayers(entry)
    local activity = FirstActivity(entry)
    local count = activity and Safe(activity.maxNumPlayers)
    if type(count) == "number" and count > 0 then return count end
end

-- The group type the leader picked (Enum.LFGEntryGeneralPlaystyle): its name in Blizzard's words,
-- and a key for its colour; nil when none was picked.
local PLAYSTYLES = { [1] = "learning", [2] = "relaxed", [3] = "competitive", [4] = "expert" }
local PLAYSTYLE_NAMES = { learning = "Learning", relaxed = "Relaxed", competitive = "Competitive", expert = "Expert" }

function Finder.Playstyle(entry)
    local key = PLAYSTYLES[entry.generalPlaystyle or 0]
    if not key then return nil end
    local name
    if GetGeneralPlaystyleString then
        local ok, text = pcall(GetGeneralPlaystyleString, entry.generalPlaystyle)
        if ok and type(text) == "string" and not issecret(text) and text ~= "" then name = text end
    end
    return name or PLAYSTYLE_NAMES[key], key
end

-- The category a group's listed in (its first activity's), or nil.
function Finder.CategoryOf(entry)
    local activity = FirstActivity(entry)
    return activity and activity.categoryID
end

local function CategoryName(id)
    local ok, info = pcall(C_LFGList.GetLfgCategoryInfo, id)
    return ok and type(info) == "table" and info.name or ("Category " .. id)
end

-- The categories to search, the one Blizzard's group finder has picked first: { { id, name } }.
function Finder.Categories()
    local categories = {}
    local ok, available = pcall(C_LFGList.GetAvailableCategories)
    if not ok or type(available) ~= "table" then return categories end
    local picked
    pcall(function() picked = LFGBrowseFrame.CategoryDropdown:GetValue() end)
    for _, id in ipairs(available) do
        local fine, activities = pcall(C_LFGList.GetAvailableActivities, id)
        if fine and type(activities) == "table" and #activities > 0 then
            local category = { id = id, name = CategoryName(id) }
            if id == picked then table.insert(categories, 1, category) else categories[#categories + 1] = category end
        end
    end
    return categories
end

-- Searches a whole category (every activity in it, whatever your level). Only from a click: the
-- game restricts C_LFGList.Search, so the panel's button runs it.
function Finder.Search(categoryID)
    local ok, activities = pcall(C_LFGList.GetAvailableActivities, categoryID)
    if not ok or type(activities) ~= "table" then return false end
    return (pcall(C_LFGList.Search, categoryID, 0, 0, nil, false, nil, activities))
end

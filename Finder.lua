local _, ns = ...

-- The group finder side: reading listings out of the search results, remembering every group seen
-- (by the name of each member, so an invite from any of them matches) and running searches.
--
-- Forever's group finder is the vanilla-style one: a listing is its leader, its members, the
-- activities it's listed for and a comment (no title). One search covers one category, and
-- C_LFGList.Search only runs from a click (it's restricted), so the panel's button runs it.
-- Anything the game may hide (names, levels, the result itself in chat lockdown) is read safely:
-- a hidden value is left out, never compared.

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

local function Roles(r)
    if type(r) ~= "table" then return nil end
    return { tank = Safe(r.tank), healer = Safe(r.healer), dps = Safe(r.dps) }
end

local function Player(p)
    if type(p) ~= "table" then return nil end
    return {
        name = Safe(p.name), level = Safe(p.level), area = Safe(p.areaName),
        class = Safe(p.classFilename), className = Safe(p.className),
        role = Safe(p.assignedRole), roles = Roles(p.lfgRoles), leader = Safe(p.isLeader),
    }
end

-- One search result as a plain table, or nil when the game won't give it.
local function Read(id)
    local ok, info = pcall(C_LFGList.GetSearchResultInfo, id)
    if not ok or type(info) ~= "table" then return nil end
    local e = {
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
        for _, a in ipairs(info.activityIDs) do
            a = Safe(a)
            if a then e.activities[#e.activities + 1] = a end
        end
    end
    for i = 1, math.min(e.numMembers, 40) do
        local fine, p = pcall(C_LFGList.GetSearchResultPlayerInfo, id, i)
        p = fine and Player(p)
        if p then e.members[#e.members + 1] = p end
    end
    if #e.members == 0 then
        -- Only the leader, when the members can't be read.
        local fine, p = pcall(C_LFGList.GetSearchResultLeaderInfo, id)
        p = fine and Player(p)
        if p then
            p.leader = true
            e.members[1] = p
        end
    end
    return e
end

local function Remember(e)
    local keys = {}
    local k = Finder.Key(e.leader)
    if k then keys[k] = true end
    for _, m in ipairs(e.members) do
        k = Finder.Key(m.name)
        if k then keys[k] = true end
    end
    for key in pairs(keys) do seen[key] = e end
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
                local e = Read(id)
                if e then Remember(e) end
            end
        end
    end
    -- Forget groups not seen for a while.
    local now = GetTime()
    for key, e in pairs(seen) do
        if now - e.seenAt > KEEP then seen[key] = nil end
    end
end

-- One result changed (members joined or left, delisted): read again if it's remembered.
function Finder.Updated(id)
    id = Safe(id)
    if not (id and current[id]) then return end
    local e = Read(id)
    if e then Remember(e) end
end

local function Has(e, key)
    if Finder.Key(e.leader) == key then return true end
    for _, m in ipairs(e.members) do
        if Finder.Key(m.name) == key then return true end
    end
    return false
end

-- The group `name` is in: its entry and whether it's in the game's results now (then it's read
-- afresh), or nil.
function Finder.Find(name)
    local key = Finder.Key(name)
    if not key then return nil end
    local e = seen[key]
    if not e then return nil end
    if current[e.id] then
        local fresh = Read(e.id)
        if fresh and Has(fresh, key) then
            Remember(fresh)
            return fresh, true
        end
    end
    return e, false
end

------------------------------------------------------------------------------
-- Activities and categories
------------------------------------------------------------------------------

local function Activity(id)
    local ok, a = pcall(C_LFGList.GetActivityInfoTable, id)
    if ok and type(a) == "table" then return a end
end

-- The names of what a group's listed for.
function Finder.ActivityNames(e)
    local names = {}
    for _, id in ipairs(e.activities) do
        local a = Activity(id)
        local name = a and ((a.shortName ~= "" and a.shortName) or a.fullName)
        names[#names + 1] = name or ("Activity " .. id)
    end
    return names
end

-- The dungeon's own art for the banner: the Encounter Journal's lore picture (the painting in its
-- frame, cut to a band across its middle), found through the journal or by the dungeon's name, or
-- the group finder's darker background for it: a list of { file, { left, right, top, bottom } }
-- to try in turn (a file that isn't there won't set), or nil.
local LORE = "Interface\\EncounterJournal\\UI-EJ-LOREBG-"
local BACKGROUND = "Interface\\LFGFrame\\UI-LFG-BACKGROUND-"
local LORE_CUT = { 0.08, 0.69, 0.23, 0.35 } -- the painting inside the lore picture's frame
local BACKGROUND_CUT = { 0, 1, 0.31, 0.69 }

function Finder.Art(e)
    local a = e.activities[1] and Activity(e.activities[1])
    if not a then return nil end
    local tries = {}
    local mapID = Safe(a.mapID)
    if mapID and mapID > 0 and C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap and EJ_GetInstanceInfo then
        local ok, journal = pcall(C_EncounterJournal.GetInstanceForGameMap, mapID)
        if ok and journal then
            local fine, _, _, bg, _, lore = pcall(EJ_GetInstanceInfo, journal)
            if fine and lore and lore ~= 0 then tries[#tries + 1] = { lore, LORE_CUT } end
            if fine and bg and bg ~= 0 then tries[#tries + 1] = { bg, { 0, 1, 0.3, 0.5 } } end
        end
    end
    local name = Safe(a.fullName)
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
            local who, _, _, _, _, zone, _, _, online = GetGuildRosterInfo(i)
            if online and Finder.Key(who) == key then
                zone = Safe(zone)
                if zone and zone ~= "" then return zone end
            end
        end
    end
end

-- How many players its activity takes (the first one's), or nil.
function Finder.MaxPlayers(e)
    local a = e.activities[1] and Activity(e.activities[1])
    local n = a and Safe(a.maxNumPlayers)
    if type(n) == "number" and n > 0 then return n end
end

-- The group type the leader picked (Enum.LFGEntryGeneralPlaystyle): its name in Blizzard's words,
-- and a key for its colour; nil when none was picked.
local PLAYSTYLES = { [1] = "learning", [2] = "relaxed", [3] = "competitive", [4] = "expert" }
local PLAYSTYLE_NAMES = { learning = "Learning", relaxed = "Relaxed", competitive = "Competitive", expert = "Expert" }

function Finder.Playstyle(e)
    local key = PLAYSTYLES[e.generalPlaystyle or 0]
    if not key then return nil end
    local name
    if GetGeneralPlaystyleString then
        local ok, text = pcall(GetGeneralPlaystyleString, e.generalPlaystyle)
        if ok and type(text) == "string" and not issecret(text) and text ~= "" then name = text end
    end
    return name or PLAYSTYLE_NAMES[key], key
end

-- The category a group's listed in (its first activity's), or nil.
function Finder.CategoryOf(e)
    local a = e.activities[1] and Activity(e.activities[1])
    return a and a.categoryID
end

local function CategoryName(id)
    local ok, info = pcall(C_LFGList.GetLfgCategoryInfo, id)
    return ok and type(info) == "table" and info.name or ("Category " .. id)
end

-- The categories to search, the one Blizzard's group finder has picked first: { { id, name } }.
function Finder.Categories()
    local out = {}
    local ok, cats = pcall(C_LFGList.GetAvailableCategories)
    if not ok or type(cats) ~= "table" then return out end
    local picked
    pcall(function() picked = LFGBrowseFrame.CategoryDropdown:GetValue() end)
    for _, id in ipairs(cats) do
        local fine, acts = pcall(C_LFGList.GetAvailableActivities, id)
        if fine and type(acts) == "table" and #acts > 0 then
            local c = { id = id, name = CategoryName(id) }
            if id == picked then table.insert(out, 1, c) else out[#out + 1] = c end
        end
    end
    return out
end

-- Searches a whole category (every activity in it, whatever your level). Only from a click.
function Finder.Search(categoryID)
    local ok, acts = pcall(C_LFGList.GetAvailableActivities, categoryID)
    if not ok or type(acts) ~= "table" then return false end
    return (pcall(C_LFGList.Search, categoryID, 0, 0, nil, false, nil, acts))
end

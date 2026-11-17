local _, ns = ...

-- Who the inviter is, when they aren't in the group finder: race and class straight away (from the
-- invite's GUID) and level, guild and zone from a /who. SendWho only runs from a click, so the
-- panel's Who button sends it; the answer is the who list (WHO_LIST_UPDATE, or a line in chat for a
-- short list), read by name, and no answer in a few seconds means they weren't found.

local Who = {}
ns.Who = Who

local issecret, Safe = FrogLib.issecret, FrogLib.Safe
Who.WAIT = 5 -- seconds to wait for an answer

-- Race and class from the inviter's GUID: { class, className, race }, or nil.
function Who.FromGUID(guid)
    if type(guid) ~= "string" or issecret(guid) or guid == "" or not GetPlayerInfoByGUID then return nil end
    local ok, className, class, race = pcall(GetPlayerInfoByGUID, guid)
    if not ok then return nil end
    class, className, race = Safe(class), Safe(className), Safe(race)
    if type(class) ~= "string" or class == "" then return nil end
    return { class = class, className = className, race = race }
end

-- A who list row as a plain table, or nil.
local function Row(index)
    if C_FriendList and C_FriendList.GetWhoInfo then
        local ok, info = pcall(C_FriendList.GetWhoInfo, index)
        if not ok or type(info) ~= "table" then return nil end
        return {
            name = Safe(info.fullName), guild = Safe(info.fullGuildName), level = Safe(info.level),
            race = Safe(info.raceStr), className = Safe(info.classStr), class = Safe(info.filename),
            area = Safe(info.area),
        }
    elseif GetWhoInfo then
        local ok, name, guild, level, race, className, area, class = pcall(GetWhoInfo, index)
        if not ok then return nil end
        return {
            name = Safe(name), guild = Safe(guild), level = Safe(level), race = Safe(race),
            className = Safe(className), class = Safe(class), area = Safe(area),
        }
    end
end

-- `name` in the who list the game holds now, or nil.
function Who.Find(name)
    local key = ns.Finder.Key(name)
    if not key then return nil end
    local count = 0
    if C_FriendList and C_FriendList.GetNumWhoResults then
        local ok, results = pcall(C_FriendList.GetNumWhoResults)
        count = ok and Safe(results) or 0
    elseif GetNumWhoResults then
        local ok, results = pcall(GetNumWhoResults)
        count = ok and Safe(results) or 0
    end
    for i = 1, math.min(tonumber(count) or 0, 50) do
        local row = Row(i)
        if row and ns.Finder.Key(row.name) == key then return row end
    end
end

-- Sends the /who (only from a click). True when the game took it.
function Who.Send(name)
    local base = type(name) == "string" and not issecret(name) and name:match("^[^-]+")
    if not base or base == "" then return false end
    local filter = 'n-"' .. base .. '"'
    if C_FriendList and C_FriendList.SendWho then
        return (pcall(C_FriendList.SendWho, filter))
    elseif SendWho then
        return (pcall(SendWho, filter))
    end
    return false
end

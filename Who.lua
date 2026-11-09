local _, ns = ...

-- Who the inviter is, for an invite from someone who isn't in the group finder: their race and
-- class straight away (from the invite's GUID, which the game already knows), and their level,
-- guild and zone from a /who. C_FriendList.SendWho is restricted (it only runs from a click), so
-- the panel's Who button sends it. Its answer comes back as the who list (WHO_LIST_UPDATE, or a
-- line in chat for a short list), read by name; no answer in a few seconds means they weren't found.

local Who = {}
ns.Who = Who

local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local WAIT = 5 -- seconds to wait for an answer

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
local function Row(i)
    if C_FriendList and C_FriendList.GetWhoInfo then
        local ok, info = pcall(C_FriendList.GetWhoInfo, i)
        if not ok or type(info) ~= "table" then return nil end
        return {
            name = Safe(info.fullName), guild = Safe(info.fullGuildName), level = Safe(info.level),
            race = Safe(info.raceStr), className = Safe(info.classStr), class = Safe(info.filename),
            area = Safe(info.area),
        }
    elseif GetWhoInfo then
        local ok, name, guild, level, race, className, area, class = pcall(GetWhoInfo, i)
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
    local n = 0
    if C_FriendList and C_FriendList.GetNumWhoResults then
        local ok, num = pcall(C_FriendList.GetNumWhoResults)
        n = ok and Safe(num) or 0
    elseif GetNumWhoResults then
        local ok, num = pcall(GetNumWhoResults)
        n = ok and Safe(num) or 0
    end
    for i = 1, math.min(tonumber(n) or 0, 50) do
        local r = Row(i)
        if r and ns.Finder.Key(r.name) == key then return r end
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

Who.WAIT = WAIT

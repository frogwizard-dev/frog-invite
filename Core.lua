local ADDON, ns = ...

-- FrogInvite: when someone invites you to a group, a panel under the invite shows their group
-- finder listing (what it's for, its comment, who's in it), matched against every member of every
-- group in your results and those seen in the last half hour. Not there: a button searches the
-- finder a category a click, and a Who button asks /who for their level, guild and zone.

local Finder, Who, Panel = ns.Finder, ns.Who, ns.Panel
ns.Print = FrogLib.Util.Printer("FrogInvite", "7fd07f")

-- The invite being looked into: { inviter, categories = { { id, name } }, next (index into them),
-- searching (a category name, while its search runs), failed, who = { info, asking, none } }, or nil.
local state

local function NextCategory()
    -- A group seen before: its own category first.
    if state.entry and not state.ownTried then
        local id = Finder.CategoryOf(state.entry)
        for _, category in ipairs(state.categories) do
            if category.id == id then return category, true end
        end
    end
    return state.categories[state.next]
end

local function Refresh()
    if not state then return end
    local entry, live = Finder.Find(state.inviter)
    state.entry = entry
    local view = { inviter = state.inviter, entry = entry, live = live, test = state.test }
    if not entry then
        -- Not in the group finder: who they are, and the button that asks /who.
        local who = state.who
        view.who = who.info
        if who.asking then
            view.whoButton, view.whoBusy = "Asking /who...", true
        elseif who.none then
            view.whoNote = "Not found by /who: offline, or asked too soon after another /who."
            view.whoButton = "Ask /who again"
        elseif not (who.info and who.info.level) then
            view.whoButton = "Who is " .. state.inviter .. "?"
        end
    end
    local category, own = NextCategory()
    if state.searching then
        view.status = "Searching " .. state.searching .. "..."
        view.busy = true
    elseif state.failed then
        view.status = "The search didn't go through (searching too often?). Try again in a moment."
    elseif entry and live then
        view.status = "From your group finder results."
    elseif entry then
        view.status = "Seen in an earlier search, no longer in your results: it may have changed."
    elseif #state.categories == 0 then
        view.status = "The group finder isn't available."
    elseif not category then
        view.status = "Not listed in any group finder category."
    elseif state.next > 1 then
        view.status = "Not found yet."
    else
        view.status = "Not in your group finder results."
    end
    if category then
        view.button = (entry and own) and ("Refresh (" .. category.name .. ")") or ("Search " .. category.name
            .. (#state.categories > 1 and (" (%d/%d)"):format(state.next, #state.categories) or ""))
    elseif #state.categories > 0 then
        view.button = "Search again from the start"
    end
    Panel:Show(view)
end

-- The panel's button (a click: the only way a search may start).
function ns.SearchNext()
    if not state or state.searching then return end
    local category, own = NextCategory()
    if not category then
        state.next = 1 -- every category tried: round again
        state.ownTried = nil
        category, own = NextCategory()
        if not category then return end
    end
    state.failed = nil
    if Finder.Search(category.id) then
        state.searching = category.name
        state.pending = { own = own }
        -- No answer at all: the button back after a while.
        local mine = state.pending
        C_Timer.After(10, function()
            if state and state.pending == mine then
                state.searching, state.pending, state.failed = nil, nil, true
                Refresh()
            end
        end)
    else
        state.failed = true
    end
    Refresh()
end

-- The Who button (a click: the only way a /who may go out).
function ns.AskWho()
    if not state or state.who.asking then return end
    local who = state.who
    who.none = nil
    if not Who.Send(state.inviter) then
        who.none = true
        Refresh()
        return
    end
    local mine = {}
    who.asking = mine
    C_Timer.After(Who.WAIT, function()
        if state and state.who == who and who.asking == mine then
            who.asking, who.none = nil, true
            Refresh()
        end
    end)
    Refresh()
end

-- The who list changed (or a line came into chat): the answer, if it's there.
local function WhoAnswered()
    local who = state and state.who
    if not (who and who.asking) then return end
    local answer = Who.Find(state.inviter)
    if not answer then return end
    -- Keep what the invite already said where the /who leaves it out.
    local info = who.info or {}
    for key, value in pairs(answer) do
        if value ~= nil and value ~= "" then info[key] = value end
    end
    who.info, who.asking, who.none = info, nil, nil
    Refresh()
end

function ns.Closed()
    state = nil
end

local function Start(inviter, test, guid)
    if type(inviter) ~= "string" or FrogLib.issecret(inviter) or inviter == "" then return end
    state = { inviter = inviter, categories = Finder.Categories(), next = 1, test = test,
        who = { info = Who.FromGUID(guid) } }
    Finder.Snapshot()
    Refresh()
end

-- The inviter's GUID in an invite, picked out by its look: a Forever update put a new field in
-- front of it, so its place depends on the game's version. Hidden values are passed over.
local function InviterGUID(...)
    for i = 2, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "string" and not FrogLib.issecret(value) and value:find("^Player%-") then return value end
    end
end

ns.defaults = {
    scale = 1.15, -- the panel's size
}

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PARTY_INVITE_REQUEST", "PARTY_INVITE_CANCEL", "LFG_LIST_SEARCH_RESULTS_RECEIVED",
    "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_SEARCH_FAILED", "GROUP_JOINED", "WHO_LIST_UPDATE", "CHAT_MSG_SYSTEM" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == ADDON then
            FrogInviteDB = FrogInviteDB or {}
            FrogLib.Util.CopyDefaults(ns.defaults, FrogInviteDB)
            ns.db = FrogInviteDB
        end
    elseif event == "PARTY_INVITE_REQUEST" then
        -- Once the game's own popup is up (the one with role buttons takes a moment), so the
        -- panel can sit under it.
        local inviter, guid = (...), InviterGUID(...)
        C_Timer.After(0.15, function() Start(inviter, nil, guid) end)
    elseif event == "PARTY_INVITE_CANCEL" or event == "GROUP_JOINED" then
        if Panel:IsShown() then Panel:Hide() end
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        Finder.Snapshot()
        if state then
            local pending = state.pending
            if pending and state.searching then
                -- Ours: if they still aren't in, the next click tries the next category.
                if pending.own then
                    state.ownTried = true
                else
                    state.next = state.next + 1
                end
            end
            state.searching, state.pending = nil, nil
            Refresh()
        end
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        local resultID = ...
        Finder.Updated(resultID)
        if state and not state.searching then Refresh() end
    elseif event == "WHO_LIST_UPDATE" or event == "CHAT_MSG_SYSTEM" then
        -- A short who list comes as lines in chat; the list itself is filled either way.
        WhoAnswered()
    elseif event == "LFG_LIST_SEARCH_FAILED" then
        if state and state.searching then
            state.searching, state.pending, state.failed = nil, nil, true
            Refresh()
        end
    end
end)

SLASH_FROGINVITE1 = "/finvite"
SLASH_FROGINVITE2 = "/froginvite"
SlashCmdList.FROGINVITE = function(input)
    input = strtrim(input or "")
    local scale = input:match("^scale%s*([%d%.]*)$")
    if scale then
        scale = tonumber(scale)
        if scale and scale >= 0.5 and scale <= 2 then
            ns.db.scale = scale
            if Panel:IsShown() then Refresh() end
        end
        ns.Print(("Panel scale: %.2f (/finvite scale 0.5 to 2)."):format(ns.db.scale))
        return
    end
    if input == "" then
        ns.Print("/finvite <name>: shows the panel as if <name> had invited you (matched against your group finder results).")
        ns.Print("/finvite scale <0.5 to 2>: the panel's size.")
        return
    end
    Start(input, true) -- a test: no invite popup to sit under
end

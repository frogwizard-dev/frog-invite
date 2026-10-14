local ADDON, ns = ...

-- FrogInvite: when someone invites you to a group, a panel under the invite shows their group
-- finder listing: what it's listed for, its comment and who's in it already. It matches the
-- inviter against every member of every group in your group finder results (and groups seen in
-- the last half hour, from earlier searches). When they aren't there, its button searches the
-- group finder, a category a click (the game only lets a search start from a click), and it
-- looks again as each search's results come in.
--   Finder.lua: the listings and searches. Panel.lua: the panel.
--   /finvite <name>: shows the panel as if <name> had invited you.

local Finder, Panel = ns.Finder, ns.Panel
ns.Print = FrogLib.Util.Printer("FrogInvite", "7fd07f")

-- The invite being looked into: { inviter, cats = { { id, name } }, next (index into cats),
-- searching (a category name, while its search runs), failed }, or nil.
local state

local function NextCategory()
    -- A group seen before: its own category first.
    if state.entry and not state.ownTried then
        local id = Finder.CategoryOf(state.entry)
        for _, c in ipairs(state.cats) do
            if c.id == id then return c, true end
        end
    end
    return state.cats[state.next]
end

local function Refresh()
    if not state then return end
    local entry, live = Finder.Find(state.inviter)
    state.entry = entry
    local s = { inviter = state.inviter, entry = entry, live = live, test = state.test }
    local c, own = NextCategory()
    if state.searching then
        s.status = "Searching " .. state.searching .. "..."
        s.busy = true
    elseif state.failed then
        s.status = "The search didn't go through (searching too often?). Try again in a moment."
    elseif entry and live then
        s.status = "From your group finder results."
    elseif entry then
        s.status = "Seen in an earlier search, no longer in your results: it may have changed."
    elseif #state.cats == 0 then
        s.status = "The group finder isn't available."
    elseif not c then
        s.status = "Not listed in any group finder category."
    elseif state.next > 1 then
        s.status = "Not found yet."
    else
        s.status = "Not in your group finder results."
    end
    if c then
        s.button = (entry and own) and ("Refresh (" .. c.name .. ")") or ("Search " .. c.name
            .. (#state.cats > 1 and (" (%d/%d)"):format(state.next, #state.cats) or ""))
    elseif #state.cats > 0 then
        s.button = "Search again from the start"
    end
    Panel:Show(s)
end

-- The panel's button (a click: the only way a search may start).
function ns.SearchNext()
    if not state or state.searching then return end
    local c, own = NextCategory()
    if not c then
        state.next = 1 -- every category tried: round again
        state.ownTried = nil
        c, own = NextCategory()
        if not c then return end
    end
    state.failed = nil
    if Finder.Search(c.id) then
        state.searching = c.name
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

function ns.Closed()
    state = nil
end

local function Start(inviter, test)
    if type(inviter) ~= "string" or FrogLib.issecret(inviter) or inviter == "" then return end
    state = { inviter = inviter, cats = Finder.Categories(), next = 1, test = test }
    Finder.Snapshot()
    Refresh()
end

ns.defaults = {
    scale = 1.15, -- the panel's size
}

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PARTY_INVITE_REQUEST", "PARTY_INVITE_CANCEL", "LFG_LIST_SEARCH_RESULTS_RECEIVED",
    "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_SEARCH_FAILED", "GROUP_JOINED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            FrogInviteDB = FrogInviteDB or {}
            FrogLib.Util.CopyDefaults(ns.defaults, FrogInviteDB)
            ns.db = FrogInviteDB
        end
    elseif event == "PARTY_INVITE_REQUEST" then
        -- Once the game's own popup is up (the one with role buttons takes a moment), so the
        -- panel can sit under it.
        C_Timer.After(0.15, function() Start(arg1) end)
    elseif event == "PARTY_INVITE_CANCEL" or event == "GROUP_JOINED" then
        if Panel:IsShown() then Panel:Hide() end
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        Finder.Snapshot()
        if state then
            local p = state.pending
            if p and state.searching then
                -- Ours: if they still aren't in, the next click tries the next category.
                if p.own then
                    state.ownTried = true
                else
                    state.next = state.next + 1
                end
            end
            state.searching, state.pending = nil, nil
            Refresh()
        end
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        Finder.Updated(arg1)
        if state and not state.searching then Refresh() end
    elseif event == "LFG_LIST_SEARCH_FAILED" then
        if state and state.searching then
            state.searching, state.pending, state.failed = nil, nil, true
            Refresh()
        end
    end
end)

SLASH_FROGINVITE1 = "/finvite"
SLASH_FROGINVITE2 = "/froginvite"
SlashCmdList.FROGINVITE = function(msg)
    msg = strtrim(msg or "")
    local scale = msg:match("^scale%s*([%d%.]*)$")
    if scale then
        scale = tonumber(scale)
        if scale and scale >= 0.5 and scale <= 2 then
            ns.db.scale = scale
            if Panel:IsShown() then Refresh() end
        end
        ns.Print(("Panel scale: %.2f (/finvite scale 0.5 to 2)."):format(ns.db.scale))
        return
    end
    if msg == "" then
        ns.Print("/finvite <name>: shows the panel as if <name> had invited you (matched against your group finder results).")
        ns.Print("/finvite scale <0.5 to 2>: the panel's size.")
        return
    end
    Start(msg, true) -- a test: no invite popup to sit under
end

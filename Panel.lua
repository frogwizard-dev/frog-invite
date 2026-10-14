local _, ns = ...

-- The panel under the invite popup, minimal dark like FrogUI:
--   a banner with the category's own group finder art (darkened): what the group's listed for,
--     who invited you (in their class colour) and the group type (Learning, Relaxed, Competitive,
--     Expert) as a coloured badge;
--   a line of details (players, how long it's been listed, auto accept), the other activities,
--     the comment, and a row for each member (class icon, name, leader's crown, level, role, zone)
--     and each open slot;
--   at the bottom, where that came from and the button that searches the group finder again.

local Panel = {}
ns.Panel = Panel

local WHITE = "Interface\\Buttons\\WHITE8X8"
local W, PAD, BANNER_H, ROW_H = 300, 10, 56, 18
local MAX_OPEN = 5 -- open slot rows shown; more (raids) as one line
local DOT = "  |cff555555\194\183|r  " -- a middle dot between details

-- The group finder's own art for each category (its constants, or these where they aren't loaded).
local ART = {
    [2] = "groupfinder-button-dungeons", [114] = "groupfinder-button-raids-warlords",
    [116] = "groupfinder-button-questing", [118] = "groupfinder-button-battlegrounds",
    [120] = "groupfinder-button-custom-pve",
}
local ART_DEFAULT = "groupfinder-button-questing"
local ROLE_ATLAS = {
    TANK = "groupfinder-icon-role-large-tank", HEALER = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps",
}
local STYLE_COLOR = {
    learning = { 0.35, 0.72, 1 }, relaxed = { 0.4, 0.85, 0.45 },
    competitive = { 1, 0.62, 0.2 }, expert = { 1, 0.32, 0.3 },
}

local function HasAtlas(name)
    return name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function SetAtlas(tex, name)
    if HasAtlas(name) then
        tex:SetAtlas(name)
        tex:Show()
        return true
    end
    tex:Hide()
    return false
end

local function Text(parent, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Line(parent, layer)
    local t = parent:CreateTexture(nil, layer or "BORDER")
    t:SetColorTexture(1, 1, 1, 0.07)
    t:SetHeight(1)
    return t
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b, c.colorStr end
    return 1, 1, 1, "ffffffff"
end

------------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------------

-- A flat button: dark, a 1px edge, gold text that lights up under the mouse.
local function FlatButton(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetHeight(22)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(0.13, 0.13, 0.14, 1)
    b:SetBackdropBorderColor(0, 0, 0, 1)
    b.label = Text(b, "GameFontNormalSmall", "CENTER")
    b.label:SetPoint("CENTER")
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self:SetBackdropColor(0.2, 0.19, 0.15, 1) end
    end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(0.13, 0.13, 0.14, 1) end)
    return b
end

function Panel:Build()
    local f = CreateFrame("Frame", "FrogInvitePanel", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetWidth(W)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.06, 0.07, 0.96)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    f:SetClampedToScreen(true)
    f:Hide()

    -- The banner.
    local banner = CreateFrame("Frame", nil, f)
    banner:SetPoint("TOPLEFT", 1, -1)
    banner:SetPoint("TOPRIGHT", -1, -1)
    banner:SetHeight(BANNER_H)
    banner:SetClipsChildren(true)
    banner.art = banner:CreateTexture(nil, "BACKGROUND")
    banner.art:SetAllPoints()
    banner.art:SetAlpha(0.6)
    banner.shade = banner:CreateTexture(nil, "BORDER")
    banner.shade:SetAllPoints()
    banner.shade:SetColorTexture(1, 1, 1, 1)
    if not pcall(banner.shade.SetGradient, banner.shade, "HORIZONTAL",
        CreateColor(0, 0, 0, 0.9), CreateColor(0, 0, 0, 0.25)) then
        banner.shade:SetColorTexture(0, 0, 0, 0.6)
    end
    local accent = banner:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetHeight(1)
    accent:SetColorTexture(1, 0.82, 0, 0.5)
    local under = banner:CreateTexture(nil, "ARTWORK")
    under:SetPoint("BOTTOMLEFT")
    under:SetPoint("BOTTOMRIGHT")
    under:SetHeight(1)
    under:SetColorTexture(0, 0, 0, 1)
    banner.title = Text(banner, "GameFontNormalLarge")
    banner.title:SetTextColor(1, 1, 1)
    banner.title:SetPoint("TOPLEFT", PAD, -10)
    banner.title:SetPoint("RIGHT", -28, 0)
    banner.sub = Text(banner, "GameFontHighlightSmall")
    banner.sub:SetTextColor(0.8, 0.8, 0.8)
    banner.sub:SetPoint("TOPLEFT", banner.title, "BOTTOMLEFT", 0, -5)
    f.banner = banner

    -- The group type badge, at the banner's lower right.
    local badge = CreateFrame("Frame", nil, banner, "BackdropTemplate")
    badge:SetHeight(16)
    badge:SetPoint("BOTTOMRIGHT", -PAD, 8)
    badge:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    badge.text = Text(badge, "GameFontNormalSmall", "CENTER")
    badge.text:SetPoint("CENTER", 0, 0)
    f.badge = badge
    banner.sub:SetPoint("RIGHT", badge, "LEFT", -6, 0)

    -- A small close cross.
    local close = CreateFrame("Button", nil, banner)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -4, -4)
    close.x = Text(close, "GameFontNormal", "CENTER")
    close.x:SetPoint("CENTER")
    close.x:SetText("\195\151") -- ×
    close.x:SetTextColor(0.6, 0.6, 0.6)
    close:SetScript("OnEnter", function(self) self.x:SetTextColor(1, 1, 1) end)
    close:SetScript("OnLeave", function(self) self.x:SetTextColor(0.6, 0.6, 0.6) end)
    close:SetScript("OnClick", function() Panel:Hide() end)

    -- The body.
    f.meta = Text(f)
    f.meta:SetTextColor(0.65, 0.65, 0.65)
    f.also = Text(f)
    f.also:SetTextColor(0.65, 0.65, 0.65)
    f.also:SetWordWrap(true)
    f.quote = f:CreateTexture(nil, "ARTWORK")
    f.quote:SetColorTexture(1, 0.82, 0, 0.6)
    f.quote:SetWidth(2)
    f.comment = Text(f)
    f.comment:SetTextColor(0.9, 0.88, 0.78)
    f.comment:SetWordWrap(true)
    f.rows = {}
    f.more = Text(f)
    f.more:SetTextColor(0.45, 0.45, 0.45)

    -- The footer.
    f.rule = Line(f)
    f.status = Text(f)
    f.status:SetTextColor(0.55, 0.55, 0.55)
    f.status:SetWordWrap(true)
    f.button = FlatButton(f)
    f.button:SetScript("OnClick", function() ns.SearchNext() end)

    -- Goes with the invite popup.
    f:SetScript("OnUpdate", function(self, elapsed)
        self.since = (self.since or 0) + elapsed
        if self.since < 0.2 then return end
        self.since = 0
        local d = self.dialog
        if d and not (d:IsShown() and (d.which == nil or d.which == "PARTY_INVITE")) then Panel:Hide() end
    end)
    self.frame = f
end

-- A member's row: class icon, name, crown, level, role, zone.
local function Row(f, i)
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, f)
    r:SetSize(W - 2 * PAD, ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.03)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", 2, 0)
    r.name = Text(r, "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.crown = r:CreateTexture(nil, "ARTWORK")
    r.crown:SetSize(12, 12)
    r.crown:SetPoint("LEFT", r.name, "RIGHT", 3, 1)
    r.zone = Text(r, "GameFontHighlightSmall", "RIGHT")
    r.zone:SetTextColor(0.5, 0.5, 0.5)
    r.zone:SetPoint("RIGHT", -4, 0)
    r.zone:SetWidth(84)
    r.role = r:CreateTexture(nil, "ARTWORK")
    r.role:SetSize(14, 14)
    r.role:SetPoint("RIGHT", r.zone, "LEFT", -6, 0)
    r.level = Text(r, "GameFontHighlightSmall", "RIGHT")
    r.level:SetWidth(22)
    r.level:SetPoint("RIGHT", r.role, "LEFT", -6, 0)
    f.rows[i] = r
    return r
end

local function FillMember(r, m, solo)
    r.bg:Show()
    if not (m.class and SetAtlas(r.icon, "groupfinder-icon-class-" .. m.class:lower())) then r.icon:Hide() end
    r.icon:SetDesaturated(false)
    r.icon:SetAlpha(1)
    local cr, cg, cb = ClassColor(m.class)
    r.name:SetText(m.name or "?")
    r.name:SetTextColor(cr, cg, cb)
    r.name:SetWidth(math.min(r.name:GetUnboundedStringWidth(), 120))
    if m.leader then SetAtlas(r.crown, "groupfinder-icon-leader") else r.crown:Hide() end
    r.level:SetText(m.level and tostring(m.level) or "")
    local role = m.role
    if solo and m.roles then
        -- On their own: the roles they'd take; one icon, the first of them.
        role = (m.roles.tank and "TANK") or (m.roles.healer and "HEALER") or (m.roles.dps and "DAMAGER") or role
    end
    if not SetAtlas(r.role, ROLE_ATLAS[role or ""]) then r.role:Hide() end
    -- The listing only has the leader's zone; friends' and guild members' come from those lists.
    r.zone:SetText(m.area or ns.Finder.KnownZone(m.name) or "")
    r:Show()
end

local function FillOpen(r)
    r.bg:Hide()
    if SetAtlas(r.icon, "groupfinder-waitdot") then r.icon:SetAlpha(0.5) end
    r.name:SetText("Open")
    r.name:SetTextColor(0.4, 0.4, 0.4)
    r.name:SetWidth(120)
    r.crown:Hide()
    r.level:SetText("")
    r.role:Hide()
    r.zone:SetText("")
    r:Show()
end

local function Ago(seconds)
    if not seconds then return nil end
    if seconds < 60 then return "listed just now" end
    if seconds < 3600 then return ("listed %dm ago"):format(seconds / 60) end
    return ("listed %dh %dm ago"):format(seconds / 3600, (seconds % 3600) / 60)
end

------------------------------------------------------------------------------
-- Showing
------------------------------------------------------------------------------

-- The inviter as the listing has them (properly written, with their class), else as given.
local function Inviter(s)
    local key = ns.Finder.Key(s.inviter)
    if s.entry and key then
        for _, m in ipairs(s.entry.members) do
            if ns.Finder.Key(m.name) == key then return m.name, m.class end
        end
    end
    return s.inviter or "?", nil
end

-- Frames an addon may look at: not Blizzard's protected ones (the shop and such), which can't
-- even be asked whether they're shown.
local function Open(frame)
    return not (frame.IsForbidden and frame:IsForbidden())
end

-- Whether a frame shows `name` in its text (its own font strings, or its children's).
local function Says(frame, name, depth)
    for _, r in ipairs({ frame:GetRegions() }) do
        if Open(r) and r.GetObjectType and r:GetObjectType() == "FontString" and r:IsShown() then
            local t = r:GetText()
            -- The name and the word "invite" together, as an invite says ("X invites you to a group").
            if type(t) == "string" and not FrogLib.issecret(t) then
                t = t:lower()
                if t:find(name, 1, true) and t:find("invite", 1, true) then return true end
            end
        end
    end
    if depth > 0 then
        for _, c in ipairs({ frame:GetChildren() }) do
            if Open(c) and c:IsShown() and not c:IsObjectType("EditBox") and Says(c, name, depth - 1) then return true end
        end
    end
    return false
end

-- The invite on screen: the plain popup, the one with role buttons (LFGInvitePopup), or failing
-- those any dialog on screen that names the inviter.
local function FindPopup(inviter)
    if StaticPopup_Visible then
        local _, d = StaticPopup_Visible("PARTY_INVITE")
        if d then return d end
    end
    local roles = _G.LFGInvitePopup
    if roles and Open(roles) and roles:IsShown() then return roles end
    local key = ns.Finder.Key(inviter)
    if not key then return nil end
    for _, c in ipairs({ UIParent:GetChildren() }) do
        if Open(c) and c ~= Panel.frame and not c:IsObjectType("EditBox") then
            local ok, found = pcall(function()
                local strata = c:IsShown() and c:GetFrameStrata()
                return (strata == "DIALOG" or strata == "FULLSCREEN_DIALOG") and Says(c, key, 2)
            end)
            if ok and found then return c end
        end
    end
end

-- The banner's art: the dungeon's own picture where there is one, else the category's.
local function SetBannerArt(tex, e, F)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetDesaturated(not e)
    if e then
        for _, try in ipairs(F.Art(e) or {}) do
            if tex:SetTexture(try[1]) then
                local c = try[2]
                tex:SetTexCoord(c[1], c[2], c[3], c[4])
                tex:SetAlpha(0.85)
                tex:Show()
                return
            end
        end
    end
    local cat = e and F.CategoryOf(e)
    cat = cat and ((LFGLISTING_CATEGORY_TEXTURES and LFGLISTING_CATEGORY_TEXTURES[cat]) or ART[cat])
    SetAtlas(tex, cat or ART_DEFAULT)
    tex:SetAlpha(0.6)
end

-- s: { inviter, entry, live, status, button (its label, or nil to hide it), busy }
function Panel:Show(s)
    if not self.frame then self:Build() end
    local f, F = self.frame, ns.Finder
    local e = s.entry
    local name, class = Inviter(s)
    local _, _, _, hex = ClassColor(class)

    -- The banner: the category's art, what it's listed for, who invited you, the group type.
    SetBannerArt(f.banner.art, e, F)
    local names = e and F.ActivityNames(e) or {}
    if e then
        f.banner.title:SetText(names[1] or "Group")
        f.banner.sub:SetText(("Invited by |c%s%s|r"):format(hex, name))
    else
        f.banner.title:SetText(("|c%s%s|r"):format(hex, name))
        f.banner.sub:SetText("invited you to a group")
    end
    local style, key = nil, nil
    if e then style, key = F.Playstyle(e) end
    if style then
        local c = STYLE_COLOR[key]
        f.badge.text:SetText(style)
        f.badge.text:SetTextColor(c[1], c[2], c[3])
        f.badge:SetBackdropColor(c[1], c[2], c[3], 0.18)
        f.badge:SetBackdropBorderColor(c[1], c[2], c[3], 0.6)
        f.badge:SetWidth(f.badge.text:GetUnboundedStringWidth() + 14)
        f.badge:Show()
    else
        f.badge:Hide()
    end

    local y = -(BANNER_H + 1 + 8)
    local function put(region, h, gap, x)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", (x or 0) + PAD, y)
        region:Show()
        y = y - h - (gap or 6)
    end
    local function text(fs, gap, x)
        fs:SetWidth(W - 2 * PAD - (x or 0))
        put(fs, fs:GetStringHeight(), gap, x)
    end

    for _, r in ipairs(f.rows) do r:Hide() end
    f.more:Hide()
    if e then
        -- Details.
        local max = F.MaxPlayers(e)
        local bits = { max and ("|cffffffff%d|r/%d players"):format(e.numMembers, max)
            or ("|cffffffff%d|r %s"):format(e.numMembers, e.numMembers == 1 and "player" or "players") }
        local age = e.age and Ago(e.age + (GetTime() - e.seenAt))
        if age then bits[#bits + 1] = age end
        if e.autoAccept then bits[#bits + 1] = "auto accept" end
        if e.newPlayerFriendly then bits[#bits + 1] = "|cff7fd07fnew players welcome|r" end
        if e.delisted then bits[#bits + 1] = "|cffff6060delisted|r" end
        f.meta:SetText(table.concat(bits, DOT))
        text(f.meta)
        if #names > 1 then
            f.also:SetText("Also: " .. table.concat(names, ", ", 2))
            text(f.also)
        else
            f.also:Hide()
        end
        -- The comment, with a gold bar beside it.
        if e.comment and e.comment ~= "" then
            pcall(f.comment.SetText, f.comment, e.comment)
            local top = y
            text(f.comment, 8, 8)
            f.quote:ClearAllPoints()
            f.quote:SetPoint("TOPLEFT", PAD, top + 1)
            f.quote:SetPoint("BOTTOMLEFT", f.comment, "BOTTOMLEFT", -8, -1)
            f.quote:Show()
        else
            f.comment:Hide()
            f.quote:Hide()
        end
        -- The members, the leader first, then the open slots.
        local members = {}
        for _, m in ipairs(e.members) do
            if m.leader then table.insert(members, 1, m) else members[#members + 1] = m end
        end
        local solo = e.numMembers == 1
        local i = 0
        for _, m in ipairs(members) do
            i = i + 1
            local r = Row(f, i)
            FillMember(r, m, solo)
            put(r, ROW_H, 2)
        end
        local open = max and math.max(0, max - e.numMembers) or 0
        for _ = 1, math.min(open, MAX_OPEN) do
            i = i + 1
            local r = Row(f, i)
            FillOpen(r)
            put(r, ROW_H, 2)
        end
        if open > MAX_OPEN then
            f.more:SetText(("+%d more open"):format(open - MAX_OPEN))
            text(f.more, 2, 22)
        end
        y = y - 6
    else
        f.meta:Hide()
        f.also:Hide()
        f.comment:Hide()
        f.quote:Hide()
    end

    -- The footer.
    f.rule:ClearAllPoints()
    f.rule:SetPoint("TOPLEFT", 1, y)
    f.rule:SetPoint("TOPRIGHT", -1, y)
    y = y - 8
    f.status:SetText(s.status or "")
    text(f.status, 8)
    if s.button then
        f.button.label:SetText(s.button)
        f.button:SetEnabled(not s.busy)
        if s.busy then f.button.label:SetTextColor(0.5, 0.5, 0.5) else f.button.label:SetTextColor(1, 0.82, 0) end
        f.button:SetWidth(W - 2 * PAD)
        put(f.button, 22, 8)
    else
        f.button:Hide()
    end
    f:SetHeight(-y + 2)

    -- Under the invite popup when there is one, else near the top of the screen.
    f:SetScale(ns.db and ns.db.scale or 1)
    local dialog
    if not s.test then dialog = (f.dialog and f.dialog:IsShown()) and f.dialog or FindPopup(name) end
    f.dialog = dialog
    f:ClearAllPoints()
    if dialog then
        f:SetPoint("TOP", dialog, "BOTTOM", 0, -6)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -220)
    end
    f:Show()
end

function Panel:Hide()
    if self.frame then
        self.frame:Hide()
        self.frame.dialog = nil
    end
    ns.Closed()
end

function Panel:IsShown()
    return self.frame and self.frame:IsShown()
end

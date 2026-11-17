local _, ns = ...

-- The panel under the invite popup, minimal dark like FrogUI: a banner (the dungeon's or category's
-- art, what the group's listed for, who invited you, a group type badge), the listing's details,
-- comment and a row per member and open slot; or, not in the finder, what /who says about them;
-- and at the bottom where that came from, with the buttons that search again and ask /who.

local Panel = {}
ns.Panel = Panel
local Finder = ns.Finder

local WHITE = "Interface\\Buttons\\WHITE8X8"
local WIDTH, PAD, BANNER_HEIGHT, ROW_HEIGHT = 300, 10, 56, 18
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

local function SetAtlas(texture, name)
    if HasAtlas(name) then
        texture:SetAtlas(name)
        texture:Show()
        return true
    end
    texture:Hide()
    return false
end

local function Text(parent, template, justify)
    local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    return text
end

local function Line(parent, layer)
    local line = parent:CreateTexture(nil, layer or "BORDER")
    line:SetColorTexture(1, 1, 1, 0.07)
    line:SetHeight(1)
    return line
end

local function ClassColor(class)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r, color.g, color.b, color.colorStr end
    return 1, 1, 1, "ffffffff"
end

------------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------------

-- A flat button: dark, a 1px edge, gold text that lights up under the mouse.
local function FlatButton(parent)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetHeight(22)
    button:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    button:SetBackdropColor(0.13, 0.13, 0.14, 1)
    button:SetBackdropBorderColor(0, 0, 0, 1)
    button.label = Text(button, "GameFontNormalSmall", "CENTER")
    button.label:SetPoint("CENTER")
    button:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self:SetBackdropColor(0.2, 0.19, 0.15, 1) end
    end)
    button:SetScript("OnLeave", function(self) self:SetBackdropColor(0.13, 0.13, 0.14, 1) end)
    return button
end

function Panel:Build()
    local frame = CreateFrame("Frame", "FrogInvitePanel", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:SetWidth(WIDTH)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(0.06, 0.06, 0.07, 0.96)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- The banner.
    local banner = CreateFrame("Frame", nil, frame)
    banner:SetPoint("TOPLEFT", 1, -1)
    banner:SetPoint("TOPRIGHT", -1, -1)
    banner:SetHeight(BANNER_HEIGHT)
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
    frame.banner = banner

    -- The group type badge, at the banner's lower right.
    local badge = CreateFrame("Frame", nil, banner, "BackdropTemplate")
    badge:SetHeight(16)
    badge:SetPoint("BOTTOMRIGHT", -PAD, 8)
    badge:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    badge.text = Text(badge, "GameFontNormalSmall", "CENTER")
    badge.text:SetPoint("CENTER", 0, 0)
    frame.badge = badge
    banner.sub:SetPoint("RIGHT", badge, "LEFT", -6, 0)

    -- A small close cross.
    local close = CreateFrame("Button", nil, banner)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -4, -4)
    close.cross = Text(close, "GameFontNormal", "CENTER")
    close.cross:SetPoint("CENTER")
    close.cross:SetText("\195\151") -- the multiplication sign
    close.cross:SetTextColor(0.6, 0.6, 0.6)
    close:SetScript("OnEnter", function(self) self.cross:SetTextColor(1, 1, 1) end)
    close:SetScript("OnLeave", function(self) self.cross:SetTextColor(0.6, 0.6, 0.6) end)
    close:SetScript("OnClick", function() Panel:Hide() end)

    -- The body.
    frame.meta = Text(frame)
    frame.meta:SetTextColor(0.65, 0.65, 0.65)
    frame.also = Text(frame)
    frame.also:SetTextColor(0.65, 0.65, 0.65)
    frame.also:SetWordWrap(true)
    frame.quote = frame:CreateTexture(nil, "ARTWORK")
    frame.quote:SetColorTexture(1, 0.82, 0, 0.6)
    frame.quote:SetWidth(2)
    frame.comment = Text(frame)
    frame.comment:SetTextColor(0.9, 0.88, 0.78)
    frame.comment:SetWordWrap(true)
    frame.rows = {}
    frame.more = Text(frame)
    frame.more:SetTextColor(0.45, 0.45, 0.45)

    -- The footer.
    frame.rule = Line(frame)
    frame.status = Text(frame)
    frame.status:SetTextColor(0.55, 0.55, 0.55)
    frame.status:SetWordWrap(true)
    frame.button = FlatButton(frame)
    frame.button:SetScript("OnClick", function() ns.SearchNext() end)
    frame.whoButton = FlatButton(frame)
    frame.whoButton:SetScript("OnClick", function() ns.AskWho() end)

    -- Goes with the invite popup.
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.since = (self.since or 0) + elapsed
        if self.since < 0.2 then return end
        self.since = 0
        local dialog = self.dialog
        if dialog and not (dialog:IsShown() and (dialog.which == nil or dialog.which == "PARTY_INVITE")) then
            Panel:Hide()
        end
    end)
    self.frame = frame
end

-- A member's row: class icon, name, crown, level, role, zone.
local function Row(frame, index)
    local row = frame.rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, frame)
    row:SetSize(WIDTH - 2 * PAD, ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.03)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 2, 0)
    row.name = Text(row, "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.crown = row:CreateTexture(nil, "ARTWORK")
    row.crown:SetSize(12, 12)
    row.crown:SetPoint("LEFT", row.name, "RIGHT", 3, 1)
    row.zone = Text(row, "GameFontHighlightSmall", "RIGHT")
    row.zone:SetTextColor(0.5, 0.5, 0.5)
    row.zone:SetPoint("RIGHT", -4, 0)
    row.zone:SetWidth(84)
    row.role = row:CreateTexture(nil, "ARTWORK")
    row.role:SetSize(14, 14)
    row.role:SetPoint("RIGHT", row.zone, "LEFT", -6, 0)
    row.level = Text(row, "GameFontHighlightSmall", "RIGHT")
    row.level:SetWidth(22)
    row.level:SetPoint("RIGHT", row.role, "LEFT", -6, 0)
    frame.rows[index] = row
    return row
end

local function FillMember(row, member, solo)
    row.bg:Show()
    if not (member.class and SetAtlas(row.icon, "groupfinder-icon-class-" .. member.class:lower())) then
        row.icon:Hide()
    end
    row.icon:SetDesaturated(false)
    row.icon:SetAlpha(1)
    local r, g, b = ClassColor(member.class)
    row.name:SetText(member.name or "?")
    row.name:SetTextColor(r, g, b)
    row.name:SetWidth(math.min(row.name:GetUnboundedStringWidth(), 120))
    if member.leader then SetAtlas(row.crown, "groupfinder-icon-leader") else row.crown:Hide() end
    row.level:SetText(member.level and tostring(member.level) or "")
    local role = member.role
    if solo and member.roles then
        -- On their own: the roles they'd take; one icon, the first of them.
        local roles = member.roles
        role = (roles.tank and "TANK") or (roles.healer and "HEALER") or (roles.dps and "DAMAGER") or role
    end
    if not SetAtlas(row.role, ROLE_ATLAS[role or ""]) then row.role:Hide() end
    -- The listing only has the leader's zone; friends' and guild members' come from those lists.
    row.zone:SetText(member.area or Finder.KnownZone(member.name) or "")
    row:Show()
end

local function FillOpen(row)
    row.bg:Hide()
    if SetAtlas(row.icon, "groupfinder-waitdot") then row.icon:SetAlpha(0.5) end
    row.name:SetText("Open")
    row.name:SetTextColor(0.4, 0.4, 0.4)
    row.name:SetWidth(120)
    row.crown:Hide()
    row.level:SetText("")
    row.role:Hide()
    row.zone:SetText("")
    row:Show()
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
local function Inviter(view)
    local key = Finder.Key(view.inviter)
    if view.entry and key then
        for _, member in ipairs(view.entry.members) do
            if Finder.Key(member.name) == key then return member.name, member.class end
        end
    end
    return view.inviter or "?", view.who and view.who.class
end

-- What /who (or the invite) says about them: "Level 60 Human Warrior", as much as is known.
local function WhoLine(who)
    if not who then return nil end
    local words = {}
    if who.level and who.level > 0 then words[#words + 1] = "Level " .. who.level end
    if who.race and who.race ~= "" then words[#words + 1] = who.race end
    if who.className and who.className ~= "" then words[#words + 1] = who.className end
    if #words == 0 then return nil end
    return table.concat(words, " ")
end

-- Frames an addon may look at: not Blizzard's protected ones (the shop and such), which can't
-- even be asked whether they're shown.
local function Open(frame)
    return not (frame.IsForbidden and frame:IsForbidden())
end

-- Whether a frame shows `name` in its text (its own font strings, or its children's).
local function Says(frame, name, depth)
    for _, region in ipairs({ frame:GetRegions() }) do
        if Open(region) and region.GetObjectType and region:GetObjectType() == "FontString" and region:IsShown() then
            local text = region:GetText()
            -- The name and the word "invite" together, as an invite says ("X invites you to a group").
            if type(text) == "string" and not FrogLib.issecret(text) then
                text = text:lower()
                if text:find(name, 1, true) and text:find("invite", 1, true) then return true end
            end
        end
    end
    if depth > 0 then
        for _, child in ipairs({ frame:GetChildren() }) do
            if Open(child) and child:IsShown() and not child:IsObjectType("EditBox")
                and Says(child, name, depth - 1) then return true end
        end
    end
    return false
end

-- The invite on screen: the plain popup, the one with role buttons (LFGInvitePopup), or failing
-- those any dialog on screen that names the inviter.
local function FindPopup(inviter)
    if StaticPopup_Visible then
        local _, dialog = StaticPopup_Visible("PARTY_INVITE")
        if dialog then return dialog end
    end
    local roles = _G.LFGInvitePopup
    if roles and Open(roles) and roles:IsShown() then return roles end
    local key = Finder.Key(inviter)
    if not key then return nil end
    for _, child in ipairs({ UIParent:GetChildren() }) do
        if Open(child) and child ~= Panel.frame and not child:IsObjectType("EditBox") then
            local ok, found = pcall(function()
                local strata = child:IsShown() and child:GetFrameStrata()
                return (strata == "DIALOG" or strata == "FULLSCREEN_DIALOG") and Says(child, key, 2)
            end)
            if ok and found then return child end
        end
    end
end

-- The banner's art: the dungeon's own picture where there is one, else the category's.
local function SetBannerArt(texture, entry)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetDesaturated(not entry)
    if entry then
        for _, try in ipairs(Finder.Art(entry) or {}) do
            if texture:SetTexture(try[1]) then
                local cut = try[2]
                texture:SetTexCoord(cut[1], cut[2], cut[3], cut[4])
                texture:SetAlpha(0.85)
                texture:Show()
                return
            end
        end
    end
    local category = entry and Finder.CategoryOf(entry)
    local atlas = category and ((LFGLISTING_CATEGORY_TEXTURES and LFGLISTING_CATEGORY_TEXTURES[category]) or ART[category])
    SetAtlas(texture, atlas or ART_DEFAULT)
    texture:SetAlpha(0.6)
end

-- view: { inviter, entry, live, status, button (its label, or nil to hide it), busy,
--   who ({ level, race, className, class, guild, area }), whoNote, whoButton, whoBusy }
function Panel:Show(view)
    if not self.frame then self:Build() end
    local frame = self.frame
    local entry = view.entry
    local name, class = Inviter(view)
    local _, _, _, hex = ClassColor(class)

    -- The banner: the category's art, what it's listed for, who invited you, the group type.
    SetBannerArt(frame.banner.art, entry)
    local names = entry and Finder.ActivityNames(entry) or {}
    if entry then
        frame.banner.title:SetText(names[1] or "Group")
        frame.banner.sub:SetText(("Invited by |c%s%s|r"):format(hex, name))
    else
        frame.banner.title:SetText(("|c%s%s|r"):format(hex, name))
        local line = WhoLine(view.who)
        frame.banner.sub:SetText(line and (line .. " |cff999999invited you|r") or "invited you to a group")
    end
    local style, key = nil, nil
    if entry then style, key = Finder.Playstyle(entry) end
    if style then
        local color = STYLE_COLOR[key]
        frame.badge.text:SetText(style)
        frame.badge.text:SetTextColor(color[1], color[2], color[3])
        frame.badge:SetBackdropColor(color[1], color[2], color[3], 0.18)
        frame.badge:SetBackdropBorderColor(color[1], color[2], color[3], 0.6)
        frame.badge:SetWidth(frame.badge.text:GetUnboundedStringWidth() + 14)
        frame.badge:Show()
    else
        frame.badge:Hide()
    end

    local y = -(BANNER_HEIGHT + 1 + 8)
    local function Put(region, height, gap, x)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", (x or 0) + PAD, y)
        region:Show()
        y = y - height - (gap or 6)
    end
    local function PutText(text, gap, x)
        text:SetWidth(WIDTH - 2 * PAD - (x or 0))
        Put(text, text:GetStringHeight(), gap, x)
    end

    for _, row in ipairs(frame.rows) do row:Hide() end
    frame.more:Hide()
    if entry then
        -- Details.
        local maxPlayers = Finder.MaxPlayers(entry)
        local details = { maxPlayers and ("|cffffffff%d|r/%d players"):format(entry.numMembers, maxPlayers)
            or ("|cffffffff%d|r %s"):format(entry.numMembers, entry.numMembers == 1 and "player" or "players") }
        local age = entry.age and Ago(entry.age + (GetTime() - entry.seenAt))
        if age then details[#details + 1] = age end
        if entry.autoAccept then details[#details + 1] = "auto accept" end
        if entry.newPlayerFriendly then details[#details + 1] = "|cff7fd07fnew players welcome|r" end
        if entry.delisted then details[#details + 1] = "|cffff6060delisted|r" end
        frame.meta:SetText(table.concat(details, DOT))
        frame.meta:SetWordWrap(false)
        PutText(frame.meta)
        if #names > 1 then
            frame.also:SetText("Also: " .. table.concat(names, ", ", 2))
            PutText(frame.also)
        else
            frame.also:Hide()
        end
        -- The comment, with a gold bar beside it.
        if entry.comment and entry.comment ~= "" then
            pcall(frame.comment.SetText, frame.comment, entry.comment)
            local top = y
            PutText(frame.comment, 8, 8)
            frame.quote:ClearAllPoints()
            frame.quote:SetPoint("TOPLEFT", PAD, top + 1)
            frame.quote:SetPoint("BOTTOMLEFT", frame.comment, "BOTTOMLEFT", -8, -1)
            frame.quote:Show()
        else
            frame.comment:Hide()
            frame.quote:Hide()
        end
        -- The members, the leader first, then the open slots.
        local members = {}
        for _, member in ipairs(entry.members) do
            if member.leader then table.insert(members, 1, member) else members[#members + 1] = member end
        end
        local solo = entry.numMembers == 1
        local rows = 0
        for _, member in ipairs(members) do
            rows = rows + 1
            local row = Row(frame, rows)
            FillMember(row, member, solo)
            Put(row, ROW_HEIGHT, 2)
        end
        local open = maxPlayers and math.max(0, maxPlayers - entry.numMembers) or 0
        for _ = 1, math.min(open, MAX_OPEN) do
            rows = rows + 1
            local row = Row(frame, rows)
            FillOpen(row)
            Put(row, ROW_HEIGHT, 2)
        end
        if open > MAX_OPEN then
            frame.more:SetText(("+%d more open"):format(open - MAX_OPEN))
            PutText(frame.more, 2, 22)
        end
        y = y - 6
    else
        -- Not in the group finder: their guild and zone, from /who.
        local who, details = view.who, {}
        if who and who.guild and who.guild ~= "" then details[#details + 1] = "|cffffffff<" .. who.guild .. ">|r" end
        if who and who.area and who.area ~= "" then details[#details + 1] = who.area end
        if view.whoNote then details[#details + 1] = view.whoNote end
        if #details > 0 then
            frame.meta:SetText(table.concat(details, DOT))
            frame.meta:SetWordWrap(true)
            PutText(frame.meta)
        else
            frame.meta:Hide()
        end
        frame.also:Hide()
        frame.comment:Hide()
        frame.quote:Hide()
    end

    -- The footer.
    frame.rule:ClearAllPoints()
    frame.rule:SetPoint("TOPLEFT", 1, y)
    frame.rule:SetPoint("TOPRIGHT", -1, y)
    y = y - 8
    frame.status:SetText(view.status or "")
    PutText(frame.status, 8)
    local function PutButton(button, label, busy)
        if not label then return button:Hide() end
        button.label:SetText(label)
        button:SetEnabled(not busy)
        if busy then button.label:SetTextColor(0.5, 0.5, 0.5) else button.label:SetTextColor(1, 0.82, 0) end
        button:SetWidth(WIDTH - 2 * PAD)
        Put(button, 22, 8)
    end
    PutButton(frame.button, view.button, view.busy)
    PutButton(frame.whoButton, view.whoButton, view.whoBusy)
    frame:SetHeight(-y + 2)

    -- Under the invite popup when there is one, else near the top of the screen.
    frame:SetScale(ns.db and ns.db.scale or 1)
    local dialog
    if not view.test then dialog = (frame.dialog and frame.dialog:IsShown()) and frame.dialog or FindPopup(name) end
    frame.dialog = dialog
    frame:ClearAllPoints()
    if dialog then
        frame:SetPoint("TOP", dialog, "BOTTOM", 0, -6)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -220)
    end
    frame:Show()
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

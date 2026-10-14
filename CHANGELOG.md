# FrogInvite

## 0.1.0

- First version. When someone invites you to a group, a panel under the invite shows their group finder listing: what it's listed for (its activities), how long ago it was listed, its comment, and who's in it already, each with their level, class colour, role and zone, the leader marked.
- The inviter is matched against every member of every group in your group finder results, not just the leader, so an invite from anyone in a listed group finds it. Groups seen in searches over the last half hour are remembered too (without their comment once they've left your results).
- Not found? The panel's button searches the group finder, one category a click (the game only lets a search start from a click), starting with the category Blizzard's group finder has picked, and the panel looks again as each search's results come in. For a group seen before, the button refreshes its own category first.
- The panel goes with the invite popup: accepted, declined or timed out.
- The group type the leader picked (Learning, Relaxed, Competitive or Expert) as a coloured badge, and whether new players are welcome.
- A minimal dark look: a banner with the category's own group finder art, what the group's listed for and who invited you in their class colour; each member's row with their class and role icons, the leader's crown, level and zone; the open slots; the comment beside a gold bar; a flat button.
- The banner shows the dungeon's own painting (the Encounter Journal's), falling back to the group finder's art for the category.
- Zones: the listing only gives the leader's; members who are your friends or in your guild get theirs from those lists.
- The panel sits under whichever invite is on screen: the plain popup or the one with role buttons. A little bigger than the game's own text to start with; `/finvite scale 0.5` to `2` to change it.
- `/finvite <name>` shows the panel as if that player had invited you, to try it against your current results.

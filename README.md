# Second Screen Companion

Follow your party live on your phone while you play on the PC. The mod runs a
small web server inside the game; your phone just opens a page in its browser.
No app to install. Works with Gen 1 (Red / Blue / Yellow), Gen 2 (Gold /
Silver / Crystal) and Gen 3 (FireRed / LeafGreen / Emerald); see
[Gen 2](#gen-2-gold--silver) and [Gen 3](#gen-3-firered--leafgreen) for
what differs there.

## Setup

1. Enable the mod and start the game.
2. On Windows, a firewall prompt appears the first time. Allow access on
   **Private networks**.
3. Open **OPTION > PHONE** in the game and scan the QR code with your phone's
   camera. Or type the address shown in the bottom-left corner for a few
   seconds after startup (`http://<pc-ip>:8080`).
4. The phone must be on the **same Wi-Fi** as the PC.

### HANDS-OFF MODE: a dashboard for a TV

Turn on **HANDS-OFF MODE** in the mod options for a screen nobody touches
(a TV, a second monitor). The page becomes one dashboard, no tabs and no
buttons:

- a strip on top: where you are, the time of day (Gen 2), POKéDEX SEEN /
  OWN, money, the badges (the game's own pictures, faded until earned) and
  the ELITE FOUR
- **PARTY** on the left: each POKéMON with its level, HP, status and held
  item; in a battle, the one fighting is drawn larger, gently pulsing.
  Under it, small cards while they matter (see below), and the TOWN MAP /
  POKéGEAR map always at the bottom left
- the **stage** in the middle: the map you're on, as large as it gets. When
  a battle or a contest starts, it takes the whole stage (larger, for across
  the room). In the SAFARI ZONE its balls and steps run along the stage's
  bottom the whole time, battle or not
- **DEXNAV** on the right; a long list (the SAFARI ZONE's) shrinks until
  every POKéMON fits. In a trainer battle the trainer takes its place: their
  picture and name, the team's balls, and each POKéMON of the team (a ball
  and ??? until it's sent out, unless SPOILERS) with the moves it's been seen
  using; the stage then shows only the fight itself
- FireRed / LeafGreen with the FRLG or EMERALD skin: in a place with a location
  preview (the full-screen picture shown on entering MT. MOON, VIRIDIAN
  FOREST, ROCK TUNNEL, the SEVII ISLANDS' caves ...), that picture is the
  dashboard's backdrop while you're there, and the boxes turn dark and
  see-through over it; both fade in and out. In a battle (FireRed,
  LeafGreen and Emerald, the same two skins) the battle's own scenery is the
  backdrop instead: the sky and ground the game draws behind the fight
- the cards under the party, most important first: a roaming legendary on
  this route, the DAY-CARE (an egg first), berries ready or dry (Emerald),
  trainers who want a rematch (Emerald)
- **notifications** top right: items received, POKéMON caught / joining /
  levelling up / evolving / hatching, new POKéDEX entries, a trainer beaten
  with the prize money, a blackout, a new badge, and arriving somewhere
  for the first time this session. Things you change from the phone itself
  make no notification.

The option counts for every device; one device can go its own way with
`?handsoff=1` or `?handsoff=0` in its address (remembered there;
`?handsoff=auto` follows the option again), so a phone can stay normal
while the TV shows the dashboard. Nothing scrolls: DEXNAV shrinks to fit,
and what still can't fit (many cards under the party) fades out at the
bottom.

The dashboard always fills the whole screen at the same layout: it is drawn
at a fixed size and scaled to fit, so a TV browser that pretends to be a
small screen needs no zooming out. For bigger or smaller text, add
`?size=large` (or `?size=small`) to that device's address (remembered;
`?size=auto` goes back to normal).

For a TV left on for hours (OLED panels can burn in where the picture never
changes), the dashboard looks after the screen: it drifts by a few pixels
every three minutes, in a slow loop, and after five minutes with nothing
happening in the game (no step, no battle, no change to the party, no
notification) it fades down, waking up the moment something happens.
`?protect=off` turns both off on that device (`?protect=on` brings them
back). The TV's own pixel-shift and panel-refresh settings help too.

## The page

Five tabs: **LIVE** (the lightning icon, crossed out while the game can't be reached), **POKéMON**, **ITEMS**, **PC** and **POKéDEX**. Swipe left
and right to switch, or tap a tab (arrow keys work on a desktop browser). The
last tab is remembered; `?tab=items` in the address opens a specific one.

**LIVE** follows the game:

- **Location**: the town-map name, so buildings show their town
  (inside the Celadon Mart it says CELADON CITY). Open it for a map, with
  a HERE / REGION switch (remembered):
  - HERE: the current map from the game's own minimap grid (ground,
    water, walls), exits colored by where they lead (POKéMON CENTER red,
    MART blue, GYM gold, other doors dark), item balls you could see in
    the game (hidden ones only with SPOILERS), and the neighbouring
    routes named at the edges.
  - REGION: the TOWN MAP (Gen 1) or POKéGEAR map (Gen 2) with the current
    place blinking; in FireRed / LeafGreen the TOWN MAP of the region
    you're in (Kanto or the Sevii Islands) with the game's player icon.
  The map is only sent when you enter another map (a few KB).
- **DexNav**: every wild POKéMON of the area with level range and chance,
  split into GRASS (or CAVE / INDOORS), SURF and one section per fishing rod
  you own. Chances use the game's own encounter slots, including changes by
  other mods. Caught species get a small ball mark.
- **Battle**: the trainer's picture and name, their party balls exactly like
  the battle screen (healthy / status / fainted / empty), team size, the
  active foe with HP, and the foes sent out so far. Tap a foe in the team list
  to fold out its moves. Wild battles show the foe with its moves right away.
  At the bottom: your party as a row of icons with the one fighting marked,
  and its card with HP. Raised or lowered stats show under both HP bars as
  the game counts them, e.g. ATK×0.66 after a GROWL (green up, red down).
  From Gen 2 on, the weather (RAIN DANCE, SUNNY DAY, SANDSTORM, HAIL) shows
  on top with the turns it has left.
  Effects that last several turns show as badges too: on each POKéMON
  (LEECH SEED, CONFUSED, WRAP, a DISABLED move, TOXIC with its next hit,
  PERISH 2, ENCORE, TAUNT, SUBSTITUTE ...) and, outlined, on each side
  (REFLECT 4, LIGHT SCREEN, SAFEGUARD, SPIKES, FUTURE SIGHT, WISH), and on
  the whole field in Gen 3 (MUD SPORT: ELECTRIC ×0.5, WATER SPORT: FIRE ×0.5). A count
  the game keeps secret (rolled at random, like confusion or WRAP) shows
  only with SHOW HIDDEN VALUES; fixed ones (screens, PERISH SONG) always do.
  The phone never runs ahead of the screen: a foe appears once the game shows
  it being sent out, a move once its "used ...!" text has been shown, and HP
  follows the draining HP bar.
- **Safari Zone** (Gen 1 and 3): while you're inside, a bar under the
  location shows the SAFARI BALLS and steps left. With SHOW HIDDEN
  VALUES, a SAFARI BATTLE shows
  whether the foe is eating or angry and, for BALL, BAIT and ROCK, the
  SAFARI BALL's catch chance it leaves you with and the chance the foe
  runs, from the game's own formulas. Gen 1: the chance it runs this turn
  after that choice (BAIT / ROCK averaged over their random 1-5 turns).
  Gen 3: the foe decides as the turn starts, so RUNS NOW is the same for
  every choice; each row's RUNS NEXT is the next turn's.
- **Day-Care**, while it looks after something: each POKéMON with the level
  it will have when you pick it up, the levels it gained and the fee,
  worked out as the game does (ROUTE 5 in Gen 1; ROUTE 34 in Gen 2, with
  EGG WAITING and the couple's word on how the two get along; ROUTE 5 and
  FOUR ISLAND in Gen 3). Read from the save without changing anything.

- **Item buttons**, side by side: **BIKE** and one button per fishing rod
  in the BAG (OLD ROD, GOOD ROD, SUPER ROD), each shown only when you have
  it. BIKE gets on or off without opening the BAG; a rod casts right away
  when you face the water (not while surfing). They use the game's own item
  actions, so the rules, text and music are the same (no cycling indoors or
  while surfing, no getting off on CYCLING ROAD). A tap while the player is
  mid-step is applied at the next tile, or dropped after 2 seconds of
  walking. Needs pairing in SECURE MODE; unavailable while a menu, text or
  battle is open.
- **FIELD MOVES**: a button for every field move your party can use with the
  badges you have (CUT, FLY, SURF, STRENGTH, FLASH, DIG, TELEPORT,
  SOFTBOILED), showing who knows it. Buttons are only greyed out while the
  game has a menu, text or battle open; whether a move works right where
  you stand is checked when you tap it, and if it doesn't, the phone says
  why ("Face a tree", "Only outdoors"...). The item buttons work the same
  way ("Face the water"). SURF turns into LEAVE WATER while surfing. DIG and TELEPORT ask for a
  confirmation, FLY lets you pick one of the towns you've visited, and
  SOFTBOILED asks whom to heal. Moves run through the game's own field-move
  code, with the same rules, text and animations as from the party menu.

Hidden information follows the **SPOILERS** mod option (off by default):
off, a trainer's unrevealed POKéMON and DexNav species you've never seen show
as ???, and a foe lists only the moves you've seen it use; on, everything is
shown.

**ITEMS** shows your money and the bag in the same order as the in-game BAG,
with quantities (none for key items and HMs) and the move each TM/HM teaches.
(The tab is named like the start menu: ITEM on Gen 1, PACK on Gen 2.)

**GIVE TO HOLD** (Gen 2): tap an item in the PACK and the bar at the bottom
offers GIVE TO HOLD, which opens a list of the party; tap a POKéMON and it
holds the item. If it already held one, that one goes back to the PACK.
The game's own rules apply: an EGG can't hold anything, key items and HMs
can't be held (TMs can, like on the cartridge), and a POKéMON holding MAIL
has to have it removed first. Giving MAIL itself is left to the game, since
it asks you to write the letter. A swap into a PACK with no room for the old
item is refused and changes nothing.

**USE** (every game): medicine, vitamins and PP items can be used on a party
POKéMON from the phone. Tap the item, then USE, then the POKéMON (the list
shows each one's HP and status); an ETHER, MAX ETHER or PP UP then asks
which move, with its PP. It runs the game's own item code, so its rules,
its message ("PIKACHU recovered by 20!" or "It won't have any effect.")
and the item being used up are exactly as in the game's BAG. The list
stays open for the next POTION. Like GIVE, it waits for free roam (no menu,
text or battle).

RARE CANDY, evolution stones and TMs/HMs work the same way from the phone,
and then play on the game screen as if used from the game's BAG: the level-up
with its stats, new moves (the "forget a move?" prompt when four are known),
the evolution, or the TM's teach. The party list marks who can use a TM or
stone (ABLE / LEARNED / NOT ABLE); for RARE CANDY it shows the level. What the
game would refuse (can't learn it, already knows it, no effect) is answered
on the phone instead. On FireRed / LeafGreen / Emerald the game's own party
menu opens for the moment it takes, already on the right POKéMON, and closes
again when it's done. A TM is used up once the move is learned; an HM never.

Items used in the field have a USE that works right away, without a party
list: REPELs, the ESCAPE ROPE, the ITEMFINDER, the TOWN MAP, the COIN CASE
(and on Gold the BLUE CARD, SACRED ASH and SQUIRTBOTTLE; on FireRed the
POWDER JAR), the rods and the BICYCLE. They go through the game's own field
use, the same calls the quick action buttons on LIVE make (those buttons are
shortcuts for them). A short answer shows on the phone ("RED used REPEL!",
"The REPEL used earlier is still in effect.", the ITEMFINDER's yes or no);
the ESCAPE ROPE, a rod, the BICYCLE and the TOWN MAP play on the game screen.

**SORT** (at the top, when editing is allowed) sorts the real bag, so the
in-game BAG / PACK is sorted too:
- **BY KIND** groups BALLS, MEDICINE, BERRIES, BATTLE items, BOOSTS
  (vitamins, stones, RARE CANDY, PP UP), FIELD items (repels, ESCAPE ROPE),
  HOLD ITEMS, MAIL, OTHER, TMs, HMs and KEY ITEMS. Gen 2 reads each item's
  kind from the game's own item data, so items a mod adds sort with their
  kind; Gen 1 has no such data and follows the game's item-effect lists.
- **A-Z** by the item's name.
- **No.** by the game's own item number.

Only the order changes, never what's in the bag. On Gen 2 each pocket is
sorted on its own, and the TM/HM pocket stays by number. **UNDO** puts back
the order from before the last sort (until the bag changes otherwise). New
items still go to the end, as in the game. Save in the game to keep it.

**POKéDEX** shows SEEN and OWN like the in-game POKéDEX, then every entry,
six per row: number, party icon and name, with a small ball on the ones
you've caught. Entries you haven't seen show only their number (with
SPOILERS on, their name and a faded icon). The button next to SEEN / OWN
opens **filter and sort**:

- FILTER: ALL, SEEN, CAUGHT or NOT CAUGHT (seen but not caught yet; with
  SPOILERS on, every species you don't own, unseen ones included), plus
  one TYPE (either of a species' types; only types of species you've seen
  are offered).
- SORT: No., A-Z, TYPE (grouped under type headers, by first type),
  HEIGHT or WEIGHT, low or high first. Sorted by height or weight, the
  value replaces the number in each cell. Like the in-game entry, height
  and weight are only known for caught species (all with SPOILERS);
  unknown values go last.
- The choice is remembered by the browser; a green dot on the button
  means it's not the default view, and RESET goes back to it.

Tap an entry to open its **POKéDEX page** in a sheet from the bottom:
picture, name, kind, types, HT / WT and the description, like the
in-game entry. It follows the original's rules: a caught species shows
everything; a species you've only seen shows the limited page (HT / WT as
?, no description); with SPOILERS on, unseen species open that limited
page too (with HT / WT, still no description). Swipe left / right on the
page, or use ◀ ▶, to step through the entries in the grid's current
filter and sort order (arrow keys on a PC); the page keeps one height so
the buttons never move. Close with X, by tapping outside, Esc, or the phone's back gesture.
If you catch the species while its page is open, the page completes
itself.

The **CRY** button at the bottom right of the DATA view plays the
species' cry through the phone's own speaker, the way the game renders it
(same rules as the page: seen species, or all with SPOILERS). The phone
buzzes along with it (VIBRATION option).

**DATA / EVO / MOVES / AREA** at the bottom of the page switch views (the
choice is remembered while you step through species). EVO shows the whole
family from its first stage down, every branch included, with each step's
condition between the species (Lv.16, a stone, TRADE, HAPPINESS with its
time of day, Gold's Lv.20 · ATK>DEF); tap a species to open its entry. An
evolution method a mod adds describes itself. MOVES lists the level-up
moves (`Lv.16` and the move). On Gold / Silver / Crystal, EVO also lists
the egg groups, MOVES the egg moves, and DATA shows the species' footprint
(the game's own, bottom right). Like the description, both open for species
you've caught; in the family, species you haven't seen stay `?????`
(everything shows with SPOILERS). AREA is the in-game AREA
screen: the TOWN MAP in the game's colors with blinking nests wherever
the species lives in grass, caves or water, or AREA UNKNOWN. Below it, a
list of every place with how it's found (GRASS / CAVE / SURF / OLD ROD /
GOOD ROD / SUPER ROD), the level range and its share of that place's
encounters; floors of one place are merged (MT.MOON). Tap a nest or a row
to highlight the place on both. Encounter data comes from the same code as
the DexNav, so mods that change wild POKéMON show up here too; places a
mod adds without a TOWN MAP square are listed without a nest.

The dex is as long as the
game's own (`dexSize`), so species added by other mods appear too, with the
game's number width. The list is only downloaded again when something in
it changes (a species seen or caught, a save loaded, another palette), no
matter what caused it: battle, evolution, trade, gift or another mod.

**PC** shows all 12 of Bill's PC boxes: switch with ◀ ▶ or the box buttons
(a green dot marks the current box).

## Rearranging from the phone

On **ITEMS** and **PC** you can rearrange things the Gen 1 way: tap one
entry, then tap another to swap them (tap the same entry again to cancel).
On PC a selected POKéMON can be carried to another box: switch boxes, then
tap a POKéMON there to swap, or **MOVE HERE** to put it at the end.

- **SECURE MODE (off by default).** Off, any device that opens the page can
  rearrange. On, a device must pair first: scan the QR code in
  OPTION > PHONE, or type the 4-digit PIN shown there (and in the startup
  hint) into the PIN box on the ITEMS / PC tabs. That works from a PC
  browser too. Pairing lasts until the game restarts and is shared by all
  tabs of that browser. After 5 wrong PINs the game draws a new PIN and
  takes no guesses for 30 seconds.
- **Always on:** other websites open in your browser cannot send edits to
  the game (edits need a header only this page sends, and the server only
  answers requests addressed to an IP, `localhost` or a local machine name).
- **While playing, too.** A second player can rearrange while the first one
  walks, talks or battles. Each edit is applied in one piece between two game
  frames, so a save always holds the old or the new order, never half of
  one. Edits only pause while the in-game BAG, BILL's PC, the item PC or a
  shop is open (their lists would go stale, and e.g. RELEASE works by
  position), during trades (the whole Cable Club session and every trade
  animation), and until a save is loaded.
- **Save to keep changes.** Like the in-game menus, edits change the game in
  memory; they reach your save file when you save (START > SAVE). Note that
  changing boxes in Bill's PC saves immediately, as in the original.

**POKéMON**:

- **Compact** (default): one line per Pokémon, like the in-game party menu:
  animated party icon, name, level, status and HP bar. All six fit on one
  screen.
- **SWITCH** rearranges the party like the in-game SWITCH: while it's on
  (the button reads DONE) the cards stay compact, and you tap one POKéMON,
  then another to swap them. It works whenever the game would allow it
  (free roam, no menu, text or battle; a tap while walking waits for the
  step), ends by itself when that stops, and on Gen 2 held MAIL moves with
  its POKéMON. SECURE MODE asks for the PIN first.
- Tap a Pokémon to expand it, or press **DETAILS** to expand all: front
  sprite in the current palette, types, status, stats, and moves with PP.
- The page refreshes about once a second, including HP/PP/status changes
  during battle. The mode is remembered; `?view=full` or `?view=compact` in
  the address picks one explicitly.

The pixel font loads from Google Fonts; without internet the page falls back
to a monospace font.

## Gen 2 (Gold / Silver)

Everything above works on Gold and Silver too, reading Gold's own world,
save and data. What's different there:

- **LIVE:** the location is the map's landmark name. Grass encounters
  differ by time of day: the DexNav shows the current one (GRASS · DAY)
  and the MORN / DAY / NITE switch previews the others (the green dot marks
  the real time). Fishing follows the map's fish group, night rows
  included. A roaming legendary on your current route gets a ROAMING
  section of its own. Battles read what Gold's battle screen shows (HUD, draining HP,
  "used ...!" text), so the phone never runs ahead there either.
- **Actions:** BIKE, the rods and the SQUIRTBOTTLE share the item row. The
  field moves add HEADBUTT, WHIRLPOOL, WATERFALL, SWEET SCENT and MILK DRINK
  (which asks whom to heal, like SOFTBOILED); moves your badges don't allow
  yet stay hidden. FLY offers the visited towns of the region you're in,
  like the game's fly map, and flies through the game's own flight. ROCK
  SMASH is not offered (the engine has no field action for it).
- **POKéMON:** SPCL.ATK and SPCL.DEF instead of SPECIAL, the held item (a
  small marker on the row, ITEM/ in the details), ♂ / ♀, shiny, and EGGs.
- **ITEMS:** the PACK's four pockets (ITEMS, POKé BALLS, KEY ITEMS, TM/HM).
  Items swap within a pocket; the TM/HM pocket is always sorted by number,
  as in the game. Held items are shown, not changed from the phone.
- **PC:** 14 boxes with their names; held items travel with the POKéMON.
  Editing also pauses while the PACK, a PC, a mart, the day-care or an NPC
  trade is open in the game (Gold has no Cable Club).
- **POKéDEX:** 251 entries (caught = OWN), Gold's entry texts, heights and
  weights. It opens in **JOHTO** order (the NEW POKéDEX; cells show
  J001 …), and the sort menu's **KANTO** switches to the national order.
  **AREA** uses the POKéGEAR map: a JOHTO / KANTO switch (KANTO once you've
  visited INDIGO PLATEAU, like the POKéGEAR's fly map, or have a HALL OF
  FAME record, or with SPOILERS), nests from the game's own search (roaming
  legendaries included, listed as ROAMING), and each row says when it
  applies (e.g. GRASS · MORN/DAY).
- **Icon mods:** icons a mod ships already in color (e.g. Unique Menu Icons'
  GBC RED / UNIQUE COLORS modes) are shown exactly as drawn, in both
  generations; grayscale ones get the game's palette like the built-ins.
- **GEAR** (a sixth tab, Gen 2 only, between ITEMS and PC): the POKéGEAR
  on the phone.
  - **CLOCK:** the day and time, plus MORN / DAY / NITE.
  - **PHONE:** your contacts with where they live and a REMATCH badge once
    they're waiting for a battle. CALL makes the call right on the phone.
    The contact's real call script runs in the game, but its text and any
    YES / NO show up in a text box on the phone instead of the TV. So what
    a call does in the game it does here too (a trainer on their day asks
    for a rematch, MOM asks about saving money). The game stands still
    during a call, as it does behind the POKéGEAR. With no signal, or when
    the contact is right there, you get the game's own answer instead. An
    unanswered call pages on and says NO by itself after a minute, so the
    game never stays frozen.
  - **Incoming calls:** when someone calls you in the game, it rings and
    plays on the TV exactly as before, and you can answer it there. The
    phone rings along: the game's own ring sound twice with a buzz under
    each, every few seconds, until the call is picked up in the game or on
    the phone. It then follows along in the same text box (marked
    INCOMING), and its ▼ / YES / NO buttons simply press A (or B for NO) in
    the game, so you can answer from either side. Browsers only play sound
    and vibrate once the page has been tapped at least once, and iPhones
    have no vibration for web pages.
  - **TEST CALL** (OPTION menu, Gen 2): rings the game's phone with a
    wrong-number call as soon as the menu is closed, to try the phone's
    ring and buzz. It sets nothing in the game.
  - **RADIO:** the stations you can hear where you're standing. Tapping one
    tunes it in the background: its song becomes the map music, just like
    leaving the POKéGEAR on that station, until you change maps or tap MAP
    MUSIC. That keeps the radio's field effects:
    - POKéMON MARCH and the UNOWN station double wild encounters, and
      LULLABY halves them (the tab says which one is on).
    - The POKé FLUTE station wakes SNORLAX.
    - Talk shows play their music only; their text is only in the real
      POKéGEAR.
  - Calling and tuning need the overworld free (no menu, text or battle),
    and SECURE MODE's PIN like the other actions.
- **Crystal** works like Gold and Silver, and its POKéMON pictures animate:
  the POKéDEX entry and a party POKéMON's DETAILS play the picture's
  animation once when they open, like the game's summary screen, and a tap
  on the picture plays it again (with "reduce motion" on, only on a tap).
  The phone contacts and radio stations follow what the game engine
  supports, so Crystal-only ones appear once the engine has them.
- **Look:** the same STANDARD look as Gen 1 (see **Skins**).

## Gen 3 (FireRed / LeafGreen)

FireRed and LeafGreen run on their own engine, so the mod reads them through
its own modules (`*3.lua`). Rearranging works like on the older games:
the party's SWITCH, swapping BAG items within a pocket, SORT (and UNDO), and
moving or swapping POKéMON between boxes (a move drops it in the box's first
free slot). The TM CASE and BERRY POUCH stay sorted by number, as the game
keeps them. GIVE TO HOLD works as in the game's BAG: anything but KEY ITEMS
and TM CASE items can be held (berries too), an item it already holds goes
back to the BAG, and MAIL is given in the game (it needs a letter).
LIVE's QUICK ACTIONS work too (`actions3.lua`), through the game's own code:
the BICYCLE, the rods (while facing water) and the field moves CUT, FLASH,
STRENGTH, SURF, ROCK SMASH, WATERFALL, TELEPORT, DIG, SWEET SCENT and the
SOFTBOILED / MILK DRINK heal; a move without its badge stays hidden. FLY
lists the towns the game's fly map would offer (visited, in the region
you're in) and flies there with the game's own flight. PC TRANSFERS (the
mod option) work as on the older games (`transfer3.lua`), through the
game's own PC code: DEPOSIT into a box's first free slot (healed, as the PC
does; not the last POKéMON that can fight, not one holding MAIL), WITHDRAW,
a party <-> box swap, and items between the BAG and the PLAYER's PC (up to
999 per slot, 50 slots; important items can't be stored). Without the
option the PLAYER's PC items are listed read-only. Emerald works too; see
**Emerald** below for what differs.

Edits are careful with the save (`edits3.lua`): they only run while the game
is in free roam with nothing open (no menu, text, script, battle or warp;
a request made mid-step waits for the step), they only ever reorder what is
there, and each one is checked afterwards (the same items and POKéMON, each
exactly once) and undone if anything looks off. As on the other games,
save in the game to keep the changes.

- **POKéMON:** each card adds what Gen 3 introduced:
  - **NATURE**, with the stat it raises marked ▲ (red) and the one it
    lowers ▼ (blue), as on the game's summary screen
  - **ABILITY** and its description
  - EXP and how much is left to the next level
  - the original trainer and ID, the POKé BALL it was caught in, and the
    summary screen's TRAINER MEMO ("BOLD nature. Met in ROUTE 1 at Lv.3.")
  - stats in FireRed's order: ATTACK, DEFENSE, SP. ATK, SP. DEF, SPEED
  - With **SHOW HIDDEN VALUES**, the IVs (0-31, a perfect 31 in green) and
    EVs (0-255 each, with the total out of 510) take the place of DVs and
    Stat Exp, plus HIDDEN POWER's type and power, FRIENDSHIP and Pokérus.
- **BAG:** the five pockets as the game keeps them: ITEMS, KEY ITEMS,
  POKé BALLS, TM CASE (each TM / HM with its move) and BERRY POUCH. The
  PLAYER's PC items are listed below them.
- **PC:** all 14 boxes of 30, with the names the player gave them.
- **POKéDEX:** national numbers, as long as the game's own dex currently
  is: the 151 of the Kanto dex, then all 386 once the NATIONAL DEX is
  unlocked (the game's own check). Then, like the game, SORT offers both
  numerical modes: NATIONAL (all 386) and KANTO (1-151, with its own SEEN /
  OWN counts). Entries show the category, height and weight as the game prints
  them (ft/in, lbs), the description and both **abilities** the species can
  have. MOVES adds the TMs and HMs it can learn; EVO words FireRed's
  methods (friendship by day / night, stones, trade items, ATK vs DEF, ...).
  With SHOW HIDDEN VALUES the DATA page adds the **EV yield**, the items
  wild ones may hold, base stats with their total, catch rate, base EXP and
  growth rate. The CRY button plays the game's own sample through its own
  mixer (`cry3.lua`), as the POKéDEX plays it. The roaming legendary
  (RAIKOU, ENTEI or SUICUNE, after the NATIONAL DEX) shows in its AREA
  on the route it is on right now, listed as ROAMING with its own marker,
  as the game's POKéDEX shows it.
- **LIVE:** the location is the region map's place name; DexNav lists
  grass (or cave), SURF, ROCK SMASH and each rod the player owns, with
  FireRed's slot weights, plus the roaming legendary while it is on your
  route. The battle section shows the foe and, in trainer battles, the
  team. SAFARI ZONE and DAY-CARE work as on the older games, with both
  day-cares (ROUTE 5 and FOUR ISLAND's pair).
- **Look:** the STANDARD look like the other games, or the FRLG skin in
  the cream and red of FireRed's menus (see **Skins**); the pictures are
  the game's own full-colour GBA art at 2x.

### Emerald

Emerald runs on the same Gen 3 engine, so everything above works the same
(party, BAG, PC, rearranging, transfers, DexNav, battles, cries, hidden
values). Where Emerald differs, the page follows Emerald:

- **Pictures:** the type badges and item icons are Emerald's own (its
  summary screen's and BAG's), and the BAG's pockets carry Emerald's names
  (TMs & HMs, BERRIES).
- **Places:** Hoenn's place names, as the game's map and POKéNAV give them
  (inside a building, its town). The TRAINER MEMO reads as Emerald's ("Met
  at Lv.5, ROUTE 101.").
- **REGION map:** Hoenn's map with BRENDAN or MAY on the square the game's
  own map puts you on.
- **POKéDEX:** before the NATIONAL DEX it holds the 202 Hoenn species in
  HOENN order, with HOENN's own numbers and counts; afterwards NATIONAL and
  HOENN, like the game's two modes. AREA shows Hoenn's map with the
  sections the game's own AREA search lights up (washed red) and dots on
  its caves and special places.
- **Quick actions:** the MACH BIKE or ACRO BIKE, whichever you have. FLY
  offers the towns and cities you've visited (and the BATTLE FRONTIER
  once found) and lands where the game's fly map would. DIVE and SECRET
  POWER join the field moves, in Emerald's party-menu order.
- **Extras:** the roaming LATIAS / LATIOS in AREA and DexNav, the one
  DAY-CARE on ROUTE 117, and the SAFARI ZONE: with SHOW HIDDEN VALUES its
  battles show BALL, POKéBLOCK (one it likes) and GO NEAR, each with the
  next ball's catch chance and the next turn's chance it runs.
- **CONDITION and RIBBONS:** each card (and the PC's POKéMON sheet) shows
  the five conditions as bars behind Emerald's own COOL / BEAUTY / CUTE /
  SMART / TOUGH badges, plus SHEEN (the values themselves with SHOW HIDDEN
  VALUES), and its ribbons as the PokéNav's pictures; tap one for what it
  was awarded for.
- **POKéBLOCK CASE:** in ITEMS below the pockets: each block's name,
  level, FEEL and flavours.
- **CONTEST:** while you're in one, LIVE shows it in the battle's place:
  the appeal round, the applause meter, each contestant's condition
  hearts, this round's appeal, total and state (judge's attention,
  nervous, watching), the final standings, and your moves' category,
  hearts, jam and effect (with a COMBO mark after the right move). Like
  battles, it never runs ahead of the screen: a turn shows once the screen
  has played it.
- **POKéNAV tab** (in the POKéGEAR's place): MATCH CALL lists your
  contacts as the PokéNav does, with where they are and a REMATCH badge
  when they want a battle; BERRIES lists every tree you planted with the
  berry, its stage, the time to the next one, a WATER badge when it's dry,
  and how many berries are ripe.
- **FEEBAS:** with SPOILERS, on ROUTE 119 the minimap rings today's six
  FEEBAS tiles, worked out the way the game does (and without touching its
  random numbers).

## Language mods

Names the game owns come from the game, so a language mod's translations
show on the page too: POKéMON, moves, items, types, places, the POKéDEX,
the field move buttons (named the way the party menu names them), the
BICYCLE and rod buttons (their item names), the radio stations, and the
engine's own words the page prints: the GEAR clock's day, MORN / DAY / NITE,
SEEN / OWN, MONEY and AREA UNKNOWN. Those last ones are looked up in the
engine's `Strings` catalog (`mod.content.strings`), so a language mod has
to translate them there; one that only swaps text while the game draws it
is invisible to the page. A POKéDEX entry with metric numbers (`heightM` /
`weightKg`, as a language mod may add them) shows its height and weight
like Red / Blue's metric entry screen (`GR. 0,7m`, `GEW. 6,9kg`); Gold's
dex has no metric screen, so there it only follows a mod that adds those
two fields. The page's own words (tab names, headings, hints
such as "Face a tree") are the mod's and stay English.

## Options

| Option       | Values                    | Notes                                      |
|--------------|---------------------------|--------------------------------------------|
| PHONE SERVER | ON / OFF                  | Stops listening entirely when off.         |
| PORT         | 8080, 8081, 8888, 3000    | Pick another if 8080 is already in use.    |
| SHOW URL     | AT START / ALWAYS / OFF   | When to draw the address on screen.        |
| SECURE MODE  | OFF / ON                  | Rearranging needs pairing (PIN or QR code). |
| SPOILERS     | OFF / ON                  | Reveal trainer teams, unseen DexNav species and unseen POKéDEX entries. |
| VIBRATION    | OFF / ON                  | The phone buzzes with a cry and rings with an incoming call. |
| SHOW HIDDEN VALUES | OFF / ON            | A party POKéMON's DETAILS show its hidden values (see below). |
| PC TRANSFERS       | OFF / ON            | Move POKéMON between the party and the PC boxes, and items between the BAG and the item PC (see below). |
| HANDS-OFF MODE | OFF / ON              | The dashboard for a TV (see HANDS-OFF MODE above). |
| SKIN         | STANDARD / POKéDEX RED / DARK / MODERN … | The page's look: one of the skins in `web/skins.css`. |
| TEST CALL    | RING                      | Gen 2, in the OPTION menu: a wrong-number call to try the phone's ring. |

## Hidden values

With SHOW HIDDEN VALUES on, an open party POKéMON's DETAILS get a HIDDEN
VALUES box:

- **DV and STAT EXP** per stat. The HP DV is worked out from the other four
  the way the game does; on Gen 2 one SPECIAL DV serves both SPCL.ATK and
  SPCL.DEF.
- **HIDDEN POWER** (Gen 2): the type and power its DVs give it. A POKéMON
  that knows the move shows that type and power in its move list too,
  instead of NORMAL.
- **HAPPINESS** (Gen 2), with "evolves at 220" for species that evolve by it.
- **POKéRUS** (Gen 2): none, infected (days left), or cured (a cured
  POKéMON still gains double Stat Exp).
- **FRIENDSHIP** (Yellow): your own PIKACHU's.

On Crystal, DETAILS also show where it was **MET** (level, time of day,
place), whether the option is on or not.

The POKéDEX entry gets them too, for species it shows in full (caught, or
all with SPOILERS):

- **DATA:** the base stats, CATCH RATE (out of 255, higher is easier), BASE
  EXP and GROWTH rate.
- **EVO** (Gen 2): under the egg groups, the GENDER ratio and how many steps
  an egg takes to hatch.

And LIVE's battle section gets the odds:

- **Wild battles:** the foe's CATCH RATE and every ball in the bag with the
  chance one throw catches it as it is now (HP, status, the ball's own
  bonus), from the game's own catch math. A mod that replaces the catch
  roll shows "-" instead of a guess.
- **Safari battles** (Gen 1 and 3): the catch / run table described under
  LIVE above, with the current catch rate.

Wild held items are left out: the engine doesn't give wild POKéMON items yet.

## PC transfers

With PC TRANSFERS on (off by default):

- **PC tab:** a PARTY list sits above the box. Tap a party POKéMON, then
  MOVE HERE in any box to deposit it; tap a boxed one, then MOVE HERE under
  PARTY to withdraw it. Tap a party POKéMON and then a boxed one (or the
  other way round) and they trade places, which works even with a full
  party and full boxes.
- **ITEMS tab:** a PC section lists the item PC. Tap an item in the BAG or
  the PC, pick how many (− / + / ALL), then TO PC or TO BAG. Key items and
  HMs always move one, like in the game.

Everything follows the game's own PC:
- **POKéMON:** it refuses the last POKéMON (Gen 2: the last one that can
  still fight), a full box or party, and on Gen 2 a POKéMON holding MAIL.
  The POKéMON is healed on the way in and out as the game does it. In Yellow
  the sleeping PIKACHU stays.
- **Items:** it refuses a full bag or a full PC (50 stacks).

Transfers only run while the game is standing still: no menu, text box,
battle or script, and no BAG / PC screen open. A request the game changed
in between is refused instead of hitting the wrong POKéMON or item. Like
every edit from the phone, only the game's memory changes: **save in the
game to keep it**, or reload your save to undo.

## Skins

The SKIN option picks the page's look, and every skin works on every game:
STANDARD (the Game Boy look, the default), POKéDEX RED, FRLG (FireRed's
menus), EMERALD (May's red, the bandanas' green, cream), DARK and MODERN.
The page is styled in three layers:

- `web/base.css`: the layout. It sets no colours, fonts or corner sizes
  itself, only uses the tokens (CSS variables) below.
- `web/standard.css`: the standard look (the STANDARD skin, served as
  `/theme.css` on every game), which defines every token.
- `web/skins.css`: the skins. Each one is a block of tokens under
  `html.skin-<id>`, with an `@skin <id> "<NAME>"` line above it that puts it
  in the SKIN option.

The page has three colour sets: `--header-*` for the header with the tab
bar (including the line under it), `--page-*` for the space around the
boxes (notes, buttons on the page) and `--box-*` for the game-style boxes
that hold the content. Four button groups (quick action items, field
moves, SWITCH / DETAILS, PC boxes) have their own tokens, including shadows
and a press depth for a 3D look. Text comes in six roles (label, title,
subhead, name, note and body), each with its own font and weight, so a
skin can for example make titles bold and names regular. `--sprite-palette` shows every POKéMON and
trainer picture in four colours of the skin's choosing, like the GBC
POKéDEX's green screen (POKéDEX RED does this). To make a skin, copy the POKéDEX RED block in
`skins.css`, give it a new id and name, and change the values; the steps
and the full token list are at the top of that file. A skin may also
restyle any rule by starting its selector with `html.skin-<id>`, and target
one generation with `html.gen1` / `html.gen2` / `html.gen3`. New skins show up in the
option after a game restart; edits to an existing one on a page reload.

## Troubleshooting

- **Page won't load:** check that the phone isn't on a guest or mobile network,
  and that the firewall allowed the game (Windows Settings > Firewall > Allow an
  app). Public Wi-Fi often blocks device-to-device traffic.
- **Wrong IP shown:** with a VPN or virtual network adapters active, the game
  may pick the wrong interface. Run `ipconfig` and use your Wi-Fi adapter's
  IPv4 address instead.
- **"could not listen on port" in the log:** another program (or a second game
  instance) uses that port. Change **PORT** in the mod options.

## Privacy

Anyone on your local network who knows the address can see your party, bag
and boxes, and, with SECURE MODE off, rearrange them. Turn **SECURE MODE**
on for shared networks, and **PHONE SERVER** off on untrusted ones.

## Files

- `main.lua`: options, server lifecycle, on-screen URL, OPTION > PHONE row
- `platform.lua`: which generation runs and where it keeps things (world,
  money, dex, boxes, screen ids); every other module asks here
- `live2.lua`, `actions2.lua`, `area2.lua`: the Gen 2 versions of the LIVE
  data, the game actions and the AREA view
- `gear.lua`: the Gen 2 GEAR tab (clock, phone calls run on the phone, incoming calls mirrored, radio)
- `snapshot3.lua`, `sprites3.lua`, `live3.lua`, `dex3.lua`, `area3.lua`, `edits3.lua`: the
  Gen 3 (FireRed / LeafGreen) versions of the party / bag / PC data, the
  pictures, the LIVE data, the POKéDEX and the AREA view
- `server.lua`: non-blocking HTTP responder pumped each frame
- `snapshot.lua`: party, bag and boxes to a JSON-ready table (read-only)
- `edits.lua`: bag swaps and box moves, only while the game is free-roaming
- `uids.lua`: stable ids for boxed POKéMON
- `live.lua`: LIVE tab data (location, DexNav, battle)
- `dex.lua`: POKéDEX tab data (SEEN / OWN, every entry, entry pages)
- `bagsort.lua`: the ITEM / PACK tab's SORT orders
- `transfer.lua`: PC TRANSFERS (party <-> boxes, BAG <-> item PC)
- `area.lua`: POKéDEX AREA view (nests and where each species is found)
- `cry.lua`: a species' cry (and Gen 2's phone ring) as a WAV for the phone
- `cry3.lua`: Gen 3's cries, rendered from the game's samples as a WAV
- `minimap.lua`: the LOCATION section's HERE / REGION maps
- `notify.lua`: HANDS-OFF MODE's notifications (what changed between updates)
- `pokenav3.lua`: Emerald's POK�NAV tab (MATCH CALL, BERRIES)
- `actions.lua`: game actions from the phone (BICYCLE, fishing rods, field moves)
- `transforms.lua`: asset recipe that copies the battle's ball sheet from
  your own imported game into the mod's derived folder (nothing ROM-derived
  ships with the mod)
- `sprites.lua`: front sprites and party icons as palette-colored PNGs
- `qr.lua`: QR code encoder (byte mode, level M, versions 1-6)
- `qr_screen.lua`: the in-game QR code screen
- `web/index.html`: the phone page; `web/base.css` its styles,
  `web/standard.css` the standard look, `web/skins.css` the skins

Icons: [Pixelarticons](https://pixelarticons.com) by Gerrit Halfmann (MIT
licence), copied into `web/index.html` so the page downloads nothing extra.

Permissions: `network` for the server, `engine_internals` to reuse the
game's sprite, palette, font and party-icon code.

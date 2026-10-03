# Second Screen Companion

See your game on your phone, tablet or TV while you play. Your team, your
bag, the map, wild Pokémon nearby and every battle, live, in any web
browser. There's no app to install.

Works with **Gen1, Gen2 and Gen3**.

## What it does

- **Your team at a glance:** every Pokémon with its HP, status, level,
  held item, stats and moves. It updates as you play, even mid-battle.
- **Battle helper:** the foe's HP and the moves it has used so far, the
  trainer's team, stat changes (like ATK×0.66 after a Growl), weather, and
  effects such as Leech Seed, Reflect or Perish Song with the turns left.
- **DexNav:** which wild Pokémon live where you're standing, at what level
  and how often, with the ones you've caught marked.
- **Maps:** the area you're in with its exits and items, and the town map
  with where you are.
- **Pokédex:** every entry with pictures, descriptions, evolutions, moves,
  where to find each Pokémon, and its cry.
- **Your bag and PC:** see everything, and sort or rearrange it from your
  phone. It shows up the same way in the game.
- **Use items from your phone:** Potions, status cures, Rare Candy,
  evolution stones, TMs, Repels, the bike and fishing rods. The effect
  plays in the game as usual.
- **Quick actions:** use Cut, Surf, Fly and other field moves with one tap.
- **Extras per game:** in Gold, Silver and Crystal, the Pokégear: make and
  answer phone calls and tune the radio from your phone. In Emerald, follow
  contests live, see your berry trees, and a Match Call list showing who
  wants a rematch.
- **TV dashboard:** a big overview to leave running on a second screen
  (see below).

## Getting started

1. Turn the mod on in the launcher and start the game.
2. On Windows, a firewall message may pop up the first time. Choose
   **Allow** for **private networks** (your home network).
3. In the game, open **OPTION > PHONE** (in FireRed, LeafGreen and
   Emerald: **START > PHONE**) and scan the QR code with your phone's
   camera. Or type the address shown in the corner of the game screen into
   your browser, for example `http://192.168.2.82:8080`.
4. Your phone or TV needs to be on the **same Wi-Fi** as your PC.

That's it. Keep the page open while you play. Bookmark it for next time;
the address normally stays the same.

### Playing on Android or a handheld

The companion should also work when the game runs on an Android phone or some other handheld devices:

- **Wi-Fi must be on** on the device running the game. Some handhelds turn
  it off to save battery.
- **No Wi-Fi around?** Turn on your Android phone's hotspot and connect the
  other device to it.
- **Keep the game awake.** When the screen turns off or the game goes to the
  background, the page pauses until you're back.
- **One viewer is best** on a handheld. The page works for the game, and
  small devices have less power to spare.

## Mod options

Find these in the game's options under the mod.

| Option | What it does |
|---|---|
| PHONE SERVER | Turns the companion on or off. |
| PORT | Change it only if the page won't start (if another program uses the same one). |
| SHOW URL | When to show the address on the game screen. |
| SECURE MODE | Only your devices can change things. They need the PIN or QR code from OPTION > PHONE first. |
| SPOILERS | Show what you haven't discovered yet: trainers' teams, unseen Pokémon, hidden items. |
| SHOW HIDDEN VALUES | Show behind-the-scenes numbers: IVs or DVs, EVs, catch and escape chances, and more. |
| PC TRANSFERS | Move Pokémon and items between your party, bag and PC from your phone. |
| VIBRATION | Your phone buzzes with cries and incoming calls. |
| HANDS-OFF MODE | Turns the page into the TV dashboard. |
| SKIN | The page's look: Game Boy, Pokédex Red, FireRed, Emerald, Dark or Modern. |

## TV dashboard (HANDS-OFF MODE)

Made for a TV or second monitor that nobody touches. Everything is on one
screen: your team, the map, the DexNav, and big battle views with the
trainer's team on the side. Pop-ups tell you when you catch a Pokémon, level
up, get an item or earn a badge.

In FireRed and LeafGreen with the FireRed or Emerald skin, caves and other
special places show the game's own artwork in the background.

To use the dashboard on just one device, add `?handsoff=1` to that device's
address, for example `http://192.168.2.82:8080/?handsoff=1`. Your phone
keeps the normal page. To change the size, add `?size=large` or
`?size=small`.

For TVs left on for hours, the screen slowly shifts and dims when nothing
happens, to prevent burn-in.

## Good to know

- **Save in the game to keep changes.** Things you change from your phone
  work just like the game's own menus. They're kept once you save in the
  game.
- **Your PC stays safe.** The page can only show and change your game,
  nothing else on your computer. It can only be reached from your own
  network, not from the internet.
- **Sharing a network?** Anyone on the same Wi-Fi could open the page. Turn
  on **SECURE MODE** if you play on a network with roommates or guests, or
  turn **PHONE SERVER** off on public Wi-Fi.
- **Changes wait for the right moment.** Edits from your phone only happen
  when the game would let you, for example not during a battle or while a
  menu is open. The page tells you when to wait.
- **Nothing extra to install.** The few pictures the mod makes for itself
  are built automatically from the game you already imported, and rebuilt
  on their own if you import it again. In Gold, Silver and Crystal, the
  Kanto badges appear once you've played Red, Blue or Yellow with the mod
  on.
- **Should work with other mods.** New Pokémon, items, maps and translations from
  other mods show up on the page too.

## Something not working?

- **The page doesn't open:** make sure your phone is on the same Wi-Fi as
  the PC, not on mobile data or a guest network. Check that Windows allowed
  the game: Settings > Privacy & security > Windows Security > Firewall >
  Allow an app through firewall.
- **The address doesn't work and you use a VPN:** turn the VPN off, or ask
  someone to help you find your PC's Wi-Fi address.
- **"Could not listen on port":** pick another **PORT** in the mod options.
- **The page says the game can't be reached:** the game was closed or the
  PC went to sleep. It reconnects by itself once the game is back.

---

For all the details of every feature and how the mod works inside, see
[TECHNICAL.md](TECHNICAL.md).

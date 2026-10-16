# Bestiary: design

A collectible auto battler fed by your real WoW play: the mobs you kill can drop trophy cards
of themselves. You prepare three squads of five from your collection; in a duel both players
secretly pick one, and the squads fight on their own. Every card is Armor, Magic or Assassin,
and those counter each other like rock, paper, scissors, so guessing what the other side sends
matters as much as having strong cards. Optional hardcore: when your character dies, your
bestiary dies.

Status: design only, nothing built. Sections marked **Open** still need a decision; everything
else is the current proposal and can be changed.

---

## 1. Core loop

1. Play WoW normally. Mobs you kill can drop a **card** of that mob.
2. Getting the same card again **levels it up** instead of giving a copy.
3. Build **three squads** of five cards. Every card is **Armor, Magic or Assassin** (3.5);
   squads mix them however you like. Families (beast, undead, ...) give bonuses when you
   field several of one kind.
4. **Duel** another player: both secretly pick one of their squads, then the two fight
   automatically and you watch the replay. Bring the squad that counters theirs and you win
   easily; get read and you lose.
5. Wins earn rating and small rewards; your collection is what you build up over time.

The building part is choosing what to hunt: want a dragonkin team, go farm whelps in the
Wetlands and wyrmkin in the Swamp of Sorrows.

## 2. What the addon can see

| What | How | Notes |
|---|---|---|
| A mob died that we fought | Combat log: remember GUIDs the player (or pet) damaged, then `UNIT_DIED` for one of them | GUID gives the creature's NPC id |
| Mob name | Combat log (dest name) | |
| Level, elite/rare, creature type | `UnitLevel`, `UnitClassification`, `UnitCreatureType` while it's target, mouseover or nameplate; cached by GUID and by NPC id | Not in the combat log, so a mob killed without ever being targeted or on a nameplate may lack them: then use the NPC id cache, else no drop |
| Tapped by someone else | `UnitIsTapDenied` while cached | Tapped-away mobs give nothing |
| XP worth (grey or not) | Level difference vs. player (the game's grey level formula) | Grey mobs give nothing |
| What the mob did | Combat log: spells the mob cast (`SPELL_CAST_SUCCESS`, school), melee swings | Used for its combat type (3.5) |
| Death | `PLAYER_DEAD` | Not on Feign Death. Also check `UnitIsDeadOrGhost("player")` on login for deaths while the addon was off |

## 3. Cards

### 3.1 Identity

A card is one **NPC id** (all "Defias Pillager" share one id). Stored per card:
`npcId, name, level (mob's), classification, family, combat type, stars (card level),
obtained (time, zone)`.

### 3.2 Stats without a database

We don't ship a mob database. A card's stats come from a formula over what we saw, so every
client computes the same numbers:

- **Power budget** from mob level and classification:
  `budget = base(level) * rarityFactor * starFactor`
  rarityFactor: normal 1, elite 1.6, rare 1.8, rare elite 2.4, boss 3.
  Stars 1-5: +15% each.
- The budget is split into **Attack / Health / Speed** by family (beasts fast, undead tanky,
  demons hard-hitting, ...) and nudged by a seeded roll on the NPC id, so two level-20 beasts
  still differ, always the same way for everyone.
- One **ability** per card: picked by a seeded roll on the NPC id from its family's pool (3.4).
  Elites and better get a second ability.

Duels send the card data along (npcId, level, classification, family, combat type, stars), so
the other side can compute the same stats even if it has never seen that mob.

### 3.3 Rarity and drop chance

| Mob | Card rarity | Drop chance per kill |
|---|---|---|
| Normal | Common | 4% |
| Elite | Uncommon | 15% |
| Rare | Rare | 100% on first kill, then 25% |
| Rare elite | Epic | 100% on first kill, then 35% |
| Boss (`worldboss` / skull level) | Legendary | 25% |

Getting a card you have adds a star (max 5). How many copies a star needs is a balance
question for later; it depends on how much stars matter in a fight (see 5.3).

### 3.4 Families

From `UnitCreatureType`. Critters and "Not specified" don't drop cards.

| Family | Stat lean | Example abilities | Team bonus (2 / 4 of a family) |
|---|---|---|---|
| Beast | Fast | Pounce (first hit x2), Pack Hunter | +10% / +25% speed |
| Humanoid | Balanced | Shield Wall, Rally (heal ally) | +10% / +20% all stats |
| Undead | Tanky | Rise Again (once at 30% HP) | first death gets back up at 20% / 40% HP |
| Demon | Hard-hitting | Drain Life, Sacrifice | +15% / +35% attack, lose 2% HP per turn |
| Dragonkin | Strong, slow | Breath (hits all) | +15% / +30% health |
| Elemental | Area damage | Overload, Shield of Stone | +10% / +25% ability damage |
| Giant | Very tanky, slow | Stomp (stun) | +20% / +40% health, -10% speed |
| Mechanical | Armored | Self-Repair, Overcharge | take 10% / 20% less damage |

Numbers are placeholders for balancing.

### 3.5 Combat types: Armor, Magic, Assassin

Every card has one of three combat types. They're the rock, paper, scissors of the game, and
the counters come from how each type fights (5.2), not from a "beats" table:

| Type | How it fights | Strong against | Weak against |
|---|---|---|---|
| **Armor** | High health, slow. **Armor** takes a flat amount off every physical hit. Hits the front | Assassin: their many small hits barely get through | Magic |
| **Magic** | Fragile. Hits **ignore armor** and splash onto the next enemy | Armor: big slow targets standing together | Assassin |
| **Assassin** | Fastest, acts first. Strikes **twice** with smaller hits and goes for the **back row** (or the lowest health enemy) | Magic: kills fragile casters before they cast | Armor |

- A squad is any mix: 3 Armor in front and 2 Magic behind is solid against Assassins and
  weak against Magic; a mixed squad is safe but never crushes.
- A perfect counter should win clearly, but stronger cards still matter a little (target:
  a full counter squad wins about 80% at equal power; to be tuned in the headless tests).

**Which type a card gets:** from what the mob actually did while you fought it. It cast
non-physical spells: **Magic**. Otherwise by family lean and a seeded roll on the NPC id
(Giant, Mechanical, Undead lean Armor; Beast, Humanoid lean Assassin; Demon, Dragonkin,
Elemental lean Magic). **Open:** whether watching the mob is reliable enough, or the type
should come only from family and NPC id (simpler, the same for everyone right away).

## 4. Getting cards

### 4.1 Counting a kill

A kill counts if: we (or our pet) damaged it, it wasn't tapped by someone else, it isn't grey
for us, and it isn't a critter.

Group kills count for everyone who damaged the mob, so dungeons with friends are fun. Drop
chance x0.75 in a 5-man group, x0.25 in a raid (to be balanced).

### 4.2 Against farming

- Same NPC id: drop chance halves for every card dropped from it within the last hour.
- Daily cap of commons (like 15); rarer cards uncapped.

### 4.3 Loot luck

Dropped for now: unclear what it would add. Can come back if cards need another source.

## 5. Squads and battle

### 5.1 Squads

You prepare **three squads**, each 3 to 7 cards in order, front to back, with one leader
(6.1). Front cards get
attacked first, except by Assassins (back row) and splash. A card can be in more than one
squad. You can change your squads any time, but a duel uses the squad you locked in for it.

### 5.2 Battle simulation

Deterministic, so both clients produce the same fight without talking during it:

- **Own random generator** (seeded, not `math.random`), seeded from the duel id.
- Turns: everyone acts in speed order (Assassins first). Targets by type: Armor and Magic
  hit the frontmost alive enemy (Magic splashes onto the one behind it), Assassins hit the
  backmost (or the lowest health enemy, to be tested). Armor takes a flat amount off every
  physical hit; Magic ignores it.
- Abilities trigger by rules: on first attack, below X% HP, every N turns, on death.
- At most 50 rounds; then whoever has more health left wins.
- Output: a list of events (who hit whom, for how much, who died) the UI plays back as a
  replay. The result comes from the simulation, never from the network.

Both sides run the same code and the same version. Duel messages carry a protocol version like
Quiz Duel, and mismatches are refused.

### 5.3 How a fight plays out, and where the strategy is (to work out next)

This decides whether building a squad is interesting, and it's also the answer to balancing
duels (6). Levers a player can pull, all before the fight (it's an auto battler):

- **Order:** who stands in front takes the hits; back cards with ranged or area abilities
  are safe until the front falls. Tanky front, damage behind, or a fast striker up front to
  kill something before it acts.
- **Speed:** turn order. Fast cards act first, so a fast high-damage card can remove an enemy
  before it ever acts; slow tanks act last but survive.
- **Family bonuses:** 2 or 4 of a family trade flexibility for a strong bonus.
- **Combat types:** the Armor / Magic / Assassin mix of a squad (3.5), and which of your
  three squads you send against which opponent (6). This is the main strategy: there's no
  single best squad, and a squad built against one opponent loses to another.
- **Abilities:** triggers (first attack, low health, on death, every N turns) and targets
  (front, back, lowest health, all) that combine: an undead "rise again" in front, a
  dragonkin breath behind, a humanoid healer in the middle.
- **Power cap (proposal for fairness):** every card has a power cost (its budget from 3.2).
  A duel sets a team power cap, for example 100, 200 or 400, and both teams must fit under it.
  A big collection gives more options to fill the cap well, not a guaranteed win; two strong
  cards or five weaker ones becomes a real choice. Stars and rarity raise power, so they
  matter by making a card better per cost, not just bigger.

Next step: write the fight rules out exactly (turn order, targeting, armor, splash, ability
triggers) and test them headless with many random squads: the triangle has to hold (each type
beats the one it should), mixed squads should land in between, and no single squad should beat
everything.

## 6. Duels

Both players pick one of their three squads **without seeing the other's pick**. To keep it
hidden even though the addon sends everything over whispers, picks are sealed first and only
opened once both are in (commit and reveal):

1. A challenges B. A picks a squad and sends only a **seal** of it: a hash of the squad data
   plus a random secret.
2. B accepts, picks a squad and sends its seal.
3. Once A has B's seal, A sends the real squad and the secret; B does the same once it has
   A's. Each side checks the other's squad matches its seal, so nobody can switch after
   seeing the other's pick.
4. Both simulate with the duel id as the seed and get the same result, then store the result
   and the replay.

Nobody needs to be online at the same time; every step waits until the other side is back
(like Quiz Duel). A squad snapshot is about 150 bytes, a seal about 20.

**What you know about your opponent:** nothing about their squads before the fight, only the
twist (6.2). Reading them comes from knowing the player and what they sent before.

**Open:** best of 3 (each round both send one squad, a squad can't be sent twice) instead of a
single fight.

Messages go through a paced queue like Grandma's Game Box's Box/Comm.lua (copied, since this
is its own addon): burst then 1 per second, deduplicated, offline players retried rarely.

**Fairness:** the hidden pick and the type triangle already mean the stronger collection
doesn't simply win. On top, the **power cap** (decided, 5.3): the challenger picks the cap,
and the squads both send must fit under it, like the points limit of a Warcry warband. Each of
your three squads can be built for a different cap, or you rebuild before locking in.

Rating: simple Elo per opponent and overall, per character.

## 6.1 Ideas from Warhammer Warcry

Warcry's roster building fits this game. What we take from it:

| Warcry | In Bestiary | Proposal |
|---|---|---|
| Points limit per warband | Power cap per duel; cards cost their power; caps like 300 / 600 / 1000 | **Decided** |
| Warband size varies | 3 to 7 cards per squad instead of a fixed 5: two strong cards or seven weak ones | **Decided** |
| A leader is required | One leader per squad (Elite, Rare or Boss card) with a squad-wide leader ability | **Decided** |
| Runemarks (keywords abilities refer to) | Family and combat type are the keywords abilities refer to ("other Undead get +armor") | **Decided** |
| Battleplan and twist cards | Each duel draws a twist, revealed at the challenge before both pick (6.2) | **Decided** |
| Limits on allies and monsters | At most one Legendary; no card above 40% of the cap | **Decided** |
| Campaign: injuries | Cards get worn out and sit out duels: stamina (6.3) | **Decided** |
| Campaign: experience | Cards gaining XP from duels | Not for now |
| Battle groups (Dagger / Shield / Hammer) | Reserves joining later | **No**: too complicated |
| Wild dice fuel abilities | A seeded roll per round that fuels abilities | **No** |

Squad sizes change 5.1: a squad is 3 to 7 cards, front to back, with one leader.

### 6.2 Twists

The duel id seeds a twist drawn from a list; it's shown with the challenge, so both players
know it **before** picking and building. It changes which squad is the right one each time,
so the same three squads don't always win. Examples:

- **Fog:** Assassins act twice in round 1.
- **Consecrated Ground:** Undead have no armor.
- **Ambush:** everyone hits the back row first.
- **Ley Lines:** Magic splash hits two enemies behind the target.
- **Shield Wall:** Armor takes double the usual off each hit, but everyone is slower.
- **Blood Moon:** Beasts and Demons +25% attack.
- **Calm Waters:** no twist.

Twists are pure rules in the simulation, so both sides apply them the same way.

### 6.3 Stamina: cards get worn out

Every card has a **stamina bar** (0 to 100). It makes you rotate cards instead of always
sending your best ones, so collection depth matters:

- **Fighting drains it** by how much health the card lost in the duel: stamina loss =
  health lost in % x a factor (proposal 0.6, so a card that dies loses 60). A card that
  wasn't hit loses nothing.
- **Resting refills it:** every duel you play where a card doesn't fight gives it stamina
  back (proposal +25).
- **At 0 the card is exhausted:** it sits out your next **2 duels**, then comes back with
  **full** stamina.
- Squads with an exhausted card can't be locked in, so your three squads need spares.
- Counted per duel you play, not per day, so players who duel a lot aren't punished more.
- Stamina has no effect on how a card fights; it only decides whether it can be sent.
- Card UI: a stamina bar under the health, "exhausted: back in 2 duels" when at 0.

## 7. Hardcore

- **Opt-in** when you start a bestiary on a character: Normal or Hardcore. Can't switch a
  running bestiary to Hardcore later (so nobody collects safely and then switches).
- Hardcore perks: drop chance x1.5, a separate rating, a skull on your cards in duels.
- When the character dies (`PLAYER_DEAD`, or found dead/ghost on login): the bestiary is
  **gone**. It moves to a "Hall of the Fallen" (per account): character, level, days survived,
  card count, best card, duel record. You can start a new one.
- Hardcore means complete loss, on purpose; that's its only death penalty.
- **Normal bestiaries:** dying drains stamina (6.3) from the cards in your squads (proposal:
  -50 each), so some may end up exhausted for a couple of duels. No cards are lost.

## 8. Saved data

- **Per character** (`BestiaryChar`): cards, three squads, mode (normal/hardcore), alive, duels,
  rating, anti-farming counters, mob info cache.
- **Account** (`BestiaryAccount`): Hall of the Fallen, settings, a shared mob info cache
  (npcId -> family, classification), so alts don't need to target a mob first.

Per character, because the hardcore twist is about that character's life.

## 9. UI

- **Collection:** grid of cards, filters by family/rarity/zone, card detail with stats and
  abilities. Cards are 2D: the mob's name, family icon as art, rarity border, stars, and the
  combat type as a badge (shield, flame, dagger).
- **Squads:** three squads of five slots, drag cards in; each shows its type mix, family
  bonuses and power.
- **Pick screen:** before a duel, your three squads side by side (and what you know about
  theirs); pick one and lock it in.
- **Duels:** list like Quiz Duel (challenge, incoming, finished) with replays.
- **Replay:** both teams side by side, hits and deaths played back over a few seconds, skip
  button.
- **Toast** when a card drops ("New card: Defias Pillager!", rare drops louder).
- Minimap button.

## 10. First version (MVP)

1. Kill tracking, mob info cache, card drops, collection list (no fancy UI).
2. Card stats, combat types and abilities from the formula; three squads.
3. Battle simulation with a test fight against a fixed dummy squad, replay as text; headless
   balance runs for the type triangle.
4. Duels over whispers, with sealed picks.
5. Hardcore mode and the Hall of the Fallen.
6. Proper UI (card grid, replay with visuals), balancing.

Headless tests for 3 and 4, like Quiz Duel's (the simulation must give the same result on
both sides for the same seed).

## 11. Decisions

- Name: Bestiary.
- Group and raid kills count (4.1).
- No loot luck for now (4.3).
- Hardcore is complete loss (7).
- Cards are 2D (9).
- Own addon, own git repo and GitHub.
- Combat types Armor, Magic, Assassin per card; squads mix them freely (3.5).
- Three prepared squads per player; both pick one in secret before a duel (6).
- A perfect counter wins easily (3.5).
- Power cap per duel, picked by the challenger (6).
- From Warcry: 3-7 cards per squad, a leader, keywords, twists, roster limits, cards getting
  worn out (6.1). No battle groups, no wild dice, no XP for now.
- Stamina per card: drained by health lost in duels, refilled by resting, 2 duels out at 0
  (6.3).
- You see nothing of the opponent's squads before the fight, only the twist (6).
- Death: hardcore loses the whole bestiary; normal drains your squads' stamina (7).

## 12. Open questions

1. Exact fight rules (5.2), then balance with headless runs.
2. Combat type from watching the mob, or only from family and NPC id? (3.5)
3. Single fight or best of 3 (6).
4. Cap sizes (6); stamina numbers (6.3, 7).
5. Stars: how many copies per star (3.3), after 1.

## 13. Mockup

`Bestiary.toc` loads a clickable mockup with made-up cards: the collection with one team of
five, and a duel replay against a fixed team. It predates combat types and the three squads. Nothing is tracked or sent; it's only there to
see the look in WoW. `/bestiary` or `/bst` opens it.

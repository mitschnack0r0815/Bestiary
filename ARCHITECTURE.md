# Bestiary: design

 A collectible auto battler fed by your real WoW play: the mobs you kill can drop
trophy cards of themselves; you build a team of five from your collection and it fights other
players' teams on its own. Optional hardcore: when your character dies, your bestiary dies.

Status: design only, nothing built. Sections marked **Open** still need a decision; everything
else is the current proposal and can be changed.

---

## 1. Core loop

1. Play WoW normally. Mobs you kill can drop a **card** of that mob.
2. Getting the same card again **levels it up** instead of giving a copy.
3. Pick **five cards** as your team. Families (beast, undead, ...) give bonuses when you field
   several of one kind.
4. **Duel** another player: both teams fight automatically; you watch the replay.
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
| Loot | `CHAT_MSG_LOOT` item links: quality, item level | Optional: rare/epic loot boosts the next card drop (see 4.3) |
| Death | `PLAYER_DEAD` | Not on Feign Death. Also check `UnitIsDeadOrGhost("player")` on login for deaths while the addon was off |

## 3. Cards

### 3.1 Identity

A card is one **NPC id** (all "Defias Pillager" share one id). Stored per card:
`npcId, name, level (mob's), classification, family, stars (card level), obtained (time, zone)`.

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

Duels send the card data along (npcId, level, classification, family, stars), so the other side
can compute the same stats even if it has never seen that mob.

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

## 5. Team and battle

### 5.1 Team

Five cards in order: front (1) to back (5). Front cards get attacked first; some abilities hit
the back row or everyone.

### 5.2 Battle simulation

Deterministic, so both clients produce the same fight without talking during it:

- **Own random generator** (seeded, not `math.random`), seeded from the duel id.
- Turns: everyone acts in speed order; each attack picks a target by simple rules (frontmost
  alive enemy unless an ability says otherwise).
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
- **Counters:** families beat others (proposal: a loose circle like beast > humanoid >
  undead > beast, demons strong against most but fragile, mechanical resist beasts...), so
  there's no single best team and a team built against one opponent loses to another.
- **Abilities:** triggers (first attack, low health, on death, every N turns) and targets
  (front, back, lowest health, all) that combine: an undead "rise again" in front, a
  dragonkin breath behind, a humanoid healer in the middle.
- **Power cap (proposal for fairness):** every card has a power cost (its budget from 3.2).
  A duel sets a team power cap, for example 100, 200 or 400, and both teams must fit under it.
  A big collection gives more options to fill the cap well, not a guaranteed win; two strong
  cards or five weaker ones becomes a real choice. Stars and rarity raise power, so they
  matter by making a card better per cost, not just bigger.

Next step: write the fight rules out exactly (turn order, targeting, ability triggers,
counters) and test them headless with many random teams to see which builds win.

## 6. Duels

Like Quiz Duel, nobody needs to be online at the same time for the fight itself:

1. A challenges B and sends their team snapshot (five cards, about 150 bytes).
2. B accepts with their own team snapshot.
3. Both simulate with the duel id as the seed and get the same result.
4. Both sides store the result and replay.

Messages go through a paced queue like Grandma's Game Box's Box/Comm.lua (copied, since this
is its own addon): burst then 1 per second, deduplicated, offline players retried rarely.

**Open:** fairness, the hardest question. Current proposal: the power cap from 5.3. The
challenger picks the cap, both build a team under it. Alternatives considered: raw (strongest
collection wins) and scaling both teams to the same power (hides what you collected).

Rating: simple Elo per opponent and overall, per character.

## 7. Hardcore

- **Opt-in** when you start a bestiary on a character: Normal or Hardcore. Can't switch a
  running bestiary to Hardcore later (so nobody collects safely and then switches).
- Hardcore perks: drop chance x1.5, a separate rating, a skull on your cards in duels.
- When the character dies (`PLAYER_DEAD`, or found dead/ghost on login): the bestiary is
  **gone**. It moves to a "Hall of the Fallen" (per account): character, level, days survived,
  card count, best card, duel record. You can start a new one.
- Hardcore means complete loss, on purpose.
- **Open:** normal bestiaries. Idea: dying loses a random card from your active team of five.

## 8. Saved data

- **Per character** (`BestiaryChar`): cards, team, mode (normal/hardcore), alive, duels,
  rating, anti-farming counters, mob info cache.
- **Account** (`BestiaryAccount`): Hall of the Fallen, settings, a shared mob info cache
  (npcId -> family, classification), so alts don't need to target a mob first.

Per character, because the hardcore twist is about that character's life.

## 9. UI

- **Collection:** grid of cards, filters by family/rarity/zone, card detail with stats and
  abilities. Cards are 2D: the mob's name, family icon as art, rarity border, stars.
- **Team:** five slots, drag cards in, shows family bonuses and team power.
- **Duels:** list like Quiz Duel (challenge, incoming, finished) with replays.
- **Replay:** both teams side by side, hits and deaths played back over a few seconds, skip
  button.
- **Toast** when a card drops ("New card: Defias Pillager!", rare drops louder).
- Minimap button.

## 10. First version (MVP)

1. Kill tracking, mob info cache, card drops, collection list (no fancy UI).
2. Card stats and abilities from the formula; team of five.
3. Battle simulation with a test fight against a fixed dummy team, replay as text.
4. Duels over whispers.
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

## 12. Open questions

1. Fight rules and strategy, and with them duel fairness: the power cap proposal (5.3, 6).
2. Stars: how many copies per star (3.3), after 1.
3. Penalty on death for normal bestiaries (7).

## 13. Mockup

`Bestiary.toc` loads a clickable mockup with made-up cards: the collection with a team of
five, and a duel replay against a fixed team. Nothing is tracked or sent; it's only there to
see the look in WoW. `/bestiary` or `/bst` opens it.

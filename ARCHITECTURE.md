# Bestiary: design

A collectible auto battler fed by your real WoW play: the mobs you kill can drop trophy cards
of themselves. You prepare three squads of five from your collection; in a duel both players
secretly pick one, and the squads fight on their own. Every card is Tank, Mage or Assassin,
and those counter each other like rock, paper, scissors, so guessing what the other side sends
matters as much as having strong cards. Optional hardcore: when your character dies, your
bestiary dies.

Status: design only, nothing built. Sections marked **Open** still need a decision; everything
else is the current proposal and can be changed.

---

## 1. Core loop

1. Play WoW normally. Mobs you kill can drop a **card** of that mob.
2. Getting the same card again **levels it up** instead of giving a copy.
3. Build **three squads** of five cards. Every card is **Tank, Mage or Assassin** (3.5);
   squads mix them however you like. Families (beast, undead, ...) give bonuses when you
   field several of one kind.
4. **Duel** another player: both secretly pick one of their squads, then the two fight
   automatically and you watch the replay. Bring the squad that counters theirs and you win
   easily; get read and you lose.
5. Wins earn rating and small rewards; your collection is what you build up over time.

The building part is choosing what to hunt: want a dragonkin team, go farm whelps in the
Wetlands and wyrmkin in the Swamp of Sorrows.

## 2. What the addon can see

**The combat log is closed to addons on this client** (Midnight-style restrictions:
registering `COMBAT_LOG_EVENT_UNFILTERED` is forbidden and gets the addon blocked), and unit
values can be *secret* (`issecretvalue`), mostly in combat and instances. Everything comes from
the unit API on units we can see, and secret values are skipped, never compared or stored.

| What | How | Notes |
|---|---|---|
| A mob died that we killed | Whichever comes first: a mob that was fighting us (`UnitThreatSituation`, or it targets us or our pet) seen dead as target, focus, mouseover or nameplate (also when its nameplate goes away); looting its corpse (`GetLootSourceInfo`); `PARTY_KILL` if the client sends it | Counted once per mob. `PARTY_KILL` alone didn't work in the client. GUID gives the NPC id; skipped if secret |
| Mob name, level, elite/rare, creature type | `UnitName`, `UnitLevel`, `UnitClassification`, `UnitCreatureType` while it's target, mouseover, focus or nameplate; cached by NPC id | A mob never seen that way has no data: no drop |
| Tapped by someone else | `UnitIsTapDenied` while cached | Tapped-away mobs give nothing |
| Fighting time | Every 0.5 s: visible mobs with `UnitAffectingCombat` | Study time (4.0) |
| What the mob did | Casts of visible mobs: `UNIT_SPELLCAST_START` / `_SUCCEEDED` / `_CHANNEL_START` (counted even when the spell is secret) plus their cast bar every 0.5 s (`UnitCastingInfo` / `UnitChannelInfo`: name and icon), each cast once; heals by name; `UnitPowerType` (mana), `UnitClass`, `UnitAttackSpeed` | Used for its combat type (3.5); no damage numbers, schools, dodges or parries |
| Death | `PLAYER_DEAD` | Not on Feign Death. Also check `UnitIsDeadOrGhost("player")` on login for deaths while the addon was off |

## 3. Cards

### 3.1 Identity

A card is one **NPC id** (all "Defias Pillager" share one id). Stored per card:
`npcId, name, classification, family, combat type, stars (card level),
obtained (time, zone)`.

### 3.2 Stats without a database

We don't ship a mob database. A card's stats come from a formula over what we saw, so every
client computes the same numbers:

- **Power budget** from classification and stars only; **the mob's level doesn't matter**
  (decided), so a Young Wolf can be as good as a Searing Infernal of the same rarity:
  `budget = base * rarityFactor * starFactor`
  The **power** on the card (what counts against the cap) reads like a level (decided): the
  budget scaled to **0-63**, where a Legendary card with 5 stars is 63. A common 1-star card
  is 13, elite 21, rare 24, rare elite 32, boss 39; each star adds about 15%. The cap is
  100 (was 500 before the rescale). Stats still come from the budget.
  rarityFactor: normal 1, elite 1.6, rare 1.8, rare elite 2.4, boss 3.
  Stars 1-5: +15% each.
- The budget is split into **Attack / Health / Speed** by family (beasts fast, undead tanky,
  demons hard-hitting, ...) and nudged by a seeded roll on the NPC id, so two beasts of the same
  rarity still differ, always the same way for everyone.
- One **ability** per card: picked by a seeded roll on the NPC id from its family's pool (3.4).
  Elites and better get a second ability.

Duels send the card data along (npcId, classification, family, combat type, stars), so
the other side can compute the same stats even if it has never seen that mob.

### 3.3 Rarity and drop chance

| Mob | Card rarity | Drop chance per kill |
|---|---|---|
| Normal | Common | 4% |
| Elite | Uncommon | 15% |
| Rare | Rare | 100% on the first kill once studied, then 25% |
| Rare elite | Epic | 100% on the first kill once studied, then 35% |
| Boss (`worldboss` / skull level) | Legendary | 100% on the first kill once studied, then 25% |

No mob drops anything before the addon has seen its kind fighting for 10 seconds (4.0).

**Starter boost** (decided): all drop chances are x5 (500%) while you own fewer than 10
different cards, so a new collection fills up fast. After that the extra halves every 5 more
cards: x5 at 10, x3 at 15, x2 at 20, x1.5 at 25, about x1.1 at 39, gone at 40. Applied after
the farm halving (4.2); a chance never goes over 100%.
**Copies** (decided): a normal (Common) card that isn't named can be owned up to **3 times**;
getting it again gives another copy (the drop says "copy 2 of 3"), and a squad can hold as many
copies as you own. The Collection tab shows "1x" to "3x" in the top left corner; on the Squads
tab the badge counts the copies still free, and a card whose copies are all in the squad turns
grey but stays listed. Copies share stars and stamina (a duel takes the biggest loss once).
Duels check it too: at most 3 of a normal card, 1 of anything else.
After 3 copies, and for every rarer card, getting a card you have adds a star (max 5). How many copies a star needs is a balance
question for later; it depends on how much stars matter in a fight (see 5.3).

### 3.4 Families

From `UnitCreatureType`. Critters and "Not specified" don't drop cards.

| Family | Stat lean | Example abilities | Team bonus (2 / 4 of a family) |
|---|---|---|---|
| Beast | Fast | Pounce (first hit x2), Pack Hunter | +1 / +2 speed |
| Humanoid | Balanced | Shield Wall, Rally (heal ally) | +10% attack and health / +20% and +1 speed |
| Undead | Tanky | Rise Again (once at 30% HP) | the first of them to die gets back up at 20% / 40% HP (once per squad) |
| Demon | Hard-hitting | Drain Life, Sacrifice | +15% / +35% attack, lose 2% HP each turn (never below 1) |
| Dragonkin | Strong, slow | Breath (hits all) | +15% / +30% health |
| Elemental | Area damage | Overload, Shield of Stone | splash +20% / +50% (ability damage once abilities exist) |
| Giant | Very tanky, slow | Stomp (stun) | +20% / +40% health, -1 speed |
| Mechanical | Armored | Self-Repair, Overcharge | take 10% / 20% less damage |

**Implemented** (`Core/Fight.lua`): with 2 cards of a family in the squad they get the first
bonus, with 4 or more the second; only the cards of that family get it. Speed bonuses are flat
since speed runs 1-10. Shown on the Squads tab under the type counts (what each bonus does) and
on the Duel tab under each squad and when both lock in (family and count). Numbers are
placeholders for balancing.

### 3.5 Combat types: Tank, Mage, Assassin

Every card has one of three combat types. They're the rock, paper, scissors of the game, and
the counters come from how each type fights (5.2), not from a "beats" table:

| Type | How it fights | Strong against | Weak against |
|---|---|---|---|
| **Tank** | High health, slow. **Armor** takes a flat amount off every physical hit. Hits the front | Assassin: their many small hits barely get through | Mage |
| **Mage** | Fragile. Hits **ignore armor** and splash onto the next enemy | Tank: big slow targets standing together | Assassin |
| **Assassin** | Fastest. One hard strike that goes for the **back row**; armor counts triple against it | Mage: kills fragile casters before they cast | Tank |

- A squad is any mix: 3 Tank in front and 2 Mage behind is solid against Assassins and
  weak against Mage; a mixed squad is safe but never crushes.

**Healer**, a fourth type outside the triangle: support that strengthens whatever squad it's in.

| Type | How it fights | Strong against | Weak against |
|---|---|---|---|
| **Healer** | Built like Mage (fragile, medium speed, the same stats), but never deals damage: where Mage hits the front enemy and splashes the one behind, a Healer heals the ally with the lowest health share and splashes half that heal onto the ally behind it. Each of its heals is 10% weaker than the one before, so fights don't stall | Tank squads: their slow steady damage is easy to heal through | Assassins (healers stand at the back, where they strike); Mage splash outpaces healing |

- **No limit** on Healers per squad. More Healers means less damage: a squad of only Healers
  can't hurt anyone and loses on the round limit (5.2).
- Placement matters: in the middle, behind the tanks, but not back-most where Assassins strike
  first.
- A Healer leader: all heals +20%.
- A perfect counter should win clearly, but stronger cards still matter a little (target:
  a full counter squad wins about 80% at equal power; to be tuned in the headless tests).

**Which type a card gets:** from what the mob did while you fought it (4.0).

### 3.6 Your own card (decided)

Every character starts with a card of **themselves**, created on first login with the addon:
your name, your own 3D model as the portrait, family Humanoid, type from your class (Warrior
and Paladin Tank, Rogue and Hunter Assassin, Priest and Druid Healer, Mage, Warlock and Shaman
Mage). It counts as **named**, so it's your first leader, but it's **not strong**: Common
rarity, 1 star, it never gains stars. Saved under NPC id 0 (`Core/Squads.lua`).

## 4. Getting cards

### 4.0 Studying a mob: 10 seconds of watching it fight before any card (rule)

**A mob can never drop a card until the addon has seen that kind of mob fighting for 10
seconds.** Cards aren't made up from a table: they're built from what the addon saw the mob do.

(First decided as "10 seconds of combat log data". The combat log turned out to be closed to
addons on this client, see 2, so it's now fighting time seen through the unit API.)

- **Only fighting time counts,** not time standing next to it: every 0.5 seconds, each mob we
  can see (target, mouseover, focus, nameplates) that's alive and in combat adds 0.5 seconds
  to its kind. A mob killed in one hit adds almost nothing.
- It adds up **per mob type (NPC id)** across fights and across different mobs of that type,
  per character: three Defias Pillagers fighting for 4 seconds each is 12 seconds, enough.
- Progress shows in the bestiary: "Defias Pillager: studied 7 / 10 s".
- **What the fighting records:**
  - level, classification and creature type
  - every spell it cast (name, spell id, whether it's a heal, by name)
  - whether it uses mana, its NPC class, its attack speed
  - zone
- **Once past 10 seconds, the card can be built** from what was recorded (and refined by later
  fights until it first drops; from then on it's fixed):
  - **Combat type**, the first that fits:
    - Healer: at least 2 heal casts and a third or more of its casts heal (Healer stats are
      Mage's).
    - Mage: uses mana (or its NPC class is a mana class: paladin, mage, ...) and cast at
      least 2 spells; or cast at least 3 spells at 1 or more per 10 seconds, mana or not.
    - By NPC class: mage, warlock, priest Mage; rogue, hunter Assassin. (NPC classes only say
      how a mob uses resources: "paladin" is any mana user, often a casting beast, so it
      doesn't mean Tank.)
    - Assassin: fast attacks (under 1.8 s). Tank: slow, heavy attacks (over 2.6 s).
    - Otherwise its family's lean.
  - **Ability** (after the prototype) from its signature spell (the one it cast most). Mobs
    that cast nothing get a melee ability from their type and family.
  - **Art:** the creature's **3D portrait** (decided; icons rarely showed the actual creature),
    zoomed onto its face like the target frame. The game can draw any creature it has seen
    by NPC id (`PlayerModel:SetCreature`), so nothing has to be captured or stored. While the
    model loads, or if it can't, the icon of its signature spell (or its family) shows. In
    scrolling lists a model only shows while its card is fully in view.
    The portrait stands still (animation frozen) inside a round frame. Models can't be cut
    round, so the frame is drawn above the model with the addon's own textures
    (`Media/RingCover.tga`, `Media/RingBorder.tga`): a cover in the card's color hides the
    model's corners outside the circle, and the ring in the rarity color sits on top. **Leaders** get the dragon ring around it, like an elite's portrait.
  - Stats from the formula (3.2).
- From then on, kills of that mob type can drop the card with the chances in 3.3, starting
  with the kill after the 10 seconds are reached.
- Since it's built from what **you** saw, two players' Defias Pillager cards can differ a
  little. Duels send the card data along (3.2), so that doesn't matter for fighting.
- **Rares and bosses** usually fight for more than 10 seconds, so one proper fight studies
  them; their first kill after that drops the card for sure (3.3).
- **Everything counts** (decided): a mob fighting anyone you can see is knowledge about it. A
  dungeon run studies the boss for the whole group at once, and watching a mob fight someone
  else (on its nameplate) teaches you about it too. Only the drop needs your group's kill (4.1).

### 4.1 Counting a kill

A kill counts if: we (or our pet) damaged it, it wasn't tapped by someone else, and it isn't
a critter. The mob's level doesn't matter: grey mobs (no XP) drop cards like any other, so a
level 60 can still go back and hunt the Young Wolf they're missing. Farming them quickly is
held back by the rules in 4.2, not by level.

Group kills count for everyone who damaged the mob, so dungeons with friends are fun. Drop
chance x0.75 in a 5-man group, x0.25 in a raid (to be balanced).

### 4.2 Against farming

- Same NPC id: drop chance halves for every card dropped from it within the last hour.
- **No daily cap** (decided).

### 4.3 Loot luck

Dropped for now: unclear what it would add. Can come back if cards need another source.

## 5. Squads and battle

### 5.1 Squads

You prepare **three squads**, in order, front to back, with **no minimum or maximum size**: only the power cap counts (decided; at most 7 fit under the cap of 100, since the weakest card has power 13). Dropping a card onto another card in the squad swaps the two; a card from the collection dropped onto one takes its slot. **Leaders**
(decided): only cards of **named mobs** lead, a named card always leads its squad, and a squad
holds at most one; a squad doesn't need a leader (decided: named cards are hard to get), but at most one. The game has no
"named" flag, so named means: **Rare, Rare Elite and Boss** (skull level, or in the boss
frames during a dungeon or raid encounter; once seen as a boss it stays one), plus a **manual
list of known named mobs** (`Core/Named.lua`, by NPC id or English name): named elites and
quest mobs like Hogger, Gath'Ilzogg, Mor'Ladim, Stitches, and the bosses of the early
dungeons. Their rarity doesn't change (Hogger stays an Uncommon card), they just lead.
The leader's bonus goes to allies of its combat type (6.1). Front cards get
attacked first, except by Assassins (back row) and splash. A card can be in more than one
squad. You can change your squads any time, but a duel uses the squad you locked in for it.

### 5.2 Fight rules (proposal)

Deterministic, so both clients produce the same fight without talking during it: no damage
rolls at all, and an own seeded random generator (seeded from the duel id, not `math.random`)
only breaks ties and decides chance abilities. Same code and protocol version on both sides;
the result comes from the simulation, never from the network.

**Stats.** Every card has **Health**, **Attack** and **Speed**; Tank cards also have
**Armor**. The power budget (3.2) is split by combat type, then nudged by family:

| Type | Health | Attack | Speed | Armor |
|---|---|---|---|---|
| Tank | high | low | slow (3) | 40% of its Attack |
| Mage | low | high | medium (5) | none |
| Assassin | medium-low | medium | fast (8) | none |

Speed runs from 1 to 10: the type's speed, one up or down by a seeded roll on the NPC id.
Cards show no level (decided): the mob's level doesn't count for anything.

**Start of the fight.** Squads stand in their order, position 1 in front. The twist (6.2) and
leader abilities (6.1) apply, then "start of fight" abilities.

**One attack per card per round** (decided), unless an ability says otherwise. A Mage's splash
is part of its one attack, a Healer's half heal part of its one heal.

**Rounds** (decided). At most 20. The cards pair up, one of each player per pair, and **speed
decides who acts first**, not position: each side's cards line up fastest first (ties: the
front-most), the fastest of each side form the first pair, and the faster card of a pair acts
first (ties: a seeded coin flip). If one squad is bigger, its extra cards act one after another
at the end of the round. Dead cards skip their turn. Position still decides who gets hit.

**Actions by type:**
- **Tank:** one hit for its Attack against the enemy's **front** card.
- **Mage:** one spell for its Attack against the enemy's **front** card, **ignoring armor**,
  plus a **splash** for half its Attack on the card right behind it (also ignoring armor).
- **Assassin:** **one strike** for 160% of its Attack against the enemy's **back-most** card.
  Armor counts **three times** against it: precise strikes look for gaps, and armor closes
  them.
- **Healer:** like Mage, but on its own side and healing instead of damage: heals the living
  ally with the lowest health share for its Attack, plus half that on the living ally right
  behind it, never above their maximum. Each of its heals is 10% weaker than the one before.
  It never deals damage; with nobody hurt it does nothing that turn.

**Damage.** Physical hits lose the target's Armor value, minimum 1: a Tank's hit once, an
Assassin's strike three times. Mage ignores armor. So an Assassin's 35-point strike does 35
to a caster but only 35 - 3 x 7 = 14 to a tank with Armor 7. (Tuned with headless runs: every
matchup goes the triangle's way in 50 of 50 seeds at 150, 400 and 900 power.)

**Abilities.** One trait per card from its family's pool, plus the leader ability. Triggers:
start of fight, on attack, below 50% health (once), on death, every 3rd round. Chance-based
abilities use the seeded generator.

**End.** A side with no living cards loses. After 20 rounds: the side with more health left in
percent of its total wins; equal is a draw.

**After the fight.** Each card's health lost in percent sets its stamina loss (6.3).

**Why the triangle holds:**
- **Tank beats Assassin:** armor counts three times against their strikes.
- **Assassin beats Mage:** Assassins are fast and strike the back row hard, where the fragile
  casters stand, and casters have no armor.
- **Mage beats Tank:** spells ignore armor, and the splash hits the second tank standing
  right behind the first.
- **Placement adds counterplay:** an Tank card at the very back is a bodyguard against
  Assassins, who then strike armor instead of casters. A Mage card in front is safe from
  Assassins for a while but takes every Tank and Mage hit. Mixed squads soften every
  counter.

### 5.3 Where the strategy is

This decides whether building a squad is interesting, and it's also the answer to balancing
duels (6). Levers a player can pull, all before the fight (it's an auto battler):

- **Order:** who stands in front takes the hits; back cards with ranged or area abilities
  are safe until the front falls. Tanky front, damage behind, or a fast striker up front to
  kill something before it acts.
- **Speed:** turn order. Fast cards act first in their pair, so a fast high-damage card can
  remove an enemy before it acts; slow tanks act late but survive.
- **Family bonuses:** 2 or 4 of a family trade flexibility for a strong bonus.
- **Combat types:** the Tank / Mage / Assassin mix of a squad (3.5), and which of your
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

Next step: implement the rules from 5.2 and test them headless with many random squads: the
triangle has to hold (each type beats the one it should), mixed squads should land in between,
and no single squad should beat everything.

### 5.4 Example fight

Twist: Calm Waters (none). Numbers are illustrative.

**Alice's Tank wall**, front to back:
1. Skeletal Warder (Undead, Tank, rare elite, **leader**: all Tank cards +2 armor): Health 160, Attack
   14, Speed 3, Armor 6+2 = 8
2. Harvest Watcher (Mechanical, Tank): Health 110, Attack 12, Speed 2, Armor 5+2 = 7
3. Defias Pillager (Humanoid, Mage): Health 55, Attack 26, Speed 5

**Bob's Assassin pack**, front to back:
1. Plainstrider (Beast, Assassin): Health 60, Attack 18 (strikes 29), Speed 9
2. Kolkar Centaur (Humanoid, Assassin, rare, **leader**: Assassins +2 speed in round 1): Health 80,
   Attack 22 (strikes 35), Speed 7
3. Thunderhawk Cloudscraper (Beast, Assassin): Health 65, Attack 20 (strikes 32), Speed 8

**Round 1.** Fastest first on each side, in pairs: Plainstrider (9) and Pillager (5), Kolkar
(7 + 2 leader bonus) and Warder (3), Thunderhawk (8) and Watcher (2).
- Plainstrider strikes Alice's back-most card, the **Pillager** (no armor): 29 (55 → 26).
- Pillager casts on the Plainstrider for 26 (60 → 34) and splashes the Kolkar for 13 (→ 67).
- Kolkar strikes the Pillager for 35: **dead** after a single cast (Assassin beats Mage).
- Warder hits the Plainstrider for 14 (→ 20).
- Thunderhawk strikes the new back-most, the Watcher: 32 - 3 x 7 = 11 (110 → 99).
- Watcher hits the Plainstrider for 12 (→ 8).

**Rounds 2-6.** Against the tanks the Assassins get 8 to 14 through per strike, about **25 per
round instead of 96** without armor (Tank beats Assassin). The tanks hit 26 per round: the
Plainstrider dies in round 2, the Kolkar in round 5. The Watcher falls in round 6.

**Rounds 7-9.** Only the Warder is left, Armor 8: the Thunderhawk gets 32 - 24 = 8 through per
round and dies in round 9.

**Alice wins** with the Warder at about 136 of 160 health. Stamina: Warder -9 (lost 15%),
Watcher and Pillager -60 (died).

**Had Bob sent his Mage squad instead:** spells ignore the Warder's 8 armor, and every splash
hits the Watcher right behind it, so both tanks melt at once. Alice's only answer, the
Pillager, gets a single cast off before the casters trade it away. That's the hidden pick:
Alice built well against Assassins and would be crushed by Mage.

## 6. Duels

Both players pick one of their three squads **without seeing the other's pick**. To keep it
hidden even though the addon sends everything over whispers, it uses a commit and reveal with
as few messages as possible: **4 whispers per duel** (implemented, `Core/Duel.lua`,
`Core/Comm.lua`):

1. **A → B `C|version|id|nonce`**: the challenge. The nonce sets the twist, so both see it
   before picking.
2. **B → A `A|id|commit`**: B accepted and picked in secret. The commit is a hash of B's squad
   plus a secret salt, so B can't change it any more.
3. **A → B `R|id|squad`**: A picks and shows its squad right away. No hash needed: B is already
   bound.
4. **B → A `S|id|squad|salt`**: B shows its squad; A checks it against the commit.

Both clients then run the same fight with the challenger as side 1 and a seed from the nonce
and the salt (neither side could choose it), so **no result is sent**. Also `D|id|reason`
(declined, busy, version) and `X|id` (cancelled).

- **Lost whispers** heal without extra traffic in the normal case: nothing is acknowledged on
  its own, a message is only sent again when the reply it waits for doesn't come (challenge
  after 30 and 75 s, accept once after 90 s, reveal after 8, 18 and 30 s), and a repeated
  message gets the same answer again. A lost accept is healed by the repeated challenge.
- **Cheating:** a squad that doesn't match its commit or breaks the rules (size, cap,
  one leader), or an opponent who doesn't reveal after seeing ours, loses by forfeit.
- **Limits:** B has 2 minutes to pick and accept, A 2.5 minutes after that; both players have
  to be online. Same faction only (whispers). Squads go as "npcId,stars,type,rarity,family,
  flags,name"; a message over 255 characters goes in parts.
- **Tested headless** with simulated clients over a lossy network: every message lost once,
  everything duplicated, cheating, rule-breaking squads, no answer, no pick, a sore loser,
  offline players, other versions, both challenging at once, long names, hidden (secret)
  message contents, a third player meddling, cross-realm names; 300 duels at 15% loss, 10%
  duplicates and up to 3 s delay: no duel ever ended with different results on the two
  sides, 5 whispers per duel on average. And two complete clients dueling through the UI.

**Open:** duels while the other player is offline (like Quiz Duel), each step waiting until
they're back. That needs the commits saved and both reveals to wait; the live version first.

**What you know about your opponent:** nothing about their squads before the fight, only the
twist (6.2). Reading them comes from knowing the player and what they sent before.

**Open:** best of 3 (each round both send one squad, a squad can't be sent twice) instead of a
single fight.

Messages go through a paced queue like Grandma's Game Box's Box/Comm.lua (copied, since this
is its own addon): burst then 1 per second, deduplicated, offline players retried rarely.

**Fairness:** the hidden pick and the type triangle already mean the stronger collection
doesn't simply win. On top, the **power cap** (decided, 5.3): the challenger picks the cap,
and the squads both send must fit under it, like the points limit of a Warcry warband. Each of
your three squads can be built for a different cap, or you rebuild before locking in. **For now the cap is fixed at 100** (decided) and can't be picked; the cap button on the
Squads tab is greyed out.

Rating: simple Elo per opponent and overall, per character.

### 6.1 Ideas from Warhammer Warcry

Warcry's roster building fits this game. What we take from it:

| Warcry | In Bestiary | Proposal |
|---|---|---|
| Points limit per warband | Power cap per duel; cards cost their power; fixed at 100 for now (later maybe a choice of caps) | **Decided** |
| Warband size varies | No size rule, only the power cap limits it (one strong card up to 7 weak ones) | **Decided** |
| A leader is required | The named card (Rare, Rare Elite, Boss) always leads; at most one per squad; a leader isn't required (named cards are hard to get) | **Decided** |
| Runemarks (keywords abilities refer to) | Family and combat type are the keywords abilities refer to ("other Undead get +armor") | **Decided** |
| Battleplan and twist cards | Each duel draws a twist, revealed at the challenge before both pick (6.2) | **Decided** |
| Limits on allies and monsters | At most one named card (so at most one Legendary); no per-card limit beyond the cap | **Decided** |
| Campaign: injuries | Cards get worn out and sit out duels: stamina (6.3) | **Decided** |
| Campaign: experience | Cards gaining XP from duels | Not for now |
| Battle groups (Dagger / Shield / Hammer) | Reserves joining later | **No**: too complicated |
| Wild dice fuel abilities | A seeded roll per round that fuels abilities | **No** |

Squad sizes change 5.1: a squad is any number of cards that fits the cap, front to back, led by its named card if it has one.

### 6.2 Twists

The duel id seeds a twist drawn from a list; it's shown with the challenge, so both players
know it **before** picking and building. It changes which squad is the right one each time,
so the same three squads don't always win. Examples:

- **Fog:** Assassins hit 50% harder in round 1.
- **Consecrated Ground:** Undead have no armor.
- **Ambush:** everyone hits the back row first.
- **Ley Lines:** Mage splash hits two enemies behind the target.
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

### 6.4 Bestiary friends and the board (decided)

**Only Bestiary friends duel each other** and share the board. Adding a friend by name sends a
request (`F|ask`); they get a popup and answer `F|ok` or `F|no`. If both asked each other,
it's a yes on its own. A friendship costs 2 whispers (request, yes).
Removing a friend only takes them off your list. Challenges from players who aren't your
friend are declined ("not friends"), and the challenge button refuses them. Friends have their own
**Friends tab** (`UI/Friends.lua`): add by name or your target; one row per player with the
status (friend, asked, wants to be your friend), your duel record against them and when you
last heard from them, and buttons: Duel / Remove, Accept / Decline, or Ask again / Cancel.

A **Board** tab with short posts (up to 200 characters) shared with your friends. Everyone edits and deletes
only their own posts. Saved account wide (`BestiaryAccount.board`, `Core/Board.lua`,
`UI/Board.lua`). Every post version carries the server time it was written; the newest wins,
a deletion leaves a marker so it syncs too, and posts older than 60 days are dropped
everywhere by the same rule.

**Nothing syncs on its own** (decided): posts, edits and deletes stay on your side until you
press **Sync now** on the Board tab. Then, with as few whispers as possible, only with friends:
- Each friend gets a fingerprint of your board, taken at a given time, plus when you were
  last in sync with them. Same fingerprint: no answer, so 1 whisper per friend. Different:
  they send everything they stored after that time, as one message (in parts if long), and
  answer with their own fingerprint, so you send what they lack the same way: one click
  syncs both sides (4 whispers when both have something new). Nothing they sent you is sent
  back to them.
- Posts travel on: if you share with Bob and Bob with Cid, Cid's posts reach you through Bob.
  Only messages from your contacts are accepted.
- **Tested headless** with up to four simulated clients: online and offline posting, catching
  up on login, edit and delete, only authors change posts, relaying, strangers ignored, long
  posts, old versions never win, both posting while apart (4 whispers to sync); 50 fuzz
  rounds of four players in a ring with 20% loss and random offline times: every board ended
  up the same. And through the UI of two complete clients.

## 7. Hardcore

- **Opt-in** when you start a bestiary on a character: Normal or Hardcore. Can't switch a
  running bestiary to Hardcore later (so nobody collects safely and then switches).
- Hardcore perks: drop chance x1.5, a separate rating, a skull on your cards in duels.
- When the character dies (`PLAYER_DEAD`, or found dead/ghost on login): the bestiary is
  **gone**. It moves to a "Hall of the Fallen" (per account): character, level, days survived,
  card count, best card, duel record. You can start a new one.
- Hardcore means complete loss **of the cards**, on purpose; that's its only death penalty.
  **What you've studied stays** (decided): you still know those mobs. Your own card (3.6)
  stays too, back to 1 star.
- **Implemented (prototype):** a checkbox on the Test tab, per character, with a
  confirmation (`Core/Hardcore.lua`). Feign Death doesn't count, the same death isn't counted
  twice, and a death while the addon was off is caught at the next login. Each loss is saved in
  `BestiaryAccount.fallen` for the Hall of the Fallen. The opt-in lock and the perks above
  come later; for now it can be switched any time.
- **Normal bestiaries:** no penalty when you die.

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
- **Drop alert** when a card drops, like the game's loss of control alert (decided; the first
  loot-window version sat in the top left corner and went unnoticed): a dark band centered in
  the upper half of the screen with the card's art, "New card" or "+1 star", its name in the
  rarity color, type, rarity, family and power. Shows right away, stays 4 seconds, then fades;
  more drops queue up. Hover keeps it and shows the card, click opens the collection. Rare
  drops louder.
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
- Combat types Tank, Mage, Assassin per card; squads mix them freely (3.5). Plus Healer:
  works like Mage but heals the lowest ally instead of damaging, never deals damage, no
  limit per squad (3.5, 5.2).
- No card before 10 seconds of seeing that mob type fight (across fights; first decided as
  combat log data, which addons can't read on this client); cards are built from that (4.0).
- Mob level and XP don't matter for drops (grey mobs drop cards, 4.1) or for card power (3.2).
- Studying counts the mob fighting anyone, as long as we can see it (4.0).
- No daily drop cap (4.2).
- Starter boost: drops x5 under 10 cards, then fading with diminishing returns, gone at 40 (3.3).
- No abilities in the first prototype: cards have type, stats and leader bonuses only.
- Drops show as an alert like the loss of control alert, centered in the upper half (9).
- Three prepared squads per player; both pick one in secret before a duel (6).
- A perfect counter wins easily (3.5).
- Power cap per duel, picked by the challenger (6). **For now one fixed cap of 100** (decided);
  picking a cap comes later.
- From Warcry: squad size limited only by the power cap, a leader, keywords, twists, roster limits, cards getting
  worn out (6.1). No battle groups, no wild dice, no XP for now.
- Stamina per card: drained by health lost in duels, refilled by resting, 2 duels out at 0
  (6.3).
- You see nothing of the opponent's squads before the fight, only the twist (6).
- Death: hardcore loses the whole bestiary; normal has no penalty (7).

## 12. Open questions

1. Fight rules: the proposal in 5.2, then balance with headless runs.
2. Single fight or best of 3 (6).
3. Cap sizes beyond the fixed 100 (6); stamina numbers (6.3).
4. Stars: how many copies per star (3.3), after 1.
5. Abilities, after the prototype.

## 13. Prototype (no more mockup)

`Bestiary.toc` loads:

- **Collection tab (prototype, real data):** the tracker (`Core/Tracker.lua`, unit API only)
  studies every mob type it sees fighting; after 10 seconds a kill can drop its card
  (`Core/Cards.lua`). The card's type comes from what the mob did, its art from its signature
  spell. The tab shows your cards and the mob types you're still studying with progress.
  Drops show the drop alert (`UI/Loot.lua`). Saved per character in `BestiaryChar`,
  mob info account-wide in `BestiaryAccount`.
- **Squads tab (real cards):** three squads of your own cards, saved per character
  (`BestiaryChar.squads`, `Core/Squads.lua`), built by drag and drop from your collection;
  power bar, type and family counts, checks. A card you lose drops out of its squads.
- **Duel tab (real cards):** twist, hidden pick (switch freely, drag to reorder, Ready locks it
  in), replay, stamina saved on your real cards. **Challenge target** (or `/bst duel [name]`)
  starts a duel with another player who has Bestiary: they get a popup, pick first, then you
  (protocol in 6). Without one, "New duel" fights the **Sparring
  Partner**: three squads (Tank, Mage and Assassin heavy) of mobs you've seen (not named ones),
  random stars, built up to about your own squads' average power; with fewer than 7 seen mobs
  it uses training cards. The fight (`Core/Fight.lua`) follows 5.2 with Healers and family
  bonuses (3.4). Rules shared by everything are in `Core/Rules.lua`.
- **Studying tab** (arcane eye): the mob types you're studying, most studied first, with
  progress, the card it would give so far and casts seen; hover for details (`UI/Studying.lua`).
  The Collection tab only shows cards now.
- **Stats tab:** duel record, streaks, by squad and twist; leaderboards of your cards (heavy
  hitters, healers, walls, killers, best of the duel, fell the most) and the enemy cards that
  hurt you most; hunting (kills, drops, drop rate, study time) and the collection by rarity,
  type and family. Recorded in `BestiaryChar.stats` (`Core/Stats.lua`) from every finished
  duel, kill and real drop (test drops don't count). `/bst stats`.
- **Info tab:** the rules explained (getting cards, rarity, combat types with leader bonuses,
  family bonuses, leaders, squads, the fight, twists, stamina), built from the same tables and
  numbers the code uses (`UI/Info.lua`), so it stays right while balancing. `/bst info`.
- **Test tab (prototype):** pick a mob (your target or one from the list of mobs seen), see
  the card its next drop would give and everything recorded about it (type and why, drop
  chance), show its drop alert without keeping it, give, rebuild (type and art from today's
  data, stars kept) or remove its card, or
  force a drop on the next kill (skips studying and the roll once, this session only), or
  set the drop chance to 90% until the next drop (studied mobs only, this session only).
  Also: clear the collection (with a confirmation; your own card and study stay), fill it
  with 5 basic cards (common, 1 star: 2 Tank, Mage, Assassin, Healer; not counted as drops),
  and the hardcore checkbox (7).
- `/bst` opens it, `/bst mob` prints everything known about your target's mob type, `/bst
  debug` prints kills and drop rolls, `/bst test` opens the Test tab.

To check in the game client: which unit values are secret in open world combat (if
`UnitAffectingCombat` or GUIDs are secret, studying only works out of the restricted cases),
whether `PARTY_KILL` fires for our kills and pet kills, whether mob spell casts show up
(spell ids secret?), how dungeon bosses report (elite, skull level), UnitCreatureType names in
the client's language, how the drop alert looks.

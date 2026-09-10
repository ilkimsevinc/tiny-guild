# Milestone 8: manual missions
> Milestone 9 adds default Energy retreats: Slime Nest and Treasure Trail now stop
> after four encounters. Full-run totals below describe completion rewards; the
> milestone 8 regression suite explicitly sets its Energy threshold to zero to
> retain that coverage. See milestone9.md for current default gameplay.


Normal launch starts Arthur at `IDLE_AT_GUILD`, without an enemy. The Expedition
Board opens initially and remains available from its button while Arthur is idle.
Select a mission and press SEND ARTHUR. No mission starts or repeats automatically.

## Files and responsibilities

- `scripts/mission_data.gd`: reusable Resource with identity, region/type, difficulty,
  level recommendation, encounter count, completion rewards, enemy pool, loot
  profile/modifiers, duration text, description, and tags.
- `data/missions/{forest_patrol,slime_nest,treasure_trail}.tres`: mission definitions.
- `scripts/mission_run.gd`: UI-independent lifecycle, encounter progress, combat
  reward totals, completion reward claim, and per-run loot IDs/quantities with
  shared ItemData references. `accumulated_gold/xp` are combat-only totals;
  `total_gold()/total_xp()` include completion rewards.
- `scripts/expedition_panel.gd` and `scenes/expedition_panel.tscn`: scrollable mission
  entries, selected details, recommendation warning, dispatch, and summary/CONTINUE.
- `scripts/main.gd` and `scenes/main.tscn`: connect the run to existing combat,
  rewards, pickup, encounter delay, Guild status, board, and return presentation.
- `scripts/arthur.gd`: adds a Guild assignment status, separate from combat states.
- `scripts/loot_table.gd`: scoped weighted rolls over the existing item table.
- `scripts/item_data.gd`: reward descriptions now cover encounters and completion.
- `tests/milestone8_check.gd`: mission lifecycle, UI, combat, reward, and loot tests.
- `tests/milestone3_check.gd` through `tests/milestone7_check.gd`: explicitly opt into
  debug endless combat before adding Main, preserving their original assertions.

## Mission definitions

All missions use Whispering Forest, the existing Slime loot profile, and Slimes
with the existing 30 HP. Difficulty and recommended level are descriptive;
underlevel dispatch displays a warning but is allowed.

| ID | Name | Difficulty | Recommended level | Encounters | Completion Gold | Completion XP | Duration | Loot identity |
|---|---|---|---:|---:|---:|---:|---|---|
| forest_patrol | Forest Patrol | EASY | 1 | 3 | 30 | 30 | Short | Balanced / Common |
| slime_nest | Slime Nest | MEDIUM | 2 | 6 | 70 | 60 | Medium | Higher Slime loot chance |
| treasure_trail | Treasure Trail | HARD | 3 | 8 | 40 | 80 | Long | Higher equipment rarity chance |

Descriptions:

- Forest Patrol: Patrol the edge of Whispering Forest and clear nearby Slimes.
- Slime Nest: A dense Slime colony has formed near the old forest trail.
- Treasure Trail: Follow an old treasure route through a dangerous section of the forest.

## Loot modifiers

One item or no item is rolled per encounter. No quantity bonus is added.
Weights are normalized by their sum; this is a relative weight bonus, not a
percentage-point bonus to a probability. Shared item data and base rates never mutate.

| Mission | Gel | Sword | Shield | Ring (Rare) | Crown (Epic) | No drop |
|---|---:|---:|---:|---:|---:|---:|
| Forest Patrol | 50 | 20 | 15 | 5 | 1 | 9 |
| Slime Nest | 62.5 | 25 | 18.75 | 6.25 | 1.25 | 9 |
| Treasure Trail | 50 | 20 | 15 | 7.5 | 1.5 | 9 |

Slime Nest multiplies all item weights by 1.25: overall item chance rises from
91% to approximately 92.67%. Treasure Trail multiplies Rare-or-higher weights
by 1.5: Rare+ chance rises from 6% to approximately 8.74%. Common drops and no
item remain possible. Normal rolls preserve the original seeded integer behavior.

## Rewards and lifecycle

Every Slime grants base 10 Gold and 15 XP. Completion is additional:

```
Gold = round(base_gold * (1 + equipment_gold_percent / 100) * guild_gold_multiplier)
XP   = round(base_xp   * (1 + equipment_xp_percent   / 100) * guild_xp_multiplier)
```

Use the appropriate encounter or completion base value. Round once, at the end,
to the nearest integer, with positive halves upward. Main uses the same reward
helpers and RewardCalculator for both sources; popups and summary only display
already-calculated values. Current class skills affect combat stats as before.
Modifiers are evaluated when each reward is earned; changing equipment during a
run affects later rewards, and the summary retains the amounts actually earned.

Without modifiers, complete mission totals are Forest 60 Gold/75 XP, Nest
130 Gold/150 XP, Treasure 120 Gold/200 XP. With Ring, Crown, and both tiers of
Economy/Training mastery, each encounter grants 12 Gold/18 XP. Nest completion
adds 81 Gold/73 XP, for run totals of 153 Gold/181 XP.

Run states: IDLE -> PREPARING -> IN_PROGRESS -> COMPLETED -> RETURNING -> IDLE.
PREPARING is immediate. There is a two-second delay between encounters. The
final defeat awards completion exactly once and stops spawns. Arthur collects
remaining ground loot through normal movement/pickup, then returns after a
one-second delay. Summary appears after return. CONTINUE acknowledges it and
reopens the board; SEND ARTHUR is required for the next run. Dispatch is blocked
throughout the mission, return, and unacknowledged summary.

The old endless loop is accessible only through `debug_combat_mode = true`
before Main enters the tree, and only in a debug build. No normal gameplay
control enables it. No Tokens are awarded; Repeat Orders stays unimplemented.

## Manual testing

1. Import/open `project.godot` in Godot 4.7.2 and press F5.
2. Wait a few seconds: Arthur stays Idle At Guild, Gold stays zero, no Slime appears.
3. Inspect all three entries (scroll the left list) and select Treasure Trail to
   see its underlevel warning. SEND remains enabled.
4. Select Forest Patrol and SEND ARTHUR. Board hides, Encounter 1/3 appears,
   and existing movement/attacks begin. Another mission cannot be dispatched.
5. Let all three encounters finish. Watch pickups, MISSION COMPLETE, Returning,
   then the summary. Without gear/mastery expect combat 30 Gold/45 XP plus
   completion 30 Gold/30 XP, total 60 Gold/75 XP. Loot varies with RNG.
6. Compare summary loot with inventory. The last drop must be included.
7. Wait: nothing repeats. Press CONTINUE to return to the board.
8. Complete Slime Nest (six encounters), then Treasure Trail (eight encounters).
   Their details show scoped loot modifiers. Drop probabilities require many
   trials to observe; deterministic automated tests verify exact weights.
9. For reward stacking, F9 grants equipment; equip Slime Ring and Slime Crown.
   F11 grants 1000 Gold; buy both Coin Pouch and Shared Experience tiers under
   Guild Mastery. Nest should award 153 Gold/181 XP across the entire mission.
10. Confirm Class Skills and Guild Mastery still work independently.

Debug controls only: F6 next Rare, F7 next Epic, F8 defeat current encounter,
F9 test items, F10 +500 Gold, F11 +1000 Gold, F12 +10 Guild Tokens. F8 still
uses normal death, reward, loot, progress, and return paths; press it again
only after the next encounter spawns.

## Automated testing and limits

With the Godot console executable on PATH, run from the project directory:

```powershell
3..8 | ForEach-Object {
    godot --headless --path . --script "res://tests/milestone${_}_check.gd"
}
godot --headless --path . --script res://tests/class_foundation_check.gd
godot --path . --script res://tests/milestone8_check.gd
```

The last command uses rendered mouse input; it fights Forest Patrol normally
and uses debug encounter defeats to check all six/eight encounters of the other
missions. Tests also verify actual underlevel dispatch and scoped RNG integration.

Progress remains session-only. Only the Slime enemy/profile is executable;
unsupported pools are rejected. Difficulty does not scale enemy stats yet.
The return delay is a placeholder, and final pickup assumes all current drops
are reachable on the flat arena. Special mission systems, cancellation/failure, persistence,
party selection, and automation beyond this milestone are intentionally absent.

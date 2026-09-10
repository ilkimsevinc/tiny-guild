# Milestone 10: rotating opportunities and the Ancient Treant

## Files

Created scripts:
- `enemy_data.gd`: enemy HP, rewards, type, loot profile and placeholder presentation.
- `encounter_data.gd`: one enemy plus an encounter Energy cost.
- `completion_loot_table.gd`: independent data-driven completion-only item rolls.
- `mission_instance.gd`: runtime identity, definition reference, timestamps,
  countdown, modifiers, special type, seed, claimed/active state and manual flag.
- `mission_rotation_config.gd`: refresh, mission pool, weights and expiration values.
- `mission_board_rotation.gd`: exactly one opportunity slot, weighted spawning,
  expiration, claim validation, timer signals and debug controls.
- `tests/milestone10_check.gd`: rotation, expiry, mixed combat, loot and UI tests.

Created data:
- `data/rotation/default.tres`
- `data/missions/forest_supply_run.tres`, `elite_slime_outbreak.tres`, `ancient_treant.tres`
- `data/enemies/slime.tres`, `ancient_treant.tres`
- `data/items/ancient_bark.tres`, `treant_heart.tres`, `rootbound_relic.tres`
- `data/loot/ancient_treant_completion.tres`
- This document and generated script UID files.

Modified scripts: `main.gd`, `slime.gd`, `mission_data.gd`, `mission_run.gd`,
`stop_condition_evaluator.gd`, `loot_table.gd`, `item_data.gd`, `expedition_panel.gd`.
Modified scenes: `main.tscn`, `expedition_panel.tscn`.

## Board and instance lifecycle

The three persistent missions remain unchanged below a single rotating slot.
An opportunity is generated at launch, but Arthur is never dispatched automatically.
All three special types are temporarily eligible immediately, without unlocks.

Production configuration:

| Type | Spawn weight | Expiration |
|---|---:|---:|
| Normal opportunity | 65% | 20 minutes |
| Elite | 25% | 20 minutes |
| Boss Portal | 10% | 60 minutes |

The refresh interval is 300 seconds (five minutes). An unclaimed, unexpired
opportunity is retained across refresh ticks: a 60-minute portal is not silently
replaced after five minutes. An expired inactive slot becomes empty and schedules
its next refill five minutes later. Claiming consumes the opportunity and leaves
an empty slot until the next scheduled refresh; that slot may refill while Arthur
is away. There is still only one rotating board slot.

MissionInstance references static MissionData, rather than mutating it. Spawned
instances get a unique session ID, seeded completion RNG, and their own modifier
dictionary. `spawned_at`/`expires_at` use monotonic elapsed session seconds, not
wall-clock calendar dates. The injectable clock makes expiration tests deterministic.
The countdown reads current time, including after the instance has been claimed;
UI updates once per second, not once per frame.

Dispatch validates current slot identity, claim state and expiration at click time.
An expired or stale selection cannot start even before the next timer tick.
Successful dispatch detaches the claimed instance from the slot and stores it in
MissionRun. Expiration never cancels that run. On return, active becomes false but
claimed remains true; the same instance cannot be replayed. All special missions
expose `requires_manual_attention = true`.

## Special missions

| Mission | Type / difficulty | Recommended level | Encounters | Energy | Completion Gold / XP |
|---|---|---:|---|---|---:|
| Forest Supply Run | NORMAL / MEDIUM | 2 | 4 Slimes | 16 each, 64 total | 50 / 40 |
| Elite Slime Outbreak | ELITE / HARD | 3 | 6 Slimes | 18 each, 108 total | 120 / 100 |
| Ancient Treant | BOSS / HARD | 4 | Slime, Slime, Ancient Treant | 15, 15, 25; 55 total | 250 / 180 |

All are in Whispering Forest. Supply Run completes at 36 Energy from full Energy.
Elite normally retreats after encounter four at 28 Energy with default limits;
its improved encounter loot is still kept. The boss mission can complete at
45 Energy. Predictions use the actual mixed encounter costs and existing stop
configuration; a BOSS THREAT label is descriptive and never blocks dispatch.

Exact encounter loot weights, ordered Gel / Sword / Shield / Ring / Crown / None:

- Base: `50 / 20 / 15 / 5 / 1 / 9`.
- Supply Run: `62.5 / 20 / 15 / 5 / 1 / 9` (materials x1.25). Gel probability
  increases from 50% to approximately 55.56% after normalization.
- Elite: `50 / 20 / 15 / 15 / 3 / 9` (Rare+ x3). Ring is 15/112 = approximately
  13.39%; Crown is 3/112 = approximately 2.68%. Neither is guaranteed.

Modifiers are instance-owned and passed to the existing loot roll. Base mission
loot and the existing global table remain unchanged.

## Boss implementation and loot

EnemyData drives the existing `slime.gd` damage and feedback implementation; there
is no second combat system. The retained Slime scene/controller names keep legacy
combat tests compatible, but they now accept enemy data. Ancient Treant uses
150 HP, a brown branching polygon, and 1.6x visual scale. Hit/death feedback returns
to that configured scale. It never attacks Arthur.

The two Slimes retain 10 Gold / 15 XP encounter rewards. The Treant has configured
0 Gold / 0 XP encounter rewards and no encounter loot. Its payout is the mission
completion reward plus the completion-only table:

| Item | Type | Rarity | Independent completion chance |
|---|---|---|---:|
| Ancient Bark | Material | Rare | 100% |
| Treant Heart | Relic Material (not equippable) | Epic | 15% |
| Rootbound Relic | Relic | Legendary | 3% |

Each chance uses an integer roll 0..99. Rolls are independent: Bark always drops,
and both optional items may drop together. Rootbound Relic is equippable through
the existing Relic slot, but has no implemented stat power yet. No crafting or
consumable system is added.

The completion claim guards both currency rewards and boss loot. Loot is dropped,
collected through the existing pickup path, stored in Inventory and included in
the run summary before returning. A duplicate completion callback cannot reroll.
Retreat before killing the Treant keeps encounter rewards/loot but earns no
completion bonus, Bark, Heart or Relic roll.

Without reward modifiers, a successful boss run totals 270 Gold / 210 XP.
Existing equipment and Guild multipliers still apply through RewardCalculator,
once per currency reward with final integer rounding. No Guild Tokens are added.

## Debug controls

Only debug builds respond to these keys; focus the running game:

| Key | Action |
|---|---|
| 1 | Force a weighted random refresh |
| 2 | Force Forest Supply Run |
| 3 | Force Elite Slime Outbreak |
| 4 | Force Ancient Treant Boss Portal |
| 5 | Set the active opportunity's expiration to five seconds; otherwise the slot's |
| 6 | Toggle refresh interval between ten seconds and the configured normal value |
| 0 | Set Arthur Energy to 40 for retreat testing |
| F8 | Defeat the current encounter through normal rewards/Energy/checkpoints |

Fast refresh still retains unexpired opportunities. Use 5 to expire an idle
opportunity, then observe the empty slot refill after the accelerated interval.
Existing F6/F7 loot overrides, F9 test items, F10/F11 Gold and F12 Tokens remain.

## Future Portal Mastery and limits

The rotation config owns timing, eligible mission pool and weights, providing
integration points for faster refresh, longer notices and future unlocks. Runtime
instances own expiration/claim state, where a future pinning rule can be added.
The board controller isolates slot storage from combat for later expansion.
No second slot, pinning mechanic, new Mastery purchase or automation is implemented.
Notice Board and Repeat Orders remain disabled future data.

Temporary technical debt: Elite and Boss are immediately unlocked for testing;
later progression should gate them. All state is session-only. Rootbound Relic
has no power yet, the boss has no attack AI, and Guild recovery remains instant.
Existing flat-arena pickup assumptions still apply. No save/offline/OS-notification
or automatic mission selection behavior is added.

## Manual Godot testing

1. Open `project.godot` in Godot 4.7.2 and press F5. Verify Arthur is idle and the
   three base missions remain in the scrollable list below the rotating slot.
2. Press 2, select the opportunity, inspect Supply Run and its 20-minute countdown.
3. Press 3. Verify the Elite label, notification, loot identity and retreat risk.
4. Press 4. Verify BOSS PORTAL, recommended Level 4, 15+15+25 Energy, 250 Gold/
   180 XP completion reward and the three possible unique items on the card.
5. Select the Boss card and SEND ARTHUR. Watch Slime, Slime, then the larger
   150-HP Ancient Treant. Let Arthur fight or use F8 once per spawned encounter.
6. Complete the mission. Verify Ancient Bark in Inventory and summary. Heart and
   Relic are random; one run does not verify their probabilities.
7. Press CONTINUE, then 4 and 0. Dispatch the new portal with 40 Energy. After the
   first Slime, Arthur retreats at 25 Energy. Confirm no new boss completion loot.
8. At Guild, press 4 then 5 and wait five seconds without dispatching. Verify the
   slot empties and that the expired opportunity cannot start. Base missions remain.
9. Press 4, select and dispatch, then press 5 while active. After five seconds,
   confirm the expedition continues and can still finish normally.
10. Try 6 plus 5 while idle to test accelerated expiration/refill; press 6 again
    to restore the normal interval. No debug refresh should auto-dispatch Arthur.

## Repeatable tests

With the Godot console executable on PATH as `godot`:

```powershell
3..10 | ForEach-Object {
    godot --headless --path . --script "res://tests/milestone${_}_check.gd"
}
godot --headless --path . --script res://tests/class_foundation_check.gd
godot --path . --script res://tests/milestone10_check.gd
```

Milestone 10 uses injected time for exact boundaries, checks all 100 weighted
outcomes/probability thresholds, verifies real Elite loot integration, fights the
boss naturally, and uses a known seed to verify all completion drops together.
Rendered mode uses actual mouse clicks and captures board/combat/summary images
under `.godot/`. Earlier milestone suites retain their existing coverage.

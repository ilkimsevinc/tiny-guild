# Milestone 9: Energy, stop conditions, and retreat

Arthur starts with 100/100 Energy, separate from HP, and still waits for manual
mission selection. Completed encounters consume Energy; walking, attacks, loot
pickup, and level-ups do not consume or restore Energy.

## Files

Created:
- `scripts/expedition_stop_config.gd`: configurable Resource, owned independently
  by each MissionRun. Contains thresholds, capacity, safety cap, and enable flags.
- `scripts/stop_condition_evaluator.gd`: pure snapshot evaluation returning
  `should_stop` and a reason enum, plus readable reasons and Energy/cap prediction.
- `tests/milestone9_check.gd`: defaults, boundary conditions, actual mission
  outcomes, reward preservation, recovery, and rendered UI tests.
- This document and generated script UID files.

Modified:
- `scripts/arthur.gd`: current/max Energy, clamping, consumption, Guild recovery,
  and an expedition snapshot using current total HP (including existing bonuses).
- `scripts/mission_data.gd` and the three `data/missions/*.tres` resources: Energy
  cost per encounter. No mission-specific costs are hard-coded in Arthur.
- `scripts/mission_run.gd`: post-pickup checkpoint, RETREATED state, persistent
  result/reason/ending Energy, carried units, and completion reward eligibility.
- `scripts/main.gd`: deduct Energy before rewards, await pickup, evaluate the
  checkpoint, return through the shared completion/retreat path, and recover.
- `scenes/main.tscn`: always-visible Energy text/bar.
- `scripts/expedition_panel.gd`: costs, estimates, risk warning, and both summaries.
- `tests/milestone8_check.gd`: explicit checkpoint resolution in controller tests;
  sets Energy return threshold to zero only for legacy full-run reward coverage.
- `docs/milestone8.md`: marks historical full-run expectations accordingly.

## Default configuration

| Setting | Default | Behavior |
|---|---:|---|
| min_energy_percent | 0.35 | Stop strictly below 35% of Max Energy |
| min_hp_percent | 0.45 | Stop strictly below 45% of total Max HP |
| inventory_capacity | 10 | Count item units collected during this run |
| inventory_return_percent | 0.80 | Stop at or above 8/10 units, if enabled |
| inventory_stop_enabled | false | Disabled in normal play to avoid random retreat timing |
| encounter_cap | 8 | Stop after eight completed encounters if mission remains unfinished |
| return_on_hero_downed | true | Evaluator supports HP <= 0; no death gameplay added |

At exactly 35 Energy, the Energy condition does not trigger. At exactly 45% HP,
the HP condition does not trigger. Inventory counts quantities, not unique item
IDs, and ignores items already owned or granted directly by debug controls.

Reason priority: HERO_DOWNED, HP_LOW, ENERGY_LOW, INVENTORY_LIMIT, ENCOUNTER_CAP.
NONE means continue. NO_CONSUMABLES is a definition only and never triggers.
HP/hero-down checks are supported by the evaluator but cannot naturally trigger
with current non-attacking Slimes. No enemy attacks or consumable behavior exists.

## Exact outcomes from full Energy

| Mission | Cost per encounter | Energy after completed encounters | Outcome |
|---|---:|---|---|
| Forest Patrol | 15 | 85, 70, 55 | COMPLETED at 3/3 |
| Slime Nest | 18 | 82, 64, 46, 28 | RETREATED at 4/6, ENERGY_LOW |
| Treasure Trail | 20 | 80, 60, 40, 20 | RETREATED at 4/8, ENERGY_LOW |

Energy clamps to 0..Max Energy. Completing the final encounter takes precedence
over stop thresholds: an already-finished mission earns completion rewards,
even if its final Energy is low. The eight-encounter cap therefore does not
turn a finished eight-encounter mission into a retreat.

## Checkpoint and return flow

1. Slime death deducts the mission's Energy cost once.
2. Normal encounter Gold/XP and loot roll occur with existing modifiers.
3. MissionRun records the completed encounter. No next spawn is allowed while
   its checkpoint is pending.
4. Arthur collects pending ground loot through existing movement/pickup.
5. MissionRun resolves the checkpoint: complete if finished; otherwise evaluate
   stop conditions from Arthur's snapshot and run-specific carried units.
6. If continuing, start the existing two-second encounter delay.
7. On retreat, preserve result RETREATED and stop reason, show EXPEDITION STOPPED,
   and enter the same short return presentation as completion.
8. On arrival, restore Energy to Max Energy before allowing another mission.
   The summary retains ending Energy and outcome even though current Energy is full.
9. CONTINUE acknowledges the summary. Another manual SEND ARTHUR is required.

No evaluation interrupts an active fight. Return states are transient, while
`result_status`, `stop_reason`, `ending_energy`, completed encounters, rewards,
and loot survive through RETURNING and IDLE until the next run starts.

## Rewards

Retreat keeps all earned encounter Gold, XP, and collected loot. It never awards
completion Gold or XP. The existing RewardCalculator still applies equipment and
Guild modifiers exactly once and rounds once at the end (positive halves up).

Without bonuses: Forest totals 60 Gold/75 XP; either energy-retreated long mission
keeps 40 Gold/60 XP from four encounters. With Slime Ring, Slime Crown, and full
Economy/Training mastery, a four-encounter retreat keeps 48 Gold/72 XP. Completion
rewards remain zero. Inventory and run summary both include the final pickup.

## Prediction and future integration

The board shows per-encounter and estimated total Energy, current Energy, and the
return threshold. Prediction walks through the unfinished encounter checkpoints
using current Energy and the configured cap/threshold. It labels Forest LIKELY TO
COMPLETE and the longer missions RISK OF RETREAT at default values. It does not
simulate combat power or random inventory; warnings never block dispatch.

Future Mastery can modify `mission_run.stop_config` values for HP thresholds,
capacity thresholds, or encounter cap. Neither UI nor Slime code owns those
thresholds. No new Mastery node, exception consumable, Repeat Orders, or automation
has been added. Existing class skills and Guild reward modifiers remain separate.

## Manual Godot test

1. Open `project.godot` with Godot 4.7.2 and press F5.
2. Confirm Idle At Guild, no enemy, and Energy 100/100 with a 35% return threshold.
3. Select Forest Patrol. Confirm 15 Energy each, 45 total, LIKELY TO COMPLETE.
4. SEND ARTHUR. Watch 85, 70, 55 after fights; confirm 3/3 completion.
5. Verify completion reward 30 Gold/30 XP plus normal combat rewards. Arrival
   restores Energy to 100; summary still records ending Energy 55.
6. CONTINUE, select Slime Nest. Confirm RISK OF RETREAT and 18 Energy each.
7. Dispatch and watch 82, 64, 46, 28. After pickup at 4/6, Arthur retreats;
   encounter 5 must never spawn.
8. Verify EXPEDITION ENDED, RETREATED, Low Energy, ending Energy 28, and completion
   reward NOT EARNED. Without bonuses expect combat 40 Gold/60 XP; verify loot
   remains in inventory and Energy is now 100.
9. CONTINUE and send Treasure Trail. Verify 80, 60, 40, 20, retreat at 4/8,
   retained rewards, and full Energy on return.
10. Wait after CONTINUE: no mission repeats. Select and send the next one manually.

Existing debug controls remain: F6 next Rare, F7 next Epic, F8 defeat current
encounter, F9 grant test items, F10 +500 Gold, F11 +1000 Gold, F12 +10 Tokens.
F8 follows the normal Energy/reward/pickup/checkpoint flow. No extra debug key is
needed; Energy can also be edited through Godot's Remote Inspector while testing.

## Tests and remaining limitations

Repeatable checks, with Godot's console executable available as `godot`:

```powershell
3..9 | ForEach-Object {
    godot --headless --path . --script "res://tests/milestone${_}_check.gd"
}
godot --headless --path . --script res://tests/class_foundation_check.gd
godot --path . --script res://tests/milestone9_check.gd
```

The rendered test uses actual mouse dispatch/CONTINUE, normal Forest combat, and
F8 for deterministic long-mission retreat checks. HP, inventory, cap, downed,
threshold boundaries, and final-encounter precedence have isolated tests.
Milestone 8 deliberately uses a zero Energy threshold to retain its full six/eight
encounter reward coverage; milestone 9 tests the production defaults.

Temporary technical debt: instant full Guild Energy recovery must later be
replaced by a designed rest system. Progress remains session-only. Pickup waits
assume the current unobstructed arena. Risk prediction covers Energy/cap only.
Inventory stops are implemented but opt-in, and HP stops have no natural trigger
until a later combat milestone. No automatic rest/dispatch or other future system
is activated.

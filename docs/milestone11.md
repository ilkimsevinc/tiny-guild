# Milestone 11 - Repeat Orders

Repeat Orders is an optional 250 Gold Guild Mastery unlock. It only repeats persistent missions whose MissionData.repeatable flag is enabled; rotating, Elite, Boss, and future special missions remain manual.

RepeatOrderState owns the session state: repeat enabled, mission ID, run count, stop reason, and pending restart. A successful run returns Arthur, deposits loot, restores Energy to 100, shows its summary for 1.75 seconds, waits 2 seconds, and redispatches the same mission. Instant Energy recovery is temporary until Scheduled Rest replaces it.

Retreat, future terminal failure results, changing missions, or STOP REPEAT end the session. Player cancellation never interrupts the active combat run. Special mission spawns remain visible without changing the repeated mission.

Debug controls: F10 grants 500 Gold, F8 defeats the current encounter, F4 prints/displays repeat state, and F5 stops repeat after the current mission.

## Manual verification

1. Run the project and press F10 if fewer than 250 Gold are available.
2. Open Guild Mastery, choose Repeat Orders, and buy it.
3. Open the Expedition Board, choose Forest Patrol, enable Repeat Mission, and send Arthur.
4. Use F8 on each encounter. Confirm the summary appears briefly, Arthur returns, Energy reaches 100, and Forest Patrol starts as Repeat Run 2.
5. Let multiple runs finish and verify Gold, XP, and Inventory loot increase once per run.
6. During a run press STOP REPEAT (or F5), finish it, and verify no next run starts.
7. Choose Slime Nest, enable repeat, send Arthur, press 0 to set Energy to 40, then F8. Confirm the Low Energy retreat stops repeat and does not redispatch.
8. Press 3 and select the Elite opportunity; confirm Repeat Mission is disabled with the special-mission explanation.
9. Press 4 and select the Boss Portal; confirm Repeat Mission remains disabled.
10. Start Forest Patrol repeat again, press 4 during combat, and confirm the Boss Portal notification appears without interrupting Forest Patrol.
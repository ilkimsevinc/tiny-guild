# Milestone 13 - Mission Queue / Expedition Orders

Mission Queue (`mission_queue`, 10,000 Gold + 1 Guild Token, requires Repeat Orders and Scheduled Rest) lets the player line up to 3 persistent missions that the Guild runs in order. The queue never picks or scores missions. It only follows the player's orders.

## Architecture

- `MissionQueueState` (`scripts/mission_queue_state.gd`, node in `main.tscn`) holds the entries, `enabled`/`paused`/`pause_reason`, `current_index`, `completed_entries`, `active_entry`, `session_run_count`, `stop_requested`, and the future `pause_after_current_requested` hook. Unlock state is read from `GuildMasteryState`. `capacity()` is `BASE_CAPACITY` (3) + `capacity_bonus` (a hook for a future mastery).
- `MissionQueueEntry` stores `mission_id`, `mission_instance_id` (reserved), `display_name`, `repeat_count`, `completed_count`, and a status: PENDING / ACTIVE / COMPLETED / SKIPPED / BLOCKED.
- `QueueSessionSummary` adds up each finished `MissionRun`: Gold, XP, loot, completed missions, retreats, and encounters. Individual run summaries are unchanged.
- `main.gd` dispatches (`start_queue`, `resume_queue`, `stop_queue`, `_handle_queue_return`). Rest between orders uses the existing `EnergyRecovery` / Scheduled Rest path.

## Rules

- Only persistent BASE missions can be queued: Forest Patrol, Slime Nest, and Treasure Trail. Rotating, Elite, Boss, and future Anomaly missions stay manual.
- START QUEUE dispatches the first entry right away at Arthur's current Energy. After each COMPLETED run, the result shows for 1.5 s, Arthur rests to READY if needed, then the next entry starts after the 2 s preparation delay.
- A RETREATED run (and future FAILED/HERO_DOWNED results) pauses the whole queue. The entry is marked BLOCKED and stays incomplete. RESUME QUEUE retries it from encounter 1, or waits for READY if Arthur is resting.
- STOP QUEUE during a mission lets that mission finish, then ends the session. The configured orders are kept until CLEAR.
- Edits: every entry can be edited while the queue is inactive. During a session, only future PENDING entries can be edited.
- While the queue is running it owns dispatch: SEND ARTHUR, opportunities, and Repeat Orders are blocked, and Repeat Mission shows "Repeat Orders unavailable while Expedition Orders are active." A paused queue allows one-off missions.
- Opportunities keep spawning and expiring, and notifications still appear. The queue never switches to them.
- The queue is session-only. There is no save/load yet.

Note: Treasure Trail (8 x 20 Energy) always retreats from 100 Energy under the 35% return threshold, so a queue containing it pauses there.

## Debug (debug builds only)

F10/F11 Gold | F12 +10 Guild Tokens | 7 recovery x10 | 8 Full Energy | 9 pause queue after the current mission (future Boss hook) | F4 print repeat/recovery/queue state | F8 defeat encounter | 4 force Boss Portal

## Manual verification

1. Press F11 x11 and F12. In Guild Mastery, confirm Mission Queue is LOCKED. Buy Repeat Orders, then Scheduled Rest, then Mission Queue.
2. On the Expedition Board, press ADD TO QUEUE on Forest Patrol twice, then on Treasure Trail. Check the order, and try UP/DOWN/REMOVE.
3. Press 7, then START QUEUE. Use F8 per encounter. Entry 1 shows [x], Arthur rests, then entry 2 starts automatically.
4. Treasure Trail retreats: QUEUE PAUSED with a reason. For a clean completion, queue Forest Patrol x3 and confirm EXPEDITION ORDERS COMPLETE with 3 / 3 and the totals.
5. Queue Forest Patrol and Slime Nest. Slime Nest retreats and the queue pauses, with no automatic rest and no next entry. Press CONTINUE, REST, then RESUME QUEUE, and confirm Slime Nest restarts at encounter 1.
6. Start another queue, press 4 during a mission, and confirm the Boss Portal notification appears while the queue keeps going.
7. Press STOP QUEUE during a mission. The mission finishes and no next order starts.

# MILESTONE 18 (proposed) — SAVE / LOAD

**Status: not yet implemented — this is a spec, written to be handed back and executed the same way Milestones 3–17 were.**

Continue developing the Tiny Guild Godot 4.7.2 project.

Current implemented systems: reusable HeroData/HeroController, Arthur and Mimi, PartyState, combat roles and formation, centralized targeting, missions, rotating Normal/Elite/Boss missions, Energy, stop conditions, Rest/Scheduled Rest, Repeat Orders, Mission Queue, Guild Greybox Interior, hero Guild idle presence, Development/Desktop presentation modes, inventory/equipment, class Skill Trees, Guild Mastery.

Existing Milestone 3–17 tests should continue to pass.

## Design goal

Nothing survives closing the window today. For a desktop idle RPG this is the single biggest gap: the "idle" fantasy requires the Guild to still be there — Gold, heroes, gear, mastery — the next time the player opens it. This milestone makes that true, without yet attempting **offline progression** (simulating time passed while closed). Offline progression is explicitly a separate, later milestone (it needs its own bounded-hours/efficiency design already sketched in the Guild Mastery doc); this milestone only needs the game to resume exactly where the player left it.

## 1. Scope: what gets saved

A single save file captures:

- **Wallet**: Gold, Guild Tokens.
- **Inventory**: every carried item (id + quantity), resolved back to `ItemData` resources on load.
- **Guild Mastery**: `unlocked_ids`.
- **Per hero** (Arthur, Mimi, and any future roster member — iterate `main.heroes`, don't hard-code names):
  - Progression: level, xp, xp_required, damage, max_hp, current_hp.
  - current_energy.
  - Equipment: which item id (if any) is in each slot.
  - Skill Tree: `unlocked_ids`.
  - Guild zone: which zone they're standing in, so the Guild doesn't reset to default positions every load (cosmetic, but cheap).
- **Party selection**: which heroes are currently ticked for dispatch (`PartyState.hero_ids`).
- **Mission board rotation**: the current rotating slot (mission id, special_type, spawned_at/expires_at, seed) and the next-refresh timer, so a Boss Portal the player was saving up for doesn't just vanish on reload.
- **Presentation** (optional, nice-to-have): last used mode (Development/Desktop) and, if Desktop, the last window position, so a taskbar-pet session reopens where it was left.

## 2. Explicitly out of scope for this milestone

State that is either mid-flight or genuinely complex to resume safely is **not** persisted in v1. Document this plainly in the UI rather than silently losing it:

- **An in-progress `MissionRun`.** If the game is closed while a hero is `ON_EXPEDITION` or `RETURNING`, do not try to resume the exact encounter, slime HP, or ground loot on load. On load, any hero who was mid-expedition is placed back `IDLE_AT_GUILD` with the Energy/HP they had at the last checkpoint before departure (i.e., roll back to their Guild-side stats, not their moment-of-close combat stats — those were never checkpointed either). This is a deliberate simplification; a later Offline Progression milestone is the right place to actually resolve missions that were running while the game was closed.
- **Repeat Orders and Mission Queue sessions.** Do not persist `repeat_enabled`/queue entries as still-running. On load, both come back in their default (off / empty) state. The player re-arms them — this avoids the much harder problem of resuming automation mid-cycle with correct timers.
- **Rest in progress.** A hero who was `RESTING` loads back as `IDLE_AT_GUILD` at their last-known Energy (not auto-continued, not auto-stopped-and-penalized). Scheduled Rest is a Guild Mastery automation the player already owns, so nothing is lost — they just need to see the board once.
- **Boss/Elite notification banners, floating text, in-flight tweens** — pure presentation, never serialized.
- **Multiple save slots, cloud sync, Steam Cloud.** One local save file only.

## 3. File format & location

- Plain JSON (not `ResourceSaver`/`.tres`) written to Godot's standard per-user data directory: `user://save.json`. JSON is chosen over Godot's binary resource format because it survives script/class renames across future milestones without needing custom resource-loader shims, and it's trivial to inspect/hand-edit while debugging.
- Top-level `schema_version: int`. Bump it whenever the save shape changes. `SaveManager.load_game()` should refuse (not crash) on a version it doesn't recognize, and log clearly rather than silently discarding save data.
- Items/mastery nodes/skill nodes are saved **by id string**, never by embedding the resource — on load, re-resolve through the existing data-driven lookups (`loot_table`, `guild_mastery.tree.find_node`, `skills.tree.find_node`, etc.), consistent with this project's existing "data-driven, id-based" pattern everywhere else.

## 4. `SaveManager`

A new node (`scripts/save_manager.gd`, added to `main.tscn` alongside the other state nodes — `GoldWallet`, `Inventory`, `GuildMastery`, etc.) is the single place that knows how to walk the tree and build/apply the save Dictionary. Do not scatter `FileAccess` calls through `main.gd` — every other cross-cutting concern in this project (presentation, targeting, party) already gets its own dedicated controller node; save/load should follow the same pattern.

- `func gather() -> Dictionary` — reads current state into a plain Dictionary (JSON-safe types only: String/int/float/bool/Array/Dictionary).
- `func apply(data: Dictionary) -> void` — writes a gathered Dictionary back into every live system. Must be safe to call once, right after `_ready()`, before the player can interact with anything.
- `func save_to_disk() -> bool`, `func load_from_disk() -> Dictionary` (empty Dictionary if no save file exists yet — this is the normal "first launch" case, not an error).
- `func has_save() -> bool`.

## 5. Save triggers

- **Manual**: a `SAVE` button, reachable from both Development and Desktop HUDs (Desktop: fold into the existing compact HUD button row, e.g. next to MASTERY).
- **Automatic**: on every Guild Mastery purchase, skill node purchase, and mission return-to-Guild (i.e., whenever the player would be upset to lose the last few minutes). Do not autosave on every single frame or every Energy tick — that's wasted disk I/O for no player-visible benefit.
- **On quit**: hook `NOTIFICATION_WM_CLOSE_REQUEST` (and the Desktop-mode `X` button already added in Milestone 17) to save before the window actually closes.

## 6. Load flow

- On launch, if `SaveManager.has_save()`, load it in `_ready()` before the first frame the player can act on (i.e., before `_apply_view`/HUD build), so there's no flash of default state.
- If no save exists, proceed exactly as today (fresh Arthur + Mimi, 0 Gold) — first launch must be unaffected.
- No "New Game" confirmation flow is needed yet (single slot, no menu) — loading is just "continue where you left off, or start fresh if there's nothing to load."

## 7. Preserve existing systems

Do not break: Guild interior, Guild zones, hero idle movement, departure/return, Rest, Scheduled Rest, Repeat Orders, Mission Queue, missions, rotating missions, Elite/Boss portals, party formation, targeting, Gold/XP, loot, inventory, equipment, Skill Trees, Guild Mastery, stop conditions, retreat, Development/Desktop presentation modes.

## 8. Do not implement yet

- Offline progression (computing what happened while the game was closed) — separate milestone, needs the bounded-hours/efficiency design from the Guild Mastery doc.
- Multiple save slots, manual export/import, cloud save.
- Resuming a mid-flight `MissionRun`, Repeat Orders session, or Mission Queue session (see §2).
- Save-corruption recovery UI beyond "refuse a save with an unrecognized schema_version and log why."

## 9. Automated tests

Add `tests/milestone18_check.gd`. Verify:

A. `SaveManager.has_save()` is false on a fresh project (no save file).
B. `gather()` → `save_to_disk()` → a **new** `Main` instance → `load_from_disk()` → `apply()` reproduces Gold, Guild Tokens, and inventory contents exactly.
C. Per-hero level/xp/damage/max_hp/current_hp/current_energy round-trip exactly for both Arthur and Mimi.
D. Equipped items round-trip to the correct slot on the correct hero (equip different items on Arthur vs Mimi, confirm no cross-contamination after reload).
E. Guild Mastery `unlocked_ids` round-trip, and derived values (`global_gold_multiplier`, `scheduled_rest_owned` via `RepeatOrderState`) are correct afterward.
F. Skill Tree `unlocked_ids` round-trip per hero.
G. Party selection (`hero_ids`) round-trips.
H. Mission board rotation slot (mission id, special_type, expires_at) round-trips and the countdown continues sensibly (not reset to full duration).
I. A hero who was `ON_EXPEDITION` when saved loads back `IDLE_AT_GUILD` with their pre-departure Energy/HP, not mid-combat state (§2 rule, verified explicitly, not just assumed).
J. Repeat Orders and Mission Queue come back **off/empty** after a load, even if they were active when saved (§2 rule, verified explicitly).
K. Loading a Dictionary with an unrecognized `schema_version` is refused without crashing, and existing state is left untouched.
L. Autosave fires after a Guild Mastery purchase, a skill purchase, and a mission return (assert `save_to_disk` was invoked — e.g. via a debug counter — not just that the file's mtime changed).
M. Loading with no save file present leaves a fresh game exactly as it is today (Arthur + Mimi at their scene defaults, 0 Gold) — this is the regression guard that first-launch behavior didn't change.
N. Existing Milestone 3–17 suites still pass.

## 10. Debug support

- A debug key to force-save and force-load on demand (pick an unused key — checked against the Milestone 17 debug key list first).
- A debug key or F4-style print to dump the current `gather()` Dictionary (or its size/keys) for inspection.
- A debug action to delete the save file, for testing the "fresh launch" path without reinstalling.

## 11. Manual test flow

1. Launch the game fresh (no save file). Confirm behavior is unchanged from today.
2. Grant some Gold/XP via debug keys, buy a Guild Mastery node and a Skill node, equip an item on Arthur, run a mission to completion.
3. Press SAVE (or quit and relaunch, to test the on-quit autosave).
4. Confirm on relaunch: Gold, the purchased nodes, the equipped item, and hero levels are all exactly as left.
5. Start a mission, and while it's `ON_EXPEDITION`, quit and relaunch. Confirm the hero is back `IDLE_AT_GUILD` at their pre-departure Energy (not stuck mid-mission, not crashed).
6. Enable Repeat Orders, quit mid-session, relaunch. Confirm Repeat Orders is off and the player can re-arm it manually.
7. Force a Boss Portal to spawn, quit before claiming it, relaunch. Confirm the portal is still there with a sensible remaining countdown.
8. Switch to Desktop mode, press SAVE, quit, relaunch. Confirm the game starts back in Desktop mode at the same window position (if that QoL item was implemented).

## 12. Final report

After implementation, provide: files created/modified, the save file format (with an example JSON snippet), exactly what is/isn't persisted (and why, referencing §2), save-trigger points, load-flow timing, debug controls, test results, remaining technical debt, and exact manual test steps.

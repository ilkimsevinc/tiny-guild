# Milestone 14 - Multi-Hero Foundation + Mimi

Tiny Guild now has a reusable hero layer and a two-hero party. Arthur (Knight, melee) and Mimi (Mage, ranged magic) can go out alone or together.

## Hero architecture

- `HeroData` (`scripts/hero_data.gd`, `data/heroes/*.tres`) is the static definition: `hero_id`, `display_name`, `class_id`, `combat_style` (MELEE / RANGED_MAGIC), base HP/damage, per-level growth, max Energy, attack interval, attack range, move speed, and the damage-number colour.
- `HeroController` (`scripts/hero.gd`, formerly `arthur.gd`) is the runtime hero: movement/combat state, current Energy, Guild status, and attack feedback. Melee heroes lunge. Ranged heroes stop at spell range, pulse, and fire a short-lived orb.
- Per-hero child nodes: `Progression` (`scripts/hero_progression.gd`, formerly `arthur_progression.gd`, configured from HeroData), `Equipment`, and `Skills` (the class Skill Tree loaded via `class_id`).
- Scenes: `scenes/arthur.tscn` and `scenes/mimi.tscn` share the controller and differ only in data and placeholder visuals. Adding Andre, Akane, and others later means a HeroData file, a scene, and one `_register_hero` entry. Mission and combat code are hero-agnostic.

Arthur's values are unchanged: 100 HP, 10 damage, +2 damage / +10 HP per level, 1.0 s attacks, 130 px melee. Mimi starts at 70 HP, 8 damage (+2 / +7 per level), 1.2 s attacks, 220 px range, and 160 move speed versus Arthur's 180. Her Mage tree has no nodes yet, so the Skills panel shows "No skills available for this class yet."

## Party

`PartyState` (node in `main.tscn`) holds the roster, the per-hero `EnergyRecovery`, the player's selection (`hero_ids`), the party on the current mission (`active_hero_ids`), status, and the current mission. `max_party_size()` = `BASE_PARTY_SIZE` (2) + `capacity_bonus`. The default selection is Arthur, so single-hero play behaves exactly as before.

- A hero who is resting, on an expedition, or returning cannot be newly selected. An empty party cannot be dispatched.
- Both heroes share one expedition. Split dispatch is not supported yet.

## Rules

- **XP**: every participant receives the full encounter and completion XP (no splitting). Each hero's own XP-bonus equipment applies to their own XP.
- **Gold and loot**: account-wide and paid once per enemy or mission. Loot is rolled once per enemy. Equipped Gold bonuses of all participants add together.
- **Kill credit**: one enemy death is one encounter for the party, whoever lands the last hit.
- **Energy**: each participant pays each encounter's cost. Predictions use the weakest member's Energy.
- **Stop conditions**: `MissionRun.resolve_party_checkpoint` runs the existing `StopConditionEvaluator` on every member. If any member breaches a hard stop, the party retreats.
- **Rest**: every hero has an independent `EnergyRecovery`. REST / STOP REST act on all heroes at the Guild.
- **Automation**: Repeat Orders remembers the dispatched party, and the Mission Queue uses the party selected at START QUEUE for every entry. Scheduled Rest / queue redispatch waits until every remembered member is READY. Changing the selection afterwards does not affect automation.
- **Special missions**: Elite and Boss stay manual, sent with whatever party the player selects.

## UI

- Hero roster (top right) shows each hero's class, level, status, and Energy. Clicking a hero switches the Stats / Equipment / Class Skills context. There is one set of panels, rebound per hero.
- Expedition Board: SELECT PARTY checkboxes, "Party: Arthur + Mimi", SEND PARTY, per-hero Energy lines, and a per-hero rest status.
- Mission summary lists each participant's level, XP, and ending Energy.

## Debug (debug builds only)

0 Arthur Energy=40 | F2 Mimi Energy=40 | F3 +30 Mimi XP | 7 recovery x10 (all heroes) | 8 Full Energy (all heroes) | F4 prints repeat/queue/party state | F8 defeat encounter | 4 force Boss Portal | F10/F11 Gold | F12 Tokens

## Not included

No relationships, dialogue, enemy attacks, downed heroes, per-entry queue parties, class-restricted equipment, or save/load. All state is session-only.

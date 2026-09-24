# Milestone 15 - Party Roles, Formation, and Basic Targeting

## Combat roles

`HeroData.combat_role` holds the formation intent: FRONTLINE, MELEE_DPS, RANGED_DPS, MAGE, or SUPPORT. `combat_style` stays as the attack delivery (MELEE lunge vs RANGED_MAGIC orb), so the two fields no longer overlap in meaning. A future FRONTLINE/MAGE hybrid (Regnier) can pair FRONTLINE with RANGED_MAGIC. `prefers_front()` is true for FRONTLINE and MELEE_DPS.

Arthur is FRONTLINE and Mimi is MAGE.

## Formation

`PartyFormation` (`scripts/party_formation.gd`) is an ordered list of slots with front first: SLOT_ROWS = FRONT, BACK, and MAX_SLOTS = 2 for now.

- `PartyFormation.auto(heroes)` puts front-preferring roles first and keeps roster order within each group. Arthur + Mimi gives FRONT Arthur | BACK Mimi, whatever the selection order.
- Each back slot follows the hero in the slot ahead (`leader_of`). Spacing is relative to the enemy direction, not world coordinates:
  - `BACKLINE_SPACING` = 110 px behind the hero ahead
  - `MIN_HERO_SPACING` = 56 px, never closer, even while walking
- `PartyState.formation` is the formation of the current mission. Active heroes are ordered by slot, so index 0 is the front anchor, loot walker, and party leader.
- A single hero is their own anchor. Arthur alone uses melee range; Mimi alone stops at her spell range.
- The formation is automatic by role (no swap button yet). Changing the hero context in the Stats/Equipment/Skills panels does not affect it.

## Behaviour

- **Arthur (front)** walks toward the enemy, stops at 130 px melee range, and attacks.
- **Mimi (back)** holds a slot 110 px behind Arthur on the side away from the enemy, follows him at her own slower speed, never passes the 56 px limit, and casts once she is at her slot. If a future back hero's slot is out of range, they close in but still stay behind the leader.
- **Regroup**: after each encounter checkpoint the party walks back to its formation home positions during the 2 s respawn delay. Both spawn points are now in front of the party (the missions now alternate between x=720 and a new forward spawn at x=600; the x=300 spawn is kept only for the legacy endless-combat debug mode), so every enemy is approached front-first and the formation never has to flip sides.

### Attack range adjustment

Mimi's range changed from 220 to **260 px**. With Arthur at 130 px and Mimi 110 px behind him, she stands 240 px from the enemy. That is inside 260, and the 110 px gap reads clearly as a backline. Her damage is unchanged.

## Targeting

`TargetingController` (`Targeting` node in `main.tscn`) is the only authority for encounter targets:

- `register_enemy` / `release_enemy`, with `active_target` exposed as `main.active_target`.
- Heroes receive their target via `target_for(hero)`. Every role gets the active target for now.
- Policies are ready for multi-enemy encounters: FIRST_REGISTERED (current), NEAREST, LOWEST_HP, BOSS_PRIORITY, and MARKED (player-marked).
- **Death safety**: `release_enemy` succeeds exactly once per enemy, and `_on_slime_died` refuses to run without it. Near-simultaneous hits or duplicate callbacks therefore pay Gold once, roll loot once, and advance the encounter once.

## Automation

- Repeat Orders stores `formation_slots` with the party.
- Mission Queue stores `formation_slots` at START QUEUE.

Automatic dispatches reuse the remembered formation. Energy costs, retreat thresholds, and recovery are untouched.

## UI and debug

- The board's party row shows `FRONT Arthur | BACK Mimi`.
- During a mission the status reads `Party: Arthur - FRONTLINE [FRONT] | Mimi - MAGE [BACK]`.
- Mimi's orbs fire the `orb_launched(origin, target)` signal.
- F4 debug now includes the party's formation.

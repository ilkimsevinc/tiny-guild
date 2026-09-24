# Milestone 16 - Guild Greybox Interior + Hero Idle Presence

Heroes now visibly live inside a greybox Guild when they are not on an expedition.

## Architecture

- `scenes/guild_interior.tscn` + `GuildController` (`scripts/guild_controller.gd`) builds the placeholder interior from data and manages each hero's physical presence. It never changes Energy, rest, or mission state; it only reflects them spatially.
- `GuildLayout` (`scripts/guild_layout.gd`, data in `data/guild/guild_layout.tres`) holds the zone list, the door anchors (`departure_anchor`, `return_anchor`), and the backdrop bounds.
- `GuildZoneData` (`scripts/guild_zone_data.gd`) holds `zone_id`, `display_name`, `zone_type` (GENERAL / REST / EXPEDITION_BOARD / TRAINING / TAVERN / BLACKSMITH), `anchor_position`, horizontal `left`/`right` extent, `capacity`, colour, and a placeholder note. The heroes currently in each zone are tracked at runtime in `GuildController.zone_assignments` (`assigned_heroes(zone_id)`).
- `GuildHeroAvatar` (`scripts/guild_hero_avatar.gd`) is a hero's Guild body. It uses a copy of the hero's placeholder visuals and is separate from the combat `HeroController`, so combat movement is untouched and visuals can later be swapped for sprites.
- `ViewStateController` (`scripts/view_state_controller.gd`) holds the explicit `GUILD_VIEW` / `EXPEDITION_VIEW` state, ready for future taskbar views.

## Layout (wide, horizontal side view; floor y = 350)

| Zone | Type | x range | Anchor |
|---|---|---|---|
| Tavern (reserved for Wilzaren) | TAVERN | 60-170 | 115 |
| Rest Area | REST | 170-330 | 250 |
| Social Area | GENERAL | 330-520 | 425 |
| Expedition Board | EXPEDITION_BOARD | 520-690 | 575 |
| Training | TRAINING | 690-810 | 750 |
| Blacksmith (reserved for Edward) | BLACKSMITH | 810-920 | 865 |

The Guild door (departure and return anchor) is at x = 660, inside the board zone. The Guild occupies the same stage band as combat (backdrop at 40,200 / 880x162).

## Guild states

`GuildHeroAvatar.guild_state` is one of GUILD_IDLE, GUILD_MOVING, GUILD_RESTING, GUILD_READY, or AWAY (on an expedition). It is derived from the avatar's movement plus the existing `HeroController.guild_status` (IDLE_AT_GUILD / RESTING / READY / ON_EXPEDITION / RETURNING), which is unchanged, so all Milestone 12+ logic keeps working.

## Behaviour

- **Defaults**: Arthur's home zone is Training and Mimi's is the Social Area (`HeroData.guild_home_zone`). Each stands at a spacing-safe spot near the zone anchor.
- **Idle**: every 5-12 s (seeded RNG, seed 1606), an idle hero steps up to 45 px to a free spot inside their current zone. There is no idle wandering while resting, away, moving, or held at the board by automation.
- **Spacing**: heroes stand at least 48 px apart (checked against where others are heading) and 12 px inside zone edges. Heroes may briefly pass each other while walking.
- **Rest**: when REST starts (manual or Scheduled Rest), the hero walks to the Rest Area. When rest ends (READY or STOP REST), they walk back to their home zone. Recovery itself stays in `EnergyRecovery` and starts immediately.
- **Dispatch**: SEND PARTY (or automation) starts the mission immediately, as before. The party walks to the door (0.8 s) and disappears. Encounter 1 already exists, but the party only engages once it has left, and the view switches to EXPEDITION_VIEW. Heroes not in the party stay in the Guild.
- **Return**: when the party starts home, the view switches to GUILD_VIEW. The heroes appear at the door and walk to their home zone.
- **Automation**: Repeat Orders and Mission Queue go return -> Rest Area (Scheduled Rest) -> READY -> gather at the Expedition Board during the 2 s preparation -> door -> next mission. The board overlay is hidden during automated rest so the Guild stays visible.
- **Expedition Board**: the existing panel is an overlay on the physical board. The EXPEDITION BOARD button emits `GuildController.open_expedition_board`, and CLOSE BOARD hides the overlay.
- **Views**: GUILD_VIEW shows the interior with every hero present. EXPEDITION_VIEW shows the combat stage with only the dispatched heroes.
- **Session-only**: there is no save/load. Tavern and Blacksmith are labels only.

## Debug (debug builds only)

- Z: move the context hero to the next Guild zone.
- X: freeze or unfreeze idle wandering.
- C: send all Guild heroes home.
- F4: also prints the view state and Guild zones/positions.

All earlier debug keys are unchanged.

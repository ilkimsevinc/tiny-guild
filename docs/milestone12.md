# Milestone 12 - Rest & Recovery + Scheduled Rest

Arthur no longer restores Energy instantly on return. He keeps his ending Energy and recovers through `EnergyRecovery` (`scripts/energy_recovery.gd`, the `EnergyRecovery` node in `main.tscn`).

## Recovery

- Base rate: `base_energy_recovery_per_second = 5.0`, granted once per second (`tick_seconds = 1.0`) so Energy steps 55 -> 60 -> 65, clamped at Max Energy.
- READY: `ready_threshold = 1.0` (100% of Max Energy). Only automation (Scheduled Rest) waits for READY; manual dispatch works at any Energy while Arthur is not resting.
- Modifier hooks, with no content yet: `rate_multiplier`/`bonus_rate` for permanent effects (Faster Recovery, Comfortable Quarters), `add_rate_buff`/`add_flat_recovery_buff` with an optional duration (Tavern meal +20% for 10 minutes), `set_ready_threshold` (Resting Expertise), `burst_recover` (Emergency Rest), and `pending_dispatch_energy_bonus` (Tavern drink +10 Energy on the next dispatch).

## Guild states

`arthur.guild_status` is separate from combat movement: `IDLE_AT_GUILD`, `RESTING`, `READY`, `ON_EXPEDITION`, `RETURNING`. EnergyRecovery owns the three Guild-side states and resyncs IDLE/READY whenever Energy changes at the Guild.

## Repeat Orders + Scheduled Rest

- COMPLETED repeat run, Arthur READY: redispatches after the 2 s preparation delay.
- COMPLETED repeat run, not READY, no Scheduled Rest: the session pauses ("Repeat Orders paused: Arthur needs to recover."). The player rests manually; reaching READY does not auto-resume. Manually sending the same mission continues the session.
- COMPLETED repeat run, not READY, Scheduled Rest owned: Arthur starts RESTING automatically, then redispatches the same mission 2 s after reaching READY.
- RETREATED (and future FAILED/HERO_DOWNED): Repeat Orders stops. Scheduled Rest never overrides this.

Scheduled Rest (`scheduled_rest`, 1200 Gold, requires Repeat Orders) is read from `GuildMasteryState`. `RepeatOrderState.scheduled_rest_owned` is a derived getter, not a stored flag.

## Debug (debug builds only)

0 Energy=40 | 7 toggle recovery x10 | 8 Full Energy | F4 print repeat + recovery state | F5 stop repeat | F10 +500 Gold | F11 +1000 Gold

## Manual verification

1. Send Arthur on Forest Patrol, finish it (F8 per encounter), and confirm he returns with 55/100 Energy.
2. Press CONTINUE, then REST. Status shows Resting and Energy climbs by 5 each second.
3. Press STOP REST and confirm Energy holds. Press REST again until 100 and confirm status READY.
4. Buy Repeat Orders (F10 for Gold), enable Repeat Mission on Forest Patrol, and complete a run. Repeat pauses, Arthur does not rest on his own, and after a manual rest to READY nothing auto-starts.
5. Buy Scheduled Rest (1200 Gold). Start a Forest Patrol repeat and complete it. Arthur auto-rests (press 7 to speed up) and Forest Patrol restarts about 2 s after READY.
6. Enable repeat on Slime Nest from full Energy and let it retreat at 28. Repeat Orders stops, no auto-rest or restart happens, and a manual REST still works.

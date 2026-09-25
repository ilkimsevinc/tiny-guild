# Milestone 17 - Desktop / Taskbar Window Prototype

Tiny Guild now has two presentation modes that share one running game: the full **Development** window (1280x720, unchanged) and a first **Desktop** prototype (a short 1280x320 strip, borderless, always-on-top, near the bottom of the screen). Switching between them never reloads the scene or touches gameplay state.

## Architecture

- `PresentationController` (`scripts/presentation_controller.gd`, a node in `main.tscn`) owns everything about *how* the game is shown: `Mode.DEVELOPMENT` / `Mode.DESKTOP`, the target window size, borderless/always-on-top flags, and the Guild/combat pixel offset for the current mode. No other script calls `DisplayServer` directly.
- All real window calls (`window_set_size`, `window_set_position`, `window_set_flag`, `window_set_mode`) are guarded behind `DisplayServer.get_name() != "headless"`, so the controller is fully safe to drive from headless automated tests — only the pure geometry math and game-state effects are asserted there; the real-window assertions (border, always-on-top, actual size/position) run in rendered mode.
- The window-geometry math (`clamp_window_size`, `bottom_centered_position`, `clamp_to_screen`) is implemented as **pure static functions** with no display dependency, so it is unit-tested directly.
- `project.godot`'s stretch mode changed from `canvas_items` to **`disabled`**: the root viewport always matches the OS window pixel-for-pixel in both modes. Development mode's window still defaults to exactly 1280x720, so this is a no-op there; it's what makes a 1280x320 Desktop window show a real 320px-tall slice instead of a squashed 720-tall scene.

## Development mode

Unchanged: 1280x720, decorated, not-always-on-top, the full HUD (`UI/DevHUD`), and the always-visible Guild Mastery/Inventory/Skills sidebar. All existing automated tests run in this mode (the default) and were not touched to accommodate Desktop mode.

## Desktop mode

- **Size**: 1280x320 by default (`PresentationController.desktop_size`), clamped to the usable screen (`DisplayServer.screen_get_usable_rect`) with a 320x120 floor, so it never becomes an unusable sliver on a small display and never exceeds the current monitor.
- **Position**: centered horizontally, `bottom_margin` (8px) above the bottom of the *usable* screen rect — that rect already excludes the OS taskbar, so no taskbar height is hard-coded or detected.
- **Borderless / always-on-top**: Desktop mode sets both; Development mode clears both. Toggling back to Development restores a normal decorated window.
- **Dragging**: a small "☰ TINY GUILD" handle at the top of the compact HUD is a `Control` with `gui_input` wired to `PresentationController.drag_by()`, which moves the real window and clamps it so at least 160px stays reachable on screen (`clamp_to_screen`), even if the window is dragged mostly off an edge.
- **Reset position**: `RESET WINDOW POSITION` (debug key **R**) recomputes the centered-bottom placement.
- **Minimize / Quit**: the `_` and `X` buttons in the drag bar call `DisplayServer.window_set_mode(WINDOW_MODE_MINIMIZED)` and `get_tree().quit()` — no title bar is needed.
- **Debug key M** toggles Development ↔ Desktop.

## Guild + combat presentation (the Stage trick)

A new `Stage` node (`Node2D`, child of `Main`) now holds everything that used to sit at world coordinates: `Background`, `Ground`, `Arthur`, `Mimi`, the three Slime spawn markers, and `GuildInterior`. `PresentationController.stage_offset()` returns `Vector2.ZERO` in Development mode and, in Desktop mode, shifts `Stage.position.y` just enough that the floor (world y=350) lands `desktop_floor_margin` (20px) above the bottom of the compact window, clear of the HUD strip above it.

This one offset is what makes the *same* Guild and combat code work in both windows: every hero, the Guild avatars, the Slime, and the loot magnet all read/write `global_position`, which is unaffected by a pure-translation ancestor — melee range, spell range, formation spacing, and loot pickup distance are numerically identical in both modes. The Slime and floating-text effects stay direct children of `Main` (not `Stage`, to keep existing tests that search `main.get_children()` working); their spawn positions are taken from the Stage-child spawn markers' `global_position` so they land in the correct place regardless of the current offset.

A narrower-than-1280 Desktop window (a small monitor) rescales the *same* six Guild zones via `GuildLayout.scaled_for(width, floor_y)` — a pure transform of the one `guild_layout.tres` resource, never a second layout — applied through `GuildController.apply_layout()`, which rebuilds the greybox visuals and re-places (teleports, not walks) every hero already in the Guild into the rescaled zones. This path is implemented and unit-tested, though it doesn't trigger at the default 1280-wide size.

## Compact HUD

Built procedurally in `main.gd` (`_build_desktop_hud`) inside the new `UI/DesktopHUD` container:

```
☰ TINY GUILD                                              [_] [X]
Arthur - Knight Lv1 | HP 100/100 | EN 100/100 | READY
Mimi - Mage Lv1 | HP 70/70 | EN 100/100 | READY
Gold: 60 | Guild Tokens: 0        <mission / repeat / queue status line>
[MISSIONS] [HEROES] [INVENTORY] [MASTERY]
```

The status line prefers Mission Queue status, then Repeat Orders status, then the current mission line, then the general status text — whichever is most relevant is shown. It updates from the same four refresh functions the full HUD already used (`_update_arthur_stats`, `_update_hero_roster`, `_update_repeat_status`, `_update_queue_status`), so no new signal wiring was needed. `UI/DevHUD` and `UI/DesktopHUD` are simply toggled opposite to each other; large debug text (`LootDebugLabel`) is hidden in Desktop mode per the spec.

## Overlays

`ExpeditionPanel` (the physical board) and the `Sidebar` (Inventory / Class Skills / Guild Mastery tabs) stay direct children of `UI`, not nested in `DevHUD`, precisely so Desktop mode can show them as temporary full-window overlays while the rest of the compact HUD is hidden:

- **MISSIONS** opens the board (closing the sidebar first if it was open).
- **HEROES / INVENTORY / MASTERY** open the sidebar on the matching tab (a new floating **CLOSE** button was added for it — the sidebar had no such control before, since it's always visible in Development mode).
- Both overlays get resized to fill the Desktop window below the HUD strip (`_fit_overlay`), and both start **closed** by default when Desktop mode is entered.
- **ESC** closes whichever Desktop overlay is open (checked before the debug-only key handling, so it also works in a non-debug build); it does nothing if none is open.
- The board's own **CLOSE BOARD** button (added in Milestone 16) works the same in both modes.

**Fix found via screenshot, not the automated test**: the board's `SEND PARTY` button and rest controls were rendering below the visible 320px window — genuinely unreachable by a real mouse, even though the automated test still "passed" because it emits `button.pressed` directly rather than simulating a real click. `ExpeditionPanel`'s root layout was rewired from `PanelContainer > Margin > Column` to `PanelContainer > Scroll > Margin > Column`, so any content taller than the current window scrolls into reach instead of being clipped off-screen. This applies in both modes (Development has plenty of room, so nothing visibly changes there).

## Mission Summary, notifications, and automation

The Mission Summary is the same `ExpeditionPanel` overlay, so it automatically gets the same compact, in-bounds sizing. The Elite/Boss notification banner (`OpportunityNotification`) is repositioned (not rebuilt) per mode — centered near the top of the Desktop window — using the exact same spawn logic as before. Repeat Orders and Mission Queue are untouched: their return → Rest Area → Board → departure flow plays out through the same `GuildController` calls, just visually compressed into the Desktop window via the Stage offset.

## State preservation

`_apply_presentation()` only ever touches presentation: HUD visibility, `Stage.position`, overlay `offset_*`/`visible`, and (rarely) the Guild's rescaled layout. It never reads or writes `HeroController` stats, `MissionRun`, `RepeatOrderState`, `MissionQueueState`, `Inventory`, `Equipment`, or `GuildMasteryState` — mode switches are provably presentation-only.

## Debug (debug builds only)

M toggles Development ↔ Desktop | R resets Desktop window position. All Milestone 3-16 debug keys are unchanged.

## Not implemented (as scoped)

Transparent/click-through background: two inert config flags (`PresentationController.transparent_background`, `click_through_background`) are declared for Milestone 18/19 to wire up, left `false` and unused this milestone, since real per-platform transparent-window setup was explicitly out of scope. No system tray, no Win32 APIs, no final art.

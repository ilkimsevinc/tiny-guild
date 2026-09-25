# Tiny Guild — Roadmap: GDD Coverage & What's Next

This document maps everything in the three design documents (`Tiny_Guild_Game_Design_Document_v0.6.docx`, `Tiny_Guild_Guild_Mastery_and_Idle_Progression_v0.1.docx`, `Tiny_Guild_Class_Skill_Tree_Design_v0.1.docx`) against what actually exists in `scripts/`/`data/` today, then proposes a concrete, sequenced set of future milestones to close the gap — written in the same tightly-scoped, one-system-at-a-time style as Milestones 3–17, so any section below can be handed back as a "continue developing Tiny Guild..." prompt as-is.

**Why this is a plan and not a finished implementation:** the GDD describes a large game — 13 heroes, 3 regions, a relationship/dialogue engine, a slot-machine loot feature, crafting, a Tavern economy, prestige, and more. Building all of it in one uncontrolled pass would mean dozens of interdependent systems with no tests, no review, and no way to catch the kind of bug (a session's not-quite-right prediction formula, a formation cap that silently drops a hero) that showed up even in the carefully-tested systems built so far. Every milestone in this project has been scoped, tested, and reviewed individually — that's why the project is in good shape today. This roadmap keeps that discipline: it sequences the remaining GDD scope into milestones of the same size as the ones already done, rather than attempting all of it blindly.

## Part 1 — Coverage map

Legend: ✅ done · 🟡 partial / scaffolded · ⬜ not started

### Core loop & presentation (GDD §4, §21, §26)
| Item | Status | Notes |
|---|---|---|
| Auto combat, travel, encounter resolution | ✅ | Milestones 3, 8–10 |
| Taskbar/desktop window (borderless, always-on-top, near-bottom) | ✅ | Milestone 17 |
| Transparent/click-through window | ⬜ | Flags declared inert in `PresentationController`, deliberately deferred |
| Compact vs. full HUD | ✅ | Milestone 17 |

### Heroes (GDD §8)
| Hero | Class | Status |
|---|---|---|
| Arthur | Knight | ✅ full (progression, equipment, Knight skill tree with 4 real nodes) |
| Mimi | Mage | 🟡 exists, plays, levels — but the Mage skill tree has **zero** real nodes yet (empty shell) |
| Luna | Ranger | ⬜ |
| Rowan | Knight (Vanguard) | ⬜ |
| Celeste | Mage (Frost) | ⬜ |
| Finn | Ranger (Hunter) | ⬜ |
| Dwaynel Johnsson | Fighter | ⬜ |
| Tane | Artificer | ⬜ |
| Edward | Blacksmith | ⬜ (including the "Blacksmith closes while Edward is on expedition" rule) |
| Andre + Akane | Rogue / Kitsune Samurai (exclusive pair) | ⬜ |
| Ferryn + Regnier | Legendary Dark Mage / Flame God | ⬜ |
| Wilzaren | Tavern NPC, non-combat | ⬜ |

### Class Skill Trees (Class Skill Tree doc §4–13)
| Tree | Status |
|---|---|
| Knight | 🟡 4 of ~13 nodes (Iron Posture, Measured Strike, Shield Discipline, Riposte) |
| Mage, Ranger, Rogue, Kitsune Samurai, Fighter, Artificer, Blacksmith, Legendary Dark Mage, Legendary Flame God | ⬜ tree resources exist as empty branch shells only |

### Guild Mastery (Mastery doc §9–17)
| Branch | Status |
|---|---|
| Economy | 🟡 Coin Pouch I/II only (of 8 tiers + capstone) |
| Training | 🟡 Shared Experience I only |
| Expedition | 🟡 Trail Knowledge only |
| Operations | ⬜ |
| Loot | ⬜ |
| Automation | 🟡 Repeat Orders, Scheduled Rest, Mission Queue (tiers 1/3/7 of 14 + capstone) |
| Portal Mastery | 🟡 Notice Board only |
| Offline | 🟡 Sleeping Guild resource exists but is inert (no offline system to gate) |

### Regions & content (GDD §7)
| Region | Enemies | Boss | Status |
|---|---|---|---|
| Whispering Forest | Slime (+ pool for others) | Ancient Treant | ✅ |
| Crystal Mine | — | Crystal Guardian | ⬜ |
| Forgotten Ruins | — | The Forgotten King | ⬜ |

### Economy & systems (GDD §11–19)
| System | Status |
|---|---|
| Gold, Guild Tokens | ✅ |
| Arcane Essence, Relic Shards | ⬜ (no dismantling, no essence sink) |
| Itemization (6 slots, 6 rarities, affixes) | 🟡 loot/rarity/equip works; only 8 items total; no affix rerolling |
| Arcane Machine | ⬜ |
| Crafting / Dismantling / Enchanting | ⬜ |
| Quests, Journal, Achievements | ⬜ |
| Relationships (Bond/Affinity/Rivalry, dialogue) | ⬜ |
| Active Desktop Events (Golden Slime, Treasure Goblin, etc.) | ⬜ |
| Save / Load | ⬜ **(drafted, see `docs/proposals/save_load_milestone.md`)** |
| Offline Progression | ⬜ (depends on save/load) |
| Prestige / Guild Rebirth | ⬜ |
| Pixel art | ⬜ (target dimensions already specified in `docs/milestone17.md`'s Art Dimension Report) |

## Part 2 — Proposed milestone sequence

Numbered continuing from the project's own Milestone 17 (not the Guild Mastery doc's separate M6–M18 labels, which used a different numbering scheme for a design-time sketch — this sequence reflects what's *actually* built and what actually needs to come next). Each is sized like the existing Milestones 3–17: one system, tightly scoped, with an explicit "do not implement yet" list and automated tests.

### Phase A — Foundation (unblocks everything else)
- **M18 — Save / Load.** Already drafted in full: `docs/proposals/save_load_milestone.md`. Nothing else below is safe to build on top of without this — every subsequent hero, region, and system adds more state that would otherwise vanish on close.
- **M19 — Sprite/Animation abstraction.** Wrap `HeroController`'s and `GuildHeroAvatar`'s placeholder `Polygon2D` visuals behind `AnimatedSprite2D`/`AnimationPlayer`, with a data-driven `animation_set` field on `HeroData` (per GDD §24.1). Purely technical — no visual change with placeholder geometry still in use — but it means the pixel art track (Part 3 below) can start dropping in real sprites the moment art exists, without touching combat/Guild logic again. Recommended **before** or in parallel with the first real art pass.
- **M20 — Offline Progression.** Now that state persists, compute bounded "while you were away" progress on load (Mastery doc §18: base 4h cap, extendable via the Offline branch once it has real nodes) and show the GDD's "While You Were Away" report (§18, §5 Return Session).

### Phase B — MVP completion
- **M21 — Luna joins.** Third MVP hero (GDD §23.1), Ranger class, first three-hero relationship *context* (not full relationships yet — just the social presence). Reuses the exact `HeroData`/`HeroController` pattern Mimi proved out; the real work is the Ranger skill tree (Sniper/Hunter/Poison, Class Skill Tree doc §6) and updating party capacity/formation for a 3-hero roster — which is exactly the `PartyFormation` capacity-hook this session's bug review flagged as dormant and about to matter.
- **M22 — Real skill tree nodes for Mimi and Luna.** Mage tree (Fire/Frost/Arcane) and Ranger tree (Sniper/Hunter/Poison) get actual nodes, mirroring how Knight was built in Milestone 6. Currently the highest-visibility gap: two of three playable heroes have an empty skill panel.
- **M23 — Crystal Mine region.** New enemies, Crystal Guardian boss, region unlock gate (GDD §7). Proves the mission/region system generalizes past Whispering Forest.
- **M24 — Relationship system MVP.** Bond axis, contextual dialogue tags (LOW_HP, RARE_LOOT, RAIN, etc. — GDD §9.5), 10–15 micro-events, the Arthur/Mimi and Mimi/Luna pair dynamics (§9.2). This is a core pillar ("Character Attachment") and is explicitly MVP scope in §23.1 — it should land before any post-MVP heroes.

### Phase C — Economy & collection
- **M25 — Arcane Machine.** Slot-machine loot (GDD §12): rarity odds table, pity counters (20-spin Epic+ guarantee, 100-spin Legendary guarantee), symbol-combination rewards, all-earned-currency only. Self-contained — doesn't depend on new heroes or regions.
- **M26 — Crafting, Dismantling, Enchanting.** Arcane Essence as the dismantle sink, affix rerolling, deterministic recipes (GDD §14). Needs itemization expanded past the current 8 items first (more affixes, more slots populated).
- **M27 — Quests, Journal, Achievements.** Daily/weekly/character quests, Monster Journal, the achievement list in GDD §17.1 (including the comedic ones — "Slime Problem," "Please Stop").

### Phase D — Post-MVP roster & Guild buildings
- **M28 — Rowan, Celeste, Finn.** GDD's own explicit "stretch content, can enter after MVP" list (§23.1). Vanguard Knight, Frost Mage, Hunter Ranger — all reuse existing class trees, so this is mostly hero data + personality-layer content, not new systems.
- **M29 — Dwaynel Johnsson.** New class: Fighter (Brawler/Juggernaut/Gym Rat, Class Skill Tree doc §9).
- **M30 — Tane + Edward.** Linked pair, new classes (Artificer, Blacksmith), and Edward's dual playable-hero/Guild-service availability rule (GDD §8.14.1 — "AT_GUILD vs ON_EXPEDITION" mutual exclusion, must be implemented as data-driven state per the GDD's own instruction, never hard-coded to Edward specifically).
- **M31 — Wilzaren + Tavern.** Non-combat Guild NPC, basic shop (meals/drinks/potions/daily special), per GDD §6.1 and §8.15. `GuildNPCData` as its own data model (GDD §24.1.1) — reuses the Guild-zone placeholder pattern from Milestone 16, doesn't need combat integration.
- **M32 — Andre + Akane.** Paired exclusive-relationship unlock, Rogue + Kitsune Samurai classes. GDD is explicit this pair must ship together, and that the exclusivity rule (`relationship_mode`, `exclusive_partner_id`) must be data-driven, never special-cased in combat/dialogue code (GDD §24.2, §9.3.1) — build the relationship data model generically enough here that a hard-coded "if hero_id == andre" never appears anywhere.
- **M33 — Forgotten Ruins region.** Third region, Forgotten King boss, character-backstory event hooks (GDD §7).

### Phase E — Endgame
- **M34 — Ferryn + Regnier.** Legendary divine heroes, gated behind a major late-game unlock (not ordinary recruitment — GDD §8.11/8.12 are explicit these should feel earned).
- **M35 — Advanced Guild Mastery automation tail.** Mission Scoring, Goal Policy, Auto Dispatch, Guild Routine, Autonomous Guild capstone (Mastery doc §15, tiers 10–14 + capstone) — the "policy manager" and "autonomous guild" stages of the manual-to-idle philosophy in Mastery doc §4.
- **M36 — Portal Mastery + remaining Guild Mastery branches.** Operations and Loot branches, Elite/Boss/Anomaly Rumors, Reserve Contract, Gatekeeper capstone (Mastery doc §16).
- **M37 — Prestige / Guild Rebirth.** Legacy Points, the permanent-bonus tree (GDD §19).

### Part 3 — Pixel art (parallel track, not a numbered milestone)

Art has its own lead time and doesn't need to wait for the code roadmap above — start it as soon as M19 (sprite abstraction) lands. Suggested order, using the exact dimensions from `docs/milestone17.md`'s Art Dimension Report:

1. Arthur + Mimi: Idle, Walk, Attack, Hit at minimum (the four states the game already drives via `HeroController.State`); Downed/Sleep/Celebrate and personality-specific animations (GDD §22) can follow once the base four prove the pipeline.
2. Slime (the one enemy already in constant use).
3. The six Guild zone backdrops + door + Expedition Board prop (currently flat `ColorRect`s in `guild_controller.gd`).
4. Ancient Treant.
5. Repeat steps 1–2 for each new hero/enemy as Phase B–D milestones add them, rather than batching all future art up front — this keeps art and code in lockstep the same way the rest of this project has stayed in lockstep.

## Part 3.5 — Deliberately not sequenced here

A few GDD items are genuinely speculative or monetization/legal-adjacent enough that they shouldn't get a milestone number until the core loop above is proven:

- Pets (GDD §23.2, explicitly post-MVP).
- Seasonal content, Guild customization.
- Any monetization beyond "premium game, no real-money gambling" (GDD §2) — the Arcane Machine (M25) must stay earned-currency-only per the GDD's own explicit rule.

## How to use this document

Each Phase A/B item above is written at roadmap depth, not spec depth — the way Milestones 3–17 were actually executed, each needs its own full spec (like `docs/proposals/save_load_milestone.md`) before implementation: a design-goal statement, numbered requirement sections, an explicit "do not implement yet" list, and an automated-test list. Ask for any specific one to be drafted the same way, or to be implemented directly if the spec already exists.

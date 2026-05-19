# SurvivorIO — Game Planning Document

> **For all contributors.** This document captures the vision, current state, open work, and design decisions for SurvivorIO. Read this before starting new features. Update it when the direction changes.

---

## Vision

A fast-paced browser-based multiplayer survival game where players compete to reach a score threshold first. Matches are short (target: **under 10 minutes**) and support multiple paths to victory — aggressive combat, passive base-building, or a mix of both.

The game should feel approachable to pick up and play with friends, with enough strategic depth to reward experienced players. Every session resets completely.

---

## Core Game Loop

```
Spawn → Gather resources → Craft weapons/structures → Fight enemies/players
             ↑                                                    ↓
             └─────────── Score accumulates ────────────── Win at 500 pts
```

**Three paths to score:**
| Path | How | Points |
|------|-----|--------|
| Active combat | Kill mobs, destroy world objects, PK | 1–4 pts per kill |
| Passive structures | Place windmills — they tick score over time | 10 pts / 10s each |
| Mixed | Defend windmills while fighting mobs | Best of both |

**Match flow:**
1. Players spawn on a procedurally generated island map
2. Gather wood/stone from world objects
3. Craft weapons and structures
4. Compete to hit **WIN_SCORE = 500** first
5. Winner announced, 5-second countdown, map resets

---

## What's Shipped (main branch)

### Multiplayer
- WebSocket server (Godot WebSocketMultiplayerPeer), server-authoritative
- Supports dedicated server export (Linux headless) and web client export
- Player spawning, despawning, disconnect handling
- Score sync via RPC, win condition, round reset

### Player
- WASD movement, sprint (shift), map border clamping
- Melee and ranged attacks, multiple weapon types with durability
- Inventory (9 slots), item selection (1–9, scroll wheel)
- Item drop (Q), crafting menu (C), chat (Enter), settings (ESC)
- Boat boarding/disembarking, water navigation
- Name tags, health bar, stamina bar, crown (win count)

### World
- Procedurally generated tilemap (land + water, 64×64)
- Breakable world objects: trees, rocks, bushes, ore, magic resources, crystals
- Day/night cycle
- Minimap with player dot tracking

### Crafting & Items
- Tier 1 weapons: sword, axe, pickaxe, spear, dagger
- Tier 2 weapons: axe2, pickaxe2
- Magic weapons: magicSword1, magicAxe1, magicDagger1, magicSpear1
- Placeables: wall, stone_wall, door, stone_door, chest, torch, boat
- Torch: equippable + placeable; repels enemies (coal_repeller group)

### Enemies
- Zombie (melee), Spider (ranged projectile)
- Spawn near players, drop resources on death
- Torch repulsion system

### UI
- Leaderboard (live score updates, no flicker)
- Win banner with countdown
- In-game settings overlay (resolution, exit, disconnect)
- Controls reference panel

### Infrastructure
- `Items.gd` — single source of truth for all game content data
- `Multihelper.gd` — multiplayer state, signals, win/reset logic
- `Inventory.gd` — server-authoritative inventory with client sync
- `Victories.gd` — persistent win records per player name
- `PlaceableObject` base class — owner tracking, HP, passive score, animations
- `tests/test_runner.gd` — self-contained test suite, no external framework
- `godot_mcp` plugin — editor MCP bridge for AI tooling

---

## Open Pull Requests

| PR | Branch | What it adds | Status |
|----|--------|-------------|--------|
| #32 | `feature/inventory-ui-nametags` | Item name tooltips on inventory/recipe slots; floating name label on world pickups | Ready to merge |
| #33 | `feature/windmill` | Windmill placeable (passive score, 10pts/10s, 150HP); WIN_SCORE → 500; extended `/give` command | Ready to merge |
| #34 | `feature/mob-ai-refactor` | Four-state mob AI (idle/wander, chase, attack, attack-structure); dynamic targeting; brute + wraith mob types | Ready to merge |
| #35 | `feature/resource-spawn-rates` | Weighted resource spawning; player-count scaled cap; event-driven continuous replacement; proximity exclusion; rare object minimums | Ready to merge |

---

## Backlog / Planned Features

> Prioritised roughly top-to-bottom. Move items up or down as vision evolves.

### High Priority
- **More placeable structures** — use `PlaceableObject` base class (e.g. watchtower, campfire, mine)
- **Player progression within a match** — score rewards already give HP/damage/speed bonuses; tune values
- **Enemy scaling** — harder mobs / more mobs as match progresses or as player score rises
- **Lobby system** — waiting room before match starts, player ready-up, match timer countdown

### Medium Priority
- **Character selection** — visual customisation (already partially supported via `characterFile`)
- **Loot chests** — rare fixed spawns on the map with high-value items
- **Map biomes** — different terrain zones with different resource types
- **Status effects** — freeze (icebolt), burn (fireball), slow (iceShard), stun (lightningBolt) are defined in `Items.projectiles` but not yet implemented
- **Sound & music** — spatial audio for attacks/harvesting; ambient music per biome
- **Mobile/touch controls** — virtual joystick, touch-friendly UI

### Lower Priority / Ideas
- **Teams mode** — 2v2 or squad play
- **Spectator mode** — watch after death before round resets
- **Map editor** — allow custom maps
- **Seasonal/cosmetic content** — holiday themes, skins
- **Leaderboard persistence** — cross-session win counts already saved; expose globally

---

## Design Principles

These decisions have been made deliberately. Don't change them without discussion.

### Server-authoritative
All game logic runs on the server. Clients send inputs, receive state. This prevents cheating and keeps the game deterministic. RPCs to the server; server broadcasts results.

### Data-driven content
All items, mobs, objects, weapons, recipes, and projectiles live in `Items.gd`. Adding a new mob, weapon, or resource requires only a data entry — no code changes. Keep it that way.

### Short matches
WIN_SCORE = 500. Matches should end in under 10 minutes. If they're running long, tune score rates before raising the cap. Players should want to play multiple rounds in a session.

### Multiple win paths
No single dominant strategy. Combat, windmills, and mixed play should all be viable. Tune balance to prevent any one path from being the only correct choice.

### Evergreen systems
New content should work with existing systems for free. A new placeable that extends `PlaceableObject` gets owner tracking, damage, animations, and score generation automatically. A new mob entry in `Items.mobs` spawns and behaves without code changes. Preserve this.

---

## Code Quality Standards

> These standards apply to every line of code written for this project — by humans and AI agents alike. They are enforced in `CLAUDE.md` and should be internalised by all contributors.

### 1. Check existing systems first
Before writing new code, search the codebase for systems that already solve or partially solve the problem. Extend or reuse before creating something new. The data-driven systems in `Items.gd`, `PlaceableObject`, and the damage/damageable group contracts are all designed to be extended — use them.

### 2. Evergreen
Code should be reusable by future developers and AI agents without rewriting it. Prefer general systems over one-off solutions. Ask: "if someone adds a new item/mob/structure tomorrow, does my code handle it for free?"

### 3. Documented
Every system, class, and non-trivial function must have a comment answering three things:
- **What it is** — one sentence on the purpose
- **How to use it** — a concrete usage example or extension pattern
- **What to watch out for** — constraints, authority boundaries, timing requirements, or gotchas

A future developer or AI agent reading the code cold should immediately understand its purpose and usage without asking.

### 4. Automatic
Systems should require as little manual wiring as possible. New items, scenes, or features should work with existing systems for free — not require the developer to remember extra registration steps. If adding content requires touching more than one or two files, reconsider the design.

### 5. Safe
Before finalising any code, check for:
- Null access and missing dictionary keys
- Node-ready timing issues (properties set before node enters tree)
- Server/client authority boundaries (never trust the client for game logic)
- RPC targets (guard against sending to disconnected peers)
- Edge cases at 0 players, empty arrays, or mid-round resets

### 6. Comments and commits
Commit messages must describe **what the system does and why it exists**, not just what files changed. Another developer reading the git log should be able to reconstruct the intent without reading the diff.

### 7. Pull requests
Every PR must include a test plan checklist covering every new feature, system, or fix. Each item must be specific enough that a tester knows exactly what to do and what outcome to expect.

---

## Technical Notes for New Contributors

### Adding a new mob
1. Add entry to `Items.mobs` in `scenes/autoloads/Items.gd` with all required fields
2. Add PNG sprite to `assets/characters/enemy/<mob_id>.png`
3. Done — enemy spawner picks it up automatically

### Adding a new placeable structure
1. Create `scenes/object/<name>.gd` extending `"res://scenes/object/placeable_object.gd"`
2. Set `score_per_interval`, `score_interval`, `max_hp` before `super._ready()`
3. Override `_do_break()` to spawn drops using `Items.calc_drops(Items.recipes["name"], rate)`
4. Create `scenes/object/<name>.tscn` with `damageable` group, AnimationPlayer, hitParticle
5. Add to `Items.placeables` and `Items.recipes` in `Items.gd`
6. Done — placement, owner tracking, damage, and score are all automatic

### Adding a new resource object
1. Add entry to `Items.objects` in `Items.gd` with `id`, `hp`, `tool`, `weight`, `drops`
2. Optionally add `min_count` for a guaranteed map presence
3. Add PNG to `assets/objects/<id>.png`
4. Done — spawner picks it up with correct weighting automatically

### Adding a new weapon
1. Add entry to `Items.equips` with `attack`, `damage`, `damageType`, `durability`
2. Optionally add `projectile` and `fire_rate` for ranged weapons
3. Add entry to `Items.recipes` with crafting cost
4. Add PNG to `assets/items/<id>.png`
5. Done

### Server commands
Add a match branch to `_handle_command()` in `scenes/character/player.gd`. Implement as `_cmd_<name>()`. Server-only — no client-side handling needed.

### Multiplayer authority
- **Server only**: game logic, score changes, spawning, win condition
- **All peers**: visual effects, animations, position sync via MultiplayerSynchronizer
- **Client only**: input reading, camera, local UI

---

## Open Questions

> Things the team hasn't decided yet. Discuss and update this section.

- Should windmills be destroyable by enemy mobs that wander near them?
- What should happen to a player's windmills when they disconnect?
- Should there be a max number of windmills per player?
- What does the magic weapon progression unlock? (ingredients exist but no gameplay impact yet)
- Should status effects (freeze, burn, etc.) be added to the current sprint or a later one?
- Is there a plan for a main menu / matchmaking beyond the current direct-join flow?

---

*Last updated by Claude Sonnet 4.6 — update this document when significant decisions are made.*

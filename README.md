# Dry Sea Salvage

[![CI](https://github.com/batyrkhan9/dry-sea-salvage/actions/workflows/ci.yml/badge.svg)](https://github.com/batyrkhan9/dry-sea-salvage/actions/workflows/ci.yml)

A Roblox game based on a short film I produced: an endless dried-up seabed
where old ships lie half-buried in the sand. You play a salvager digging up
relics of the vanished sea, then facing other players in **camp duels**, a
head-to-head strategy game where your relic layout is your army and clever
positioning beats a bigger collection.

**▶ Play:** [Dry Sea Salvage on Roblox](https://www.roblox.com/games/107203524958682/Dry-Sea-Salvage)
(the live place runs the salvage loop; the camp-duels update ships next)

## The salvage loop

- **Salvage** - one button. The server rolls a relic across six rarity tiers,
  from common *Rust* finds to the once-in-a-thousand *What the Sea Left*.
- **Collect** - everything you find is saved permanently to your inventory.
- **Merge** - three copies of the same relic forge one random relic of the
  next tier up.
- **Index** - a collection book tracks what you've found and what's still out
  there; the whole server gets a banner when someone pulls a top-tier relic.

## Camp duels

Every player gets a camp plot with a 6x6 grid. Relics you deploy there are
your army, and the board is the strategy:

- **Roles, not stats.** Every relic has a role - Breaker, Guard, Trap, or
  Scout - on a rock-paper-scissors counter wheel (Breaker smashes Guard,
  Guard outlasts Trap, Trap catches Breaker). A counter wins outright, so a
  common-tier Trap takes down a rare Breaker. Rarity only breaks ties.
- **Marching order.** Armies fight as a queue readable straight off the
  board: front row first, left to right. Who tanks first, what you protect
  in the back, where your Scouts stand (they can't fight, but they boost
  adjacent allies) - that's the skill.
- **Challenge flow.** Click another player's camp sign, they accept, and the
  server resolves both layouts deterministically. Both players then watch
  the same animated replay, clash by clash, with captions that teach the
  rule behind every outcome ("TRAP catches BREAKER!").
- **Honor stakes only.** Wins, losses, and streaks live on your camp sign.
  Nobody ever loses a relic - losing costs pride and teaches a lesson.

## Architecture

Written in **Luau**, developed in VS Code and synced to Roblox Studio with
**Rojo** - all game logic lives in this repo, not in the place file.

```
src/
├── server/               (ServerScriptService)
│   ├── init.server.luau   - entry point: creates remotes, wires services
│   ├── RollService.luau   - weighted RNG + per-player roll cooldown
│   ├── InventoryService.luau - owned relics + discovery tracking
│   ├── MergeService.luau  - merge validation and execution
│   ├── DataService.luau   - the ONLY module touching DataStores
│   ├── PlayerDataSchema.luau - save shape + migrations (pure, unit-tested)
│   ├── CampService.luau   - plot assignment, signs, deployed-relic visuals
│   ├── PlacementService.luau - deploy/retrieve rules for camp relics
│   ├── DuelService.luau   - challenge flow, record keeping
│   └── MapBuilder.luau    - seeded procedural wreck scatter
├── client/               (StarterPlayerScripts)
│   ├── init.client.luau   - entry point: wires remotes to UI modules
│   ├── RollUI.luau        - salvage button, cooldown, result popup + effects
│   ├── InventoryUI.luau   - relics panel with merge/place buttons
│   ├── CollectionUI.luau  - the index: found vs. missing, per tier
│   ├── AnnouncementUI.luau - server-wide rare-pull banner (queued)
│   ├── PlacementUI.luau   - cell-picking mode on the camp plot
│   ├── DuelUI.luau        - challenge prompt, notices, scoreline
│   ├── BattlePlayback.luau - animated clash-by-clash duel replay
│   └── Sound.luau         - config-driven sound playback
└── shared/               (ReplicatedStorage)
    ├── Config.luau        - ALL tuning: rarities, roles, weights, costs
    ├── RelicUtil.luau     - pure lookups shared by server and client
    └── BattleResolver.luau - deterministic duel resolution (pure, tested)
```

**Server-authoritative by design.** Every roll, inventory change, merge,
placement, and duel happens on the server; the client only sends requests and
renders results. Requests arrive as untrusted input and are fully validated
(type check → known relic → owned/eligible → board rules) before anything
mutates.

**Deterministic battles.** Duels resolve as pure logic in `BattleResolver`:
two layouts in, a winner plus an ordered event script out. The server scores
the script; both clients animate the identical script, so the replay players
watch can never disagree with the result. Determinism also makes every battle
rule unit-testable, including "a common Trap must beat a rare Breaker".

**Data flow:** client fires a remote → server service validates and executes →
result returns to the requesting client (and broadcasts to all clients for
rare pulls) → UI renders. Player data is cached in memory during a session;
`DataService` alone talks to DataStoreService, with retry + exponential
backoff, autosave, save-on-leave, `BindToClose`, and a load-failure guard that
disables saving rather than risk overwriting real data with defaults. Saves
carry a `schemaVersion` field and pass through a reconcile step on load, so
the format can evolve without breaking old saves.

**Session locking:** the same account joining two servers at once is the
classic Roblox data-loss bug (last write wins). Every save record carries a
lock (server id + timestamp) written via `UpdateAsync`; a server only loads
data it can lock, refreshes the lock on autosave, releases it on the final
save, and steals only stale locks from crashed servers. A locked-out server
gives the player a read-only session instead of the power to destroy data.

**Testing:** pure logic (roll-odds mapping, relic lookups, merge eligibility,
save-schema migrations, the battle resolver and counter wheel) is factored
into Roblox-free modules and unit-tested with
[Lune](https://github.com/lune-org/lune) on every push - `lune run
tests/run.luau` locally, 30 tests and counting.

**Data-driven content:** relics and rarities are pure data in `Config.luau` -
adding a relic or retuning the odds touches no logic. Relic definitions are
structured to carry future gameplay fields (unit stats, power values)
without save migration.

## Tech stack

- **Luau** (typed) - plain modules, no frameworks
- **Rojo** - filesystem ↔ Studio sync
- **Roblox DataStore** - persistence
- **GitHub Actions** - StyLua format check, Selene lint, and Lune unit tests
  on every push

## Design principles

Built for a mostly-young audience:

1. **No paid luck, ever.** Rolls come from playing. If monetization is ever
   added, it's cosmetics only.
2. **Equal odds for everyone** - identical RNG regardless of money or skill.
3. **Reward thinking and planning** over pure grinding - in duels, choices
   dominate collection size: counters are relative, stakes are honor-only,
   and a cheap clever layout beats an expensive lazy one.
4. **Bad luck has a floor.** A pity system guarantees a Storm-or-better
   pull after 90 dry rolls, without distorting the odds inside the rare
   band.

## Roadmap

Built mechanism by mechanism, each layer on the last:

- ✅ **Salvage loop** - weighted rolls, persistent inventory, merging,
  collection index, rare-pull announcements
- ✅ **Camp duels** - plots, cell-picked placement, roles + counter wheel,
  deterministic battles with animated replays, W/L/streak on the camp sign
- 🔨 **Building & economy** - spend salvage to build and upgrade camp
  structures
- 🔨 **Open-world expansion** - new zones across the seabed, scavenger NPCs,
  a camp that grows into a settlement

## Running locally

```bash
rojo serve
```

Then connect from Roblox Studio via the Rojo plugin. Requires
[Rojo](https://rojo.space) 7.x.

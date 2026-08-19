# Dry Sea Salvage

[![CI](https://github.com/batyrkhan9/dry-sea-salvage/actions/workflows/ci.yml/badge.svg)](https://github.com/batyrkhan9/dry-sea-salvage/actions/workflows/ci.yml)

A Roblox game set on an endless dried-up seabed, inspired by the real story of
the **Aral Sea**. Old ships lie half-buried in the sand; you play a salvager
digging up relics of the vanished sea, collecting, merging, and completing an
index of everything the water left behind.

**▶ Play:** _link coming soon — publishing in progress_

## How it plays

- **Salvage** — one button. The server rolls a relic across six rarity tiers,
  from common *Rust* finds to the once-in-a-thousand *What the Sea Left*.
- **Collect** — everything you find is saved permanently to your inventory.
- **Merge** — three copies of the same relic forge one random relic of the
  next tier up.
- **Flex** — a collection index tracks what you've found and what's still out
  there; the whole server gets a banner when someone pulls a top-tier relic.

## Architecture

Written in **Luau**, developed in VS Code and synced to Roblox Studio with
**Rojo** — all game logic lives in this repo, not in the place file.

```
src/
├── server/               (ServerScriptService)
│   ├── init.server.luau   — entry point: creates remotes, wires services
│   ├── RollService.luau   — weighted RNG + per-player roll cooldown
│   ├── InventoryService.luau — owned relics + discovery tracking
│   ├── MergeService.luau  — merge validation and execution
│   ├── DataService.luau   — the ONLY module touching DataStores
│   ├── PlayerDataSchema.luau — save shape + migrations (pure, unit-tested)
│   └── MapBuilder.luau    — seeded procedural wreck scatter
├── client/               (StarterPlayerScripts)
│   ├── init.client.luau   — entry point: wires remotes to UI modules
│   ├── RollUI.luau        — salvage button, cooldown, result popup + effects
│   ├── InventoryUI.luau   — relics panel with merge buttons
│   ├── CollectionUI.luau  — the index: found vs. missing, per tier
│   ├── AnnouncementUI.luau — server-wide rare-pull banner (queued)
│   └── Sound.luau         — config-driven sound playback
└── shared/               (ReplicatedStorage)
    ├── Config.luau        — ALL tuning: rarities, relics, weights, costs
    └── RelicUtil.luau     — pure lookups shared by server and client
```

**Server-authoritative by design.** Every roll, inventory change, and merge
happens on the server; the client only sends requests and renders results.
Merge requests arrive as untrusted input and are fully validated (type check →
known relic → mergeable tier → sufficient copies) before anything mutates.

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
save-schema migrations) is factored into Roblox-free modules and unit-tested
with [Lune](https://github.com/lune-org/lune) on every push — `lune run
tests/run.luau` locally.

**Data-driven content:** relics and rarities are pure data in `Config.luau` —
adding a relic or retuning the odds touches no logic. Relic definitions are
structured to carry future gameplay fields (defense-unit stats, power values)
without save migration.

## Tech stack

- **Luau** (typed) — plain modules, no frameworks
- **Rojo** — filesystem ↔ Studio sync
- **Roblox DataStore** — persistence
- **GitHub Actions** — StyLua format check, Selene lint, and Lune unit tests
  on every push

## Design principles

Built for a mostly-young audience:

1. **No paid luck, ever.** Rolls come from playing. If monetization is ever
   added, it's cosmetics only.
2. **Equal odds for everyone** — identical RNG regardless of money or skill.
3. **Reward thinking and planning** over pure grinding.
4. **A pity system** (guaranteed rare after enough rolls) is planned so bad
   luck always has a floor.
5. **Teach something real** — the setting is the real Aral Sea, and the
   collection index will eventually tell its true story.

## Roadmap

- ✅ Salvage loop: weighted rolls, persistent inventory, merging, collection
  index, rare-pull announcements
- 🔨 **Base-defense** — your salvage camp on the seabed; relics become
  placeable defense units against enemy waves; strategy over twitch skill
- 🔨 **Base building & economy** — spend salvage to build and upgrade camp
  structures
- 🔨 **Deeper merge paths** tied to unit upgrades
- Later: scavenger NPCs (idle layer), camp citizens, world expansion

## Running locally

```bash
rojo serve
```

Then connect from Roblox Studio via the Rojo plugin. Requires
[Rojo](https://rojo.space) 7.x.

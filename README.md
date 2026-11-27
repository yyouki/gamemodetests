# open.mp Anti-Cheat GameMode Tests

A standalone, runnable open.mp staging gamemode for testing the public integration contract of [yyouki/anticheat](https://github.com/yyouki/anticheat).

**This is a separate repository.** It does not modify the anti-cheat framework. The anti-cheat include is fetched at the exact commit `b8e7885395f35f60f64dac1db8f6428730e2674d` only when compiling. No framework source is copied into this repository.

## What is included

- Playable Pawn gamemode with normal spawn and in-game test commands.
- Synthetic account loading and a RAM-only persistence adapter (no real account data, SQL plugin, or database).
- Lifecycle forwarding: connect, disconnect, spawn, death, state changes and player updates.
- Legal server-owned teleport, vehicle, interior, virtual-world and spectating scenarios, with notifications before the server action.
- Vehicle observations capped at 2 samples/second and 3,600 records per capture. These are telemetry only; they do not change detector inputs or thresholds.
- Legacy and V2 evidence/strike callbacks. `/acstagev2info` displays callback counters and checks whether V2 strike sequence/timestamp match the evidence event that caused it.
- CI that compiles the AMX, packages it, and verifies that the pinned open.mp server boots and loads the gamemode.

The gamemode is a test harness, not an anti-cheat replacement or production gamemode. It does not automatically kick, ban, freeze, rewind or punish players. It does not simulate client-side cheats or establish bypass resistance.

## Download a runnable build

1. Open the repository's **Actions** tab.
2. Select the latest successful **Validate anti-cheat test gamemode** workflow run on `main`.
3. Download the `gamemodetests-package` artifact.
4. Extract it. It contains `gamemodes/ac-test.amx`, `config.json`, this README and `docs/TEST_MATRIX.md`.

No local Pawn compiler is required when using the CI artifact.

The CI build pins:
- Anti-cheat source: `b8e7885395f35f60f64dac1db8f6428730e2674d`
- open.mp standard includes: `17c1b0191195cb0b59a820135fbca622c84129dd`
- Pawn compiler: `3.10.11`
- open.mp Linux server smoke version: `v1.6.7.3218`

## Run it on a private staging server

1. Download and extract a compatible open.mp server from the [official downloads page](https://open.mp/downloads/server).
2. Keep this server separate from any production server. Do not expose it as a public server-list entry.
3. Copy `gamemodes/ac-test.amx` from the artifact into the server's `gamemodes/` directory.
4. Copy the artifact's `config.json` to the server root.
5. Confirm the main script is `ac-test 1`. The supplied configuration disables announcement, query visibility and RCON.
6. Start the server using the hosting provider's normal server-start mechanism.
7. Connect using a compatible SA-MP/open.mp client.

The anti-cheat include is statically linked into the compiled AMX. You do not need to install Pawn include files on the game server.

## First interactive test

On the first client:

1. Spawn, then run `/acstageauth 424242`. This is a synthetic account ID; do not use an account ID from another server.
2. Run `/acstageinfo`. Monitoring becomes enabled only after the synthetic account has loaded.
3. Run `/acstagev2info` to inspect V2 callback counters.
4. Run `/acstagetest` to exercise stale-session, account-mismatch, duplicate-load, timestamp-restore, save and simulated session-restore checks.
5. Run `/acstagehelp` to see the full command list.

Connect a second test client and leave it stationary in the same exterior world. The primary client can use `/acstagespectate <targetid>` and `/acstageunspectate` to test a real spectating round trip.

## Acceptance capture

Use one complete capture per vehicle model:

1. Run `/acstagelogbegin`.
2. Walk, sprint, jump, fall and land normally. Then run `/acstageteleport`.
3. Run `/acstagevehicle 411` (or another approved road-car model), drive normally for at least 30 seconds, and run `/acstageexitvehicle`.
4. Run `/acstageinterior` twice to enter and leave interior 17.
5. Run `/acstageworld` twice to enter and leave virtual world 9000.
6. Run `/acstagespectate <targetid>` and then `/acstageunspectate`.
7. Run `/acstagelogend`.

Keep raw server logs private. The supplied config disables chat and connection logging, but host logs may still contain operational metadata. Do not commit raw logs, account names, player identifiers, IP addresses or chat. For structured reports/review, use the sanitizer and validators from the anti-cheat repository under `tools/anticheat/`, pinned to the commit above. Run those tools locally against a private clone and share only sanitized exports.

## Test matrix

See [docs/TEST_MATRIX.md](docs/TEST_MATRIX.md) for desktop/Android, lifecycle, movement, vehicle, spectating and network scenarios.

A headless CI boot proves only that the compiled gamemode loads on the pinned Linux server. It does not test a connected player, Android/desktop input, false-positive rates, detector effectiveness, performance at target capacity, or production readiness. Those require real staging sessions.

## Commands

| Command | Purpose |
| --- | --- |
| `/acstagehelp` | List commands |
| `/acstageauth <accountid>` | Load a positive synthetic account |
| `/acstageinfo` | Show monitoring, score, strikes and player state |
| `/acstagev2info` | Show V2 callback counts and strike/evidence event linkage |
| `/acstagetest` | Run persistence/session self-tests |
| `/acstageevidence` | Display current-session evidence |
| `/acstagetoggle` | Enable or disable monitoring |
| `/acstagesave` | Save to the temporary in-memory adapter |
| `/acstageclear` | Clear current review state |
| `/acstageteleport` | Apply a server-notified legal teleport |
| `/acstagevehicle [modelid]` | Spawn an approved road car |
| `/acstageexitvehicle` | Exit the current vehicle |
| `/acstageinterior` | Enter/exit the test interior |
| `/acstageworld` | Enter/exit virtual world 9000 |
| `/acstagespectate <playerid>` | Spectate a second connected client |
| `/acstageunspectate` | Stop spectating and restore context |
| `/acstagelogbegin` | Begin a bounded structured capture |
| `/acstagelogend` | End the current capture |

## Limitations

- Persistence is RAM-only and resets when the server restarts.
- Packet loss stays unknown unless a host integration supplies fresh measurements through `AC_SetNetworkQuality`.
- Vehicle telemetry is diagnostic only; it does not establish model-specific safe speed limits.
- The gamemode has no admin authentication system and is intended only for an isolated test server.
- CI does not connect interactive clients. Detector accuracy and production readiness remain unverified.

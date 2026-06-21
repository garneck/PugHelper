# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**PUG Helper** is a World of Warcraft addon for **TBC Anniversary** realms (`## Interface: 20505`, WoW 2.0.5). It gives PUG raid leaders a draggable window of pre-written boss/trash callouts that get sent to chat with `{TOKEN}` substitution for player names. No build step, no external libraries (pure Blizzard API), no XML — all UI is created in Lua via `CreateFrame`.

## CRITICAL: everything must target TBC Anniversary (2.0.5)

- All content (raids, bosses, mechanics, callouts) must be accurate to **The Burning Crusade**. No retail or later-expansion bosses, mechanics, or terminology.
- All code must use **TBC-era WoW API**. Do not assume modern API exists; when a newer function may be needed, follow the existing compat-shim pattern in `Core.lua` (e.g. `InRaid()` checks `IsInRaid` *and* falls back to `GetNumRaidMembers`).
- `## Interface: 20505` in `PugHelper.toc` must stay correct for the targeted client.

## File roles

- **`Data.lua`** — content only. Edit this for raids and callouts. It's a pure data table: `PugHelperRaids` (raids → `sections` → `lines`) and `PugHelperRoles` (role `key`/`label` pairs). No functions.
- **`Core.lua`** — the engine (UI, events, chat, slash commands). Do not put content here. The header comment says users edit `Data.lua`, not `Core.lua`.
- Load order in `.toc` is `Data.lua` then `Core.lua` — Core depends on the globals Data defines.

## Key mechanics to preserve

- **Token substitution:** `{KEY}` in a callout line is replaced with the configured name via `gsub("{(%w+)}", ...)`. Tokens must be alphanumeric (word chars only); keys come from `PugHelperRoles` in `Data.lua`.
- **Chat splitting:** outgoing lines are split at word boundaries to a **240-char** limit before `SendChatMessage` — keep this when touching `SendLine`.
- **Channel `AUTO`** resolves RAID → PARTY → SAY based on group state.
- **Saved variables:** single global `PugHelperDB`, initialized on `ADDON_LOADED` and merged against `DEFAULTS` via the recursive `ApplyDefaults`. Add new persistent settings to `DEFAULTS`, not ad-hoc.
- **UI uses object pooling** (`rowPool`, `headerPool`) — reuse pooled frames rather than creating new ones per render.

## Slash commands

`/pug` (alias `/pughelper`): `show`, `toggle`, `name TOKEN Value`, `names`, `channel`, `reset`.

## Conventions

- Globals: PascalCase (`PugHelperDB`, `PugHelperRaids`, `PugHelperRoles`). Locals/functions: camelCase. Constants: `UPPER_SNAKE_CASE`. Keep engine functions `local` to avoid polluting the global namespace.

## Verifying changes

There is no automated test framework. Verify in-game: save the files in this AddOns folder, then `/reload` (or relog) in WoW and exercise the change manually via `/pug`.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**PUG Helper** is a World of Warcraft addon for **TBC Anniversary** realms (`## Interface: 20505`, WoW 2.0.5). It gives PUG raid leaders a draggable window of pre-written boss/trash callouts that get sent to chat with `{TOKEN}` substitution for player names. No build step, no external libraries (pure Blizzard API), no XML — all UI is created in Lua via `CreateFrame`.

## CRITICAL: everything must target TBC Anniversary (2.0.5)

- All content (raids, bosses, mechanics, callouts) must be accurate to **The Burning Crusade**. No retail or later-expansion bosses, mechanics, or terminology.
- All code must use **valid WoW API for this client** — see the dedicated **WoW API rules** section below. This is non-negotiable and is the area we have already gotten wrong, so read that section before writing or editing any function.
- `## Interface: 20505` in `PugHelper.toc` must stay correct for the targeted client.

## WoW API rules — READ BEFORE WRITING OR CHANGING ANY FUNCTION

We have already had a bug caused by code that did not use the proper addon API. Treat every WoW API call as something to **verify, not assume**. There is no compiler and no test runner here — a wrong or non-existent API call does not fail at "build" time; it silently errors at runtime in-game, often only when a specific code path runs. So the bar is: *do not write an API call you are not confident exists in this client, with the signature you are using.*

### What "this client" actually is
Anniversary realms do **not** run the literal 2007 2.0.5 binary. They run the **current Classic-era client** that merely reports `## Interface: 20505`. The practical consequences:

- **Some modern API exists** (e.g. `SetColorTexture`, `GetNumGroupMembers`, `GetNumSubgroupMembers`, `C_Timer`) — but you may **not** assume any *specific* one does. Confirm or guard it.
- **The old 2.0.5-era names may also still exist** as compatibility aliases (e.g. `GetNumRaidMembers`, `GetNumPartyMembers`). That coexistence is exactly why our helpers check **both**.
- **Retail-only / later-expansion API does NOT exist** (and neither does retail content — see the TBC content rule above).

Because both the old and new names can be present-or-absent depending on the build, **never hard-depend on a single one**.

### The one rule: never invent, guess, or "remember" an API
Hallucinated API is the #1 failure mode in this repo. Do not write a call to a global function, frame method, template, or `C_*` namespace unless you actually know it exists in this client. If you are introducing a WoW API call that is **not already used elsewhere in this codebase**, you must either be certain it is standard TBC/Classic API *or* wrap it in a type-guard with a fallback (next rule). Prefer reusing an API the codebase already calls over introducing a new one.

### The compat-shim pattern (mandatory for any version-sensitive or uncertain call)
This is the established pattern in `Core.lua` — see `InRaid()`, `InGroup()`, `RaidCount()`, `PartyCount()`. Any call that might be missing on some build MUST be guarded:

```lua
-- Prefer the modern call, fall back to the old one, then a safe default.
local function RaidCount()
    if type(GetNumGroupMembers) == "function" then return GetNumGroupMembers() end
    if type(GetNumRaidMembers) == "function" then return GetNumRaidMembers() end
    return 0
end
```

Rules for shims:
- Guard with `type(Foo) == "function"` (or `type(Ns) == "table" and type(Ns.Foo) == "function"` for namespaces) — **never** call a possibly-missing global bare.
- Always provide a fallback path and a final safe default; never let the function error if every API is absent.
- Keep the shim `local` and reuse it everywhere instead of repeating the guard inline.

### Specific landmines (do not step on these)
- **`C_*` namespaces:** do not assume `C_Timer.After`, `C_ChatInfo.*`, `C_PartyInfo.*`, etc. exist. Guard the namespace **and** the function before calling, with a fallback.
- **No backdrop system:** the UI is deliberately texture-based (see `Edge()` + `SetColorTexture` in `BuildUI`). Do **not** reach for `:SetBackdrop`, `BackdropTemplateMixin`, or `"BackdropTemplate"` — they are not guaranteed and we intentionally avoid them.
- **`CreateFrame` templates must be real:** only use templates the client ships and that we already rely on — `UIPanelButtonTemplate`, `UIPanelCloseButton`, `UIPanelScrollFrameTemplate`, `UIDropDownMenuTemplate` (plus the `UISpecialFrames` global table for Escape-to-close). Do not invent template names.
- **`UIDropDownMenu`:** use the documented helpers already used here — `UIDropDownMenu_Initialize`, `UIDropDownMenu_CreateInfo`, `UIDropDownMenu_AddButton`, `UIDropDownMenu_SetWidth`, `UIDropDownMenu_SetText`. Don't substitute retail menu APIs (`MenuUtil`, `C_Menu`, etc.).
- **`SendChatMessage(msg, channel)`:** valid channel types are `SAY`, `YELL`, `PARTY`, `RAID`, `RAID_WARNING`, `GUILD`, `WHISPER`, `CHANNEL`. `RAID_WARNING` only delivers if you are raid lead/assist (otherwise nothing is sent). Keep the 240-char word-boundary split in `SendLine`.
- **Roster API signatures:** `GetRaidRosterInfo(i)` returns `name, rank, subgroup, ...` (name first); player/unit names come from `UnitName("player")`, `UnitName("party"..i)`, `UnitName("raid"..i)`. Don't assume retail roster helpers.
- **Events:** register with `frame:RegisterEvent(...)` and handle in an `OnEvent` script (see the loader at the bottom of `Core.lua`). Do not use retail-only event utilities.

### Before you finish any change that adds a WoW API call
Ask yourself explicitly: *Does this exact function exist in the TBC-Anniversary client, and am I sure of its signature and return values?* If the answer is anything short of "yes, certain," guard it with the shim pattern or replace it with API the codebase already uses. When you genuinely cannot verify, say so in your summary rather than shipping an unguarded call.

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

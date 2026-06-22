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
This is the established pattern in `Core/Api.lua` (the `ns.api` module) — see `api.InRaid()`, `api.InGroup()`, `api.RaidCount()`, `api.PartyCount()`, and the `api.has()` / `api.hasMethod()` guard helpers. Any call that might be missing on some build MUST be guarded:

```lua
-- Prefer the modern call, fall back to the old one, then a safe default.
local function RaidCount()
    if type(GetNumGroupMembers) == "function" then return GetNumGroupMembers() end
    if type(GetNumRaidMembers) == "function" then return GetNumRaidMembers() end
    return 0
end
```

Rules for shims:
- Guard with `api.has("Foo")` / `type(Foo) == "function"` (or `api.hasMethod(Ns, "Foo")` for namespaces) — **never** call a possibly-missing global bare.
- Always provide a fallback path and a final safe default; never let the function error if every API is absent.
- Add new shims to `Core/Api.lua` (`ns.api`) and reuse them everywhere instead of repeating the guard inline.

### Specific landmines (do not step on these)
- **`C_*` namespaces:** do not assume `C_Timer.After`, `C_ChatInfo.*`, `C_PartyInfo.*`, etc. exist. Guard the namespace **and** the function before calling, with a fallback.
- **No backdrop system:** the UI is deliberately texture-based (see `Edge()` + `SetColorTexture` in `UI/Window.lua` and `UI/EditPanel.lua`). Do **not** reach for `:SetBackdrop`, `BackdropTemplateMixin`, or `"BackdropTemplate"` — they are not guaranteed and we intentionally avoid them.
- **`CreateFrame` templates must be real:** only use templates the client ships and that we already rely on — `UIPanelButtonTemplate`, `UIPanelCloseButton`, `UIPanelScrollFrameTemplate`, `UIDropDownMenuTemplate` (plus the `UISpecialFrames` global table for Escape-to-close). The in-game editor uses a plain `CreateFrame("EditBox")` with `SetMultiLine`/`SetAutoFocus`/`SetMaxLetters` (no template) — do not swap in `InputScrollFrameTemplate` or invent template names.
- **`UIDropDownMenu`:** use the documented helpers already used here — `UIDropDownMenu_Initialize`, `UIDropDownMenu_CreateInfo`, `UIDropDownMenu_AddButton`, `UIDropDownMenu_SetWidth`, `UIDropDownMenu_SetText`. Don't substitute retail menu APIs (`MenuUtil`, `C_Menu`, etc.).
- **`SendChatMessage(msg, channel)`:** valid channel types are `SAY`, `YELL`, `PARTY`, `RAID`, `RAID_WARNING`, `GUILD`, `WHISPER`, `CHANNEL`. `RAID_WARNING` only delivers if you are raid lead/assist (otherwise nothing is sent). Keep the 240-char word-boundary split in `Chat.SendLine` / `util.wrap`.
- **Roster API signatures:** `GetRaidRosterInfo(i)` returns `name, rank, subgroup, ...` (name first); player/unit names come from `UnitName("player")`, `UnitName("party"..i)`, `UnitName("raid"..i)`. Don't assume retail roster helpers. (All of this lives in `api.GroupRoster()`.)
- **Events:** register with `frame:RegisterEvent(...)` and handle in an `OnEvent` script (see the loader in `Core/Boot.lua`). Do not use retail-only event utilities.

### Before you finish any change that adds a WoW API call
Ask yourself explicitly: *Does this exact function exist in the TBC-Anniversary client, and am I sure of its signature and return values?* If the answer is anything short of "yes, certain," guard it with the shim pattern or replace it with API the codebase already uses. When you genuinely cannot verify, say so in your summary rather than shipping an unguarded call.

## File roles

The addon is split into focused modules that share one **private namespace**, `ns` — the addon's second `...` vararg (`local _, ns = ...`). Everything hangs off `ns`; the only remaining globals are `PugHelperDB` (saved vars) and the `SLASH_*` / `SlashCmdList` slash registration.

**Content — edit these for raids/callouts (no engine code):**
- **`Content/Roles.lua`** — role tokens via `ns:RegisterRoles{ ... }` (`key`/`label` pairs).
- **`Content/Raids/<Name>.lua`** — one file per instance via `ns:RegisterInstance("raids", { name, note, sections })`. A `sections` entry can be a bare title string (`"Boss Name"` → a section with no lines yet) or the full `{ title, lines = { ... } }` table; `Content.AddInstance` normalizes both. To add a raid, copy `Karazhan.lua`, change the content, and add the file to `.toc`. The `Content/Heroics/` files register into the **Heroics** category the same way.

**Engine — `Core/` (don't put content here):**
- **`Namespace.lua`** (loads first) — creates the `ns` sub-tables and `ns.Print`.
- **`Util.lua`** (`ns.util`) — pure helpers, **zero** WoW API: `applyDefaults`, `asList`, `deepCopy`, `trim`, `slug`, `wrap`.
- **`Api.lua`** (`ns.api`) — all version-sensitive WoW API behind `has`/`hasMethod` guards (group/roster shims).
- **`Config.lua`** (`ns.Config`) — owns `PugHelperDB`: `DEFAULTS`, channel list, and the **only** typed accessors that touch the saved-vars table.
- **`Content.lua`** (`ns.Content`) — the registry, the fork-on-edit customization layer (`Effective`, `materialize`, line/section mutators), `Validate`, `PruneNames`.
- **`Chat.lua`** (`ns.Chat`) — `Substitute`, `ResolveChannel`, `SendLine`.
- **`Macro.lua`** (`ns.Macro`) — turns a callout line into a draggable WoW macro (`PickupForLine`, `Fits`, `Explain`); see the **drag-to-action-bar macros** mechanic below.
- **`Slash.lua`** (`ns.Slash`) — `/pug` dispatch.
- **`Boot.lua`** (loads last) — the `ADDON_LOADED` loader; wires the init order.

**UI — `UI/` (`ns.UI`):** `Helpers.lua` (shared builders: `UI.Button`, `UI.Tooltip`, `UI.AddBorder` — use these instead of re-rolling CreateFrame/tooltip/border boilerplate), `Window.lua` (main frame, category list, object-pooled message pane, `Refresh`), `NamesPanel.lua` (Set Names overlay), `EditPanel.lua` (in-game callout editor).

**Load order in `.toc` matters** (dependencies flow down): Namespace → Util → Api → Config → Content → Chat → Macro → UI/Helpers → UI/* → Slash → Content data files → Boot. Data files must load **after** `Core/Content.lua` (which defines `ns:RegisterInstance`); `Boot.lua` is always last.

## Key mechanics to preserve

- **Token substitution:** `{KEY}` in a callout line is replaced with the configured name in `Chat.Substitute` via `gsub("{(%w+)}", ...)`. Tokens must be alphanumeric (word chars only); keys come from `Content/Roles.lua`.
- **Customization (fork-on-edit):** built-in callouts are **defaults** registered with `ns:RegisterInstance`. The first time a user edits an instance, `Content.materialize` copies that instance's whole `sections` list into `PugHelperDB.custom[instanceId].sections`, which is then authoritative; `Content.Effective` returns that copy (or a copy of the defaults) and **never mutates** the registered defaults. Sections and lines are addressed by display index (recomputed each render), so titles can repeat (e.g. two "Trash" sections). Edit in-game via the **Edit** toolbar button: click a line to edit / right-click to delete, "+ Add line" per section, click a section title to rename / right-click to delete it / **drag it to reorder** (`Content.MoveSection`; headers `RegisterForDrag("LeftButton")`, drop slot tracked via OnEnter + an insertion-line texture), "+ Add section" at the bottom; **Reset tab** drops the instance's custom copy. Add new mutators in `Content.lua`, not ad-hoc.
- **Chat splitting:** outgoing lines are split at word boundaries to a **240-char** limit (`Config.CHAT_LIMIT`) before `SendChatMessage` — keep this when touching `Chat.SendLine` / `util.wrap`.
- **Drag-to-action-bar macros (`Core/Macro.lua`):** each callout line shows a small grip on its right in **normal mode** (`row.grip` in `UI/Window.lua`, hidden in edit mode so it never clashes with row drag-to-reorder). Dragging/clicking it calls `ns.Macro.PickupForLine`, which creates a **general (account-wide) WoW macro** whose body is `"/pug send <raw callout>"` and `PickupMacro`s it onto the cursor to drop on a bar. The macro is a **snapshot** (the line text *and its `{TOKENS}`* are baked in, so editing the line — or renaming a custom role token it uses — does NOT update an already-placed button; drag again to place a fresh one) but substitutes `{TOKENS}` and resolves the channel **live at click time** via the `/pug send` handler (`Chat.SendLine`). Macro names are a body hash (`"PH"`+base36, ≤16-char client limit) so re-dragging the **same** line reuses one macro; distinct snapshots are distinct macros and placed ones are never auto-deleted (heavy editing accumulates entries in `/macro`). All macro API (`CreateMacro`/`EditMacro`/`GetMacroIndexByName`/`PickupMacro`) is `api.has`-guarded and `pcall`'d (CreateMacro **errors** when the list is full; all three are `#nocombat`); over-long callouts (>`Macro.MAX_LINE`≈245) are refused, never truncated; the gesture is refused in combat (`api.InCombat`) — combat *starting after* a pickup just fails the (protected) bar drop, leaving the macro on the cursor. A line with an unset `{TOKEN}` would make a button that broadcasts it literally (no click-time confirm is possible on a bar), so the grip tooltip warns in amber, mirroring the in-window send guard. First successful pickup prints a once-ever tip (`Config.MacroTipShown`).
- **Role customization (Set Names):** roles are composed by `Content.EffectiveRoles(instanceId)` from built-ins (`Content/Roles.lua`) + global customs + per-instance customs, minus per-tab hidden tokens, then a per-tab **label override** and **display order** are applied. All user role state lives in `PugHelperDB.customRoles = { global, byInstance, hidden, labels, order }` (`labels`/`order` are keyed by instanceId; `order` is a list of uppercased tokens). In the **Set Names** overlay each role row can be deleted (X), **edited** (Edit button → `Content.EditRole`: label for any role; `{TOKEN}` only for customs, since built-in tokens are referenced by callouts — a token change migrates the saved name + sweeps the order/label/hidden maps via `renameTokenInMaps`), and **drag-reordered** (`Content.MoveRole`; rows `RegisterForDrag`, drop slot via OnEnter + an end-zone for the last slot + an insertion-line texture, mirroring the section drag). Editing/reordering are **per-tab**; **Reset roles** drops that tab's customs, hides, labels, and order. Add new role mutators in `Content.lua`; never write `PugHelperDB.customRoles` outside `Config`/`Content`.
- **Channel `AUTO`** resolves RAID → PARTY → SAY based on group state (`Chat.ResolveChannel`).
- **Saved variables:** single global `PugHelperDB`, initialized in `Config.Init()` on `ADDON_LOADED` and merged against `DEFAULTS` via `util.applyDefaults`. Add new persistent settings to `DEFAULTS` in `Config.lua` and expose them through a `Config` accessor — don't read/write `PugHelperDB` elsewhere.
- **UI uses object pooling** (`rowPool`, `headerPool` in `UI/Window.lua`) — reuse pooled frames rather than creating new ones per render.

## Slash commands

`/pug` (alias `/pughelper`): `show`, `toggle`, `edit`, `send TEXT` (broadcast a callout now; what the drag-to-bar line macros run), `name TOKEN Value`, `names`, `channel`, `reset`.

## Conventions

- **Namespace, not globals:** only `PugHelperDB` and `SLASH_*` / `SlashCmdList` are global; everything else lives on `ns`. Modules are `ns.PascalCase` (`Config`, `Content`, `Chat`, `UI`, `Slash`) or lowercase utility namespaces (`ns.util`, `ns.api`). Start every file with `local _, ns = ...` (use `ADDON_NAME` only where needed, e.g. `Boot.lua`).
- Locals/functions: camelCase. Constants: `UPPER_SNAKE_CASE`. Keep file-internal helpers `local`.

## Verifying changes

There is no automated test framework. Verify in-game: save the files in this AddOns folder, then `/reload` (or relog) in WoW and exercise the change manually via `/pug` (including the **Edit** button for callout customization). Optionally lint with luacheck (config in `.luacheckrc`): `& "C:\Users\garneck\luacheck\luacheck.cmd" .`.

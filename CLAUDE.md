# Martini Hub (Fix It Up! script)

A Roblox exploit script for **Fix It Up!** (place 72712036210947). It uses the Obsidian UI library (deividcomsono) and is titled **"Martini Hub"** (renamed from "CruelHub" on 2026-10-15). The owner is Martinikaws, who writes in English and Italian.

**Look:** Emerald theme set with `ThemeManager:SetDefaultTheme` (background `0a0d0b`, main `121714`, accent `10b981`, outline `1d2a23`, text `e8f2ec`), Gotham font, corner radius 6. The window icon is `assets/logo.png` from this repo, cached as `MartiniHub/logo_v1.png`; bump the `_v1` suffix when the logo changes, or old caches keep showing the old one. If the image can't load, it falls back to the Lucide `wrench` icon. Webhook posts use the username "Martini Hub". Internal names (`FIU_*` globals, the `FixItUp/` settings folder) were kept so existing settings still load.

Everything is in one file, `fiu_main.lua` (~5,650 lines). Users load it with:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Martinikaws/fix-it-up/main/fiu_main.lua"))()
```

Pushing to `main` updates every user. GitHub's raw link can take a few minutes to refresh. The server-hop reload (`RELOAD` in the script) also downloads from this URL, falling back to the local `fiu_main.lua` if the download fails. The script was forked from `LeeDoesStuff/Lee-sStuff/fix-it-up/fiu_main.lua`. The header mentions `fix-it-up-spec.md`, but that file is not in this repo.

## Hard rules

1. **Luau's 200-local register limit.** The main chunk sits right at the limit. Adding a new top-level `local` breaks the whole script with `Out of local registers when trying to allocate X: exceeded limit 200`. Executors compile without optimization, so default `-O1`/`-O2` builds hide the problem.
   - Put new state in existing tables (`HOOK.*`, `farm.*`, `AUC.*`, `CANDY.*`, `HOOK.WH.*`, `HOOK.TR.*`) or inside `do ... end` blocks.
   - **Compile at every level before pushing:**
     ```sh
     for o in -O0 -O1 -O2; do for g in -g0 -g1 -g2; do luau-compile --null $o $g fiu_main.lua; done; done
     ```
     Get `luau-compile` from https://github.com/luau-lang/luau/releases. Big blocks such as the Drive tab hit the same limit on their own, so keep checking there too.
2. **Never hold a car instance across a wait.** A respawn, or the car streaming out while you're at the store, swaps the instance in `workspace.Vehicles`, and the old one loses its children: indexing it throws "Values / Body is not a valid member of Model". Read the car through `HOOK.carNow(e, timeout)` (the current instance once `Values.Engine.Wear` exist) or `carOf(e)` at each step, and use `FindFirstChild` on anything under it.
3. **Multiple accounts share one executor workspace.** Any state that belongs to one account must go in a file named with its `LP.UserId`. A shared file lets one account overwrite another's data; this caused real bugs, now fixed.
4. **No in-game test from the cloud.** Code was written against the measured mechanics below. Anything marked *untested* needs an in-game check.
5. **Commits:** small, with a message explaining *why*. The author is `Martinikaws`.

## Files in the executor workspace (`FixItUp/`)

| File | What |
|---|---|
| `owned_<UserId>.json` | flip-tagged cars (the **only** cars auto sell sells), migrated from the old shared `owned.json` |
| `favorites_<UserId>.json` | locked cars: never sold, never touched by auto |
| `pending_buys_<UserId>.json` | buys written the moment they are confirmed, used to re-tag a car after a crash (matched on the server's `BoughtAt`) |
| `../fiu_hop_<UserId>.json` | server-hop settings and visited servers (workspace root, not `FixItUp/`) |
| `webhook.json` | Discord webhook URL and settings (shared, kept out of SaveManager configs) |
| `accounts/<UserId>.json`, `accounts_last.json` | multi-account heartbeat (every 20 s) and the last grouped money report |
| `menukey.json` | open/close menu key (`key`), 3D-rendering key (`render`), stats screen key (`stats`) |
| `state.json` | sell cooldown, auction stats, auction sell queue (`STATE.auction.sell`) |
| `drive.json` | km per car, Drive tab car pick, auto-tune results |
| `life.log`, `errors.txt` | lifecycle log (hops, anti-mod, auctions) and errors caught by `guard()` |

## Game mechanics measured (keep these in mind)

- **Store:** clicks only register within ~32 studs (game update 2026-10-08), so stand next to the item. The store ignores quick re-buys of the same item, so retry with a growing pause.
- **Spark plugs etc.:** parts without a repair machine are bought new. The store lookup is loose (it ignores spacing, case and a trailing "s"), and replacement buys may ignore the reserve (`CFG.replaceNoReserve`).
- **Auctions:** 12 garages at `Workspace.Utils.Auctions`, using only the €75,000 `MoneyBuy` prompt (never Robux). An open within ~3.5 s of the previous one is silently ignored. Odds: junk car 40%, cash prizes, rare car 0.5%.
- **Distance (km):** the game counts it **only while the wheels touch ground the server knows about.** A client-only road counts nothing; this was tested and removed. Measured speeds on the Highway route:

  | Speed (studs/s) | Share of driven distance counted | Credited km/min |
  |---|---|---|
  | 115 | 69% | ≈1.20 |
  | 120 | 63% | ≈1.16 |
  | 150 | n/a | ~0.9–1.0 |
  | 210 | n/a | ~0.1–0.5 |

  The best speed is probably around 110–115. The Drive tab's **Auto tune** runs 95/105/115/125/135 and keeps the best.
- **Candy event (2026-10-10):** `Workspace.Event` has 12 numbered slots (Models), each holding `LOLLYPOPYS`, `LOLLYJAR` and a **ClickDetector**. Clicking a jar collects it. Far slots don't have their lollipop pieces streamed in, but the slot model and its ClickDetector are always present. Slots 1 and 11 share a position. No player candy value was found; refill timing is unknown.
- **Traffic:** its folder hasn't been found yet. `HOOK.TR` finds it by name (traffic / npccar / aicar …), and the Settings → Traffic section has a dump button.

## Features added in the 2026-10-08 → 10 session

- Spark plug fix: loose store lookup, retries, reserve bypass, and a notification when it puts a worn part back.
- **Webhook tab:**
  - rare spawn alerts with a ping;
  - money reports that include km driven, cars sold and "you owe";
  - **multi-account grouping**: the lowest live UserId sends one combined report, and only one account per server sends each spawn alert.
- Settings:
  - remappable open/close menu key;
  - 3D-rendering toggle with its own key;
  - Traffic section (disable traffic / disable traffic collisions, both on at every load) — *untested: the traffic folder hasn't been found*.
- Server hop: Prefer Largest/Smallest option; settings per account; a notification when a rule break triggers a hop.
- **Chat keyword hop** (Chat tab → Keyword hop): `STAFF.noteChat` checks every line other players say against `HOP.kwWords`; a match runs `STAFF.chatHop`, which sets `STAFF.leaving` (gates new actions), waits for the running job, then `STAFF.hopOnce()` hops once via `candidates()` (retries 4 min, then gives up). 90 s cooldown (`HOP.kwLast`) so a keyword in the next server cannot start a loop; also posts to the webhook. Only the repair must finish before the hop (parts in the machines are wiped by a server change); clean/paint are saved as `cleanPending`/`paintPending` on the owned entry and done by `HOOK.finishLook` (right after the repair if no hop is waiting, otherwise in the new server by `autoStep` before selling). *Untested in game.*
- Drive farm:
  - auto resume (with a "no km counted for 2 min" watchdog);
  - Auto pick car;
  - credited km/min meter and Auto tune.
- Flip tags kept across crashes (per-account files, pending buys, re-keying); buttons to tag or untag a car manually.
- **Auctions tab:**
  - cases to open, non-stop mode, stop at cash, stop on rare (the 4 named prize cars or any S/EX car);
  - **auto sell of won junk cars, washed first**, with a queue that survives crashes;
  - this-run and all-time stats.
- **Candy tab:** collects all 12 jars, nearest first, clicking each once and rechecking every 5 min. *Untested: refill time unknown.*

## Added 2026-10-15 (local Claude Code session)

- **Rebrand:** Martini Hub, Emerald theme, logo (see the top of this file).
- **Auto repair crash fix:** `repairCar` is a pcall wrapper over `HOOK.repairRaw`. A throw counts as one failed try (before, it skipped autoStep's try counter and the same car was retried every 2 s forever), disconnects the parts pin (`HOOK.repairPin`) and reinstalls the pulled parts (`HOOK.repairParts`).
- **Auto rejoin** (Server hop tab, `HOP.rejoin`, on by default): `STAFF.rejoin` runs on `GuiService.ErrorMessageChanged` and CoreGui's `ErrorPrompt`. It acts only on a real disconnect (a 2xx code, or no `ClientReplicator`), never after the anti-mod kick (`STAFF.gone`) or on error 273. It queues `RELOAD`, then calls `TeleportService:Teleport(PlaceId)` with retries. *Untested in game.*
- **Stuck watchdog** (Auto tab, `CFG.wdOn/wdMins/wdHop`): the auto loop is `HOOK.autoLoop(gen)`, and `HOOK.WD` tracks the step start and the error streak. A step running past the limit, or 10+ errors over 3 min, fires `HOOK.wdFire`: cancel the run, reinstall pulled parts, clear `busy`, reset the character, restart. A second hang within 30 min hops via `STAFF.hopOnce`. Error loops never hop and stop after 3 resets. *Untested in game.*
- **Stats screen** (Settings > Menu, key F6 by default): `HOOK.statsShow(on)` builds a full-screen ScreenGui (DisplayOrder 900, under Obsidian's 998) in the theme's MainColor with 9 stat cards, and turns 3D rendering off. It reads `HOOK.farm` and `HOOK.candy`, published from their tabs. *Untested in game.*

## Open items / verify in game

- Candy: does a collected jar disappear, respawn, or stay put? How long until it refills? Tune `CANDY.wait` (300 s).
- Traffic: find the real folder (use the dump button), then point `HOOK.TR.scan` at it.
- Auctions auto sell: check the wash → sell flow and the sell timer on won cars.
- Auto tune results on the Highway (the first run was spoiled by the removed private road).

## Debug script

`fiu_debug.lua` (standalone, not loaded by the main script) tests the game pieces the script depends on and writes a report to `FixItUp/debug_<UserId>.txt` and the clipboard: executor functions, game paths, repair shops/machines, store clicks (fireclickdetector vs real clicks), spawn + five ways of sitting in the DriveSeat with state/message logging, a drive-loop ejection check, and hood + remove/reinstall one part. It unloads the main script first. Load it with `loadstring(game:HttpGet("https://raw.githubusercontent.com/Martinikaws/fix-it-up/main/fiu_debug.lua"))()`. Paste its report back when auto/drive misbehaves.

## Potassium MCP (local only)

The owner runs the Potassium executor, which exposes an MCP server at `http://127.0.0.1:8225/mcp` with a bearer token. Add it to your **local** Claude Code config; never commit the token. With it, you can run Lua in the live client to inspect `Workspace.Event`, find the traffic folder, and check values before changing the script.

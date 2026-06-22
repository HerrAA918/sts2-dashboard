# Slay the Spire 2 Run History Dashboard

A fully offline, self-contained run analytics dashboard and database compendium for **Slay the Spire 2**. 

This dashboard allows you to import, visualize, and analyze your runs (both Single Player and Co-op) directly from your game run files.

## Features

- **Run History**: Table views of all loaded single player and co-op runs with pagination, search, and sorting.
- **Run Map Timeline**: Detailed interactive step-by-step path visualizer for each run showing floors, events, combats, rest sites, shops, and boss nodes.
- **Card & Relic Analytics**: Win rates, pick rates, survival distributions, and playstyle correlation tables based on your uploaded history.
- **Survival & Playstyle Charts**: Floor-by-floor survival rates and radar charts depicting your playstyle (Aggressive, Defensive, Tactical, Wealthy).
- **Offline Compendium**: A complete Slay the Spire 2 database of Cards, Relics, and Monsters with hover tooltips, rarity color-coding, and move-set/intent lists.
- **Privacy First**: Fully client-side. No data is sent to any server. Your runs are parsed locally and stored in your browser's `localStorage` for quick access next time.

## Where to Find Your Run History Files

To import your runs into the dashboard, drag and drop the JSON files from your game's run history folder into the dashboard. You can find these files in the following locations:

### Windows
- **Steam Cloud Location (Recommended)**:
  `C:\Program Files (x86)\Steam\userdata\<YOUR_STEAM_ID>\2868840\remote\profile1\saves\history\`
- **Local AppData Location**:
  `%AppData%\SlayTheSpire2\steam\<YOUR_STEAM_ID>\profile1\saves\history\`

*(Note: Replace `<YOUR_STEAM_ID>` with your actual unique Steam numeric ID, and `profile1` with your corresponding in-game profile number if you use multiple profiles.)*

### macOS
`~/Library/Application Support/Steam/userdata/<YOUR_STEAM_ID>/2868840/remote/profile1/saves/history/`

### Linux (Steam Deck / Proton)
`~/.steam/steam/userdata/<YOUR_STEAM_ID>/2868840/remote/profile1/saves/history/`

## Architecture

`sts2_dashboard.html` is **hand-maintained directly** — its CSS, JavaScript, and markup are edited in place. The game database is embedded inside it as a `const sts2Database = { ... }` block, fenced by `/* STS2_DATABASE_START */` … `/* STS2_DATABASE_END */` markers.

Game data and the dashboard's UI are therefore updated independently:

- **UI changes** (layout, styling, new features) → edit `sts2_dashboard.html` directly.
- **Game-data changes** → run `compile_db.ps1` then `embed_database.ps1`, which swaps *only* the marked database block and leaves everything else untouched.

> **Do not run `generate_dashboard.ps1`.** It is deprecated and disabled (it throws on start). It was the original full-HTML generator, but the dashboard has since diverged from it; running it would overwrite all current UI work. It is retained only as a reference for the run-parsing logic.

## Files in this Repository

- `sts2_dashboard.html`: The ready-to-use offline dashboard, hand-maintained. Open in any modern web browser.
- `compile_db.ps1`: Database compiler — pulls raw game data from the Spire Codex API and builds `sts2_database.json`.
- `embed_database.ps1`: Injects `sts2_database.json` into the dashboard's embedded database block (between the `STS2_DATABASE` markers), without regenerating the rest of the HTML.
- `sts2_database.json`: The compiled database of cards, relics, potions, monsters, events, and keywords used by the dashboard.
- `cards_api.json`, `relics_api.json`, `monsters_api.json`, `encounters_api.json`, `events_api.json`, `potions_api.json`, `keywords_api.json`: Source API data caches.
- `validate_js.js`: Helper that verifies the syntax of every `<script>` block in `sts2_dashboard.html`. Run `node validate_js.js` after editing the dashboard's JS.
- `generate_dashboard.ps1`: **Deprecated / disabled.** Original full-HTML generator, kept for reference only.

## How to Update the Game Data

When the game gets a balance patch or new content, refresh the embedded database:

```powershell
.\compile_db.ps1       # rebuild sts2_database.json from the API caches
.\embed_database.ps1   # swap the new database into sts2_dashboard.html
```

Only the embedded database block changes; the dashboard UI is preserved. (The GitHub Action below does this automatically.)

## Auto-Update (GitHub Actions)

This repository includes a GitHub Actions workflow that **automatically checks for game updates daily** and rebuilds the dashboard if new data is found.

### How it works

1. Every day at 06:00 UTC, the workflow downloads the latest card, relic, monster, encounter, event, potion, and keyword data from the [Spire Codex](https://github.com/ptrlrd/spire-codex) repository.
2. It compares the downloaded data against the committed API JSON files.
3. If any changes are detected, it rebuilds the compiled database (`compile_db.ps1` → `sts2_database.json`) and embeds it into the dashboard's database block (`embed_database.ps1` → `sts2_dashboard.html`). The dashboard UI is left untouched.
4. The updated data files and dashboard are automatically committed and pushed back to the repository.

If no changes are detected, the workflow exits cleanly with no commit.

### Manual trigger

You can also trigger an update manually at any time:

1. Go to the **Actions** tab on the GitHub repository page.
2. Select the **Auto-Update Game Database** workflow.
3. Click **Run workflow** → **Run workflow**.

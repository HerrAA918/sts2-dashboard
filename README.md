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

## Files in this Repository

- `sts2_dashboard.html`: The fully compiled, ready-to-use offline dashboard. You can open this in any modern web browser.
- `generate_dashboard.ps1`: The PowerShell generator script that compiles the HTML, CSS, JS, and database JSON into a single self-contained file.
- `compile_db.ps1`: The database compiler script that pulls raw game data from the Spire Codex API to build the game database.
- `sts2_database.json`: The compiled database of cards, relics, and monsters used by the dashboard.
- `cards_api.json`, `relics_api.json`, `monsters_api.json`, `encounters_api.json`: Source API data caches.
- `validate_js.js`: A helper validation script to verify JS syntax inside the PowerShell builder script before generation.

## How to Regenerate the Dashboard

If you modify the generator script or database, you can rebuild the dashboard by running the following command in PowerShell:

```powershell
.\generate_dashboard.ps1
```

This will output/refresh `sts2_dashboard.html` in the same directory.

## Auto-Update (GitHub Actions)

This repository includes a GitHub Actions workflow that **automatically checks for game updates daily** and rebuilds the dashboard if new data is found.

### How it works

1. Every day at 06:00 UTC, the workflow downloads the latest card, relic, monster, and encounter data from the [Spire Codex](https://github.com/ptrlrd/spire-codex) repository.
2. It compares the downloaded data against the committed API JSON files.
3. If any changes are detected, it rebuilds the compiled database (`sts2_database.json`) and regenerates the dashboard HTML (`sts2_dashboard.html`).
4. The updated files are automatically committed and pushed back to the repository.

If no changes are detected, the workflow exits cleanly with no commit.

### Manual trigger

You can also trigger an update manually at any time:

1. Go to the **Actions** tab on the GitHub repository page.
2. Select the **Auto-Update Game Database** workflow.
3. Click **Run workflow** → **Run workflow**.

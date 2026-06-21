# Disable local saves scanning by default to start the dashboard in a clean, blank state.
# To scan local Steam saves, uncomment the lines below and set your own Steam user ID.
# $runsDir = "C:\Program Files (x86)\Steam\userdata\<YOUR_STEAM_ID>\2868840\remote\profile1\saves\history"
# $runFiles = Get-ChildItem -Path $runsDir -Filter "*.run"

$parsedRuns = @()

foreach ($file in $runFiles) {
    try {
        $content = Get-Content -Raw -Path $file.FullName -Encoding utf8 -ErrorAction Stop
        $data = ConvertFrom-Json $content -ErrorAction Stop
        
        # Check start_time
        $startTimeRaw = $data.start_time
        if ($startTimeRaw) {
            $date = [datetime]::new(1970, 1, 1, 0, 0, 0, [datetimekind]::Utc).AddSeconds($startTimeRaw).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
        } else {
            $date = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            $startTimeRaw = [int64]($file.LastWriteTime - [datetime]::new(1970, 1, 1)).TotalSeconds
        }
        
        # Character(s) & Players parsing
        $isMultiplayer = $false
        $players = @()
        if ($data.players) {
            $isMultiplayer = $data.players.Count -gt 1
            foreach ($p in $data.players) {
                $pChar = $p.character
                if ($pChar.StartsWith("CHARACTER.")) {
                    $pChar = $pChar.Substring(10)
                    $pChar = $pChar.Substring(0, 1).ToUpper() + $pChar.Substring(1).ToLower()
                }
                
                $pRelics = @()
                if ($p.relics) {
                    foreach ($relic in $p.relics) {
                        if ($relic.id) { $pRelics += $relic.id }
                    }
                }
                
                $pDeck = @()
                if ($p.deck) {
                    foreach ($card in $p.deck) {
                        if ($card.id) { $pDeck += $card.id }
                    }
                }
                
                $players += @{
                    character = $pChar
                    relics = $pRelics
                    deck = $pDeck
                }
            }
        }
        
        $charNames = @()
        foreach ($p in $players) { $charNames += $p.character }
        $character = $charNames -join " + "
        
        $win = $data.win -eq $true
        $abandoned = $data.was_abandoned -eq $true
        $ascension = if ($data.ascension -ne $null) { $data.ascension } else { 0 }
        $runTime = if ($data.run_time) { $data.run_time } else { 0 }
        
        $killedBy = "N/A"
        $encounter = ""
        if (-not $win) {
            $encounter = $data.killed_by_encounter
            $event = $data.killed_by_event
            if ($encounter -and $encounter -ne "NONE.NONE") {
                $killedBy = $encounter.Replace("ENCOUNTER.", "").Replace("MONSTER.", "").Replace("_", " ")
                $killedBy = (Get-Culture).TextInfo.ToTitleCase($killedBy.ToLower())
            } elseif ($event -and $event -ne "NONE.NONE") {
                $killedBy = $event.Replace("EVENT.", "").Replace("_", " ")
                $killedBy = (Get-Culture).TextInfo.ToTitleCase($killedBy.ToLower())
            } elseif ($abandoned) {
                $killedBy = "Abandoned"
            } else {
                $killedBy = "Unknown Cause"
            }
        }
        
        # Floor count
        $floors = 0
        if ($data.map_point_history) {
            foreach ($act in $data.map_point_history) {
                if ($act) {
                    $floors += $act.Count
                }
            }
        }
        
        $seed = if ($data.seed) { $data.seed } else { "Unknown" }
        $version = if ($data.build_id) { $data.build_id } else { "Unknown" }
        
        $relics = if ($players.Count -gt 0) { $players[0].relics } else { @() }
        $deck = if ($players.Count -gt 0) { $players[0].deck } else { @() }
        
        # Minimize map history to save storage space
        $minimizedMapHistory = @()
        if ($data.map_point_history) {
            foreach ($act in $data.map_point_history) {
                if ($act) {
                    $minimizedAct = @()
                    foreach ($node in $act) {
                        $rooms = @()
                        if ($node.rooms) {
                            foreach ($r in $node.rooms) {
                                $rooms += @{
                                    model_id = $r.model_id
                                    turns_taken = [int]$r.turns_taken
                                }
                            }
                        }
                        
                        $playerStats = @()
                        if ($node.player_stats) {
                            foreach ($p in $node.player_stats) {
                                $cardChoices = @()
                                if ($p.card_choices) {
                                    foreach ($cc in $p.card_choices) {
                                        if ($cc.was_picked -eq $true) {
                                            $cardChoices += @{
                                                was_picked = $true
                                                card = @{ id = $cc.card.id }
                                            }
                                        }
                                    }
                                }
                                
                                $relicChoices = @()
                                if ($p.relic_choices) {
                                    foreach ($rc in $p.relic_choices) {
                                        if ($rc.was_picked -eq $true) {
                                            $relicChoices += @{
                                                was_picked = $true
                                                choice = $rc.choice
                                            }
                                        }
                                    }
                                }
                                
                                $ancientChoices = @()
                                if ($p.ancient_choice) {
                                    foreach ($ac in $p.ancient_choice) {
                                        if ($ac.was_chosen -eq $true) {
                                            $ancientChoices += @{
                                                was_chosen = $true
                                                TextKey = $ac.TextKey
                                            }
                                        }
                                    }
                                }
                                
                                $playerStats += @{
                                    current_hp = [int]$p.current_hp
                                    max_hp = [int]$p.max_hp
                                    damage_taken = [int]$p.damage_taken
                                    hp_healed = [int]$p.hp_healed
                                    gold_spent = [int]$p.gold_spent
                                    gold_gained = [int]$p.gold_gained
                                    cards_gained_count = if ($p.cards_gained) { $p.cards_gained.Count } else { 0 }
                                    rest_site_choices = $p.rest_site_choices
                                    card_choices = $cardChoices
                                    relic_choices = $relicChoices
                                    ancient_choice = $ancientChoices
                                }
                            }
                        }
                        
                        $minimizedAct += @{
                            map_point_type = $node.map_point_type
                            rooms = $rooms
                            player_stats = $playerStats
                        }
                    }
                    $minimizedMapHistory += ,$minimizedAct
                }
            }
        }
        
        $parsedRuns += [PSCustomObject]@{
            id = $file.BaseName
            timestamp = $startTimeRaw
            date = $date
            character = $character
            win = $win
            abandoned = $abandoned
            ascension = [int]$ascension
            runTime = [int]$runTime
            killedBy = $killedBy
            killedByEncounter = $encounter
            floors = [int]$floors
            seed = $seed
            relics = $relics
            deck = $deck
            isMultiplayer = $isMultiplayer
            players = $players
            version = $version
            mapPointHistory = $minimizedMapHistory
        }
    } catch {
        Write-Warning "Failed to parse $($file.Name): $_"
    }
}

# Sort by Timestamp ascending
if ($parsedRuns -and $parsedRuns.Count -gt 0) {
    $parsedRuns = $parsedRuns | Sort-Object timestamp
    $jsonData = ConvertTo-Json $parsedRuns -Depth 10
} else {
    $jsonData = "[]"
}

# HTML template single-quoted here-string (prevents PowerShell variable/backtick interpolation!)
$htmlTemplate = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Slay the Spire 2 - Run History Dashboard</title>
    <!-- Google Fonts -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700;800&family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <!-- Chart.js -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <!-- JSZip (for reading zip files directly in browser) -->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js"></script>
    
    <style>
        :root {
            --bg-color: #080c14;
            --card-bg: rgba(15, 23, 42, 0.65);
            --card-border: rgba(255, 255, 255, 0.06);
            --text-main: #f8fafc;
            --text-muted: #94a3b8;
            --accent-primary: #8b5cf6;
            --accent-primary-hover: #7c3aed;
            --accent-success: #10b981;
            --accent-danger: #ef4444;
            --accent-warning: #f59e0b;
            
            --char-ironclad: #ef4444;
            --char-silent: #10b981;
            --char-defect: #3b82f6;
            --char-regent: #fbbf24;
            --char-necrobinder: #a855f7;
            --char-unknown: #64748b;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            background-color: var(--bg-color);
            background-image: 
                radial-gradient(at 0% 0%, rgba(139, 92, 246, 0.12) 0px, transparent 50%),
                radial-gradient(at 50% 0%, rgba(59, 130, 246, 0.08) 0px, transparent 50%),
                radial-gradient(at 100% 0%, rgba(20, 184, 166, 0.12) 0px, transparent 50%);
            background-attachment: fixed;
            font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            color: var(--text-main);
            padding: 24px;
            min-height: 100vh;
        }

        /* Scrollbar styling */
        ::-webkit-scrollbar {
            width: 8px;
            height: 8px;
        }
        ::-webkit-scrollbar-track {
            background: rgba(15, 23, 42, 0.3);
        }
        ::-webkit-scrollbar-thumb {
            background: rgba(255, 255, 255, 0.1);
            border-radius: 4px;
        }
        ::-webkit-scrollbar-thumb:hover {
            background: rgba(255, 255, 255, 0.2);
        }

        header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 24px;
            padding-bottom: 16px;
            border-bottom: 1px solid rgba(255, 255, 255, 0.05);
            flex-wrap: wrap;
            gap: 16px;
        }

        .logo-area {
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .logo-icon {
            width: 40px;
            height: 40px;
            background: linear-gradient(135deg, var(--accent-primary), #3b82f6);
            border-radius: 10px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: 800;
            font-size: 22px;
            box-shadow: 0 4px 15px rgba(139, 92, 246, 0.4);
        }

        h1 {
            font-family: 'Outfit', sans-serif;
            font-size: 26px;
            font-weight: 800;
            background: linear-gradient(to right, #f8fafc, #cbd5e1);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }

        .sub-heading {
            font-size: 14px;
            color: var(--text-muted);
            margin-top: 2px;
        }

        .header-actions {
            display: flex;
            align-items: center;
            gap: 16px;
        }

        .btn-group {
            display: flex;
            gap: 8px;
        }

        .import-btn {
            display: inline-flex;
            align-items: center;
            background: linear-gradient(135deg, var(--accent-primary), var(--accent-primary-hover));
            color: #fff;
            border-radius: 8px;
            padding: 8px 16px;
            font-size: 13.5px;
            font-weight: 700;
            cursor: pointer;
            border: 1px solid rgba(255, 255, 255, 0.1);
            box-shadow: 0 4px 12px rgba(139, 92, 246, 0.25);
            transition: all 0.2s ease;
        }

        .import-btn:hover {
            transform: translateY(-1px);
            box-shadow: 0 6px 16px rgba(139, 92, 246, 0.35);
            background: linear-gradient(135deg, var(--accent-primary-hover), #6d28d9);
        }

        .import-btn:active {
            transform: translateY(1px);
        }

        .reset-btn {
            display: inline-flex;
            align-items: center;
            background: rgba(255, 255, 255, 0.05);
            color: var(--text-muted);
            border-radius: 8px;
            padding: 8px 16px;
            font-size: 13.5px;
            font-weight: 700;
            cursor: pointer;
            border: 1px solid rgba(255, 255, 255, 0.08);
            transition: all 0.2s ease;
            outline: none;
            font-family: inherit;
        }

        .reset-btn:hover {
            background: rgba(255, 255, 255, 0.1);
            color: var(--text-main);
            border-color: rgba(255, 255, 255, 0.15);
        }

        .reset-btn:active {
            transform: translateY(1px);
        }

        .meta-info {
            text-align: right;
            font-size: 13px;
            color: var(--text-muted);
        }

        /* Tabs styling */
        .tab-container {
            display: flex;
            gap: 4px;
            background: rgba(15, 23, 42, 0.5);
            padding: 4px;
            border-radius: 8px;
            border: 1px solid rgba(255, 255, 255, 0.05);
            margin-left: 24px;
            margin-right: auto;
        }

        .tab-btn {
            background: transparent;
            border: none;
            color: var(--text-muted);
            padding: 6px 16px;
            font-size: 13px;
            font-weight: 700;
            cursor: pointer;
            border-radius: 6px;
            transition: all 0.2s;
            font-family: inherit;
            outline: none;
        }

        .tab-btn:hover {
            color: var(--text-main);
        }

        .tab-btn.active {
            background: rgba(139, 92, 246, 0.2);
            color: #d8b4fe;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        }

        /* Stats Cards */
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 16px;
            margin-bottom: 24px;
        }

        .card {
            background: var(--card-bg);
            backdrop-filter: blur(16px);
            -webkit-backdrop-filter: blur(16px);
            border: 1px solid var(--card-border);
            border-radius: 16px;
            padding: 20px;
            box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.25);
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
            position: relative;
            overflow: hidden;
        }

        .card:hover {
            border-color: rgba(255, 255, 255, 0.12);
            transform: translateY(-2px);
            box-shadow: 0 12px 40px 0 rgba(0, 0, 0, 0.35);
        }

        .card-glow {
            position: absolute;
            top: -20px;
            right: -20px;
            width: 80px;
            height: 80px;
            background: var(--accent-primary);
            filter: blur(40px);
            opacity: 0.15;
            border-radius: 50%;
            pointer-events: none;
        }

        .card-title {
            font-size: 13px;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            color: var(--text-muted);
            font-weight: 600;
            margin-bottom: 8px;
        }

        .card-value {
            font-family: 'Outfit', sans-serif;
            font-size: 32px;
            font-weight: 700;
            margin-bottom: 4px;
        }

        .card-subtext {
            font-size: 12px;
            color: var(--text-muted);
        }
        
        .kpi-card {
            cursor: help;
        }

        /* Filter Panel */
        .filter-panel {
            display: flex;
            flex-wrap: wrap;
            gap: 12px;
            background: rgba(15, 23, 42, 0.4);
            border: 1px solid var(--card-border);
            border-radius: 14px;
            padding: 16px;
            margin-bottom: 24px;
            align-items: center;
        }

        .search-wrapper {
            position: relative;
            flex-grow: 1;
            min-width: 200px;
        }

        .search-input {
            width: 100%;
            background: rgba(0, 0, 0, 0.3);
            border: 1px solid var(--card-border);
            border-radius: 8px;
            padding: 10px 14px;
            color: var(--text-main);
            font-family: inherit;
            font-size: 14px;
            outline: none;
            transition: border-color 0.2s;
        }

        .search-input:focus {
            border-color: var(--accent-primary);
        }

        .select-filter {
            background: rgba(0, 0, 0, 0.3);
            border: 1px solid var(--card-border);
            border-radius: 8px;
            padding: 10px 14px;
            color: var(--text-main);
            font-family: inherit;
            font-size: 14px;
            outline: none;
            cursor: pointer;
            min-width: 140px;
        }

        .select-filter:focus {
            border-color: var(--accent-primary);
        }

        .char-pills {
            display: flex;
            gap: 8px;
            flex-wrap: wrap;
        }

        .char-pill {
            padding: 8px 16px;
            border-radius: 20px;
            font-size: 13px;
            font-weight: 600;
            cursor: pointer;
            border: 1px solid rgba(255, 255, 255, 0.05);
            background: rgba(255, 255, 255, 0.02);
            transition: all 0.2s ease;
            color: var(--text-muted);
        }

        .char-pill.active {
            color: #fff;
        }

        .char-pill[data-char="all"].active { background: #334155; border-color: #475569; }
        .char-pill[data-char="ironclad"].active { background: var(--char-ironclad); border-color: var(--char-ironclad); }
        .char-pill[data-char="silent"].active { background: var(--char-silent); border-color: var(--char-silent); }
        .char-pill[data-char="defect"].active { background: var(--char-defect); border-color: var(--char-defect); }
        .char-pill[data-char="regent"].active { background: var(--char-regent); border-color: var(--char-regent); }
        .char-pill[data-char="necrobinder"].active { background: var(--char-necrobinder); border-color: var(--char-necrobinder); }
        .char-pill[data-char="shared"].active { background: #64748b; border-color: #64748b; }


        .char-icon-mini {
            width: 14px;
            height: 14px;
            border-radius: 50%;
            margin-right: 6px;
            vertical-align: middle;
            border: 1px solid rgba(255, 255, 255, 0.25);
            background: rgba(0, 0, 0, 0.3);
            display: inline-block;
        }

        .char-pill:hover {
            transform: scale(1.03);
            border-color: rgba(255, 255, 255, 0.15);
        }

        /* Layout Grid */
        .dashboard-grid {
            display: grid;
            grid-template-columns: 1.8fr 1.2fr;
            gap: 24px;
        }

        @media (max-width: 1024px) {
            .dashboard-grid {
                grid-template-columns: 1fr;
            }
        }

        /* Charts section */
        .charts-container {
            display: grid;
            grid-template-columns: 1.2fr 0.8fr;
            gap: 16px;
            margin-bottom: 24px;
        }

        @media (max-width: 768px) {
            .charts-container {
                grid-template-columns: 1fr;
            }
        }

        .chart-box {
            height: 280px;
            display: flex;
            flex-direction: column;
            justify-content: center;
        }

        .chart-box h3 {
            font-size: 14px;
            font-weight: 600;
            color: var(--text-muted);
            margin-bottom: 12px;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }

        .chart-wrapper {
            position: relative;
            flex-grow: 1;
            width: 100%;
            height: 100%;
        }

        /* Runs Table List */
        .runs-container {
            display: flex;
            flex-direction: column;
            gap: 12px;
        }

        .runs-header-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 8px;
        }

        .runs-header-row h3 {
            font-family: 'Outfit', sans-serif;
            font-size: 18px;
            font-weight: 700;
        }

        .runs-count-badge {
            background: rgba(139, 92, 246, 0.2);
            color: #c084fc;
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 700;
        }

        .table-wrapper {
            max-height: 520px;
            overflow-y: auto;
            border: 1px solid var(--card-border);
            border-radius: 12px;
            background: rgba(15, 23, 42, 0.4);
        }

        table {
            width: 100%;
            border-collapse: collapse;
            text-align: left;
            font-size: 13.5px;
        }

        th {
            background: rgba(15, 23, 42, 0.8);
            position: sticky;
            top: 0;
            padding: 12px 16px;
            color: var(--text-muted);
            font-weight: 600;
            border-bottom: 1px solid var(--card-border);
            z-index: 10;
            cursor: pointer;
            user-select: none;
            transition: background 0.15s ease, color 0.15s ease;
        }

        th:hover {
            background: rgba(30, 41, 59, 0.95);
            color: var(--text-main);
        }

        td {
            padding: 12px 16px;
            border-bottom: 1px solid rgba(255, 255, 255, 0.03);
            vertical-align: middle;
        }

        tr {
            cursor: pointer;
            transition: background 0.15s ease;
        }

        tr:hover {
            background: rgba(255, 255, 255, 0.03);
        }

        tr.selected {
            background: rgba(139, 92, 246, 0.12) !important;
            border-left: 3px solid var(--accent-primary);
        }

        .badge {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            padding: 4px 8px;
            border-radius: 6px;
            font-size: 11.5px;
            font-weight: 700;
        }

        .badge-win {
            background: rgba(16, 185, 129, 0.15);
            color: #34d399;
            border: 1px solid rgba(16, 185, 129, 0.2);
        }

        .badge-loss {
            background: rgba(239, 68, 68, 0.15);
            color: #f87171;
            border: 1px solid rgba(239, 68, 68, 0.2);
        }

        .badge-abandoned {
            background: rgba(148, 163, 184, 0.15);
            color: #cbd5e1;
            border: 1px solid rgba(148, 163, 184, 0.2);
        }

        .version-badge {
            display: inline-block;
            padding: 2px 6px;
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.08);
            border-radius: 4px;
            font-size: 11px;
            font-family: monospace;
            color: var(--text-muted);
        }

        .detail-tab-btn {
            background: none;
            border: none;
            color: var(--text-muted);
            font-family: inherit;
            font-size: 12.5px;
            font-weight: 500;
            padding: 6px 12px;
            cursor: pointer;
            border-radius: 6px;
            transition: all 0.2s;
        }

        .detail-tab-btn:hover {
            color: var(--text-main);
            background: rgba(255, 255, 255, 0.04);
        }

        .detail-tab-btn.active {
            color: #a78bfa;
            background: rgba(139, 92, 246, 0.15);
            font-weight: 600;
        }

        #detail-tab-map::-webkit-scrollbar {
            width: 4px;
        }
        #detail-tab-map::-webkit-scrollbar-track {
            background: rgba(255, 255, 255, 0.01);
        }
        #detail-tab-map::-webkit-scrollbar-thumb {
            background: rgba(255, 255, 255, 0.08);
            border-radius: 2px;
        }
        #detail-tab-map::-webkit-scrollbar-thumb:hover {
            background: rgba(255, 255, 255, 0.15);
        }

        .char-indicator {
            display: inline-block;
            width: 8px;
            height: 8px;
            border-radius: 50%;
            margin-right: 6px;
        }

        .char-cell {
            display: flex;
            align-items: center;
            font-weight: 600;
        }

        /* Right Sidebar Panel */
        .sidebar-container {
            display: flex;
            flex-direction: column;
            gap: 20px;
        }

        /* Run Details Card */
        .details-card {
            background: linear-gradient(135deg, rgba(20, 26, 46, 0.7), rgba(15, 23, 42, 0.55));
            border-color: rgba(139, 92, 246, 0.15);
        }

        .details-header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 18px;
            padding-bottom: 12px;
            border-bottom: 1px solid rgba(255, 255, 255, 0.05);
        }

        .details-title-area h3 {
            font-family: 'Outfit', sans-serif;
            font-size: 20px;
            font-weight: 700;
        }

        .details-title-area p {
            font-size: 12px;
            color: var(--text-muted);
            margin-top: 4px;
        }

        .run-meta-row {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 12px;
            margin-bottom: 18px;
            background: rgba(0, 0, 0, 0.2);
            padding: 12px;
            border-radius: 10px;
            border: 1px solid rgba(255, 255, 255, 0.02);
        }

        .run-meta-item {
            text-align: center;
        }

        .run-meta-label {
            font-size: 11px;
            color: var(--text-muted);
            text-transform: uppercase;
            margin-bottom: 4px;
            font-weight: 600;
        }

        .run-meta-value {
            font-size: 14px;
            font-weight: 700;
        }

        .section-title {
            font-size: 13px;
            font-weight: 700;
            color: var(--text-muted);
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 10px;
            display: flex;
            align-items: center;
            gap: 6px;
        }

        .badge-list {
            display: flex;
            flex-wrap: wrap;
            gap: 6px;
            margin-bottom: 18px;
            max-height: 140px;
            overflow-y: auto;
            padding-right: 4px;
        }

        .detail-badge {
            background: rgba(255, 255, 255, 0.04);
            border: 1px solid rgba(255, 255, 255, 0.06);
            border-radius: 6px;
            padding: 4px 8px;
            font-size: 12px;
            display: inline-flex;
            align-items: center;
            cursor: help;
            transition: all 0.2s;
        }

        .detail-badge:hover {
            background: rgba(255, 255, 255, 0.08);
            border-color: rgba(255, 255, 255, 0.15);
        }

        .detail-badge.relic-badge {
            background: rgba(139, 92, 246, 0.06);
            border-color: rgba(139, 92, 246, 0.15);
            color: #d8b4fe;
        }

        .detail-badge.relic-badge:hover {
            background: rgba(139, 92, 246, 0.12);
            border-color: rgba(139, 92, 246, 0.3);
        }

        .card-count-badge {
            background: rgba(255, 255, 255, 0.1);
            border-radius: 4px;
            padding: 1px 4px;
            font-weight: 700;
            margin-right: 5px;
            font-size: 10px;
        }

        /* Death list */
        .death-list {
            display: flex;
            flex-direction: column;
            gap: 10px;
        }

        .death-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            font-size: 13px;
        }

        .death-name {
            font-weight: 500;
            flex-grow: 1;
        }

        .death-bar-container {
            width: 120px;
            height: 6px;
            background: rgba(255, 255, 255, 0.05);
            border-radius: 3px;
            margin: 0 12px;
            overflow: hidden;
        }

        .death-bar {
            height: 100%;
            background: linear-gradient(to right, #ef4444, #f87171);
            border-radius: 3px;
        }

        .death-count {
            font-weight: 700;
            width: 20px;
            text-align: right;
            color: var(--text-muted);
        }

        /* Utility classes */
        .text-win { color: var(--accent-success); }
        .text-loss { color: var(--accent-danger); }
        .text-abandoned { color: var(--text-muted); }

        .seed-box {
            display: flex;
            align-items: center;
            gap: 8px;
            cursor: pointer;
            padding: 4px 8px;
            background: rgba(0, 0, 0, 0.2);
            border-radius: 6px;
            font-family: monospace;
            font-size: 12px;
            border: 1px solid rgba(255, 255, 255, 0.05);
            transition: all 0.2s;
        }

        .seed-box:hover {
            border-color: rgba(255, 255, 255, 0.2);
            background: rgba(255, 255, 255, 0.05);
        }

        .no-data {
            text-align: center;
            padding: 40px;
            color: var(--text-muted);
            font-size: 15px;
        }

        /* Tooltip styling */
        .db-tooltip {
            position: absolute;
            z-index: 9999;
            background: rgba(10, 15, 30, 0.95);
            border: 1px solid rgba(139, 92, 246, 0.45);
            box-shadow: 0 10px 30px rgba(0,0,0,0.8), 0 0 20px rgba(139, 92, 246, 0.25);
            border-radius: 12px;
            max-width: 320px;
            padding: 16px;
            pointer-events: none;
            backdrop-filter: blur(8px);
            -webkit-backdrop-filter: blur(8px);
            transition: opacity 0.1s ease;
        }

        .card-tooltip-wrapper {
            display: flex;
            justify-content: center;
            align-items: center;
        }

        .tooltip-card-img {
            max-width: 260px;
            height: auto;
            border-radius: 10px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.6);
        }

        .tooltip-fallback {
            width: 100%;
        }

        .tooltip-content-text {
            display: flex;
            flex-direction: column;
            gap: 8px;
        }

        .tooltip-header-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .tooltip-title {
            font-family: 'Outfit', sans-serif;
            font-size: 18px;
            font-weight: 800;
            color: #f8fafc;
        }

        .tooltip-cost {
            font-size: 12px;
            font-weight: 700;
            background: rgba(59, 130, 246, 0.2);
            color: #60a5fa;
            padding: 2px 8px;
            border-radius: 4px;
        }

        .tooltip-sub-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            color: var(--text-muted);
            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
            padding-bottom: 6px;
            margin-bottom: 4px;
        }

        .tooltip-type {
            font-weight: 600;
        }

        .tooltip-rarity {
            font-weight: 700;
        }

        .rarity-common { color: #e2e8f0; }
        .rarity-uncommon { color: #60a5fa; }
        .rarity-rare { color: #fbbf24; }
        .rarity-starter { color: #34d399; }
        .rarity-special { color: #c084fc; }
        .rarity-boss { color: #a855f7; }
        .rarity-shop { color: #14b8a6; }

        .tooltip-desc {
            font-size: 13px;
            color: #cbd5e1;
            line-height: 1.5;
            margin-top: 4px;
        }

        /* Relic Tooltip specific */
        .relic-tooltip-content {
            display: flex;
            flex-direction: column;
            gap: 10px;
        }

        .relic-tooltip-header {
            display: flex;
            align-items: center;
            gap: 12px;
            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
            padding-bottom: 8px;
        }

        .tooltip-relic-img {
            width: 44px;
            height: 44px;
            object-fit: contain;
        }

        .relic-tooltip-title-area {
            display: flex;
            flex-direction: column;
            gap: 2px;
        }

        /* BBCode styles */
        .text-gold { color: #fbbf24; font-weight: 600; }
        .text-blue { color: #3b82f6; font-weight: 600; }
        .text-purple { color: #c084fc; font-weight: 600; }
        .text-green { color: #34d399; font-weight: 600; }
        .text-red { color: #f87171; font-weight: 600; }
        
        .energy-icon {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 16px;
            height: 16px;
            background: #ef4444;
            color: #fff;
            border-radius: 50%;
            font-size: 10px;
            font-weight: 800;
            margin: 0 2px;
            vertical-align: middle;
            border: 1px solid rgba(255, 255, 255, 0.3);
        }
        .star-icon {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            background: #eab308;
            color: #000;
            border-radius: 4px;
            padding: 0 4px;
            font-size: 10px;
            font-weight: 700;
            margin: 0 2px;
            vertical-align: middle;
        }

        /* Compendium Tab styling */
        .compendium-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 16px;
            max-height: calc(100vh - 220px);
            overflow-y: auto;
            padding-right: 4px;
        }

        .compendium-card {
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 14px;
            padding: 18px;
            display: flex;
            flex-direction: column;
            gap: 10px;
            cursor: pointer;
            transition: all 0.25s ease;
            position: relative;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.15);
        }

        .compendium-card:hover {
            transform: translateY(-3px);
            box-shadow: 0 8px 25px rgba(0, 0, 0, 0.3);
            background: rgba(20, 30, 55, 0.75);
        }

        /* Card Rarity Colors */
        .compendium-card.rarity-basic {
            border-color: rgba(100, 116, 139, 0.3);
            border-top: 2px solid rgba(100, 116, 139, 0.5);
        }
        .compendium-card.rarity-basic:hover {
            border-color: rgba(100, 116, 139, 0.5);
            box-shadow: 0 8px 25px rgba(100, 116, 139, 0.1);
        }

        .compendium-card.rarity-common {
            border-color: rgba(148, 163, 184, 0.25);
            border-top: 2px solid rgba(148, 163, 184, 0.45);
        }
        .compendium-card.rarity-common:hover {
            border-color: rgba(148, 163, 184, 0.45);
            box-shadow: 0 8px 25px rgba(148, 163, 184, 0.1);
        }

        .compendium-card.rarity-uncommon {
            border-color: rgba(34, 211, 238, 0.2);
            border-top: 2px solid rgba(34, 211, 238, 0.5);
        }
        .compendium-card.rarity-uncommon:hover {
            border-color: rgba(34, 211, 238, 0.4);
            box-shadow: 0 8px 25px rgba(34, 211, 238, 0.12);
        }
        .compendium-card.rarity-uncommon .comp-card-name {
            color: #67e8f9;
        }

        .compendium-card.rarity-rare {
            border-color: rgba(251, 191, 36, 0.25);
            border-top: 2px solid rgba(251, 191, 36, 0.6);
            background: linear-gradient(165deg, rgba(251, 191, 36, 0.04) 0%, var(--card-bg) 40%);
        }
        .compendium-card.rarity-rare:hover {
            border-color: rgba(251, 191, 36, 0.45);
            box-shadow: 0 8px 30px rgba(251, 191, 36, 0.12);
        }
        .compendium-card.rarity-rare .comp-card-name {
            color: #fbbf24;
        }

        /* Relic Rarity Colors */
        .compendium-card.rarity-starter {
            border-color: rgba(100, 116, 139, 0.3);
            border-top: 2px solid rgba(100, 116, 139, 0.5);
        }
        .compendium-card.rarity-starter:hover {
            border-color: rgba(100, 116, 139, 0.5);
            box-shadow: 0 8px 25px rgba(100, 116, 139, 0.1);
        }

        .compendium-card.rarity-boss {
            border-color: rgba(244, 63, 94, 0.25);
            border-top: 2px solid rgba(244, 63, 94, 0.55);
            background: linear-gradient(165deg, rgba(244, 63, 94, 0.04) 0%, var(--card-bg) 40%);
        }
        .compendium-card.rarity-boss:hover {
            border-color: rgba(244, 63, 94, 0.45);
            box-shadow: 0 8px 30px rgba(244, 63, 94, 0.12);
        }
        .compendium-card.rarity-boss .comp-card-name {
            color: #fb7185;
        }

        .compendium-card.rarity-shop {
            border-color: rgba(74, 222, 128, 0.2);
            border-top: 2px solid rgba(74, 222, 128, 0.5);
        }
        .compendium-card.rarity-shop:hover {
            border-color: rgba(74, 222, 128, 0.4);
            box-shadow: 0 8px 25px rgba(74, 222, 128, 0.1);
        }
        .compendium-card.rarity-shop .comp-card-name {
            color: #4ade80;
        }

        .compendium-card.rarity-ancient,
        .compendium-card.rarity-special {
            border-color: rgba(168, 85, 247, 0.25);
            border-top: 2px solid rgba(168, 85, 247, 0.55);
            background: linear-gradient(165deg, rgba(168, 85, 247, 0.04) 0%, var(--card-bg) 40%);
        }
        .compendium-card.rarity-ancient:hover,
        .compendium-card.rarity-special:hover {
            border-color: rgba(168, 85, 247, 0.45);
            box-shadow: 0 8px 30px rgba(168, 85, 247, 0.12);
        }
        .compendium-card.rarity-ancient .comp-card-name,
        .compendium-card.rarity-special .comp-card-name {
            color: #c084fc;
        }

        /* Monster Type Colors */
        .compendium-card.monster-normal {
            border-color: rgba(148, 163, 184, 0.25);
            border-top: 2px solid rgba(148, 163, 184, 0.45);
        }
        .compendium-card.monster-normal:hover {
            border-color: rgba(148, 163, 184, 0.45);
            box-shadow: 0 8px 25px rgba(148, 163, 184, 0.1);
        }

        .compendium-card.monster-elite {
            border-color: rgba(251, 191, 36, 0.25);
            border-top: 2px solid rgba(251, 191, 36, 0.55);
            background: linear-gradient(165deg, rgba(251, 191, 36, 0.03) 0%, var(--card-bg) 40%);
        }
        .compendium-card.monster-elite:hover {
            border-color: rgba(251, 191, 36, 0.45);
            box-shadow: 0 8px 30px rgba(251, 191, 36, 0.1);
        }
        .compendium-card.monster-elite .comp-card-name {
            color: #fbbf24;
        }

        .compendium-card.monster-boss {
            border-color: rgba(244, 63, 94, 0.25);
            border-top: 2px solid rgba(244, 63, 94, 0.55);
            background: linear-gradient(165deg, rgba(244, 63, 94, 0.04) 0%, var(--card-bg) 40%);
        }
        .compendium-card.monster-boss:hover {
            border-color: rgba(244, 63, 94, 0.45);
            box-shadow: 0 8px 30px rgba(244, 63, 94, 0.12);
        }
        .compendium-card.monster-boss .comp-card-name {
            color: #fb7185;
        }

        /* Compendium Monster Table & Intent Styles */
        .comp-monster-row {
            transition: background 0.15s ease;
        }
        .comp-monster-row:hover {
            background: rgba(255, 255, 255, 0.02) !important;
        }
        .comp-act-badge {
            display: inline-block;
            background: rgba(99, 102, 241, 0.1);
            color: #818cf8;
            border: 1px solid rgba(99, 102, 241, 0.2);
            padding: 2px 6px;
            font-size: 11px;
            border-radius: 4px;
            font-weight: 500;
            margin: 2px;
        }
        .comp-moves-container {
            display: flex;
            flex-direction: column;
            gap: 6px;
        }
        .comp-move-item {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 12px;
            background: rgba(255, 255, 255, 0.015);
            border: 1px solid rgba(255, 255, 255, 0.03);
            border-radius: 6px;
            padding: 4px 8px;
        }
        .comp-intent-badge {
            display: inline-flex;
            align-items: center;
            gap: 4px;
            padding: 1px 6px;
            font-size: 9.5px;
            font-weight: 700;
            text-transform: uppercase;
            border-radius: 4px;
            min-width: 75px;
            justify-content: center;
        }
        .comp-intent-attack {
            background: rgba(239, 68, 68, 0.12);
            color: #f87171;
            border: 1px solid rgba(239, 68, 68, 0.2);
        }
        .comp-intent-defend {
            background: rgba(59, 130, 246, 0.12);
            color: #60a5fa;
            border: 1px solid rgba(59, 130, 246, 0.2);
        }
        .comp-intent-buff {
            background: rgba(16, 185, 129, 0.12);
            color: #34d399;
            border: 1px solid rgba(16, 185, 129, 0.2);
        }
        .comp-intent-debuff {
            background: rgba(245, 158, 11, 0.12);
            color: #fbbf24;
            border: 1px solid rgba(245, 158, 11, 0.2);
        }
        .comp-intent-unknown {
            background: rgba(148, 163, 184, 0.12);
            color: #94a3b8;
            border: 1px solid rgba(148, 163, 184, 0.2);
        }
        .comp-move-name {
            font-weight: 600;
            color: #e2e8f0;
            min-width: 100px;
        }
        .comp-move-details {
            color: var(--text-muted);
            font-size: 11.5px;
        }

        /* Compendium Sub-Tabs Styles */
        .sub-tab-btn {
            background: rgba(255, 255, 255, 0.03);
            border: 1px solid rgba(255, 255, 255, 0.05);
            color: var(--text-muted);
            font-size: 13.5px;
            font-weight: 600;
            padding: 6px 16px;
            cursor: pointer;
            border-radius: 6px;
            transition: all 0.2s ease;
            font-family: 'Outfit', sans-serif;
        }
        .sub-tab-btn:hover {
            color: var(--text-main);
            background: rgba(255, 255, 255, 0.08);
            border-color: rgba(255, 255, 255, 0.1);
        }
        .sub-tab-btn.active {
            color: var(--accent-gold);
            background: rgba(250, 204, 21, 0.12);
            border-color: rgba(250, 204, 21, 0.3);
        }
        .comp-sub-view {
            transition: opacity 0.15s ease-in-out;
        }

        /* Events Tab Styles */
        .events-grid-layout {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(400px, 1fr));
            gap: 20px;
            margin-top: 12px;
        }
        .event-card {
            background: rgba(30, 41, 59, 0.25);
            border: 1px solid var(--card-border);
            border-radius: 12px;
            padding: 16px;
            display: flex;
            flex-direction: column;
            gap: 12px;
            transition: transform 0.2s ease, border-color 0.2s ease, box-shadow 0.2s ease;
        }
        .event-card:hover {
            transform: translateY(-2px);
            border-color: rgba(99, 102, 241, 0.35);
            box-shadow: 0 8px 30px rgba(99, 102, 241, 0.08);
        }
        .event-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid rgba(255, 255, 255, 0.05);
            padding-bottom: 8px;
        }
        .event-name {
            font-family: 'Outfit', sans-serif;
            font-size: 16px;
            font-weight: 700;
            color: var(--text-main);
        }
        .event-desc {
            font-size: 12.5px;
            color: #94a3b8;
            line-height: 1.5;
            white-space: pre-line;
            max-height: 120px;
            overflow-y: auto;
            padding-right: 4px;
        }
        .event-options-title {
            font-size: 10px;
            font-weight: 800;
            text-transform: uppercase;
            color: var(--text-muted);
            letter-spacing: 0.05em;
            margin-top: 4px;
        }
        .event-options-list {
            display: flex;
            flex-direction: column;
            gap: 6px;
        }
        .event-option-row {
            display: flex;
            flex-direction: column;
            gap: 3px;
            background: rgba(255, 255, 255, 0.02);
            border: 1px solid rgba(255, 255, 255, 0.04);
            padding: 8px 10px;
            border-radius: 6px;
        }
        .event-option-header {
            display: flex;
            align-items: center;
            gap: 6px;
        }
        .event-option-pill {
            background: rgba(99, 102, 241, 0.15);
            color: #a5b4fc;
            border: 1px solid rgba(99, 102, 241, 0.25);
            padding: 1px 6px;
            font-size: 10px;
            border-radius: 4px;
            font-weight: 700;
            text-transform: uppercase;
        }
        .event-option-text {
            font-size: 12.5px;
            font-weight: 600;
            color: #e2e8f0;
        }
        .event-option-outcome {
            font-size: 11.5px;
            color: #94a3b8;
            line-height: 1.35;
        }

        .comp-card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .comp-card-name {
            font-family: 'Outfit', sans-serif;
            font-size: 16px;
            font-weight: 700;
            color: #fff;
        }

        .comp-card-cost {
            font-size: 11px;
            background: rgba(139, 92, 246, 0.15);
            color: #c084fc;
            padding: 2px 8px;
            border-radius: 4px;
            font-weight: 700;
        }

        .comp-card-meta {
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 10.5px;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            color: var(--text-muted);
            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
            padding-bottom: 6px;
            margin-bottom: 2px;
        }

        .comp-card-desc {
            font-size: 12.5px;
            color: #cbd5e1;
            line-height: 1.45;
        }

        .comp-relic-img-preview {
            width: 28px;
            height: 28px;
            object-fit: contain;
            margin-right: 8px;
            vertical-align: middle;
        }
        
        .comp-relic-title-row {
            display: flex;
            align-items: center;
        }
        
        /* Monster Tooltip Styles */
        .monster-tooltip-content {
            min-width: 280px;
            max-width: 340px;
            display: flex;
            flex-direction: column;
            gap: 10px;
        }

        .monster-tooltip-header {
            display: flex;
            gap: 12px;
            align-items: center;
            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
            padding-bottom: 8px;
        }

        .tooltip-monster-img {
            width: 48px;
            height: 48px;
            object-fit: cover;
            border-radius: 6px;
            border: 1px solid rgba(255, 255, 255, 0.1);
            background: rgba(0, 0, 0, 0.2);
        }

        .monster-title-area {
            flex-grow: 1;
        }

        .monster-type-badge {
            display: inline-block;
            padding: 2px 6px;
            border-radius: 4px;
            font-size: 10px;
            font-weight: 800;
            text-transform: uppercase;
            margin-top: 2px;
            letter-spacing: 0.03em;
        }

        .type-normal {
            background: rgba(148, 163, 184, 0.15);
            color: #cbd5e1;
            border: 1px solid rgba(148, 163, 184, 0.2);
        }

        .type-elite {
            background: rgba(245, 158, 11, 0.15);
            color: #fbbf24;
            border: 1px solid rgba(245, 158, 11, 0.2);
        }

        .type-boss {
            background: rgba(168, 85, 247, 0.15);
            color: #e9d5ff;
            border: 1px solid rgba(168, 85, 247, 0.2);
        }

        .monster-hp {
            font-size: 11.5px;
            color: var(--text-muted);
            margin-top: 2px;
            font-weight: 600;
        }

        .monster-pattern {
            font-size: 11.5px;
            background: rgba(255, 255, 255, 0.02);
            border: 1px solid rgba(255, 255, 255, 0.04);
            padding: 6px 8px;
            border-radius: 6px;
            color: #cbd5e1;
            line-height: 1.35;
        }

        .monster-pattern-title {
            font-size: 9px;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            color: var(--text-muted);
            font-weight: 700;
            margin-bottom: 2px;
        }

        .monster-moves-title {
            font-size: 9.5px;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            color: var(--text-muted);
            font-weight: 700;
            margin-bottom: 4px;
        }

        .monster-moves-list {
            display: flex;
            flex-direction: column;
            gap: 6px;
            max-height: 200px;
            overflow-y: auto;
            padding-right: 4px;
        }

        .monster-move-row {
            background: rgba(0, 0, 0, 0.15);
            border: 1px solid rgba(255, 255, 255, 0.03);
            border-radius: 6px;
            padding: 6px 8px;
            display: flex;
            flex-direction: column;
            gap: 3px;
        }

        .monster-move-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 6px;
        }

        .monster-move-name {
            font-size: 12px;
            font-weight: 700;
            color: #f1f5f9;
        }

        .monster-move-intent {
            font-size: 9px;
            font-weight: 700;
            padding: 1px 4px;
            border-radius: 3px;
            text-transform: uppercase;
        }

        .intent-attack { background: rgba(239, 68, 68, 0.12); color: #f87171; border: 1px solid rgba(239, 68, 68, 0.18); }
        .intent-defend { background: rgba(16, 185, 129, 0.12); color: #34d399; border: 1px solid rgba(16, 185, 129, 0.18); }
        .intent-buff { background: rgba(59, 130, 246, 0.12); color: #60a5fa; border: 1px solid rgba(59, 130, 246, 0.18); }
        .intent-debuff { background: rgba(245, 158, 11, 0.12); color: #fbbf24; border: 1px solid rgba(245, 158, 11, 0.18); }
        .intent-status { background: rgba(148, 163, 184, 0.12); color: #cbd5e1; border: 1px solid rgba(148, 163, 184, 0.18); }
        .intent-unknown { background: rgba(100, 116, 139, 0.12); color: #94a3b8; border: 1px solid rgba(100, 116, 139, 0.18); }

        .monster-move-dmg {
            font-size: 11px;
            font-weight: 700;
            color: #ef4444;
        }

        .monster-move-desc {
            font-size: 10.5px;
            color: var(--text-muted);
            line-height: 1.3;
        }

        /* Card Statistics Styles */
        .card-stats-row {
            transition: background 0.15s ease;
        }
        .card-stats-row:hover {
            background: rgba(255, 255, 255, 0.02) !important;
        }
        
        /* Relic Statistics Styles */
        .relic-stats-row {
            transition: background 0.15s ease;
        }
        .relic-stats-row:hover {
            background: rgba(255, 255, 255, 0.02) !important;
        }
        
        /* Player Selector Tabs for Co-op details */
        .player-selector-container {
            display: flex;
            gap: 8px;
            margin-bottom: 16px;
            background: rgba(0, 0, 0, 0.25);
            padding: 4px;
            border-radius: 8px;
            border: 1px solid rgba(255, 255, 255, 0.04);
        }
        .player-selector-btn {
            flex: 1;
            background: transparent;
            border: none;
            color: var(--text-muted);
            padding: 8px 12px;
            font-size: 11.5px;
            font-weight: 700;
            cursor: pointer;
            border-radius: 6px;
            transition: all 0.2s ease;
            text-align: center;
            outline: none;
            font-family: inherit;
        }
        .player-selector-btn:hover {
            color: var(--text-main);
            background: rgba(255, 255, 255, 0.03);
        }
        .player-selector-btn.active {
            background: rgba(255, 255, 255, 0.08);
            color: var(--text-main);
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
        }
        
        /* Multiple player indicator circles */
        .player-indicators {
            display: inline-flex;
            align-items: center;
            gap: 4px;
            margin-right: 6px;
        }
    </style>
</head>
<body>
    <!-- Global Error Overlay for Debugging -->
    <div id="error-overlay" style="display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(8, 12, 20, 0.95); color: #ef4444; z-index: 99999; padding: 40px; font-family: monospace; overflow: auto; box-sizing: border-box; border: 4px solid #ef4444;">
        <h2 style="margin-bottom: 20px; font-size: 24px; text-transform: uppercase; letter-spacing: 2px;">⚠️ Critical Runtime JavaScript Error Detected</h2>
        <p style="color: #94a3b8; margin-bottom: 20px; font-size: 16px;">The dashboard failed to load or run. Please copy the error message below to help debug the issue:</p>
        <pre id="error-msg" style="background: rgba(0,0,0,0.5); padding: 20px; border-radius: 8px; border: 1px solid rgba(239, 68, 68, 0.3); font-size: 14px; line-height: 1.6; white-space: pre-wrap; word-break: break-all; color: #f8fafc;"></pre>
    </div>
    <script>
        window.addEventListener('error', function(e) {
            const overlay = document.getElementById('error-overlay');
            const msg = document.getElementById('error-msg');
            if (overlay && msg) {
                overlay.style.display = 'block';
                msg.textContent = e.message + '\n\nStack Trace:\n' + (e.error ? e.error.stack : 'No stack trace available.');
            }
        });
    </script>

    <header>
        <div class="logo-area">
            <div class="logo-icon">S2</div>
            <div>
                <h1>Slay the Spire 2</h1>
                <div class="sub-heading">Run History & Interactive Analytics Dashboard</div>
            </div>
        </div>
        
        <div class="tab-container">
            <button class="tab-btn active" id="tab-runs" onclick="switchTab('runs')">Run History</button>
            <button class="tab-btn" id="tab-multiplayer" onclick="switchTab('multiplayer')">Co-op History</button>
            <button class="tab-btn" id="tab-compendium" onclick="switchTab('compendium')">Compendium</button>
            <button class="tab-btn" id="tab-card-stats" onclick="switchTab('card-stats')">Card Analytics</button>
            <button class="tab-btn" id="tab-relic-stats" onclick="switchTab('relic-stats')">Relic Analytics</button>
        </div>
        
        <div class="header-actions">
            <div class="btn-group">
                <button class="reset-btn" id="reset-btn" style="display: none;">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="margin-right: 6px;"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.57-8.38l5.67-5.67"/></svg>
                    Reset to Default
                </button>
                <label class="import-btn" style="background: linear-gradient(135deg, #0ea5e9, #0284c7);box-shadow: 0 4px 12px rgba(14,165,233,0.25);">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="margin-right: 6px;"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="12" y1="18" x2="12" y2="12"/><line x1="9" y1="15" x2="15" y2="15"/></svg>
                    Add Runs
                    <input type="file" id="run-input" accept=".run" multiple style="display: none;">
                </label>
                <label class="import-btn">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="margin-right: 6px;"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12"/></svg>
                    Import ZIP
                    <input type="file" id="zip-input" accept=".zip" style="display: none;">
                </label>
            </div>
            <div class="meta-info">
                <div id="meta-source">Source: None</div>
                <div id="meta-updated">Last Run: None</div>
            </div>
        </div>
    </header>

    <!-- MAIN DASHBOARD GRID (wraps left content and shared sidebar) -->
    <div class="dashboard-grid" id="main-grid">
        <!-- Left Content Area (holds runs and multiplayer views) -->
        <div>
            <!-- RUN HISTORY VIEW -->
            <div id="view-runs">
        <!-- Stats KPI Grid -->
        <div class="stats-grid">
            <div class="card kpi-card" id="kpi-card-runs">
                <div class="card-glow"></div>
                <div class="card-title">Total Runs</div>
                <div class="card-value" id="kpi-total-runs">0</div>
                <div class="card-subtext" id="kpi-sub-total">Wins vs Losses</div>
            </div>
            <div class="card kpi-card" id="kpi-card-winrate">
                <div class="card-glow" style="background: var(--accent-success);"></div>
                <div class="card-title">Overall Win Rate</div>
                <div class="card-value" id="kpi-win-rate">0.0%</div>
                <div class="card-subtext" id="kpi-sub-wins">0 Wins recorded</div>
            </div>
            <div class="card kpi-card" id="kpi-card-playtime">
                <div class="card-glow" style="background: var(--char-defect);"></div>
                <div class="card-title">Total Playtime</div>
                <div class="card-value" id="kpi-playtime">0h 0m</div>
                <div class="card-subtext" id="kpi-sub-avg-time">Avg: 0m per run</div>
            </div>
            <div class="card kpi-card" id="kpi-card-maxasc">
                <div class="card-glow" style="background: var(--accent-warning);"></div>
                <div class="card-title">Max Ascension</div>
                <div class="card-value" id="kpi-max-asc">A0</div>
                <div class="card-subtext" id="kpi-sub-fav-char">Preferred Character</div>
            </div>
        </div>

        <!-- Filter Control Bar -->
        <div class="filter-panel">
            <div class="char-pills">
                <div class="char-pill active" data-char="all">All Characters</div>
                <div class="char-pill" data-char="ironclad">Ironclad</div>
                <div class="char-pill" data-char="silent">Silent</div>
                <div class="char-pill" data-char="defect">Defect</div>
                <div class="char-pill" data-char="regent">Regent</div>
                <div class="char-pill" data-char="necrobinder">Necrobinder</div>
            </div>
            
            <div class="search-wrapper">
                <input type="text" class="search-input" id="search-seed" placeholder="Search by Seed or Killed By...">
            </div>

            <select class="select-filter" id="filter-result">
                <option value="all">All Results</option>
                <option value="win">Wins Only</option>
                <option value="loss">Losses Only</option>
                <option value="abandoned">Abandoned Only</option>
            </select>

            <select class="select-filter" id="filter-asc">
                <option value="all">All Ascensions</option>
                <!-- Generated dynamically -->
            </select>
        </div>

        <!-- Main Dashboard Grid content container -->
        <div>
            <!-- Left Side: Charts & Table -->
            <div>
                <!-- Charts Row -->
                <div class="charts-container">
                    <div class="card chart-box">
                        <h3>Win Rate & Runs by Character</h3>
                        <div class="chart-wrapper">
                            <canvas id="chart-character"></canvas>
                        </div>
                    </div>
                    <div class="card chart-box">
                        <h3>Run distribution</h3>
                        <div class="chart-wrapper">
                            <canvas id="chart-share"></canvas>
                        </div>
                    </div>
                </div>

                <!-- Playstyle & Survival Analytics Row -->
                <div style="display: grid; grid-template-columns: 1.2fr 0.8fr; gap: 16px; margin-bottom: 24px;">
                    <!-- Playstyle Card -->
                    <div class="card" style="padding: 20px; display: flex; flex-direction: column;">
                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); padding-bottom: 8px;">
                            <div>
                                <h3 style="font-size: 14px; font-weight: 600; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.05em;">Playstyle Traits</h3>
                                <p id="playstyle-subtitle" style="font-size: 11px; color: var(--text-muted); margin-top: 2px;"></p>
                            </div>
                            <div style="display: flex; gap: 6px;">
                                <span id="playstyle-badge-runs" class="runs-count-badge" style="font-size: 11px; padding: 2px 8px;">0 Runs</span>
                                <span id="playstyle-badge-wr" class="runs-count-badge" style="font-size: 11px; padding: 2px 8px; background: rgba(16, 185, 129, 0.15); color: #34d399;">0% WR</span>
                            </div>
                        </div>
                        
                        <div style="display: grid; grid-template-columns: 1fr 1.1fr; gap: 16px; flex-grow: 1; align-items: center;">
                            <!-- Radar Chart -->
                            <div style="height: 250px; position: relative;">
                                <canvas id="chart-playstyle"></canvas>
                            </div>
                            <!-- Trait Breakdown -->
                            <div style="display: flex; flex-direction: column; gap: 8px; justify-content: center; font-size: 12px;">
                                <!-- Route Discipline -->
                                <div style="display: flex; justify-content: space-between; align-items: center; padding-bottom: 6px; border-bottom: 1px solid rgba(255, 255, 255, 0.03);">
                                    <div style="display: flex; flex-direction: column; gap: 2px;">
                                        <span style="font-weight: 600; color: #ef4444;">Route Discipline</span>
                                        <span id="trait-desc-route" style="font-size: 10px; color: var(--text-muted);">Avg floors reached</span>
                                    </div>
                                    <span id="trait-val-route" style="font-size: 16px; font-weight: 800; color: #ef4444; font-family: monospace;">0</span>
                                </div>
                                <!-- Deck Cohesion -->
                                <div style="display: flex; justify-content: space-between; align-items: center; padding-bottom: 6px; border-bottom: 1px solid rgba(255, 255, 255, 0.03);">
                                    <div style="display: flex; flex-direction: column; gap: 2px;">
                                        <span style="font-weight: 600; color: #3b82f6;">Deck Cohesion</span>
                                        <span id="trait-desc-cohesion" style="font-size: 10px; color: var(--text-muted);">Pick selectivity</span>
                                    </div>
                                    <span id="trait-val-cohesion" style="font-size: 16px; font-weight: 800; color: #3b82f6; font-family: monospace;">0</span>
                                </div>
                                <!-- Boss Conversion -->
                                <div style="display: flex; justify-content: space-between; align-items: center; padding-bottom: 6px; border-bottom: 1px solid rgba(255, 255, 255, 0.03);">
                                    <div style="display: flex; flex-direction: column; gap: 2px;">
                                        <span style="font-weight: 600; color: #10b981;">Boss Conversion</span>
                                        <span id="trait-desc-conversion" style="font-size: 10px; color: var(--text-muted);">Overall win rate</span>
                                    </div>
                                    <span id="trait-val-conversion" style="font-size: 16px; font-weight: 800; color: #10b981; font-family: monospace;">0</span>
                                </div>
                                <!-- Clutch Survival -->
                                <div style="display: flex; justify-content: space-between; align-items: center; padding-bottom: 6px; border-bottom: 1px solid rgba(255, 255, 255, 0.03);">
                                    <div style="display: flex; flex-direction: column; gap: 2px;">
                                        <span style="font-weight: 600; color: #fbbf24;">Clutch Survival</span>
                                        <span id="trait-desc-survival" style="font-size: 10px; color: var(--text-muted);">Final HP on victories</span>
                                    </div>
                                    <span id="trait-val-survival" style="font-size: 16px; font-weight: 800; color: #fbbf24; font-family: monospace;">0</span>
                                </div>
                                <!-- Elite Tempo -->
                                <div style="display: flex; justify-content: space-between; align-items: center; padding-bottom: 6px; border-bottom: 1px solid rgba(255, 255, 255, 0.03);">
                                    <div style="display: flex; flex-direction: column; gap: 2px;">
                                        <span style="font-weight: 600; color: #a855f7;">Elite Tempo</span>
                                        <span id="trait-desc-tempo" style="font-size: 10px; color: var(--text-muted);">Attack card ratio</span>
                                    </div>
                                    <span id="trait-val-tempo" style="font-size: 16px; font-weight: 800; color: #a855f7; font-family: monospace;">0</span>
                                </div>
                                <!-- Resource Efficiency -->
                                <div style="display: flex; justify-content: space-between; align-items: center;">
                                    <div style="display: flex; flex-direction: column; gap: 2px;">
                                        <span style="font-weight: 600; color: #14b8a6;">Resource Efficiency</span>
                                        <span id="trait-desc-resource" style="font-size: 10px; color: var(--text-muted);">Gold spent vs earned</span>
                                    </div>
                                    <span id="trait-val-resource" style="font-size: 16px; font-weight: 800; color: #14b8a6; font-family: monospace;">0</span>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- Survival Card -->
                    <div class="card" style="padding: 20px; display: flex; flex-direction: column;">
                        <h3 style="font-size: 14px; font-weight: 600; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 16px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); padding-bottom: 8px;">Survival By Floor</h3>
                        <div style="height: 250px; position: relative; flex-grow: 1; width: 100%;">
                            <canvas id="chart-survival"></canvas>
                        </div>
                    </div>
                </div>

                <!-- Run History Table -->
                <div class="card runs-container">
                    <div class="runs-header-row">
                        <h3>Run History</h3>
                        <span class="runs-count-badge" id="runs-filtered-count">Showing 0 of 0 runs</span>
                    </div>
                    <div class="table-wrapper">
                        <table>
                            <thead>
                                <tr id="runs-header-row-tr">
                                    <th data-sort="date" onclick="sortRuns('date')">Date / Time</th>
                                    <th data-sort="version" onclick="sortRuns('version')">Version</th>
                                    <th data-sort="character" onclick="sortRuns('character')">Character</th>
                                    <th data-sort="ascension" onclick="sortRuns('ascension')">Asc.</th>
                                    <th data-sort="result" onclick="sortRuns('result')">Result</th>
                                    <th data-sort="floors" onclick="sortRuns('floors')">Floor</th>
                                    <th data-sort="runTime" onclick="sortRuns('runTime')">Duration</th>
                                    <th data-sort="killedBy" onclick="sortRuns('killedBy')">Killed By</th>
                                </tr>
                            </thead>
                            <tbody id="runs-table-body">
                                <!-- Populated dynamically -->
                            </tbody>
                        </table>
                    </div>
                </div>
            </div> <!-- End of runs left-side content -->
        </div> <!-- End of Main Dashboard Grid content container -->
    </div> <!-- End of view-runs -->
            
            <!-- MULTIPLAYER HISTORY VIEW -->
            <div id="view-multiplayer" style="display: none;">
                <!-- Filter Control Bar -->
                <div class="filter-panel">
                    <div class="search-wrapper">
                        <input type="text" class="search-input" id="multi-search" placeholder="Search by Seed, Player or Killed By...">
                    </div>
                    
                    <select class="select-filter" id="multi-filter-result">
                        <option value="all">All Results</option>
                        <option value="win">Wins Only</option>
                        <option value="loss">Losses Only</option>
                        <option value="abandoned">Abandoned Only</option>
                    </select>

                    <select class="select-filter" id="multi-filter-asc">
                        <option value="all">All Ascensions</option>
                        <!-- Generated dynamically -->
                    </select>
                </div>
                
                <!-- Multiplayer Runs Table Container -->
                <div class="card runs-container">
                    <div class="runs-header-row">
                        <h3>Co-op History</h3>
                        <span class="runs-count-badge" id="multi-runs-count">Showing 0 of 0 runs</span>
                    </div>
                    <div class="table-wrapper">
                        <table>
                            <thead>
                                <tr id="multi-header-row-tr">
                                    <th data-sort="date" onclick="sortMulti('date')">Date / Time</th>
                                    <th data-sort="version" onclick="sortMulti('version')">Version</th>
                                    <th data-sort="character" onclick="sortMulti('character')">Players</th>
                                    <th data-sort="ascension" onclick="sortMulti('ascension')">Asc.</th>
                                    <th data-sort="result" onclick="sortMulti('result')">Result</th>
                                    <th data-sort="floors" onclick="sortMulti('floors')">Floor</th>
                                    <th data-sort="runTime" onclick="sortMulti('runTime')">Duration</th>
                                    <th data-sort="killedBy" onclick="sortMulti('killedBy')">Killed By</th>
                                </tr>
                            </thead>
                            <tbody id="multi-runs-table-body">
                                <!-- Populated dynamically -->
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div> <!-- End of left-side co-op + single content -->
        
        <!-- Right Side: Shared Sidebar -->
        <div class="sidebar-container" id="shared-sidebar">
                <!-- Run Details Panel -->
                <div class="card details-card">
                    <div class="details-header">
                        <div class="details-title-area">
                            <h3 id="detail-char-name">No Run Selected</h3>
                            <p id="detail-date">Select a run in the table to view deck and relics</p>
                        </div>
                        <div class="seed-box" id="detail-seed-box" style="display:none;" onclick="copySeed()">
                            <span id="detail-seed">SEED</span>
                            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>
                        </div>
                    </div>

                    <div id="detail-content" style="display:none;">
                        <!-- Player Selector Tabs for Multiplayer -->
                        <div class="player-selector-container" id="detail-player-tabs" style="display: none;"></div>
                        
                        <div class="run-meta-row">
                            <div class="run-meta-item">
                                <div class="run-meta-label">Result</div>
                                <div class="run-meta-value" id="detail-result">Loss</div>
                            </div>
                            <div class="run-meta-item">
                                <div class="run-meta-label">Floors Reached</div>
                                <div class="run-meta-value" id="detail-floors">0</div>
                            </div>
                            <div class="run-meta-item">
                                <div class="run-meta-label">Time</div>
                                <div class="run-meta-value" id="detail-duration">0m</div>
                            </div>
                        </div>

                        <!-- Sub-tabs for equipment vs map -->
                        <div class="detail-tabs-nav" style="display: flex; gap: 8px; margin: 16px 0 12px 0; border-bottom: 1px solid rgba(255, 255, 255, 0.08); padding-bottom: 8px;">
                            <button class="detail-tab-btn active" id="detail-btn-equipment" onclick="switchDetailSubTab('equipment')">Equipment & Deck</button>
                            <button class="detail-tab-btn" id="detail-btn-map" onclick="switchDetailSubTab('map')">Run Map</button>
                        </div>

                        <div id="detail-tab-equipment">
                            <div class="section-title">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"></path></svg>
                                Relics (<span id="detail-relics-count">0</span>)
                            </div>
                            <div class="badge-list" id="detail-relics">
                                <!-- Relics badges -->
                            </div>

                            <div class="section-title">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect><line x1="9" y1="9" x2="15" y2="9"></line><line x1="9" y1="13" x2="15" y2="13"></line><line x1="9" y1="17" x2="15" y2="17"></line></svg>
                                Deck Cards (<span id="detail-deck-count">0</span>)
                            </div>
                            <div class="badge-list" id="detail-deck">
                                <!-- Deck badges -->
                            </div>
                        </div>

                        <div id="detail-tab-map" style="display:none; max-height: 480px; overflow-y: auto; padding-right: 4px; margin-top: 8px;">
                            <!-- Populated dynamically with map timeline -->
                        </div>
                    </div>
                </div>

                <!-- Top Death Causes Panel -->
                <div class="card">
                    <div class="section-title" style="margin-bottom: 16px; font-size:14px;">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="15" y1="9" x2="9" y2="15"></line><line x1="9" y1="9" x2="15" y2="15"></line></svg>
                        Top Death Causes
                    </div>
                    <div class="death-list" id="death-list-body">
                        <!-- Dynamic list -->
                    </div>
                </div>
            </div>
        </div>

    <!-- COMPENDIUM TAB VIEW -->
    <div id="view-compendium" style="display: none;">
        <!-- Sub-navigation tabs -->
        <div class="sub-tab-nav" style="display: flex; gap: 10px; margin-bottom: 20px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); padding-bottom: 14px; flex-wrap: wrap;">
            <button class="sub-tab-btn active" id="sub-tab-cards" onclick="switchSubTab('cards')">Cards</button>
            <button class="sub-tab-btn" id="sub-tab-relics" onclick="switchSubTab('relics')">Relics</button>
            <button class="sub-tab-btn" id="sub-tab-potions" onclick="switchSubTab('potions')">Potions</button>
            <button class="sub-tab-btn" id="sub-tab-campfire" onclick="switchSubTab('campfire')">Campfire</button>
            <button class="sub-tab-btn" id="sub-tab-mobs" onclick="switchSubTab('mobs')">Mobs</button>
            <button class="sub-tab-btn" id="sub-tab-events" onclick="switchSubTab('events')">Events</button>
            <button class="sub-tab-btn" id="sub-tab-keywords" onclick="switchSubTab('keywords')">Keywords</button>
        </div>

        <!-- Cards Sub-View -->
        <div id="sub-view-cards" class="comp-sub-view">
            <div class="filter-panel">
                <div class="search-wrapper">
                    <input type="text" id="comp-cards-search" class="search-input" placeholder="Search cards by name or description...">
                </div>
                <select id="comp-cards-sort-by" class="select-filter">
                    <option value="name">Sort by Name</option>
                    <option value="rarity">Sort by Rarity</option>
                </select>
                <div class="char-pills" id="comp-cards-char-pills">
                    <div class="char-pill active" data-char="all">All Classes</div>
                    <div class="char-pill" data-char="ironclad"><img src="https://cdn.spire-codex.com/characters/combat_ironclad.webp" class="char-icon-mini" onerror="this.style.display='none';">Ironclad</div>
                    <div class="char-pill" data-char="silent"><img src="https://cdn.spire-codex.com/characters/combat_silent.webp" class="char-icon-mini" onerror="this.style.display='none';">Silent</div>
                    <div class="char-pill" data-char="defect"><img src="https://cdn.spire-codex.com/characters/combat_defect.webp" class="char-icon-mini" onerror="this.style.display='none';">Defect</div>
                    <div class="char-pill" data-char="regent"><img src="https://cdn.spire-codex.com/characters/combat_regent.webp" class="char-icon-mini" onerror="this.style.display='none';">Regent</div>
                    <div class="char-pill" data-char="necrobinder"><img src="https://cdn.spire-codex.com/characters/combat_necrobinder.webp" class="char-icon-mini" onerror="this.style.display='none';">Necrobinder</div>
                    <div class="char-pill" data-char="shared">Neutral / Shared</div>
                </div>
            </div>
            <div class="compendium-grid" id="comp-cards-grid">
                <!-- Populated dynamically -->
            </div>
        </div>

        <!-- Relics Sub-View -->
        <div id="sub-view-relics" class="comp-sub-view" style="display: none;">
            <div class="filter-panel">
                <div class="search-wrapper">
                    <input type="text" id="comp-relics-search" class="search-input" placeholder="Search relics by name or description...">
                </div>
                <select id="comp-relics-sort-by" class="select-filter">
                    <option value="name">Sort by Name</option>
                    <option value="rarity">Sort by Rarity</option>
                </select>
                <div class="char-pills" id="comp-relics-char-pills">
                    <div class="char-pill active" data-char="all">All Relics</div>
                    <div class="char-pill" data-char="shared">Shared / Neutral</div>
                </div>
            </div>
            <div class="compendium-grid" id="comp-relics-grid">
                <!-- Populated dynamically -->
            </div>
        </div>

        <!-- Potions Sub-View -->
        <div id="sub-view-potions" class="comp-sub-view" style="display: none;">
            <div class="filter-panel">
                <div class="search-wrapper">
                    <input type="text" id="comp-potions-search" class="search-input" placeholder="Search potions by name or description...">
                </div>
                <select id="comp-potions-rarity" class="select-filter">
                    <option value="all">All Rarities</option>
                    <option value="Common">Common</option>
                    <option value="Uncommon">Uncommon</option>
                    <option value="Rare">Rare</option>
                    <option value="Token">Token</option>
                    <option value="Event">Event</option>
                </select>
                <div class="char-pills" id="comp-potions-pool-pills">
                    <div class="char-pill active" data-pool="all">All Pools</div>
                    <div class="char-pill" data-pool="ironclad"><img src="https://cdn.spire-codex.com/characters/combat_ironclad.webp" class="char-icon-mini" onerror="this.style.display='none';">Ironclad</div>
                    <div class="char-pill" data-pool="silent"><img src="https://cdn.spire-codex.com/characters/combat_silent.webp" class="char-icon-mini" onerror="this.style.display='none';">Silent</div>
                    <div class="char-pill" data-pool="defect"><img src="https://cdn.spire-codex.com/characters/combat_defect.webp" class="char-icon-mini" onerror="this.style.display='none';">Defect</div>
                    <div class="char-pill" data-pool="regent"><img src="https://cdn.spire-codex.com/characters/combat_regent.webp" class="char-icon-mini" onerror="this.style.display='none';">Regent</div>
                    <div class="char-pill" data-pool="necrobinder"><img src="https://cdn.spire-codex.com/characters/combat_necrobinder.webp" class="char-icon-mini" onerror="this.style.display='none';">Necrobinder</div>
                    <div class="char-pill" data-pool="shared">Shared</div>
                </div>
            </div>
            <div class="compendium-grid" id="comp-potions-grid">
                <!-- Populated dynamically -->
            </div>
        </div>

        <!-- Campfire Sub-View -->
        <div id="sub-view-campfire" class="comp-sub-view" style="display: none;">
            <div class="filter-panel">
                <div class="search-wrapper" style="flex-grow: 1;">
                    <input type="text" id="comp-campfire-search" class="search-input" placeholder="Search campfire abilities by name, effect, or requirement...">
                </div>
            </div>
            <div class="compendium-grid" id="comp-campfire-grid">
                <!-- Populated dynamically -->
            </div>
        </div>

        <!-- Mobs Sub-View -->
        <div id="sub-view-mobs" class="comp-sub-view" style="display: none;">
            <div class="filter-panel" style="flex-wrap: wrap; gap: 12px;">
                <div class="search-wrapper" style="flex-grow: 1; min-width: 250px;">
                    <input type="text" id="comp-mobs-search" class="search-input" placeholder="Search enemies by name, behavior, or moves...">
                </div>
                
                <div class="char-pills" id="comp-mobs-type-pills">
                    <div class="char-pill active" data-type="all">All Types</div>
                    <div class="char-pill" data-type="normal">Normal</div>
                    <div class="char-pill" data-type="elite">Elite</div>
                    <div class="char-pill" data-type="boss">Boss</div>
                </div>

                <div class="char-pills" id="comp-mobs-act-pills">
                    <div class="char-pill active" data-act="all">All Acts</div>
                    <div class="char-pill" data-act="Act 1 - Overgrowth">Act 1: Overgrowth</div>
                    <div class="char-pill" data-act="Act 2 - Hive">Act 2: Hive</div>
                    <div class="char-pill" data-act="Act 3 - Glory">Act 3: Glory</div>
                    <div class="char-pill" data-act="Underdocks">Underdocks</div>
                    <div class="char-pill" data-act="other">Other / Special</div>
                </div>
            </div>

            <div class="card runs-container" style="margin-top: 16px;">
                <div class="runs-header-row">
                    <h3 style="margin: 0; font-size: 16px; font-weight: 600; color: var(--text-main);">Monsters & Bosses Compendium</h3>
                    <span class="runs-count-badge" id="comp-mobs-count">Showing 0 enemies</span>
                </div>
                <div class="table-wrapper" style="max-height: 600px; margin-top: 12px;">
                    <table>
                        <thead>
                            <tr id="comp-mobs-header-row-tr">
                                <th data-sort="name" onclick="sortEnemies('name')">Enemy Name</th>
                                <th data-sort="type" onclick="sortEnemies('type')" style="width: 120px;">Type</th>
                                <th data-sort="hp" onclick="sortEnemies('hp')" style="text-align:center; width: 120px;">HP Range</th>
                                <th data-sort="acts" onclick="sortEnemies('acts')">Acts / Levels</th>
                                <th style="width: 45%;">Moves & Intents</th>
                            </tr>
                        </thead>
                        <tbody id="comp-mobs-table-body">
                            <!-- Populated dynamically -->
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <!-- Events Sub-View -->
        <div id="sub-view-events" class="comp-sub-view" style="display: none;">
            <div class="filter-panel" style="flex-wrap: wrap; gap: 12px;">
                <div class="search-wrapper" style="flex-grow: 1; min-width: 250px;">
                    <input type="text" id="comp-events-search" class="search-input" placeholder="Search events by name, text, or choice outcomes...">
                </div>

                <div class="char-pills" id="comp-events-act-pills">
                    <div class="char-pill active" data-act="all">All Acts</div>
                    <div class="char-pill" data-act="Act 1 - Overgrowth">Act 1: Overgrowth</div>
                    <div class="char-pill" data-act="Act 2 - Hive">Act 2: Hive</div>
                    <div class="char-pill" data-act="Act 3 - Glory">Act 3: Glory</div>
                    <div class="char-pill" data-act="Underdocks">Underdocks</div>
                    <div class="char-pill" data-act="other">Other / Special</div>
                </div>
            </div>

            <div class="card runs-container" style="margin-top: 16px; padding: 20px;">
                <div class="runs-header-row" style="margin-bottom: 16px;">
                    <h3 style="margin: 0; font-size: 16px; font-weight: 600; color: var(--text-main);">Choose Your Path: Events</h3>
                    <span class="runs-count-badge" id="comp-events-count">Showing 0 events</span>
                </div>
                <div class="events-grid-layout" id="comp-events-grid">
                    <!-- Populated dynamically -->
                </div>
            </div>
        </div>

        <!-- Keywords Sub-View -->
        <div id="sub-view-keywords" class="comp-sub-view" style="display: none;">
            <div class="filter-panel">
                <div class="search-wrapper" style="flex-grow: 1;">
                    <input type="text" id="comp-keywords-search" class="search-input" placeholder="Search keywords by name or description...">
                </div>
            </div>
            <div class="compendium-grid" id="comp-keywords-grid">
                <!-- Populated dynamically -->
            </div>
        </div>
    </div>

    <!-- CARD STATISTICS TAB VIEW -->
    <div id="view-card-stats" style="display: none;">
        <!-- Filters panel -->
        <div class="filter-panel">
            <div class="search-wrapper">
                <input type="text" id="card-stats-search" class="search-input" placeholder="Search cards by name...">
            </div>
            
            <select id="card-stats-sort" class="select-filter">
                <option value="frequency">Sort by Frequency (Most Used)</option>
                <option value="winrate">Sort by Win Rate (%)</option>
                <option value="name">Sort by Name</option>
            </select>
            
            <div class="char-pills" id="card-stats-char-pills">
                <div class="char-pill active" data-char="all">All Classes</div>
                <div class="char-pill" data-char="ironclad"><img src="https://cdn.spire-codex.com/characters/combat_ironclad.webp" class="char-icon-mini" onerror="this.style.display='none';">Ironclad</div>
                <div class="char-pill" data-char="silent"><img src="https://cdn.spire-codex.com/characters/combat_silent.webp" class="char-icon-mini" onerror="this.style.display='none';">Silent</div>
                <div class="char-pill" data-char="defect"><img src="https://cdn.spire-codex.com/characters/combat_defect.webp" class="char-icon-mini" onerror="this.style.display='none';">Defect</div>
                <div class="char-pill" data-char="regent"><img src="https://cdn.spire-codex.com/characters/combat_regent.webp" class="char-icon-mini" onerror="this.style.display='none';">Regent</div>
                <div class="char-pill" data-char="necrobinder"><img src="https://cdn.spire-codex.com/characters/combat_necrobinder.webp" class="char-icon-mini" onerror="this.style.display='none';">Necrobinder</div>
                <div class="char-pill" data-char="shared">Neutral / Shared</div>
            </div>
        </div>
        
        <!-- Table container -->
        <div class="card runs-container">
            <div class="runs-header-row">
                <h3>Card Analytics</h3>
                <span class="runs-count-badge" id="card-stats-count">Showing 0 cards</span>
            </div>
            <div class="table-wrapper" style="max-height: 520px;">
                <table>
                    <thead>
                        <tr id="card-header-row-tr">
                            <th data-sort="name" onclick="sortCards('name')">Card Name</th>
                            <th data-sort="rarity" onclick="sortCards('rarity')">Rarity</th>
                            <th data-sort="timesPicked" onclick="sortCards('timesPicked')" style="text-align:center;">Runs Contained</th>
                            <th data-sort="wins" onclick="sortCards('wins')" style="text-align:center;">Wins - Losses</th>
                            <th data-sort="winRate" onclick="sortCards('winRate')">Win Rate (%)</th>
                            <th data-sort="avgFloors" onclick="sortCards('avgFloors')" style="text-align:center;">Avg. Floor</th>
                            <th data-sort="avgAscension" onclick="sortCards('avgAscension')" style="text-align:center;">Avg. Ascension</th>
                        </tr>
                    </thead>
                    <tbody id="card-stats-table-body">
                        <!-- Populated dynamically -->
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <!-- RELIC STATISTICS TAB VIEW -->
    <div id="view-relic-stats" style="display: none;">
        <!-- Filters panel -->
        <div class="filter-panel">
            <div class="search-wrapper">
                <input type="text" id="relic-stats-search" class="search-input" placeholder="Search relics by name...">
            </div>
            
            <select id="relic-stats-sort" class="select-filter">
                <option value="frequency">Sort by Frequency (Most Used)</option>
                <option value="winrate">Sort by Win Rate (%)</option>
                <option value="name">Sort by Name</option>
            </select>
            
            <div class="char-pills" id="relic-stats-char-pills">
                <div class="char-pill active" data-char="all">All Classes</div>
                <div class="char-pill" data-char="ironclad"><img src="https://cdn.spire-codex.com/characters/combat_ironclad.webp" class="char-icon-mini" onerror="this.style.display='none';">Ironclad</div>
                <div class="char-pill" data-char="silent"><img src="https://cdn.spire-codex.com/characters/combat_silent.webp" class="char-icon-mini" onerror="this.style.display='none';">Silent</div>
                <div class="char-pill" data-char="defect"><img src="https://cdn.spire-codex.com/characters/combat_defect.webp" class="char-icon-mini" onerror="this.style.display='none';">Defect</div>
                <div class="char-pill" data-char="regent"><img src="https://cdn.spire-codex.com/characters/combat_regent.webp" class="char-icon-mini" onerror="this.style.display='none';">Regent</div>
                <div class="char-pill" data-char="necrobinder"><img src="https://cdn.spire-codex.com/characters/combat_necrobinder.webp" class="char-icon-mini" onerror="this.style.display='none';">Necrobinder</div>
            </div>
        </div>
        
        <!-- Table container -->
        <div class="card runs-container">
            <div class="runs-header-row">
                <h3>Relic Analytics</h3>
                <span class="runs-count-badge" id="relic-stats-count">Showing 0 relics</span>
            </div>
            <div class="table-wrapper" style="max-height: 520px;">
                <table>
                    <thead>
                        <tr id="relic-header-row-tr">
                            <th data-sort="name" onclick="sortRelics('name')">Relic Name</th>
                            <th data-sort="rarity" onclick="sortRelics('rarity')">Rarity</th>
                            <th data-sort="timesPicked" onclick="sortRelics('timesPicked')" style="text-align:center;">Runs Contained</th>
                            <th data-sort="wins" onclick="sortRelics('wins')" style="text-align:center;">Wins - Losses</th>
                            <th data-sort="winRate" onclick="sortRelics('winRate')">Win Rate (%)</th>
                            <th data-sort="avgFloors" onclick="sortRelics('avgFloors')" style="text-align:center;">Avg. Floor</th>
                            <th data-sort="avgAscension" onclick="sortRelics('avgAscension')" style="text-align:center;">Avg. Ascension</th>
                        </tr>
                    </thead>
                    <tbody id="relic-stats-table-body">
                        <!-- Populated dynamically -->
                    </tbody>
                </table>
            </div>
        </div>
    </div>



    <!-- Floating Tooltip -->
    <div id="db-tooltip" class="db-tooltip" style="display: none;"></div>

    <!-- Data Injection -->
    <script>
        const rawRunData = __RUN_DATA__;
        const sts2Database = __DB_DATA__;
    </script>

    <!-- Dashboard Logic -->
    <script>
        // Monster Encounter Mapping Helpers
        function getMonsterIdFromEncounter(encounterId) {
            if (!encounterId || !sts2Database || !sts2Database.monsters) return null;
            let clean = encounterId.toUpperCase().replace("ENCOUNTER.", "").replace("MONSTER.", "").replace("EVENT.", "").replace(/\s+/g, "_");
            
            // 1. Direct match on monster ID
            if (sts2Database.monsters[clean]) {
                return clean;
            }
            
            // 2. Match by stripping standard suffixes
            let base = clean.replace(/_(BOSS|ELITE|NORMAL|WEAK|EVENT_ENCOUNTER)$/, "");
            if (sts2Database.monsters[base]) {
                return base;
            }
            
            // 3. Match by checking the encounters array in the database
            for (const [id, monster] of Object.entries(sts2Database.monsters)) {
                if (monster.encounters && monster.encounters.includes(clean)) {
                    return id;
                }
            }
            
            // 4. Try matching base without suffix in encounters array
            for (const [id, monster] of Object.entries(sts2Database.monsters)) {
                if (monster.encounters) {
                    for (const enc of monster.encounters) {
                        let encBase = enc.replace(/_(BOSS|ELITE|NORMAL|WEAK|EVENT_ENCOUNTER)$/, "");
                        if (encBase === base) {
                            return id;
                        }
                    }
                }
            }
            
            // 5. Try name comparison: clean KILLED_BY text to compare to monster names
            let cleanTitle = clean.replace(/_/g, " ").toLowerCase();
            for (const [id, monster] of Object.entries(sts2Database.monsters)) {
                if (monster.name && monster.name.toLowerCase() === cleanTitle) {
                    return id;
                }
            }
            
            // 6. Fuzzy substring match on ID
            for (const [id, monster] of Object.entries(sts2Database.monsters)) {
                if (id.includes(base) || base.includes(id)) {
                    return id;
                }
            }
            
            return null;
        }

        function findMonsterIdByName(name) {
            if (!name || !sts2Database || !sts2Database.monsters) return null;
            const cleanName = name.toLowerCase().replace(/[^a-z0-9]/g, '');
            
            // 1. Match name directly
            for (const [id, monster] of Object.entries(sts2Database.monsters)) {
                if (monster.name && monster.name.toLowerCase().replace(/[^a-z0-9]/g, '') === cleanName) {
                    return id;
                }
            }
            
            // 2. Match ID directly or substring
            let cleanId = name.toUpperCase().replace(/\s+/g, '_');
            if (sts2Database.monsters[cleanId]) {
                return cleanId;
            }
            
            // 3. Match ID substring
            for (const id of Object.keys(sts2Database.monsters)) {
                if (id.includes(cleanId) || cleanId.includes(id)) {
                    return id;
                }
            }
            
            // 4. Try matching via encounter mapping
            let encounterResolve = getMonsterIdFromEncounter(name);
            if (encounterResolve) {
                return encounterResolve;
            }
            
            return null;
        }

        // Name Cleaners for fallback
        function cleanCharacterName(charId) {
            if (!charId) return "Unknown";
            let name = charId.replace(/^CHARACTER\./, "");
            return name.charAt(0).toUpperCase() + name.slice(1).toLowerCase();
        }

        function cleanRelicName(id) {
            if (!id) return "";
            let name = id.replace(/^RELIC\./, "").replace(/_/g, " ");
            return name.toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
        }

        function cleanCardName(id) {
            if (!id) return "";
            let name = id.replace(/^CARD\./, "").replace(/_/g, " ");
            return name.toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
        }

        // Database Lookup Helpers
        function getRelicName(id) {
            if (sts2Database && sts2Database.relics && sts2Database.relics[id]) {
                return sts2Database.relics[id].name;
            }
            return cleanRelicName(id);
        }

        function getCardName(id) {
            if (sts2Database && sts2Database.cards && sts2Database.cards[id]) {
                return sts2Database.cards[id].name;
            }
            return cleanCardName(id);
        }

        // Helper to resolve legacy clean names to raw database IDs
        function findIdByName(name, category) {
            if (!sts2Database) return null;
            const db = category === 'card' ? sts2Database.cards : sts2Database.relics;
            const cleanName = name.toLowerCase().replace(/[^a-z0-9]/g, '');
            
            // Try matching database item's name
            for (const [id, item] of Object.entries(db)) {
                if (item.name && item.name.toLowerCase().replace(/[^a-z0-9]/g, '') === cleanName) {
                    return id;
                }
            }
            
            // Try matching cleaned ID
            for (const [id, item] of Object.entries(db)) {
                const cleanIdName = category === 'card' ? cleanCardName(id) : cleanRelicName(id);
                if (cleanIdName.toLowerCase().replace(/[^a-z0-9]/g, '') === cleanName) {
                    return id;
                }
            }
            
            return null;
        }

        // BBCode Parser to HTML Style
        function formatDescription(desc) {
            if (!desc) return '';
            let html = desc
                // Clean encoding anomalies (mojibake)
                .replace(/\u00e2\u20ac\u0153|â€œ|\uFFFD\?o|\?o/g, '&ldquo;')
                .replace(/\u00e2\u20ac\u009d|â€\u009d|\uFFFD\?\?|\?\?/g, '&rdquo;')
                // Standard BBCode parsing
                .replace(/\[gold\]/g, '<span class="text-gold">')
                .replace(/\[\/gold\]/g, '</span>')
                .replace(/\[blue\]/g, '<span class="text-blue">')
                .replace(/\[\/blue\]/g, '</span>')
                .replace(/\[purple\]/g, '<span class="text-purple">')
                .replace(/\[\/purple\]/g, '</span>')
                .replace(/\[green\]/g, '<span class="text-green">')
                .replace(/\[\/green\]/g, '</span>')
                .replace(/\[red\]/g, '<span class="text-red">')
                .replace(/\[\/red\]/g, '</span>')
                .replace(/\[orange\]/g, '<span style="color: #fb923c; font-weight: 600;">')
                .replace(/\[\/orange\]/g, '</span>')
                .replace(/\[aqua\]/g, '<span style="color: #22d3ee; font-weight: 600;">')
                .replace(/\[\/aqua\]/g, '</span>')
                .replace(/\[sine\]/g, '<span style="display: inline-block; font-style: italic; color: #a5b4fc;">')
                .replace(/\[\/sine\]/g, '</span>')
                .replace(/\[jitter\]/g, '<span style="display: inline-block; font-style: italic; color: #f87171;">')
                .replace(/\[\/jitter\]/g, '</span>')
                .replace(/\[rainbow\]/g, '<span style="font-weight: bold; background: linear-gradient(to right, #f87171, #fb923c, #fbbf24, #34d399, #3b82f6, #c084fc); -webkit-background-clip: text; -webkit-text-fill-color: transparent;">')
                .replace(/\[\/rainbow\]/g, '</span>')
                .replace(/\[b\]/g, '<strong>')
                .replace(/\[\/b\]/g, '</strong>')
                .replace(/\[energy:(\d+)\]/g, (match, p1) => {
                    return `<span class="energy-icon energy-${p1}">${p1}</span>`;
                })
                .replace(/\[star:(\d+)\]/g, (match, p1) => {
                    return `<span class="star-icon star-${p1}">${p1}&#9733;</span>`;
                })
                .replace(/\n/g, '<br>');
            return html;
        }

        // JS Helpers
        function getFloorCount(data) {
            let count = 0;
            if (data.map_point_history && Array.isArray(data.map_point_history)) {
                data.map_point_history.forEach(act => {
                    if (Array.isArray(act)) {
                        count += act.length;
                    }
                });
            }
            return count;
        }

        function getKilledBy(data, win, abandoned) {
            if (win) return "N/A";
            let encounter = data.killed_by_encounter || "NONE.NONE";
            let event = data.killed_by_event || "NONE.NONE";
            if (encounter !== "NONE.NONE") {
                let name = encounter.replace("ENCOUNTER.", "").replace("MONSTER.", "").replace(/_/g, " ");
                return name.toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
            } else if (event !== "NONE.NONE") {
                let name = event.replace("EVENT.", "").replace(/_/g, " ");
                return name.toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
            } else if (abandoned) {
                return "Abandoned";
            }
            return "Unknown Cause";
        }

        // State variables
        let allRuns = [];
        let filteredRuns = [];
        let activeChar = 'all';
        let charChart = null;
        let shareChart = null;
        let selectedRunId = null;
        
        // Compendium Tab state
        let activeCompSubTab = 'cards';
        let activeCardsChar = 'all';
        let cardsSortBy = 'name';
        let activeRelicsChar = 'all';
        let relicsSortBy = 'name';
        let activePotionsRarity = 'all';
        let activePotionsPool = 'all';
        let activeMobsAct = 'all';
        let activeMobsType = 'all';
        let mobsSortCol = 'name';
        let mobsSortDir = 'asc';
        let activeEventsAct = 'all';

        // Card Stats Tab state
        let activeCardStatsChar = 'all';

        // Relic Stats Tab state
        let activeRelicStatsChar = 'all';

        // Multiplayer Tab state
        let activeMultiplayerResult = 'all';
        let activeMultiplayerAsc = 'all';
        let activeDetailPlayerIndex = 0;
        let activeDetailSubTab = 'equipment';
        const nodeStyles = {
            'monster': { icon: '\u2694\uFE0F', label: 'Combat', color: '#f97316', bg: 'rgba(249, 115, 22, 0.12)', border: 'rgba(249, 115, 22, 0.2)' },
            'elite': { icon: '\u{1F480}', label: 'Elite Combat', color: '#ef4444', bg: 'rgba(239, 68, 68, 0.12)', border: 'rgba(239, 68, 68, 0.2)' },
            'boss': { icon: '\u{1F451}', label: 'Boss Combat', color: '#a855f7', bg: 'rgba(168, 85, 247, 0.12)', border: 'rgba(168, 85, 247, 0.2)' },
            'rest_site': { icon: '\u{1F525}', label: 'Campfire', color: '#f59e0b', bg: 'rgba(245, 158, 11, 0.12)', border: 'rgba(245, 158, 11, 0.2)' },
            'treasure': { icon: '\u{1F48E}', label: 'Treasure Chest', color: '#10b981', bg: 'rgba(16, 185, 129, 0.12)', border: 'rgba(16, 185, 129, 0.2)' },
            'shop': { icon: '\u{1F6D2}', label: 'Merchant', color: '#eab308', bg: 'rgba(234, 179, 8, 0.12)', border: 'rgba(234, 179, 8, 0.2)' },
            'unknown': { icon: '\u2753', label: 'Event', color: '#06b6d4', bg: 'rgba(6, 182, 212, 0.12)', border: 'rgba(6, 182, 212, 0.2)' },
            'ancient': { icon: '\u{1F3DB}\uFE0F', label: 'Ancient Chest', color: '#6366f1', bg: 'rgba(99, 102, 241, 0.12)', border: 'rgba(99, 102, 241, 0.2)' }
        };

        // Sorting states
        let runsSortCol = 'date';
        let runsSortDir = 'desc';
        let multiSortCol = 'date';
        let multiSortDir = 'desc';
        let cardSortCol = 'timesPicked';
        let cardSortDir = 'desc';
        let relicSortCol = 'timesPicked';
        let relicSortDir = 'desc';
        
        // DOM Elements
        const kpiTotalRuns = document.getElementById('kpi-total-runs');
        const kpiSubTotal = document.getElementById('kpi-sub-total');
        const kpiWinRate = document.getElementById('kpi-win-rate');
        const kpiSubWins = document.getElementById('kpi-sub-wins');
        const kpiPlaytime = document.getElementById('kpi-playtime');
        const kpiSubAvgTime = document.getElementById('kpi-sub-avg-time');
        const kpiMaxAsc = document.getElementById('kpi-max-asc');
        const kpiSubFavChar = document.getElementById('kpi-sub-fav-char');
        
        const searchInput = document.getElementById('search-seed');
        const filterResult = document.getElementById('filter-result');
        const filterAsc = document.getElementById('filter-asc');
        const runsFilteredCount = document.getElementById('runs-filtered-count');
        const runsTableBody = document.getElementById('runs-table-body');
        
        // Detail DOM
        const detailCharName = document.getElementById('detail-char-name');
        const detailDate = document.getElementById('detail-date');
        const detailSeedBox = document.getElementById('detail-seed-box');
        const detailSeed = document.getElementById('detail-seed');
        const detailContent = document.getElementById('detail-content');
        const detailResult = document.getElementById('detail-result');
        const detailFloors = document.getElementById('detail-floors');
        const detailDuration = document.getElementById('detail-duration');
        const detailRelicsCount = document.getElementById('detail-relics-count');
        const detailRelics = document.getElementById('detail-relics');
        const detailDeckCount = document.getElementById('detail-deck-count');
        const detailDeck = document.getElementById('detail-deck');
        
        const deathListBody = document.getElementById('death-list-body');
        const zipInput = document.getElementById('zip-input');
        const runInput = document.getElementById('run-input');
        const resetBtn = document.getElementById('reset-btn');
        
        // Compendium DOM Elements
        // Cards
        const compCardsSearch = document.getElementById('comp-cards-search');
        const compCardsSortBy = document.getElementById('comp-cards-sort-by');
        const compCardsGrid = document.getElementById('comp-cards-grid');
        // Relics
        const compRelicsSearch = document.getElementById('comp-relics-search');
        const compRelicsSortBy = document.getElementById('comp-relics-sort-by');
        const compRelicsGrid = document.getElementById('comp-relics-grid');
        // Potions
        const compPotionsSearch = document.getElementById('comp-potions-search');
        const compPotionsRarity = document.getElementById('comp-potions-rarity');
        const compPotionsGrid = document.getElementById('comp-potions-grid');
        // Campfire
        const compCampfireSearch = document.getElementById('comp-campfire-search');
        const compCampfireGrid = document.getElementById('comp-campfire-grid');
        // Mobs
        const compMobsSearch = document.getElementById('comp-mobs-search');
        const compMobsTableBody = document.getElementById('comp-mobs-table-body');
        const compMobsCount = document.getElementById('comp-mobs-count');
        // Events
        const compEventsSearch = document.getElementById('comp-events-search');
        const compEventsGrid = document.getElementById('comp-events-grid');
        const compEventsCount = document.getElementById('comp-events-count');
        // Keywords
        const compKeywordsSearch = document.getElementById('comp-keywords-search');
        const compKeywordsGrid = document.getElementById('comp-keywords-grid');

        // Colors
        const charColors = {
            'Ironclad': '#ef4444',
            'Silent': '#10b981',
            'Defect': '#3b82f6',
            'Regent': '#fbbf24',
            'Necrobinder': '#a855f7',
            'Unknown': '#64748b'
        };

        // Time formatter helper
        function formatDuration(secs) {
            const h = Math.floor(secs / 3600);
            const m = Math.floor((secs % 3600) / 60);
            const s = secs % 60;
            if (h > 0) return `${h}h ${m}m`;
            return `${m}m ${s}s`;
        }

        // Version comparison helper
        function compareVersions(a, b) {
            const partsA = (a || '').replace(/^v/, '').split('.').map(Number);
            const partsB = (b || '').replace(/^v/, '').split('.').map(Number);
            for (let i = 0; i < Math.max(partsA.length, partsB.length); i++) {
                const numA = partsA[i] || 0;
                const numB = partsB[i] || 0;
                if (numA < numB) return -1;
                if (numA > numB) return 1;
            }
            return 0;
        }

        // Initialize App
        function init() {
            // Check localStorage cache for imported data
            try {
                const cached = localStorage.getItem('sts2_runs_data');
                if (cached) {
                    allRuns = JSON.parse(cached);
                    resetBtn.style.display = 'inline-flex';
                } else {
                    allRuns = rawRunData;
                }
            } catch (e) {
                allRuns = rawRunData;
            }

            filteredRuns = [...allRuns];

            populateAscensionFilter();
            populateMultiplayerAscensionFilter();
            calculateKPIs();
            renderTopDeaths();
            applyFilters();
            setupCharts();
            
            // Default select the first run if available
            if (allRuns.length > 0) {
                selectRun(allRuns[allRuns.length - 1].id);
            }

            // Multiplayer event listeners
            const multiSearchInput = document.getElementById('multi-search');
            if (multiSearchInput) {
                multiSearchInput.addEventListener('input', applyMultiplayerFilters);
            }
            const multiFilterResult = document.getElementById('multi-filter-result');
            if (multiFilterResult) {
                multiFilterResult.addEventListener('change', applyMultiplayerFilters);
            }
            const multiFilterAsc = document.getElementById('multi-filter-asc');
            if (multiFilterAsc) {
                multiFilterAsc.addEventListener('change', applyMultiplayerFilters);
            }
            
            // Card stats event listeners
            const cardStatsSearchInput = document.getElementById('card-stats-search');
            if (cardStatsSearchInput) {
                cardStatsSearchInput.addEventListener('input', renderCardStats);
            }
            const cardStatsSortSelect = document.getElementById('card-stats-sort');
            if (cardStatsSortSelect) {
                cardStatsSortSelect.addEventListener('change', () => {
                    const val = cardStatsSortSelect.value;
                    if (val === 'frequency') {
                        cardSortCol = 'timesPicked';
                        cardSortDir = 'desc';
                    } else if (val === 'winrate') {
                        cardSortCol = 'winRate';
                        cardSortDir = 'desc';
                    } else if (val === 'name') {
                        cardSortCol = 'name';
                        cardSortDir = 'asc';
                    }
                    renderCardStats();
                    updateTableHeaders('card-header-row-tr', cardSortCol, cardSortDir);
                });
            }
            document.querySelectorAll('#card-stats-char-pills .char-pill').forEach(pill => {
                pill.addEventListener('click', () => {
                    document.querySelectorAll('#card-stats-char-pills .char-pill').forEach(p => p.classList.remove('active'));
                    pill.classList.add('active');
                    activeCardStatsChar = pill.dataset.char;
                    renderCardStats();
                });
            });

            // Relic stats event listeners
            const relicStatsSearchInput = document.getElementById('relic-stats-search');
            if (relicStatsSearchInput) {
                relicStatsSearchInput.addEventListener('input', renderRelicStats);
            }
            const relicStatsSortSelect = document.getElementById('relic-stats-sort');
            if (relicStatsSortSelect) {
                relicStatsSortSelect.addEventListener('change', () => {
                    const val = relicStatsSortSelect.value;
                    if (val === 'frequency') {
                        relicSortCol = 'timesPicked';
                        relicSortDir = 'desc';
                    } else if (val === 'winrate') {
                        relicSortCol = 'winRate';
                        relicSortDir = 'desc';
                    } else if (val === 'name') {
                        relicSortCol = 'name';
                        relicSortDir = 'asc';
                    }
                    renderRelicStats();
                    updateTableHeaders('relic-header-row-tr', relicSortCol, relicSortDir);
                });
            }
            document.querySelectorAll('#relic-stats-char-pills .char-pill').forEach(pill => {
                pill.addEventListener('click', () => {
                    document.querySelectorAll('#relic-stats-char-pills .char-pill').forEach(p => p.classList.remove('active'));
                    pill.classList.add('active');
                    activeRelicStatsChar = pill.dataset.char;
                    renderRelicStats();
                });
            });

            // Cards Sub-view listeners
            if (compCardsSearch) compCardsSearch.addEventListener('input', renderCompendiumCards);
            if (compCardsSortBy) compCardsSortBy.addEventListener('change', renderCompendiumCards);
            document.querySelectorAll('#comp-cards-char-pills .char-pill').forEach(pill => {
                pill.addEventListener('click', () => {
                    document.querySelectorAll('#comp-cards-char-pills .char-pill').forEach(p => p.classList.remove('active'));
                    pill.classList.add('active');
                    activeCardsChar = pill.dataset.char;
                    renderCompendiumCards();
                });
            });

            // Relics Sub-view listeners
            if (compRelicsSearch) compRelicsSearch.addEventListener('input', renderCompendiumRelics);
            if (compRelicsSortBy) compRelicsSortBy.addEventListener('change', renderCompendiumRelics);
            document.querySelectorAll('#comp-relics-char-pills .char-pill').forEach(pill => {
                pill.addEventListener('click', () => {
                    document.querySelectorAll('#comp-relics-char-pills .char-pill').forEach(p => p.classList.remove('active'));
                    pill.classList.add('active');
                    activeRelicsChar = pill.dataset.char;
                    renderCompendiumRelics();
                });
            });

            // Potions Sub-view listeners
            if (compPotionsSearch) compPotionsSearch.addEventListener('input', renderCompendiumPotions);
            if (compPotionsRarity) compPotionsRarity.addEventListener('change', renderCompendiumPotions);
            document.querySelectorAll('#comp-potions-pool-pills .char-pill').forEach(pill => {
                pill.addEventListener('click', () => {
                    document.querySelectorAll('#comp-potions-pool-pills .char-pill').forEach(p => p.classList.remove('active'));
                    pill.classList.add('active');
                    activePotionsPool = pill.dataset.pool;
                    renderCompendiumPotions();
                });
            });

            // Campfire Sub-view listeners
            if (compCampfireSearch) compCampfireSearch.addEventListener('input', renderCompendiumCampfire);

            // Mobs Sub-view listeners
            if (compMobsSearch) compMobsSearch.addEventListener('input', renderCompendiumMobs);
            document.querySelectorAll('#comp-mobs-type-pills .char-pill').forEach(pill => {
                pill.addEventListener('click', () => {
                    document.querySelectorAll('#comp-mobs-type-pills .char-pill').forEach(p => p.classList.remove('active'));
                    pill.classList.add('active');
                    activeMobsType = pill.dataset.type;
                    renderCompendiumMobs();
                });
            });
            document.querySelectorAll('#comp-mobs-act-pills .char-pill').forEach(pill => {
                pill.addEventListener('click', () => {
                    document.querySelectorAll('#comp-mobs-act-pills .char-pill').forEach(p => p.classList.remove('active'));
                    pill.classList.add('active');
                    activeMobsAct = pill.dataset.act;
                    renderCompendiumMobs();
                });
            });

            // Events Sub-view listeners
            if (compEventsSearch) compEventsSearch.addEventListener('input', renderCompendiumEvents);
            document.querySelectorAll('#comp-events-act-pills .char-pill').forEach(pill => {
                pill.addEventListener('click', () => {
                    document.querySelectorAll('#comp-events-act-pills .char-pill').forEach(p => p.classList.remove('active'));
                    pill.classList.add('active');
                    activeEventsAct = pill.dataset.act;
                    renderCompendiumEvents();
                });
            });

            // Keywords Sub-view listeners
            if (compKeywordsSearch) compKeywordsSearch.addEventListener('input', renderCompendiumKeywords);
            
            // Overview KPI cards event listeners
            document.getElementById('kpi-card-runs').addEventListener('mouseenter', (e) => showKpiTooltip(e, 'runs'));
            document.getElementById('kpi-card-runs').addEventListener('mousemove', moveTooltip);
            document.getElementById('kpi-card-runs').addEventListener('mouseleave', hideTooltip);

            document.getElementById('kpi-card-winrate').addEventListener('mouseenter', (e) => showKpiTooltip(e, 'winrate'));
            document.getElementById('kpi-card-winrate').addEventListener('mousemove', moveTooltip);
            document.getElementById('kpi-card-winrate').addEventListener('mouseleave', hideTooltip);

            document.getElementById('kpi-card-playtime').addEventListener('mouseenter', (e) => showKpiTooltip(e, 'playtime'));
            document.getElementById('kpi-card-playtime').addEventListener('mousemove', moveTooltip);
            document.getElementById('kpi-card-playtime').addEventListener('mouseleave', hideTooltip);

            document.getElementById('kpi-card-maxasc').addEventListener('mouseenter', (e) => showKpiTooltip(e, 'maxasc'));
            document.getElementById('kpi-card-maxasc').addEventListener('mousemove', moveTooltip);
            document.getElementById('kpi-card-maxasc').addEventListener('mouseleave', hideTooltip);



            // Initialize sort indicators
            updateTableHeaders('runs-header-row-tr', runsSortCol, runsSortDir);
            updateTableHeaders('multi-header-row-tr', multiSortCol, multiSortDir);
            updateTableHeaders('card-header-row-tr', cardSortCol, cardSortDir);
            updateTableHeaders('relic-header-row-tr', relicSortCol, relicSortDir);
        }

        // Setup Event Listeners
        document.querySelectorAll('.char-pills:not(#comp-char-pills) .char-pill').forEach(pill => {
            pill.addEventListener('click', (e) => {
                document.querySelectorAll('.char-pills:not(#comp-char-pills) .char-pill').forEach(p => p.classList.remove('active'));
                pill.classList.add('active');
                activeChar = pill.dataset.char;
                applyFilters();
            });
        });

        searchInput.addEventListener('input', applyFilters);
        filterResult.addEventListener('change', applyFilters);
        filterAsc.addEventListener('change', applyFilters);

        // Shared run parser: takes raw JSON data and a filename, returns a parsed run object
        function parseRunFile(data, fileName) {
            const win = data.win === true;
            const abandoned = data.was_abandoned === true;
            
            let isMultiplayer = false;
            let players = [];
            
            if (data.players && data.players.length > 0) {
                isMultiplayer = data.players.length > 1;
                data.players.forEach(p => {
                    let pChar = cleanCharacterName(p.character);
                    let pRelics = p.relics ? p.relics.map(r => r.id).filter(Boolean) : [];
                    let pDeck = p.deck ? p.deck.map(c => c.id).filter(Boolean) : [];
                    players.push({ character: pChar, relics: pRelics, deck: pDeck });
                });
            } else {
                let pChar = cleanCharacterName(data.character);
                let pRelics = data.relics ? data.relics.map(r => r.id).filter(Boolean) : [];
                let pDeck = data.deck ? data.deck.map(c => c.id).filter(Boolean) : [];
                players.push({ character: pChar, relics: pRelics, deck: pDeck });
            }
            
            const character = players.map(p => p.character).join(" + ");
            const relics = players.length > 0 ? players[0].relics : [];
            const deck = players.length > 0 ? players[0].deck : [];
            
            const startTimeRaw = data.start_time || Math.floor(Date.now() / 1000);
            const date = new Date(startTimeRaw * 1000).toISOString().replace('T', ' ').substring(0, 19);
            
            let minMap = [];
            if (data.map_point_history) {
                data.map_point_history.forEach(act => {
                    if (!act) return;
                    let minAct = [];
                    act.forEach(node => {
                        let rooms = [];
                        if (node.rooms) {
                            node.rooms.forEach(r => {
                                rooms.push({
                                    model_id: r.model_id,
                                    turns_taken: Number(r.turns_taken) || 0
                                });
                            });
                        }
                        let pStats = [];
                        if (node.player_stats) {
                            node.player_stats.forEach(p => {
                                let cardChoices = [];
                                if (p.card_choices) {
                                    p.card_choices.forEach(cc => {
                                        if (cc.was_picked) {
                                            cardChoices.push({
                                                was_picked: true,
                                                card: { id: cc.card ? cc.card.id : null }
                                            });
                                        }
                                    });
                                }
                                let relicChoices = [];
                                if (p.relic_choices) {
                                    p.relic_choices.forEach(rc => {
                                        if (rc.was_picked) {
                                            relicChoices.push({
                                                was_picked: true,
                                                choice: rc.choice
                                            });
                                        }
                                    });
                                }
                                let ancientChoices = [];
                                if (p.ancient_choice) {
                                    p.ancient_choice.forEach(ac => {
                                        if (ac.was_chosen) {
                                            ancientChoices.push({
                                                was_chosen: true,
                                                TextKey: ac.TextKey
                                            });
                                        }
                                    });
                                }
                                pStats.push({
                                    current_hp: Number(p.current_hp) || 0,
                                    max_hp: Number(p.max_hp) || 0,
                                    damage_taken: Number(p.damage_taken) || 0,
                                    hp_healed: Number(p.hp_healed) || 0,
                                    gold_spent: Number(p.gold_spent) || 0,
                                    gold_gained: Number(p.gold_gained) || 0,
                                    cards_gained_count: p.cards_gained ? p.cards_gained.length : 0,
                                    rest_site_choices: p.rest_site_choices || [],
                                    card_choices: cardChoices,
                                    relic_choices: relicChoices,
                                    ancient_choice: ancientChoices
                                });
                            });
                        }
                        minAct.push({
                            map_point_type: node.map_point_type,
                            rooms: rooms,
                            player_stats: pStats
                        });
                    });
                    minMap.push(minAct);
                });
            }

            return {
                id: fileName.replace(/\.run$/, ""),
                timestamp: startTimeRaw,
                date: date,
                character: character,
                version: data.build_id || "Unknown",
                mapPointHistory: minMap,
                win: win,
                abandoned: abandoned,
                ascension: data.ascension || 0,
                runTime: data.run_time || 0,
                killedBy: getKilledBy(data, win, abandoned),
                killedByEncounter: data.killed_by_encounter || "",
                floors: getFloorCount(data),
                seed: data.seed || "Unknown",
                relics: relics,
                deck: deck,
                isMultiplayer: isMultiplayer,
                players: players
            };
        }

        // Shared post-import refresh
        function refreshAfterImport(runs, message) {
            runs.sort((a, b) => a.timestamp - b.timestamp);
            
            try {
                localStorage.setItem('sts2_runs_data', JSON.stringify(runs));
            } catch (err) {
                console.error("Could not cache run data in localStorage", err);
            }
            
            allRuns = runs;
            resetBtn.style.display = 'inline-flex';
            
            populateAscensionFilter();
            populateMultiplayerAscensionFilter();
            calculateKPIs();
            renderTopDeaths();
            applyFilters();
            
            selectRun(allRuns[allRuns.length - 1].id);
            alert(message);
        }

        // ZIP Import Logic
        zipInput.addEventListener('change', function(e) {
            const file = e.target.files[0];
            if (!file) return;

            const reader = new FileReader();
            reader.onload = function(evt) {
                const zip = new JSZip();
                zip.loadAsync(evt.target.result).then(function(zipContent) {
                    const promises = [];
                    const newRuns = [];
                    
                    zipContent.forEach(function (relativePath, zipEntry) {
                        if (zipEntry.name.endsWith('.run')) {
                            const promise = zipEntry.async("string").then(function (content) {
                                try {
                                    const data = JSON.parse(content);
                                    newRuns.push(parseRunFile(data, zipEntry.name));
                                } catch (err) {
                                    console.error("Failed to parse run file in zip: " + zipEntry.name, err);
                                }
                            });
                            promises.push(promise);
                        }
                    });
                    
                    Promise.all(promises).then(() => {
                        if (newRuns.length > 0) {
                            refreshAfterImport(newRuns, `Successfully imported ${newRuns.length} runs from ${file.name}!`);
                        } else {
                            alert("No Slay the Spire 2 .run files found in this zip.");
                        }
                    });
                }).catch(function(err) {
                    alert("Error reading zip file: " + err.message);
                });
            };
            reader.readAsArrayBuffer(file);
            zipInput.value = '';
        });

        // Individual .run File Import Logic
        runInput.addEventListener('change', function(e) {
            const files = Array.from(e.target.files);
            if (files.length === 0) return;
            
            const promises = [];
            const parsedRuns = [];
            let failCount = 0;
            
            files.forEach(file => {
                const promise = new Promise((resolve) => {
                    const reader = new FileReader();
                    reader.onload = function(evt) {
                        try {
                            const data = JSON.parse(evt.target.result);
                            parsedRuns.push(parseRunFile(data, file.name));
                        } catch (err) {
                            console.error("Failed to parse run file: " + file.name, err);
                            failCount++;
                        }
                        resolve();
                    };
                    reader.onerror = function() {
                        console.error("Failed to read file: " + file.name);
                        failCount++;
                        resolve();
                    };
                    reader.readAsText(file);
                });
                promises.push(promise);
            });
            
            Promise.all(promises).then(() => {
                if (parsedRuns.length > 0) {
                    // Merge with existing runs, avoiding duplicates by ID
                    const existingIds = new Set(allRuns.map(r => r.id));
                    const uniqueNew = parsedRuns.filter(r => !existingIds.has(r.id));
                    const duplicateCount = parsedRuns.length - uniqueNew.length;
                    
                    const merged = [...allRuns, ...uniqueNew];
                    
                    let msg = `Successfully added ${uniqueNew.length} run${uniqueNew.length !== 1 ? 's' : ''}!`;
                    if (duplicateCount > 0) msg += ` (${duplicateCount} duplicate${duplicateCount !== 1 ? 's' : ''} skipped)`;
                    if (failCount > 0) msg += ` (${failCount} file${failCount !== 1 ? 's' : ''} failed to parse)`;
                    
                    refreshAfterImport(merged, msg);
                } else {
                    let msg = 'No valid .run files could be parsed.';
                    if (failCount > 0) msg += ` ${failCount} file${failCount !== 1 ? 's' : ''} failed.`;
                    alert(msg);
                }
            });
            runInput.value = '';
        });

        // Reset to default
        resetBtn.addEventListener('click', function() {
            localStorage.removeItem('sts2_runs_data');
            location.reload();
        });

        // Populate Ascension levels in dropdown
        function populateAscensionFilter() {
            filterAsc.innerHTML = '<option value="all">All Ascensions</option>';
            const ascensions = [...new Set(allRuns.map(r => r.ascension))].sort((a, b) => a - b);
            ascensions.forEach(asc => {
                const opt = document.createElement('option');
                opt.value = asc;
                opt.textContent = `Ascension A${asc}`;
                filterAsc.appendChild(opt);
            });
        }

        // Calculate Overview KPIs
        function calculateKPIs() {
            const total = allRuns.length;
            kpiTotalRuns.textContent = total;
            
            const wins = allRuns.filter(r => r.win).length;
            const losses = allRuns.filter(r => !r.win && !r.abandoned).length;
            const abandoned = allRuns.filter(r => r.abandoned).length;
            kpiSubTotal.textContent = `${wins}W / ${losses}L / ${abandoned}A`;
            
            const winRate = total > 0 ? ((wins / total) * 100).toFixed(1) : '0.0';
            kpiWinRate.textContent = `${winRate}%`;
            kpiSubWins.textContent = `${wins} victorious runs`;
            
            const totalSecs = allRuns.reduce((acc, r) => acc + r.runTime, 0);
            kpiPlaytime.textContent = formatDuration(totalSecs);
            
            const avgSecs = total > 0 ? Math.floor(totalSecs / total) : 0;
            kpiSubAvgTime.textContent = `Avg: ${formatDuration(avgSecs)} per run`;
            
            const maxAsc = allRuns.reduce((max, r) => r.ascension > max ? r.ascension : max, 0);
            kpiMaxAsc.textContent = `A${maxAsc}`;
            
            // Favorite character
            const charCounts = {};
            allRuns.forEach(r => {
                charCounts[r.character] = (charCounts[r.character] || 0) + 1;
            });
            let favChar = 'None';
            let maxCount = 0;
            for (const char in charCounts) {
                if (charCounts[char] > maxCount) {
                    maxCount = charCounts[char];
                    favChar = char;
                }
            }
            kpiSubFavChar.textContent = favChar !== 'None' ? `Most Played: ${favChar} (${maxCount} runs)` : "Preferred Character";
            updateHeaderMeta();
        }

        function updateHeaderMeta() {
            const metaSource = document.getElementById('meta-source');
            const metaUpdated = document.getElementById('meta-updated');
            if (!metaSource || !metaUpdated) return;
            
            const isImported = localStorage.getItem('sts2_runs_data') !== null;
            metaSource.textContent = allRuns.length > 0 ? (isImported ? 'Source: Imported Backup' : 'Source: Steam Saves') : 'Source: None';
            
            if (allRuns.length > 0) {
                const latestRun = allRuns.reduce((latest, r) => {
                    return (!latest || r.timestamp > latest.timestamp) ? r : latest;
                }, null);
                if (latestRun && latestRun.date) {
                    const dateOnly = latestRun.date.split(' ')[0];
                    metaUpdated.textContent = `Last Run: ${dateOnly}`;
                } else {
                    metaUpdated.textContent = 'Last Run: Unknown';
                }
            } else {
                metaUpdated.textContent = 'Last Run: None';
            }
        }

        // Render Top Death Causes
        function renderTopDeaths() {
            const deaths = {};
            allRuns.forEach(r => {
                if (!r.win && r.killedBy !== 'N/A' && r.killedBy !== 'Abandoned' && r.killedBy !== 'Unknown Cause') {
                    deaths[r.killedBy] = (deaths[r.killedBy] || 0) + 1;
                }
            });
            
            const sortedDeaths = Object.entries(deaths)
                .sort((a, b) => b[1] - a[1])
                .slice(0, 5);
                
            const maxDeaths = sortedDeaths.length > 0 ? sortedDeaths[0][1] : 1;
            
            deathListBody.innerHTML = '';
            if (sortedDeaths.length === 0) {
                deathListBody.innerHTML = '<div class="no-data">No recorded deaths outside wins/abandons.</div>';
                return;
            }

            sortedDeaths.forEach(([name, count]) => {
                const pct = (count / maxDeaths) * 100;
                const div = document.createElement('div');
                div.className = 'death-item';
                
                // Find monster ID
                const monsterId = findMonsterIdByName(name);
                if (monsterId) {
                    div.style.cursor = 'help';
                    div.addEventListener('mouseenter', (e) => showTooltip(e, monsterId));
                    div.addEventListener('mousemove', moveTooltip);
                    div.addEventListener('mouseleave', hideTooltip);
                    
                    div.innerHTML = `
                        <span class="death-name" style="text-decoration: underline dotted rgba(255,255,255,0.3);">${name}</span>
                        <div class="death-bar-container">
                            <div class="death-bar" style="width: ${pct}%"></div>
                        </div>
                        <span class="death-count">${count}</span>
                    `;
                } else {
                    div.innerHTML = `
                        <span class="death-name">${name}</span>
                        <div class="death-bar-container">
                            <div class="death-bar" style="width: ${pct}%"></div>
                        </div>
                        <span class="death-count">${count}</span>
                    `;
                }
                
                deathListBody.appendChild(div);
            });
        }

        // Apply filters to Table and update Chart
        function applyFilters() {
            const searchVal = searchInput.value.toLowerCase();
            const resultVal = filterResult.value;
            const ascVal = filterAsc.value;
            
            filteredRuns = allRuns.filter(r => {
                if (r.isMultiplayer) return false;
                
                // Character Filter
                if (activeChar !== 'all' && (!r.character || r.character.toLowerCase() !== activeChar)) return false;
                
                // Result Filter
                if (resultVal === 'win' && !r.win) return false;
                if (resultVal === 'loss' && (r.win || r.abandoned)) return false;
                if (resultVal === 'abandoned' && !r.abandoned) return false;
                
                // Ascension Filter
                if (ascVal !== 'all' && r.ascension.toString() !== ascVal) return false;
                
                // Search Filter
                if (searchVal) {
                    const matchSeed = r.seed.toLowerCase().includes(searchVal);
                    const matchKilled = r.killedBy.toLowerCase().includes(searchVal);
                    if (!matchSeed && !matchKilled) return false;
                }
                
                return true;
            });
            
            const totalSP = allRuns.filter(r => !r.isMultiplayer).length;
            runsFilteredCount.textContent = `Showing ${filteredRuns.length} of ${totalSP} runs`;
            renderTable();
            updateCharts();
            renderPlaystyleChart(activeChar);
            renderSurvivalChart(activeChar);
        }

        // Render Runs Table
        // Render Runs Table
        function renderTable() {
            runsTableBody.innerHTML = '';
            if (filteredRuns.length === 0) {
                runsTableBody.innerHTML = '<tr><td colspan="8" class="no-data">No runs match active filters.</td></tr>';
                return;
            }
            
            const runsToShow = [...filteredRuns];
            runsToShow.sort((a, b) => {
                let valA = a[runsSortCol];
                let valB = b[runsSortCol];
                
                if (runsSortCol === 'result') {
                    valA = a.win ? 2 : (a.abandoned ? 1 : 0);
                    valB = b.win ? 2 : (b.abandoned ? 1 : 0);
                } else if (runsSortCol === 'version') {
                    const cmp = compareVersions(valA, valB);
                    return runsSortDir === 'asc' ? cmp : -cmp;
                } else if (runsSortCol === 'character' || runsSortCol === 'killedBy' || runsSortCol === 'date') {
                    valA = (valA || '').toString().toLowerCase();
                    valB = (valB || '').toString().toLowerCase();
                    return runsSortDir === 'asc' ? valA.localeCompare(valB) : valB.localeCompare(valA);
                } else {
                    valA = Number(valA) || 0;
                    valB = Number(valB) || 0;
                }
                
                if (valA < valB) return runsSortDir === 'asc' ? -1 : 1;
                if (valA > valB) return runsSortDir === 'asc' ? 1 : -1;
                return 0;
            });
            
            runsToShow.forEach(r => {
                const tr = document.createElement('tr');
                tr.dataset.id = r.id;
                if (r.id === selectedRunId) tr.className = 'selected';
                
                const dotColor = charColors[r.character] || charColors['Unknown'];
                let resBadge = '';
                if (r.win) {
                    resBadge = '<span class="badge badge-win">\u{1F3C6} WIN</span>';
                } else if (r.abandoned) {
                    resBadge = '<span class="badge badge-abandoned">\u{1F3F3}\u{FE0F} Abandon</span>';
                } else {
                    resBadge = '<span class="badge badge-loss">\u{1F480} Loss</span>';
                }
                
                tr.innerHTML = `
                    <td>${r.date}</td>
                    <td><span class="version-badge">${r.version || 'Unknown'}</span></td>
                    <td class="char-cell"><span class="char-indicator" style="background: ${dotColor}"></span>${r.character}</td>
                    <td style="font-weight:600;">A${r.ascension}</td>
                    <td>${resBadge}</td>
                    <td style="font-weight:600;">${r.floors}</td>
                    <td>${formatDuration(r.runTime)}</td>
                    <td class="${r.win ? 'text-win' : (r.abandoned ? 'text-abandoned' : 'text-loss')}">${r.killedBy}</td>
                `;
                
                tr.addEventListener('click', () => {
                    selectRun(r.id);
                });
                
                runsTableBody.appendChild(tr);
            });
        }

        // Populate Multiplayer Ascension levels in dropdown
        function populateMultiplayerAscensionFilter() {
            const multiFilterAsc = document.getElementById('multi-filter-asc');
            if (!multiFilterAsc) return;
            multiFilterAsc.innerHTML = '<option value="all">All Ascensions</option>';
            const multiRuns = allRuns.filter(r => r.isMultiplayer);
            const ascensions = [...new Set(multiRuns.map(r => r.ascension))].sort((a, b) => a - b);
            ascensions.forEach(asc => {
                const opt = document.createElement('option');
                opt.value = asc;
                opt.textContent = `Ascension A${asc}`;
                multiFilterAsc.appendChild(opt);
            });
        }

        // Apply filters to multiplayer view
        function applyMultiplayerFilters() {
            const multiFilterResult = document.getElementById('multi-filter-result');
            const multiFilterAsc = document.getElementById('multi-filter-asc');
            
            activeMultiplayerResult = multiFilterResult ? multiFilterResult.value : 'all';
            activeMultiplayerAsc = multiFilterAsc ? multiFilterAsc.value : 'all';
            
            renderMultiplayerTable();
        }

        // Render Multiplayer Table
        function renderMultiplayerTable() {
            const tbody = document.getElementById('multi-runs-table-body');
            const countEl = document.getElementById('multi-runs-count');
            if (!tbody) return;
            
            const multiSearchInput = document.getElementById('multi-search');
            const searchVal = multiSearchInput ? multiSearchInput.value.toLowerCase() : '';
            
            // Filter runs
            const multiRuns = allRuns.filter(r => {
                if (!r.isMultiplayer) return false;
                
                // Result filter
                if (activeMultiplayerResult === 'win' && !r.win) return false;
                if (activeMultiplayerResult === 'loss' && (r.win || r.abandoned)) return false;
                if (activeMultiplayerResult === 'abandoned' && !r.abandoned) return false;
                
                // Ascension filter
                if (activeMultiplayerAsc !== 'all' && r.ascension.toString() !== activeMultiplayerAsc) return false;
                
                // Search filter (seed, killedBy, player characters)
                if (searchVal) {
                    const matchSeed = r.seed.toLowerCase().includes(searchVal);
                    const matchKilled = r.killedBy.toLowerCase().includes(searchVal);
                    const matchChar = r.character ? r.character.toLowerCase().includes(searchVal) : false;
                    if (!matchSeed && !matchKilled && !matchChar) return false;
                }
                
                return true;
            });
            
            if (countEl) {
                const totalMulti = allRuns.filter(r => r.isMultiplayer).length;
                countEl.textContent = `Showing ${multiRuns.length} of ${totalMulti} runs`;
            }
            
            tbody.innerHTML = '';
            if (multiRuns.length === 0) {
                tbody.innerHTML = '<tr><td colspan="9" class="no-data">No co-op runs match active filters.</td></tr>';
                return;
            }
            
            const runsToShow = [...multiRuns];
            runsToShow.sort((a, b) => {
                let valA = a[multiSortCol];
                let valB = b[multiSortCol];
                
                if (multiSortCol === 'result') {
                    valA = a.win ? 2 : (a.abandoned ? 1 : 0);
                    valB = b.win ? 2 : (b.abandoned ? 1 : 0);
                } else if (multiSortCol === 'version') {
                    const cmp = compareVersions(valA, valB);
                    return multiSortDir === 'asc' ? cmp : -cmp;
                } else if (multiSortCol === 'character' || multiSortCol === 'killedBy' || multiSortCol === 'date') {
                    valA = (valA || '').toString().toLowerCase();
                    valB = (valB || '').toString().toLowerCase();
                    return multiSortDir === 'asc' ? valA.localeCompare(valB) : valB.localeCompare(valA);
                } else {
                    valA = Number(valA) || 0;
                    valB = Number(valB) || 0;
                }
                
                if (valA < valB) return multiSortDir === 'asc' ? -1 : 1;
                if (valA > valB) return multiSortDir === 'asc' ? 1 : -1;
                return 0;
            });
            
            runsToShow.forEach(r => {
                const tr = document.createElement('tr');
                tr.dataset.id = r.id;
                if (r.id === selectedRunId) tr.className = 'selected';
                
                // Result badge
                let resBadge = '';
                if (r.win) {
                    resBadge = '<span class="badge badge-win">\u{1F3C6} WIN</span>';
                } else if (r.abandoned) {
                    resBadge = '<span class="badge badge-abandoned">\u{1F3F3}\u{FE0F} Abandon</span>';
                } else {
                    resBadge = '<span class="badge badge-loss">\u{1F480} Loss</span>';
                }
                
                // Generate dots for each player
                let playerIndicatorsHtml = '<span class="player-indicators">';
                if (r.players && r.players.length > 0) {
                    r.players.forEach(p => {
                        const dotColor = charColors[p.character] || charColors['Unknown'];
                        playerIndicatorsHtml += `<span class="char-indicator" style="background: ${dotColor}; margin-right: 2px;"></span>`;
                    });
                } else {
                    const dotColor = charColors[r.character] || charColors['Unknown'];
                    playerIndicatorsHtml += `<span class="char-indicator" style="background: ${dotColor}"></span>`;
                }
                playerIndicatorsHtml += '</span>';
                
                tr.innerHTML = `
                    <td>${r.date}</td>
                    <td><span class="version-badge">${r.version || 'Unknown'}</span></td>
                    <td class="char-cell">${playerIndicatorsHtml}${r.character}</td>
                    <td style="font-weight:600;">A${r.ascension}</td>
                    <td>${resBadge}</td>
                    <td style="font-weight:600;">${r.floors}</td>
                    <td>${formatDuration(r.runTime)}</td>
                    <td class="${r.win ? 'text-win' : (r.abandoned ? 'text-abandoned' : 'text-loss')}">${r.killedBy}</td>
                `;
                
                tr.addEventListener('click', () => {
                    selectRun(r.id);
                });
                
                tbody.appendChild(tr);
            });
        }

        // Render relics and deck cards to details card
        function renderInventory(deck, relics) {
            // Relics with Tooltips
            detailRelicsCount.textContent = relics.length;
            detailRelics.innerHTML = '';
            if (relics.length === 0) {
                detailRelics.innerHTML = '<span class="text-muted" style="font-size:12px; padding: 4px 0;">No relics collected.</span>';
            } else {
                relics.forEach(relic => {
                    const badge = document.createElement('span');
                    badge.className = 'detail-badge relic-badge';
                    badge.dataset.id = relic;
                    badge.textContent = getRelicName(relic);
                    
                    // Attach hover tooltip event listeners
                    badge.addEventListener('mouseenter', (e) => showTooltip(e, relic));
                    badge.addEventListener('mousemove', moveTooltip);
                    badge.addEventListener('mouseleave', hideTooltip);
                    
                    detailRelics.appendChild(badge);
                });
            }
            
            // Deck Cards with Tooltips
            const cardCounts = {};
            deck.forEach(card => {
                cardCounts[card] = (cardCounts[card] || 0) + 1;
            });
            
            detailDeckCount.textContent = deck.length;
            detailDeck.innerHTML = '';
            if (deck.length === 0) {
                detailDeck.innerHTML = '<span class="text-muted" style="font-size:12px; padding: 4px 0;">Empty deck.</span>';
            } else {
                Object.keys(cardCounts).sort().forEach(card => {
                    const count = cardCounts[card];
                    const badge = document.createElement('span');
                    badge.className = 'detail-badge';
                    badge.dataset.id = card;
                    badge.innerHTML = `<span class="card-count-badge">${count}x</span>${getCardName(card)}`;
                    
                    // Attach hover tooltip event listeners
                    badge.addEventListener('mouseenter', (e) => showTooltip(e, card));
                    badge.addEventListener('mousemove', moveTooltip);
                    badge.addEventListener('mouseleave', hideTooltip);
                    
                    detailDeck.appendChild(badge);
                });
            }
        }

        // Render details for selected player in co-op run
        function renderSelectedPlayerDetails(run, playerIdx) {
            if (!run || !run.players || !run.players[playerIdx]) return;
            const player = run.players[playerIdx];
            renderInventory(player.deck, player.relics);
        }

        // Select a run to view details
        function selectRun(id) {
            selectedRunId = id;
            const run = allRuns.find(r => r.id === id);
            if (!run) return;
            
            // Sync selection in both tables
            document.querySelectorAll('#runs-table-body tr').forEach(row => {
                if (row.dataset.id === id) row.classList.add('selected');
                else row.classList.remove('selected');
            });
            document.querySelectorAll('#multi-runs-table-body tr').forEach(row => {
                if (row.dataset.id === id) row.classList.add('selected');
                else row.classList.remove('selected');
            });
            
            detailCharName.textContent = run.character;
            detailCharName.style.color = charColors[run.character] || '#fff';
            detailDate.textContent = run.date;
            
            detailSeed.textContent = run.seed;
            detailSeedBox.style.display = 'flex';
            
            detailContent.style.display = 'block';
            
            // Clear previous hover event listeners
            detailResult.style.cursor = 'default';
            detailResult.onmouseenter = null;
            detailResult.onmousemove = null;
            detailResult.onmouseleave = null;
            
            if (run.win) {
                detailResult.textContent = '\u{1F3C6} WIN';
                detailResult.className = 'run-meta-value text-win';
            } else if (run.abandoned) {
                detailResult.textContent = '\u{1F3F3}\u{FE0F} Abandoned';
                detailResult.className = 'run-meta-value text-abandoned';
            } else {
                detailResult.textContent = `\u{1F480} Loss (${run.killedBy})`;
                detailResult.className = 'run-meta-value text-loss';
                
                // Bind hover listener for loss cause
                const mobId = run.killedByEncounter || run.killedBy;
                detailResult.style.cursor = 'help';
                detailResult.onmouseenter = (e) => showTooltip(e, mobId);
                detailResult.onmousemove = moveTooltip;
                detailResult.onmouseleave = hideTooltip;
            }
            
            detailFloors.textContent = run.floors;
            detailDuration.textContent = formatDuration(run.runTime);
            
            // Multiplayer player selector tabs
            const tabsContainer = document.getElementById('detail-player-tabs');
            if (run.isMultiplayer && run.players && run.players.length > 0) {
                if (tabsContainer) {
                    tabsContainer.style.display = 'flex';
                    tabsContainer.innerHTML = '';
                    
                    if (activeDetailPlayerIndex >= run.players.length) {
                        activeDetailPlayerIndex = 0;
                    }
                    
                    run.players.forEach((player, idx) => {
                        const btn = document.createElement('button');
                        btn.className = 'player-selector-btn';
                        if (idx === activeDetailPlayerIndex) {
                            btn.classList.add('active');
                        }
                        const pColor = charColors[player.character] || '#fff';
                        btn.innerHTML = `<span style="display:inline-block; width:8px; height:8px; border-radius:50%; background:${pColor}; margin-right:6px;"></span>${player.character}`;
                        
                        btn.addEventListener('click', () => {
                            activeDetailPlayerIndex = idx;
                            document.querySelectorAll('#detail-player-tabs .player-selector-btn').forEach((b, i) => {
                                if (i === idx) b.classList.add('active');
                                else b.classList.remove('active');
                            });
                            renderSelectedPlayerDetails(run, idx);
                            if (activeDetailSubTab === 'map') {
                                renderRunMap();
                            }
                        });
                        tabsContainer.appendChild(btn);
                    });
                }
                
                renderSelectedPlayerDetails(run, activeDetailPlayerIndex);
            } else {
                if (tabsContainer) {
                    tabsContainer.style.display = 'none';
                }
                renderInventory(run.deck, run.relics);
            }
            
            // Refresh detail subtab view
            if (activeDetailSubTab === 'map') {
                renderRunMap();
            } else {
                switchDetailSubTab('equipment');
            }
        }
        
        function switchDetailSubTab(tab) {
            activeDetailSubTab = tab;
            const eqEl = document.getElementById('detail-tab-equipment');
            const mapEl = document.getElementById('detail-tab-map');
            const btnEq = document.getElementById('detail-btn-equipment');
            const btnMap = document.getElementById('detail-btn-map');
            
            if (tab === 'equipment') {
                if (eqEl) eqEl.style.display = 'block';
                if (mapEl) mapEl.style.display = 'none';
                if (btnEq) btnEq.className = 'detail-tab-btn active';
                if (btnMap) btnMap.className = 'detail-tab-btn';
            } else {
                if (eqEl) eqEl.style.display = 'none';
                if (mapEl) mapEl.style.display = 'block';
                if (btnEq) btnEq.className = 'detail-tab-btn';
                if (btnMap) btnMap.className = 'detail-tab-btn active';
                renderRunMap();
            }
        }
        
        function renderRunMap() {
            const mapContainer = document.getElementById('detail-tab-map');
            if (!mapContainer) return;
            mapContainer.innerHTML = '';
            
            const run = allRuns.find(r => r.id === selectedRunId);
            if (!run) return;
            
            const history = run.mapPointHistory;
            if (!history || history.length === 0) {
                mapContainer.innerHTML = '<div class="text-muted" style="font-size:12px; padding: 16px 0; text-align:center;">No map history available for this run.</div>';
                return;
            }
            
            history.forEach((act, actIdx) => {
                if (!act || act.length === 0) return;
                
                const actDiv = document.createElement('div');
                actDiv.className = 'act-container';
                actDiv.style.marginBottom = '20px';
                
                const actTitle = document.createElement('div');
                actTitle.className = 'act-title';
                actTitle.style.fontSize = '12px';
                actTitle.style.fontWeight = '700';
                actTitle.style.color = 'var(--accent-primary)';
                actTitle.style.textTransform = 'uppercase';
                actTitle.style.letterSpacing = '0.05em';
                actTitle.style.marginBottom = '12px';
                actTitle.style.paddingLeft = '8px';
                actTitle.style.borderLeft = '2px solid var(--accent-primary)';
                actTitle.textContent = `Act ${actIdx + 1}`;
                actDiv.appendChild(actTitle);
                
                const timeline = document.createElement('div');
                timeline.className = 'map-timeline';
                timeline.style.position = 'relative';
                timeline.style.paddingLeft = '20px';
                timeline.style.borderLeft = '1px solid rgba(255, 255, 255, 0.08)';
                timeline.style.marginLeft = '12px';
                
                let floorCount = 1;
                for (let prevIdx = 0; prevIdx < actIdx; prevIdx++) {
                    if (history[prevIdx]) floorCount += history[prevIdx].length;
                }
                
                act.forEach((node, nodeIdx) => {
                    const currentFloor = floorCount + nodeIdx;
                    const nodeDiv = document.createElement('div');
                    nodeDiv.className = 'timeline-node';
                    nodeDiv.style.position = 'relative';
                    nodeDiv.style.marginBottom = '16px';
                    
                    const type = node.map_point_type || 'unknown';
                    const style = nodeStyles[type] || nodeStyles['unknown'];
                    
                    const marker = document.createElement('div');
                    marker.className = 'timeline-marker';
                    marker.style.position = 'absolute';
                    marker.style.left = '-27.5px';
                    marker.style.top = '2px';
                    marker.style.width = '14px';
                    marker.style.height = '14px';
                    marker.style.borderRadius = '50%';
                    marker.style.background = style.color;
                    marker.style.boxShadow = `0 0 8px ${style.color}66`;
                    marker.style.border = '2px solid var(--bg-color)';
                    nodeDiv.appendChild(marker);
                    
                    const content = document.createElement('div');
                    content.className = 'timeline-node-content';
                    content.style.background = 'rgba(255, 255, 255, 0.02)';
                    content.style.border = '1px solid rgba(255, 255, 255, 0.04)';
                    content.style.borderRadius = '8px';
                    content.style.padding = '8px 12px';
                    content.style.transition = 'all 0.2s';
                    
                    const header = document.createElement('div');
                    header.style.display = 'flex';
                    header.style.justifyContent = 'space-between';
                    header.style.alignItems = 'center';
                    header.style.marginBottom = '4px';
                    
                    const titleText = document.createElement('span');
                    titleText.style.fontWeight = '600';
                    titleText.style.fontSize = '12.5px';
                    titleText.style.color = '#f1f5f9';
                    
                    let label = style.label;
                    let desc = '';
                    
                    const room = node.rooms && node.rooms[0];
                    if (room) {
                        if (room.model_id) {
                            label = formatModelName(room.model_id);
                        }
                        if (room.turns_taken > 0) {
                            desc = `${room.turns_taken} turns`;
                        }
                    }
                    
                    titleText.innerHTML = `<span style="margin-right:6px;">${style.icon}</span>${label}`;
                    
                    const floorText = document.createElement('span');
                    floorText.style.fontSize = '10px';
                    floorText.style.color = 'var(--text-muted)';
                    floorText.style.fontFamily = 'monospace';
                    floorText.textContent = `Floor ${currentFloor}`;
                    
                    header.appendChild(titleText);
                    header.appendChild(floorText);
                    content.appendChild(header);
                    
                    const details = document.createElement('div');
                    details.style.fontSize = '11px';
                    details.style.color = 'var(--text-muted)';
                    details.style.lineHeight = '1.4';
                    
                    let stats = node.player_stats && node.player_stats[0];
                    if (run.isMultiplayer && node.player_stats && node.player_stats.length > activeDetailPlayerIndex) {
                        stats = node.player_stats[activeDetailPlayerIndex];
                    }
                    
                    const detailParts = [];
                    
                    if (stats) {
                        detailParts.push(`HP: ${stats.current_hp} / ${stats.max_hp}`);
                        
                        if (stats.damage_taken > 0) {
                            detailParts.push(`<span style="color:#ef4444; font-weight:600;">-${stats.damage_taken} HP</span>`);
                        }
                        if (stats.hp_healed > 0) {
                            detailParts.push(`<span style="color:#10b981; font-weight:600;">+${stats.hp_healed} HP</span>`);
                        }
                        
                        if (stats.rest_site_choices && stats.rest_site_choices.length > 0) {
                            const choice = stats.rest_site_choices[0];
                            if (choice === 'HEAL') {
                                detailParts.push(`<span style="color:#f59e0b; font-weight:600;">Rested</span>`);
                            } else if (choice === 'UPGRADE') {
                                detailParts.push(`<span style="color:#a78bfa; font-weight:600;">Forged</span>`);
                            } else {
                                detailParts.push(`<span style="color:#a78bfa; font-weight:600;">${choice}</span>`);
                            }
                        }
                        
                        if (stats.card_choices && stats.card_choices.length > 0) {
                            const picked = stats.card_choices.find(c => c.was_picked);
                            if (picked && picked.card && picked.card.id) {
                                detailParts.push(`Picked: <span style="color:#e2e8f0; font-weight:500;">${formatModelName(picked.card.id)}</span>`);
                            }
                        }
                        
                        if (stats.relic_choices && stats.relic_choices.length > 0) {
                            const picked = stats.relic_choices.find(c => c.was_picked);
                            if (picked && picked.choice) {
                                detailParts.push(`Relic: <span style="color:#eab308; font-weight:500;">${formatModelName(picked.choice)}</span>`);
                            }
                        }
                        
                        if (stats.ancient_choice && stats.ancient_choice.length > 0) {
                            const picked = stats.ancient_choice.find(c => c.was_chosen);
                            if (picked && picked.TextKey) {
                                detailParts.push(`Chose Relic: <span style="color:#eab308; font-weight:500;">${formatModelName(picked.TextKey)}</span>`);
                            }
                        }
                    }
                    
                    if (desc) {
                        detailParts.unshift(desc);
                    }
                    
                    details.innerHTML = detailParts.join(' &bull; ');
                    content.appendChild(details);
                    
                    nodeDiv.appendChild(content);
                    timeline.appendChild(nodeDiv);
                });
                
                actDiv.appendChild(timeline);
                mapContainer.appendChild(actDiv);
            });
        }
        
        function formatModelName(id) {
            if (!id) return '';
            let s = id.replace(/^(CARD|RELIC|ENCOUNTER|EVENT|MONSTER|TREASURE)\./, '');
            s = s.replace(/_/g, ' ').toLowerCase();
            return s.replace(/\b\w/g, c => c.toUpperCase());
        }

        // Copy Seed
        function copySeed() {
            const seedText = detailSeed.textContent;
            navigator.clipboard.writeText(seedText).then(() => {
                alert(`Seed copied to clipboard: ${seedText}`);
            }).catch(err => {
                console.error('Failed to copy seed: ', err);
            });
        }

        // Table Header Sort Indicator Helper
        function updateTableHeaders(headerRowId, activeCol, activeDir) {
            const row = document.getElementById(headerRowId);
            if (!row) return;
            const ths = row.querySelectorAll('th');
            ths.forEach(th => {
                const key = th.getAttribute('data-sort');
                if (!key) return;
                
                // Strip existing arrow indicators if any
                let baseText = th.textContent.replace(/ [\u25B2\u25BC]/g, '');
                
                if (key === activeCol) {
                    th.textContent = baseText + (activeDir === 'asc' ? ' \u25B2' : ' \u25BC');
                    th.classList.add('sorted');
                } else {
                    th.textContent = baseText;
                    th.classList.remove('sorted');
                }
            });
        }

        // Custom Sort Handlers
        function sortRuns(col) {
            if (runsSortCol === col) {
                runsSortDir = runsSortDir === 'asc' ? 'desc' : 'asc';
            } else {
                runsSortCol = col;
                if (['character', 'killedBy'].includes(col)) {
                    runsSortDir = 'asc';
                } else {
                    runsSortDir = 'desc';
                }
            }
            renderTable();
            updateTableHeaders('runs-header-row-tr', runsSortCol, runsSortDir);
        }

        function sortMulti(col) {
            if (multiSortCol === col) {
                multiSortDir = multiSortDir === 'asc' ? 'desc' : 'asc';
            } else {
                multiSortCol = col;
                if (['character', 'killedBy'].includes(col)) {
                    multiSortDir = 'asc';
                } else {
                    multiSortDir = 'desc';
                }
            }
            renderMultiplayerTable();
            updateTableHeaders('multi-header-row-tr', multiSortCol, multiSortDir);
        }

        function sortCards(col) {
            if (cardSortCol === col) {
                cardSortDir = cardSortDir === 'asc' ? 'desc' : 'asc';
            } else {
                cardSortCol = col;
                if (col === 'name') {
                    cardSortDir = 'asc';
                } else {
                    cardSortDir = 'desc';
                }
            }
            
            // Sync dropdown
            const sortInputEl = document.getElementById('card-stats-sort');
            if (sortInputEl) {
                if (cardSortCol === 'timesPicked' && cardSortDir === 'desc') {
                    sortInputEl.value = 'frequency';
                } else if (cardSortCol === 'winRate' && cardSortDir === 'desc') {
                    sortInputEl.value = 'winrate';
                } else if (cardSortCol === 'name' && cardSortDir === 'asc') {
                    sortInputEl.value = 'name';
                } else {
                    let customOpt = sortInputEl.querySelector('option[value="custom"]');
                    if (!customOpt) {
                        customOpt = document.createElement('option');
                        customOpt.value = 'custom';
                        customOpt.textContent = 'Custom Sort';
                        customOpt.style.display = 'none';
                        sortInputEl.appendChild(customOpt);
                    }
                    sortInputEl.value = 'custom';
                }
            }
            renderCardStats();
            updateTableHeaders('card-header-row-tr', cardSortCol, cardSortDir);
        }

        function sortRelics(col) {
            if (relicSortCol === col) {
                relicSortDir = relicSortDir === 'asc' ? 'desc' : 'asc';
            } else {
                relicSortCol = col;
                if (col === 'name') {
                    relicSortDir = 'asc';
                } else {
                    relicSortDir = 'desc';
                }
            }
            
            // Sync dropdown
            const sortInputEl = document.getElementById('relic-stats-sort');
            if (sortInputEl) {
                if (relicSortCol === 'timesPicked' && relicSortDir === 'desc') {
                    sortInputEl.value = 'frequency';
                } else if (relicSortCol === 'winRate' && relicSortDir === 'desc') {
                    sortInputEl.value = 'winrate';
                } else if (relicSortCol === 'name' && relicSortDir === 'asc') {
                    sortInputEl.value = 'name';
                } else {
                    let customOpt = sortInputEl.querySelector('option[value="custom"]');
                    if (!customOpt) {
                        customOpt = document.createElement('option');
                        customOpt.value = 'custom';
                        customOpt.textContent = 'Custom Sort';
                        customOpt.style.display = 'none';
                        sortInputEl.appendChild(customOpt);
                    }
                    sortInputEl.value = 'custom';
                }
            }
            renderRelicStats();
            updateTableHeaders('relic-header-row-tr', relicSortCol, relicSortDir);
        }

        function sortEnemies(col) {
            if (enemiesSortCol === col) {
                enemiesSortDir = enemiesSortDir === 'asc' ? 'desc' : 'asc';
            } else {
                enemiesSortCol = col;
                if (col === 'name' || col === 'acts') {
                    enemiesSortDir = 'asc';
                } else {
                    enemiesSortDir = 'desc';
                }
            }
            renderEnemies();
        }

        // Tab Switching Logic
        function switchTab(tab) {
            document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
            const btnEl = document.getElementById(`tab-${tab}`);
            if (btnEl) btnEl.classList.add('active');
            
            const mainGrid = document.getElementById('main-grid');
            
            const tabViews = ['view-runs', 'view-multiplayer', 'view-compendium', 'view-card-stats', 'view-relic-stats'];
            tabViews.forEach(viewId => {
                const el = document.getElementById(viewId);
                if (el) el.style.display = 'none';
            });
            
            if (tab === 'runs') {
                if (mainGrid) mainGrid.style.display = 'grid';
                document.getElementById('view-runs').style.display = 'block';
                
                if (selectedRunId) {
                    selectRun(selectedRunId);
                } else if (allRuns.length > 0) {
                    selectRun(allRuns[allRuns.length - 1].id);
                }
            } else if (tab === 'multiplayer') {
                if (mainGrid) mainGrid.style.display = 'grid';
                document.getElementById('view-multiplayer').style.display = 'block';
                
                renderMultiplayerTable();
                
                const currentSelectedRun = allRuns.find(r => r.id === selectedRunId);
                const multiRuns = allRuns.filter(r => r.isMultiplayer);
                if (multiRuns.length > 0) {
                    if (!currentSelectedRun || !currentSelectedRun.isMultiplayer) {
                        selectRun(multiRuns[multiRuns.length - 1].id);
                    } else {
                        selectRun(selectedRunId);
                    }
                }
            } else if (tab === 'compendium') {
                if (mainGrid) mainGrid.style.display = 'none';
                document.getElementById('view-compendium').style.display = 'block';
                switchSubTab(activeCompSubTab);
            } else if (tab === 'card-stats') {
                if (mainGrid) mainGrid.style.display = 'none';
                document.getElementById('view-card-stats').style.display = 'block';
                renderCardStats();
            } else if (tab === 'relic-stats') {
                if (mainGrid) mainGrid.style.display = 'none';
                document.getElementById('view-relic-stats').style.display = 'block';
                renderRelicStats();
            }
        }

        // Floating Tooltip Logic
        function showTooltip(e, id) {
            const tooltip = document.getElementById('db-tooltip');
            let html = '';
            
            let monsterId = null;
            // Resolve legacy clean names to raw database IDs
            if (!id.startsWith('CARD.') && !id.startsWith('RELIC.')) {
                monsterId = getMonsterIdFromEncounter(id);
                if (!monsterId) {
                    let resolved = findIdByName(id, 'relic');
                    if (resolved) {
                        id = resolved;
                    } else {
                        resolved = findIdByName(id, 'card');
                        if (resolved) {
                            id = resolved;
                        }
                    }
                }
            }
            
            if (id.startsWith('CARD.')) {
                const card = sts2Database && sts2Database.cards && sts2Database.cards[id];
                if (card) {
                    const imgUrl = `https://cdn.spire-codex.com/cards-full/stable/${card.img.toLowerCase()}`;
                    const textFallback = `
                        <div class="tooltip-content-text">
                            <div class="tooltip-header-row">
                                <span class="tooltip-title">${card.name}</span>
                                <span class="tooltip-cost">${card.cost !== "" ? card.cost + " Energy" : "No Cost"}</span>
                            </div>
                            <div class="tooltip-sub-row">
                                <span class="tooltip-type">${card.type}</span>
                                <span class="tooltip-rarity rarity-${card.rarity.toLowerCase()}">${card.rarity}</span>
                            </div>
                            <div class="tooltip-desc">${formatDescription(card.desc)}</div>
                        </div>
                    `;
                    
                    // We render both the image and the fallback. If image fails to load (offline), it defaults to display fallback.
                    html = `
                        <div class="card-tooltip-wrapper">
                            <img class="tooltip-card-img" src="${imgUrl}" alt="${card.name}" onerror="this.style.display='none'; this.nextElementSibling.style.display='block';">
                            <div class="tooltip-fallback" style="display: none;">
                                ${textFallback}
                            </div>
                        </div>
                    `;
                } else {
                    html = `
                        <div class="tooltip-content-text">
                            <div class="tooltip-title">${cleanCardName(id)}</div>
                            <div class="tooltip-desc">No database details available for this card.</div>
                        </div>
                    `;
                }
            } else if (id.startsWith('RELIC.')) {
                const relic = sts2Database && sts2Database.relics && sts2Database.relics[id];
                if (relic) {
                    const imgUrl = `https://spire-codex.com/static/images/relics/${relic.img.toLowerCase()}`;
                    html = `
                        <div class="relic-tooltip-content">
                            <div class="relic-tooltip-header">
                                <img class="tooltip-relic-img" src="${imgUrl}" alt="${relic.name}" onerror="this.style.display='none';">
                                <div class="relic-tooltip-title-area">
                                    <div class="tooltip-title">${relic.name}</div>
                                    <div class="tooltip-rarity rarity-${relic.rarity.replace(' Relic', '').toLowerCase()}">${relic.rarity}</div>
                                </div>
                            </div>
                            <div class="tooltip-desc">${formatDescription(relic.desc)}</div>
                        </div>
                    `;
                } else {
                    html = `
                        <div class="relic-tooltip-content">
                            <div class="tooltip-title">${cleanRelicName(id)}</div>
                            <div class="tooltip-desc">No database details available for this relic.</div>
                        </div>
                    `;
                }
            } else {
                // Render monster tooltip
                if (!monsterId) {
                    monsterId = getMonsterIdFromEncounter(id);
                }
                const monster = sts2Database && sts2Database.monsters && sts2Database.monsters[monsterId];
                if (monster) {
                    const imgUrl = `https://spire-codex.com/static/images/monsters/${monster.img.toLowerCase()}`;
                    const hpText = monster.minHp === monster.maxHp ? `HP: ${monster.minHp}` : `HP: ${monster.minHp}-${monster.maxHp}`;
                    
                    let movesHtml = '';
                    if (monster.moves && monster.moves.length > 0) {
                        monster.moves.forEach(move => {
                            let dmgStr = '';
                            if (move.damage && move.damage !== "") {
                                let hitStr = (move.damage.hit_count && move.damage.hit_count > 1) ? `x${move.damage.hit_count}` : '';
                                let normalDmg = move.damage.normal;
                                let ascDmg = move.damage.ascension;
                                if (ascDmg && ascDmg !== normalDmg) {
                                    dmgStr = `<span class="monster-move-dmg">&#9876; ${normalDmg}${hitStr} (${ascDmg}${hitStr} Asc)</span>`;
                                } else {
                                    dmgStr = `<span class="monster-move-dmg">&#9876; ${normalDmg}${hitStr}</span>`;
                                }
                            }
                            
                            let intentClass = 'intent-unknown';
                            let intentLower = move.intent ? move.intent.toLowerCase() : '';
                            if (intentLower.includes('attack') && intentLower.includes('defend')) intentClass = 'intent-unknown';
                            else if (intentLower.includes('attack')) intentClass = 'intent-attack';
                            else if (intentLower.includes('defend') || intentLower.includes('block')) intentClass = 'intent-defend';
                            else if (intentLower.includes('buff') || intentLower.includes('strength')) intentClass = 'intent-buff';
                            else if (intentLower.includes('debuff') || intentLower.includes('weak') || intentLower.includes('frail')) intentClass = 'intent-debuff';
                            else if (intentLower.includes('status') || intentLower.includes('curse')) intentClass = 'intent-status';
                            
                            movesHtml += `
                                <div class="monster-move-row">
                                    <div class="monster-move-header">
                                        <span class="monster-move-name">${move.name}</span>
                                        <div style="display:flex; gap:6px; align-items:center;">
                                            ${dmgStr}
                                            <span class="monster-move-intent ${intentClass}">${move.intent || 'Unknown'}</span>
                                        </div>
                                    </div>
                                    ${move.desc ? `<div class="monster-move-desc">${formatDescription(move.desc)}</div>` : ''}
                                </div>
                            `;
                        });
                    } else {
                        movesHtml = '<div class="no-data" style="font-size:11px;">No recorded moves.</div>';
                    }
                    
                    html = `
                        <div class="monster-tooltip-content">
                            <div class="monster-tooltip-header">
                                <img class="tooltip-monster-img" src="${imgUrl}" alt="${monster.name}" onerror="this.style.display='none';">
                                <div class="monster-title-area">
                                    <div class="tooltip-title">${monster.name}</div>
                                    <div class="monster-type-badge type-${monster.type.toLowerCase()}">${monster.type}</div>
                                    <div class="monster-hp">${hpText}</div>
                                </div>
                            </div>
                            ${monster.pattern ? `
                                <div class="monster-pattern">
                                    <div class="monster-pattern-title">Attack Pattern</div>
                                    <div>${monster.pattern}</div>
                                </div>
                            ` : ''}
                            <div class="monster-moves-title">Moveset</div>
                            <div class="monster-moves-list">
                                ${movesHtml}
                            </div>
                        </div>
                    `;
                } else {
                    let cleanName = id.replace(/^ENCOUNTER\./, "").replace(/^MONSTER\./, "").replace(/_/g, " ");
                    cleanName = cleanName.toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
                    html = `
                        <div class="tooltip-content-text" style="min-width:200px;">
                            <div class="tooltip-title">${cleanName}</div>
                            <div class="tooltip-desc">No database details available for this monster.</div>
                        </div>
                    `;
                }
            }
            
            tooltip.innerHTML = html;
            tooltip.style.display = 'block';
            moveTooltip(e);
        }

        // Overview KPI Cards Tooltip Logic
        function showKpiTooltip(e, type) {
            const tooltip = document.getElementById('db-tooltip');
            let html = '';
            
            const total = allRuns.length;
            if (total === 0) return;
            
            const wins = allRuns.filter(r => r.win).length;
            const losses = allRuns.filter(r => !r.win && !r.abandoned).length;
            const abandoned = allRuns.filter(r => r.abandoned).length;
            
            const chars = ['Ironclad', 'Silent', 'Regent', 'Defect', 'Necrobinder'];
            
            if (type === 'runs') {
                let charBreakdown = '';
                chars.forEach(c => {
                    const count = allRuns.filter(r => r.character === c).length;
                    const pct = total > 0 ? ((count / total) * 100).toFixed(1) : 0;
                    charBreakdown += `
                        <div style="display: flex; justify-content: space-between; font-size: 12px; margin-top: 4px;">
                            <span style="color: ${charColors[c] || '#fff'}; font-weight: 600;">${c}</span>
                            <span>${count} runs (${pct}%)</span>
                        </div>
                    `;
                });
                
                html = `
                    <div style="min-width: 200px;">
                        <div class="tooltip-title" style="border-bottom: 1px solid rgba(255,255,255,0.08); padding-bottom: 6px; margin-bottom: 8px;">Run Results</div>
                        <div style="display: flex; justify-content: space-between; font-size: 12px; margin-bottom: 4px;">
                            <span class="text-win">Wins</span>
                            <span>${wins} (${((wins / total) * 100).toFixed(1)}%)</span>
                        </div>
                        <div style="display: flex; justify-content: space-between; font-size: 12px; margin-bottom: 4px;">
                            <span class="text-loss">Losses</span>
                            <span>${losses} (${((losses / total) * 100).toFixed(1)}%)</span>
                        </div>
                        <div style="display: flex; justify-content: space-between; font-size: 12px; margin-bottom: 8px;">
                            <span class="text-abandoned">Abandoned</span>
                            <span>${abandoned} (${((abandoned / total) * 100).toFixed(1)}%)</span>
                        </div>
                        <div class="tooltip-title" style="border-top: 1px solid rgba(255,255,255,0.08); padding-top: 6px; border-bottom: 1px solid rgba(255,255,255,0.08); padding-bottom: 6px; margin-bottom: 8px; font-size: 13.5px;">By Character</div>
                        ${charBreakdown}
                    </div>
                `;
            } else if (type === 'winrate') {
                let winRateBreakdown = '';
                chars.forEach(c => {
                    const charRuns = allRuns.filter(r => r.character === c);
                    const count = charRuns.length;
                    const charWins = charRuns.filter(r => r.win).length;
                    const rate = count > 0 ? ((charWins / count) * 100).toFixed(1) : '0.0';
                    winRateBreakdown += `
                        <div style="display: flex; justify-content: space-between; font-size: 12px; margin-top: 4px;">
                            <span style="color: ${charColors[c] || '#fff'}; font-weight: 600;">${c}</span>
                            <span>${rate}% (${charWins}/${count})</span>
                        </div>
                    `;
                });
                
                html = `
                    <div style="min-width: 200px;">
                        <div class="tooltip-title" style="border-bottom: 1px solid rgba(255,255,255,0.08); padding-bottom: 6px; margin-bottom: 8px;">Win Rates by Class</div>
                        ${winRateBreakdown}
                    </div>
                `;
            } else if (type === 'playtime') {
                let playtimeBreakdown = '';
                chars.forEach(c => {
                    const charRuns = allRuns.filter(r => r.character === c);
                    const count = charRuns.length;
                    const totalSecs = charRuns.reduce((acc, r) => acc + r.runTime, 0);
                    const avgSecs = count > 0 ? Math.floor(totalSecs / count) : 0;
                    playtimeBreakdown += `
                        <div style="display: flex; justify-content: space-between; font-size: 12px; margin-top: 4px;">
                            <span style="color: ${charColors[c] || '#fff'}; font-weight: 600;">${c}</span>
                            <span>${formatDuration(totalSecs)} (avg: ${formatDuration(avgSecs)})</span>
                        </div>
                    `;
                });
                
                html = `
                    <div style="min-width: 220px;">
                        <div class="tooltip-title" style="border-bottom: 1px solid rgba(255,255,255,0.08); padding-bottom: 6px; margin-bottom: 8px;">Playtime per Class</div>
                        ${playtimeBreakdown}
                    </div>
                `;
            } else if (type === 'maxasc') {
                let ascBreakdown = '';
                chars.forEach(c => {
                    const charRuns = allRuns.filter(r => r.character === c);
                    const maxAsc = charRuns.reduce((max, r) => r.ascension > max ? r.ascension : max, 0);
                    ascBreakdown += `
                        <div style="display: flex; justify-content: space-between; font-size: 12px; margin-top: 4px;">
                            <span style="color: ${charColors[c] || '#fff'}; font-weight: 600;">${c}</span>
                            <span>Ascension A${maxAsc}</span>
                        </div>
                    `;
                });
                
                html = `
                    <div style="min-width: 200px;">
                        <div class="tooltip-title" style="border-bottom: 1px solid rgba(255,255,255,0.08); padding-bottom: 6px; margin-bottom: 8px;">Max Ascension by Class</div>
                        ${ascBreakdown}
                    </div>
                `;
            } else {
                return;
            }
            
            tooltip.innerHTML = html;
            tooltip.style.display = 'block';
            moveTooltip(e);
        }

        function moveTooltip(e) {
            const tooltip = document.getElementById('db-tooltip');
            if (tooltip.style.display === 'block') {
                // Calculate position offsets to keep tooltip on screen
                let x = e.pageX + 15;
                let y = e.pageY + 15;
                
                const tooltipWidth = tooltip.offsetWidth || 280;
                const tooltipHeight = tooltip.offsetHeight || 380;
                const pageWidth = window.innerWidth;
                const pageHeight = window.innerHeight;
                const scrollX = window.scrollX;
                const scrollY = window.scrollY;
                
                if (x + tooltipWidth > pageWidth + scrollX - 10) {
                    x = e.pageX - tooltipWidth - 15;
                }
                if (y + tooltipHeight > pageHeight + scrollY - 10) {
                    y = e.pageY - tooltipHeight - 15;
                }
                if (y < scrollY + 10) {
                    y = scrollY + 10;
                }
                
                tooltip.style.left = x + 'px';
                tooltip.style.top = y + 'px';
            }
        }

        function hideTooltip() {
            document.getElementById('db-tooltip').style.display = 'none';
        }

        // Switch Compendium Sub-Tabs
        function switchSubTab(subTab) {
            activeCompSubTab = subTab;
            
            // Toggle active class on sub-tab buttons
            document.querySelectorAll('.sub-tab-btn').forEach(btn => {
                btn.classList.remove('active');
            });
            const activeBtn = document.getElementById(`sub-tab-${subTab}`);
            if (activeBtn) activeBtn.classList.add('active');
            
            // Show / Hide Sub-Views
            const subViews = ['cards', 'relics', 'potions', 'campfire', 'mobs', 'events', 'keywords'];
            subViews.forEach(viewName => {
                const viewEl = document.getElementById(`sub-view-${viewName}`);
                if (viewEl) {
                    viewEl.style.display = (viewName === subTab) ? 'block' : 'none';
                }
            });
            
            // Trigger correct render routine
            if (subTab === 'cards') {
                renderCompendiumCards();
            } else if (subTab === 'relics') {
                renderCompendiumRelics();
            } else if (subTab === 'potions') {
                renderCompendiumPotions();
            } else if (subTab === 'campfire') {
                renderCompendiumCampfire();
            } else if (subTab === 'mobs') {
                renderCompendiumMobs();
            } else if (subTab === 'events') {
                renderCompendiumEvents();
            } else if (subTab === 'keywords') {
                renderCompendiumKeywords();
            }
        }

        // Render Cards Sub-View
        function renderCompendiumCards() {
            const searchVal = compCardsSearch ? compCardsSearch.value.toLowerCase() : '';
            const sortByVal = compCardsSortBy ? compCardsSortBy.value : 'name';
            
            if (!compCardsGrid) return;
            compCardsGrid.innerHTML = '';
            
            if (!sts2Database || !sts2Database.cards) {
                compCardsGrid.innerHTML = '<div class="no-data" style="grid-column: 1 / -1;">No cards found in database.</div>';
                return;
            }
            
            let items = Object.entries(sts2Database.cards).map(([id, card]) => ({ id, ...card }));
            
            // Filter by character class color
            if (activeCardsChar !== 'all') {
                if (activeCardsChar === 'shared') {
                    const knownClasses = ['ironclad', 'silent', 'defect', 'regent', 'necrobinder'];
                    items = items.filter(c => !c.color || !knownClasses.includes(c.color.toLowerCase()));
                } else {
                    items = items.filter(c => c.color && c.color.toLowerCase() === activeCardsChar);
                }
            }
            
            // Filter by search query
            if (searchVal) {
                items = items.filter(c => {
                    const matchName = c.name && c.name.toLowerCase().includes(searchVal);
                    const matchDesc = c.desc && c.desc.toLowerCase().includes(searchVal);
                    const matchType = c.type && c.type.toLowerCase().includes(searchVal);
                    return matchName || matchDesc || matchType;
                });
            }
            
            if (items.length === 0) {
                compCardsGrid.innerHTML = '<div class="no-data" style="grid-column: 1 / -1;">No cards match active filters.</div>';
                return;
            }
            
            const RARITY_ORDER = {
                'basic': 1,
                'starter': 1,
                'common': 2,
                'uncommon': 3,
                'rare': 4,
                'shop': 5,
                'ancient': 6,
                'event': 7,
                'special': 8,
                'curse': 9,
                'status': 10,
                'token': 11,
                'quest': 12,
                'none': 99,
                'unknown': 99
            };
            
            items.sort((a, b) => {
                if (sortByVal === 'rarity') {
                    const rarityA = RARITY_ORDER[(a.rarity || '').toLowerCase()] || 99;
                    const rarityB = RARITY_ORDER[(b.rarity || '').toLowerCase()] || 99;
                    if (rarityA !== rarityB) {
                        return rarityA - rarityB;
                    }
                }
                return a.name.localeCompare(b.name);
            });
            
            items.forEach(item => {
                const el = document.createElement('div');
                el.dataset.id = item.id;
                const rarityClass = 'rarity-' + (item.rarity || 'common').toLowerCase();
                el.className = 'compendium-card ' + rarityClass;
                
                const cleanColor = item.color ? item.color.charAt(0).toUpperCase() + item.color.slice(1).toLowerCase() : 'Neutral';
                el.innerHTML = `
                    <div class="comp-card-header">
                        <span class="comp-card-name">${item.name}</span>
                        <span class="comp-card-cost">${item.cost !== "" ? item.cost : "No Cost"}</span>
                    </div>
                    <div class="comp-card-meta">
                        <span>${item.type}</span>
                        <span class="rarity-${item.rarity.toLowerCase()}">${item.rarity}</span>
                    </div>
                    <div class="comp-card-desc">${formatDescription(item.desc)}</div>
                    <div style="font-size: 9px; color: var(--text-muted); text-align: right; margin-top: auto; padding-top: 6px;">${cleanColor}</div>
                `;
                
                // Tooltips
                el.addEventListener('mouseenter', (e) => showTooltip(e, item.id));
                el.addEventListener('mousemove', moveTooltip);
                el.addEventListener('mouseleave', hideTooltip);
                
                compCardsGrid.appendChild(el);
            });
        }

        // Render Relics Sub-View
        function renderCompendiumRelics() {
            const searchVal = compRelicsSearch ? compRelicsSearch.value.toLowerCase() : '';
            const sortByVal = compRelicsSortBy ? compRelicsSortBy.value : 'name';
            
            if (!compRelicsGrid) return;
            compRelicsGrid.innerHTML = '';
            
            if (!sts2Database || !sts2Database.relics) {
                compRelicsGrid.innerHTML = '<div class="no-data" style="grid-column: 1 / -1;">No relics found in database.</div>';
                return;
            }
            
            let items = Object.entries(sts2Database.relics).map(([id, relic]) => ({ id, ...relic }));
            
            // Relic search filter
            if (searchVal) {
                items = items.filter(r => {
                    const matchName = r.name && r.name.toLowerCase().includes(searchVal);
                    const matchDesc = r.desc && r.desc.toLowerCase().includes(searchVal);
                    return matchName || matchDesc;
                });
            }
            
            if (items.length === 0) {
                compRelicsGrid.innerHTML = '<div class="no-data" style="grid-column: 1 / -1;">No relics match active filters.</div>';
                return;
            }
            
            const RARITY_ORDER = {
                'starter': 1,
                'common': 2,
                'uncommon': 3,
                'rare': 4,
                'boss': 5,
                'shop': 6,
                'special': 7,
                'event': 8,
                'none': 99,
                'unknown': 99
            };
            
            items.sort((a, b) => {
                if (sortByVal === 'rarity') {
                    const rarityA = RARITY_ORDER[(a.rarity || '').replace(' Relic', '').toLowerCase()] || 99;
                    const rarityB = RARITY_ORDER[(b.rarity || '').replace(' Relic', '').toLowerCase()] || 99;
                    if (rarityA !== rarityB) {
                        return rarityA - rarityB;
                    }
                }
                return a.name.localeCompare(b.name);
            });
            
            items.forEach(item => {
                const el = document.createElement('div');
                el.dataset.id = item.id;
                const relRarity = (item.rarity || '').replace(/ Relic/i, '').toLowerCase();
                const rarityClass = 'rarity-' + (relRarity || 'common');
                el.className = 'compendium-card ' + rarityClass;
                
                const imgUrl = `https://spire-codex.com/static/images/relics/${item.img.toLowerCase()}`;
                el.innerHTML = `
                    <div class="comp-relic-title-row">
                        <img class="comp-relic-img-preview" src="${imgUrl}" alt="${item.name}" onerror="this.style.display='none';">
                        <span class="comp-card-name">${item.name}</span>
                    </div>
                    <div class="comp-card-meta">
                        <span>Relic</span>
                        <span class="rarity-${(item.rarity || '').replace(' Relic', '').toLowerCase()}">${item.rarity}</span>
                    </div>
                    <div class="comp-card-desc">${formatDescription(item.desc)}</div>
                `;
                
                // Tooltips
                el.addEventListener('mouseenter', (e) => showTooltip(e, item.id));
                el.addEventListener('mousemove', moveTooltip);
                el.addEventListener('mouseleave', hideTooltip);
                
                compRelicsGrid.appendChild(el);
            });
        }

        // Render Potions Sub-View
        function renderCompendiumPotions() {
            const searchVal = compPotionsSearch ? compPotionsSearch.value.toLowerCase() : '';
            const rarityVal = compPotionsRarity ? compPotionsRarity.value : 'all';
            
            if (!compPotionsGrid) return;
            compPotionsGrid.innerHTML = '';
            
            if (!sts2Database || !sts2Database.potions) {
                compPotionsGrid.innerHTML = '<div class="no-data" style="grid-column: 1 / -1;">No potions found in database.</div>';
                return;
            }
            
            let items = Object.entries(sts2Database.potions).map(([id, p]) => ({ id, ...p }));
            
            // Filter by character pool
            if (activePotionsPool !== 'all') {
                if (activePotionsPool === 'shared') {
                    const knownPools = ['ironclad', 'silent', 'defect', 'regent', 'necrobinder'];
                    items = items.filter(p => !p.pool || !knownPools.includes(p.pool.toLowerCase()));
                } else {
                    items = items.filter(p => p.pool && p.pool.toLowerCase() === activePotionsPool);
                }
            }
            
            // Filter by rarity
            if (rarityVal !== 'all') {
                items = items.filter(p => p.rarity && p.rarity.toLowerCase() === rarityVal.toLowerCase());
            }
            
            // Filter by search query
            if (searchVal) {
                items = items.filter(p => {
                    const matchName = p.name && p.name.toLowerCase().includes(searchVal);
                    const matchDesc = p.desc && p.desc.toLowerCase().includes(searchVal);
                    return matchName || matchDesc;
                });
            }
            
            if (items.length === 0) {
                compPotionsGrid.innerHTML = '<div class="no-data" style="grid-column: 1 / -1;">No potions match active filters.</div>';
                return;
            }
            
            items.sort((a, b) => a.name.localeCompare(b.name));
            
            items.forEach(item => {
                const el = document.createElement('div');
                const rarityClass = 'rarity-' + (item.rarity || 'common').toLowerCase();
                el.className = 'compendium-card ' + rarityClass;
                
                const cleanPool = item.pool ? item.pool.charAt(0).toUpperCase() + item.pool.slice(1).toLowerCase() : 'Shared';
                const imgUrl = `https://spire-codex.com/static/images/potions/${item.img.toLowerCase()}`;
                
                el.innerHTML = `
                    <div class="comp-relic-title-row" style="display: flex; align-items: center; gap: 8px;">
                        <img class="comp-relic-img-preview" src="${imgUrl}" alt="${item.name}" style="width: 24px; height: 24px;" onerror="this.src=''; this.style.display='none'; this.nextElementSibling.style.display='inline';">
                        <span class="fallback-potion-icon" style="display: none; font-size: 20px;">&#129514;</span>
                        <span class="comp-card-name" style="font-size: 15px;">${item.name}</span>
                    </div>
                    <div class="comp-card-meta" style="margin-top: 4px;">
                        <span>Potion</span>
                        <span class="rarity-${item.rarity.toLowerCase()}">${item.rarity}</span>
                    </div>
                    <div class="comp-card-desc" style="margin-top: 8px;">${formatDescription(item.desc)}</div>
                    <div style="font-size: 9px; color: var(--text-muted); text-align: right; margin-top: auto; padding-top: 6px;">${cleanPool}</div>
                `;
                
                compPotionsGrid.appendChild(el);
            });
        }

        // Static Campfire Abilities
        const staticCampfireAbilities = [
            {
                name: "Rest",
                effect: "Recover 30% of your Max HP.",
                requirement: "None (Default)",
                type: "Default",
                colorClass: "rarity-common"
            },
            {
                name: "Forge",
                effect: "Permanently upgrade a card in your deck.",
                requirement: "None (Default)",
                type: "Default",
                colorClass: "rarity-common"
            },
            {
                name: "Dig",
                effect: "Find a random Relic.",
                requirement: "Requires the Shovel relic.",
                type: "Relic-Unlocked",
                colorClass: "rarity-uncommon"
            },
            {
                name: "Lift",
                effect: "Gain 1 permanent Strength for the rest of the run.",
                requirement: "Requires the Girya relic.",
                type: "Relic-Unlocked",
                colorClass: "rarity-uncommon"
            },
            {
                name: "Cook",
                effect: "Cook food to gain max HP and heal.",
                requirement: "Requires the Meat Cleaver relic.",
                type: "Relic-Unlocked",
                colorClass: "rarity-uncommon"
            },
            {
                name: "Clone",
                effect: "Duplicate a card in your deck.",
                requirement: "Requires the Pael's Growth relic.",
                type: "Relic-Unlocked",
                colorClass: "rarity-rare"
            },
            {
                name: "Hatch",
                effect: "Hatch a bird companion to aid you in combat.",
                requirement: "Requires the Byrdonis Egg (from Event).",
                type: "Event-Unlocked",
                colorClass: "rarity-special"
            },
            {
                name: "Kindle",
                effect: "Gain special combat buffs or stats.",
                requirement: "Requires the Pumpkin Candle relic.",
                type: "Relic-Unlocked",
                colorClass: "rarity-uncommon"
            },
            {
                name: "Mend",
                effect: "Heal an ally's HP (multiplayer).",
                requirement: "Co-op / Multiplayer Mode only.",
                type: "Co-op Exclusive",
                colorClass: "rarity-boss"
            }
        ];

        // Render Campfire Sub-View
        function renderCampfire() {
            renderCompendiumCampfire();
        }

        function renderCompendiumCampfire() {
            const searchVal = compCampfireSearch ? compCampfireSearch.value.toLowerCase() : '';
            
            if (!compCampfireGrid) return;
            compCampfireGrid.innerHTML = '';
            
            let filtered = staticCampfireAbilities;
            if (searchVal) {
                filtered = staticCampfireAbilities.filter(a => {
                    return a.name.toLowerCase().includes(searchVal) || 
                           a.effect.toLowerCase().includes(searchVal) || 
                           a.requirement.toLowerCase().includes(searchVal) ||
                           a.type.toLowerCase().includes(searchVal);
                });
            }
            
            if (filtered.length === 0) {
                compCampfireGrid.innerHTML = '<div class="no-data" style="grid-column: 1 / -1;">No campfire abilities match search.</div>';
                return;
            }
            
            filtered.forEach(item => {
                const el = document.createElement('div');
                el.className = 'compendium-card ' + item.colorClass;
                
                el.innerHTML = `
                    <div class="comp-card-header">
                        <span class="comp-card-name" style="font-size: 16px;">${item.name}</span>
                        <span style="font-size: 11px; padding: 2px 6px; border-radius: 4px; background: rgba(255,255,255,0.05); color: var(--text-muted);">${item.type}</span>
                    </div>
                    <div class="comp-card-desc" style="margin-top: 10px;">${item.effect}</div>
                    <div style="font-size: 11px; color: var(--accent-primary); margin-top: auto; padding-top: 8px; border-top: 1px solid rgba(255,255,255,0.03);">
                        <strong>Requirement:</strong> ${item.requirement}
                    </div>
                `;
                compCampfireGrid.appendChild(el);
            });
        }

        // Render Mobs Sub-View (formerly Enemies)
        function renderEnemies() {
            renderCompendiumMobs();
        }

        function renderCompendiumMobs() {
            const searchVal = compMobsSearch ? compMobsSearch.value.toLowerCase() : '';
            
            if (!compMobsTableBody) return;
            compMobsTableBody.innerHTML = '';
            
            let monsters = [];
            if (sts2Database && sts2Database.monsters) {
                Object.entries(sts2Database.monsters).forEach(([id, monster]) => {
                    monsters.push({ id, ...monster });
                });
            }
            
            // Filter monsters
            let filteredMonsters = monsters.filter(item => {
                // Act filter
                if (activeMobsAct !== 'all') {
                    const actsList = item.acts || [];
                    if (activeMobsAct === 'other') {
                        const isStandardAct = actsList.some(a => a.includes('Act 1') || a.includes('Act 2') || a.includes('Act 3') || a.includes('Underdocks'));
                        if (isStandardAct && actsList.length > 0) return false;
                    } else {
                        const hasAct = actsList.some(a => a.toLowerCase().includes(activeMobsAct.toLowerCase()));
                        if (!hasAct) return false;
                    }
                }
                
                // Type filter
                if (activeMobsType !== 'all') {
                    if ((item.type || '').toLowerCase() !== activeMobsType.toLowerCase()) return false;
                }
                
                // Search query
                if (searchVal) {
                    const matchName = item.name.toLowerCase().includes(searchVal);
                    const matchPattern = item.pattern && item.pattern.toLowerCase().includes(searchVal);
                    const matchMoves = item.moves && item.moves.some(m => m.name.toLowerCase().includes(searchVal) || (m.desc && m.desc.toLowerCase().includes(searchVal)));
                    if (!matchName && !matchPattern && !matchMoves) return false;
                }
                
                return true;
            });

            // Update table headers
            updateTableHeaders('comp-mobs-header-row-tr', mobsSortCol, mobsSortDir);

            // Sort enemies
            filteredMonsters.sort((a, b) => {
                let valA = a[mobsSortCol];
                let valB = b[mobsSortCol];

                if (mobsSortCol === 'name') {
                    valA = (valA || '').toString().toLowerCase();
                    valB = (valB || '').toString().toLowerCase();
                    return mobsSortDir === 'asc' ? valA.localeCompare(valB) : valB.localeCompare(valA);
                } else if (mobsSortCol === 'type') {
                    const TYPE_ORDER = { 'normal': 0, 'elite': 1, 'boss': 2 };
                    valA = TYPE_ORDER[(a.type || '').toLowerCase()] ?? 99;
                    valB = TYPE_ORDER[(b.type || '').toLowerCase()] ?? 99;
                } else if (mobsSortCol === 'hp') {
                    valA = Number(a.minHp) || 0;
                    valB = Number(b.minHp) || 0;
                } else if (mobsSortCol === 'acts') {
                    valA = ((a.acts && a.acts[0]) || '').toString().toLowerCase();
                    valB = ((b.acts && b.acts[0]) || '').toString().toLowerCase();
                    return mobsSortDir === 'asc' ? valA.localeCompare(valB) : valB.localeCompare(valA);
                }

                if (valA < valB) return mobsSortDir === 'asc' ? -1 : 1;
                if (valA > valB) return mobsSortDir === 'asc' ? 1 : -1;
                return 0;
            });

            if (compMobsCount) {
                compMobsCount.textContent = `Showing ${filteredMonsters.length} enemies`;
            }

            if (filteredMonsters.length === 0) {
                compMobsTableBody.innerHTML = '<tr><td colspan="5" class="no-data" style="text-align:center;">No enemies match active filters.</td></tr>';
                return;
            }

            filteredMonsters.forEach(item => {
                const tr = document.createElement('tr');
                tr.className = 'comp-monster-row';
                tr.style.cursor = 'help';
                
                const imgUrl = `https://spire-codex.com/static/images/monsters/${item.img.toLowerCase()}`;
                const hpText = item.minHp === item.maxHp ? `${item.minHp}` : (item.maxHp ? `${item.minHp}-${item.maxHp}` : `${item.minHp}`);
                
                // Format acts list
                let actsHtml = '';
                if (item.acts && item.acts.length > 0) {
                    actsHtml = item.acts.map(act => `<span class="comp-act-badge">${act.split(' - ')[0]}</span>`).join('');
                } else {
                    actsHtml = '<span class="comp-act-badge" style="background: rgba(148, 163, 184, 0.1); color: #94a3b8; border-color: rgba(148, 163, 184, 0.2);">Special</span>';
                }

                // Format moves list
                let movesHtml = '<div class="comp-moves-container">';
                if (item.pattern) {
                    movesHtml += `<div style="font-style: italic; color: #cbd5e1; font-size: 11.5px; margin-bottom: 4px;">Behavior: ${item.pattern}</div>`;
                }
                if (item.moves && item.moves.length > 0) {
                    item.moves.forEach(m => {
                        let intentIcon = '\u2753';
                        let intentClass = 'comp-intent-unknown';
                        
                        const intentLower = (m.intent || '').toLowerCase();
                        if (intentLower === 'attack') {
                            intentIcon = '\u2694\uFE0F';
                            intentClass = 'comp-intent-attack';
                        } else if (intentLower === 'defend') {
                            intentIcon = '\uD83D\uDEE1\uFE0F';
                            intentClass = 'comp-intent-defend';
                        } else if (intentLower === 'buff') {
                            intentIcon = '\uD83E\uDDEA';
                            intentClass = 'comp-intent-buff';
                        } else if (intentLower === 'debuff') {
                            intentIcon = '\u2620\uFE0F';
                            intentClass = 'comp-intent-debuff';
                        }

                        const dmgText = m.damage ? ` (deals ${m.damage})` : '';
                        const descText = m.desc ? `: ${m.desc}` : '';
                        movesHtml += `
                            <div class="comp-move-item" style="margin-bottom: 2px;">
                                <span class="comp-intent-badge ${intentClass}">${intentIcon} ${m.intent || 'Unknown'}</span>
                                <span class="comp-move-name" style="margin-left: 8px;">${m.name}</span>
                                <span class="comp-move-details" style="margin-left: auto;">${dmgText}${descText}</span>
                            </div>
                        `;
                    });
                } else {
                    movesHtml += '<div style="font-size: 11.5px; color: var(--text-muted);">No recorded moves.</div>';
                }
                movesHtml += '</div>';

                tr.innerHTML = `
                    <td style="font-weight: 600;">
                        <div style="display: flex; align-items: center; gap: 12px;">
                            <img src="${imgUrl}" alt="${item.name}" style="width: 32px; height: 32px; object-fit: cover; border-radius: 4px; border: 1px solid rgba(255, 255, 255, 0.1); background: rgba(0, 0, 0, 0.2);" onerror="this.style.display='none';">
                            <span>${item.name}</span>
                        </div>
                    </td>
                    <td><span class="monster-type-badge type-${item.type.toLowerCase()}" style="margin: 0;">${item.type}</span></td>
                    <td style="text-align: center; font-weight: 700; color: #ef4444;">${hpText}</td>
                    <td>${actsHtml}</td>
                    <td>${movesHtml}</td>
                `;

                // Hover tooltips
                tr.addEventListener('mouseenter', (e) => showTooltip(e, item.id));
                tr.addEventListener('mousemove', moveTooltip);
                tr.addEventListener('mouseleave', hideTooltip);

                compMobsTableBody.appendChild(tr);
            });
        }

        // Render Events Sub-View
        function renderEvents() {
            renderCompendiumEvents();
        }

        function renderCompendiumEvents() {
            const searchVal = compEventsSearch ? compEventsSearch.value.toLowerCase() : '';
            
            if (!compEventsGrid) return;
            compEventsGrid.innerHTML = '';
            
            let events = [];
            if (sts2Database && sts2Database.events) {
                Object.entries(sts2Database.events).forEach(([name, event]) => {
                    events.push({ name, ...event });
                });
            }
            
            // Filter events
            let filteredEvents = events.filter(item => {
                // Act filter
                if (activeEventsAct !== 'all') {
                    if (activeEventsAct === 'other') {
                        const isStandardAct = item.act && (item.act.includes('Act 1') || item.act.includes('Act 2') || item.act.includes('Act 3') || item.act.includes('Underdocks'));
                        if (isStandardAct) return false;
                    } else {
                        if (!item.act || !item.act.toLowerCase().includes(activeEventsAct.toLowerCase())) return false;
                    }
                }
                
                // Search query
                if (searchVal) {
                    const matchName = item.name.toLowerCase().includes(searchVal);
                    const matchDesc = item.description && item.description.toLowerCase().includes(searchVal);
                    const matchOptions = item.options && item.options.some(o => 
                        (o.title && o.title.toLowerCase().includes(searchVal)) || 
                        (o.description && o.description.toLowerCase().includes(searchVal)) ||
                        (o.id && o.id.toLowerCase().includes(searchVal))
                    );
                    if (!matchName && !matchDesc && !matchOptions) return false;
                }
                
                return true;
            });

            // Sort
            filteredEvents.sort((a, b) => a.name.localeCompare(b.name));

            if (compEventsCount) {
                compEventsCount.textContent = `Showing ${filteredEvents.length} events`;
            }

            if (filteredEvents.length === 0) {
                compEventsGrid.innerHTML = '<div class="no-data" style="grid-column: 1 / -1;">No events match active filters.</div>';
                return;
            }

            filteredEvents.forEach(item => {
                const el = document.createElement('div');
                el.className = 'event-card';
                
                let optionsHtml = '';
                if (item.options && item.options.length > 0) {
                    optionsHtml = `
                        <div class="event-options-title">Choices & Outcomes</div>
                        <div class="event-options-list">
                    `;
                    item.options.forEach(opt => {
                        const title = opt.title || opt.id || 'Choice';
                        const desc = opt.description || '';
                        optionsHtml += `
                            <div class="event-option-row">
                                <div class="event-option-header">
                                    <span class="event-option-pill">${opt.id || 'CHOOSE'}</span>
                                    <span class="event-option-text">${title}</span>
                                </div>
                                <div class="event-option-outcome">${formatDescription(desc)}</div>
                            </div>
                        `;
                    });
                    optionsHtml += `</div>`;
                } else {
                    optionsHtml = '<div style="font-size: 11.5px; color: var(--text-muted); font-style: italic;">No interactive choices.</div>';
                }

                let actHtml = '';
                if (item.act) {
                    actHtml = `<span class="comp-act-badge" style="margin: 0; font-size: 10px; padding: 2px 8px;">${item.act.split(' - ')[0]}</span>`;
                } else {
                    actHtml = '<span class="comp-act-badge" style="margin: 0; font-size: 10px; padding: 2px 8px; background: rgba(148, 163, 184, 0.1); color: #94a3b8; border-color: rgba(148, 163, 184, 0.2);">Special</span>';
                }

                el.innerHTML = `
                    <div class="event-header">
                        <span class="event-name">${item.name}</span>
                        ${actHtml}
                    </div>
                    <div class="event-desc">${formatDescription(item.description)}</div>
                    ${optionsHtml}
                `;
                compEventsGrid.appendChild(el);
            });
        }

        // Render Keywords Sub-View
        function renderCompendiumKeywords() {
            const searchVal = compKeywordsSearch ? compKeywordsSearch.value.toLowerCase() : '';
            
            if (!compKeywordsGrid) return;
            compKeywordsGrid.innerHTML = '';
            
            if (!sts2Database || !sts2Database.keywords) {
                compKeywordsGrid.innerHTML = '<div class="no-data" style="grid-column: 1 / -1;">No keywords found in database.</div>';
                return;
            }
            
            let items = Object.entries(sts2Database.keywords).map(([id, kw]) => ({ id, ...kw }));
            
            // Search query
            if (searchVal) {
                items = items.filter(kw => {
                    const matchName = kw.name && kw.name.toLowerCase().includes(searchVal);
                    const matchDesc = kw.desc && kw.desc.toLowerCase().includes(searchVal);
                    return matchName || matchDesc;
                });
            }
            
            if (items.length === 0) {
                compKeywordsGrid.innerHTML = '<div class="no-data" style="grid-column: 1 / -1;">No keywords match search.</div>';
                return;
            }
            
            items.sort((a, b) => a.name.localeCompare(b.name));
            
            items.forEach(item => {
                const el = document.createElement('div');
                el.className = 'compendium-card rarity-common';
                
                el.innerHTML = `
                    <div class="comp-card-header">
                        <span class="comp-card-name" style="color: var(--accent-primary); font-size: 16px;">${item.name}</span>
                        <span style="font-size: 11px; padding: 2px 6px; border-radius: 4px; background: rgba(255,255,255,0.05); color: var(--text-muted);">Keyword</span>
                    </div>
                    <div class="comp-card-desc" style="margin-top: 10px; font-size: 13px; line-height: 1.5;">${formatDescription(item.desc)}</div>
                `;
                compKeywordsGrid.appendChild(el);
            });
        }

        // Render Card Statistics View
        function renderCardStats() {
            const searchInputEl = document.getElementById('card-stats-search');
            const sortInputEl = document.getElementById('card-stats-sort');
            const countEl = document.getElementById('card-stats-count');
            
            const searchVal = searchInputEl ? searchInputEl.value.toLowerCase() : '';
            const sortVal = sortInputEl ? sortInputEl.value : 'frequency';
            
            if (!sts2Database || !sts2Database.cards) return;
            
            const cardStats = {};
            
            // Initialize stats for each card in the database
            Object.keys(sts2Database.cards).forEach(cardId => {
                cardStats[cardId] = {
                    id: cardId,
                    name: sts2Database.cards[cardId].name,
                    rarity: sts2Database.cards[cardId].rarity,
                    color: sts2Database.cards[cardId].color,
                    timesPicked: 0,
                    wins: 0,
                    losses: 0,
                    totalFloors: 0,
                    totalAscension: 0
                };
            });
            
            // Accumulate stats from all runs
            allRuns.forEach(run => {
                const uniqueCardsInRun = new Set(run.deck);
                uniqueCardsInRun.forEach(cardId => {
                    let resolvedId = cardId;
                    if (!sts2Database.cards[cardId]) {
                        const resolved = findIdByName(cardId, 'card');
                        if (resolved) resolvedId = resolved;
                    }
                    
                    if (cardStats[resolvedId]) {
                        const stat = cardStats[resolvedId];
                        stat.timesPicked++;
                        if (run.win) {
                            stat.wins++;
                        } else {
                            stat.losses++;
                        }
                        stat.totalFloors += run.floors;
                        stat.totalAscension += run.ascension;
                    }
                });
            });
            
            // Convert to array
            let statsArray = Object.values(cardStats);
            
            // Filter by character class
            if (activeCardStatsChar !== 'all') {
                statsArray = statsArray.filter(stat => {
                    if (!stat.color) return activeCardStatsChar === 'shared';
                    return stat.color.toLowerCase() === activeCardStatsChar;
                });
            }
            
            // Filter by search term
            if (searchVal) {
                statsArray = statsArray.filter(stat => {
                    return stat.name.toLowerCase().includes(searchVal);
                });
            }
            
            // Calculate final metrics
            statsArray.forEach(stat => {
                stat.winRate = stat.timesPicked > 0 ? Math.round((stat.wins / stat.timesPicked) * 100) : 0;
                stat.avgFloors = stat.timesPicked > 0 ? (stat.totalFloors / stat.timesPicked).toFixed(1) : '0.0';
                stat.avgAscension = stat.timesPicked > 0 ? (stat.totalAscension / stat.timesPicked).toFixed(1) : '0.0';
            });
            
            // Only show cards that have been in at least 1 run (unless searched)
            statsArray = statsArray.filter(stat => stat.timesPicked > 0 || searchVal !== '');
            
            // Sort
            const RARITY_ORDER = {
                'starter': 0, 'basic': 0, 'common': 1, 'uncommon': 2, 'rare': 3, 'special': 4,
                'starter/basic': 0
            };
            statsArray.sort((a, b) => {
                let valA = a[cardSortCol];
                let valB = b[cardSortCol];
                
                if (cardSortCol === 'name') {
                    valA = (valA || '').toString().toLowerCase();
                    valB = (valB || '').toString().toLowerCase();
                    return cardSortDir === 'asc' ? valA.localeCompare(valB) : valB.localeCompare(valA);
                } else if (cardSortCol === 'rarity') {
                    valA = RARITY_ORDER[(a.rarity || '').toLowerCase()] ?? -1;
                    valB = RARITY_ORDER[(b.rarity || '').toLowerCase()] ?? -1;
                } else {
                    valA = Number(valA) || 0;
                    valB = Number(valB) || 0;
                }
                
                if (valA < valB) return cardSortDir === 'asc' ? -1 : 1;
                if (valA > valB) return cardSortDir === 'asc' ? 1 : -1;
                return 0;
            });
            
            // Render count
            if (countEl) {
                countEl.textContent = `Showing ${statsArray.length} cards`;
            }
            
            // Render table rows
            const tbody = document.getElementById('card-stats-table-body');
            if (!tbody) return;
            tbody.innerHTML = '';
            
            if (statsArray.length === 0) {
                tbody.innerHTML = '<tr><td colspan="7" class="no-data" style="text-align:center;">No card analytics match filters.</td></tr>';
                return;
            }
            
            statsArray.forEach(stat => {
                const tr = document.createElement('tr');
                tr.className = 'card-stats-row';
                tr.style.cursor = 'help';
                
                const cleanColor = stat.color ? stat.color.charAt(0).toUpperCase() + stat.color.slice(1).toLowerCase() : 'Neutral';
                const dotColor = charColors[cleanColor] || 'var(--text-muted)';
                
                tr.innerHTML = `
                    <td class="char-cell" style="font-weight:600;"><span class="char-indicator" style="background: ${dotColor}"></span>${stat.name}</td>
                    <td><span class="rarity-${stat.rarity.toLowerCase()}" style="font-size:12px; font-weight:600;">${stat.rarity}</span></td>
                    <td style="font-weight:700; text-align:center;">${stat.timesPicked}</td>
                    <td style="text-align:center;"><span class="text-win">${stat.wins}</span> - <span class="text-loss">${stat.losses}</span></td>
                    <td>
                        <div style="display: flex; align-items: center; gap: 8px; justify-content: flex-start;">
                            <div class="death-bar-container" style="width: 70px; height: 6px; margin: 0; background: rgba(239, 68, 68, 0.25);">
                                <div class="death-bar" style="width: ${stat.winRate}%; background: var(--accent-success); height: 6px;"></div>
                            </div>
                            <span style="font-weight:700; min-width:32px;">${stat.winRate}%</span>
                        </div>
                    </td>
                    <td style="text-align:center; font-weight:600;">${stat.avgFloors}</td>
                    <td style="text-align:center; font-weight:600;">A${stat.avgAscension}</td>
                `;
                
                // Attach hover tooltip for the card details!
                tr.addEventListener('mouseenter', (e) => showTooltip(e, stat.id));
                tr.addEventListener('mousemove', moveTooltip);
                tr.addEventListener('mouseleave', hideTooltip);
                
                tbody.appendChild(tr);
            });
        }

        // Render Relic Statistics View
        function renderRelicStats() {
            const searchInputEl = document.getElementById('relic-stats-search');
            const sortInputEl = document.getElementById('relic-stats-sort');
            const countEl = document.getElementById('relic-stats-count');
            
            const searchVal = searchInputEl ? searchInputEl.value.toLowerCase() : '';
            const sortVal = sortInputEl ? sortInputEl.value : 'frequency';
            
            if (!sts2Database || !sts2Database.relics) return;
            
            const relicStats = {};
            
            // Initialize stats for each relic in the database
            Object.keys(sts2Database.relics).forEach(relicId => {
                relicStats[relicId] = {
                    id: relicId,
                    name: sts2Database.relics[relicId].name,
                    rarity: sts2Database.relics[relicId].rarity,
                    timesPicked: 0,
                    wins: 0,
                    losses: 0,
                    totalFloors: 0,
                    totalAscension: 0
                };
            });
            
            // Accumulate stats from all runs, checking which inventories are relevant for the selected character class
            allRuns.forEach(run => {
                let relevantInventories = [];
                if (run.isMultiplayer && run.players && run.players.length > 0) {
                    run.players.forEach(p => {
                        if (activeRelicStatsChar === 'all' || (p.character && p.character.toLowerCase() === activeRelicStatsChar)) {
                            relevantInventories.push(p.relics);
                        }
                    });
                } else {
                    if (activeRelicStatsChar === 'all' || (run.character && run.character.toLowerCase() === activeRelicStatsChar)) {
                        relevantInventories.push(run.relics);
                    }
                }

                relevantInventories.forEach(relicsList => {
                    if (!relicsList) return;
                    const uniqueRelics = new Set(relicsList);
                    uniqueRelics.forEach(relicId => {
                        let resolvedId = relicId;
                        if (!sts2Database.relics[relicId]) {
                            const resolved = findIdByName(relicId, 'relic');
                            if (resolved) resolvedId = resolved;
                        }
                        
                        if (relicStats[resolvedId]) {
                            const stat = relicStats[resolvedId];
                            stat.timesPicked++;
                            if (run.win) {
                                stat.wins++;
                            } else {
                                stat.losses++;
                            }
                            stat.totalFloors += run.floors;
                            stat.totalAscension += run.ascension;
                        }
                    });
                });
            });
            
            // Convert to array
            let statsArray = Object.values(relicStats);
            
            // Filter by search term
            if (searchVal) {
                statsArray = statsArray.filter(stat => {
                    return stat.name.toLowerCase().includes(searchVal);
                });
            }
            
            // Calculate final metrics
            statsArray.forEach(stat => {
                stat.winRate = stat.timesPicked > 0 ? Math.round((stat.wins / stat.timesPicked) * 100) : 0;
                stat.avgFloors = stat.timesPicked > 0 ? (stat.totalFloors / stat.timesPicked).toFixed(1) : '0.0';
                stat.avgAscension = stat.timesPicked > 0 ? (stat.totalAscension / stat.timesPicked).toFixed(1) : '0.0';
            });
            
            // Only show relics that have been in at least 1 run (unless searched)
            statsArray = statsArray.filter(stat => stat.timesPicked > 0 || searchVal !== '');
            
            // Sort
            const RELIC_RARITY_ORDER = {
                'starter': 0, 'common': 1, 'uncommon': 2, 'rare': 3, 'boss': 4, 'shop': 5, 'special': 6
            };
            statsArray.sort((a, b) => {
                let valA = a[relicSortCol];
                let valB = b[relicSortCol];
                
                if (relicSortCol === 'name') {
                    valA = (valA || '').toString().toLowerCase();
                    valB = (valB || '').toString().toLowerCase();
                    return relicSortDir === 'asc' ? valA.localeCompare(valB) : valB.localeCompare(valA);
                } else if (relicSortCol === 'rarity') {
                    valA = RELIC_RARITY_ORDER[(a.rarity || '').toLowerCase()] ?? -1;
                    valB = RELIC_RARITY_ORDER[(b.rarity || '').toLowerCase()] ?? -1;
                } else {
                    valA = Number(valA) || 0;
                    valB = Number(valB) || 0;
                }
                
                if (valA < valB) return relicSortDir === 'asc' ? -1 : 1;
                if (valA > valB) return relicSortDir === 'asc' ? 1 : -1;
                return 0;
            });
            
            // Render count
            if (countEl) {
                countEl.textContent = `Showing ${statsArray.length} relics`;
            }
            
            // Render table rows
            const tbody = document.getElementById('relic-stats-table-body');
            if (!tbody) return;
            tbody.innerHTML = '';
            
            if (statsArray.length === 0) {
                tbody.innerHTML = '<tr><td colspan="7" class="no-data" style="text-align:center;">No relic analytics match filters.</td></tr>';
                return;
            }
            
            statsArray.forEach(stat => {
                const tr = document.createElement('tr');
                tr.className = 'relic-stats-row';
                tr.style.cursor = 'help';
                
                // Color dots represent the rarity of the relic!
                const cleanRarity = stat.rarity.replace(' Relic', '');
                let rarityColor = 'var(--text-muted)';
                if (cleanRarity === 'Starter') rarityColor = '#94a3b8';
                else if (cleanRarity === 'Common') rarityColor = '#cbd5e1';
                else if (cleanRarity === 'Uncommon') rarityColor = '#3b82f6';
                else if (cleanRarity === 'Rare') rarityColor = '#f59e0b';
                else if (cleanRarity === 'Boss') rarityColor = '#8b5cf6';
                else if (cleanRarity === 'Shop') rarityColor = '#14b8a6';
                else if (cleanRarity === 'Special') rarityColor = '#ef4444';
                
                tr.innerHTML = `
                    <td class="char-cell" style="font-weight:600;"><span class="char-indicator" style="background: ${rarityColor}"></span>${stat.name}</td>
                    <td><span class="rarity-${cleanRarity.toLowerCase().replace(' ', '-')}" style="font-size:12px; font-weight:600;">${stat.rarity}</span></td>
                    <td style="font-weight:700; text-align:center;">${stat.timesPicked}</td>
                    <td style="text-align:center;"><span class="text-win">${stat.wins}</span> - <span class="text-loss">${stat.losses}</span></td>
                    <td>
                        <div style="display: flex; align-items: center; gap: 8px; justify-content: flex-start;">
                            <div class="death-bar-container" style="width: 70px; height: 6px; margin: 0; background: rgba(239, 68, 68, 0.25);">
                                <div class="death-bar" style="width: ${stat.winRate}%; background: var(--accent-success); height: 6px;"></div>
                            </div>
                            <span style="font-weight:700; min-width:32px;">${stat.winRate}%</span>
                        </div>
                    </td>
                    <td style="text-align:center; font-weight:600;">${stat.avgFloors}</td>
                    <td style="text-align:center; font-weight:600;">A${stat.avgAscension}</td>
                `;
                
                // Attach hover tooltip for the relic details!
                tr.addEventListener('mouseenter', (e) => showTooltip(e, stat.id));
                tr.addEventListener('mousemove', moveTooltip);
                tr.addEventListener('mouseleave', hideTooltip);
                
                tbody.appendChild(tr);
            });
        }

        // Charts config
        function setupCharts() {
            Chart.defaults.color = '#94a3b8';
            Chart.defaults.font.family = "'Plus Jakarta Sans', sans-serif";
            Chart.defaults.borderColor = 'rgba(255, 255, 255, 0.05)';
            
            const ctxChar = document.getElementById('chart-character').getContext('2d');
            charChart = new Chart(ctxChar, {
                type: 'bar',
                data: getCharacterChartData(),
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: { display: false },
                        tooltip: {
                            callbacks: {
                                label: function(context) {
                                    if (context.datasetIndex === 0) return `Runs: ${context.parsed.y}`;
                                    return `Win Rate: ${context.parsed.y}%`;
                                }
                            }
                        }
                    },
                    scales: {
                        y: {
                            beginAtZero: true,
                            title: { display: true, text: 'Runs' }
                        },
                        y1: {
                            beginAtZero: true,
                            position: 'right',
                            grid: { drawOnChartArea: false },
                            title: { display: true, text: 'Win Rate (%)' },
                            max: 100
                        }
                    }
                }
            });

            const ctxShare = document.getElementById('chart-share').getContext('2d');
            shareChart = new Chart(ctxShare, {
                type: 'doughnut',
                data: getShareChartData(),
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            position: 'right',
                            labels: { boxWidth: 12, padding: 10, font: { size: 11 } }
                        }
                    },
                    cutout: '65%'
                }
            });
        }

        function getCharacterChartData() {
            const characters = ['Ironclad', 'Silent', 'Regent', 'Defect', 'Necrobinder'];
            const runCounts = [];
            const winRates = [];
            
            characters.forEach(char => {
                const charRuns = filteredRuns.filter(r => r.character && r.character.toLowerCase() === char.toLowerCase());
                runCounts.push(charRuns.length);
                
                const wins = charRuns.filter(r => r.win).length;
                const rate = charRuns.length > 0 ? Math.round((wins / charRuns.length) * 100) : 0;
                winRates.push(rate);
            });
            
            return {
                labels: characters,
                datasets: [
                    {
                        label: 'Runs',
                        data: runCounts,
                        backgroundColor: characters.map(c => charColors[c] + 'cc'),
                        borderColor: characters.map(c => charColors[c]),
                        borderWidth: 1,
                        yAxisID: 'y'
                    },
                    {
                        label: 'Win Rate (%)',
                        data: winRates,
                        type: 'line',
                        borderColor: '#cbd5e1',
                        borderWidth: 2,
                        pointBackgroundColor: '#8b5cf6',
                        pointBorderColor: '#fff',
                        pointHoverRadius: 6,
                        yAxisID: 'y1'
                    }
                ]
            };
        }

        function getShareChartData() {
            const characters = ['Ironclad', 'Silent', 'Regent', 'Defect', 'Necrobinder'];
            const counts = characters.map(char => filteredRuns.filter(r => r.character && r.character.toLowerCase() === char.toLowerCase()).length);
            
            return {
                labels: characters,
                datasets: [{
                    data: counts,
                    backgroundColor: characters.map(c => charColors[c] + 'bb'),
                    borderColor: 'rgba(255, 255, 255, 0.05)',
                    borderWidth: 2
                }]
            };
        }

        function updateCharts() {
            if (charChart && shareChart) {
                charChart.data = getCharacterChartData();
                shareChart.data = getShareChartData();
                charChart.update();
                shareChart.update();
            }
        }

        // Survival By Floor Line Chart
        let survivalChart = null;
        function renderSurvivalChart(charFilter = 'all') {
            const canvas = document.getElementById('chart-survival');
            if (!canvas) return;
            const ctx = canvas.getContext('2d');
            
            const searchVal = searchInput ? searchInput.value.toLowerCase() : '';
            const resultVal = filterResult ? filterResult.value : 'all';
            const ascVal = filterAsc ? filterAsc.value : 'all';
            
            // Filter runs by overall filters except character pill
            const baseRuns = allRuns.filter(r => {
                if (r.isMultiplayer) return false;
                
                // Result Filter
                if (resultVal === 'win' && !r.win) return false;
                if (resultVal === 'loss' && (r.win || r.abandoned)) return false;
                if (resultVal === 'abandoned' && !r.abandoned) return false;
                
                // Ascension Filter
                if (ascVal !== 'all' && r.ascension.toString() !== ascVal) return false;
                
                // Search Filter
                if (searchVal) {
                    const matchSeed = r.seed.toLowerCase().includes(searchVal);
                    const matchKilled = r.killedBy.toLowerCase().includes(searchVal);
                    if (!matchSeed && !matchKilled) return false;
                }
                
                return true;
            });
            
            const characters = ['Ironclad', 'Silent', 'Defect', 'Regent', 'Necrobinder'];
            const datasets = [];
            
            characters.forEach(char => {
                const charRuns = baseRuns.filter(r => r.character && r.character.toLowerCase() === char.toLowerCase());
                if (charRuns.length === 0) return;
                
                const dataPoints = [];
                const maxFloor = 50;
                for (let f = 0; f <= maxFloor; f++) {
                    const survived = charRuns.filter(r => r.floors > f || (r.win && f <= r.floors)).length;
                    const percentage = Math.round((survived / charRuns.length) * 100);
                    dataPoints.push(percentage);
                }
                
                const isSelected = (charFilter === 'all') || (char.toLowerCase() === charFilter.toLowerCase());
                
                let borderColor = charColors[char] || '#64748b';
                let backgroundColor = (charColors[char] || '#64748b') + '15';
                let borderWidth = 2.5;
                
                if (charFilter !== 'all') {
                    if (isSelected) {
                        borderWidth = 3.5;
                        borderColor = charColors[char] || '#64748b';
                        backgroundColor = (charColors[char] || '#64748b') + '25';
                    } else {
                        borderWidth = 1.2;
                        borderColor = (charColors[char] || '#64748b') + '33'; // faded
                        backgroundColor = 'rgba(0,0,0,0)';
                    }
                }
                
                datasets.push({
                    label: char,
                    data: dataPoints,
                    borderColor: borderColor,
                    backgroundColor: backgroundColor,
                    borderWidth: borderWidth,
                    tension: 0.2,
                    pointRadius: charFilter === 'all' || isSelected ? 1.5 : 0,
                    pointHoverRadius: 4
                });
            });
            
            if (survivalChart) {
                survivalChart.destroy();
            }
            
            survivalChart = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: Array.from({ length: 51 }, (_, i) => i),
                    datasets: datasets
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            position: 'top',
                            labels: { color: '#f8fafc', font: { family: 'Outfit', size: 12, weight: '500' } }
                        },
                        tooltip: {
                            callbacks: {
                                label: function(context) {
                                    return `${context.dataset.label}: ${context.parsed.y}% Survival`;
                                }
                            }
                        }
                    },
                    scales: {
                        x: {
                            title: { display: true, text: 'Floor', color: '#94a3b8', font: { family: 'Outfit', size: 11 } },
                            grid: { color: 'rgba(255, 255, 255, 0.04)' },
                            ticks: { color: '#94a3b8', font: { family: 'Outfit', size: 10 } }
                        },
                        y: {
                            title: { display: true, text: 'Survival Rate (%)', color: '#94a3b8', font: { family: 'Outfit', size: 11 } },
                            min: 0,
                            max: 100,
                            grid: { color: 'rgba(255, 255, 255, 0.04)' },
                            ticks: { color: '#94a3b8', font: { family: 'Outfit', size: 10 }, callback: value => value + '%' }
                        }
                    }
                }
            });
        }

        // Playstyle Radar Chart
        let playstyleChart = null;
        function renderPlaystyleChart(charFilter = 'all') {
            const canvas = document.getElementById('chart-playstyle');
            if (!canvas) return;
            const ctx = canvas.getContext('2d');
            
            const runs = filteredRuns.filter(r => !r.isMultiplayer);
            
            // Header stats & subtexts updating
            const totalRunsCount = runs.length;
            const winsCount = runs.filter(r => r.win).length;
            const overallWinRate = totalRunsCount > 0 ? (winsCount / totalRunsCount * 100) : 0;
            
            // Subtitle
            let mainChar = "All Characters";
            if (charFilter !== 'all') {
                mainChar = Object.keys(charColors).find(k => k.toLowerCase() === charFilter.toLowerCase()) || charFilter;
            } else {
                // Find most played character overall
                const charCounts = {};
                runs.forEach(r => {
                    charCounts[r.character] = (charCounts[r.character] || 0) + 1;
                });
                let maxVal = 0;
                for (const [ch, count] of Object.entries(charCounts)) {
                    if (count > maxVal) {
                        maxVal = count;
                        mainChar = ch;
                    }
                }
            }
            document.getElementById('playstyle-subtitle').innerHTML = `${mainChar} Main &bull; distilled from ${totalRunsCount} runs`;
            document.getElementById('playstyle-badge-runs').textContent = `${totalRunsCount} Runs`;
            document.getElementById('playstyle-badge-wr').textContent = `${Math.round(overallWinRate)}% WR`;
            
            if (totalRunsCount === 0) {
                if (playstyleChart) playstyleChart.destroy();
                document.getElementById('trait-val-route').textContent = '0';
                document.getElementById('trait-val-cohesion').textContent = '0';
                document.getElementById('trait-val-conversion').textContent = '0';
                document.getElementById('trait-val-survival').textContent = '0';
                document.getElementById('trait-val-tempo').textContent = '0';
                document.getElementById('trait-val-resource').textContent = '0';
                
                document.getElementById('trait-desc-route').innerHTML = `0 avg floors &bull; Avg floors reached &bull; Run completion rate`;
                document.getElementById('trait-desc-cohesion').innerHTML = `0% pick rate &bull; 0 removals/run &bull; Pick selectivity &bull; Card removals &bull; Skip frequency`;
                document.getElementById('trait-desc-conversion').innerHTML = `0% win rate &bull; Overall win rate &bull; Boss kill consistency`;
                document.getElementById('trait-desc-survival').innerHTML = `0% avg HP on wins &bull; Final HP on victories &bull; Damage mitigation`;
                document.getElementById('trait-desc-tempo').innerHTML = `0% atk &bull; 0 dmg/floor &bull; Attack card ratio &bull; Damage taken per floor &bull; Aggression index`;
                document.getElementById('trait-desc-resource').innerHTML = `0% gold spent &bull; Gold spent vs earned &bull; Shop utilization`;
                return;
            }
            
            let totalRoute = 0;
            let totalCohesion = 0;
            let totalConversion = 0;
            let totalSurvival = 0;
            let totalTempo = 0;
            let totalResource = 0;
            
            let totalFloors = 0;
            let totalPicks = 0;
            let totalSkips = 0;
            let totalRemovals = 0;
            let totalBossKills = 0;
            
            let totalHpOnWins = 0;
            let winCountForHp = 0;
            let totalDmgTaken = 0;
            
            let totalAttacks = 0;
            let totalDeckCardsCount = 0;
            
            let totalTurns = 0;
            let combatCount = 0;
            
            let totalGoldSpent = 0;
            let totalGoldGained = 0;
            
            runs.forEach(r => {
                totalRoute += (r.floors / 50) * 100;
                totalFloors += r.floors;
                
                // Deck Cohesion: picks, skips, removals
                let picks = 0;
                let skips = 0;
                if (r.mapPointHistory) {
                    r.mapPointHistory.forEach(act => {
                        if (act) {
                            act.forEach(node => {
                                const stats = node.player_stats && node.player_stats[0];
                                if (stats && stats.card_choices) {
                                    stats.card_choices.forEach(cc => {
                                        if (cc.was_picked) picks++;
                                        else skips++;
                                    });
                                }
                            });
                        }
                    });
                }
                totalPicks += picks;
                totalSkips += skips;
                const totalChoices = picks + skips;
                const cohesion = totalChoices > 0 ? (skips / totalChoices) * 100 : 70;
                totalCohesion += cohesion;
                
                // Removals
                const startingDeck = r.character === 'Silent' ? 12 : (r.character === 'Ironclad' ? 11 : 10);
                // Sum cards_gained_count from history if available
                let cardsGained = 0;
                if (r.mapPointHistory) {
                    r.mapPointHistory.forEach(act => {
                        if (act) {
                            act.forEach(node => {
                                const stats = node.player_stats && node.player_stats[0];
                                if (stats) {
                                    cardsGained += stats.cards_gained_count || 0;
                                }
                            });
                        }
                    });
                }
                // Fallback to picks if cards_gained_count is not available
                if (cardsGained === 0) {
                    cardsGained = picks;
                }
                const removals = Math.max(0, (startingDeck + cardsGained) - (r.deck ? r.deck.length : startingDeck));
                totalRemovals += removals;
                
                // Boss Conversion
                const winVal = r.win ? 100 : 0;
                const bossKills = r.floors >= 34 ? 2 : (r.floors >= 17 ? 1 : 0);
                const bossScore = (bossKills / 3) * 100;
                totalConversion += (winVal * 0.3 + bossScore * 0.7);
                totalBossKills += bossKills + (r.win ? 1 : 0); // winning means killing 3rd boss
                
                // Clutch Survival
                let finalHpPercent = 50;
                let runDmgTaken = 0;
                if (r.mapPointHistory) {
                    let lastNode = null;
                    r.mapPointHistory.forEach(act => {
                        if (act && act.length > 0) {
                            lastNode = act[act.length - 1];
                            act.forEach(node => {
                                const stats = node.player_stats && node.player_stats[0];
                                if (stats) {
                                    runDmgTaken += stats.damage_taken || 0;
                                }
                            });
                        }
                    });
                    if (lastNode) {
                        const stats = lastNode.player_stats && lastNode.player_stats[0];
                        if (stats && stats.max_hp > 0) {
                            finalHpPercent = (stats.current_hp / stats.max_hp) * 100;
                        }
                    }
                }
                totalDmgTaken += runDmgTaken;
                const avgDmgPerFloor = r.floors > 0 ? runDmgTaken / r.floors : 0;
                const mitigationScore = Math.max(0, 100 - (avgDmgPerFloor * 6));
                totalSurvival += (finalHpPercent * 0.4 + mitigationScore * 0.6);
                
                if (r.win) {
                    totalHpOnWins += finalHpPercent;
                    winCountForHp++;
                }
                
                // Elite Tempo: Attack Ratio & Combat turns
                let attackCount = 0;
                let totalDeckCards = r.deck ? r.deck.length : 0;
                if (r.deck && sts2Database && sts2Database.cards) {
                    r.deck.forEach(cId => {
                        const dbCard = sts2Database.cards[cId] || sts2Database.cards[cId.toUpperCase()] || sts2Database.cards[cId.toLowerCase()];
                        if (dbCard && dbCard.type === 'Attack') {
                            attackCount++;
                        }
                    });
                }
                totalAttacks += attackCount;
                totalDeckCardsCount += totalDeckCards;
                const attackRatio = totalDeckCards > 0 ? (attackCount / totalDeckCards) * 100 : 35;
                
                let runTurns = 0;
                let runCombats = 0;
                if (r.mapPointHistory) {
                    r.mapPointHistory.forEach(act => {
                        if (act) {
                            act.forEach(node => {
                                const room = node.rooms && node.rooms[0];
                                if (room && room.turns_taken > 0) {
                                    runTurns += room.turns_taken;
                                    runCombats++;
                                }
                            });
                        }
                    });
                }
                totalTurns += runTurns;
                combatCount += runCombats;
                const avgTurns = runCombats > 0 ? runTurns / runCombats : 4;
                const speedScore = Math.max(0, 100 - (avgTurns * 12));
                totalTempo += (attackRatio * 0.5 + speedScore * 0.5);
                
                // Resource Efficiency
                let goldSpent = 0;
                let goldGained = 0;
                if (r.mapPointHistory) {
                    r.mapPointHistory.forEach(act => {
                        if (act) {
                            act.forEach(node => {
                                const stats = node.player_stats && node.player_stats[0];
                                if (stats) {
                                    goldSpent += stats.gold_spent || 0;
                                    goldGained += stats.gold_gained || 0;
                                }
                            });
                        }
                    });
                }
                totalGoldSpent += goldSpent;
                totalGoldGained += goldGained;
                const goldScore = goldGained > 0 ? (goldSpent / goldGained) * 100 : 50;
                totalResource += Math.min(100, goldScore);
            });
            
            const n = totalRunsCount;
            const routeScore = Math.round(totalRoute / n);
            const cohesionScore = Math.round(totalCohesion / n);
            const conversionScore = Math.round(totalConversion / n);
            const survivalScore = Math.round(totalSurvival / n);
            const tempoScore = Math.round(totalTempo / n);
            const resourceScore = Math.round(totalResource / n);
            
            const traitData = [routeScore, cohesionScore, conversionScore, survivalScore, tempoScore, resourceScore];
            
            // Format dynamic subtext averages
            const avgFloorsVal = totalFloors / n;
            const pickRateVal = (totalPicks + totalSkips) > 0 ? (totalPicks / (totalPicks + totalSkips) * 100) : 0;
            const avgRemovalsVal = totalRemovals / n;
            const winRateVal = overallWinRate;
            const avgHpOnWinsVal = winCountForHp > 0 ? (totalHpOnWins / winCountForHp) : (totalHpOnWins / n); // Fallback to all runs if 0 wins
            const avgDmgPerFloorVal = totalFloors > 0 ? (totalDmgTaken / totalFloors) : 0;
            const attackRatioVal = totalDeckCardsCount > 0 ? (totalAttacks / totalDeckCardsCount * 100) : 0;
            const goldSpentPctVal = totalGoldGained > 0 ? (totalGoldSpent / totalGoldGained * 100) : 0;
            
            document.getElementById('trait-desc-route').innerHTML = `${avgFloorsVal.toFixed(0)} avg floors &bull; Avg floors reached &bull; Run completion rate`;
            document.getElementById('trait-desc-cohesion').innerHTML = `${Math.round(pickRateVal)}% pick rate &bull; ${avgRemovalsVal.toFixed(1)} removals/run &bull; Pick selectivity &bull; Card removals &bull; Skip frequency`;
            document.getElementById('trait-desc-conversion').innerHTML = `${Math.round(winRateVal)}% win rate &bull; Overall win rate &bull; Boss kill consistency`;
            document.getElementById('trait-desc-survival').innerHTML = `${Math.round(avgHpOnWinsVal)}% avg HP on wins &bull; Final HP on victories &bull; Damage mitigation`;
            document.getElementById('trait-desc-tempo').innerHTML = `${Math.round(attackRatioVal)}% atk &bull; ${avgDmgPerFloorVal.toFixed(1)} dmg/floor &bull; Attack card ratio &bull; Damage taken per floor &bull; Aggression index`;
            document.getElementById('trait-desc-resource').innerHTML = `${Math.round(goldSpentPctVal)}% gold spent &bull; Gold spent vs earned &bull; Shop utilization`;
            
            if (playstyleChart) {
                playstyleChart.destroy();
            }
            
            playstyleChart = new Chart(ctx, {
                type: 'radar',
                plugins: [{
                    id: 'centerCircle',
                    afterDraw: function(chart) {
                        const ctx = chart.ctx;
                        const x = chart.scales.r.xCenter;
                        const y = chart.scales.r.yCenter;
                        
                        // Draw a dark circle
                        ctx.save();
                        ctx.beginPath();
                        ctx.arc(x, y, 22, 0, 2 * Math.PI);
                        ctx.fillStyle = '#080c14'; // body bg color
                        ctx.fill();
                        ctx.lineWidth = 2;
                        ctx.strokeStyle = 'rgba(255, 255, 255, 0.08)';
                        ctx.stroke();
                        
                        // Draw text "A0" (or max ascension) in the middle
                        ctx.fillStyle = '#f8fafc';
                        ctx.font = 'bold 12px Outfit';
                        ctx.textAlign = 'center';
                        ctx.textBaseline = 'middle';
                        
                        // Compute max ascension for current runs
                        const maxAsc = runs.reduce((max, r) => r.ascension > max ? r.ascension : max, 0);
                        ctx.fillText('A' + maxAsc, x, y);
                        ctx.restore();
                    }
                }],
                data: {
                    labels: ['Route Discipline', 'Deck Cohesion', 'Boss Conversion', 'Clutch Survival', 'Elite Tempo', 'Resource Efficiency'],
                    datasets: [{
                        label: charFilter === 'all' ? 'All Classes' : charFilter,
                        data: traitData,
                        backgroundColor: 'rgba(139, 92, 246, 0.15)',
                        borderColor: '#8b5cf6',
                        borderWidth: 2,
                        pointBackgroundColor: '#8b5cf6',
                        pointBorderColor: '#fff',
                        pointHoverBackgroundColor: '#fff',
                        pointHoverBorderColor: '#8b5cf6'
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: { display: false }
                    },
                    scales: {
                        r: {
                            angleLines: { color: 'rgba(255, 255, 255, 0.08)' },
                            grid: { color: 'rgba(255, 255, 255, 0.08)' },
                            pointLabels: { color: '#cbd5e1', font: { family: 'Outfit', size: 11.5, weight: '600' } },
                            ticks: { display: false },
                            min: 0,
                            max: 100
                        }
                    }
                }
            });
            
            document.getElementById('trait-val-route').textContent = routeScore;
            document.getElementById('trait-val-cohesion').textContent = cohesionScore;
            document.getElementById('trait-val-conversion').textContent = conversionScore;
            document.getElementById('trait-val-survival').textContent = survivalScore;
            document.getElementById('trait-val-tempo').textContent = tempoScore;
            document.getElementById('trait-val-resource').textContent = resourceScore;
        }

        window.onload = init;
    </script>
</body>
</html>
'@

# Inject database JSON into HTML template
$dbPath = Join-Path $PSScriptRoot "sts2_database.json"
$dbJson = Get-Content -Raw -Path $dbPath -Encoding utf8

$htmlContent = $htmlTemplate -replace "__RUN_DATA__", $jsonData
$htmlContent = $htmlContent -replace "__DB_DATA__", $dbJson

$outputPath = Join-Path $PSScriptRoot "sts2_dashboard.html"
$parentDir = Split-Path $outputPath
if (-not (Test-Path $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
}

[System.IO.File]::WriteAllText($outputPath, $htmlContent, [System.Text.Encoding]::UTF8)

Write-Host "Dashboard generated successfully at: $outputPath"

$scratchDir = $PSScriptRoot
$cardsFile = Join-Path $scratchDir "cards_api.json"
$relicsFile = Join-Path $scratchDir "relics_api.json"
$monstersFile = Join-Path $scratchDir "monsters_api.json"
$encountersFile = Join-Path $scratchDir "encounters_api.json"
$eventsFile = Join-Path $scratchDir "events_api.json"
$potionsFile = Join-Path $scratchDir "potions_api.json"
$keywordsFile = Join-Path $scratchDir "keywords_api.json"
$outputFile = Join-Path $scratchDir "sts2_database.json"

Write-Host "Loading raw data..."
$cardsData = Get-Content -Raw -Path $cardsFile -Encoding utf8 | ConvertFrom-Json
$relicsData = Get-Content -Raw -Path $relicsFile -Encoding utf8 | ConvertFrom-Json
$monstersData = Get-Content -Raw -Path $monstersFile -Encoding utf8 | ConvertFrom-Json
$encountersData = @()
if (Test-Path $encountersFile) {
    $encountersData = Get-Content -Raw -Path $encountersFile -Encoding utf8 | ConvertFrom-Json
}
$eventsData = @()
if (Test-Path $eventsFile) {
    $eventsData = Get-Content -Raw -Path $eventsFile -Encoding utf8 | ConvertFrom-Json
}
$potionsData = @()
if (Test-Path $potionsFile) {
    $potionsData = Get-Content -Raw -Path $potionsFile -Encoding utf8 | ConvertFrom-Json
}
$keywordsData = @()
if (Test-Path $keywordsFile) {
    $keywordsData = Get-Content -Raw -Path $keywordsFile -Encoding utf8 | ConvertFrom-Json
}

# Build monster-to-encounter map
$monsterEncounters = @{}
foreach ($enc in $encountersData) {
    if ($enc.monsters) {
        foreach ($mon in $enc.monsters) {
            if ($mon.id) {
                $monId = $mon.id.ToUpper()
                if (-not $monsterEncounters.ContainsKey($monId)) {
                    $monsterEncounters[$monId] = @()
                }
                $encIdRaw = $enc.id.ToUpper()
                $encIdPrefixed = "ENCOUNTER." + $encIdRaw
                if ($monsterEncounters[$monId] -notcontains $encIdRaw) {
                    $monsterEncounters[$monId] += $encIdRaw
                }
                if ($monsterEncounters[$monId] -notcontains $encIdPrefixed) {
                    $monsterEncounters[$monId] += $encIdPrefixed
                }
            }
        }
    }
}

$database = @{
    cards    = @{}
    relics   = @{}
    monsters = @{}
    events   = @{}
    potions  = @{}
    keywords = @{}
}

Write-Host "Processing $($cardsData.Count) cards..."
foreach ($card in $cardsData) {
    if (-not $card.id) { continue }
    
    $fullId = "CARD." + $card.id.ToUpper()
    
    # Get image filename leaf
    $imgLeaf = ""
    if ($card.image_url) {
        $imgLeaf = Split-Path $card.image_url -Leaf
    }
    
    $database.cards[$fullId] = @{
        name   = $card.name
        cost   = if ($card.cost -ne $null) { $card.cost } else { "" }
        type   = $card.type
        rarity = $card.rarity
        color  = $card.color
        desc   = $card.description
        img    = $imgLeaf
    }
}

Write-Host "Processing $($relicsData.Count) relics..."
foreach ($relic in $relicsData) {
    if (-not $relic.id) { continue }
    
    $fullId = "RELIC." + $relic.id.ToUpper()
    
    # Get image filename leaf
    $imgLeaf = ""
    if ($relic.image_url) {
        $imgLeaf = Split-Path $relic.image_url -Leaf
    }
    
    $database.relics[$fullId] = @{
        name   = $relic.name
        rarity = $relic.rarity
        desc   = $relic.description
        img    = $imgLeaf
    }
}

Write-Host "Processing $($monstersData.Count) monsters..."
foreach ($monster in $monstersData) {
    if (-not $monster.id) { continue }
    
    $fullId = $monster.id.ToUpper()
    
    # Get image filename leaf
    $imgLeaf = ""
    if ($monster.image_url) {
        $imgLeaf = Split-Path $monster.image_url -Leaf
    }
    
    # Simplify moves list
    $moves = @()
    if ($monster.moves) {
        foreach ($move in $monster.moves) {
            $damage = ""
            $intent = "Unknown"
            
            # Remove spaces, dashes and numbers from move name to compare against key values
            $cleanMoveName = ($move.name -replace '\s+', '' -replace '\d+', '' -replace '-', '').ToLower()
            
            $matchedDmg = $null
            if ($monster.damage_values) {
                # 1. Custom explicit monster mappings
                if ($monster.name -eq "Turret Operator" -and $move.name -match "Unload") {
                    $matchedDmg = $monster.damage_values.Fire
                } elseif ($monster.name -eq "Thieving Hopper" -and ($move.name -eq "Thievery" -or $move.name -eq "Nab")) {
                    $matchedDmg = $monster.damage_values.Theft
                } elseif ($monster.name -eq "Bowlbug (Silk)" -and $move.name -eq "Trash") {
                    $matchedDmg = $monster.damage_values.Thrash
                } elseif ($monster.name -eq "Slithering Strangler" -and $move.name -eq "Twack") {
                    $matchedDmg = $monster.damage_values.Thwack
                } elseif (($monster.name -eq "Leaf Slime (S)" -or $monster.name -eq "Twig Slime (S)") -and $move.name -eq "Butt") {
                    $matchedDmg = $monster.damage_values.Tackle
                } elseif ($monster.name -eq "Magi Knight" -and $move.name -eq "Ram") {
                    $matchedDmg = $monster.damage_values.Spear
                } elseif ($monster.name -eq "Torch Head Amalgam") {
                    if ($move.name -eq "Tackle 1" -or $move.name -eq "Tackle 2") {
                        $matchedDmg = $monster.damage_values.WeakTackle
                    } elseif ($move.name -eq "Tackle 3" -or $move.name -eq "Tackle 4") {
                        $matchedDmg = $monster.damage_values.Tackle
                    }
                }
                
                # 2. General fuzzy mappings
                if ($matchedDmg -eq $null) {
                    foreach ($dmgProp in $monster.damage_values.psobject.properties) {
                        $dmgKey = $dmgProp.Name
                        $cleanDmgKey = ($dmgKey -replace '\s+', '' -replace '\d+', '' -replace '-', '' -replace '!', '').ToLower()
                        $cleanDmgKey = $cleanDmgKey -replace '^the', '' -replace 'move$', ''
                        
                        $cleanMove = $cleanMoveName -replace '^the', ''
                        
                        $dmgSingular = $cleanDmgKey -replace 's$', ''
                        $moveSingular = $cleanMove -replace 's$', ''
                        
                        if ($cleanDmgKey -eq "bees" -and $cleanMove -match "be+s") {
                            $matchedDmg = $monster.damage_values.$dmgKey
                            break
                        }
                        
                        if ($dmgKey.ToLower() -eq $move.name.ToLower() -or 
                            $cleanDmgKey -eq $cleanMove -or 
                            $dmgSingular -eq $moveSingular -or
                            $cleanDmgKey -eq $moveSingular -or
                            $dmgSingular -eq $cleanMove -or
                            $move.name.ToLower().Contains($dmgKey.ToLower()) -or
                            $dmgKey.ToLower().Contains($move.name.ToLower()) -or
                            $cleanDmgKey.Contains($cleanMove) -or
                            $cleanMove.Contains($cleanDmgKey)) {
                            $matchedDmg = $monster.damage_values.$dmgKey
                            break
                        }
                    }
                }
                
                if ($matchedDmg -ne $null) {
                    if ($matchedDmg.normal -ne $null) {
                        $damage = "$($matchedDmg.normal)"
                        if ($matchedDmg.ascension -ne $null) {
                            $damage = "$($matchedDmg.normal) (A: $($matchedDmg.ascension))"
                        }
                    }
                    $intent = "Attack"
                }
            }
            
            if ($intent -eq "Unknown" -and $monster.block_values) {
                foreach ($blkProp in $monster.block_values.psobject.properties) {
                    $blkKey = $blkProp.Name
                    $cleanBlkKey = ($blkKey -replace '\s+', '' -replace '\d+', '' -replace '-', '' -replace '!', '').ToLower()
                    $cleanBlkKey = $cleanBlkKey -replace '^the', '' -replace 'move$', ''
                    
                    $cleanMove = $cleanMoveName -replace '^the', ''
                    
                    $blkSingular = $cleanBlkKey -replace 's$', ''
                    $moveSingular = $cleanMove -replace 's$', ''
                    
                    if ($blkKey.ToLower() -eq $move.name.ToLower() -or 
                        $cleanBlkKey -eq $cleanMove -or 
                        $blkSingular -eq $moveSingular -or
                        $cleanBlkKey -eq $moveSingular -or
                        $blkSingular -eq $cleanMove -or
                        $move.name.ToLower().Contains($blkKey.ToLower()) -or
                        $blkKey.ToLower().Contains($move.name.ToLower()) -or
                        $cleanBlkKey.Contains($cleanMove) -or
                        $cleanMove.Contains($cleanBlkKey)) {
                        $intent = "Defend"
                        break
                    }
                }
            }
            
            # Simple keyword match for intent fallback
            if ($intent -eq "Unknown") {
                $lowerName = $move.name.ToLower()
                if ($lowerName -match "incantation|sharpen|roar|cry|buff|charge|boot|adapt|power|growl") {
                    $intent = "Buff"
                } elseif ($lowerName -match "debuff|goop|spit|screech|slime|toxic|curse|status|pounce|constrict") {
                    $intent = "Debuff"
                } elseif ($lowerName -match "nothing|sleep") {
                    $intent = "Unknown"
                }
            }
            
            $moves += @{
                name   = $move.name
                intent = $intent
                damage = $damage
                desc   = ""
            }
        }
    }
    
    # Extract encounter IDs and Acts
    $encounters = @()
    $acts = @()
    if ($monsterEncounters.ContainsKey($fullId)) {
        $encounters = $monsterEncounters[$fullId]
        foreach ($encId in $encounters) {
            $rawId = $encId
            if ($rawId.StartsWith("ENCOUNTER.")) {
                $rawId = $rawId.Substring(10)
            }
            $matchEnc = $encountersData | Where-Object { $_.id.ToUpper() -eq $rawId.ToUpper() }
            if ($matchEnc -and $matchEnc.act) {
                if ($acts -notcontains $matchEnc.act) {
                    $acts += $matchEnc.act
                }
            }
        }
    }
    
    $database.monsters[$fullId] = @{
        name       = $monster.name
        type       = $monster.type
        minHp      = if ($monster.min_hp -ne $null) { $monster.min_hp } else { "" }
        maxHp      = if ($monster.max_hp -ne $null) { $monster.max_hp } else { "" }
        moves      = $moves
        img        = $imgLeaf
        pattern    = ""
        encounters = $encounters
        acts       = $acts
    }
}

Write-Host "Saving compiled database to $outputFile..."
# ========================================================
# MANUALLY PATCH FOR MAJOR UPDATE #2 (v0.107.1)
# ========================================================
Write-Host "Applying v0.107.1 manual database patches..."

# 1. New Relics
$database.relics["RELIC.KALEIDOSCOPE"] = @{
    name   = "Kaleidoscope"
    rarity = "Ancient"
    desc   = "Upon pickup, gain 2 card rewards with cards from other characters."
    img    = "kaleidoscope.png"
}
$database.relics["RELIC.FISHING_ROD"] = @{
    name   = "Fishing Rod"
    rarity = "Ancient"
    desc   = "Every 3 normal combats, Upgrade a random card in your deck."
    img    = "fishing_rod.png"
}
$database.relics["RELIC.SILKEN_TRESS"] = @{
    name   = "Silken Tress"
    rarity = "Ancient"
    desc   = "Enchant all cards in the first card reward with Glam. Upon pickup, lose all gold."
    img    = "silken_tress.png"
}

# 2. Relics Updates
if ($database.relics.ContainsKey("RELIC.PUMPKIN_CANDLE")) {
    $database.relics["RELIC.PUMPKIN_CANDLE"].desc = "Gain [energy:1] at the start of each turn. Extinguishes after 5 combats and can be Kindled at rest sites."
}
if ($database.relics.ContainsKey("RELIC.SCROLL_BOXES")) {
    $database.relics["RELIC.SCROLL_BOXES"].desc = "Upon pickup, choose [blue]1[/blue] of [blue]2[/blue] packs of cards to add to your [gold]Deck[/gold]."
}
if ($database.relics.ContainsKey("RELIC.BOOMING_CONCH")) {
    $database.relics["RELIC.BOOMING_CONCH"].desc = "At the start of [gold]Elite[/gold] combats, draw [blue]2[/blue] additional cards and gain [energy:1]."
}
if ($database.relics.ContainsKey("RELIC.NUTRITIOUS_SOUP")) {
    $database.relics["RELIC.NUTRITIOUS_SOUP"].desc = "Strikes cost 0, are [gold]Eternal[/gold], and deal [blue]3[/blue] additional damage."
}
if ($database.relics.ContainsKey("RELIC.INFUSED_CORE")) {
    $database.relics["RELIC.INFUSED_CORE"].desc = "At the start of each combat, [gold]Channel[/gold] [blue]3[/blue] [gold]Lightning[/gold]. [gold]Lightning[/gold] Orbs deal [blue]1[/blue] additional damage."
}

# 3. Card Updates & Rename Follow Through -> Scare
if ($database.cards.ContainsKey("CARD.FOLLOW_THROUGH")) {
    $followThrough = $database.cards["CARD.FOLLOW_THROUGH"]
    $followThrough.name = "Scare"
    $followThrough.rarity = "Uncommon"
    $followThrough.desc = "Deal 6 damage to ALL enemies.`nIf the last card you played this turn was a Skill, apply 1 [gold]Weak[/gold] to ALL enemies."
    $database.cards["CARD.SCARE"] = $followThrough
    $database.cards.Remove("CARD.FOLLOW_THROUGH")
}
if ($database.cards.ContainsKey("CARD.HYPERBEAM")) {
    $database.cards["CARD.HYPERBEAM"].desc = "Deal 28 damage to ALL enemies.`nLose 3 [gold]Focus[/gold]."
}
if ($database.cards.ContainsKey("CARD.UNRELENTING")) {
    $database.cards["CARD.UNRELENTING"].desc = "Deal 14 damage.`nThe next Attack you play costs 0 [energy:1]."
}
if ($database.cards.ContainsKey("CARD.POUNCE")) {
    $database.cards["CARD.POUNCE"].desc = "Deal 14 damage.`nThe next Skill you play costs 0 [energy:1]."
}
if ($database.cards.ContainsKey("CARD.FASTEN")) {
    $database.cards["CARD.FASTEN"].desc = "Gain an additional 4 [gold]Block[/gold] from Defend cards."
}
if ($database.cards.ContainsKey("CARD.CONFLAGRATION")) {
    $database.cards["CARD.CONFLAGRATION"].desc = "Deal 2 damage to ALL enemies 4 times."
}
if ($database.cards.ContainsKey("CARD.DRUM_OF_BATTLE")) {
    $database.cards["CARD.DRUM_OF_BATTLE"].cost = 1
    $database.cards["CARD.DRUM_OF_BATTLE"].type = "Skill"
    $database.cards["CARD.DRUM_OF_BATTLE"].rarity = "Uncommon"
    $database.cards["CARD.DRUM_OF_BATTLE"].desc = "Draw 2 cards.`nWhen [gold]Exhausted[/gold], gain 2 [energy:1]."
}
if ($database.cards.ContainsKey("CARD.PREDATOR")) {
    $database.cards["CARD.PREDATOR"].rarity = "Common"
}
if ($database.cards.ContainsKey("CARD.HOWL_FROM_BEYOND")) {
    $database.cards["CARD.HOWL_FROM_BEYOND"].desc = "Deal 16 damage to ALL enemies.`nAt the end of your turn, plays from the [gold]Exhaust Pile[/gold]."
}
if ($database.cards.ContainsKey("CARD.FURNACE")) {
    $database.cards["CARD.FURNACE"].desc = "At the start of your turn, [gold]Forge[/gold] 5."
}
if ($database.cards.ContainsKey("CARD.REFLECT")) {
    $database.cards["CARD.REFLECT"].desc = "Gain 15 [gold]Block[/gold].`nBlocked attack damage is reflected to your attacker this turn."
}
if ($database.cards.ContainsKey("CARD.BULWARK")) {
    $database.cards["CARD.BULWARK"].desc = "Gain 12 [gold]Block[/gold].`n[gold]Forge[/gold] 10."
}
if ($database.cards.ContainsKey("CARD.MINION_SACRIFICE")) {
    $database.cards["CARD.MINION_SACRIFICE"].desc = "Gain 8 [gold]Block[/gold]."
}
if ($database.cards.ContainsKey("CARD.DEBILITATE")) {
    $database.cards["CARD.DEBILITATE"].desc = "Deal 7 damage.`n[gold]Vulnerable[/gold] and [gold]Weak[/gold] are twice as effective against the enemy for the next 2 turns."
}
if ($database.cards.ContainsKey("CARD.DEATH_MARCH")) {
    $database.cards["CARD.DEATH_MARCH"].desc = "Deal 11 damage.`nDeals 4 additional damage for each card drawn during your turn."
}
if ($database.cards.ContainsKey("CARD.SIC_EM")) {
    $database.cards["CARD.SIC_EM"].desc = "[gold]Osty[/gold] deals 5 damage.`nWhenever [gold]Osty[/gold] hits this enemy this turn, [gold]Summon[/gold] 3."
}
if ($database.cards.ContainsKey("CARD.THE_SCYTHE")) {
    $database.cards["CARD.THE_SCYTHE"].desc = "Deal 13 damage.`nPermanently increase this card's damage by 4."
}
if ($database.cards.ContainsKey("CARD.UPROAR")) {
    $database.cards["CARD.UPROAR"].desc = "Deal 6 damage twice.`nPlay a random Attack from your [gold]Draw Pile[/gold]."
}
if ($database.cards.ContainsKey("CARD.FUSION")) {
    $database.cards["CARD.FUSION"].cost = 1
    $database.cards["CARD.FUSION"].desc = "[gold]Channel[/gold] 1 [gold]Plasma[/gold].`n[gold]Exhaust[/gold]."
}
if ($database.cards.ContainsKey("CARD.SHATTER")) {
    $database.cards["CARD.SHATTER"].desc = "Deal 7 damage to ALL enemies.`n[gold]Evoke[/gold] all of your Orbs twice."
}
if ($database.cards.ContainsKey("CARD.PARRY")) {
    $database.cards["CARD.PARRY"].desc = "Whenever you play [gold]Sovereign Blade[/gold], it gains 10 [gold]Block[/gold]."
}
if ($database.cards.ContainsKey("CARD.SWORD_SAGE")) {
    $database.cards["CARD.SWORD_SAGE"].desc = "Increase the cost of [gold]Sovereign Blade[/gold] by 1. [gold]Sovereign Blade[/gold] now gains [gold]Replay[/gold] 1."
}
if ($database.cards.ContainsKey("CARD.ASTRAL_PULSE")) {
    $database.cards["CARD.ASTRAL_PULSE"].desc = "Deal 6 damage 2 times to ALL enemies."
}
if ($database.cards.ContainsKey("CARD.MONARCHS_GAZE")) {
    $database.cards["CARD.MONARCHS_GAZE"].cost = 2
}

# 4. Boss Changes (Doormaker -> Aeonglass)
if ($database.monsters.ContainsKey("DOORMAKER")) {
    $database.monsters.Remove("DOORMAKER")
}
$database.monsters["AEONGLASS"] = @{
    name       = "Aeonglass"
    type       = "Boss"
    minHp      = 489
    maxHp      = ""
    img        = "aeonglass.png"
    pattern    = "Alternates between Swipe and Stomp."
    encounters = @("AEONGLASS_BOSS", "ENCOUNTER.AEONGLASS_BOSS", "DOORMAKER_BOSS", "ENCOUNTER.DOORMAKER_BOSS")
    acts       = @("Act 4 - Special")
    moves      = @(
        @{ name = "Swipe"; intent = "Attack"; damage = "15 (A: 17)"; desc = "" },
        @{ name = "Stomp"; intent = "Attack"; damage = "20 (A: 22)"; desc = "" },
        @{ name = "Wither"; intent = "Debuff"; damage = ""; desc = "Applies Wither." }
    )
}

# 5. Monster Updates
if ($database.monsters.ContainsKey("SKULKING_COLONY")) {
    $database.monsters["SKULKING_COLONY"].minHp = 75
    $database.monsters["SKULKING_COLONY"].maxHp = ""
    $database.monsters["SKULKING_COLONY"].moves = @(
        @{ name = "Inertia"; intent = "Buff"; damage = ""; desc = "" },
        @{ name = "Zoom"; intent = "Attack"; damage = "16 (A: 17)"; desc = "" }
    )
}
if ($database.monsters.ContainsKey("SCROLL_OF_BITING")) {
    $database.monsters["SCROLL_OF_BITING"].minHp = 30
    $database.monsters["SCROLL_OF_BITING"].maxHp = 37
}
if ($database.monsters.ContainsKey("OWL_MAGISTRATE")) {
    $database.monsters["OWL_MAGISTRATE"].minHp = 231
    $database.monsters["OWL_MAGISTRATE"].maxHp = ""
}
if ($database.monsters.ContainsKey("SLIMED_BERSERKER")) {
    $database.monsters["SLIMED_BERSERKER"].minHp = 261
    $database.monsters["SLIMED_BERSERKER"].maxHp = ""
}
if ($database.monsters.ContainsKey("SOUL_FYSH")) {
    foreach ($move in $database.monsters["SOUL_FYSH"].moves) {
        if ($move.name -eq "Scream") {
            $move.damage = "13 (A: 15)"
        }
    }
}
if ($database.monsters.ContainsKey("ASSASSIN_RUBY_RAIDER")) {
    foreach ($move in $database.monsters["ASSASSIN_RUBY_RAIDER"].moves) {
        if ($move.name -eq "Killshot") {
            $move.damage = "10 (A: 11)"
        }
    }
}
if ($database.monsters.ContainsKey("HAUNTED_SHIP")) {
    $database.monsters["HAUNTED_SHIP"].moves = $database.monsters["HAUNTED_SHIP"].moves | Where-Object { $_.name -ne "Ramming Speed" }
    $database.monsters["HAUNTED_SHIP"].pattern = "Alternates between Swipe and Stomp (always starting with Swipe after Haunt)."
}
$database.monsters["KAISER_CRAB"] = @{
    name       = "Kaiser Crab"
    type       = "Boss"
    minHp      = 199
    maxHp      = 189
    img        = "crusher.png"
    pattern    = "Contend with Crusher (Left Claw, 199/209 HP) and Rocket (Right Claw, 189/199 HP). Face different directions to block backstabs. The surviving claw buffs itself when the other dies."
    encounters = @("KAISER_CRAB_BOSS", "ENCOUNTER.KAISER_CRAB_BOSS")
    acts       = @("Act 2 - Hive")
    moves      = @(
        @{ name = "Crusher: Thrash"; intent = "Attack"; damage = "12 (A: 14)"; desc = "" },
        @{ name = "Crusher: Bug Sting"; intent = "Attack"; damage = "6 (A: 7)"; desc = "" },
        @{ name = "Crusher: Guarded Strike"; intent = "Attack"; damage = "12 (A: 14)"; desc = "" },
        @{ name = "Rocket: Precision Beam"; intent = "Attack"; damage = "18 (A: 20)"; desc = "" },
        @{ name = "Rocket: Laser"; intent = "Attack"; damage = "31 (A: 35)"; desc = "" }
    )
}

Write-Host "Processing $($eventsData.Count) events..."
foreach ($event in $eventsData) {
    if (-not $event.id) { continue }
    
    $fullId = "EVENT." + $event.id.ToUpper()
    
    $options = @()
    if ($event.options) {
        foreach ($opt in $event.options) {
            $options += @{
                id          = $opt.id
                title       = $opt.title
                description = if ($opt.description) { $opt.description } else { "" }
            }
        }
    }
    
    $database.events[$fullId] = @{
        name        = $event.name
        act         = if ($event.act) { $event.act } else { "Other / Special" }
        description = if ($event.description) { $event.description } else { "" }
        options     = $options
    }
}

Write-Host "Processing $($potionsData.Count) potions..."
foreach ($potion in $potionsData) {
    if (-not $potion.id) { continue }
    
    $fullId = "POTION." + $potion.id.ToUpper()
    
    # Get image filename leaf
    $imgLeaf = ""
    if ($potion.image_url) {
        $imgLeaf = Split-Path $potion.image_url -Leaf
    }
    
    $database.potions[$fullId] = @{
        name   = $potion.name
        rarity = $potion.rarity
        desc   = $potion.description
        img    = $imgLeaf
        pool   = $potion.pool
    }
}

Write-Host "Processing $($keywordsData.Count) keywords..."
foreach ($keyword in $keywordsData) {
    if (-not $keyword.id) { continue }
    
    $fullId = "KEYWORD." + $keyword.id.ToUpper()
    
    $database.keywords[$fullId] = @{
        name = $keyword.name
        desc = $keyword.description
    }
}

$jsonOut = ConvertTo-Json $database -Depth 10
[System.IO.File]::WriteAllText($outputFile, $jsonOut, [System.Text.Encoding]::UTF8)
Write-Host "Database compiled successfully! File size: $((Get-Item $outputFile).Length) bytes."

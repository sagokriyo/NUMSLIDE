<#
.SYNOPSIS
    2048 Infinity - mutation verification: proves the regression tests can fail.

.DESCRIPTION
    A test suite is only trustworthy once you've watched each test go red for
    the right reason. This script automates that: for each KNOWN MUTATION it
    (1) plants a realistic bug in product code, (2) runs the test(s) that are
    supposed to catch it, (3) asserts they went RED, (4) restores the file
    byte-for-byte, and finally (5) re-runs every involved test on clean code
    to prove the board is green again.

    "RED" means the same failure signal run_all.ps1 uses: a non-zero exit, a
    "SCRIPT ERROR" in the output, or a timeout. So it works for the assertion
    suites (which quit non-zero) AND the scene smokes (which quit 0 but log a
    SCRIPT ERROR / crash when their exercised path breaks).

    The catalog below covers EVERY test file in the suite, so a green run
    proves all 24 test files + the boot smoke are able to fail on their target
    bug. When you add a test surface, add a mutation here that proves it bites.

    Restoration is from an in-memory copy of the file (never git), so
    uncommitted work is safe. The user save is backed up/restored around the
    whole run, same as run_all.ps1.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File regression\headless\verify_tests.ps1
    powershell -File regression\headless\verify_tests.ps1 -Filter *merge*
    powershell -File regression\headless\verify_tests.ps1 -List
#>
param(
    [string]$Godot = "D:\Godot_v4.7.1-stable_win64_console.exe",
    [string]$Filter = "*",
    [int]$TimeoutSec = 240,       # per script/boot test
    [int]$SceneTimeoutSec = 90,   # per scene smoke (bounds a halted-scene hang)
    [switch]$SkipGreenCheck,
    [switch]$List
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$RunDir = Join-Path $PSScriptRoot (".results\verify-" + (Get-Date -Format "yyyyMMdd-HHmmss"))

# --- The mutation catalog ---------------------------------------------------------
# Each entry plants ONE realistic bug (Find must be an exact, UNIQUE substring of
# the file) and names the test(s) that MUST go red for it. A test is named by its
# res:// path; the mode is inferred: *.gd = --script, *.tscn = scene run,
# "<boot>" = the shipped main scene. Keep one mutation per test file so a green
# verify run proves the whole suite is able to fail.
$Mutations = @(
    @{ Name = "store_product_id_typo"; File = "core\store_products.gd"
       Simulates = "the IAP product id drifts from the Play Console id"
       Find = 'const PREMIUM_LIFETIME := "premium_lifetime"'
       Replace = 'const PREMIUM_LIFETIME := "premium_lifetime_TYPO"'
       ExpectRed = @("tests/test_store_products.gd") },
    @{ Name = "billing_purchased_inverted"; File = "core\billing_payloads.gd"
       Simulates = "a real PURCHASED receipt is read as not-owned"
       Find = 'return int(p["purchase_state"]) == PURCHASE_STATE_PURCHASED'
       Replace = 'return int(p["purchase_state"]) != PURCHASE_STATE_PURCHASED'
       ExpectRed = @("tests/test_billing_parsing.gd") },
    @{ Name = "account_signed_in_off_device"; File = "autoload\account_manager.gd"
       Simulates = "the identity facade claims configured/signed-in with no PGS plugin"
       Find = 'func is_configured() -> bool:'
       Replace = 'func is_configured() -> bool:'+"`n"+'	return true'
       ExpectRed = @("tests/test_account_facade.tscn") },
    @{ Name = "boot_intro_crash"; File = "scenes\intro\intro.gd"
       Simulates = "the shipped boot chain (intro -> splash) errors on launch"
       Find = 'SceneRouter.goto(SceneRouter.Route["SPLASH"])'
       Replace = 'SceneRouter.goto_MUTANT(SceneRouter.Route["SPLASH"])'
       ExpectRed = @("<boot>") },

    @{ Name = "economy_bounty_ignores_its_kind"; File = "core\bounties.gd"
       Simulates = "any event advances any bounty"
       Find = "`tif k.is_empty() or k != event_kind or amount <= 0:"
       Replace = "`tif k.is_empty() or amount <= 0:"
       ExpectRed = @("tests/test_bounties.gd") },

    @{ Name = "economy_bounty_threshold_becomes_a_tally"; File = "core\bounties.gd"
       Simulates = "threshold bounties tally instead"
       Find = "`t`treturn goal(id) if amount >= goal(id) else 0"
       Replace = "`t`treturn amount"
       ExpectRed = @("tests/test_bounties.gd") },

    @{ Name = "economy_daily_bounties_stop_rotating"; File = "core\bounties.gd"
       Simulates = "every day offers the same three tasks"
       Find = "`tvar start: int = seed_value % n"
       Replace = "`tvar start: int = 0 # mutation: the day no longer matters"
       ExpectRed = @("tests/test_bounties.gd") },

    @{ Name = "economy_bounty_set_can_repeat_a_task"; File = "core\bounties.gd"
       Simulates = "a day can show the same bounty twice"
       Find = "`t`tif _gcd(s, n) == 1:`n`t`t`treturn s"
       Replace = "`t`tif true:`n`t`t`treturn n"
       ExpectRed = @("tests/test_bounties.gd") },

    @{ Name = "economy_daily_cap_zeroes_instead_of_halving"; File = "core\economy_rules.gd"
       Simulates = "past the daily cap a run pays NOTHING"
       Find = "`t`ttotal = int(round(float(total) * OVER_CAP_RATE))"
       Replace = "`t`ttotal = 0 # mutation: the cap zeroes the payout"
       ExpectRed = @("tests/test_economy_rules.gd") },

    @{ Name = "economy_undo_price_stops_escalating"; File = "core\economy_rules.gd"
       Simulates = "every paid undo costs the base price"
       Find = "`tvar steps: int = mini(nth - 1, 8)   # 2^8 already clears the cap; guards overflow"
       Replace = "`tvar steps: int = 0 # mutation: the ladder is flat"
       ExpectRed = @("tests/test_economy_rules.gd") },

    @{ Name = "home_colour_table_forgets_a_mode"; File = "scenes\home\home.gd"
       Simulates = "a mode row on Home with no colour story"
       Find = '	"fog":         [Color("9A9CC8"), Color("3A3F6B")],'
       Replace = ''
       ExpectRed = @("tests/test_game_modes.gd") },

    @{ Name = "more_modes_lists_a_featured_mode_twice"; File = "scenes\mode_select\mode_select.gd"
       Simulates = "Vanish listed on Home AND on More Modes"
       Find = 'const ORDER: Array[String] = ["gravity", "fog",'
       Replace = 'const ORDER: Array[String] = ["vanish", "gravity", "fog",'
       ExpectRed = @("tests/test_game_modes.gd") },

    @{ Name = "rules_other_mark_is_itself"; File = "core\rules\rules.gd"
       Simulates = "the turn never passes: other(X) is X"
       Find = "`treturn Board.O if mark == Board.X else Board.X"
       Replace = "`treturn mark # mutation: the other side is the same side"
       ExpectRed = @("tests/test_rules.gd") },

    @{ Name = "vanish_forgets_to_shatter"; File = "core\rules\rules_vanish.gd"
       Simulates = "the fourth mark lands but the oldest never leaves the tray"
       Find = '		events.append({"type": "shattered", "cell": oldest, "id": oid, "mark": mark})'
       Replace = '		pass # mutation: no shatter event'
       ExpectRed = @("tests/test_rules.gd") },

    @{ Name = "ultimate_never_routes"; File = "core\rules\rules_meta.gd"
       Simulates = "any board is always playable in Ultimate"
       Find = "`tvar last := last_cell(board)`n`tif last < 0:`n`t`treturn -1"
       Replace = "`tvar last := last_cell(board)`n`tif last < 0 or true:`n`t`treturn -1"
       ExpectRed = @("tests/test_rules.gd") },

    @{ Name = "oracle_stops_thinking"; File = "core\ai\personas.gd"
       Simulates = "Oracle searches no deeper than Pip"
       Find = '		"depth": 64, "mistake": 0.0, "time_ms": 1200, "book": true,'
       Replace = '		"depth": 1, "mistake": 0.0, "time_ms": 1200, "book": true,'
       ExpectRed = @("tests/test_ai.gd") },

    @{ Name = "academy_loses_a_launch_mode"; File = "core\game_modes.gd"
       Simulates = "Vanish slips out of the launch tier, so the Academy teaches seven"
       Find = '		"theme_id": "", "tier": "launch",'
       Replace = '		"theme_id": "", "tier": "w2",'
       ExpectRed = @("regression/headless/suites/test_academy_catalog.gd", "tests/test_game_modes.gd") },

    @{ Name = "board_lines_never_detected"; File = "core\rules\board.gd"
       Simulates = "no line is ever found, so no round can end"
       Find = "`tif mark == EMPTY or i < 0 or i >= cells.size() or cells[i] != mark:"
       Replace = "`tif true: # mutation: every line check comes back empty"
       ExpectRed = @("tests/test_board.gd", "tests/test_rules.gd") },

    @{ Name = "series_winner_opens_the_next_round"; File = "core\rules\series.gd"
       Simulates = "the winner, not the loser, starts the next round"
       Find = "`t`tfirst_mover = Rules.other(winner)"
       Replace = "`t`tfirst_mover = winner"
       ExpectRed = @("tests/test_series.gd") },

    @{ Name = "fog_shows_everything"; File = "core\rules\rules_fog.gd"
       Simulates = "Fog hides nothing"
       Find = "`t`tif v == Board.EMPTY or v == viewer or _near_mark(board, i, viewer):"
       Replace = "`t`tif true: # mutation: every cell is visible"
       ExpectRed = @("tests/test_rules_wave.gd") },

    @{ Name = "cube_lines_leave_their_face"; File = "core\rules\rules_cube.gd"
       Simulates = "a face row runs on past the edge of its face, so a line spans two faces again and the cube is decided in ten plies"
       Find = 'out.append(_window(base + row * n + c, 1, LINE))'
       Replace = 'out.append(_window(base + row * n + c + 1, 1, LINE))'
       ExpectRed = @("tests/test_rules_cube.gd") },

    @{ Name = "cube_size_ignores_the_picker"; File = "core\rules\rules_cube.gd"
       Simulates = "every cube is a 3 x 3 x 3 whatever the player picked"
       Find = "`treturn clampi(mode.board_size, MIN_N, MAX_N)"
       Replace = "`treturn DEFAULT_N"
       ExpectRed = @("tests/test_rules_cube.gd") },

    @{ Name = "orbit_straightness_measured_through_the_solid"; File = "core\rules\orbit_solid.gd"
       Simulates = "straightness is judged on the chord between two face centres rather than in the surface, so the sphere own curvature reads as a turn and no walk is ever straight"
       Find = "`treturn (v - u * v.dot(u)).normalized()"
       Replace = "`treturn (v - u).normalized()"
       ExpectRed = @("tests/test_rules_orbit.gd") },

    @{ Name = "orbit_lines_are_not_straight"; File = "core\rules\orbit_solid.gd"
       Simulates = "any neighbour counts as the straight continuation, so a line may bend across the globe"
       Find = 'if tangent(cur, n).dot(travel) > STRAIGHT_DOT:'
       Replace = 'if tangent(cur, n).dot(travel) > -2.0:'
       ExpectRed = @("tests/test_rules_orbit.gd") },

    @{ Name = "quantum_collapse_never_owed"; File = "core\rules\rules_quantum.gd"
       Simulates = "a closed cycle never asks for a collapse"
       Find = 'return not pending_collapse(board).is_empty()'
       Replace = 'return false'
       ExpectRed = @("tests/test_rules_quantum.gd") },

    @{ Name = "mastery_crown_never_unlocks"; File = "autoload\progression.gd"
       Simulates = "ten series won on a board unlock nothing"
       Find = 'if int(rec.get("series_won", 0)) >= mode.mastery_yardstick():'
       Replace = 'if false:'
       ExpectRed = @("regression/headless/suites/test_progression.gd") },

    # --- Tic Tac Toe Limitless ---------------------------------------------------
    @{ Name = "mode_multiplier_sign_flip"; File = "core\economy_rules.gd"
       Simulates = "Ultimate pays LESS than Classic instead of more"
       Find = '"ultimate": 1.6,'
       Replace = '"ultimate": 0.6,'
       ExpectRed = @("tests/test_economy_rules.gd") },
    @{ Name = "vanish_leaks_to_premium"; File = "core\entitlements.gd"
       Simulates = "Vanish, the featured mode, drops out of the free set"
       Find = 'const FREE_MODES: Array[String] = ["vanish", "classic",'
       Replace = 'const FREE_MODES: Array[String] = ["classic",'
       ExpectRed = @("tests/test_entitlements.gd") },
    @{ Name = "boot_theme_goes_premium"; File = "core\entitlements.gd"
       Simulates = "Starforged, the boot default, leaves the free set"
       Find = '	"starforged",     # the boot default'
       Replace = '	# "starforged",     # the boot default'
       ExpectRed = @("tests/test_entitlements.gd", "tests/test_themes.gd") },
    @{ Name = "leaderboard_catalog_forgets_a_mode"; File = "core\play_games_ids.gd"
       Simulates = "a mode whose best series never ranks anywhere"
       Find = '	"vanish": "",'
       Replace = ''
       ExpectRed = @("tests/test_play_games_ids.gd") },
    @{ Name = "pgs_achievement_slot_dropped"; File = "core\play_games_ids.gd"
       Simulates = "an achievement that never mirrors to Play Games"
       Find = '	"oracle_slayer": "",'
       Replace = ''
       ExpectRed = @("tests/test_play_games_ids.gd") },
    @{ Name = "mode_crown_table_forgets_a_mode"; File = "autoload\achievements.gd"
       Simulates = "winning a Vanish series unlocks nothing"
       Find = '	"vanish": "vanish_series", "classic": "classic_series",'
       Replace = '	"classic": "classic_series",'
       ExpectRed = @("tests/test_game_modes.gd") }
)

$Mutations = @($Mutations | Where-Object { $_.Name -like $Filter })

# --- Per-test invocation (mode inferred from the res path) ------------------------
function Get-TestPlan {
    param([string]$ResPath)
    if ($ResPath -eq "<boot>") {
        return [pscustomobject]@{
            Name = "boot_smoke"; Timeout = $TimeoutSec
            Args = "--headless --path . --quit-after 2400" }
    }
    $name = [IO.Path]::GetFileNameWithoutExtension($ResPath)
    if ($ResPath.EndsWith(".tscn")) {
        # --fixed-fps makes the smokes' real-time create_timer() waits burn as
        # frames (headless computes them near-instantly) instead of wall time;
        # --quit-after backstops a scene that errors at load and would otherwise
        # idle-hang with no current scene. Clean smokes call quit() first.
        return [pscustomobject]@{
            Name = "scene_$name"; Timeout = $SceneTimeoutSec
            Args = "--headless --path . res://$ResPath --fixed-fps 60 --quit-after 3000" }
    }
    # Suites are Nodes hosted by the headless_boot SceneTree shim (mirrors
    # run_all.ps1 -- the same files also run embedded on-device).
    return [pscustomobject]@{
        Name = $name; Timeout = $TimeoutSec
        Args = "--headless --path . --script res://regression/headless/harness/headless_boot.gd -- --test=res://$ResPath" }
}

if ($List) {
    foreach ($m in $Mutations) {
        Write-Host ("  {0,-28} {1}" -f $m.Name, $m.Simulates)
        foreach ($t in $m.ExpectRed) { Write-Host ("  {0,-28}   must fail: {1}" -f "", (Get-TestPlan $t).Name) }
    }
    Write-Host "$($Mutations.Count) mutations."
    exit 0
}
if ($Mutations.Count -eq 0) { Write-Host "No mutations match filter '$Filter'."; exit 1 }
if (-not (Test-Path $Godot)) { throw "Godot binary not found: $Godot" }
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

# --- Save backup (same contract as run_all.ps1) ------------------------------------
$projectCfg = Get-Content (Join-Path $ProjectRoot "project.godot") -Raw
$projectName = "2048 Infinity"
if ($projectCfg -match 'config/name="([^"]+)"') { $projectName = $Matches[1] }
$SaveDir = Join-Path $env:APPDATA "Godot\app_userdata\$projectName"
$SaveFiles = @("tictactoe_save.json", "tictactoe_save.tmp")
$saveBackup = @{}
foreach ($f in $SaveFiles) {
    $p = Join-Path $SaveDir $f
    if (Test-Path $p) {
        $dest = Join-Path $RunDir ("save_backup_" + $f)
        Copy-Item $p $dest -Force
        $saveBackup[$f] = $dest
    } else { $saveBackup[$f] = $null }
}

function Invoke-GodotTest {
    param([string]$LogName, [string]$Arguments, [int]$Timeout)
    $outFile = Join-Path $RunDir "$LogName.out.log"
    $errFile = Join-Path $RunDir "$LogName.err.log"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Process -FilePath $Godot -ArgumentList $Arguments `
        -WorkingDirectory $ProjectRoot -PassThru -NoNewWindow `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $null = $proc.Handle   # PS 5.1: cache the handle or ExitCode reads as null
    $timedOut = -not $proc.WaitForExit($Timeout * 1000)
    if ($timedOut) { try { $proc.Kill() } catch {}; $proc.WaitForExit() }
    $sw.Stop()
    $output = ""
    if (Test-Path $outFile) { $output += (Get-Content $outFile -Raw) }
    if (Test-Path $errFile) { $output += "`n" + (Get-Content $errFile -Raw) }
    Set-Content -Path (Join-Path $RunDir "$LogName.log") -Value $output -Encoding utf8
    Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
    $scriptErr = ($output -match "SCRIPT ERROR")
    $failures = ""
    if ($output -match "(\d+) checks, (\d+) failures") { $failures = $Matches[2] }
    return [pscustomobject]@{
        ExitCode = $proc.ExitCode; TimedOut = $timedOut; ScriptError = $scriptErr
        Failures = $failures; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    }
}

# --- Warm the Godot class cache on a cold checkout ----------------------------------
# Same reason as run_all.ps1: a cold .godot cache makes vendored addon scripts log
# transient := inference errors on the first import. Left unwarmed, those SCRIPT
# ERRORs would appear in the mutation runs (a false "PROVEN") and fail the green
# check. Warm once up front so every test compiles cleanly on clean code.
if (-not (Test-Path (Join-Path $ProjectRoot ".godot"))) {
    Write-Host "Warming Godot class cache (cold checkout)..."
    $wi = Invoke-GodotTest -LogName "import_warmup" -Arguments "--headless --path . --import" -Timeout 600
    Write-Host "  done ($($wi.Seconds)s)"
    Write-Host ""
}

# --- Run the mutations --------------------------------------------------------------
Write-Host "Mutation verification  ->  $RunDir"
Write-Host "PROVEN = the test went red (non-zero exit / SCRIPT ERROR / timeout) while its target bug was planted."
Write-Host ""

$rows = @()
$problems = 0
$involved = @{}

try {
    foreach ($m in $Mutations) {
        $path = Join-Path $ProjectRoot $m.File
        $orig = [IO.File]::ReadAllText($path)
        $count = ([regex]::Matches($orig, [regex]::Escape($m.Find))).Count
        if ($count -ne 1) {
            Write-Host ("{0,-28} SETUP ERROR: anchor found {1}x in {2} (need exactly 1)" -f $m.Name, $count, $m.File) -ForegroundColor Red
            $problems++
            continue
        }
        Write-Host ("{0,-28} planting: {1}" -f $m.Name, $m.Simulates)
        [IO.File]::WriteAllText($path, $orig.Replace($m.Find, $m.Replace))
        try {
            foreach ($t in $m.ExpectRed) {
                $plan = Get-TestPlan $t
                $involved[$t] = $true
                $r = Invoke-GodotTest -LogName "$($m.Name)__$($plan.Name)" -Arguments $plan.Args -Timeout $plan.Timeout
                $caught = $r.TimedOut -or ($r.ExitCode -ne 0) -or $r.ScriptError
                if ($caught) {
                    $how = @()
                    if ($r.ExitCode -ne 0 -and -not $r.TimedOut) { $how += "exit $($r.ExitCode)" }
                    if ($r.Failures -ne "" -and $r.Failures -ne "0") { $how += "$($r.Failures) failed checks" }
                    if ($r.ScriptError) { $how += "SCRIPT ERROR" }
                    if ($r.TimedOut) { $how += "timeout" }
                    $verdict = "PROVEN (" + ($how -join ", ") + ")"
                    $color = "Green"
                } else {
                    $verdict = "MISSED (stayed green!)"
                    $color = "Red"
                    $problems++
                }
                Write-Host ("{0,-28}   {1,-26} {2,-42} {3,6}s" -f "", $plan.Name, $verdict, $r.Seconds) -ForegroundColor $color
                $rows += [pscustomobject]@{ Mutation = $m.Name; Test = $plan.Name; Caught = $caught; Seconds = $r.Seconds }
            }
        } finally {
            [IO.File]::WriteAllText($path, $orig)
            if ([IO.File]::ReadAllText($path) -ne $orig) {
                Write-Host ("{0,-28} RESTORE MISMATCH in {1} - CHECK THE FILE" -f $m.Name, $m.File) -ForegroundColor Red
                $problems++
            }
        }
    }

    # --- Green check: clean code must pass every involved test -----------------------
    if (-not $SkipGreenCheck) {
        Write-Host ""
        Write-Host "Green check (clean code must pass every involved test):"
        foreach ($t in ($involved.Keys | Sort-Object)) {
            $plan = Get-TestPlan $t
            $r = Invoke-GodotTest -LogName "green__$($plan.Name)" -Arguments $plan.Args -Timeout $plan.Timeout
            $ok = (-not $r.TimedOut) -and ($r.ExitCode -eq 0) -and (-not $r.ScriptError)
            if (-not $ok) { $problems++ }
            $verdict = "PASS"; $color = "Green"
            if (-not $ok) { $verdict = "FAIL - code or test left broken!"; $color = "Red" }
            Write-Host ("  {0,-26} {1,-34} {2,6}s" -f $plan.Name, $verdict, $r.Seconds) -ForegroundColor $color
        }
    }
} finally {
    foreach ($f in $SaveFiles) {
        $p = Join-Path $SaveDir $f
        if ($null -ne $saveBackup[$f]) { Copy-Item $saveBackup[$f] $p -Force }
        elseif (Test-Path $p) { Remove-Item $p -Force }
    }
    Write-Host ""
    Write-Host "User save restored."
}

# --- Verdict ------------------------------------------------------------------------
$rows | ConvertTo-Json | Set-Content -Path (Join-Path $RunDir "verify_summary.json") -Encoding utf8
$covered = ($rows | Select-Object -ExpandProperty Test -Unique).Count
Write-Host ""
if ($problems -eq 0) {
    Write-Host "ALL $($Mutations.Count) MUTATIONS CAUGHT - $covered test file(s) proven able to fail on their target bug." -ForegroundColor Green
} else {
    Write-Host "$problems problem(s) - a test failed to catch its bug, or cleanup failed. See logs in $RunDir" -ForegroundColor Red
}
exit $problems

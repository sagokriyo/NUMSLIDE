<#
.SYNOPSIS
    2048 Infinity - headless regression suite runner.

.DESCRIPTION
    Runs, in order:
      1. An import gate (--import): every resource and scene imports.
      1b. A PARSE gate (parse_gate.gd): every .gd in the project actually
          compiles. This is the one that means "the project compiles" --
          --import does NOT (see -SkipParse below and regression/perf/SPEC.md
          section 2, defect D1).
      2. Every script test (Node suite): tests/test_*.gd  +  regression/headless/suites/test_*.gd
      3. Every full-boot flow test:     regression/headless/flows/flow_*.gd
      4. Every scene smoke:             tests/*.tscn
      5. A real boot smoke of the shipped main scene (intro -> splash -> home).

    Each test runs in its own Godot process (crash + state isolation) with a
    wall-clock timeout. The player's save file is backed up before the run and
    restored afterwards, no matter what the tests did to it.

    Pass criteria per test: exit code 0, no "SCRIPT ERROR", and no abandoned
    coroutine ("after yield, but class instance is gone") in the output.
    Exit code of this script = number of failed tests.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File regression\headless\run_all.ps1
    powershell -File regression\headless\run_all.ps1 -Filter *game_board*
    powershell -File regression\headless\run_all.ps1 -List

.EXAMPLE
    # The parse gate on its own (2.4 s, exits 1 naming every .gd that will not compile):
    & $Godot --headless --path . --script res://regression/headless/parse_gate.gd
#>
param(
    [string]$Godot = "D:\Godot_v4.7.1-stable_win64_console.exe",
    [string]$Filter = "*",
    # Basic = the fast quick-gate: the import gate + every --script unit/service
    #         suite (tests\ and regression\headless\suites\). Deterministic, no
    #         booted game, seconds. Meant for every PR.
    # Full  = EVERYTHING: Basic plus the full-boot flows, the scene smokes and the
    #         boot smoke. The exhaustive gate (merge to main / nightly / release).
    # Default is Full so an un-tiered call keeps its historical meaning.
    #
    # The tier is inferred from the test's DIRECTORY, never a hand-kept list: a new
    # suite is Basic and a new flow is Full automatically. That is deliberate --
    # this repo has twice been bitten by a hardcoded inventory silently drifting
    # (verify_tests.ps1's mutation catalog, device_test_runner.gd's SUITE_SCRIPTS).
    [ValidateSet("Basic", "Full")][string]$Tier = "Full",
    [int]$TimeoutSec = 300,
    [switch]$SkipImport,
    # The parse gate is what actually enforces "the project compiles", and it is
    # NOT the import gate. Measured on 4.6.3, twice: `--headless --path . --import`
    # returns exit 0 against a planted hard parse error in an ordinary .gd, with
    # zero stderr -- so for years this runner's first plan entry was green on a
    # project that did not compile, and all 43 tests ran on top of that false
    # assurance (regression/perf/SPEC.md section 2, defect D1). --import IS kept:
    # it still imports every resource/scene and warms .godot, and when the broken
    # file happens to be an autoload the editor's own autoload pass does print a
    # SCRIPT ERROR that this runner catches. But that is incidental coverage of
    # 15 of ~190 scripts, not a gate. Escape hatch only; leave it off in CI.
    [switch]$SkipParse,
    [switch]$List
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ResultsRoot = Join-Path $PSScriptRoot ".results"
$RunStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$RunDir = Join-Path $ResultsRoot $RunStamp

if (-not (Test-Path $Godot)) { throw "Godot binary not found: $Godot" }

# --- Locate the user save (project name -> user:// directory) -------------------
$projectCfg = Get-Content (Join-Path $ProjectRoot "project.godot") -Raw
$projectName = "2048 Infinity"
if ($projectCfg -match 'config/name="([^"]+)"') { $projectName = $Matches[1] }
$SaveDir = Join-Path $env:APPDATA "Godot\app_userdata\$projectName"
$SaveFiles = @("tictactoe_save.json", "tictactoe_save.tmp")

function Backup-Save {
    $backup = @{}
    foreach ($f in $SaveFiles) {
        $path = Join-Path $SaveDir $f
        if (Test-Path $path) {
            $dest = Join-Path $RunDir ("save_backup_" + $f)
            Copy-Item $path $dest -Force
            $backup[$f] = $dest
        } else {
            $backup[$f] = $null
        }
    }
    return $backup
}

function Restore-Save($backup) {
    foreach ($f in $SaveFiles) {
        $path = Join-Path $SaveDir $f
        if ($null -ne $backup[$f]) {
            Copy-Item $backup[$f] $path -Force
        } elseif (Test-Path $path) {
            Remove-Item $path -Force
        }
    }
}

# --- One Godot process per test --------------------------------------------------
function Invoke-GodotTest {
    param([string]$Name, [string]$Arguments, [int]$Timeout)

    $outFile = Join-Path $RunDir ("$Name.out.log")
    $errFile = Join-Path $RunDir ("$Name.err.log")
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Process -FilePath $Godot -ArgumentList $Arguments `
        -WorkingDirectory $ProjectRoot -PassThru -NoNewWindow `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $null = $proc.Handle   # PS 5.1: cache the handle or ExitCode reads as null
    $timedOut = -not $proc.WaitForExit($Timeout * 1000)
    if ($timedOut) {
        try { $proc.Kill() } catch {}
        $proc.WaitForExit()
    }
    $sw.Stop()

    $output = ""
    if (Test-Path $outFile) { $output += (Get-Content $outFile -Raw) }
    if (Test-Path $errFile) { $output += "`n" + (Get-Content $errFile -Raw) }
    # Merge the two streams into one readable log per test.
    Set-Content -Path (Join-Path $RunDir "$Name.log") -Value $output -Encoding utf8
    Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue

    $scriptErrors = ([regex]::Matches($output, "SCRIPT ERROR")).Count
    # Godot logs an ABANDONED COROUTINE as a plain "ERROR:", not a "SCRIPT ERROR",
    # so it used to sail straight past this gate — that is exactly how the
    # intro/splash reduce-motion orphan (a SceneTree timer resuming _ready() on a
    # freed node) stayed invisible. Matched narrowly on purpose: a blanket /ERROR/
    # would trip on the benign shutdown noise every clean run prints (leaked RIDs,
    # "resources still in use at exit", the absent PGS singleton).
    $orphanErrors = ([regex]::Matches($output, "after yield, but class instance is gone")).Count
    $checks = ""
    if ($output -match "(\d+) checks, (\d+) failures") { $checks = "$($Matches[1])/$($Matches[2])" }

    $result = "PASS"
    if ($timedOut) { $result = "TIMEOUT" }
    elseif ($proc.ExitCode -ne 0) { $result = "FAIL(exit $($proc.ExitCode))" }
    elseif ($scriptErrors -gt 0) { $result = "FAIL(script errors: $scriptErrors)" }
    elseif ($orphanErrors -gt 0) { $result = "FAIL(abandoned coroutine: $orphanErrors)" }
    elseif ($output -match "TESTS FAILED") { $result = "FAIL(assertions)" }

    return [pscustomobject]@{
        Name = $Name; Result = $result; Pass = ($result -eq "PASS")
        Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        Checks = $checks; Log = "$Name.log"
    }
}

# --- Build the test plan ----------------------------------------------------------
$plan = @()

$scriptDirs = @(
    # Tier by directory (see the -Tier param): unit/service suites are Basic,
    # full-boot flows are Full.
    @{ Dir = "tests";                       Pattern = "test_*.gd"; Tier = "Basic" },
    @{ Dir = "regression\headless\suites";  Pattern = "test_*.gd"; Tier = "Basic" },
    @{ Dir = "regression\headless\flows";   Pattern = "flow_*.gd"; Tier = "Full"  }
)
foreach ($entry in $scriptDirs) {
    $dir = Join-Path $ProjectRoot $entry.Dir
    if (-not (Test-Path $dir)) { continue }
    foreach ($f in (Get-ChildItem $dir -Filter $entry.Pattern | Sort-Object Name)) {
        # A sibling .tscn means it's a scene-based test (extends Node) -- it is
        # discovered by the scene pass below, not runnable via --script.
        if (Test-Path (Join-Path $f.DirectoryName ($f.BaseName + ".tscn"))) { continue }
        $res = ($entry.Dir -replace "\\", "/") + "/" + $f.Name
        # Suites are Nodes (so the on-device runner can embed the same files);
        # headless_boot.gd is the SceneTree shim that hosts one under --script.
        $plan += [pscustomobject]@{
            Name = [IO.Path]::GetFileNameWithoutExtension($f.Name)
            Tier = $entry.Tier
            Args = "--headless --path . --script res://regression/headless/harness/headless_boot.gd -- --test=res://$res"
        }
    }
}
# Scene smokes instantiate real scenes and run frames -> Full.
$sceneDir = Join-Path $ProjectRoot "tests"
foreach ($f in (Get-ChildItem $sceneDir -Filter "*.tscn" | Sort-Object Name)) {
    $plan += [pscustomobject]@{
        Name = "scene_" + [IO.Path]::GetFileNameWithoutExtension($f.Name)
        Tier = "Full"
        Args = "--headless --path . res://tests/$($f.Name)"
    }
}
# The shipped main scene booted for real -> Full.
$plan += [pscustomobject]@{
    Name = "boot_smoke"
    Tier = "Full"
    Args = "--headless --path . --quit-after 2400"
}

$plan = @($plan | Where-Object { $_.Name -like $Filter })
# Full is a superset of Basic, so only Basic actually narrows the plan.
if ($Tier -eq "Basic") { $plan = @($plan | Where-Object { $_.Tier -eq "Basic" }) }

if ($List) {
    $plan | ForEach-Object { Write-Host ("  {0,-6} {1}" -f $_.Tier, $_.Name) }
    Write-Host "$($plan.Count) tests (tier: $Tier)."
    # The two gates are not tests and are not discovered: they run ahead of the
    # plan and abort it. Named here so this listing is not read as the whole run.
    $gateNote = @()
    if (-not $SkipImport) { $gateNote += "import_gate" }
    if (-not $SkipParse)  { $gateNote += "parse_gate" }
    if ($gateNote.Count -gt 0) {
        Write-Host ("Gates before the plan (not tests, abort on failure): {0}." -f ($gateNote -join ", "))
    }
    exit 0
}

# --- Run --------------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
Write-Host "2048 Infinity regression run  ->  $RunDir"
Write-Host "Project: $ProjectRoot"
Write-Host ""

$backup = Backup-Save
$results = @()
# Gates run BEFORE the plan and ABORT it. A test result is evidence about the
# game; a gate result is evidence about whether any test result means anything.
$gatesOk = $true
try {
    if (-not $SkipImport) {
        # Cold checkouts (CI, fresh clones) have no .godot cache. Some vendored
        # addon scripts (GodotPlayGameServices) use := type inference that only
        # resolves once Godot's global class cache exists, so the FIRST import on
        # a cold tree logs transient parse errors that clear on the next pass.
        # Warm the cache with a throwaway import first, so the gates below only
        # ever fail on a REAL compile error, not cold-cache noise. (This is also
        # why the parse gate runs AFTER the import gate rather than instead of
        # it: it resolves global class names, so it needs the same warm cache.
        # Corollary: -SkipImport on a tree with no .godot can make the parse
        # gate report cold-cache noise as a failure. Do not do that in CI.)
        if (-not (Test-Path (Join-Path $ProjectRoot ".godot"))) {
            Write-Host ("{0,-38} " -f "import_warmup (cold cache)") -NoNewline
            $w = Invoke-GodotTest -Name "import_warmup" -Arguments "--headless --path . --import" -Timeout 600
            Write-Host ("{0,-22} {1,6}s" -f "done", $w.Seconds)
        }
        Write-Host ("{0,-38} " -f "import_gate") -NoNewline
        $r = Invoke-GodotTest -Name "import_gate" -Arguments "--headless --path . --import" -Timeout 600
        $results += $r
        $color = "Green"
        if (-not $r.Pass) { $color = "Red" }
        Write-Host ("{0,-22} {1,6}s" -f $r.Result, $r.Seconds) -ForegroundColor $color
        if (-not $r.Pass) {
            $gatesOk = $false
            Write-Host "Import gate failed - a resource or scene did not import; aborting the run." -ForegroundColor Red
        }
    }

    # The gate STRATEGY.md has always promised and --import never delivered:
    # every .gd in the project is compiled, one at a time, with the only oracle
    # that reports a parse error (GDScript.reload() on a DETACHED TWIN -- the
    # live/cached script of a running autoload answers ERR_ALREADY_IN_USE no
    # matter what its source says; run parse_gate.gd -- --explain-autoload-trap
    # to see all 15 of them do it). Non-zero exit here means the project does
    # not compile, and no test result below it would have been evidence of
    # anything.
    if ($gatesOk -and -not $SkipParse) {
        Write-Host ("{0,-38} " -f "parse_gate") -NoNewline
        $r = Invoke-GodotTest -Name "parse_gate" `
            -Arguments "--headless --path . --script res://regression/headless/parse_gate.gd" -Timeout 300
        $results += $r
        $color = "Green"
        if (-not $r.Pass) { $color = "Red" }
        Write-Host ("{0,-22} {1,6}s" -f $r.Result, $r.Seconds) -ForegroundColor $color
        if (-not $r.Pass) {
            $gatesOk = $false
            Write-Host "Parse gate failed - the project does not compile; aborting the run." -ForegroundColor Red
            Write-Host ("  the failing file(s) and Godot's own parse errors are in {0}" -f (Join-Path $RunDir "parse_gate.log")) -ForegroundColor Red
        }
    }

    if ($gatesOk) {
        foreach ($t in $plan) {
            Write-Host ("{0,-38} " -f $t.Name) -NoNewline
            $r = Invoke-GodotTest -Name $t.Name -Arguments $t.Args -Timeout $TimeoutSec
            $results += $r
            $color = "Green"
            if (-not $r.Pass) { $color = "Red" }
            Write-Host ("{0,-22} {1,6}s  {2}" -f $r.Result, $r.Seconds, $r.Checks) -ForegroundColor $color
        }
    }
} finally {
    Restore-Save $backup
    Write-Host ""
    Write-Host "User save restored ($SaveDir)."
}

# --- Report -----------------------------------------------------------------------
$failed = @($results | Where-Object { -not $_.Pass })
$summaryLines = @()
$summaryLines += "# Regression run $RunStamp"
$summaryLines += ""
$summaryLines += "| Test | Result | Seconds | Checks (n/failures) |"
$summaryLines += "|------|--------|---------|---------------------|"
foreach ($r in $results) {
    $summaryLines += "| $($r.Name) | $($r.Result) | $($r.Seconds) | $($r.Checks) |"
}
$summaryLines += ""
$summaryLines += "$($results.Count) tests, $($failed.Count) failed."
Set-Content -Path (Join-Path $RunDir "summary.md") -Value ($summaryLines -join "`n") -Encoding utf8
$results | ConvertTo-Json | Set-Content -Path (Join-Path $RunDir "summary.json") -Encoding utf8

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "ALL $($results.Count) TESTS PASSED" -ForegroundColor Green
} else {
    Write-Host "$($failed.Count) of $($results.Count) tests FAILED:" -ForegroundColor Red
    foreach ($r in $failed) { Write-Host "  $($r.Name)  ->  $($r.Result)   (see $($r.Log))" -ForegroundColor Red }
}
exit $failed.Count

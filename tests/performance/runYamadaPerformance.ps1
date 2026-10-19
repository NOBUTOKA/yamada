# Run each benchmark in an owned MATLAB process and preserve partial results on timeout.
[CmdletBinding()]
param(
    [string]$Matlab = 'D:\Program Files\MATLAB\R2024a\bin\matlab.exe',
    [string[]]$Cases = @('absolute', 'flatgrid', 'nestedgrid'),
    [int]$ComponentCount = 12,
    [int]$NestedDepth = 2,
    [int]$Samples = 4,
    [int]$RepeatedSelections = 0,
    [int]$AlternatingSelections = 0,
    [int]$DocumentCycles = 0,
    [int]$PropertyChanges = 0,
    [switch]$EnduranceOnly,
    [switch]$Profile,
    [string]$OutputFolder = '',
    [int]$OperationTimeoutSeconds = 30,
    [int]$CaseTimeoutSeconds = 300
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (!$OutputFolder) { $OutputFolder = Join-Path $projectRoot ('testResults/performance/' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$OutputFolder = [IO.Path]::GetFullPath($OutputFolder)
if ((Test-Path -LiteralPath $OutputFolder) -and @(Get-ChildItem -LiteralPath $OutputFolder -Force).Count) {
    throw "Use a new output directory: $OutputFolder"
}
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
$harnessArchive = Join-Path $OutputFolder 'harness-source'
New-Item -ItemType Directory -Path $harnessArchive | Out-Null
Copy-Item -LiteralPath $PSCommandPath,(Join-Path $PSScriptRoot 'runYamadaPerformance.m'),(Join-Path $PSScriptRoot 'README.md') -Destination $harnessArchive
$tracked = @(git -C $projectRoot ls-files -- '*.m' '*.html' '*.json' 'tests/performance/*.ps1')
$added = @(git -C $projectRoot ls-files --others --exclude-standard -- '*.m' '*.html' '*.json' 'tests/performance/*.ps1')
$manifest = @($tracked + $added | Sort-Object -Unique | ForEach-Object {
    $sourcePath = Join-Path $projectRoot $_
    if (Test-Path -LiteralPath $sourcePath) {
        [pscustomobject]@{path = $_; sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash}
    }
})
[pscustomobject]@{commit = (git -C $projectRoot rev-parse HEAD); status = @(git -C $projectRoot status --short);
    count = $ComponentCount; samples = $Samples; profile = [bool]$Profile;
    repeatedSelections = $RepeatedSelections; alternatingSelections = $AlternatingSelections;
    documentCycles = $DocumentCycles; propertyChanges = $PropertyChanges; nestedDepth = $NestedDepth; enduranceOnly = [bool]$EnduranceOnly; sources = $manifest} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputFolder 'source-manifest.json') -Encoding utf8
$outcomes = @()
foreach ($case in $Cases) {
    if ($case -notin @('absolute', 'flatgrid', 'nestedgrid', 'gallery', 'navigation')) { throw "Unknown case: $case" }
    $caseFolder = Join-Path $OutputFolder $case
    New-Item -ItemType Directory -Path $caseFolder -Force | Out-Null
    $progressPath = Join-Path $caseFolder 'progress.jsonl'
    if (Test-Path -LiteralPath $progressPath) { throw "Use a new output directory: $caseFolder" }
    $quoteRoot = $projectRoot.Replace("'", "''")
    $quoteOutput = $caseFolder.Replace("'", "''")
    $profileLiteral = if ($Profile) { 'true' } else { 'false' }
    $enduranceLiteral = if ($EnduranceOnly) { 'true' } else { 'false' }
    $expression = "cd('$quoteRoot'); addpath(pwd,fullfile(pwd,'tests','performance')); runYamadaPerformance(OutputFolder=string('$quoteOutput'),Case=string('$case'),ComponentCount=$ComponentCount,NestedDepth=$NestedDepth,PropertyChanges=$PropertyChanges,Samples=$Samples,Profile=$profileLiteral,RepeatedSelections=$RepeatedSelections,AlternatingSelections=$AlternatingSelections,DocumentCycles=$DocumentCycles,EnduranceOnly=$enduranceLiteral);"
    $log = Join-Path $caseFolder 'matlab.log'
    $arguments = @('-wait', '-nosplash', '-logfile', ('"' + $log + '"'), '-batch', ('"' + $expression + '"'))
    $process = Start-Process -FilePath $Matlab -ArgumentList $arguments -PassThru -WindowStyle Hidden
    $createdAfter = $process.StartTime.ToUniversalTime()
    $started = [DateTimeOffset]::UtcNow
    $status = 'running'
    $action = 'startup'
    $ownedIds = @($process.Id)
    $nextResources = [DateTimeOffset]::UtcNow
    while (!$process.HasExited) {
        $now = [DateTimeOffset]::UtcNow
        if ($now -ge $nextResources) {
            # Ignore stale parent IDs belonging to processes created before this invocation.
            $children = @(Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -in $ownedIds -and $_.CreationDate.ToUniversalTime() -ge $createdAfter })
            $ownedIds = @($ownedIds + @($children | ForEach-Object { [int]$_.ProcessId }) | Sort-Object -Unique)
            foreach ($ownedId in $ownedIds) {
                $owned = Get-Process -Id $ownedId -ErrorAction SilentlyContinue
                if ($owned) {
                    [pscustomobject]@{timestamp = $now.ToUnixTimeMilliseconds() / 1000; pid = $ownedId;
                        cpuSeconds = $owned.CPU; privateBytes = $owned.PrivateMemorySize64;
                        workingSetBytes = $owned.WorkingSet64; handles = $owned.HandleCount} |
                        ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $caseFolder 'resources.jsonl') -Encoding utf8
                }
            }
            $nextResources = $now.AddSeconds(1)
        }
        $limit = 120
        $elapsed = ($now - $started).TotalSeconds
        if (Test-Path -LiteralPath $progressPath) {
            $lines = @(Get-Content -LiteralPath $progressPath | Where-Object { $_.Trim() })
            if ($lines.Count) {
                $event = $lines[-1] | ConvertFrom-Json
                $first = $lines[0] | ConvertFrom-Json
                $action = $event.action
                $elapsed = $now.ToUnixTimeMilliseconds() / 1000 - $event.timestamp
                $limit = if ($action -like 'profile*') { 90 } elseif ($action -eq 'fixture') { $CaseTimeoutSeconds } else { $OperationTimeoutSeconds }
                if (($now.ToUnixTimeMilliseconds() / 1000 - $first.timestamp) -gt $CaseTimeoutSeconds) { $status = 'case-timeout'; break }
            }
        }
        if ($elapsed -gt $limit) { $status = 'operation-timeout'; break }
        Start-Sleep -Milliseconds 250
        $process.Refresh()
    }
    if ($status -ne 'running') {
        # Kill only the process tree created for this fixture, never other MATLAB sessions.
        if (!$process.HasExited) { $process.Kill($true); $process.WaitForExit() }
    } else {
        $process.WaitForExit()
        $status = if ($process.ExitCode -eq 0) { 'completed' } else { 'failed' }
    }
    $outcomes += [pscustomobject]@{ case = $case; status = $status; action = $action; exitCode = $process.ExitCode; output = $caseFolder }
    ConvertTo-Json -InputObject @($outcomes) -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputFolder 'outcomes.json') -Encoding utf8
    $fixturePath = Join-Path $caseFolder 'PerformanceFixture.m'
    if (Test-Path -LiteralPath $fixturePath) {
        [pscustomobject]@{path = $fixturePath; sha256 = (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $caseFolder 'fixture-manifest.json') -Encoding utf8
    }
    Write-Output $outcomes[-1]
    $process.Dispose()
}
if (@($outcomes | Where-Object { $_.status -ne 'completed' }).Count) { throw 'Some benchmark cases did not complete; inspect outcomes.json and partial measurements.' }

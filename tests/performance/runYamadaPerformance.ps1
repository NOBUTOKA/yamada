# Run each benchmark in an owned MATLAB process and preserve partial results on timeout.
[CmdletBinding()]
param(
    [string]$Matlab = 'D:\Program Files\MATLAB\R2024a\bin\matlab.exe',
    [string[]]$Cases = @('absolute', 'flatgrid', 'nestedgrid'),
    [int]$ComponentCount = 12,
    [int]$Samples = 4,
    [switch]$Profile,
    [string]$OutputFolder = '',
    [int]$OperationTimeoutSeconds = 30,
    [int]$CaseTimeoutSeconds = 300
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (!$OutputFolder) { $OutputFolder = Join-Path $projectRoot ('testResults/performance/' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$OutputFolder = [IO.Path]::GetFullPath($OutputFolder)
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
    $expression = "cd('$quoteRoot'); addpath(pwd,fullfile(pwd,'tests','performance')); runYamadaPerformance(OutputFolder=string('$quoteOutput'),Case=string('$case'),ComponentCount=$ComponentCount,Samples=$Samples,Profile=$profileLiteral);"
    $log = Join-Path $caseFolder 'matlab.log'
    $arguments = @('-wait', '-nosplash', '-logfile', ('"' + $log + '"'), '-batch', ('"' + $expression + '"'))
    $process = Start-Process -FilePath $Matlab -ArgumentList $arguments -PassThru -WindowStyle Hidden
    $started = [DateTimeOffset]::UtcNow
    $status = 'running'
    $action = 'startup'
    while (!$process.HasExited) {
        $now = [DateTimeOffset]::UtcNow
        $limit = 120
        $elapsed = ($now - $started).TotalSeconds
        if (Test-Path -LiteralPath $progressPath) {
            $lines = @(Get-Content -LiteralPath $progressPath | Where-Object { $_.Trim() })
            if ($lines.Count) {
                $event = $lines[-1] | ConvertFrom-Json
                $first = $lines[0] | ConvertFrom-Json
                $action = $event.action
                $elapsed = $now.ToUnixTimeMilliseconds() / 1000 - $event.timestamp
                $limit = if ($action -eq 'profile') { 90 } elseif ($action -eq 'fixture') { $CaseTimeoutSeconds } else { $OperationTimeoutSeconds }
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
    $outcomes | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputFolder 'outcomes.json') -Encoding utf8
    Write-Output $outcomes[-1]
    $process.Dispose()
}
if (@($outcomes | Where-Object { $_.status -ne 'completed' }).Count) { throw 'Some benchmark cases did not complete; inspect outcomes.json and partial measurements.' }

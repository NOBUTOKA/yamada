# Copyright (C) 2026 Nobuto Kaitoh
# SPDX-License-Identifier: GPL-3.0-or-later
# This file is part of yamada. See LICENSE for the license text.

param([string]$Phase='ordinary',[switch]$Profiled,[int]$Rounds=2,[string[]]$Layouts=@('absolute','flatgrid','nestedgrid'),[int[]]$Counts=@(10,50,100))
$ErrorActionPreference='Stop'
$root=(Get-Location).Path
$base=Join-Path $root 'testResults/performance/source-strategy-20261031'
$inputs=Get-Content (Join-Path $base 'inputs.json') -Raw | ConvertFrom-Json
function Assert-Inputs {
 foreach ($mode in @('deferred','eager')) {
  $variant=$inputs.variants.$mode
  if ((Get-FileHash -LiteralPath (Join-Path $variant.root 'yamada.m')).Hash -ne $variant.sha256) {throw 'Detached UI variant changed.'}
 }
 foreach ($layout in @('absolute','flatgrid','nestedgrid')) {
  $fixture=$inputs.fixtures.$layout
  if ((Get-FileHash -LiteralPath $fixture.path).Hash -ne $fixture.sha256) {throw 'Fixture changed.'}
 }
 if ((Get-FileHash -LiteralPath (Join-Path $base 'operations.json')).Hash -ne $inputs.operationsSha256) {throw 'Operations changed.'}
 foreach ($entry in $inputs.sources) {if ((Get-FileHash -LiteralPath (Join-Path $root $entry.path)).Hash -ne $entry.sha256) {throw ('Source changed: '+$entry.path)}}
}
for ($round=1;$round -le $Rounds;$round++) {
 $modes=if ($round % 2) {@('deferred','eager')} else {@('eager','deferred')}
 foreach ($layout in $Layouts) {foreach ($count in $Counts) {foreach ($mode in $modes) {
  if (Get-Process -Name MATLAB -ErrorAction SilentlyContinue) {throw 'Another MATLAB is active.'}
  Assert-Inputs
  $out=Join-Path $base ($Phase+'-'+$layout+'-'+$mode+'-'+$count+'-'+$round)
  if (Test-Path -LiteralPath $out) {throw 'Preserve existing output.'}
  New-Item -ItemType Directory -Path $out|Out-Null
  $profileValue=if($Profiled){'true'}else{'false'}
  $expression="addpath('tests/performance'); runSourceStrategyUIComparison('$layout','$mode',$count,'$out',$profileValue);"
  $p=Start-Process -FilePath 'D:\Program Files\MATLAB\R2024a\bin\matlab.exe' -ArgumentList @('-wait','-nosplash','-logfile',('"'+(Join-Path $out 'matlab.log')+'"'),'-batch',('"'+$expression+'"')) -WindowStyle Hidden -PassThru
  $ownedIds=@($p.Id)
  $started=[DateTime]::UtcNow
  [IO.File]::WriteAllText((Join-Path $out 'process.json'),(@{pid=$p.Id;started=$started.ToString('o')}|ConvertTo-Json))
  while (-not $p.WaitForExit(3000)) {
   $all=@(Get-CimInstance Win32_Process -Filter "Name='MATLAB.exe'")
   $ownedIds=@($ownedIds+@($all|Where-Object {$_.CommandLine -and $_.CommandLine.Contains($out)}|ForEach-Object {$_.ProcessId})|Sort-Object -Unique)
   $unexpected=@($all|Where-Object {$_.ProcessId -notin $ownedIds}|ForEach-Object {$_.ProcessId})
   [IO.File]::AppendAllText((Join-Path $out 'processes.jsonl'),(@{utc=[DateTime]::UtcNow.ToString('o');pids=@($all.ProcessId);unexpected=$unexpected}|ConvertTo-Json -Compress)+[Environment]::NewLine)
   if ($unexpected.Count) {throw 'Concurrent MATLAB observed.'}
   if (([DateTime]::UtcNow-$started).TotalSeconds -gt 7200) {throw 'Inspect existing process; observation limit reached.'}
  }
  if ($p.ExitCode -ne 0) {throw ('Experiment failed: '+$out)}
  Assert-Inputs
  Write-Output ('CASE_COMPLETE '+$Phase+' '+$layout+' '+$mode+' '+$count+' Round='+$round)
 }}}
}

<#
.SYNOPSIS
Verifies reviewed ledger rules, deterministic application, and validation isolation.
.DESCRIPTION
Uses a fresh owned temporary directory. Never writes to the project ledger.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $projectRoot 'dev/component-data'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('yamada-policy-review-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-LedgerHashes {
    param([string]$Root)
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Root 'components') -Filter '*.json' | Sort-Object Name)
    return @($files | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ','
}

try {
    $releaseRoot = Join-Path $temporaryRoot 'R2024a'
    Copy-Item -LiteralPath (Join-Path $toolRoot 'R2024a') -Destination $releaseRoot -Recurse
    $apply = Join-Path $toolRoot 'ApplyApplicationPolicyReview.ps1'
    & $apply -ReleaseDirectory $releaseRoot | Out-Null
    $first = Get-LedgerHashes $releaseRoot
    & $apply -ReleaseDirectory $releaseRoot | Out-Null
    Assert-Condition ($first -ceq (Get-LedgerHashes $releaseRoot)) 'Reviewed rules are not reproducible.'

    # Assert actual reviewed contracts rather than duplicating the graph algorithm.
    $dropdown = Get-Content -LiteralPath (Join-Path $releaseRoot 'components/uidropdown.json') -Raw | ConvertFrom-Json
    $value = $dropdown.properties | Where-Object path -CEQ 'Value'
    Assert-Condition (($value.application.applyAfter -join ',') -ceq 'Editable,Items,ItemsData') 'Dropdown domain prerequisites were lost.'
    Assert-Condition ($value.application.nameValue -ceq 'supported') 'Verified Dropdown constructor support was lost.'
    Assert-Condition ($value.applicationEvidence[0].kind -ceq 'inference') 'An inferred ordering was misrepresented as an explicit documentation command.'
    Assert-Condition (@($value.applicationEvidence | Where-Object kind -CEQ 'runtime').Count -eq 1) 'Constructor evidence is missing or duplicated.'
    $date = Get-Content -LiteralPath (Join-Path $releaseRoot 'components/uidatepicker.json') -Raw | ConvertFrom-Json
    $dateValue = $date.properties | Where-Object path -CEQ 'Value'
    Assert-Condition ($dateValue.application.nameValue -ceq 'unknown') 'Unverified date constructor support was asserted.'
    $axes = Get-Content -LiteralPath (Join-Path $releaseRoot 'components/uiaxes.json') -Raw | ConvertFrom-Json
    $ticks = $axes.properties | Where-Object path -CEQ 'XTick'
    $mode = $axes.properties | Where-Object path -CEQ 'XTickMode'
    Assert-Condition ($ticks.application.effectPolicy -ceq 'valueMode') 'Audited axes mode effects were lost.'
    Assert-Condition (($mode.application.applyAfter -join ',') -ceq 'XTick') 'A final axes mode must follow its value.'
    Assert-Condition ($mode.application.defaultLiteral -ceq "'auto'") 'The documented automatic mode seed was lost.'
    Assert-Condition ($mode.application.nameValue -ceq 'supported') 'Verified axes constructor mode support was lost.'
    $geographic = Get-Content -LiteralPath (Join-Path $releaseRoot 'components/geoaxes.json') -Raw | ConvertFrom-Json
    $direction = $geographic.properties | Where-Object path -CEQ 'TickDir'
    Assert-Condition ($null -eq $direction.PSObject.Properties['application'] -or
        $direction.application.effectPolicy -cne 'valueMode') 'Unresolved geographic direction behavior was generalized.'
    foreach ($style in @('circular', 'linear', 'ninetydegree', 'semicircular')) {
        $gauge = Get-Content -LiteralPath (Join-Path $releaseRoot "components/uigauge-$style.json") -Raw | ConvertFrom-Json
        $gaugeValue = $gauge.properties | Where-Object path -CEQ 'Value'
        Assert-Condition (@($gaugeValue.valueContract.constraints | Where-Object kind -CEQ 'withinLimitsOf').Count -eq 0) 'Gauge inherited a slider constraint.'
    }

    # A late invalid rule must not partially rewrite earlier validated components.
    $reviewPath = Join-Path $releaseRoot 'APPLICATION_POLICY_REVIEW.json'
    $review = Get-Content -LiteralPath $reviewPath -Raw | ConvertFrom-Json
    $review.rules[-1].applyAfter = @('MissingDependency')
    [IO.File]::WriteAllText($reviewPath, ($review | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    $failed = $false
    try { & $apply -ReleaseDirectory $releaseRoot | Out-Null } catch { $failed = $true }
    Assert-Condition $failed 'A missing dependency was accepted.'
    Assert-Condition ($first -ceq (Get-LedgerHashes $releaseRoot)) 'Validation failure changed a ledger.'
    Write-Output 'APPLICATION_POLICY_REVIEW Passed: reviewed rules, conservative constructor support, gauge exception, reproducibility, atomic validation failure.'
}
finally {
    $resolvedRoot = [IO.Path]::GetFullPath($temporaryRoot)
    $temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolvedRoot.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedRoot) -notlike 'yamada-policy-review-*') {
        throw 'Temporary verification directory failed cleanup boundary validation.'
    }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
}

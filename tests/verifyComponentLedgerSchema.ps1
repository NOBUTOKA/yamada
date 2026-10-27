<#
.SYNOPSIS
Verifies complete ledger schemas and pipeline rejection before any output write.
.DESCRIPTION
Uses an owned temporary release copy for valid regeneration and invalid input
fixtures. Source ledgers and packaged catalogs are never modified.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $projectRoot 'dev/component-data'
. (Join-Path $toolRoot 'ComponentLedger.ps1')

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-TreeDigest {
    param([string]$Root)
    return (@(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
        [IO.Path]::GetRelativePath($Root, $_.FullName) + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }) -join ',')
}

function Invoke-PipelineEntry {
    param([string]$Name, [string]$ReleaseRoot, [string]$CatalogRoot)
    $parameters = @{ ReleaseDirectory = $ReleaseRoot }
    if ($Name -ceq 'PromoteGroupingToRuntimeCatalog') { $parameters.CatalogRoot = $CatalogRoot }
    & (Join-Path $toolRoot ($Name + '.ps1')) @parameters | Out-Null
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('yamada-ledger-schema-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
try {
    $releaseRoot = Join-Path $temporaryRoot 'R2024a'
    $catalogRoot = Join-Path $temporaryRoot 'catalog'
    Copy-Item -LiteralPath (Join-Path $toolRoot 'R2024a') -Destination $releaseRoot -Recurse
    Assert-ComponentLedgerSchema -ReleaseDirectory $releaseRoot
    $documents = @(Get-ChildItem -LiteralPath (Join-Path $releaseRoot 'components') -Filter '*.json' -File)
    $entries = @('ApplyGeometryImpactReview', 'ApplyApplicationPolicyReview', 'GenerateGroupingArtifacts', 'GenerateGroupingDesign', 'PromoteGroupingToRuntimeCatalog')
    foreach ($entry in $entries) { Invoke-PipelineEntry $entry $releaseRoot $catalogRoot }
    Assert-ComponentLedgerSchema -ReleaseDirectory $releaseRoot

    # Reapplying reviewed rules must retain the canonical arrays and complete schema.
    $baseline = Get-TreeDigest $temporaryRoot
    foreach ($entry in $entries) { Invoke-PipelineEntry $entry $releaseRoot $catalogRoot }
    Assert-Condition ($baseline -ceq (Get-TreeDigest $temporaryRoot)) 'Valid schema regeneration is not reproducible.'
    $runtime = Get-Content -LiteralPath (Join-Path $catalogRoot 'components/uiaxes.json') -Raw | ConvertFrom-Json
    $ticks = @($runtime.categories | ForEach-Object { $_.entries }) | Where-Object path -CEQ 'XTick'
    Assert-Condition ($ticks.metadata.description -ceq 'Tick values') 'The grouped official heading did not reach runtime metadata.'

    $label = Get-Content -LiteralPath (Join-Path $catalogRoot 'components/uilabel.json') -Raw | ConvertFrom-Json
    $text = @($label.categories | ForEach-Object { $_.entries }) | Where-Object path -CEQ 'Text'
    Assert-Condition ($text.metadata.gridGeometryImpact -ceq 'fit' -and $text.metadata.absoluteGeometryImpact -ceq $false) 'Geometry metadata did not reach the runtime component.'
    $manifest = Get-Content -LiteralPath (Join-Path $catalogRoot 'catalog.json') -Raw | ConvertFrom-Json
    $grid = $manifest.parentContextRules | Where-Object kind -CEQ 'grid'
    Assert-Condition ($grid.geometryImpacts.Count -eq 2 -and @($grid.geometryImpacts | Where-Object gridGeometryImpact -CNE 'required').Count -eq 0) 'Contributed geometry metadata did not reach runtime rules.'

    # A late invalid component must block every ingress without partial artifacts.
    $fixturePath = Join-Path $releaseRoot 'components/uilistbox.json'
    $original = [IO.File]::ReadAllText($fixturePath)
    $rejections = 0
    foreach ($case in @('missingGeometry', 'unknownGeometry', 'numericGeometryBoolean', 'scalarClass', 'emptySummary', 'unknownReason', 'invalidPeerPath', 'unknownPolicyField', 'malformedJson')) {
        $fixture = $original | ConvertFrom-Json
        $value = $fixture.properties | Where-Object path -CEQ 'Value'
        switch ($case) {
            'missingGeometry' { $value.PSObject.Properties.Remove('gridGeometryImpact') }
            'unknownGeometry' { $value.gridGeometryImpact = 'unknown' }
            'numericGeometryBoolean' { $value.absoluteGeometryImpact = 0 }
            'scalarClass' { $value.valueContract.matlabClasses = 'any' }
            'emptySummary' { $value.summary = '' }
            'unknownReason' { $value.disposition.reasonCodes = @('unreviewedReason') }
            'invalidPeerPath' { $value.valueContract.multiselectProperty = 42 }
            'unknownPolicyField' { $value.application | Add-Member -NotePropertyName evaluate -NotePropertyValue 'unsupported' }
        }
        $text = $fixture | ConvertTo-Json -Depth 100
        if ($case -ceq 'malformedJson') { $text = '{ invalid component JSON' }
        [IO.File]::WriteAllText($fixturePath, $text, [Text.UTF8Encoding]::new($false))
        $before = Get-TreeDigest $temporaryRoot
        foreach ($entry in $entries) {
            $message = ''
            try { Invoke-PipelineEntry $entry $releaseRoot $catalogRoot }
            catch { $message = $_.Exception.Message }
            Assert-Condition ($message.Contains('Component ledger schema preflight failed') -and $message.Contains('uilistbox.json')) "Invalid fixture $case was not rejected contextually by $entry."
            Assert-Condition ($before -ceq (Get-TreeDigest $temporaryRoot)) "$entry wrote outputs before rejecting $case."
            $rejections++
        }
    }
    [IO.File]::WriteAllText($fixturePath, $original, [Text.UTF8Encoding]::new($false))
    Assert-ComponentLedgerSchema -ReleaseDirectory $releaseRoot
    Write-Output "COMPONENT_LEDGER_SCHEMA Passed: $($documents.Count) documents, reproducible regeneration, runtime heading, $rejections atomic ingress rejections."
}
finally {
    $resolvedRoot = [IO.Path]::GetFullPath($temporaryRoot)
    $temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolvedRoot.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedRoot) -notlike 'yamada-ledger-schema-*') {
        throw 'Temporary verification directory failed cleanup boundary validation.'
    }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
}

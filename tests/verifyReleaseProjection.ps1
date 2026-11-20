# Copyright (C) 2026 Nobuto Kaitoh
# SPDX-License-Identifier: GPL-3.0-or-later
# This file is part of yamada. See LICENSE for the license text.

<#
.SYNOPSIS
Verifies release projections of the surface ledger and their committed outputs.
.DESCRIPTION
Copies the component data tools, ledger, and packaged catalogs into an owned
temporary tree and regenerates every release there. The catalogs, availability
index, projection reports, surface grouping artifacts, and refreshed ledger text
must equal the committed files, so a stale output fails. Synthetic annotations
then exercise availability, overrides, value ranges, and the fail-closed cases.
Source ledgers and packaged catalogs are never modified. Requires PowerShell 7.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-Text {
    param([string]$Path)
    return [IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
}

function Assert-SameTree {
    param([string]$Expected, [string]$Actual, [string]$Label, [string[]]$Exclude = @())
    # Compare LF-normalized text so CRLF and LF checkouts agree.
    $expectedFiles = @(Get-ChildItem -LiteralPath $Expected -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($Expected, $_.FullName).Replace('\', '/') } | Where-Object { $Exclude -cnotcontains $_ } | Sort-Object)
    $actualFiles = @(Get-ChildItem -LiteralPath $Actual -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($Actual, $_.FullName).Replace('\', '/') } | Where-Object { $Exclude -cnotcontains $_ } | Sort-Object)
    Assert-Condition (($expectedFiles -join ',') -ceq ($actualFiles -join ',')) "$Label has different files after regeneration."
    foreach ($relative in $expectedFiles) {
        Assert-Condition ((Get-Text (Join-Path $Expected $relative)) -ceq (Get-Text (Join-Path $Actual $relative))) "$Label/$relative is not current; regenerate the release catalogs."
    }
}

function Edit-Document {
    param([string]$Path, [scriptblock]$Change)
    $document = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    & $Change $document
    [IO.File]::WriteAllText($Path, ($document | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
}

function New-Range {
    param([string]$Since = '', [string]$Before = '')
    $range = [ordered]@{}
    if ($Since) { $range.since = $Since }
    if ($Before) { $range.before = $Before }
    return $range
}

function Add-Availability {
    param([object]$Record, [object]$Range)
    $Record | Add-Member -NotePropertyName availability -NotePropertyValue ([ordered]@{ releases = $Range; evidence = $evidence }) -Force
}

function Add-Override {
    param([object]$Record, [object]$Range, [object]$Patch)
    $existing = @()
    if ($null -ne $Record.PSObject.Properties['overrides']) { $existing = @($Record.overrides) }
    $Record | Add-Member -NotePropertyName overrides -NotePropertyValue @($existing + [ordered]@{ releases = $Range; patch = $Patch; evidence = $evidence }) -Force
}

function Invoke-Projection {
    param([string]$Release)
    $output = Join-Path $projectionRoot $Release
    & (Join-Path $tools 'ProjectReleaseLedger.ps1') -Release $Release -OutputDirectory $output -ToolDirectory $tools | Out-Null
    return $output
}

function Read-Projected {
    param([string]$Release, [string]$Id)
    return Get-Content -LiteralPath (Join-Path $projectionRoot "$Release/components/$Id.json") -Raw | ConvertFrom-Json
}

function Assert-Rejected {
    param([string]$Release, [string]$Expected, [string]$Case)
    $message = ''
    try { Invoke-Projection $Release | Out-Null } catch { $message = $_.Exception.Message }
    Assert-Condition ($message.Contains($Expected)) "Case $Case was not rejected with '$Expected': $message"
}

$evidence = @([ordered]@{ kind = 'projectDecision'; source = 'tests/verifyReleaseProjection.ps1'; detail = 'Synthetic verification input.' })
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('yamada-release-projection-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
try {
    # Regenerate everything in an isolated copy and compare it with the committed outputs.
    $tools = Join-Path $temporaryRoot 'dev/component-data'
    New-Item -ItemType Directory -Path (Split-Path -Parent $tools) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'dev/component-data') -Destination $tools -Recurse
    New-Item -ItemType Directory -Path (Join-Path $temporaryRoot 'resources') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'resources/component-catalog') -Destination (Join-Path $temporaryRoot 'resources/component-catalog') -Recurse
    & (Join-Path $tools 'RegenerateReleaseCatalogs.ps1') -RepositoryRoot $temporaryRoot -ToolDirectory $tools | Out-Null
    $releases = Get-Content -LiteralPath (Join-Path $tools 'releases.json') -Raw | ConvertFrom-Json
    $surface = [string]$releases.surfaceRelease
    Assert-SameTree (Join-Path $projectRoot 'resources/component-catalog') (Join-Path $temporaryRoot 'resources/component-catalog') 'resources/component-catalog'
    Assert-SameTree (Join-Path $projectRoot 'dev/component-data/projections') (Join-Path $tools 'projections') 'dev/component-data/projections'
    # The baseline commit depends on the checkout, not on the ledger content.
    Assert-SameTree (Join-Path $projectRoot "dev/component-data/$surface") (Join-Path $tools $surface) "dev/component-data/$surface" @('grouping/INPUT_BASELINE.json')
    $generated = @($releases.releases | Where-Object status -CNE 'known').Count

    # Availability, before bounds, overrides, and value ranges shape each projection.
    $projectionRoot = Join-Path $temporaryRoot 'projections'
    $ledger = Join-Path $tools "$surface/components"
    $older = @($releases.releases | Where-Object status -CEQ 'verified' | ForEach-Object { [string]$_.release })
    Assert-Condition ($older.Count -ge 2) 'The synthetic cases need two verified releases older than the surface.'
    $oldest = $older[0]
    $newer = $older[-1]
    Edit-Document (Join-Path $ledger 'uilabel.json') {
        param($document)
        $tooltip = $document.properties | Where-Object path -CEQ 'Tooltip'
        Add-Availability $tooltip (New-Range -Since $surface)
        $text = $document.properties | Where-Object path -CEQ 'Text'
        Add-Override $text (New-Range -Before $surface) ([ordered]@{ summary = 'Older summary.' })
        $alignment = $document.properties | Where-Object path -CEQ 'HorizontalAlignment'
        $alignment.valueContract | Add-Member -NotePropertyName valueAvailability -NotePropertyValue @([ordered]@{ value = 'right'; releases = (New-Range -Since $surface); evidence = $evidence })
    }
    Edit-Document (Join-Path $ledger 'uilamp.json') {
        param($document)
        Add-Availability ($document.properties | Where-Object path -CEQ 'Color') (New-Range -Before $newer)
    }
    Invoke-Projection $newer | Out-Null
    Invoke-Projection $oldest | Out-Null
    Invoke-Projection $surface | Out-Null
    $label = Read-Projected $newer 'uilabel'
    Assert-Condition (@($label.properties | Where-Object path -CEQ 'Tooltip').Count -eq 0) 'A property available since the surface remained in an older release.'
    Assert-Condition ((Read-Projected $surface 'uilabel').properties.path -ccontains 'Tooltip') 'A property available since the surface left the surface release.'
    Assert-Condition (($label.properties | Where-Object path -CEQ 'Text').summary -ceq 'Older summary.') 'An override did not apply inside its range.'
    Assert-Condition (((Read-Projected $surface 'uilabel').properties | Where-Object path -CEQ 'Text').summary -cne 'Older summary.') 'An override applied outside its range.'
    Assert-Condition (@(($label.properties | Where-Object path -CEQ 'HorizontalAlignment').valueContract.values) -cnotcontains 'right') 'An unavailable enum value remained.'
    Assert-Condition ($null -eq (($label.properties | Where-Object path -CEQ 'Text').PSObject.Properties['overrides'])) 'A projection kept annotations.'
    Assert-Condition ((Read-Projected $oldest 'uilamp').properties.path -ccontains 'Color') 'A property before its removal left an older release.'
    Assert-Condition ((Read-Projected $newer 'uilamp').properties.path -cnotcontains 'Color') 'A removed property remained after its removal.'
    $categories = @((Read-Projected $newer 'uilabel').properties | Group-Object categoryId | ForEach-Object { ($_.Group | ForEach-Object { [int]$_.order } | Sort-Object) -join ',' })
    foreach ($orders in $categories) { Assert-Condition ($orders -ceq ((1..(@($orders -split ',').Count)) -join ',')) 'Category orders are not contiguous after a removal.' }

    # Contradictory or ambiguous annotations fail before writing a projection.
    $original = @{}
    foreach ($id in @('uilabel', 'uicolorpicker', 'uislider-slider', 'uilamp')) { $original[$id] = [IO.File]::ReadAllText((Join-Path $ledger "$id.json")) }
    $restore = { foreach ($id in $original.Keys) { [IO.File]::WriteAllText((Join-Path $ledger "$id.json"), $original[$id], [Text.UTF8Encoding]::new($false)) } }
    $cases = @(
        @{ name = 'overrideCoversSurface'; expected = 'covers the surface release'; id = 'uilamp'; change = { param($d) Add-Override ($d.properties | Where-Object path -CEQ 'Color') (New-Range -Since $oldest) ([ordered]@{ summary = 'x' }) } },
        @{ name = 'overlappingOverrides'; expected = 'overlapping releases'; id = 'uilamp'; change = { param($d) $p = $d.properties | Where-Object path -CEQ 'Color'; Add-Override $p (New-Range -Before $surface) ([ordered]@{ summary = 'x' }); Add-Override $p (New-Range -Before $newer) ([ordered]@{ summary = 'y' }) } },
        @{ name = 'unknownRelease'; expected = 'does not list'; id = 'uilamp'; change = { param($d) Add-Availability ($d.properties | Where-Object path -CEQ 'Color') (New-Range -Since 'R1999a') } },
        @{ name = 'propertyOutsideVariant'; expected = 'outside the releases of its variant'; id = 'uicolorpicker'; change = { param($d) Add-Availability ($d.properties | Select-Object -First 1) (New-Range -Since $oldest) } },
        @{ name = 'constraintOnUnavailable'; expected = 'constrains on unavailable'; id = 'uislider-slider'; change = { param($d) Add-Availability ($d.properties | Where-Object path -CEQ 'Limits') (New-Range -Since $surface) } },
        @{ name = 'defaultVariantRemoved'; expected = 'default variant'; id = 'uislider-slider'; change = { param($d)
            # Property ranges may start before this synthetic variant range; only the default-variant rule is under test.
            foreach ($property in @($d.properties)) { if ($null -ne $property.PSObject.Properties['availability']) { $property.PSObject.Properties.Remove('availability') } }
            Add-Availability $d (New-Range -Since $surface) } }
    )
    foreach ($case in $cases) {
        & $restore
        Edit-Document (Join-Path $ledger "$($case.id).json") $case.change
        Assert-Rejected $newer $case.expected $case.name
    }
    & $restore
    $known = @($releases.releases | Where-Object status -CEQ 'known' | Select-Object -First 1)
    if ($known.Count -eq 1) { Assert-Rejected ([string]$known[0].release) 'only known from release notes' 'knownRelease' }
    Write-Output "RELEASE_PROJECTION Passed: $generated current release catalogs, availability, overrides, value ranges, $($cases.Count + $known.Count) rejected annotations."
}
finally {
    $resolvedRoot = [IO.Path]::GetFullPath($temporaryRoot)
    $temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolvedRoot.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedRoot) -notlike 'yamada-release-projection-*') {
        throw 'Temporary verification directory failed cleanup boundary validation.'
    }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
}

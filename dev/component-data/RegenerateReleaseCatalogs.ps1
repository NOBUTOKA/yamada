# Copyright (C) 2026 Nobuto Kaitoh
# SPDX-License-Identifier: GPL-3.0-or-later
# This file is part of yamada. See LICENSE for the license text.

<#
.SYNOPSIS
Regenerates every release catalog from the surface release ledger.

.DESCRIPTION
Refreshes presentation text in the surface ledger named by releases.json,
then projects it onto every audited and verified release with
ProjectReleaseLedger.ps1 and runs grouping artifact generation, grouping
design, and promotion on each projection. Catalogs are written to
resources/component-catalog/<release>, projection reports to
dev/component-data/projections/<release>.md, and the surface release's grouping
review artifacts back into its ledger. Catalogs of releases that are only
known are removed. The release-independent availability index is written to
resources/component-catalog/availability.json. Projections themselves are
temporary. Requires PowerShell 7 and Git on PATH.

.EXAMPLE
./RegenerateReleaseCatalogs.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [Parameter()]
    [string]$ToolDirectory = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Json {
    param([string]$Path, [object]$Value)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Get-Range {
    param([object]$Record)
    if ($null -eq $Record.PSObject.Properties['availability']) { return $null }
    $range = [ordered]@{}
    if ($null -ne $Record.availability.releases.PSObject.Properties['since']) { $range.since = [string]$Record.availability.releases.since }
    if ($null -ne $Record.availability.releases.PSObject.Properties['before']) { $range.before = [string]$Record.availability.releases.before }
    return $range
}

# Read the release list and refresh source presentation text once.
$releases = [IO.File]::ReadAllText((Join-Path $ToolDirectory 'releases.json')) | ConvertFrom-Json
$surface = [string]$releases.surfaceRelease
$ledger = Join-Path $ToolDirectory $surface
& (Join-Path $ToolDirectory 'UpdateProjectPropertyText.ps1') -ReleaseDirectory $ledger | Out-Null
$catalogs = Join-Path $RepositoryRoot 'resources/component-catalog'
$reports = Join-Path $ToolDirectory 'projections'
New-Item -ItemType Directory -Path $reports -Force | Out-Null

# Project, group, and promote each release that has a verified surface.
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('yamada-projections-' + [guid]::NewGuid())
try {
    foreach ($entry in @($releases.releases)) {
        $name = [string]$entry.release
        $catalog = Join-Path $catalogs $name
        if ([string]$entry.status -ceq 'known') {
            if (Test-Path -LiteralPath $catalog) { Remove-Item -LiteralPath $catalog -Recurse -Force; "Removed catalog of known-only $name." }
            continue
        }
        $projection = Join-Path $temporary $name
        & (Join-Path $ToolDirectory 'ProjectReleaseLedger.ps1') -Release $name -OutputDirectory $projection -ToolDirectory $ToolDirectory | Out-Null
        & (Join-Path $ToolDirectory 'GenerateGroupingArtifacts.ps1') -ReleaseDirectory $projection -ProvenanceDirectory $ledger | Out-Null
        & (Join-Path $ToolDirectory 'GenerateGroupingDesign.ps1') -ReleaseDirectory $projection | Out-Null
        & (Join-Path $ToolDirectory 'PromoteGroupingToRuntimeCatalog.ps1') -ReleaseDirectory $projection -CatalogRoot $catalog | Out-Null
        Copy-Item -LiteralPath (Join-Path $projection 'PROJECTION.md') -Destination (Join-Path $reports "$name.md") -Force
        if ($name -ceq $surface) {
            # The surface release keeps its reviewed grouping artifacts beside its ledger.
            $grouping = Join-Path $ledger 'grouping'
            if (Test-Path -LiteralPath $grouping) { Remove-Item -LiteralPath $grouping -Recurse -Force }
            Copy-Item -LiteralPath (Join-Path $projection 'grouping') -Destination $grouping -Recurse
        }
        "Regenerated $name."
    }
}
finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}

# Publish which variants, properties, and values exist in which releases for diagnostics in other releases.
$metadata = [IO.File]::ReadAllText((Join-Path $ledger 'runtime-component-metadata.json')) | ConvertFrom-Json
$variants = [System.Collections.Generic.List[object]]::new()
$properties = [System.Collections.Generic.List[object]]::new()
$values = [System.Collections.Generic.List[object]]::new()
foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $ledger 'components') -Filter '*.json' -File | Sort-Object Name)) {
    $document = [IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
    $range = Get-Range $document
    if ($null -ne $range) {
        $entry = @($metadata.factories | Where-Object factory -CEQ ([string]$document.factory))[0]
        $displayName = [string]$entry.capabilities.displayName
        if ($null -ne $entry.PSObject.Properties['variantCapabilities'] -and $null -ne $entry.variantCapabilities.PSObject.Properties[[string]$document.id]) {
            $displayName = [string]$entry.variantCapabilities.([string]$document.id).displayName
        }
        $variants.Add([ordered]@{ id = [string]$document.id; factory = [string]$document.factory
            creationArguments = @($document.creationArguments); displayName = $displayName; releases = $range })
    }
    foreach ($property in @($document.properties)) {
        $range = Get-Range $property
        if ($null -ne $range) { $properties.Add([ordered]@{ variantId = [string]$document.id; path = [string]$property.path; releases = $range }) }
        if ($null -ne $property.valueContract.PSObject.Properties['valueAvailability']) {
            foreach ($value in @($property.valueContract.valueAvailability)) {
                $valueRange = [ordered]@{}
                foreach ($bound in @('since', 'before')) { if ($null -ne $value.releases.PSObject.Properties[$bound]) { $valueRange[$bound] = [string]$value.releases.$bound } }
                $values.Add([ordered]@{ variantId = [string]$document.id; path = [string]$property.path; value = [string]$value.value; releases = $valueRange })
            }
        }
    }
}
Write-Json (Join-Path $catalogs 'availability.json') ([ordered]@{
    schemaVersion = 1
    surfaceRelease = $surface
    releases = @($releases.releases | ForEach-Object { [ordered]@{ release = [string]$_.release; catalog = [string]$_.status -cne 'known' } })
    variants = @($variants.ToArray())
    properties = @($properties.ToArray())
    values = @($values.ToArray())
})
"Wrote the availability index with $($variants.Count) variants, $($properties.Count) properties, and $($values.Count) values."

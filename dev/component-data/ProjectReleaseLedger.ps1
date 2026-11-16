# Copyright (C) 2026 Nobuto Kaitoh
# SPDX-License-Identifier: GPL-3.0-or-later
# This file is part of yamada. See LICENSE for the license text.

<#
.SYNOPSIS
Projects the surface release ledger onto one MATLAB release.

.DESCRIPTION
The component ledger in the directory named by releases.json surfaceRelease
describes that release. Availability ranges and release-range overrides in
its records describe every other listed release. This script writes an
ordinary, annotation-free ledger for one release into OutputDirectory, so the
grouping and promotion tools can build that release's runtime catalog
unchanged.

For the target release it applies every override whose range contains it,
removes unavailable variants, properties, and enum values, and updates
references whose consequence is determined: styles of removed variants,
application-order references to removed paths, emptied categories and their
scope classifications, shared-subset membership, and Inspector-row targets.
Any other reference to an unavailable path, a removed default style, an
override covering the surface release, and overlapping overrides fail the
projection. A Markdown report of every removal and override is written next to
the projected ledger. Requires PowerShell 7.

.EXAMPLE
./ProjectReleaseLedger.ps1 -Release R2023a -OutputDirectory $env:TEMP/projection/R2023a
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^R[0-9]{4}[ab]$')]
    [string]$Release,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter()]
    [string]$ToolDirectory = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ComponentLedger.ps1')

# Files that the grouping and promotion steps read; audit records stay with the surface ledger.
$inputFiles = @(
    'schema.json',
    'runtime-component-metadata.json', 'runtime-component-metadata.schema.json',
    'parent-context-rules.json', 'parent-context-rules.schema.json',
    'inspector-rows.json', 'inspector-rows.schema.json',
    'category-scope-classification.json',
    'grouping-design-input.json', 'grouping-design-input.schema.json'
)

function Read-Json {
    param([string]$Path)
    return [IO.File]::ReadAllText($Path) | ConvertFrom-Json
}

function Write-Json {
    param([string]$Path, [object]$Value)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Test-HasProperty {
    param([object]$Object, [string]$Name)
    return $Object -is [pscustomobject] -and $null -ne $Object.PSObject.Properties[$Name]
}

function Set-Field {
    param([pscustomobject]$Object, [string]$Name, [object]$Value)
    if (Test-HasProperty $Object $Name) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Copy-Value {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    # Avoid the pipeline so one-element arrays stay arrays.
    $copy = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 100 -Compress) -NoEnumerate
    return ,$copy
}

function Merge-Patch {
    param([object]$Target, [object]$Patch)
    # RFC 7386: objects merge recursively, null removes, and every other value replaces.
    foreach ($property in $Patch.PSObject.Properties) {
        if ($null -eq $property.Value) {
            if (Test-HasProperty $Target $property.Name) { $Target.PSObject.Properties.Remove($property.Name) }
        }
        elseif ($property.Value -is [pscustomobject] -and (Test-HasProperty $Target $property.Name) -and $Target.($property.Name) -is [pscustomobject]) {
            Merge-Patch $Target.($property.Name) $property.Value
        }
        else {
            Set-Field $Target $property.Name (Copy-Value $property.Value)
        }
    }
}

function Get-PatchLeaves {
    param([object]$Patch, [string]$Prefix = '')
    # Leaves name every field a merge patch replaces, so overlapping overrides can be detected.
    $leaves = [System.Collections.Generic.List[string]]::new()
    foreach ($property in $Patch.PSObject.Properties) {
        $path = "$Prefix/$($property.Name)"
        if ($property.Value -is [pscustomobject]) { foreach ($leaf in (Get-PatchLeaves $property.Value $path)) { $leaves.Add($leaf) } }
        else { $leaves.Add($path) }
    }
    return ,$leaves.ToArray()
}

function Get-ReleaseIndex {
    param([string]$Name, [string]$Context)
    if (-not $releaseIndex.ContainsKey($Name)) { throw "$Context names release $Name, which releases.json does not list." }
    return $releaseIndex[$Name]
}

function Get-Bounds {
    param([object]$Range, [string]$Context)
    # Half-open bounds in releases.json order; a missing bound is open.
    $lower = 0
    $upper = $releaseIndex.Count
    if (Test-HasProperty $Range 'since') { $lower = Get-ReleaseIndex ([string]$Range.since) $Context }
    if (Test-HasProperty $Range 'before') { $upper = Get-ReleaseIndex ([string]$Range.before) $Context }
    if ($lower -ge $upper) { throw "$Context has an empty release range." }
    return @($lower, $upper)
}

function Test-InRange {
    param([object]$Range, [int]$Index, [string]$Context)
    $bounds = Get-Bounds $Range $Context
    return $Index -ge $bounds[0] -and $Index -lt $bounds[1]
}

function Test-Available {
    param([object]$Record, [int]$Index, [string]$Context)
    if (-not (Test-HasProperty $Record 'availability')) { return $true }
    return Test-InRange $Record.availability.releases $Index $Context
}

function Assert-Overrides {
    param([object]$Record, [string]$Context)
    # Overrides describe other releases than the surface and never edit one field twice for one release.
    if (-not (Test-HasProperty $Record 'overrides')) { return }
    $overrides = @($Record.overrides)
    for ($first = 0; $first -lt $overrides.Count; $first++) {
        $bounds = Get-Bounds $overrides[$first].releases "$Context override $($first + 1)"
        if ($surfaceIndex -ge $bounds[0] -and $surfaceIndex -lt $bounds[1]) {
            throw "$Context override $($first + 1) covers the surface release $surface; edit the record itself instead."
        }
        for ($second = $first + 1; $second -lt $overrides.Count; $second++) {
            $other = Get-Bounds $overrides[$second].releases "$Context override $($second + 1)"
            if ($bounds[0] -lt $other[1] -and $other[0] -lt $bounds[1]) {
                $shared = @(Get-PatchLeaves $overrides[$first].patch | Where-Object { (Get-PatchLeaves $overrides[$second].patch) -ccontains $_ })
                $nested = @(Get-PatchLeaves $overrides[$first].patch | Where-Object { $leaf = $_; @(Get-PatchLeaves $overrides[$second].patch | Where-Object { $_.StartsWith($leaf + '/') -or $leaf.StartsWith($_ + '/') }).Count -gt 0 })
                if ($shared.Count -gt 0 -or $nested.Count -gt 0) { throw "$Context overrides $($first + 1) and $($second + 1) edit $(@($shared + $nested)[0]) for overlapping releases." }
            }
        }
    }
}

function Invoke-Overrides {
    param([object]$Record, [string]$Context, [int]$Index)
    if (-not (Test-HasProperty $Record 'overrides')) { return }
    $number = 0
    foreach ($override in @($Record.overrides)) {
        $number++
        if (Test-InRange $override.releases $Index "$Context override $number") {
            Merge-Patch $Record $override.patch
            $report.overrides.Add("$Context with ``$($override.patch | ConvertTo-Json -Depth 20 -Compress)``")
        }
    }
}

function Format-Ids {
    param([object[]]$Ids)
    return (@($Ids | ForEach-Object { '`' + [string]$_ + '`' }) -join ', ')
}

function Remove-Annotations {
    param([object]$Record)
    foreach ($name in @('availability', 'overrides')) { if (Test-HasProperty $Record $name) { $Record.PSObject.Properties.Remove($name) } }
}

function Update-SchemaReleaseMarkers {
    param([object]$Node, [string]$Base, [string]$Target)
    # Rewrite release constants and identifying text, never documentation URL patterns.
    if ($Node -is [pscustomobject]) {
        foreach ($property in @($Node.PSObject.Properties)) {
            $value = $property.Value
            if ($property.Name -ceq 'matlabRelease' -and (Test-HasProperty $value 'const')) {
                if ([string]$value.const -cne $Base) { throw "Schema release constant '$($value.const)' does not match the surface release $Base." }
                $value.const = $Target
            }
            elseif ($property.Name -cin @('$id', 'title') -and $value -is [string]) { $property.Value = $value.Replace($Base, $Target) }
            elseif ($property.Name -ceq 'const' -and $value -is [string] -and $value -ceq $Base) { $property.Value = $Target }
            else { Update-SchemaReleaseMarkers $value $Base $Target }
        }
    }
    elseif ($Node -is [array]) {
        foreach ($item in $Node) { Update-SchemaReleaseMarkers $item $Base $Target }
    }
}

function Remove-SchemaAnnotations {
    param([string]$Name, [object]$Schema)
    # Projections are annotation-free, so their schemas describe the ledger format the tools already read.
    $remove = { param($Object, [string[]]$Fields) foreach ($field in $Fields) { if (Test-HasProperty $Object $field) { $Object.PSObject.Properties.Remove($field) } } }
    if ($Name -ceq 'schema.json') {
        & $remove $Schema.properties @('availability', 'overrides')
        & $remove $Schema.'$defs'.property.properties @('availability', 'overrides')
        & $remove $Schema.'$defs'.valueContract.properties @('valueAvailability')
        & $remove $Schema.'$defs' @('releaseName', 'releaseRange', 'releaseEvidence', 'availability', 'override')
    }
    elseif ($Name -ceq 'runtime-component-metadata.schema.json') {
        & $remove $Schema.properties.factories.items.properties @('overrides')
    }
}

function Assert-PathReferences {
    param([object]$Document, [string[]]$Removed)
    # Value constraints and peer properties must not name a path the release lacks.
    foreach ($property in @($Document.properties)) {
        $contract = $property.valueContract
        foreach ($constraint in @(if (Test-HasProperty $contract 'constraints') { $contract.constraints })) {
            if ((Test-HasProperty $constraint 'property') -and $Removed -ccontains [string]$constraint.property) {
                throw "$($Document.id).$($property.path) constrains on unavailable $($constraint.property) in $Release; add an override."
            }
        }
        if ((Test-HasProperty $contract 'multiselectProperty') -and $Removed -ccontains [string]$contract.multiselectProperty) {
            throw "$($Document.id).$($property.path) depends on unavailable $($contract.multiselectProperty) in $Release; add an override."
        }
    }
}

# Resolve the release list, the surface ledger, and the target.
$releasesPath = Join-Path $ToolDirectory 'releases.json'
$releasesText = [IO.File]::ReadAllText($releasesPath)
if (-not (Test-Json -Json $releasesText -Schema ([IO.File]::ReadAllText((Join-Path $ToolDirectory 'releases.schema.json'))) -ErrorAction SilentlyContinue)) {
    throw "releases.json does not satisfy releases.schema.json."
}
$releases = $releasesText | ConvertFrom-Json
$releaseIndex = @{}
$position = 0
foreach ($entry in @($releases.releases)) {
    if ($releaseIndex.ContainsKey([string]$entry.release)) { throw "releases.json lists $($entry.release) twice." }
    $releaseIndex[[string]$entry.release] = $position++
}
$names = @($releases.releases | ForEach-Object { [string]$_.release })
if (($names -join ',') -cne ((@($names | Sort-Object)) -join ',')) { throw 'releases.json must list releases in chronological order.' }
$surface = [string]$releases.surfaceRelease
$audited = @($releases.releases | Where-Object status -CEQ 'audited')
if ($audited.Count -ne 1 -or [string]$audited[0].release -cne $surface) { throw 'releases.json must mark exactly the surface release as audited.' }
$target = @($releases.releases | Where-Object release -CEQ $Release)
if ($target.Count -ne 1) { throw "releases.json does not list $Release." }
if ([string]$target[0].status -ceq 'known') { throw "$Release is only known from release notes; verify it before generating its catalog." }
$surfaceIndex = $releaseIndex[$surface]
$targetIndex = $releaseIndex[$Release]
$ledgerPath = Join-Path $ToolDirectory $surface
Assert-ComponentLedgerSchema -ReleaseDirectory $ledgerPath

# Refuse to overwrite a ledger in the tool directory.
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
if ($outputPath.StartsWith([IO.Path]::GetFullPath($ToolDirectory), [StringComparison]::OrdinalIgnoreCase)) {
    throw "Projections are generated outside $ToolDirectory."
}
if ((Split-Path -Leaf $outputPath) -cne $Release) { throw "The projection directory must be named $Release so the grouping tools read its release." }
if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Recurse -Force }

$report = [ordered]@{
    variants = [System.Collections.Generic.List[string]]::new()
    properties = [System.Collections.Generic.List[string]]::new()
    values = [System.Collections.Generic.List[string]]::new()
    overrides = [System.Collections.Generic.List[string]]::new()
    derived = [System.Collections.Generic.List[string]]::new()
}

# Read inputs and component documents, and validate every annotation before projecting.
$inputs = @{}
$originals = @{}
foreach ($name in $inputFiles) {
    $inputs[$name] = Read-Json (Join-Path $ledgerPath $name)
    $originals[$name] = $inputs[$name] | ConvertTo-Json -Depth 100 -Compress
}
$components = [ordered]@{}
foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $ledgerPath 'components') -Filter '*.json' -File | Sort-Object Name)) {
    $document = Read-Json $file.FullName
    $components[[string]$document.id] = $document
    $originals["components/$($document.id).json"] = $document | ConvertTo-Json -Depth 100 -Compress
}
foreach ($document in $components.Values) {
    $context = [string]$document.id
    Assert-Overrides $document $context
    $variantBounds = @(0, $releaseIndex.Count)
    if (Test-HasProperty $document 'availability') { $variantBounds = Get-Bounds $document.availability.releases $context }
    foreach ($property in @($document.properties)) {
        $propertyContext = "$context.$($property.path)"
        Assert-Overrides $property $propertyContext
        if (Test-HasProperty $property 'availability') {
            $bounds = Get-Bounds $property.availability.releases $propertyContext
            if ($bounds[0] -lt $variantBounds[0] -or $bounds[1] -gt $variantBounds[1]) {
                throw "$propertyContext is available outside the releases of its variant."
            }
        }
        if (Test-HasProperty $property.valueContract 'valueAvailability') {
            foreach ($value in @($property.valueContract.valueAvailability)) {
                if (@($property.valueContract.values) -cnotcontains [string]$value.value) { throw "$propertyContext annotates unknown value '$($value.value)'." }
                [void](Get-Bounds $value.releases "$propertyContext value '$($value.value)'")
            }
        }
    }
}
foreach ($entry in @($inputs['runtime-component-metadata.json'].factories)) { Assert-Overrides $entry "runtime metadata $($entry.factory)" }

# Apply the overrides of the target release before anything is removed.
foreach ($document in $components.Values) {
    Invoke-Overrides $document ([string]$document.id) $targetIndex
    foreach ($property in @($document.properties)) { Invoke-Overrides $property "$($document.id).$($property.path)" $targetIndex }
}
foreach ($entry in @($inputs['runtime-component-metadata.json'].factories)) { Invoke-Overrides $entry "runtime metadata $($entry.factory)" $targetIndex }

# Remove unavailable enum values and properties, then derive dependent edits within each variant.
$removedPaths = @{}
foreach ($document in $components.Values) {
    $id = [string]$document.id
    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($property in @($document.properties)) {
        $contract = $property.valueContract
        if (Test-HasProperty $contract 'valueAvailability') {
            $absent = @($contract.valueAvailability | Where-Object { -not (Test-InRange $_.releases $targetIndex "$id.$($property.path)") } | ForEach-Object { [string]$_.value })
            if ($absent.Count -gt 0) {
                $contract.values = @($contract.values | Where-Object { $absent -cnotcontains [string]$_ })
                $report.values.Add("``$id.$($property.path)``: $(Format-Ids $absent)")
            }
            $contract.PSObject.Properties.Remove('valueAvailability')
        }
        if (-not (Test-Available $property $targetIndex "$id.$($property.path)")) { $removed.Add([string]$property.path) }
    }
    if ($removed.Count -eq 0) { $removedPaths[$id] = @(); continue }
    $removedPaths[$id] = @($removed)
    $report.properties.Add("``$id``: $(Format-Ids $removed)")
    $document.properties = @($document.properties | Where-Object { $removed -cnotcontains [string]$_.path })
    foreach ($property in @($document.properties)) {
        if (-not (Test-HasProperty $property 'application')) { continue }
        foreach ($field in @('applyAfter', 'affectedPaths')) {
            if (-not (Test-HasProperty $property.application $field)) { continue }
            $before = @($property.application.$field)
            $kept = @($before | Where-Object { $removed -cnotcontains [string]$_ })
            if ($kept.Count -ne $before.Count) {
                $property.application.$field = $kept
                $report.derived.Add("Dropped unavailable paths from ``$id.$($property.path)`` application $field.")
            }
        }
    }
    Assert-PathReferences $document @($removed)

    # Categories keep contiguous orders, and a category without properties leaves the variant.
    $categories = @($document.documentationCategories | Sort-Object { [int]$_.order })
    $keptCategories = [System.Collections.Generic.List[object]]::new()
    foreach ($category in $categories) {
        $members = @($document.properties | Where-Object { [string]$_.categoryId -ceq [string]$category.id } | Sort-Object { [int]$_.order })
        if ($members.Count -eq 0) {
            $report.derived.Add("Dropped emptied category ``$($category.id)`` from ``$id``.")
            continue
        }
        $order = 0
        foreach ($member in $members) { $order++; $member.order = $order }
        $keptCategories.Add($category)
    }
    $order = 0
    foreach ($category in $keptCategories) { $order++; $category.order = $order }
    $document.documentationCategories = @($keptCategories.ToArray())
}

# Remove unavailable variants and their styles, factories, shared subsets, and Inspector-row targets.
$metadata = $inputs['runtime-component-metadata.json']
foreach ($id in @($components.Keys)) {
    $document = $components[$id]
    if (Test-Available $document $targetIndex $id) { continue }
    $components.Remove($id)
    $report.variants.Add("``$id``")
    $factory = [string]$document.factory
    $entry = @($metadata.factories | Where-Object factory -CEQ $factory)
    if ($entry.Count -ne 1) { throw "$id has no single runtime metadata entry for factory $factory." }
    $entry = $entry[0]
    if (@($components.Values | Where-Object { [string]$_.factory -ceq $factory }).Count -eq 0) {
        $metadata.factories = @($metadata.factories | Where-Object factory -CNE $factory)
        $report.derived.Add("Dropped runtime metadata of factory ``$factory``.")
        continue
    }
    if (@($document.creationArguments).Count -eq 0) { throw "$id is the default variant of $factory and other variants remain in $Release; override the runtime metadata." }
    $style = [string]@($document.creationArguments)[0]
    $capabilities = $entry.capabilities
    if ((Test-HasProperty $capabilities 'defaultStyle') -and [string]$capabilities.defaultStyle -ceq $style) {
        throw "$id is the default style of $factory in $Release; override the runtime metadata."
    }
    if (Test-HasProperty $capabilities 'supportedStyles') { $capabilities.supportedStyles = @($capabilities.supportedStyles | Where-Object { [string]$_ -cne $style }) }
    if ((Test-HasProperty $capabilities 'declaredTypesByStyle') -and (Test-HasProperty $capabilities.declaredTypesByStyle $style)) { $capabilities.declaredTypesByStyle.PSObject.Properties.Remove($style) }
    if ((Test-HasProperty $entry 'variantCapabilities') -and (Test-HasProperty $entry.variantCapabilities $id)) {
        $entry.variantCapabilities.PSObject.Properties.Remove($id)
        if (@($entry.variantCapabilities.PSObject.Properties).Count -eq 0) { $entry.PSObject.Properties.Remove('variantCapabilities') }
    }
    $report.derived.Add("Dropped style ``$style`` of factory ``$factory``.")
}
foreach ($entry in @($metadata.factories)) { Remove-Annotations $entry }

$hasPath = { param($VariantId, $Path) $components.Contains($VariantId) -and @($components[$VariantId].properties | Where-Object { [string]$_.path -ceq $Path }).Count -gt 0 }
$design = $inputs['grouping-design-input.json']
$subsets = [System.Collections.Generic.List[object]]::new()
foreach ($subset in @($design.sharedSubsetDefinitions)) {
    $members = @($subset.memberVariantIds | Where-Object { $variantId = [string]$_; @($subset.propertyPaths | Where-Object { -not (& $hasPath $variantId ([string]$_)) }).Count -eq 0 })
    if ($members.Count -lt 2) {
        $report.derived.Add("Dropped shared subset ``$($subset.id)``, which keeps fewer than two members.")
        continue
    }
    $dropped = @($subset.memberVariantIds | Where-Object { $members -cnotcontains [string]$_ })
    if ($dropped.Count -gt 0) { $report.derived.Add("Shared subset ``$($subset.id)`` drops members $(Format-Ids $dropped).") }
    if ($members -cnotcontains [string]$subset.sourceVariantId) {
        $report.derived.Add("Shared subset ``$($subset.id)`` takes ``$($members[0])`` as its source; members share identical records.")
        $subset.sourceVariantId = [string]$members[0]
    }
    $subset.memberVariantIds = $members
    $subsets.Add($subset)
}
$design.sharedSubsetDefinitions = @($subsets.ToArray())

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($row in @($inputs['inspector-rows.json'].rows)) {
    $paths = @($row.members | ForEach-Object { [string]$_.path })
    $ids = @($row.match.componentIds)
    if ($ids.Count -gt 0) {
        $kept = @($ids | Where-Object { $variantId = [string]$_; @($paths | Where-Object { -not (& $hasPath $variantId $_) }).Count -eq 0 })
        if ($kept.Count -eq 0) { $report.derived.Add("Dropped Inspector row ``$($row.id)``, whose members no target variant has."); continue }
        $dropped = @($ids | Where-Object { $kept -cnotcontains [string]$_ })
        if ($dropped.Count -gt 0) { $report.derived.Add("Inspector row ``$($row.id)`` drops targets $(Format-Ids $dropped).") }
        $row.match.componentIds = $kept
    }
    $rows.Add($row)
}
$inputs['inspector-rows.json'].rows = @($rows.ToArray())

$used = @($components.Values | ForEach-Object { @($_.documentationCategories) | ForEach-Object { [string]$_.id } } | Sort-Object -Unique)
$classification = $inputs['category-scope-classification.json']
$unused = @($classification.categories | Where-Object { $used -cnotcontains [string]$_.id } | ForEach-Object { [string]$_.id })
if ($unused.Count -gt 0) {
    $classification.categories = @($classification.categories | Where-Object { $used -ccontains [string]$_.id })
    $report.derived.Add("Dropped scope classifications of categories no variant documents: $(Format-Ids $unused).")
}

# Strip annotations and move every release marker to the target release.
foreach ($document in $components.Values) {
    Remove-Annotations $document
    foreach ($property in @($document.properties)) { Remove-Annotations $property }
    $document.matlabRelease = $Release
}
foreach ($name in $inputFiles) {
    $value = $inputs[$name]
    if ($name -like '*schema.json') {
        Remove-SchemaAnnotations $name $value
        Update-SchemaReleaseMarkers $value $surface $Release
    }
    elseif (Test-HasProperty $value 'matlabRelease') { $value.matlabRelease = $Release }
}
$inputs['inspector-rows.json'].runtimeArtifact = ([string]$inputs['inspector-rows.json'].runtimeArtifact).Replace("/$surface/", "/$Release/")
# Copied records keep the documentation release where the ledger was audited, which can precede the surface.
$url = $inputs['schema.json'].'$defs'.source.properties.url
$documented = [regex]::Match([string]$url.pattern, 'releases/(r[0-9]{4}[ab])/').Groups[1].Value
if (-not $documented) { throw 'The ledger schema does not name a release-fixed documentation URL pattern.' }
$documentedRelease = 'R' + $documented.Substring(1)
if ($Release -cne $documentedRelease) {
    $url.pattern = '^https://www\.mathworks\.com/help/releases/(' + $documented + '|' + $Release.ToLowerInvariant() + ')/'
    $url.description = "Must be a release-fixed MathWorks documentation URL of $documentedRelease, where the surface ledger was audited, or of $Release."
}

# Write the projection; unchanged files keep their source bytes so the surface projection reproduces the ledger exactly.
$writeRecord = {
    param([string]$Relative, [object]$Value)
    $destination = Join-Path $outputPath $Relative
    if (($Value | ConvertTo-Json -Depth 100 -Compress) -ceq $originals[$Relative]) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $ledgerPath $Relative) -Destination $destination
    }
    else { Write-Json $destination $Value }
}
foreach ($name in $inputFiles) { & $writeRecord $name $inputs[$name] }
foreach ($id in $components.Keys) { & $writeRecord "components/$id.json" $components[$id] }
Assert-ComponentLedgerSchema -ReleaseDirectory $outputPath

$section = { param($Title, $Items) @("## $Title", '') + @(if ($Items.Count -eq 0) { '- None.' } else { $Items | ForEach-Object { "- $_" } }) + @('') }
$lines = @(
    "# $Release projection of the $surface ledger",
    '',
    "Generated by ``dev/component-data/ProjectReleaseLedger.ps1``. Do not edit; change availability or overrides in the $surface ledger and regenerate.",
    ''
) + (& $section 'Unavailable variants' $report.variants) + (& $section 'Unavailable properties' $report.properties) +
    (& $section 'Unavailable values' $report.values) + (& $section 'Applied overrides' $report.overrides) + (& $section 'Derived edits' $report.derived)
[IO.File]::WriteAllText((Join-Path $outputPath 'PROJECTION.md'), ($lines -join [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
"Projected $surface onto $Release with $($components.Count) variants."

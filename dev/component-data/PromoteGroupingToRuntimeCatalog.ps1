<#
.SYNOPSIS
Promotes one audited grouping design into the runtime component catalog.

.DESCRIPTION
Builds the version 2 runtime catalog from the release-fixed component ledger,
its Step 7-11 grouping artifact, and reviewed runtime construction metadata.
The generated catalog contains concrete component variants, reusable property
groups, official category ordering, and the non-executable property capability
metadata consumed by the catalog loader. It deliberately does not infer editor
implementation support.

.EXAMPLE
./PromoteGroupingToRuntimeCatalog.ps1 -ReleaseDirectory ./R2024a -CatalogRoot ../../resources/component-catalog/v2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$ReleaseDirectory,

    [Parameter(Mandatory = $true)]
    [string]$CatalogRoot,

    [Parameter()]
    [string]$RuntimeMetadataPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Utf8JsonFile {
    param([string]$Path, [object]$Value)

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $text = ($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

function Get-PropertyMetadata {
    param([object]$Capability, [object]$SourceProperty, [object]$Category, [int]$Order, [string]$GroupId)

    $editor = [string]$Capability.requiredEditor
    if ($editor -eq "none") { $editor = "readOnly" }
    $constraints = @($Capability.valueContract.constraints | ForEach-Object {
        $constraint = [ordered]@{ kind = [string]$_.kind }
        if ($null -ne $_.PSObject.Properties["property"]) {
            $constraint.property = [string]$_.property
        }
        $constraint
    })
    $valueSchema = [ordered]@{
        kind = [string]$Capability.valueContract.kind
        matlabClasses = @($Capability.valueContract.matlabClasses | ForEach-Object { [string]$_ })
        shape = [string]$Capability.valueContract.shape
        allowsEmpty = [bool]$Capability.valueContract.allowsEmpty
        constraints = $constraints
    }
    if ($null -ne $Capability.valueContract.PSObject.Properties["values"]) {
        $valueSchema.values = @($Capability.valueContract.values | ForEach-Object { [string]$_ })
    }
    if ($null -ne $Capability.valueContract.PSObject.Properties["fixedLength"]) {
        $valueSchema.fixedLength = [int]$Capability.valueContract.fixedLength
    }
    if ($null -ne $Capability.valueContract.PSObject.Properties["orientation"]) {
        $valueSchema.orientation = [string]$Capability.valueContract.orientation
    }
    if ($null -ne $Capability.valueContract.PSObject.Properties["allowsNaT"]) {
        $valueSchema.allowsNaT = [bool]$Capability.valueContract.allowsNaT
    }
    if ($null -ne $Capability.valueContract.PSObject.Properties["normalization"]) {
        $valueSchema.normalization = [string]$Capability.valueContract.normalization
    }
    if ($null -ne $Capability.valueContract.PSObject.Properties["multiselectProperty"]) {
        $valueSchema.multiselectProperty = [string]$Capability.valueContract.multiselectProperty
    }
    foreach ($name in @("minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "integer", "allowsInfinity")) {
        if ($null -ne $Capability.valueContract.PSObject.Properties[$name]) {
            $valueSchema[$name] = $Capability.valueContract.$name
        }
    }
    return [ordered]@{
        displayName = [string]$SourceProperty.path
        description = [string]$SourceProperty.summary
        categoryId = [string]$Category.id
        category = [string]$Category.displayName
        order = $Order
        groupId = $GroupId
        editor = $editor
        previewPolicy = [string]$Capability.previewPolicy
        auditDisposition = [string]$Capability.disposition.kind
        valueSchema = $valueSchema
    }
}

$releasePath = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$catalogPath = [IO.Path]::GetFullPath($CatalogRoot)
$designPath = Join-Path $releasePath "grouping/GROUPING_DESIGN.json"
$groupingInputPath = Join-Path $releasePath "grouping-design-input.json"
$componentPath = Join-Path $releasePath "components"
$inspectorRowsPath = Join-Path $releasePath "inspector-rows.json"
$parentContextPath = Join-Path $releasePath "parent-context-rules.json"
if ([string]::IsNullOrWhiteSpace($RuntimeMetadataPath)) {
    $RuntimeMetadataPath = Join-Path $releasePath "runtime-component-metadata.json"
}
$runtimeMetadataPath = [IO.Path]::GetFullPath($RuntimeMetadataPath)

foreach ($path in @($designPath, $groupingInputPath, $componentPath,
        $parentContextPath, $runtimeMetadataPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required promotion input '$path' does not exist." }
}

$design = Get-Content -Raw -LiteralPath $designPath | ConvertFrom-Json
$groupingInput = Get-Content -Raw -LiteralPath $groupingInputPath | ConvertFrom-Json
$parentContextDocument = Get-Content -Raw -LiteralPath $parentContextPath | ConvertFrom-Json
$runtimeMetadata = Get-Content -Raw -LiteralPath $runtimeMetadataPath | ConvertFrom-Json
$documents = @{}
foreach ($file in @(Get-ChildItem -LiteralPath $componentPath -Filter '*.json' -File)) {
    $document = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    $documents[[string]$document.id] = $document
}

# Validate the release-owned construction and palette metadata before promotion.
if ([int]$runtimeMetadata.schemaVersion -ne 1 -or
        [string]$runtimeMetadata.matlabRelease -ne [string]$design.matlabRelease) {
    throw "Runtime component metadata must use schema version 1 and match the grouping release."
}
$metadataByFactory = @{}
foreach ($entry in @($runtimeMetadata.factories)) {
    $factory = [string]$entry.factory
    if ([string]::IsNullOrWhiteSpace($factory)) {
        throw "Runtime component metadata contains an empty factory."
    }
    if ($metadataByFactory.ContainsKey($factory)) {
        throw "Runtime component metadata contains duplicate factory '$factory'."
    }
    foreach ($requiredField in @("allowedParentFactories", "isRoot", "capabilities")) {
        if ($null -eq $entry.PSObject.Properties[$requiredField]) {
            throw "Runtime component metadata for '$factory' is missing '$requiredField'."
        }
    }
    $metadataByFactory[$factory] = $entry
}

if (Test-Path -LiteralPath $catalogPath) {
    Remove-Item -LiteralPath $catalogPath -Recurse -Force
}

# Write every reusable group exactly once; category placement remains variant-owned.
$runtimeGroups = @()
foreach ($group in @($design.groups | Sort-Object id)) {
    $runtimeGroups += [ordered]@{
        id = [string]$group.id
        kind = [string]$group.kind
        categoryId = [string]$group.categoryId
        entries = @($group.capabilities | ForEach-Object {
            [ordered]@{
                path = [string]$_.path
                valueContract = $_.valueContract
                affectsDisplay = [bool]$_.affectsDisplay
                previewPolicy = [string]$_.previewPolicy
                requiredEditor = [string]$_.requiredEditor
                disposition = $_.disposition
            }
        })
    }
}
Write-Utf8JsonFile (Join-Path $catalogPath "property-groups/groups.json") ([ordered]@{
    artifactVersion = 1
    matlabRelease = [string]$design.matlabRelease
    inputSha256 = [string]$design.inputSha256
    groups = $runtimeGroups
})
Write-Utf8JsonFile (Join-Path $catalogPath "order-profiles.json") ([ordered]@{
    artifactVersion = 1
    matlabRelease = [string]$design.matlabRelease
    profiles = @($groupingInput.profileDefinitions | ForEach-Object {
        [ordered]@{ id = [string]$_.id; categoryOrder = @($_.categoryOrder | ForEach-Object { [string]$_ }) }
    })
})

# Inspector rows are presentation overlays, not grouping-derived property
# capabilities. Preserve their separately reviewed release artifact verbatim.
$inspectorRowFiles = @()
if (Test-Path -LiteralPath $inspectorRowsPath -PathType Leaf) {
    $inspectorRowsText = [IO.File]::ReadAllText($inspectorRowsPath)
    $inspectorRowsText = [regex]::Replace($inspectorRowsText, '(?m)^\s*"runtimeArtifact"\s*:\s*"[^"]+",\s*\r?\n', '')
    [IO.File]::WriteAllText((Join-Path $catalogPath "inspector-rows.json"), $inspectorRowsText, [Text.UTF8Encoding]::new($false))
    $inspectorRowFiles = @("inspector-rows.json")
}

$componentFiles = @()
foreach ($componentId in @($documents.Keys | Sort-Object)) {
    $source = $documents[$componentId]
    $factory = [string]$source.factory
    if (-not $metadataByFactory.ContainsKey($factory)) {
        throw "Runtime component metadata has no construction definition for '$factory'."
    }
    $runtime = $metadataByFactory[$factory]
    $profile = @($design.profileAssignments | Where-Object componentId -eq $componentId)
    if ($profile.Count -ne 1) { throw "Grouping design has no unique profile for '$componentId'." }
    $declaredType = [string]$source.declaredType
    if ([string]::IsNullOrWhiteSpace($declaredType)) {
        throw "The audited component '$componentId' has no declared type."
    }

    $categories = @()
    foreach ($mapping in @($design.categoryMappings | Where-Object componentId -eq $componentId | Sort-Object documentedOrder)) {
        $category = @($source.documentationCategories | Where-Object id -eq $mapping.categoryId)
        if ($category.Count -ne 1) { throw "'$componentId' has no unique category '$($mapping.categoryId)'." }
        $entries = @()
        $order = 0
        foreach ($owner in @($mapping.propertyOwners)) {
            $order++
            $group = @($design.groups | Where-Object id -eq $owner.groupId)
            if ($group.Count -ne 1) { throw "'$componentId.$($owner.path)' has no unique group '$($owner.groupId)'." }
            $capability = @($group[0].capabilities | Where-Object path -eq $owner.path)
            $sourceProperty = @($source.properties | Where-Object path -eq $owner.path)
            if ($capability.Count -ne 1 -or $sourceProperty.Count -ne 1) {
                throw "'$componentId.$($owner.path)' cannot be promoted from its group."
            }
            $entries += [ordered]@{
                path = [string]$owner.path
                groupId = [string]$owner.groupId
                runtimeSetAccess = [string]$owner.runtimeSetAccess
                metadata = Get-PropertyMetadata $capability[0] $sourceProperty[0] $category[0] $order ([string]$owner.groupId)
            }
        }
        $categories += [ordered]@{
            id = [string]$category[0].id
            displayName = [string]$category[0].displayName
            order = [int]$mapping.documentedOrder
            entries = $entries
        }
    }

    $relativePath = "components/$componentId.json"
    $componentFiles += $relativePath
    Write-Utf8JsonFile (Join-Path $catalogPath $relativePath) ([ordered]@{
        id = $componentId
        factory = $factory
        declaredType = $declaredType
        allowedParentFactories = @($runtime.allowedParentFactories | ForEach-Object { [string]$_ })
        isRoot = [bool]$runtime.isRoot
        creationArguments = @($source.creationArguments)
        profileId = [string]$profile[0].profileId
        profileDelta = [ordered]@{
            omittedCategoryIds = @($profile[0].omittedCategoryIds | ForEach-Object { [string]$_ })
            insertions = @($profile[0].insertions | ForEach-Object {
                [ordered]@{ categoryId = [string]$_.categoryId; documentedOrder = [int]$_.documentedOrder; afterCategoryId = [string]$_.afterCategoryId; beforeCategoryId = [string]$_.beforeCategoryId }
            })
        }
        categories = $categories
        capabilities = $runtime.capabilities
    })
}

# Position is intrinsic in the audited v2 ledger; absolute parents only suppress grid fields.
$contextOrder = @{ grid = 1; absolute = 2; structural = 3 }
$parentContextRules = @($parentContextDocument.contexts |
    Sort-Object { $contextOrder[[string]$_.id] } |
    ForEach-Object {
        $kind = switch ([string]$_.id) {
            "grid" { "grid" }
            "absolute" { "absoluteIntrinsic" }
            "structural" { "structural" }
            default { throw "Unsupported parent context '$($_.id)'." }
        }
        [ordered]@{
            parentFactories = @($_.parentFactories | ForEach-Object { [string]$_ })
            kind = $kind
        }
    })
Write-Utf8JsonFile (Join-Path $catalogPath "catalog.json") ([ordered]@{
    schemaVersion = 2
    matlabRelease = [string]$design.matlabRelease
    sourceGroupingSha256 = [string]$design.inputSha256
    propertyGroupFiles = @("property-groups/groups.json")
    orderProfileFiles = @("order-profiles.json")
    inspectorRowFiles = $inspectorRowFiles
    parentContextRules = $parentContextRules
    componentFiles = $componentFiles
})

<#
.SYNOPSIS
Builds Step 7 through Step 11 property-grouping design artifacts.

.DESCRIPTION
Reads a release component ledger and its reviewed grouping-design input,
derives category-order profile assignments and group ownership, and verifies
that the composed intrinsic and parent-context effective surfaces preserve the
audited capabilities.

.EXAMPLE
./GenerateGroupingDesign.ps1 -ReleaseDirectory ./R2024a
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$ReleaseDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Utf8File {
    param([string]$Path, [string]$Text)
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    Write-Utf8File $Path (($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine)
}

function Get-Hash {
    param([string]$Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return -join ($algorithm.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") })
    }
    finally {
        $algorithm.Dispose()
    }
}

function Get-PropertyCapability {
    param([object]$Property)
    return [ordered]@{
        path = [string]$Property.path
        valueContract = [ordered]@{
            kind = [string]$Property.valueContract.kind
            matlabClasses = @($Property.valueContract.matlabClasses | ForEach-Object { [string]$_ } | Sort-Object)
            shape = [string]$Property.valueContract.shape
            allowsEmpty = [bool]$Property.valueContract.allowsEmpty
            constraints = @($Property.valueContract.constraints | ForEach-Object {
                [ordered]@{ kind = [string]$_.kind; property = [string]$_.property }
            } | Sort-Object { "$($_.kind)`u{001F}$($_.property)" })
        }
        affectsDisplay = [bool]$Property.affectsDisplay
        previewPolicy = [string]$Property.previewPolicy
        requiredEditor = [string]$Property.requiredEditor
        disposition = [ordered]@{
            kind = [string]$Property.disposition.kind
            reasonCodes = @($Property.disposition.reasonCodes | ForEach-Object { [string]$_ } | Sort-Object)
        }
    }
}

function Get-CapabilityText {
    param([object]$Capability)
    return $Capability | ConvertTo-Json -Compress -Depth 100
}

function Get-LcsLength {
    param([string[]]$Left, [string[]]$Right)
    $matrix = New-Object 'int[,]' ($Left.Count + 1), ($Right.Count + 1)
    for ($leftIndex = 1; $leftIndex -le $Left.Count; $leftIndex++) {
        for ($rightIndex = 1; $rightIndex -le $Right.Count; $rightIndex++) {
            if ($Left[$leftIndex - 1] -eq $Right[$rightIndex - 1]) {
                $priorLeftIndex = $leftIndex - 1
                $priorRightIndex = $rightIndex - 1
                $matrix.SetValue($matrix.GetValue($priorLeftIndex, $priorRightIndex) + 1, $leftIndex, $rightIndex)
            }
            else {
                $priorLeftIndex = $leftIndex - 1
                $priorRightIndex = $rightIndex - 1
                $largest = [Math]::Max($matrix.GetValue($priorLeftIndex, $rightIndex), $matrix.GetValue($leftIndex, $priorRightIndex))
                $matrix.SetValue($largest, $leftIndex, $rightIndex)
            }
        }
    }
    return $matrix.GetValue($Left.Count, $Right.Count)
}

function Get-ProfileDelta {
    param([string[]]$ProfileOrder, [string[]]$VariantOrder)
    $omissions = @($ProfileOrder | Where-Object { $VariantOrder -notcontains $_ })
    $insertions = @()
    for ($index = 0; $index -lt $VariantOrder.Count; $index++) {
        $categoryId = $VariantOrder[$index]
        if ($ProfileOrder -contains $categoryId) { continue }
        $after = $null
        for ($prior = $index - 1; $prior -ge 0; $prior--) {
            if ($ProfileOrder -contains $VariantOrder[$prior]) { $after = $VariantOrder[$prior]; break }
        }
        $before = $null
        for ($next = $index + 1; $next -lt $VariantOrder.Count; $next++) {
            if ($ProfileOrder -contains $VariantOrder[$next]) { $before = $VariantOrder[$next]; break }
        }
        $insertions += [ordered]@{ categoryId = $categoryId; documentedOrder = $index + 1; afterCategoryId = $after; beforeCategoryId = $before }
    }
    return [ordered]@{ omittedCategoryIds = $omissions; insertions = $insertions }
}

$releasePath = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$release = Split-Path -Leaf $releasePath
$componentsPath = Join-Path $releasePath "components"
$inputPath = Join-Path $releasePath "grouping-design-input.json"
$inputSchemaPath = Join-Path $releasePath "grouping-design-input.schema.json"
$rulesPath = Join-Path $releasePath "parent-context-rules.json"
$outputPath = Join-Path $releasePath "grouping"

foreach ($path in @($componentsPath, $inputPath, $inputSchemaPath, $rulesPath, $outputPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required grouping-design path '$path' does not exist." }
}

try { $input = Get-Content -Raw -LiteralPath $inputPath | ConvertFrom-Json } catch { throw "Unable to parse '$inputPath': $($_.Exception.Message)" }
if ($input.schemaVersion -ne 1 -or [string]$input.matlabRelease -ne $release) { throw "Grouping-design input has an unexpected schema or release." }
if ([string]$input.'$schema' -ne 'grouping-design-input.schema.json') { throw "Grouping-design input has an unexpected schema reference." }
$profileIds = @($input.profileDefinitions | ForEach-Object { [string]$_.id })
if ($profileIds.Count -eq 0 -or $profileIds.Count -ne @($profileIds | Sort-Object -Unique).Count) { throw 'Grouping-design input must contain unique profile IDs.' }
foreach ($profile in @($input.profileDefinitions)) {
    $order = @($profile.categoryOrder | ForEach-Object { [string]$_ })
    if ($order.Count -eq 0 -or $order.Count -ne @($order | Sort-Object -Unique).Count) { throw "Profile '$($profile.id)' has an empty or duplicate category order." }
}
$subsetIds = @($input.sharedSubsetDefinitions | ForEach-Object { [string]$_.id })
if ($subsetIds.Count -ne @($subsetIds | Sort-Object -Unique).Count) { throw 'Grouping-design input has duplicate shared subset IDs.' }

$documents = @()
$documentsById = @{}
foreach ($file in @(Get-ChildItem -LiteralPath $componentsPath -Filter '*.json' -File | Sort-Object Name)) {
    $document = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    $documents += $document
    $documentsById[[string]$document.id] = $document
}
try { $parentRules = Get-Content -Raw -LiteralPath $rulesPath | ConvertFrom-Json } catch { throw "Unable to parse '$rulesPath': $($_.Exception.Message)" }

$inputDigestFiles = @((Get-ChildItem -LiteralPath $componentsPath -Filter '*.json' -File | Sort-Object Name).FullName + $inputPath + $inputSchemaPath + $rulesPath | Sort-Object)
$inputDigest = Get-Hash (($inputDigestFiles | ForEach-Object { "$($_.Substring($releasePath.Length + 1).Replace('\', '/')):$((Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant())" }) -join "`n")

# Build reusable subset groups and verify their declared source parity.
$groupsById = @{}
$specialByCategoryAndVariant = @{}
foreach ($definition in @($input.sharedSubsetDefinitions | Sort-Object id)) {
    foreach ($memberVariantId in @($definition.memberVariantIds | ForEach-Object { [string]$_ } | Sort-Object -Unique)) {
        if (-not $documentsById.ContainsKey($memberVariantId)) { throw "Shared subset '$($definition.id)' references unknown variant '$memberVariantId'." }
    }
    $source = $documentsById[[string]$definition.sourceVariantId]
    if ($null -eq $source) { throw "Shared subset '$($definition.id)' has unknown source variant '$($definition.sourceVariantId)'." }
    $sourceProperties = @($source.properties | Where-Object { $_.categoryId -eq $definition.categoryId } | Sort-Object order)
    $capabilities = @()
    foreach ($path in @($definition.propertyPaths)) {
        $property = @($sourceProperties | Where-Object path -eq $path)
        if ($property.Count -ne 1) { throw "Shared subset '$($definition.id)' source has no unique '$path' property." }
        $capabilities += Get-PropertyCapability $property[0]
    }
    $groupsById[[string]$definition.id] = [ordered]@{ id = [string]$definition.id; kind = 'sharedSubset'; categoryId = [string]$definition.categoryId; capabilities = $capabilities; memberVariantIds = @($definition.memberVariantIds | ForEach-Object { [string]$_ } | Sort-Object) }
    foreach ($memberVariantId in @($definition.memberVariantIds)) {
        $key = "$memberVariantId`u{001F}$($definition.categoryId)"
        if (-not $specialByCategoryAndVariant.ContainsKey($key)) { $specialByCategoryAndVariant[$key] = @() }
        $specialByCategoryAndVariant[$key] += $groupsById[[string]$definition.id]
    }
}

$categoryMappings = @()
foreach ($document in @($documents | Sort-Object id)) {
    foreach ($category in @($document.documentationCategories | Sort-Object order)) {
        $properties = @($document.properties | Where-Object { $_.categoryId -eq $category.id } | Sort-Object order)
        $capabilitiesByPath = @{}
        foreach ($property in $properties) { $capabilitiesByPath[[string]$property.path] = Get-PropertyCapability $property }
        $key = "$($document.id)`u{001F}$($category.id)"
        $specialGroups = @()
        if ($specialByCategoryAndVariant.ContainsKey($key)) { $specialGroups = @($specialByCategoryAndVariant[$key]) }
        $owners = @{}
        foreach ($specialGroup in $specialGroups) {
            foreach ($expected in @($specialGroup.capabilities)) {
                if (-not $capabilitiesByPath.ContainsKey($expected.path) -or (Get-CapabilityText $capabilitiesByPath[$expected.path]) -ne (Get-CapabilityText $expected)) {
                    throw "Shared subset '$($specialGroup.id)' does not exactly match '$($document.id).$($category.id).$($expected.path)'."
                }
                if ($owners.ContainsKey($expected.path)) { throw "Overlapping shared subsets own '$($document.id).$($category.id).$($expected.path)'." }
                $owners[$expected.path] = $specialGroup.id
            }
        }
        $residualCapabilities = @($properties | Where-Object { -not $owners.ContainsKey($_.path) } | ForEach-Object { Get-PropertyCapability $_ })
        if ($residualCapabilities.Count -gt 0) {
            $editableCount = @($residualCapabilities | Where-Object { $_.disposition.kind -eq 'editable' }).Count
            $capabilityHash = Get-Hash (($residualCapabilities | ConvertTo-Json -Compress -Depth 100))
            $sameResidualCount = 0
            foreach ($otherDocument in $documents) {
                $otherCategory = @($otherDocument.documentationCategories | Where-Object id -eq $category.id)
                if ($otherCategory.Count -ne 1) { continue }
                $otherProperties = @($otherDocument.properties | Where-Object { $_.categoryId -eq $category.id } | Sort-Object order)
                $otherCapabilities = @($otherProperties | ForEach-Object { Get-PropertyCapability $_ })
                if ((Get-Hash (($otherCapabilities | ConvertTo-Json -Compress -Depth 100))) -eq $capabilityHash) { $sameResidualCount++ }
            }
            $groupId = if ($specialGroups.Count -eq 0 -and $sameResidualCount -ge 2 -and $editableCount -ge 2) { "exact.$($category.id).$($capabilityHash.Substring(0, 12))" } else { "local.$($document.id).$($category.id)" }
            if (-not $groupsById.ContainsKey($groupId)) {
                $groupsById[$groupId] = [ordered]@{ id = $groupId; kind = if ($groupId.StartsWith('exact.')) { 'exactCategory' } else { 'variantLocal' }; categoryId = [string]$category.id; capabilities = $residualCapabilities; memberVariantIds = @([string]$document.id) }
            }
            elseif ($groupsById[$groupId].kind -eq 'exactCategory') {
                $groupsById[$groupId].memberVariantIds = @($groupsById[$groupId].memberVariantIds + [string]$document.id | Sort-Object -Unique)
            }
            foreach ($capability in $residualCapabilities) { $owners[$capability.path] = $groupId }
        }
        $propertyOwners = @($properties | ForEach-Object { [ordered]@{ path = [string]$_.path; groupId = [string]$owners[$_.path]; runtimeSetAccess = [string]$_.runtimeSetAccess } })
        $categoryMappings += [ordered]@{ componentId = [string]$document.id; categoryId = [string]$category.id; documentedOrder = [int]$category.order; propertyOrder = @($properties | ForEach-Object { [string]$_.path }); propertyOwners = $propertyOwners }
    }
}

# Select the closest reusable category-order profile and record exact deltas.
$profiles = @($input.profileDefinitions | Sort-Object id)
$profileAssignments = @()
foreach ($document in @($documents | Sort-Object id)) {
    $variantOrder = @($document.documentationCategories | Sort-Object order | ForEach-Object { [string]$_.id })
    $ranked = @($profiles | ForEach-Object {
        $profile = $_
        [pscustomobject]@{ profile = $profile; lcs = Get-LcsLength @($profile.categoryOrder) $variantOrder; additions = @($variantOrder | Where-Object { $_ -notin $profile.categoryOrder }).Count; omissions = @($profile.categoryOrder | Where-Object { $_ -notin $variantOrder }).Count }
    } | Sort-Object @{ Expression = 'lcs'; Descending = $true }, omissions, additions, @{ Expression = { $_.profile.id }; Descending = $false })
    $selected = $ranked[0].profile
    $delta = Get-ProfileDelta @($selected.categoryOrder) $variantOrder
    $profileAssignments += [ordered]@{ componentId = [string]$document.id; profileId = [string]$selected.id; effectiveCategoryOrder = $variantOrder; omittedCategoryIds = $delta.omittedCategoryIds; insertions = $delta.insertions }
}

# Expand each category mapping and prove every intrinsic capability is preserved exactly.
$intrinsicParity = @()
foreach ($document in @($documents | Sort-Object id)) {
    $expected = @($document.properties | ForEach-Object { Get-PropertyCapability $_ })
    $actual = @()
    $runtimeAccessByPath = @{}
    foreach ($mapping in @($categoryMappings | Where-Object componentId -eq $document.id | Sort-Object documentedOrder)) {
        foreach ($owner in @($mapping.propertyOwners)) {
            $matches = @($groupsById[$owner.groupId].capabilities | Where-Object path -eq $owner.path)
            if ($matches.Count -ne 1) { throw "Group '$($owner.groupId)' cannot resolve '$($document.id).$($owner.path)'." }
            $actual += $matches[0]
            $runtimeAccessByPath[$owner.path] = [string]$owner.runtimeSetAccess
        }
    }
    $expectedByPath = @{}; $actualByPath = @{}
    foreach ($capability in $expected) { $expectedByPath[$capability.path] = Get-CapabilityText $capability }
    foreach ($capability in $actual) { if ($actualByPath.ContainsKey($capability.path)) { throw "Expansion duplicates '$($document.id).$($capability.path)'." }; $actualByPath[$capability.path] = Get-CapabilityText $capability }
    $missing = @($expectedByPath.Keys | Where-Object { -not $actualByPath.ContainsKey($_) } | Sort-Object)
    $extra = @($actualByPath.Keys | Where-Object { -not $expectedByPath.ContainsKey($_) } | Sort-Object)
    $changed = @($expectedByPath.Keys | Where-Object { $actualByPath.ContainsKey($_) -and $expectedByPath[$_] -ne $actualByPath[$_] } | Sort-Object)
    $changedRuntimeAccess = @($document.properties | Where-Object { $runtimeAccessByPath[[string]$_.path] -ne [string]$_.runtimeSetAccess } | ForEach-Object path | Sort-Object)
    $intrinsicParity += [ordered]@{ componentId = [string]$document.id; passed = ($missing.Count -eq 0 -and $extra.Count -eq 0 -and $changed.Count -eq 0 -and $changedRuntimeAccess.Count -eq 0); missingPaths = $missing; extraPaths = $extra; changedCapabilityPaths = $changed; changedRuntimeSetAccessPaths = $changedRuntimeAccess }
}

# Apply every parent-context rule as a hypothetical eligible direct-child context.
$effectiveParity = @()
foreach ($document in @($documents | Sort-Object id)) {
    $intrinsic = @($document.properties | ForEach-Object { Get-PropertyCapability $_ })
    foreach ($context in @($parentRules.contexts | Sort-Object id)) {
        $effective = @($intrinsic)
        foreach ($rule in @($parentRules.rules | Where-Object contextId -eq $context.id)) {
            if ($rule.effect -eq 'suppressed') { $effective = @($effective | Where-Object path -ne $rule.path) }
            elseif ($rule.effect -eq 'contributed') {
                if (@($effective | Where-Object path -eq $rule.path).Count -ne 0) { throw "Parent context '$($context.id)' duplicates '$($rule.path)' for '$($document.id)'." }
                $effective += [ordered]@{ path = [string]$rule.path; valueContract = $rule.valueContract; affectsDisplay = [bool]$rule.affectsDisplay; previewPolicy = [string]$rule.previewPolicy; requiredEditor = [string]$rule.requiredEditor; disposition = $rule.disposition }
            }
        }
        $paths = @($effective | ForEach-Object path)
        if ($paths.Count -ne @($paths | Sort-Object -Unique).Count) { throw "Effective context '$($context.id)' duplicates paths for '$($document.id)'." }
        $missingTargets = @($effective | ForEach-Object { $_.valueContract.constraints } | ForEach-Object property | Where-Object { $paths -notcontains $_ } | Sort-Object -Unique)
        $effectiveParity += [ordered]@{ componentId = [string]$document.id; contextId = [string]$context.id; passed = ($missingTargets.Count -eq 0); propertyCount = $paths.Count; missingConstraintTargets = $missingTargets }
    }
}

if (@($intrinsicParity | Where-Object { -not $_.passed }).Count -ne 0 -or @($effectiveParity | Where-Object { -not $_.passed }).Count -ne 0) { throw 'Grouping expansion parity failed.' }

$design = [ordered]@{ artifactVersion = 1; matlabRelease = $release; inputSha256 = $inputDigest; groups = @($groupsById.Values | Sort-Object id); categoryMappings = $categoryMappings; profileAssignments = $profileAssignments }
$profileAnalysis = [ordered]@{ artifactVersion = 1; matlabRelease = $release; inputSha256 = $inputDigest; profiles = @($profiles | ForEach-Object { [ordered]@{ id = [string]$_.id; categoryOrder = @($_.categoryOrder); assignedVariantIds = @($profileAssignments | Where-Object profileId -eq $_.id | ForEach-Object componentId | Sort-Object) } }); assignments = $profileAssignments }
$parity = [ordered]@{ artifactVersion = 1; matlabRelease = $release; inputSha256 = $inputDigest; intrinsic = $intrinsicParity; parentEffective = $effectiveParity }
Write-JsonFile (Join-Path $outputPath 'GROUPING_DESIGN.json') $design
Write-JsonFile (Join-Path $outputPath 'ORDER_PROFILE_ANALYSIS.json') $profileAnalysis
Write-JsonFile (Join-Path $outputPath 'EXPANSION_PARITY.json') $parity

$summary = @(
    "# R2024a grouping design and parity report",
    '',
    "Generated by GenerateGroupingDesign.ps1 from input $inputDigest.",
    '',
    "- Groups: $($groupsById.Count)",
    "- Category mappings: $($categoryMappings.Count)",
    "- Order profiles: $($profiles.Count)",
    "- Intrinsic parity: $(@($intrinsicParity | Where-Object passed).Count)/$($intrinsicParity.Count) passed",
    "- Parent-effective parity: $(@($effectiveParity | Where-Object passed).Count)/$($effectiveParity.Count) passed",
    '',
    '## Profile assignments',
    ''
)
foreach ($profile in @($profileAnalysis.profiles)) { $summary += "- $($profile.id): $($profile.assignedVariantIds.Count) variant(s)" }
Write-Utf8File (Join-Path $outputPath 'GROUPING_DESIGN_SUMMARY.md') (($summary -join [Environment]::NewLine) + [Environment]::NewLine)
Write-Output (($summary | Select-Object -First 9) -join [Environment]::NewLine)

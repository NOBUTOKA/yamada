<#
.SYNOPSIS
Generates review artifacts for category-oriented property grouping.

.DESCRIPTION
Validates the grouping-relevant R2024a audit ledger, freezes its input hash,
and derives category-surface clusters, initial exact shared-group candidates,
and human judgment candidates for Steps 4 and 6 of the grouping procedure.

.EXAMPLE
./GenerateGroupingArtifacts.ps1 -ReleaseDirectory ./R2024a
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$ReleaseDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function ConvertTo-StringArray {
    param([object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    return @($Value | ForEach-Object { [string]$_ })
}

function ConvertTo-NormalizedValueContract {
    param([object]$ValueContract)

    $constraints = @(
        @($ValueContract.constraints | ForEach-Object {
            [ordered]@{
                kind     = [string]$_.kind
                property = [string]$_.property
            }
        }) | Sort-Object { "$($_.kind)`u{001F}$($_.property)" }
    )

    $result = [ordered]@{
        kind          = [string]$ValueContract.kind
        matlabClasses = @(ConvertTo-StringArray $ValueContract.matlabClasses | Sort-Object)
        shape         = [string]$ValueContract.shape
        allowsEmpty   = [bool]$ValueContract.allowsEmpty
        constraints   = $constraints
    }
    if ($null -ne $ValueContract.PSObject.Properties["values"]) {
        $result.values = @(ConvertTo-StringArray $ValueContract.values)
    }
    return $result
}

function ConvertTo-NormalizedDisposition {
    param([object]$Disposition)

    return [ordered]@{
        kind        = [string]$Disposition.kind
        reasonCodes = @(ConvertTo-StringArray $Disposition.reasonCodes | Sort-Object)
    }
}

function ConvertTo-PropertyCapability {
    param([object]$Property)

    return [ordered]@{
        path           = [string]$Property.path
        valueContract  = ConvertTo-NormalizedValueContract $Property.valueContract
        affectsDisplay = [bool]$Property.affectsDisplay
        previewPolicy  = [string]$Property.previewPolicy
        requiredEditor = [string]$Property.requiredEditor
        disposition    = ConvertTo-NormalizedDisposition $Property.disposition
    }
}

function Get-Sha256 {
    param([string]$Text)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return -join ($algorithm.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") })
    }
    finally {
        $algorithm.Dispose()
    }
}

function Get-RequiredProperty {
    param(
        [object]$Object,
        [string]$Name,
        [string]$Context
    )

    if ($null -eq $Object.PSObject.Properties[$Name]) {
        throw "$Context is missing required field '$Name'."
    }

    return $Object.$Name
}

function Test-ComponentDocument {
    param(
        [object]$Document,
        [string]$FilePath,
        [string]$Release
    )

    $context = "Component document '$FilePath'"
    foreach ($name in @("schemaVersion", "matlabRelease", "id", "factory", "creationArguments", "declaredType", "sources", "documentationCategories", "properties")) {
        $null = Get-RequiredProperty $Document $name $context
    }

    if ($Document.schemaVersion -ne 3) {
        throw "$context has schemaVersion '$($Document.schemaVersion)' instead of 3."
    }
    if ([string]$Document.matlabRelease -ne $Release) {
        throw "$context has matlabRelease '$($Document.matlabRelease)' instead of '$Release'."
    }

    $categories = @($Document.documentationCategories)
    $categoryIds = @(ConvertTo-StringArray ($categories | ForEach-Object { $_.id }))
    if ($categoryIds.Count -ne @($categoryIds | Sort-Object -Unique).Count) {
        throw "$context contains duplicate category IDs."
    }
    $expectedCategoryOrders = 1..$categories.Count
    $actualCategoryOrders = @($categories | ForEach-Object { [int]$_.order } | Sort-Object)
    if (Compare-Object $expectedCategoryOrders $actualCategoryOrders) {
        throw "$context has non-contiguous documentation category order."
    }

    $properties = @($Document.properties)
    $paths = @(ConvertTo-StringArray ($properties | ForEach-Object { $_.path }))
    if ($paths.Count -ne @($paths | Sort-Object -Unique).Count) {
        throw "$context contains duplicate property paths."
    }

    foreach ($property in $properties) {
        foreach ($name in @("path", "categoryId", "order", "runtimeSetAccess", "valueContract", "affectsDisplay", "previewPolicy", "requiredEditor", "disposition")) {
            $null = Get-RequiredProperty $property $name "$context property '$($property.path)'"
        }
        if ($categoryIds -notcontains [string]$property.categoryId) {
            throw "$context property '$($property.path)' references unknown category '$($property.categoryId)'."
        }
        foreach ($name in @("kind", "matlabClasses", "shape", "allowsEmpty", "constraints")) {
            $null = Get-RequiredProperty $property.valueContract $name "$context property '$($property.path)' valueContract"
        }
        foreach ($name in @("kind", "reasonCodes")) {
            $null = Get-RequiredProperty $property.disposition $name "$context property '$($property.path)' disposition"
        }
    }

    foreach ($category in $categories) {
        $categoryProperties = @($properties | Where-Object { [string]$_.categoryId -eq [string]$category.id })
        if ($categoryProperties.Count -eq 0) {
            throw "$context category '$($category.id)' has no properties."
        }
        $actualOrders = @($categoryProperties | ForEach-Object { [int]$_.order } | Sort-Object)
        $expectedOrders = 1..$categoryProperties.Count
        if (Compare-Object $expectedOrders $actualOrders) {
            throw "$context category '$($category.id)' has non-contiguous property order."
        }
    }

    $adjacency = @{}
    foreach ($path in $paths) {
        $adjacency[$path] = @()
    }
    foreach ($property in $properties) {
        foreach ($constraint in @($property.valueContract.constraints)) {
            $target = [string]$constraint.property
            if ($paths -notcontains $target) {
                throw "$context property '$($property.path)' depends on missing property '$target'."
            }
            if ($target -eq [string]$property.path) {
                throw "$context property '$($property.path)' has a self-referential constraint."
            }
            $adjacency[[string]$property.path] += $target
        }
    }

    $state = @{}
    function Visit-PropertyDependency {
        param([string]$Path)

        if ($state[$Path] -eq "visiting") {
            throw "$context contains a cyclic property constraint involving '$Path'."
        }
        if ($state[$Path] -eq "visited") {
            return
        }
        $state[$Path] = "visiting"
        foreach ($target in @($adjacency[$Path])) {
            Visit-PropertyDependency $target
        }
        $state[$Path] = "visited"
    }

    foreach ($path in $paths) {
        Visit-PropertyDependency $path
    }
}

function Test-ParentContextRules {
    param(
        [object]$Rules,
        [string]$FilePath,
        [string]$Release
    )

    $context = "Parent-context rules '$FilePath'"
    foreach ($name in @("schemaVersion", "matlabRelease", "contexts", "rules")) {
        $null = Get-RequiredProperty $Rules $name $context
    }
    if ($Rules.schemaVersion -ne 1 -or [string]$Rules.matlabRelease -ne $Release) {
        throw "$context has an unexpected schema or MATLAB release."
    }
    $contextIds = @(ConvertTo-StringArray (@($Rules.contexts) | ForEach-Object { $_.id }))
    if ($contextIds.Count -ne @($contextIds | Sort-Object -Unique).Count) {
        throw "$context contains duplicate context IDs."
    }
    foreach ($rule in @($Rules.rules)) {
        if ($contextIds -notcontains [string]$rule.contextId) {
            throw "$context rule for '$($rule.path)' references unknown context '$($rule.contextId)'."
        }
    }
}

function Test-CategoryScopeClassification {
    param(
        [object]$Classification,
        [string]$FilePath,
        [string]$Release,
        [string[]]$LedgerCategoryIds
    )

    $context = "Category scope classification '$FilePath'"
    foreach ($name in @("schemaVersion", "matlabRelease", "categories")) {
        $null = Get-RequiredProperty $Classification $name $context
    }
    if ($Classification.schemaVersion -ne 1 -or [string]$Classification.matlabRelease -ne $Release) {
        throw "$context has an unexpected schema or MATLAB release."
    }

    $entries = @($Classification.categories)
    $categoryIds = @(ConvertTo-StringArray ($entries | ForEach-Object { $_.id }))
    if ($categoryIds.Count -ne @($categoryIds | Sort-Object -Unique).Count) {
        throw "$context contains duplicate category IDs."
    }
    if (Compare-Object (@($LedgerCategoryIds | Sort-Object -Unique)) (@($categoryIds | Sort-Object -Unique))) {
        throw "$context must classify every and only the category IDs in the release ledger."
    }

    $allowedScopes = @("crossCutting", "familyScoped", "variantLocal")
    foreach ($entry in $entries) {
        foreach ($name in @("id", "scope", "reason")) {
            $null = Get-RequiredProperty $entry $name "$context category '$($entry.id)'"
        }
        if ($allowedScopes -notcontains [string]$entry.scope) {
            throw "$context category '$($entry.id)' has unsupported scope '$($entry.scope)'."
        }
        if ([string]::IsNullOrWhiteSpace([string]$entry.reason)) {
            throw "$context category '$($entry.id)' has an empty rationale."
        }
    }
}

function Write-Utf8File {
    param(
        [string]$Path,
        [string]$Text
    )

    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Write-JsonArtifact {
    param(
        [string]$Path,
        [object]$Value
    )

    Write-Utf8File $Path (($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine)
}

function Format-VariantList {
    param([string[]]$VariantIds)

    return ($VariantIds -join ", ")
}

$releasePath = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$release = Split-Path -Leaf $releasePath
$componentsPath = Join-Path $releasePath "components"
$rulesPath = Join-Path $releasePath "parent-context-rules.json"
$schemaPath = Join-Path $releasePath "schema.json"
$scopeClassificationPath = Join-Path $releasePath "category-scope-classification.json"
$outputPath = Join-Path $releasePath "grouping"

if (-not (Test-Path -LiteralPath $componentsPath -PathType Container)) {
    throw "Release directory '$releasePath' has no components directory."
}
if (-not (Test-Path -LiteralPath $rulesPath -PathType Leaf)) {
    throw "Release directory '$releasePath' has no parent-context-rules.json file."
}
if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
    throw "Release directory '$releasePath' has no schema.json file."
}
if (-not (Test-Path -LiteralPath $scopeClassificationPath -PathType Leaf)) {
    throw "Release directory '$releasePath' has no category-scope-classification.json file."
}

$componentFiles = @(Get-ChildItem -LiteralPath $componentsPath -Filter "*.json" -File | Sort-Object Name)
if ($componentFiles.Count -eq 0) {
    throw "Release directory '$releasePath' has no component documents."
}

$documents = @()
$seenComponentIds = @{}
foreach ($file in $componentFiles) {
    try {
        $document = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    }
    catch {
        throw "Unable to parse component document '$($file.FullName)': $($_.Exception.Message)"
    }
    Test-ComponentDocument $document $file.FullName $release
    $componentId = [string]$document.id
    if ($seenComponentIds.ContainsKey($componentId)) {
        throw "Duplicate concrete component ID '$componentId'."
    }
    $seenComponentIds[$componentId] = $true
    $documents += [pscustomobject]@{ File = $file; Document = $document }
}

try {
    $parentRules = Get-Content -Raw -LiteralPath $rulesPath | ConvertFrom-Json
}
catch {
    throw "Unable to parse parent-context rules '$rulesPath': $($_.Exception.Message)"
}
Test-ParentContextRules $parentRules $rulesPath $release

try {
    $scopeClassification = Get-Content -Raw -LiteralPath $scopeClassificationPath | ConvertFrom-Json
}
catch {
    throw "Unable to parse category scope classification '$scopeClassificationPath': $($_.Exception.Message)"
}
$ledgerCategoryIds = @($documents.Document.documentationCategories | ForEach-Object { $_.id } | Sort-Object -Unique)
Test-CategoryScopeClassification $scopeClassification $scopeClassificationPath $release $ledgerCategoryIds
$categoryScopeById = @{}
foreach ($entry in @($scopeClassification.categories)) {
    $categoryScopeById[[string]$entry.id] = $entry
}

$ledgerInputFiles = @($componentFiles.FullName + $rulesPath + $schemaPath | Sort-Object)
$inputFiles = @($ledgerInputFiles + $scopeClassificationPath | Sort-Object)
$inputFileDigests = @(
    foreach ($filePath in $inputFiles) {
        $relativePath = $filePath.Substring($releasePath.Length + 1).Replace("\", "/")
        [ordered]@{
            path   = $relativePath
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $filePath).Hash.ToLowerInvariant()
        }
    }
)
$inputDigestText = ($inputFileDigests | ForEach-Object { "$($_.path):$($_.sha256)" }) -join "`n"
$repositoryPath = (Resolve-Path -LiteralPath (Join-Path $releasePath "..\..\..")).Path
$releaseRelativePath = $releasePath.Substring($repositoryPath.Length + 1).Replace("\", "/")
$ledgerRelativePaths = @($ledgerInputFiles | ForEach-Object { "$releaseRelativePath/$($_.Substring($releasePath.Length + 1).Replace("\", "/"))" })
$inputRelativePaths = $ledgerRelativePaths
$gitCommitOutput = @(& git -C $repositoryPath log -1 --format=%H -- $inputRelativePaths 2>$null)
if ($LASTEXITCODE -ne 0 -or $gitCommitOutput.Count -eq 0) {
    $gitCommit = "unavailable"
}
else {
    $gitCommit = ([string]$gitCommitOutput[0]).Trim()
}

$matrix = @()
foreach ($entry in $documents) {
    $document = $entry.Document
    foreach ($category in @($document.documentationCategories | Sort-Object { [int]$_.order })) {
        $properties = @($document.properties | Where-Object { [string]$_.categoryId -eq [string]$category.id } | Sort-Object { [int]$_.order })
        $capabilities = @($properties | ForEach-Object { ConvertTo-PropertyCapability $_ })
        $signature = $capabilities | ConvertTo-Json -Compress -Depth 100
        $hash = Get-Sha256 $signature
        $propertyCapabilityHashes = @($capabilities | ForEach-Object { Get-Sha256 ($_ | ConvertTo-Json -Compress -Depth 100) })
        $scopeEntry = $categoryScopeById[[string]$category.id]
        $matrix += [pscustomobject]([ordered]@{
            componentId          = [string]$document.id
            categoryId           = [string]$category.id
            categoryDisplayName  = [string]$category.displayName
            sharingScope         = [string]$scopeEntry.scope
            scopeRationale       = [string]$scopeEntry.reason
            documentedOrder      = [int]$category.order
            propertyPaths        = @($capabilities | ForEach-Object { [string]$_.path })
            propertyCapabilitySha256 = $propertyCapabilityHashes
            capabilitySha256     = $hash
        })
    }
}

$clusters = @()
foreach ($group in @($matrix | Group-Object { "$($_.categoryId)`u{001F}$($_.categoryDisplayName)`u{001F}$($_.capabilitySha256)" } | Sort-Object Name)) {
    $first = $group.Group[0]
    $memberIds = @($group.Group.componentId | Sort-Object)
    $orders = @($group.Group.documentedOrder | Sort-Object -Unique)
    $clusters += [pscustomobject]([ordered]@{
        candidateId              = "candidate.$($first.categoryId).$($first.capabilitySha256.Substring(0, 12))"
        categoryId               = $first.categoryId
        categoryDisplayName      = $first.categoryDisplayName
        sharingScope             = $first.sharingScope
        scopeRationale           = $first.scopeRationale
        capabilitySha256         = $first.capabilitySha256
        propertyPaths            = $first.propertyPaths
        propertyCapabilitySha256 = $first.propertyCapabilitySha256
        memberVariantIds         = $memberIds
        reuseCount               = $memberIds.Count
        documentedCategoryOrders = $orders
    })
}

$initialCandidates = @($clusters | Where-Object { $_.reuseCount -ge 2 } | Sort-Object categoryId, capabilitySha256)

Write-Verbose "Built $($matrix.Count) category occurrences, $($clusters.Count) exact clusters, and $($initialCandidates.Count) initial group candidates."

$conflicts = @()
foreach ($group in @($clusters | Group-Object categoryId | Sort-Object Name)) {
    $surfaces = @($group.Group | Sort-Object capabilitySha256)
    if ($surfaces.Count -le 1) {
        continue
    }
    $allPaths = @($surfaces | ForEach-Object { $_.propertyPaths } | Sort-Object -Unique)
    $pathVariants = @()
    foreach ($path in $allPaths) {
        $presentIn = @($surfaces | Where-Object { $_.propertyPaths -contains $path } | ForEach-Object candidateId)
        $pathVariants += [pscustomobject]([ordered]@{
            path                  = $path
            presentInSurfaceCount = $presentIn.Count
            presentInCandidateIds = $presentIn
        })
    }
    $conflicts += [pscustomobject]([ordered]@{
        categoryId              = $group.Name
        categoryDisplayNames    = @($surfaces.categoryDisplayName | Sort-Object -Unique)
        sharingScope            = $surfaces[0].sharingScope
        scopeRationale          = $surfaces[0].scopeRationale
        surfaceCount            = $surfaces.Count
        affectedVariantIds      = @($surfaces.memberVariantIds | ForEach-Object { $_ } | Sort-Object -Unique)
        surfaces                = $surfaces
        pathCoverage            = $pathVariants
        requiredDecision        = if ($surfaces[0].sharingScope -eq "crossCutting") { "Classify each surface difference as a family distinction, variant distinction, parent-context issue, or audit discrepancy." } else { "Retain as family-local evidence unless a later family-specific sharing design selects it." }
    })
}

$coreExtensionCandidates = @()
Write-Verbose "Analyzing same-name category conflicts for ordered strict core/extension pairs."
foreach ($conflict in $conflicts) {
    $surfaces = @($conflict.surfaces)
    Write-Verbose "Analyzing category '$($conflict.categoryId)' with $($surfaces.Count) distinct surfaces."
    for ($baseIndex = 0; $baseIndex -lt $surfaces.Count; $baseIndex++) {
        for ($extendedIndex = 0; $extendedIndex -lt $surfaces.Count; $extendedIndex++) {
            if ($baseIndex -eq $extendedIndex) {
                continue
            }
            $base = $surfaces[$baseIndex]
            $extended = $surfaces[$extendedIndex]
            $basePaths = @($base.propertyPaths)
            $extendedPaths = @($extended.propertyPaths)
            $missingFromExtended = @($basePaths | Where-Object { $extendedPaths -notcontains $_ })
            $additions = @($extendedPaths | Where-Object { $basePaths -notcontains $_ })
            if ($missingFromExtended.Count -ne 0 -or $additions.Count -eq 0) {
                continue
            }
            $extendedPositionByPath = @{}
            for ($propertyIndex = 0; $propertyIndex -lt $extendedPaths.Count; $propertyIndex++) {
                $extendedPositionByPath[[string]$extendedPaths[$propertyIndex]] = $propertyIndex
            }
            $previousExtendedIndex = -1
            $preservesBaseOrder = $true
            foreach ($path in $basePaths) {
                $pathIndex = [int]$extendedPositionByPath[[string]$path]
                if ($pathIndex -le $previousExtendedIndex) {
                    $preservesBaseOrder = $false
                    break
                }
                $previousExtendedIndex = $pathIndex
            }
            if (-not $preservesBaseOrder) {
                continue
            }
            $extendedCapabilityByPath = @{}
            for ($propertyIndex = 0; $propertyIndex -lt $extended.propertyPaths.Count; $propertyIndex++) {
                $extendedCapabilityByPath[[string]$extended.propertyPaths[$propertyIndex]] = [string]$extended.propertyCapabilitySha256[$propertyIndex]
            }
            $capabilitiesMatch = $true
            for ($propertyIndex = 0; $propertyIndex -lt $base.propertyPaths.Count; $propertyIndex++) {
                $path = [string]$base.propertyPaths[$propertyIndex]
                if ($extendedCapabilityByPath[$path] -ne [string]$base.propertyCapabilitySha256[$propertyIndex]) {
                    $capabilitiesMatch = $false
                    break
                }
            }
            if (-not $capabilitiesMatch) {
                continue
            }
            $extensionInsertions = @()
            $precedingBasePath = $null
            foreach ($path in $extendedPaths) {
                if ($basePaths -contains $path) {
                    $precedingBasePath = $path
                }
                else {
                    $extensionInsertions += [pscustomobject]([ordered]@{
                        path             = $path
                        insertedAfterPath = $precedingBasePath
                    })
                }
            }
            if ($base.reuseCount -ge 2 -and $extended.reuseCount -ge 2) {
                $reviewPriority = "high"
            }
            elseif (($base.reuseCount + $extended.reuseCount) -ge 3) {
                $reviewPriority = "medium"
            }
            else {
                $reviewPriority = "informational"
            }
            $coreExtensionCandidates += [pscustomobject]([ordered]@{
                categoryId                  = $conflict.categoryId
                sharingScope                = $conflict.sharingScope
                baseCandidateId             = $base.candidateId
                baseVariantIds              = $base.memberVariantIds
                baseReuseCount              = $base.reuseCount
                extendedCandidateId         = $extended.candidateId
                extendedVariantIds          = $extended.memberVariantIds
                extendedReuseCount          = $extended.reuseCount
                extensionPropertyPaths      = $additions
                extensionPropertyCount      = $additions.Count
                extensionInsertions         = $extensionInsertions
                reviewPriority              = $reviewPriority
                requiredDecision            = "Decide whether this ordered strict extension has a stable semantic meaning and is simpler than separate complete category groups."
            })
        }
    }
}
$coreExtensionCandidates = @($coreExtensionCandidates | Sort-Object categoryId, extensionPropertyCount, baseCandidateId, extendedCandidateId)
Write-Verbose "Found $($conflicts.Count) category conflicts and $($coreExtensionCandidates.Count) ordered strict core/extension candidates."

$step4CrossCuttingConflicts = @($conflicts | Where-Object { $_.sharingScope -eq "crossCutting" })
$familyScopedDifferences = @($conflicts | Where-Object { $_.sharingScope -eq "familyScoped" })
$step6CrossCuttingCandidates = @($coreExtensionCandidates | Where-Object { $_.sharingScope -eq "crossCutting" })
$familyScopedCoreExtensionCandidates = @($coreExtensionCandidates | Where-Object { $_.sharingScope -eq "familyScoped" })
$scopeCounts = @(
    $scopeClassification.categories | Group-Object scope | Sort-Object Name | ForEach-Object {
        [ordered]@{
            scope = $_.Name
            categoryCount = $_.Count
        }
    }
)

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$baseline = [ordered]@{
    artifactVersion       = 1
    matlabRelease         = $release
    ledgerBaselineGitCommit = $gitCommit
    inputSha256           = Get-Sha256 $inputDigestText
    componentDocumentCount = $documents.Count
    componentVariantIds   = @($documents.Document.id | Sort-Object)
    propertyEntryCount    = @($documents.Document.properties | ForEach-Object { @($_).Count } | Measure-Object -Sum).Sum
    categoryOccurrenceCount = $matrix.Count
    categoryScopeCounts   = $scopeCounts
    inputFiles            = $inputFileDigests
    validation            = [ordered]@{
        status = "passed"
        checks = @(
            "component document JSON parsing",
            "required grouping fields",
            "release and schema versions",
            "unique component IDs, category IDs, and property paths",
            "category and property source-page order",
            "category references and property constraint targets",
            "acyclic property constraints",
            "parent-context rule context references",
            "complete category sharing-scope classification"
        )
    }
}

Write-JsonArtifact (Join-Path $outputPath "INPUT_BASELINE.json") $baseline
Write-JsonArtifact (Join-Path $outputPath "CATEGORY_SURFACE_MATRIX.json") ([ordered]@{
    artifactVersion = 1
    matlabRelease   = $release
    inputSha256     = $baseline.inputSha256
    occurrences     = $matrix
})
Write-JsonArtifact (Join-Path $outputPath "EXACT_CATEGORY_SURFACE_CLUSTERS.json") ([ordered]@{
    artifactVersion = 1
    matlabRelease   = $release
    inputSha256     = $baseline.inputSha256
    clusters        = $clusters
})
Write-JsonArtifact (Join-Path $outputPath "INITIAL_CATEGORY_GROUP_CANDIDATES.json") ([ordered]@{
    artifactVersion = 1
    matlabRelease   = $release
    inputSha256     = $baseline.inputSha256
    selectionRule   = "Complete exact category surfaces with reuseCount >= 2. Candidate IDs are temporary until Step 9 assigns reviewed stable identifiers."
    candidates      = $initialCandidates
})
Write-JsonArtifact (Join-Path $outputPath "JUDGMENT_CANDIDATES.json") ([ordered]@{
    artifactVersion                     = 1
    matlabRelease                       = $release
    inputSha256                         = $baseline.inputSha256
    step4CrossCuttingConflicts          = $step4CrossCuttingConflicts
    familyScopedDifferences             = $familyScopedDifferences
    step6CrossCuttingCoreExtensionPairs = $step6CrossCuttingCandidates
    familyScopedCoreExtensionPairs      = $familyScopedCoreExtensionCandidates
})
Write-Verbose "Wrote JSON grouping artifacts."

$markdown = [System.Text.StringBuilder]::new()
$null = $markdown.AppendLine("# R2024a grouping judgment candidates")
$null = $markdown.AppendLine()
$null = $markdown.AppendLine("Generated by GenerateGroupingArtifacts.ps1 from frozen input baseline $($baseline.inputSha256). This report does not modify the release ledger or promote any candidate into the runtime catalog.")
$null = $markdown.AppendLine()
$null = $markdown.AppendLine("## Baseline")
$null = $markdown.AppendLine()
$null = $markdown.AppendLine("- Ledger Git commit: $($baseline.ledgerBaselineGitCommit)")
$null = $markdown.AppendLine("- Concrete variants: $($baseline.componentDocumentCount)")
$null = $markdown.AppendLine("- Property entries: $($baseline.propertyEntryCount)")
$null = $markdown.AppendLine("- Category occurrences: $($baseline.categoryOccurrenceCount)")
$null = $markdown.AppendLine("- Exact category-surface clusters: $($clusters.Count)")
$null = $markdown.AppendLine("- Initial complete shared-group candidates: $($initialCandidates.Count)")
$null = $markdown.AppendLine("- Category scope classification: $((@($scopeCounts | ForEach-Object { "$($_.scope)=$($_.categoryCount)" }) -join ", "))")
$null = $markdown.AppendLine("- Step 4 cross-cutting conflicts requiring classification: $($step4CrossCuttingConflicts.Count)")
$null = $markdown.AppendLine("- Family-scoped differences retained as reference: $($familyScopedDifferences.Count)")
$null = $markdown.AppendLine("- Step 6 cross-cutting strict core/extension candidates: $($step6CrossCuttingCandidates.Count)")
$null = $markdown.AppendLine("- Family-scoped core/extension pairs retained as reference: $($familyScopedCoreExtensionCandidates.Count)")
$null = $markdown.AppendLine()
$null = $markdown.AppendLine("## Step 4: cross-cutting same-name category conflicts")
$null = $markdown.AppendLine()
if ($step4CrossCuttingConflicts.Count -eq 0) {
    $null = $markdown.AppendLine("No cross-cutting same-name category conflicts were found.")
}
else {
    foreach ($conflict in $step4CrossCuttingConflicts) {
        $null = $markdown.AppendLine("### $($conflict.categoryId)")
        $null = $markdown.AppendLine()
        $null = $markdown.AppendLine("$($conflict.surfaceCount) distinct exact surfaces across: $(Format-VariantList $conflict.affectedVariantIds)")
        $null = $markdown.AppendLine()
        foreach ($surface in @($conflict.surfaces | Sort-Object candidateId)) {
            $null = $markdown.AppendLine("- $($surface.candidateId) - $($surface.reuseCount) variant(s): $(Format-VariantList $surface.memberVariantIds)")
            $null = $markdown.AppendLine("  - Properties: $($surface.propertyPaths -join ", ")")
        }
        $variablePaths = @($conflict.pathCoverage | Where-Object { $_.presentInSurfaceCount -ne $conflict.surfaceCount } | ForEach-Object path)
        if ($variablePaths.Count -gt 0) {
            $null = $markdown.AppendLine("- Paths not present in every surface: $($variablePaths -join ", ")")
        }
        $null = $markdown.AppendLine("- Decision needed: $($conflict.requiredDecision)")
        $null = $markdown.AppendLine()
    }
}

$null = $markdown.AppendLine("## Family-scoped differences")
$null = $markdown.AppendLine()
if ($familyScopedDifferences.Count -eq 0) {
    $null = $markdown.AppendLine("No family-scoped category differences were found.")
}
else {
    $null = $markdown.AppendLine("These are retained as evidence, not Step 4 cross-family review items: $((@($familyScopedDifferences.categoryId) -join ", ")).")
}
$null = $markdown.AppendLine()

$null = $markdown.AppendLine("## Step 6: cross-cutting strict core/extension candidates")
$null = $markdown.AppendLine()
if ($step6CrossCuttingCandidates.Count -eq 0) {
    $null = $markdown.AppendLine("No cross-cutting strict core/extension pairs were found.")
}
else {
    foreach ($priority in @("high", "medium", "informational")) {
        $priorityCandidates = @($step6CrossCuttingCandidates | Where-Object { $_.reviewPriority -eq $priority })
        if ($priorityCandidates.Count -eq 0) {
            continue
        }
        $null = $markdown.AppendLine("### $priority priority ($($priorityCandidates.Count))")
        $null = $markdown.AppendLine()
        foreach ($candidate in $priorityCandidates) {
            $insertionText = @($candidate.extensionInsertions | ForEach-Object {
                if ($null -eq $_.insertedAfterPath) {
                    "$($_.path) at category start"
                }
                else {
                    "$($_.path) after $($_.insertedAfterPath)"
                }
            }) -join "; "
            $null = $markdown.AppendLine("- $($candidate.categoryId): $($candidate.baseCandidateId) ($(Format-VariantList $candidate.baseVariantIds)) -> $($candidate.extendedCandidateId) ($(Format-VariantList $candidate.extendedVariantIds)); extension: $($candidate.extensionPropertyPaths -join ", "); placement: $insertionText.")
        }
        $null = $markdown.AppendLine()
    }
    $null = $markdown.AppendLine("For each pair, accept a core/extension split only when the extension is semantically stable, repeated, non-overlapping, and simpler than retaining complete family category groups.")
}

Write-Utf8File (Join-Path $outputPath "JUDGMENT_CANDIDATES.md") $markdown.ToString()

$summary = [ordered]@{
    artifactVersion                 = 1
    matlabRelease                   = $release
    inputSha256                     = $baseline.inputSha256
    componentDocumentCount          = $documents.Count
    propertyEntryCount              = $baseline.propertyEntryCount
    categoryOccurrenceCount         = $matrix.Count
    categoryScopeCounts             = $scopeCounts
    exactClusterCount               = $clusters.Count
    initialGroupCandidateCount      = $initialCandidates.Count
    allSameNameConflictCount        = $conflicts.Count
    step4CrossCuttingConflictCount  = $step4CrossCuttingConflicts.Count
    familyScopedDifferenceCount     = $familyScopedDifferences.Count
    allCoreExtensionCandidateCount  = $coreExtensionCandidates.Count
    step6CrossCuttingCandidateCount = $step6CrossCuttingCandidates.Count
    familyScopedCoreExtensionCandidateCount = $familyScopedCoreExtensionCandidates.Count
}
Write-JsonArtifact (Join-Path $outputPath "SUMMARY.json") $summary

Write-Output "Validated $($documents.Count) component documents and generated grouping artifacts in '$outputPath'."
Write-Output ($summary | ConvertTo-Json -Compress)

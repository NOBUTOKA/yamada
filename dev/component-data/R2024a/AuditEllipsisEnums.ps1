[CmdletBinding()]
param(
    [string]$ReleaseDirectory = $PSScriptRoot,
    [string]$CatalogRoot = (Join-Path $PSScriptRoot '..\..\..\resources\component-catalog\R2024a'),
    [string]$OutputDirectory = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-StringArray {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    return @($Value | ForEach-Object { [string]$_ })
}

function Get-PropertySection {
    param([string]$Html, [string]$Path)
    $anchor = [regex]::Match($Html, '(?s)<span\s+id="prop_' + [regex]::Escape($Path) + '"[^>]*>.*?(?=<span\s+id="prop_|\z)')
    if (-not $anchor.Success) { return $null }
    return $anchor.Value
}

function Get-HeadingValueText {
    param([string]$Section)
    $match = [regex]::Match($Section, '(?s)itemprop="inputvalues"[^>]*>(.*?)</span></span></h3>')
    if (-not $match.Success) { return '' }
    return [System.Net.WebUtility]::HtmlDecode(($match.Groups[1].Value -replace '<[^>]+>', ' ')).Trim()
}

function Get-QuotedTokens {
    param([string]$HtmlFragment)
    $decoded = [System.Net.WebUtility]::HtmlDecode($HtmlFragment)
    $pattern = '''([^'']+)''|""([^""]+)""'
    $tokens = [regex]::Matches($decoded, $pattern) |
        ForEach-Object {
            if ($_.Groups[1].Success) { $_.Groups[1].Value }
            elseif ($_.Groups[2].Success) { $_.Groups[2].Value }
        }
    return @($tokens | Where-Object { $_ -and $_ -notmatch '\s' } | Select-Object -Unique)
}

function Get-DocumentationUrl {
    param([object]$Sources)
    $urls = @($Sources | ForEach-Object { [string]$_.url } | Where-Object { $_ })
    $propertyUrl = $urls | Where-Object { $_ -match '-properties\.html(?:$|[?#])' } | Select-Object -First 1
    if ($propertyUrl) { return $propertyUrl }
    return ($urls | Select-Object -First 1)
}

function Get-CatalogEntries {
    param([string]$Root)
    $map = @{}
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $Root 'components') -Filter '*.json') {
        $component = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
        foreach ($category in @($component.categories)) {
            foreach ($entry in @($category.entries)) {
                $key = '{0}|{1}' -f [string]$component.id, [string]$entry.path
                $map[$key] = [string]$entry.groupId
            }
        }
    }
    return $map
}

$componentDirectory = Join-Path $ReleaseDirectory 'components'
$catalogMap = Get-CatalogEntries -Root $CatalogRoot
$auditRows = [System.Collections.Generic.List[object]]::new()
$reviewMap = @{}

foreach ($file in Get-ChildItem -LiteralPath $componentDirectory -Filter '*.json') {
    $component = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    foreach ($property in @($component.properties)) {
        if ([string]$property.valueContract.kind -ne 'enum') { continue }
        $componentId = [string]$component.id
        $path = [string]$property.path
        $key = '{0}|{1}' -f $componentId, $path
        $groupId = if ($catalogMap.ContainsKey($key)) { $catalogMap[$key] } else { '' }
        $sourceUrls = @(Get-StringArray $component.sources | ForEach-Object { $_ })
        $sourceUrls = @($component.sources | ForEach-Object { [string]$_.url } | Where-Object { $_ })
        $propertyUrl = Get-DocumentationUrl -Sources $component.sources
        $row = [ordered]@{
            componentId = $componentId
            factory = [string]$component.factory
            path = $path
            categoryId = [string]$property.categoryId
            groupId = $groupId
            disposition = [string]$property.disposition.kind
            requiredEditor = [string]$property.requiredEditor
            documentedDefault = if ($property.PSObject.Properties.Name -contains 'documentedDefault') { [string]$property.documentedDefault } else { $null }
            documentedAcceptedValues = @(Get-StringArray $property.documentedAcceptedValues)
            valueContractValues = if ($property.valueContract.PSObject.Properties.Name -contains 'values') { @(Get-StringArray $property.valueContract.values) } else { @() }
            sourceUrls = $sourceUrls
            propertyUrl = $propertyUrl
            htmlStatus = 'notFetched'
            headingValueText = ''
            headingHasEllipsis = $false
            fetchedValues = @()
            fetchError = $null
        }
        $auditRows.Add([pscustomobject]$row)
        $reviewKey = '{0}|{1}' -f $groupId, $path
        if (-not $reviewMap.ContainsKey($reviewKey)) {
            $reviewMap[$reviewKey] = [ordered]@{
                reviewUnitId = $reviewKey
                groupId = $groupId
                path = $path
                representativeComponentId = $componentId
                derivedEntries = [System.Collections.Generic.List[object]]::new()
            }
        }
        $reviewMap[$reviewKey].derivedEntries.Add([pscustomobject]@{
            componentId = $componentId
            factory = [string]$component.factory
            propertyUrl = $propertyUrl
            sourceUrls = $sourceUrls
        })
    }
}

$cache = @{}
foreach ($row in $auditRows) {
    if (-not $row.propertyUrl) {
        $row.htmlStatus = 'missingUrl'
        continue
    }
    try {
        if (-not $cache.ContainsKey($row.propertyUrl)) {
            $cache[$row.propertyUrl] = (Invoke-WebRequest -UseBasicParsing -Uri $row.propertyUrl).Content
        }
        $section = Get-PropertySection -Html $cache[$row.propertyUrl] -Path $row.path
        if ($null -eq $section) {
            $row.htmlStatus = 'propertyNotFound'
            continue
        }
        $row.htmlStatus = 'ok'
        $row.headingValueText = Get-HeadingValueText -Section $section
        $row.headingHasEllipsis = $row.headingValueText -match '(?:\.\.\.|…)'
        $row.fetchedValues = @(Get-QuotedTokens -HtmlFragment $section)
    }
    catch {
        $row.htmlStatus = 'fetchError'
        $row.fetchError = $_.Exception.Message
    }
}

$reviewRows = foreach ($unit in $reviewMap.Values) {
    $members = @($auditRows | Where-Object { ('{0}|{1}' -f $_.groupId, $_.path) -eq $unit.reviewUnitId })
    [pscustomobject][ordered]@{
        reviewUnitId = $unit.reviewUnitId
        groupId = $unit.groupId
        path = $unit.path
        representativeComponentId = $unit.representativeComponentId
        derivedEntries = @($unit.derivedEntries)
        memberCount = $members.Count
        htmlStatusCounts = @($members | Group-Object htmlStatus | ForEach-Object { [pscustomobject]@{ status = $_.Name; count = $_.Count } })
        headingValueTexts = @($members | ForEach-Object { [pscustomobject]@{ componentId = $_.componentId; text = $_.headingValueText; hasEllipsis = $_.headingHasEllipsis } })
        hasEllipsis = [bool](@($members | Where-Object { $_.headingHasEllipsis }).Count)
        headingMismatch = (@($members.headingValueText | Select-Object -Unique).Count -gt 1)
        reviewStatus = if (@($members | Where-Object { $_.headingHasEllipsis }).Count) { 'requiresBodyReview' } else { 'noEllipsisDetected' }
    }
}

$auditPath = Join-Path $OutputDirectory 'ENUM_AUDIT.json'
$reviewPath = Join-Path $OutputDirectory 'ENUM_REVIEW_UNITS.json'
$auditDocument = [ordered]@{
    schemaVersion = 1
    release = 'R2024a'
    generatedBy = 'AuditEllipsisEnums.ps1'
    enumEntryCount = $auditRows.Count
    entries = @($auditRows)
}
$reviewDocument = [ordered]@{
    schemaVersion = 1
    release = 'R2024a'
    generatedBy = 'AuditEllipsisEnums.ps1'
    reviewUnitCount = @($reviewRows).Count
    ellipsisReviewUnitCount = @($reviewRows | Where-Object hasEllipsis).Count
    reviewUnits = @($reviewRows)
}
$auditDocument | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 -LiteralPath $auditPath
$reviewDocument | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 -LiteralPath $reviewPath
Write-Output ('Wrote {0} enum entries and {1} review units ({2} with ellipsis).' -f $auditRows.Count, @($reviewRows).Count, @($reviewRows | Where-Object hasEllipsis).Count)

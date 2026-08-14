<#
.SYNOPSIS
Reacquires incomplete editable enum contracts from release-fixed MathWorks pages.

.DESCRIPTION
Reads each ledger property whose enum contract has no finite values, fetches
its release-fixed mathworksDocumentation source page, and extracts quoted
choices from the property heading or body. A property whose documentation says
that changing it has no effect is omitted instead of being presented as a
single-choice editor. The script fails closed for any other incomplete result.

.EXAMPLE
./ReacquireIncompleteEnumContracts.ps1 -ReleaseDirectory ./R2024a
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$ReleaseDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-QuotedTokens {
    param([string]$Html)

    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($Html, '<code class="literal">(?<value>.*?)</code>')) {
        $literal = [System.Net.WebUtility]::HtmlDecode($match.Groups["value"].Value)
        if ($literal -match "^'(?<value>[^']+)'$") {
            $value = $Matches["value"]
            if (-not $tokens.Contains($value)) { $tokens.Add($value) }
        }
    }
    return @($tokens)
}

function Get-PropertySection {
    param([string]$Html, [string]$Path)

    $anchor = 'id="prop_{0}"' -f [regex]::Escape($Path)
    $start = $Html.IndexOf($anchor, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "The source page has no property anchor for '$Path'." }
    $headingEnd = $Html.IndexOf("</h3>", $start, [StringComparison]::Ordinal)
    if ($headingEnd -lt 0) { throw "The source page has no closing heading for '$Path'." }
    $nextAnchor = $Html.IndexOf('id="prop_', $headingEnd, [StringComparison]::Ordinal)
    if ($nextAnchor -lt 0) { $nextAnchor = $Html.Length }
    return [pscustomobject]@{
        Heading = $Html.Substring($start, $headingEnd + 5 - $start)
        Body = $Html.Substring($headingEnd + 5, $nextAnchor - $headingEnd - 5)
    }
}

function Get-DefaultToken {
    param([string]$Heading)

    $match = [regex]::Match($Heading, '(?s)<span itemprop="inputvalue defaultvalue">.*?<code class="literal">(?<value>.*?)</code>')
    if (-not $match.Success) { return "" }
    $literal = [System.Net.WebUtility]::HtmlDecode($match.Groups["value"].Value)
    if ($literal -match "^'(?<value>[^']+)'$") { return $Matches["value"] }
    return ""
}

function Write-Utf8JsonFile {
    param([string]$Path, [object]$Value)

    $text = ($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

$releasePath = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$componentPath = Join-Path $releasePath "components"
$cache = @{}
$updated = 0
$omitted = 0

foreach ($file in @(Get-ChildItem -LiteralPath $componentPath -Filter '*.json' -File | Sort-Object Name)) {
    $document = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    $changed = $false
    $source = @($document.sources | Where-Object type -eq "mathworksDocumentation" | Select-Object -Last 1)
    foreach ($property in @($document.properties)) {
        if ([string]$property.valueContract.kind -ne "enum" -or [string]$property.disposition.kind -ne "editable" -or $null -ne $property.valueContract.PSObject.Properties["values"]) {
            continue
        }
        if ($source.Count -ne 1) { throw "'$($document.id).$($property.path)' has no unique MathWorks property source." }
        $url = [string]$source[0].url
        if (-not $cache.ContainsKey($url)) {
            $cache[$url] = (Invoke-WebRequest -UseBasicParsing -Uri $url).Content
        }
        $section = Get-PropertySection $cache[$url] ([string]$property.path)
        $values = @(Get-QuotedTokens $section.Heading)
        if ($values.Count -lt 2) { $values = @(Get-QuotedTokens $section.Body) }
        if ($values.Count -ge 2) {
            $default = Get-DefaultToken $section.Heading
            if ([string]::IsNullOrEmpty($default)) { $default = $values[0] }
            $ordered = @($default) + @($values | Where-Object { $_ -ne $default })
            $property | Add-Member -NotePropertyName documentedDefault -NotePropertyValue "'$default'" -Force
            $property | Add-Member -NotePropertyName documentedAcceptedValues -NotePropertyValue @($ordered | Select-Object -Skip 1 | ForEach-Object { "'$_'" }) -Force
            $property.valueContract | Add-Member -NotePropertyName values -NotePropertyValue $ordered -Force
            $updated++
            $changed = $true
        }
        elseif ($section.Body -match 'Changing the value has no effect') {
            $property.affectsDisplay = $false
            $property.previewPolicy = "skip"
            $property.requiredEditor = "none"
            $property.disposition.kind = "omitted"
            $property.disposition.reasonCodes = @("lowDesignTimeValue")
            $omitted++
            $changed = $true
        }
        else {
            throw "'$($document.id).$($property.path)' remains incomplete after source reacquisition."
        }
    }
    if ($changed) { Write-Utf8JsonFile $file.FullName $document }
}

Write-Output "Reacquired $updated enum contracts and omitted $omitted no-effect properties."

<#
.SYNOPSIS
Normalizes complete documented enum choices and omits non-design-time inner geometry.

.DESCRIPTION
Reads one release-fixed component ledger. For editable enum properties, it
records valueContract.values only when quoted documentation tokens establish
at least two distinct choices. It also marks InnerPosition as omitted because
the inspector exposes Position as the design-time geometry surface.

.EXAMPLE
./NormalizeFiniteEnumValues.ps1 -ReleaseDirectory ./R2024a
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$ReleaseDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-DocumentedEnumValues {
    param([object]$Property)

    $values = [System.Collections.Generic.List[string]]::new()
    $sources = @()
    if ($null -ne $Property.PSObject.Properties["documentedDefault"]) {
        $sources += [string]$Property.documentedDefault
    }
    if ($null -ne $Property.PSObject.Properties["documentedAcceptedValues"]) {
        $sources += @($Property.documentedAcceptedValues | ForEach-Object { [string]$_ })
    }
    foreach ($source in $sources) {
        if ($null -eq $source) { continue }
        foreach ($match in [regex]::Matches([string]$source, "'(?:''|[^'])*'")) {
            $value = $match.Value.Substring(1, $match.Value.Length - 2).Replace("''", "'")
            if (-not [string]::IsNullOrEmpty($value) -and -not $values.Contains($value)) {
                $values.Add($value)
            }
        }
    }
    return @($values)
}

function Write-Utf8JsonFile {
    param([string]$Path, [object]$Value)

    $text = ($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

$releasePath = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$componentPath = Join-Path $releasePath "components"
$enumCount = 0
$innerPositionCount = 0

foreach ($file in @(Get-ChildItem -LiteralPath $componentPath -Filter '*.json' -File | Sort-Object Name)) {
    $document = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    $changed = $false
    foreach ($property in @($document.properties)) {
        if ([string]$property.path -eq "InnerPosition") {
            $property.affectsDisplay = $false
            $property.previewPolicy = "skip"
            $property.requiredEditor = "none"
            $property.disposition.kind = "omitted"
            $property.disposition.reasonCodes = @("lowDesignTimeValue")
            $innerPositionCount++
            $changed = $true
        }
        if ([string]$property.valueContract.kind -ne "enum" -or [string]$property.disposition.kind -ne "editable") {
            continue
        }
        $values = @(Get-DocumentedEnumValues $property)
        if ($values.Count -lt 2) { continue }
        $property.valueContract | Add-Member -NotePropertyName values -NotePropertyValue $values -Force
        $enumCount++
        $changed = $true
    }
    if ($changed) {
        Write-Utf8JsonFile $file.FullName $document
    }
}

Write-Output "Normalized $enumCount finite editable enum contracts and omitted $innerPositionCount InnerPosition properties."

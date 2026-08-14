<#
.SYNOPSIS
Marks audited text surfaces that use arrays to represent display lines.

.DESCRIPTION
Classifies the seven component Text properties, 37 Tooltip properties, and
uitextarea.Value as multilineText. This semantic kind deliberately excludes
Items, tick labels, table labels, and other string-list data that require
different structured editors.

.EXAMPLE
./MarkMultilineTextProperties.ps1 -ReleaseDirectory ./R2024a
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$ReleaseDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Utf8JsonFile {
    param([string]$Path, [object]$Value)

    $text = ($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

$releasePath = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$componentPath = Join-Path $releasePath "components"
$counts = @{ Text = 0; Tooltip = 0; Value = 0 }

foreach ($file in @(Get-ChildItem -LiteralPath $componentPath -Filter '*.json' -File | Sort-Object Name)) {
    $document = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    $changed = $false
    foreach ($property in @($document.properties)) {
        $isText = [string]$property.path -eq "Text" -and [string]$property.valueContract.kind -eq "stringList" -and
            (@($property.documentedAcceptedValues) -join " ") -match "cell array of character vectors"
        $isTooltip = [string]$property.path -eq "Tooltip" -and [string]$property.valueContract.kind -eq "stringList"
        $isTextAreaValue = [string]$document.id -eq "uitextarea" -and [string]$property.path -eq "Value" -and
            [string]$property.valueContract.kind -eq "stringList"
        if (-not ($isText -or $isTooltip -or $isTextAreaValue)) { continue }

        $property.valueContract.kind = "multilineText"
        $property.requiredEditor = "multilineText"
        if ($isText) { $counts.Text++ }
        elseif ($isTooltip) { $counts.Tooltip++ }
        else { $counts.Value++ }
        $changed = $true
    }
    if ($changed) { Write-Utf8JsonFile $file.FullName $document }
}

if ($counts.Text -ne 7 -or $counts.Tooltip -ne 37 -or $counts.Value -ne 1) {
    throw "Expected 7 Text, 37 Tooltip, and 1 uitextarea.Value surfaces; found Text=$($counts.Text), Tooltip=$($counts.Tooltip), Value=$($counts.Value)."
}
Write-Output "Classified $($counts.Text) Text, $($counts.Tooltip) Tooltip, and $($counts.Value) uitextarea.Value surfaces as multilineText."

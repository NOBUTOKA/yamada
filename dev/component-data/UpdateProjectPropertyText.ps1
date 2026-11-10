<#
.SYNOPSIS
Refreshes project-authored summaries without changing reviewed capabilities.
.DESCRIPTION
Uses API identifiers and value contracts for descriptions and canonicalizes
optional value notation. All component schemas are checked before any write.
#>
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ReleaseDirectory)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ComponentLedger.ps1')
. (Join-Path $PSScriptRoot 'ProjectPropertyText.ps1')
Assert-ComponentLedgerSchema -ReleaseDirectory $ReleaseDirectory

$count = 0
foreach ($file in Get-ChildItem (Join-Path $ReleaseDirectory 'components') -Filter '*.json' -File) {
    $document = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    foreach ($property in $document.properties) {
        $property.summary = Get-ProjectPropertySummary $property
        if ($property.PSObject.Properties['documentedDefault']) {
            $property.documentedDefault = ConvertTo-ProjectValueNotation $property.documentedDefault
        }
        if ($property.PSObject.Properties['documentedAcceptedValues']) {
            $property.documentedAcceptedValues = @($property.documentedAcceptedValues | ForEach-Object {
                ConvertTo-ProjectValueNotation $_
            })
        }
        $count++
    }
    [IO.File]::WriteAllText($file.FullName, ($document | ConvertTo-Json -Depth 100) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
Write-Output "PROJECT_PROPERTY_TEXT Updated=$count"

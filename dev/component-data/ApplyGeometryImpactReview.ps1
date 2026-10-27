<#
.SYNOPSIS
Records reviewed Safe Preview geometry impacts in the authoritative ledger.
.DESCRIPTION
Uses documented layout mechanisms and conservative inference. Unknown properties
retain required geometry refresh; this script never asserts runtime observations.
#>
[CmdletBinding()]
param([string]$ReleaseDirectory = (Join-Path $PSScriptRoot 'R2024a'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ComponentLedger.ps1')
Assert-ComponentLedgerSchema -ReleaseDirectory $ReleaseDirectory

function Set-GeometryImpact {
    param([object]$Property, [string]$Factory)
    $path = [string]$Property.path
    $grid = 'required'
    $absolute = $true
    $detail = 'Unproven geometry or interaction effect: retain full refresh.'
    if ($Property.previewPolicy -in @('skip', 'notRendered')) {
        $grid = 'none'; $absolute = $false
        $detail = 'Safe Preview does not apply this property; it cannot change native preview geometry.'
    }
    elseif ($path -match 'Color$' -or $path -in @('Tooltip', 'HorizontalAlignment', 'VerticalAlignment')) {
        $grid = 'none'; $absolute = $false
        $detail = 'Paint, alignment within an assigned rectangle, or hover text does not change the assigned rectangle.'
    }
    elseif ($path -in @('Text', 'FontSize', 'FontName', 'FontWeight', 'FontAngle', 'WordWrap', 'Interpreter')) {
        $grid = 'fit'; $absolute = $false
        $detail = 'Text metrics can resize fit tracks; a freely positioned control retains its assigned rectangle.'
        if ($Factory -in @('uipanel', 'uibuttongroup', 'uitab', 'uitabgroup', 'uifigure', 'axes', 'uiaxes', 'polaraxes', 'geoaxes')) {
            $grid = 'required'; $absolute = $true
            $detail = 'Container or axes text metrics can also alter the child content area or public inner/outer geometry.'
        }
    }
    elseif ($path -eq 'Value' -and $Factory -in @('uieditfield', 'uispinner', 'uislider', 'uigauge', 'uiknob', 'uiswitch', 'uibutton', 'uitogglebutton', 'uicheckbox', 'uiradiobutton')) {
        $grid = 'none'; $absolute = $false
        $detail = 'The value changes displayed state inside the assigned rectangle, not layout metrics.'
        if ($Property.valueContract.kind -in @('text', 'multilineText')) {
            $grid = 'fit'
            $detail = 'Text-valued content may change preferred size in a fit track; free-position bounds remain assigned.'
        }
    }
    $Property | Add-Member -Force -NotePropertyName gridGeometryImpact -NotePropertyValue $grid
    $Property | Add-Member -Force -NotePropertyName absoluteGeometryImpact -NotePropertyValue $absolute
    $Property | Add-Member -Force -NotePropertyName geometryEvidence -NotePropertyValue @([ordered]@{
        kind = 'inference'; source = 'PROPERTY_AUDIT_GUIDELINES.md#geometry-impact'; detail = $detail
    })
}

foreach ($file in Get-ChildItem -LiteralPath (Join-Path $ReleaseDirectory 'components') -Filter '*.json' -File) {
    $document = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    foreach ($property in $document.properties) { Set-GeometryImpact $property ([string]$document.factory) }
    [IO.File]::WriteAllText($file.FullName, (($document | ConvertTo-Json -Depth 100) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}
$path = Join-Path $ReleaseDirectory 'parent-context-rules.json'
$rules = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
foreach ($rule in $rules.rules | Where-Object effect -EQ 'contributed') { Set-GeometryImpact $rule '' }
[IO.File]::WriteAllText($path, (($rules | ConvertTo-Json -Depth 100) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

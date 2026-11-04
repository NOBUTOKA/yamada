<#
.SYNOPSIS
Applies reviewed R2024a callback event contracts to concrete ledger properties.
.DESCRIPTION
Keeps documentation and installed-release evidence in the ledger. Empty type names
leave unresolved events untyped; no runtime audit-status state machine is needed.
#>
[CmdletBinding()]
param([string]$ReleaseDirectory = (Join-Path $PSScriptRoot 'R2024a'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Explicit concrete variants share reviewed value-event contracts, not inferred name prefixes.
$contracts = @{}
foreach ($variant in @('uibutton-state','uicheckbox','uicolorpicker','uidatepicker','uidropdown',
    'uieditfield-numeric','uieditfield-text','uiknob-continuous','uiknob-discrete','uilistbox',
    'uislider-range','uislider-slider','uispinner','uiswitch-rocker','uiswitch-slider','uiswitch-toggle','uitextarea')) {
    $contracts["${variant}:ValueChangedFcn"] = 'ValueChangedData'
}
foreach ($variant in @('uieditfield-text','uiknob-continuous','uislider-range','uislider-slider','uispinner','uitextarea')) {
    $contracts["${variant}:ValueChangingFcn"] = 'ValueChangingData'
}
$contracts['uibutton-push:ButtonPushedFcn'] = 'ButtonPushedData'
$contracts['uidropdown:DropDownOpeningFcn'] = 'DropDownOpeningData'
$contracts['uicontextmenu:ContextMenuOpeningFcn'] = 'ContextMenuOpeningData'
$contracts['uihtml:DataChangedFcn'] = 'DataChangedData'
$contracts['uihtml:HTMLEventReceivedFcn'] = 'HTMLEventReceivedData'
$contracts['uihyperlink:HyperlinkClickedFcn'] = 'HyperlinkClickedData'
$contracts['uiimage:ImageClickedFcn'] = 'ImageClickedData'
$contracts['uimenu:MenuSelectedFcn'] = 'MenuSelectedData'
foreach ($variant in @('uitree','uitree-checkbox')) {
    $contracts["${variant}:SelectionChangedFcn"] = 'SelectedNodesChangedData'
    $contracts["${variant}:NodeExpandedFcn"] = 'NodeExpandedData'
    $contracts["${variant}:NodeCollapsedFcn"] = 'NodeCollapsedData'
    $contracts["${variant}:NodeTextChangedFcn"] = 'NodeTextChangedData'
}
$contracts['uitree-checkbox:CheckedNodesChangedFcn'] = 'CheckedNodesChangedData'
foreach ($variant in @('uibuttongroup','uitabgroup','uitable')) {
    $contracts["${variant}:SelectionChangedFcn"] = 'SelectionChangedData'
}
$contracts['uitable:CellEditCallback'] = 'CellEditData'
$contracts['uitable:DisplayDataChangedFcn'] = 'DisplayDataChangedData'
foreach ($variant in @('uifigure','uitable')) {
    $contracts["${variant}:KeyPressFcn"] = 'KeyData'
    $contracts["${variant}:KeyReleaseFcn"] = 'KeyData'
}
$contracts['uifigure:WindowKeyPressFcn'] = 'KeyData'
$contracts['uifigure:WindowKeyReleaseFcn'] = 'KeyData'
$contracts['uifigure:WindowScrollWheelFcn'] = 'ScrollWheelData'
foreach ($name in @('WindowButtonDownFcn','WindowButtonMotionFcn','WindowButtonUpFcn')) {
    $contracts["uifigure:$name"] = 'WindowMouseData'
}

$total = 0; $typed = 0
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $ReleaseDirectory 'components') -Filter '*.json' -File) {
    $document = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    $documentation = @($document.sources | Where-Object { $_.scope -like '*properties*' -or $_.scope -like '*Properties*' })
    if ($documentation.Count -eq 0) { $documentation = @($document.sources | Select-Object -Last 1) }
    foreach ($property in $document.properties) {
        if ($property.valueContract.kind -ne 'callback') { continue }
        $className = ''; $shape = @()
        $detail = 'No safe concrete event type is established by this reviewed contract; preserve an untyped event argument.'
        $key = $document.id + ':' + $property.path
        if ($contracts.ContainsKey($key)) {
            $className = 'matlab.ui.eventdata.' + $contracts[$key]
            $detail = 'The callback documents the ' + $contracts[$key] + ' event object. The qualified class is present in initialized MATLAB R2024a.'
        }
        $evidence = @([ordered]@{kind='mathworksDocumentation'; source=([string]$documentation[0].url).Replace('/r2024a/','/R2024a/'); detail=$property.path + ': ' + $detail})
        # These observed legacy callback values disprove a universal event.EventData fallback.
        if ($document.id -in @('uifigure','uibutton-push') -and $property.path -eq 'CreateFcn') {
            $className = 'double'; $shape = @(0,0)
            $evidence += [ordered]@{kind='nativeObservation';source='MATLAB R2024a owned uifigure/uibutton fixture';detail='CreateFcn receives an empty 0-by-0 double, not event.EventData.'}
        }
        if ($document.id -in @('uifigure','uibutton-push') -and $property.path -eq 'DeleteFcn') {
            $className = 'event.EventData'
            $evidence += [ordered]@{kind='nativeObservation';source='MATLAB R2024a owned uifigure/uibutton fixture';detail='DeleteFcn receives event.EventData; no more specific public type is required.'}
        }
        $signature = [ordered]@{eventArgument=[ordered]@{className=$className;shape=$shape};evidence=$evidence}
        $property | Add-Member -NotePropertyName callbackSignature -NotePropertyValue $signature -Force
        $total++
        if ($className -ne '') { $typed++ }
    }
    [IO.File]::WriteAllText($file.FullName, ($document | ConvertTo-Json -Depth 100) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
Write-Output "CALLBACK_CONTRACTS Total=$total Typed=$typed Untyped=$($total-$typed)"

# Copyright (C) 2026 Nobuto Kaitoh
# SPDX-License-Identifier: GPL-3.0-or-later
# This file is part of yamada. See LICENSE for the license text.

<#
.SYNOPSIS
Records the reviewed method suffix on every concrete R2024a callback entry.
.DESCRIPTION
Suffixes are project naming choices, separate from event contracts. Only explicit
component/callback decisions shorten names; unchanged outcomes remain explicit.
#>
[CmdletBinding()]
param([string]$ReleaseDirectory = (Join-Path $PSScriptRoot 'R2024a'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$reviewed = @{
    'uibutton-push:ButtonPushedFcn' = 'Pushed'
    'uimenu:MenuSelectedFcn' = 'Selected'
    'uihyperlink:HyperlinkClickedFcn' = 'Clicked'
    'uiimage:ImageClickedFcn' = 'Clicked'
    'uihtml:HTMLEventReceivedFcn' = 'EventReceived'
}
$total = 0
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $ReleaseDirectory 'components') -Filter '*.json' -File) {
    $document = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    foreach ($property in $document.properties) {
        if ($property.valueContract.kind -ne 'callback') { continue }
        $key = $document.id + ':' + $property.path
        $suffix = ([string]$property.path).Replace('Fcn','')
        if ($reviewed.ContainsKey($key)) { $suffix = $reviewed[$key] }
        $property | Add-Member -NotePropertyName handlerSuffix -NotePropertyValue $suffix -Force
        $total++
    }
    [IO.File]::WriteAllText($file.FullName, ($document | ConvertTo-Json -Depth 100) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
Write-Output "CALLBACK_SUFFIXES Explicit=$total"

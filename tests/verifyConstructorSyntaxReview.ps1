# Copyright (C) 2026 Nobuto Kaitoh
# SPDX-License-Identifier: GPL-3.0-or-later
# This file is part of yamada. See LICENSE for the license text.

<#
.SYNOPSIS
Verifies complete constructor documentation coverage and atomic retirement of support flags.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root 'dev/component-data'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('yamada-constructor-review-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

function Get-LedgerHash {
    param([string]$Release)
    return (@(Get-ChildItem -LiteralPath (Join-Path $Release 'components') -Filter '*.json' |
        Sort-Object Name | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ',')
}

try {
    $release = Join-Path $temporaryRoot 'R2024a'
    Copy-Item -LiteralPath (Join-Path $tools 'R2024a') -Destination $release -Recurse
    $path = Join-Path $release 'CONSTRUCTOR_SYNTAX_REVIEW.json'
    $original = Get-Content -LiteralPath $path -Raw
    $review = $original | ConvertFrom-Json
    if ($review.factories.Count -ne 38 -or $review.variants.Count -ne 48) { throw 'Constructor review does not cover the complete catalog.' }
    $total = 0
    foreach ($variant in $review.variants) {
        $classified = @($variant.documentedReadOnly) + @($variant.restrictedSetter) + @($variant.documentedWritable)
        if ($classified.Count -ne $variant.priorUnknownCount -or @($classified | Sort-Object -Unique).Count -ne $classified.Count) {
            throw "Constructor review does not classify every previous unknown for $($variant.componentId)."
        }
        $total += $classified.Count
    }
    if ($total -ne 1542) { throw 'The previous unknown constructor entries are not fully accounted for.' }

    # Old support flags must be retired without changing any other application policy.
    $file = Join-Path $release 'components/uilabel.json'
    $ledger = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    $ledger.properties[0].application | Add-Member -NotePropertyName nameValue -NotePropertyValue 'unknown'
    [IO.File]::WriteAllText($file, ($ledger | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    $apply = Join-Path $tools 'ApplyConstructorSyntaxReview.ps1'
    & $apply -ReleaseDirectory $release | Out-Null
    $expected = Get-LedgerHash $release
    & $apply -ReleaseDirectory $release | Out-Null
    if ($expected -cne (Get-LedgerHash $release)) { throw 'Constructor review application is not idempotent.' }
    foreach ($case in @('missingFactory', 'duplicate', 'wrongReleaseSource', 'missingSyntax')) {
        $review = $original | ConvertFrom-Json
        switch ($case) {
            'missingFactory' { $review.factories = @($review.factories | Select-Object -SkipLast 1) }
            'duplicate' { $review.factories += $review.factories[0] }
            'wrongReleaseSource' { $review.factories[-1].source = 'https://www.mathworks.com/help/matlab/ref/uitreenode.html' }
            'missingSyntax' { $review.factories[-1].constructorSyntax = '' }
        }
        [IO.File]::WriteAllText($path, ($review | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        $failed = $false
        try { & $apply -ReleaseDirectory $release | Out-Null } catch { $failed = $true }
        if (-not $failed -or $expected -cne (Get-LedgerHash $release)) { throw "Invalid constructor evidence $case was not rejected atomically." }
    }
    Write-Output 'CONSTRUCTOR_SYNTAX_REVIEW_TEST Passed: 38 factories, 48 variants, 1542 classified unknowns, flag removal, idempotence, atomic evidence rejection.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($temporaryRoot)
    $base = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notlike 'yamada-constructor-review-*') { throw 'Unsafe temporary cleanup boundary.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

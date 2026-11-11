# Copyright (C) 2026 Nobuto Kaitoh
# SPDX-License-Identifier: GPL-3.0-or-later
# This file is part of yamada. See LICENSE for the license text.

<#
.SYNOPSIS
Verifies reproducible setter review application and atomic rejection of invalid evidence.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root 'dev/component-data'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('yamada-setter-review-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

function Get-LedgerHash {
    param([string]$Release)
    return (@(Get-ChildItem -LiteralPath (Join-Path $Release 'components') -Filter '*.json' |
        Sort-Object Name | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ',')
}

try {
    $release = Join-Path $temporaryRoot 'R2024a'
    Copy-Item -LiteralPath (Join-Path $tools 'R2024a') -Destination $release -Recurse
    $apply = Join-Path $tools 'ApplySetterAccessReview.ps1'
    & $apply -ReleaseDirectory $release | Out-Null
    $expected = Get-LedgerHash $release
    & $apply -ReleaseDirectory $release | Out-Null
    if ($expected -cne (Get-LedgerHash $release)) { throw 'Setter review application is not idempotent.' }
    $path = Join-Path $release 'SETTER_ACCESS_RUNTIME_REVIEW.json'
    $original = Get-Content -LiteralPath $path -Raw
    foreach ($case in @('unresolved', 'nativeMismatch', 'probeError', 'missingProperty', 'duplicate', 'documentedReadOnly')) {
        $review = $original | ConvertFrom-Json
        switch ($case) {
            'unresolved' { $review.observations[-1].runtimeSetAccess = 'unresolved' }
            'nativeMismatch' { $review.observations[-1].nativeSetAccess = 'private' }
            'probeError' { $review.observations[-1].errorId = 'NativeProbe:Failed' }
            'missingProperty' { $review.observations[-1].path = 'MissingNativeProperty' }
            'duplicate' { $review.observations += $review.observations[0] }
            'documentedReadOnly' {
                $review.observations[-1].componentId = 'uieditfield-text'
                $review.observations[-1].path = 'Type'
                $review.observations[-1].runtimeSetAccess = 'public'
                $review.observations[-1].nativeSetAccess = 'public'
            }
        }
        [IO.File]::WriteAllText($path, ($review | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        $failed = $false
        try { & $apply -ReleaseDirectory $release | Out-Null } catch { $failed = $true }
        if (-not $failed -or $expected -cne (Get-LedgerHash $release)) { throw "Invalid setter evidence $case was not rejected atomically." }
    }
    Write-Output 'SETTER_ACCESS_REVIEW_TEST Passed: idempotence and six atomic evidence rejection cases.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($temporaryRoot)
    $base = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notlike 'yamada-setter-review-*') { throw 'Unsafe temporary cleanup boundary.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

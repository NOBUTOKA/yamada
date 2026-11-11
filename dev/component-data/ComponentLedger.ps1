# Copyright (C) 2026 Nobuto Kaitoh
# SPDX-License-Identifier: GPL-3.0-or-later
# This file is part of yamada. See LICENSE for the license text.

<#
.SYNOPSIS
Provides full-schema preflight for development component ledgers.
.DESCRIPTION
Reads the release's schema and every concrete component document before a
pipeline entry point writes outputs. Graph and grouping validation remain the
responsibility of the existing policy and grouping tools. Requires PowerShell 7.
#>

function Assert-ComponentLedgerSchema {
    param([Parameter(Mandatory = $true)][string]$ReleaseDirectory)

    $schemaPath = Join-Path $ReleaseDirectory 'schema.json'
    $componentPath = Join-Path $ReleaseDirectory 'components'
    if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $componentPath -PathType Container)) {
        throw "The component ledger needs schema.json and a components directory: $ReleaseDirectory"
    }
    $schema = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $schemaPath).Path)
    $files = @(Get-ChildItem -LiteralPath $componentPath -Filter '*.json' -File | Sort-Object Name)
    if ($files.Count -eq 0) { throw "The component ledger contains no documents: $ReleaseDirectory" }

    # Keep validation read-only and contextual, including malformed JSON or schema.
    foreach ($file in $files) {
        try {
            $valid = Test-Json -Json ([IO.File]::ReadAllText($file.FullName)) -Schema $schema -ErrorAction Stop
            if (-not $valid) { throw 'The document does not satisfy the component schema.' }
        }
        catch {
            throw "Component ledger schema preflight failed for '$($file.FullName)': $($_.Exception.Message)"
        }
    }
}

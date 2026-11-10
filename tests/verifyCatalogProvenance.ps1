<#
.SYNOPSIS
Verifies that catalog presentation text cannot determine semantic capabilities.
.DESCRIPTION
Uses an owned temporary ledger and preserves the project's source records.
Exercises regeneration, stale-heading replacement, reviewed enum values, and
multiline classification without relying on wording from a reference page.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root 'dev/component-data'
. (Join-Path $tools 'ProjectPropertyText.ps1')

function Assert-Contract {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Write-Record {
    param([string]$Path, [object]$Record)
    [IO.File]::WriteAllText($Path, ($Record | ConvertTo-Json -Depth 100) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Get-Capabilities {
    param([string]$Directory)
    $records = foreach ($file in Get-ChildItem (Join-Path $Directory 'components') -Filter '*.json' -File | Sort-Object Name) {
        $record = Get-Content $file.FullName -Raw | ConvertFrom-Json
        foreach ($property in $record.properties) {
            foreach ($field in @('summary', 'documentedDefault', 'documentedAcceptedValues')) {
                $property.PSObject.Properties.Remove($field)
            }
        }
        $record
    }
    return ConvertTo-Json -InputObject @($records) -Depth 100 -Compress
}

$temporary = Join-Path ([IO.Path]::GetTempPath()) ('yamada-provenance-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $ledger = Join-Path $temporary 'R2024a'
    $catalog = Join-Path $temporary 'catalog'
    Copy-Item -LiteralPath (Join-Path $tools 'R2024a') -Destination $ledger -Recurse
    $before = Get-Capabilities $ledger
    $labelPath = Join-Path $ledger 'components/uilabel.json'
    $label = Get-Content $labelPath -Raw | ConvertFrom-Json
    $text = $label.properties | Where-Object path -CEQ 'Text'
    $text.summary = 'Injected heading that must not become presentation text.'
    Write-Record $labelPath $label

    & (Join-Path $tools 'UpdateProjectPropertyText.ps1') -ReleaseDirectory $ledger | Out-Null
    Assert-Contract ($before -ceq (Get-Capabilities $ledger)) 'Presentation refresh altered semantic capabilities.'
    & (Join-Path $tools 'PromoteGroupingToRuntimeCatalog.ps1') -ReleaseDirectory $ledger -CatalogRoot $catalog | Out-Null
    $runtime = Get-Content (Join-Path $catalog 'components/uilabel.json') -Raw | ConvertFrom-Json
    $entry = @($runtime.categories | ForEach-Object { $_.entries }) | Where-Object path -CEQ 'Text'
    Assert-Contract ($entry.metadata.description -ceq 'Text rendered by the component.') 'An injected heading reached runtime metadata.'
    $first = @(Get-ChildItem $catalog -Recurse -File | Sort-Object FullName | Get-FileHash).Hash -join ','
    & (Join-Path $tools 'UpdateProjectPropertyText.ps1') -ReleaseDirectory $ledger | Out-Null
    & (Join-Path $tools 'PromoteGroupingToRuntimeCatalog.ps1') -ReleaseDirectory $ledger -CatalogRoot $catalog | Out-Null
    $second = @(Get-ChildItem $catalog -Recurse -File | Sort-Object FullName | Get-FileHash).Hash -join ','
    Assert-Contract ($first -ceq $second) 'Catalog regeneration changed on the second pass.'

    $buttonPath = Join-Path $ledger 'components/uibutton-push.json'
    $button = Get-Content $buttonPath -Raw | ConvertFrom-Json
    $enum = $button.properties | Where-Object { $_.valueContract.kind -ceq 'enum' -and $_.disposition.kind -ceq 'editable' } | Select-Object -First 1
    $expected = ConvertTo-Json -InputObject @($enum.valueContract.values) -Compress
    $enum.documentedDefault = "'unreviewed-default'"
    $enum.documentedAcceptedValues = @("'unreviewed-choice'")
    Write-Record $buttonPath $button
    & (Join-Path $tools 'NormalizeFiniteEnumValues.ps1') -ReleaseDirectory $ledger | Out-Null
    $button = Get-Content $buttonPath -Raw | ConvertFrom-Json
    $actual = $button.properties | Where-Object path -CEQ $enum.path
    Assert-Contract ($expected -ceq (ConvertTo-Json -InputObject @($actual.valueContract.values) -Compress)) 'Reference wording changed reviewed enum values.'

    $label = Get-Content $labelPath -Raw | ConvertFrom-Json
    $text = $label.properties | Where-Object path -CEQ 'Text'
    $text.valueContract.kind = 'stringList'
    $text.documentedAcceptedValues = @('Wording unrelated to the type contract.')
    Write-Record $labelPath $label
    & (Join-Path $tools 'MarkMultilineTextProperties.ps1') -ReleaseDirectory $ledger | Out-Null
    $label = Get-Content $labelPath -Raw | ConvertFrom-Json
    $text = $label.properties | Where-Object path -CEQ 'Text'
    Assert-Contract ($text.valueContract.kind -ceq 'multilineText') 'Multiline classification depended on reference wording.'
    Assert-Contract ((ConvertTo-ProjectValueNotation 'real, finite, numeric scalar between 0 and 25, inclusive') -ceq 'numeric scalar; real; finite; 0 <= value <= 25') 'Numeric limits were lost in canonical notation.'
    Assert-Contract ((ConvertTo-ProjectValueNotation "'on'") -ceq "'on'") 'An API enum token was changed.'
    Write-Output 'CATALOG_PROVENANCE Passed: semantic preservation, project text, deterministic regeneration, enum independence, multiline independence, API notation.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($temporary)
    $base = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notlike 'yamada-provenance-*') {
        throw 'Refusing cleanup outside the owned temporary directory.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

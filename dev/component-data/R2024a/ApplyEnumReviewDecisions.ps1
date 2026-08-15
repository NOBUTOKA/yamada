[CmdletBinding()]
param(
    [string]$ReleaseDirectory = $PSScriptRoot,
    [string]$DecisionPath = (Join-Path $PSScriptRoot 'ENUM_REVIEW_DECISIONS.json'),
    [string]$ReviewUnitsPath = (Join-Path $PSScriptRoot 'ENUM_REVIEW_UNITS.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Property {
    param([object]$Component, [string]$Path)
    return @($Component.properties | Where-Object { [string]$_.path -eq $Path }) | Select-Object -First 1
}

$decisions = Get-Content -Raw -LiteralPath $DecisionPath | ConvertFrom-Json
$reviewUnits = Get-Content -Raw -LiteralPath $ReviewUnitsPath | ConvertFrom-Json
$decisionMap = @{}
foreach ($decision in @($decisions.decisions)) {
    $decisionMap[[string]$decision.reviewUnitId] = $decision
}
$memberMap = @{}
foreach ($unit in @($reviewUnits.reviewUnits)) {
    foreach ($derived in @($unit.derivedEntries)) {
        $memberMap['{0}|{1}' -f [string]$derived.componentId, [string]$unit.path] = [string]$unit.reviewUnitId
    }
}

$updated = 0
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $ReleaseDirectory 'components') -Filter '*.json') {
    $component = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    $componentId = [string]$component.id

    foreach ($property in @($component.properties)) {
        if ([string]$property.valueContract.kind -ne 'enum') { continue }
        $memberKey = '{0}|{1}' -f $componentId, [string]$property.path
        if ($memberMap.ContainsKey($memberKey) -and $decisionMap.ContainsKey($memberMap[$memberKey])) {
            $decision = $decisionMap[$memberMap[$memberKey]]
        }
        else {
            # Fall back to the durable derived-component mapping because the
            # hash portion of a groupId changes when a group's values change.
            $decision = @($decisions.decisions | Where-Object {
                [string]$_.path -eq [string]$property.path -and
                @($_.derivedComponentIds) -contains $componentId
            }) | Select-Object -First 1
            if ($null -eq $decision) { continue }
        }
        $values = @($decision.values | ForEach-Object { [string]$_ })
        if ($values.Count -eq 0) { throw "Decision has no values: $($decision.reviewUnitId)" }

        # Preserve the documentation convention: accepted values exclude the default.
        $defaultText = if ($decision.PSObject.Properties.Name -contains 'documentedDefault') { [string]$decision.documentedDefault } else { '' }
        if ($defaultText) { $property.documentedDefault = $defaultText }
        elseif ($property.PSObject.Properties.Name -contains 'documentedDefault') { $property.PSObject.Properties.Remove('documentedDefault') }
        $defaultValue = if ($defaultText -match "^'(.*)'$") { $Matches[1] } else { '' }
        $property.documentedAcceptedValues = @($values | Where-Object { $_ -ne $defaultValue } | ForEach-Object { "'$_'" })
        $property.valueContract.values = $values
        $updated++
    }

    $component | ConvertTo-Json -Depth 20 | Set-Content -Encoding utf8 -LiteralPath $file.FullName
}

Write-Output "Updated $updated enum properties."

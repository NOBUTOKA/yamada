<#
.SYNOPSIS
Verifies application policy validation and complete catalog promotion.
.DESCRIPTION
Uses an independent temporary ledger copy. Source ledgers and packaged catalog
files are never modified by this verification.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $projectRoot 'dev/component-data'
. (Join-Path $toolRoot 'ApplicationPolicy.ps1')

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-PolicyFailure {
    param([scriptblock]$Action)
    $failed = $false
    try { & $Action | Out-Null }
    catch { $failed = $true }
    Assert-Condition $failed 'An invalid application policy was accepted.'
}

# Cover normalization and invalid symbols independently of the generator.
$emptyPolicy = ConvertTo-ApplicationPolicy ([pscustomobject]@{})
Assert-Condition ($emptyPolicy.nameValue -ceq 'unknown' -and $emptyPolicy.effectPolicy -ceq 'none' -and
    $emptyPolicy.applyAfter.Count -eq 0) 'An empty optional policy did not retain conservative defaults.'
$seedPolicy = ConvertTo-ApplicationPolicy ([pscustomobject]@{ defaultLiteral = '[-Inf Inf]' })
Assert-Condition ($seedPolicy.defaultLiteral -ceq '[-Inf Inf]') 'A default literal was lost in normalization.'
$modePolicy = ConvertTo-ApplicationPolicy ([pscustomobject]@{ effectPolicy = 'valueMode' })
Assert-Condition ($modePolicy.effectPolicy -ceq 'valueMode') 'An audited value/mode adapter was lost.'
Assert-PolicyFailure { ConvertTo-ApplicationPolicy ([pscustomobject]@{ defaultLiteral = 0 }) }
$policy = ConvertTo-ApplicationPolicy ([pscustomobject]@{
    applyAfter = @('ItemsData', 'Items'); nameValue = 'supported'; effectPolicy = 'itemSelection'
})
Assert-Condition (($policy.applyAfter -join ',') -ceq 'Items,ItemsData') 'Policy normalization is unstable.'
Assert-PolicyFailure { ConvertTo-ApplicationPolicy ([pscustomobject]@{ nameValue = 'SUPPORTED' }) }
Assert-PolicyFailure { ConvertTo-ApplicationPolicy ([pscustomobject]@{ effectPolicy = 'execute' }) }
Assert-PolicyFailure { ConvertTo-ApplicationPolicy ([pscustomobject]@{ applyAfter = @('Items', 'Items') }) }
Assert-PolicyFailure { Test-ApplicationPolicies @([pscustomobject]@{
    path = 'A'; application = [pscustomobject]@{ applyAfter = @('Missing') }
}) 'fixture' }
Assert-PolicyFailure { Test-ApplicationPolicies @(
    [pscustomobject]@{ path = 'A'; application = [pscustomobject]@{ applyAfter = @('B') } },
    [pscustomobject]@{ path = 'B'; application = [pscustomobject]@{ applyAfter = @('A') } }
) 'fixture' }

# Rebuild the real pipeline with an intentionally changed capability in an owned copy.
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('yamada-application-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
try {
    $releaseRoot = Join-Path $temporaryRoot 'R2024a'
    Copy-Item -LiteralPath (Join-Path $toolRoot 'R2024a') -Destination $releaseRoot -Recurse
    $ledgerPath = Join-Path $releaseRoot 'components/uidropdown.json'
    $ledger = Get-Content -Raw -LiteralPath $ledgerPath | ConvertFrom-Json
    $value = $ledger.properties | Where-Object { $_.path -ceq 'Value' }
    $value | Add-Member -MemberType NoteProperty -Name application -Value ([pscustomobject]$policy) -Force
    $value | Add-Member -MemberType NoteProperty -Name applicationEvidence -Value @(
        [pscustomobject]@{ kind = 'inference'; source = 'owned promotion fixture'; detail = 'Test capability propagation.' }
    ) -Force
    [IO.File]::WriteAllText($ledgerPath, ($ledger | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    $schema = Get-Content -Raw -LiteralPath (Join-Path $releaseRoot 'schema.json') | ConvertFrom-Json
    $policySchema = [ordered]@{ '$schema' = $schema.'$schema'; '$ref' = '#/$defs/application'; '$defs' = $schema.'$defs' } | ConvertTo-Json -Depth 100
    Assert-Condition (Test-Json -Json ($value.application | ConvertTo-Json -Depth 10) -Schema $policySchema) 'Application policy violates its schema.'

    & (Join-Path $toolRoot 'GenerateGroupingArtifacts.ps1') -ReleaseDirectory $releaseRoot | Out-Null
    & (Join-Path $toolRoot 'GenerateGroupingDesign.ps1') -ReleaseDirectory $releaseRoot | Out-Null
    $catalogRoot = Join-Path $temporaryRoot 'catalog'
    & (Join-Path $toolRoot 'PromoteGroupingToRuntimeCatalog.ps1') -ReleaseDirectory $releaseRoot -CatalogRoot $catalogRoot | Out-Null
    $runtime = Get-Content -Raw -LiteralPath (Join-Path $catalogRoot 'components/uidropdown.json') | ConvertFrom-Json
    $entries = @($runtime.categories | ForEach-Object { $_.entries })
    $promoted = $entries | Where-Object { $_.path -ceq 'Value' }
    Assert-Condition ($promoted.metadata.application.nameValue -ceq 'supported') 'Constructor support was lost during promotion.'
    Assert-Condition (($promoted.metadata.application.applyAfter -join ',') -ceq 'Items,ItemsData') 'Application dependencies were lost during promotion.'
    Assert-Condition ($promoted.metadata.application.effectPolicy -ceq 'itemSelection') 'Effect policy was lost during promotion.'
    Assert-Condition ($null -eq $promoted.metadata.PSObject.Properties['applicationEvidence']) 'Evidence leaked into runtime metadata.'
    $gauge = Get-Content -Raw -LiteralPath (Join-Path $catalogRoot 'components/uigauge-circular.json') | ConvertFrom-Json
    Assert-Condition ($gauge.capabilities.overlayShapesByStyle.ninetydegree -ceq 'quarterCircle' -and
        $gauge.capabilities.overlayShapesByStyle.semicircular -ceq 'semicircle') 'Promotion lost reviewed gauge style silhouettes.'
    $slider = Get-Content -Raw -LiteralPath (Join-Path $catalogRoot 'components/uislider-slider.json') | ConvertFrom-Json
    $sliderValue = @($slider.categories | ForEach-Object { $_.entries }) | Where-Object path -CEQ 'Value'
    Assert-Condition ($sliderValue.metadata.application.defaultLiteral -ceq '0') 'An audited default seed was lost during promotion.'
    $first = [IO.File]::ReadAllBytes((Join-Path $catalogRoot 'components/uidropdown.json'))
    & (Join-Path $toolRoot 'PromoteGroupingToRuntimeCatalog.ps1') -ReleaseDirectory $releaseRoot -CatalogRoot $catalogRoot | Out-Null
    $second = [IO.File]::ReadAllBytes((Join-Path $catalogRoot 'components/uidropdown.json'))
    Assert-Condition ([Convert]::ToBase64String($first) -ceq [Convert]::ToBase64String($second)) 'Repeated promotion changed identical output.'
    Write-Output 'APPLICATION_POLICY_VERIFICATION Passed: normalization, rejection, schema, grouping, promotion, evidence isolation, reproducibility.'
}
finally {
    # Delete only the exact temporary directory created and resolved by this test.
    $resolvedRoot = [IO.Path]::GetFullPath($temporaryRoot)
    $resolvedTemporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolvedRoot.StartsWith($resolvedTemporaryBase, [StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Leaf $resolvedRoot) -notlike 'yamada-application-*') {
        throw 'Temporary verification directory failed cleanup boundary validation.'
    }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
}

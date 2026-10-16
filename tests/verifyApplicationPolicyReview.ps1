<#
.SYNOPSIS
Verifies reviewed ledger rules, deterministic application, and validation isolation.
.DESCRIPTION
Uses a fresh owned temporary directory. Never writes to the project ledger.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $projectRoot 'dev/component-data'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('yamada-policy-review-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-LedgerHashes {
    param([string]$Root)
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Root 'components') -Filter '*.json' | Sort-Object Name)
    return @($files | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ','
}

try {
    $releaseRoot = Join-Path $temporaryRoot 'R2024a'
    Copy-Item -LiteralPath (Join-Path $toolRoot 'R2024a') -Destination $releaseRoot -Recurse
    $apply = Join-Path $toolRoot 'ApplyApplicationPolicyReview.ps1'
    & $apply -ReleaseDirectory $releaseRoot | Out-Null
    $first = Get-LedgerHashes $releaseRoot
    & $apply -ReleaseDirectory $releaseRoot | Out-Null
    Assert-Condition ($first -ceq (Get-LedgerHashes $releaseRoot)) 'Reviewed rules are not reproducible.'
    $auditPath = Join-Path $releaseRoot 'APPLICATION_POLICY_AUDIT.json'
    $auditHash = (Get-FileHash -LiteralPath $auditPath -Algorithm SHA256).Hash

    # Assert actual reviewed contracts rather than duplicating the graph algorithm.
    $dropdown = Get-Content -LiteralPath (Join-Path $releaseRoot 'components/uidropdown.json') -Raw | ConvertFrom-Json
    $value = $dropdown.properties | Where-Object path -CEQ 'Value'
    Assert-Condition (($value.application.applyAfter -join ',') -ceq 'Editable,Items,ItemsData') 'Dropdown domain prerequisites were lost.'
    Assert-Condition ($value.application.nameValue -ceq 'supported') 'Verified Dropdown constructor support was lost.'
    Assert-Condition ($value.applicationEvidence[0].kind -ceq 'inference') 'An inferred ordering was misrepresented as an explicit documentation command.'
    Assert-Condition (@($value.applicationEvidence | Where-Object kind -CEQ 'runtime').Count -eq 1) 'Constructor evidence is missing or duplicated.'
    $date = Get-Content -LiteralPath (Join-Path $releaseRoot 'components/uidatepicker.json') -Raw | ConvertFrom-Json
    $dateValue = $date.properties | Where-Object path -CEQ 'Value'
    Assert-Condition ($dateValue.application.nameValue -ceq 'unknown') 'Unverified date constructor support was asserted.'
    $axes = Get-Content -LiteralPath (Join-Path $releaseRoot 'components/uiaxes.json') -Raw | ConvertFrom-Json
    $ticks = $axes.properties | Where-Object path -CEQ 'XTick'
    $mode = $axes.properties | Where-Object path -CEQ 'XTickMode'
    Assert-Condition ($ticks.application.effectPolicy -ceq 'valueMode') 'Audited axes mode effects were lost.'
    Assert-Condition (($mode.application.applyAfter -join ',') -ceq 'XTick') 'A final axes mode must follow its value.'
    Assert-Condition ($mode.application.defaultLiteral -ceq "'auto'") 'The documented automatic mode seed was lost.'
    Assert-Condition ($mode.application.nameValue -ceq 'supported') 'Verified axes constructor mode support was lost.'
    $width = $axes.properties | Where-Object path -CEQ 'MinorGridLineWidth'
    $widthMode = $axes.properties | Where-Object path -CEQ 'MinorGridLineWidthMode'
    $color = $axes.properties | Where-Object path -CEQ 'GridColor'
    Assert-Condition ($width.application.effectPolicy -ceq 'axisWidth') 'Width follower semantics were lost.'
    Assert-Condition (($widthMode.application.applyAfter -join ',') -ceq 'GridLineWidthMode,MinorGridLineWidth') 'Final width mode ordering was lost.'
    Assert-Condition ($width.application.defaultLiteral -ceq '0.5') 'The audited width seed was lost.'
    Assert-Condition ($width.application.nameValue -ceq 'supported') 'Verified width constructor support was lost.'
    Assert-Condition ($color.application.effectPolicy -ceq 'modeFlag') 'Stored color semantics were confused with computed auto values.'
    $geographic = Get-Content -LiteralPath (Join-Path $releaseRoot 'components/geoaxes.json') -Raw | ConvertFrom-Json
    $direction = $geographic.properties | Where-Object path -CEQ 'TickDir'
    Assert-Condition ($null -eq $direction.PSObject.Properties['application'] -or
        $direction.application.effectPolicy -cne 'valueMode') 'Unresolved geographic direction behavior was generalized.'
    foreach ($style in @('circular', 'linear', 'ninetydegree', 'semicircular')) {
        $gauge = Get-Content -LiteralPath (Join-Path $releaseRoot "components/uigauge-$style.json") -Raw | ConvertFrom-Json
        $gaugeValue = $gauge.properties | Where-Object path -CEQ 'Value'
        Assert-Condition (@($gaugeValue.valueContract.constraints | Where-Object kind -CEQ 'withinLimitsOf').Count -eq 0) 'Gauge inherited a slider constraint.'
    }

    # Native setter access must survive promotion without changing the product disposition.
    $tree = Get-Content -LiteralPath (Join-Path $releaseRoot 'components/uitree-checkbox.json') -Raw | ConvertFrom-Json
    $position = $tree.properties | Where-Object path -CEQ 'Position'
    $inner = $tree.properties | Where-Object path -CEQ 'InnerPosition'
    $outer = $tree.properties | Where-Object path -CEQ 'OuterPosition'
    Assert-Condition ($position.runtimeSetAccess -ceq 'public' -and $position.disposition.kind -ceq 'editable') 'Checkbox Tree Position access was not corrected.'
    Assert-Condition ($inner.runtimeSetAccess -ceq 'public' -and $inner.disposition.kind -ceq 'omitted') 'A source alias was confused with inspector editability.'
    Assert-Condition ($outer.runtimeSetAccess -ceq 'restricted' -and $outer.disposition.kind -ceq 'omitted') 'A read-only alias gained a public setter.'
    Assert-Condition ($inner.runtimeObservations.Count -eq 1) 'Runtime setter evidence is missing or duplicated.'
    Assert-Condition ($null -eq $inner.PSObject.Properties['application']) 'Setter access was mistaken for constructor or resolver support.'
    $audit = Get-Content -LiteralPath $auditPath -Raw | ConvertFrom-Json
    $treeAudit = $audit.variants | Where-Object id -CEQ 'uitree-checkbox'
    Assert-Condition ($treeAudit.policyReviewStatus -ceq 'pending' -and $treeAudit.runtimeVerificationStatus -ceq 'partial') 'A native access check completed the policy review.'

    # Validate the newly written fields against their actual ledger schema fragments.
    $schema = Get-Content -LiteralPath (Join-Path $releaseRoot 'schema.json') -Raw | ConvertFrom-Json
    $accessSchema = [ordered]@{
        type = 'object'; additionalProperties = $false
        required = @('runtimeSetAccess', 'runtimeObservations')
        properties = [ordered]@{
            runtimeSetAccess = $schema.'$defs'.property.properties.runtimeSetAccess
            runtimeObservations = $schema.'$defs'.property.properties.runtimeObservations
        }
    } | ConvertTo-Json -Depth 20
    $runtimePath = Join-Path $releaseRoot 'APPLICATION_POLICY_RUNTIME_REVIEW.json'
    $originalRuntime = Get-Content -LiteralPath $runtimePath -Raw
    $runtime = $originalRuntime | ConvertFrom-Json
    foreach ($observation in $runtime.setterAccess) {
        foreach ($id in $observation.variants) {
            $ledger = Get-Content -LiteralPath (Join-Path $releaseRoot "components/$id.json") -Raw | ConvertFrom-Json
            $property = $ledger.properties | Where-Object path -CEQ $observation.path
            $fields = [ordered]@{
                runtimeSetAccess = $property.runtimeSetAccess; runtimeObservations = $property.runtimeObservations
            } | ConvertTo-Json -Depth 10
            Assert-Condition (Test-Json -Json $fields -Schema $accessSchema) "Access evidence violates the schema for $id.$($observation.path)."
        }
    }

    # Reject late invalid observations atomically, including documentation conflicts.
    foreach ($case in @('unpassed', 'unknownAccess', 'documentedReadOnly', 'duplicateTarget',
            'unreviewedConstructor', 'arrayMethod', 'missingProperty')) {
        $runtime = $originalRuntime | ConvertFrom-Json
        switch ($case) {
            'unpassed' { $runtime.setterAccess[-1].result = 'pending' }
            'unknownAccess' { $runtime.setterAccess[-1].runtimeSetAccess = 'unresolved' }
            'documentedReadOnly' { $runtime.setterAccess[-1].runtimeSetAccess = 'public' }
            'duplicateTarget' { $runtime.setterAccess += $runtime.setterAccess[0] }
            'arrayMethod' { $runtime.setterAccess[-1].testMethod = @('positionAliasesExposeNativeSetterAccess') }
            'missingProperty' { $runtime.setterAccess[-1].path = 'MissingNativeProperty' }
            'unreviewedConstructor' {
                $runtime.coverage += [pscustomobject]@{
                    testMethod = 'positionAliasesExposeNativeSetterAccess'; variants = @('uitree-checkbox')
                    nameValuePaths = @('Position'); result = 'passed'; detail = 'A setter check is not a policy review.'
                }
            }
        }
        [IO.File]::WriteAllText($runtimePath, ($runtime | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        $failed = $false
        try { & $apply -ReleaseDirectory $releaseRoot | Out-Null } catch { $failed = $true }
        Assert-Condition $failed "Invalid setter observation $case was accepted."
        Assert-Condition ($first -ceq (Get-LedgerHashes $releaseRoot)) "Setter observation $case changed a ledger."
        Assert-Condition ($auditHash -ceq (Get-FileHash -LiteralPath $auditPath -Algorithm SHA256).Hash) "Setter observation $case changed the audit."
    }
    [IO.File]::WriteAllText($runtimePath, $originalRuntime, [Text.UTF8Encoding]::new($false))

    # A late invalid rule must not partially rewrite earlier validated components.
    $reviewPath = Join-Path $releaseRoot 'APPLICATION_POLICY_REVIEW.json'
    $review = Get-Content -LiteralPath $reviewPath -Raw | ConvertFrom-Json
    $review.rules[-1].applyAfter = @('MissingDependency')
    [IO.File]::WriteAllText($reviewPath, ($review | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    $failed = $false
    try { & $apply -ReleaseDirectory $releaseRoot | Out-Null } catch { $failed = $true }
    Assert-Condition $failed 'A missing dependency was accepted.'
    Assert-Condition ($first -ceq (Get-LedgerHashes $releaseRoot)) 'Validation failure changed a ledger.'
    Assert-Condition ($auditHash -ceq (Get-FileHash -LiteralPath $auditPath -Algorithm SHA256).Hash) 'Validation failure changed the audit.'
    Write-Output 'APPLICATION_POLICY_REVIEW Passed: reviewed rules, native setter access, conservative constructor support, gauge exception, reproducibility, atomic validation failures.'
}
finally {
    $resolvedRoot = [IO.Path]::GetFullPath($temporaryRoot)
    $temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolvedRoot.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedRoot) -notlike 'yamada-policy-review-*') {
        throw 'Temporary verification directory failed cleanup boundary validation.'
    }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
}

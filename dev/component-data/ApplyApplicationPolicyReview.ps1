<#
.SYNOPSIS
Applies explicitly reviewed initialization rules to the development ledger.
.DESCRIPTION
Uses release-fixed source URLs and a separate review artifact. Unknown
constructor support remains unknown. Does not infer rules from candidate text
or promote artifacts into the runtime catalog.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ApplicationPolicy.ps1')
$reviewPath = Join-Path $ReleaseDirectory 'APPLICATION_POLICY_REVIEW.json'
$review = Get-Content -LiteralPath $reviewPath -Raw | ConvertFrom-Json
$auditPath = Join-Path $ReleaseDirectory 'APPLICATION_POLICY_AUDIT.json'
$audit = Get-Content -LiteralPath $auditPath -Raw | ConvertFrom-Json
if ($review.matlabRelease -cne $audit.matlabRelease) { throw 'Review release does not match the source audit.' }

# Validate all candidates before writing any ledger, preserving unrelated fields.
$documents = [ordered]@{}
$targets = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($rule in $review.rules) {
    if ($rule.kind -cnotin @('documentation', 'inference') -or
        $rule.detail -isnot [string] -or [string]::IsNullOrWhiteSpace($rule.detail) -or
        $rule.variants -isnot [array] -or $rule.variants.Count -eq 0) {
        throw 'A reviewed rule needs variants, a documentation/inference kind, and a rationale.'
    }
    foreach ($id in $rule.variants) {
        if ($id -cnotmatch '^[a-z][a-z0-9-]*$' -or -not $targets.Add("$id.$($rule.path)")) {
            throw 'A reviewed property target must be unique and use a valid component ID.'
        }
        if (-not $documents.Contains($id)) {
            $path = Join-Path $ReleaseDirectory "components/$id.json"
            $documents[$id] = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        }
        $ledger = $documents[$id]
        $property = @($ledger.properties | Where-Object path -CEQ $rule.path)
        if ($property.Count -ne 1) { throw "Expected one $id.$($rule.path) in the ledger." }
        $raw = [ordered]@{}
        if ($null -ne $rule.PSObject.Properties['applyAfter']) { $raw.applyAfter = @($rule.applyAfter) }
        if ($null -ne $rule.PSObject.Properties['effectPolicy']) { $raw.effectPolicy = $rule.effectPolicy }
        $policy = ConvertTo-ApplicationPolicy ([pscustomobject]$raw) "$id.$($rule.path)"
        $source = @($ledger.sources | Where-Object scope -CEQ 'Public properties.')
        $collected = @($audit.variants | Where-Object id -CEQ $id)
        if ($source.Count -ne 1 -or $collected.Count -ne 1 -or
            $source[0].url -cne $collected[0].source -or
            $source[0].url -cnotmatch '^https://www\.mathworks\.com/help/releases/r2024a/') {
            throw "Missing or mismatched release-fixed source for $id."
        }
        $evidence = @([ordered]@{
            kind = $rule.kind; source = $source[0].url; detail = $rule.detail
        })
        $property[0] | Add-Member -NotePropertyName application -NotePropertyValue ([pscustomobject]$policy) -Force
        $property[0] | Add-Member -NotePropertyName applicationEvidence -NotePropertyValue $evidence -Force
    }
}
foreach ($correction in $review.contractCorrections) {
    foreach ($id in $correction.variants) {
        if (-not $documents.Contains($id) -or $correction.kind -cne 'documentation' -or
            $correction.removeConstraintKinds -isnot [array] -or
            [string]::IsNullOrWhiteSpace($correction.detail)) {
            throw 'A contract correction needs a validated component, documentation rationale, and constraint kinds.'
        }
        $property = @($documents[$id].properties | Where-Object path -CEQ $correction.path)
        if ($property.Count -ne 1) { throw "Expected one correction target $id.$($correction.path)." }
        $contract = $property[0].valueContract
        $contract.constraints = @($contract.constraints | Where-Object { $_.kind -cnotin $correction.removeConstraintKinds })
        if ($null -ne $correction.PSObject.Properties['allowsEmpty']) {
            if ($correction.allowsEmpty -isnot [bool]) { throw 'allowsEmpty corrections must be boolean.' }
            $contract.allowsEmpty = $correction.allowsEmpty
        }
        $source = $documents[$id].sources | Where-Object scope -CEQ 'Public properties.'
        $property[0] | Add-Member -NotePropertyName applicationEvidence -NotePropertyValue @(
            [ordered]@{ kind = $correction.kind; source = $source.url; detail = $correction.detail }
        ) -Force
    }
}

# Seed only explicitly audited defaults; never manufacture missing source settings.
foreach ($seed in $review.initialValues) {
    foreach ($id in $seed.variants) {
        if (-not $documents.Contains($id)) { throw "An initial-value seed has no reviewed variant $id." }
        $ledger = $documents[$id]
        foreach ($field in $seed.values.PSObject.Properties) {
            $property = @($ledger.properties | Where-Object path -CEQ $field.Name)
            if ($property.Count -ne 1) { throw "Missing initial-value target $id.$($field.Name)." }
            if ($null -eq $property[0].PSObject.Properties['application']) {
                $policy = ConvertTo-ApplicationPolicy ([pscustomobject]@{}) "$id.$($field.Name)"
                $property[0] | Add-Member -NotePropertyName application -NotePropertyValue ([pscustomobject]$policy)
            }
            $property[0].application | Add-Member -NotePropertyName defaultLiteral -NotePropertyValue $field.Value -Force
            $source = $ledger.sources | Where-Object scope -CEQ 'Public properties.'
            $evidence = @()
            if ($null -ne $property[0].PSObject.Properties['applicationEvidence']) {
                $evidence = @($property[0].applicationEvidence | Where-Object { $_.detail -cne $seed.detail })
            }
            $evidence += [ordered]@{ kind = 'documentation'; source = $source.url; detail = $seed.detail }
            $property[0] | Add-Member -NotePropertyName applicationEvidence -NotePropertyValue $evidence -Force
        }
    }
}

# Constructor support is a separate reviewed runtime fact, never inferred from SetAccess.
$runtimePath = Join-Path $ReleaseDirectory 'APPLICATION_POLICY_RUNTIME_REVIEW.json'
$runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
if ($runtime.matlabRelease -cne $review.matlabRelease) { throw 'Runtime review release does not match the ledger.' }
foreach ($coverage in $runtime.coverage) {
    if ($coverage.result -cne 'passed') { throw 'Only verified runtime coverage may grant constructor support.' }
    foreach ($id in $coverage.variants) {
        if (-not $documents.Contains($id)) { throw "Runtime review has no documentation-reviewed variant $id." }
        $ledger = $documents[$id]
        foreach ($path in $coverage.nameValuePaths) {
            $property = @($ledger.properties | Where-Object path -CEQ $path)
            if ($property.Count -ne 1) { throw "Missing runtime review target $id.$path." }
            if ($null -eq $property[0].PSObject.Properties['application']) {
                $policy = ConvertTo-ApplicationPolicy ([pscustomobject]@{}) "$id.$path"
                $property[0] | Add-Member -NotePropertyName application -NotePropertyValue ([pscustomobject]$policy)
            }
            $property[0].application.nameValue = 'supported'
            $evidence = @()
            if ($null -ne $property[0].PSObject.Properties['applicationEvidence']) {
                $evidence = @($property[0].applicationEvidence | Where-Object kind -CNE 'runtime')
            }
            $evidence += [ordered]@{ kind = 'runtime'; source = $runtime.testSource + '#' + $coverage.testMethod; detail = $coverage.detail }
            $property[0] | Add-Member -NotePropertyName applicationEvidence -NotePropertyValue $evidence -Force
        }
        $variant = $audit.variants | Where-Object id -CEQ $id
        $variant.runtimeVerificationStatus = 'partial'
    }
}
foreach ($id in $documents.Keys) {
    Test-ApplicationPolicies $documents[$id].properties $id
}

# Keep partial review distinct from verification of MATLAB setter behavior.
foreach ($id in $documents.Keys) {
    $path = Join-Path $ReleaseDirectory "components/$id.json"
    [IO.File]::WriteAllText($path, ($documents[$id] | ConvertTo-Json -Depth 100) + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false))
    $variant = $audit.variants | Where-Object id -CEQ $id
    $variant.policyReviewStatus = 'partial'
    $count = @($documents[$id].properties | Where-Object { $null -ne $_.PSObject.Properties['application'] }).Count
    $variant | Add-Member -NotePropertyName reviewedPolicyCount -NotePropertyValue $count -Force
}
[IO.File]::WriteAllText($auditPath, ($audit | ConvertTo-Json -Depth 100) + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))
Write-Output "Applied reviewed rules to $($documents.Count) variants. Full review and runtime verification remain pending."

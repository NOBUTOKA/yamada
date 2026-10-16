<#
.SYNOPSIS
Applies explicit, property-level effect coverage without inferring independence.
.DESCRIPTION
The reviewed artifact enumerates exact concrete properties. Missing entries
remain unknown; constructor evidence and default seeds never complete review.
#>
function Add-EffectReview {
    param([string]$ReleaseDirectory, [System.Collections.IDictionary]$Documents)

    $review = Get-Content -LiteralPath (Join-Path $ReleaseDirectory 'APPLICATION_EFFECT_REVIEW.json') -Raw | ConvertFrom-Json
    if ($review.matlabRelease -cne 'R2024a') { throw 'Effect review release mismatch.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($variant in $review.variants) {
        if (-not $seen.Add($variant.id)) { throw 'Duplicate effect-review variant.' }
        if (-not $Documents.Contains($variant.id)) {
            $Documents[$variant.id] = Get-Content -LiteralPath (Join-Path $ReleaseDirectory "components/$($variant.id).json") -Raw | ConvertFrom-Json
        }
        $ledger = $Documents[$variant.id]
        $source = @($ledger.sources | Where-Object scope -CEQ 'Public properties.')
        if ($source.Count -ne 1 -or $source[0].url -cne $variant.source) { throw 'Effect-review source mismatch.' }
        $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($entry in $variant.properties) {
            if (-not $paths.Add($entry.path)) { throw 'Duplicate effect-review property.' }
            $property = @($ledger.properties | Where-Object path -CEQ $entry.path)
            if ($property.Count -ne 1 -or $entry.status -cnotin @('unknown','independent','modeled','unsupported') -or
                    [string]::IsNullOrWhiteSpace($entry.reason)) { throw 'Invalid effect-review target or rationale.' }
            $raw = [ordered]@{}
            if ($null -ne $property[0].PSObject.Properties['application']) {
                foreach ($field in $property[0].application.PSObject.Properties) { $raw[$field.Name] = $field.Value }
            }
            $raw.effectStatus = $entry.status
            $raw.affectedPaths = @($entry.affectedPaths)
            $raw.effectReason = $entry.reason
            $policy = ConvertTo-ApplicationPolicy ([pscustomobject]$raw) "$($variant.id).$($entry.path)"
            $property[0] | Add-Member -NotePropertyName application -NotePropertyValue ([pscustomobject]$policy) -Force
        }
        if ($paths.Count -ne $ledger.properties.Count) { throw 'Effect review must enumerate the whole concrete surface.' }
    }
    $ids = @(Get-ChildItem -LiteralPath (Join-Path $ReleaseDirectory 'components') -Filter '*.json' | ForEach-Object BaseName)
    if ($seen.Count -ne $ids.Count -or @($ids | Where-Object { -not $seen.Contains($_) }).Count -gt 0) {
        throw 'Effect review must enumerate every concrete variant.'
    }
}

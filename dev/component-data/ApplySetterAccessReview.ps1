<#
.SYNOPSIS
Applies recorded native setter metadata without changing product disposition.
#>
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ReleaseDirectory)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ComponentLedger.ps1')
Assert-ComponentLedgerSchema -ReleaseDirectory $ReleaseDirectory
$review = Get-Content -LiteralPath (Join-Path $ReleaseDirectory 'SETTER_ACCESS_RUNTIME_REVIEW.json') -Raw | ConvertFrom-Json
if ($review.artifactVersion -ne 1 -or $review.matlabRelease -cne 'R2024a' -or
    [string]::IsNullOrWhiteSpace($review.probeSource)) {
    throw 'Setter review needs a versioned R2024a native probe source.'
}

# Validate every observation before writing any component file.
$documents = [ordered]@{}
$targets = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($observation in $review.observations) {
    $id = $observation.componentId
    $path = $observation.path
    $access = $observation.runtimeSetAccess
    if ($id -cnotmatch '^[a-z][a-z0-9-]*$' -or $path -cnotmatch '^[A-Za-z]\w*$' -or
        -not $targets.Add("$id.$path") -or $access -cnotin @('public', 'restricted') -or
        -not [string]::IsNullOrWhiteSpace($observation.errorId) -or
        [string]::IsNullOrWhiteSpace($observation.metadataClass) -or
        ($access -ceq 'public' -and $observation.nativeSetAccess -cne 'public') -or
        ($access -ceq 'restricted' -and $observation.nativeSetAccess -cnotin @('private', 'protected', 'immutable', 'class-restricted'))) {
        throw 'Setter observations need unique targets and resolved native metadata.'
    }
    if (-not $documents.Contains($id)) {
        $documents[$id] = Get-Content -LiteralPath (Join-Path $ReleaseDirectory "components/$id.json") -Raw | ConvertFrom-Json
    }
    $property = @($documents[$id].properties | Where-Object path -CEQ $path)
    if ($property.Count -ne 1 -or ($access -ceq 'public' -and
            $null -ne $property[0].PSObject.Properties['documentedReadOnly'] -and $property[0].documentedReadOnly)) {
        throw "Setter observation conflicts with the documented property $id.$path."
    }
    $property[0].runtimeSetAccess = $access
    $evidence = "$($review.probeSource): R2024a owned instance $($observation.metadataClass).SetAccess=$($observation.nativeSetAccess); recorded in SETTER_ACCESS_RUNTIME_REVIEW.json."
    $previous = @()
    if ($null -ne $property[0].PSObject.Properties['runtimeObservations']) {
        $previous = @($property[0].runtimeObservations | Where-Object { $_ -cne $evidence })
    }
    $property[0] | Add-Member -NotePropertyName runtimeObservations -NotePropertyValue @($previous + $evidence) -Force
}

# Preserve all unrelated property contracts and serialize only affected variants.
foreach ($id in $documents.Keys) {
    $text = ($documents[$id] | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $ReleaseDirectory "components/$id.json"), $text, [Text.UTF8Encoding]::new($false))
}
Write-Output "SETTER_ACCESS_REVIEW Applied=$($targets.Count) Variants=$($documents.Count)"

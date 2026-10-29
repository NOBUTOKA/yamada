<#
.SYNOPSIS
Removes redundant per-property constructor flags after a complete documented factory review.
#>
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ReleaseDirectory)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$review = Get-Content -LiteralPath (Join-Path $ReleaseDirectory 'CONSTRUCTOR_SYNTAX_REVIEW.json') -Raw | ConvertFrom-Json
if ($review.matlabRelease -cne 'R2024a' -or $review.decision -cne 'removePerPropertyConstructorFlag') {
    throw 'A release-specific constructor syntax decision is required.'
}
$sources = @{}
foreach ($factory in $review.factories) {
    if ($factory.factory -cnotmatch '^[a-z][a-z0-9]*$' -or $sources.ContainsKey($factory.factory) -or
        $factory.source -cne "https://www.mathworks.com/help/releases/r2024a/matlab/ref/$($factory.factory).html" -or
        $factory.evidenceKind -cnotin @('releaseDocumentation', 'installedOfficialHelp') -or
        [string]::IsNullOrWhiteSpace($factory.constructorSyntax)) {
        throw 'Each factory needs unique release-fixed official constructor evidence.'
    }
    $sources[$factory.factory] = $factory
}

# Validate the complete updated ledger before serializing any component.
$documents = [ordered]@{}
$schemaPath = Join-Path $ReleaseDirectory 'schema.json'
$removed = 0
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $ReleaseDirectory 'components') -Filter '*.json') {
    $ledger = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    if (-not $sources.ContainsKey($ledger.factory)) { throw "Missing constructor documentation for $($ledger.id)." }
    $creation = @($ledger.sources | Where-Object scope -CNE 'Public properties.')
    if ($creation.Count -ne 1 -or $creation[0].url -cne $sources[$ledger.factory].source) {
        throw "Constructor documentation does not match the ledger source for $($ledger.id)."
    }
    foreach ($property in $ledger.properties) {
        if ($null -ne $property.PSObject.Properties['application'] -and
            $null -ne $property.application.PSObject.Properties['nameValue']) {
            $property.application.PSObject.Properties.Remove('nameValue')
            $removed++
        }
    }
    $text = ($ledger | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    if (-not (Test-Json -Json $text -SchemaFile $schemaPath)) { throw "Updated component violates its schema: $($ledger.id)." }
    $documents[$file.FullName] = $text
}
foreach ($path in $documents.Keys) { [IO.File]::WriteAllText($path, $documents[$path], [Text.UTF8Encoding]::new($false)) }
Write-Output "CONSTRUCTOR_SYNTAX_REVIEW Variants=$($documents.Count) Factories=$($sources.Count) RemovedFlags=$removed"

param(
    [string]$ReleaseDirectory = $PSScriptRoot
)

# Reclassify the audited R2024a properties required by Phase 6.9 Step 1.
# This changes editor semantics and disposition while preserving documented
# value contracts until the corresponding specialized editor is implemented.
$componentDirectory = Join-Path $ReleaseDirectory "components"

function Save-Json($path, $document) {
    $json = $document | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($path, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Set-PropertyMetadata($document, $path, $editor, $disposition, $reasons) {
    $property = @($document.properties | Where-Object { $_.path -eq $path }) | Select-Object -First 1
    if ($null -eq $property) { throw "Property '$path' was not found in $($document.factory)." }
    $property.requiredEditor = $editor
    $property.disposition.kind = $disposition
    $property.disposition.reasonCodes = @($reasons)
    return $property
}

$uitablePath = Join-Path $componentDirectory "uitable.json"
$uitable = Get-Content -Raw $uitablePath | ConvertFrom-Json
Set-PropertyMetadata $uitable "Data" "tableData" "editable" @() | Out-Null
foreach ($path in @("ColumnWidth", "ColumnEditable", "ColumnSortable", "ColumnFormat")) {
    Set-PropertyMetadata $uitable $path "columnSettings" "editable" @() | Out-Null
}
$rearrangeable = Set-PropertyMetadata $uitable "ColumnRearrangeable" "onOff" "editable" @()
$rearrangeable.valueContract.kind = "onOff"
$rearrangeable.valueContract.shape = "scalar"
$rearrangeable.valueContract.allowsEmpty = $false
$rearrangeable.valueContract.matlabClasses = @("char", "string", "logical")
foreach ($path in @("Selection", "SelectionType")) {
    Set-PropertyMetadata $uitable $path "none" "omitted" @("lowDesignTimeValue") | Out-Null
}
Save-Json $uitablePath $uitable

$uihtmlPath = Join-Path $componentDirectory "uihtml.json"
$uihtml = Get-Content -Raw $uihtmlPath | ConvertFrom-Json
Set-PropertyMetadata $uihtml "Data" "none" "readOnly" @("arbitraryData") | Out-Null
Save-Json $uihtmlPath $uihtml

Write-Host "Reclassified Phase 6.9 Step 1 properties in $componentDirectory."

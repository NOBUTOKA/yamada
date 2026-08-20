param(
    [string]$ReleaseDirectory = $PSScriptRoot
)

# Reclassify and apply the audited R2024a contracts required by Phase 6.9.
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

function Set-ValueContract($property, $kind, $classes, $shape, $allowsEmpty, $constraints, $optional = @{}) {
    $contract = [ordered]@{
        kind = $kind
        shape = $shape
        allowsEmpty = $allowsEmpty
        constraints = @($constraints)
        matlabClasses = @($classes)
    }
    foreach ($name in $optional.Keys) {
        $contract[$name] = $optional[$name]
    }
    $property.valueContract = [pscustomobject]$contract
}

function Set-RuntimeObservations($property, $observations) {
    $property | Add-Member -NotePropertyName runtimeObservations -NotePropertyValue @($observations) -Force
}

$uidatepickerPath = Join-Path $componentDirectory "uidatepicker.json"
$uidatepicker = Get-Content -Raw $uidatepickerPath | ConvertFrom-Json
$dateValue = Set-PropertyMetadata $uidatepicker "Value" "dateTime" "editable" @()
Set-ValueContract $dateValue "dateTime" @("datetime") "scalar" $false @(
    [ordered]@{ kind = "withinLimitsOf"; property = "Limits" }
) ([ordered]@{ allowsNaT = $true; normalization = "dateOnly" })
Set-RuntimeObservations $dateValue @(
    "R2024a preserves only the date when assigned a datetime containing time information; assigning [] is rejected."
)

$dateLimits = Set-PropertyMetadata $uidatepicker "Limits" "dateTime" "editable" @()
$dateLimits | Add-Member -NotePropertyName documentedDefault -NotePropertyValue "[datetime(0000,1,1) datetime(9999,12,31)]" -Force
Set-ValueContract $dateLimits "dateTime" @("datetime") "fixedLengthVector" $false @(
    [ordered]@{ kind = "strictlyIncreasing" }
) ([ordered]@{ fixedLength = 2; orientation = "row"; allowsNaT = $false })
Set-RuntimeObservations $dateLimits @(
    "R2024a normalizes a two-element column input to a 1-by-2 row.",
    "R2024a accepts equal bounds although the R2024a documentation says the second value must be later; the normalized contract follows the documentation."
)

$disabledDates = Set-PropertyMetadata $uidatepicker "DisabledDates" "dateTime" "editable" @()
Set-ValueContract $disabledDates "dateTime" @("datetime") "vector" $true @(
    [ordered]@{ kind = "sortedAscending" }
) ([ordered]@{ orientation = "column"; allowsNaT = $false })
Set-RuntimeObservations $disabledDates @(
    "R2024a accepts row input and stores it as a column, sorts descending input, and removes duplicate dates; the normalized contract follows the documented m-by-1 sorted input.",
    "R2024a rejects nonempty DisabledDates values containing NaT and stores NaT(0) as an empty datetime array."
)
Save-Json $uidatepickerPath $uidatepicker

$uitablePath = Join-Path $componentDirectory "uitable.json"
$uitable = Get-Content -Raw $uitablePath | ConvertFrom-Json
$tableData = Set-PropertyMetadata $uitable "Data" "tableData" "editable" @()
$tableData.documentedAcceptedValues = @(
    "table array",
    "numeric array",
    "logical array",
    "cell array",
    "string array",
    "cell array of character vectors"
)
Set-ValueContract $tableData "tabularData" @("numeric", "logical", "cell", "string", "table") "matrix" $true @()
Set-RuntimeObservations $tableData @(
    "R2024a accepts numeric subclasses such as single and int32 and rejects direct char, categorical, datetime, duration, timetable, and multidimensional array values."
)

foreach ($path in @("ColumnName", "RowName")) {
    $heading = Set-PropertyMetadata $uitable $path "tableData" "editable" @()
    $heading.documentedAcceptedValues = @(
        "'numbered'",
        "n-by-1 cell array of character vectors",
        "n-by-1 string array",
        "categorical array",
        "empty cell array ({})",
        "empty matrix ([])"
    )
    Set-ValueContract $heading "stringList" @("char", "string", "cell", "categorical", "double") "propertyDependent" $true @() ([ordered]@{ normalization = "columnVector" })
    Set-RuntimeObservations $heading @(
        "R2024a stores string and categorical input as a column cell array of character vectors, reshapes matrix input column-wise, and stores [] as empty char."
    )
}

$columnWidth = Set-PropertyMetadata $uitable "ColumnWidth" "columnSettings" "editable" @()
Set-ValueContract $columnWidth "columnWidth" @("char", "string", "cell") "propertyDependent" $false @() ([ordered]@{ normalization = "charOrRowCell" })
Set-RuntimeObservations $columnWidth @(
    "R2024a stores a string scalar as char and a string array as a row cell array; mixed cell entries can contain nonnegative numeric widths and documented text width specifications."
)

foreach ($path in @("ColumnEditable", "ColumnSortable")) {
    $logicalColumns = Set-PropertyMetadata $uitable $path "columnSettings" "editable" @()
    Set-ValueContract $logicalColumns "logical" @("logical", "double") "propertyDependent" $true @() ([ordered]@{ normalization = "logical" })
    Set-RuntimeObservations $logicalColumns @(
        "R2024a stores [] as an empty logical array and accepts a logical scalar or row vector; missing vector entries behave as false and excess entries are ignored."
    )
}

$columnFormat = Set-PropertyMetadata $uitable "ColumnFormat" "columnSettings" "editable" @()
Set-ValueContract $columnFormat "columnFormat" @("cell", "double") "propertyDependent" $true @() ([ordered]@{ normalization = "rowCell" })
Set-RuntimeObservations $columnFormat @(
    "R2024a stores [] as an empty cell array, rejects string format elements, and accepts char format names, empty entries, and nested cell arrays of character vectors for pop-up menus."
)

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

Write-Host "Applied audited Phase 6.9 property contracts in $componentDirectory."

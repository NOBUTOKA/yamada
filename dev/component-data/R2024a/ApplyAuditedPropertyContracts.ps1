param(
    [string]$ReleaseDirectory = $PSScriptRoot
)

# Apply the audited R2024a Inspector property contracts.
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

function Set-ContractOptions($property, $options) {
    foreach ($name in $options.Keys) {
        $property.valueContract | Add-Member -NotePropertyName $name -NotePropertyValue $options[$name] -Force
    }
}

function Set-TextContract($document, $path, $classes) {
    $property = Set-PropertyMetadata $document $path "text" "editable" @()
    Set-ValueContract $property "text" $classes "scalar" $true @()
}

function Set-FixedNumericVectorContract($document, $path, $length) {
    $property = Set-PropertyMetadata $document $path "numericVector" "editable" @()
    Set-ValueContract $property "numericArray" @("double") "fixedLengthVector" $false @() ([ordered]@{ fixedLength = $length })
}

function Set-PositiveNumberContract($document, $path, $integer = $false) {
    $property = Set-PropertyMetadata $document $path "number" "editable" @()
    Set-ValueContract $property "number" @("double") "scalar" $false @() ([ordered]@{
        minimum = 0
        exclusiveMinimum = $true
        integer = $integer
    })
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

# Correct text-like properties that an earlier classifier incorrectly labelled numeric.
$textContracts = [ordered]@{
    "uidatepicker" = [ordered]@{ Placeholder = @("char", "string"); DisplayFormat = @("char", "string") }
    "uidropdown" = [ordered]@{ Placeholder = @("char", "string") }
    "uieditfield-numeric" = [ordered]@{ Placeholder = @("char", "string"); ValueDisplayFormat = @("char", "string") }
    "uieditfield-text" = [ordered]@{ Placeholder = @("char", "string"); Value = @("char", "string") }
    "uiimage" = [ordered]@{ AltText = @("char", "string") }
    "uipushtool" = [ordered]@{ Tooltip = @("char", "string", "categorical"); TooltipString = @("char", "string", "categorical") }
    "uispinner" = [ordered]@{ Placeholder = @("char", "string"); ValueDisplayFormat = @("char", "string") }
    "uitextarea" = [ordered]@{ Placeholder = @("char", "string") }
    "uitoggletool" = [ordered]@{ Tooltip = @("char", "string", "categorical"); TooltipString = @("char", "string", "categorical") }
    "uibuttongroup" = [ordered]@{ Title = @("char", "string", "categorical") }
    "uipanel" = [ordered]@{ Title = @("char", "string", "categorical") }
    "uitab" = [ordered]@{ Title = @("char", "string", "categorical") }
}
foreach ($componentId in $textContracts.Keys) {
    $path = Join-Path $componentDirectory ($componentId + ".json")
    $document = Get-Content -Raw $path | ConvertFrom-Json
    foreach ($propertyPath in $textContracts[$componentId].Keys) {
        Set-TextContract $document $propertyPath $textContracts[$componentId][$propertyPath]
    }
    Save-Json $path $document
}

# Record heterogeneous and deferred grid-layout contracts without claiming a native adapter.
$uidatepicker = Get-Content -Raw $uidatepickerPath | ConvertFrom-Json
$disabledDays = Set-PropertyMetadata $uidatepicker "DisabledDaysOfWeek" "structuredData" "editable" @()
Set-ValueContract $disabledDays "dayOfWeekList" @("numeric", "string", "cell") "vector" $true @()
Save-Json $uidatepickerPath $uidatepicker

$uigridlayoutPath = Join-Path $componentDirectory "uigridlayout.json"
$uigridlayout = Get-Content -Raw $uigridlayoutPath | ConvertFrom-Json
foreach ($path in @("ColumnWidth", "RowHeight")) {
    $trackList = Set-PropertyMetadata $uigridlayout $path "gridTrackList" "editable" @()
    Set-ValueContract $trackList "gridTrackList" @("numeric", "char", "string", "cell") "vector" $true @()
}
Save-Json $uigridlayoutPath $uigridlayout

# Replace scalar numeric-vector misclassifications and preserve documented scalar bounds.
foreach ($componentId in @("uibuttongroup", "uipanel")) {
    $path = Join-Path $componentDirectory ($componentId + ".json")
    $document = Get-Content -Raw $path | ConvertFrom-Json
    Set-PositiveNumberContract $document "BorderWidth" $true
    Save-Json $path $document
}
foreach ($componentId in @("axes", "polaraxes", "uiaxes")) {
    $path = Join-Path $componentDirectory ($componentId + ".json")
    $document = Get-Content -Raw $path | ConvertFrom-Json
    $rotationPath = if ($componentId -eq "polaraxes") { "RTickLabelRotation" } else { "ZTickLabelRotation" }
    $rotation = Set-PropertyMetadata $document $rotationPath "number" "editable" @()
    Set-ValueContract $rotation "number" @("double") "scalar" $false @()
    Save-Json $path $document
}

# Capture documented cardinality for editable numeric vectors.
$fixedVectors = [ordered]@{
    "axes" = [ordered]@{ ALim = 2; CameraPosition = 3; CameraTarget = 3; CameraUpVector = 3; CLim = 2; DataAspectRatio = 3; OuterPosition = 4; PlotBoxAspectRatio = 3; TickLength = 2; View = 2; ZLim = 2 }
    "geoaxes" = [ordered]@{ ALim = 2; CLim = 2; MapCenter = 2; OuterPosition = 4; TickLength = 2 }
    "polaraxes" = [ordered]@{ ALim = 2; CLim = 2; OuterPosition = 4; RLim = 2; ThetaLim = 2; TickLength = 2 }
    "uiaxes" = [ordered]@{ ALim = 2; CameraPosition = 3; CameraTarget = 3; CameraUpVector = 3; CLim = 2; DataAspectRatio = 3; OuterPosition = 4; PlotBoxAspectRatio = 3; TickLength = 2; View = 2; ZLim = 2 }
    "uieditfield-numeric" = [ordered]@{ Limits = 2 }
    "uieditfield-text" = [ordered]@{ CharacterLimits = 2 }
    "uigauge-circular" = [ordered]@{ Limits = 2 }
    "uigauge-linear" = [ordered]@{ Limits = 2 }
    "uigauge-ninetydegree" = [ordered]@{ Limits = 2 }
    "uigauge-semicircular" = [ordered]@{ Limits = 2 }
    "uiknob-continuous" = [ordered]@{ Limits = 2 }
    "uislider-range" = [ordered]@{ Limits = 2; Value = 2 }
    "uislider-slider" = [ordered]@{ Limits = 2 }
    "uispinner" = [ordered]@{ Limits = 2 }
}
foreach ($componentId in $fixedVectors.Keys) {
    $path = Join-Path $componentDirectory ($componentId + ".json")
    $document = Get-Content -Raw $path | ConvertFrom-Json
    foreach ($propertyPath in $fixedVectors[$componentId].Keys) {
        Set-FixedNumericVectorContract $document $propertyPath $fixedVectors[$componentId][$propertyPath]
    }
    Save-Json $path $document
}

# These three documented range surfaces expressly allow positive or negative infinity.
foreach ($target in @(
    @{ ComponentId = "uieditfield-numeric"; Path = "Limits" },
    @{ ComponentId = "uieditfield-text"; Path = "CharacterLimits" },
    @{ ComponentId = "uispinner"; Path = "Limits" }
)) {
    $path = Join-Path $componentDirectory ($target.ComponentId + ".json")
    $document = Get-Content -Raw $path | ConvertFrom-Json
    $property = @($document.properties | Where-Object { $_.path -eq $target.Path }) | Select-Object -First 1
    Set-ContractOptions $property ([ordered]@{ allowsInfinity = $true })
    Save-Json $path $document
}

# Apply directly documented numeric ranges after the property shape has been normalized.
$positiveFontComponents = @(
    "uibutton-push", "uibutton-state", "uibuttongroup", "uicheckbox", "uidatepicker", "uidropdown", "uieditfield-numeric", "uieditfield-text", "uigauge-circular", "uigauge-linear", "uigauge-ninetydegree", "uigauge-semicircular", "uihyperlink", "uiknob-continuous", "uiknob-discrete", "uilabel", "uilistbox", "uipanel", "uiradiobutton", "uislider-range", "uislider-slider", "uispinner", "uiswitch-rocker", "uiswitch-slider", "uiswitch-toggle", "uitable", "uitextarea", "uitogglebutton", "uitree", "uitree-checkbox")
foreach ($componentId in $positiveFontComponents) {
    $path = Join-Path $componentDirectory ($componentId + ".json")
    $document = Get-Content -Raw $path | ConvertFrom-Json
    Set-PositiveNumberContract $document "FontSize"
    Save-Json $path $document
}

foreach ($componentId in @("axes", "geoaxes", "polaraxes", "uiaxes")) {
    $path = Join-Path $componentDirectory ($componentId + ".json")
    $document = Get-Content -Raw $path | ConvertFrom-Json
    Set-ContractOptions (Set-PropertyMetadata $document "Alphamap" "numericVector" "editable" @()) ([ordered]@{ minimum = 0; maximum = 1 })
    Set-ContractOptions (Set-PropertyMetadata $document "GridAlpha" "number" "editable" @()) ([ordered]@{ minimum = 0; maximum = 1 })
    if ($componentId -in @("axes", "polaraxes", "uiaxes")) {
        Set-ContractOptions (Set-PropertyMetadata $document "MinorGridAlpha" "number" "editable" @()) ([ordered]@{ minimum = 0; maximum = 1 })
    }
    Save-Json $path $document
}
foreach ($componentId in @("axes", "uiaxes")) {
    $path = Join-Path $componentDirectory ($componentId + ".json")
    $document = Get-Content -Raw $path | ConvertFrom-Json
    Set-ContractOptions (Set-PropertyMetadata $document "CameraViewAngle" "number" "editable" @()) ([ordered]@{ minimum = 0; maximum = 180; exclusiveMaximum = $true })
    foreach ($propertyPath in @("GridLineWidth", "LineWidth", "MinorGridLineWidth")) {
        Set-ContractOptions (Set-PropertyMetadata $document $propertyPath "number" "editable" @()) ([ordered]@{ minimum = 0; exclusiveMinimum = $true })
    }
    Save-Json $path $document
}
$geoaxesPath = Join-Path $componentDirectory "geoaxes.json"
$geoaxes = Get-Content -Raw $geoaxesPath | ConvertFrom-Json
Set-ContractOptions (Set-PropertyMetadata $geoaxes "LineWidth" "number" "editable" @()) ([ordered]@{ minimum = 0; exclusiveMinimum = $true })
Set-ContractOptions (Set-PropertyMetadata $geoaxes "ZoomLevel" "number" "editable" @()) ([ordered]@{ minimum = 0; maximum = 25 })
Save-Json $geoaxesPath $geoaxes
$sliderPath = Join-Path $componentDirectory "uislider-range.json"
$slider = Get-Content -Raw $sliderPath | ConvertFrom-Json
Set-ContractOptions (Set-PropertyMetadata $slider "Step" "number" "editable" @()) ([ordered]@{ minimum = 0; exclusiveMinimum = $true })
Save-Json $sliderPath $slider

# Value is selected from Items and, when supplied, the parallel ItemsData value.
# A native selection control exposes the Items labels and commits the associated
# literal without treating the choice as a numeric scalar.
$itemSelectionComponents = [ordered]@{
    "uidropdown" = $false
    "uiknob-discrete" = $false
    "uilistbox" = $true
    "uiswitch-rocker" = $false
    "uiswitch-slider" = $false
    "uiswitch-toggle" = $false
}
foreach ($componentId in $itemSelectionComponents.Keys) {
    $path = Join-Path $componentDirectory ($componentId + ".json")
    $document = Get-Content -Raw $path | ConvertFrom-Json
    $value = Set-PropertyMetadata $document "Value" "itemSelection" "editable" @()
    $options = [ordered]@{}
    if ($componentId -eq "uilistbox") {
        $options.multiselectProperty = "Multiselect"
    }
    Set-ValueContract $value "itemSelection" @("any") "propertyDependent" $itemSelectionComponents[$componentId] @() $options
    Save-Json $path $document
}

# Model-owned component references and GridLayout track lists need dedicated
# interaction contracts. Keep their documented values visible, but do not
# advertise an editable adapter before those later vertical slices exist.
foreach ($file in @(Get-ChildItem -LiteralPath $componentDirectory -Filter '*.json' -File)) {
    $document = Get-Content -Raw $file.FullName | ConvertFrom-Json
    $changed = $false
    foreach ($property in @($document.properties)) {
        $kind = [string]$property.valueContract.kind
        if ($kind -eq 'componentReference') {
            $property.requiredEditor = 'none'
            $property.disposition.kind = 'readOnly'
            $property.disposition.reasonCodes = @('deferredComponentReference')
            $changed = $true
        }
        elseif ($kind -eq 'gridTrackList') {
            $property.requiredEditor = 'none'
            $property.disposition.kind = 'readOnly'
            $property.disposition.reasonCodes = @('deferredGridTrackList')
            $changed = $true
        }
    }
    if ($changed) {
        Save-Json $file.FullName $document
    }
}

# CurrentPoint is runtime interaction state, not an editable design-time property.
$uiaxesPath = Join-Path $componentDirectory "uiaxes.json"
$uiaxes = Get-Content -Raw $uiaxesPath | ConvertFrom-Json
$currentPoint = Set-PropertyMetadata $uiaxes "CurrentPoint" "none" "omitted" @("lowDesignTimeValue", "runtimeSetRestricted")
Set-ValueContract $currentPoint "opaque" @("unknown") "any" $false @()
Save-Json $uiaxesPath $uiaxes

Write-Host "Applied audited Inspector property contracts in $componentDirectory."

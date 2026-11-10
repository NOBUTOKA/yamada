<#
.SYNOPSIS
Provides project-authored descriptions and canonical notation for API facts.
.DESCRIPTION
Descriptions are composed from API identifiers and reviewed value contracts,
not from reference-page headings. This module never downloads documentation.
#>

function Get-ProjectPropertySummary {
    param([Parameter(Mandatory = $true)][object]$Property)

    $path = [string]$Property.path
    $descriptions = @{
        Text = 'Text rendered by the component.'
        Title = 'Heading displayed with the component.'
        Subtitle = 'Secondary heading displayed below the title.'
        Name = 'Name displayed for the window.'
        Tag = 'Identifier available to application code.'
        UserData = 'Application-defined data attached to the component.'
        NodeData = 'Application-defined data attached to the node.'
        Value = 'Current value of the control.'
        ValueIndex = 'Index of the currently chosen item.'
        Items = 'Choices presented by the control.'
        ItemsData = 'Application values associated with the displayed choices.'
        Data = 'Data supplied to this component.'
        DisplayData = 'Data in the current displayed order.'
        Position = 'Component rectangle [left bottom width height] in its configured units.'
        InnerPosition = 'Inner rectangle [left bottom width height] in its configured units.'
        OuterPosition = 'Outer rectangle [left bottom width height] in its configured units.'
        Units = 'Measurement unit used for component geometry.'
        TightInset = 'Margins [left bottom right top] needed around the plotted area.'
        Extent = 'Measured bounds needed by the displayed content.'
        Parent = 'Container that owns this component.'
        Children = 'Components owned directly by this container.'
        ContextMenu = 'Menu opened for this component by a context-menu gesture.'
        Layout = 'Placement settings supplied by the parent layout.'
        RowHeight = 'Sizes or weights assigned to the grid rows.'
        ColumnWidth = 'Sizes or weights assigned to the columns.'
        RowSpacing = 'Gap between adjacent grid rows.'
        ColumnSpacing = 'Gap between adjacent grid columns.'
        Padding = 'Container padding [left bottom right top].'
        Visible = 'Whether this component is displayed.'
        Enable = 'Whether the control accepts user interaction.'
        Editable = 'Whether the user can change the displayed value.'
        Scrollable = 'Whether scrolling is available for the container.'
        AutoResizeChildren = 'Whether the container resizes its children automatically.'
        Resize = 'Whether the user can resize the window.'
        Orientation = 'Direction in which the control is arranged.'
        SelectedTab = 'Tab currently displayed by the tab group.'
        SelectedObject = 'Control currently chosen in the button group.'
        SelectedNodes = 'Nodes currently selected in the tree.'
        CheckedNodes = 'Nodes currently checked in the tree.'
        Checked = 'Whether the menu item is checked.'
        Selected = 'Whether the object is selected.'
        Selection = 'Current selection reported by the component.'
        Multiselect = 'Whether more than one item can be selected.'
        Tooltip = 'Help text displayed when the pointer rests on the component.'
        TooltipString = 'Help text displayed when the pointer rests on the tool.'
        Placeholder = 'Hint displayed while the control has no entered text.'
        AltText = 'Text alternative for the displayed image.'
        FontName = 'Typeface used to render text.'
        FontSize = 'Size used to render text.'
        FontUnits = 'Measurement unit used for text size.'
        FontWeight = 'Weight used to render text.'
        FontAngle = 'Upright or italic text style.'
        FontColor = 'Color used to render text.'
        FontSmoothing = 'Whether text edges are smoothed.'
        HorizontalAlignment = 'Horizontal alignment of the displayed content.'
        VerticalAlignment = 'Vertical alignment of the displayed content.'
        Interpreter = 'Markup rules used to interpret displayed text.'
        WordWrap = 'Whether text can continue onto another display line.'
        ImageSource = 'Local file or image data used by the image component.'
        ImageScaling = 'How image dimensions are fitted to the available area.'
        Icon = 'Image displayed beside the component text.'
        IconAlignment = 'Placement of the icon relative to the text.'
        HTMLSource = 'HTML content or file supplied to the HTML component.'
        URL = 'Address opened by the hyperlink.'
        Limits = 'Lower and upper limits of the control value.'
        CharacterLimits = 'Minimum and maximum allowed text lengths.'
        AllowEmpty = 'Whether an empty entry is accepted.'
        LowerLimitInclusive = 'Whether the lower limit itself is accepted.'
        UpperLimitInclusive = 'Whether the upper limit itself is accepted.'
        RoundFractionalValues = 'Whether fractional input is rounded to a whole number.'
        Step = 'Amount added or subtracted for one control step.'
        ColumnName = 'Labels displayed above the table columns.'
        RowName = 'Labels displayed beside the table rows.'
        ColumnFormat = 'Display or input format of each table column.'
        ColumnEditable = 'Whether users can edit cells in each column.'
        ColumnSortable = 'Whether users can sort each column.'
        ColumnRearrangeable = 'Whether users can change the column order.'
        RowStriping = 'Whether alternating table rows use different backgrounds.'
        CData = 'Color or image data associated with the object.'
        Color = 'Color used by the component.'
        BackgroundColor = 'Color behind the component content.'
        ForegroundColor = 'Color used in front of the component background.'
        Colormap = 'Sequence of colors used to map indexed data.'
        Alphamap = 'Sequence of transparency values used for indexed data.'
        ColorOrder = 'Sequence of colors selected for successive plots.'
        LineStyleOrder = 'Sequence of line patterns selected for successive plots.'
        LineWidth = 'Width used to draw lines.'
        Grid = 'Whether the plotted grid is displayed.'
        View = 'Viewing angles [azimuth elevation] for the axes.'
        DataAspectRatio = 'Relative scale of data units along the three axes.'
        PlotBoxAspectRatio = 'Relative lengths of the three plot-box edges.'
        CameraPosition = 'Camera location [x y z] in data coordinates.'
        CameraTarget = 'Point [x y z] toward which the camera is directed.'
        CameraUpVector = 'Direction vector used as the camera up direction.'
        CameraViewAngle = 'Angular extent of the camera view.'
        Projection = 'Projection used to map the scene onto the display.'
        Clipping = 'Whether graphics outside the clipping region are hidden.'
        NextPlot = 'How a subsequent plot affects the existing axes content.'
        Basemap = 'Map background selected for geographic display.'
        MapCenter = 'Latitude and longitude of the map center.'
        ZoomLevel = 'Map magnification level.'
        LatitudeLimits = 'Latitude interval shown by the map.'
        LongitudeLimits = 'Longitude interval shown by the map.'
        MenuBar = 'Menu-bar configuration of the window.'
        Toolbar = 'Toolbar associated with the window or axes.'
        Pointer = 'Pointer shape displayed over the window.'
        PointerShapeCData = 'Pixel data for a custom pointer shape.'
        PointerShapeHotSpot = 'Active pixel location within a custom pointer image.'
        BusyAction = 'How a callback is handled while another callback is busy.'
        Interruptible = 'Whether another callback can interrupt the running callback.'
        BeingDeleted = 'Whether destruction of this object is in progress.'
        Type = 'MATLAB graphics type identifying the object.'
        HandleVisibility = 'Whether handle-search operations expose this object.'
        HitTest = 'Whether this object responds to pointer hit testing.'
        PickableParts = 'Parts of the object eligible for pointer hit testing.'
        PositionConstraint = 'Rectangle kept fixed while related geometry changes.'
        Buttons = 'Buttons included in the toolbar.'
        ColorOrderIndex = 'Position within the color sequence for the next plot.'
        LineStyleOrderIndex = 'Position within the line-pattern sequence for the next plot.'
        LineStyleCyclingMethod = 'How color and line-pattern sequences advance together.'
        CurrentPoint = 'Pointer location reported in the component coordinates.'
        DisabledDates = 'Dates that the date control does not accept.'
        DisabledDaysOfWeek = 'Weekday numbers that the date control does not accept.'
        DisplaySelection = 'Whether the table indicates its current selection.'
        InteractionOptions = 'Options used by the axes interaction tools.'
        Interactions = 'Interaction tools enabled on the axes.'
        LabelFontSizeMultiplier = 'Text-size multiplier for labels relative to axes text.'
        TitleFontSizeMultiplier = 'Text-size multiplier for the title relative to axes text.'
        LatitudeAxis = 'Ruler object used for geographic latitude.'
        LongitudeAxis = 'Ruler object used for geographic longitude.'
        Legend = 'Legend object associated with these axes.'
        Scalebar = 'Distance-scale object associated with the geographic axes.'
        NextSeriesIndex = 'Series index assigned to the next plotted object.'
        Number = 'Numeric identifier assigned to the figure.'
        StyleConfigurations = 'Style settings associated with the component.'
        TickLabelFormat = 'Formatting specification used for tick text.'
    }
    if ($descriptions.ContainsKey($path)) { return $descriptions[$path] }
    if ([string]$Property.valueContract.kind -eq 'callback') {
        $event = $path -replace '(Fcn|Callback)$', ''
        $event = [regex]::Replace($event, '(?<=[a-z])(?=[A-Z])', ' ')
        return "Callback invoked for the $($event.ToLowerInvariant()) event."
    }
    if ($path.EndsWith('Mode')) {
        $setting = $path.Substring(0, $path.Length - 4)
        return "Automatic or explicit control of $setting."
    }
    if ($path -cmatch '^(X|Y|Z|R|Theta)(Lim|Tick|TickLabel|TickLabelRotation|MinorTick|MinorGrid|Grid|Scale|Dir|Color|AxisLocation|Axis)$') {
        $axis = $Matches[1]; $part = $Matches[2]
        $patterns = @{
            Lim='Displayed interval of the {0} axis.'; Tick='Tick positions along the {0} axis.'
            TickLabel='Text shown at the {0}-axis ticks.'; TickLabelRotation='Rotation of the {0}-axis tick text.'
            MinorTick='Whether intermediate {0}-axis ticks are displayed.'; MinorGrid='Whether intermediate {0}-axis grid lines are displayed.'
            Grid='Whether {0}-axis grid lines are displayed.'; Scale='Linear or logarithmic mapping of the {0} axis.'
            Dir='Direction in which {0}-axis values increase.'; Color='Color used to draw the {0} axis.'
            AxisLocation='Placement of the {0} axis within the plot.'; Axis='Ruler object representing the {0} axis.'
        }
        return $patterns[$part] -f $axis
    }
    $words = [regex]::Replace($path, '(?<=[a-z0-9])(?=[A-Z])', ' ').ToLowerInvariant()
    $kind = [string]$Property.valueContract.kind
    switch ($kind) {
        'componentReference' { return "Component associated with the $words setting." }
        'graphicsObject' { return "Graphics object associated with the $words setting." }
        'color' { return "Color used for $words." }
        'onOff' { return "Whether $words is enabled." }
        'logical' { return "Whether $words is enabled." }
        'number' { return "Numeric setting for $words." }
        'numericArray' { return "Numeric values used for $words." }
        'enum' { return "Choice controlling $words." }
        'text' { return "Text used for $words." }
        'stringList' { return "Text entries used for $words." }
        default { return "Configuration of $words." }
    }
}

function ConvertTo-ProjectValueNotation {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    # Keep API tokens, literals, and common type names exact; shorten descriptive notation.
    if ($Text -match '^\s*(["'']).*\1\s*$' -or $Text -match '^\s*[\[\{].*[\]\}]\s*$') { return $Text }
    $map = @{
        '"-" solid line'='"-"'
        'real, finite, numeric scalar between 0 and 25, inclusive'='numeric scalar; real; finite; 0 <= value <= 25'
        'scalar angle in range [0,180)'='angle scalar; 0 <= value < 180'
        'four-element vector of the form [left bottom right top]'='vector[4]: [left bottom right top]'
        'three-element direction vector of the form [x y z]'='vector[3]: [x y z]'
        'three-element vector of the form [dx dy dz]'='vector[3]: [dx dy dz]'
        'three-element vector of the form [px py pz]'='vector[3]: [px py pz]'
        'three-element vector of the form [x y z]'='vector[3]: [x y z]'
        'two-element vector of the form [amin amax]'='vector[2]: [amin amax]'
        'two-element vector of the form [azimuth elevation]'='vector[2]: [azimuth elevation]'
        'two-element vector of the form [cmin cmax]'='vector[2]: [cmin cmax]'
        'two-element vector of the form [min max]'='vector[2]: [min max]'
        'two-element vector of the form [rmin rmax]'='vector[2]: [rmin rmax]'
        'two-element vector of the form [thmin thmax]'='vector[2]: [thmin thmax]'
        'array of finite alpha values from 0 to 1'='alpha array; finite; 0 <= value <= 1'
        'vector of integers in the range [1, 7]'='integer vector; 1 <= value <= 7'
        'vector of values between 0 and 1'='vector; 0 <= value <= 1'
        'value in the range [0,1]'='0 <= value <= 1'
        'vector of 64 values between 0 and 1'='vector[64]; 0 <= value <= 1'
        'array of 64 values from 0 to 1'='array[64]; 0 <= value <= 1'
        'first radio button or toggle button in button group'='first created RadioButton/ToggleButton in the group'
        'seven predefined colors'='MATLAB default seven-color sequence'
    }
    if ($map.ContainsKey($Text)) { return $map[$Text] }
    return $Text
}

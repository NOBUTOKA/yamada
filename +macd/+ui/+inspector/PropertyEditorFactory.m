classdef PropertyEditorFactory
    % PropertyEditorFactory Create allowlisted native inspector editors.
    %   This factory maps catalog editor identifiers to project-owned controls and
    %   never evaluates catalog text as MATLAB code.

    methods (Static)
        function control = create(parent, definition, commitFcn, batchCommitFcn)
            % create Construct one editor control for a typed property definition.
            arguments (Input)
                parent
                definition (1, 1) macd.model.PropertyDefinition
                commitFcn (1, 1) function_handle
                batchCommitFcn = []
            end

            % Preserve the public three-argument factory contract for focused tests.
            if isempty(batchCommitFcn)
                batchCommitFcn = @(changes) ...
                    macd.ui.inspector.PropertyEditorFactory.commitSingleChange(commitFcn, changes);
            end

            switch definition.Editor
                case {"logical", "onOff"}
                    control = uicheckbox(parent, "Text", "", "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) commitFcn(source.Value));
                    control.UserData = definition.Editor;
                case "enum"
                    items = macd.ui.inspector.PropertyEditorFactory.enumItems(definition);
                    control = uidropdown(parent, "Items", cellstr(items), ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) commitFcn( ...
                        macd.source.LiteralEncoder.encode(char(source.Value))));
                case "asset"
                    control = uipanel(parent, "BorderType", "none", ...
                        "Tag", "macd-inspector-asset-editor");
                    grid = uigridlayout(control, [1 2], "Padding", [0 0 0 0], ...
                        "ColumnWidth", {"1x", 34}, "ColumnSpacing", 3);
                    edit = uieditfield(grid, "text", "Tag", "macd-inspector-asset-path", ...
                        "ValueChangedFcn", @(source, ~) commitFcn(string(source.Value)));
                    browse = uibutton(grid, "Text", "...", "Tag", "macd-inspector-asset-browse", ...
                        "ButtonPushedFcn", @(~, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.browseAsset(control, commitFcn));
                    control.UserData = struct("Edit", edit, "Browse", browse);
                case "number"
                    control = uieditfield(parent, "numeric", ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) commitFcn(source.Value));
                    macd.ui.inspector.PropertyEditorFactory.applyNumberSchema( ...
                        control, definition.ValueSchema);
                case "color"
                    control = uibutton(parent, "Text", "", ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ButtonPushedFcn", @(source, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.pickColor(source, commitFcn));
                case "stringList"
                    control = uibutton(parent, "Text", "", ...
                        "Tag", "macd-inspector-string-list-editor", ...
                        "ButtonPushedFcn", @(source, ~) ...
                        macd.ui.inspector.StringListEditorDialog.open( ...
                        source.UserData, definition.Path, batchCommitFcn));
                case "multilineText"
                    control = uitextarea(parent, "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.commitTextArea(source, commitFcn));
                case "itemSelection"
                    control = macd.ui.inspector.PropertyEditorFactory.createItemSelection( ...
                        parent, definition, commitFcn);
                case "structuredData"
                    if macd.ui.inspector.PropertyEditorFactory.isDayOfWeekSchema(definition)
                        control = uibutton(parent, "Text", "Edit weekdays", ...
                            "Tag", "macd-inspector-day-of-week-editor", ...
                            "ButtonPushedFcn", @(source, ~) ...
                            macd.ui.inspector.PropertyEditorFactory.openDayOfWeekEditor( ...
                            source, definition.Path, batchCommitFcn));
                    else
                        control = uibutton(parent, "Text", "Edit data", ...
                            "Tag", "macd-inspector-structured-data-editor", ...
                            "ButtonPushedFcn", @(source, ~) ...
                            macd.ui.inspector.PropertyEditorFactory.openStructuredDataEditor( ...
                            source.UserData, definition.Path, batchCommitFcn));
                    end
                case "dateTime"
                    control = macd.ui.inspector.PropertyEditorFactory.createDateTimeEditor( ...
                        parent, definition, commitFcn, batchCommitFcn);
                case "tableData"
                    control = uibutton(parent, "Text", "Edit table", ...
                        "Tag", "macd-inspector-table-data-editor", ...
                        "ButtonPushedFcn", @(source, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.openTableDataEditor( ...
                        source, batchCommitFcn));
                    control.UserData = struct("Path", definition.Path);
                case "text"
                    control = uieditfield(parent, "text", ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.commitText(source, commitFcn));
                    control.UserData = struct("Kind", "text", "Value", []);
                case {"literal", "numericVector"}
                    control = uieditfield(parent, "text", ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) commitFcn(string(source.Value)));
                case "url"
                    control = uieditfield(parent, "text", ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.commitUrl(source, commitFcn));
                    control.UserData = struct("Kind", "url", "Value", []);
                otherwise
                    control = uieditfield(parent, "text", ...
                        "Tag", "macd-inspector-property-editor");
                    control.UserData = "readOnlyFallback";
            end
        end

        function control = createComposite(parent, row, batchCommitFcn)
            % createComposite Construct one allowlisted multi-property Inspector editor.
            arguments (Input)
                parent
                row (1, 1) struct
                batchCommitFcn (1, 1) function_handle
            end

            switch string(row.Editor)
                case "tableData"
                    control = uibutton(parent, "Text", "Edit table", ...
                        "Tag", "macd-inspector-table-data-editor", ...
                        "ButtonPushedFcn", @(source, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.openTableDataEditor(source, batchCommitFcn));
                case "columnSettings"
                    control = uibutton(parent, "Text", "Edit columns", ...
                        "Tag", "macd-inspector-column-settings-editor", ...
                        "ButtonPushedFcn", @(source, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.openColumnSettingsEditor(source, batchCommitFcn));
                case "items"
                    control = uibutton(parent, "Text", "Edit items", ...
                        "Tag", "macd-inspector-items-editor", ...
                        "ButtonPushedFcn", @(source, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.openItemsEditor(source, batchCommitFcn));
                case "fontStyle"
                    control = uipanel(parent, "BorderType", "none", ...
                        "Tag", "macd-inspector-font-style-editor");
                    grid = uigridlayout(control, [1 2], "Padding", [0 0 0 0], ...
                        "ColumnWidth", {34, 34}, "ColumnSpacing", 3);
                    weight = uibutton(grid, "state", "Text", "B", ...
                        "FontName", "Times", "FontWeight", "bold", "FontSize", 16, ...
                        "Tag", "macd-inspector-font-weight-button", ...
                        "ValueChangedFcn", @(source, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.commitFontStyle( ...
                        source, "FontWeight", "bold", "normal", batchCommitFcn));
                    angle = uibutton(grid, "state", "Text", "I", ...
                        "FontName", "Times", "FontAngle", "italic", "FontSize", 16, ...
                        "Tag", "macd-inspector-font-angle-button", ...
                        "ValueChangedFcn", @(source, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.commitFontStyle( ...
                        source, "FontAngle", "italic", "normal", batchCommitFcn));
                    control.UserData = struct("Weight", weight, "Angle", angle);
                otherwise
                    error("macd:PropertyEditorFactory:UnknownCompositeEditor", ...
                        "Unknown composite Inspector editor.");
            end
        end

        function result = supportsEditing(definition)
            % supportsEditing Return whether the definition has a native editable adapter.
            arguments (Input)
                definition (1, 1) macd.model.PropertyDefinition
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = any(definition.Editor == ["literal", "text", "logical", ...
                "onOff", "enum", "number", "numericVector", "color", "stringList", ...
                "multilineText", "url", "asset", "structuredData", "dateTime", "tableData", ...
                "itemSelection"]);
            if definition.Editor == "enum" && ~isfield(definition.ValueSchema, "values")
                result = false;
            end
        end

        function synchronizeComposite(control, row, members, relatedValues)
            % synchronizeComposite Load all member values into one composite editor host.
            arguments (Input)
                control
                row (1, 1) struct
                members (1, :) struct
                relatedValues struct = struct()
            end

            switch string(row.Editor)
                case "tableData"
                    state = macd.ui.inspector.PropertyEditorFactory.compositeState( ...
                        members, ["Data", "ColumnName", "RowName"]);
                    indexedPaths = ["ColumnWidth", "ColumnEditable", "ColumnSortable", "ColumnFormat"];
                    for indexedPath = indexedPaths
                        [state.(char(indexedPath)), state.("Has" + indexedPath)] = ...
                            macd.ui.inspector.PropertyEditorFactory.relatedKnownValue( ...
                            relatedValues, indexedPath, []);
                    end
                    state.HasData = macd.ui.inspector.PropertyEditorFactory.memberKnown(state, "Data");
                    control.UserData = state;
                    control.Text = macd.ui.inspector.TableDataEditorDialog.summary(state.Data);
                    control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff( ...
                        macd.ui.inspector.PropertyEditorFactory.membersEditable(members) && ...
                        state.HasData && macd.ui.inspector.TableDataEditorDialog.supportsData(state.Data));
                case "columnSettings"
                    state = macd.ui.inspector.PropertyEditorFactory.compositeState( ...
                        members, ["ColumnWidth", "ColumnEditable", "ColumnRearrangeable", ...
                        "ColumnSortable", "ColumnFormat"]);
                    [state.Data, state.HasData] = macd.ui.inspector.PropertyEditorFactory.relatedKnownValue( ...
                        relatedValues, "Data", []);
                    [state.ColumnName, state.HasColumnName] = ...
                        macd.ui.inspector.PropertyEditorFactory.relatedKnownValue( ...
                        relatedValues, "ColumnName", []);
                    control.UserData = state;
                    control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff( ...
                        macd.ui.inspector.PropertyEditorFactory.membersEditable(members) && ...
                        state.HasData && macd.ui.inspector.TableDataEditorDialog.supportsData(state.Data));
                case "items"
                    state = macd.ui.inspector.PropertyEditorFactory.compositeState( ...
                        members, ["Items", "ItemsData"]);
                    control.UserData = state;
                    control.Text = macd.ui.inspector.PropertyEditorFactory.listSummary(state.Items);
                    control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff( ...
                        macd.ui.inspector.PropertyEditorFactory.membersEditable(members) && ...
                        macd.ui.inspector.PropertyEditorFactory.isEditableItemList(state.Items));
                case "fontStyle"
                    state = macd.ui.inspector.PropertyEditorFactory.compositeState( ...
                        members, ["FontWeight", "FontAngle"]);
                    controls = control.UserData;
                    controls.Weight.Value = macd.ui.inspector.PropertyEditorFactory.fontState( ...
                        state.FontWeight, "bold");
                    controls.Angle.Value = macd.ui.inspector.PropertyEditorFactory.fontState( ...
                        state.FontAngle, "italic");
                    controls.Weight.Enable = macd.ui.inspector.PropertyEditorFactory.onOff( ...
                        macd.ui.inspector.PropertyEditorFactory.memberEditable(members, "FontWeight"));
                    controls.Angle.Enable = macd.ui.inspector.PropertyEditorFactory.onOff( ...
                        macd.ui.inspector.PropertyEditorFactory.memberEditable(members, "FontAngle"));
                    control.UserData = controls;
                otherwise
                    error("macd:PropertyEditorFactory:UnknownCompositeEditor", ...
                        "Unknown composite Inspector editor.");
            end
        end

        function synchronize(control, value, isEditable, rawValue, relatedValues)
            % synchronize Load a model value into one factory-created editor.
            arguments (Input)
                control
                value (1, 1) string
                isEditable (1, 1) logical
                rawValue = []
                relatedValues struct = struct()
            end

            if isprop(control, "Tag") && control.Tag == "macd-inspector-item-selection-editor"
                macd.ui.inspector.PropertyEditorFactory.synchronizeItemSelection( ...
                    control, rawValue, isEditable, relatedValues);
                return
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-date-picker-editor"
                macd.ui.inspector.PropertyEditorFactory.synchronizeDatePicker( ...
                    control, rawValue, isEditable, relatedValues);
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-date-limits-editor"
                macd.ui.inspector.PropertyEditorFactory.synchronizeDateLimits( ...
                    control, rawValue, isEditable);
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-date-list-editor"
                control.UserData = rawValue;
                control.Text = macd.ui.inspector.PropertyEditorFactory.dateListSummary(rawValue);
                control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff( ...
                    isEditable && macd.ui.inspector.PropertyEditorFactory.isSafeDateList(rawValue));
                return
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-day-of-week-editor"
                control.UserData = rawValue;
                control.Text = macd.ui.inspector.PropertyEditorFactory.daySummary(rawValue);
                control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff( ...
                    isEditable && macd.ui.inspector.PropertyEditorFactory.isSafeDayOfWeekValue(rawValue));
                return
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-table-data-editor"
                state = macd.ui.inspector.PropertyEditorFactory.tableDataState( ...
                    control.UserData.Path, rawValue, relatedValues);
                control.UserData = state;
                control.Text = macd.ui.inspector.TableDataEditorDialog.summary(state.Data);
                control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff( ...
                    isEditable && state.HasData && ...
                    macd.ui.inspector.TableDataEditorDialog.supportsData(state.Data));
                return
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-asset-editor"
                parts = control.UserData;
                if ischar(rawValue) && isrow(rawValue)
                    parts.Edit.Value = string(rawValue);
                elseif isstring(rawValue) && isscalar(rawValue)
                    parts.Edit.Value = rawValue;
                else
                    parts.Edit.Value = string(value);
                end
                parts.Edit.Editable = isEditable;
                parts.Browse.Enable = macd.ui.inspector.PropertyEditorFactory.onOff(isEditable);
            elseif isa(control, "matlab.ui.control.CheckBox")
                logicalValue = value;
                if ~isempty(rawValue)
                    logicalValue = string(rawValue);
                end
                control.Value = logicalValue == "on" || logicalValue == "true" || logicalValue == "1";
                control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff(isEditable);
            elseif isa(control, "matlab.ui.control.DropDown")
                % Prefer the raw char or string value over its inspector literal rendering.
                selectedValue = value;
                if (ischar(rawValue) && isrow(rawValue)) || ...
                        (isstring(rawValue) && isscalar(rawValue))
                    selectedValue = string(rawValue);
                end
                % Retain documented or runtime defaults absent from an incomplete enum contract.
                items = string(control.Items);
                if ~any(items == selectedValue)
                    control.Items = cellstr([items(:); selectedValue]);
                end
                control.Value = char(selectedValue);
                control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff(isEditable);
            elseif isa(control, "matlab.ui.control.NumericEditField")
                number = str2double(value);
                if ~isnan(number)
                    control.Value = number;
                end
                control.Editable = isEditable;
            elseif isa(control, "matlab.ui.control.Button")
                control.Text = char(value);
                control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff(isEditable);
                if control.Tag == "macd-inspector-string-list-editor"
                    control.UserData = rawValue;
                    control.Text = macd.ui.inspector.PropertyEditorFactory.listSummary(rawValue);
                    return
                end
                if control.Tag == "macd-inspector-structured-data-editor"
                    state = struct("Value", {rawValue}, "Items", {[]}, "HasItems", false);
                    if isfield(relatedValues, "Paths") && isfield(relatedValues, "Values") && ...
                            isfield(relatedValues, "KnownValues")
                        itemIndex = find(string(relatedValues.Paths) == "Items", 1);
                        if ~isempty(itemIndex) && relatedValues.KnownValues(itemIndex)
                            state.Items = relatedValues.Values(itemIndex);
                            state.HasItems = true;
                        end
                    elseif isfield(relatedValues, "Items")
                        % Retain direct factory-test compatibility with the prior narrow snapshot.
                        state.Items = {relatedValues.Items};
                        state.HasItems = true;
                    end
                    control.UserData = state;
                    control.Text = macd.ui.inspector.PropertyEditorFactory.structuredSummary(rawValue, value);
                    control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff( ...
                        isEditable && (state.HasItems || ...
                        macd.ui.inspector.PropertyEditorFactory.isSafeStructuredLiteral(rawValue)));
                    return
                end
                [rgb, isLiteral] = macd.source.MatlabLiteralParser.parse(value);
                if isLiteral && isnumeric(rgb) && isequal(size(rgb), [1 3]) && ...
                        all(isfinite(rgb)) && all(rgb >= 0) && all(rgb <= 1)
                    control.BackgroundColor = rgb;
                    control.UserData = rgb;
                else
                    control.BackgroundColor = [0.94 0.94 0.94];
                    control.UserData = [];
                end
            elseif isa(control, "matlab.ui.control.TextArea")
                if iscell(rawValue) || (isstring(rawValue) && ~isscalar(rawValue))
                    control.Value = rawValue;
                elseif ischar(rawValue) || (isstring(rawValue) && isscalar(rawValue))
                    control.Value = {char(rawValue)};
                else
                    control.Value = {char(value)};
                end
                control.UserData = rawValue;
                control.Editable = isEditable;
            elseif isprop(control, "UserData") && isstruct(control.UserData) && ...
                    isfield(control.UserData, "Kind") && control.UserData.Kind == "text"
                state = control.UserData;
                state.Value = rawValue;
                control.UserData = state;
                if ischar(rawValue) && isrow(rawValue)
                    control.Value = string(rawValue);
                elseif isstring(rawValue) && isscalar(rawValue)
                    control.Value = rawValue;
                else
                    control.Value = string(value);
                end
                control.Editable = isEditable;
            elseif isprop(control, "UserData") && isstruct(control.UserData) && ...
                    isfield(control.UserData, "Kind") && control.UserData.Kind == "url"
                state = control.UserData;
                state.Value = rawValue;
                control.UserData = state;
                if ischar(rawValue) && isrow(rawValue)
                    control.Value = string(rawValue);
                elseif isstring(rawValue) && isscalar(rawValue)
                    control.Value = rawValue;
                else
                    control.Value = string(value);
                end
                control.Editable = isEditable;
            else
                control.Value = char(value);
                control.Editable = isEditable && ~macd.ui.inspector.PropertyEditorFactory.isReadOnlyFallback(control);
            end
        end

        function value = editorValue(control)
            % editorValue Return the current adapter value without parsing or committing it.
            arguments (Input)
                control
            end

            if isprop(control, "Tag") && control.Tag == "macd-inspector-date-picker-editor"
                value = control.Value;
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-date-limits-editor"
                parts = control.UserData;
                value = [parts.Start.Value parts.End.Value];
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-date-list-editor"
                value = control.UserData;
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-day-of-week-editor"
                value = control.UserData;
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-asset-editor"
                value = control.UserData.Edit.Value;
            elseif isa(control, "matlab.ui.control.CheckBox") || ...
                    isa(control, "matlab.ui.control.NumericEditField") || ...
                    isa(control, "matlab.ui.control.EditField") || ...
                    isa(control, "matlab.ui.control.TextArea")
                value = control.Value;
            elseif isa(control, "matlab.ui.control.Button")
                value = control.UserData;
            else
                value = [];
            end
        end

        function restoreDraft(control, value)
            % restoreDraft Restore an uncommitted adapter value without invoking its callback.
            arguments (Input)
                control
                value
            end

            if isprop(control, "Tag") && control.Tag == "macd-inspector-date-picker-editor"
                if isdatetime(value) && isscalar(value)
                    control.Value = value;
                end
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-date-limits-editor"
                parts = control.UserData;
                if isdatetime(value) && numel(value) == 2
                    parts.Start.Value = value(1);
                    parts.End.Value = value(2);
                end
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-date-list-editor"
                control.UserData = value;
                control.Text = macd.ui.inspector.PropertyEditorFactory.dateListSummary(value);
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-day-of-week-editor"
                control.UserData = value;
                control.Text = macd.ui.inspector.PropertyEditorFactory.daySummary(value);
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-table-data-editor"
                state = control.UserData;
                if isstruct(state) && isfield(state, "Path")
                    state.Data = value;
                    state.HasData = true;
                    control.UserData = state;
                    control.Text = macd.ui.inspector.TableDataEditorDialog.summary(value);
                end
            elseif isprop(control, "Tag") && control.Tag == "macd-inspector-asset-editor"
                parts = control.UserData;
                parts.Edit.Value = value;
            elseif isa(control, "matlab.ui.control.CheckBox") || ...
                    isa(control, "matlab.ui.control.NumericEditField") || ...
                    isa(control, "matlab.ui.control.EditField") || ...
                    isa(control, "matlab.ui.control.TextArea")
                control.Value = value;
            elseif isa(control, "matlab.ui.control.Button")
                control.UserData = value;
                if control.Tag == "macd-inspector-string-list-editor"
                    control.Text = macd.ui.inspector.PropertyEditorFactory.listSummary(value);
                elseif control.Tag == "macd-inspector-structured-data-editor"
                    control.Text = macd.ui.inspector.PropertyEditorFactory.structuredSummary(value, "");
                elseif isnumeric(value) && isequal(size(value), [1 3])
                    control.BackgroundColor = value;
                end
            end
        end
    end

    methods (Static, Access = private)
        function control = createItemSelection(parent, definition, commitFcn)
            % createItemSelection Create an Items-backed native selection control.
            arguments (Input)
                parent
                definition (1, 1) macd.model.PropertyDefinition
                commitFcn (1, 1) function_handle
            end
            arguments (Output)
                control
            end

            % List Box is the one audited family whose Value can be multivalued.
            schema = definition.ValueSchema;
            if isfield(schema, "multiselectProperty")
                control = uilistbox(parent, "Tag", "macd-inspector-item-selection-editor", ...
                    "ValueChangedFcn", @(source, ~) ...
                    macd.ui.inspector.PropertyEditorFactory.commitItemSelection(source, commitFcn));
            else
                control = uidropdown(parent, "Tag", "macd-inspector-item-selection-editor", ...
                    "ValueChangedFcn", @(source, ~) ...
                    macd.ui.inspector.PropertyEditorFactory.commitItemSelection(source, commitFcn));
            end
            control.UserData = struct("Schema", schema, "Labels", strings(0, 1), ...
                "Values", {cell(1, 0)}, "HasCandidates", false);
        end

        function synchronizeItemSelection(control, rawValue, isEditable, relatedValues)
            % synchronizeItemSelection Load Items labels and optional ItemsData mappings.
            arguments (Input)
                control
                rawValue
                isEditable (1, 1) logical
                relatedValues struct = struct()
            end

            state = macd.ui.inspector.PropertyEditorFactory.itemSelectionState( ...
                rawValue, control.UserData.Schema, relatedValues);
            control.Items = cellstr(state.Labels);
            control.UserData = state;
            control.Tooltip = state.Message;
            control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff( ...
                isEditable && state.HasCandidates);

            if isa(control, "matlab.ui.control.ListBox")
                control.Multiselect = macd.ui.inspector.PropertyEditorFactory.onOff(state.Multiselect);
                if isempty(state.SelectedIndices)
                    control.Value = {};
                elseif state.Multiselect
                    control.Value = cellstr(state.Labels(state.SelectedIndices));
                else
                    control.Value = char(state.Labels(state.SelectedIndices(1)));
                end
            else
                % DropDown requires one valid selected label, including the empty sentinel.
                selectedIndex = state.SelectedIndices(1);
                control.Value = char(state.Labels(selectedIndex));
            end
        end

        function commitItemSelection(source, commitFcn)
            % commitItemSelection Map selected labels back to ItemsData or Items literals.
            arguments (Input)
                source
                commitFcn (1, 1) function_handle
            end

            state = source.UserData;
            selectedLabels = string(source.Value);
            selectedValues = cell(1, numel(selectedLabels));
            for index = 1:numel(selectedLabels)
                selectedIndex = find(state.Labels == selectedLabels(index), 1);
                if isempty(selectedIndex)
                    return
                end
                selectedValues{index} = state.Values{selectedIndex};
            end
            value = macd.ui.inspector.PropertyEditorFactory.itemSelectionOutput(selectedValues);
            if (ischar(value) && isrow(value)) || (isstring(value) && isscalar(value))
                value = macd.source.LiteralEncoder.encode(value);
            end
            commitFcn(value);
        end

        function state = itemSelectionState(rawValue, schema, relatedValues)
            % itemSelectionState Build display labels, selected values, and multiselect state.
            arguments (Input)
                rawValue
                schema (1, 1) struct
                relatedValues struct
            end
            arguments (Output)
                state (1, 1) struct
            end

            [items, hasItems] = macd.ui.inspector.PropertyEditorFactory.relatedKnownValue( ...
                relatedValues, "Items", []);
            [itemsData, hasItemsData] = macd.ui.inspector.PropertyEditorFactory.relatedKnownValue( ...
                relatedValues, "ItemsData", []);
            labels = macd.ui.inspector.PropertyEditorFactory.itemSelectionLabels(items);
            values = macd.ui.inspector.PropertyEditorFactory.itemSelectionCells(items);
            message = "";
            hasCandidates = hasItems && ~isempty(labels);
            if hasItemsData && ~isempty(itemsData)
                dataValues = macd.ui.inspector.PropertyEditorFactory.itemSelectionCells(itemsData);
                if numel(dataValues) == numel(labels)
                    values = dataValues;
                else
                    hasCandidates = false;
                    message = "ItemsData must have the same number of values as Items.";
                end
            end
            multiselect = false;
            if isfield(schema, "multiselectProperty")
                property = string(schema.multiselectProperty);
                [flag, hasFlag] = macd.ui.inspector.PropertyEditorFactory.relatedKnownValue( ...
                    relatedValues, property, "off");
                multiselect = hasFlag && macd.ui.inspector.PropertyEditorFactory.isOn(flag);
            end
            selectedIndices = macd.ui.inspector.PropertyEditorFactory.itemSelectionIndices( ...
                rawValue, values, multiselect);

            % Preserve an empty or imported unmatched current value without inventing a choice.
            if isempty(selectedIndices) && ~(isempty(rawValue) && multiselect)
                if isempty(rawValue) && isfield(schema, "allowsEmpty") && schema.allowsEmpty
                    labels = ["<empty>"; labels];
                    values = [{[]}, values];
                    selectedIndices = 1;
                else
                    labels = ["<current value>"; labels];
                    values = [{rawValue}, values];
                    selectedIndices = 1;
                    if strlength(message) == 0
                        message = "The current value is not represented by the current Items.";
                    end
                end
            end
            if isempty(labels)
                labels = "<set Items first>";
                values = {[]};
                selectedIndices = 1;
            end
            state = struct("Schema", schema, "Labels", labels, "Values", {values}, ...
                "HasCandidates", hasCandidates, "Multiselect", multiselect, ...
                "SelectedIndices", selectedIndices, "Message", message);
        end

        function labels = itemSelectionLabels(items)
            % itemSelectionLabels Normalize supported Items text into UI labels.
            arguments (Input)
                items
            end
            arguments (Output)
                labels string
            end

            if isstring(items)
                labels = reshape(items, [], 1);
            elseif iscell(items) && all(cellfun(@(item) ischar(item) && isrow(item), items))
                labels = string(items(:));
            elseif ischar(items) && isrow(items)
                labels = string(items);
            else
                labels = strings(0, 1);
            end
        end

        function values = itemSelectionCells(value)
            % itemSelectionCells Split a supported Items or ItemsData vector into literal cells.
            arguments (Input)
                value
            end
            arguments (Output)
                values cell
            end

            if iscell(value)
                values = reshape(value, 1, []);
            elseif ischar(value) && isrow(value)
                values = {value};
            elseif isstring(value)
                values = num2cell(reshape(value, 1, []));
            elseif isvector(value)
                values = num2cell(reshape(value, 1, []));
            else
                values = cell(1, 0);
            end
        end

        function indices = itemSelectionIndices(value, candidates, multiselect)
            % itemSelectionIndices Find selected candidate positions without coercing literals.
            arguments (Input)
                value
                candidates cell
                multiselect (1, 1) logical
            end
            arguments (Output)
                indices double
            end

            selected = macd.ui.inspector.PropertyEditorFactory.itemSelectionCells(value);
            if isempty(selected)
                indices = zeros(1, 0);
                return
            end
            if ~multiselect && numel(selected) ~= 1
                indices = zeros(1, 0);
                return
            end
            indices = zeros(1, numel(selected));
            for index = 1:numel(selected)
                candidateIndex = find(cellfun(@(candidate) isequaln(candidate, selected{index}), candidates), 1);
                if isempty(candidateIndex)
                    indices = zeros(1, 0);
                    return
                end
                indices(index) = candidateIndex;
            end
        end

        function value = itemSelectionOutput(values)
            % itemSelectionOutput Restore a practical MATLAB value shape from selected literals.
            arguments (Input)
                values cell
            end
            arguments (Output)
                value
            end

            if isempty(values)
                value = [];
            elseif isscalar(values)
                value = values{1};
            elseif all(cellfun(@(item) isnumeric(item) && isscalar(item), values)) || ...
                    all(cellfun(@(item) islogical(item) && isscalar(item), values))
                value = cell2mat(values);
            elseif all(cellfun(@(item) ischar(item) && isrow(item), values))
                value = reshape(values, 1, []);
            elseif all(cellfun(@(item) isstring(item) && isscalar(item), values))
                value = [values{:}];
            else
                value = values;
            end
        end

        function result = isOn(value)
            % isOn Interpret the documented logical and on/off representations.
            result = (islogical(value) && isscalar(value) && value) || ...
                ((ischar(value) && isrow(value) || (isstring(value) && isscalar(value))) && ...
                lower(string(value)) == "on");
        end

        function result = isDayOfWeekSchema(definition)
            % isDayOfWeekSchema Identify the catalog contract for the compact weekday editor.
            arguments (Input)
                definition (1, 1) macd.model.PropertyDefinition
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = isfield(definition.ValueSchema, "kind") && ...
                string(definition.ValueSchema.kind) == "dayOfWeekList";
        end

        function openDayOfWeekEditor(control, path, batchCommitFcn)
            % openDayOfWeekEditor Open a weekday draft that commits through the dialog batch path.
            arguments (Input)
                control (1, 1) matlab.ui.control.Button
                path (1, 1) string
                batchCommitFcn (1, 1) function_handle
            end
            original = control.UserData;
            days = macd.ui.inspector.PropertyEditorFactory.dayNumbers(original);
            owner = ancestor(control, "figure");
            visible = isempty(owner) || string(owner.Visible) == "on";
            macd.ui.inspector.DayOfWeekEditorDialog.open(days, path, @(changes) ...
                batchCommitFcn(struct("Path", changes.Path, "Value", ...
                macd.ui.inspector.PropertyEditorFactory.dayValue(changes.Value, original))), visible);
        end

        function openTableDataEditor(control, batchCommitFcn)
            % openTableDataEditor Open the complete table draft through the shared batch pathway.
            arguments (Input)
                control (1, 1) matlab.ui.control.Button
                batchCommitFcn (1, 1) function_handle
            end

            state = control.UserData;
            owner = ancestor(control, "figure");
            visible = isempty(owner) || string(owner.Visible) == "on";
            macd.ui.inspector.TableDataEditorDialog.open(state, batchCommitFcn, visible);
        end

        function openColumnSettingsEditor(control, batchCommitFcn)
            % openColumnSettingsEditor Open the staged per-column settings dialog.
            arguments (Input)
                control (1, 1) matlab.ui.control.Button
                batchCommitFcn (1, 1) function_handle
            end

            owner = ancestor(control, "figure");
            visible = isempty(owner) || string(owner.Visible) == "on";
            macd.ui.inspector.ColumnSettingsEditorDialog.open( ...
                control.UserData, batchCommitFcn, visible);
        end

        function openItemsEditor(control, batchCommitFcn)
            % openItemsEditor Open one paired Items and ItemsData candidate dialog.
            arguments (Input)
                control (1, 1) matlab.ui.control.Button
                batchCommitFcn (1, 1) function_handle
            end

            owner = ancestor(control, "figure");
            visible = isempty(owner) || string(owner.Visible) == "on";
            macd.ui.inspector.ItemsDataEditorDialog.openComposite( ...
                control.UserData, batchCommitFcn, visible);
        end

        function state = tableDataState(currentPath, rawValue, relatedValues)
            % tableDataState Gather Data and heading values from one effective inspector snapshot.
            arguments (Input)
                currentPath (1, 1) string
                rawValue
                relatedValues struct
            end
            arguments (Output)
                state (1, 1) struct
            end

            paths = ["Data", "ColumnName", "RowName"];
            values = {[], [], []};
            known = false(1, numel(paths));
            for index = 1:numel(paths)
                if paths(index) == currentPath
                    values{index} = rawValue;
                    known(index) = ~isempty(rawValue) || currentPath == "Data";
                else
                    [values{index}, known(index)] = ...
                        macd.ui.inspector.PropertyEditorFactory.relatedKnownValue( ...
                        relatedValues, paths(index), []);
                end
            end
            state = struct("Path", currentPath, "Data", [], "ColumnName", [], "RowName", [], ...
                "HasData", known(1), "HasColumnName", known(2), "HasRowName", known(3));
            state.Data = values{1};
            state.ColumnName = values{2};
            state.RowName = values{3};
        end

        function state = compositeState(members, paths)
            % compositeState Copy named member values and editability into one adapter state.
            arguments (Input)
                members (1, :) struct
                paths (1, :) string
            end
            arguments (Output)
                state (1, 1) struct
            end

            state = struct();
            state.MemberPaths = paths;
            state.MemberEditable = false(1, numel(paths));
            state.MemberKnown = false(1, numel(paths));
            for index = 1:numel(paths)
                memberIndex = find(string({members.Path}) == paths(index), 1);
                if isempty(memberIndex)
                    continue
                end
                member = members(memberIndex);
                state.(char(paths(index))) = member.RawValue;
                state.MemberEditable(index) = member.IsEditable;
                state.MemberKnown(index) = member.IsKnown;
            end
        end

        function result = memberKnown(state, path)
            % memberKnown Read one composite availability bit by property path.
            index = find(state.MemberPaths == path, 1);
            result = ~isempty(index) && state.MemberKnown(index);
        end

        function result = membersEditable(members)
            % membersEditable Require all composite members to be editable and known.
            result = all([members.IsEditable]) && all([members.IsKnown]);
        end

        function result = memberEditable(members, path)
            % memberEditable Read one member-specific editability state.
            index = find(string({members.Path}) == path, 1);
            result = ~isempty(index) && members(index).IsEditable && members(index).IsKnown;
        end

        function result = fontState(value, enabledValue)
            % fontState Map normalized text values to one typographic state button.
            result = (ischar(value) || (isstring(value) && isscalar(value))) && ...
                lower(string(value)) == enabledValue;
        end

        function result = isEditableItemList(value)
            % isEditableItemList Limit paired item editing to documented text list forms.
            result = isstring(value) || iscell(value) || (ischar(value) && isrow(value));
            if iscell(value)
                result = all(cellfun(@(item) ischar(item) && isrow(item), value));
            end
        end

        function commitFontStyle(control, path, enabledValue, disabledValue, batchCommitFcn)
            % commitFontStyle Submit one font-style toggle through the common batch route.
            arguments (Input)
                control (1, 1) matlab.ui.control.StateButton
                path (1, 1) string
                enabledValue (1, 1) string
                disabledValue (1, 1) string
                batchCommitFcn (1, 1) function_handle
            end

            value = char(disabledValue);
            if control.Value
                value = char(enabledValue);
            end
            message = batchCommitFcn(macd.model.PropertyTransaction.singleChange(path, value));
            if strlength(message) > 0
                control.Tooltip = message;
                control.BackgroundColor = [1 0.9 0.9];
            end
        end

        function [value, known] = relatedKnownValue(relatedValues, path, fallback)
            % relatedKnownValue Read one value and its availability bit from a related snapshot.
            arguments (Input)
                relatedValues struct
                path (1, 1) string
                fallback
            end
            arguments (Output)
                value
                known (1, 1) logical
            end

            value = fallback;
            known = false;
            if ~isfield(relatedValues, "Paths") || ~isfield(relatedValues, "Values") || ...
                    ~isfield(relatedValues, "KnownValues")
                return
            end
            index = find(string(relatedValues.Paths) == path, 1);
            if ~isempty(index) && relatedValues.KnownValues(index)
                value = relatedValues.Values{index};
                known = true;
            end
        end

        function result = dayValue(days, original)
            % dayValue Retain numeric, string, or cell style while mapping selected weekdays.
            arguments (Input)
                days double
                original
            end
            arguments (Output)
                result
            end

            names = ["Sunday", "Monday", "Tuesday", "Wednesday", ...
                "Thursday", "Friday", "Saturday"];
            if isstring(original)
                result = names(days);
            elseif iscell(original)
                result = cellstr(names(days));
            else
                result = reshape(days, 1, []);
            end
        end

        function result = dayNumbers(value)
            % dayNumbers Normalize documented numeric or English weekday forms to button indices.
            arguments (Input)
                value
            end
            arguments (Output)
                result double
            end

            if isnumeric(value)
                result = reshape(value(isfinite(value) & value == floor(value) & ...
                    value >= 1 & value <= 7), 1, []);
                return
            end
            if ~(isstring(value) || iscell(value))
                result = zeros(1, 0);
                return
            end
            names = lower(["Sunday", "Monday", "Tuesday", "Wednesday", ...
                "Thursday", "Friday", "Saturday"]);
            values = lower(strtrim(string(value)));
            result = zeros(1, 0);
            for index = 1:numel(values)
                match = find(startsWith(names, values(index)), 1);
                if ~isempty(match)
                    result(end + 1) = match; %#ok<AGROW>
                end
            end
            result = unique(result, "sorted");
        end

        function result = daySummary(value)
            % daySummary Render selected weekdays in concise English for the inspector button.
            arguments (Input)
                value
            end
            arguments (Output)
                result (1, 1) string
            end

            names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
            days = macd.ui.inspector.PropertyEditorFactory.dayNumbers(value);
            if isempty(days)
                result = "No disabled weekdays";
            else
                result = strjoin(names(days), ", ");
            end
        end

        function result = isSafeDayOfWeekValue(value)
            % isSafeDayOfWeekValue Return whether documented weekday data can open the dedicated editor.
            arguments (Input)
                value
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = isnumeric(value) || isstring(value) || iscell(value);
        end

        function control = createDateTimeEditor(parent, definition, commitFcn, batchCommitFcn)
            % createDateTimeEditor Select a native date adapter from the audited schema shape.
            arguments (Input)
                parent
                definition (1, 1) macd.model.PropertyDefinition
                commitFcn (1, 1) function_handle
                batchCommitFcn (1, 1) function_handle
            end
            arguments (Output)
                control
            end

            schema = definition.ValueSchema;
            shape = string(schema.shape);
            if shape == "scalar"
                control = uidatepicker(parent, "Tag", "macd-inspector-date-picker-editor", ...
                    "ValueChangedFcn", @(source, ~) commitFcn(source.Value));
                return
            end
            if shape == "fixedLengthVector"
                control = uipanel(parent, "BorderType", "none", ...
                    "Tag", "macd-inspector-date-limits-editor");
                grid = uigridlayout(control, [2 2], "Padding", [0 0 0 0], ...
                    "RowHeight", {25, 25}, "ColumnWidth", {36, "1x"}, "RowSpacing", 2);
                uilabel(grid, "Text", "Start");
                start = uidatepicker(grid, "Tag", "macd-inspector-date-limit-start");
                uilabel(grid, "Text", "End");
                finish = uidatepicker(grid, "Tag", "macd-inspector-date-limit-end");
                parts = struct("Start", start, "End", finish);
                control.UserData = parts;
                start.UserData = parts;
                finish.UserData = parts;
                start.ValueChangedFcn = @(source, ~) ...
                    macd.ui.inspector.PropertyEditorFactory.commitDateLimits(source, commitFcn);
                finish.ValueChangedFcn = @(source, ~) ...
                    macd.ui.inspector.PropertyEditorFactory.commitDateLimits(source, commitFcn);
                return
            end
            if shape == "vector"
                control = uibutton(parent, "Text", "Edit dates", ...
                    "Tag", "macd-inspector-date-list-editor", ...
                    "ButtonPushedFcn", @(source, ~) ...
                    macd.ui.inspector.DateListEditorDialog.open( ...
                    source.UserData, definition.Path, batchCommitFcn));
                return
            end
            error("macd:PropertyEditorFactory:UnsupportedDateTimeSchema", ...
                "The dateTime editor requires a scalar, fixed-length vector, or vector schema.");
        end

        function synchronizeDatePicker(control, rawValue, isEditable, relatedValues)
            % synchronizeDatePicker Load a date and its effective calendar restrictions into one picker.
            arguments (Input)
                control
                rawValue
                isEditable (1, 1) logical
                relatedValues struct = struct()
            end

            if macd.ui.inspector.PropertyEditorFactory.isSafeDateScalar(rawValue)
                limits = macd.ui.inspector.PropertyEditorFactory.relatedValue( ...
                    relatedValues, "Limits", []);
                disabledDates = macd.ui.inspector.PropertyEditorFactory.relatedValue( ...
                    relatedValues, "DisabledDates", datetime.empty(0, 1));
                disabledDays = macd.ui.inspector.PropertyEditorFactory.relatedValue( ...
                    relatedValues, "DisabledDaysOfWeek", []);
                if macd.ui.inspector.PropertyEditorFactory.isSafeDateLimits(limits)
                    control.Limits = limits;
                end
                if macd.ui.inspector.PropertyEditorFactory.isSafeDateList(disabledDates)
                    control.DisabledDates = reshape(disabledDates, [], 1);
                end
                if macd.ui.inspector.PropertyEditorFactory.isSafeDayOfWeekValue(disabledDays)
                    control.DisabledDaysOfWeek = disabledDays;
                end
                control.Value = rawValue;
                control.UserData = rawValue;
                control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff(isEditable);
            else
                control.Value = NaT;
                control.UserData = [];
                control.Enable = "off";
            end
        end

        function value = relatedValue(relatedValues, path, fallback)
            % relatedValue Read one known effective value from the inspector's property snapshot.
            arguments (Input)
                relatedValues struct
                path (1, 1) string
                fallback
            end
            arguments (Output)
                value
            end

            value = fallback;
            if ~isfield(relatedValues, "Paths") || ~isfield(relatedValues, "Values") || ...
                    ~isfield(relatedValues, "KnownValues")
                return
            end
            index = find(string(relatedValues.Paths) == path, 1);
            if ~isempty(index) && relatedValues.KnownValues(index)
                value = relatedValues.Values{index};
            end
        end

        function synchronizeDateLimits(control, rawValue, isEditable)
            % synchronizeDateLimits Load both bounds together, preserving the atomic editor contract.
            arguments (Input)
                control
                rawValue
                isEditable (1, 1) logical
            end

            parts = control.UserData;
            if macd.ui.inspector.PropertyEditorFactory.isSafeDateLimits(rawValue)
                parts.Start.Value = rawValue(1);
                parts.End.Value = rawValue(2);
                enabled = macd.ui.inspector.PropertyEditorFactory.onOff(isEditable);
                parts.Start.Enable = enabled;
                parts.End.Enable = enabled;
            else
                parts.Start.Value = NaT;
                parts.End.Value = NaT;
                parts.Start.Enable = "off";
                parts.End.Enable = "off";
            end
        end

        function commitDateLimits(source, commitFcn)
            % commitDateLimits Submit both bounds as one property candidate after either edit.
            arguments (Input)
                source
                commitFcn (1, 1) function_handle
            end

            parts = source.UserData;
            commitFcn([parts.Start.Value parts.End.Value]);
        end

        function result = isSafeDateScalar(value)
            % isSafeDateScalar Return whether one value can enter a native date picker losslessly.
            arguments (Input)
                value
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = isdatetime(value) && isscalar(value) && isempty(value.TimeZone) && ...
                (isnat(value) || seconds(timeofday(value)) == 0);
        end

        function result = isSafeDateLimits(value)
            % isSafeDateLimits Return whether two date-only bounds can enter paired pickers.
            arguments (Input)
                value
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = isdatetime(value) && isvector(value) && numel(value) == 2 && ...
                isempty(value.TimeZone) && ~any(isnat(value)) && ...
                all(seconds(timeofday(value)) == 0);
        end

        function result = isSafeDateList(value)
            % isSafeDateList Return whether a datetime vector can open the disabled-date dialog.
            arguments (Input)
                value
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = isdatetime(value) && (isempty(value) || isvector(value)) && ...
                isempty(value.TimeZone) && ~any(isnat(value)) && ...
                all(seconds(timeofday(value)) == 0);
        end

        function text = dateListSummary(value)
            % dateListSummary Describe a safe disabled-date vector without formatted source parsing.
            arguments (Input)
                value
            end
            arguments (Output)
                text (1, 1) string
            end

            if macd.ui.inspector.PropertyEditorFactory.isSafeDateList(value)
                text = sprintf("%d disabled dates", numel(value));
            else
                text = "Unsupported dates";
            end
        end

        function items = enumItems(definition)
            % enumItems Extract finite enum choices from the definition schema.
            items = strings(1, 0);
            if isfield(definition.ValueSchema, "values")
                items = string(definition.ValueSchema.values);
            end
            if isempty(items)
                items = "";
            end
        end

        function result = onOff(value)
            % onOff Convert a logical enable flag to the MATLAB UI token.
            if value
                result = "on";
            else
                result = "off";
            end
        end

        function result = isReadOnlyFallback(control)
            % isReadOnlyFallback Identify controls created for deferred editor kinds.
            result = isstring(control.UserData) && isscalar(control.UserData) && ...
                control.UserData == "readOnlyFallback";
        end

        function applyNumberSchema(control, schema)
            % applyNumberSchema Apply supported scalar constraints to a numeric editor.
            arguments (Input)
                control (1, 1) matlab.ui.control.NumericEditField
                schema (1, 1) struct
            end

            if isfield(schema, "minimum")
                control.Limits(1) = schema.minimum;
            end
            if isfield(schema, "maximum")
                control.Limits(2) = schema.maximum;
            end
            if isfield(schema, "integer") && schema.integer
                control.RoundFractionalValues = "on";
            end
        end

        function pickColor(control, commitFcn)
            % pickColor Open the native picker and commit a valid RGB row vector.
            arguments (Input)
                control (1, 1) matlab.ui.control.Button
                commitFcn (1, 1) function_handle
            end

            current = control.UserData;
            if ~isnumeric(current) || ~isequal(size(current), [1 3])
                current = [0 0 0];
            end
            selected = uisetcolor(current);
            if isnumeric(selected) && isequal(size(selected), [1 3]) && ...
                    all(isfinite(selected)) && all(selected >= 0) && all(selected <= 1)
                commitFcn(selected);
            end
            owner = ancestor(control, "figure");
            if ~isempty(owner) && isvalid(owner)
                focus(owner);
            end
        end

        function text = listSummary(value)
            % listSummary Describe a string-list value without flattening its shape.
            if isstring(value)
                text = sprintf("%d-by-%d string", size(value, 1), size(value, 2));
            elseif iscell(value)
                text = sprintf("%d item cell list", numel(value));
            else
                text = "Edit list";
            end
        end

        function text = structuredSummary(value, fallback)
            % structuredSummary Describe safe structured data without coercing its type.
            try
                text = macd.source.LiteralEncoder.encode(value);
            catch
                text = string(fallback);
                if strlength(text) == 0
                    text = "Unsupported data";
                end
            end
            if strlength(text) > 42
                text = extractBefore(text, 40) + "...";
            end
        end

        function result = isSafeStructuredLiteral(value)
            % isSafeStructuredLiteral Return whether data can enter the modal literal editor.
            try
                macd.source.LiteralEncoder.encode(value);
                result = true;
            catch exception
                if exception.identifier ~= "macd:LiteralEncoder:UnsupportedValue"
                    rethrow(exception)
                end
                result = false;
            end
        end

        function commitTextArea(control, commitFcn)
            % commitTextArea Preserve scalar char/string representation when possible.
            draft = control.Value;
            original = control.UserData;
            if ischar(original) && isrow(original) && iscell(draft) && isscalar(draft)
                draft = char(draft{1});
            elseif isstring(original) && isscalar(original) && iscell(draft) && isscalar(draft)
                draft = string(draft{1});
            elseif iscell(draft)
                % TextArea returns visual lines as a column; source literals use a row cell array.
                draft = reshape(draft, 1, []);
            end
            commitFcn(draft);
        end

        function commitUrl(control, commitFcn)
            % commitUrl Commit a URL as plain text while preserving char/string style.
            draft = string(control.Value);
            if contains(draft, newline) || contains(draft, char(13))
                return
            end
            original = control.UserData.Value;
            if ischar(original)
                commitFcn(char(draft));
            else
                commitFcn(draft);
            end
        end

        function commitText(control, commitFcn)
            % commitText Commit one plain text value without treating it as source syntax.
            arguments (Input)
                control (1, 1) matlab.ui.control.EditField
                commitFcn (1, 1) function_handle
            end

            draft = string(control.Value);
            original = control.UserData.Value;
            if ischar(original) && isrow(original)
                commitFcn(char(draft));
            elseif isstring(original) && isscalar(original)
                commitFcn(draft);
            else
                % Use character text for an absent or non-text default; it is the common API form.
                commitFcn(char(draft));
            end
        end

        function openStructuredDataEditor(state, path, commitFcn)
            % openStructuredDataEditor Select the ItemsData or generic safe-literal editor.
            if isstruct(state) && isfield(state, "HasItems") && state.HasItems
                macd.ui.inspector.ItemsDataEditorDialog.open( ...
                    state.Items{1}, state.Value, path, commitFcn);
            elseif isstruct(state) && isfield(state, "Value")
                macd.ui.inspector.StructuredDataEditorDialog.open(state.Value, path, commitFcn);
            else
                macd.ui.inspector.StructuredDataEditorDialog.open(state, path, commitFcn);
            end
        end

        function message = commitSingleChange(commitFcn, changes)
            % commitSingleChange Adapt legacy one-value callbacks to a one-property batch.
            arguments (Input)
                commitFcn (1, 1) function_handle
                changes (1, :) struct
            end
            arguments (Output)
                message (1, 1) string
            end

            if numel(changes) ~= 1
                error("macd:PropertyEditorFactory:InvalidSingleChange", ...
                    "A legacy editor callback can commit only one property value.");
            end
            commitFcn(changes.Value);
            message = "";
        end

        function browseAsset(container, commitFcn)
            % browseAsset Select an asset path without reading or evaluating the file.
            [name, folder] = uigetfile({"*.*", "All files"}, "Select asset");
            if isequal(name, 0) || isequal(folder, 0)
                return
            end
            selected = fullfile(folder, name);
            original = container.UserData.Edit.Value;
            if ischar(original)
                commitFcn(char(selected));
            else
                commitFcn(string(selected));
            end
        end
    end
end

%{
Copyright (C) 2026 Nobuto Kaitoh

This file is part of MatlabAppClassDesigner.

MatlabAppClassDesigner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MatlabAppClassDesigner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MatlabAppClassDesigner. If not, see <https://www.gnu.org/licenses/>.
%}

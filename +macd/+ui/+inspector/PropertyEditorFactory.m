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
                "multilineText", "url", "asset", "structuredData", "dateTime"]);
            if definition.Editor == "enum" && ~isfield(definition.ValueSchema, "values")
                result = false;
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

            if isprop(control, "Tag") && control.Tag == "macd-inspector-date-picker-editor"
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

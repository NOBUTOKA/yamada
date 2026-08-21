classdef ColumnSettingsEditorDialog
    % ColumnSettingsEditorDialog Edit UITable column behavior as one atomic draft.
    %   The dialog derives its rows from the effective Data width and stages width,
    %   editability, sortability, display format, and rearrangeability together.

    methods (Static)
        function dialog = open(state, commitFcn, visible)
            % open Show the table-wide and per-column settings candidate editor.
            arguments (Input)
                state (1, 1) struct
                commitFcn (1, 1) function_handle
                visible (1, 1) logical = true
            end
            arguments (Output)
                dialog (1, 1) matlab.ui.Figure
            end

            initial = macd.ui.inspector.ColumnSettingsEditorDialog.initialState(state);
            columnCount = size(initial.Data, 2);
            names = macd.ui.inspector.ColumnSettingsEditorDialog.columnNames( ...
                initial.ColumnName, columnCount);
            widths = macd.ui.inspector.ColumnSettingsEditorDialog.widthValues( ...
                initial.ColumnWidth, columnCount);
            editable = macd.ui.inspector.ColumnSettingsEditorDialog.logicalValues( ...
                initial.ColumnEditable, columnCount);
            sortable = macd.ui.inspector.ColumnSettingsEditorDialog.logicalValues( ...
                initial.ColumnSortable, columnCount);
            formats = macd.ui.inspector.ColumnSettingsEditorDialog.formatValues( ...
                initial.ColumnFormat, columnCount);
            dialog = uifigure("Name", "Edit columns", "Position", [100 100 680 380], ...
                "WindowStyle", "modal", "Visible", ...
                macd.ui.inspector.ColumnSettingsEditorDialog.onOff(visible), ...
                "Tag", "macd-column-settings-dialog");
            grid = uigridlayout(dialog, [6 6], "Padding", [12 12 12 12], ...
                "RowHeight", {24, "1x", 24, 24, 24, 30}, ...
                "ColumnWidth", {"fit", "fit", "fit", "fit", "1x", "fit"}, ...
                "ColumnSpacing", 6);
            rearrange = uicheckbox(grid, "Text", "Allow column rearranging", ...
                "Value", macd.ui.inspector.ColumnSettingsEditorDialog.onOffValue( ...
                initial.ColumnRearrangeable), "Tag", "macd-column-settings-rearrangeable");
            rearrange.Layout.Row = 1;
            rearrange.Layout.Column = [1 6];
            data = macd.ui.inspector.ColumnSettingsEditorDialog.displayData( ...
                names, widths, editable, sortable, formats);
            table = uitable(grid, "Data", data, ...
                "ColumnName", {"Column", "Width", "Editable", "Sortable", "Format"}, ...
                "ColumnEditable", [false true true true true], ...
                "ColumnWidth", {100, 100, 70, 70, "1x"}, ...
                "Tag", "macd-column-settings-table");
            table.Layout.Row = 2;
            table.Layout.Column = [1 6];
            allOn = uibutton(grid, "Text", "All editable", "Tag", ...
                "macd-column-settings-all-editable", "ButtonPushedFcn", @(~, ~) setLogicalColumn(3, true));
            allOn.Layout.Row = 3;
            allOff = uibutton(grid, "Text", "None editable", "Tag", ...
                "macd-column-settings-no-editable", "ButtonPushedFcn", @(~, ~) setLogicalColumn(3, false));
            allOff.Layout.Row = 3;
            sortOn = uibutton(grid, "Text", "All sortable", "Tag", ...
                "macd-column-settings-all-sortable", "ButtonPushedFcn", @(~, ~) setLogicalColumn(4, true));
            sortOn.Layout.Row = 3;
            sortOff = uibutton(grid, "Text", "None sortable", "Tag", ...
                "macd-column-settings-no-sortable", "ButtonPushedFcn", @(~, ~) setLogicalColumn(4, false));
            sortOff.Layout.Row = 3;
            widthAuto = uibutton(grid, "Text", "All auto", "Tag", ...
                "macd-column-settings-all-auto", "ButtonPushedFcn", @(~, ~) setWidth("auto"));
            widthAuto.Layout.Row = 3;
            widthAuto.Layout.Column = 5;
            widthFit = uibutton(grid, "Text", "All fit", "Tag", ...
                "macd-column-settings-all-fit", "ButtonPushedFcn", @(~, ~) setWidth("fit"));
            widthFit.Layout.Row = 3;
            widthFit.Layout.Column = 6;
            widthOneX = uibutton(grid, "Text", "All 1x", "Tag", ...
                "macd-column-settings-all-1x", "ButtonPushedFcn", @(~, ~) setWidth("1x"));
            widthOneX.Layout.Row = 4;
            widthOneX.Layout.Column = [5 6];
            message = uilabel(grid, "Text", "Widths accept auto, fit, 1x, or nonnegative numeric literals.", ...
                "FontColor", [0.3 0.3 0.3]);
            message.Layout.Row = 5;
            message.Layout.Column = [1 6];
            clearButton = uibutton(grid, "Text", "Clear", "Tag", "macd-column-settings-clear", ...
                "ButtonPushedFcn", @(~, ~) clearDraft());
            clearButton.Layout.Row = 6;
            apply = uibutton(grid, "Text", "Apply", "Tag", "macd-column-settings-apply", ...
                "ButtonPushedFcn", @(~, ~) applyDraft());
            apply.Layout.Row = 6;
            apply.Layout.Column = [2 6];
            if columnCount == 0
                table.Enable = "off";
                allOn.Enable = "off";
                allOff.Enable = "off";
                sortOn.Enable = "off";
                sortOff.Enable = "off";
                widthAuto.Enable = "off";
                widthFit.Enable = "off";
                widthOneX.Enable = "off";
                message.Text = "Add columns through Data & Names before editing column settings.";
            end

            function setLogicalColumn(column, value)
                % setLogicalColumn Apply one all-column logical operation to the local table draft.
                if ~isempty(table.Data)
                    table.Data(:, column) = num2cell(repmat(logical(value), size(table.Data, 1), 1));
                end
            end

            function setWidth(value)
                % setWidth Apply one all-column documented width token to the local draft.
                if ~isempty(table.Data)
                    table.Data(:, 2) = repmat({char(value)}, size(table.Data, 1), 1);
                end
            end

            function clearDraft()
                % clearDraft Stage documented empty/default column values without mutation.
                if ~isempty(table.Data)
                    table.Data(:, 2) = repmat({'auto'}, size(table.Data, 1), 1);
                    table.Data(:, 3) = num2cell(false(size(table.Data, 1), 1));
                    table.Data(:, 4) = num2cell(false(size(table.Data, 1), 1));
                    table.Data(:, 5) = repmat({''}, size(table.Data, 1), 1);
                end
                rearrange.Value = false;
                message.Text = "Widths accept auto, fit, 1x, or nonnegative numeric literals.";
                message.FontColor = [0.3 0.3 0.3];
            end

            function applyDraft()
                % applyDraft Parse every column field and atomically submit only changed values.
                removeStyle(table);
                [width, row, messageText] = macd.ui.inspector.ColumnSettingsEditorDialog.parseWidths(table.Data(:, 2));
                if row > 0
                    markError(row, 2, messageText);
                    return
                end
                [format, row, messageText] = macd.ui.inspector.ColumnSettingsEditorDialog.parseFormats(table.Data(:, 5));
                if row > 0
                    markError(row, 5, messageText);
                    return
                end
                editableValue = logical(cell2mat(table.Data(:, 3))).';
                sortableValue = logical(cell2mat(table.Data(:, 4))).';
                transaction = macd.model.PropertyTransaction( ...
                    ["ColumnWidth", "ColumnEditable", "ColumnRearrangeable", "ColumnSortable", "ColumnFormat"], ...
                    {initial.ColumnWidth, initial.ColumnEditable, initial.ColumnRearrangeable, ...
                    initial.ColumnSortable, initial.ColumnFormat});
                width = macd.ui.inspector.ColumnSettingsEditorDialog.compactWidth(width, initial.ColumnWidth);
                format = macd.ui.inspector.ColumnSettingsEditorDialog.compactFormat(format, initial.ColumnFormat);
                if ~isequaln(width, initial.ColumnWidth), transaction.stage("ColumnWidth", width); end
                if ~isequaln(editableValue, initial.ColumnEditable), transaction.stage("ColumnEditable", editableValue); end
                if ~isequaln(sortableValue, initial.ColumnSortable), transaction.stage("ColumnSortable", sortableValue); end
                rearrangeValue = logical(rearrange.Value);
                if ~isequaln(rearrangeValue, initial.ColumnRearrangeable)
                    transaction.stage("ColumnRearrangeable", rearrangeValue);
                end
                if ~isequaln(format, initial.ColumnFormat), transaction.stage("ColumnFormat", format); end
                errorMessage = commitFcn(transaction.changes());
                if strlength(errorMessage) > 0
                    message.Text = errorMessage;
                    message.FontColor = [0.7 0 0];
                    return
                end
                if isvalid(dialog)
                    delete(dialog);
                end
            end

            function markError(row, column, text)
                % markError Highlight one invalid table cell and retain the draft.
                addStyle(table, uistyle("BackgroundColor", [1 0.9 0.9]), "cell", [row column]);
                message.Text = text;
                message.FontColor = [0.7 0 0];
            end
        end
    end

    methods (Static, Access = private)
        function state = initialState(state)
            % initialState Fill optional state fields with safe documented defaults.
            names = ["Data", "ColumnName", "ColumnWidth", "ColumnEditable", ...
                "ColumnRearrangeable", "ColumnSortable", "ColumnFormat"];
            defaults = {[], [], 'auto', false(1, 0), false, false(1, 0), cell(1, 0)};
            for index = 1:numel(names)
                if ~isfield(state, names(index))
                    state.(char(names(index))) = defaults{index};
                end
            end
        end

        function result = columnNames(value, count)
            % columnNames Return one stable display name per effective Data column.
            result = "Column " + string(1:count);
            if iscell(value)
                names = string(value(:)).';
            elseif isstring(value)
                names = value(:).';
            elseif ischar(value) && isrow(value) && ~strcmpi(value, "numbered")
                names = string({value});
            else
                names = strings(1, 0);
            end
            result(1:min(count, numel(names))) = names(1:min(count, numel(names)));
        end

        function result = widthValues(value, count)
            % widthValues Expand documented scalar or row-cell widths to visible columns.
            result = repmat({'auto'}, count, 1);
            if iscell(value)
                values = value(:);
            elseif ischar(value) || (isstring(value) && isscalar(value))
                values = {char(value)};
            elseif isstring(value)
                values = cellstr(value(:));
            else
                values = {};
            end
            for index = 1:min(count, numel(values))
                result{index} = macd.ui.inspector.TypedCellCodec.literalText(values{index});
            end
        end

        function result = logicalValues(value, count)
            % logicalValues Expand documented scalar or short logical settings to columns.
            result = false(count, 1);
            if isempty(value)
                return
            end
            values = logical(value(:));
            if isscalar(values)
                result(:) = values;
            else
                result(1:min(count, numel(values))) = values(1:min(count, numel(values)));
            end
        end

        function result = formatValues(value, count)
            % formatValues Expand per-column format cells to safely rendered text.
            result = repmat({''}, count, 1);
            if ~iscell(value)
                return
            end
            for index = 1:min(count, numel(value))
                result{index} = macd.ui.inspector.TypedCellCodec.literalText(value{index});
            end
        end

        function result = displayData(names, widths, editable, sortable, formats)
            % displayData Construct native UITable-compatible heterogeneous column cells.
            result = cell(numel(names), 5);
            for index = 1:numel(names)
                result(index, :) = {char(names(index)), char(string(widths{index})), ...
                    logical(editable(index)), logical(sortable(index)), ...
                    char(string(formats{index}))};
            end
        end

        function [values, errorRow, message] = parseWidths(text)
            % parseWidths Parse width tokens or nonnegative scalar MATLAB literals.
            values = cell(1, numel(text));
            errorRow = 0;
            message = "";
            for index = 1:numel(text)
                source = strtrim(string(text{index}));
                if any(lower(source) == ["auto", "fit", "1x"])
                    values{index} = char(lower(source));
                    continue
                end
                [value, isLiteral] = macd.source.MatlabLiteralParser.parse(source);
                if ~isLiteral || ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value < 0
                    errorRow = index;
                    message = "Enter auto, fit, 1x, or one nonnegative numeric width.";
                    return
                end
                values{index} = value;
            end
        end

        function [values, errorRow, message] = parseFormats(text)
            % parseFormats Parse documented char or char-cell format values without evaluation.
            values = cell(1, numel(text));
            errorRow = 0;
            message = "";
            for index = 1:numel(text)
                source = strtrim(string(text{index}));
                if strlength(source) == 0
                    values{index} = [];
                    continue
                end
                [value, isLiteral] = macd.source.MatlabLiteralParser.parse(source);
                if isLiteral && isstring(value) && isscalar(value)
                    value = char(value);
                end
                validCell = iscell(value) && all(cellfun(@(item) ischar(item) && isrow(item), value));
                if ~isLiteral || ~((ischar(value) && isrow(value)) || validCell)
                    errorRow = index;
                    message = "Enter a character format name or a cell array of character vectors.";
                    return
                end
                values{index} = value;
            end
        end

        function value = compactWidth(values, original)
            % compactWidth Preserve an unchanged representation or emit a documented row cell array.
            if isequaln(values, macd.ui.inspector.ColumnSettingsEditorDialog.widthValues(original, numel(values)))
                value = original;
            elseif isscalar(values) && ischar(values{1})
                value = values{1};
            else
                value = values;
            end
        end

        function value = compactFormat(values, original)
            % compactFormat Preserve an unchanged format representation or emit a row cell array.
            if isequaln(values, macd.ui.inspector.ColumnSettingsEditorDialog.formatValues(original, numel(values)))
                value = original;
            elseif all(cellfun(@isempty, values))
                value = cell(1, 0);
            else
                value = values;
            end
        end

        function result = onOffValue(value)
            % onOffValue Normalize char, string, or logical on/off values for a checkbox.
            result = islogical(value) && isscalar(value) && value;
            if ischar(value) || (isstring(value) && isscalar(value))
                result = lower(string(value)) == "on";
            end
        end

        function value = onOff(enabled)
            % onOff Convert a logical visibility flag to the native UI token.
            if enabled
                value = "on";
            else
                value = "off";
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

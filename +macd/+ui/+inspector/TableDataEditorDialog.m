classdef TableDataEditorDialog
    % TableDataEditorDialog Edit a supported UITable data draft and its visible headings.
    %   The dialog retains typed cell values and row/column names locally. It emits
    %   one property batch for Data, ColumnName, and RowName only after Apply.

    methods (Static)
        function dialog = open(state, commitFcn, visible)
            % open Create a table editor with row and column controls around one native UITable.
            arguments (Input)
                state (1, 1) struct
                commitFcn (1, 1) function_handle
                visible (1, 1) logical = true
            end
            arguments (Output)
                dialog (1, 1) matlab.ui.Figure
            end

            if ~isfield(state, "HasData") || ~state.HasData || ...
                    ~macd.ui.inspector.TableDataEditorDialog.supportsData(state.Data)
                error("macd:TableDataEditorDialog:UnsupportedData", ...
                    "Table data must be an empty, numeric, logical, string, or safe cell matrix.");
            end
            initialData = state.Data;
            initialColumnName = macd.ui.inspector.TableDataEditorDialog.stateValue( ...
                state, "ColumnName", []);
            initialRowName = macd.ui.inspector.TableDataEditorDialog.stateValue( ...
                state, "RowName", []);
            initialColumnLabels = macd.ui.inspector.TableDataEditorDialog.nameVector(initialColumnName);
            initialRowLabels = macd.ui.inspector.TableDataEditorDialog.nameVector(initialRowName);
            columnNumbered = macd.ui.inspector.TableDataEditorDialog.isNumberedName(initialColumnName);
            rowNumbered = macd.ui.inspector.TableDataEditorDialog.isNumberedName(initialRowName);
            draftText = macd.ui.inspector.TableDataEditorDialog.displayData(initialData);
            columnLabels = initialColumnLabels;
            rowLabels = initialRowLabels;
            initialLayoutPending = false;
            initialHostPosition = zeros(1, 4);
            transaction = macd.model.PropertyTransaction( ...
                ["Data", "ColumnName", "RowName"], ...
                {initialData, initialColumnName, initialRowName}, ...
                [true, isfield(state, "HasColumnName") && state.HasColumnName, ...
                isfield(state, "HasRowName") && state.HasRowName]);

            dialog = uifigure("Name", "Edit table data", "Visible", "off", ...
                "WindowStyle", "modal", "Position", [260 220 760 510], ...
                "Tag", "macd-inspector-table-data-dialog");
            dialog.CloseRequestFcn = @(~, ~) closeDialog();
            grid = uigridlayout(dialog, [4 1], "Padding", [12 12 12 12], ...
                "RowHeight", {"1x", 32, 23.3, 32}, "RowSpacing", 6);
            tableHost = uipanel(grid, "BorderType", "line", "Scrollable", "on", ...
                "AutoResizeChildren", "off", "Tag", "macd-table-data-scroll-host");
            tableContent = uipanel(tableHost, "BorderType", "none", "AutoResizeChildren", "off", ...
                "Tag", "macd-table-data-scroll-content");
            table = uitable(tableContent, "ColumnEditable", true, "RowStriping", "off", ...
                "Tag", "macd-table-data-editor-table");
            rowActions = uipanel(tableContent, "BorderType", "none", ...
                "Tag", "macd-table-data-row-actions");
            columnActions = uipanel(tableContent, "BorderType", "none", ...
                "Tag", "macd-table-data-column-actions");
            structuralActions = uigridlayout(grid, [1 2], "Padding", [0 0 0 0], ...
                "ColumnWidth", {"1x", "1x"}, "ColumnSpacing", 6);
            structuralActions.Layout.Row = 2;
            rowNumberedButton = uibutton(structuralActions, "state", "Text", "Numbered rows", ...
                "Tag", "macd-table-data-numbered-rows", ...
                "ValueChangedFcn", @(source, ~) setRowNumbered(source.Value));
            rowNumberedButton.Value = rowNumbered;
            columnNumberedButton = uibutton(structuralActions, "state", "Text", "Numbered columns", ...
                "Tag", "macd-table-data-numbered-columns", ...
                "ValueChangedFcn", @(source, ~) setColumnNumbered(source.Value));
            columnNumberedButton.Value = columnNumbered;
            message = uilabel(grid, "Text", ...
                "Enter MATLAB literals; unquoted text becomes a string.", ...
                "FontColor", [0.3 0.3 0.3], "Tag", "macd-table-data-message");
            message.Layout.Row = 3;
            actions = uigridlayout(grid, [1 2], "Padding", [0 0 0 0], ...
                "ColumnWidth", {90, "1x"}, "ColumnSpacing", 6);
            actions.Layout.Row = 4;
            uibutton(actions, "Text", "Clear", "Tag", "macd-table-data-clear", ...
                "ButtonPushedFcn", @(~, ~) clearDraft());
            uibutton(actions, "Text", "Apply", "Tag", "macd-table-data-apply", ...
                "ButtonPushedFcn", @(~, ~) applyDraft());
            rebuildChrome();
            if visible
                initialLayoutPending = true;
                initialHostPosition = getpixelposition(tableHost, true);
                tableHost.SizeChangedFcn = @(~, ~) finishInitialLayout();
                dialog.Visible = "on";
            end

            function rebuildChrome()
                % rebuildChrome Rebuild nearby structural controls around the editable table grid.
                delete(rowActions.Children);
                delete(columnActions.Children);
                macd.ui.inspector.TableDataEditorDialog.createRowActions( ...
                    rowActions, size(draftText, 1), @(~, ~) addRow(), ...
                    @(source) deleteRow(source.UserData));
                macd.ui.inspector.TableDataEditorDialog.createColumnActions( ...
                    columnActions, size(draftText, 2), @(~, ~) addColumn(), ...
                    @(source) deleteColumn(source.UserData));
                table.Data = macd.ui.inspector.TableDataEditorDialog.editorMatrix( ...
                    draftText, rowLabels, columnLabels, rowNumbered, columnNumbered);
                table.ColumnName = [];
                table.RowName = [];
                table.ColumnWidth = macd.ui.inspector.TableDataEditorDialog.editorColumnWidths( ...
                    size(table.Data, 2));
                removeStyle(table);
                macd.ui.inspector.TableDataEditorDialog.styleNameCells(table, ...
                    size(draftText, 1), size(draftText, 2));
                layoutTableSurface();
            end

            function layoutTableSurface()
                % layoutTableSurface Size one scrollable canvas so every table action scrolls with its cell.
                padding = 4;
                rowActionWidth = 32;
                columnActionHeight = 23.3;
                rowCount = max(size(table.Data, 1), 1);
                columnCount = max(size(table.Data, 2), 1);
                tableSafetyMargin = 4;
                actionHeight = macd.ui.inspector.TableDataEditorDialog.editorPixelHeight(rowCount);
                tableWidth = macd.ui.inspector.TableDataEditorDialog.editorPixelWidth(columnCount) + ...
                    tableSafetyMargin;
                tableHeight = actionHeight + tableSafetyMargin;
                hostPosition = getpixelposition(tableHost, true);
                naturalWidth = tableWidth + rowActionWidth + 2 * padding;
                naturalHeight = tableHeight + columnActionHeight + 2 * padding;
                [contentWidth, contentHeight] = ...
                    macd.ui.inspector.TableDataEditorDialog.scrollContentExtent( ...
                    naturalWidth, naturalHeight, hostPosition(3), hostPosition(4));
                tableContent.Position = [1 1 contentWidth contentHeight];
                tableY = contentHeight - padding - columnActionHeight - tableHeight;
                tableX = padding + rowActionWidth;
                table.Position = [tableX tableY tableWidth tableHeight];
                rowActions.Position = [padding tableY + tableSafetyMargin rowActionWidth actionHeight];
                columnActions.Position = [tableX tableY + tableHeight tableWidth columnActionHeight];
            end

            function finishInitialLayout()
                % finishInitialLayout Relayout once after the visible dialog resolves its real grid extent.
                if ~initialLayoutPending || ~isvalid(tableHost)
                    return
                end
                if isequal(getpixelposition(tableHost, true), initialHostPosition)
                    return
                end
                initialLayoutPending = false;
                tableHost.SizeChangedFcn = [];
                layoutTableSurface();
            end

            function addRow()
                % addRow Append one empty data row, creating the first column when needed.
                if ~captureTableData()
                    return
                end
                if size(draftText, 2) == 0
                    draftText = strings(0, 1);
                end
                draftText(end + 1, 1:size(draftText, 2)) = "";
                if ~isempty(rowLabels)
                    rowLabels = macd.ui.inspector.TableDataEditorDialog.extendName( ...
                        rowLabels, size(draftText, 1), "Row");
                end
                rebuildChrome();
            end

            function deleteRow(index)
                % deleteRow Remove one data row and its matching editable row-name entry.
                if ~captureTableData()
                    return
                end
                draftText(index, :) = [];
                if index <= numel(rowLabels)
                    rowLabels(index) = [];
                end
                rebuildChrome();
            end

            function addColumn()
                % addColumn Append one empty data column and a matching name when headings exist.
                if ~captureTableData()
                    return
                end
                draftText(:, end + 1) = "";
                if ~isempty(columnLabels)
                    columnLabels = macd.ui.inspector.TableDataEditorDialog.extendName( ...
                        columnLabels, size(draftText, 2), "Column");
                end
                rebuildChrome();
            end

            function deleteColumn(index)
                % deleteColumn Remove one data column and its matching editable column-name entry.
                if ~captureTableData()
                    return
                end
                draftText(:, index) = [];
                if index <= numel(columnLabels)
                    columnLabels(index) = [];
                end
                rebuildChrome();
            end

            function clearDraft()
                % clearDraft Stage no document mutation while resetting all local table surfaces.
                draftText = strings(0, 0);
                columnLabels = strings(0, 1);
                rowLabels = strings(0, 1);
                columnNumbered = false;
                rowNumbered = false;
                columnNumberedButton.Value = false;
                rowNumberedButton.Value = false;
                removeStyle(table);
                setMessage("Enter MATLAB literals; unquoted text becomes a string.", [0.3 0.3 0.3]);
                rebuildChrome();
            end

            function result = captureTableData()
                % captureTableData Validate displayed cells before retaining a structural edit.
                result = false;
                removeStyle(table);
                [draftText, rowLabels, columnLabels, rowNumbered, columnNumbered] = ...
                    macd.ui.inspector.TableDataEditorDialog.editorValues( ...
                    string(table.Data), size(draftText, 1), size(draftText, 2), ...
                    rowNumbered, columnNumbered);
                rowNumberedButton.Value = rowNumbered;
                columnNumberedButton.Value = columnNumbered;
                removeStyle(table);
                macd.ui.inspector.TableDataEditorDialog.styleNameCells(table, ...
                    size(draftText, 1), size(draftText, 2));
                [values, errorRow, errorColumn, errorMessage] = ...
                    macd.ui.inspector.TypedCellCodec.parse(draftText, true);
                if errorRow > 0
                    macd.ui.inspector.TableDataEditorDialog.markCellError( ...
                        table, errorRow, errorColumn, errorMessage, message);
                    return
                end
                if ~macd.ui.inspector.TableDataEditorDialog.supportsCells(values)
                    setMessage("Table cells must be empty, scalar numeric, logical, string, or char values.", ...
                        [0.7 0 0]);
                    return
                end
                result = true;
            end

            function applyDraft()
                % applyDraft Parse, type-pack, and atomically submit every changed table surface.
                if ~captureTableData()
                    return
                end
                [values, errorRow, errorColumn, errorMessage] = ...
                    macd.ui.inspector.TypedCellCodec.parse(draftText, true);
                if errorRow > 0
                    macd.ui.inspector.TableDataEditorDialog.markCellError( ...
                        table, errorRow, errorColumn, errorMessage, message);
                    return
                end
                if ~macd.ui.inspector.TableDataEditorDialog.supportsCells(values)
                    setMessage("Table cells must be empty, scalar numeric, logical, string, or char values.", ...
                        [0.7 0 0]);
                    return
                end
                data = macd.ui.inspector.TypedCellCodec.packMatrix(values);
                columnName = macd.ui.inspector.TableDataEditorDialog.nameOutput( ...
                    columnLabels, initialColumnLabels, initialColumnName, columnNumbered);
                rowName = macd.ui.inspector.TableDataEditorDialog.nameOutput( ...
                    rowLabels, initialRowLabels, initialRowName, rowNumbered);
                if ~isequaln(data, initialData)
                    transaction.stage("Data", data);
                end
                if ~isequaln(columnName, initialColumnName)
                    transaction.stage("ColumnName", columnName);
                end
                if ~isequaln(rowName, initialRowName)
                    transaction.stage("RowName", rowName);
                end
                changes = transaction.changes();
                if isempty(changes)
                    closeDialog();
                    return
                end
                errorMessage = commitFcn(changes);
                if strlength(errorMessage) > 0
                    setMessage(errorMessage, [0.7 0 0]);
                    return
                end
                closeDialog();
            end

            function setRowNumbered(value)
                % setRowNumbered Switch the row-name representation without changing the document yet.
                rowNumbered = value;
                if rowNumbered
                    rowLabels = strings(0, 1);
                elseif isempty(rowLabels)
                    rowLabels = macd.ui.inspector.TableDataEditorDialog.numberedNames( ...
                        "Row", size(draftText, 1));
                end
                rebuildChrome();
            end

            function setColumnNumbered(value)
                % setColumnNumbered Switch the column-name representation without changing the document yet.
                columnNumbered = value;
                if columnNumbered
                    columnLabels = strings(0, 1);
                elseif isempty(columnLabels)
                    columnLabels = macd.ui.inspector.TableDataEditorDialog.numberedNames( ...
                        "Column", size(draftText, 2));
                end
                rebuildChrome();
            end

            function setMessage(text, color)
                % setMessage Present one local validation result without changing the model.
                message.Text = text;
                message.FontColor = color;
            end

            function closeDialog()
                % closeDialog Dispose the modal editor without applying uncommitted draft values.
                if isvalid(dialog)
                    delete(dialog);
                end
            end
        end

        function result = supportsData(value)
            % supportsData Report whether one table Data value has a finite editable matrix representation.
            arguments (Input)
                value
            end
            arguments (Output)
                result (1, 1) logical
            end

            if isempty(value)
                result = true;
                return
            end
            if ~(isnumeric(value) || islogical(value) || isstring(value) || iscell(value)) || ...
                    ~ismatrix(value)
                result = false;
                return
            end
            if iscell(value)
                result = macd.ui.inspector.TableDataEditorDialog.supportsCells(value);
            else
                result = true;
            end
        end

        function text = summary(value)
            % summary Render one supported table value without flattening its shape or type.
            arguments (Input)
                value
            end
            arguments (Output)
                text (1, 1) string
            end

            if macd.ui.inspector.TableDataEditorDialog.supportsData(value)
                text = sprintf("%d-by-%d table", size(value, 1), size(value, 2));
            else
                text = "Unsupported table data";
            end
        end
    end

    methods (Static, Access = private)
        function value = stateValue(state, name, fallback)
            % stateValue Read one optional table state value without requiring a default provider entry.
            if isfield(state, name)
                value = state.(name);
            else
                value = fallback;
            end
        end

        function result = supportsCells(values)
            % supportsCells Limit editable cells to finite scalar literal forms.
            if ~iscell(values)
                values = num2cell(values);
            end
            result = all(cellfun(@macd.ui.inspector.TableDataEditorDialog.isSupportedCell, values), "all");
        end

        function result = isSupportedCell(value)
            % isSupportedCell Check one parsed literal cell before type-preserving packing.
            result = isempty(value) || (isnumeric(value) && isscalar(value)) || ...
                (islogical(value) && isscalar(value)) || (isstring(value) && isscalar(value)) || ...
                (ischar(value) && isrow(value));
        end

        function data = displayData(value)
            % displayData Convert supported typed Data into a string matrix accepted by native UITable.
            if isempty(value)
                data = strings(size(value));
                return
            end
            if iscell(value)
                values = value;
            else
                values = num2cell(value);
            end
            data = strings(size(values));
            for index = 1:numel(values)
                data(index) = macd.ui.inspector.TypedCellCodec.literalText(values{index});
            end
        end

        function labels = nameVector(value)
            % nameVector Normalize documented heading forms without expanding the numbered marker.
            if isempty(value)
                labels = strings(0, 1);
            elseif (ischar(value) && isrow(value) && strcmpi(value, "numbered")) || ...
                    (isstring(value) && isscalar(value) && lower(value) == "numbered")
                labels = strings(0, 1);
            elseif iscell(value)
                labels = string(value(:));
            elseif ischar(value) && isrow(value)
                labels = string({value});
            else
                labels = string(value(:));
            end
        end

        function createRowActions(parent, rowCount, addFcn, deleteFcn)
            % createRowActions Align the row add and delete actions beside the table's visible rows.
            rowHeights = repmat({23.3}, 1, rowCount + 1);
            grid = uigridlayout(parent, [rowCount + 1 1], "Padding", [0 0 0 0], ...
                "RowSpacing", 0, "RowHeight", rowHeights);
            uibutton(grid, "Text", "+", "FontSize", 14, "FontWeight", "bold", ...
                "FontColor", [0 0.55 0], "Tag", "macd-table-data-add-row", ...
                "ButtonPushedFcn", addFcn);
            for index = 1:rowCount
                button = uibutton(grid, "Text", "−", "FontSize", 14, "FontWeight", "bold", ...
                    "FontColor", [0.8 0 0], "Tag", "macd-table-data-delete-row", ...
                    "ButtonPushedFcn", @(source, ~) deleteFcn(source));
                button.UserData = index;
            end
        end

        function createColumnActions(parent, columnCount, addFcn, deleteFcn)
            % createColumnActions Align the column add and delete actions above the table's visible columns.
            grid = uigridlayout(parent, [1 columnCount + 1], "Padding", [0 0 0 0], ...
                "ColumnSpacing", 0, "ColumnWidth", ...
                macd.ui.inspector.TableDataEditorDialog.editorColumnWidths(columnCount + 1));
            uibutton(grid, "Text", "+", "FontSize", 14, "FontWeight", "bold", ...
                "FontColor", [0 0.55 0], "Tag", "macd-table-data-add-column", ...
                "ButtonPushedFcn", addFcn);
            for index = 1:columnCount
                button = uibutton(grid, "Text", "−", "FontSize", 14, "FontWeight", "bold", ...
                    "FontColor", [0.8 0 0], "Tag", "macd-table-data-delete-column", ...
                    "ButtonPushedFcn", @(source, ~) deleteFcn(source));
                button.UserData = index;
            end
        end

        function labels = extendName(labels, count, prefix)
            % extendName Append conventional names while retaining unmatched imported heading entries.
            while numel(labels) < count
                labels(end + 1, 1) = prefix + " " + string(numel(labels) + 1); %#ok<AGROW>
            end
        end

        function value = editorMatrix(data, rowLabels, columnLabels, rowNumbered, columnNumbered)
            % editorMatrix Place editable names in the first row and first column of the native table.
            rowCount = max(size(data, 1), numel(rowLabels));
            columnCount = max(size(data, 2), numel(columnLabels));
            value = strings(rowCount + 1, columnCount + 1);
            if columnNumbered
                value(1, 2:end) = reshape( ...
                    macd.ui.inspector.TableDataEditorDialog.numberedNames("Column", columnCount), 1, []);
            elseif ~isempty(columnLabels)
                value(1, 2:numel(columnLabels) + 1) = reshape(columnLabels, 1, []);
            end
            if rowNumbered
                value(2:end, 1) = macd.ui.inspector.TableDataEditorDialog.numberedNames("Row", rowCount);
            elseif ~isempty(rowLabels)
                value(2:numel(rowLabels) + 1, 1) = reshape(rowLabels, [], 1);
            end
            if ~isempty(data)
                value(2:size(data, 1) + 1, 2:size(data, 2) + 1) = data;
            end
        end

        function [data, rowLabels, columnLabels, rowNumbered, columnNumbered] = editorValues( ...
                value, dataRows, dataColumns, rowNumbered, columnNumbered)
            % editorValues Split native-table name cells from the editable data body.
            displayedRows = reshape(value(2:end, 1), [], 1);
            displayedColumns = reshape(value(1, 2:end), [], 1);
            if rowNumbered && isequal(displayedRows, ...
                    macd.ui.inspector.TableDataEditorDialog.numberedNames("Row", numel(displayedRows)))
                rowLabels = strings(0, 1);
            else
                rowNumbered = false;
                rowLabels = macd.ui.inspector.TableDataEditorDialog.trimTrailingEmptyNames(displayedRows);
            end
            if columnNumbered && isequal(displayedColumns, ...
                    macd.ui.inspector.TableDataEditorDialog.numberedNames("Column", numel(displayedColumns)))
                columnLabels = strings(0, 1);
            else
                columnNumbered = false;
                columnLabels = macd.ui.inspector.TableDataEditorDialog.trimTrailingEmptyNames(displayedColumns);
            end
            data = value(2:dataRows + 1, 2:dataColumns + 1);
        end

        function result = isNumberedName(value)
            % isNumberedName Identify the documented special marker without accepting partial labels.
            result = (ischar(value) && isrow(value) && strcmpi(value, "numbered")) || ...
                (isstring(value) && isscalar(value) && lower(value) == "numbered");
        end

        function names = numberedNames(prefix, count)
            % numberedNames Create the native UITable visible labels for the numbered name mode.
            names = strings(count, 1);
            for index = 1:count
                names(index) = prefix + " " + string(index);
            end
        end

        function labels = trimTrailingEmptyNames(labels)
            % trimTrailingEmptyNames Remove unused trailing name cells while retaining intentional gaps.
            last = find(strlength(labels) > 0, 1, "last");
            if isempty(last)
                labels = strings(0, 1);
            else
                labels = labels(1:last);
            end
        end

        function widths = editorColumnWidths(count)
            % editorColumnWidths Keep header-name and data columns aligned with the column delete controls.
            widths = repmat({110}, 1, count);
            if count > 0
                widths{1} = 120;
            end
        end

        function value = editorPixelWidth(columnCount)
            % editorPixelWidth Return the pixel width required to show every native table column.
            value = sum(cell2mat(macd.ui.inspector.TableDataEditorDialog.editorColumnWidths(columnCount)));
        end

        function value = editorPixelHeight(rowCount)
            % editorPixelHeight Return the native table extent for all displayed cells at the shared action height.
            value = 23.3 * rowCount;
        end

        function [width, height] = scrollContentExtent(naturalWidth, naturalHeight, hostWidth, hostHeight)
            % scrollContentExtent Fill the viewport without manufacturing scrollable slack around a small table.
            borderWidth = 2;
            scrollbarWidth = 18;
            viewportSafetyMargin = 4;
            viewportWidth = max(hostWidth - borderWidth - viewportSafetyMargin, 1);
            viewportHeight = max(hostHeight - borderWidth - viewportSafetyMargin, 1);
            needsVertical = naturalHeight > viewportHeight;
            needsHorizontal = naturalWidth > viewportWidth - scrollbarWidth * needsVertical;
            if needsHorizontal && naturalHeight > viewportHeight - scrollbarWidth
                needsVertical = true;
            end
            if needsVertical && naturalWidth > viewportWidth - scrollbarWidth
                needsHorizontal = true;
            end
            width = max(naturalWidth, viewportWidth - scrollbarWidth * needsVertical);
            height = max(naturalHeight, viewportHeight - scrollbarWidth * needsHorizontal);
        end

        function styleNameCells(table, dataRows, dataColumns)
            % styleNameCells Distinguish editable heading cells from literal data with a pale gray background.
            nameStyle = uistyle("BackgroundColor", [0.88 0.88 0.88]);
            addStyle(table, nameStyle, "row", 1);
            addStyle(table, nameStyle, "column", 1);
            if dataRows == 0 && dataColumns == 0
                addStyle(table, nameStyle, "cell", [1 1]);
            end
        end

        function value = nameOutput(labels, initialLabels, initialValue, numbered)
            % nameOutput Preserve untouched source representation or emit editable headings as row char cells.
            if numbered
                value = 'numbered';
            elseif isequal(labels, initialLabels)
                value = initialValue;
            elseif isempty(labels)
                value = [];
            else
                value = cellstr(reshape(labels, 1, []));
            end
        end

        function markCellError(table, row, column, errorMessage, messageLabel)
            % markCellError Highlight one malformed table cell without replacing its user draft.
            errorStyle = uistyle("BackgroundColor", [1 0.9 0.9]);
            addStyle(table, errorStyle, "cell", [row column]);
            messageLabel.Text = errorMessage;
            messageLabel.FontColor = [0.7 0 0];
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

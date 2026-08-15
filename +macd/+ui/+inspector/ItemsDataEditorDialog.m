classdef ItemsDataEditorDialog
    % ItemsDataEditorDialog Edit data paired one-to-one with an Items list.
    %   The dialog displays immutable item labels beside editable associated
    %   values as typed literal text and commits a matching typed row or an empty array.

    methods (Static)
        function open(items, initialData, commitFcn)
            % open Show a paired Items and ItemsData editor.
            arguments (Input)
                items
                initialData
                commitFcn (1, 1) function_handle
            end

            labels = macd.ui.inspector.ItemsDataEditorDialog.itemLabels(items);
            data = macd.ui.inspector.ItemsDataEditorDialog.tableData(labels, initialData);
            dialog = uifigure("Name", "Edit item data", "Position", [100 100 520 330], ...
                "WindowStyle", "modal");
            grid = uigridlayout(dialog, [3 2], "Padding", [12 12 12 12], ...
                "RowHeight", {"1x", 24, 30}, "ColumnWidth", {90, "1x"});
            table = uitable(grid, "Data", data, "ColumnName", {"Items", "ItemsData"}, ...
                "ColumnEditable", [false true], "Tag", "macd-items-data-editor-table");
            table.Layout.Row = 1;
            table.Layout.Column = [1 2];
            message = uilabel(grid, "Text", "Enter literals such as 1, ""Text"", or 'Text'.", ...
                "FontColor", [0.3 0.3 0.3]);
            message.Layout.Row = 2;
            message.Layout.Column = [1 2];
            uibutton(grid, "Text", "Clear", "ButtonPushedFcn", @(~, ~) clearData());
            uibutton(grid, "Text", "Apply", "ButtonPushedFcn", @(~, ~) applyData());
            uiwait(dialog);

            function clearData()
                close(dialog);
                commitFcn([]);
            end

            function applyData()
                try
                    value = macd.ui.inspector.ItemsDataEditorDialog.commitValue(table.Data);
                catch exception
                    message.Text = string(exception.message);
                    message.FontColor = [0.7 0 0];
                    return
                end
                close(dialog);
                commitFcn(value);
            end
        end
    end

    methods (Static, Access = private)
        function labels = itemLabels(items)
            % itemLabels Normalize supported item labels into display-only table text.
            if isstring(items)
                labels = string(items(:));
            elseif iscell(items)
                labels = string(cellfun(@string, items(:), "UniformOutput", false));
            elseif ischar(items)
                labels = string({items});
            else
                error("macd:ItemsDataEditorDialog:UnsupportedItems", ...
                    "Items must be text before editing ItemsData.");
            end
        end

        function data = tableData(labels, value)
            % tableData Construct a string matrix so UITable accepts typed literal text.
            data = strings(numel(labels), 2);
            data(:, 1) = labels;
            if isempty(value)
                return
            end
            if ~isvector(value) || numel(value) ~= numel(labels)
                error("macd:ItemsDataEditorDialog:LengthMismatch", ...
                    "ItemsData must be empty or have one value for every item.");
            end
            for index = 1:numel(labels)
                if iscell(value)
                    item = value{index};
                else
                    item = value(index);
                end
                data(index, 2) = macd.ui.inspector.ItemsDataEditorDialog.literalText(item);
            end
        end

        function value = commitValue(data)
            % commitValue Preserve homogeneous numeric/logical rows or heterogeneous cell rows.
            source = string(data(:, 2))';
            values = cell(1, numel(source));
            for index = 1:numel(source)
                if strlength(strtrim(source(index))) == 0
                    values{index} = [];
                    continue
                end
                [item, isLiteral] = macd.source.MatlabLiteralParser.parse(source(index));
                if ~isLiteral
                    error("macd:ItemsDataEditorDialog:InvalidLiteral", ...
                        "ItemsData row %d must be a supported MATLAB literal.", index);
                end
                values{index} = item;
            end
            if all(cellfun(@(item) isnumeric(item) && isscalar(item), values))
                value = cell2mat(values);
            elseif all(cellfun(@(item) islogical(item) && isscalar(item), values))
                value = logical(cell2mat(values));
            elseif all(cellfun(@(item) isstring(item) && isscalar(item), values))
                value = string([values{:}]);
            else
                value = values;
            end
        end

        function text = literalText(value)
            % literalText Display each associated value using a safe typed MATLAB literal.
            try
                text = macd.source.LiteralEncoder.encode(value);
            catch
                text = "<unsupported>";
            end
        end
    end
end

%{
Copyright (C) 2026 Nobuto Kaitoh

This file is part of MatlabAppClassDesigner.

MatlabAppClassDesigner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by the
Free Software Foundation, either version 3 of the License, or (at your option)
any later version.

MatlabAppClassDesigner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MatlabAppClassDesigner. If not, see <https://www.gnu.org/licenses/>.
%}

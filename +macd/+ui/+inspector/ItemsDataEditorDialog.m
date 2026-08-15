classdef ItemsDataEditorDialog
    % ItemsDataEditorDialog Edit data paired one-to-one with an Items list.
    %   The dialog displays immutable item labels beside editable associated
    %   values and commits either a matching numeric/cell row or an empty array.

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
                "RowHeight", {"1x", 24, 30}, "ColumnWidth", {"1x", 90});
            table = uitable(grid, "Data", data, "ColumnName", {"Items", "ItemsData"}, ...
                "ColumnEditable", [false true], "Tag", "macd-items-data-editor-table");
            table.Layout.Row = 1;
            table.Layout.Column = [1 2];
            message = uilabel(grid, "Text", "", "FontColor", [0.7 0 0]);
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
            % tableData Construct two columns without coercing existing data types.
            data = cell(numel(labels), 2);
            data(:, 1) = cellstr(labels);
            if isempty(value)
                return
            end
            if ~isvector(value) || numel(value) ~= numel(labels)
                error("macd:ItemsDataEditorDialog:LengthMismatch", ...
                    "ItemsData must be empty or have one value for every item.");
            end
            for index = 1:numel(labels)
                if iscell(value)
                    data{index, 2} = value{index};
                else
                    data{index, 2} = value(index);
                end
            end
        end

        function value = commitValue(data)
            % commitValue Preserve homogeneous numeric/logical rows or heterogeneous cell rows.
            values = data(:, 2)';
            if all(cellfun(@(item) isnumeric(item) && isscalar(item), values))
                value = cell2mat(values);
            elseif all(cellfun(@(item) islogical(item) && isscalar(item), values))
                value = logical(cell2mat(values));
            else
                value = values;
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

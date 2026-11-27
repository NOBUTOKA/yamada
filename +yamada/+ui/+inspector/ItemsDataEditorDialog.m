classdef ItemsDataEditorDialog < yamada.ui.inspector.PropertyEditDialog
    % ItemsDataEditorDialog Edit data paired one-to-one with an Items list.
    %   The "data" kind displays immutable item labels beside editable associated
    %   values as typed literal text and stages a matching typed row or an empty
    %   array. The "paired" kind edits Items and ItemsData together as one
    %   candidate. PropertyEditDialog owns Apply, Cancel, and the commit.
    %
    %   Example:
    %       editor = yamada.ui.inspector.ItemsDataEditorDialog("paired", state);
    %       dialog = yamada.ui.inspector.PropertyEditDialog.show(editor, commitFcn);

    properties (Access = private)
        % Kind - "data" for ItemsData beside fixed Items, or "paired" for both.
        Kind string = "data"
        % State - Items, ItemsData, and for the data kind the target Path.
        State struct = struct()
        % Table - Native table holding the draft rows.
        Table matlab.ui.control.Table = matlab.ui.control.Table.empty
        % Message - Hint and validation message line.
        Message matlab.ui.control.Label = matlab.ui.control.Label.empty
        % Cleared - Whether Clear staged an empty ItemsData in the data kind.
        Cleared logical = false
    end

    methods
        function obj = ItemsDataEditorDialog(kind, state)
            % ItemsDataEditorDialog Prepare an Items/ItemsData draft of the given kind.
            %   state has Items and ItemsData fields, and a Path field for the data kind.
            arguments (Input)
                kind (1, 1) string {mustBeMember(kind, ["data", "paired"])}
                state (1, 1) struct
            end
            arguments (Output)
                obj (1, 1) yamada.ui.inspector.ItemsDataEditorDialog
            end

            if kind == "data"
                spec = struct("Name", "Edit item data", "Tag", "yamada-items-data-editor-dialog", ...
                    "Position", [100 100 520 330], "ContentHeight", "1x", ...
                    "AlertTitle", "Invalid item data", "ApplyTag", "yamada-items-data-editor-apply", ...
                    "CancelTag", "yamada-items-data-editor-cancel");
                transaction = yamada.model.PropertyTransaction(state.Path, {state.ItemsData});
            else
                spec = struct("Name", "Edit items", "Tag", "yamada-items-editor-dialog", ...
                    "Position", [100 100 520 360], "ContentHeight", "1x", ...
                    "AlertTitle", "Invalid items", "ApplyTag", "yamada-items-editor-apply", ...
                    "CancelTag", "yamada-items-editor-cancel");
                transaction = yamada.model.PropertyTransaction(["Items", "ItemsData"], ...
                    {state.Items, state.ItemsData});
            end
            obj@yamada.ui.inspector.PropertyEditDialog(spec, transaction);
            obj.Kind = kind;
            obj.State = state;
        end
    end

    methods (Access = protected)
        function buildContent(obj, content)
            % buildContent Create the paired table, the paired kind's row actions, and the message line.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.ItemsDataEditorDialog
                content (1, 1) matlab.ui.container.GridLayout
            end

            labels = yamada.ui.inspector.ItemsDataEditorDialog.itemLabels(obj.State.Items);
            data = yamada.ui.inspector.ItemsDataEditorDialog.tableData(labels, obj.State.ItemsData);
            if obj.Kind == "data"
                % Item labels are fixed; only their associated data is editable.
                grid = uigridlayout(content, [2 1], "Padding", [0 0 0 0], "RowHeight", {"1x", 24});
                obj.Table = uitable(grid, "Data", data, "ColumnName", {"Items", "ItemsData"}, ...
                    "ColumnEditable", [false true], "Tag", "yamada-items-data-editor-table");
                obj.Message = uilabel(grid, "Text", obj.hint(), "FontColor", [0.3 0.3 0.3]);
                return
            end

            % Both columns are editable, with row actions beside the message line.
            grid = uigridlayout(content, [2 3], "Padding", [0 0 0 0], ...
                "RowHeight", {"1x", 24}, "ColumnWidth", {70, 70, "1x"}, "ColumnSpacing", 6);
            obj.Table = uitable(grid, "Data", data, "ColumnName", {"Items", "ItemsData"}, ...
                "ColumnEditable", [true true], "Tag", "yamada-items-editor-table");
            obj.Table.Layout.Row = 1;
            obj.Table.Layout.Column = [1 3];
            add = uibutton(grid, "Text", "+", "FontSize", 14, "FontWeight", "bold", ...
                "FontColor", [0 0.55 0], "Tag", "yamada-items-editor-add", ...
                "ButtonPushedFcn", @(~, ~) obj.addRow());
            add.Layout.Row = 2;
            remove = uibutton(grid, "Text", "−", "FontSize", 14, "FontWeight", "bold", ...
                "FontColor", [0.8 0 0], "Tag", "yamada-items-editor-remove", ...
                "ButtonPushedFcn", @(~, ~) obj.removeRow());
            remove.Layout.Row = 2;
            obj.Message = uilabel(grid, "Text", obj.hint(), "FontColor", [0.3 0.3 0.3]);
            obj.Message.Layout.Row = 2;
            obj.Message.Layout.Column = 3;
        end

        function actions = editorActions(obj)
            % editorActions Offer Clear beside the shared Cancel and Apply.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.ItemsDataEditorDialog
            end
            arguments (Output)
                actions struct
            end

            tag = "yamada-items-data-editor-clear";
            if obj.Kind == "paired", tag = "yamada-items-editor-clear"; end
            actions = struct("Text", "Clear", "Tag", tag, "Callback", @(~, ~) obj.clearDraft());
        end

        function [transaction, message] = read(obj, transaction)
            % read Parse the data column and stage the changed properties, or mark the invalid cell.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.ItemsDataEditorDialog
                transaction (1, 1) yamada.model.PropertyTransaction
            end
            arguments (Output)
                transaction (1, 1) yamada.model.PropertyTransaction
                message (1, 1) string
            end

            % Reject the first cell that is not a supported literal.
            removeStyle(obj.Table);
            [values, errorRow, errorColumn, message] = ...
                yamada.ui.inspector.TypedCellCodec.parse(obj.Table.Data(:, 2), true);
            if errorRow > 0
                addStyle(obj.Table, uistyle("BackgroundColor", [1 0.9 0.9]), ...
                    "cell", [errorRow errorColumn + 1]);
                return
            end
            message = "";
            if isempty(values) || all(cellfun(@isempty, values))
                itemData = [];
            else
                itemData = yamada.ui.inspector.TypedCellCodec.packVector(values);
            end

            % Stage only the properties the draft changed.
            if obj.Kind == "data"
                if obj.Cleared || ~isequaln(itemData, obj.State.ItemsData)
                    transaction = transaction.stage(obj.State.Path, itemData);
                end
                return
            end
            items = yamada.ui.inspector.ItemsDataEditorDialog.itemOutput( ...
                string(obj.Table.Data(:, 1)), obj.State.Items);
            if ~isequaln(items, obj.State.Items)
                transaction = transaction.stage("Items", items);
            end
            if ~isequaln(itemData, obj.State.ItemsData)
                transaction = transaction.stage("ItemsData", itemData);
            end
        end

        function showRejection(obj, message)
            % showRejection Show a rejection in the message line and retain the draft.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.ItemsDataEditorDialog
                message (1, 1) string
            end

            obj.Message.Text = message;
            obj.Message.FontColor = [0.7 0 0];
        end
    end

    methods (Access = private)
        function addRow(obj)
            % addRow Extend both paired columns in the local candidate only.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.ItemsDataEditorDialog
            end

            obj.Table.Data(end + 1, :) = ["", ""];
        end

        function removeRow(obj)
            % removeRow Remove the final paired item only from the local candidate.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.ItemsDataEditorDialog
            end

            if size(obj.Table.Data, 1) > 0
                obj.Table.Data(end, :) = [];
            end
        end

        function clearDraft(obj)
            % clearDraft Reset the local draft; Clear still requires Apply.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.ItemsDataEditorDialog
            end

            if obj.Kind == "data"
                labels = yamada.ui.inspector.ItemsDataEditorDialog.itemLabels(obj.State.Items);
                obj.Table.Data = yamada.ui.inspector.ItemsDataEditorDialog.tableData(labels, []);
                obj.Cleared = true;
            else
                obj.Table.Data = strings(0, 2);
            end
            removeStyle(obj.Table);
            obj.Message.Text = obj.hint();
            obj.Message.FontColor = [0.3 0.3 0.3];
        end

        function text = hint(obj)
            % hint Return the neutral guidance shown in the message line.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.ItemsDataEditorDialog
            end
            arguments (Output)
                text (1, 1) string
            end

            if obj.Kind == "data"
                text = "Enter literals such as 1, ""Text"", or 'Text'.";
            else
                text = "Enter item text and MATLAB literals for item data.";
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
                error("yamada:ItemsDataEditorDialog:UnsupportedItems", ...
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
                error("yamada:ItemsDataEditorDialog:LengthMismatch", ...
                    "ItemsData must be empty or have one value for every item.");
            end
            for index = 1:numel(labels)
                if iscell(value)
                    item = value{index};
                else
                    item = value(index);
                end
                data(index, 2) = yamada.ui.inspector.ItemsDataEditorDialog.literalText(item);
            end
        end

        function value = itemOutput(labels, original)
            % itemOutput Preserve the documented text-list style while storing edited labels.
            if isstring(original)
                value = reshape(labels, 1, []);
            elseif ischar(original)
                if isscalar(labels)
                    value = char(labels);
                else
                    value = cellstr(reshape(labels, 1, []));
                end
            else
                value = cellstr(reshape(labels, 1, []));
            end
        end

        function text = literalText(value)
            % literalText Display each associated value using a safe typed MATLAB literal.
            text = yamada.ui.inspector.TypedCellCodec.literalText(value);
        end
    end
end

%{
Copyright (C) 2026 Nobuto Kaitoh

This file is part of yamada.

yamada is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by the
Free Software Foundation, either version 3 of the License, or (at your option)
any later version.

yamada is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with yamada. If not, see <https://www.gnu.org/licenses/>.
%}

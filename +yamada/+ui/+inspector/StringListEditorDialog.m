classdef StringListEditorDialog < yamada.ui.inspector.PropertyEditDialog
    % StringListEditorDialog Edit a safe string or cell list in a native dialog.
    %   The editor retains draft text until it parses as a conservative MATLAB
    %   literal and stages only supported string-list values. PropertyEditDialog
    %   owns Apply, Cancel, and the commit.
    %
    %   Example:
    %       editor = yamada.ui.inspector.StringListEditorDialog(["One", "Two"], "Items");
    %       dialog = yamada.ui.inspector.PropertyEditDialog.show(editor, commitFcn);

    properties (Access = private)
        % Path - Property path that receives the list.
        Path string = ""
        % InitialValue - List shown when the editor opens.
        InitialValue = strings(1, 0)
        % Editor - Text area holding the literal draft.
        Editor matlab.ui.control.TextArea = matlab.ui.control.TextArea.empty
    end

    methods
        function obj = StringListEditorDialog(initialValue, path)
            % StringListEditorDialog Prepare a list-literal draft for one property path.
            arguments (Input)
                initialValue
                path (1, 1) string
            end
            arguments (Output)
                obj (1, 1) yamada.ui.inspector.StringListEditorDialog
            end

            spec = struct("Name", "Edit list", "Tag", "yamada-inspector-string-list-dialog", ...
                "Position", [300 300 420 260], "ContentHeight", "1x", "AlertTitle", "Invalid list", ...
                "ApplyTag", "yamada-inspector-string-list-apply", ...
                "CancelTag", "yamada-inspector-string-list-cancel");
            obj@yamada.ui.inspector.PropertyEditDialog(spec, ...
                yamada.model.PropertyTransaction(path, {initialValue}));
            obj.Path = path;
            obj.InitialValue = initialValue;
        end
    end

    methods (Access = protected)
        function buildContent(obj, content)
            % buildContent Create the label and the literal text area.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.StringListEditorDialog
                content (1, 1) matlab.ui.container.GridLayout
            end

            grid = uigridlayout(content, [2 1], "Padding", [0 0 0 0], "RowHeight", {22, "1x"});
            uilabel(grid, "Text", "MATLAB string/cell literal", ...
                "Tag", "yamada-inspector-string-list-label");
            obj.Editor = uitextarea(grid, "Value", cellstr( ...
                yamada.ui.inspector.StringListEditorDialog.literalText(obj.InitialValue)), ...
                "Tag", "yamada-inspector-string-list-dialog-editor");
        end

        function [transaction, message] = read(obj, transaction)
            % read Stage the draft only when it is a safe string or cell list literal.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.StringListEditorDialog
                transaction (1, 1) yamada.model.PropertyTransaction
            end
            arguments (Output)
                transaction (1, 1) yamada.model.PropertyTransaction
                message (1, 1) string
            end

            message = "";
            text = strjoin(string(obj.Editor.Value), newline);
            [value, isLiteral] = yamada.source.MatlabLiteralParser.parse(text);
            if ~isLiteral || ~(isstring(value) || iscell(value))
                message = "Enter a string array or row cell array literal.";
                return
            end
            transaction = transaction.stage(obj.Path, value);
        end
    end

    methods (Static, Access = private)
        function text = literalText(value)
            % literalText Render supported list data as a safe editable MATLAB literal.
            if isstring(value)
                rows = strings(size(value, 1), 1);
                for row = 1:size(value, 1)
                    items = strings(1, size(value, 2));
                    for column = 1:size(value, 2)
                        items(column) = yamada.source.LiteralEncoder.encode(value(row, column));
                    end
                    rows(row) = strjoin(items, " ");
                end
                text = "[" + strjoin(rows, "; ") + "]";
                return
            end
            try
                text = yamada.source.LiteralEncoder.encode(value);
            catch
                text = "";
            end
        end
    end
end

%{
Copyright (C) 2026 Nobuto Kaitoh

This file is part of yamada.

yamada is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

yamada is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with yamada. If not, see <https://www.gnu.org/licenses/>.
%}

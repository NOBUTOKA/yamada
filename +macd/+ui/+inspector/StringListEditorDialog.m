classdef StringListEditorDialog
    % StringListEditorDialog Edit a safe string or cell list in a native dialog.
    %   The dialog retains draft text until it parses as a conservative MATLAB
    %   literal and commits only supported string-list values.

    methods (Static)
        function open(initialValue, commitFcn)
            % open Create a modal string-list editor for one property value.
            arguments (Input)
                initialValue
                commitFcn (1, 1) function_handle
            end

            dialog = uifigure("Name", "Edit list", "Visible", "off", ...
                "WindowStyle", "modal", "Position", [300 300 420 260]);
            grid = uigridlayout(dialog, [3 2]);
            grid.RowHeight = {22, "1x", 30};
            grid.ColumnWidth = {"1x", "1x"};
            label = uilabel(grid, "Text", "MATLAB string/cell literal", ...
                "Tag", "macd-inspector-string-list-label");
            label.Layout.Column = [1 2];
            editor = uitextarea(grid, "Value", cellstr( ...
                macd.ui.inspector.StringListEditorDialog.literalText(initialValue)), ...
                "Tag", "macd-inspector-string-list-dialog-editor");
            editor.Layout.Row = 2;
            editor.Layout.Column = [1 2];
            saveButton = uibutton(grid, "Text", "Apply", ...
                "ButtonPushedFcn", @(~, ~) ...
                macd.ui.inspector.StringListEditorDialog.save(dialog, editor, commitFcn));
            saveButton.Layout.Row = 3;
            cancelButton = uibutton(grid, "Text", "Cancel", ...
                "ButtonPushedFcn", @(~, ~) delete(dialog));
            cancelButton.Layout.Row = 3;
            cancelButton.Layout.Column = 2;
            dialog.Visible = "on";
        end
    end

    methods (Static, Access = private)
        function save(dialog, editor, commitFcn)
            % save Parse and commit the dialog text only when it is a safe list literal.
            text = strjoin(string(editor.Value), newline);
            [value, isLiteral] = macd.source.MatlabLiteralParser.parse(text);
            if ~isLiteral || ~(isstring(value) || iscell(value))
                uialert(dialog, "Enter a string array or row cell array literal.", "Invalid list");
                return
            end
            commitFcn(value);
            delete(dialog);
        end

        function text = literalText(value)
            % literalText Render supported list data as a safe editable MATLAB literal.
            if isstring(value)
                rows = strings(size(value, 1), 1);
                for row = 1:size(value, 1)
                    items = strings(1, size(value, 2));
                    for column = 1:size(value, 2)
                        items(column) = macd.source.LiteralEncoder.encode(value(row, column));
                    end
                    rows(row) = strjoin(items, " ");
                end
                text = "[" + strjoin(rows, "; ") + "]";
                return
            end
            try
                text = macd.source.LiteralEncoder.encode(value);
            catch
                text = "";
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

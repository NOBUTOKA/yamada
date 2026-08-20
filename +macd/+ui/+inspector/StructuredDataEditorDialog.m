classdef StructuredDataEditorDialog
    % StructuredDataEditorDialog Edit finite safe MATLAB data literals in a modal dialog.
    %   The dialog accepts only the non-evaluating literal subset implemented by
    %   MatlabLiteralParser and never executes user-entered MATLAB expressions.

    methods (Static)
        function open(currentValue, path, commitFcn)
            % open Show a modal structured-data literal editor.
            arguments (Input)
                currentValue
                path (1, 1) string
                commitFcn (1, 1) function_handle
            end

            transaction = macd.model.PropertyTransaction(path, {currentValue});
            dialog = uifigure("Name", "Edit data", "Position", [100 100 500 300], ...
                "WindowStyle", "modal");
            grid = uigridlayout(dialog, [3 1], "Padding", [12 12 12 12], ...
                "RowHeight", {"1x", 24, 30});
            text = macd.ui.inspector.StructuredDataEditorDialog.initialText(currentValue);
            area = uitextarea(grid, "Value", {char(text)}, ...
                "Tag", "macd-inspector-structured-data-text");
            message = uilabel(grid, "Text", "", "FontColor", [0.7 0 0], ...
                "Tag", "macd-inspector-structured-data-error");
            buttons = uigridlayout(grid, [1 2], "Padding", [0 0 0 0], ...
                "ColumnWidth", {"1x", 90});
            uibutton(buttons, "Text", "Cancel", "ButtonPushedFcn", @(~, ~) closeDialog());
            uibutton(buttons, "Text", "Apply", "ButtonPushedFcn", @(~, ~) applyValue());

            function applyValue()
                source = strjoin(string(area.Value), newline);
                [value, isLiteral] = macd.source.MatlabLiteralParser.parse(source);
                if ~isLiteral
                    message.Text = "Enter a supported MATLAB literal.";
                    area.BackgroundColor = [1 0.9 0.9];
                    return
                end
                transaction.stage(path, value);
                message.Text = commitFcn(transaction.changes());
                if strlength(message.Text) > 0
                    area.BackgroundColor = [1 0.9 0.9];
                    return
                end
                close(dialog);
            end

            function closeDialog()
                if isvalid(dialog)
                    delete(dialog);
                end
            end
        end
    end

    methods (Static, Access = private)
        function text = initialText(value)
            % initialText Render current data only when it has a safe literal form.
            try
                text = macd.source.LiteralEncoder.encode(value);
            catch
                text = "[]";
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

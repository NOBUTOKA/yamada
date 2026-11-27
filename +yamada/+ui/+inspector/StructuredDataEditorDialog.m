classdef StructuredDataEditorDialog < yamada.ui.inspector.PropertyEditDialog
    % StructuredDataEditorDialog Edit finite safe MATLAB data literals in a modal dialog.
    %   The editor accepts only the non-evaluating literal subset implemented by
    %   MatlabLiteralParser and never executes user-entered MATLAB expressions.
    %   PropertyEditDialog owns Apply, Cancel, and the commit.
    %
    %   Example:
    %       editor = yamada.ui.inspector.StructuredDataEditorDialog([1 2], "NodeData");
    %       dialog = yamada.ui.inspector.PropertyEditDialog.show(editor, commitFcn);

    properties (Access = private)
        % Path - Property path that receives the value.
        Path string = ""
        % CurrentValue - Value shown when the editor opens.
        CurrentValue = []
        % Area - Text area holding the literal draft.
        Area matlab.ui.control.TextArea = matlab.ui.control.TextArea.empty
        % Message - Validation message line.
        Message matlab.ui.control.Label = matlab.ui.control.Label.empty
    end

    methods
        function obj = StructuredDataEditorDialog(currentValue, path)
            % StructuredDataEditorDialog Prepare a literal draft for one property path.
            arguments (Input)
                currentValue
                path (1, 1) string
            end
            arguments (Output)
                obj (1, 1) yamada.ui.inspector.StructuredDataEditorDialog
            end

            spec = struct("Name", "Edit data", "Tag", "yamada-inspector-structured-data-dialog", ...
                "Position", [100 100 500 300], "ContentHeight", "1x", "AlertTitle", "Invalid data", ...
                "ApplyTag", "yamada-inspector-structured-data-apply", ...
                "CancelTag", "yamada-inspector-structured-data-cancel");
            obj@yamada.ui.inspector.PropertyEditDialog(spec, ...
                yamada.model.PropertyTransaction(path, {currentValue}));
            obj.Path = path;
            obj.CurrentValue = currentValue;
        end
    end

    methods (Access = protected)
        function buildContent(obj, content)
            % buildContent Create the literal text area and the message line.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.StructuredDataEditorDialog
                content (1, 1) matlab.ui.container.GridLayout
            end

            grid = uigridlayout(content, [2 1], "Padding", [0 0 0 0], "RowHeight", {"1x", 24});
            text = yamada.ui.inspector.StructuredDataEditorDialog.initialText(obj.CurrentValue);
            obj.Area = uitextarea(grid, "Value", {char(text)}, ...
                "Tag", "yamada-inspector-structured-data-text");
            obj.Message = uilabel(grid, "Text", "", "FontColor", [0.7 0 0], ...
                "Tag", "yamada-inspector-structured-data-error");
        end

        function [transaction, message] = read(obj, transaction)
            % read Stage the draft only when it parses as a supported literal.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.StructuredDataEditorDialog
                transaction (1, 1) yamada.model.PropertyTransaction
            end
            arguments (Output)
                transaction (1, 1) yamada.model.PropertyTransaction
                message (1, 1) string
            end

            message = "";
            source = strjoin(string(obj.Area.Value), newline);
            [value, isLiteral] = yamada.source.MatlabLiteralParser.parse(source);
            if ~isLiteral
                message = "Enter a supported MATLAB literal.";
                return
            end
            transaction = transaction.stage(obj.Path, value);
        end

        function showRejection(obj, message)
            % showRejection Show a rejection below the text and tint the text area.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.StructuredDataEditorDialog
                message (1, 1) string
            end

            obj.Message.Text = message;
            obj.Area.BackgroundColor = [1 0.9 0.9];
        end
    end

    methods (Static, Access = private)
        function text = initialText(value)
            % initialText Render current data only when it has a safe literal form.
            try
                text = yamada.source.LiteralEncoder.encode(value);
            catch
                text = "[]";
            end
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

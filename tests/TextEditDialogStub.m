classdef TextEditDialogStub < yamada.ui.inspector.PropertyEditDialog
    % TextEditDialogStub Minimal one-field editor for testing the PropertyEditDialog frame.
    %   The editor stages the field text into the Text path and reports an empty
    %   field as invalid without staging it.
    %
    %   Example:
    %       editor = TextEditDialogStub("Initial");
    %       dialog = yamada.ui.inspector.PropertyEditDialog.show(editor, commitFcn, false);

    properties (Access = private)
        % InitialText - Text shown when the field is created.
        InitialText string = ""
        % Field - Text field that holds the draft.
        Field matlab.ui.control.EditField = matlab.ui.control.EditField.empty
    end

    methods
        function obj = TextEditDialogStub(initialText)
            % TextEditDialogStub Prepare a text draft for the Text path.
            arguments (Input)
                initialText (1, 1) string
            end
            arguments (Output)
                obj (1, 1) TextEditDialogStub
            end

            spec = struct("Name", "Edit text", "Tag", "text-edit-dialog-stub", ...
                "Position", [300 300 300 120], "ContentHeight", "1x", ...
                "AlertTitle", "Invalid text", "ApplyTag", "text-edit-dialog-stub-apply", ...
                "CancelTag", "text-edit-dialog-stub-cancel");
            obj@yamada.ui.inspector.PropertyEditDialog(spec, ...
                yamada.model.PropertyTransaction("Text", {initialText}));
            obj.InitialText = initialText;
        end
    end

    methods (Access = protected)
        function buildContent(obj, content)
            % buildContent Create the single text field.
            arguments (Input)
                obj (1, 1) TextEditDialogStub
                content (1, 1) matlab.ui.container.GridLayout
            end

            obj.Field = uieditfield(content, "Value", obj.InitialText, ...
                "Tag", "text-edit-dialog-stub-field");
        end

        function [transaction, message] = read(obj, transaction)
            % read Stage the field text, or report an empty field without staging it.
            arguments (Input)
                obj (1, 1) TextEditDialogStub
                transaction (1, 1) yamada.model.PropertyTransaction
            end
            arguments (Output)
                transaction (1, 1) yamada.model.PropertyTransaction
                message (1, 1) string
            end

            message = "";
            if strlength(obj.Field.Value) == 0
                message = "Enter text.";
                return
            end
            transaction = transaction.stage("Text", string(obj.Field.Value));
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

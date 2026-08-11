classdef PropertyEditorFactory
    % PropertyEditorFactory Create allowlisted native inspector editors.
    %   This factory maps catalog editor identifiers to project-owned controls and
    %   never evaluates catalog text as MATLAB code.

    methods (Static)
        function control = create(parent, definition, commitFcn)
            % create Construct one editor control for a typed property definition.
            arguments (Input)
                parent
                definition (1, 1) macd.model.PropertyDefinition
                commitFcn (1, 1) function_handle
            end

            switch definition.Editor
                case {"logical", "onOff"}
                    control = uicheckbox(parent, "Text", "", "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) commitFcn(source.Value));
                    control.UserData = definition.Editor;
                case "enum"
                    items = macd.ui.inspector.PropertyEditorFactory.enumItems(definition);
                    control = uidropdown(parent, "Items", cellstr(items), ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) commitFcn(string(source.Value)));
                case "number"
                    control = uieditfield(parent, "numeric", ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) commitFcn(source.Value));
                    macd.ui.inspector.PropertyEditorFactory.applyNumberSchema( ...
                        control, definition.ValueSchema);
                case "color"
                    control = uibutton(parent, "Text", "", ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ButtonPushedFcn", @(source, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.pickColor(source, commitFcn));
                case "stringList"
                    control = uibutton(parent, "Text", "", ...
                        "Tag", "macd-inspector-string-list-editor", ...
                        "ButtonPushedFcn", @(source, ~) ...
                        macd.ui.inspector.StringListEditorDialog.open(source.UserData, commitFcn));
                case {"literal", "text", "numericVector"}
                    control = uieditfield(parent, "text", ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) commitFcn(string(source.Value)));
                otherwise
                    control = uieditfield(parent, "text", ...
                        "Tag", "macd-inspector-property-editor");
                    control.UserData = "readOnlyFallback";
            end
        end

        function result = supportsEditing(definition)
            % supportsEditing Return whether the definition has a native editable adapter.
            arguments (Input)
                definition (1, 1) macd.model.PropertyDefinition
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = any(definition.Editor == ["literal", "text", "logical", ...
                "onOff", "enum", "number", "numericVector", "color", "stringList"]);
            if definition.Editor == "enum" && ~isfield(definition.ValueSchema, "values")
                result = false;
            end
        end

        function synchronize(control, value, isEditable, rawValue)
            % synchronize Load a model value into one factory-created editor.
            arguments (Input)
                control
                value (1, 1) string
                isEditable (1, 1) logical
                rawValue = []
            end

            if isa(control, "matlab.ui.control.CheckBox")
                control.Value = value == "on" || value == "true" || value == "1";
                control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff(isEditable);
            elseif isa(control, "matlab.ui.control.NumericEditField")
                number = str2double(value);
                if ~isnan(number)
                    control.Value = number;
                end
                control.Editable = isEditable;
            elseif isa(control, "matlab.ui.control.Button")
                control.Text = char(value);
                control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff(isEditable);
                if control.Tag == "macd-inspector-string-list-editor"
                    control.UserData = rawValue;
                    control.Text = macd.ui.inspector.PropertyEditorFactory.listSummary(rawValue);
                    return
                end
                [rgb, isLiteral] = macd.source.MatlabLiteralParser.parse(value);
                if isLiteral && isnumeric(rgb) && isequal(size(rgb), [1 3]) && ...
                        all(isfinite(rgb)) && all(rgb >= 0) && all(rgb <= 1)
                    control.BackgroundColor = rgb;
                    control.UserData = rgb;
                else
                    control.BackgroundColor = [0.94 0.94 0.94];
                    control.UserData = [];
                end
            else
                control.Value = char(value);
                control.Editable = isEditable && ~macd.ui.inspector.PropertyEditorFactory.isReadOnlyFallback(control);
            end
        end

        function value = editorValue(control)
            % editorValue Return the current adapter value without parsing or committing it.
            arguments (Input)
                control
            end

            if isa(control, "matlab.ui.control.CheckBox") || ...
                    isa(control, "matlab.ui.control.NumericEditField") || ...
                    isa(control, "matlab.ui.control.EditField")
                value = control.Value;
            elseif isa(control, "matlab.ui.control.Button")
                value = control.UserData;
            else
                value = [];
            end
        end

        function restoreDraft(control, value)
            % restoreDraft Restore an uncommitted adapter value without invoking its callback.
            arguments (Input)
                control
                value
            end

            if isa(control, "matlab.ui.control.CheckBox") || ...
                    isa(control, "matlab.ui.control.NumericEditField") || ...
                    isa(control, "matlab.ui.control.EditField")
                control.Value = value;
            elseif isa(control, "matlab.ui.control.Button")
                control.UserData = value;
                if control.Tag == "macd-inspector-string-list-editor"
                    control.Text = macd.ui.inspector.PropertyEditorFactory.listSummary(value);
                elseif isnumeric(value) && isequal(size(value), [1 3])
                    control.BackgroundColor = value;
                end
            end
        end
    end

    methods (Static, Access = private)
        function items = enumItems(definition)
            % enumItems Extract finite enum choices from the definition schema.
            items = strings(1, 0);
            if isfield(definition.ValueSchema, "values")
                items = string(definition.ValueSchema.values);
            end
            if isempty(items)
                items = "";
            end
        end

        function result = onOff(value)
            % onOff Convert a logical enable flag to the MATLAB UI token.
            if value
                result = "on";
            else
                result = "off";
            end
        end

        function result = isReadOnlyFallback(control)
            % isReadOnlyFallback Identify controls created for deferred editor kinds.
            result = isstring(control.UserData) && isscalar(control.UserData) && ...
                control.UserData == "readOnlyFallback";
        end

        function applyNumberSchema(control, schema)
            % applyNumberSchema Apply supported scalar constraints to a numeric editor.
            arguments (Input)
                control (1, 1) matlab.ui.control.NumericEditField
                schema (1, 1) struct
            end

            if isfield(schema, "minimum")
                control.Limits(1) = schema.minimum;
            end
            if isfield(schema, "maximum")
                control.Limits(2) = schema.maximum;
            end
            if isfield(schema, "integer") && schema.integer
                control.RoundFractionalValues = "on";
            end
        end

        function pickColor(control, commitFcn)
            % pickColor Open the native picker and commit a valid RGB row vector.
            arguments (Input)
                control (1, 1) matlab.ui.control.Button
                commitFcn (1, 1) function_handle
            end

            current = control.UserData;
            if ~isnumeric(current) || ~isequal(size(current), [1 3])
                current = [0 0 0];
            end
            selected = uisetcolor(current);
            if isnumeric(selected) && isequal(size(selected), [1 3]) && ...
                    all(isfinite(selected)) && all(selected >= 0) && all(selected <= 1)
                commitFcn(selected);
            end
        end

        function text = listSummary(value)
            % listSummary Describe a string-list value without flattening its shape.
            if isstring(value)
                text = sprintf("%d-by-%d string", size(value, 1), size(value, 2));
            elseif iscell(value)
                text = sprintf("%d item cell list", numel(value));
            else
                text = "Edit list";
            end
        end
    end
end

%{
MatlabAppClassDesigner - Allowlisted native property-editor factory.
Copyright (C) 2026 MatlabAppClassDesigner contributors

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

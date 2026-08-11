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
                    control = uicheckbox(parent, "Tag", "macd-inspector-property-editor", ...
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
                otherwise
                    control = uieditfield(parent, "text", ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) commitFcn(string(source.Value)));
            end
        end

        function synchronize(control, value, isEditable)
            % synchronize Load a model value into one factory-created editor.
            arguments (Input)
                control
                value (1, 1) string
                isEditable (1, 1) logical
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
            else
                control.Value = char(value);
                control.Editable = isEditable;
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

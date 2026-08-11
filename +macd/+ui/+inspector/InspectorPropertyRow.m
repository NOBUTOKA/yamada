classdef InspectorPropertyRow < handle
    % InspectorPropertyRow Present and synchronize one inspector property value.
    %   The row owns a label and one native editor. Its callback identifies the
    %   component and property without allowing adapters to mutate the model.

    properties (Access = private)
        Editor matlab.ui.control.EditField
        CommitFcn function_handle
        ComponentId string
        Path string
    end

    methods
        function obj = InspectorPropertyRow(parent, row, componentId, definition, commitFcn)
            % InspectorPropertyRow Create one disposable native property-row control set.
            arguments (Input)
                parent
                row (1, 1) double {mustBeInteger, mustBePositive}
                componentId (1, 1) string
                definition (1, 1) macd.model.PropertyDefinition
                commitFcn (1, 1) function_handle
            end
            arguments (Output)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
            end

            % Keep layout and binding local to the inspector reconstruction.
            grid = uigridlayout(parent, [1 2]);
            grid.Layout.Row = row;
            grid.Padding = [0 0 0 0];
            grid.ColumnSpacing = 4;
            grid.ColumnWidth = {105, "1x"};
            obj.ComponentId = componentId;
            obj.Path = definition.Path;
            obj.CommitFcn = commitFcn;
            uilabel(grid, "Text", definition.DisplayName, "Tooltip", definition.Path, ...
                "Tag", "macd-inspector-property-label");
            obj.Editor = uieditfield(grid, "text", "Tag", "macd-inspector-property-editor", ...
                "ValueChangedFcn", @(~, ~) obj.commit());
            obj.Editor.Layout.Column = 2;
        end

        function synchronize(obj, value, isEditable)
            % synchronize Load a current value and editability presentation.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
                value (1, 1) string
                isEditable (1, 1) logical
            end
            obj.Editor.Value = char(value);
            obj.Editor.Editable = isEditable;
        end
    end

    methods (Access = private)
        function commit(obj)
            % commit Forward edited text through the row-owned current binding.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
            end
            obj.CommitFcn(obj.ComponentId, obj.Path, string(obj.Editor.Value));
        end
    end
end

%{
MatlabAppClassDesigner - Native property row for the categorized inspector.
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

classdef InspectorPropertyRow < handle
    % InspectorPropertyRow Present and synchronize one inspector property value.
    %   The row owns a label and one native editor. Its callback identifies the
    %   component and property without allowing adapters to mutate the model.

    properties (Access = private)
        Editor
        ErrorLabel matlab.ui.control.Label
        Definition macd.model.PropertyDefinition
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
            grid = uigridlayout(parent, [2 2]);
            grid.Layout.Row = row;
            grid.Padding = [0 0 0 0];
            grid.ColumnSpacing = 4;
            grid.ColumnWidth = {105, "1x"};
            grid.RowHeight = {28, 18};
            obj.ComponentId = componentId;
            obj.Path = definition.Path;
            obj.Definition = definition;
            obj.CommitFcn = commitFcn;
            uilabel(grid, "Text", definition.DisplayName, "Tooltip", definition.Path, ...
                "Tag", "macd-inspector-property-label");
            obj.Editor = macd.ui.inspector.PropertyEditorFactory.create(grid, definition, ...
                @(value) obj.commit(value));
            obj.Editor.Layout.Column = 2;
            obj.ErrorLabel = uilabel(grid, "Text", "", "FontColor", [0.75 0 0], ...
                "Tag", "macd-inspector-property-error");
            obj.ErrorLabel.Layout.Row = 2;
            obj.ErrorLabel.Layout.Column = [1 2];
        end

        function synchronize(obj, value, isEditable, rawValue)
            % synchronize Load a current value and editability presentation.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
                value (1, 1) string
                isEditable (1, 1) logical
                rawValue = []
            end
            macd.ui.inspector.PropertyEditorFactory.synchronize( ...
                obj.Editor, value, isEditable && ...
                macd.ui.inspector.PropertyEditorFactory.supportsEditing(obj.Definition), rawValue);
            obj.ErrorLabel.Text = "";
        end

        function state = snapshotTransientState(obj)
            % snapshotTransientState Return an uncommitted invalid draft for later restoration.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
            end
            arguments (Output)
                state (1, 1) struct
            end

            % Only invalid drafts are transient state; committed values come from the model.
            state = struct("Path", obj.Path, "HasDraft", strlength(obj.ErrorLabel.Text) > 0, ...
                "Value", [], "Message", string(obj.ErrorLabel.Text), "HasFocus", obj.hasFocus());
            if state.HasDraft
                state.Value = macd.ui.inspector.PropertyEditorFactory.editorValue(obj.Editor);
            end
        end

        function restoreTransientState(obj, state)
            % restoreTransientState Restore one compatible invalid draft and focus state.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
                state (1, 1) struct
            end

            if state.Path ~= obj.Path
                return
            end
            if state.HasDraft
                macd.ui.inspector.PropertyEditorFactory.restoreDraft(obj.Editor, state.Value);
                obj.ErrorLabel.Text = state.Message;
            end
            if state.HasFocus
                try
                    focus(obj.Editor);
                catch
                    % Focus is best effort when the rebuilt control is not yet visible.
                end
            end
        end
    end

    methods (Access = private)
        function commit(obj, value)
            % commit Forward edited text through the row-owned current binding.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
                value
            end
            message = obj.CommitFcn(obj.ComponentId, obj.Path, value);
            if strlength(message) > 0
                obj.ErrorLabel.Text = message;
            end
        end

        function result = hasFocus(obj)
            % hasFocus Return whether this row editor currently owns UI focus.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = false;
            figure = ancestor(obj.Editor, "figure");
            if ~isempty(figure) && isvalid(figure) && isprop(figure, "CurrentObject")
                result = isequal(figure.CurrentObject, obj.Editor);
            end
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

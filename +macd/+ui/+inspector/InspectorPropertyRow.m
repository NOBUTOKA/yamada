classdef InspectorPropertyRow < handle
    % InspectorPropertyRow Present and synchronize one inspector property value.
    %   The row owns a label and one native editor. Its callback identifies the
    %   component and property without allowing adapters to mutate the model.

    properties (Access = private)
        Editor
        ErrorMessage string = ""
        NormalBackgroundColor double = [1 1 1]
        Definition macd.model.PropertyDefinition
        CommitFcn function_handle
        BatchCommitFcn function_handle
        ComponentId string
        Path string
        Row struct = struct()
        IsComposite logical = false
    end

    methods
        function obj = InspectorPropertyRow( ...
                parent, row, componentId, definition, commitFcn, batchCommitFcn)
            % InspectorPropertyRow Create one disposable native property-row control set.
            arguments (Input)
                parent
                row (1, 1) double {mustBeInteger, mustBePositive}
                componentId (1, 1) string
                definition
                commitFcn (1, 1) function_handle
                batchCommitFcn = []
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
            grid.RowHeight = {macd.ui.inspector.InspectorPropertyRow.rowHeight(definition)};
            obj.ComponentId = componentId;
            obj.IsComposite = isstruct(definition) && isfield(definition, "IsComposite") && ...
                definition.IsComposite;
            if obj.IsComposite
                obj.Row = definition;
                obj.Path = definition.Id;
                obj.Definition = macd.model.PropertyDefinition(definition.Id, [], false, false, ...
                    struct("displayName", definition.DisplayName, "editor", definition.Editor));
                displayName = definition.DisplayName;
                tooltip = strjoin(definition.MemberPaths, ", ");
            else
                obj.Path = definition.Path;
                obj.Definition = definition;
                displayName = definition.DisplayName;
                tooltip = definition.Path;
            end
            obj.CommitFcn = commitFcn;
            if isempty(batchCommitFcn)
                batchCommitFcn = @(id, changes) ...
                    macd.ui.inspector.InspectorPropertyRow.commitSingleChange( ...
                    commitFcn, id, changes);
            end
            obj.BatchCommitFcn = batchCommitFcn;
            uilabel(grid, "Text", displayName, "Tooltip", tooltip, ...
                "Tag", "macd-inspector-property-label");
            if obj.IsComposite
                obj.Editor = macd.ui.inspector.PropertyEditorFactory.createComposite( ...
                    grid, definition, @(changes) obj.commitBatch(changes));
            else
                obj.Editor = macd.ui.inspector.PropertyEditorFactory.create(grid, definition, ...
                    @(value) obj.commit(value), @(changes) obj.commitBatch(changes));
            end
            obj.Editor.Layout.Column = 2;
            obj.captureNormalBackgroundColor();
        end

        function synchronize(obj, value, isEditable, rawValue, relatedValues)
            % synchronize Load a current value and editability presentation.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
                value (1, 1) string
                isEditable (1, 1) logical
                rawValue = []
                relatedValues struct = struct()
            end
            if obj.IsComposite
                error("macd:InspectorPropertyRow:CompositeSynchronization", ...
                    "Composite rows require ordered member synchronization.");
            end
            % Clear a stale error presentation before loading the current model value.
            obj.restoreNormalBackgroundColor();
            macd.ui.inspector.PropertyEditorFactory.synchronize( ...
                obj.Editor, value, isEditable && ...
                macd.ui.inspector.PropertyEditorFactory.supportsEditing(obj.Definition), rawValue, relatedValues);
            obj.ErrorMessage = "";
            obj.Editor.Tooltip = "";
            obj.captureNormalBackgroundColor();
        end

        function synchronizeMembers(obj, members, relatedValues)
            % synchronizeMembers Load an ordered multi-property row from effective member state.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
                members (1, :) struct
                relatedValues struct = struct()
            end

            if ~obj.IsComposite
                if numel(members) ~= 1
                    error("macd:InspectorPropertyRow:UnexpectedMemberCount", ...
                        "A singleton Inspector row requires exactly one member.");
                end
                obj.synchronize(members.Value, members.IsEditable, members.RawValue, relatedValues);
                return
            end
            obj.restoreNormalBackgroundColor();
            macd.ui.inspector.PropertyEditorFactory.synchronizeComposite( ...
                obj.Editor, obj.Row, members, relatedValues);
            obj.ErrorMessage = "";
            obj.Editor.Tooltip = "";
            obj.captureNormalBackgroundColor();
        end

        function id = identifier(obj)
            % identifier Return the stable projected row identifier for surface comparison.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
            end
            arguments (Output)
                id (1, 1) string
            end

            id = obj.Path;
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
            state = struct("Path", obj.Path, "HasDraft", strlength(obj.ErrorMessage) > 0 && ...
                ~obj.IsComposite, ...
                "Value", [], "Message", obj.ErrorMessage, "HasFocus", obj.hasFocus());
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

            if state.Path ~= obj.Path || obj.IsComposite
                return
            end
            if state.HasDraft
                macd.ui.inspector.PropertyEditorFactory.restoreDraft(obj.Editor, state.Value);
                obj.showError(state.Message);
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
                obj.showError(message);
            end
        end

        function message = commitBatch(obj, changes)
            % commitBatch Submit one dialog-owned staged property batch through the row binding.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
                changes (1, :) struct
            end
            arguments (Output)
                message (1, 1) string
            end

            message = obj.BatchCommitFcn(obj.ComponentId, changes);
        end

        function showError(obj, message)
            % showError Mark an invalid editor draft and expose its explanation by hover.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
                message (1, 1) string
            end

            if strlength(obj.ErrorMessage) == 0
                obj.captureNormalBackgroundColor();
            end
            obj.ErrorMessage = message;
            obj.Editor.Tooltip = message;
            if isprop(obj.Editor, "BackgroundColor")
                obj.Editor.BackgroundColor = [1 0.9 0.9];
            end
        end

        function captureNormalBackgroundColor(obj)
            % captureNormalBackgroundColor Save the editor background used outside errors.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
            end

            if isprop(obj.Editor, "BackgroundColor")
                obj.NormalBackgroundColor = obj.Editor.BackgroundColor;
            end
        end

        function restoreNormalBackgroundColor(obj)
            % restoreNormalBackgroundColor Restore the editor background after an error clears.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorPropertyRow
            end

            if isprop(obj.Editor, "BackgroundColor")
                obj.Editor.BackgroundColor = obj.NormalBackgroundColor;
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

    methods (Static)
        function height = rowHeight(definition)
            % rowHeight Return the deterministic native height requested by one editor schema.
            arguments (Input)
                definition
            end
            arguments (Output)
                height (1, 1) double
            end

            if isstruct(definition) && isfield(definition, "IsComposite") && definition.IsComposite
                height = 28;
            elseif definition.Editor == "itemSelection" && ...
                    isfield(definition.ValueSchema, "multiselectProperty")
                % Reserve the List Box selection surface for its optional multi-select mode.
                height = 84;
            elseif definition.Editor == "multilineText"
                height = 84;
            elseif definition.Editor == "dateTime" && ...
                    isfield(definition.ValueSchema, "shape") && ...
                    string(definition.ValueSchema.shape) == "fixedLengthVector"
                % The two native date pickers require a full two-row parent slot.
                height = 56;
            else
                height = 28;
            end
        end
    end

    methods (Static, Access = private)
        function message = commitSingleChange(commitFcn, componentId, changes)
            % commitSingleChange Adapt a legacy row callback to one staged property value.
            arguments (Input)
                commitFcn (1, 1) function_handle
                componentId (1, 1) string
                changes (1, :) struct
            end
            arguments (Output)
                message (1, 1) string
            end

            if numel(changes) ~= 1
                error("macd:InspectorPropertyRow:InvalidSingleChange", ...
                    "A legacy inspector row can commit only one property value.");
            end
            message = commitFcn(componentId, string(changes.Path), changes.Value);
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

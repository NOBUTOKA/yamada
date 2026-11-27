classdef (Abstract) PropertyEditDialog < handle
    % PropertyEditDialog Own the modal frame, Apply, Cancel, and close handling of a property draft editor.
    %   A subclass builds its controls in the content area and stages its local
    %   draft into a PropertyTransaction when asked. The commit function is a
    %   private property of this class, so a subclass cannot change the document:
    %   Apply is the only commit path, and Cancel or closing the window never
    %   commits. A draft that stages nothing closes without committing; the
    %   Inspector commit drops staged values equal to the effective value. A rejected read
    %   or commit keeps the dialog and its draft open; a subclass may override
    %   showRejection to present the message inside the dialog.
    %
    %   Example:
    %       editor = yamada.ui.inspector.DayOfWeekEditorDialog([1 7], "DisabledDaysOfWeek");
    %       dialog = yamada.ui.inspector.PropertyEditDialog.show(editor, commitFcn);

    properties (SetAccess = private)
        % Figure - Modal dialog figure, empty until show creates it.
        Figure matlab.ui.Figure = matlab.ui.Figure.empty
    end

    properties (Access = private)
        % Spec - Title, tags, size, and content row height of the frame.
        Spec struct = struct()
        % Transaction - Starting snapshot that read stages the draft into.
        Transaction yamada.model.PropertyTransaction = yamada.model.PropertyTransaction.empty
        % CommitFcn - Document commit function, reachable only from apply.
        CommitFcn function_handle = function_handle.empty
    end

    methods (Static)
        function dialog = show(editor, commitFcn, visible)
            % show Create the frame for one editor and wire Apply as its only commit path.
            arguments (Input)
                editor (1, 1) yamada.ui.inspector.PropertyEditDialog
                commitFcn (1, 1) function_handle
                visible (1, 1) logical = true
            end
            arguments (Output)
                dialog (1, 1) matlab.ui.Figure
            end

            % Build the modal frame with the editor content above the action row.
            spec = editor.Spec;
            editor.CommitFcn = commitFcn;
            dialog = uifigure("Name", spec.Name, "Visible", "off", ...
                "WindowStyle", "modal", "Position", spec.Position, "Tag", spec.Tag);
            editor.Figure = dialog;
            dialog.CloseRequestFcn = @(~, ~) editor.close();
            grid = uigridlayout(dialog, [2 1], "Padding", [12 12 12 12], ...
                "RowHeight", {spec.ContentHeight, 30}, "RowSpacing", 10);
            content = uigridlayout(grid, [1 1], "Padding", [0 0 0 0]);
            content.Layout.Row = 1;
            editor.buildContent(content);

            % Place editor-local actions before the shared Cancel and Apply.
            actions = editor.editorActions();
            actionGrid = uigridlayout(grid, [1 numel(actions) + 2], "Padding", [0 0 0 0], ...
                "ColumnWidth", [repmat({90}, 1, numel(actions)) {"1x", "1x"}], "ColumnSpacing", 8);
            actionGrid.Layout.Row = 2;
            for index = 1:numel(actions)
                uibutton(actionGrid, "Text", actions(index).Text, "Tag", actions(index).Tag, ...
                    "ButtonPushedFcn", actions(index).Callback);
            end
            uibutton(actionGrid, "Text", "Cancel", "Tag", spec.CancelTag, ...
                "ButtonPushedFcn", @(~, ~) editor.close());
            uibutton(actionGrid, "Text", "Apply", "Tag", spec.ApplyTag, ...
                "ButtonPushedFcn", @(~, ~) editor.apply());
            if visible
                editor.aboutToShow();
                dialog.Visible = "on";
            end
        end
    end

    methods (Access = protected)
        function obj = PropertyEditDialog(spec, transaction)
            % PropertyEditDialog Record the frame description and the starting snapshot.
            %   spec has Name, Tag, Position, ContentHeight, AlertTitle, ApplyTag,
            %   and CancelTag fields.
            arguments (Input)
                spec (1, 1) struct
                transaction (1, 1) yamada.model.PropertyTransaction
            end
            arguments (Output)
                obj (1, 1) yamada.ui.inspector.PropertyEditDialog
            end

            obj.Spec = spec;
            obj.Transaction = transaction;
        end

        function actions = editorActions(~)
            % editorActions Return editor-local buttons as a struct array with Text, Tag, and Callback.
            arguments (Output)
                actions struct
            end

            actions = struct("Text", {}, "Tag", {}, "Callback", {});
        end

        function aboutToShow(~)
            % aboutToShow Prepare layout work that must start before a visible dialog appears.
        end

        function showRejection(obj, message)
            % showRejection Present a rejected read or commit; the draft stays open either way.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.PropertyEditDialog
                message (1, 1) string
            end

            % uialert requires a visible figure; a hidden dialog only keeps its draft.
            if string(obj.Figure.Visible) == "on"
                uialert(obj.Figure, message, obj.Spec.AlertTitle);
            end
        end
    end

    methods (Abstract, Access = protected)
        % buildContent Create the editor controls inside the given content grid.
        buildContent(obj, content)
        % read Stage the current draft into transaction, or return a nonempty message.
        [transaction, message] = read(obj, transaction)
    end

    methods (Access = private)
        function apply(obj)
            % apply Commit the staged draft as one batch, or keep the draft after a rejection.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.PropertyEditDialog
            end

            % The snapshot is a value, so each attempt stages from the unchanged start.
            [candidate, message] = obj.read(obj.Transaction);
            if strlength(message) == 0
                changes = candidate.changes();
                if isempty(changes)
                    % A draft that stages nothing closes without a document edit.
                    obj.close();
                    return
                end
                message = obj.CommitFcn(changes);
            end
            if strlength(message) > 0
                obj.showRejection(message);
                return
            end
            obj.close();
        end

        function close(obj)
            % close Dispose the dialog without committing an unapplied draft.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.PropertyEditDialog
            end

            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure);
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

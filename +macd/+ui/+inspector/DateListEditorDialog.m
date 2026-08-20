classdef DateListEditorDialog
    % DateListEditorDialog Edit a draft list of disabled calendar dates.
    %   This modal adapter keeps a column datetime vector local until Apply. It
    %   uses native date controls, so no locale-formatted date text is parsed.

    methods (Static)
        function dialog = open(initialValue, path, commitFcn, visible)
            % open Create a date-list dialog with Add, Delete, Clear, Apply, and Cancel actions.
            arguments (Input)
                initialValue datetime
                path (1, 1) string
                commitFcn (1, 1) function_handle
                visible (1, 1) logical = true
            end
            arguments (Output)
                dialog (1, 1) matlab.ui.Figure
            end

            dates = macd.ui.inspector.DateListEditorDialog.normalize(initialValue);
            transaction = macd.model.PropertyTransaction(path, {dates});
            dialog = uifigure("Name", "Edit disabled dates", "Visible", "off", ...
                "WindowStyle", "modal", "Position", [300 300 420 330], ...
                "Tag", "macd-inspector-date-list-dialog");
            grid = uigridlayout(dialog, [5 2], "Padding", [12 12 12 12], ...
                "RowHeight", {22, "1x", 30, 30, 30}, "ColumnWidth", {"1x", 90});
            uilabel(grid, "Text", "Disabled dates", ...
                "Tag", "macd-inspector-date-list-label");
            list = uilistbox(grid, "Multiselect", "on", ...
                "Tag", "macd-inspector-date-list-values");
            list.Layout.Row = 2;
            list.Layout.Column = [1 2];
            picker = uidatepicker(grid, "Value", datetime("today"), ...
                "Tag", "macd-inspector-date-list-picker");
            picker.Layout.Row = 3;
            addButton = uibutton(grid, "Text", "Add", ...
                "Tag", "macd-inspector-date-list-add", ...
                "ButtonPushedFcn", @(~, ~) addDate());
            addButton.Layout.Row = 3;
            addButton.Layout.Column = 2;
            clearButton = uibutton(grid, "Text", "Clear", ...
                "Tag", "macd-inspector-date-list-clear", ...
                "ButtonPushedFcn", @(~, ~) clearDates());
            clearButton.Layout.Row = 4;
            deleteButton = uibutton(grid, "Text", "Delete selected", ...
                "Tag", "macd-inspector-date-list-delete", ...
                "ButtonPushedFcn", @(~, ~) deleteSelected());
            deleteButton.Layout.Row = 4;
            deleteButton.Layout.Column = 2;
            cancelButton = uibutton(grid, "Text", "Cancel", ...
                "Tag", "macd-inspector-date-list-cancel", ...
                "ButtonPushedFcn", @(~, ~) closeDialog());
            cancelButton.Layout.Row = 5;
            applyButton = uibutton(grid, "Text", "Apply", ...
                "Tag", "macd-inspector-date-list-apply", ...
                "ButtonPushedFcn", @(~, ~) applyDates());
            applyButton.Layout.Row = 5;
            applyButton.Layout.Column = 2;
            refreshList();
            if visible
                dialog.Visible = "on";
            end

            function addDate()
                % addDate Stage one picker date locally and retain canonical ordering.
                candidate = picker.Value;
                if isnat(candidate)
                    uialert(dialog, "Choose one calendar date before adding it.", "Invalid date");
                    return
                end
                dates = macd.ui.inspector.DateListEditorDialog.normalize([dates; candidate]);
                refreshList();
            end

            function deleteSelected()
                % deleteSelected Remove the selected draft dates without committing the property.
                selected = string(list.Value);
                if isempty(selected)
                    return
                end
                items = macd.ui.inspector.DateListEditorDialog.labels(dates);
                dates(ismember(items, selected)) = [];
                dates = reshape(dates, [], 1);
                refreshList();
            end

            function clearDates()
                % clearDates Stage the documented empty column vector until Apply.
                dates = datetime.empty(0, 1);
                refreshList();
            end

            function applyDates()
                % applyDates Commit the complete draft as one atomic property batch.
                transaction.stage(path, dates);
                message = commitFcn(transaction.changes());
                if strlength(message) > 0
                    uialert(dialog, message, "Invalid dates");
                    return
                end
                closeDialog();
            end

            function refreshList()
                % refreshList Synchronize only dialog controls from its private draft.
                list.Items = cellstr(macd.ui.inspector.DateListEditorDialog.labels(dates));
                list.Value = {};
            end

            function closeDialog()
                % closeDialog Dispose the modal dialog without committing an un-applied draft.
                if isvalid(dialog)
                    delete(dialog);
                end
            end
        end
    end

    methods (Static, Access = private)
        function value = normalize(value)
            % normalize Canonicalize a nonmissing date list as one sorted unique column vector.
            arguments (Input)
                value datetime
            end
            arguments (Output)
                value datetime
            end

            value = reshape(value, [], 1);
            value = value(~isnat(value));
            if isempty(value)
                value = datetime.empty(0, 1);
                return
            end
            value.TimeZone = "";
            value = dateshift(value, "start", "day");
            value = unique(value, "sorted");
        end

        function result = labels(value)
            % labels Render lossless date-only list labels for selection and deletion.
            arguments (Input)
                value datetime
            end
            arguments (Output)
                result string
            end

            result = string(value, "yyyy-MM-dd");
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

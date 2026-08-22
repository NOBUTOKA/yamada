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
                "WindowStyle", "modal", "Position", [300 300 360 330], ...
                "Tag", "macd-inspector-date-list-dialog");
            dialog.CloseRequestFcn = @(~, ~) closeDialog();
            grid = uigridlayout(dialog, [2 1], "Padding", [12 12 12 12], ...
                "RowHeight", {"1x", 32}, "RowSpacing", 8);
            listPanel = uipanel(grid, "BorderType", "line", ...
                "Tag", "macd-inspector-date-list-values");
            listPanel.Scrollable = "on";
            listPanel.AutoResizeChildren = "off";
            listPanel.SizeChangedFcn = @(~, ~) refreshRows();
            buttons = uigridlayout(grid, [1 2], "Padding", [0 0 0 0], ...
                "ColumnWidth", {90, "1x"}, "ColumnSpacing", 8);
            uibutton(buttons, "Text", "Clear", ...
                "Tag", "macd-inspector-date-list-clear", ...
                "ButtonPushedFcn", @(~, ~) clearDates());
            uibutton(buttons, "Text", "Apply", ...
                "Tag", "macd-inspector-date-list-apply", ...
                "ButtonPushedFcn", @(~, ~) applyDates());
            refreshRows();
            if visible
                dialog.Visible = "on";
            end

            function addDate()
                % addDate Insert one editable, nonduplicate calendar date into the local draft.
                candidate = macd.ui.inspector.DateListEditorDialog.nextSuggestedDate(dates);
                dates = macd.ui.inspector.DateListEditorDialog.normalize([dates; candidate]);
                refreshRows();
            end

            function deleteDate(source)
                % deleteDate Remove one draft row without changing the document.
                index = source.UserData;
                dates(index) = [];
                dates = reshape(dates, [], 1);
                refreshRows();
            end

            function changeDate(source)
                % changeDate Replace one draft date and retain the documented normalized order.
                index = source.UserData;
                candidate = source.Value;
                if isnat(candidate)
                    source.Value = dates(index);
                    return
                end
                dates(index) = candidate;
                dates = macd.ui.inspector.DateListEditorDialog.normalize(dates);
                refreshRows();
            end

            function clearDates()
                % clearDates Stage the documented empty column vector until Apply.
                dates = datetime.empty(0, 1);
                refreshRows();
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

            function refreshRows()
                % refreshRows Rebuild native date rows from the dialog-owned draft only.
                delete(listPanel.Children);
                panelPosition = getpixelposition(listPanel, true);
                rowCount = numel(dates) + 1;
                contentHeight = max(6 + 33 * rowCount, panelPosition(4) + 1);
                contentWidth = max(panelPosition(3) - 18, 1);
                content = uipanel(listPanel, "BorderType", "none", ...
                    "Position", [1 1 contentWidth contentHeight]);
                rows = uigridlayout(content, [rowCount 2], "Padding", [3 3 3 3], ...
                    "RowSpacing", 3, "ColumnSpacing", 6, ...
                    "ColumnWidth", {"1x", 30}, ...
                    "RowHeight", repmat({30}, 1, rowCount));
                for index = 1:numel(dates)
                    picker = uidatepicker(rows, "Value", dates(index), ...
                        "Tag", "macd-inspector-date-list-row-picker", ...
                        "ValueChangedFcn", @(source, ~) changeDate(source));
                    picker.UserData = index;
                    picker.Layout.Row = index;
                    remove = uibutton(rows, "Text", "−", "FontColor", [0.8 0 0], ...
                        "FontSize", 18, "FontWeight", "bold", ...
                        "Tag", "macd-inspector-date-list-delete", ...
                        "ButtonPushedFcn", @(source, ~) deleteDate(source));
                    remove.UserData = index;
                    remove.Layout.Row = index;
                    remove.Layout.Column = 2;
                end
                add = uibutton(rows, "Text", "+", "FontColor", [0 0.55 0], ...
                    "FontSize", 18, "FontWeight", "bold", ...
                    "Tag", "macd-inspector-date-list-add", ...
                    "ButtonPushedFcn", @(~, ~) addDate());
                add.Layout.Row = rowCount;
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

        function result = nextSuggestedDate(value)
            % nextSuggestedDate Choose a visible new date without duplicating the current draft.
            arguments (Input)
                value datetime
            end
            arguments (Output)
                result (1, 1) datetime
            end

            result = dateshift(datetime("today"), "start", "day");
            if ~isempty(value) && result <= value(end)
                result = value(end) + caldays(1);
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

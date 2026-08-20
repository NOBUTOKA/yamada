classdef DayOfWeekEditorDialog
    % DayOfWeekEditorDialog Edit a weekday-selection draft with readable English state buttons.
    %   The dialog retains its selection locally until Apply, allowing the narrow
    %   inspector to summarize the value without truncating weekday labels.

    methods (Static)
        function dialog = open(initialDays, path, commitFcn, visible)
            % open Create a modal weekday editor with one delayed commit.
            arguments (Input)
                initialDays double
                path (1, 1) string
                commitFcn (1, 1) function_handle
                visible (1, 1) logical = true
            end
            arguments (Output)
                dialog (1, 1) matlab.ui.Figure
            end

            initialDays = reshape(unique(initialDays), 1, []);
            transaction = macd.model.PropertyTransaction(path, {initialDays});
            dialog = uifigure("Name", "Edit disabled weekdays", "Visible", "off", ...
                "WindowStyle", "modal", "Position", [320 320 470 135], ...
                "Tag", "macd-inspector-day-of-week-dialog");
            dialog.CloseRequestFcn = @(~, ~) closeDialog();
            grid = uigridlayout(dialog, [2 1], "Padding", [12 12 12 12], ...
                "RowHeight", {34, 30}, "RowSpacing", 10);
            dayGrid = uigridlayout(grid, [1 7], "Padding", [0 0 0 0], ...
                "ColumnSpacing", 5, "ColumnWidth", repmat({"1x"}, 1, 7));
            names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
            buttons = matlab.ui.control.StateButton.empty;
            for dayIndex = 1:numel(names)
                buttons(end + 1) = uibutton(dayGrid, "state", "Text", names(dayIndex), ...
                    "FontWeight", "bold", "Tag", "macd-inspector-day-of-week-button"); %#ok<AGROW>
                buttons(end).Value = any(initialDays == dayIndex);
            end
            actions = uigridlayout(grid, [1 2], "Padding", [0 0 0 0], ...
                "ColumnWidth", {"1x", "1x"}, "ColumnSpacing", 8);
            uibutton(actions, "Text", "Cancel", ...
                "Tag", "macd-inspector-day-of-week-cancel", ...
                "ButtonPushedFcn", @(~, ~) closeDialog());
            uibutton(actions, "Text", "Apply", ...
                "Tag", "macd-inspector-day-of-week-apply", ...
                "ButtonPushedFcn", @(~, ~) applyDays());
            if visible
                dialog.Visible = "on";
            end

            function applyDays()
                % applyDays Commit all selected weekdays at once after local editing.
                selected = zeros(1, numel(buttons));
                count = 0;
                for buttonIndex = 1:numel(buttons)
                    if buttons(buttonIndex).Value
                        count = count + 1;
                        selected(count) = buttonIndex;
                    end
                end
                selected = selected(1:count);
                transaction.stage(path, selected);
                message = commitFcn(transaction.changes());
                if strlength(message) > 0
                    uialert(dialog, message, "Invalid weekdays");
                    return
                end
                closeDialog();
            end

            function closeDialog()
                % closeDialog Dispose the modal dialog without committing an unapplied draft.
                if isvalid(dialog)
                    delete(dialog);
                end
            end
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

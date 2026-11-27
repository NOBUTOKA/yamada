classdef DayOfWeekEditorDialog < yamada.ui.inspector.PropertyEditDialog
    % DayOfWeekEditorDialog Edit a weekday-selection draft with readable English state buttons.
    %   The editor keeps its selection in native state buttons until Apply, so the
    %   narrow Inspector can summarize the value without truncating weekday labels.
    %   PropertyEditDialog owns Apply, Cancel, and the commit.
    %
    %   Example:
    %       editor = yamada.ui.inspector.DayOfWeekEditorDialog([1 7], "DisabledDaysOfWeek");
    %       dialog = yamada.ui.inspector.PropertyEditDialog.show(editor, commitFcn);

    properties (Access = private)
        % Path - Property path that receives the weekday numbers.
        Path string = ""
        % InitialDays - Sorted unique weekday numbers shown as selected.
        InitialDays double = zeros(1, 0)
        % Buttons - One state button per weekday, Sunday first.
        Buttons matlab.ui.control.StateButton = matlab.ui.control.StateButton.empty
    end

    methods
        function obj = DayOfWeekEditorDialog(initialDays, path)
            % DayOfWeekEditorDialog Prepare a weekday draft for one property path.
            arguments (Input)
                initialDays double
                path (1, 1) string
            end
            arguments (Output)
                obj (1, 1) yamada.ui.inspector.DayOfWeekEditorDialog
            end

            initialDays = reshape(unique(initialDays), 1, []);
            spec = struct("Name", "Edit disabled weekdays", ...
                "Tag", "yamada-inspector-day-of-week-dialog", "Position", [320 320 470 135], ...
                "ContentHeight", 34, "AlertTitle", "Invalid weekdays", ...
                "ApplyTag", "yamada-inspector-day-of-week-apply", ...
                "CancelTag", "yamada-inspector-day-of-week-cancel");
            obj@yamada.ui.inspector.PropertyEditDialog(spec, ...
                yamada.model.PropertyTransaction(path, {initialDays}));
            obj.Path = path;
            obj.InitialDays = initialDays;
        end
    end

    methods (Access = protected)
        function buildContent(obj, content)
            % buildContent Create one readable English state button per weekday.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.DayOfWeekEditorDialog
                content (1, 1) matlab.ui.container.GridLayout
            end

            dayGrid = uigridlayout(content, [1 7], "Padding", [0 0 0 0], ...
                "ColumnSpacing", 5, "ColumnWidth", repmat({"1x"}, 1, 7));
            names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
            for dayIndex = 1:numel(names)
                obj.Buttons(end + 1) = uibutton(dayGrid, "state", "Text", names(dayIndex), ...
                    "FontWeight", "bold", "Tag", "yamada-inspector-day-of-week-button", ...
                    "Value", any(obj.InitialDays == dayIndex));
            end
        end

        function [transaction, message] = read(obj, transaction)
            % read Stage the selected weekday numbers for the single commit.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.DayOfWeekEditorDialog
                transaction (1, 1) yamada.model.PropertyTransaction
            end
            arguments (Output)
                transaction (1, 1) yamada.model.PropertyTransaction
                message (1, 1) string
            end

            transaction.stage(obj.Path, find([obj.Buttons.Value]));
            message = "";
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

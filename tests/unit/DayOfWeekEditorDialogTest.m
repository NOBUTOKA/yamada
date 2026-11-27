classdef (TestTags = {'dialog', 'inspector', 'ui'}) DayOfWeekEditorDialogTest < matlab.unittest.TestCase
    % DayOfWeekEditorDialogTest Verify weekday buttons are readable and submit day numbers.

    methods (Test)
        % Guarantee: weekday buttons show readable English names and submit the selected day numbers in order.
        % Failure mode: a label names the wrong day, or a toggled day is submitted as the wrong number.
        function statesSubmitSelectedDayNumbers(testCase)
            % statesSubmitSelectedDayNumbers Keep state edits local until Apply.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            setappdata(owner, "changes", struct.empty);
            dialog = yamada.ui.inspector.PropertyEditDialog.show(yamada.ui.inspector.DayOfWeekEditorDialog([1 3], ...
                "DisabledDaysOfWeek"), @(changes) captureChanges(owner, changes), false);
            buttons = findall(dialog, "Tag", "yamada-inspector-day-of-week-button");
            testCase.verifyEqual(sort(string({buttons([buttons.Value]).Text})), ["Sun", "Tue"]);
            monday = buttons(string({buttons.Text}) == "Mon");
            monday.Value = true;
            applyButton = findall(dialog, "Tag", "yamada-inspector-day-of-week-apply");
            applyButton.ButtonPushedFcn(applyButton, struct());

            changes = getappdata(owner, "changes");
            testCase.verifySize(changes, [1 1]);
            testCase.verifyEqual(changes.Path, "DisabledDaysOfWeek");
            testCase.verifyEqual(changes.Value, [1 2 3]);
            testCase.verifyFalse(isvalid(dialog));
            clear cleanup
        end

    end
end

function message = captureChanges(owner, changes)
% captureChanges Record one dialog-owned batch while reporting that it was accepted.
arguments (Input)
    owner (1, 1) matlab.ui.Figure
    changes (1, :) struct
end
arguments (Output)
    message (1, 1) string
end

setappdata(owner, "changes", changes);
message = "";
end

function deleteIfValid(value)
% deleteIfValid Delete one UI fixture when it remains valid.
arguments (Input)
    value
end

if ~isempty(value) && isvalid(value)
    delete(value);
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

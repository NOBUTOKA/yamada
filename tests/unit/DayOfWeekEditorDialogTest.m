classdef DayOfWeekEditorDialogTest < matlab.unittest.TestCase
    % DayOfWeekEditorDialogTest Verify weekday drafts are readable and delayed until Apply.

    methods (Test)
        function usesEnglishStateButtonsAndOneApplyCommit(testCase)
            % usesEnglishStateButtonsAndOneApplyCommit Keep state edits local until Apply.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            setappdata(owner, "changes", struct.empty);
            dialog = macd.ui.inspector.DayOfWeekEditorDialog.open([1 3], ...
                "DisabledDaysOfWeek", @(changes) captureChanges(owner, changes), false);
            buttons = findall(dialog, "Tag", "macd-inspector-day-of-week-button");
            testCase.verifyEqual(sort(string({buttons.Text})), ...
                ["Fri", "Mon", "Sat", "Sun", "Thu", "Tue", "Wed"]);
            testCase.verifyEqual(sort(string({buttons([buttons.Value]).Text})), ["Sun", "Tue"]);
            monday = buttons(string({buttons.Text}) == "Mon");
            monday.Value = true;
            applyButton = findall(dialog, "Tag", "macd-inspector-day-of-week-apply");
            applyButton.ButtonPushedFcn(applyButton, struct());

            changes = getappdata(owner, "changes");
            testCase.verifySize(changes, [1 1]);
            testCase.verifyEqual(changes.Path, "DisabledDaysOfWeek");
            testCase.verifyEqual(changes.Value, [1 2 3]);
            testCase.verifyFalse(isvalid(dialog));
            clear cleanup
        end

        function cancelDiscardsWeekdayDraft(testCase)
            % cancelDiscardsWeekdayDraft Close without applying any edited state.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            setappdata(owner, "changes", struct.empty);
            dialog = macd.ui.inspector.DayOfWeekEditorDialog.open([], "DisabledDaysOfWeek", ...
                @(changes) captureChanges(owner, changes), false);
            dialog.CloseRequestFcn(dialog, struct());

            testCase.verifyEmpty(getappdata(owner, "changes"));
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

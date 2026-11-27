classdef (TestTags = {'dialog', 'inspector', 'ui'}) DateListEditorDialogTest < matlab.unittest.TestCase
    % DateListEditorDialogTest Verify date-list row actions produce the submitted date column.
    %   These tests construct the dialog hidden and invoke its bound callbacks,
    %   without opening a visible application window.

    methods (Test)
        % Guarantee: Add, Delete, Clear, and date edits produce the normalized date column that Apply submits.
        % Failure mode: a row action edits the wrong row, Clear leaves stale rows, or the submitted value is not the edited list.
        function rowActionsProduceTheSubmittedDateList(testCase)
            % rowActionsProduceTheSubmittedDateList Keep date-list edits local until Apply.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            setappdata(owner, "changes", struct.empty);
            dialog = yamada.ui.inspector.PropertyEditDialog.show(yamada.ui.inspector.DateListEditorDialog( ...
                [datetime(2024, 3, 1); datetime(2024, 3, 2)], "DisabledDates"), ...
                @(changes) captureChanges(owner, changes), false);
            clearButton = findall(dialog, "Tag", "yamada-inspector-date-list-clear");
            applyButton = findall(dialog, "Tag", "yamada-inspector-date-list-apply");

            testCase.verifyEmpty(getappdata(owner, "changes"));
            pickers = findall(dialog, "Tag", "yamada-inspector-date-list-row-picker");
            testCase.verifyEqual(numel(pickers), 2);
            deleteButtons = findall(dialog, "Tag", "yamada-inspector-date-list-delete");
            deleteButton = deleteButtons([deleteButtons.UserData] == 1);
            deleteButton.ButtonPushedFcn(deleteButton, struct());
            pickers = findall(dialog, "Tag", "yamada-inspector-date-list-row-picker");
            testCase.verifyEqual(numel(pickers), 1);
            testCase.verifyEqual(pickers.Value, datetime(2024, 3, 2));
            clearButton.ButtonPushedFcn(clearButton, struct());
            testCase.verifyEmpty(findall(dialog, "Tag", "yamada-inspector-date-list-row-picker"));
            addButton = findall(dialog, "Tag", "yamada-inspector-date-list-add");
            addButton.ButtonPushedFcn(addButton, struct());
            picker = findall(dialog, "Tag", "yamada-inspector-date-list-row-picker");
            expected = datetime(2024, 3, 3);
            picker.Value = expected;
            picker.ValueChangedFcn(picker, struct());
            applyButton.ButtonPushedFcn(applyButton, struct());

            changes = getappdata(owner, "changes");
            testCase.verifySize(changes, [1 1]);
            testCase.verifyEqual(changes.Path, "DisabledDates");
            testCase.verifyEqual(changes.Value, expected);
            testCase.verifyFalse(isvalid(dialog));
            clear cleanup
        end

    end
end

function message = captureChanges(owner, changes)
% captureChanges Record one dialog commit while reporting it accepted.
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

classdef DateListEditorDialogTest < matlab.unittest.TestCase
    % DateListEditorDialogTest Verify disabled-date drafts use one delayed atomic commit.
    %   These tests construct the dialog hidden and invoke its bound callbacks,
    %   without opening a visible application window.

    methods (Test)
        function addDeleteClearAndApplyUseOneDraftCommit(testCase)
            % addDeleteClearAndApplyUseOneDraftCommit Keep date-list edits local until Apply.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            setappdata(owner, "changes", struct.empty);
            dialog = macd.ui.inspector.DateListEditorDialog.open( ...
                datetime.empty(0, 1), "DisabledDates", ...
                @(changes) captureChanges(owner, changes), false);
            picker = findall(dialog, "Tag", "macd-inspector-date-list-picker");
            addButton = findall(dialog, "Tag", "macd-inspector-date-list-add");
            list = findall(dialog, "Tag", "macd-inspector-date-list-values");
            deleteButton = findall(dialog, "Tag", "macd-inspector-date-list-delete");
            clearButton = findall(dialog, "Tag", "macd-inspector-date-list-clear");
            applyButton = findall(dialog, "Tag", "macd-inspector-date-list-apply");

            picker.Value = datetime(2024, 3, 2);
            addButton.ButtonPushedFcn(addButton, struct());
            picker.Value = datetime(2024, 3, 1);
            addButton.ButtonPushedFcn(addButton, struct());
            testCase.verifyEmpty(getappdata(owner, "changes"));
            testCase.verifyEqual(string(list.Items), ["2024-03-01", "2024-03-02"]);
            list.Value = '2024-03-01';
            deleteButton.ButtonPushedFcn(deleteButton, struct());
            testCase.verifyEqual(string(list.Items), "2024-03-02");
            clearButton.ButtonPushedFcn(clearButton, struct());
            testCase.verifyEmpty(list.Items);
            picker.Value = datetime(2024, 3, 3);
            addButton.ButtonPushedFcn(addButton, struct());
            applyButton.ButtonPushedFcn(applyButton, struct());

            changes = getappdata(owner, "changes");
            testCase.verifySize(changes, [1 1]);
            testCase.verifyEqual(changes.Path, "DisabledDates");
            testCase.verifyEqual(changes.Value, datetime(2024, 3, 3));
            testCase.verifyFalse(isvalid(dialog));
            clear cleanup
        end

        function cancelDiscardsDateListDraft(testCase)
            % cancelDiscardsDateListDraft Confirm added dates do not commit when the dialog closes.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            setappdata(owner, "changes", struct.empty);
            dialog = macd.ui.inspector.DateListEditorDialog.open( ...
                datetime.empty(0, 1), "DisabledDates", ...
                @(changes) captureChanges(owner, changes), false);
            picker = findall(dialog, "Tag", "macd-inspector-date-list-picker");
            addButton = findall(dialog, "Tag", "macd-inspector-date-list-add");
            cancelButton = findall(dialog, "Tag", "macd-inspector-date-list-cancel");
            picker.Value = datetime(2024, 3, 1);
            addButton.ButtonPushedFcn(addButton, struct());
            cancelButton.ButtonPushedFcn(cancelButton, struct());

            testCase.verifyEmpty(getappdata(owner, "changes"));
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

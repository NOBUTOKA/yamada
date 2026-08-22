classdef ColumnSettingsEditorDialogTest < matlab.unittest.TestCase
    % ColumnSettingsEditorDialogTest Verify staged UITable column-setting edits.

    methods (Test)
        function stagesPerColumnSettingsAsOneBatch(testCase)
            % stagesPerColumnSettingsAsOneBatch Preserve the complete candidate until Apply.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            setappdata(owner, "changes", struct.empty);
            state = makeState();
            dialog = macd.ui.inspector.ColumnSettingsEditorDialog.open( ...
                state, @(changes) captureChanges(owner, changes), false);
            table = findall(dialog, "Tag", "macd-column-settings-table");
            oneX = findall(dialog, "Tag", "macd-column-settings-all-1x");
            oneX.ButtonPushedFcn(oneX, struct());
            testCase.verifyTrue(all(strcmp(table.Data(:, 4), '1x')));
            table.Data{1, 4} = 'fit';
            table.Data{1, 2} = true;
            table.Data{1, 3} = true;
            table.Data{1, 5} = '''bank''';
            rearrangeable = findall(dialog, "Tag", "macd-column-settings-rearrangeable");
            rearrangeable.Value = true;
            apply = findall(dialog, "Tag", "macd-column-settings-apply");
            apply.ButtonPushedFcn(apply, struct());

            changes = getappdata(owner, "changes");
            testCase.verifyEqual(string({changes.Path}), ...
                ["ColumnWidth", "ColumnEditable", "ColumnRearrangeable", "ColumnSortable", "ColumnFormat"]);
            testCase.verifyEqual(changes(1).Value, {'fit', '1x'});
            testCase.verifyEqual(changes(2).Value, [true false]);
            testCase.verifyTrue(changes(3).Value);
            testCase.verifyEqual(changes(4).Value, [true false]);
            testCase.verifyEqual(changes(5).Value, {'bank', []});
            testCase.verifyFalse(isvalid(dialog));
            clear cleanup
        end

        function rejectsInvalidWidthWithoutSubmitting(testCase)
            % rejectsInvalidWidthWithoutSubmitting Keep malformed width text local to the dialog.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            setappdata(owner, "changes", struct.empty);
            dialog = macd.ui.inspector.ColumnSettingsEditorDialog.open( ...
                makeState(), @(changes) captureChanges(owner, changes), false);
            table = findall(dialog, "Tag", "macd-column-settings-table");
            table.Data{1, 4} = 'wide';
            apply = findall(dialog, "Tag", "macd-column-settings-apply");
            apply.ButtonPushedFcn(apply, struct());

            testCase.verifyEmpty(getappdata(owner, "changes"));
            testCase.verifyTrue(isvalid(dialog));
            deleteIfValid(dialog);
            clear cleanup
        end

        function showsWidthKeywordsWithoutQuotesAndAcceptsNoOp(testCase)
            % showsWidthKeywordsWithoutQuotesAndAcceptsNoOp Keep documented width tokens editable.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            setappdata(owner, "changes", struct.empty);
            state = makeState();
            state.ColumnWidth = {'1x', '1x'};
            dialog = macd.ui.inspector.ColumnSettingsEditorDialog.open( ...
                state, @(changes) captureChanges(owner, changes), false);
            table = findall(dialog, "Tag", "macd-column-settings-table");
            testCase.verifyEqual(string(table.Data(:, 4)), ["1x"; "1x"]);
            auto = findall(dialog, "Tag", "macd-column-settings-all-auto");
            auto.ButtonPushedFcn(auto, struct());
            apply = findall(dialog, "Tag", "macd-column-settings-apply");
            apply.ButtonPushedFcn(apply, struct());

            changes = getappdata(owner, "changes");
            testCase.verifyEqual(changes.Path, "ColumnWidth");
            testCase.verifyEqual(changes.Value, {'auto', 'auto'});
            state.ColumnWidth = changes.Value;
            setappdata(owner, "changes", struct.empty);
            dialog = macd.ui.inspector.ColumnSettingsEditorDialog.open( ...
                state, @(nextChanges) captureChanges(owner, nextChanges), false);
            table = findall(dialog, "Tag", "macd-column-settings-table");
            testCase.verifyEqual(string(table.Data(:, 4)), ["auto"; "auto"]);
            auto = findall(dialog, "Tag", "macd-column-settings-all-auto");
            auto.ButtonPushedFcn(auto, struct());
            apply = findall(dialog, "Tag", "macd-column-settings-apply");
            apply.ButtonPushedFcn(apply, struct());

            testCase.verifyEmpty(getappdata(owner, "changes"));
            testCase.verifyFalse(isvalid(dialog));
            clear cleanup
        end

        function usesTheRequestedColumnOrderAndActionLayout(testCase)
            % usesTheRequestedColumnOrderAndActionLayout Keep action controls aligned with settings columns.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            dialog = macd.ui.inspector.ColumnSettingsEditorDialog.open( ...
                makeState(), @(changes) captureChanges(owner, changes), false);
            table = findall(dialog, "Tag", "macd-column-settings-table");
            testCase.verifyEqual(string(table.ColumnName).', ...
                ["Column", "Editable", "Sortable", "Width", "Format"]);
            allEditable = findall(dialog, "Tag", "macd-column-settings-all-editable");
            noEditable = findall(dialog, "Tag", "macd-column-settings-no-editable");
            allSortable = findall(dialog, "Tag", "macd-column-settings-all-sortable");
            noSortable = findall(dialog, "Tag", "macd-column-settings-no-sortable");
            auto = findall(dialog, "Tag", "macd-column-settings-all-auto");
            fit = findall(dialog, "Tag", "macd-column-settings-all-fit");
            oneX = findall(dialog, "Tag", "macd-column-settings-all-1x");
            testCase.verifyEqual([allEditable.Layout.Row, noEditable.Layout.Row], [3 4]);
            testCase.verifyEqual([allSortable.Layout.Row, noSortable.Layout.Row], [3 4]);
            testCase.verifyEqual([auto.Layout.Row, fit.Layout.Row, oneX.Layout.Row], [3 3 3]);
            testCase.verifyEqual([auto.Layout.Column, fit.Layout.Column, oneX.Layout.Column], [3 4 5]);
            deleteIfValid(dialog);
            clear cleanup
        end
    end
end

function state = makeState()
% makeState Return a two-column supported table settings fixture.
state = struct();
state.Data = [1 2];
state.ColumnName = {'First', 'Second'};
state.ColumnWidth = 'auto';
state.ColumnEditable = false(1, 0);
state.ColumnRearrangeable = false;
state.ColumnSortable = false(1, 0);
state.ColumnFormat = cell(1, 0);
end

function message = captureChanges(owner, changes)
% captureChanges Record one accepted atomic batch for test assertions.
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
% deleteIfValid Delete one remaining hidden UI fixture.
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

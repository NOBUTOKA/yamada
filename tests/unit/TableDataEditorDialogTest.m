classdef TableDataEditorDialogTest < matlab.unittest.TestCase
    % TableDataEditorDialogTest Verify typed table drafts use nearby structural actions and one batch.

    methods (Test)
        function addDeleteAndApplyCommitOneTableBatch(testCase)
            % addDeleteAndApplyCommitOneTableBatch Retain all row and column edits until Apply.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            setappdata(owner, "changes", struct.empty);
            state = struct("Data", {num2cell([1 2; 3 4])}, ...
                "ColumnName", {{'First', 'Second'}}, "RowName", {{'One', 'Two'}}, ...
                "HasData", true, "HasColumnName", true, "HasRowName", true);
            dialog = macd.ui.inspector.TableDataEditorDialog.open( ...
                state, @(changes) captureChanges(owner, changes), false);
            deleteRows = findall(dialog, "Tag", "macd-table-data-delete-row");
            deleteRow = deleteRows([deleteRows.UserData] == 1);
            deleteRow.ButtonPushedFcn(deleteRow, struct());
            addRow = findall(dialog, "Tag", "macd-table-data-add-row");
            addRow.ButtonPushedFcn(addRow, struct());
            deleteColumns = findall(dialog, "Tag", "macd-table-data-delete-column");
            deleteColumn = deleteColumns([deleteColumns.UserData] == 1);
            deleteColumn.ButtonPushedFcn(deleteColumn, struct());
            addColumn = findall(dialog, "Tag", "macd-table-data-add-column");
            addColumn.ButtonPushedFcn(addColumn, struct());
            table = findall(dialog, "Tag", "macd-table-data-editor-table");
            table.Data(2:3, 2:3) = ["true", """Updated"""; "1", "'last'"];
            applyButton = findall(dialog, "Tag", "macd-table-data-apply");
            applyButton.ButtonPushedFcn(applyButton, struct());

            changes = getappdata(owner, "changes");
            testCase.verifyEqual(string({changes.Path}), ["Data", "ColumnName", "RowName"]);
            data = changes([changes.Path] == "Data").Value;
            testCase.verifyEqual(data, {true, "Updated"; 1, 'last'});
            testCase.verifyFalse(isvalid(dialog));
            clear cleanup
        end

        function presentsNamesInsideTheGrayLeadingTableCells(testCase)
            % presentsNamesInsideTheGrayLeadingTableCells Avoid standalone header edit fields.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            state = struct("Data", {num2cell([1 2])}, "ColumnName", "numbered", ...
                "RowName", "numbered", "HasData", true, ...
                "HasColumnName", true, "HasRowName", true);
            dialog = macd.ui.inspector.TableDataEditorDialog.open( ...
                state, @(~) "", false);
            table = findall(dialog, "Tag", "macd-table-data-editor-table");

            testCase.verifyEmpty(table.ColumnName);
            testCase.verifyEmpty(table.RowName);
            testCase.verifyEqual(size(table.Data), [2 3]);
            testCase.verifyTrue(all(table.Data(1, :) == ""));
            testCase.verifyTrue(all(table.Data(:, 1) == ""));
            testCase.verifyEmpty(findall(dialog, "Tag", "macd-table-data-column-name"));
            testCase.verifyEmpty(findall(dialog, "Tag", "macd-table-data-row-name"));
            clear cleanup
        end

        function appliesNamesEditedInTheLeadingTableCells(testCase)
            % appliesNamesEditedInTheLeadingTableCells Commit first-row and first-column names with the data body.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            setappdata(owner, "changes", struct.empty);
            state = struct("Data", 1, "ColumnName", "numbered", "RowName", "numbered", ...
                "HasData", true, "HasColumnName", true, "HasRowName", true);
            dialog = macd.ui.inspector.TableDataEditorDialog.open( ...
                state, @(changes) captureChanges(owner, changes), false);
            table = findall(dialog, "Tag", "macd-table-data-editor-table");
            table.Data(1, 2) = "Amount";
            table.Data(2, 1) = "Total";
            table.Data(2, 2) = "3";
            applyButton = findall(dialog, "Tag", "macd-table-data-apply");
            applyButton.ButtonPushedFcn(applyButton, struct());

            changes = getappdata(owner, "changes");
            testCase.verifyEqual(changes([changes.Path] == "Data").Value, 3);
            testCase.verifyEqual(changes([changes.Path] == "ColumnName").Value, {'Amount'});
            testCase.verifyEqual(changes([changes.Path] == "RowName").Value, {'Total'});
            clear cleanup
        end

        function clearStagesEmptyTableSurfacesUntilApply(testCase)
            % clearStagesEmptyTableSurfacesUntilApply Keep Clear local until the complete table batch applies.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            setappdata(owner, "changes", struct.empty);
            state = struct("Data", {num2cell([1 2])}, "ColumnName", {{'A', 'B'}}, ...
                "RowName", {{'One'}}, "HasData", true, "HasColumnName", true, "HasRowName", true);
            dialog = macd.ui.inspector.TableDataEditorDialog.open( ...
                state, @(changes) captureChanges(owner, changes), false);
            clearButton = findall(dialog, "Tag", "macd-table-data-clear");
            clearButton.ButtonPushedFcn(clearButton, struct());

            testCase.verifyEmpty(getappdata(owner, "changes"));
            applyButton = findall(dialog, "Tag", "macd-table-data-apply");
            applyButton.ButtonPushedFcn(applyButton, struct());
            changes = getappdata(owner, "changes");
            testCase.verifyEqual(string({changes.Path}), ["Data", "ColumnName", "RowName"]);
            testCase.verifyEmpty(changes([changes.Path] == "Data").Value);
            testCase.verifyEmpty(changes([changes.Path] == "ColumnName").Value);
            testCase.verifyEmpty(changes([changes.Path] == "RowName").Value);
            clear cleanup
        end

        function rejectsUnsupportedTableData(testCase)
            % rejectsUnsupportedTableData Defer table-class values instead of coercing them through the UI.

            state = struct("Data", table([1; 2]), "ColumnName", [], "RowName", [], ...
                "HasData", true, "HasColumnName", false, "HasRowName", false);
            testCase.verifyError(@() macd.ui.inspector.TableDataEditorDialog.open( ...
                state, @(~) "", false), "macd:TableDataEditorDialog:UnsupportedData");
        end
    end
end

function message = captureChanges(owner, changes)
% captureChanges Record one table dialog batch while reporting it was accepted.
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
% deleteIfValid Delete one hidden UI fixture when it remains valid.
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

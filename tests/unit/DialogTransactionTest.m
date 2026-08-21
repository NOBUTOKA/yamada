classdef DialogTransactionTest < matlab.unittest.TestCase
    % DialogTransactionTest Verify existing modal editors use staged property batches.
    %   These tests construct hidden native dialogs, invoke their owned callbacks,
    %   and prove that Apply alone emits one typed batch. They do not inspect a
    %   visible application window or execute generated app source.

    methods (Test)
        function itemsDataClearStagesUntilApply(testCase)
            % itemsDataClearStagesUntilApply Keep Clear local until the user applies it.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            macd.ui.inspector.ItemsDataEditorDialog.open( ...
                ["One", "Two"], [1 2], "ItemsData", ...
                @(changes) captureBatch(owner, changes));
            dialog = dialogByName("Edit item data");
            dialog.Visible = "off";
            buttons = findall(dialog, "Type", "uibutton");
            clearButton = buttons(string({buttons.Text}) == "Clear");
            applyButton = buttons(string({buttons.Text}) == "Apply");
            clearButton.ButtonPushedFcn(clearButton, struct());

            testCase.verifyFalse(isappdata(owner, "batch"));
            table = findall(dialog, "Type", "uitable");
            testCase.verifyTrue(all(string(table.Data(:, 2)) == ""));
            applyButton.ButtonPushedFcn(applyButton, struct());
            changes = getappdata(owner, "batch");
            testCase.verifyEqual(changes.Path, "ItemsData");
            testCase.verifyEmpty(changes.Value);
            testCase.verifyFalse(isvalid(dialog));
            clear cleanup
        end

        function compositeItemsDialogStagesBothProperties(testCase)
            % compositeItemsDialogStagesBothProperties Commit paired labels and data as one batch.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            state = struct();
            state.Items = ["One", "Two"];
            state.ItemsData = [1 2];
            macd.ui.inspector.ItemsDataEditorDialog.openComposite( ...
                state, @(changes) captureBatch(owner, changes), false);
            dialog = findall(0, "Tag", "macd-items-editor-dialog");
            table = findall(dialog, "Tag", "macd-items-editor-table");
            table.Data(1, 1) = "Updated";
            table.Data(1, 2) = "5";
            apply = findall(dialog, "Tag", "macd-items-editor-apply");
            apply.ButtonPushedFcn(apply, struct());

            changes = getappdata(owner, "batch");
            testCase.verifyEqual(string({changes.Path}), ["Items", "ItemsData"]);
            testCase.verifyEqual(changes(1).Value, ["Updated", "Two"]);
            testCase.verifyEqual(changes(2).Value, [5 2]);
            testCase.verifyFalse(isvalid(dialog));
            clear cleanup
        end

        function structuredDataApplyEmitsOneTypedBatch(testCase)
            % structuredDataApplyEmitsOneTypedBatch Route a finite literal through the shared transaction.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            macd.ui.inspector.StructuredDataEditorDialog.open([1 2], "NodeData", ...
                @(changes) captureBatch(owner, changes));
            dialog = dialogByName("Edit data");
            dialog.Visible = "off";
            area = findall(dialog, "Type", "uitextarea");
            area.Value = {'[3 4]'};
            buttons = findall(dialog, "Type", "uibutton");
            applyButton = buttons(string({buttons.Text}) == "Apply");
            applyButton.ButtonPushedFcn(applyButton, struct());

            changes = getappdata(owner, "batch");
            testCase.verifyEqual(changes.Path, "NodeData");
            testCase.verifyEqual(changes.Value, [3 4]);
            testCase.verifyFalse(isvalid(dialog));
            clear cleanup
        end

        function stringListCancelEmitsNoBatch(testCase)
            % stringListCancelEmitsNoBatch Discard local text when the dialog is cancelled.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            macd.ui.inspector.StringListEditorDialog.open(["One", "Two"], "Items", ...
                @(changes) captureBatch(owner, changes));
            dialog = dialogByName("Edit list");
            dialog.Visible = "off";
            buttons = findall(dialog, "Type", "uibutton");
            cancelButton = buttons(string({buttons.Text}) == "Cancel");
            cancelButton.ButtonPushedFcn(cancelButton, struct());

            testCase.verifyFalse(isappdata(owner, "batch"));
            testCase.verifyFalse(isvalid(dialog));
            clear cleanup
        end
    end
end

function dialog = dialogByName(name)
% dialogByName Return exactly one current native dialog with the requested title.
arguments (Input)
    name (1, 1) string
end
arguments (Output)
    dialog (1, 1) matlab.ui.Figure
end

drawnow;
dialogs = findall(0, "Type", "figure", "Name", name);
assert(isscalar(dialogs), "macd:DialogTransactionTest:MissingDialog", ...
    "Expected one dialog named ""%s"".", name);
dialog = dialogs;
end

function message = captureBatch(owner, changes)
% captureBatch Retain one emitted batch for a focused dialog interaction test.
arguments (Input)
    owner (1, 1) matlab.ui.Figure
    changes (1, :) struct
end
arguments (Output)
    message (1, 1) string
end

setappdata(owner, "batch", changes);
message = "";
end

function deleteIfValid(value)
% deleteIfValid Delete one owned test UI fixture when it remains valid.
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

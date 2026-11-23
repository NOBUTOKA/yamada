classdef EditorTypedPropertyInteractionTest < matlab.unittest.TestCase
    % EditorTypedPropertyInteractionTest Verify typed edits through the Inspector.

    methods (Test, TestTags = {'inspector', 'ui'})
        % Guarantee: typed Inspector editors commit native values unchanged, as one atomic change per property group.
        % Failure mode: a datetime or table value is round-tripped through text and loses its type, or one Limits bound commits alone.
        function datePickerValueCommitPreservesTypedDate(testCase)
            % datePickerValueCommitPreservesTypedDate Keep native datetime data out of text parsing.

            % Insert a Date Picker, then invoke the native date editor callback.
            app = yamada(Visible="off");
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Date Picker", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            labels = findall(figure, "Type", "uilabel", ...
                "Tag", "yamada-inspector-property-label");
            label = labels(string({labels.Text}) == "Value");
            editor = findall(label.Parent, "Tag", "yamada-inspector-date-picker-editor");
            selected = datetime(2024, 2, 29);
            editor.Value = selected;
            editor.ValueChangedFcn(editor, struct());
            drawnow;

            component = app.Document.getComponent(app.SelectedComponentId);
            entry = component.getProperty("Value");
            testCase.verifyClass(entry.LiteralValue, "datetime");
            testCase.verifyEqual(entry.LiteralValue, selected);
            clear cleanup
        end

        function datePickerLimitsCommitBothBoundsAtomically(testCase)
            % datePickerLimitsCommitBothBoundsAtomically Reject a partial invalid range without mutation.

            app = yamada(Visible="off");
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Date Picker", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            limitsEditor = findall(figure, "Tag", "yamada-inspector-date-limits-editor");
            editorPosition = getpixelposition(limitsEditor, true);
            testCase.verifyGreaterThanOrEqual(editorPosition(4), 56);
            parts = limitsEditor.UserData;
            parts.Start.Value = datetime(2024, 12, 31);
            parts.End.Value = datetime(2024, 1, 1);
            parts.Start.ValueChangedFcn(parts.Start, struct());
            component = app.Document.getComponent(app.SelectedComponentId);
            testCase.verifyEmpty(component.getProperty("Limits"));
            parts.Start.Value = datetime(2024, 1, 1);
            parts.End.Value = datetime(2024, 12, 31);
            parts.End.ValueChangedFcn(parts.End, struct());
            entry = component.getProperty("Limits");
            testCase.verifyEqual(entry.LiteralValue, ...
                [datetime(2024, 1, 1) datetime(2024, 12, 31)]);
            clear cleanup
        end

        % Guarantee: the date picker rows stay complete and reflect related restrictions after edits.
        % Failure mode: the calendar keeps stale disabled dates, or an audited row is missing from the Inspector.
        function datePickerValueEditorSynchronizesEffectiveRestrictions(testCase)
            % datePickerValueEditorSynchronizesEffectiveRestrictions Refresh the native calendar after a related inspector edit.

            app = yamada(Visible="off");
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Date Picker", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            limits = [datetime(2024, 1, 1) datetime(2024, 12, 31)];
            limitsEditor = findall(figure, "Tag", "yamada-inspector-date-limits-editor");
            parts = limitsEditor.UserData;
            parts.Start.Value = limits(1);
            parts.End.Value = limits(2);
            parts.End.ValueChangedFcn(parts.End, struct());
            drawnow;

            editor = findall(figure, "Tag", "yamada-inspector-date-picker-editor");
            testCase.verifyEqual(editor.Limits, limits);
            clear cleanup
        end

        function datePickerInspectorRetainsItsCompleteEditableSurface(testCase)
            % datePickerInspectorRetainsItsCompleteEditableSurface Keep all audited Date Picker rows visible.

            app = yamada(Visible="off");
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Date Picker", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            labels = findall(figure, "Type", "uilabel", ...
                "Tag", "yamada-inspector-property-label");
            actual = string({labels.Text});
            expected = ["Value", "Placeholder", "Limits", "DisplayFormat", ...
                "DisabledDates", "DisabledDaysOfWeek", "FontName", "FontSize", ...
                "Font Style", "FontColor", "BackgroundColor", "Visible", "Editable", ...
                "Enable", "Tooltip", "ContextMenu", "Position", "Interruptible", "BusyAction"];
            testCase.verifyTrue(all(ismember(expected, actual)));

            % Unaudited defaults still initialize editable date and weekday dialogs.
            dates = findall(figure, "Tag", "yamada-inspector-date-list-editor");
            days = findall(figure, "Tag", "yamada-inspector-day-of-week-editor");
            testCase.verifyEqual(string(dates.Enable), "on");
            testCase.verifyClass(dates.UserData, "datetime");
            testCase.verifyEqual(string(days.Enable), "on");
            days.ButtonPushedFcn(days, struct());
            dialog = findall(0, "Tag", "yamada-inspector-day-of-week-dialog");
            testCase.addTeardown(@() deleteIfValid(dialog));
            buttons = findall(dialog, "Tag", "yamada-inspector-day-of-week-button");
            sunday = buttons(string({buttons.Text}) == "Sun");
            sunday.Value = true;
            apply = findall(dialog, "Tag", "yamada-inspector-day-of-week-apply");
            apply.ButtonPushedFcn(apply, struct());
            component = app.Document.getComponent(app.SelectedComponentId);
            testCase.verifyEqual(component.getProperty("DisabledDaysOfWeek").LiteralValue, 1);

            % Commit a date through the same live Inspector and related calendar state.
            dates = findall(figure, "Tag", "yamada-inspector-date-list-editor");
            dates.ButtonPushedFcn(dates, struct());
            dialog = findall(0, "Tag", "yamada-inspector-date-list-dialog");
            testCase.addTeardown(@() deleteIfValid(dialog));
            add = findall(dialog, "Tag", "yamada-inspector-date-list-add");
            add.ButtonPushedFcn(add, struct());
            picker = findall(dialog, "Tag", "yamada-inspector-date-list-row-picker");
            selected = datetime(2026, 10, 17);
            picker.Value = selected;
            picker.ValueChangedFcn(picker, struct());
            apply = findall(dialog, "Tag", "yamada-inspector-date-list-apply");
            apply.ButtonPushedFcn(apply, struct());
            testCase.verifyEqual(component.getProperty("DisabledDates").LiteralValue, selected);
            editor = findall(figure, "Tag", "yamada-inspector-date-picker-editor");
            testCase.verifyEqual(editor.DisabledDates, selected);
            testCase.verifyEqual(editor.DisabledDaysOfWeek, 1);
            clear cleanup
        end

        function tableDataDialogCommitsTypedDataFromTheInspector(testCase)
            % tableDataDialogCommitsTypedDataFromTheInspector Apply one typed table draft through the real row binding.
            % Guarantee and failure mode: shared with datePickerValueCommitPreservesTypedDate.

            app = yamada(Visible="off");
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Table", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            labels = findall(figure, "Type", "uilabel", ...
                "Tag", "yamada-inspector-property-label");
            dataLabel = labels(string({labels.Text}) == "Data & Names");
            editor = findall(dataLabel.Parent, "Tag", "yamada-inspector-table-data-editor");
            editor.ButtonPushedFcn(editor, struct());
            dialog = findall(0, "Tag", "yamada-inspector-table-data-dialog");
            addColumn = findall(dialog, "Tag", "yamada-table-data-add-column");
            addColumn.ButtonPushedFcn(addColumn, struct());
            addRow = findall(dialog, "Tag", "yamada-table-data-add-row");
            addRow.ButtonPushedFcn(addRow, struct());
            table = findall(dialog, "Tag", "yamada-table-data-editor-table");
            bodyRows = size(table.Data, 1) - 1;
            bodyColumns = size(table.Data, 2) - 1;
            expected = reshape(1:bodyRows * bodyColumns, bodyRows, bodyColumns);
            dataType = findall(dialog, "Tag", "yamada-table-data-type");
            dataType.Value = "numeric";
            dataType.ValueChangedFcn(dataType, struct());
            table.Data(2:end, 2:end) = string(expected);
            applyButton = findall(dialog, "Tag", "yamada-table-data-apply");
            applyButton.ButtonPushedFcn(applyButton, struct());
            drawnow;

            component = app.Document.getComponent(app.SelectedComponentId);
            entry = component.getProperty("Data");
            testCase.verifyEqual(entry.LiteralValue, expected);
            columnEditors = findall(figure, "Tag", "yamada-inspector-column-settings-editor");
            columnEditor = columnEditors(arrayfun(@(candidate) isa(candidate, ...
                "matlab.ui.control.Button") && isvalid(candidate), columnEditors));
            testCase.verifyEqual(numel(columnEditor), 1);
            columnEditor.ButtonPushedFcn(columnEditor, struct());
            columnDialog = findall(0, "Tag", "yamada-column-settings-dialog");
            columnTable = findall(columnDialog, "Tag", "yamada-column-settings-table");
            columnTable.Data{1, 2} = true;
            columnTable.Data{1, 3} = true;
            columnTable.Data{1, 4} = 'fit';
            columnTable.Data{1, 5} = '''bank''';
            columnApply = findall(columnDialog, "Tag", "yamada-column-settings-apply");
            columnApply.ButtonPushedFcn(columnApply, struct());
            drawnow;
            component = app.Document.getComponent(app.SelectedComponentId);
            testCase.verifyEqual(component.getProperty("ColumnWidth").LiteralValue, 'fit');
            testCase.verifyTrue(component.getProperty("ColumnEditable").LiteralValue);
            testCase.verifyTrue(component.getProperty("ColumnSortable").LiteralValue);
            testCase.verifyEqual(component.getProperty("ColumnFormat").LiteralValue, {'bank'});
            clear cleanup
        end
    end
end

function deleteIfValid(value)
% deleteIfValid Delete an editor fixture when it remains valid.
arguments (Input)
    value
end

% Keep cleanup safe if an assertion or UI construction fails midway.
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

classdef (TestTags = {'dialog', 'inspector', 'ui'}) PropertyEditorFactoryTest < matlab.unittest.TestCase
    % PropertyEditorFactoryTest Verify native allowlisted inspector editor creation.
    %   These tests construct real controls and ensure unsupported editor kinds
    %   remain visible but cannot become accidentally editable.

    methods (Test)
        % Guarantee: unsupported kinds and values are shown read-only.
        % Failure mode: an unsupported value is editable and an edit replaces it with a simpler literal.
        function defersUnsupportedEditorAsReadOnly(testCase)
            % defersUnsupportedEditorAsReadOnly Keep unimplemented kinds non-editable.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = yamada.model.PropertyDefinition("Icon", [], false, true, ...
                struct("editor", "filePath"));
            control = yamada.ui.inspector.PropertyEditorFactory.create( ...
                figure, definition, @(~) []);
            yamada.ui.inspector.PropertyEditorFactory.synchronize(control, "[1 0 0]", true);
            drawnow;
            testCase.verifyFalse(control.Editable);
            clear cleanup
        end

        function normalizesMultilineTextAreaLinesToSourceSafeRowCells(testCase)
            % normalizesMultilineTextAreaLinesToSourceSafeRowCells Preserve multiline text in a literal form.
            % Guarantee: multiline text is committed in a literal form that round-trips.
            % Failure mode: lines are joined, or stored in a form that generation cannot encode.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = yamada.model.PropertyDefinition("Text", [], false, true, ...
                struct("editor", "multilineText"));
            control = yamada.ui.inspector.PropertyEditorFactory.create(figure, definition, ...
                @(value) setappdata(figure, "committed", value));
            yamada.ui.inspector.PropertyEditorFactory.synchronize(control, "", true, {'Line one'; 'Line two'});
            control.Value = {'Line one'; 'Line two'; 'Line three'};
            callback = control.ValueChangedFcn;
            callback(control, struct());
            drawnow;
            committed = getappdata(figure, "committed");
            testCase.verifyTrue(isrow(committed));
            testCase.verifyEqual(committed, {'Line one', 'Line two', 'Line three'});
            testCase.verifyEqual(yamada.source.LiteralEncoder.encode(committed), ...
                "{'Line one', 'Line two', 'Line three'}");
            clear cleanup
        end
    end

    methods (Test)

        function createsStructuredDataLiteralEditor(testCase)
            % createsStructuredDataLiteralEditor Keep arbitrary data on the safe literal path.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = yamada.model.ComponentRegistry.createDefault().getById("uidropdown");
            definition = definition.Properties([definition.Properties.Path] == "ItemsData");
            control = yamada.ui.inspector.PropertyEditorFactory.create(figure, definition, @(~) []);
            yamada.ui.inspector.PropertyEditorFactory.synchronize( ...
                control, "[1 2]", true, [1 2], struct("Items", ["First", "Second"]));
            drawnow;
            testCase.verifyTrue(yamada.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyClass(control, "matlab.ui.control.Button");
            testCase.verifyEqual(string(control.Enable), "on");
            testCase.verifyEqual(string(control.Text), "[1 2]");
            testCase.verifyTrue(control.UserData.HasItems);
            testCase.verifyEqual(string(control.UserData.Items{1}), ["First", "Second"]);
            related = struct("Paths", ["Items", "Value"], ...
                "Values", {{["Updated", "Choices"], "Updated"}}, "KnownValues", [true true]);
            yamada.ui.inspector.PropertyEditorFactory.synchronize(control, "[1 2]", true, [1 2], related);
            testCase.verifyTrue(control.UserData.HasItems);
            testCase.verifyEqual(string(control.UserData.Items{1}), ["Updated", "Choices"]);
            clear cleanup
        end

        function defersUnsupportedStructuredData(testCase)
            % defersUnsupportedStructuredData Keep unsupported arbitrary values source-preserved.
            % Guarantee and failure mode: shared with defersUnsupportedEditorAsReadOnly.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = yamada.model.ComponentRegistry.createDefault().getById("uidropdown");
            definition = definition.Properties([definition.Properties.Path] == "ItemsData");
            control = yamada.ui.inspector.PropertyEditorFactory.create(figure, definition, @(~) []);
            yamada.ui.inspector.PropertyEditorFactory.synchronize( ...
                control, "<unsupported: struct>", true, struct("Code", 1));
            drawnow;
            testCase.verifyEqual(string(control.Enable), "off");
            testCase.verifyEqual(string(control.Text), "<unsupported: struct>");
            clear cleanup
        end

        function createsPlainTextEditorWithoutLiteralParsing(testCase)
            % createsPlainTextEditorWithoutLiteralParsing Commit plain text as a text value rather than source syntax.
            % Guarantee: plain-text capabilities commit the typed characters as a text value.
            % Failure mode: plain text is routed through the literal parser, so quotes or brackets are read as source.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = yamada.model.ComponentRegistry.createDefault().getById("uidatepicker");
            definition = definition.Properties([definition.Properties.Path] == "Placeholder");
            control = yamada.ui.inspector.PropertyEditorFactory.create(figure, definition, ...
                @(value) setappdata(figure, "committed", value));
            yamada.ui.inspector.PropertyEditorFactory.synchronize(control, "''", true, '');
            control.Value = "No date selected";
            control.ValueChangedFcn(control, struct());
            drawnow;
            testCase.verifyTrue(yamada.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyEqual(getappdata(figure, "committed"), 'No date selected');
            clear cleanup
        end

    end

    methods (Test, TestTags = {'fast'})
        % Guarantee: editors for dependent properties stay synchronized with related values.
        % Failure mode: a dropdown keeps old labels, a list box loses multiselect, or a date picker ignores related limits.
        function itemSelectionDropDownMapsItemsDataAndRefreshesItems(testCase)
            % itemSelectionDropDownMapsItemsDataAndRefreshesItems Keep labels synchronized with paired values.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = yamada.model.ComponentRegistry.createDefault().getById("uidropdown");
            definition = definition.Properties([definition.Properties.Path] == "Value");
            control = yamada.ui.inspector.PropertyEditorFactory.create(figure, definition, ...
                @(value) setappdata(figure, "committed", value));
            related = struct("Paths", ["Items", "ItemsData"], ...
                "Values", {{["First", "Second"], [10 20]}}, ...
                "KnownValues", [true true]);
            yamada.ui.inspector.PropertyEditorFactory.synchronize(control, "10", true, ...
                10, related);
            drawnow;
            testCase.verifyTrue(yamada.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyClass(control, "matlab.ui.control.DropDown");
            testCase.verifyEqual(string(control.Items), ["First", "Second"]);
            control.Value = "Second";
            control.ValueChangedFcn(control, struct());
            testCase.verifyEqual(getappdata(figure, "committed"), 20);

            updated = struct("Paths", ["Items", "ItemsData"], ...
                "Values", {{["First", "Third"], [10 30]}}, ...
                "KnownValues", [true true]);
            yamada.ui.inspector.PropertyEditorFactory.synchronize(control, "10", true, 10, updated);
            testCase.verifyEqual(string(control.Items), ["First", "Third"]);
            testCase.verifyEqual(string(control.Value), "First");
            clear cleanup
        end
    end

    methods (Test)
        function itemSelectionListBoxSupportsItemsDataMultiSelection(testCase)
            % itemSelectionListBoxSupportsItemsDataMultiSelection Preserve List Box multiselect semantics.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = yamada.model.ComponentRegistry.createDefault().getById("uilistbox");
            definition = definition.Properties([definition.Properties.Path] == "Value");
            control = yamada.ui.inspector.PropertyEditorFactory.create(figure, definition, ...
                @(value) setappdata(figure, "committed", value));
            related = struct("Paths", ["Items", "ItemsData", "Multiselect"], ...
                "Values", {{["One", "Two", "Three"], [10 20 30], "on"}}, ...
                "KnownValues", [true true true]);
            yamada.ui.inspector.PropertyEditorFactory.synchronize(control, "[10 30]", true, ...
                [10 30], related);
            drawnow;
            testCase.verifyClass(control, "matlab.ui.control.ListBox");
            testCase.verifyEqual(string(control.Multiselect), "on");
            testCase.verifyEqual(string(control.Value), ["One", "Three"]);
            control.Value = {'Two', 'Three'};
            control.ValueChangedFcn(control, struct());
            testCase.verifyEqual(getappdata(figure, "committed"), [20 30]);
            clear cleanup
        end
    end

    methods (Test, TestTags = {'fast'})
        function tableDataRowsShareOneTypedTableEditor(testCase)
            % tableDataRowsShareOneTypedTableEditor Route Data and heading rows through one atomic table batch.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            setappdata(figure, "changes", struct.empty);
            component = yamada.model.ComponentRegistry.createDefault().getById("uitable");
            paths = ["Data", "ColumnName", "RowName"];
            relatedValues = struct("Paths", paths, ...
                "Values", {{[1 2], {'First', 'Second'}, {'One'}}}, ...
                "KnownValues", [true true true]);
            for index = 1:numel(paths)
                definition = component.Properties([component.Properties.Path] == paths(index));
                control = yamada.ui.inspector.PropertyEditorFactory.create(figure, definition, @(~) [], ...
                    @(changes) captureBatch(figure, changes));
                yamada.ui.inspector.PropertyEditorFactory.synchronize( ...
                    control, "", true, relatedValues.Values{index}, relatedValues);
                testCase.verifyEqual(string(control.Enable), "on");
                if paths(index) == "Data"
                    control.ButtonPushedFcn(control, struct());
                end
            end
            dialog = findall(0, "Tag", "yamada-inspector-table-data-dialog");
            table = findall(dialog, "Tag", "yamada-table-data-editor-table");
            table.Data(2, 2:3) = ["3", "4"];
            applyButton = findall(dialog, "Tag", "yamada-table-data-apply");
            applyButton.ButtonPushedFcn(applyButton, struct());

            % The batch carries every table surface; unchanged headings keep their starting values.
            changes = getappdata(figure, "changes");
            data = changes(string({changes.Path}) == "Data");
            testCase.verifyEqual(data.Value, [3 4]);
            columnName = changes(string({changes.Path}) == "ColumnName");
            testCase.verifyEqual(columnName.Value, {'First', 'Second'});
            clear cleanup
        end
    end

    methods (Test)
        function synchronizesDatePickerRestrictionsFromRelatedValues(testCase)
            % synchronizesDatePickerRestrictionsFromRelatedValues Apply the effective date contracts to the native picker.
            % Guarantee and failure mode: shared with itemSelectionDropDownMapsItemsDataAndRefreshesItems.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = yamada.model.ComponentRegistry.createDefault().getById("uidatepicker");
            definition = definition.Properties([definition.Properties.Path] == "Value");
            control = yamada.ui.inspector.PropertyEditorFactory.create(figure, definition, @(~) []);
            limits = [datetime(2024, 1, 1) datetime(2024, 12, 31)];
            disabledDates = [datetime(2024, 3, 1); datetime(2024, 3, 2)];
            relatedValues = struct("Paths", ["Limits", "DisabledDates", "DisabledDaysOfWeek"], ...
                "Values", {{limits, disabledDates, [1 7]}}, "KnownValues", [true true true]);
            yamada.ui.inspector.PropertyEditorFactory.synchronize( ...
                control, "", true, datetime(2024, 2, 29), relatedValues);
            drawnow;
            testCase.verifyEqual(control.Limits, limits);
            testCase.verifyEqual(control.DisabledDates, disabledDates);
            testCase.verifyEqual(control.DisabledDaysOfWeek, [1 7]);
            clear cleanup
        end

    end
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

function message = captureBatch(owner, changes)
% captureBatch Record one dialog batch while reporting that it was accepted.
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

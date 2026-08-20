classdef PropertyEditorFactoryTest < matlab.unittest.TestCase
    % PropertyEditorFactoryTest Verify native allowlisted inspector editor creation.
    %   These tests construct real controls and ensure unsupported editor kinds
    %   remain visible but cannot become accidentally editable.

    methods (Test)
        function createsOnOffCheckBox(testCase)
            % createsOnOffCheckBox Map onOff metadata to a native CheckBox.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.PropertyDefinition("Visible", [], false, true, ...
                struct("editor", "onOff"));
            control = macd.ui.inspector.PropertyEditorFactory.create( ...
                figure, definition, @(~) []);
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "on", true);
            drawnow;
            testCase.verifyClass(control, "matlab.ui.control.CheckBox");
            testCase.verifyTrue(control.Value);
            testCase.verifyEqual(string(control.Text), "");
            clear cleanup
        end

        function createsEnumDropDownFromSchema(testCase)
            % createsEnumDropDownFromSchema Map schema choices to a native DropDown.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.PropertyDefinition("Orientation", [], false, true, ...
                struct("editor", "enum", "valueSchema", ...
                struct("values", {{"horizontal", "vertical"}})));
            control = macd.ui.inspector.PropertyEditorFactory.create( ...
                figure, definition, @(~) []);
            drawnow;
            testCase.verifyClass(control, "matlab.ui.control.DropDown");
            testCase.verifyEqual(string(control.Items), ["horizontal", "vertical"]);
            clear cleanup
        end

        function enablesCatalogEnumDropDown(testCase)
            % enablesCatalogEnumDropDown Use audited finite choices in an editable native DropDown.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.ComponentRegistry.createDefault().getById("uibutton-push");
            definition = definition.Properties([definition.Properties.Path] == "FontWeight");
            control = macd.ui.inspector.PropertyEditorFactory.create( ...
                figure, definition, @(~) []);
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "normal", true);
            drawnow;
            testCase.verifyTrue(macd.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyEqual(string(control.Items), ["normal", "bold"]);
            testCase.verifyEqual(string(control.Enable), "on");
            clear cleanup
        end

        function enablesEllipsisEnumDropDowns(testCase)
            % enablesEllipsisEnumDropDowns Verify complete choices recovered from R2024a value tables.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.ComponentRegistry.createDefault().getById("uifigure");
            definition = definition.Properties([definition.Properties.Path] == "Pointer");
            control = macd.ui.inspector.PropertyEditorFactory.create( ...
                figure, definition, @(~) []);
            expected = ["arrow", "ibeam", "crosshair", "watch", "topl", "custom", ...
                "botr", "topr", "botl", "circle", "cross", "fleur", "left", ...
                "right", "top", "bottom", "hand"];
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "arrow", true);
            drawnow;
            testCase.verifyTrue(macd.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyEqual(string(control.Items), expected);
            testCase.verifyEqual(string(control.Enable), "on");
            clear cleanup
        end

        function enablesEveryRecoveredEllipsisSurface(testCase)
            % enablesEveryRecoveredEllipsisSurface Check all representative recovered enum surfaces.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            registry = macd.model.ComponentRegistry.createDefault();
            cases = {
                "uifigure", "Pointer", ...
                ["arrow", "ibeam", "crosshair", "watch", "topl", "custom", ...
                "botr", "topr", "botl", "circle", "cross", "fleur", "left", ...
                "right", "top", "bottom", "hand"];
                "geoaxes", "Basemap", ...
                ["streets-light", "streets-dark", "streets", "satellite", ...
                "topographic", "landcover", "colorterrain", "grayterrain", ...
                "bluegreen", "grayland", "darkwater", "none"];
                "uibuttongroup", "TitlePosition", ...
                ["lefttop", "centertop", "righttop", "leftbottom", ...
                "centerbottom", "rightbottom"];
                "uipanel", "TitlePosition", ...
                ["lefttop", "centertop", "righttop", "leftbottom", ...
                "centerbottom", "rightbottom"];
                "uibuttongroup", "BorderType", ...
                ["line", "none", "etchedin", "etchedout", "beveledin", "beveledout"];
                "uipanel", "BorderType", ...
                ["line", "none", "etchedin", "etchedout", "beveledin", "beveledout"]};
            for caseIndex = 1:size(cases, 1)
                definition = registry.getById(cases{caseIndex, 1});
                definition = definition.Properties([definition.Properties.Path] == cases{caseIndex, 2});
                control = macd.ui.inspector.PropertyEditorFactory.create( ...
                    figure, definition, @(~) []);
                macd.ui.inspector.PropertyEditorFactory.synchronize( ...
                    control, cases{caseIndex, 3}(1), true);
                drawnow;
                testCase.verifyTrue(macd.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
                testCase.verifyEqual(string(control.Items), cases{caseIndex, 3});
                testCase.verifyEqual(string(control.Enable), "on");
                delete(control);
            end
            clear cleanup
        end

        function defersUnsupportedEditorAsReadOnly(testCase)
            % defersUnsupportedEditorAsReadOnly Keep unimplemented kinds non-editable.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.PropertyDefinition("Icon", [], false, true, ...
                struct("editor", "filePath"));
            control = macd.ui.inspector.PropertyEditorFactory.create( ...
                figure, definition, @(~) []);
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "[1 0 0]", true);
            drawnow;
            testCase.verifyFalse(control.Editable);
            clear cleanup
        end

        function createsMultilineTextArea(testCase)
            % createsMultilineTextArea Render prose properties in an inline multiline editor.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.PropertyDefinition("Tooltip", [], false, true, ...
                struct("editor", "multilineText"));
            control = macd.ui.inspector.PropertyEditorFactory.create( ...
                figure, definition, @(~) []);
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "'Line one'", true, 'Line one');
            drawnow;
            testCase.verifyClass(control, "matlab.ui.control.TextArea");
            testCase.verifyTrue(macd.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyTrue(control.Editable);
            testCase.verifyEqual(string(control.Value), "Line one");
            clear cleanup
        end

        function normalizesMultilineTextAreaLinesToSourceSafeRowCells(testCase)
            % normalizesMultilineTextAreaLinesToSourceSafeRowCells Preserve multiline text in a literal form.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.PropertyDefinition("Text", [], false, true, ...
                struct("editor", "multilineText"));
            control = macd.ui.inspector.PropertyEditorFactory.create(figure, definition, ...
                @(value) setappdata(figure, "committed", value));
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "", true, {'Line one'; 'Line two'});
            control.Value = {'Line one'; 'Line two'; 'Line three'};
            callback = control.ValueChangedFcn;
            callback(control, struct());
            drawnow;
            committed = getappdata(figure, "committed");
            testCase.verifyTrue(isrow(committed));
            testCase.verifyEqual(committed, {'Line one', 'Line two', 'Line three'});
            testCase.verifyEqual(macd.source.LiteralEncoder.encode(committed), ...
                "{'Line one', 'Line two', 'Line three'}");
            clear cleanup
        end

        function createsNativeDateTimeEditors(testCase)
            % createsNativeDateTimeEditors Route scalar, bounds, and date lists by schema shape.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            component = macd.model.ComponentRegistry.createDefault().getById("uidatepicker");
            scalar = component.Properties([component.Properties.Path] == "Value");
            scalarControl = macd.ui.inspector.PropertyEditorFactory.create(figure, scalar, ...
                @(value) setappdata(figure, "scalarDate", value));
            selected = datetime(2024, 2, 29);
            macd.ui.inspector.PropertyEditorFactory.synchronize( ...
                scalarControl, "", true, selected);
            scalarControl.Value = datetime(2024, 3, 1);
            scalarControl.ValueChangedFcn(scalarControl, struct());

            limits = component.Properties([component.Properties.Path] == "Limits");
            limitsControl = macd.ui.inspector.PropertyEditorFactory.create(figure, limits, ...
                @(value) setappdata(figure, "dateLimits", value));
            range = [datetime(2024, 1, 1) datetime(2024, 12, 31)];
            macd.ui.inspector.PropertyEditorFactory.synchronize(limitsControl, "", true, range);
            parts = limitsControl.UserData;
            parts.Start.Value = datetime(2024, 2, 1);
            parts.Start.ValueChangedFcn(parts.Start, struct());

            list = component.Properties([component.Properties.Path] == "DisabledDates");
            listControl = macd.ui.inspector.PropertyEditorFactory.create(figure, list, @(~) []);
            macd.ui.inspector.PropertyEditorFactory.synchronize( ...
                listControl, "", true, datetime.empty(0, 1));
            drawnow;
            testCase.verifyTrue(macd.ui.inspector.PropertyEditorFactory.supportsEditing(scalar));
            testCase.verifyClass(scalarControl, "matlab.ui.control.DatePicker");
            testCase.verifyEqual(getappdata(figure, "scalarDate"), datetime(2024, 3, 1));
            testCase.verifyEqual(getappdata(figure, "dateLimits"), ...
                [datetime(2024, 2, 1) datetime(2024, 12, 31)]);
            testCase.verifyEqual(string(listControl.Tag), "macd-inspector-date-list-editor");
            testCase.verifyEqual(string(listControl.Enable), "on");
            clear cleanup
        end

        function defersItemsDataAsReadOnly(testCase)
            % defersItemsDataAsReadOnly Keep arbitrary list-associated data out of the string editor.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.PropertyDefinition("ItemsData", [], false, true, ...
                struct("editor", "itemsData", "auditDisposition", "readOnly"));
            control = macd.ui.inspector.PropertyEditorFactory.create( ...
                figure, definition, @(~) []);
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "[1 2 3]", false);
            drawnow;
            testCase.verifyFalse(macd.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyFalse(control.Editable);
            clear cleanup
        end

        function createsRgbColorAction(testCase)
            % createsRgbColorAction Render one validated RGB value on a native action button.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.PropertyDefinition("Color", [], false, true, ...
                struct("editor", "color"));
            control = macd.ui.inspector.PropertyEditorFactory.create( ...
                figure, definition, @(~) []);
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "[1 0 0]", true);
            drawnow;
            testCase.verifyClass(control, "matlab.ui.control.Button");
            testCase.verifyEqual(control.BackgroundColor, [1 0 0]);
            clear cleanup
        end

        function createsStringListSummaryAction(testCase)
            % createsStringListSummaryAction Retain raw string arrays behind a native list action.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.PropertyDefinition("Items", [], false, true, ...
                struct("editor", "stringList"));
            control = macd.ui.inspector.PropertyEditorFactory.create( ...
                figure, definition, @(~) []);
            values = ["Light", "Dark"];
            macd.ui.inspector.PropertyEditorFactory.synchronize( ...
                control, "<unsupported: string array>", true, values);
            drawnow;
            testCase.verifyClass(control, "matlab.ui.control.Button");
            testCase.verifyEqual(string(control.Text), "1-by-2 string");
            clear cleanup
        end

        function createsStructuredDataLiteralEditor(testCase)
            % createsStructuredDataLiteralEditor Keep arbitrary data on the safe literal path.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.ComponentRegistry.createDefault().getById("uidropdown");
            definition = definition.Properties([definition.Properties.Path] == "ItemsData");
            control = macd.ui.inspector.PropertyEditorFactory.create(figure, definition, @(~) []);
            macd.ui.inspector.PropertyEditorFactory.synchronize( ...
                control, "[1 2]", true, [1 2], struct("Items", ["First", "Second"]));
            drawnow;
            testCase.verifyTrue(macd.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyClass(control, "matlab.ui.control.Button");
            testCase.verifyEqual(string(control.Enable), "on");
            testCase.verifyEqual(string(control.Text), "[1 2]");
            testCase.verifyTrue(control.UserData.HasItems);
            testCase.verifyEqual(string(control.UserData.Items{1}), ["First", "Second"]);
            clear cleanup
        end

        function resolvesItemsDataFromGeneralRelatedState(testCase)
            % resolvesItemsDataFromGeneralRelatedState Use the shared effective-value snapshot.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.ComponentRegistry.createDefault().getById("uidropdown");
            definition = definition.Properties([definition.Properties.Path] == "ItemsData");
            control = macd.ui.inspector.PropertyEditorFactory.create(figure, definition, @(~) []);
            relatedValues = struct("Paths", ["Items", "Value"], ...
                "Values", {{["First", "Second"], "First"}}, ...
                "KnownValues", [true true]);
            macd.ui.inspector.PropertyEditorFactory.synchronize( ...
                control, "[1 2]", true, [1 2], relatedValues);
            drawnow;
            testCase.verifyTrue(control.UserData.HasItems);
            testCase.verifyEqual(string(control.UserData.Items{1}), ["First", "Second"]);
            clear cleanup
        end

        function defersUnsupportedStructuredData(testCase)
            % defersUnsupportedStructuredData Keep unsupported arbitrary values source-preserved.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.ComponentRegistry.createDefault().getById("uidropdown");
            definition = definition.Properties([definition.Properties.Path] == "ItemsData");
            control = macd.ui.inspector.PropertyEditorFactory.create(figure, definition, @(~) []);
            macd.ui.inspector.PropertyEditorFactory.synchronize( ...
                control, "<unsupported: struct>", true, struct("Code", 1));
            drawnow;
            testCase.verifyEqual(string(control.Enable), "off");
            testCase.verifyEqual(string(control.Text), "<unsupported: struct>");
            clear cleanup
        end

        function createsUrlTextEditor(testCase)
            % createsUrlTextEditor Edit hyperlink values as plain URL text.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.ComponentRegistry.createDefault().getById("uihyperlink");
            definition = definition.Properties([definition.Properties.Path] == "URL");
            control = macd.ui.inspector.PropertyEditorFactory.create(figure, definition, ...
                @(~) []);
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "'https://example.com'", true, ...
                "https://example.com");
            drawnow;
            testCase.verifyTrue(macd.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyEqual(string(control.Tag), "macd-inspector-property-editor");
            testCase.verifyEqual(string(control.Value), "https://example.com");
            testCase.verifyTrue(control.Editable);
            clear cleanup
        end

        function createsPlainTextEditorWithoutLiteralParsing(testCase)
            % createsPlainTextEditor Commit plain text as a text value rather than source syntax.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.ComponentRegistry.createDefault().getById("uidatepicker");
            definition = definition.Properties([definition.Properties.Path] == "Placeholder");
            control = macd.ui.inspector.PropertyEditorFactory.create(figure, definition, ...
                @(value) setappdata(figure, "committed", value));
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "''", true, '');
            control.Value = "No date selected";
            control.ValueChangedFcn(control, struct());
            drawnow;
            testCase.verifyTrue(macd.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyEqual(getappdata(figure, "committed"), 'No date selected');
            clear cleanup
        end

        function defersGridTrackEditorUntilItsDedicatedImplementation(testCase)
            % defersGridTrackEditorUntilItsDedicatedImplementation Avoid a lossy string-list editor.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.ComponentRegistry.createDefault().getById("uigridlayout");
            definition = definition.Properties([definition.Properties.Path] == "ColumnWidth");
            control = macd.ui.inspector.PropertyEditorFactory.create(figure, definition, @(~) []);
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "{'1x', '1x'}", true, {'1x', '1x'});
            drawnow;
            testCase.verifyFalse(macd.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyFalse(control.Editable);
            clear cleanup
        end

        function defersItemSelectionUntilItsDedicatedImplementation(testCase)
            % defersItemSelectionUntilItsDedicatedImplementation Remove the incorrect numeric editor safely.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.ComponentRegistry.createDefault().getById("uidropdown");
            definition = definition.Properties([definition.Properties.Path] == "Value");
            control = macd.ui.inspector.PropertyEditorFactory.create(figure, definition, @(~) []);
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "'First'", true, 'First');
            drawnow;
            testCase.verifyFalse(macd.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyFalse(control.Editable);
            clear cleanup
        end

        function createsStructuredDayListEditor(testCase)
            % createsStructuredDayListEditor Route documented weekdays to the readable dialog action.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.ComponentRegistry.createDefault().getById("uidatepicker");
            definition = definition.Properties([definition.Properties.Path] == "DisabledDaysOfWeek");
            control = macd.ui.inspector.PropertyEditorFactory.create(figure, definition, ...
                @(value) setappdata(figure, "committed", value));
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "[1 3]", true, [1 3]);
            drawnow;
            testCase.verifyTrue(macd.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyClass(control, "matlab.ui.control.Button");
            testCase.verifyEqual(string(control.Text), "Sun, Tue");
            testCase.verifyEqual(control.UserData, [1 3]);
            clear cleanup
        end

        function weekdayDialogUsesTheBatchCommitContract(testCase)
            % weekdayDialogUsesTheBatchCommitContract Return validation messages through the dialog batch path.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            setappdata(figure, "changes", struct.empty);
            definition = macd.model.ComponentRegistry.createDefault().getById("uidatepicker");
            definition = definition.Properties([definition.Properties.Path] == "DisabledDaysOfWeek");
            control = macd.ui.inspector.PropertyEditorFactory.create(figure, definition, @(~) [], ...
                @(changes) captureBatch(figure, changes));
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "[1 3]", true, [1 3]);
            control.ButtonPushedFcn(control, struct());
            dialog = findall(0, "Tag", "macd-inspector-day-of-week-dialog");
            buttons = findall(dialog, "Tag", "macd-inspector-day-of-week-button");
            monday = buttons(string({buttons.Text}) == "Mon");
            monday.Value = true;
            applyButton = findall(dialog, "Tag", "macd-inspector-day-of-week-apply");
            applyButton.ButtonPushedFcn(applyButton, struct());

            changes = getappdata(figure, "changes");
            testCase.verifySize(changes, [1 1]);
            testCase.verifyEqual(changes.Path, "DisabledDaysOfWeek");
            testCase.verifyEqual(changes.Value, [1 2 3]);
            clear cleanup
        end

        function tableDataRowsShareOneTypedTableEditor(testCase)
            % tableDataRowsShareOneTypedTableEditor Route Data and heading rows through one atomic table batch.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            setappdata(figure, "changes", struct.empty);
            component = macd.model.ComponentRegistry.createDefault().getById("uitable");
            paths = ["Data", "ColumnName", "RowName"];
            relatedValues = struct("Paths", paths, ...
                "Values", {{[1 2], {'First', 'Second'}, {'One'}}}, ...
                "KnownValues", [true true true]);
            for index = 1:numel(paths)
                definition = component.Properties([component.Properties.Path] == paths(index));
                control = macd.ui.inspector.PropertyEditorFactory.create(figure, definition, @(~) [], ...
                    @(changes) captureBatch(figure, changes));
                macd.ui.inspector.PropertyEditorFactory.synchronize( ...
                    control, "", true, relatedValues.Values{index}, relatedValues);
                testCase.verifyEqual(string(control.Tag), "macd-inspector-table-data-editor");
                testCase.verifyEqual(string(control.Enable), "on");
                if paths(index) == "Data"
                    control.ButtonPushedFcn(control, struct());
                end
            end
            dialog = findall(0, "Tag", "macd-inspector-table-data-dialog");
            table = findall(dialog, "Tag", "macd-table-data-editor-table");
            table.Data(2, 2:3) = ["3", "4"];
            applyButton = findall(dialog, "Tag", "macd-table-data-apply");
            applyButton.ButtonPushedFcn(applyButton, struct());

            changes = getappdata(figure, "changes");
            testCase.verifyEqual(changes.Path, "Data");
            testCase.verifyEqual(changes.Value, [3 4]);
            clear cleanup
        end

        function synchronizesDatePickerRestrictionsFromRelatedValues(testCase)
            % synchronizesDatePickerRestrictions Apply the effective date contracts to the native picker.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.ComponentRegistry.createDefault().getById("uidatepicker");
            definition = definition.Properties([definition.Properties.Path] == "Value");
            control = macd.ui.inspector.PropertyEditorFactory.create(figure, definition, @(~) []);
            limits = [datetime(2024, 1, 1) datetime(2024, 12, 31)];
            disabledDates = [datetime(2024, 3, 1); datetime(2024, 3, 2)];
            relatedValues = struct("Paths", ["Limits", "DisabledDates", "DisabledDaysOfWeek"], ...
                "Values", {{limits, disabledDates, [1 7]}}, "KnownValues", [true true true]);
            macd.ui.inspector.PropertyEditorFactory.synchronize( ...
                control, "", true, datetime(2024, 2, 29), relatedValues);
            drawnow;
            testCase.verifyEqual(control.Limits, limits);
            testCase.verifyEqual(control.DisabledDates, disabledDates);
            testCase.verifyEqual(control.DisabledDaysOfWeek, [1 7]);
            clear cleanup
        end

        function createsAssetPathEditor(testCase)
            % createsAssetPathEditor Render asset paths with an inline browse action.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.ComponentRegistry.createDefault().getById("uibutton-push");
            definition = definition.Properties([definition.Properties.Path] == "Icon");
            control = macd.ui.inspector.PropertyEditorFactory.create(figure, definition, @(~) []);
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "'icon.png'", true, "icon.png");
            drawnow;
            testCase.verifyTrue(macd.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyEqual(string(control.Tag), "macd-inspector-asset-editor");
            testCase.verifyEqual(string(control.UserData.Edit.Value), "icon.png");
            testCase.verifyEqual(string(control.UserData.Browse.Enable), "on");
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

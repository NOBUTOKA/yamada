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
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "[1 2]", true, [1 2]);
            drawnow;
            testCase.verifyTrue(macd.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyClass(control, "matlab.ui.control.Button");
            testCase.verifyEqual(string(control.Enable), "on");
            testCase.verifyEqual(string(control.Text), "[1 2]");
            clear cleanup
        end

        function createsUrlTextEditor(testCase)
            % createsUrlTextEditor Edit hyperlink values as plain URL text.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            definition = macd.model.ComponentRegistry.createDefault().getById("uihyperlink");
            definition = definition.Properties([definition.Properties.Path] == "URL");
            received = "";
            control = macd.ui.inspector.PropertyEditorFactory.create(figure, definition, ...
                @(value) assignin("caller", "received", value));
            macd.ui.inspector.PropertyEditorFactory.synchronize(control, "'https://example.com'", true, ...
                "https://example.com");
            drawnow;
            testCase.verifyTrue(macd.ui.inspector.PropertyEditorFactory.supportsEditing(definition));
            testCase.verifyEqual(string(control.Value), "https://example.com");
            testCase.verifyTrue(control.Editable);
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

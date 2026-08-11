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
MatlabAppClassDesigner - Native property editor factory tests.
Copyright (C) 2026 MatlabAppClassDesigner contributors

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

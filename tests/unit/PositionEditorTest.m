classdef (TestTags = {'inspector', 'ui'}) PositionEditorTest < matlab.unittest.TestCase
    % PositionEditorTest Verify inline geometry fields and their atomic live bindings.
    %   Fixtures own all native controls and never open or evaluate user source.

    methods (Test, TestTags = {'fast'})
        function verticalFieldsAndLinkedSizesCommitOnce(testCase)
            % verticalFieldsAndLinkedSizesCommitOnce Show a vertical bracket and preserve Position order.
            figure = uifigure("Visible", "off", "Position", [100 100 270 160]);
            cleanup = onCleanup(@() delete(figure));
            grid = uigridlayout(figure, [1 1]);
            definition = yamada.model.ComponentRegistry.createDefault().getById("uiswitch-rocker").getProperty("Position");
            control = yamada.ui.inspector.PropertyEditorFactory.create(grid, definition, @(value) capture(figure, value));
            related = struct("Paths", "Orientation", "Values", {{"vertical"}}, "KnownValues", true);
            yamada.ui.inspector.PropertyEditorFactory.synchronize(control, "", true, [10 20 20 45], related);
            drawnow;
            parts = control.UserData;
            testCase.verifyEqual(string({parts.Fields.Tooltip}), ["X", "Y", "Width", "Height"]);
            testCase.verifyEqual([parts.Fields.Value], [10 20 20 45]);
            testCase.verifyEqual(string({parts.FieldLabels.Text}), ["X", "Y", "W", "H"]);
            testCase.verifyEqual(arrayfun(@(item) item.Layout.Column, parts.Fields), [2 2 2 2]);
            testCase.verifyEqual(string({parts.Links.Text}), ["┓", "┛"]);
            testCase.verifyEqual(string([parts.Links.Visible]), ["on", "on"]);
            testCase.verifyEqual(parts.Links(1).Layout.Column, parts.Links(2).Layout.Column);
            testCase.verifyEqual(arrayfun(@(item) item.Layout.Row, parts.Links), [3 4]);
            for index = 1:4, testCase.verifyEqual(parts.Fields(index).Layout.Row, index); end
            parts.Fields(3).Value = 40;
            parts.Fields(3).ValueChangedFcn(parts.Fields(3), struct());
            testCase.verifyEqual(getappdata(figure, "Value"), [10 20 40 90]);
            testCase.verifyEqual(getappdata(figure, "Count"), 1);
            testCase.verifyEqual(parts.Fields(4).Value, 90);
            parts.Fields(4).Value = 135;
            parts.Fields(4).ValueChangedFcn(parts.Fields(4), struct());
            testCase.verifyEqual(getappdata(figure, "Value"), [10 20 60 135]);
            testCase.verifyEqual(getappdata(figure, "Count"), 2);
        end

        function fixedDimensionTooltipsFollowOrientation(testCase)
            % fixedDimensionTooltipsFollowOrientation Keep a fixed side readable without disabling the other fields.
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            definition = yamada.model.ComponentRegistry.createDefault().getById("uislider-slider").getProperty("Position");
            control = yamada.ui.inspector.PropertyEditorFactory.create(figure, definition, @(value) capture(figure, value));
            for orientation = ["horizontal", "vertical"]
                related = struct("Paths", "Orientation", "Values", {{orientation}}, "KnownValues", true);
                value = [10 20 100 3];
                fixed = 4;
                if orientation == "vertical", value(3:4) = [3 100]; fixed = 3; end
                yamada.ui.inspector.PropertyEditorFactory.synchronize(control, "", true, value, related);
                parts = control.UserData;
                expected = ["X", "Y", "Width", "Height"];
                expected(fixed) = expected(fixed) + " (fixed)";
                testCase.verifyEqual(string({parts.Fields.Tooltip}), expected);
                testCase.verifyEqual(string(parts.Fields(fixed).Editable), "off");
                testCase.verifyEqual(string(parts.Fields(fixed).Enable), "on");
                testCase.verifyTrue(all(string({parts.Links.Text}) == ""));
                testCase.verifyEqual(string([parts.Links.Visible]), ["off", "off"]);
                parts.Fields(fixed).ValueChangedFcn(parts.Fields(fixed), struct());
                testCase.verifyEmpty(getappdata(figure, "Value"));
            end
        end

        function rowRebindingRejectsStaleNumericEvents(testCase)
            % rowRebindingRejectsStaleNumericEvents Do not send a queued field change to a newly selected component.
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            grid = uigridlayout(figure, [1 1]);
            definition = yamada.model.ComponentRegistry.createDefault().getById("uilabel").getProperty("Position");
            row = yamada.ui.inspector.InspectorPropertyRow(grid, 1, "old", definition, ...
                @(id, ~, value) captureMessage(figure, id, value));
            row.synchronize("", true, [1 2 100 30]);
            control = findall(figure, "Tag", "yamada-inspector-position-editor");
            field = control.UserData.Fields(1);
            old = field.ValueChangedFcn;
            row.rebind("new");
            row.synchronize("", true, [10 20 100 30]);
            old(field, struct());
            testCase.verifyEmpty(getappdata(figure, "Value"));
            field.Value = 30;
            field.ValueChangedFcn(field, struct());
            testCase.verifyEqual(getappdata(figure, "Id"), "new");
            testCase.verifyEqual(getappdata(figure, "Value"), [30 20 100 30]);
        end
    end

    methods (Test)
        function liveInspectorUsesOneUndoForBothLinkedSizes(testCase)
            % liveInspectorUsesOneUndoForBothLinkedSizes Verify palette, Inspector, model, and Preview agreement.
            app = yamada();
            cleanup = onCleanup(@() delete(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            figure.Visible = "off";
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(item) any(string(item.ColumnName) == "Component") && ...
                any(string(item.ColumnName) == "Category"), tables));
            index = find(string(palette.Data(:, 1)) == "Rocker Switch", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", index)));
            drawnow;
            component = app.Document.getComponent(app.SelectedComponentId);
            history = app.Document.HistoryIndex;
            control = findall(figure, "Tag", "yamada-inspector-position-editor");
            parts = control.UserData;
            before = [parts.Fields.Value];
            testCase.verifyEqual(string(parts.Fields(3).Editable), "on");
            parts.Fields(3).Value = 40;
            parts.Fields(3).ValueChangedFcn(parts.Fields(3), struct());
            drawnow;
            testCase.verifyEqual(component.getProperty("Position").LiteralValue(3:4), [40 90]);
            testCase.verifyEqual(app.Document.HistoryIndex, history + 1);
            menus = findall(figure, "Type", "uimenu");
            undo = menus(erase(string({menus.Text}), "&") == "Undo");
            undo.MenuSelectedFcn(undo, struct());
            drawnow;
            control = findall(figure, "Tag", "yamada-inspector-position-editor");
            testCase.verifyEqual([control.UserData.Fields.Value], before);
        end
    end
end

function capture(figure, value)
% capture Record one adapter commit without mutating any document state.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
    value
end
count = getappdata(figure, "Count");
if isempty(count), count = 0; end
setappdata(figure, "Count", count + 1);
setappdata(figure, "Value", value);
end

function message = captureMessage(figure, id, value)
% captureMessage Return an accepted row commit after recording its current identity.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
    id (1, 1) string
    value
end
arguments (Output)
    message (1, 1) string
end
capture(figure, value);
setappdata(figure, "Id", id);
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

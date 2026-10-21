classdef (TestTags = {'preview', 'ui'}) NumericPreviewReuseTest < matlab.unittest.TestCase
    % NumericPreviewReuseTest Verify numeric Value updates retain native controls and layout equivalence.
    %   Incremental rendering must agree with an independent full renderer and
    %   reject unrelated changes, unknown constraints and stale native objects.
    methods (Test)
        function valueUpdatesMatchFullRenderingAcrossFitLayouts(testCase)
            % valueUpdatesMatchFullRenderingAcrossFitLayouts Reuse each owned native field while republishing geometry.
            for layout = ["absolute", "flat", "nested"]
                [document, registry, first] = numericPreviewFixture(layout);
                figure = uifigure(Visible="off", Position=[100 100 1100 650]);
                cleanup = onCleanup(@() delete(figure));
                left = uipanel(figure, Position=[1 1 520 600]);
                right = uipanel(figure, Position=[550 1 520 600]);
                renderer = macd.ui.PreviewRenderer(registry);
                [handles, diagnostics, canvas] = renderer.render(document, left);
                testCase.assertEmpty(diagnostics);
                original = handles(char(first.Id));
                beforeCount = numel(findall(left));
                for value = [3 7 -2 1e6]
                    document.setProperty(first.Id, "Value", value, registry);
                    document.validatePropertyCommit(registry);
                    [applied, diagnostics, geometry] = renderer.synchronize(document, handles, ...
                        macd.ui.RefreshRequest("properties", first.Id, "Value"));
                    testCase.verifyTrue(applied, layout);
                    testCase.verifyEmpty(diagnostics);
                    testCase.verifyTrue(geometry);
                    testCase.verifyTrue(isvalid(canvas));
                    testCase.verifyEqual(handles(char(first.Id)), original);
                    testCase.verifyEqual(original.Value, value);
                    testCase.verifyEqual(numel(findall(left)), beforeCount);
                end
                reference = macd.ui.PreviewRenderer(registry).render(document, right);
                drawnow; pause(0.15); drawnow;
                testCase.verifyEqual(original.Value, reference(char(first.Id)).Value);
                testCase.verifyEqual(original.Limits, reference(char(first.Id)).Limits);
                if layout ~= "absolute"
                    testCase.verifyEqual(original.Position, reference(char(first.Id)).Position, "AbsTol", 1);
                end
                testCase.verifyEqual(renderer.statistics().renders, 1);
                testCase.verifyEqual(renderer.statistics().synchronizations, 4);
                clear cleanup
            end
        end

        function constraintFormatParentAndCatalogChangesFallBack(testCase)
            % constraintFormatParentAndCatalogChangesFallBack Never reuse a widget configured from different inputs.
            for kind = ["limits", "format", "parent", "registry"]
                [document, registry, first] = numericPreviewFixture("absolute");
                figure = uifigure(Visible="off");
                cleanup = onCleanup(@() delete(figure));
                renderer = macd.ui.PreviewRenderer(registry);
                handles = renderer.render(document, figure);
                if kind == "limits"
                    first.setProperty("Limits", [-10 10]);
                elseif kind == "format"
                    first.setProperty("ValueDisplayFormat", "%.4f");
                elseif kind == "parent"
                    first.ParentId = "unproven-parent";
                else
                    registry.register(registry.get("uieditfield", {"numeric"}));
                end
                first.setProperty("Value", 4);
                applied = renderer.synchronize(document, handles, macd.ui.RefreshRequest("properties", first.Id, "Value"));
                testCase.verifyFalse(applied, kind);
                clear cleanup
            end
        end

        function emptyRequestsAndDeadHandlesUseTheExistingRenderer(testCase)
            % emptyRequestsAndDeadHandlesUseTheExistingRenderer Keep unsupported values and disposed widgets outside reuse.
            for kind = ["empty", "deleted"]
                [document, registry, first] = numericPreviewFixture("absolute");
                first.setProperty("AllowEmpty", "on");
                figure = uifigure(Visible="off");
                cleanup = onCleanup(@() delete(figure));
                renderer = macd.ui.PreviewRenderer(registry);
                handles = renderer.render(document, figure);
                if kind == "empty"
                    document.setProperty(first.Id, "Value", [], registry);
                else
                    document.setProperty(first.Id, "Value", 4, registry);
                    delete(handles(char(first.Id)));
                end
                applied = renderer.synchronize(document, handles, macd.ui.RefreshRequest("properties", first.Id, "Value"));
                testCase.verifyFalse(applied, kind);
                clear cleanup
            end
        end
    end
end

function [document, registry, first] = numericPreviewFixture(layout)
% numericPreviewFixture Parse typed numeric controls with known constraints and optional nested fit grids.
arguments (Input)
    layout (1, 1) string
end
arguments (Output)
    document (1, 1) macd.model.DocumentModel
    registry (1, 1) macd.model.ComponentRegistry
    first (1, 1) macd.model.ComponentRecord
end
registry = macd.model.ComponentRegistry.createDefault();
declarations = ["UIFigure matlab.ui.Figure", "First matlab.ui.control.NumericEditField", ...
    "Second matlab.ui.control.Label"];
body = ["app.UIFigure = uifigure(Visible='off');", "app.UIFigure.Position = [100 100 480 500];"];
parent = "app.UIFigure";
if layout == "nested"
    for depth = 1:3
        name = "Outer" + depth;
        declarations(end + 1) = name + " matlab.ui.container.GridLayout"; %#ok<AGROW>
        body = [body, "app." + name + " = uigridlayout(" + parent + ",[1 1]);", ...
            "app." + name + ".RowHeight = {'1x'};", "app." + name + ".ColumnWidth = {'1x'};"]; %#ok<AGROW>
        parent = "app." + name;
    end
end
if layout ~= "absolute"
    declarations(end + 1) = "Grid matlab.ui.container.GridLayout";
    body = [body, "app.Grid = uigridlayout(" + parent + ",[2 1]);", ...
        "app.Grid.RowHeight = {'fit','1x'};", "app.Grid.ColumnWidth = {'fit'};"];
    parent = "app.Grid";
end
body = [body, "app.First = uieditfield(" + parent + ",'numeric');", "app.First.Value = 1;", ...
    "app.Second = uilabel(" + parent + ");", "app.Second.Text = 'Reference';"];
if layout ~= "absolute", body = [body, "app.First.Layout.Row = 1;", "app.Second.Layout.Row = 2;"]; end
source = strjoin(["classdef NumericPreviewFixture < handle", "properties", declarations, ...
    "end", "methods", "function app = NumericPreviewFixture", "createComponents(app);", "end", ...
    "function createComponents(app)", body, "end", "end", "end"], sprintf("\r\n"));
document = macd.source.AppSourceParser.parseText(source, registry);
first = document.getComponentByName("First");
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

classdef (TestTags = {'model', 'generation', 'preview', 'ui'}) PropertyInsertionRuntimeTest < matlab.unittest.TestCase
    % PropertyInsertionRuntimeTest Execute only test-authored generated source fixtures.
    %   These tests compile owned handle-based classes and compare Preview with the
    %   same planned source. Arbitrary opened application text is never run.

    methods (Test)
        function generatedOwnedClassesExecuteAllSixStyleCases(testCase)
            % generatedOwnedClassesExecuteAllSixStyleCases Check three existing styles with constructor and assignment additions.
            registry = yamada.model.ComponentRegistry.createDefault();
            folder = string(tempname());
            mkdir(folder);
            originalPath = path;
            addpath(folder);
            cleanup = onCleanup(@() PropertyInsertionRuntimeTest.cleanFolder(folder, originalPath));
            for style = ["nameValue", "assignment", "mixed"]
                for property = ["Value", "Tooltip"]
                    className = "OwnedInsertion" + erase(string(java.util.UUID.randomUUID()), "-");
                    if style == "nameValue"
                        body = "app.Control = uidropdown(app.UIFigure, Items=[""A"" ""B""], ItemsData=[10 20]);";
                    elseif style == "assignment"
                        body = ["app.Control = uidropdown(app.UIFigure);", ...
                            "app.Control.Items = [""A"" ""B""];", "app.Control.ItemsData = [10 20];"];
                    else
                        body = ["app.Control = uidropdown(app.UIFigure, Items=[""A"" ""B""]);", ...
                            "app.Control.ItemsData = [10 20];"];
                    end
                    document = yamada.source.AppSourceParser.parseText(testCase.source(className, body), registry);
                    component = document.getComponentByName("Control");
                    value = 20;
                    if property == "Tooltip", value = "Hint"; end
                    document.setProperty(component.Id, property, value, registry);
                    source = yamada.source.RoundTripGenerator(registry).generate(document);
                    testCase.assertGreaterThan(strlength(source), 0);
                    yamada.source.SourceWriter.write(fullfile(folder, className + ".m"), source);
                    app = feval(className);
                    appCleanup = onCleanup(@() delete(app));
                    actual = app.Control.(property);
                    if property == "Tooltip", actual = string(actual); end
                    testCase.verifyEqual(actual, value, style + "/" + property);
                    clear appCleanup
                end
            end
            clear cleanup
        end

        function relocatedOwnedClassesMatchNativeStateAndPreview(testCase)
            % relocatedOwnedClassesMatchNativeStateAndPreview Execute all source styles and constructor layout removal.
            registry = yamada.model.ComponentRegistry.createDefault();
            folder = string(tempname());
            mkdir(folder);
            originalPath = path;
            addpath(folder);
            cleanup = onCleanup(@() PropertyInsertionRuntimeTest.cleanFolder(folder, originalPath));
            try
            for style = ["nameValue", "assignment", "mixed", "grid"]
                className = "OwnedInsertion" + erase(string(java.util.UUID.randomUUID()), "-");
                if style == "nameValue"
                    creation = "app.Control = uidropdown(app.Left, Items=[""A"" ""B""], ItemsData=[10 20]);";
                elseif style == "assignment"
                    creation = ["app.Control = uidropdown(app.Left);", "app.Control.Items = [""A"" ""B""];", ...
                        "app.Control.ItemsData = [10 20];"];
                elseif style == "mixed"
                    creation = ["app.Control = uidropdown(app.Left, Items=[""A"" ""B""]);", ...
                        "app.Control.ItemsData = [10 20];"];
                else
                    creation = ["app.Control = uidropdown(app.Left, ... % factory", ...
                        "    Position=[10 ... % x-coordinate", "    20 100 22], ... % position", ...
                        "    Items=[""A"" ""B""], ItemsData=[10 20]);"];
                end
                body = ["app.Left = uipanel(app.UIFigure);", creation, "app.Right = uipanel(app.UIFigure);", ...
                    "app.Grid = uigridlayout(app.Right);"];
                source = testCase.source(className, body);
                source = replace(source, "UIFigure matlab.ui.Figure", ...
                    strjoin(["UIFigure matlab.ui.Figure", "Left matlab.ui.container.Panel", ...
                    "Right matlab.ui.container.Panel", "Grid matlab.ui.container.GridLayout"], sprintf("\r\n")));
                document = yamada.source.AppSourceParser.parseText(source, registry);
                component = document.getComponentByName("Control");
                document.setProperty(component.Id, "Value", 20, registry);
                target = document.getComponentByName("Right");
                if style == "grid", target = document.getComponentByName("Grid"); end
                document.reparentSubtree(component.Id, target.Id, registry, [], [], [10 20 100 22]);
                source = yamada.source.RoundTripGenerator(registry).generate(document);
                yamada.source.SourceWriter.write(fullfile(folder, className + ".m"), source);
                app = feval(className);
                appCleanup = onCleanup(@() delete(app));
                figure = uifigure("Visible", "off");
                figureCleanup = onCleanup(@() delete(figure));
                [handles, diagnostics] = yamada.ui.PreviewRenderer(registry).render(document, uipanel(figure));
                testCase.assertEmpty(diagnostics, style + ": " + strjoin(string({diagnostics.Message}), " | "));
                testCase.verifyEqual(app.Control.Value, 20);
                testCase.verifyEqual(handles(char(component.Id)).Value, app.Control.Value);
                testCase.verifyEqual(app.Control.Parent, app.(target.Name));
                testCase.verifyEqual(handles(char(component.Id)).Parent, handles(char(target.Id)));
                if style == "grid"
                    testCase.verifyEqual(app.Control.Layout.Row, 1);
                    testCase.verifyEqual(app.Control.Layout.Column, 1);
                end
                clear figureCleanup appCleanup
            end
            catch exception
                % Dispose owned instances before removing their class files from the path.
                clear figureCleanup appCleanup cleanup
                rethrow(exception)
            end
            clear cleanup
        end

        function copiedOwnedClassesRetainNativeEffectiveValues(testCase)
            % copiedOwnedClassesRetainNativeEffectiveValues Compare copied bounded, item, rounded, and automatic states with native originals.
            registry = yamada.model.ComponentRegistry.createDefault();
            folder = string(tempname());
            mkdir(folder);
            originalPath = path;
            addpath(folder);
            cleanup = onCleanup(@() PropertyInsertionRuntimeTest.cleanFolder(folder, originalPath));
            try
                for scenario = ["bounded", "items", "rounded", "automatic"]
                    className = "OwnedInsertion" + erase(string(java.util.UUID.randomUUID()), "-");
                    type = "Slider";
                    if scenario == "bounded"
                        control = ["app.Control = uislider(app.Left);", "app.Control.Value = 20;", "app.Control.Limits = [50 100];"];
                    elseif scenario == "items"
                        type = "DropDown";
                        control = ["app.Control = uidropdown(app.Left, Items=[""A"" ""B""], ItemsData=[10 20], Value=20);", ...
                            "app.Control.ItemsData = [100 200];"];
                    elseif scenario == "rounded"
                        type = "NumericEditField";
                        control = "app.Control = uieditfield(app.Left, 'numeric', Value=3.4, RoundFractionalValues='on');";
                    else
                        control = ["app.Control = uislider(app.Left);", "app.Control.MajorTicks = [0 25 100];", ...
                            "app.Control.MajorTicksMode = 'auto';"];
                    end
                    height = 22;
                    if type == "Slider", height = 3; end
                    position = yamada.source.LiteralEncoder.encode([10 20 100 height]);
                    body = ["app.Left = uipanel(app.UIFigure);", control, "app.Control.Position = " + position + ";", ...
                        "app.Right = uipanel(app.UIFigure);"];
                    source = testCase.source(className, body);
                    source = replace(source, "Control matlab.ui.control.DropDown", "Control matlab.ui.control." + type);
                    source = replace(source, "UIFigure matlab.ui.Figure", strjoin(["UIFigure matlab.ui.Figure", ...
                        "Left matlab.ui.container.Panel", "Right matlab.ui.container.Panel"], sprintf("\r\n")));
                    document = yamada.source.AppSourceParser.parseText(source, registry);
                    component = document.getComponentByName("Control");
                    target = document.getComponentByName("Right");
                    pasted = document.pasteSubtree(document.copySubtree(component.Id, registry), target.Id, registry);
                    source = yamada.source.RoundTripGenerator(registry).generate(document);
                    yamada.source.SourceWriter.write(fullfile(folder, className + ".m"), source);
                    app = feval(className);
                    appCleanup = onCleanup(@() delete(app));
                    figure = uifigure("Visible", "off");
                    figureCleanup = onCleanup(@() delete(figure));
                    [handles, diagnostics] = yamada.ui.PreviewRenderer(registry).render(document, uipanel(figure));
                    testCase.assertEmpty(diagnostics, scenario + ": " + strjoin(string({diagnostics.Message}), " | "));
                    copied = app.(pasted.Name);
                    testCase.verifyEqual(copied.Value, app.Control.Value, scenario);
                    testCase.verifyEqual(handles(char(pasted.Id)).Value, copied.Value, scenario);
                    if scenario == "automatic"
                        testCase.verifyEqual(string(copied.MajorTicksMode), "auto");
                        testCase.verifyEqual(copied.MajorTicks, app.Control.MajorTicks);
                        testCase.verifyEqual(handles(char(pasted.Id)).MajorTicks, copied.MajorTicks);
                        drawnow;
                        testCase.verifyEqual(copied.MajorTicks, app.Control.MajorTicks);
                    end
                    clear figureCleanup appCleanup
                end
            catch exception
                % Remove class files only after disposing the instances that depend on them.
                clear figureCleanup appCleanup cleanup
                rethrow(exception)
            end
            clear cleanup
        end

        function multilineConstructorInsertionCompilesAndPreviewMatches(testCase)
            % multilineConstructorInsertionCompilesAndPreviewMatches Verify source token trivia against actual MATLAB syntax.
            registry = yamada.model.ComponentRegistry.createDefault();
            className = "OwnedInsertion" + erase(string(java.util.UUID.randomUUID()), "-");
            body = ["app.Control = uidropdown(app.UIFigure, ... % factory", ...
                "    'Items', {'A','B'}, ... % labels", "    'ItemsData', [10 20] ... % data", "    );"];
            document = yamada.source.AppSourceParser.parseText(testCase.source(className, body), registry);
            component = document.getComponentByName("Control");
            document.setProperty(component.Id, "Value", 20, registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            folder = string(tempname());
            mkdir(folder);
            originalPath = path;
            addpath(folder);
            cleanup = onCleanup(@() PropertyInsertionRuntimeTest.cleanFolder(folder, originalPath));
            yamada.source.SourceWriter.write(fullfile(folder, className + ".m"), source);
            app = feval(className);
            appCleanup = onCleanup(@() delete(app));
            figure = uifigure("Visible", "off");
            figureCleanup = onCleanup(@() delete(figure));
            panel = uipanel(figure);
            [handles, diagnostics] = yamada.ui.PreviewRenderer(registry).render(document, panel);
            testCase.verifyEmpty(diagnostics);
            testCase.verifyEqual(handles(char(component.Id)).Value, app.Control.Value);
            testCase.verifyEqual(app.Control.Value, 20);
            clear figureCleanup appCleanup cleanup
        end
    end

    methods (Static, Access = private)
        function text = source(className, body)
            % source Build one explicitly owned, noninteractive handle-based fixture class.
            arguments (Input)
                className (1, 1) string
                body (1, :) string
            end
            arguments (Output)
                text (1, 1) string
            end
            text = strjoin(["classdef " + className + " < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Control matlab.ui.control.DropDown", "end", "methods", ...
                "function app = " + className, "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", body, "end", ...
                "function delete(app)", "if ~isempty(app.UIFigure) && isvalid(app.UIFigure)", ...
                "delete(app.UIFigure);", "end", "end", "end", "end"], sprintf("\r\n"));
        end

        function cleanFolder(folder, originalPath)
            % cleanFolder Restore the path and delete only owned fixture files without recursive removal.
            arguments (Input)
                folder (1, 1) string
                originalPath
            end
            path(originalPath);
            files = dir(fullfile(folder, "OwnedInsertion*.m"));
            for file = reshape(files, 1, []), delete(fullfile(folder, file.name)); end
            rmdir(folder);
        end
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

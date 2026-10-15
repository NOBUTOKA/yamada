classdef (TestTags = {'model', 'generation', 'preview', 'ui'}) PropertyInsertionRuntimeTest < matlab.unittest.TestCase
    % PropertyInsertionRuntimeTest Execute only test-authored generated source fixtures.
    %   These tests compile owned AppBase classes and compare Preview with the
    %   same planned source. Arbitrary opened application text is never run.

    methods (Test)
        function generatedOwnedClassesExecuteAllSixStyleCases(testCase)
            % generatedOwnedClassesExecuteAllSixStyleCases Check three existing styles with constructor and assignment additions.
            registry = macd.model.ComponentRegistry.createDefault();
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
                    document = macd.source.AppSourceParser.parseText(testCase.source(className, body), registry);
                    component = document.getComponentByName("Control");
                    value = 20;
                    if property == "Tooltip", value = "Hint"; end
                    document.setProperty(component.Id, property, value, registry);
                    source = macd.source.RoundTripGenerator(registry).generate(document);
                    testCase.assertGreaterThan(strlength(source), 0);
                    macd.source.SourceWriter.write(fullfile(folder, className + ".m"), source);
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

        function multilineConstructorInsertionCompilesAndPreviewMatches(testCase)
            % multilineConstructorInsertionCompilesAndPreviewMatches Verify source token trivia against actual MATLAB syntax.
            registry = macd.model.ComponentRegistry.createDefault();
            className = "OwnedInsertion" + erase(string(java.util.UUID.randomUUID()), "-");
            body = ["app.Control = uidropdown(app.UIFigure, ... % factory", ...
                "    'Items', {'A','B'}, ... % labels", "    'ItemsData', [10 20] ... % data", "    );"];
            document = macd.source.AppSourceParser.parseText(testCase.source(className, body), registry);
            component = document.getComponentByName("Control");
            document.setProperty(component.Id, "Value", 20, registry);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            folder = string(tempname());
            mkdir(folder);
            originalPath = path;
            addpath(folder);
            cleanup = onCleanup(@() PropertyInsertionRuntimeTest.cleanFolder(folder, originalPath));
            macd.source.SourceWriter.write(fullfile(folder, className + ".m"), source);
            app = feval(className);
            appCleanup = onCleanup(@() delete(app));
            figure = uifigure("Visible", "off");
            figureCleanup = onCleanup(@() delete(figure));
            panel = uipanel(figure);
            [handles, diagnostics] = macd.ui.PreviewRenderer(registry).render(document, panel);
            testCase.verifyEmpty(diagnostics);
            testCase.verifyEqual(handles(char(component.Id)).Value, app.Control.Value);
            testCase.verifyEqual(app.Control.Value, 20);
            clear figureCleanup appCleanup cleanup
        end
    end

    methods (Static, Access = private)
        function text = source(className, body)
            % source Build one explicitly owned, noninteractive AppBase fixture class.
            arguments (Input)
                className (1, 1) string
                body (1, :) string
            end
            arguments (Output)
                text (1, 1) string
            end
            text = strjoin(["classdef " + className + " < matlab.apps.AppBase", "properties", ...
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

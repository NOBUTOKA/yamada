classdef PreviewRendererTest < matlab.unittest.TestCase
    % PreviewRendererTest Compare safe previews against trusted fixture applications.
    %   This data-driven test parses each explicitly trusted fixture, renders its
    %   model without executing source, then compares every supported editable
    %   literal property with a separate runtime instance of that known fixture.
    %   It never permits the editor to execute arbitrary opened source.

    methods (Test)
        function safePreviewMatchesTrustedFixtureProperties(testCase)
            % safePreviewMatchesTrustedFixtureProperties Compare every trusted fixture.

            % Keep fixture execution explicit while rendering always uses parsed data.
            fixtures = PreviewRendererTest.trustedFixtures();
            for fixtureIndex = 1:numel(fixtures)
                fixture = fixtures(fixtureIndex);
                testCase.compareFixture(string(fixture.Path));
            end
        end

        function safePreviewRendersExtendedFixtureSemantics(testCase)
            % safePreviewRendersExtendedFixtureSemantics Cover string lists, axes, and tools.

            % Render the source-derived models without executing any of these fixtures.
            registry = macd.model.ComponentRegistry.createDefault();
            testPath = mfilename("fullpath");
            fixtureFolder = fullfile(fileparts(fileparts(fileparts(testPath))), ...
                "tests", "fixtures");
            previewFigure = uifigure("Visible", "off", ...
                "Position", [100 100 900 700]);
            previewCleanup = onCleanup(@() deleteIfValid(previewFigure));

            % Verify string-array literals populate the control text shown in preview.
            [controlDocument, controlHandles, controlDiagnostics, controlPanel] = ...
                testCase.renderFixture(registry, fixtureFolder, "ControlGalleryApp", previewFigure);
            controlCleanup = onCleanup(@() deleteIfValid(controlPanel));
            testCase.verifyEmpty(controlDocument.Diagnostics);
            testCase.verifyEmpty(controlDiagnostics);
            testCase.verifyEqual(string(controlHandles("parsed-ThemeDropDown").Items), ...
                ["Light", "Dark", "System"]);
            testCase.verifyEqual(string(controlHandles("parsed-NotesTextArea").Value), ...
                ["A multi-line"; "notes field"]);
            testCase.verifyEqual(string(controlHandles("parsed-GainKnob").Items), ...
                ["0", "2", "4", "6", "8", "10"]);
            testCase.verifyEqual(string(controlHandles("parsed-ModeSwitch").Items), ...
                ["Manual", "Auto"]);
            previewSurface = controlHandles("parsed-MainGrid").Parent;
            sourceSize = [580 460];
            previewMargin = 12;
            usableSize = controlPanel.InnerPosition(3:4) - 2 * previewMargin;
            scale = min(usableSize ./ sourceSize);
            testCase.verifyEqual(previewSurface.Position, ...
                [previewMargin + (usableSize - sourceSize .* scale) ./ 2, ...
                sourceSize .* scale], "AbsTol", 1e-10);
            clear controlCleanup

            % Keep pixel axes proportional to the fitted figure surface.
            [axesDocument, axesHandles, axesDiagnostics, axesPanel] = ...
                testCase.renderFixture(registry, fixtureFolder, "AxesExplorerApp", previewFigure);
            axesCleanup = onCleanup(@() deleteIfValid(axesPanel));
            testCase.verifyEmpty(axesDocument.Diagnostics);
            testCase.verifyEmpty(axesDiagnostics);
            scale = axesHandles("parsed-UIAxes").Position(3) / 340;
            testCase.verifyEqual(axesHandles("parsed-UIAxes").Position, ...
                [20 230 340 180] .* scale, "AbsTol", 1e-10);
            testCase.verifyEqual(axesHandles("parsed-StandardAxes").Position, ...
                [0.55 0.55 0.35 0.35]);
            clear axesCleanup

            % Parse the table headers rather than retaining their source expression.
            [navigationDocument, navigationHandles, navigationDiagnostics, navigationPanel] = ...
                testCase.renderFixture(registry, fixtureFolder, "NavigationDataApp", previewFigure);
            navigationCleanup = onCleanup(@() deleteIfValid(navigationPanel));
            testCase.verifyEmpty(navigationDocument.Diagnostics);
            testCase.verifyEmpty(navigationDiagnostics);
            testCase.verifyEqual(string(navigationHandles("parsed-CatalogTable").ColumnName), ...
                ["Title"; "Rating"]);
            clear navigationCleanup

            % Ignore figure-only tools while retaining ordinary controls on the surface.
            [toolsDocument, toolsHandles, toolsDiagnostics, toolsPanel] = ...
                testCase.renderFixture(registry, fixtureFolder, "FigureToolsApp", previewFigure);
            toolsCleanup = onCleanup(@() deleteIfValid(toolsPanel));
            testCase.verifyEmpty(toolsDocument.Diagnostics);
            testCase.verifyEmpty(toolsDiagnostics);
            testCase.verifyEqual(double(toolsHandles.Count), 1);
            testCase.verifyTrue(isKey(toolsHandles, "parsed-PreviewLabel"));
            testCase.verifyEqual(string(toolsHandles("parsed-PreviewLabel").Text), ...
                "Figure tools are ignored in Safe Preview.");
            testCase.verifyFalse(isKey(toolsHandles, "parsed-FileMenu"));
            testCase.verifyFalse(isKey(toolsHandles, "parsed-Toolbar"));
            clear toolsCleanup previewCleanup
        end

        function constrainedControlsRenderWithoutPositionWarnings(testCase)
            % constrainedControlsRenderWithoutPositionWarnings Verify safe Position writes.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ConstraintApp", registry);
            document.insertComponent(registry, "uislider", document.RootComponentId);
            document.insertComponent(registry, "uiswitch", document.RootComponentId);
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            panel = uipanel(figure, "Position", [1 1 700 500]);
            renderer = macd.ui.PreviewRenderer(registry);
            lastwarn("");
            [~, diagnostics] = renderer.render(document, panel);
            [warningMessage, ~] = lastwarn;
            testCase.verifyEmpty(diagnostics);
            testCase.verifyEmpty(warningMessage);
            clear cleanup
        end
    end

    methods (Access = private)
        function compareFixture(testCase, fixturePath)
            % compareFixture Compare one trusted app instance with its safe preview.
            arguments (Input)
                testCase (1, 1) PreviewRendererTest
                fixturePath (1, 1) string
            end

            % Render only the parsed model into an editor-owned hidden surface.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseFile(fixturePath, registry);
            previewFigure = uifigure("Visible", "off");
            previewPanel = uipanel(previewFigure);
            previewCleanup = onCleanup(@() deleteIfValid(previewFigure));
            renderer = macd.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, previewPanel);
            testCase.verifyEmpty(diagnostics, fixturePath);

            % Execute only the maintained fixture named in the explicit trusted list.
            fixtureFolder = fileparts(fixturePath);
            addpath(fixtureFolder);
            pathCleanup = onCleanup(@() rmpath(fixtureFolder));
            actual = feval(char(document.ClassName));
            actual.UIFigure.Visible = "off";
            actualCleanup = onCleanup(@() deleteIfValid(actual));

            % Traverse the model rather than hard-coding component or property names.
            for componentIndex = 1:numel(document.Components)
                component = document.Components(componentIndex);
                if component.Id == document.RootComponentId
                    continue
                end
                testCase.assertTrue(isKey(handles, char(component.Id)), ...
                    fixturePath + ": preview is missing " + component.Name);
                preview = handles(char(component.Id));
                actualComponent = actual.(char(component.Name));
                for propertyIndex = 1:numel(component.Properties)
                    entry = component.Properties(propertyIndex);
                    if entry.ValueKind ~= "literal" || ~entry.IsEditable
                        continue
                    end
                    testCase.compareProperty(preview, actualComponent, entry.Path, ...
                        fixturePath + ": " + component.Name + "." + entry.Path);
                end
            end
            clear actualCleanup pathCleanup previewCleanup
        end

        function compareProperty(testCase, preview, actual, path, context)
            % compareProperty Compare one direct or nested property after text normalization.
            arguments (Input)
                testCase (1, 1) PreviewRendererTest
                preview
                actual
                path (1, 1) string
                context (1, 1) string
            end

            % Read both paths directly from controls after normalizing text containers.
            previewValue = PreviewRendererTest.propertyValue(preview, path);
            actualValue = PreviewRendererTest.propertyValue(actual, path);
            testCase.verifyEqual(PreviewRendererTest.normalizeText(previewValue), ...
                PreviewRendererTest.normalizeText(actualValue), context);
        end

        function [document, handles, diagnostics, panel] = renderFixture( ...
                testCase, registry, fixtureFolder, fixtureName, previewFigure)
            % renderFixture Render one maintained fixture into a disposable preview panel.
            arguments (Input)
                testCase (1, 1) PreviewRendererTest %#ok<INUSA>
                registry (1, 1) macd.model.ComponentRegistry
                fixtureFolder (1, 1) string
                fixtureName (1, 1) string
                previewFigure (1, 1) matlab.ui.Figure
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                handles containers.Map
                diagnostics macd.model.Diagnostic
                panel (1, 1) matlab.ui.container.Panel
            end

            % Keep each fixture isolated while sharing a stable editor-sized surface.
            document = macd.source.AppSourceParser.parseFile( ...
                fullfile(fixtureFolder, fixtureName + ".m"), registry);
            panel = uipanel(previewFigure, "Position", [1 1 900 700]);
            renderer = macd.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, panel);
        end
    end

    methods (Static, Access = private)
        function fixtures = trustedFixtures()
            % trustedFixtures List only repository-managed apps allowed to execute in tests.
            arguments (Output)
                fixtures (1, :) struct
            end

            % Adding a fixture here opts it into runtime-oracle comparison explicitly.
            testPath = mfilename("fullpath");
            projectRoot = fileparts(fileparts(fileparts(testPath)));
            fixtures = struct("Path", string(fullfile(projectRoot, "tests", ...
                "fixtures", "SimpleCalculatorApp.m")));
        end

        function value = propertyValue(target, path)
            % propertyValue Read one direct or nested graphics property by model path.
            arguments (Input)
                target
                path (1, 1) string
            end
            arguments (Output)
                value
            end

            % Follow each safe model path segment without evaluating source text.
            value = target;
            parts = split(path, ".");
            for partIndex = 1:numel(parts)
                value = value.(char(parts(partIndex)));
            end
        end

        function value = normalizeText(value)
            % normalizeText Make equivalent UI text container representations comparable.
            arguments (Input)
                value
            end
            arguments (Output)
                value
            end

            % MATLAB UI APIs accept either char cells or string arrays for text lists.
            if ischar(value)
                value = string(value);
            elseif iscell(value) && all(cellfun(@(item) ...
                    ischar(item) || (isstring(item) && isscalar(item)), value))
                value = string(value);
            end
        end
    end
end

function deleteIfValid(value)
% deleteIfValid Delete one graphics or AppBase handle when it remains valid.
arguments (Input)
    value
end

% Keep cleanup idempotent after assertion failures and partial construction.
if isvalid(value)
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

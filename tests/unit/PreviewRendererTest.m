classdef (TestTags = {'preview', 'ui'}) PreviewRendererTest < matlab.unittest.TestCase
    % PreviewRendererTest Compare safe previews against trusted fixture applications.
    %   This data-driven test parses each explicitly trusted fixture, renders its
    %   model without executing source, then compares every supported editable
    %   literal property with a separate runtime instance of that known fixture.
    %   It never permits the editor to execute arbitrary opened source.

    methods (Test, TestTags = {'fast'})
        function safePreviewMatchesTrustedFixtureProperties(testCase)
            % safePreviewMatchesTrustedFixtureProperties Compare every trusted fixture.

            % Keep fixture execution explicit while rendering always uses parsed data.
            fixtures = PreviewRendererTest.trustedFixtures();
            for fixtureIndex = 1:numel(fixtures)
                fixture = fixtures(fixtureIndex);
                testCase.compareFixture(string(fixture.Path));
            end
        end
    end

    methods (Test)
        function preservesNewerControlsAsLabelsInOlderPreview(testCase)
            % preservesNewerControlsAsLabelsInOlderPreview Check source-owned grid and absolute placement.

            % Render all three fixture surfaces against the oldest runtime catalog.
            registry = yamada.catalog.ComponentCatalogLoader.load(fullfile( ...
                fileparts(yamada.catalog.ComponentCatalogLoader.defaultCatalogRoot()), "R2023a"));
            fixtureFolder = fullfile(fileparts(fileparts(mfilename("fullpath"))), "fixtures");
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            panel = uipanel(figure, "AutoResizeChildren", "off");
            renderer = yamada.ui.PreviewRenderer(registry);
            folders = [fullfile(fixtureFolder, "R2023a"), fullfile(fixtureFolder, "R2023b"), fixtureFolder];
            for index = 1:numel(folders)
                path = fullfile(folders(index), "ControlGalleryApp.m");
                document = yamada.source.AppSourceParser.parseFile(path, registry);
                [handles, diagnostics] = renderer.render(document, panel);
                testCase.verifyFalse(any(string({diagnostics.Code}) == "preview-render-failed"));
                slider = handles("parsed-IntensitySlider");
                if index == 1
                    testCase.verifyClass(slider, "matlab.ui.control.Slider");
                else
                    testCase.verifyClass(slider, "matlab.ui.control.Label");
                    testCase.verifySubstring(string(slider.Text), "R2023b");
                end
                testCase.verifyEqual(slider.Layout.Row, 4);
                testCase.verifyEqual(slider.Layout.Column, [1 2]);
                if index == 3
                    picker = handles("parsed-AccentColorPicker");
                    testCase.verifyClass(picker, "matlab.ui.control.Label");
                    testCase.verifySubstring(string(picker.Text), "R2024a");
                    testCase.verifyEqual(picker.Layout.Row, 2);
                    testCase.verifyEqual(picker.Layout.Column, 1);
                end
            end

            % Parse an absolute child through the same model and preview entry points.
            source = join(["classdef ReleaseExample < handle", "methods", ...
                "function app = ReleaseExample", "app.Figure = uifigure();", ...
                "app.Picker = uicolorpicker(app.Figure, Position=[20 30 140 25]);", ...
                "end", "end", "end"], newline);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            handles = renderer.render(document, panel);
            testCase.verifyEqual(handles("parsed-Picker").Position, [20 30 140 25]);

            % Replay implicit allocation before a sibling's later explicit move.
            source = join(["classdef ReleaseExample < handle", "methods", ...
                "function app = ReleaseExample", "app.Figure = uifigure();", ...
                "app.Grid = uigridlayout(app.Figure, [2 2]);", ...
                "app.First = uilabel(app.Grid);", "app.Picker = uicolorpicker(app.Grid);", ...
                "app.First.Layout.Row = 2;", "app.First.Layout.Column = 2;", ...
                "app.Last = uilabel(app.Grid);", "end", "end", "end"], newline);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            handles = renderer.render(document, panel);
            testCase.verifyEqual(handles("parsed-Picker").Layout.Row, 1);
            testCase.verifyEqual(handles("parsed-Picker").Layout.Column, 2);
            testCase.verifyEqual(handles("parsed-Last").Layout.Row, 3);
            testCase.verifyEqual(handles("parsed-Last").Layout.Column, 1);
            clear cleanup
        end

        function actualSizeFixturesKeepCanvasAndEdgeControlsUnscaled(testCase)
            % actualSizeFixturesKeepCanvasAndEdgeControlsUnscaled Cover fit and overflow.
            registry = yamada.model.ComponentRegistry.createDefault();
            testPath = mfilename("fullpath");
            fixtureFolder = fullfile(fileparts(fileparts(fileparts(testPath))), ...
                "tests", "fixtures");
            figure = uifigure("Visible", "off", "Position", [100 100 750 550]);
            cleanup = onCleanup(@() deleteIfValid(figure));
            cases = {"SmallPreviewFixtureApp", [320 240], [220 10 90 26]; ...
                "LargePreviewFixtureApp", [1200 900], [1070 12 116 28]};

            for index = 1:size(cases, 1)
                document = yamada.source.AppSourceParser.parseFile( ...
                    fullfile(fixtureFolder, cases{index, 1} + ".m"), registry);
                testCase.verifyEmpty(document.Diagnostics);
                panel = uipanel(figure, "Position", [1 1 700 500], ...
                    "Scrollable", "on", "AutoResizeChildren", "off");
                panelCleanup = onCleanup(@() deleteIfValid(panel));
                renderer = yamada.ui.PreviewRenderer(registry);
                [handles, diagnostics, canvas] = renderer.render(document, panel);
                testCase.verifyEmpty(diagnostics);
                testCase.verifyEqual(canvas.Position, [2 2 cases{index, 2}]);
                testCase.verifyEqual(canvas.Parent.Position(3:4), cases{index, 2} + 2);
                content = canvas.Parent.Parent;
                frameSize = canvas.Parent.Position(3:4);
                testCase.verifyEqual(content.Position(3:4), ...
                    max(double(panel.InnerPosition(3:4)), frameSize + 24));
                testCase.verifyEqual(canvas.Parent.Position(1:2), ...
                    floor((content.Position(3:4) - frameSize) ./ 2) + 1);
                if index == 1
                    testCase.verifyEqual(canvas.BackgroundColor, [0.88 0.92 0.96]);
                end
                testCase.verifyEqual(handles("parsed-BottomRightButton").Position, ...
                    cases{index, 3});
                testCase.verifyEqual(handles("parsed-CenterPanel").Parent, canvas);
                testCase.verifyEqual(handles("parsed-CenterGrid").Parent, ...
                    handles("parsed-CenterPanel"));
                clear panelCleanup
            end
            clear cleanup
        end

        function safePreviewRendersExtendedFixtureSemantics(testCase)
            % safePreviewRendersExtendedFixtureSemantics Cover string lists, axes, and tools.

            % Render the source-derived models without executing any of these fixtures.
            registry = yamada.model.ComponentRegistry.createDefault();
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
            testCase.verifyEqual(previewSurface.Position, [2 2 sourceSize]);
            testCase.verifyEqual(previewSurface.Parent.Position(3:4), sourceSize + 2);
            clear controlCleanup

            % Keep pixel axes at their source dimensions on the actual-size canvas.
            [axesDocument, axesHandles, axesDiagnostics, axesPanel] = ...
                testCase.renderFixture(registry, fixtureFolder, "AxesExplorerApp", previewFigure);
            axesCleanup = onCleanup(@() deleteIfValid(axesPanel));
            testCase.verifyEqual(string({axesDocument.Diagnostics.Code}), "unresolved-initialization-call");
            testCase.verifyEqual(axesDocument.Diagnostics.Severity, "warning");
            testCase.verifySubstring(axesDocument.Diagnostics.Message, "geolimits");
            testCase.verifyEmpty(axesDiagnostics);
            testCase.verifyEqual(axesHandles("parsed-UIAxes").Position, ...
                [20 230 340 180]);
            testCase.verifyEqual(axesHandles("parsed-StandardAxes").Position, ...
                [0.55 0.55 0.35 0.35]);
            clear axesCleanup

            % Parse the table headers rather than retaining their source expression.
            [navigationDocument, navigationHandles, navigationDiagnostics, navigationPanel] = ...
                testCase.renderFixture(registry, fixtureFolder, "NavigationDataApp", previewFigure);
            navigationCleanup = onCleanup(@() deleteIfValid(navigationPanel));
            testCase.verifyEmpty(navigationDocument.Diagnostics);
            testCase.verifyTrue(navigationDocument.Metadata.HasUnresolvedExecutableEffects);
            testCase.assertNotEmpty(navigationDiagnostics);
            testCase.verifyTrue(all(string({navigationDiagnostics.Severity}) == "warning"));
            testCase.verifyTrue(all(ismember(string({navigationDiagnostics.Code}), ...
                ["preview-position-unknown", "preview-grid-unknown"])));
            testCase.verifyEqual(string(navigationHandles("parsed-CatalogTable").ColumnName), ...
                ["Title"; "Rating"]);
            clear navigationCleanup

            % Ignore figure-only tools while retaining ordinary controls on the surface.
            [toolsDocument, toolsHandles, toolsDiagnostics, toolsPanel] = ...
                testCase.renderFixture(registry, fixtureFolder, "FigureToolsApp", previewFigure);
            toolsCleanup = onCleanup(@() deleteIfValid(toolsPanel));
            testCase.verifyEmpty(toolsDocument.Diagnostics);
            testCase.verifyEqual(string({toolsDiagnostics.Code}), "preview-position-unknown");
            testCase.verifyEqual(string({toolsDiagnostics.Severity}), "warning");
            testCase.verifyEqual(numEntries(toolsHandles), 1);
            testCase.verifyTrue(isKey(toolsHandles, "parsed-PreviewLabel"));
            testCase.verifyEqual(string(toolsHandles("parsed-PreviewLabel").Text), ...
                "Figure tools are ignored in Safe Preview.");
            testCase.verifyFalse(isKey(toolsHandles, "parsed-FileMenu"));
            testCase.verifyFalse(isKey(toolsHandles, "parsed-Toolbar"));
            clear toolsCleanup previewCleanup
        end

        function constrainedControlsRenderWithoutPositionWarnings(testCase)
            % constrainedControlsRenderWithoutPositionWarnings Verify safe Position writes.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ConstraintApp", registry);
            document.insertComponent(registry, "uislider", document.RootComponentId);
            document.insertComponent(registry, "uiswitch", document.RootComponentId);
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            panel = uipanel(figure, "Position", [1 1 700 500]);
            renderer = yamada.ui.PreviewRenderer(registry);
            lastwarn("");
            [~, diagnostics] = renderer.render(document, panel);
            [warningMessage, ~] = lastwarn;
            testCase.verifyEmpty(diagnostics);
            testCase.verifyEmpty(warningMessage);
            clear cleanup
        end

        function styleSpecificSwitchesUseNaturalPreviewSize(testCase)
            % styleSpecificSwitchesUseNaturalPreviewSize Keep vertical switch variants compact.

            % Render both vertical variants through the catalog-backed insertion path.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("SwitchPreviewApp", registry);
            rocker = registry.getById("uiswitch-rocker");
            toggle = registry.getById("uiswitch-toggle");
            rockerComponent = document.insertComponent(registry, rocker.Factory, ...
                document.RootComponentId, rocker.CreationArguments);
            toggleComponent = document.insertComponent(registry, toggle.Factory, ...
                document.RootComponentId, toggle.CreationArguments);
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            panel = uipanel(figure, "Position", [1 1 700 500]);
            renderer = yamada.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, panel);

            testCase.verifyEmpty(diagnostics);
            for id = [rockerComponent.Id, toggleComponent.Id]
                position = double(handles(id).Position);
                testCase.verifyEqual(position(3) / position(4), 20 / 45, "AbsTol", 1e-10);
                testCase.verifyLessThan(position(4), 60);
            end
            clear cleanup
        end

        function itemSelectionDependenciesRenderBeforeValue(testCase)
            % itemSelectionDependenciesRenderBeforeValue Render mapped and multiselect values.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ItemSelectionApp", registry);
            dropDown = document.insertComponent(registry, "uidropdown", document.RootComponentId);
            listBox = document.insertComponent(registry, "uilistbox", document.RootComponentId);
            % Deliberately store the dependent value first; PreviewRenderer must
            % still apply Items, ItemsData, and Multiselect before it.
            dropDown.setProperty("Value", 20);
            dropDown.setProperty("ItemsData", [10 20]);
            dropDown.setProperty("Items", ["First", "Second"]);
            listBox.setProperty("Value", [10 30]);
            listBox.setProperty("ItemsData", [10 20 30]);
            listBox.setProperty("Items", ["One", "Two", "Three"]);
            listBox.setProperty("Multiselect", "on");

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            panel = uipanel(figure, "Position", [1 1 700 500]);
            renderer = yamada.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, panel);

            testCase.verifyEmpty(diagnostics);
            testCase.verifyEqual(handles(dropDown.Id).Value, 20);
            testCase.verifyEqual(handles(listBox.Id).Value, [10 30]);
            clear cleanup
        end

        function imageSourceRendersFromOpenedAppFolder(testCase)
            % imageSourceRendersFromOpenedAppFolder Resolve a relative image beside the app source.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ImagePreviewApp", registry);
            imageComponent = document.insertComponent(registry, "uiimage", ...
                document.RootComponentId);
            imagePath = string(tempname) + ".png";
            imageCleanup = onCleanup(@() delete(imagePath));
            imwrite(uint8([255 0; 0 255]), imagePath);
            [folder, name, extension] = fileparts(imagePath);
            document.FilePath = fullfile(folder, "ImagePreviewApp.m");
            document.setProperty(imageComponent.Id, "ImageSource", name + extension);

            figure = uifigure("Visible", "off");
            figureCleanup = onCleanup(@() deleteIfValid(figure));
            panel = uipanel(figure, "Position", [1 1 700 500]);
            renderer = yamada.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, panel);

            testCase.verifyEmpty(diagnostics);
            testCase.verifyEqual(string(handles(imageComponent.Id).ImageSource), imagePath);
            clear figureCleanup imageCleanup
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
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.source.AppSourceParser.parseFile(fixturePath, registry);
            previewFigure = uifigure("Visible", "off");
            previewPanel = uipanel(previewFigure);
            previewCleanup = onCleanup(@() deleteIfValid(previewFigure));
            renderer = yamada.ui.PreviewRenderer(registry);
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
                testCase.assertTrue(isKey(handles, component.Id), ...
                    fixturePath + ": preview is missing " + component.Name);
                preview = handles(component.Id);
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
                registry (1, 1) yamada.model.ComponentRegistry
                fixtureFolder (1, 1) string
                fixtureName (1, 1) string
                previewFigure (1, 1) matlab.ui.Figure
            end
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                handles dictionary
                diagnostics yamada.model.Diagnostic
                panel (1, 1) matlab.ui.container.Panel
            end

            % Keep each fixture isolated while sharing a stable editor-sized surface.
            % Fixtures in the shared folder may have variants for older release catalogs.
            path = fullfile(fixtureFolder, fixtureName + ".m");
            if isfile(path), path = yamadaFixturePath(fixtureName + ".m"); end
            document = yamada.source.AppSourceParser.parseFile(path, registry);
            panel = uipanel(previewFigure, "Position", [1 1 900 700]);
            renderer = yamada.ui.PreviewRenderer(registry);
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
% deleteIfValid Delete one graphics or handle-based handle when it remains valid.
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

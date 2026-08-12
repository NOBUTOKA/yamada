classdef AppSourceParserTest < matlab.unittest.TestCase
    % AppSourceParserTest Verify conservative read-only AppBase source parsing.
    %   This test class parses fixtures without running their constructors and
    %   verifies component hierarchy, literals, source expressions, diagnostics,
    %   and source-span retention.

    methods (Test)
        function parsesSimpleCalculatorFixtureIntoSharedModel(testCase)
            % parsesSimpleCalculatorFixtureIntoSharedModel Parse supported fixture.

            % Read the preserved fixture without adding it to the MATLAB path.
            fixturePath = AppSourceParserTest.fixturePath("SimpleCalculatorApp.m");
            registry = macd.model.ComponentRegistry.createDefault();
            [document, diagnostics] = macd.source.AppSourceParser.parseFile( ...
                fixturePath, registry);

            % Verify class identity, source preservation, and hierarchy recovery.
            testCase.verifyEqual(document.ClassName, "SimpleCalculatorApp");
            testCase.verifyEqual(document.FilePath, fixturePath);
            testCase.verifySubstring(document.OriginalText, ...
                "classdef SimpleCalculatorApp < matlab.apps.AppBase");
            testCase.verifyEqual(document.LineEnding, "CRLF");
            testCase.verifyEqual(numel(document.Components), 11);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));

            root = document.getComponentByName("UIFigure");
            grid = document.getComponentByName("GridLayout");
            label = document.getComponentByName("LeftValueLabel");
            testCase.verifyEqual(root.Factory, "uifigure");
            testCase.verifyEqual(grid.ParentId, root.Id);
            testCase.verifyEqual(label.ParentId, grid.Id);
            testCase.verifyTrue(root.SourceSpans.Declaration.isKnown());
            testCase.verifyTrue(root.SourceSpans.Creation.isKnown());
        end

        function parsesSafeLiteralsAndRetainsCallbackExpression(testCase)
            % parsesSafeLiteralsAndRetainsCallbackExpression Check value handling.

            % Parse values from the same fixture through the shared document model.
            fixturePath = AppSourceParserTest.fixturePath("SimpleCalculatorApp.m");
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseFile(fixturePath, registry);
            label = document.getComponentByName("LeftValueLabel");
            dropDown = document.getComponentByName("OperatorDropDown");
            button = document.getComponentByName("CalculateButton");

            % Editable literals preserve their values and assignment source spans.
            text = label.getProperty("Text");
            items = dropDown.getProperty("Items");
            testCase.verifyEqual(text.LiteralValue, 'Left value');
            testCase.verifyTrue(text.SourceSpan.isKnown());
            testCase.verifyEqual(items.LiteralValue, ...
                {'Add', 'Subtract', 'Multiply', 'Divide'});

            % Callback code remains source-backed and cannot become editable.
            callback = button.getProperty("ButtonPushedFcn");
            testCase.verifyEqual(callback.ValueKind, "expression");
            testCase.verifyFalse(callback.IsEditable);
            testCase.verifySubstring(callback.SourceExpression, ...
                "createCallbackFcn(");
            testCase.verifyTrue(any([document.UnknownRegions.Reason] == ...
                "source-expression"));
        end

        function parsesContinuationSeparatedCreationArguments(testCase)
            % parsesContinuationSeparatedCreationArguments Parse multiline safe factory values.

            % Keep the continuation inside parentheses to match normal AppBase formatting.
            source = strjoin([ ...
                "classdef ContinuedApp < matlab.apps.AppBase", ...
                "    properties", ...
                "        UIFigure matlab.ui.Figure", ...
                "    end", ...
                "    methods", ...
                "        function createComponents(app)", ...
                "            app.UIFigure = uifigure(""Visible"", ""off"", ...", ...
                "                ""Position"", [100 100 320 240]);", ...
                "        end", ...
                "    end", ...
                "end"], newline);
            registry = macd.model.ComponentRegistry.createDefault();
            [document, diagnostics] = macd.source.AppSourceParser.parseText(source, registry);

            % Recover the root and its literal constructor values without evaluation.
            root = document.getComponentByName("UIFigure");
            testCase.verifyFalse(isempty(root));
            testCase.verifyEqual(root.Factory, "uifigure");
            testCase.verifyEqual(root.CreationArguments, ...
                {"Visible", "off", "Position", [100 100 320 240]});
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function retainsConditionalAssignmentsWithoutOverwritingExpressions(testCase)
            % retainsConditionalAssignmentsWithoutOverwritingExpressions Preserve branch ambiguity.

            % Model both branches without evaluating which assignment executes at runtime.
            source = strjoin([ ...
                "classdef ConditionalApp < matlab.apps.AppBase", ...
                "    properties", ...
                "        UIFigure matlab.ui.Figure", ...
                "        StatusLabel matlab.ui.control.Label", ...
                "    end", ...
                "    methods", ...
                "        function createComponents(app)", ...
                "            app.UIFigure = uifigure();", ...
                "            app.StatusLabel = uilabel(app.UIFigure);", ...
                "            if true", ...
                "                app.StatusLabel.Text = compose(""Count %d"", 1);", ...
                "            else", ...
                "                app.StatusLabel.Text = ""Ready"";", ...
                "            end", ...
                "        end", ...
                "    end", ...
                "end"], newline);
            registry = macd.model.ComponentRegistry.createDefault();
            [document, diagnostics] = macd.source.AppSourceParser.parseText(source, registry);

            % Preserve the first opaque value and retain the alternate branch as unknown source.
            statusLabel = document.getComponentByName("StatusLabel");
            entry = statusLabel.getProperty("Text");
            testCase.verifyEqual(entry.ValueKind, "expression");
            testCase.verifyEqual(entry.SourceExpression, "compose(""Count %d"", 1)");
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyTrue(any([diagnostics.Code] == ...
                "conflicting-property-assignment"));
        end

        function retainsSafeCreationPairsWhileSkippingCallbackPairs(testCase)
            % retainsSafeCreationPairsWhileSkippingCallbackPairs Preserve renderable inputs.

            % Keep safe constructor pairs while leaving callbacks unevaluated and absent.
            source = strjoin([ ...
                "classdef CreationPairApp < matlab.apps.AppBase", ...
                "    properties", ...
                "        UIFigure matlab.ui.Figure", ...
                "        RunButton matlab.ui.control.Button", ...
                "        ResultTable matlab.ui.control.Table", ...
                "    end", ...
                "    methods", ...
                "        function createComponents(app)", ...
                "            app.UIFigure = uifigure();", ...
                "            app.RunButton = uibutton(app.UIFigure, ""Text"", ""Run"", ...", ...
                "                ""ButtonPushedFcn"", @(~, ~) disp(""run""));", ...
                "            app.ResultTable = uitable(app.UIFigure, ...", ...
                "                ""ColumnEditable"", [true false]);", ...
                "        end", ...
                "    end", ...
                "end"], newline);
            registry = macd.model.ComponentRegistry.createDefault();
            [document, diagnostics] = macd.source.AppSourceParser.parseText(source, registry);

            % Confirm source callbacks do not prevent the renderable control model.
            runButton = document.getComponentByName("RunButton");
            resultTable = document.getComponentByName("ResultTable");
            testCase.verifyFalse(isempty(runButton));
            testCase.verifyEqual(runButton.CreationArguments, {"Text", "Run"});
            testCase.verifyFalse(isempty(resultTable));
            testCase.verifyEqual(resultTable.CreationArguments, ...
                {"ColumnEditable", [true false]});
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyTrue(any([diagnostics.Code] == "source-creation-property"));
        end

        function parsesExtendedComponentFixtures(testCase)
            % parsesExtendedComponentFixtures Parse representative component sets.

            % Keep each registry category covered by a non-executing source fixture.
            fixtureNames = ["ControlGalleryApp.m", "NavigationDataApp.m", ...
                "AxesExplorerApp.m", "FigureToolsApp.m"];
            expectedComponentCounts = [16 19 5 9];
            registry = macd.model.ComponentRegistry.createDefault();

            % Verify class identity and lossless structural recovery per fixture.
            for index = 1:numel(fixtureNames)
                fixturePath = AppSourceParserTest.fixturePath(fixtureNames(index));
                [document, diagnostics] = macd.source.AppSourceParser.parseFile( ...
                    fixturePath, registry);
                expectedClassName = erase(fixtureNames(index), ".m");
                testCase.verifyEqual(document.ClassName, expectedClassName);
                testCase.verifyEqual(numel(document.Components), ...
                    expectedComponentCounts(index));
                testCase.verifyFalse( ...
                    macd.validation.ModelValidator.hasErrors(diagnostics));
            end
        end

        function retainsUnknownCreationPairsWithoutDroppingComponent(testCase)
            % retainsUnknownCreationPairsWithoutDroppingComponent Preserve unknown callbacks.

            % Unknown factory properties must not discard an otherwise supported control.
            source = strjoin([ ...
                "classdef UnknownCreationPairApp < matlab.apps.AppBase", ...
                "    properties", ...
                "        UIFigure matlab.ui.Figure", ...
                "    end", ...
                "    methods", ...
                "        function createComponents(app)", ...
                "            app.UIFigure = uifigure(""Name"", ""Example"", ...", ...
                "                ""WindowKeyPressFcn"", @(~, event) disp(event.Key));", ...
                "        end", ...
                "    end", ...
                "end"], newline);
            registry = macd.model.ComponentRegistry.createDefault();
            [document, diagnostics] = macd.source.AppSourceParser.parseText(source, registry);

            % Keep supported literals while retaining the callback as opaque source.
            root = document.getComponentByName("UIFigure");
            testCase.verifyNotEmpty(root);
            testCase.verifyEqual(root.CreationArguments, {"Name", "Example"});
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyTrue(any([diagnostics.Code] == "source-creation-property"));
        end

        function parsesEditorOwnAppBaseSource(testCase)
            % parsesEditorOwnAppBaseSource Verify the editor source remains openable.

            % Use the production source as a regression fixture without executing it.
            projectRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            sourcePath = string(fullfile(projectRoot, "MatlabAppClassDesigner.m"));
            registry = macd.model.ComponentRegistry.createDefault();
            [document, diagnostics] = macd.source.AppSourceParser.parseFile(sourcePath, registry);

            % Recover an editable root despite source-only callback properties.
            testCase.verifyEqual(document.ClassName, "MatlabAppClassDesigner");
            testCase.verifyNotEmpty(document.getComponentByName("UIFigure"));
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function parserNeverExecutesInputSource(testCase)
            % parserNeverExecutesInputSource Check parsing remains read-only.

            % Include a constructor error that would fail immediately if executed.
            source = [ ...
                "classdef NonExecutingApp < matlab.apps.AppBase", newline, ...
                "    properties", newline, ...
                "        UIFigure matlab.ui.Figure", newline, ...
                "    end", newline, ...
                "    methods", newline, ...
                "        function app = NonExecutingApp", newline, ...
                "            error(""AppSourceParserTest:Executed"", ""Must not run"");", newline, ...
                "        end", newline, ...
                "        function createComponents(app)", newline, ...
                "            app.UIFigure = uifigure(""Visible"", ""off"");", newline, ...
                "        end", newline, ...
                "    end", newline, ...
                "end", newline];
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(source, registry);

            % Successful recovery proves the source was inspected rather than run.
            testCase.verifyEqual(document.ClassName, "NonExecutingApp");
            testCase.verifyNotEmpty(document.getComponentByName("UIFigure"));
        end

        function parseFileRejectsMissingPathsAndDirectories(testCase)
            % parseFileRejectsMissingPathsAndDirectories Validate file inputs early.

            % Supply a nonexistent path and a directory instead of a source file.
            registry = macd.model.ComponentRegistry.createDefault();
            missingPath = string(tempname) + ".m";
            inputPaths = [missingPath string(tempdir)];

            % Confirm argument validation rejects both invalid file-path forms.
            for inputPath = inputPaths
                caughtException = MException.empty;
                try
                    macd.source.AppSourceParser.parseFile(inputPath, registry);
                catch exception
                    caughtException = exception;
                end
                testCase.verifyNotEmpty(caughtException);
            end
        end

        function parseFileRejectsInvalidUtf8(testCase)
            % parseFileRejectsInvalidUtf8 Block source that cannot decode losslessly.

            % Write a malformed byte after an otherwise plausible AppBase header.
            sourceBytes = [unicode2native( ...
                "classdef EncodingApp < matlab.apps.AppBase", "UTF-8") ...
                uint8(255)];
            fixturePath = AppSourceParserTest.writeTemporaryBytes(sourceBytes);
            cleanup = onCleanup(@() deleteIfPresent(fixturePath));
            registry = macd.model.ComponentRegistry.createDefault();

            % Report an error without constructing editable component records.
            [document, diagnostics] = macd.source.AppSourceParser.parseFile( ...
                fixturePath, registry);
            encodingDiagnostic = diagnostics([diagnostics.Code] == "invalid-utf8");
            testCase.verifyEqual(encodingDiagnostic.Severity, "error");
            testCase.verifyEmpty(document.Components);
            clear cleanup
        end

        function parseFilePreservesLfLineEndings(testCase)
            % parseFilePreservesLfLineEndings Keep the opened source convention.

            % Store a valid UTF-8 AppBase source using LF line endings only.
            source = strjoin(["classdef LfApp < matlab.apps.AppBase", ...
                "properties", "UIFigure matlab.ui.Figure", "end", "methods", ...
                "function createComponents(app)", ...
                "app.UIFigure = uifigure();", "end", "end", "end"], newline) + ...
                newline;
            fixturePath = AppSourceParserTest.writeTemporaryBytes( ...
                unicode2native(source, "UTF-8"));
            cleanup = onCleanup(@() deleteIfPresent(fixturePath));
            registry = macd.model.ComponentRegistry.createDefault();

            % Do not normalize an opened LF source to the new-document default.
            document = macd.source.AppSourceParser.parseFile(fixturePath, registry);
            testCase.verifyEqual(document.LineEnding, "LF");
            clear cleanup
        end
    end

    methods (Static, Access = private)
        function result = fixturePath(name)
            % fixturePath Resolve one preserved parser fixture by file name.
            arguments (Input)
                name string
            end
            arguments (Output)
                result string
            end

            % Resolve from this test location so tests run from any work folder.
            testPath = mfilename("fullpath");
            testRoot = fileparts(fileparts(testPath));
            result = string(fullfile(testRoot, "fixtures", name));
        end

        function filePath = writeTemporaryBytes(bytes)
            % writeTemporaryBytes Create one isolated raw-byte parser fixture.
            arguments (Input)
                bytes uint8
            end
            arguments (Output)
                filePath string
            end

            % Preserve the requested test bytes without text-mode translation.
            filePath = string(tempname) + ".m";
            fileId = fopen(filePath, "wb");
            cleanup = onCleanup(@() fclose(fileId));
            fwrite(fileId, bytes, "uint8");
            clear cleanup
        end
    end
end

function deleteIfPresent(filePath)
% deleteIfPresent Remove a temporary parser fixture when it remains on disk.
arguments (Input)
    filePath string
end

% Keep cleanup idempotent after a test interruption or partial setup.
if isfile(filePath)
    delete(filePath);
end
end

%{
MatlabAppClassDesigner - Tests for conservative read-only AppBase parsing.
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

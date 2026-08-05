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
            testCase.verifyEqual(text.LiteralValue, "Left value");
            testCase.verifyTrue(text.SourceSpan.isKnown());
            testCase.verifyEqual(items.LiteralValue, ...
                {"Add", "Subtract", "Multiply", "Divide"});

            % Callback code remains source-backed and cannot become editable.
            callback = button.getProperty("ButtonPushedFcn");
            testCase.verifyEqual(callback.ValueKind, "expression");
            testCase.verifyFalse(callback.IsEditable);
            testCase.verifySubstring(callback.SourceExpression, ...
                "createCallbackFcn(");
            testCase.verifyTrue(any([document.UnknownRegions.Reason] == ...
                "source-expression"));
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

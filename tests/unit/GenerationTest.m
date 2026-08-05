classdef GenerationTest < matlab.unittest.TestCase
    % GenerationTest Verify canonical new-app generation and source writing.
    %   This test class covers generated AppBase structure, safe literal output,
    %   blocking diagnostics, UTF-8 encoding, CRLF lines, and license isolation.

    methods (Test)
        function generatesMinimalRunnableClass(testCase)
            % generatesMinimalRunnableClass Verify the canonical AppBase skeleton.

            % Generate from the same empty model used by the future editor.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("GeneratedApp", registry);
            generator = macd.source.NewAppGenerator(registry);

            [source, diagnostics] = generator.generate(document);

            % Check required runtime structure, formatting, and license isolation.
            testCase.verifyGreaterThan(strlength(source), 0);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifySubstring(source, ...
                "classdef GeneratedApp < matlab.apps.AppBase");
            testCase.verifySubstring(source, ...
                "% GeneratedApp Define a programmatic AppBase application.");
            testCase.verifySubstring(source, ...
                "%       app = GeneratedApp();");
            testCase.verifySubstring(source, ...
                "app.UIFigure = uifigure(""Visible"", ""off"");");
            testCase.verifySubstring(source, ...
                "% UIFigure - Generated UI component handle.");
            testCase.verifySubstring(source, ...
                "arguments (Input)");
            testCase.verifySubstring(source, ...
                "arguments (Output)");
            testCase.verifySubstring(source, ...
                "% createComponents Create and configure UI components.");
            testCase.verifySubstring(source, ...
                "% GeneratedApp Construct and register the application.");
            testCase.verifySubstring(source, "registerApp(app, app.UIFigure);");
            testCase.verifySubstring(source, "delete(app.UIFigure);");
            if ispc
                testCase.verifyEmpty(regexp(source, "(?<!\r)\n", "once"));
            else
                testCase.verifyEmpty(regexp(source, "\r", "once"));
            end
            testCase.verifyEmpty(regexp(source, "GNU General Public License", "once"));
        end

        function generatesChildFromRegistryDrivenRecord(testCase)
            % generatesChildFromRegistryDrivenRecord Verify generic child output.

            % Add a registry-defined label to the shared document hierarchy.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("LabelApp", registry);
            definition = registry.get("uilabel");
            label = macd.model.ComponentRecord( ...
                "label-1", "GreetingLabel", definition.Factory, ...
                definition.DeclaredType, "generated");
            label.setProperty("Text", "It's ready");
            label.setProperty("Position", [20 20 100 22]);
            document.addComponent(label, document.RootComponentId);

            % Confirm parent calls and escaped literals in generated source.
            source = macd.source.NewAppGenerator(registry).generate(document);

            testCase.verifySubstring(source, ...
                "app.GreetingLabel = uilabel(app.UIFigure);");
            testCase.verifySubstring(source, ...
                "app.GreetingLabel.Text = ""It's ready"";");
        end

        function invalidClassNameBlocksGeneration(testCase)
            % invalidClassNameBlocksGeneration Verify fatal name validation.

            % Attempt generation from an intentionally invalid class identity.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("not valid", registry);

            [source, diagnostics] = macd.source.NewAppGenerator(registry).generate(document);

            testCase.verifyEqual(source, "");
            testCase.verifyTrue(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyEqual(diagnostics(1).Code, "invalid-class-name");
        end

        function writerUsesUtf8WithoutBomAndRequestedLineEnding(testCase)
            % writerUsesUtf8WithoutBomAndRequestedLineEnding Verify exact output bytes.

            % Prepare Unicode source and a recoverable temporary target.
            filePath = string(tempname) + ".m";
            cleanup = onCleanup(@() deleteIfPresent(filePath));
            japaneseText = string(char([26085 26412 35486]));
            source = compose("classdef JapaneseApp\n%% Japanese text: %s\nend\n", ...
                japaneseText);

            % Read raw bytes so encoding and newline assertions are independent.
            macd.source.SourceWriter.write(filePath, source, "LF");
            fileId = fopen(filePath, "r");
            closeFile = onCleanup(@() fclose(fileId));
            bytes = fread(fileId, Inf, "*uint8")';

            % Verify BOM absence, Unicode fidelity, and exact LF normalization.
            testCase.verifyFalse(numel(bytes) >= 3 && ...
                isequal(bytes(1:3), uint8([239 187 191])));
            text = string(native2unicode(bytes, "UTF-8"));
            testCase.verifySubstring(text, "Japanese text: " + japaneseText);
            testCase.verifyEmpty(regexp(text, "\r", "once"));
            expected = regexprep(source, "\r\n|\r|\n", newline);
            testCase.verifyEqual(text, expected);
            clear closeFile cleanup
        end

        function sourceExpressionIsNeverSilentlyGeneratedAsEmpty(testCase)
            % sourceExpressionIsNeverSilentlyGeneratedAsEmpty Verify safe failure.

            % Replace a safe literal with an unevaluated source expression.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ExpressionApp", registry);
            root = document.getComponent(document.RootComponentId);
            entry = root.getProperty("Name");
            entry.setSourceExpression("getAppName()");

            % Require an explicit diagnostic instead of destructive coercion.
            [source, diagnostics] = macd.source.NewAppGenerator(registry).generate(document);

            testCase.verifyEqual(source, "");
            testCase.verifyEqual(diagnostics(end).Code, ...
                "nonliteral-new-app-property");
        end
    end
end

function deleteIfPresent(filePath)
% deleteIfPresent Remove a temporary test file when it still exists.
arguments (Input)
    filePath string
end

% Keep test cleanup idempotent after partial failures.
if isfile(filePath)
    delete(filePath);
end
end

%{
MatlabAppClassDesigner - Tests for canonical new-app source generation.
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

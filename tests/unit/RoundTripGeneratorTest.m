classdef RoundTripGeneratorTest < matlab.unittest.TestCase
    % RoundTripGeneratorTest Verify conservative source-preserving rewrites.

    methods (Test)
        function noEditRoundTripPreservesExactSource(testCase)
            % noEditRoundTripPreservesExactSource Keep parsed bytes unchanged.

            [document, generator] = RoundTripGeneratorTest.parsedFixture();
            [source, diagnostics] = generator.generate(document);

            testCase.verifyEqual(source, document.OriginalText);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function propertyEditChangesOnlyOwnedAssignment(testCase)
            % propertyEditChangesOnlyOwnedAssignment Replace one direct literal value.

            [document, generator] = RoundTripGeneratorTest.parsedFixture();
            label = document.getComponentByName("LeftValueLabel");
            label.setProperty("Text", "First value");
            [source, diagnostics] = generator.generate(document);

            testCase.verifySubstring(source, "app.LeftValueLabel.Text = ""First value"";");
            testCase.verifySubstring(source, "app.CalculateButton.ButtonPushedFcn = createCallbackFcn(");
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function generatedComponentUsesAnchoredInsertion(testCase)
            % generatedComponentUsesAnchoredInsertion Add declaration and initialization.

            [document, generator] = RoundTripGeneratorTest.parsedFixture();
            parent = document.getComponentByName("GridLayout");
            component = macd.model.ComponentRecord("generated-status", "StatusLabel", ...
                "uilabel", "matlab.ui.control.Label", "generated");
            component.setProperty("Text", "Ready");
            document.addComponent(component, parent.Id);
            [source, diagnostics] = generator.generate(document);

            testCase.verifySubstring(source, "StatusLabel matlab.ui.control.Label");
            testCase.verifySubstring(source, "app.StatusLabel = uilabel(app.GridLayout);");
            testCase.verifySubstring(source, "app.StatusLabel.Text = ""Ready"";");
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function deletionRejectsExternalReference(testCase)
            % deletionRejectsExternalReference Block deletion when source uses the component.

            [document, generator] = RoundTripGeneratorTest.parsedFixture();
            source = document.OriginalText + newline + "app.LeftValueLabel.Visible = 'on';";
            document.OriginalText = source;
            document.removeComponent("parsed-LeftValueLabel");
            [generated, diagnostics] = generator.generate(document);

            testCase.verifyEqual(generated, source);
            testCase.verifyTrue(any([diagnostics.Code] == "ambiguous-component-deletion"));
        end

        function ownedLeafDeletionRemovesOnlyOwnedSource(testCase)
            % ownedLeafDeletionRemovesOnlyOwnedSource Remove an unreferenced leaf.

            [document, generator] = RoundTripGeneratorTest.parsedFixture();
            document.removeComponent("parsed-LeftValueLabel");
            [source, diagnostics] = generator.generate(document);

            testCase.verifyFalse(contains(source, "app.LeftValueLabel"));
            testCase.verifyFalse(contains(source, "LeftValueLabel  matlab.ui.control.Label"));
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
        end
    end

    methods (Static, Access = private)
        function [document, generator] = parsedFixture()
            % parsedFixture Load the preserved fixture and one shared generator.

            testPath = mfilename("fullpath");
            fixturePath = string(fullfile(fileparts(fileparts(testPath)), ...
                "fixtures", "SimpleCalculatorApp.m"));
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseFile(fixturePath, registry);
            generator = macd.source.RoundTripGenerator(registry);
        end
    end
end

%{
MatlabAppClassDesigner - Tests for conservative source round-trip generation.
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

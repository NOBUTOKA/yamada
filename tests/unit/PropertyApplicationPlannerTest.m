classdef (TestTags = {'fast', 'catalog', 'model', 'generation'}) PropertyApplicationPlannerTest < matlab.unittest.TestCase
    % PropertyApplicationPlannerTest Verify graph projection and shared generation order.
    %   These tests do not execute represented app source. Native setter checks
    %   are isolated in PropertyApplicationRuntimeTest.

    methods (Test)
        function projectsTransitiveEdgesWithoutChangingIndependentEntryOrder(testCase)
            % projectsTransitiveEdgesWithoutChangingIndependentEntryOrder Use graph closure without Inspector sorting.
            definitions = [ ...
                macd.model.PropertyDefinition("Prerequisite"), ...
                testCase.dependent("Intermediate", "Prerequisite"), ...
                testCase.dependent("Value", "Intermediate"), ...
                macd.model.PropertyDefinition("Text")];
            entries = [macd.model.PropertyEntry("Value", 3), ...
                macd.model.PropertyEntry("UnknownProperty", 4), ...
                macd.model.PropertyEntry("Text", "Keep order"), ...
                macd.model.PropertyEntry("Prerequisite", 1)];
            ordered = macd.model.PropertyApplicationPlanner.order(entries, definitions);
            testCase.verifyEqual(string({ordered.Path}), ...
                ["UnknownProperty", "Text", "Prerequisite", "Value"]);
            testCase.verifyEqual(string({entries.Path}), ...
                ["Value", "UnknownProperty", "Text", "Prerequisite"]);
            testCase.verifyTrue(ordered(end) == entries(1));
        end

        function previewFiltersLegacyExecutableConstructorPairs(testCase)
            % previewFiltersLegacyExecutableConstructorPairs Apply skip policy without occurrence metadata.
            registry = macd.model.ComponentRegistry.createDefault();
            member = macd.model.ComponentRecord("label", "Label", "uilabel", "matlab.ui.control.Label");
            member.CreationArguments = {"Text", "retained", "CreateFcn", @(~,~) error("MustNotExecute")};
            actual = macd.model.PropertyApplicationPlanner.forPreviewArguments(member, registry);
            testCase.verifyEqual(actual, {"Text", "retained"});
        end

        function handlesEmptySubsetAndConservativeLegacyMetadata(testCase)
            % handlesEmptySubsetAndConservativeLegacyMetadata Retain original order without declared dependencies.
            definitions = [macd.model.PropertyDefinition("A"), macd.model.PropertyDefinition("B")];
            entries = [macd.model.PropertyEntry("B", 2), macd.model.PropertyEntry("A", 1)];
            testCase.verifyEqual(macd.model.PropertyApplicationPlanner.order(entries, definitions), entries);
            testCase.verifyEmpty(macd.model.PropertyApplicationPlanner.order( ...
                macd.model.PropertyEntry.empty, definitions));
        end

        function rejectsDuplicateProjectionAndInvalidFullGraph(testCase)
            % rejectsDuplicateProjectionAndInvalidFullGraph Refuse ambiguous entries and invalid omitted definitions.
            entries = [macd.model.PropertyEntry("A", 1), macd.model.PropertyEntry("A", 2)];
            testCase.verifyError(@() macd.model.PropertyApplicationPlanner.order(entries, ...
                macd.model.PropertyDefinition("A")), "macd:PropertyApplicationPlanner:DuplicateProperty");
            testCase.verifyError(@() macd.model.PropertyApplicationPlanner.order( ...
                macd.model.PropertyEntry.empty, testCase.dependent("A", "Missing")), ...
                "macd:ComponentCatalogLoader:InvalidCatalog");
        end

        function generatedNumericControlsEstablishRangeBeforeValue(testCase)
            % generatedNumericControlsEstablishRangeBeforeValue Use the promoted policy in canonical output.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("OrderedNumericApp", registry);
            slider = document.insertComponent(registry, "uislider", document.RootComponentId);
            slider.setProperty("Value", 75);
            slider.setProperty("Limits", [50 100]);
            entries = macd.model.PropertyApplicationPlanner.forComponent(slider, document, registry);
            paths = string({entries.Path});
            testCase.verifyLessThan(find(paths == "Limits"), find(paths == "Value"));
            [source, diagnostics] = macd.source.NewAppGenerator(registry).generate(document);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            prefix = "app." + slider.Name + ".";
            testCase.verifyLessThan(strfind(source, prefix + "Limits ="), strfind(source, prefix + "Value ="));
            reloaded = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(reloaded.getComponentByName(slider.Name).getProperty("Value").LiteralValue, 75);
        end

        function generationAcceptsDocumentedOffScaleGaugeValues(testCase)
            % generationAcceptsDocumentedOffScaleGaugeValues Avoid applying slider restrictions to a gauge.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("OffScaleGaugeApp", registry);
            gauge = document.insertComponent(registry, "uigauge", document.RootComponentId, {"circular"});
            gauge.setProperty("Value", 150);
            gauge.setProperty("Limits", [0 100]);
            [source, diagnostics] = macd.source.NewAppGenerator(registry).generate(document);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifySubstring(source, "app." + gauge.Name + ".Value = 150;");
            testCase.verifyEmpty(registry.get("uigauge", {"circular"}).getProperty("Value").Application.ApplyAfter);
        end

        function preservesNoEditParsedSourceDespiteCanonicalPolicy(testCase)
            % preservesNoEditParsedSourceDespiteCanonicalPolicy Do not reorder original legal setter histories.
            ending = string(newline);
            source = strjoin(["classdef ParsedPolicyApp < matlab.apps.AppBase", ...
                "properties (Access=public)", "UIFigure matlab.ui.Figure", ...
                "Slider matlab.ui.control.Slider", "end", "methods (Access=private)", ...
                "function createComponents(app)", "app.UIFigure = uifigure('Visible','off');", ...
                "app.Slider = uislider(app.UIFigure);", "app.Slider.Value = 20;", ...
                "app.Slider.Limits = [0 50];", "end", "end", "methods (Access=public)", ...
                "function app = ParsedPolicyApp", "createComponents(app);", "end", "end", "end"], ending);
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(source, registry);
            generated = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifyEqual(generated, source);
            component = document.getComponentByName("Slider");
            entries = macd.model.PropertyApplicationPlanner.forPreview(component, document, registry);
            testCase.verifyEqual(string({entries.Path}), ["Value", "Limits"]);
            testCase.verifyEqual(entries(1).LiteralValue, 20);
            testCase.verifyEqual(entries(2).LiteralValue, [0 50]);
        end
    end

    methods (Static, Access = private)
        function definition = dependent(path, prerequisite)
            % dependent Construct a small declarative graph fixture.
            arguments (Input)
                path (1, 1) string
                prerequisite (1, 1) string
            end
            arguments (Output)
                definition (1, 1) macd.model.PropertyDefinition
            end
            definition = macd.model.PropertyDefinition(path, [], false, true, ...
                struct("application", struct("applyAfter", {{prerequisite}})));
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

classdef (TestTags = {'fast', 'parser', 'model', 'generation'}) PropertyInsertionBatchTest < matlab.unittest.TestCase
    % PropertyInsertionBatchTest Verify shared candidate evaluation across pending source owners.
    %   All fixtures are synthetic handle-based text and are never executed. Candidate
    %   sharing must preserve source ownership, setting order and caller isolation.
    properties (Access = private)
        Registry macd.model.ComponentRegistry
    end

    methods (TestClassSetup)
        function loadRegistry(testCase)
            % loadRegistry Load the release catalog used by placement and state checks.
            testCase.Registry = macd.model.ComponentRegistry.createDefault();
        end
    end

    methods (Test)
        function parsesOneCandidateForTwelvePendingValueOwners(testCase)
            % parsesOneCandidateForTwelvePendingValueOwners Bound reparsing independently of owner count.
            document = testCase.numericFixture(12);
            original = document.OriginalText;
            for index = 1:12
                document.getComponentByName("Field" + index).setProperty("Value", index + 1);
            end
            profile clear; profile on;
            cleanup = onCleanup(@() profile("off"));
            [source, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            profile off;
            functions = profile("info").FunctionTable;
            matches = contains(string({functions.FunctionName}), "AppSourceParser.parseText");
            testCase.verifyEqual(sum([functions(matches).NumCalls]), 1);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            for index = 1:12
                testCase.verifyEqual(parsed.getComponentByName("Field" + index).getProperty("Value").LiteralValue, index + 1);
            end
            testCase.verifyEqual(document.OriginalText, original);
            testCase.verifyEmpty(document.History);
        end

        function placementsMatchIndependentOwnersAndReturnedPlansStayPrivate(testCase)
            % placementsMatchIndependentOwnersAndReturnedPlansStayPrivate Reuse syntax without exposing retained models.
            document = testCase.numericFixture(2);
            for index = 1:2
                document.getComponentByName("Field" + index).setProperty("Value", index + 2);
            end
            for index = 1:2
                isolated = macd.source.AppSourceParser.parseText(document.OriginalText, testCase.Registry);
                single = isolated.getComponentByName("Field" + index);
                single.setProperty("Value", index + 2);
                reference = macd.source.PropertyInsertionPlanner.plan(isolated, single, testCase.Registry);
                component = document.getComponentByName("Field" + index);
                plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
                testCase.verifyEqual(plan.Edits, reference.Edits);
                testCase.verifyEqual(plan.Placements, reference.Placements);
                plan.Component.setProperty("Value", 99);
                plan.Document.getComponentByName("Field" + (3 - index)).setProperty("Value", 98);
                retained = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
                testCase.verifyEqual(retained.Component.getProperty("Value").LiteralValue, index + 2);
                testCase.verifyEqual(retained.Document.getComponentByName("Field" + (3 - index)).getProperty("Value").LiteralValue, 5 - index);
            end
            document.getComponentByName("Field1").setProperty("Value", 7);
            refreshed = macd.source.PropertyInsertionPlanner.plan(document, document.getComponentByName("Field2"), testCase.Registry);
            testCase.verifyEqual(refreshed.Document.getComponentByName("Field1").getProperty("Value").LiteralValue, 7);
        end

        function retainsExistingOccurrencesAndOtherUnsavedRequests(testCase)
            % retainsExistingOccurrencesAndOtherUnsavedRequests Preserve every original setting while replacing only the last.
            document = testCase.fixture(["First", "Second"], ...
                ["app.First = uieditfield(app.UIFigure,'numeric');", ...
                "app.First.FontSize = 10; % earlier setting", ...
                "app.First.FontSize = 12; % latest setting", ...
                "app.Second = uieditfield(app.UIFigure,'numeric');"]);
            first = document.getComponentByName("First");
            second = document.getComponentByName("Second");
            first.setProperty("FontSize", 18);
            first.setProperty("Value", 3);
            second.setProperty("Value", 4);
            source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifySubstring(source, "app.First.FontSize = 10; % earlier setting");
            testCase.verifySubstring(source, "app.First.FontSize = 18; % latest setting");
            parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            testCase.verifyNumElements(parsed.getComponentByName("First").getSettings("FontSize"), 2);
            testCase.verifyEqual(parsed.getComponentByName("First").getProperty("Value").LiteralValue, 3);
            testCase.verifyEqual(parsed.getComponentByName("Second").getProperty("Value").LiteralValue, 4);
        end

        function preservesConstructorStyleAndAssignmentPrerequisites(testCase)
            % preservesConstructorStyleAndAssignmentPrerequisites Validate both constructor grouping and execution order.
            document = testCase.fixture(["First", "Second"], ...
                ["app.First = uidropdown(app.UIFigure, Items=[""A"" ""B""], ItemsData=[10 20]);", ...
                "app.Second = uidropdown(app.UIFigure);", ...
                "app.Second.Items = [""A"" ""B""];", ...
                "app.Second.ItemsData = [10 20];"]);
            document.getComponentByName("First").setProperty("Value", 20);
            document.getComponentByName("Second").setProperty("Value", 10);
            [source, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            first = parsed.getComponentByName("First");
            second = parsed.getComponentByName("Second");
            testCase.verifyEqual(first.getSettings("Value").Method, "nameValue");
            testCase.verifyEqual(second.getSettings("Value").Method, "assignment");
            testCase.verifyGreaterThan(second.getSettings("Value").SourceSpan.StartOffset, ...
                second.getSettings("ItemsData").SourceSpan.EndOffset);
            testCase.verifyEqual(first.getProperty("Value").LiteralValue, 20);
            testCase.verifyEqual(second.getProperty("Value").LiteralValue, 10);
        end

        function failedTentativeBatchKeepsTheEstablishedLaterSlotSearch(testCase)
            % failedTentativeBatchKeepsTheEstablishedLaterSlotSearch Preserve legal setter clamping and fallback.
            document = testCase.fixture(["First", "Second"], ...
                ["app.First = uislider(app.UIFigure);", "app.First.Value = 20;", ...
                "app.Second = uieditfield(app.UIFigure,'numeric');"]);
            document.getComponentByName("First").setProperty("Limits", [50 100]);
            document.getComponentByName("Second").setProperty("Value", 3);
            [source, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            first = parsed.getComponentByName("First");
            testCase.verifyGreaterThan(first.getSettings("Limits").SourceSpan.StartOffset, ...
                first.getSettings("Value").SourceSpan.EndOffset);
            states = parsed.getEffectivePropertyStates(testCase.Registry, first.Id);
            value = states(arrayfun(@(state) state.Definition.Path == "Value", states)).Resolution;
            testCase.verifyEqual(value.EffectiveValue, 50);
            testCase.verifyEqual(parsed.getComponentByName("Second").getProperty("Value").LiteralValue, 3);
        end

        function unsafeOwnerCannotBeHiddenByAnotherOwner(testCase)
            % unsafeOwnerCannotBeHiddenByAnotherOwner Keep initialization boundaries effective for aggregated edits.
            document = testCase.fixture(["First", "Second"], ...
                ["app.First = uidropdown(app.UIFigure);", "observed = app.First.Value;", ...
                "app.First.Items = [""A"" ""B""];", "app.First.ItemsData = [10 20];", ...
                "app.Second = uieditfield(app.UIFigure,'numeric');"]);
            original = document.OriginalText;
            document.getComponentByName("First").setProperty("Value", 20);
            document.getComponentByName("Second").setProperty("Value", 3);
            [~, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifyTrue(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyEqual(document.OriginalText, original);
            testCase.verifyEmpty(document.History);
        end

        function undoAndRedoRebuildTheCorrectOwnerSet(testCase)
            % undoAndRedoRebuildTheCorrectOwnerSet Never reuse a batch from a later history state.
            document = testCase.numericFixture(2);
            first = document.getComponentByName("Field1");
            second = document.getComponentByName("Field2");
            document.setProperty(first.Id, "Value", 3, testCase.Registry);
            document.setProperty(second.Id, "Value", 4, testCase.Registry);
            generator = macd.source.RoundTripGenerator(testCase.Registry);
            both = generator.generate(document);
            document.undo();
            one = generator.generate(document);
            testCase.verifySubstring(one, "app.Field1.Value = 3;");
            testCase.verifyFalse(contains(one, "app.Field2.Value ="));
            document.redo();
            testCase.verifyEqual(generator.generate(document), both);
            testCase.verifyEqual(document.HistoryIndex, 2);
        end

        function generatedComponentsParticipateInOneCompletePlacementProof(testCase)
            % generatedComponentsParticipateInOneCompletePlacementProof Include additions while sharing all owned requests.
            for layout = ["absolute", "flat", "nested"]
                document = testCase.numericFixture(2, layout);
                first = document.getComponentByName("Field1");
                second = document.getComponentByName("Field2");
                first.setProperty("Value", 3); second.setProperty("Value", 4);
                added = document.insertComponent(testCase.Registry, "uilabel", first.ParentId);
                added.setProperty("FontSize", 14);
                original = document.OriginalText;
                profile clear; profile on; stop = onCleanup(@() profile("off"));
                plan = macd.source.PropertyInsertionPlanner.plan(document, first, testCase.Registry);
                other = macd.source.PropertyInsertionPlanner.plan(document, second, testCase.Registry);
                profile off; functions = profile("info").FunctionTable; clear stop
                parsed = contains(string({functions.FunctionName}), "AppSourceParser.parseText");
                testCase.verifyEqual(sum([functions(parsed).NumCalls]), 1, layout);
                testCase.verifyEqual(plan.Component.getProperty("Value").LiteralValue, 3);
                testCase.verifyEqual(other.Component.getProperty("Value").LiteralValue, 4);
                testCase.verifyEqual(plan.Document.getComponentByName(added.Name).getProperty("FontSize").LiteralValue, 14);
                expected = plan.Document.OriginalText;
                % Public results cannot mutate the complete configuration retained by the live document.
                plan.Document.getComponentByName(second.Name).setProperty("Value", 99);
                [retained, found] = document.evaluationContext(testCase.Registry).configuration("combined", added.Name);
                testCase.verifyTrue(found, layout);
                testCase.verifyEqual(retained.Document.getComponentByName(second.Name).getProperty("Value").LiteralValue, 4);
                [source, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
                testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
                testCase.verifyEqual(source, expected, layout);
                testCase.verifyEqual(document.OriginalText, original);
                testCase.verifyEqual(document.HistoryIndex, 1);
            end
        end

        function generatedComponentsKeepTheLaterSlotFallback(testCase)
            % generatedComponentsKeepTheLaterSlotFallback Reject an invalid first batch without losing a valid later placement.
            document = testCase.fixture(["First", "Second"], ...
                ["app.First = uieditfield(app.UIFigure,'numeric');", "app.First.Value = 20;", ...
                "app.Second = uieditfield(app.UIFigure,'numeric');"]);
            document.getComponentByName("First").setProperty("Limits", [50 100]);
            document.getComponentByName("Second").setProperty("Value", 3);
            added = document.insertComponent(testCase.Registry, "uilabel", document.RootComponentId);
            [source, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            first = parsed.getComponentByName("First");
            testCase.verifyGreaterThan(first.getSettings("Limits").SourceSpan.StartOffset, ...
                first.getSettings("Value").SourceSpan.EndOffset);
            testCase.verifyNotEmpty(parsed.getComponentByName(added.Name));
            testCase.verifyEqual(parsed.getComponentByName("Second").getProperty("Value").LiteralValue, 3);
        end

        function invalidGeneratedRequestsCannotPublishACompleteProof(testCase)
            % invalidGeneratedRequestsCannotPublishACompleteProof Validate generated settings before retaining source-wide evidence.
            document = testCase.numericFixture(2);
            first = document.getComponentByName("Field1");
            first.setProperty("Value", 3);
            document.getComponentByName("Field2").setProperty("Value", 4);
            added = document.insertComponent(testCase.Registry, "uilabel", document.RootComponentId);
            added.setProperty("FontSize", -2);
            macd.source.PropertyInsertionPlanner.plan(document, first, testCase.Registry);
            [~, found] = document.evaluationContext(testCase.Registry).configuration("combined", first.Name);
            testCase.verifyFalse(found);
            [~, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifyTrue(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function generatedChangesInvalidateTheCompletePlacementProof(testCase)
            % generatedChangesInvalidateTheCompletePlacementProof Never retain an earlier value after an added record changes.
            document = testCase.numericFixture(2);
            first = document.getComponentByName("Field1");
            first.setProperty("Value", 3);
            document.getComponentByName("Field2").setProperty("Value", 4);
            added = document.insertComponent(testCase.Registry, "uilabel", document.RootComponentId);
            added.setProperty("FontSize", 14);
            before = macd.source.PropertyInsertionPlanner.plan(document, first, testCase.Registry);
            added.setProperty("FontSize", 18);
            [~, found] = document.evaluationContext(testCase.Registry).configuration("combined", first.Name);
            testCase.verifyFalse(found);
            after = macd.source.PropertyInsertionPlanner.plan(document, first, testCase.Registry);
            testCase.verifyEqual(before.Document.getComponentByName(added.Name).getProperty("FontSize").LiteralValue, 14);
            testCase.verifyEqual(after.Document.getComponentByName(added.Name).getProperty("FontSize").LiteralValue, 18);
        end

        function completePlacementCoversEveryGeneratedCatalogVariant(testCase)
            % completePlacementCoversEveryGeneratedCatalogVariant Apply the proof wherever ordinary generation is supported.
            variants = testCase.Registry.listVariantIds();
            applicable = 0;
            unsupported = 0;
            for variant = reshape(variants, 1, [])
                definition = testCase.Registry.getById(variant);
                if definition.IsRoot, continue, end
                document = testCase.numericFixture(2);
                parentId = testCase.generatedParent(document, definition);
                generated = macd.model.ComponentRecord("generated-subject", "Subject", ...
                    definition.Factory, definition.DeclaredType, "generated");
                generated.CreationArguments = definition.CreationArguments;
                document.addComponent(generated, parentId);
                % Existing ordinary generation defines applicability without broadening product capabilities.
                [~, baselineDiagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
                first = document.getComponentByName("Field1");
                first.setProperty("Value", 3);
                document.getComponentByName("Field2").setProperty("FontSize", 14);
                if macd.validation.ModelValidator.hasErrors(baselineDiagnostics)
                    [~, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
                    testCase.verifyTrue(macd.validation.ModelValidator.hasErrors(diagnostics), variant);
                    unsupported = unsupported + 1;
                    fprintf("GENERATED_BATCH_NOT_APPLICABLE %s\n", variant);
                    continue
                end
                profile clear; profile on; stop = onCleanup(@() profile("off"));
                plan = macd.source.PropertyInsertionPlanner.plan(document, first, testCase.Registry);
                profile off; functions = profile("info").FunctionTable; clear stop
                parsed = contains(string({functions.FunctionName}), "AppSourceParser.parseText");
                testCase.verifyEqual(sum([functions(parsed).NumCalls]), 1, variant);
                retained = plan.Document.getComponentByName(generated.Name);
                testCase.assertNotEmpty(retained, variant);
                testCase.verifyEqual(retained.Factory, generated.Factory, variant);
                testCase.verifyEqual(retained.CreationArguments, generated.CreationArguments, variant);
                testCase.verifyEqual(plan.Component.getProperty("Value").LiteralValue, 3, variant);
                testCase.verifyEqual(plan.Document.getComponentByName("Field2").getProperty("FontSize").LiteralValue, 14, variant);
                [source, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
                testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics), variant);
                testCase.verifyEqual(source, plan.Document.OriginalText, variant);
                applicable = applicable + 1;
                fprintf("GENERATED_BATCH_VARIANT %s\n", variant);
            end
            testCase.verifyGreaterThan(applicable, 0);
            testCase.verifyEqual(applicable + unsupported, numel(variants) - 1);
            fprintf("GENERATED_BATCH_COVERAGE Reviewed=%d Applicable=%d Unsupported=%d\n", ...
                numel(variants), applicable, unsupported);
        end

        function combinedPlansReuseExactCompleteEmissions(testCase)
            % combinedPlansReuseExactCompleteEmissions Parse and assemble one complete candidate across every layout.
            for layout = ["absolute", "flat", "nested"]
                document = testCase.numericFixture(2, layout);
                first = document.getComponentByName("Field1");
                first.setProperty("Value", 3);
                document.getComponentByName("Field2").setProperty("Value", 4);
                added = document.insertComponent(testCase.Registry, "uilabel", first.ParentId);
                original = document.OriginalText;
                profile clear; profile on; stop = onCleanup(@() profile("off"));
                plan = macd.source.PropertySourcePlan.combined(document, first, testCase.Registry);
                profile off; functions = profile("info").FunctionTable; clear stop
                names = string({functions.FunctionName});
                testCase.verifyEqual(sum([functions(contains(names, "AppSourceParser.parseText")).NumCalls]), 1, layout);
                testCase.verifyEqual(sum([functions(endsWith(names, "RoundTripGenerator.additionEdits")).NumCalls]), 1, layout);
                testCase.verifyEqual(plan.Component.getProperty("Value").LiteralValue, 3);
                testCase.verifyNotEmpty(plan.Document.getComponentByName(added.Name));
                expected = plan.Document.OriginalText;
                plan.Document.getComponentByName("Field2").setProperty("Value", 99);
                retained = macd.source.PropertySourcePlan.combined(document, first, testCase.Registry);
                testCase.verifyEqual(retained.Document.OriginalText, expected);
                testCase.verifyEqual(retained.Document.getComponentByName("Field2").getProperty("Value").LiteralValue, 4);
                testCase.verifyEqual(document.OriginalText, original);
            end
        end

        function publicGenerationReusesEmissionAfterInputValidation(testCase)
            % publicGenerationReusesEmissionAfterInputValidation Preserve validation while avoiding a second assembly.
            document = testCase.numericFixture(2);
            first = document.getComponentByName("Field1");
            first.setProperty("Value", 3);
            document.getComponentByName("Field2").setProperty("Value", 4);
            document.insertComponent(testCase.Registry, "uilabel", document.RootComponentId);
            plan = macd.source.PropertyInsertionPlanner.plan(document, first, testCase.Registry);
            expected = plan.Document.OriginalText;
            plan.Document.getComponentByName("Field2").setProperty("Value", 99);
            profile clear; profile on; stop = onCleanup(@() profile("off"));
            [source, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            profile off; functions = profile("info").FunctionTable; clear stop
            names = string({functions.FunctionName});
            testCase.verifyEqual(sum([functions(contains(names, "AppSourceParser.parseText")).NumCalls]), 0);
            testCase.verifyEqual(sum([functions(endsWith(names, "RoundTripGenerator.additionEdits")).NumCalls]), 0);
            testCase.verifyEqual(sum([functions(endsWith(names, "ModelValidator.validate")).NumCalls]), 1);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyEqual(source, expected);
            testCase.verifyEqual(document.GeneratedText, expected);
        end

        function changedInputsCannotReuseAnEarlierEmission(testCase)
            % changedInputsCannotReuseAnEarlierEmission Reject stale source after values and the registry change.
            document = testCase.numericFixture(2);
            first = document.getComponentByName("Field1");
            first.setProperty("Value", 3);
            second = document.getComponentByName("Field2");
            second.setProperty("Value", 4);
            added = document.insertComponent(testCase.Registry, "uilabel", document.RootComponentId);
            macd.source.PropertyInsertionPlanner.plan(document, first, testCase.Registry);
            [~, found] = document.evaluationContext(testCase.Registry).lookup("complete-insertion-source");
            testCase.verifyTrue(found);
            replacement = macd.model.ComponentRegistry.createDefault();
            [~, found] = document.evaluationContext(replacement).lookup("complete-insertion-source");
            testCase.verifyFalse(found);
            second.setProperty("Value", 5);
            [~, found] = document.evaluationContext(testCase.Registry).lookup("complete-insertion-source");
            testCase.verifyFalse(found);
            [source, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            testCase.verifyEqual(parsed.getComponentByName("Field2").getProperty("Value").LiteralValue, 5);
            added.setProperty("FontSize", -2);
            [~, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifyTrue(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function partialPlacementsRetainCompleteSourceParsing(testCase)
            % partialPlacementsRetainCompleteSourceParsing Never treat a partial placement plan as verified emission.
            document = testCase.numericFixture(2);
            first = document.getComponentByName("Field1");
            first.setProperty("Value", 3);
            document.getComponentByName("Field2").setProperty("Value", 4);
            macd.source.PropertyInsertionPlanner.plan(document, first, testCase.Registry);
            [~, found] = document.evaluationContext(testCase.Registry).lookup("complete-insertion-source");
            testCase.verifyFalse(found);
            profile clear; profile on; stop = onCleanup(@() profile("off"));
            plan = macd.source.PropertySourcePlan.combined(document, first, testCase.Registry);
            profile off; functions = profile("info").FunctionTable; clear stop
            parsed = contains(string({functions.FunctionName}), "AppSourceParser.parseText");
            testCase.verifyEqual(sum([functions(parsed).NumCalls]), 2);
            testCase.verifyEqual(plan.Component.getProperty("Value").LiteralValue, 3);
            testCase.verifyEqual(plan.Document.getComponentByName("Field2").getProperty("Value").LiteralValue, 4);
        end
    end

    methods (Access = private)
        function document = numericFixture(testCase, count, layout)
            % numericFixture Create controls without explicit Value settings for owner-scaling coverage.
            arguments (Input)
                testCase (1, 1) PropertyInsertionBatchTest
                count (1, 1) double
                layout (1, 1) string = "absolute"
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
            end
            fields = "Field" + (1:count);
            names = fields;
            initialization = strings(1, 0);
            parent = "UIFigure";
            if layout ~= "absolute"
                depth = 1;
                if layout == "nested", depth = 3; end
                for index = 1:depth
                    grid = "Grid" + index;
                    names(end + 1) = grid; %#ok<AGROW>
                    initialization(end + 1) = "app." + grid + " = uigridlayout(app." + parent + ",[2 1]);"; %#ok<AGROW>
                    parent = grid;
                end
            end
            initialization = [initialization "app." + fields + " = uieditfield(app." + parent + ",'numeric');"];
            document = testCase.fixture(names, initialization);
        end

        function id = generatedParent(testCase, document, definition)
            % generatedParent Build the minimal allowed generated hierarchy for source-only catalog coverage.
            arguments (Input)
                testCase (1, 1) PropertyInsertionBatchTest
                document (1, 1) macd.model.DocumentModel
                definition (1, 1) macd.model.ComponentDefinition
            end
            arguments (Output)
                id (1, 1) string
            end
            if any(definition.AllowedParentFactories == "uifigure")
                id = document.RootComponentId;
                return
            end
            parentDefinition = testCase.Registry.get(definition.AllowedParentFactories(1));
            parentId = testCase.generatedParent(document, parentDefinition);
            name = "GeneratedParent" + numel(document.Components);
            parent = macd.model.ComponentRecord("generated-" + name, name, ...
                parentDefinition.Factory, parentDefinition.DeclaredType, "generated");
            parent.CreationArguments = parentDefinition.CreationArguments;
            document.addComponent(parent, parentId);
            id = parent.Id;
        end

        function document = fixture(testCase, names, initialization)
            % fixture Parse owned source while preserving original lines and constructor grouping.
            arguments (Input)
                testCase (1, 1) PropertyInsertionBatchTest
                names (1, :) string
                initialization (1, :) string
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
            end
            source = strjoin(["classdef BatchInsertionFixture < handle", ...
                "properties", "UIFigure matlab.ui.Figure", names, "end", "methods", ...
                "function app = BatchInsertionFixture", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                initialization, "end", "end", "end"], sprintf("\r\n"));
            document = macd.source.AppSourceParser.parseText(source, testCase.Registry);
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

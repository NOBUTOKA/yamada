classdef (TestTags = {'fast', 'model', 'generation'}) NumericLocalValueTest < matlab.unittest.TestCase
    % NumericLocalValueTest Verify finite numeric Value edits against complete owned source checkpoints.
    %   Local validation must preserve source order, constraint behavior, atomic
    %   history, full save verification and the independence of public results.
    properties (Access = private)
        Registry macd.model.ComponentRegistry
    end

    methods (TestClassSetup)
        function loadRegistry(testCase)
            % loadRegistry Load the same catalog used by full property preflight.
            testCase.Registry = macd.model.ComponentRegistry.createDefault();
        end
    end

    methods (Test)
        function reusesACompleteCheckpointAcrossNumericOwners(testCase)
            % reusesACompleteCheckpointAcrossNumericOwners Avoid parsing for owned re-edits across grid layouts.
            for layout = ["absolute", "flat", "nested"]
                document = testCase.fixture(layout, "app.First = uieditfield(PARENT,'numeric');");
                first = document.getComponentByName("First");
                second = document.getComponentByName("Second");
                document.setProperty(first.Id, "Value", 2, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                document.setProperty(second.Id, "Value", 3, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                profile clear; profile on;
                cleanup = onCleanup(@() profile("off"));
                document.setPropertyBatch(first.Id, macd.model.PropertyTransaction.singleChange("Value", 4), testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                document.setProperty(second.Id, "Value", 5, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                profile off; functions = profile("info").FunctionTable; clear cleanup
                names = string({functions.FunctionName});
                repeated = contains(names, "AppSourceParser.parseText") | ...
                    contains(names, "RoundTripGenerator.generate") | contains(names, "ModelValidator.validate");
                testCase.verifyEqual(sum([functions(repeated).NumCalls]), 0, layout);
                testCase.verifyEqual(first.getProperty("Value").LiteralValue, 4);
                testCase.verifyEqual(second.getProperty("Value").LiteralValue, 5);
                testCase.verifyEqual(document.HistoryIndex, 4);
                document.undo(); document.redo();
                source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
                parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
                testCase.verifyEqual(parsed.getComponentByName("First").getProperty("Value").LiteralValue, 4);
                testCase.verifyEqual(parsed.getComponentByName("Second").getProperty("Value").LiteralValue, 5);
            end
        end

        function localValueEditsRetainEquivalentAvailabilityAcrossOwners(testCase)
            % localValueEditsRetainEquivalentAvailabilityAcrossOwners Reuse answers while commands retain current values.
            for layout = ["absolute", "flat", "nested"]
                document = testCase.availabilityFixture(layout);
                first = document.getComponentByName("First");
                second = document.getComponentByName("Second");
                for id = [first.Id, second.Id]
                    document.setProperty(id, "Value", 1, testCase.Registry);
                    document.validatePropertyCommit(testCase.Registry);
                end
                measured = [10 20 100 22];
                for id = [first.Id, second.Id]
                    macd.model.DocumentEditAvailability.copying(document, id, testCase.Registry);
                    macd.model.DocumentEditAvailability.deletion(document, id, testCase.Registry);
                    macd.model.DocumentEditAvailability.reparenting(document, id, testCase.Registry, measured);
                end
                for id = [first.Id, second.Id]
                    document.setPropertyBatch(id, macd.model.PropertyTransaction.singleChange("Value", 4), testCase.Registry);
                    document.validatePropertyCommit(testCase.Registry);
                    profile clear; profile on;
                    stopProfile = onCleanup(@() profile("off"));
                    copied = macd.model.DocumentEditAvailability.copying(document, id, testCase.Registry);
                    deleted = macd.model.DocumentEditAvailability.deletion(document, id, testCase.Registry);
                    parents = macd.model.DocumentEditAvailability.reparenting(document, id, testCase.Registry, measured);
                    profile off; functions = profile("info").FunctionTable; clear stopProfile
                    repeated = contains(string({functions.FunctionName}), "DocumentEditAvailability.inspect") | ...
                        contains(string({functions.FunctionName}), "SubtreePlacementPlanner.prepare");
                    testCase.verifyEqual(sum([functions(repeated).NumCalls]), 0, layout);
                    fresh = document.structuralCandidate();
                    testCase.verifyEqual(copied, macd.model.DocumentEditAvailability.copying(fresh, id, testCase.Registry));
                    testCase.verifyEqual(deleted, macd.model.DocumentEditAvailability.deletion(fresh, id, testCase.Registry));
                    testCase.verifyEqual(parents, macd.model.DocumentEditAvailability.reparenting(fresh, id, testCase.Registry, measured));
                end
                snapshot = document.copySubtree(second.Id, testCase.Registry);
                value = snapshot.Records(1).Properties(string({snapshot.Records(1).Properties.Path}) == "Value");
                testCase.verifyEqual(value.LiteralValue, 4);
            end
        end

        function inheritedNumericAvailabilityRechecksGeometryAndHistory(testCase)
            % inheritedNumericAvailabilityRechecksGeometryAndHistory Retain measured-rectangle guards and invalidate on undo.
            document = testCase.availabilityFixture("flat");
            first = document.getComponentByName("First");
            destination = document.Components(string({document.Components.Factory}) == "uipanel");
            document.setProperty(first.Id, "Value", 1, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            before = macd.model.DocumentEditAvailability.reparenting(document, first.Id, testCase.Registry);
            testCase.assertFalse(before(string({before.Id}) == destination.Id).Enabled);
            document.setProperty(first.Id, "Value", 2, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            testCase.verifyEqual(macd.model.DocumentEditAvailability.reparenting(document, first.Id, testCase.Registry), before);
            measured = [10 20 100 30];
            profile clear; profile on;
            stopProfile = onCleanup(@() profile("off"));
            after = macd.model.DocumentEditAvailability.reparenting(document, first.Id, testCase.Registry, measured);
            profile off; functions = profile("info").FunctionTable; clear stopProfile
            placement = contains(string({functions.FunctionName}), "SubtreePlacementPlanner.prepare");
            testCase.verifyGreaterThan(sum([functions(placement).NumCalls]), 0);
            testCase.verifyTrue(after(string({after.Id}) == destination.Id).Enabled);
            fresh = document.structuralCandidate();
            testCase.verifyEqual(after, macd.model.DocumentEditAvailability.reparenting(fresh, first.Id, testCase.Registry, measured));
            document.undo(); document.redo();
            profile clear; profile on;
            stopProfile = onCleanup(@() profile("off"));
            restored = macd.model.DocumentEditAvailability.reparenting(document, first.Id, testCase.Registry, measured);
            profile off; functions = profile("info").FunctionTable; clear stopProfile
            inspected = contains(string({functions.FunctionName}), "DocumentEditAvailability.inspect");
            testCase.verifyGreaterThan(sum([functions(inspected).NumCalls]), 0);
            testCase.verifyEqual(restored, after);
        end

        function inheritedNumericAvailabilityRejectsChangedInputs(testCase)
            % inheritedNumericAvailabilityRejectsChangedInputs Recompute after ownership, constraints or catalog changes.
            for kind = ["readonly", "limits", "registry"]
                document = testCase.availabilityFixture("absolute");
                first = document.getComponentByName("First");
                document.setProperty(first.Id, "Value", 1, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                macd.model.DocumentEditAvailability.copying(document, first.Id, testCase.Registry);
                document.setProperty(first.Id, "Value", 2, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                switch kind
                    case "readonly"
                        first.IsEditable = false;
                    case "limits"
                        document.setProperty(first.Id, "Limits", [-10 10], testCase.Registry);
                    case "registry"
                        testCase.Registry.register(testCase.Registry.get(first.Factory, first.CreationArguments));
                end
                profile clear; profile on;
                stopProfile = onCleanup(@() profile("off"));
                actual = macd.model.DocumentEditAvailability.copying(document, first.Id, testCase.Registry);
                profile off; functions = profile("info").FunctionTable; clear stopProfile
                inspected = contains(string({functions.FunctionName}), "DocumentEditAvailability.inspect");
                testCase.verifyGreaterThan(sum([functions(inspected).NumCalls]), 0, kind);
                fresh = document.structuralCandidate();
                testCase.verifyEqual(actual, macd.model.DocumentEditAvailability.copying(fresh, first.Id, testCase.Registry));
                if kind == "readonly", testCase.verifyFalse(actual.Enabled); end
            end
        end

        function ownedCheckpointReadsAvoidDocumentMaterialization(testCase)
            % ownedCheckpointReadsAvoidDocumentMaterialization Keep local reads private and public copies independent.
            for layout = ["absolute", "flat", "nested"]
                document = testCase.fixture(layout, "app.First = uieditfield(PARENT,'numeric');");
                first = document.getComponentByName("First");
                document.setProperty(first.Id, "Value", 1, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                profile clear; profile on;
                stopProfile = onCleanup(@() profile("off"));
                document.setProperty(first.Id, "Value", 2, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                states = document.getEffectivePropertyStates(testCase.Registry, first.Id);
                profile off; functions = profile("info").FunctionTable; clear stopProfile
                expensive = contains(string({functions.FunctionName}), "DocumentModel.structuralCandidate") | ...
                    contains(string({functions.FunctionName}), "SubtreeSnapshot.materialize") | ...
                    contains(string({functions.FunctionName}), "AppSourceParser.parseText") | ...
                    contains(string({functions.FunctionName}), "RoundTripGenerator.generate");
                testCase.verifyEqual(sum([functions(expensive).NumCalls]), 0, layout);
                definitions = [states.Definition];
                value = states(string({definitions.Path}) == "Value");
                testCase.verifyEqual(value.Resolution.EffectiveValue, 2);
                context = document.evaluationContext(testCase.Registry);
                [copy, found] = context.configuration("combined", first.Name);
                testCase.assertTrue(found);
                normal = copy.Document.structuralCandidate();
                [again, found] = context.configuration("combined", first.Name);
                testCase.assertTrue(found);
                testCase.verifyEqual(macd.model.SubtreeSnapshot(normal, normal.RootComponentId).Records, ...
                    macd.model.SubtreeSnapshot(again.Document, again.Document.RootComponentId).Records);
                for name = reshape(string(properties(normal)), 1, [])
                    if name ~= "Components", testCase.verifyEqual(again.Document.(name), normal.(name), name); end
                end
                copy.Component.setProperty("Value", 9);
                testCase.verifyEqual(first.getProperty("Value").LiteralValue, 2);
                [again, ~] = context.configuration("combined", first.Name);
                testCase.verifyEqual(again.Component.getProperty("Value").LiteralValue, 2);
            end
        end

        function ownedSnapshotsKeepEarlierVersionsAfterLaterEdits(testCase)
            % ownedSnapshotsKeepEarlierVersionsAfterLaterEdits Preserve old source plans even when their checkpoint is reused.
            document = testCase.fixture("absolute", ...
                ["app.First = uieditfield(PARENT,'numeric');", "app.First.Value = 1;"]);
            first = document.getComponentByName("First");
            document.setProperty(first.Id, "Value", 2, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            document.setProperty(first.Id, "Value", 3, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            previous = document.evaluationContext(testCase.Registry);
            previousDocument = document.structuralCandidate();
            previousComponent = previousDocument.getComponent(first.Id);
            definitions = testCase.Registry.getEffectiveProperties(first.Factory, "uifigure", first.CreationArguments);
            document.setProperty(first.Id, "Value", 4, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            [old, found] = previous.configuration("combined", first.Name);
            testCase.assertTrue(found);
            testCase.verifyEqual(old.Component.getProperty("Value").LiteralValue, 3);
            [states, ~, found] = previous.configurationStates("combined", previousComponent, definitions, previousDocument);
            testCase.assertTrue(found);
            testCase.verifyEqual(states(string({states.Path}) == "Value").EffectiveValue, 3);
            source = macd.source.RoundTripGenerator(testCase.Registry).generate(old.Document);
            parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            testCase.verifyEqual(parsed.getComponentByName("First").getProperty("Value").LiteralValue, 3);
            testCase.verifyEqual(first.getProperty("Value").LiteralValue, 4);
        end

        function rejectedOwnedEditsDoNotPublishMutatedCandidateValues(testCase)
            % rejectedOwnedEditsDoNotPublishMutatedCandidateValues Restore old reads after a failed source-order replay.
            document = testCase.fixture("absolute", ...
                ["app.First = uieditfield(PARENT,'numeric');", "app.First.Limits = [0 10];", ...
                "app.First.Value = 1;", "app.First.Limits = [0 100];"]);
            first = document.getComponentByName("First");
            document.setProperty(first.Id, "Value", 2, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            document.setProperty(first.Id, "Value", 3, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            context = document.evaluationContext(testCase.Registry);
            history = document.History;
            testCase.verifyError(@() document.setProperty(first.Id, "Value", 50, testCase.Registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(document.History, history);
            definitions = testCase.Registry.getEffectiveProperties(first.Factory, "uifigure", first.CreationArguments);
            [states, ~, found] = context.configurationStates("combined", first, definitions, document);
            testCase.assertTrue(found);
            testCase.verifyEqual(states(string({states.Path}) == "Value").EffectiveValue, 3);
            [copy, found] = context.configuration("combined", first.Name);
            testCase.assertTrue(found);
            testCase.verifyEqual(copy.Component.getProperty("Value").LiteralValue, 3);
            testCase.verifyEqual(first.getProperty("Value").LiteralValue, 3);
        end

        function checkpointStateReadsMatchIndependentPlans(testCase)
            % checkpointStateReadsMatchIndependentPlans Preserve pending identities and values while avoiding read-only copies.
            for layout = ["absolute", "flat", "nested"]
                document = testCase.fixture(layout, "app.First = uieditfield(PARENT,'numeric');");
                first = document.getComponentByName("First");
                document.setProperty(first.Id, "Value", 4, testCase.Registry);
                context = document.evaluationContext(testCase.Registry);
                parent = document.getComponent(first.ParentId);
                definitions = testCase.Registry.getEffectiveProperties(first.Factory, parent.Factory, first.CreationArguments);
                [plan, found] = context.configuration("combined", first.Name);
                testCase.assertTrue(found);
                expected = macd.model.PropertyStateResolver.resolve(plan.Component, definitions, plan.Document, testCase.Registry);
                profile clear; profile on;
                cleanup = onCleanup(@() profile("off"));
                actual = document.getEffectivePropertyStates(testCase.Registry, first.Id);
                actual = [actual.Resolution];
                profile off; functions = profile("info").FunctionTable; clear cleanup
                value = actual(string({actual.Path}) == "Value");
                testCase.verifyEqual(value.EffectiveValue, 4);
                settings = first.getSettings("Value");
                testCase.verifyEqual(value.EffectSettingId, settings(end).Id);
                testCase.verifyEqual([actual.IsKnown], [expected.IsKnown]);
                testCase.verifyEqual({actual.EffectiveValue}, {expected.EffectiveValue});
                if layout == "absolute"
                    cloned = contains(string({functions.FunctionName}), "DocumentModel.structuralCandidate");
                    testCase.verifyEqual(sum([functions(cloned).NumCalls]), 0);
                end
                plan.Component.setProperty("Value", 99);
                again = document.getEffectivePropertyStates(testCase.Registry, first.Id);
                again = [again.Resolution];
                testCase.verifyEqual(again(string({again.Path}) == "Value").EffectiveValue, 4);
            end
        end

        function laterConstraintsDoNotHideAnEarlierInvalidAssignment(testCase)
            % laterConstraintsDoNotHideAnEarlierInvalidAssignment Validate every occurrence rather than final bounds alone.
            document = testCase.fixture("absolute", ...
                ["app.First = uieditfield(PARENT,'numeric');", "app.First.Limits = [0 10];", ...
                "app.First.Value = 1;", "app.First.Limits = [0 100];"]);
            first = document.getComponentByName("First");
            document.setProperty(first.Id, "Value", 2, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            history = document.History;
            source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifyError(@() document.setProperty(first.Id, "Value", 50, testCase.Registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(document.History, history);
            testCase.verifyEqual(first.getProperty("Value").LiteralValue, 2);
            testCase.verifyEqual(macd.source.RoundTripGenerator(testCase.Registry).generate(document), source);
        end

        function preservesRoundingAndExclusiveBoundaryRejections(testCase)
            % preservesRoundingAndExclusiveBoundaryRejections Keep strict requested-value equality and native limits.
            for kind = ["rounding", "lower", "upper"]
                settings = ["app.First = uieditfield(PARENT,'numeric');", ...
                    "app.First.Limits = [0 10];", "app.First.Value = 1;"];
                if kind == "rounding"
                    settings(end + 1) = "app.First.RoundFractionalValues = 'on';"; %#ok<AGROW>
                    rejected = 2.5;
                elseif kind == "lower"
                    settings(end + 1) = "app.First.LowerLimitInclusive = 'off';"; %#ok<AGROW>
                    rejected = 0;
                else
                    settings(end + 1) = "app.First.UpperLimitInclusive = 'off';"; %#ok<AGROW>
                    rejected = 10;
                end
                document = testCase.fixture("absolute", settings);
                first = document.getComponentByName("First");
                document.setProperty(first.Id, "Value", 2, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                before = document.History;
                testCase.verifyError(@() document.setProperty(first.Id, "Value", rejected, testCase.Registry), ...
                    "macd:DocumentModel:UnsafePropertyEdit", kind);
                testCase.verifyEqual(first.getProperty("Value").LiteralValue, 2);
                testCase.verifyEqual(document.History, before);
            end
        end

        function changedConstraintsAndCatalogInvalidateTheCheckpoint(testCase)
            % changedConstraintsAndCatalogInvalidateTheCheckpoint Re-enter full source validation after semantic changes.
            for kind = ["limits", "registry"]
                document = testCase.fixture("absolute", ...
                    ["app.First = uieditfield(PARENT,'numeric');", "app.First.Limits = [0 10];", "app.First.Value = 1;"]);
                first = document.getComponentByName("First");
                document.setProperty(first.Id, "Value", 2, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                if kind == "limits"
                    first.setProperty("Limits", [0 5]);
                else
                    testCase.Registry.register(testCase.Registry.get("uieditfield", {"numeric"}));
                end
                profile clear; profile on;
                cleanup = onCleanup(@() profile("off"));
                document.setProperty(first.Id, "Value", 4, testCase.Registry);
                profile off; functions = profile("info").FunctionTable; clear cleanup
                parsing = contains(string({functions.FunctionName}), "AppSourceParser.parseText");
                testCase.verifyGreaterThan(sum([functions(parsing).NumCalls]), 0, kind);
                testCase.verifyEqual(first.getProperty("Value").LiteralValue, 4);
            end
        end

        function constructorAndRepeatedAssignmentsKeepTheirSourceForm(testCase)
            % constructorAndRepeatedAssignmentsKeepTheirSourceForm Rewrite only the latest original Value occurrence.
            cases = {"app.First = uieditfield(PARENT,'numeric',Limits=[0 10],Value=1);", ...
                ["app.First = uieditfield(PARENT,'numeric');", "app.First.Value = 1; % earlier", ...
                "app.First.Value = 2; % latest"]};
            for index = 1:numel(cases)
                document = testCase.fixture("absolute", cases{index});
                first = document.getComponentByName("First");
                document.setProperty(first.Id, "Value", 3, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                document.setProperty(first.Id, "Value", 4, testCase.Registry);
                source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
                parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
                settings = parsed.getComponentByName("First").getSettings("Value");
                if index == 1
                    testCase.verifyEqual(settings.Method, "nameValue");
                else
                    testCase.verifyNumElements(settings, 2);
                    testCase.verifySubstring(source, "app.First.Value = 1; % earlier");
                    testCase.verifySubstring(source, "app.First.Value = 4; % latest");
                end
                testCase.verifyEqual(parsed.getComponentByName("First").getProperty("Value").LiteralValue, 4);
            end
        end

        function emptyValuesUseTheFullAllowedEmptyPath(testCase)
            % emptyValuesUseTheFullAllowedEmptyPath Keep non-scalar requests outside finite scalar local validation.
            document = testCase.fixture("absolute", ...
                ["app.First = uieditfield(PARENT,'numeric');", "app.First.AllowEmpty = 'on';", "app.First.Value = 1;"]);
            first = document.getComponentByName("First");
            document.setProperty(first.Id, "Value", 2, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            profile clear; profile on;
            cleanup = onCleanup(@() profile("off"));
            document.setProperty(first.Id, "Value", [], testCase.Registry);
            profile off; functions = profile("info").FunctionTable; clear cleanup
            parsing = contains(string({functions.FunctionName}), "AppSourceParser.parseText");
            testCase.verifyGreaterThan(sum([functions(parsing).NumCalls]), 0);
            testCase.verifyEmpty(first.getProperty("Value").LiteralValue);
        end

        function fullSaveValidationStillGeneratesAndReparses(testCase)
            % fullSaveValidationStillGeneratesAndReparses Retain source and checkpoint checks after a local commit.
            document = testCase.fixture("absolute", "app.First = uieditfield(PARENT,'numeric');");
            first = document.getComponentByName("First");
            document.setProperty(first.Id, "Value", 2, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            document.setProperty(first.Id, "Value", 3, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            profile clear; profile on;
            cleanup = onCleanup(@() profile("off"));
            source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            checkpoint = macd.model.SavedSourceCheckpoint(document, source, ...
                fullfile(tempdir, "LocalNumericFixture.m"), testCase.Registry);
            profile off; functions = profile("info").FunctionTable; clear cleanup
            names = string({functions.FunctionName});
            testCase.verifyGreaterThan(sum([functions(contains(names, "AppSourceParser.parseText")).NumCalls]), 0);
            testCase.verifyGreaterThan(sum([functions(contains(names, "ModelValidator.validate")).NumCalls]), 0);
            testCase.verifyEqual(checkpoint.SourceText, source);
        end
    end

    methods (Access = private)
        function document = availabilityFixture(testCase, layout)
            % availabilityFixture Add a parsed absolute destination for testing actual numeric relocation conditions.
            arguments (Input)
                testCase (1, 1) NumericLocalValueTest
                layout (1, 1) string
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
            end
            document = testCase.fixture(layout, "app.First = uieditfield(PARENT,'numeric');");
            document.insertComponent(testCase.Registry, "uipanel", document.RootComponentId);
            source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            document = macd.source.AppSourceParser.parseText(source, testCase.Registry);
        end

        function document = fixture(testCase, layout, firstBody)
            % fixture Parse synthetic numeric initialization without executing application code.
            arguments (Input)
                testCase (1, 1) NumericLocalValueTest
                layout (1, 1) string
                firstBody (1, :) string
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
            end
            declarations = ["UIFigure matlab.ui.Figure", "First matlab.ui.control.NumericEditField", ...
                "Second matlab.ui.control.NumericEditField"];
            body = "app.UIFigure = uifigure(Visible='off');";
            parent = "app.UIFigure";
            if layout == "nested"
                for depth = 1:2
                    name = "Outer" + depth;
                    declarations(end + 1) = name + " matlab.ui.container.GridLayout"; %#ok<AGROW>
                    body = [body, "app." + name + " = uigridlayout(" + parent + ",[1 1]);", ...
                        "app." + name + ".RowHeight = {'1x'};", "app." + name + ".ColumnWidth = {'1x'};"]; %#ok<AGROW>
                    parent = "app." + name;
                end
            end
            if layout ~= "absolute"
                declarations(end + 1) = "Grid matlab.ui.container.GridLayout";
                body = [body, "app.Grid = uigridlayout(" + parent + ",[2 1]);", ...
                    "app.Grid.RowHeight = {'fit','1x'};", "app.Grid.ColumnWidth = {'1x'};"];
                parent = "app.Grid";
            end
            body = [body, replace(firstBody, "PARENT", parent), ...
                "app.Second = uieditfield(" + parent + ",'numeric');"];
            if layout ~= "absolute"
                body = [body, "app.First.Layout.Row = 1;", "app.Second.Layout.Row = 2;"];
            end
            source = strjoin(["classdef LocalNumericFixture < matlab.apps.AppBase", "properties", ...
                declarations, "end", "methods", "function app = LocalNumericFixture", ...
                "createComponents(app);", "end", "function createComponents(app)", ...
                body, "end", "end", "end"], sprintf("\r\n"));
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

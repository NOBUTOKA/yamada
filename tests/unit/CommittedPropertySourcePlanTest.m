classdef (TestTags = {'fast', 'model', 'generation'}) CommittedPropertySourcePlanTest < matlab.unittest.TestCase
    % CommittedPropertySourcePlanTest Verify shared committed source without stale or mutable results.
    %   Successful edits keep their parsed configuration for state and Preview
    %   consumers while direct writes and catalog changes invalidate that input.

    methods (Test)
        function independentFontEditsRetainConditionResults(testCase)
            % independentFontEditsRetainConditionResults Reuse conditions without freezing native placement or command data.
            registry = yamada.model.ComponentRegistry.createDefault();
            [document, ~, children] = CommittedPropertySourcePlanTest.gridFixture(registry, 2);
            label = children(1);
            document.setProperty(label.Id, "FontSize", 23, registry);
            document.validatePropertyCommit(registry);
            measured = [20 20 100 22];
            beforeCopy = yamada.model.DocumentEditAvailability.copying(document, label.Id, registry);
            beforeDelete = yamada.model.DocumentEditAvailability.deletion(document, label.Id, registry);
            beforeParents = yamada.model.DocumentEditAvailability.reparenting(document, label.Id, registry, measured);
            testCase.assertTrue(beforeCopy.Enabled);
            testCase.assertTrue(beforeDelete.Enabled);
            document.setPropertyBatch(label.Id, ...
                yamada.model.PropertyTransaction.singleChange("FontSize", 31), registry);
            document.validatePropertyCommit(registry);

            % Condition reads must use immutable prior answers for the same measured rectangle.
            afterCopy = yamada.model.DocumentEditAvailability.copying(document, label.Id, registry);
            afterDelete = yamada.model.DocumentEditAvailability.deletion(document, label.Id, registry);
            afterParents = yamada.model.DocumentEditAvailability.reparenting(document, label.Id, registry, measured);
            testCase.verifyEqual(afterCopy, beforeCopy);
            testCase.verifyEqual(afterDelete, beforeDelete);
            testCase.verifyEqual(afterParents, beforeParents);

            % Changed fit geometry must still recompute destination conditions.
            yamada.model.DocumentEditAvailability.reparenting(document, label.Id, registry, [20 20 100 40]);
            snapshot = document.copySubtree(label.Id, registry);
            font = snapshot.Records(1).Properties(string({snapshot.Records(1).Properties.Path}) == "FontSize");
            testCase.verifyEqual(font.LiteralValue, 31);
            document.removeSubtree(label.Id, registry);
            document.undo();
            testCase.verifyEqual(document.getComponent(label.Id).getProperty("FontSize").LiteralValue, 31);
        end

        function inheritedConditionsInvalidateOnSemanticChanges(testCase)
            % inheritedConditionsInvalidateOnSemanticChanges Reject stale permissions after ownership and catalog changes.
            for kind = ["readonly", "metadata", "registry"]
                registry = yamada.model.ComponentRegistry.createDefault();
                [document, label] = CommittedPropertySourcePlanTest.fixture(registry, false);
                document.setProperty(label.Id, "FontSize", 23, registry);
                document.validatePropertyCommit(registry);
                yamada.model.DocumentEditAvailability.copying(document, label.Id, registry);
                document.setProperty(label.Id, "FontSize", 31, registry);
                document.validatePropertyCommit(registry);
                yamada.model.DocumentEditAvailability.copying(document, label.Id, registry);
                switch kind
                    case "readonly"
                        label.IsEditable = false;
                    case "metadata"
                        document.Metadata.EligibilityInvalidation = true;
                    case "registry"
                        registry.register(registry.get("uilabel"));
                end
                state = yamada.model.DocumentEditAvailability.copying(document, label.Id, registry);
                if kind == "readonly", testCase.verifyFalse(state.Enabled); end
            end
        end

        function localCommitReusesOnlyProvenModelValidation(testCase)
            % localCommitReusesOnlyProvenModelValidation Avoid duplicate checks while retaining full save verification.
            registry = yamada.model.ComponentRegistry.createDefault();
            for inGrid = [false true]
                for batch = [false true]
                    [document, label] = CommittedPropertySourcePlanTest.fixture(registry, inGrid);
                    document.setProperty(label.Id, "FontSize", 23, registry);
                    baseline = document.validatePropertyCommit(registry);
                    document.Diagnostics = yamada.model.Diagnostic("preview-only", "warning", "Derived presentation data.");

                    % Apply the edit and compare its diagnostics with independent validation.
                    if batch
                        document.setPropertyBatch(label.Id, ...
                            yamada.model.PropertyTransaction.singleChange("FontSize", 31), registry);
                    else
                        document.setProperty(label.Id, "FontSize", 31, registry);
                    end
                    actual = document.validatePropertyCommit(registry);
                    testCase.verifyEqual(actual, baseline);
                    testCase.verifyEqual(document.Diagnostics, baseline);
                    testCase.verifyEqual(label.getProperty("FontSize").LiteralValue, 31);
                    testCase.verifyEqual(document.HistoryIndex, 2);

                    % Direct validation and the save checkpoint retain their complete checks.
                    expected = yamada.validation.ModelValidator.validate(document, registry);
                    source = yamada.source.RoundTripGenerator(registry).generate(document);
                    checkpoint = yamada.model.SavedSourceCheckpoint(document, source, ...
                        fullfile(tempdir, document.ClassName + ".m"), registry);
                    testCase.verifyEqual(actual, expected);
                    testCase.verifyEqual(checkpoint.SourceText, yamada.source.SourceWriter.normalize(source, document.LineEnding));
                end
            end
        end

        function commitValidationRejectsStaleProofs(testCase)
            % commitValidationRejectsStaleProofs Revalidate semantic, catalog, history, and unpreflighted changes.
            for kind = ["metadata", "entry", "registry", "history", "unproven", "structure"]
                registry = yamada.model.ComponentRegistry.createDefault();
                [document, label] = CommittedPropertySourcePlanTest.fixture(registry, true);
                document.setProperty(label.Id, "FontSize", 23, registry);
                document.validatePropertyCommit(registry);
                switch kind
                    case "metadata"
                        document.Metadata.ValidationProofInvalidation = true;
                    case "entry"
                        label.setProperty("Text", "Direct write");
                    case "registry"
                        registry.register(registry.get("uilabel"));
                    case "history"
                        document.undo();
                    case "unproven"
                        label.setProperty("FontSize", 31);
                    case "structure"
                        document.insertComponent(registry, "uilabel", document.RootComponentId);
                end
                actual = document.validatePropertyCommit(registry);
                testCase.verifyEqual(actual, yamada.validation.ModelValidator.validate(document, registry));
            end
        end

        function repeatedNumericEditsAvoidWholeSourcePreflight(testCase)
            % repeatedNumericEditsAvoidWholeSourcePreflight Reuse proven placement for saved and unsaved settings.
            registry = yamada.model.ComponentRegistry.createDefault();
            for inGrid = [false true]
                for sourceBacked = [false true]
                    for batch = [false true]
                        [document, label] = CommittedPropertySourcePlanTest.fixture(registry, inGrid);
                        if sourceBacked
                            label.setProperty("FontSize", 17);
                            source = yamada.source.RoundTripGenerator(registry).generate(document);
                            document = yamada.source.AppSourceParser.parseText(source, registry);
                            label = document.getComponentByName(label.Name);
                        end
                        original = document.OriginalText;
                        document.setProperty(label.Id, "FontSize", 23, registry);
                        settings = label.Settings;
                        previousPlan = yamada.source.PropertySourcePlan.combined(document, label, registry);

                        % Measure the complete model transaction, including committed source sharing.
                        if batch
                            document.setPropertyBatch(label.Id, ...
                                yamada.model.PropertyTransaction.singleChange("FontSize", 37), registry);
                        else
                            document.setProperty(label.Id, "FontSize", 37, registry);
                        end
                        testCase.verifyEqual(document.OriginalText, original);
                        testCase.verifyEqual(string({label.Settings.Id}), string({settings.Id}));
                        testCase.verifyEqual(label.getSettings("FontSize").LiteralValue, 37);
                        testCase.verifyEqual(document.HistoryIndex, 2);
                        testCase.verifyNotEmpty(previousPlan.Component);
                        testCase.verifyEqual(previousPlan.Component.getProperty("FontSize").LiteralValue, 23);
                        states = document.getEffectivePropertyStates(registry, label.Id);
                        font = states(arrayfun(@(item) item.Definition.Path == "FontSize", states)).Resolution;
                        testCase.verifyTrue(font.IsKnown);
                        testCase.verifyEqual(font.EffectiveValue, 37);

                        % Compare emission against a fresh full-preflight reference and exercise history.
                        reference = yamada.source.AppSourceParser.parseText(original, registry);
                        referenceLabel = reference.getComponentByName(label.Name);
                        reference.setProperty(referenceLabel.Id, "FontSize", 37, registry);
                        source = yamada.source.RoundTripGenerator(registry).generate(document);
                        testCase.verifyEqual(source, yamada.source.RoundTripGenerator(registry).generate(reference));
                        parsed = yamada.source.AppSourceParser.parseText(source, registry);
                        testCase.verifyEqual(parsed.getComponentByName(label.Name).getProperty("FontSize").LiteralValue, 37);
                        document.undo();
                        testCase.verifyEqual(label.getProperty("FontSize").LiteralValue, 23);
                        document.redo();
                        testCase.verifyEqual(label.getProperty("FontSize").LiteralValue, 37);
                    end
                end
            end
        end

        function localNumericEditsRejectInvalidValuesAtomically(testCase)
            % localNumericEditsRejectInvalidValuesAtomically Keep range failures outside the live model and history.
            registry = yamada.model.ComponentRegistry.createDefault();
            [document, label] = CommittedPropertySourcePlanTest.fixture(registry, true);
            document.setProperty(label.Id, "FontSize", 23, registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            testCase.verifyError(@() document.setPropertyBatch(label.Id, ...
                yamada.model.PropertyTransaction.singleChange("FontSize", -1), registry), ...
                "yamada:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(label.getProperty("FontSize").LiteralValue, 23);
            testCase.verifyEqual(document.HistoryIndex, 1);
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
            document.setProperty(label.Id, "FontSize", 31, registry);
            testCase.verifyEqual(label.getProperty("FontSize").LiteralValue, 31);
        end

        function numericCheckpointInvalidatesAfterExternalChanges(testCase)
            % numericCheckpointInvalidatesAfterExternalChanges Require full preflight after writes or catalog/history changes.
            for kind = ["metadata", "entry", "registry", "history"]
                registry = yamada.model.ComponentRegistry.createDefault();
                [document, label] = CommittedPropertySourcePlanTest.fixture(registry, true);
                document.setProperty(label.Id, "FontSize", 23, registry);
                switch kind
                    case "metadata"
                        document.Metadata.LocalProofInvalidation = true;
                    case "entry"
                        label.setProperty("Text", "Direct write");
                    case "registry"
                        registry.register(registry.get("uilabel"));
                    case "history"
                        document.undo();
                        document.redo();
                end
                document.setProperty(label.Id, "FontSize", 31, registry);
                document.validatePropertyCommit(registry);
                testCase.verifyEqual(label.getProperty("FontSize").LiteralValue, 31);
            end
        end

        function siblingStateReadsDoNotClonePerChild(testCase)
            % siblingStateReadsDoNotClonePerChild Bound document copies when siblings read one grid result.
            registry = yamada.model.ComponentRegistry.createDefault();
            for count = [2 8]
                [document, grid, children] = CommittedPropertySourcePlanTest.gridFixture(registry, count);
                document.setPropertyBatch(children(1).Id, ...
                    yamada.model.PropertyTransaction.singleChange("FontSize", 23), registry);
                original = document.OriginalText;
                rows = zeros(1, count);
                effects = zeros(1, count);

                % Read effective values and verify independently mutable public results.
                document.getEffectivePropertyStates(registry, grid.Id);
                for index = 1:count
                    states = document.getEffectivePropertyStates(registry, children(index).Id);
                    resolution = states(arrayfun(@(item) item.Definition.Path == "Layout.Row", states)).Resolution;
                    rows(index) = resolution.EffectiveValue;
                    effects(index) = resolution.EffectSettingId;
                end
                testCase.verifyEqual(rows, 1:count);
                for index = 1:count
                    testCase.verifyEqual(effects(index), children(index).getSettings("Layout.Row").Id);
                end
                testCase.verifyEqual(document.OriginalText, original);
                testCase.verifyEqual(document.HistoryIndex, 1);

                % Compare finite values with independently generated and reparsed initialization.
                source = yamada.source.RoundTripGenerator(registry).generate(document);
                parsed = yamada.source.AppSourceParser.parseText(source, registry);
                expected = parsed.getComponentByName(grid.Name);
                actualStates = document.getEffectivePropertyStates(registry, grid.Id);
                expectedStates = parsed.getEffectivePropertyStates(registry, expected.Id);
                for path = ["RowHeight", "ColumnWidth"]
                    actual = actualStates(arrayfun(@(item) item.Definition.Path == path, actualStates)).Resolution;
                    expectedState = expectedStates(arrayfun(@(item) item.Definition.Path == path, expectedStates)).Resolution;
                    testCase.verifyEqual(actual.EffectiveValue, expectedState.EffectiveValue);
                    testCase.verifyEqual(actual.IsKnown, expectedState.IsKnown);
                end
            end
        end

        function gridValuesInvalidateAcrossWritesAndHistory(testCase)
            % gridValuesInvalidateAcrossWritesAndHistory Keep cached tracks and coordinates tied to current input.
            registry = yamada.model.ComponentRegistry.createDefault();
            [document, grid, children] = CommittedPropertySourcePlanTest.gridFixture(registry, 2);
            document.setPropertyBatch(children(1).Id, ...
                yamada.model.PropertyTransaction.singleChange("FontSize", 23), registry);
            document.getEffectivePropertyStates(registry, grid.Id);

            % A compound placement edit must invalidate all earlier geometry values.
            document.applyGridLayoutEdit(grid.Id, ...
                [struct("ComponentId", grid.Id, "Path", "RowHeight", "Value", {{40, 80, "1x"}}), ...
                struct("ComponentId", children(2).Id, "Path", "Layout.Row", "Value", 3)], registry);
            states = document.getEffectivePropertyStates(registry, grid.Id);
            value = states(arrayfun(@(item) item.Definition.Path == "RowHeight", states)).Resolution.EffectiveValue;
            testCase.verifyEqual(value, {40, 80, "1x"});
            value{1} = 999; %#ok<NASGU>
            states = document.getEffectivePropertyStates(registry, grid.Id);
            testCase.verifyEqual(states(arrayfun(@(item) item.Definition.Path == "RowHeight", states)).Resolution.EffectiveValue, ...
                {40, 80, "1x"});

            % Undo and Redo restore the complete source and its derived grid state.
            document.undo();
            document.redo();
            states = document.getEffectivePropertyStates(registry, grid.Id);
            testCase.verifyEqual(states(arrayfun(@(item) item.Definition.Path == "RowHeight", states)).Resolution.EffectiveValue, ...
                {40, 80, "1x"});
            previous = document.evaluationContext(registry);
            registry.register(registry.get("uigridlayout"));
            testCase.verifyNotEqual(document.evaluationContext(registry), previous);
            states = document.getEffectivePropertyStates(registry, grid.Id);
            testCase.verifyEqual(states(arrayfun(@(item) item.Definition.Path == "RowHeight", states)).Resolution.EffectiveValue, ...
                {40, 80, "1x"});
            document.Metadata.HasUnresolvedInitialization = true;
            states = document.getEffectivePropertyStates(registry, grid.Id);
            testCase.verifyEqual(states(arrayfun(@(item) item.Definition.Path == "RowHeight", states)).Resolution.EffectiveValue, ...
                {40, 80, "1x"});
            document.Metadata.HasUnresolvedInitialization = false;
            states = document.getEffectivePropertyStates(registry, grid.Id);
            testCase.verifyEqual(states(arrayfun(@(item) item.Definition.Path == "RowHeight", states)).Resolution.EffectiveValue, ...
                {40, 80, "1x"});
            testCase.verifyEqual(document.HistoryIndex, 2);
        end

        function committedEditsDoNotReparseForStateConsumers(testCase)
            % committedEditsDoNotReparseForStateConsumers Reuse complete source for single and batch edits.
            registry = yamada.model.ComponentRegistry.createDefault();
            for inGrid = [false true]
                for batch = [false true]
                    [document, label] = CommittedPropertySourcePlanTest.fixture(registry, inGrid);
                    original = document.OriginalText;
                    if batch
                        document.setPropertyBatch(label.Id, ...
                            yamada.model.PropertyTransaction.singleChange("FontSize", 23), registry);
                    else
                        document.setProperty(label.Id, "FontSize", 23, registry);
                    end

                    % Check state consumers after distinct accepted source edits.
                    plan = yamada.source.PropertySourcePlan.plan(document, label, registry);
                    states = document.getEffectivePropertyStates(registry, label.Id);
                    testCase.verifyEqual(plan.Component.getProperty("FontSize").LiteralValue, 23);
                    state = states(arrayfun(@(item) item.Definition.Path == "FontSize", states)).Resolution;
                    testCase.verifyTrue(state.IsKnown);
                    testCase.verifyEqual(state.EffectiveValue, 23);
                    testCase.verifyEqual(document.OriginalText, original);
                    testCase.verifyEqual(document.HistoryIndex, 1);
                    document.undo();
                    testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), original);
                end
            end
        end

        function committedPlansRemainIndependentAndInvalidateOnWrites(testCase)
            % committedPlansRemainIndependentAndInvalidateOnWrites Never borrow stale values or caller mutations.
            registry = yamada.model.ComponentRegistry.createDefault();
            [document, label] = CommittedPropertySourcePlanTest.fixture(registry, true);
            document.setPropertyBatch(label.Id, ...
                yamada.model.PropertyTransaction.singleChange("FontSize", 23), registry);
            first = yamada.source.PropertySourcePlan.plan(document, label, registry);
            first.Component.setProperty("FontSize", 99);
            second = yamada.source.PropertySourcePlan.plan(document, label, registry);
            testCase.verifyEqual(second.Component.getProperty("FontSize").LiteralValue, 23);
            testCase.verifyEqual(label.getProperty("FontSize").LiteralValue, 23);

            % Direct record writes and registry replacement both invalidate the shared plan.
            label.setProperty("FontSize", 31);
            [~, found] = document.evaluationContext(registry).configuration("combined", label.Name);
            testCase.verifyFalse(found);
            updated = yamada.source.PropertySourcePlan.plan(document, label, registry);
            testCase.verifyEqual(updated.Component.getProperty("FontSize").LiteralValue, 31);
            registry.register(registry.get("uilabel"));
            [~, found] = document.evaluationContext(registry).configuration("combined", label.Name);
            testCase.verifyFalse(found);
            updated = yamada.source.PropertySourcePlan.plan(document, label, registry);
            testCase.verifyEqual(updated.Component.getProperty("FontSize").LiteralValue, 31);
            testCase.verifyEqual(document.HistoryIndex, 1);
        end
    end

    methods (Static, Access = private)
        function [document, grid, children] = gridFixture(registry, count)
            % gridFixture Parse a grid with explicit independent child coordinates.
            arguments (Input)
                registry (1, 1) yamada.model.ComponentRegistry
                count (1, 1) double {mustBePositive, mustBeInteger}
            end
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                grid (1, 1) yamada.model.ComponentRecord
                children (1, :) yamada.model.ComponentRecord
            end
            document = yamada.model.NewAppFactory.createEmpty("SharedGridFixture", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            grid.setProperty("RowHeight", repmat({"1x"}, 1, count));
            grid.setProperty("ColumnWidth", {"1x"});
            children = yamada.model.ComponentRecord.empty;
            for index = 1:count
                child = document.insertComponent(registry, "uilabel", grid.Id);
                child.setProperty("Layout.Row", index);
                child.setProperty("Layout.Column", 1);
                children(end + 1) = child; %#ok<AGROW>
            end
            names = string({children.Name});
            gridName = grid.Name;
            source = yamada.source.NewAppGenerator(registry).generate(document);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            grid = document.getComponentByName(gridName);
            children = yamada.model.ComponentRecord.empty;
            for name = names, children(end + 1) = document.getComponentByName(name); end %#ok<AGROW>
        end

        function [document, label] = fixture(registry, inGrid)
            % fixture Create parsed controls with no explicit font setting in either parent layout.
            arguments (Input)
                registry (1, 1) yamada.model.ComponentRegistry
                inGrid (1, 1) logical
            end
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                label (1, 1) yamada.model.ComponentRecord
            end
            document = yamada.model.NewAppFactory.createEmpty("CommittedSourceFixture", registry);
            parentId = document.RootComponentId;
            if inGrid
                grid = document.insertComponent(registry, "uigridlayout", parentId);
                parentId = grid.Id;
            end
            label = document.insertComponent(registry, "uilabel", parentId);
            name = label.Name;
            source = yamada.source.NewAppGenerator(registry).generate(document);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName(name);
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

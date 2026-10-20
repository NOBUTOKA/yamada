classdef (TestTags = {'fast', 'model', 'generation'}) EvaluationContextTest < matlab.unittest.TestCase
    % EvaluationContextTest Verify exact-input caching without shared mutable results.
    %   Direct changes and history branching must not reuse an obsolete evaluation.
    methods (Test)
        function nestedGridInheritanceKeepsUnrelatedScopes(testCase)
            % nestedGridInheritanceKeepsUnrelatedScopes Invalidate coupled descendants while retaining separate groups.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("NestedInheritanceFixture", registry);
            outer = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            inner = document.insertComponent(registry, "uigridlayout", outer.Id);
            first = document.insertComponent(registry, "uilabel", inner.Id);
            sibling = document.insertComponent(registry, "uilabel", inner.Id);
            separate = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            other = document.insertComponent(registry, "uilabel", separate.Id);
            absolute = document.insertComponent(registry, "uilabel", document.RootComponentId);
            ids = [first.Id, sibling.Id, outer.Id, other.Id, absolute.Id];
            for id = ids
                document.getEffectivePropertyStates(registry, id);
            end
            history = document.HistoryIndex;
            candidate = document.structuralCandidate(registry);
            context = candidate.evaluationContext(registry);
            for id = ids
                [~, found] = context.lookup("states:" + id);
                testCase.assertTrue(found);
            end

            % A local setter invalidates every overlapping grid scope, not independent siblings.
            candidate.getComponent(first.Id).setProperty("FontSize", 19);
            context = candidate.evaluationContext(registry);
            for id = [first.Id, sibling.Id, outer.Id]
                [~, found] = context.lookup("states:" + id);
                testCase.verifyFalse(found);
            end
            for id = [other.Id, absolute.Id]
                [~, found] = context.lookup("states:" + id);
                testCase.verifyTrue(found);
            end
            testCase.verifyEmpty(first.getProperty("FontSize"));
            testCase.verifyEqual(candidate.getComponent(first.Id).getProperty("FontSize").LiteralValue, 19);
            testCase.verifyEqual(document.HistoryIndex, history);
        end

        function inheritedScopesPreserveNestedValueEquality(testCase)
            % inheritedScopesPreserveNestedValueEquality Keep NaN equality and distinguish empty-array shapes.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ValueInheritanceFixture", registry);
            first = document.insertComponent(registry, "uilabel", document.RootComponentId);
            second = document.insertComponent(registry, "uilabel", document.RootComponentId);
            first.Metadata.EqualityFixture = struct("Samples", [NaN Inf], ...
                "Empty", zeros(0, 2), "Cell", {{[], strings(0, 1)}});
            document.getEffectivePropertyStates(registry, first.Id);
            document.getEffectivePropertyStates(registry, second.Id);
            candidate = document.structuralCandidate(registry);
            copied = candidate.getComponent(first.Id);
            copied.Metadata.EqualityFixture.Samples = [NaN Inf];
            context = candidate.evaluationContext(registry);
            [~, found] = context.lookup("states:" + first.Id);
            testCase.verifyTrue(found);

            % Equal empty contents with a different shape still change the complete input.
            copied.Metadata.EqualityFixture.Empty = zeros(0, 3);
            context = candidate.evaluationContext(registry);
            [~, found] = context.lookup("states:" + first.Id);
            testCase.verifyFalse(found);
            [~, found] = context.lookup("states:" + second.Id);
            testCase.verifyTrue(found);
            testCase.verifySize(first.Metadata.EqualityFixture.Empty, [0 2]);
            testCase.verifySize(copied.Metadata.EqualityFixture.Empty, [0 3]);
        end

        function isolatedCandidatesRetainOnlyUnaffectedStates(testCase)
            % isolatedCandidatesRetainOnlyUnaffectedStates Reuse value resolutions without sharing editable records.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CandidateFixture", registry);
            first = document.insertComponent(registry, "uilabel", document.RootComponentId);
            second = document.insertComponent(registry, "uilabel", document.RootComponentId);
            first.setProperty("FontSize", 13);
            document.getEffectivePropertyStates(registry, first.Id);
            document.getEffectivePropertyStates(registry, second.Id);
            history = document.HistoryIndex;
            dirty = document.IsDirty;
            candidate = document.structuralCandidate(registry);
            context = candidate.evaluationContext(registry);
            [~, found] = context.lookup("states:" + second.Id);
            testCase.verifyTrue(found);
            candidate.getComponent(first.Id).setProperty("FontSize", 21);
            context = candidate.evaluationContext(registry);
            [~, found] = context.lookup("states:" + first.Id);
            testCase.verifyFalse(found);
            [~, found] = context.lookup("states:" + second.Id);
            testCase.verifyTrue(found);
            testCase.verifyEqual(first.getProperty("FontSize").LiteralValue, 13);
            testCase.verifyEqual(candidate.getComponent(first.Id).getProperty("FontSize").LiteralValue, 21);
            testCase.verifyEqual(document.HistoryIndex, history);
            testCase.verifyEqual(document.IsDirty, dirty);
        end

        function candidateGridChangesDiscardCoupledStates(testCase)
            % candidateGridChangesDiscardCoupledStates Preserve the existing conservative grid dependency scope.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CandidateGridFixture", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            grid.setProperty("RowHeight", {"1x", "1x"});
            label = document.insertComponent(registry, "uilabel", grid.Id);
            document.getEffectivePropertyStates(registry, label.Id);
            candidate = document.structuralCandidate(registry);
            context = candidate.evaluationContext(registry);
            [~, found] = context.lookup("states:" + label.Id);
            testCase.verifyTrue(found);
            candidate.getComponent(grid.Id).setProperty("RowHeight", {40, 80});
            context = candidate.evaluationContext(registry);
            [~, found] = context.lookup("states:" + label.Id);
            testCase.verifyFalse(found);
            testCase.verifyEqual(grid.getProperty("RowHeight").LiteralValue, {"1x", "1x"});
        end

        function liveDefinitionDataCannotBorrowAnIndependentProof(testCase)
            % liveDefinitionDataCannotBorrowAnIndependentProof Reject live metadata behind the same property path.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            context = document.evaluationContext(registry);
            independent = macd.model.PropertyDefinition("Example", 1, true);
            context.remember("independent", struct("Definitions", independent));
            [~, found] = context.lookup("independent");
            testCase.verifyTrue(found);
            live = containers.Map("a", 1);
            definition = macd.model.PropertyDefinition("Example", 1, true, true, struct("Live", live));
            context.remember("live", struct("Definitions", definition));
            [~, found] = context.lookup("live");
            testCase.verifyFalse(found);
            live("a") = 2;
            testCase.verifyEqual(live("a"), 2);
            context.remember("live", struct("Definitions", definition));
            [~, found] = context.lookup("live");
            testCase.verifyFalse(found);
            document.Metadata.Definition = definition;
            context = document.evaluationContext(registry);
            [~, safe] = context.inputs();
            testCase.verifyFalse(safe);
        end

        function writesInvalidateAnAccidentallyHeldReadScope(testCase)
            % writesInvalidateAnAccidentallyHeldReadScope Do not hide tracked writes behind a read lease.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            context = document.evaluationContext(registry);
            lease = context.readScope(); %#ok<NASGU>
            document.Metadata.Changed = true;
            testCase.verifyFalse(context.isReading(registry));
            testCase.verifyNotEqual(document.evaluationContext(registry), context);
        end

        function buttonGroupSiblingChangesDiscardResolverValues(testCase)
            % buttonGroupSiblingChangesDiscardResolverValues Preserve the exclusive-selection dependency scope.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            group = document.insertComponent(registry, "uibuttongroup", document.RootComponentId);
            first = document.insertComponent(registry, "uiradiobutton", group.Id);
            second = document.insertComponent(registry, "uiradiobutton", group.Id);
            definitions = registry.getEffectiveProperties(second.Factory, group.Factory, second.CreationArguments);
            macd.model.PropertyStateResolver.resolve(second, definitions, document, registry);
            first.setProperty("Value", true);
            context = document.evaluationContext(registry);
            [~, found] = context.lookup("states:" + second.Id);
            testCase.verifyFalse(found);
        end

        function sourceChangesDiscardAllResolverValues(testCase)
            % sourceChangesDiscardAllResolverValues Keep source and global initialization inputs authoritative.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            root = document.getComponent(document.RootComponentId);
            definitions = registry.getEffectiveProperties(root.Factory, "", root.CreationArguments);
            macd.model.PropertyStateResolver.resolve(root, definitions, document, registry);
            document.Metadata.HasUnresolvedInitialization = true;
            context = document.evaluationContext(registry);
            [~, found] = context.lookup("states:" + root.Id);
            testCase.verifyFalse(found);
            states = macd.model.PropertyStateResolver.resolve(root, definitions, document, registry);
            testCase.verifyFalse(any([states.IsKnown]));
        end

        function unchangedAbsoluteSiblingRetainsResolverValues(testCase)
            % unchangedAbsoluteSiblingRetainsResolverValues Reuse an unchanged dependency scope after a local write.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            first = document.insertComponent(registry, "uilabel", document.RootComponentId);
            second = document.insertComponent(registry, "uilabel", document.RootComponentId);
            definitions = registry.getEffectiveProperties(second.Factory, document.getComponent(second.ParentId).Factory, second.CreationArguments);
            [expected, diagnostics] = macd.model.PropertyStateResolver.resolve(second, definitions, document, registry);
            before = document.evaluationContext(registry);
            [~, found] = before.lookup("states:" + second.Id);
            testCase.verifyTrue(found);
            first.setProperty("FontSize", 19);
            after = document.evaluationContext(registry);
            [cached, found] = after.lookup("states:" + second.Id);
            testCase.verifyTrue(found);
            testCase.verifyEqual(cached.States, expected);
            testCase.verifyEqual(cached.Diagnostics, diagnostics);
        end

        function ancestorAndCoupledSiblingChangesDiscardResolverValues(testCase)
            % ancestorAndCoupledSiblingChangesDiscardResolverValues Include geometry and grid members in invalidation.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            first = document.insertComponent(registry, "uilabel", grid.Id);
            second = document.insertComponent(registry, "uilabel", grid.Id);
            definitions = registry.getEffectiveProperties(second.Factory, document.getComponent(second.ParentId).Factory, second.CreationArguments);
            macd.model.PropertyStateResolver.resolve(second, definitions, document, registry);
            first.setProperty("FontSize", 19);
            context = document.evaluationContext(registry);
            [~, found] = context.lookup("states:" + second.Id);
            testCase.verifyFalse(found);
            macd.model.PropertyStateResolver.resolve(second, definitions, document, registry);
            document.getComponent(document.RootComponentId).setProperty("Position", [1 1 900 700]);
            context = document.evaluationContext(registry);
            [~, found] = context.lookup("states:" + second.Id);
            testCase.verifyFalse(found);
        end

        function changedThenRestoredValueStillInvalidatesRevision(testCase)
            % changedThenRestoredValueStillInvalidatesRevision Observe writes without rescanning equal final values.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            context = document.evaluationContext(registry);
            document.ClassName = "TemporaryName";
            document.ClassName = "CacheFixture";
            testCase.verifyFalse(context.matches(document, registry));
        end

        function nestedAssignmentsInvalidateAllOwners(testCase)
            % nestedAssignmentsInvalidateAllOwners Observe public struct and cell subscript writes.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            root = document.getComponent(document.RootComponentId);
            entry = root.getProperty("Name");
            context = document.evaluationContext(registry);
            root.Metadata.Nested.Value = 1;
            testCase.verifyFalse(context.matches(document, registry));
            context = document.evaluationContext(registry);
            entry.Metadata.Nested.Value = 2;
            testCase.verifyFalse(context.matches(document, registry));
            context = document.evaluationContext(registry);
            document.PendingEdits{end + 1} = struct("Example", 3);
            testCase.verifyFalse(context.matches(document, registry));
        end

        function collectionChangesAttachNewEntries(testCase)
            % collectionChangesAttachNewEntries Track entries introduced after the first evaluation.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            root = document.getComponent(document.RootComponentId);
            previous = document.evaluationContext(registry);
            entry = root.setProperty("Tooltip", "first");
            testCase.verifyFalse(previous.matches(document, registry));
            current = document.evaluationContext(registry);
            entry.setLiteral("second");
            testCase.verifyFalse(current.matches(document, registry));
            current = document.evaluationContext(registry);
            root.removeProperty("Tooltip");
            testCase.verifyFalse(current.matches(document, registry));
            % Public component collections accept either array orientation.
            document.addComponent(macd.model.ComponentRecord("column-label", "ColumnLabel", ...
                "uilabel", "matlab.ui.control.Label"), root.Id);
            document.Components = reshape(document.Components, [], 1);
            current = document.evaluationContext(registry);
            root.setProperty("Name", "After collection replacement");
            testCase.verifyFalse(current.matches(document, registry));
        end

        function sharedRecordsUseExactComparisonForBothDocuments(testCase)
            % sharedRecordsUseExactComparisonForBothDocuments Do not lose writes through another owner.
            registry = macd.model.ComponentRegistry.createDefault();
            first = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            old = first.evaluationContext(registry);
            second = macd.model.DocumentModel("CacheFixture");
            second.Components = first.Components;
            second.RootComponentId = first.RootComponentId;
            other = second.evaluationContext(registry);
            testCase.verifyTrue(old.matches(first, registry));
            root = first.getComponent(first.RootComponentId);
            root.Name = "SharedRoot";
            testCase.verifyFalse(old.matches(first, registry));
            testCase.verifyFalse(other.matches(second, registry));
        end

        function candidateWritesDoNotInvalidateOriginal(testCase)
            % candidateWritesDoNotInvalidateOriginal Keep revision ownership separate across deep copies.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            original = document.evaluationContext(registry);
            candidate = document.structuralCandidate();
            candidate.evaluationContext(registry);
            candidate.getComponent(candidate.RootComponentId).setProperty("Name", "Candidate");
            testCase.verifyTrue(original.matches(document, registry));
        end

        function liveDataIntroducedAfterCaptureRejectsFastReuse(testCase)
            % liveDataIntroducedAfterCaptureRejectsFastReuse Reject hidden mutations even after a value is restored.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            previous = document.evaluationContext(registry);
            document.Metadata.Live = containers.Map("a", 1);
            testCase.verifyFalse(previous.matches(document, registry));
            unsafe = document.evaluationContext(registry);
            testCase.verifyFalse(unsafe.matches(document, registry));
            document.Metadata = struct();
            safe = document.evaluationContext(registry);
            testCase.verifyTrue(safe.matches(document, registry));
            document.Metadata.After = 1;
            testCase.verifyFalse(safe.matches(document, registry));
        end

        function detectsDirectEntryChangesWithoutHistory(testCase)
            % detectsDirectEntryChangesWithoutHistory Compare current values even outside document commands.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            label = document.insertComponent(registry, "uilabel", document.RootComponentId);
            label.setProperty("FontSize", 13);
            context = document.evaluationContext(registry);
            context.remember("sample", struct("value", 13));
            [value, found] = context.lookup("sample");
            testCase.verifyTrue(found);
            testCase.verifyEqual(value.value, 13);
            label.getProperty("FontSize").setLiteral(17);
            testCase.verifyFalse(context.matches(document, registry));
            replacement = document.evaluationContext(registry);
            [~, found] = replacement.lookup("sample");
            testCase.verifyFalse(found);
        end

        function derivedOutputsDoNotInvalidateInputs(testCase)
            % derivedOutputsDoNotInvalidateInputs Exclude generated text and display diagnostics.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            context = document.evaluationContext(registry);
            document.GeneratedText = "derived output";
            document.Diagnostics = macd.model.Diagnostic("example", "warning", "Derived diagnostic.");
            testCase.verifyTrue(context.matches(document, registry));
            document.Metadata.DirectInput = 1;
            testCase.verifyFalse(context.matches(document, registry));
        end

        function doesNotExposeSharedConfigurationHandles(testCase)
            % doesNotExposeSharedConfigurationHandles Copy a cached plan for each mutable caller.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            context = document.evaluationContext(registry);
            context.rememberConfiguration("plan", document);
            [first, found] = context.configuration("plan", "UIFigure");
            testCase.verifyTrue(found);
            first.Component.setProperty("Name", "Changed privately");
            [second, found] = context.configuration("plan", "UIFigure");
            testCase.verifyTrue(found);
            testCase.verifyNotEqual(second.Component.getProperty("Name").LiteralValue, "Changed privately");
        end

        function liveMetadataBypassesCache(testCase)
            % liveMetadataBypassesCache Do not assume unrecognized mutable metadata is immutable.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            document.Metadata.Live = containers.Map("a", 1);
            context = document.evaluationContext(registry);
            context.remember("sample", 1);
            [~, found] = context.lookup("sample");
            testCase.verifyFalse(found);
            testCase.verifyFalse(context.matches(document, registry));
        end

        function registryChangesInvalidateContext(testCase)
            % registryChangesInvalidateContext Detect registration even when its values are equal.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            context = document.evaluationContext(registry);
            registry.register(registry.get("uilabel"));
            testCase.verifyFalse(context.matches(document, registry));
        end

        function cyclicLiveMetadataBypassesWithoutRetainingHandles(testCase)
            % cyclicLiveMetadataBypassesWithoutRetainingHandles Do not recursively snapshot arbitrary model references.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            root = document.getComponent(document.RootComponentId);
            root.Metadata.Live = root;
            context = document.evaluationContext(registry);
            [inputs, safe] = context.inputs();
            testCase.verifyFalse(safe);
            testCase.verifyEmpty(fieldnames(inputs));
            testCase.verifyFalse(context.matches(document, registry));
            root.Metadata = struct();
        end

        function historyBranchAndSourceConventionsInvalidateContext(testCase)
            % historyBranchAndSourceConventionsInvalidateContext Never identify input by history index alone.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            label = document.insertComponent(registry, "uilabel", document.RootComponentId);
            document.setProperty(label.Id, "FontSize", 17, registry);
            previous = document.evaluationContext(registry);
            previous.remember("sample", 17);
            index = document.HistoryIndex;
            document.undo();
            document.setProperty(label.Id, "FontSize", 21, registry);
            testCase.verifyEqual(document.HistoryIndex, index);
            testCase.verifyFalse(previous.matches(document, registry));
            current = document.evaluationContext(registry);
            document.LineEnding = "LF";
            testCase.verifyFalse(current.matches(document, registry));
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

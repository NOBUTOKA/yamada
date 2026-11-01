classdef GridLayoutStatePolicyTest < matlab.unittest.TestCase
    % GridLayoutStatePolicyTest Verify finite grid effects and source-edit safety.
    %   Fixtures keep explicit source occurrences independent of effective tracks,
    %   default child placement, copy configuration, and Preview projection.

    methods (Test, TestTags = {'fast', 'model', 'parser', 'generation', 'roundtrip'})
        function committedPlacementProjectsPrivateGridValues(testCase)
            % committedPlacementProjectsPrivateGridValues Preserve source identities and padded tracks without plan copies.
            [document, registry, grid] = testCase.fixture(["app.Grid = uigridlayout(app.UIFigure);", ...
                "app.First = uibutton(app.Grid);", "app.Second = uibutton(app.Grid);"]);
            first = document.getComponentByName("First");
            second = document.getComponentByName("Second");
            document.setProperty(first.Id, "Layout.Row", 3, registry);
            context = document.evaluationContext(registry);

            profile clear; profile on;
            cleanup = onCleanup(@() profile("off"));
            actual = testCase.state(document, registry, grid, "RowHeight");
            profile off; functions = profile("info").FunctionTable; clear cleanup
            names = string({functions.FunctionName});
            copies = contains(names, "DocumentModel.structuralCandidate") | ...
                contains(names, "DocumentModel.fromConfigurationSnapshot");
            testCase.verifyEqual(sum([functions(copies).NumCalls]), 0);
            testCase.verifyTrue(actual.IsKnown);
            testCase.verifyTrue(macd.model.GridLayoutStatePolicy.equivalent(actual.EffectiveValue, {"1x", "1x", "1x"}));
            testCase.verifyEqual(testCase.state(document, registry, first, "Layout.Row").EffectiveValue, 3);
            copy = macd.source.PropertySourcePlan.combined(document, grid, registry);
            copy.Component.setProperty("RowHeight", {999});
            again = testCase.state(document, registry, grid, "RowHeight");
            testCase.verifyEqual(again.EffectiveValue, actual.EffectiveValue);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            parsedFirst = parsed.getComponentByName("First");
            testCase.verifyEqual(testCase.state(parsed, registry, parsedFirst, "Layout.Row").EffectiveValue, 3);
        end

        function sharedUncertaintyFollowsDirectSourceChanges(testCase)
            % sharedUncertaintyFollowsDirectSourceChanges Invalidate both empty and diagnostic group results.
            [document, registry, grid] = testCase.fixture(["app.Grid = uigridlayout(app.UIFigure);", ...
                "app.First = uibutton(app.Grid);", "app.Second = uibutton(app.Grid);"]);
            first = document.getComponentByName("First");
            second = document.getComponentByName("Second");
            testCase.verifyTrue(testCase.state(document, registry, grid, "RowHeight").IsKnown);
            testCase.verifyTrue(testCase.state(document, registry, second, "Layout.Column").IsKnown);
            before = first.settingSnapshot();
            uncertain = macd.model.PropertySetting("Layout", [], struct( ...
                "SourceSnapshotId", "changed-layout", "SourceExpression", "layoutValue"));
            first.restoreSettings([before, uncertain.toStruct()]);
            for target = [grid, second]
                path = "Layout.Row";
                if target == grid, path = "RowHeight"; end
                actual = testCase.state(document, registry, target, path);
                testCase.verifyFalse(actual.IsKnown);
                testCase.verifyEqual(actual.ReasonCode, "unreviewed-effect");
                testCase.verifyEqual(actual.EffectSettingId, uncertain.Id);
            end
            first.restoreSettings(before);
            testCase.verifyTrue(testCase.state(document, registry, second, "Layout.Column").IsKnown);
            testCase.verifyTrue(testCase.state(document, registry, grid, "RowHeight").IsKnown);
            % Uncacheable metadata must retain the same uncached uncertainty behavior.
            document.Metadata.Live = containers.Map("entry", 1);
            first.restoreSettings([before, uncertain.toStruct()]);
            actual = testCase.state(document, registry, grid, "RowHeight");
            testCase.verifyFalse(actual.IsKnown);
            testCase.verifyEqual(actual.EffectSettingId, uncertain.Id);
            first.restoreSettings(before);
            testCase.verifyTrue(testCase.state(document, registry, grid, "RowHeight").IsKnown);
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyFalse(document.IsDirty);
        end

        function sharedUncertaintyFollowsCatalogRevisions(testCase)
            % sharedUncertaintyFollowsCatalogRevisions Recompute a cached empty result after policy changes.
            [document, registry, grid] = testCase.fixture(["app.Grid = uigridlayout(app.UIFigure);", ...
                "app.First = uibutton(app.Grid);", "app.First.Text = 'before';"]);
            first = document.getComponentByName("First");
            testCase.verifyTrue(testCase.state(document, registry, grid, "RowHeight").IsKnown);
            original = registry.get("uibutton");
            property = original.getProperty("Text");
            metadata = property.Metadata;
            metadata.application.effectStatus = "unsupported";
            metadata.application.affectedPaths = {"RowHeight", "Layout.Row"};
            metadata.application.effectReason = "Synthetic layout dependency for cache validation.";
            replacement = macd.model.PropertyDefinition(property.Path, property.DefaultValue, ...
                property.HasDefault, property.IsEditable, metadata);
            testCase.replaceButtonProperty(registry, replacement);
            actual = testCase.state(document, registry, grid, "RowHeight");
            testCase.verifyFalse(actual.IsKnown);
            setting = first.getSettings("Text");
            testCase.verifyEqual(actual.EffectSettingId, setting(end).Id);
            registry.register(original);
            testCase.verifyTrue(testCase.state(document, registry, grid, "RowHeight").IsKnown);
        end

        function sharedUncertaintyTracksMembershipAndOrder(testCase)
            % sharedUncertaintyTracksMembershipAndOrder Keep separate grids and moved members tied to current records.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("GridMembershipFixture", registry);
            firstGrid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            first = document.insertComponent(registry, "uibutton", firstGrid.Id);
            secondGrid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            second = document.insertComponent(registry, "uibutton", secondGrid.Id);
            firstEffect = macd.model.PropertySetting("Layout", [], struct( ...
                "SourceSnapshotId", "first-layout", "SourceExpression", "firstLayout"));
            secondEffect = macd.model.PropertySetting("Layout", [], struct( ...
                "SourceSnapshotId", "second-layout", "SourceExpression", "secondLayout"));
            first.restoreSettings([first.settingSnapshot(), firstEffect.toStruct()]);
            second.restoreSettings([second.settingSnapshot(), secondEffect.toStruct()]);
            testCase.verifyEqual(testCase.state(document, registry, firstGrid, "RowHeight").EffectSettingId, firstEffect.Id);
            testCase.verifyEqual(testCase.state(document, registry, secondGrid, "RowHeight").EffectSettingId, secondEffect.Id);

            % Moving the earlier record changes the first diagnostic in its destination group.
            firstGrid.removeChild(first.Id);
            secondGrid.addChild(first.Id);
            first.ParentId = secondGrid.Id;
            testCase.verifyTrue(testCase.state(document, registry, firstGrid, "RowHeight").IsKnown);
            actual = testCase.state(document, registry, secondGrid, "RowHeight");
            testCase.verifyEqual(actual.EffectSettingId, firstEffect.Id);
            document.Components = fliplr(document.Components);
            actual = testCase.state(document, registry, secondGrid, "RowHeight");
            testCase.verifyEqual(actual.EffectSettingId, secondEffect.Id);
        end

        function independentPendingSettingsDoNotCombineGridSource(testCase)
            % independentPendingSettingsDoNotCombineGridSource Keep independent additions out of shared placement plans.
            [document, registry, grid] = testCase.fixture(["app.Grid = uigridlayout(app.UIFigure, [2 2]);", ...
                "app.First = uibutton(app.Grid);", "app.Second = uibutton(app.Grid);"]);
            first = document.getComponentByName("First");
            second = document.getComponentByName("Second");
            document.setProperty(first.Id, "FontSize", 14, registry);
            document.setProperty(second.Id, "FontSize", 15, registry);
            testCase.verifyFalse(macd.model.GridLayoutStatePolicy.requiresCombinedPlan(first, document, registry));
            testCase.verifyFalse(macd.model.GridLayoutStatePolicy.requiresCombinedPlan(first, document));
            testCase.verifyTrue(testCase.state(document, registry, grid, "RowHeight").IsKnown);
            testCase.verifyEqual(testCase.state(document, registry, second, "Layout.Column").EffectiveValue, 2);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifyEqual(count(source, "app.First.FontSize"), 1);
            testCase.verifyEqual(count(source, "app.Second.FontSize"), 1);
            testCase.verifyEqual(document.HistoryIndex, 2);
            document.undo();
            testCase.verifyEmpty(second.getProperty("FontSize"));
            document.redo();
            testCase.verifyEqual(second.getProperty("FontSize").LiteralValue, 15);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(parsed.getComponentByName("First").getProperty("FontSize").LiteralValue, 14);
            testCase.verifyEqual(parsed.getComponentByName("Second").getProperty("FontSize").LiteralValue, 15);
        end

        function logicalChangesInvalidateIndependentGridPlan(testCase)
            % logicalChangesInvalidateIndependentGridPlan Recompute shared plans when coupled settings are introduced.
            [document, registry, grid] = testCase.fixture(["app.Grid = uigridlayout(app.UIFigure, [2 2]);", ...
                "app.First = uibutton(app.Grid);", "app.Second = uibutton(app.Grid);"]);
            first = document.getComponentByName("First");
            second = document.getComponentByName("Second");
            first.setProperty("FontSize", 14);
            second.setProperty("FontSize", 15);
            testCase.verifyFalse(macd.model.GridLayoutStatePolicy.requiresCombinedPlan(grid, document, registry));
            first.setProperty("Layout.Row", 3);
            second.setProperty("Layout.Column", 3);
            testCase.verifyTrue(macd.model.GridLayoutStatePolicy.requiresCombinedPlan(grid, document, registry));
            source = macd.source.RoundTripGenerator(registry).generate(document);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            actual = parsed.getComponentByName("Grid");
            for path = ["RowHeight", "ColumnWidth"]
                before = testCase.state(document, registry, grid, path);
                after = testCase.state(parsed, registry, actual, path);
                testCase.verifyTrue(before.IsKnown && after.IsKnown);
                testCase.verifyTrue(macd.model.GridLayoutStatePolicy.equivalent(before.EffectiveValue, after.EffectiveValue));
            end
        end

        function independentSettingWithNewSiblingKeepsPlacementKnown(testCase)
            % independentSettingWithNewSiblingKeepsPlacementKnown Preserve creation-anchor effects after unrelated insertions.
            [document, registry, grid] = testCase.fixture(["app.Grid = uigridlayout(app.UIFigure, [2 2]);", ...
                "app.First = uibutton(app.Grid);", "app.Second = uibutton(app.Grid);", "app.First.Layout.Row = 4;"]);
            first = document.getComponentByName("First");
            first.setProperty("FontSize", 14);
            third = macd.model.ComponentRecord("new-third", "Third", "uibutton", "matlab.ui.control.Button", "generated");
            document.addComponent(third, grid.Id);
            testCase.verifyFalse(macd.model.GridLayoutStatePolicy.requiresCombinedPlan(grid, document, registry));
            before = testCase.state(document, registry, third, "Layout.Row");
            testCase.verifyTrue(before.IsKnown);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            after = testCase.state(parsed, registry, parsed.getComponentByName("Third"), "Layout.Row");
            testCase.verifyTrue(after.IsKnown);
            testCase.verifyEqual(before.EffectiveValue, after.EffectiveValue);
        end

        function unknownPendingSettingsRetainCombinedFallback(testCase)
            % unknownPendingSettingsRetainCombinedFallback Never infer independence for unregistered setter semantics.
            [document, registry, grid] = testCase.fixture(["app.Grid = uigridlayout(app.UIFigure);", ...
                "app.First = uibutton(app.Grid);", "app.Second = uibutton(app.Grid);"]);
            first = document.getComponentByName("First");
            second = document.getComponentByName("Second");
            first.setProperty("FontSize", 14);
            second.setProperty("FontSize", 15);
            testCase.verifyFalse(macd.model.GridLayoutStatePolicy.requiresCombinedPlan(grid, document, registry));
            first.setProperty("UnregisteredSetting", 1);
            second.setProperty("UnregisteredSetting", 2);
            testCase.verifyTrue(macd.model.GridLayoutStatePolicy.requiresCombinedPlan(grid, document, registry));
        end

        function unreviewedMemberEffectKeepsCoupledTracksUnknown(testCase)
            % unreviewedMemberEffectKeepsCoupledTracksUnknown Do not overwrite conservative shared state.
            [document, registry, grid] = testCase.fixture(["app.Grid = uigridlayout(app.UIFigure);", ...
                "app.First = uibutton(app.Grid);", "app.First.Layout = layoutValue;"]);
            result = testCase.state(document, registry, grid, "RowHeight");
            testCase.verifyFalse(result.IsKnown);
            testCase.verifyEqual(result.ReasonCode, "unreviewed-effect");
        end

        function generatedConstructorTracksSurviveOtherGeneratedSettings(testCase)
            % generatedConstructorTracksSurviveOtherGeneratedSettings Retain legacy named inputs when unrelated setters exist.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("GeneratedGridFixture", registry);
            grid = macd.model.ComponentRecord("generated-grid", "Grid", "uigridlayout", ...
                "matlab.ui.container.GridLayout", "generated");
            grid.CreationArguments = {[3 4], "RowHeight", {55}, "ColumnWidth", {65, 75}};
            grid.setProperty("Padding", [1 2 3 4]);
            document.addComponent(grid, document.RootComponentId);
            testCase.verifyEqual(testCase.state(document, registry, grid, "RowHeight").EffectiveValue, {55});
            testCase.verifyEqual(testCase.state(document, registry, grid, "ColumnWidth").EffectiveValue, {65, 75});
            source = macd.source.NewAppGenerator(registry).generate(document);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            configured = parsed.getComponentByName("Grid");
            testCase.verifyEqual(testCase.state(parsed, registry, configured, "RowHeight").EffectiveValue, {55});
            checkpoint = macd.model.SavedSourceCheckpoint(document, source, fullfile(tempdir, "GeneratedGridFixture.m"), registry);
            testCase.verifyEqual(checkpoint.SourceText, source);
            testCase.verifyFalse(document.IsDirty);
        end

        function trackComparisonRequiresTheAuditedPolicy(testCase)
            % trackComparisonRequiresTheAuditedPolicy Keep similarly named table properties in their own schema.
            ordinary = macd.model.PropertyState(macd.model.PropertyDefinition("ColumnWidth"));
            ordinary = ordinary.withEffective("fit", true);
            testCase.verifyTrue(macd.model.PropertyStateResolver.matchesRequested(ordinary, 'fit'));
            ordinary = ordinary.withEffective({100, 200}, true);
            testCase.verifyFalse(macd.model.PropertyStateResolver.matchesRequested(ordinary, [100 200]));
            definition = macd.model.PropertyDefinition("ColumnWidth", [], false, true, ...
                struct("application", struct("effectPolicy", "gridTracks")));
            audited = macd.model.PropertyState(definition).withEffective({100, 200}, true);
            testCase.verifyTrue(macd.model.PropertyStateResolver.matchesRequested(audited, [100 200]));
        end

        function creationOrderUsesTheInitializerTraceRatherThanFileOrder(testCase)
            % creationOrderUsesTheInitializerTraceRatherThanFileOrder Record creation events even without named arguments.
            body = ["createGrid(app);", "createChildren(app);", "end", "function createChildren(app)", ...
                "app.First = uibutton(app.Grid);", "app.Second = uibutton(app.Grid);", "end", ...
                "function createGrid(app)", "app.Grid = uigridlayout(app.UIFigure, [1 1]);"];
            [document, registry, grid] = testCase.fixture(body);
            first = document.getComponentByName("First");
            second = document.getComponentByName("Second");
            testCase.verifyLessThan(grid.Metadata.InitializationCreationSequence, first.Metadata.InitializationCreationSequence);
            testCase.verifyGreaterThan(grid.SourceSpans.Creation.StartOffset, first.SourceSpans.Creation.StartOffset);
            testCase.verifyEqual(testCase.state(document, registry, second, "Layout.Row").EffectiveValue, 2);
            testCase.verifyEqual(testCase.state(document, registry, grid, "RowHeight").EffectiveValue, {"1x", "1x"});
        end

        function occupiedTracksArePaddedWithoutChangingTheirSource(testCase)
            % occupiedTracksArePaddedWithoutChangingTheirSource Resolve occupancy rather than trusting the last literal.
            for axis = ["Row", "Column"]
                path = "RowHeight";
                if axis == "Column", path = "ColumnWidth"; end
                body = ["app.Grid = uigridlayout(app.UIFigure, [2 2]);", ...
                    "app.First = uibutton(app.Grid);", "app.First.Layout." + axis + " = [2 4];", ...
                    "app.Grid." + path + " = {50};"];
                [document, registry, grid] = testCase.fixture(body);
                before = grid.settingSnapshot();
                state = testCase.state(document, registry, grid, path);
                testCase.verifyTrue(state.IsKnown);
                testCase.verifyEqual(state.ExplicitValue, {50});
                testCase.verifyEqual(state.EffectiveValue, {50, "1x", "1x", "1x"});
                testCase.verifyEqual(SourceAssertions.retained(grid.settingSnapshot(), before), SourceAssertions.semantics(before));
                testCase.verifyFalse(document.IsDirty);
                testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
                testCase.verifyFalse(macd.model.PropertyStateResolver.matchesRequested(state, {50}));
            end
        end

        function movingOutReleasesImplicitTracksAndRetainsFitTokens(testCase)
            % movingOutReleasesImplicitTracksAndRetainsFitTokens Recompute padding from current occupancy.
            body = ["app.Grid = uigridlayout(app.UIFigure, RowHeight={'fit', 200}, ColumnWidth={110, 210});", ...
                "app.First = uibutton(app.Grid);", "app.First.Layout.Row = 4;", ...
                "app.First.Layout.Row = 1;"];
            [document, registry, grid] = testCase.fixture(body);
            testCase.verifyEqual(testCase.state(document, registry, grid, "RowHeight").EffectiveValue, {'fit', 200});
            body(end + 1) = "app.Grid.RowHeight = {50};";
            [document, registry, grid] = testCase.fixture(body);
            testCase.verifyEqual(testCase.state(document, registry, grid, "RowHeight").EffectiveValue, {50});
            body = [body(1:3), "app.Grid.RowHeight = {60};", "app.First.Layout.Row = 1;"];
            [document, registry, grid] = testCase.fixture(body);
            testCase.verifyEqual(testCase.state(document, registry, grid, "RowHeight").EffectiveValue, {60});
        end

        function automaticPlacementFollowsTheLastOccupiedCell(testCase)
            % automaticPlacementFollowsTheLastOccupiedCell Preserve creation order and do not fill earlier holes.
            body = ["app.Grid = uigridlayout(app.UIFigure, [2 2]);", "app.First = uibutton(app.Grid);", ...
                "app.First.Layout.Row = 2;", "app.First.Layout.Column = 2;", "app.Second = uibutton(app.Grid);", ...
                "app.Third = uibutton(app.Grid);"];
            [document, registry, grid] = testCase.fixture(body);
            second = document.getComponentByName("Second");
            third = document.getComponentByName("Third");
            testCase.verifyEqual(testCase.state(document, registry, second, "Layout.Row").EffectiveValue, 3);
            testCase.verifyEqual(testCase.state(document, registry, second, "Layout.Column").EffectiveValue, 1);
            testCase.verifyEqual(testCase.state(document, registry, third, "Layout.Row").EffectiveValue, 3);
            testCase.verifyEqual(testCase.state(document, registry, third, "Layout.Column").EffectiveValue, 2);
            testCase.verifyEqual(testCase.state(document, registry, grid, "RowHeight").EffectiveValue, {"1x", "1x", "1x"});
            testCase.verifyEmpty(second.getProperty("Layout.Row"));
            testCase.verifyLessThan(grid.Metadata.InitializationCreationSequence, second.Metadata.InitializationCreationSequence);
        end

        function positionalSizeAndConstructorTrackOverridesAreResolved(testCase)
            % positionalSizeAndConstructorTrackOverridesAreResolved Distinguish positional shape from later named setters.
            body = "app.Grid = uigridlayout(app.UIFigure, [3 4], RowHeight={55}, ColumnWidth=[65 75]);";
            [document, registry, grid] = testCase.fixture(body);
            testCase.verifyEqual(testCase.state(document, registry, grid, "RowHeight").EffectiveValue, {55});
            state = testCase.state(document, registry, grid, "ColumnWidth");
            testCase.verifyEqual(state.EffectiveValue, {65, 75});
            testCase.verifyTrue(macd.model.PropertyStateResolver.matchesRequested(state, [65 75]));
            body = "app.Grid = uigridlayout(app.UIFigure, [3 4]);";
            [document, registry, grid] = testCase.fixture(body);
            testCase.verifyNumElements(testCase.state(document, registry, grid, "RowHeight").EffectiveValue, 3);
            testCase.verifyNumElements(testCase.state(document, registry, grid, "ColumnWidth").EffectiveValue, 4);
        end

        function uncertainPlacementInvalidatesOnlyAffectedTracks(testCase)
            % uncertainPlacementInvalidatesOnlyAffectedTracks Do not replace unknown expressions with earlier literals.
            body = ["app.Grid = uigridlayout(app.UIFigure, RowHeight={100}, ColumnWidth={200});", ...
                "app.First = uibutton(app.Grid);", "app.First.Layout.Row = 1 + 0;"];
            [document, registry, grid] = testCase.fixture(body);
            first = document.getComponentByName("First");
            testCase.verifyFalse(testCase.state(document, registry, grid, "RowHeight").IsKnown);
            testCase.verifyEqual(testCase.state(document, registry, grid, "RowHeight").ReasonCode, "grid-layout");
            testCase.verifyTrue(testCase.state(document, registry, grid, "ColumnWidth").IsKnown);
            testCase.verifyFalse(testCase.state(document, registry, first, "Layout.Row").IsKnown);
            body(end + 1) = "app.First.Layout.Row = 1;";
            [document, registry, grid] = testCase.fixture(body);
            testCase.verifyEqual(testCase.state(document, registry, grid, "RowHeight").EffectiveValue, {100});
        end

        function editsLostToOccupancyAreRejectedAtomically(testCase)
            % editsLostToOccupancyAreRejectedAtomically Keep the original setter and user history intact on failure.
            body = ["app.Grid = uigridlayout(app.UIFigure);", "app.Grid.RowHeight = {100, 200};", ...
                "app.First = uibutton(app.Grid);", "app.First.Layout.Row = 2;"];
            [document, registry, grid] = testCase.fixture(body);
            before = grid.settingSnapshot();
            testCase.verifyError(@() document.setProperty(grid.Id, "RowHeight", {50}, registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(SourceAssertions.retained(grid.settingSnapshot(), before), SourceAssertions.semantics(before));
            testCase.verifyEqual(grid.getProperty("RowHeight").LiteralValue, {100, 200});
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyFalse(document.IsDirty);
            document.setProperty(grid.Id, "RowHeight", {50, 60}, registry);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifyTrue(contains(source, "app.Grid.RowHeight = {50, 60};"));
            testCase.verifyEqual(grid.getSettings("RowHeight").Id, before(1).Location.SourceSnapshotId + ...
                ":" + string(before(1).Location.ValueSpan.StartOffset) + ":RowHeight");
            document.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            document.redo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
        end

        function newTrackSettingsUseVerifiedStyleAndRejectImpossibleSizes(testCase)
            % newTrackSettingsUseVerifiedStyleAndRejectImpossibleSizes Share candidate insertion with final grid-state checks.
            bodies = {"app.Grid = uigridlayout(app.UIFigure, ColumnWidth={100});", ...
                ["app.Grid = uigridlayout(app.UIFigure);", "app.Grid.ColumnWidth = {100};"], ...
                ["app.Grid = uigridlayout(app.UIFigure, ColumnWidth={100});", "app.Grid.Padding = [1 2 3 4];"]};
            for index = 1:numel(bodies)
                [document, registry, grid] = testCase.fixture(bodies{index});
                document.setProperty(grid.Id, "RowHeight", {50}, registry);
                source = macd.source.RoundTripGenerator(registry).generate(document);
                parsed = macd.source.AppSourceParser.parseText(source, registry);
                configured = parsed.getComponentByName("Grid");
                method = "assignment";
                if index == 1, method = "nameValue"; end
                testCase.verifyEqual(configured.getSettings("RowHeight").Method, method);
                testCase.verifyEqual(testCase.state(document, registry, grid, "RowHeight").EffectiveValue, {50});
            end
            body = ["app.Grid = uigridlayout(app.UIFigure, ColumnWidth={100});", ...
                "app.First = uibutton(app.Grid);", "app.First.Layout.Row = 2;"];
            [document, registry, grid] = testCase.fixture(body);
            testCase.verifyError(@() document.setProperty(grid.Id, "RowHeight", {50}, registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEmpty(grid.getProperty("RowHeight"));
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyFalse(document.IsDirty);
        end

        function pendingChildPlacementUsesItsActualInsertionBeforeLaterChildren(testCase)
            % pendingChildPlacementUsesItsActualInsertionBeforeLaterChildren Resolve siblings through the same candidate source.
            body = ["app.Grid = uigridlayout(app.UIFigure, [2 2]);", ...
                "app.First = uibutton(app.Grid);", "app.Second = uibutton(app.Grid);"];
            [document, registry, grid] = testCase.fixture(body);
            first = document.getComponentByName("First");
            second = document.getComponentByName("Second");
            document.setProperty(first.Id, "Layout.Row", 3, registry);
            testCase.verifyEqual(testCase.state(document, registry, second, "Layout.Row").EffectiveValue, 3);
            testCase.verifyEqual(testCase.state(document, registry, second, "Layout.Column").EffectiveValue, 2);
            testCase.verifyNumElements(testCase.state(document, registry, grid, "RowHeight").EffectiveValue, 3);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(testCase.state(document, registry, second, "Layout.Row").EffectiveValue, ...
                testCase.state(parsed, registry, parsed.getComponentByName("Second"), "Layout.Row").EffectiveValue);
        end

        function generatedChildrenFollowTheGeneratorsCreationAnchor(testCase)
            % generatedChildrenFollowTheGeneratorsCreationAnchor Keep new creation before trailing original setters.
            body = ["app.Grid = uigridlayout(app.UIFigure, [2 2]);", ...
                "app.First = uibutton(app.Grid);", "app.Second = uibutton(app.Grid);", "app.First.Layout.Row = 4;"];
            [document, registry, grid] = testCase.fixture(body);
            third = macd.model.ComponentRecord("new-fourth", "Fourth", "uibutton", "matlab.ui.control.Button", "generated");
            document.addComponent(third, grid.Id);
            state = testCase.state(document, registry, third, "Layout.Row");
            testCase.verifyTrue(state.IsKnown);
            testCase.verifyEqual(state.EffectiveValue, 2);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(testCase.state(parsed, registry, parsed.getComponentByName("Fourth"), "Layout.Row").EffectiveValue, 2);
        end

        function gridBatchChecksCombinedPlacementsBeforeMutation(testCase)
            % gridBatchChecksCombinedPlacementsBeforeMutation Reject a lost shrink and accept a single atomic move-and-shrink.
            body = ["app.Grid = uigridlayout(app.UIFigure);", "app.Grid.RowHeight = {100, 200};", ...
                "app.First = uibutton(app.Grid);", "app.First.Layout.Row = 2;"];
            [document, registry, grid] = testCase.fixture(body);
            first = document.getComponentByName("First");
            changes = struct("ComponentId", grid.Id, "Path", "RowHeight", "Value", {{50}});
            testCase.verifyError(@() document.applyGridLayoutEdit(grid.Id, changes, registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(document.HistoryIndex, 0);
            changes(end + 1) = struct("ComponentId", first.Id, "Path", "Layout.Row", "Value", 1);
            document.applyGridLayoutEdit(grid.Id, changes, registry);
            testCase.verifyEqual(testCase.state(document, registry, grid, "RowHeight").EffectiveValue, {50});
            testCase.verifyEqual(document.HistoryIndex, 1);
            document.undo();
            testCase.verifyEqual(first.getProperty("Layout.Row").LiteralValue, 2);
            testCase.verifyEqual(grid.getProperty("RowHeight").LiteralValue, {100, 200});
            document.redo();
            testCase.verifyEqual(testCase.state(document, registry, grid, "RowHeight").EffectiveValue, {50});
        end

        function pendingSettingsUseCombinedSource(testCase)
            % pendingSettingsUseCombinedSource Resolve complete emitted initialization without changing source ownership.
            body = ["app.Grid = uigridlayout(app.UIFigure, ColumnWidth={100});", "app.First = uibutton(app.Grid);"];
            [document, registry, grid] = testCase.fixture(body);
            first = document.getComponentByName("First");
            changes = [struct("ComponentId", grid.Id, "Path", "RowHeight", "Value", {{50, 60}}), ...
                struct("ComponentId", first.Id, "Path", "Layout.Row", "Value", 2)];
            document.applyGridLayoutEdit(grid.Id, changes, registry);
            testCase.verifyEqual(document.HistoryIndex, 1);
            state = testCase.state(document, registry, grid, "RowHeight");
            testCase.verifyTrue(state.IsKnown);
            testCase.verifyEqual(state.EffectiveValue, {50, 60});
            testCase.verifyEqual(state.RequestedValue, {50, 60});
            testCase.verifyEqual(state.ExplicitKind, "literal");
            testCase.verifyFalse(isfield(document.Metadata, "ResolvingCombinedPropertySource"));
            source = macd.source.RoundTripGenerator(registry).generate(document);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(testCase.state(parsed, registry, parsed.getComponentByName("Grid"), "RowHeight").EffectiveValue, {50, 60});
            checkpoint = macd.model.SavedSourceCheckpoint(document, source, fullfile(tempdir, "GridStateFixture.m"), registry);
            testCase.verifyEqual(checkpoint.SourceText, source);
            document.undo();
            testCase.verifyEmpty(grid.getProperty("RowHeight"));
            testCase.verifyEmpty(first.getProperty("Layout.Row"));
        end

        function copyFreezesImplicitPlacementsAndPaddedTracks(testCase)
            % copyFreezesImplicitPlacementsAndPaddedTracks Reproduce effective layout without changing the original occurrences.
            body = ["app.Grid = uigridlayout(app.UIFigure, RowHeight={100}, ColumnWidth={100});", ...
                "app.First = uibutton(app.Grid);", "app.Second = uibutton(app.Grid);"];
            [document, registry, grid] = testCase.fixture(body);
            before = grid.settingSnapshot();
            snapshot = document.copySubtree(grid.Id, registry);
            configuration = snapshot.CopyConfiguration;
            first = configuration(string({configuration.ComponentId}) == "parsed-First");
            testCase.verifyEqual(first.Properties(string({first.Properties.Path}) == "Layout.Row").LiteralValue, 1);
            copied = document.pasteSubtree(snapshot, document.RootComponentId, registry);
            testCase.verifyEqual(testCase.state(document, registry, copied, "RowHeight").EffectiveValue, {100, "1x"});
            testCase.verifyEqual(SourceAssertions.retained(grid.settingSnapshot(), before), SourceAssertions.semantics(before));
            testCase.verifyEqual(document.HistoryIndex, 1);
        end
    end

    methods (Test, TestTags = {'ui', 'model', 'preview'})
        function copyAndPreviewShareCombinedPendingGridState(testCase)
            % copyAndPreviewShareCombinedPendingGridState Preserve user edits across copy, native projection, and overlay data.
            body = ["app.Grid = uigridlayout(app.UIFigure, ColumnWidth={100});", "app.First = uibutton(app.Grid);"];
            [document, registry, grid] = testCase.fixture(body);
            first = document.getComponentByName("First");
            changes = [struct("ComponentId", grid.Id, "Path", "RowHeight", "Value", {{50, 60}}), ...
                struct("ComponentId", first.Id, "Path", "Layout.Row", "Value", 2)];
            document.applyGridLayoutEdit(grid.Id, changes, registry);
            before = grid.settingSnapshot();
            snapshot = document.copySubtree(grid.Id, registry);
            configuration = snapshot.CopyConfiguration;
            copiedGrid = configuration(string({configuration.ComponentId}) == grid.Id);
            copiedChild = configuration(string({configuration.ComponentId}) == first.Id);
            testCase.verifyEqual(copiedGrid.Properties(string({copiedGrid.Properties.Path}) == "RowHeight").LiteralValue, {50, 60});
            testCase.verifyEqual(copiedChild.Properties(string({copiedChild.Properties.Path}) == "Layout.Row").LiteralValue, 2);
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            [handles, diagnostics] = macd.ui.PreviewRenderer(registry).render(document, figure);
            drawnow;
            testCase.verifyEmpty(diagnostics);
            testCase.verifyEqual(handles(char(first.Id)).Layout.Row, 2);
            testCase.verifyTrue(macd.model.GridLayoutStatePolicy.equivalent(handles(char(grid.Id)).RowHeight, {50, 60}));
            overlay = macd.ui.GridLayoutOverlayDataBuilder().build(document, handles, figure, grid.Id, first.Id, 1, registry);
            testCase.verifyNumElements(overlay.rowTracks, 2);
            testCase.verifyEqual([overlay.rowTracks.value], [50 60]);
            testCase.verifyEqual(SourceAssertions.retained(grid.settingSnapshot(), before), SourceAssertions.semantics(before));
            testCase.verifyEqual(document.HistoryIndex, 1);
        end

        function nativeGettersAgreeWithOwnedSourceFixtures(testCase)
            % nativeGettersAgreeWithOwnedSourceFixtures Compare known grid effects with native R2024a objects.
            fixtureBodies = {["app.Grid = uigridlayout(app.UIFigure, [2 2]);", ...
                "app.First = uibutton(app.Grid);", "app.First.Layout.Row = [2 4];", "app.Grid.RowHeight = {50};"], ...
                ["app.Grid = uigridlayout(app.UIFigure, [2 2]);", "app.First = uibutton(app.Grid);", ...
                "app.First.Layout.Row = 2;", "app.First.Layout.Column = 2;", ...
                "app.Second = uibutton(app.Grid);", "app.Third = uibutton(app.Grid);"], ...
                ["app.Grid = uigridlayout(app.UIFigure, RowHeight={100, 200}, ColumnWidth={110, 210});", ...
                "app.First = uibutton(app.Grid);", "app.First.Layout.Row = 4;", ...
                "app.Grid.RowHeight = {50};", "app.First.Layout.Row = 1;"]};
            for fixtureBody = fixtureBodies
                [document, registry, grid] = testCase.fixture(fixtureBody{1});
                figure = uifigure("Visible", "off");
                cleanup = onCleanup(@() delete(figure));
                % Execute only this test's literal fixture, never opened application source.
                app = struct("UIFigure", figure);
                for line = fixtureBody{1}, eval(line); end
                for path = ["RowHeight", "ColumnWidth"]
                    testCase.verifyTrue(macd.model.GridLayoutStatePolicy.equivalent( ...
                        testCase.state(document, registry, grid, path).EffectiveValue, app.Grid.(path)));
                end
                for childId = grid.Children
                    child = document.getComponent(childId);
                    for axis = ["Row", "Column"]
                        testCase.verifyEqual(testCase.state(document, registry, child, "Layout." + axis).EffectiveValue, ...
                            app.(child.Name).Layout.(axis));
                    end
                end
                clear cleanup
            end
        end

        function previewProjectsEffectiveLayoutWithoutAddingSettings(testCase)
            % previewProjectsEffectiveLayoutWithoutAddingSettings Render implicit child positions from the shared resolver.
            body = ["app.Grid = uigridlayout(app.UIFigure, RowHeight={100, 200}, ColumnWidth={100, 200});", "app.First = uibutton(app.Grid);", ...
                "app.First.Layout.Row = 2;", "app.First.Layout.Column = 2;", "app.Second = uibutton(app.Grid);"];
            [document, registry, grid] = testCase.fixture(body);
            second = document.getComponentByName("Second");
            before = second.settingSnapshot();
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            renderer = macd.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, figure);
            drawnow;
            testCase.verifyEmpty(diagnostics);
            testCase.verifyEqual(handles(char(second.Id)).Layout.Row, 3);
            testCase.verifyEqual(handles(char(second.Id)).Layout.Column, 1);
            testCase.verifyTrue(macd.model.GridLayoutStatePolicy.equivalent(handles(char(grid.Id)).RowHeight, {100, 200, "1x"}));
            overlay = macd.ui.GridLayoutOverlayDataBuilder().build(document, handles, figure, grid.Id, second.Id, 1, registry);
            testCase.verifyNumElements(overlay.rowTracks, 3);
            testCase.verifyEqual(string({overlay.rowTracks.kind}), ["fixed", "fixed", "flexible"]);
            testCase.verifyEqual(second.settingSnapshot(), before);
            testCase.verifyEmpty(second.getProperty("Layout.Row"));
        end
    end

    methods (Static, Access = private)
        function replaceButtonProperty(registry, property)
            % replaceButtonProperty Change one immutable policy while preserving the component variant.
            arguments (Input)
                registry (1, 1) macd.model.ComponentRegistry
                property (1, 1) macd.model.PropertyDefinition
            end
            original = registry.get("uibutton");
            definitions = original.Properties;
            definitions(string({definitions.Path}) == property.Path) = property;
            replacement = macd.model.ComponentDefinition(original.Factory, original.DeclaredType, ...
                original.AllowedParentFactories, original.IsRoot, original.CreationArguments, definitions, ...
                original.DisplayName, original.Category, original.IsProgrammaticOnly, original.RequiresParentComponent, ...
                original.SupportedStyles, original.DefaultStyle, original.DeclaredTypesByStyle, ...
                original.OverlayShape, original.OverlayShapesByStyle, original.ResizeConstraint, ...
                original.ResizeConstraintsByStyle, original.DefaultSize, original.Metadata);
            registry.register(replacement);
        end

        function [document, registry, grid] = fixture(body)
            % fixture Parse a literal owned handle-based initializer with up to three controls.
            arguments (Input)
                body string
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                grid (1, 1) macd.model.ComponentRecord
            end
            registry = macd.model.ComponentRegistry.createDefault();
            source = strjoin(["classdef GridStateFixture < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Grid matlab.ui.container.GridLayout", ...
                "First matlab.ui.control.Button", "Second matlab.ui.control.Button", "Third matlab.ui.control.Button", ...
                "end", "methods", "function app = GridStateFixture", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", body, "end", "end", "end"], sprintf('\r\n'));
            document = macd.source.AppSourceParser.parseText(source, registry);
            grid = document.getComponentByName("Grid");
        end

        function resolution = state(document, registry, component, path)
            % state Select one shared effective state from the document projection.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                component (1, 1) macd.model.ComponentRecord
                path (1, 1) string
            end
            arguments (Output)
                resolution (1, 1) macd.model.PropertyState
            end
            states = document.getEffectivePropertyStates(registry, component.Id);
            index = find(arrayfun(@(state) state.Definition.Path == path, states), 1);
            resolution = states(index).Resolution;
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

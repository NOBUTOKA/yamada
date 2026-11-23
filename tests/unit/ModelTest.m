classdef (TestTags = {'fast', 'gridOverlay', 'model'}) ModelTest < matlab.unittest.TestCase
    % ModelTest Verify the shared intermediate model and registry contracts.
    %   This test class covers model editing, generic property paths, registry
    %   extensibility, and conservative storage of source expressions. It does not
    %   exercise MATLAB source parsing or live UI components.

    methods (Test)

        % Guarantee: palette insertion creates the selected variant with valid initial geometry.
        % Failure mode: insertion falls back to the default style or size, or places a grid child without coordinates.
        function registryInsertionSeedsSafeGeometry(testCase)
            % registryInsertionSeedsSafeGeometry Verify model-owned palette insertion.

            % Insert two controls through the same registry used by the editor.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            first = document.insertComponent(registry, "uilabel", ...
                document.RootComponentId);
            second = document.insertComponent(registry, "uibutton", ...
                document.RootComponentId);

            testCase.verifyEqual(first.Name, "Label");
            testCase.verifyEqual(second.Name, "Button");
            testCase.verifyEqual(first.ParentId, document.RootComponentId);
            testCase.verifyEqual(first.getProperty("Position").LiteralValue, ...
                [20 20 100 30]);
            testCase.verifyEqual(second.getProperty("Position").LiteralValue, ...
                [40 40 100 30]);
            testCase.verifyTrue(document.canUndo());
            testCase.verifyFalse(document.canRedo());
        end

        function insertionPreservesSelectedComponentVariant(testCase)
            % insertionPreservesSelectedComponentVariant Create a non-default catalog style.

            % Pass the selected style arguments through the model insertion boundary.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("VariantApp", registry);
            variant = registry.getById("uibutton-state");
            component = document.insertComponent(registry, variant.Factory, ...
                document.RootComponentId, variant.CreationArguments);
            testCase.verifyEqual(component.CreationArguments, variant.CreationArguments);
            testCase.verifyEqual(component.DeclaredType, "matlab.ui.control.StateButton");
        end

        function insertionUsesVariantDefaultSize(testCase)
            % insertionUsesVariantDefaultSize Preserve a style-specific initial size.

            % Keep vertical switch variants at their documented MATLAB dimensions.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("SwitchApp", registry);
            variant = registry.getById("uiswitch-rocker");
            component = document.insertComponent(registry, variant.Factory, ...
                document.RootComponentId, variant.CreationArguments);
            testCase.verifyEqual(component.getProperty("Position").LiteralValue, ...
                [20 20 variant.DefaultSize]);
        end

        function gridInsertionSeedsLayoutCoordinates(testCase)
            % gridInsertionSeedsLayoutCoordinates Verify grid insertion defaults.

            % Build a grid parent and insert a label beneath it.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("GridApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", ...
                document.RootComponentId);
            label = document.insertComponent(registry, "uilabel", grid.Id);

            testCase.verifyEqual(label.getProperty("Layout.Row").LiteralValue, 1);
            testCase.verifyEqual(label.getProperty("Layout.Column").LiteralValue, 1);
            testCase.verifyError(@() document.insertComponent( ...
                registry, "uilabel", label.Id), ...
                "yamada:DocumentModel:InvalidInsertionParent");
        end

        % Guarantee: property edits and resets are reversible units, and rejected batches change nothing.
        % Failure mode: a batch is undone in several steps, or a reset deletes a parsed assignment that yamada does not own.
        function propertyEditsUndoAndRedo(testCase)
            % propertyEditsUndoAndRedo Verify reversible literal property changes.

            % Change one model value, then traverse both history directions.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            label = document.insertComponent(registry, "uilabel", ...
                document.RootComponentId);
            document.setProperty(label.Id, "Position", [30 40 120 30]);
            testCase.verifyEqual(label.getProperty("Position").LiteralValue, ...
                [30 40 120 30]);
            document.undo();
            testCase.verifyEqual(label.getProperty("Position").LiteralValue, ...
                [20 20 100 30]);
            document.redo();
            testCase.verifyEqual(label.getProperty("Position").LiteralValue, ...
                [30 40 120 30]);
        end

        function propertyBatchesAreAtomicAndUndoAsOneEdit(testCase)
            % propertyBatchesAreAtomicAndUndoAsOneEdit Verify one reversible multi-property mutation.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            label = document.insertComponent(registry, "uilabel", ...
                document.RootComponentId);
            initialHistoryCount = numel(document.History);
            changes = [struct("Path", "Text", "Value", "Ready"), ...
                struct("Path", "Position", "Value", [30 40 120 30])];

            document.setPropertyBatch(label.Id, changes);
            testCase.verifyEqual(numel(document.History), initialHistoryCount + 1);
            testCase.verifyEqual(label.getProperty("Text").LiteralValue, "Ready");
            testCase.verifyEqual(label.getProperty("Position").LiteralValue, [30 40 120 30]);
            document.undo();
            testCase.verifyEmpty(label.getProperty("Text"));
            testCase.verifyEqual(label.getProperty("Position").LiteralValue, [20 20 100 30]);
            document.redo();
            testCase.verifyEqual(label.getProperty("Text").LiteralValue, "Ready");
            testCase.verifyEqual(label.getProperty("Position").LiteralValue, [30 40 120 30]);
        end

        function propertyBatchPreflightLeavesValuesUntouched(testCase)
            % propertyBatchPreflightLeavesValuesUntouched Reject duplicate paths before mutation.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            label = document.insertComponent(registry, "uilabel", ...
                document.RootComponentId);
            changes = [struct("Path", "Text", "Value", "First"), ...
                struct("Path", "Text", "Value", "Second")];

            testCase.verifyError(@() document.setPropertyBatch(label.Id, changes), ...
                "yamada:DocumentModel:InvalidPropertyBatch");
            testCase.verifyEmpty(label.getProperty("Text"));
        end

        % Guarantee: Undo of insertion or deletion restores the exact pending intention.
        % Failure mode: undoing an insertion records a deletion of parsed source, or undoing a deletion loses it.
        function insertionUndoRemovesWithoutDeletionIntent(testCase)
            % insertionUndoRemovesWithoutDeletionIntent Verify generated undo semantics.

            % Undoing a new component must not create a source deletion request.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            label = document.insertComponent(registry, "uilabel", ...
                document.RootComponentId);
            document.undo();
            testCase.verifyEmpty(document.getComponent(label.Id));
            testCase.verifyEmpty(document.PendingEdits);
            document.redo();
            testCase.verifyEqual(document.getComponent(label.Id).Name, "Label");
        end

        % Guarantee: model validation applies the same schema as the Inspector to values set by any route.
        % Failure mode: values set outside the Inspector, such as by parsing, skip validation and fail in Preview.
        function geometryValidationRejectsUnsafeLiterals(testCase)
            % geometryValidationRejectsUnsafeLiterals Verify canvas geometry checks.

            % Negative size and invalid grid coordinates must block generation safely.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            label = document.insertComponent(registry, "uilabel", ...
                document.RootComponentId);
            grid = document.insertComponent(registry, "uigridlayout", ...
                document.RootComponentId);
            gridLabel = document.insertComponent(registry, "uilabel", grid.Id);
            label.setProperty("Position", [10 10 -1 30]);
            gridLabel.setProperty("Layout.Row", [0 2]);
            diagnostics = yamada.validation.ModelValidator.validate(document, registry);

            testCase.verifyTrue(any([diagnostics.Code] == "invalid-position"));
            testCase.verifyTrue(any([diagnostics.Code] == "invalid-grid-coordinate"));
            testCase.verifyTrue(yamada.validation.ModelValidator.hasErrors(diagnostics));
        end

        function geometryValidationAcceptsGridSpans(testCase)
            % geometryValidationAcceptsGridSpans Accept positive integer grid ranges.

            % Grid row and column values may span two adjacent tracks.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", ...
                document.RootComponentId);
            label = document.insertComponent(registry, "uilabel", grid.Id);
            label.setProperty("Layout.Row", [1 2]);
            label.setProperty("Layout.Column", [1 2]);
            diagnostics = yamada.validation.ModelValidator.validate(document, registry);

            % The context schema and geometry check must agree on valid spans.
            diagnosticCodes = string({diagnostics.Code});
            testCase.verifyFalse(any(diagnosticCodes == "invalid-catalog-property"));
            testCase.verifyFalse(any(diagnosticCodes == "invalid-grid-coordinate"));
            testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(diagnostics));
        end

        function geometryValidationRejectsInvalidGridTrackLists(testCase)
            % geometryValidationRejectsInvalidGridTrackLists Reject literals the public GridLayout setter rejects.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            grid.setProperty("RowHeight", {'auto'});

            diagnostics = yamada.validation.ModelValidator.validate(document, registry);

            testCase.verifyTrue(any([diagnostics.Code] == "invalid-grid-track-list"));
            testCase.verifyTrue(yamada.validation.ModelValidator.hasErrors(diagnostics));
        end

        % Guarantee: grid edits remap children deterministically in one atomic step.
        % Failure mode: inserting a track leaves children in the wrong cell, or a read-only child causes a partial edit.
        function gridLayoutEditsAreAtomicAndUndoable(testCase)
            % gridLayoutEditsAreAtomicAndUndoable Keep track and direct-child changes in one history step.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            nestedGrid = document.insertComponent(registry, "uigridlayout", grid.Id);
            label = document.insertComponent(registry, "uilabel", grid.Id);
            document.markSaved();
            changes = struct( ...
                "ComponentId", {grid.Id, grid.Id, nestedGrid.Id, nestedGrid.Id, label.Id, label.Id}, ...
                "Path", {"RowHeight", "ColumnWidth", "Layout.Row", "Layout.Column", ...
                "Layout.Row", "Layout.Column"}, ...
                "Value", {{'fit', 80}, {'1x', '2x'}, 2, [1 2], [1 2], 2});

            document.applyGridLayoutEdit(grid.Id, changes);

            testCase.verifyEqual(grid.getProperty("RowHeight").LiteralValue, {'fit', 80});
            testCase.verifyEqual(grid.getProperty("ColumnWidth").LiteralValue, {'1x', '2x'});
            testCase.verifyEqual(nestedGrid.getProperty("Layout.Row").LiteralValue, 2);
            testCase.verifyEqual(nestedGrid.getProperty("Layout.Column").LiteralValue, [1 2]);
            testCase.verifyTrue(document.IsDirty);
            document.undo();
            testCase.verifyEmpty(grid.getProperty("RowHeight"));
            testCase.verifyEmpty(grid.getProperty("ColumnWidth"));
            testCase.verifyEqual(nestedGrid.getProperty("Layout.Row").LiteralValue, 1);
            testCase.verifyEqual(nestedGrid.getProperty("Layout.Column").LiteralValue, 1);
            testCase.verifyEqual(label.getProperty("Layout.Row").LiteralValue, 1);
            testCase.verifyEqual(label.getProperty("Layout.Column").LiteralValue, 1);
            testCase.verifyFalse(document.IsDirty);
            document.redo();
            testCase.verifyEqual(label.getProperty("Layout.Row").LiteralValue, [1 2]);
            testCase.verifyEqual(label.getProperty("Layout.Column").LiteralValue, 2);
        end

        function gridLayoutEditsRejectReadOnlyTargetsBeforeMutation(testCase)
            % gridLayoutEditsRejectReadOnlyTargetsBeforeMutation Avoid partial changes around source expressions.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            label = document.insertComponent(registry, "uilabel", grid.Id);
            readOnly = label.getProperty("Layout.Row");
            readOnly.setSourceExpression("currentRow");
            historyIndex = document.HistoryIndex;
            changes = struct( ...
                "ComponentId", {grid.Id, label.Id}, ...
                "Path", {"RowHeight", "Layout.Row"}, ...
                "Value", {{'fit', 80}, 2});

            testCase.verifyError(@() document.applyGridLayoutEdit(grid.Id, changes), ...
                "yamada:DocumentModel:ReadOnlyProperty");
            testCase.verifyEmpty(grid.getProperty("RowHeight"));
            testCase.verifyEqual(label.getProperty("Layout.Row").SourceExpression, "currentRow");
            testCase.verifyEqual(document.HistoryIndex, historyIndex);
        end

        function gridStructuralPlannerRemapsExplicitChildrenDeterministically(testCase)
            % gridStructuralPlannerRemapsExplicitChildrenDeterministically Plan safe insert and delete effects.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            first = document.insertComponent(registry, "uilabel", grid.Id);
            second = document.insertComponent(registry, "uilabel", grid.Id);
            document.setProperty(first.Id, "Layout.Row", [1 2]);
            document.setProperty(second.Id, "Layout.Row", 3);

            changes = yamada.model.GridLayoutStructuralEditPlanner.insert( ...
                document, grid.Id, "row", 2, [20 30 40]);
            document.applyGridLayoutEdit(grid.Id, changes);
            testCase.verifyEqual(grid.getProperty("RowHeight").LiteralValue, ...
                {20, "1x", 30, 40});
            testCase.verifyEqual(first.getProperty("Layout.Row").LiteralValue, [1 3]);
            testCase.verifyEqual(second.getProperty("Layout.Row").LiteralValue, 4);
            document.undo();
            changes = yamada.model.GridLayoutStructuralEditPlanner.delete( ...
                document, grid.Id, "row", 2, [20 30 40]);
            document.applyGridLayoutEdit(grid.Id, changes);
            testCase.verifyEqual(grid.getProperty("RowHeight").LiteralValue, [20 40]);
            testCase.verifyEqual(first.getProperty("Layout.Row").LiteralValue, 1);
            testCase.verifyEqual(second.getProperty("Layout.Row").LiteralValue, 2);
        end

        function gridChildPlacementPlannerPreservesSpanAndAllowsOverlap(testCase)
            % gridChildPlacementPlannerPreservesSpanAndAllowsOverlap Allow overlap while validating grid bounds.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            document.setProperty(grid.Id, "RowHeight", {"1x", "1x", "1x", "1x"});
            document.setProperty(grid.Id, "ColumnWidth", {"1x", "1x", "1x", "1x"});
            moving = document.insertComponent(registry, "uilabel", grid.Id);
            occupied = document.insertComponent(registry, "uilabel", grid.Id);
            document.setProperty(moving.Id, "Layout.Row", [1 2]);
            document.setProperty(moving.Id, "Layout.Column", [1 2]);
            document.setProperty(occupied.Id, "Layout.Row", 4);
            document.setProperty(occupied.Id, "Layout.Column", 4);

            changes = yamada.model.GridChildPlacementPlanner.move( ...
                document, grid.Id, moving.Id, 2, 2, 4, 4);
            document.applyGridLayoutEdit(grid.Id, changes);
            testCase.verifyEqual(moving.getProperty("Layout.Row").LiteralValue, [2 3]);
            testCase.verifyEqual(moving.getProperty("Layout.Column").LiteralValue, [2 3]);
            changes = yamada.model.GridChildPlacementPlanner.move( ...
                document, grid.Id, moving.Id, 3, 3, 4, 4);
            document.applyGridLayoutEdit(grid.Id, changes);
            testCase.verifyEqual(moving.getProperty("Layout.Row").LiteralValue, [3 4]);
            testCase.verifyEqual(moving.getProperty("Layout.Column").LiteralValue, [3 4]);
            changes = yamada.model.GridChildPlacementPlanner.resize( ...
                document, grid.Id, moving.Id, 1, 3, 1, 3, 4, 4);
            document.applyGridLayoutEdit(grid.Id, changes);
            testCase.verifyEqual(moving.getProperty("Layout.Row").LiteralValue, [1 3]);
            testCase.verifyEqual(moving.getProperty("Layout.Column").LiteralValue, [1 3]);
            changes = yamada.model.GridChildPlacementPlanner.resize( ...
                document, grid.Id, moving.Id, 1, 4, 1, 4, 4, 4);
            document.applyGridLayoutEdit(grid.Id, changes);
            testCase.verifyEqual(moving.getProperty("Layout.Row").LiteralValue, [1 4]);
            testCase.verifyEqual(moving.getProperty("Layout.Column").LiteralValue, [1 4]);
            testCase.verifyEqual(occupied.getProperty("Layout.Row").LiteralValue, 4);
            testCase.verifyEqual(occupied.getProperty("Layout.Column").LiteralValue, 4);

            % Overlap remains valid source while invalid coordinates remain rejected.
            generator = yamada.source.RoundTripGenerator(registry);
            [~, diagnostics] = generator.generate(document);
            testCase.verifyEmpty(diagnostics);
            testCase.verifyError(@() yamada.model.GridChildPlacementPlanner.move( ...
                document, grid.Id, moving.Id, 2, 1, 4, 4), ...
                "yamada:GridChildPlacementPlanner:OutOfBounds");
            testCase.verifyError(@() yamada.model.GridChildPlacementPlanner.resize( ...
                document, grid.Id, moving.Id, 1, 5, 1, 4, 4, 4), ...
                "yamada:GridChildPlacementPlanner:OutOfBounds");
            testCase.verifyError(@() yamada.model.GridChildPlacementPlanner.resize( ...
                document, grid.Id, moving.Id, NaN, 4, 1, 4, 4, 4), ...
                "yamada:GridChildPlacementPlanner:InvalidTarget");
        end

        function modelValidationUsesTheInspectorPropertySchema(testCase)
            % modelValidationUsesTheInspectorPropertySchema Reject catalog-invalid values outside the Inspector.
            % Guarantee and failure mode: shared with geometryValidationRejectsUnsafeLiterals.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            definition = registry.get("uidatepicker");
            picker = yamada.model.ComponentRecord("picker", "Picker", "uidatepicker", definition.DeclaredType);
            document.addComponent(picker, document.RootComponentId);
            picker.setProperty("Limits", [datetime(2024, 12, 31) datetime(2024, 1, 1)]);

            diagnostics = yamada.validation.ModelValidator.validate(document, registry);

            invalid = diagnostics([diagnostics.Code] == "invalid-catalog-property");
            testCase.verifyNotEmpty(invalid);
            testCase.verifyEqual(invalid(1).ComponentId, picker.Id);
        end

        % Guarantee: effective properties depend on the direct parent and never create entries.
        % Failure mode: a child of a nested grid uses the outer grid's context, or reading state materializes defaults.
        function effectivePropertiesFollowDirectParentContext(testCase)
            % effectivePropertiesFollowDirectParentContext Verify geometry follows the direct parent.

            % Compare the resolved surface without exposing registry implementation state.
            registry = yamada.model.ComponentRegistry.createDefault();
            gridPaths = string({registry.getEffectiveProperties("uilabel", "uigridlayout").Path});
            absolutePaths = string({registry.getEffectiveProperties("uilabel", "uifigure").Path});
            tabPaths = string({registry.getEffectiveProperties("uitab", "uitabgroup").Path});
            testCase.verifyTrue(all(ismember(["Layout.Row", "Layout.Column"], gridPaths)));
            testCase.verifyFalse(any(gridPaths == "Position"));
            testCase.verifyTrue(any(absolutePaths == "Position"));
            testCase.verifyFalse(any(absolutePaths == "Layout.Row"));
            testCase.verifyFalse(any(tabPaths == "Position"));
            testCase.verifyFalse(any(tabPaths == "Layout.Row"));
        end

        function activeGridResolutionKeepsNestedGridContextsSeparate(testCase)
            % activeGridResolutionKeepsNestedGridContextsSeparate Resolve only the nearest Grid Layout.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            outer = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            inner = document.insertComponent(registry, "uigridlayout", outer.Id);
            label = document.insertComponent(registry, "uilabel", inner.Id);

            testCase.verifyEqual(yamada.model.ActiveGridResolver.resolve(document, outer.Id), outer.Id);
            testCase.verifyEqual(yamada.model.ActiveGridResolver.resolve(document, inner.Id), inner.Id);
            testCase.verifyEqual(yamada.model.ActiveGridResolver.resolve(document, label.Id), inner.Id);
            testCase.verifyEqual(yamada.model.ActiveGridResolver.resolve( ...
                document, document.RootComponentId), "");
        end

        % Guarantee: the dirty flag is clear only at an exact saved checkpoint.
        % Failure mode: the editor reports a clean document after a branch replaced the saved state, and changes are lost on close.
        function newAndParsedDocumentsHaveExpectedDirtyStates(testCase)
            % newAndParsedDocumentsHaveExpectedDirtyStates Start factory and parsed models clean.

            registry = yamada.model.ComponentRegistry.createDefault();
            newDocument = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            fixturePath = fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
                "fixtures", "SimpleCalculatorApp.m");
            parsedDocument = yamada.source.AppSourceParser.parseFile(fixturePath, registry);

            testCase.verifyFalse(newDocument.IsDirty);
            testCase.verifyFalse(parsedDocument.IsDirty);
        end

        function savedCheckpointControlsUndoAndRedoDirtyState(testCase)
            % savedCheckpointControlsUndoAndRedoDirtyState Retain only one exact clean history point.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            label = document.insertComponent(registry, "uilabel", document.RootComponentId);
            document.markSaved();
            document.setProperty(label.Id, "Text", "Ready");
            testCase.verifyTrue(document.IsDirty);
            document.undo();
            testCase.verifyFalse(document.IsDirty);
            document.undo();
            testCase.verifyTrue(document.IsDirty);
            document.redo();
            testCase.verifyTrue(document.IsDirty);
        end

        function branchReplacementAndHistoryTrimmingRemainConservativelyDirty(testCase)
            % branchReplacementAndHistoryTrimmingRemainConservativelyDirty Preserve only certain checkpoints.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExampleApp", registry);
            document.HistoryLimit = 2;
            label = document.insertComponent(registry, "uilabel", document.RootComponentId);
            document.markSaved();
            document.setProperty(label.Id, "Text", "First");
            document.undo();
            testCase.verifyFalse(document.IsDirty);
            document.setProperty(label.Id, "Text", "Replacement");
            document.undo();
            testCase.verifyTrue(document.IsDirty);

            trimmed = yamada.model.NewAppFactory.createEmpty("TrimmedApp", registry);
            trimmed.HistoryLimit = 2;
            trimmedLabel = trimmed.insertComponent(registry, "uilabel", ...
                trimmed.RootComponentId);
            trimmed.markSaved();
            trimmed.setProperty(trimmedLabel.Id, "Text", "Second");
            trimmed.setProperty(trimmedLabel.Id, "Text", "Third");
            trimmed.undo();
            trimmed.undo();
            testCase.verifyFalse(trimmed.IsDirty);
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

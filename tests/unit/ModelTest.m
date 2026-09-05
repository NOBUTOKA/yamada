classdef ModelTest < matlab.unittest.TestCase
    % ModelTest Verify the shared intermediate model and registry contracts.
    %   This test class covers model editing, generic property paths, registry
    %   extensibility, and conservative storage of source expressions. It does not
    %   exercise MATLAB source parsing or live UI components.

    methods (Test)
        function emptyModelHasEditableRoot(testCase)
            % emptyModelHasEditableRoot Verify the initial shared model contract.

            % Build and inspect the root created through the default registry.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ExampleApp", registry);

            testCase.verifyEqual(numel(document.Components), 1);
            if ispc
                testCase.verifyEqual(document.LineEnding, "CRLF");
            else
                testCase.verifyEqual(document.LineEnding, "LF");
            end
            testCase.verifyClass(document.Components, ...
                "macd.model.ComponentRecord");
            root = document.getComponent(document.RootComponentId);
            testCase.verifyEqual(root.Factory, "uifigure");
            testCase.verifyEqual(root.getProperty("Name").LiteralValue, "ExampleApp");
            testCase.verifyClass(root.Properties, "macd.model.PropertyEntry");
            testCase.verifyClass(root.Diagnostics, "macd.model.Diagnostic");

            % Confirm edits and validation use the same intermediate record.
            root.setProperty("Name", "Renamed App");
            testCase.verifyEqual(root.getProperty("Name").LiteralValue, "Renamed App");
            diagnostics = macd.validation.ModelValidator.validate(document, registry);
            testCase.verifyClass(diagnostics, "macd.model.Diagnostic");
            testCase.verifyClass(document.Diagnostics, "macd.model.Diagnostic");
            testCase.verifyFalse( ...
                macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function nestedPropertyPathsAreNotHardCodedInRecord(testCase)
            % nestedPropertyPathsAreNotHardCodedInRecord Verify generic paths.

            % Add a nested path without changing the component record class.
            component = macd.model.ComponentRecord( ...
                "label-1", "StatusLabel", "uilabel", ...
                "matlab.ui.control.Label", "parsed");
            entry = component.setProperty("Layout.Row", [1 2]);

            testCase.verifyEqual(entry.Path, "Layout.Row");
            testCase.verifyEqual(component.getProperty("Layout.Row").LiteralValue, [1 2]);
        end

        function defaultRegistryCoversR2024StandardComponents(testCase)
            % defaultRegistryCoversR2024StandardComponents Verify the R2024 catalog.

            % Keep the supported factory catalog explicit and reviewable.
            registry = macd.model.ComponentRegistry.createDefault();
            expected = ["axes", "geoaxes", "polaraxes", "uiaxes", "uibutton", ...
                "uibuttongroup", "uicheckbox", "uicolorpicker", "uicontextmenu", ...
                "uidatepicker", "uidropdown", "uieditfield", "uigauge", ...
                "uihtml", "uihyperlink", "uiimage", "uiknob", "uilabel", ...
                "uilamp", "uilistbox", "uimenu", "uipanel", "uipushtool", ...
                "uiradiobutton", "uislider", "uispinner", "uitable", "uitab", ...
                "uitabgroup", "uitextarea", "uitogglebutton", "uitoggletool", ...
                "uitoolbar", "uitree", "uitreenode", "uifigure", "uigridlayout", ...
                "uiswitch"];

            % Compare sorted names so registration order remains an implementation detail.
            testCase.verifyEqual(registry.listFactories(), sort(expected));
            testCase.verifyEqual(numel(registry.listFactories()), numel(expected));
            testCase.verifyEqual(registry.get("uicolorpicker").Metadata.Introduced, "R2024a");
            testCase.verifyEqual(registry.get("uislider").SupportedStyles, ...
                ["slider", "range"]);
            testCase.verifyTrue(registry.get("uitreenode").RequiresParentComponent);
            testCase.verifyTrue(any(registry.get("uigridlayout").AllowedParentFactories == ...
                "uigridlayout"));
            testCase.verifyEqual(registry.get("uibutton").DisplayName, "Button");
            testCase.verifyEqual(registry.displayName("uibutton"), "Button");
            testCase.verifyEqual(registry.displayName("uigridlayout"), "Grid Layout");
        end

        function registryAcceptsFutureComponentDefinitions(testCase)
            % registryAcceptsFutureComponentDefinitions Verify additive extension.

            % Define a component that is intentionally outside the initial list.
            registry = macd.model.ComponentRegistry.createDefault();
            propertyDefinition = macd.model.PropertyDefinition( ...
                "Multiselect", "off", true, true, struct());
            definition = macd.model.ComponentDefinition.fromPaths( ...
                "uitree", "matlab.ui.container.Tree", ...
                ["uifigure", "uipanel", "uigridlayout"], false, {}, ...
                propertyDefinition, struct("Category", "Navigation"));

            % Register and retrieve component-specific extension metadata.
            registry.register(definition);

            testCase.verifyTrue(registry.contains("uitree"));
            stored = registry.get("uitree");
            testCase.verifyClass(stored, "macd.model.ComponentDefinition");
            testCase.verifyClass(stored.Properties, ...
                "macd.model.PropertyDefinition");
            testCase.verifyEqual(stored.Properties.Path, "Multiselect");
            testCase.verifyEqual(stored.Category, "Navigation");

            % Confirm the shared model and validator require no code changes.
            document = macd.model.NewAppFactory.createEmpty("TreeApp", registry);
            tree = macd.model.ComponentRecord("tree-1", "NavigationTree", ...
                stored.Factory, stored.DeclaredType, "generated");
            tree.setProperty("Multiselect", "on");
            document.addComponent(tree, document.RootComponentId);
            diagnostics = macd.validation.ModelValidator.validate(document, registry);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function sourceExpressionCanRemainReadOnly(testCase)
            % sourceExpressionCanRemainReadOnly Verify conservative parse storage.

            % Retain a complex expression without evaluating or coercing it.
            entry = macd.model.PropertyEntry("Items", []);
            entry.setSourceExpression("loadItems(app)");

            testCase.verifyEqual(entry.ValueKind, "expression");
            testCase.verifyFalse(entry.IsEditable);
            testCase.verifyEqual(entry.SourceExpression, "loadItems(app)");
        end

        function registryInsertionSeedsSafeGeometry(testCase)
            % registryInsertionSeedsSafeGeometry Verify model-owned palette insertion.

            % Insert two controls through the same registry used by the editor.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ExampleApp", registry);
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
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("VariantApp", registry);
            variant = registry.getById("uibutton-state");
            component = document.insertComponent(registry, variant.Factory, ...
                document.RootComponentId, variant.CreationArguments);
            testCase.verifyEqual(component.CreationArguments, variant.CreationArguments);
            testCase.verifyEqual(component.DeclaredType, "matlab.ui.control.StateButton");
        end

        function gridInsertionSeedsLayoutCoordinates(testCase)
            % gridInsertionSeedsLayoutCoordinates Verify grid insertion defaults.

            % Build a grid parent and insert a label beneath it.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("GridApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", ...
                document.RootComponentId);
            label = document.insertComponent(registry, "uilabel", grid.Id);

            testCase.verifyEqual(label.getProperty("Layout.Row").LiteralValue, 1);
            testCase.verifyEqual(label.getProperty("Layout.Column").LiteralValue, 1);
            testCase.verifyError(@() document.insertComponent( ...
                registry, "uilabel", label.Id), ...
                "macd:DocumentModel:InvalidInsertionParent");
        end

        function propertyEditsUndoAndRedo(testCase)
            % propertyEditsUndoAndRedo Verify reversible literal property changes.

            % Change one model value, then traverse both history directions.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ExampleApp", registry);
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

            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ExampleApp", registry);
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

            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ExampleApp", registry);
            label = document.insertComponent(registry, "uilabel", ...
                document.RootComponentId);
            changes = [struct("Path", "Text", "Value", "First"), ...
                struct("Path", "Text", "Value", "Second")];

            testCase.verifyError(@() document.setPropertyBatch(label.Id, changes), ...
                "macd:DocumentModel:InvalidPropertyBatch");
            testCase.verifyEmpty(label.getProperty("Text"));
        end

        function insertionUndoRemovesWithoutDeletionIntent(testCase)
            % insertionUndoRemovesWithoutDeletionIntent Verify generated undo semantics.

            % Undoing a new component must not create a source deletion request.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ExampleApp", registry);
            label = document.insertComponent(registry, "uilabel", ...
                document.RootComponentId);
            document.undo();
            testCase.verifyEmpty(document.getComponent(label.Id));
            testCase.verifyEmpty(document.PendingEdits);
            document.redo();
            testCase.verifyEqual(document.getComponent(label.Id).Name, "Label");
        end

        function parsedDeletionUndoRestoresPendingIntent(testCase)
            % parsedDeletionUndoRestoresPendingIntent Verify parsed deletion history.

            % Use a parsed fixture so deletion remains source-backed and reversible.
            testPath = mfilename("fullpath");
            fixturePath = string(fullfile(fileparts(fileparts(testPath)), ...
                "fixtures", "SimpleCalculatorApp.m"));
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseFile(fixturePath, registry);
            target = document.getComponentByName("LeftValueLabel");
            document.removeComponent(target.Id);
            testCase.verifyEmpty(document.getComponent(target.Id));
            testCase.verifyEqual(numel(document.PendingEdits), 1);
            document.undo();
            testCase.verifyEqual(document.getComponent(target.Id).Name, ...
                "LeftValueLabel");
            testCase.verifyEmpty(document.PendingEdits);
            document.redo();
            testCase.verifyEmpty(document.getComponent(target.Id));
            testCase.verifyEqual(numel(document.PendingEdits), 1);
        end

        function geometryValidationRejectsUnsafeLiterals(testCase)
            % geometryValidationRejectsUnsafeLiterals Verify canvas geometry checks.

            % Invalid Position and grid coordinates must block generation safely.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ExampleApp", registry);
            label = document.insertComponent(registry, "uilabel", ...
                document.RootComponentId);
            label.setProperty("Position", [10 10 0 30]);
            grid = document.insertComponent(registry, "uigridlayout", ...
                document.RootComponentId);
            gridLabel = document.insertComponent(registry, "uilabel", grid.Id);
            gridLabel.setProperty("Layout.Row", [0 2]);
            diagnostics = macd.validation.ModelValidator.validate(document, registry);

            testCase.verifyTrue(any([diagnostics.Code] == "invalid-position"));
            testCase.verifyTrue(any([diagnostics.Code] == "invalid-grid-coordinate"));
            testCase.verifyTrue(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function geometryValidationAcceptsGridSpans(testCase)
            % geometryValidationAcceptsGridSpans Accept positive integer grid ranges.

            % Grid row and column values may span two adjacent tracks.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ExampleApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", ...
                document.RootComponentId);
            label = document.insertComponent(registry, "uilabel", grid.Id);
            label.setProperty("Layout.Row", [1 2]);
            label.setProperty("Layout.Column", [1 2]);
            diagnostics = macd.validation.ModelValidator.validate(document, registry);

            % The context schema and geometry check must agree on valid spans.
            diagnosticCodes = string({diagnostics.Code});
            testCase.verifyFalse(any(diagnosticCodes == "invalid-catalog-property"));
            testCase.verifyFalse(any(diagnosticCodes == "invalid-grid-coordinate"));
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function modelValidationUsesTheInspectorPropertySchema(testCase)
            % modelValidationUsesTheInspectorPropertySchema Reject catalog-invalid values outside the Inspector.

            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ExampleApp", registry);
            picker = document.insertComponent(registry, "uidatepicker", ...
                document.RootComponentId);
            picker.setProperty("Limits", [datetime(2024, 12, 31) datetime(2024, 1, 1)]);

            diagnostics = macd.validation.ModelValidator.validate(document, registry);

            invalid = diagnostics([diagnostics.Code] == "invalid-catalog-property");
            testCase.verifyNotEmpty(invalid);
            testCase.verifyEqual(invalid(1).Message, ...
                "The end date must be later than the start date.");
        end

        function effectivePropertiesFollowDirectParentContext(testCase)
            % effectivePropertiesFollowDirectParentContext Verify geometry follows the direct parent.

            % Compare the resolved surface without exposing registry implementation state.
            registry = macd.model.ComponentRegistry.createDefault();
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
        function propertyDefinitionExposesTypedBehavior(testCase)
            % propertyDefinitionExposesTypedBehavior Project validated metadata into typed fields.

            % Keep adapter selection independent of metadata field access by consumers.
            metadata = struct("editor", "logical", "validator", "logical", ...
                "previewPolicy", "skip", "resetPolicy", "retain", ...
                "displayName", "Shown", "category", "Appearance", "order", 20, ...
                "valueSchema", struct("values", {{"on", "off"}}), ...
                "applicableStyles", ["push", "state"], ...
                "auditDisposition", "readOnly");
            definition = macd.model.PropertyDefinition("Visible", [], false, true, metadata);
            testCase.verifyEqual(definition.Editor, "logical");
            testCase.verifyEqual(definition.Validator, "logical");
            testCase.verifyEqual(definition.PreviewPolicy, "skip");
            testCase.verifyEqual(definition.ResetPolicy, "retain");
            testCase.verifyEqual(definition.DisplayName, "Shown");
            testCase.verifyEqual(definition.Category, "Appearance");
            testCase.verifyEqual(definition.Order, 20);
            testCase.verifyEqual(definition.ValueSchema.values, {"on", "off"});
            testCase.verifyEqual(definition.ApplicableStyles, ["push", "state"]);
            testCase.verifyEqual(definition.AuditDisposition, "readOnly");
        end
        function propertyStatesKeepDefaultsImplicit(testCase)
            % propertyStatesKeepDefaultsImplicit Join definitions without creating entries.

            % A catalog capability remains absent until the document explicitly assigns it.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ExampleApp", registry);
            label = document.insertComponent(registry, "uilabel", document.RootComponentId);
            states = document.getEffectivePropertyStates(registry, label.Id);
            paths = arrayfun(@(state) state.Definition.Path, states);
            textIndex = find(paths == "Text", 1);
            testCase.verifyFalse(states(textIndex).IsExplicit);
            testCase.verifyEmpty(states(textIndex).Entry);
            testCase.verifyEmpty(label.getProperty("Text"));
        end

        function generatedPropertyResetIsUndoable(testCase)
            % generatedPropertyResetIsUndoable Remove and restore one generated literal.

            % Reset stores absence rather than the catalog default and keeps redo reversible.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ExampleApp", registry);
            label = document.insertComponent(registry, "uilabel", document.RootComponentId);
            document.setProperty(label.Id, "Text", "Ready");
            document.resetProperty(label.Id, "Text");
            testCase.verifyEmpty(label.getProperty("Text"));
            document.undo();
            testCase.verifyEqual(label.getProperty("Text").LiteralValue, "Ready");
            document.redo();
            testCase.verifyEmpty(label.getProperty("Text"));
            document.setProperty(label.Id, "Text", "New branch");
            testCase.verifyFalse(document.canRedo());
        end

        function parsedPropertyResetIsRejected(testCase)
            % parsedPropertyResetIsRejected Keep parsed assignments until owned deletion exists.

            % Source preservation takes precedence over removing a parsed literal.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseFile(fullfile( ...
                fileparts(fileparts(mfilename("fullpath"))), "fixtures", "SimpleCalculatorApp.m"), registry);
            label = document.getComponentByName("LeftValueLabel");
            testCase.verifyError(@() document.resetProperty(label.Id, "Text"), ...
                "macd:DocumentModel:ParsedPropertyResetUnsupported");
        end
        function publicPropertiesProvideMetadataHelp(testCase)
            % publicPropertiesProvideMetadataHelp Verify documented public state.

            % Inspect every public model class through MATLAB property metadata.
            classNames = ["macd.model.ComponentRecord", ...
                "macd.model.ComponentDefinition", "macd.model.Diagnostic", ...
                "macd.model.DocumentModel", "macd.model.ParentContextRule", ...
                "macd.model.PropertyDefinition", ...
                "macd.model.PropertyEntry", "macd.model.SourceSpan"];
            for className = classNames
                classMetadata = meta.class.fromName(char(className));
                propertyMetadata = classMetadata.PropertyList;
                if iscell(propertyMetadata)
                    propertyMetadata = [propertyMetadata{:}];
                end
                for property = propertyMetadata(:)'
                    if strcmp(property.GetAccess, "public")
                        testCase.verifyNotEmpty(property.Description, ...
                            className + "." + string(property.Name));
                    end
                end
            end

            % Confirm internal registry storage remains inaccessible to callers.
            registryMetadata = ?macd.model.ComponentRegistry;
            definitions = findobj(registryMetadata.PropertyList, ...
                "Name", "Definitions");
            testCase.verifyEqual(string(definitions.GetAccess), "private");

            % Keep externally readable invariants writable only by their owners.
            readOnlyProperties = { ...
                ?macd.model.ComponentRecord, "Id"; ...
                ?macd.model.ComponentDefinition, "Factory"; ...
                ?macd.model.Diagnostic, "Code"; ...
                ?macd.model.PropertyDefinition, "Path"; ...
                ?macd.model.PropertyEntry, "ValueKind"; ...
                ?macd.model.SourceSpan, "StartOffset"};
            for index = 1:size(readOnlyProperties, 1)
                classMetadata = readOnlyProperties{index, 1};
                propertyName = readOnlyProperties{index, 2};
                property = findobj(classMetadata.PropertyList, ...
                    "Name", propertyName);
                testCase.verifyEqual(string(property.GetAccess), "public");
                testCase.verifyEqual(string(property.SetAccess), "private");
            end
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

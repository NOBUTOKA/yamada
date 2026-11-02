classdef (TestTags = {'preview', 'ui'}) PreviewSynchronizationTest < matlab.unittest.TestCase
    % PreviewSynchronizationTest Verify capability-wide updates and coupled native transitions.
    %   Every registered variant participates; specific cases exercise policies
    %   with state transitions that cannot be represented by one plain setter.
    methods (Test)
        function immediateValuesKeepNativeHandlesAndRejectUnrelatedChanges(testCase)
            % immediateValuesKeepNativeHandlesAndRejectUnrelatedChanges Apply source additions and replacements through native diffs.
            registry = macd.model.ComponentRegistry.createDefault();
            root = fileparts(fileparts(mfilename("fullpath")));
            source = string(fileread(fullfile(root, "fixtures", "handle", "SmallPreviewFixtureApp.m")));
            document = macd.source.AppSourceParser.parseText(source, registry);
            owner = document.getComponentByName("TopLeftLabel");
            figure = uifigure(Visible="off"); cleanup = onCleanup(@() delete(figure));
            renderer = macd.ui.PreviewRenderer(registry);
            handles = renderer.render(document, figure);
            for path = ["Text", "FontSize"]
                value = "Longer changed text";
                if path == "FontSize", value = 23; end
                document.setProperty(owner.Id, path, value, registry);
                [applied, diagnostics] = renderer.synchronize(document, handles, ...
                    macd.ui.RefreshRequest("properties", owner.Id, path));
                testCase.verifyTrue(applied, renderer.statistics().fallbackReason);
                testCase.verifyEmpty(diagnostics);
                current = handles(char(owner.Id));
                if path == "Text"
                    testCase.verifyEqual(string(current.Text), value);
                else
                    testCase.verifyEqual(current.FontSize, value);
                end
            end
            document.setProperty(owner.Id, "Text", "Another change", registry);
            owner.Metadata.UnrelatedInput = true;
            applied = renderer.synchronize(document, handles, ...
                macd.ui.RefreshRequest("properties", owner.Id, "Text"));
            testCase.verifyFalse(applied);
        end

        function appliesIndependentPropertiesAcrossAllCatalogVariants(testCase)
            % appliesIndependentPropertiesAcrossAllCatalogVariants Reuse native handles across every eligible variant.
            registry = macd.model.ComponentRegistry.createDefault();
            variants = registry.listVariantIds();
            changes = 0;
            for variant = reshape(variants, 1, [])
                definition = registry.getById(variant);
                document = macd.model.NewAppFactory.createEmpty("CatalogPreviewFixture", registry);
                if definition.IsRoot
                    component = document.getComponent(document.RootComponentId);
                else
                    parentId = fixtureParent(document, registry, definition);
                    component = fixtureComponent(document, definition, parentId, "Subject");
                end
                figure = uifigure(Visible="off");
                cleanup = onCleanup(@() delete(figure));
                renderer = macd.ui.PreviewRenderer(registry);
                [handles, initialDiagnostics] = renderer.render(document, figure);
                original = [];
                if isKey(handles, char(component.Id)), original = handles(char(component.Id)); end
                if isempty(original) && ~definition.IsRoot && ~isempty(initialDiagnostics)
                    fprintf("CATALOG_NATIVE_DIAGNOSTIC %s: %s\n", variant, strjoin(string({initialDiagnostics.Message}), "; "));
                end
                exercised = 0;
                touched = strings(1, 0);
                for property = reshape(definition.Properties, 1, [])
                    if ~property.IsEditable || ~any(property.Application.EffectStatus == ["independent", "modeled"]), continue, end
                    if any(property.PreviewPolicy == ["skip", "notRendered"])
                        if exercised > 0, continue, end
                        value = "Preview metadata";
                    else
                        [valid, value] = propertyMutation(property, original, component.Id == document.RootComponentId);
                        if ~valid, continue, end
                    end
                    component.setProperty(property.Path, value);
                    [applied, diagnostics] = renderer.synchronize(document, handles, ...
                        macd.ui.RefreshRequest("properties", component.Id, property.Path));
                    testCase.verifyTrue(applied, variant + "." + property.Path + ": " + renderer.statistics().fallbackReason);
                    testCase.verifyEmpty(diagnostics, variant + "." + property.Path);
                    if isKey(handles, char(component.Id)), original = handles(char(component.Id)); end
                    touched(end + 1) = property.Path; %#ok<AGROW>
                    exercised = exercised + 1;
                    changes = changes + 1;
                end
                testCase.verifyGreaterThan(exercised, 0, variant);
                if ~isempty(original)
                    referenceFigure = uifigure(Visible="off");
                    referenceCleanup = onCleanup(@() delete(referenceFigure));
                    reference = macd.ui.PreviewRenderer(registry).render(document, referenceFigure);
                    drawnow;
                    for path = unique(touched)
                        testCase.verifyEqual(handles(char(component.Id)).(path), reference(char(component.Id)).(path), ...
                            variant + "." + path);
                    end
                    clear referenceCleanup
                end
                clear cleanup
            end
            fprintf("CATALOG_DELTA_COVERAGE Variants=%d Changes=%d\n", numel(variants), changes);
        end

        function movesDisjointRangesAndItemsAsResolvedBatches(testCase)
            % movesDisjointRangesAndItemsAsResolvedBatches Preserve final values through otherwise invalid intermediate states.
            registry = macd.model.ComponentRegistry.createDefault();
            for kind = ["numeric", "slider", "dropdown", "text"]
                document = macd.model.NewAppFactory.createEmpty("CoupledPreviewFixture", registry);
                if kind == "slider"
                    factory = "uislider"; args = {};
                elseif kind == "dropdown"
                    factory = "uidropdown"; args = {};
                else
                    factory = "uieditfield"; args = {char(kind)};
                end
                definition = registry.get(factory, args);
                component = fixtureComponent(document, definition, document.RootComponentId, "Subject");
                if kind == "dropdown"
                    component.setProperty("Items", ["Old A", "Old B"]);
                    component.setProperty("ItemsData", [1 2]);
                    component.setProperty("Value", 1);
                elseif kind == "text"
                    component.setProperty("CharacterLimits", [1 4]); component.setProperty("Value", "old");
                else
                    component.setProperty("Limits", [0 5]); component.setProperty("Value", 2);
                end
                figure = uifigure(Visible="off"); cleanup = onCleanup(@() delete(figure));
                renderer = macd.ui.PreviewRenderer(registry);
                handles = renderer.render(document, figure);
                if kind == "dropdown"
                    paths = ["Items", "ItemsData", "Value"];
                    values = {["New A", "New B", "New C"], [7 8 9], 8};
                elseif kind == "text"
                    paths = ["CharacterLimits", "Value"]; values = {[6 10], "new text"};
                else
                    paths = ["Limits", "Value"]; values = {[7 10], 8};
                end
                for index = 1:numel(paths), component.setProperty(paths(index), values{index}); end
                [applied, diagnostics] = renderer.synchronize(document, handles, ...
                    macd.ui.RefreshRequest("properties", component.Id, paths));
                testCase.verifyTrue(applied, kind + ": " + renderer.statistics().fallbackReason); testCase.verifyEmpty(diagnostics, kind);
                original = handles(char(component.Id));
                if kind == "text"
                    testCase.verifyEqual(string(original.Value), string(values{end}), kind);
                else
                    testCase.verifyEqual(original.Value, values{end}, kind);
                end
                clear cleanup
            end
        end

        function keepsHeterogeneousBatchOwnershipExact(testCase)
            % keepsHeterogeneousBatchOwnershipExact Synchronize different paths without masking unrelated writes.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("BatchPreviewFixture", registry);
            first = fixtureComponent(document, registry.get("uilabel"), document.RootComponentId, "First");
            second = fixtureComponent(document, registry.get("uilabel"), document.RootComponentId, "Second");
            figure = uifigure(Visible="off"); cleanup = onCleanup(@() delete(figure));
            renderer = macd.ui.PreviewRenderer(registry); handles = renderer.render(document, figure);
            first.setProperty("FontColor", [0.2 0.3 0.4]); second.setProperty("Text", "Batch update");
            changes = [struct("ComponentId", first.Id, "Path", "FontColor"), ...
                struct("ComponentId", second.Id, "Path", "Text")];
            [applied, diagnostics, geometry] = renderer.synchronize(document, handles, macd.ui.RefreshRequest.forChanges(changes));
            testCase.verifyTrue(applied); testCase.verifyEmpty(diagnostics); testCase.verifyFalse(geometry);
            testCase.verifyEqual(string(handles(char(second.Id)).Text), "Batch update");
            first.setProperty("FontColor", [0.4 0.3 0.2]); second.setProperty("Text", "Next batch");
            second.setProperty("FontColor", [0.1 0.1 0.1]);
            testCase.verifyFalse(renderer.synchronize(document, handles, macd.ui.RefreshRequest.forChanges(changes)));
            clear cleanup
        end

        function reconstructsUncertainScopesWithoutReplacingUnrelatedControls(testCase)
            % reconstructsUncertainScopesWithoutReplacingUnrelatedControls Keep reconstruction bounded by ownership.
            registry = macd.model.ComponentRegistry.createDefault();
            definition = registry.get("uilabel"); properties = definition.Properties;
            index = find(string({properties.Path}) == "FontSize", 1);
            metadata = properties(index).Metadata; metadata.application.effectStatus = "unknown";
            properties(index) = macd.model.PropertyDefinition("FontSize", [], false, true, metadata);
            registry.register(macd.model.ComponentDefinition("uilabel", definition.DeclaredType, ...
                definition.AllowedParentFactories, false, {}, properties));
            document = macd.model.NewAppFactory.createEmpty("LocalRepairFixture", registry);
            label = fixtureComponent(document, registry.get("uilabel"), document.RootComponentId, "Subject");
            sibling = fixtureComponent(document, registry.get("uibutton"), document.RootComponentId, "Sibling");
            figure = uifigure(Visible="off"); cleanup = onCleanup(@() delete(figure));
            renderer = macd.ui.PreviewRenderer(registry); handles = renderer.render(document, figure);
            label.setProperty("FontSize", 24);
            [applied, diagnostics] = renderer.synchronize(document, handles, macd.ui.RefreshRequest("properties", label.Id, "FontSize"));
            testCase.verifyTrue(applied); testCase.verifyEmpty(diagnostics);
            testCase.verifyEqual(handles(char(label.Id)).FontSize, 24);
            currentSibling = handles(char(sibling.Id));
            testCase.verifyEqual(currentSibling.Parent.Children(1), currentSibling);
            clear cleanup
        end

        function adaptsAssetsAndClearsExistingNativeContent(testCase)
            % adaptsAssetsAndClearsExistingNativeContent Share catalog adaptation between full and incremental rendering.
            registry = macd.model.ComponentRegistry.createDefault();
            temporary = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            imwrite(uint8(ones(8, 8, 3) * 120), fullfile(temporary.Folder, "first.png"));
            imwrite(uint8(ones(4, 16, 3) * 200), fullfile(temporary.Folder, "second.png"));
            document = macd.model.NewAppFactory.createEmpty("AssetPreviewFixture", registry);
            document.FilePath = fullfile(temporary.Folder, "AssetPreviewFixture.m");
            image = fixtureComponent(document, registry.get("uiimage"), document.RootComponentId, "Subject");
            image.setProperty("ImageSource", "first.png");
            figure = uifigure(Visible="off"); cleanup = onCleanup(@() delete(figure));
            renderer = macd.ui.PreviewRenderer(registry); handles = renderer.render(document, figure);
            for value = ["second.png", ""]
                image.setProperty("ImageSource", value);
                [applied, diagnostics] = renderer.synchronize(document, handles, macd.ui.RefreshRequest("properties", image.Id, "ImageSource"));
                testCase.verifyTrue(applied); testCase.verifyEmpty(diagnostics);
                original = handles(char(image.Id));
                if strlength(value) > 0
                    testCase.verifyEqual(string(original.ImageSource), string(fullfile(temporary.Folder, value)));
                else
                    testCase.verifyTrue(isempty(original.ImageSource) || strlength(string(original.ImageSource)) == 0);
                end
            end
            clear cleanup
        end

        function restoresChildGeometryAfterParentReflow(testCase)
            % restoresChildGeometryAfterParentReflow Match fresh construction rather than compound prior native resizing.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ContainerReflowFixture", registry);
            panel = fixtureComponent(document, registry.get("uipanel"), document.RootComponentId, "Panel");
            panel.setProperty("Position", [10 10 300 200]); panel.setProperty("AutoResizeChildren", "on");
            label = fixtureComponent(document, registry.get("uilabel"), panel.Id, "Subject");
            label.setProperty("Position", [10 20 100 22]);
            figure = uifigure(Visible="off"); cleanup = onCleanup(@() delete(figure));
            renderer = macd.ui.PreviewRenderer(registry); handles = renderer.render(document, figure);
            panel.setProperty("Position", [20 20 500 300]);
            [applied, diagnostics] = renderer.synchronize(document, handles, macd.ui.RefreshRequest("properties", panel.Id, "Position"));
            testCase.verifyTrue(applied); testCase.verifyEmpty(diagnostics);
            original = handles(char(label.Id));
            drawnow; pause(0.15); drawnow;
            testCase.verifyEqual(original.Position, [10 20 100 22]);
            clear cleanup
        end

        function updatesGridPlacementSelectionAndRootSurface(testCase)
            % updatesGridPlacementSelectionAndRootSurface Keep grid and group native identities during coupled edits.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("LayoutPreviewFixture", registry);
            root = document.getComponent(document.RootComponentId);
            grid = fixtureComponent(document, registry.get("uigridlayout"), root.Id, "Grid");
            grid.setProperty("RowHeight", {100, 100}); grid.setProperty("ColumnWidth", {'1x'});
            label = fixtureComponent(document, registry.get("uilabel"), grid.Id, "Label");
            label.setProperty("Layout.Row", 1); label.setProperty("Layout.Column", 1);
            group = fixtureComponent(document, registry.get("uibuttongroup"), root.Id, "Group");
            first = fixtureComponent(document, registry.get("uiradiobutton"), group.Id, "First");
            second = fixtureComponent(document, registry.get("uiradiobutton"), group.Id, "Second");
            first.setProperty("Value", true); second.setProperty("Value", false);
            figure = uifigure(Visible="off"); cleanup = onCleanup(@() delete(figure));
            renderer = macd.ui.PreviewRenderer(registry); [handles, ~, canvas] = renderer.render(document, figure);
            original = handles(char(grid.Id));
            grid.setProperty("RowHeight", {150, 80});
            testCase.verifyTrue(renderer.synchronize(document, handles, macd.ui.RefreshRequest("properties", grid.Id, "RowHeight")));
            testCase.verifyEqual(handles(char(grid.Id)), original);
            label.setProperty("Layout.Row", 2);
            testCase.verifyTrue(renderer.synchronize(document, handles, macd.ui.RefreshRequest("properties", label.Id, "Layout.Row")));
            testCase.verifyEqual(handles(char(label.Id)).Layout.Row, 2);
            second.setProperty("Value", true);
            testCase.verifyTrue(renderer.synchronize(document, handles, macd.ui.RefreshRequest("properties", second.Id, "Value")));
            testCase.verifyEqual(handles(char(group.Id)).SelectedObject, handles(char(second.Id)));
            testCase.verifyFalse(logical(handles(char(first.Id)).Value));
            root.setProperty("Position", [100 100 720 480]);
            testCase.verifyTrue(renderer.synchronize(document, handles, macd.ui.RefreshRequest("properties", root.Id, "Position")));
            testCase.verifyEqual(canvas.Position(3:4), [720 480]);
            testCase.verifyEqual(handles(char(grid.Id)), original);
            clear cleanup
        end
    end
end

function component = fixtureComponent(document, definition, parentId, name)
% fixtureComponent Add one catalog record without broadening the product insertion UI.
arguments (Input)
    document (1, 1) macd.model.DocumentModel
    definition (1, 1) macd.model.ComponentDefinition
    parentId (1, 1) string
    name (1, 1) string
end
arguments (Output)
    component (1, 1) macd.model.ComponentRecord
end
component = macd.model.ComponentRecord("test-" + name, name, definition.Factory, definition.DeclaredType, "generated");
component.CreationArguments = definition.CreationArguments;
document.addComponent(component, parentId);
end

function id = fixtureParent(document, registry, definition)
% fixtureParent Recursively construct the minimal catalog-allowed native parent hierarchy.
arguments (Input)
    document (1, 1) macd.model.DocumentModel
    registry (1, 1) macd.model.ComponentRegistry
    definition (1, 1) macd.model.ComponentDefinition
end
arguments (Output)
    id (1, 1) string
end
if any(definition.AllowedParentFactories == "uifigure"), id = document.RootComponentId; return, end
parent = registry.get(definition.AllowedParentFactories(1));
parentId = fixtureParent(document, registry, parent);
record = fixtureComponent(document, parent, parentId, "Parent" + numel(document.Components));
id = record.Id;
end

function [valid, value] = propertyMutation(property, native, root)
% propertyMutation Generate inert independent mutations from catalog value contracts.
arguments (Input)
    property (1, 1) macd.model.PropertyDefinition
    native
    root (1, 1) logical
end
arguments (Output)
    valid (1, 1) logical
    value
end
valid = false; value = [];
if ~root && (isempty(native) || contains(property.Path, ".") || ~isprop(native, property.Path)), return, end
schema = property.ValueSchema;
if ~isfield(schema, "kind"), return, end
kind = string(schema.kind);
initial = [];
if ~isempty(native)
    initial = native.(property.Path);
    if isa(initial, "handle") || isa(initial, "function_handle"), return, end
end
if kind == "color"
    value = [0.15 0.35 0.55];
elseif kind == "text" || kind == "multilineText"
    value = initial;
    if root, value = "Updated preview"; end
elseif kind == "onOff"
    value = "off";
    if property.Application.EffectStatus == "modeled"
        value = initial;
    elseif ~isempty(initial) && string(initial) == "off"
        value = "on";
    end
elseif kind == "logical"
    value = initial;
elseif kind == "enum" && isfield(schema, "values") && ~isempty(schema.values)
    value = string(schema.values(end));
elseif kind == "numericArray" && isnumeric(initial) && ~isempty(initial) && numel(initial) <= 4 && all(isfinite(initial), "all")
    value = initial;
elseif kind == "number" && ~isempty(native)
    initial = native.(property.Path);
    if ~isnumeric(initial) || ~isscalar(initial) || ~isfinite(initial) || initial <= 0, return, end
    value = initial * 0.9;
    if isfield(schema, "integer") && schema.integer, value = initial; end
else
    return
end
valid = true;
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

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

        function registryAcceptsFutureComponentDefinitions(testCase)
            % registryAcceptsFutureComponentDefinitions Verify additive extension.

            % Define a component that is intentionally outside the initial list.
            registry = macd.model.ComponentRegistry.createDefault();
            propertyDefinition = macd.model.PropertyDefinition( ...
                "Multiselect", "off", true, true, struct());
            definition = macd.model.ComponentDefinition( ...
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
            testCase.verifyEqual(stored.Metadata.Category, "Navigation");

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

        function publicPropertiesProvideMetadataHelp(testCase)
            % publicPropertiesProvideMetadataHelp Verify documented public state.

            % Inspect every Phase 1 model class through MATLAB property metadata.
            classNames = ["macd.model.ComponentRecord", ...
                "macd.model.ComponentDefinition", "macd.model.Diagnostic", ...
                "macd.model.DocumentModel", "macd.model.PropertyDefinition", ...
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
MatlabAppClassDesigner - Tests for the extensible intermediate data model.
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
